//! Astra Strike process entry point.
//!
//! Speaks two newline delimited text protocols over stdio, which is the whole
//! bridge to Quickshell - no sockets, no files, no daemon state:
//!
//! * in  on stdin, one command per line (see [`game::Command::parse`])
//! * out on stdout, one snapshot per frame (see [`frame`])
//!
//! Lifetime is tied to the shell side by construction: when Quickshell
//! destroys the `Process`, our stdin reaches EOF, the reader thread stops and
//! the loop exits. There is nothing to clean up and no way to orphan a
//! process or leak a timer.
//!
//! Threading model: one blocked reader thread feeding a channel, one main
//! thread doing a fixed timestep simulation. Simulation never blocks on I/O,
//! and I/O never advances the simulation, so a slow or stalled consumer can
//! not distort game timing.

mod frame;
mod game;

use frame::{FrameWriter, OUTPUT_HZ};
use game::{Command, Game, TICK};

use std::io::{self, BufRead, Write};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

fn main() {
    // Seed from the clock so two sessions never play the identical game, but
    // stay deterministic within a session (replays/tests stay reproducible).
    let seed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0x5EED);
    let mut game = Game::new(1920.0, 1080.0, seed);

    // Reader thread: stdin is a blocking resource, so it never touches Game.
    let (tx, rx) = mpsc::channel::<Command>();
    thread::spawn(move || {
        let stdin = io::stdin();
        let mut lines = stdin.lock().lines();
        while let Some(Ok(line)) = lines.next() {
            if let Some(cmd) = Command::parse(line.trim()) {
                if tx.send(cmd).is_err() {
                    break; // main thread gone
                }
            }
            // Unparseable lines are dropped on purpose: a malformed input
            // stream must never take the game down.
        }
        // EOF: caller closed us. Make sure the process winds down.
        let _ = tx.send(Command::Quit);
    });

    let stdout = io::stdout();
    let mut out = stdout.lock();
    let mut writer = FrameWriter::new();

    let frame_interval = Duration::from_secs_f64(1.0 / OUTPUT_HZ);
    let tick_dt = Duration::from_secs_f64(TICK);

    let mut last_tick = Instant::now();
    let mut next_frame = last_tick;
    let mut acc = Duration::ZERO;
    let mut stdout_broken = false;

    loop {
        // Drain every pending command before stepping, so input is applied in
        // arrival order and never lags a tick behind.
        while let Ok(cmd) = rx.try_recv() {
            game.handle(cmd);
        }
        if game.should_quit() {
            break;
        }

        let now = Instant::now();
        acc += now - last_tick;
        last_tick = now;

        // Cap the backlog: after a suspend or a long stall we drop the excess
        // instead of fast-forwarding through thousands of ticks at once.
        if acc > tick_dt * 30 {
            acc = tick_dt * 30;
        }

        // Fixed timestep. The accumulator keeps physics deterministic no
        // matter how irregularly we get scheduled.
        while acc >= tick_dt {
            game.update(TICK);
            acc -= tick_dt;
        }

        if now >= next_frame {
            let line = writer.write(&game);
            if out.write_all(line.as_bytes()).is_err() || out.flush().is_err() {
                // Reader is gone; there is nobody left to render for.
                stdout_broken = true;
                break;
            }
            next_frame += frame_interval;
            // If we fell behind (slow consumer, debugger stop), resynchronise
            // rather than emitting a burst of catch-up frames.
            if next_frame < now {
                next_frame = now + frame_interval;
            }
        }

        // Sleep until the earlier of the two deadlines. The accumulator means
        // oversleeping is harmless, so a coarse sleep is fine and keeps CPU
        // near idle while the game is on screen.
        let now = Instant::now();
        let until_tick = tick_dt.saturating_sub(acc);
        let until_frame = next_frame.saturating_duration_since(now);
        let sleep_for = until_tick.min(until_frame);
        if !sleep_for.is_zero() {
            thread::sleep(sleep_for);
        }
    }

    if stdout_broken {
        // Exiting non-zero lets the shell notice the pipe died on our side.
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn game_new_does_not_panic_on_tiny_world() {
        let mut g = Game::new(1.0, 1.0, 3);
        for _ in 0..500 {
            g.update(TICK);
        }
    }

    #[test]
    fn command_stream_is_resilient_to_garbage() {
        // Mirrors the reader loop's contract: garbage is ignored, Quit wins.
        assert!(Command::parse("nonsense").is_none());
        assert!(Command::parse("").is_none());
        assert!(Command::parse("   ").is_none());
        assert!(Command::parse("k notakey 1").is_none());
        assert!(Command::parse("c 800 600").is_some());
        assert!(matches!(Command::parse("q"), Some(Command::Quit)));
    }

    #[test]
    fn configure_repositions_world_bounds() {
        let mut g = Game::new(100.0, 100.0, 9);
        g.handle(Command::Configure { w: 2560.0, h: 1440.0 });
        assert_eq!(g.w, 2560.0);
        assert_eq!(g.h, 1440.0);
    }
}
