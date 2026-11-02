//! Serialises a [`Game`] snapshot into the single-line wire format that QML
//! reads.
//!
//! The format is deliberately positional (no keys, no JSON): the consumer is a
//! QML frame loop that walks a number cursor, so keys would only add work.
//!
//! One line, all whitespace separated:
//!
//! ```text
//! F <score> <lives> <phase> <flash> <shakeX> <shakeY>
//!   <shipX> <shipY> <shipRotDeg> <thrust 0|1> <shipAlpha> <shipAlive 0|1>
//!   <nAst> <nBul> <nPart>
//!   [x y rotDeg radius tier]*        <- nAst groups
//!   [x y vx vy]*                     <- nBul groups
//!   [x y size lifeFrac variant]*     <- nPart groups
//! ```
//!
//! Counts appear up front so the reader can size its scratch buffers exactly
//! once and stop the moment it has consumed what the header promised.
//!
//! Coordinates are rounded to whole pixels and angles to one decimal: the
//! extra digits cost bandwidth and parse time without being visible.

use crate::game::{Game, Phase};
use std::fmt::Write as FmtWrite;

/// Output rate. The simulation runs at [`crate::game::TICK_HZ`]; this is how
/// often we pay to serialise and ship a snapshot. Rendering only needs the
/// display's refresh rate, so there is no reason to push more.
pub const OUTPUT_HZ: f64 = 60.0;

pub struct FrameWriter {
    buf: String,
}

impl FrameWriter {
    pub fn new() -> FrameWriter {
        // A busy frame (48 asteroids + full particle pool) is ~8k. Pre-size so
        // the hot path never reallocates.
        FrameWriter {
            buf: String::with_capacity(16 * 1024),
        }
    }

    /// Render `game` into the internal buffer and return it as a line,
    /// newline included. The buffer is reused across calls, so the returned
    /// borrow is only valid until the next `write` call.
    pub fn write(&mut self, game: &Game) -> &str {
        self.buf.clear();

        let ship = &game.ship;
        let _ = write!(
            self.buf,
            "F {} {} {} {:.2} {:.0} {:.0} {:.0} {:.0} {:.1} {} {:.2} {} {} {} {}",
            game.score,
            game.lives,
            match game.phase {
                Phase::Playing => 0,
                Phase::GameOver => 1,
            },
            game.flash,
            game.shake_x,
            game.shake_y,
            ship.x,
            ship.y,
            ship.rot.to_degrees(),
            u8::from(ship.thrusting),
            game.ship_alpha,
            u8::from(game.ship_alive),
            game.asteroids.iter().filter(|a| a.alive).count(),
            game.bullets.iter().filter(|b| b.alive).count(),
            game.particles.iter().filter(|p| p.alive).count(),
        );

        for a in game.asteroids.iter().filter(|a| a.alive) {
            let _ = write!(
                self.buf,
                " {:.0} {:.0} {:.1} {:.0} {}",
                a.x,
                a.y,
                a.rot.to_degrees(),
                a.radius(),
                a.tier
            );
        }

        for b in game.bullets.iter().filter(|b| b.alive) {
            let _ = write!(self.buf, " {:.0} {:.0} {:.0} {:.0}", b.x, b.y, b.vx, b.vy);
        }

        for p in game.particles.iter().filter(|p| p.alive) {
            // Life is sent as a 0..1 fraction so QML can drive opacity without
            // needing to know the particle's original duration.
            let frac = if p.max_life > 0.0 { p.life / p.max_life } else { 0.0 };
            let _ = write!(
                self.buf,
                " {:.0} {:.0} {:.1} {:.2} {}",
                p.x, p.y, p.size, frac, p.variant
            );
        }

        self.buf.push('\n');
        &self.buf
    }
}

impl Default for FrameWriter {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game::{Asteroid, Bullet, Particle, Ship, Rng};

    fn empty_game() -> Game {
        let mut g = Game::new(1920.0, 1080.0, 1);
        // Silence the opening wave so counts are deterministic.
        for a in g.asteroids.iter_mut() {
            a.alive = false;
        }
        for b in g.bullets.iter_mut() {
            b.alive = false;
        }
        for p in g.particles.iter_mut() {
            p.alive = false;
        }
        g
    }

    #[test]
    fn header_leads_and_counts_are_zero_when_empty() {
        let g = empty_game();
        let mut w = FrameWriter::new();
        let line = w.write(&g);
        let fields: Vec<&str> = line.split_whitespace().collect();

        assert_eq!(fields[0], "F");
        // 3 header tokens after F + 9 more header fields + 3 counts = 16 total
        assert_eq!(fields.len(), 16, "got {line:?}");
        assert_eq!(fields[13], "0", "asteroid count");
        assert_eq!(fields[14], "0", "bullet count");
        assert_eq!(fields[15], "0", "particle count");
        assert!(line.ends_with('\n'));
    }

    #[test]
    fn counts_match_emitted_groups() {
        let mut g = empty_game();
        g.asteroids[0] = Asteroid {
            x: 10.0,
            y: 20.0,
            vx: 0.0,
            vy: 0.0,
            rot: 0.0,
            spin: 0.0,
            tier: 1,
            alive: true,
        };
        g.bullets[0] = Bullet {
            x: 1.0,
            y: 2.0,
            vx: 3.0,
            vy: 4.0,
            life: 1.0,
            alive: true,
        };
        g.particles[0] = Particle {
            x: 5.0,
            y: 6.0,
            vx: 0.0,
            vy: 0.0,
            life: 0.5,
            max_life: 1.0,
            size: 3.0,
            variant: 2,
            alive: true,
        };

        let mut w = FrameWriter::new();
        let line = w.write(&g).to_string();
        let n: Vec<f64> = line[2..]
            .split_whitespace()
            .map(|f| f.parse().expect("every field must be numeric"))
            .collect();

        // line[2..] drops "F ", so the 15 header numbers are n[0..=14] and the
        // counts sit at n[12], n[13], n[14].
        let (n_ast, n_bul, n_par) = (n[12] as usize, n[13] as usize, n[14] as usize);
        assert_eq!((n_ast, n_bul, n_par), (1, 1, 1));

        // 15 header numbers, then 5 per asteroid, 4 per bullet, 5 per particle.
        assert_eq!(n.len(), 15 + 5 * n_ast + 4 * n_bul + 5 * n_par, "got {line:?}");
    }

    #[test]
    fn rotation_is_emitted_in_degrees() {
        let mut g = empty_game();
        g.ship.rot = std::f64::consts::PI;
        let mut w = FrameWriter::new();
        let line = w.write(&g).to_string();
        let n: Vec<f64> = line[2..].split_whitespace().map(|f| f.parse().unwrap()).collect();
        assert!((n[8] - 180.0).abs() < 0.05, "expected 180 deg, got {}", n[8]);
    }

    #[test]
    fn buffer_is_reused_and_never_accumulates() {
        let mut g = empty_game();
        g.particles[0] = Particle {
            x: 0.0,
            y: 0.0,
            vx: 0.0,
            vy: 0.0,
            life: 1.0,
            max_life: 1.0,
            size: 2.0,
            variant: 0,
            alive: true,
        };
        let mut w = FrameWriter::new();
        let first = w.write(&g).len();
        for _ in 0..1000 {
            let line = w.write(&g);
            assert_eq!(line.len(), first, "line length drifted across frames");
            assert!(line.starts_with('F'));
        }
    }

    #[test]
    fn rng_never_yields_outside_range() {
        let mut r = Rng::new(12345);
        for _ in 0..10_000 {
            let v = r.range(-5.0, 7.0);
            assert!((-5.0..7.0).contains(&v), "out of range: {v}");
        }
        assert_ne!(r.range(0.0, 1.0), r.range(0.0, 1.0), "rng appears stuck");
    }

    #[test]
    fn ship_struct_still_constructible() {
        // Guards against accidental field renames breaking the QML contract.
        let s = Ship {
            x: 1.0,
            y: 2.0,
            vx: 3.0,
            vy: 4.0,
            rot: 5.0,
            thrusting: true,
        };
        assert!(s.thrusting);
    }
}
