//! Astra Strike - fixed timestep simulation of the game world.
//!
//! The engine owns every piece of gameplay state: movement, collisions,
//! splitting, spawning, particles, score and game rules.  It is completely
//! unaware of QML/Quickshell; its only input/output is the command stream and
//! the frame snapshot built in [`crate::frame`].

use std::f64::consts::{PI, TAU};

// ---------------------------------------------------------------------------
// Tunables
// ---------------------------------------------------------------------------

pub const TICK_HZ: f64 = 120.0;
pub const TICK: f64 = 1.0 / TICK_HZ;

const SHIP_RADIUS: f64 = 11.0;
const BULLET_RADIUS: f64 = 3.0;
const SHIP_ACCEL: f64 = 780.0;
const SHIP_BRAKE: f64 = 420.0;
const SHIP_MAX_SPEED: f64 = 430.0;
const SHIP_DRAG: f64 = 0.5; // exponential damping, per second
const SHIP_TURN: f64 = 3.6; // rad/s while steering with the keyboard
const AIM_SMOOTH: f64 = 15.0 // how fast the nose tracks the cursor
    ;

const BULLET_SPEED: f64 = 640.0;
const BULLET_LIFE: f64 = 1.05;
const FIRE_COOLDOWN: f64 = 0.17;
const MAX_BULLETS: usize = 16;

const MAX_ASTEROIDS: usize = 48;
const MAX_PARTICLES: usize = 180;

const RESPAWN_DELAY: f64 = 1.25;
const INVULN_TIME: f64 = 1.6;
const STARTING_LIVES: i32 = 3;
const WAVE_DELAY: f64 = 1.6;

/// Tier radii / score for asteroids. Index 0 is the smallest shard.
const TIERS: [f64; 3] = [15.0, 27.0, 44.0];
const TIER_SCORE: [i32; 3] = [100, 50, 20];

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Key {
    Thrust,
    Brake,
    Left,
    Right,
    Space,
}

#[derive(Debug, Clone, Copy)]
pub enum Command {
    Configure { w: f64, h: f64 },
    Key { key: Key, down: bool },
    Mouse { x: f64, y: f64 },
    Fire(bool),
    Restart,
    Quit,
}

impl Command {
    /// Parse a single wire command. Unknown input is ignored rather than
    /// fatal - the shell and the engine must never kill each other over
    /// malformed data.
    pub fn parse(line: &str) -> Option<Command> {
        let mut it = line.split_ascii_whitespace();
        let head = it.next()?;
        match head {
            "c" => Some(Command::Configure {
                w: it.next()?.parse().ok()?,
                h: it.next()?.parse().ok()?,
            }),
            "m" => Some(Command::Mouse {
                x: it.next()?.parse().ok()?,
                y: it.next()?.parse().ok()?,
            }),
            "k" => Some(Command::Key {
                key: match it.next()? {
                    "w" | "up" => Key::Thrust,
                    "s" | "down" => Key::Brake,
                    "a" | "left" => Key::Left,
                    "d" | "right" => Key::Right,
                    "space" => Key::Space,
                    _ => return None,
                },
                down: it.next()? != "0",
            }),
            "f" => Some(Command::Fire(it.next()? != "0")),
            "r" => Some(Command::Restart),
            "q" => Some(Command::Quit),
            _ => None,
        }
    }
}

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

#[derive(Clone, Copy)]
pub struct Ship {
    pub x: f64,
    pub y: f64,
    pub vx: f64,
    pub vy: f64,
    pub rot: f64,
    pub thrusting: bool,
}

#[derive(Clone, Copy)]
pub struct Asteroid {
    pub x: f64,
    pub y: f64,
    pub vx: f64,
    pub vy: f64,
    pub rot: f64,
    pub spin: f64,
    /// 0 = shard, 1 = rock, 2 = boulder
    pub tier: u8,
    pub alive: bool,
}

impl Asteroid {
    #[inline]
    pub fn radius(&self) -> f64 {
        TIERS[self.tier as usize]
    }
}

#[derive(Clone, Copy)]
pub struct Bullet {
    pub x: f64,
    pub y: f64,
    pub vx: f64,
    pub vy: f64,
    pub life: f64,
    pub alive: bool,
}

#[derive(Clone, Copy)]
pub struct Particle {
    pub x: f64,
    pub y: f64,
    pub vx: f64,
    pub vy: f64,
    pub life: f64,
    pub max_life: f64,
    pub size: f64,
    /// 0 = blue, 1 = violet, 2 = pale
    pub variant: u8,
    pub alive: bool,
}

// ---------------------------------------------------------------------------
// Tiny dependency free RNG (xorshift64*)
// ---------------------------------------------------------------------------

pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Rng {
        Rng(if seed == 0 { 0x9E3779B97F4A7C15 } else { seed })
    }

    #[inline]
    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545F4914F6CDD1D)
    }

    /// Uniform in [lo, hi)
    #[inline]
    pub fn range(&mut self, lo: f64, hi: f64) -> f64 {
        let t = (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64;
        lo + (hi - lo) * t
    }
}

// ---------------------------------------------------------------------------
// Game
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Playing,
    GameOver,
}

pub struct Game {
    pub w: f64,
    pub h: f64,
    pub score: i32,
    pub lives: i32,
    pub phase: Phase,
    pub ship: Ship,
    pub ship_alive: bool,
    /// 0..1 alpha for the invulnerability blink, computed by the engine
    pub ship_alpha: f64,
    pub asteroids: Vec<Asteroid>,
    pub bullets: Vec<Bullet>,
    pub particles: Vec<Particle>,
    pub flash: f64,
    pub shake_x: f64,
    pub shake_y: f64,

    // --- internal state -----------------------------------------------------
    respawn: f64,
    invuln: f64,
    shake_mag: f64,
    wave: i32,
    wave_delay: f64,
    fire_cd: f64,
    fire_held: bool,
    thrust_held: bool,
    brake_held: bool,
    rot_left: bool,
    rot_right: bool,
    aim: Option<(f64, f64)>,
    time: f64,
    quit: bool,
    rng: Rng,
}

impl Game {
    pub fn new(w: f64, h: f64, seed: u64) -> Game {
        let mut g = Game {
            w,
            h,
            score: 0,
            lives: STARTING_LIVES,
            phase: Phase::Playing,
            ship: Ship {
                x: w * 0.5,
                y: h * 0.5,
                vx: 0.0,
                vy: 0.0,
                rot: -PI / 2.0,
                thrusting: false,
            },
            ship_alive: true,
            ship_alpha: 1.0,
            asteroids: Vec::with_capacity(MAX_ASTEROIDS),
            bullets: Vec::with_capacity(MAX_BULLETS),
            particles: Vec::with_capacity(MAX_PARTICLES),
            flash: 0.0,
            shake_x: 0.0,
            shake_y: 0.0,
            respawn: 0.0,
            invuln: INVULN_TIME,
            shake_mag: 0.0,
            wave: 0,
            wave_delay: 0.35,
            fire_cd: 0.0,
            fire_held: false,
            thrust_held: false,
            brake_held: false,
            rot_left: false,
            rot_right: false,
            aim: None,
            time: 0.0,
            quit: false,
            rng: Rng::new(seed),
        };
        // Pools are pre-sized once; nothing below allocates during update().
        g.asteroids.resize(
            MAX_ASTEROIDS,
            Asteroid {
                x: 0.0,
                y: 0.0,
                vx: 0.0,
                vy: 0.0,
                rot: 0.0,
                spin: 0.0,
                tier: 2,
                alive: false,
            },
        );
        g.bullets.resize(
            MAX_BULLETS,
            Bullet {
                x: 0.0,
                y: 0.0,
                vx: 0.0,
                vy: 0.0,
                life: 0.0,
                alive: false,
            },
        );
        g.particles.resize(
            MAX_PARTICLES,
            Particle {
                x: 0.0,
                y: 0.0,
                vx: 0.0,
                vy: 0.0,
                life: 0.0,
                max_life: 1.0,
                size: 2.0,
                variant: 0,
                alive: false,
            },
        );
        g
    }

    pub fn should_quit(&self) -> bool {
        self.quit
    }

    pub fn handle(&mut self, cmd: Command) {
        match cmd {
            Command::Configure { w, h } => {
                if w > 1.0 && h > 1.0 {
                    self.w = w;
                    self.h = h;
                    for a in self.asteroids.iter_mut() {
                        if a.alive {
                            a.x = wrap(a.x, self.w);
                            a.y = wrap(a.y, self.h);
                        }
                    }
                    self.ship.x = wrap(self.ship.x, self.w);
                    self.ship.y = wrap(self.ship.y, self.h);
                }
            }
            Command::Key { key, down } => match key {
                Key::Thrust => self.thrust_held = down,
                Key::Brake => self.brake_held = down,
                Key::Left => {
                    self.rot_left = down;
                    if down {
                        self.aim = None;
                    }
                }
                Key::Right => {
                    self.rot_right = down;
                    if down {
                        self.aim = None;
                    }
                }
                Key::Space => {
                    if down && self.phase == Phase::GameOver {
                        self.restart();
                    } else {
                        self.fire_held = down;
                    }
                }
            },
            Command::Mouse { x, y } => self.aim = Some((x, y)),
            Command::Fire(down) => {
                if down && self.phase == Phase::GameOver {
                    self.restart();
                } else {
                    self.fire_held = down;
                }
            }
            Command::Restart => self.restart(),
            Command::Quit => self.quit = true,
        }
    }

    pub fn restart(&mut self) {
        self.score = 0;
        self.lives = STARTING_LIVES;
        self.phase = Phase::Playing;
        self.wave = 0;
        self.wave_delay = 0.5;
        for a in self.asteroids.iter_mut() {
            a.alive = false;
        }
        for b in self.bullets.iter_mut() {
            b.alive = false;
        }
        for p in self.particles.iter_mut() {
            p.alive = false;
        }
        self.respawn = 0.0;
        self.ship_alive = true;
        self.ship.x = self.w * 0.5;
        self.ship.y = self.h * 0.5;
        self.ship.vx = 0.0;
        self.ship.vy = 0.0;
        self.ship.rot = -PI / 2.0;
        self.invuln = INVULN_TIME;
        self.flash = 0.0;
        self.shake_mag = 0.0;
    }

    /// Advance the simulation by a fixed `dt` seconds.
    pub fn update(&mut self, dt: f64) {
        self.time += dt;

        // --- screen shake + flash decay (visual only, drawn by QML) --------
        self.shake_mag *= (-5.5 * dt).exp();
        if self.shake_mag < 0.01 {
            self.shake_mag = 0.0;
        }
        self.shake_x = self.shake_mag * (self.time * 47.0).sin();
        self.shake_y = self.shake_mag * (self.time * 61.0 + 1.7).sin();
        self.flash = (self.flash - dt * 3.4).max(0.0);

        self.update_ship(dt);
        self.update_bullets(dt);
        self.update_asteroids(dt);
        self.update_particles(dt);
        self.collide(dt);
        self.update_waves(dt);
    }

    fn update_ship(&mut self, dt: f64) {
        if !self.ship_alive {
            if self.phase == Phase::Playing {
                self.respawn -= dt;
                if self.respawn <= 0.0 {
                    self.ship_alive = true;
                    self.ship.x = self.w * 0.5;
                    self.ship.y = self.h * 0.5;
                    self.ship.vx = 0.0;
                    self.ship.vy = 0.0;
                    self.ship.rot = -PI / 2.0;
                    self.invuln = INVULN_TIME;
                    self.aim = None;
                }
            }
            self.ship_alpha = 0.0;
            return;
        }

        if self.invuln > 0.0 {
            self.invuln -= dt;
            // smooth blink rather than a hard toggle
            let t = self.time * 11.0;
            self.ship_alpha = 0.42 + 0.58 * t.sin().abs();
        } else {
            self.ship_alpha = 1.0;
        }

        // steering: keyboard overrides the cursor until the pointer moves again
        if self.rot_left ^ self.rot_right {
            let dir = if self.rot_right { 1.0 } else { -1.0 };
            self.ship.rot += dir * SHIP_TURN * dt;
        } else if let Some((mx, my)) = self.aim {
            let target = (my - self.ship.y).atan2(mx - self.ship.x);
            self.ship.rot = angle_lerp(self.ship.rot, target, 1.0 - (-AIM_SMOOTH * dt).exp());
        }

        let (mut ax, mut ay) = (0.0, 0.0);
        if self.thrust_held {
            ax += self.ship.rot.cos() * SHIP_ACCEL;
            ay += self.ship.rot.sin() * SHIP_ACCEL;
            self.ship.thrusting = true;
        } else if self.brake_held {
            ax -= self.ship.rot.cos() * SHIP_BRAKE;
            ay -= self.ship.rot.sin() * SHIP_BRAKE;
            self.ship.thrusting = false;
        } else {
            self.ship.thrusting = false;
        }

        self.ship.vx += ax * dt;
        self.ship.vy += ay * dt;

        let damp = (-SHIP_DRAG * dt).exp();
        self.ship.vx *= damp;
        self.ship.vy *= damp;

        let speed = (self.ship.vx * self.ship.vx + self.ship.vy * self.ship.vy).sqrt();
        if speed > SHIP_MAX_SPEED {
            let k = SHIP_MAX_SPEED / speed;
            self.ship.vx *= k;
            self.ship.vy *= k;
        }

        self.ship.x = wrap(self.ship.x + self.ship.vx * dt, self.w);
        self.ship.y = wrap(self.ship.y + self.ship.vy * dt, self.h);

        if self.phase == Phase::Playing {
            self.fire_cd -= dt;
            if self.fire_held && self.fire_cd <= 0.0 {
                self.fire();
            }
        }
    }

    fn fire(&mut self) {
        self.fire_cd = FIRE_COOLDOWN;
        let slot = match self.bullets.iter().position(|b| !b.alive) {
            Some(i) => i,
            None => return,
        };
        let dirx = self.ship.rot.cos();
        let diry = self.ship.rot.sin();
        let b = &mut self.bullets[slot];
        // spawn at the nose, inherit part of the ship's velocity
        b.x = self.ship.x + dirx * (SHIP_RADIUS + 4.0);
        b.y = self.ship.y + diry * (SHIP_RADIUS + 4.0);
        b.vx = dirx * BULLET_SPEED + self.ship.vx * 0.35;
        b.vy = diry * BULLET_SPEED + self.ship.vy * 0.35;
        b.life = BULLET_LIFE;
        b.alive = true;
    }

    fn update_bullets(&mut self, dt: f64) {
        for b in self.bullets.iter_mut() {
            if !b.alive {
                continue;
            }
            b.life -= dt;
            if b.life <= 0.0 {
                b.alive = false;
                continue;
            }
            b.x = wrap(b.x + b.vx * dt, self.w);
            b.y = wrap(b.y + b.vy * dt, self.h);
        }
    }

    fn update_asteroids(&mut self, dt: f64) {
        for a in self.asteroids.iter_mut() {
            if !a.alive {
                continue;
            }
            a.rot += a.spin * dt;
            a.x = wrap(a.x + a.vx * dt, self.w);
            a.y = wrap(a.y + a.vy * dt, self.h);
        }
    }

    fn update_particles(&mut self, dt: f64) {
        for p in self.particles.iter_mut() {
            if !p.alive {
                continue;
            }
            p.life -= dt;
            if p.life <= 0.0 {
                p.alive = false;
                continue;
            }
            let damp = (-1.6 * dt).exp();
            p.vx *= damp;
            p.vy *= damp;
            p.x += p.vx * dt;
            p.y += p.vy * dt;
        }
    }

    fn collide(&mut self, dt: f64) {
        // bullets vs asteroids -------------------------------------------------
        for bi in 0..self.bullets.len() {
            if !self.bullets[bi].alive {
                continue;
            }
            let (bx, by) = (self.bullets[bi].x, self.bullets[bi].y);
            for ai in 0..self.asteroids.len() {
                if !self.asteroids[ai].alive {
                    continue;
                }
                let r = self.asteroids[ai].radius() + BULLET_RADIUS;
                let dx = self.asteroids[ai].x - bx;
                let dy = self.asteroids[ai].y - by;
                if dx * dx + dy * dy <= r * r {
                    self.bullets[bi].alive = false;
                    let tier = self.asteroids[ai].tier;
                    self.destroy_asteroid(ai, true, tier);
                    break;
                }
            }
        }

        // ship vs asteroids ----------------------------------------------------
        if self.ship_alive
            && self.phase == Phase::Playing
            && self.invuln <= 0.0
        {
            let (sx, sy) = (self.ship.x, self.ship.y);
            for ai in 0..self.asteroids.len() {
                if !self.asteroids[ai].alive {
                    continue;
                }
                let r = self.asteroids[ai].radius() + SHIP_RADIUS * 0.75;
                let dx = self.asteroids[ai].x - sx;
                let dy = self.asteroids[ai].y - sy;
                if dx * dx + dy * dy <= r * r {
                    self.destroy_asteroid(ai, false, self.asteroids[ai].tier);
                    self.kill_ship();
                    break;
                }
            }
        }

        // keeps dt referenced for future timed effects without warnings
        let _ = dt;
    }

    /// Remove asteroid `ai`, award points, spawn debris, add shake/flash and
    /// split it when it was large enough.
    fn destroy_asteroid(&mut self, ai: usize, award: bool, tier: u8) {
        let (cx, cy) = (self.asteroids[ai].x, self.asteroids[ai].y);
        self.asteroids[ai].alive = false;

        if award {
            self.score += TIER_SCORE[tier as usize];
        }

        self.burst(cx, cy, 9 + tier as i32 * 5, 140.0 + tier as f64 * 70.0, tier);
        self.flash = (self.flash + 0.16 + tier as f64 * 0.05).min(1.0);
        self.add_shake(2.6 + tier as f64 * 1.6);

        if tier > 0 {
            self.split(cx, cy, tier);
        }
    }

    fn split(&mut self, cx: f64, cy: f64, tier: u8) {
        let base = (55.0 + tier as f64 * 32.0) * (1.0 + self.wave as f64 * 0.03);
        for _ in 0..2 {
            let slot = match self.asteroids.iter().position(|a| !a.alive) {
                Some(i) => i,
                None => return,
            };
            let ang = self.rng.range(0.0, std::f64::consts::TAU);
            let speed = self.rng.range(base * 0.7, base * 1.35);
            let a = &mut self.asteroids[slot];
            a.x = cx;
            a.y = cy;
            a.vx = ang.cos() * speed;
            a.vy = ang.sin() * speed;
            a.rot = self.rng.range(0.0, std::f64::consts::TAU);
            a.spin = self.rng.range(-1.4, 1.4);
            a.tier = tier - 1;
            a.alive = true;
        }
    }

    fn kill_ship(&mut self) {
        let (sx, sy) = (self.ship.x, self.ship.y);
        self.ship_alive = false;
        self.ship_alpha = 0.0;
        self.burst(sx, sy, 26, 250.0, 2);
        self.flash = (self.flash + 0.55).min(1.0);
        self.add_shake(7.0);
        self.lives -= 1;
        if self.lives <= 0 {
            self.lives = 0;
            self.phase = Phase::GameOver;
        } else {
            self.respawn = RESPAWN_DELAY;
        }
    }

    fn add_shake(&mut self, amount: f64) {
        self.shake_mag = (self.shake_mag + amount).min(9.0);
    }

    /// Spawn `n` debris particles at (x, y) radiating outward.
    fn burst(&mut self, x: f64, y: f64, n: i32, speed: f64, tier: u8) {
        for _ in 0..n {
            let slot = match self.particles.iter().position(|p| !p.alive) {
                Some(i) => i,
                None => return, // pool exhausted: drop rather than grow
            };
            let ang = self.rng.range(0.0, std::f64::consts::TAU);
            let sp = self.rng.range(speed * 0.25, speed);
            let life = self.rng.range(0.35, 0.85);
            let p = &mut self.particles[slot];
            p.x = x;
            p.y = y;
            p.vx = ang.cos() * sp;
            p.vy = ang.sin() * sp;
            p.life = life;
            p.max_life = life;
            p.size = self.rng.range(1.6, 3.4 + tier as f64 * 0.9);
            p.variant = if tier == 2 {
                (self.rng.next_u64() % 3) as u8
            } else {
                (self.rng.next_u64() % 2) as u8
            };
            p.alive = true;
        }
    }

    fn update_waves(&mut self, dt: f64) {
        if self.phase != Phase::Playing {
            return;
        }
        let any = self.asteroids.iter().any(|a| a.alive);
        if any {
            return;
        }
        self.wave_delay -= dt;
        if self.wave_delay <= 0.0 {
            self.spawn_wave();
            self.wave_delay = WAVE_DELAY;
        }
    }

    fn spawn_wave(&mut self) {
        self.wave += 1;
        let count = (5 + (self.wave - 1)).min(8);
        let speed_scale = (1.0 + (self.wave - 1) as f64 * 0.07).min(1.7);
        let (cx, cy) = (self.ship.x, self.ship.y);

        for _ in 0..count {
            let slot = match self.asteroids.iter().position(|a| !a.alive) {
                Some(i) => i,
                None => return,
            };
            // ring spawn, kept clear of the ship
            let ang = self.rng.range(0.0, std::f64::consts::TAU);
            let radius = self.rng.range(0.0, 260.0);
            let mut x = cx + ang.cos() * (320.0 + radius);
            let mut y = cy + ang.sin() * (320.0 + radius);
            x = wrap(x, self.w);
            y = wrap(y, self.h);
            if dist(x, y, cx, cy) < 300.0 {
                x = wrap(x + self.w * 0.5, self.w);
                y = wrap(y + self.h * 0.5, self.h);
            }

            // head roughly toward the play area with jitter
            let to_center = (self.h * 0.5 - y).atan2(self.w * 0.5 - x);
            let dir = to_center + self.rng.range(-0.7, 0.7);
            let sp = self.rng.range(45.0, 95.0) * speed_scale;
            let a = &mut self.asteroids[slot];
            a.x = x;
            a.y = y;
            a.vx = dir.cos() * sp;
            a.vy = dir.sin() * sp;
            a.rot = self.rng.range(0.0, std::f64::consts::TAU);
            a.spin = self.rng.range(-0.9, 0.9);
            a.tier = 2;
            a.alive = true;
        }
    }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

#[inline]
fn wrap(v: f64, max: f64) -> f64 {
    if v < -64.0 {
        max + 64.0
    } else if v > max + 64.0 {
        -64.0
    } else {
        v
    }
}

#[inline]
fn dist(x1: f64, y1: f64, x2: f64, y2: f64) -> f64 {
    ((x1 - x2).powi(2) + (y1 - y2).powi(2)).sqrt()
}

/// Shortest-path interpolation between two angles.
///
/// `b - a` is wrapped into (-PI, PI] first so that lerping across the
/// +/-PI seam rotates the short way round instead of spinning the long way.
#[inline]
fn angle_lerp(a: f64, b: f64, k: f64) -> f64 {
    let mut delta = (b - a) % TAU;
    if delta > PI {
        delta -= TAU;
    } else if delta < -PI {
        delta += TAU;
    }
    a + delta * k.clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_parse_roundtrip() {
        assert!(matches!(
            Command::parse("c 1920 1080"),
            Some(Command::Configure { .. })
        ));
        assert!(matches!(
            Command::parse("k up 1"),
            Some(Command::Key {
                key: Key::Thrust,
                down: true
            })
        ));
        assert!(matches!(Command::parse("m 12.5 -3"), Some(Command::Mouse { .. })));
        assert!(matches!(Command::parse("f 0"), Some(Command::Fire(false))));
        assert!(matches!(Command::parse("r"), Some(Command::Restart)));
        assert!(matches!(Command::parse("q"), Some(Command::Quit)));
        assert!(Command::parse("k nope 1").is_none());
        assert!(Command::parse("garbage").is_none());
        assert!(Command::parse("").is_none());
    }

    #[test]
    fn pool_sizes_are_fixed() {
        let mut g = Game::new(1920.0, 1080.0, 42);
        g.handle(Command::Configure { w: 1920.0, h: 1080.0 });
        for _ in 0..600 {
            g.update(TICK);
        }
        assert!(g.asteroids.len() <= MAX_ASTEROIDS);
        assert!(g.bullets.len() <= MAX_BULLETS);
        assert!(g.particles.len() <= MAX_PARTICLES);
    }

    #[test]
    fn particles_never_exceed_pool() {
        let mut g = Game::new(800.0, 600.0, 7);
        for i in 0..400 {
            g.burst(100.0 + i as f64, 100.0, 30, 200.0, 2);
        }
        assert!(g.particles.iter().filter(|p| p.alive).count() <= MAX_PARTICLES);
    }

    #[test]
    fn shooting_destroys_and_scores() {
        let mut g = Game::new(1200.0, 800.0, 3);
        // place one asteroid right in front of the ship
        g.asteroids[0] = Asteroid {
            x: 200.0,
            y: 400.0,
            vx: 0.0,
            vy: 0.0,
            rot: 0.0,
            spin: 0.0,
            tier: 0,
            alive: true,
        };
        g.ship.x = 150.0;
        g.ship.y = 400.0;
        g.ship.rot = 0.0;
        g.handle(Command::Key {
            key: Key::Space,
            down: true,
        });
        g.update(TICK); // fires

        // The bullet closes ~17px of gap in about 3 ticks. Stop well before
        // the 0.35s wave delay, otherwise update_waves() refills the emptied
        // pool into slot 0 and this assertion would see a fresh boulder.
        for _ in 0..20 {
            g.update(TICK);
            if !g.asteroids[0].alive {
                break;
            }
        }
        assert!(!g.asteroids[0].alive, "asteroid should be destroyed");
        assert!(g.score >= TIER_SCORE[0], "score should increase");
    }

    #[test]
    fn ship_respawns_after_hit_and_game_ends_at_zero_lives() {
        let mut g = Game::new(1200.0, 800.0, 3);
        g.invuln = 0.0;
        g.lives = 1;
        g.kill_ship();
        assert_eq!(g.phase, Phase::GameOver);
        assert_eq!(g.lives, 0);

        g.restart();
        assert_eq!(g.phase, Phase::Playing);
        assert_eq!(g.lives, STARTING_LIVES);
        assert_eq!(g.score, 0);
        assert!(g.ship_alive);
    }

    #[test]
    fn entities_wrap_around_the_world() {
        let mut g = Game::new(500.0, 400.0, 1);
        g.ship.x = -100.0;
        g.ship.y = 500.0;
        g.ship.vx = -50.0;
        g.ship.vy = 50.0;
        for _ in 0..600 {
            g.update(TICK);
        }
        assert!(g.ship.x >= -65.0 && g.ship.x <= 565.0);
        assert!(g.ship.y >= -65.0 && g.ship.y <= 465.0);
    }

    #[test]
    fn no_quiet_spin_after_long_run() {
        // 5 minutes of simulated play must not panic, grow pools or lose time
        let mut g = Game::new(1920.0, 1080.0, 9);
        g.handle(Command::Key {
            key: Key::Thrust,
            down: true,
        });
        g.handle(Command::Fire(true));
        for _ in 0..(60 * 300) {
            g.update(TICK);
        }
        assert!(!g.should_quit());
        assert!(g.asteroids.len() == MAX_ASTEROIDS);
    }
}
