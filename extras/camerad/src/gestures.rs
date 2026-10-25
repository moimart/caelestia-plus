//! Turning hand landmarks into deliberate gestures.
//!
//! Poses come from finger states, which only depend on distances between
//! landmarks, so they work whatever the hand's rotation:
//!   palm      open hand held still for a moment
//!   swipe     open hand moved sideways quickly (left/right as you see it)
//!   thumbs    fist with the thumb out, held: up or down in the frame
//! Each fires once, then waits for the hand to change or leave, plus a short
//! cooldown, so a gesture never repeats by accident.

use std::collections::VecDeque;
use std::time::{Duration, Instant};

use crate::vision::Hand;

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Pose {
    Open,
    ThumbUp,
    ThumbDown,
    Other,
}

type P = (f32, f32, f32);

fn d(a: P, b: P) -> f32 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

pub fn pose(hand: &Hand) -> Pose {
    let l = &hand.lm;
    let wrist = l[0];
    // A finger is out when its tip is well beyond its middle joint from the wrist
    let out = |tip: usize, pip: usize| d(l[tip], wrist) > d(l[pip], wrist) * 1.12;
    let fingers = [out(8, 6), out(12, 10), out(16, 14), out(20, 18)];
    // Thumb out: its tip far from the index knuckle compared with its own joint
    let thumb = d(l[4], l[5]) > d(l[3], l[5]) * 1.15 && d(l[4], l[17]) > d(l[2], l[17]);

    if fingers.iter().all(|&f| f) {
        return Pose::Open;
    }
    if thumb && fingers.iter().all(|&f| !f) {
        // Thumb direction, turned from the crop back into the frame
        let (vx, vy) = (l[4].0 - l[2].0, l[4].1 - l[2].1);
        let (c, s) = (hand.rotation.cos(), hand.rotation.sin());
        let fy = vx * s + vy * c;
        let len = (vx * vx + vy * vy).sqrt().max(1e-3);
        if fy < -0.55 * len {
            return Pose::ThumbUp;
        }
        if fy > 0.55 * len {
            return Pose::ThumbDown;
        }
    }
    Pose::Other
}

pub struct Tracker {
    history: VecDeque<(Instant, f32, f32, Pose)>,
    fired: Option<Pose>,
    cooldown_until: Instant,
}

const HOLD: Duration = Duration::from_millis(700);
const SWIPE_WINDOW: Duration = Duration::from_millis(600);
const COOLDOWN: Duration = Duration::from_millis(1000);

impl Tracker {
    pub fn new() -> Self {
        Self {
            history: VecDeque::new(),
            fired: None,
            cooldown_until: Instant::now(),
        }
    }

    pub fn reset(&mut self) {
        self.history.clear();
        self.fired = None;
    }

    /// One observation: the hand's pose and the palm centre (0..1 of the
    /// frame), or None when no hand is seen. Returns a gesture when one completes.
    pub fn update(&mut self, now: Instant, seen: Option<(Pose, f32, f32)>) -> Option<&'static str> {
        let Some((pose, x, y)) = seen else {
            // Hand gone: a new gesture may start
            self.history.clear();
            self.fired = None;
            return None;
        };
        self.history.push_back((now, x, y, pose));
        while self
            .history
            .front()
            .is_some_and(|h| now - h.0 > Duration::from_secs(2))
        {
            self.history.pop_front();
        }
        if now < self.cooldown_until {
            return None;
        }

        // Swipe: an open hand travelling a quarter of the frame sideways, fast.
        // The camera isn't mirrored, so moving towards the image's left is your right.
        let recent: Vec<_> = self
            .history
            .iter()
            .filter(|h| now - h.0 <= SWIPE_WINDOW && h.3 == Pose::Open)
            .collect();
        if recent.len() >= 3 {
            let dx = recent.last().unwrap().1 - recent.first().unwrap().1;
            let dy = (recent.last().unwrap().2 - recent.first().unwrap().2).abs();
            if dx.abs() > 0.25 && dy < dx.abs() * 0.6 {
                return self.fire(
                    now,
                    Pose::Other,
                    if dx < 0.0 {
                        "swipe_right"
                    } else {
                        "swipe_left"
                    },
                );
            }
        }

        // Holds: the same pose for HOLD, without moving much
        if self.fired == Some(pose) {
            return None;
        }
        let held: Vec<_> = self
            .history
            .iter()
            .rev()
            .take_while(|h| h.3 == pose)
            .collect();
        let (Some(first), Some(last)) = (held.last(), held.first()) else {
            return None;
        };
        if now - first.0 < HOLD {
            return None;
        }
        let travel = ((last.1 - first.1).powi(2) + (last.2 - first.2).powi(2)).sqrt();
        if travel > 0.06 {
            return None;
        }
        match pose {
            Pose::Open => self.fire(now, pose, "palm"),
            Pose::ThumbUp => self.fire(now, pose, "thumbs_up"),
            Pose::ThumbDown => self.fire(now, pose, "thumbs_down"),
            Pose::Other => None,
        }
    }

    fn fire(&mut self, now: Instant, pose: Pose, name: &'static str) -> Option<&'static str> {
        self.fired = Some(pose);
        self.cooldown_until = now + COOLDOWN;
        // A swipe ends with the hand still open; don't let that count as a palm hold
        if name.starts_with("swipe") {
            self.fired = Some(Pose::Open);
            self.history.clear();
        }
        Some(name)
    }
}
