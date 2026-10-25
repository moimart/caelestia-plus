//! Recognises an app that opens the camera on a fixed beat only to list
//! devices: Discord's voice engine opens every video node every 3 s, all day.
//! Its opens don't mean it wants the camera, so they shouldn't send capture
//! away; without this, gestures would stay paused for as long as Discord runs.

use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// Opens this close together are one burst (one look at every node)
const BURST: Duration = Duration::from_millis(500);
/// Bursts needed to learn a beat: four equal gaps
const LEARN: usize = 5;
/// How far a gap may stray from the beat and still count
const SLACK: Duration = Duration::from_millis(300);
const MIN_PERIOD: Duration = Duration::from_secs(1);
const MAX_PERIOD: Duration = Duration::from_secs(60);

#[derive(Default)]
pub struct Beat {
    bursts: VecDeque<Instant>,
    burst_start: Option<Instant>,
    burst_on_beat: bool,
    period: Option<Duration>,
    last_beat: Option<Instant>,
}

impl Beat {
    /// Records an open. True if it belongs to the learned beat. `learn` says
    /// whether this open can teach the beat: only while the camera was free, so
    /// an app that really wants it would have kept it open instead.
    pub fn on_beat(&mut self, now: Instant, learn: bool) -> bool {
        if self.burst_start.is_some_and(|t| now - t < BURST) {
            return self.burst_on_beat;
        }
        self.burst_start = Some(now);

        // The poller stopped (Discord quit): forget its beat
        if let (Some(p), Some(last)) = (self.period, self.last_beat)
            && now - last > p * 3
        {
            self.period = None;
            self.last_beat = None;
        }

        self.burst_on_beat = match (self.period, self.last_beat) {
            (Some(p), Some(last)) => {
                let gap = now - last;
                // Also allow one missed beat
                (1..=2).any(|k| gap.abs_diff(p * k) <= SLACK)
            }
            _ => false,
        };
        if self.burst_on_beat {
            self.last_beat = Some(now);
            return true;
        }

        if !learn {
            self.bursts.clear();
            return false;
        }
        self.bursts.push_back(now);
        while self.bursts.len() > LEARN {
            self.bursts.pop_front();
        }
        if self.bursts.len() == LEARN {
            let gaps: Vec<Duration> = self
                .bursts
                .iter()
                .zip(self.bursts.iter().skip(1))
                .map(|(a, b)| *b - *a)
                .collect();
            let mean = gaps.iter().sum::<Duration>() / gaps.len() as u32;
            if (MIN_PERIOD..=MAX_PERIOD).contains(&mean)
                && gaps.iter().all(|g| g.abs_diff(mean) <= SLACK)
            {
                self.period = Some(mean);
                self.last_beat = Some(now);
                self.burst_on_beat = true;
                self.bursts.clear();
                return true;
            }
        }
        false
    }

    /// Someone actually holds the camera: whatever was learning isn't a poller
    pub fn reset_learning(&mut self) {
        self.bursts.clear();
    }

    pub fn period(&self) -> Option<Duration> {
        self.period
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(start: Instant, ms: u64) -> Instant {
        start + Duration::from_millis(ms)
    }

    #[test]
    fn learns_a_steady_poller_and_ignores_it() {
        let t = Instant::now();
        let mut b = Beat::default();
        for i in 0..4 {
            assert!(!b.on_beat(at(t, i * 3000), true));
            // The rest of the burst follows the verdict of its first open
            assert!(!b.on_beat(at(t, i * 3000 + 5), true));
        }
        assert!(b.on_beat(at(t, 12000), true));
        assert!(b.on_beat(at(t, 15050), false));
        assert!(b.on_beat(at(t, 15060), false));
        // An open off the beat is a real app
        assert!(!b.on_beat(at(t, 16500), false));
        // and doesn't upset the beat
        assert!(b.on_beat(at(t, 18000), false));
        // A missed beat is fine
        assert!(b.on_beat(at(t, 24000), false));
    }

    #[test]
    fn irregular_opens_teach_nothing() {
        let t = Instant::now();
        let mut b = Beat::default();
        for ms in [0, 2000, 5000, 6000, 11000, 13000, 20000] {
            assert!(!b.on_beat(at(t, ms), true));
        }
        assert_eq!(b.period(), None);
    }

    #[test]
    fn opens_while_capturing_teach_nothing() {
        let t = Instant::now();
        let mut b = Beat::default();
        for i in 0..8 {
            assert!(!b.on_beat(at(t, i * 3000), false));
        }
        assert_eq!(b.period(), None);
    }

    #[test]
    fn forgets_a_poller_that_stops() {
        let t = Instant::now();
        let mut b = Beat::default();
        for i in 0..5 {
            b.on_beat(at(t, i * 3000), true);
        }
        assert!(b.period().is_some());
        assert!(!b.on_beat(at(t, 40000), false));
        assert_eq!(b.period(), None);
    }
}
