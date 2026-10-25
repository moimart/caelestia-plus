//! Who has the camera open directly (not through PipeWire): inotify on the
//! device nodes says when it's opened or closed, and /proc says by whom.

use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;
use std::time::Duration;

use inotify::{EventMask, Inotify, WatchMask};

use crate::engine::Msg;

#[derive(Clone, Debug, PartialEq)]
pub struct User {
    pub pid: i32,
    pub name: String,
    /// "pipewire" (shares the camera) or "direct" (has the device to itself)
    pub via: &'static str,
    /// The daemon's own capture stream
    pub own: bool,
}

/// The device and its sibling nodes from the same camera (/dev/video0 and
/// /dev/video1 are usually one camera's capture and metadata nodes)
fn sibling_nodes(device: &str) -> Vec<PathBuf> {
    let name = Path::new(device)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");
    let usb = std::fs::read_link(format!("/sys/class/video4linux/{name}/device")).ok();
    let mut nodes = vec![PathBuf::from(device)];
    if let (Some(usb), Ok(entries)) = (usb, std::fs::read_dir("/sys/class/video4linux")) {
        for e in entries.flatten() {
            let other = e.file_name();
            if other.to_str() == Some(name) {
                continue;
            }
            if std::fs::read_link(e.path().join("device")).ok().as_ref() == Some(&usb) {
                nodes.push(PathBuf::from("/dev").join(other));
            }
        }
    }
    nodes
}

/// Processes holding any of the nodes open, other than PipeWire's own (its
/// readers are reported per app from the PipeWire graph instead)
pub fn direct_users(nodes: &[PathBuf]) -> Vec<User> {
    let me = std::process::id() as i32;
    let mut users = vec![];
    let Ok(procs) = std::fs::read_dir("/proc") else {
        return users;
    };
    for p in procs.flatten() {
        let Some(pid) = p.file_name().to_str().and_then(|s| s.parse::<i32>().ok()) else {
            continue;
        };
        if pid == me {
            continue;
        }
        let Ok(fds) = std::fs::read_dir(p.path().join("fd")) else {
            continue;
        };
        let holds = fds
            .flatten()
            .any(|fd| std::fs::read_link(fd.path()).is_ok_and(|t| nodes.contains(&t)));
        if !holds {
            continue;
        }
        let comm = std::fs::read_to_string(p.path().join("comm"))
            .unwrap_or_default()
            .trim()
            .to_string();
        if matches!(
            comm.as_str(),
            "pipewire" | "wireplumber" | "pipewire-media-session"
        ) {
            continue;
        }
        users.push(User {
            pid,
            name: comm,
            via: "direct",
            own: false,
        });
    }
    users.sort_by_key(|u| u.pid);
    users
}

pub fn spawn_direct_watch(device: &str, tx: Sender<Msg>) -> anyhow::Result<()> {
    let nodes = sibling_nodes(device);
    let mut inotify = Inotify::init()?;
    for n in &nodes {
        // Missing nodes (camera unplugged) are simply not watched
        let _ = inotify.watches().add(
            n,
            WatchMask::OPEN | WatchMask::CLOSE_WRITE | WatchMask::CLOSE_NOWRITE,
        );
    }
    let _ = tx.send(Msg::DirectUsers(direct_users(&nodes)));
    std::thread::Builder::new()
        .name("inotify".into())
        .spawn(move || {
            let mut buf = [0u8; 4096];
            let mut last = vec![];
            loop {
                let opened = match inotify.read_events_blocking(&mut buf) {
                    Ok(events) => events.into_iter().any(|e| e.mask.contains(EventMask::OPEN)),
                    Err(_) => break,
                };
                // Report opens straight away: an app that finds the device busy
                // gives up within microseconds, long before it shows up in /proc
                if opened && tx.send(Msg::DeviceOpened).is_err() {
                    break;
                }
                // Let the burst of open/close events settle, then look once
                std::thread::sleep(Duration::from_millis(40));
                while inotify
                    .read_events(&mut buf)
                    .is_ok_and(|mut e| e.next().is_some())
                {}
                let users = direct_users(&nodes);
                if users != last {
                    last = users.clone();
                    if tx.send(Msg::DirectUsers(users)).is_err() {
                        break;
                    }
                }
            }
        })?;
    Ok(())
}
