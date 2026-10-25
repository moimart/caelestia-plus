//! Frames and models: MJPEG decoding at reduced size, face detection (YuNet),
//! a light estimate, and the MediaPipe palm detector and hand landmarker.
//! Models are from opencv_zoo and run on ONNX Runtime.

use std::path::Path;

use anyhow::Context;
use ndarray::Array4;
use ort::environment::Environment;
use ort::session::Session;
use ort::value::TensorRef;

/// An RGB frame
pub struct Rgb {
    pub w: usize,
    pub h: usize,
    pub px: Vec<u8>,
}

impl Rgb {
    fn get(&self, x: f32, y: f32) -> [f32; 3] {
        // Bilinear, black outside
        if x < 0.0 || y < 0.0 || x > (self.w - 1) as f32 || y > (self.h - 1) as f32 {
            return [0.0; 3];
        }
        let (x0, y0) = (x.floor() as usize, y.floor() as usize);
        let (x1, y1) = ((x0 + 1).min(self.w - 1), (y0 + 1).min(self.h - 1));
        let (fx, fy) = (x - x0 as f32, y - y0 as f32);
        let p = |x: usize, y: usize, c: usize| self.px[(y * self.w + x) * 3 + c] as f32;
        let mut out = [0.0; 3];
        for (c, o) in out.iter_mut().enumerate() {
            let top = p(x0, y0, c) * (1.0 - fx) + p(x1, y0, c) * fx;
            let bot = p(x0, y1, c) * (1.0 - fx) + p(x1, y1, c) * fx;
            *o = top * (1.0 - fy) + bot * fy;
        }
        out
    }
}

/// Decodes a JPEG at roughly `max_w` wide, using the decoder's DCT scaling
/// (1/2, 1/4, 1/8) so large camera frames cost little
pub fn decode(jpeg: &[u8], max_w: u16) -> anyhow::Result<Rgb> {
    let mut dec = jpeg_decoder::Decoder::new(jpeg);
    dec.read_info()?;
    let info = dec.info().context("no JPEG info")?;
    let h = (max_w as u32 * info.height as u32 / info.width.max(1) as u32) as u16;
    dec.scale(max_w, h)?;
    let px = dec.decode()?;
    let info = dec.info().context("no JPEG info")?;
    let (w, h) = (info.width as usize, info.height as usize);
    let px = match info.pixel_format {
        jpeg_decoder::PixelFormat::RGB24 => px,
        jpeg_decoder::PixelFormat::L8 => px.iter().flat_map(|&v| [v, v, v]).collect(),
        f => anyhow::bail!("unsupported JPEG pixel format {f:?}"),
    };
    Ok(Rgb { w, h, px })
}

/// Fits a frame into a `size` square (aspect kept, centred, black bars):
/// returns NHWC or NCHW floats and the mapping back (scale, pad x, pad y)
fn letterbox(
    img: &Rgb,
    size: usize,
    nchw: bool,
    bgr: bool,
    norm: f32,
) -> (Array4<f32>, f32, f32, f32) {
    let s = size as f32 / img.w.max(img.h) as f32;
    let (nw, nh) = (img.w as f32 * s, img.h as f32 * s);
    let (px, py) = ((size as f32 - nw) / 2.0, (size as f32 - nh) / 2.0);
    let mut t = if nchw {
        Array4::zeros((1, 3, size, size))
    } else {
        Array4::zeros((1, size, size, 3))
    };
    for y in 0..size {
        let sy = (y as f32 - py + 0.5) / s - 0.5;
        if sy < -0.5 || sy > img.h as f32 - 0.5 {
            continue;
        }
        for x in 0..size {
            let sx = (x as f32 - px + 0.5) / s - 0.5;
            if sx < -0.5 || sx > img.w as f32 - 0.5 {
                continue;
            }
            let p = img.get(
                sx.clamp(0.0, (img.w - 1) as f32),
                sy.clamp(0.0, (img.h - 1) as f32),
            );
            for c in 0..3 {
                let v = p[if bgr { 2 - c } else { c }] * norm;
                if nchw {
                    t[[0, c, y, x]] = v;
                } else {
                    t[[0, y, x, c]] = v;
                }
            }
        }
    }
    (t, s, px, py)
}

/// Mean brightness of the scene, 0..1, with the darkest and brightest tenth.
/// The camera adjusts its exposure on its own, so this is relative: it tells
/// a dim room from a lit one, not lux.
pub fn light(img: &Rgb) -> (f32, f32, f32) {
    let mut lum: Vec<u8> = img
        .px
        .as_chunks::<3>()
        .0
        .iter()
        .map(|p| (0.2126 * p[0] as f32 + 0.7152 * p[1] as f32 + 0.0722 * p[2] as f32) as u8)
        .collect();
    if lum.is_empty() {
        return (0.0, 0.0, 0.0);
    }
    let mean = lum.iter().map(|&v| v as f32).sum::<f32>() / lum.len() as f32 / 255.0;
    lum.sort_unstable();
    let p = |q: f32| lum[((lum.len() - 1) as f32 * q) as usize] as f32 / 255.0;
    (mean, p(0.1), p(0.9))
}

pub struct Face {
    pub score: f32,
    /// Box in the frame, normalised to 0..1
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

pub struct Palm {
    /// Box and the 7 palm keypoints, in frame pixels
    pub x1: f32,
    pub y1: f32,
    pub x2: f32,
    pub y2: f32,
    pub kps: [(f32, f32); 7],
}

pub struct Hand {
    /// 21 landmarks in the 224px crop, which is rotated so the hand points up
    pub lm: [(f32, f32, f32); 21],
    /// The crop's rotation (radians), to turn crop directions back into the frame's
    pub rotation: f32,
}

pub struct Models {
    env: Option<Environment>,
    face: Option<Session>,
    palm: Option<Session>,
    hand: Option<Session>,
    anchors: Vec<(f32, f32)>,
    dir: std::path::PathBuf,
}

const FACE: &str = "face_detection_yunet_2023mar.onnx";
const PALM: &str = "palm_detection_mediapipe_2023feb.onnx";
const HAND: &str = "handpose_estimation_mediapipe_2023feb.onnx";

fn session(env: &Environment, path: &Path) -> anyhow::Result<Session> {
    // ort's builder errors carry the builder, which isn't Send; keep the message
    let mut builder = Session::builder(env)
        .map_err(|e| anyhow::anyhow!("{e}"))?
        .with_intra_threads(2)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    builder
        .commit_from_file(path)
        .map_err(|e| anyhow::anyhow!("loading {}: {e}", path.display()))
}

/// The palm detector's anchors: one per cell of a 24x24 grid (twice) and a
/// 12x12 grid (six times), centred in the cell
fn palm_anchors() -> Vec<(f32, f32)> {
    let mut a = Vec::with_capacity(2016);
    for (fm, n) in [(24usize, 2usize), (12, 6)] {
        for y in 0..fm {
            for x in 0..fm {
                for _ in 0..n {
                    a.push(((x as f32 + 0.5) / fm as f32, (y as f32 + 0.5) / fm as f32));
                }
            }
        }
    }
    a
}

fn sigmoid(v: f32) -> f32 {
    1.0 / (1.0 + (-v).exp())
}

impl Models {
    pub fn new(dir: &Path) -> Self {
        Self {
            env: None,
            face: None,
            palm: None,
            hand: None,
            anchors: palm_anchors(),
            dir: dir.to_path_buf(),
        }
    }

    /// ONNX Runtime (libonnxruntime.so) is loaded on first use, then each model
    /// as a feature needs it, so features that are off never cost memory
    fn load(
        env: &mut Option<Environment>,
        slot: &mut Option<Session>,
        dir: &Path,
        file: &str,
    ) -> anyhow::Result<()> {
        if slot.is_none() {
            if env.is_none() {
                *env = Some(
                    ort::init()
                        .with_name("caelestia-camerad")
                        .build()
                        .map_err(|e| anyhow::anyhow!("ONNX Runtime: {e}"))?,
                );
            }
            *slot = Some(session(env.as_ref().unwrap(), &dir.join(file))?);
        }
        Ok(())
    }

    /// Unloads the gesture models while gestures are off
    pub fn drop_hands(&mut self) {
        self.palm = None;
        self.hand = None;
    }

    pub fn faces(&mut self, img: &Rgb) -> anyhow::Result<Vec<Face>> {
        Self::load(&mut self.env, &mut self.face, &self.dir, FACE)?;
        let face = self.face.as_mut().unwrap();
        // YuNet: 640x640, BGR, 0..255
        let (input, s, px, py) = letterbox(img, 640, true, true, 1.0);
        let outputs = face.run(ort::inputs![TensorRef::from_array_view(&input)?])?;
        let get = |name: &str| -> anyhow::Result<Vec<f32>> {
            let (_, data) = outputs[name].try_extract_tensor::<f32>()?;
            Ok(data.to_vec())
        };
        let mut faces = vec![];
        for stride in [8usize, 16, 32] {
            let cls = get(&format!("cls_{stride}"))?;
            let obj = get(&format!("obj_{stride}"))?;
            let bbox = get(&format!("bbox_{stride}"))?;
            let cols = 640 / stride;
            for i in 0..cls.len() {
                let score = (cls[i].clamp(0.0, 1.0) * obj[i].clamp(0.0, 1.0)).sqrt();
                if score < 0.6 {
                    continue;
                }
                let (r, c) = ((i / cols) as f32, (i % cols) as f32);
                let cx = (c + bbox[i * 4]) * stride as f32;
                let cy = (r + bbox[i * 4 + 1]) * stride as f32;
                let w = bbox[i * 4 + 2].exp() * stride as f32;
                let h = bbox[i * 4 + 3].exp() * stride as f32;
                // Back from the letterbox to the frame, normalised
                let fx = ((cx - w / 2.0 - px) / s) / img.w as f32;
                let fy = ((cy - h / 2.0 - py) / s) / img.h as f32;
                faces.push(Face {
                    score,
                    x: fx,
                    y: fy,
                    w: w / s / img.w as f32,
                    h: h / s / img.h as f32,
                });
            }
        }
        // Keep the best of overlapping boxes
        faces.sort_by(|a, b| b.score.total_cmp(&a.score));
        let mut kept: Vec<Face> = vec![];
        for f in faces {
            if kept.iter().all(|k| iou(k, &f) < 0.3) {
                kept.push(f);
            }
        }
        Ok(kept)
    }

    pub fn palm(&mut self, img: &Rgb) -> anyhow::Result<Option<Palm>> {
        Self::load(&mut self.env, &mut self.palm, &self.dir, PALM)?;
        let palm = self.palm.as_mut().unwrap();
        // 192x192, RGB, 0..1, NHWC
        let (input, s, px, py) = letterbox(img, 192, false, false, 1.0 / 255.0);
        let outputs = palm.run(ort::inputs![TensorRef::from_array_view(&input)?])?;
        let (_, boxes) = outputs[0].try_extract_tensor::<f32>()?;
        let (_, scores) = outputs[1].try_extract_tensor::<f32>()?;
        let mut best: Option<(usize, f32)> = None;
        for (i, &raw) in scores.iter().enumerate() {
            let sc = sigmoid(raw);
            if sc >= 0.5 && best.is_none_or(|(_, b)| sc > b) {
                best = Some((i, sc));
            }
        }
        let Some((i, score)) = best else {
            return Ok(None);
        };
        let b = &boxes[i * 18..i * 18 + 18];
        let (ax, ay) = self.anchors[i];
        // Model space (0..1 of the letterboxed input) -> frame pixels
        let to_frame = |nx: f32, ny: f32| ((nx * 192.0 - px) / s, (ny * 192.0 - py) / s);
        let (cx, cy) = (b[0] / 192.0 + ax, b[1] / 192.0 + ay);
        let (w, h) = (b[2] / 192.0, b[3] / 192.0);
        let (x1, y1) = to_frame(cx - w / 2.0, cy - h / 2.0);
        let (x2, y2) = to_frame(cx + w / 2.0, cy + h / 2.0);
        let mut kps = [(0.0, 0.0); 7];
        for (k, kp) in kps.iter_mut().enumerate() {
            *kp = to_frame(b[4 + k * 2] / 192.0 + ax, b[5 + k * 2] / 192.0 + ay);
        }
        let _ = score;
        Ok(Some(Palm {
            x1,
            y1,
            x2,
            y2,
            kps,
        }))
    }

    /// Landmarks for the hand around a detected palm. The crop follows
    /// MediaPipe: rotated so wrist -> middle finger points up, shifted towards
    /// the fingers and enlarged to take in the whole hand.
    pub fn hand(&mut self, img: &Rgb, palm: &Palm) -> anyhow::Result<Option<Hand>> {
        Self::load(&mut self.env, &mut self.hand, &self.dir, HAND)?;
        let hand = self.hand.as_mut().unwrap();
        let (wx, wy) = palm.kps[0]; // wrist
        let (mx, my) = palm.kps[2]; // middle finger base
        let mut rotation = std::f32::consts::FRAC_PI_2 - (-(my - wy)).atan2(mx - wx);
        rotation -= 2.0
            * std::f32::consts::PI
            * ((rotation + std::f32::consts::PI) / (2.0 * std::f32::consts::PI)).floor();
        let size = (palm.x2 - palm.x1).max(palm.y2 - palm.y1);
        let (cos, sin) = (rotation.cos(), rotation.sin());
        // Shift half a box towards the fingers (in the rotated frame)
        let (shift_x, shift_y) = (0.0, -0.5 * size);
        let cx = (palm.x1 + palm.x2) / 2.0 + shift_x * cos - shift_y * sin;
        let cy = (palm.y1 + palm.y2) / 2.0 + shift_x * sin + shift_y * cos;
        let side = size * 2.6;

        const N: usize = 224;
        let mut input = Array4::<f32>::zeros((1, N, N, 3));
        for v in 0..N {
            for u in 0..N {
                let lx = ((u as f32 + 0.5) / N as f32 - 0.5) * side;
                let ly = ((v as f32 + 0.5) / N as f32 - 0.5) * side;
                let p = img.get(cx + lx * cos - ly * sin, cy + lx * sin + ly * cos);
                for c in 0..3 {
                    input[[0, v, u, c]] = p[c] / 255.0;
                }
            }
        }
        if let Some(path) = std::env::var_os("CAMERAD_DUMP_CROP") {
            // Debugging aid: the crop the landmarker sees, as a PPM
            let mut ppm = format!("P6 {N} {N} 255\n").into_bytes();
            ppm.extend(input.iter().map(|v| (v * 255.0) as u8));
            let _ = std::fs::write(path, ppm);
        }
        let outputs = hand.run(ort::inputs![TensorRef::from_array_view(&input)?])?;
        let (_, lms) = outputs[0].try_extract_tensor::<f32>()?;
        let (_, conf) = outputs[1].try_extract_tensor::<f32>()?;
        let conf = conf.first().copied().unwrap_or(0.0);
        if std::env::var_os("CAMERAD_DEBUG").is_some() {
            eprintln!("camerad: hand confidence {conf:.2}");
        }
        if conf < 0.6 {
            return Ok(None);
        }
        let mut lm = [(0.0, 0.0, 0.0); 21];
        for (k, l) in lm.iter_mut().enumerate() {
            *l = (lms[k * 3], lms[k * 3 + 1], lms[k * 3 + 2]);
        }
        Ok(Some(Hand { lm, rotation }))
    }
}

fn iou(a: &Face, b: &Face) -> f32 {
    let (x1, y1) = (a.x.max(b.x), a.y.max(b.y));
    let (x2, y2) = ((a.x + a.w).min(b.x + b.w), (a.y + a.h).min(b.y + b.h));
    let inter = (x2 - x1).max(0.0) * (y2 - y1).max(0.0);
    inter / (a.w * a.h + b.w * b.h - inter).max(1e-6)
}
