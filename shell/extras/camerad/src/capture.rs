//! PipeWire side: a capture stream on the camera's node, created only while the
//! engine asks for frames, and a registry watch that tells who else is reading
//! the camera through PipeWire.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::mpsc::Sender;

use pipewire as pw;
use pw::spa;
use pw::spa::param::format::{FormatProperties, MediaSubtype, MediaType};
use pw::spa::pod::Pod;

use crate::engine::Msg;
use crate::users::User;

/// Commands for the PipeWire thread
pub enum Cmd {
    Start,
    Stop,
}

pub type Handle = pw::channel::Sender<Cmd>;

/// A running capture stream and its listener (dropped together)
type Capture = (pw::stream::StreamRc, pw::stream::StreamListener<()>);

#[derive(Default)]
struct Graph {
    // id -> props we care about
    nodes: HashMap<u32, NodeInfo>,
    // link id -> (output node, input node)
    links: HashMap<u32, (u32, u32)>,
}

#[derive(Clone, Default)]
struct NodeInfo {
    name: String,
    node_name: String,
    app: String,
    pid: Option<i32>,
    v4l2_path: Option<String>,
    is_video_source: bool,
}

impl Graph {
    fn camera_node(&self, device: &str) -> Option<(u32, String)> {
        self.nodes
            .iter()
            .find(|(_, n)| n.is_video_source && n.v4l2_path.as_deref() == Some(device))
            .map(|(id, n)| (*id, n.name.clone()))
    }

    /// Apps whose streams are linked to the camera's node
    fn readers(&self, device: &str) -> Vec<User> {
        let Some((cam, _)) = self.camera_node(device) else {
            return vec![];
        };
        let mut seen = std::collections::HashSet::new();
        self.links
            .values()
            .filter(|(out, _)| *out == cam)
            .filter_map(|(_, input)| self.nodes.get(input))
            .filter(|n| seen.insert((n.pid, n.app.clone())))
            .map(|n| User {
                pid: n.pid.unwrap_or(0),
                name: if n.app.is_empty() {
                    n.name.clone()
                } else {
                    n.app.clone()
                },
                via: "pipewire",
                own: n.node_name == "caelestia-camerad",
            })
            .collect()
    }
}

pub fn spawn(device: String, tx: Sender<Msg>) -> anyhow::Result<Handle> {
    let (cmd_tx, cmd_rx) = pw::channel::channel::<Cmd>();
    std::thread::Builder::new()
        .name("pipewire".into())
        .spawn(move || {
            if let Err(e) = run(device, tx.clone(), cmd_rx) {
                let _ = tx.send(Msg::CaptureError(format!("PipeWire: {e}")));
            }
        })?;
    Ok(cmd_tx)
}

fn run(device: String, tx: Sender<Msg>, cmd_rx: pw::channel::Receiver<Cmd>) -> anyhow::Result<()> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = context.connect_rc(None)?;
    let registry = core.get_registry_rc()?;

    let graph = Rc::new(RefCell::new(Graph::default()));
    let last_readers: Rc<RefCell<Vec<User>>> = Rc::new(RefCell::new(vec![]));

    let report = {
        let graph = graph.clone();
        let last = last_readers.clone();
        let tx = tx.clone();
        let device = device.clone();
        move || {
            let readers = graph.borrow().readers(&device);
            if *last.borrow() != readers {
                *last.borrow_mut() = readers.clone();
                let _ = tx.send(Msg::PipeWireUsers(readers));
            }
        }
    };
    let report = Rc::new(report);

    let _registry_listener = {
        let graph_add = graph.clone();
        let graph_rm = graph.clone();
        let report_add = report.clone();
        let report_rm = report.clone();
        registry
            .add_listener_local()
            .global(move |obj| {
                let Some(props) = obj.props else { return };
                let get = |k: &str| props.get(k).map(str::to_string);
                match obj.type_ {
                    pw::types::ObjectType::Node => {
                        let class = get("media.class").unwrap_or_default();
                        let info = NodeInfo {
                            name: get("node.description")
                                .or_else(|| get("node.name"))
                                .unwrap_or_default(),
                            node_name: get("node.name").unwrap_or_default(),
                            app: get("application.name")
                                .or_else(|| get("application.process.binary"))
                                .unwrap_or_default(),
                            pid: get("application.process.id").and_then(|p| p.parse().ok()),
                            v4l2_path: get("api.v4l2.path").or_else(|| {
                                get("object.path")
                                    .and_then(|p| p.strip_prefix("v4l2:").map(str::to_string))
                            }),
                            is_video_source: class == "Video/Source",
                        };
                        graph_add.borrow_mut().nodes.insert(obj.id, info);
                        report_add();
                    }
                    pw::types::ObjectType::Link => {
                        let out = get("link.output.node").and_then(|v| v.parse().ok());
                        let input = get("link.input.node").and_then(|v| v.parse().ok());
                        if let (Some(o), Some(i)) = (out, input) {
                            graph_add.borrow_mut().links.insert(obj.id, (o, i));
                            report_add();
                        }
                    }
                    _ => {}
                }
            })
            .global_remove(move |id| {
                let mut g = graph_rm.borrow_mut();
                let changed = g.nodes.remove(&id).is_some() | g.links.remove(&id).is_some();
                drop(g);
                if changed {
                    report_rm();
                }
            })
            .register()
    };

    // The capture stream, while one is wanted
    let stream: Rc<RefCell<Option<Capture>>> = Rc::new(RefCell::new(None));

    let _cmd_attach = {
        let stream = stream.clone();
        let core = core.clone();
        let graph = graph.clone();
        let tx = tx.clone();
        let device = device.clone();
        cmd_rx.attach(mainloop.loop_(), move |cmd| match cmd {
            Cmd::Start => {
                if stream.borrow().is_some() {
                    return;
                }
                let target = graph.borrow().camera_node(&device);
                let Some((_, target_name)) = target else {
                    let _ = tx.send(Msg::CaptureError(format!(
                        "no PipeWire camera for {device}"
                    )));
                    return;
                };
                match start_stream(&core, &target_name, &device, tx.clone()) {
                    Ok(s) => *stream.borrow_mut() = Some(s),
                    Err(e) => {
                        let _ = tx.send(Msg::CaptureError(format!("couldn't start capture: {e}")));
                    }
                }
            }
            Cmd::Stop => {
                if let Some((s, listener)) = stream.borrow_mut().take() {
                    let _ = s.disconnect();
                    drop(listener);
                }
            }
        })
    };

    mainloop.run();
    Ok(())
}

fn start_stream(
    core: &pw::core::CoreRc,
    target_name: &str,
    device: &str,
    tx: Sender<Msg>,
) -> anyhow::Result<Capture> {
    let _ = device;
    let stream = pw::stream::StreamRc::new(
        core.clone(),
        "caelestia-camerad",
        pw::properties::properties! {
            *pw::keys::MEDIA_TYPE => "Video",
            *pw::keys::MEDIA_CATEGORY => "Capture",
            *pw::keys::MEDIA_ROLE => "Camera",
            *pw::keys::APP_NAME => "Caelestia",
            *pw::keys::NODE_NAME => "caelestia-camerad",
            "target.object" => target_name,
        },
    )?;

    let err_tx = tx.clone();
    let listener = stream
        .add_local_listener_with_user_data(())
        .state_changed(move |_, _, old, new| {
            if std::env::var_os("CAMERAD_DEBUG").is_some() {
                eprintln!("camerad: stream {old:?} -> {new:?}");
            }
            if let pw::stream::StreamState::Error(e) = new {
                let _ = err_tx.send(Msg::CaptureError(format!("stream error: {e}")));
            }
        })
        .param_changed(|stream, _, id, param| {
            if std::env::var_os("CAMERAD_DEBUG").is_some() {
                eprintln!("camerad: param {id} set: {}", param.is_some());
            }
            // Once the format is agreed, say which buffer memory we can read:
            // the camera node hands over its V4L2 buffers as memfd or DMA-BUF
            if id == spa::param::ParamType::Format.as_raw()
                && param.is_some()
                && let Some(bytes) = buffers_param()
                && let Some(pod) = Pod::from_bytes(&bytes)
            {
                let _ = stream.update_params(&mut [pod]);
            }
        })
        .process(move |stream, _| {
            if let Some(mut buffer) = stream.dequeue_buffer() {
                let datas = buffer.datas_mut();
                if let Some(d) = datas.first_mut() {
                    let size = d.chunk().size() as usize;
                    let offset = d.chunk().offset() as usize;
                    if let Some(bytes) = d.data()
                        && size > 0
                        && offset + size <= bytes.len()
                    {
                        let _ = tx.send(Msg::Frame(bytes[offset..offset + size].to_vec()));
                    }
                }
            }
        })
        .register()?;

    // Ask for MJPEG: it's what the camera produces, and the engine decodes it at
    // a fraction of the size, which is far cheaper than any raw conversion
    let obj = spa::pod::object!(
        spa::utils::SpaTypes::ObjectParamFormat,
        spa::param::ParamType::EnumFormat,
        spa::pod::property!(FormatProperties::MediaType, Id, MediaType::Video),
        spa::pod::property!(FormatProperties::MediaSubtype, Id, MediaSubtype::Mjpg),
        spa::pod::property!(
            FormatProperties::VideoSize,
            Choice,
            Range,
            Rectangle,
            spa::utils::Rectangle {
                width: 1280,
                height: 720
            },
            spa::utils::Rectangle {
                width: 320,
                height: 180
            },
            spa::utils::Rectangle {
                width: 1920,
                height: 1080
            }
        ),
        spa::pod::property!(
            FormatProperties::VideoFramerate,
            Choice,
            Range,
            Fraction,
            spa::utils::Fraction { num: 30, denom: 1 },
            spa::utils::Fraction { num: 1, denom: 1 },
            spa::utils::Fraction { num: 60, denom: 1 }
        ),
    );
    let bytes: Vec<u8> = spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &spa::pod::Value::Object(obj),
    )?
    .0
    .into_inner();
    let mut params = [Pod::from_bytes(&bytes).ok_or_else(|| anyhow::anyhow!("bad format pod"))?];

    stream.connect(
        spa::utils::Direction::Input,
        None,
        pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS,
        &mut params,
    )?;
    Ok((stream, listener))
}

fn buffers_param() -> Option<Vec<u8>> {
    use spa::pod::{Object, Property, PropertyFlags, Value};
    let types = (1 << spa::sys::SPA_DATA_MemPtr)
        | (1 << spa::sys::SPA_DATA_MemFd)
        | (1 << spa::sys::SPA_DATA_DmaBuf);
    let obj = Object {
        type_: spa::sys::SPA_TYPE_OBJECT_ParamBuffers,
        id: spa::sys::SPA_PARAM_Buffers,
        properties: vec![Property {
            key: spa::sys::SPA_PARAM_BUFFERS_dataType,
            flags: PropertyFlags::empty(),
            value: Value::Int(types),
        }],
    };
    spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &Value::Object(obj),
    )
    .ok()
    .map(|(c, _)| c.into_inner())
}
