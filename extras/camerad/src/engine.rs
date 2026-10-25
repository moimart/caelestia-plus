//! The coordinator: requests from the shell, frames from PipeWire, and who's
//! using the camera. Capture runs only while a request or gestures need it,
//! and stops the moment another app opens the device directly.

use std::path::Path;
use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::time::{Duration, Instant};

use serde_json::{Value, json};

use crate::capture::{self, Cmd};
use crate::gestures::{self, Tracker};
use crate::users::User;
use crate::vision::{self, Models};
use crate::{Options, Out, controls};

pub enum Msg {
    Request(Value),
    BadRequest(String),
    Frame(Vec<u8>),
    PipeWireUsers(Vec<User>),
    DirectUsers(Vec<User>),
    /// Something opened the device node (possibly PipeWire, for our own stream)
    DeviceOpened,
    CaptureError(String),
    Quit,
}

enum Pending {
    Presence,
    Light,
    Snapshot(String),
}

/// Frames to let pass after starting, while the camera settles its exposure
const WARMUP: u32 = 12;
/// How often gestures look at a frame
const GESTURE_INTERVAL: Duration = Duration::from_millis(100);
/// How long the camera must be free again before gestures resume
const RESUME_AFTER: Duration = Duration::from_secs(3);
/// After another app opens the camera, how long to leave it alone (each
/// further open restarts the wait)
const STEP_ASIDE: Duration = Duration::from_secs(30);

struct State {
    out: Out,
    opts: Options,
    capture: capture::Handle,
    models: Models,
    tracker: Tracker,

    pw_users: Vec<User>,
    direct_users: Vec<User>,
    reported: Value,

    capturing: bool,
    started: Instant,
    frames: u32,
    pending: Vec<Pending>,

    gestures: bool,
    paused: bool,
    resume_at: Option<Instant>,
    last_gesture_frame: Instant,
    /// Kept free for another app until then
    aside_until: Option<Instant>,
    feedback: bool,
}

pub fn run(opts: Options, out: Out, rx: Receiver<Msg>, capture: capture::Handle) {
    let models = Models::new(&opts.models);
    let mut s = State {
        out,
        opts,
        capture,
        models,
        tracker: Tracker::new(),
        pw_users: vec![],
        direct_users: vec![],
        reported: Value::Null,
        capturing: false,
        started: Instant::now(),
        frames: 0,
        pending: vec![],
        gestures: false,
        paused: false,
        resume_at: None,
        last_gesture_frame: Instant::now(),
        aside_until: None,
        feedback: false,
    };
    s.out.emit(json!({
        "event": "ready",
        "device": s.opts.device,
        // A camera node exists, and presence/gestures can run (or why not)
        "camera": std::path::Path::new(&s.opts.device).exists(),
        "vision": s.models.available.is_ok(),
        "visionError": s.models.available.as_ref().err(),
    }));

    loop {
        let first = match rx.recv_timeout(Duration::from_millis(200)) {
            Ok(m) => Some(m),
            Err(RecvTimeoutError::Timeout) => None,
            Err(RecvTimeoutError::Disconnected) => break,
        };
        // Take everything waiting, keeping only the newest frame
        let mut latest = None;
        let mut quit = false;
        for msg in first
            .into_iter()
            .chain(std::iter::from_fn(|| rx.try_recv().ok()))
        {
            match msg {
                Msg::Frame(f) => latest = Some(f),
                Msg::Quit => quit = true,
                other => s.handle(other),
            }
        }
        if quit {
            s.stop_capture();
            break;
        }
        if let Some(frame) = latest {
            s.frame(&frame);
        }
        s.tick();
    }
}

impl State {
    fn handle(&mut self, msg: Msg) {
        match msg {
            Msg::Request(v) => self.request(&v),
            Msg::BadRequest(e) => self
                .out
                .emit(json!({ "event": "error", "message": format!("bad request: {e}") })),
            Msg::PipeWireUsers(u) => {
                self.pw_users = u;
                self.report_users();
            }
            Msg::DirectUsers(u) => {
                self.direct_users = u;
                self.report_users();
                self.yield_or_resume();
            }
            Msg::DeviceOpened => self.device_opened(),
            Msg::CaptureError(e) => {
                self.capturing = false;
                self.fail_pending(&e);
                self.out.emit(json!({ "event": "error", "message": e }));
            }
            Msg::Frame(_) | Msg::Quit => {}
        }
    }

    fn request(&mut self, v: &Value) {
        let cmd = v["cmd"].as_str().unwrap_or("");
        match cmd {
            "status" => self.status(),
            "presence" | "light" | "snapshot" => {
                let p =
                    match cmd {
                        "presence" => Pending::Presence,
                        "light" => Pending::Light,
                        _ => match v["path"].as_str() {
                            Some(path) => Pending::Snapshot(path.to_string()),
                            None => return self.out.emit(
                                json!({ "event": "snapshot", "ok": false, "reason": "no path" }),
                            ),
                        },
                    };
                if !std::path::Path::new(&self.opts.device).exists() {
                    return self.fail(&p, "no camera");
                }
                if let (Pending::Presence, Err(why)) = (&p, &self.models.available) {
                    let why = why.clone();
                    return self.fail(&p, &why);
                }
                if self.foreign() {
                    return self.fail(&p, "busy");
                }
                self.pending.push(p);
                self.start_capture();
            }
            "gestures" => {
                let mut on = v["on"].as_bool().unwrap_or(false);
                if on && let Err(why) = &self.models.available {
                    self.out
                        .emit(json!({ "event": "error", "message": format!("gestures: {why}") }));
                    on = false;
                }
                self.gestures = on;
                // The shell's gesture tutorial wants to see what the camera sees
                self.feedback = on && v["feedback"].as_bool().unwrap_or(false);
                self.tracker.reset();
                if on {
                    if self.foreign() {
                        self.paused = true;
                    } else {
                        self.start_capture();
                    }
                } else {
                    self.paused = false;
                    self.resume_at = None;
                    self.models.drop_hands();
                    if self.pending.is_empty() {
                        self.stop_capture();
                    }
                }
                self.status();
            }
            "controls" => match controls::list(&self.opts.device) {
                Ok(list) => self
                    .out
                    .emit(json!({ "event": "controls", "controls": list })),
                Err(e) => self
                    .out
                    .emit(json!({ "event": "error", "message": format!("controls: {e}") })),
            },
            "set" => {
                let name = v["name"].as_str().unwrap_or("");
                let r = controls::set(&self.opts.device, name, &v["value"]);
                self.out.emit(json!({ "event": "set", "name": name, "ok": r.is_ok(), "reason": r.err().map(|e| e.to_string()) }));
            }
            other => self
                .out
                .emit(json!({ "event": "error", "message": format!("unknown cmd {other:?}") })),
        }
    }

    /// Someone other than PipeWire has the device open directly
    fn foreign(&self) -> bool {
        !self.direct_users.is_empty() || self.aside_until.is_some_and(|t| Instant::now() < t)
    }

    /// Someone opened the device node. Apps that read the camera directly
    /// can't share it with a stream, so every such open means: let go now, and
    /// stay off until nobody has shown interest for a while. An app polling
    /// for cameras keeps gestures paused; other apps always come first.
    fn device_opened(&mut self) {
        // Our own stream starting makes PipeWire open the device: that's us
        if self.capturing && self.started.elapsed() < Duration::from_millis(1500) {
            return;
        }
        // One-off readings take under a second; only gestures hold the camera
        if !self.gestures && !self.capturing {
            return;
        }
        let now = Instant::now();
        let first = !self.aside_until.is_some_and(|t| now < t);
        self.aside_until = Some(now + STEP_ASIDE);
        if first {
            self.out
                .emit(json!({ "event": "stepped_aside", "seconds": STEP_ASIDE.as_secs() }));
        }
        self.yield_or_resume();
    }

    fn yield_or_resume(&mut self) {
        if self.foreign() {
            self.resume_at = None;
            if self.capturing {
                // Give it up at once: a direct user can't share the device
                self.stop_capture();
                self.fail_pending("busy");
            }
            if self.gestures && !self.paused {
                self.paused = true;
                self.status();
            }
        } else if self.gestures && self.paused {
            self.resume_at = Some(Instant::now() + RESUME_AFTER);
        }
    }

    fn tick(&mut self) {
        if self.aside_until.is_some_and(|t| Instant::now() >= t) {
            self.aside_until = None;
            if !self.foreign() && self.gestures && self.paused {
                // Nobody took the camera: carry on straight away
                self.paused = false;
                self.start_capture();
                self.status();
            }
        }
        if let Some(at) = self.resume_at
            && Instant::now() >= at
            && !self.foreign()
        {
            self.resume_at = None;
            self.paused = false;
            self.start_capture();
            self.status();
        }
        if self.capturing && self.frames == 0 && self.started.elapsed() > Duration::from_secs(6) {
            self.stop_capture();
            self.fail_pending("no frames from the camera");
            self.out
                .emit(json!({ "event": "error", "message": "no frames from the camera" }));
        }
    }

    fn start_capture(&mut self) {
        if self.capturing {
            return;
        }
        self.capturing = true;
        self.frames = 0;
        self.started = Instant::now();
        let _ = self.capture.send(Cmd::Start);
    }

    fn stop_capture(&mut self) {
        if !self.capturing {
            return;
        }
        self.capturing = false;
        let _ = self.capture.send(Cmd::Stop);
    }

    fn frame(&mut self, jpeg: &[u8]) {
        if !self.capturing {
            return;
        }
        self.frames += 1;
        if self.frames <= WARMUP {
            return;
        }

        if !self.pending.is_empty() {
            let pending = std::mem::take(&mut self.pending);
            let img = vision::decode(jpeg, 640);
            for p in pending {
                self.answer(p, jpeg, img.as_ref().map_err(|e| e.to_string()));
            }
        }

        if self.gestures && !self.paused && self.last_gesture_frame.elapsed() >= GESTURE_INTERVAL {
            self.last_gesture_frame = Instant::now();
            if let Err(e) = self.gesture_frame(jpeg) {
                self.out
                    .emit(json!({ "event": "error", "message": format!("gestures: {e}") }));
                self.gestures = false;
                self.status();
            }
        }

        if !self.gestures && self.pending.is_empty() {
            self.stop_capture();
        }
    }

    fn answer(&mut self, p: Pending, jpeg: &[u8], img: Result<&vision::Rgb, String>) {
        let img = match img {
            Ok(i) => i,
            Err(e) => return self.fail(&p, &format!("decode: {e}")),
        };
        match p {
            Pending::Presence => match self.models.faces(img) {
                Ok(faces) => {
                    let best = faces.first().map(
                        |f| json!({ "score": f.score, "x": f.x, "y": f.y, "w": f.w, "h": f.h }),
                    );
                    self.out.emit(json!({ "event": "presence", "ok": true, "faces": faces.len(), "best": best }));
                }
                Err(e) => self.fail(&Pending::Presence, &e.to_string()),
            },
            Pending::Light => {
                let (mean, dark, bright) = vision::light(img);
                self.out.emit(json!({ "event": "light", "ok": true, "level": mean, "dark": dark, "bright": bright }));
            }
            Pending::Snapshot(path) => {
                // The camera's frames are complete JPEGs; keep them as they are
                let r = Path::new(&path)
                    .parent()
                    .map_or(Ok(()), std::fs::create_dir_all)
                    .and_then(|_| std::fs::write(&path, jpeg));
                self.out.emit(json!({ "event": "snapshot", "ok": r.is_ok(), "path": path, "reason": r.err().map(|e| e.to_string()) }));
            }
        }
    }

    fn gesture_frame(&mut self, jpeg: &[u8]) -> anyhow::Result<()> {
        let img = vision::decode(jpeg, 640)?;
        let now = Instant::now();
        let seen = match self.models.palm(&img)? {
            Some(palm) => self.models.hand(&img, &palm)?.map(|hand| {
                let cx = (palm.x1 + palm.x2) / 2.0 / img.w as f32;
                let cy = (palm.y1 + palm.y2) / 2.0 / img.h as f32;
                (gestures::pose(&hand), cx, cy)
            }),
            None => None,
        };
        if self.feedback {
            // Where the hand is (0..1 of the frame, as the camera sees it) and its pose
            let hand = seen.map(|(pose, x, y)| {
                let pose = match pose {
                    gestures::Pose::Open => "open",
                    gestures::Pose::ThumbUp => "thumbs_up",
                    gestures::Pose::ThumbDown => "thumbs_down",
                    gestures::Pose::Other => "other",
                };
                json!({ "pose": pose, "x": x, "y": y })
            });
            self.out.emit(json!({ "event": "hand", "hand": hand }));
        }
        if let Some(name) = self.tracker.update(now, seen) {
            self.out.emit(json!({ "event": "gesture", "name": name }));
        }
        Ok(())
    }

    fn fail(&self, p: &Pending, reason: &str) {
        let event = match p {
            Pending::Presence => "presence",
            Pending::Light => "light",
            Pending::Snapshot(_) => "snapshot",
        };
        self.out
            .emit(json!({ "event": event, "ok": false, "reason": reason }));
    }

    fn fail_pending(&mut self, reason: &str) {
        for p in std::mem::take(&mut self.pending) {
            self.fail(&p, reason);
        }
    }

    fn report_users(&mut self) {
        let me = std::process::id() as i32;
        let shell = unsafe { libc::getppid() };
        let list: Vec<Value> = self
            .pw_users
            .iter()
            .chain(self.direct_users.iter())
            .map(|u| {
                json!({
                    "pid": u.pid,
                    "name": u.name,
                    "via": u.via,
                    "self": u.own || u.pid == me,
                    "shell": u.pid == shell,
                })
            })
            .collect();
        let v = Value::Array(list);
        if v != self.reported {
            self.reported = v.clone();
            self.out.emit(json!({ "event": "users", "users": v }));
        }
    }

    fn status(&self) {
        let gestures = if !self.gestures {
            "off"
        } else if self.paused {
            "paused"
        } else {
            "running"
        };
        self.out.emit(json!({ "event": "status", "capturing": self.capturing, "gestures": gestures, "device": self.opts.device }));
    }
}
