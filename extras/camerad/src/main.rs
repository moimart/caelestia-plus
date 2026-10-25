//! caelestia-camerad: the one thing in the shell that touches the camera.
//!
//! The shell runs it and talks JSON lines: requests on stdin, events on stdout.
//! Frames come through PipeWire, only while something needs them, so other
//! PipeWire users (Chrome with its PipeWire camera flag, OBS, ...) share the
//! camera, and the camera light is off the rest of the time. If an app opens
//! the device directly, capture stops at once and resumes once it's free.
//!
//! Requests: {"cmd": "presence" | "light" | "snapshot", "path"?: ...}
//!           {"cmd": "gestures", "on": bool}
//!           {"cmd": "controls"} | {"cmd": "set", "name": ..., "value": ...}
//!           {"cmd": "status"}
//! Events:   {"event": "users" | "presence" | "light" | "snapshot" | "gesture"
//!            | "gestures" | "controls" | "status" | "error", ...}

mod beat;
mod capture;
mod controls;
mod engine;
mod gestures;
mod users;
mod vision;

use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};

use serde_json::Value;

/// Events go to stdout, one JSON object per line, from several threads.
#[derive(Clone)]
pub struct Out(Arc<Mutex<std::io::Stdout>>);

impl Out {
    pub fn emit(&self, v: Value) {
        let mut out = self.0.lock().unwrap_or_else(|e| e.into_inner());
        let _ = writeln!(out, "{v}");
        let _ = out.flush();
    }
}

pub struct Options {
    pub device: String,
    pub models: PathBuf,
}

fn options() -> Options {
    let mut device = "/dev/video0".to_string();
    let mut models = std::env::var_os("CAELESTIA_CAMERA_MODELS")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/usr/lib/caelestia/camera-models"));
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--device" => device = args.next().unwrap_or(device),
            "--models" => models = args.next().map(PathBuf::from).unwrap_or(models),
            _ => {}
        }
    }
    Options { device, models }
}

/// `--test <image.jpg>`: run the models on a picture and print what they see
fn test_image(opts: &Options, path: &str) -> anyhow::Result<()> {
    let jpeg = std::fs::read(path)?;
    let img = vision::decode(&jpeg, 640)?;
    let mut models = vision::Models::new(&opts.models);
    let faces = models.faces(&img)?;
    println!("{}x{} faces: {}", img.w, img.h, faces.len());
    for f in &faces {
        println!(
            "  face {:.2} at {:.2},{:.2} size {:.2}x{:.2}",
            f.score, f.x, f.y, f.w, f.h
        );
    }
    let (level, dark, bright) = vision::light(&img);
    println!("light {level:.2} (dark {dark:.2}, bright {bright:.2})");
    match models.palm(&img)? {
        Some(palm) => {
            println!(
                "palm at {:.0},{:.0}-{:.0},{:.0}",
                palm.x1, palm.y1, palm.x2, palm.y2
            );
            match models.hand(&img, &palm)? {
                Some(hand) => println!(
                    "hand pose {:?} (rotation {:.0} deg)",
                    gestures::pose(&hand),
                    hand.rotation.to_degrees()
                ),
                None => println!("no hand landmarks"),
            }
        }
        None => println!("no palm"),
    }
    Ok(())
}

fn main() -> anyhow::Result<()> {
    let opts = options();
    if let Some(i) = std::env::args().position(|a| a == "--test") {
        let path = std::env::args()
            .nth(i + 1)
            .ok_or_else(|| anyhow::anyhow!("--test needs an image"))?;
        // Inference wants a deep stack for the model graphs
        let h = std::thread::Builder::new()
            .stack_size(64 << 20)
            .spawn(move || test_image(&opts, &path))?;
        return h.join().map_err(|_| anyhow::anyhow!("test panicked"))?;
    }
    let out = Out(Arc::new(Mutex::new(std::io::stdout())));
    let (tx, rx) = mpsc::channel::<engine::Msg>();

    // PipeWire: capture on request, and who is reading the camera through it
    let capture = capture::spawn(opts.device.clone(), tx.clone())?;
    // Direct opens of the device node
    users::spawn_direct_watch(&opts.device, tx.clone())?;

    // Requests from the shell; EOF (the shell went away) ends the daemon
    let stdin_tx = tx.clone();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            if line.trim().is_empty() {
                continue;
            }
            match serde_json::from_str::<Value>(&line) {
                Ok(v) => {
                    let _ = stdin_tx.send(engine::Msg::Request(v));
                }
                Err(e) => {
                    let _ = stdin_tx.send(engine::Msg::BadRequest(e.to_string()));
                }
            }
        }
        let _ = stdin_tx.send(engine::Msg::Quit);
    });

    // Inference wants a deep stack for the model graphs
    let engine = std::thread::Builder::new()
        .name("engine".into())
        .stack_size(64 << 20)
        .spawn(move || engine::run(opts, out, rx, capture))?;
    engine
        .join()
        .map_err(|_| anyhow::anyhow!("engine thread panicked"))?;
    Ok(())
}
