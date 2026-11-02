# Astra Strike

A small, hidden Asteroids-style easter egg for the Caelestia shell, triggered
from the utilities control panel.

The simulation lives in a standalone Rust binary; the shell plugin only renders it.
The two talk over stdin/stdout, so there is **no daemon, no socket and no file
state** — and nothing to clean up.

## Why out-of-process

An in-process Rust QML plugin was evaluated first and rejected, on evidence:

- Quickshell's virtual import root `qs:@/` cannot resolve native plugins —
  Qt looks the `.so` up against the virtual URL, and the URL interceptor is
  never consulted for `QLibrary`.
- A plugin *is* loadable with `QML_IMPORT_PATH` set before engine creation,
  but producing it needs C++/moc or a `cxx-qt` stack, which breaks the
  cargo-only build.
- Native code in the shell process means a Rust panic takes down the desktop.

A pipe is not the bottleneck here: worst case (every pool full) a frame is
4.3 kB / 1219 numbers and parses in **46.7 µs**, i.e. 0.28% of a 60 fps
budget. Measured, not estimated.

## Wire protocol

Newline-delimited text over stdio. Both directions are positional — no keys,
no JSON — because the consumer is a numeric cursor walk.

### In (stdin), one command per line

| Line           | Meaning                                   |
| -------------- | ----------------------------------------- |
| `c <w> <h>`    | set playfield size (call on resize)       |
| `k <key> <0\|1>` | key down/up; `key` ∈ `w a s d space esc` |
| `m <x> <y>`    | cursor position, aims the nose            |
| `f <0\|1>`     | fire held                                 |
| `r`            | restart after game over                   |
| `q`            | quit                                      |

Unknown lines are ignored — a malformed stream can never crash the game.

### Out (stdout), one snapshot per frame

```
F <score> <lives> <phase> <flash> <shakeX> <shakeY>
  <shipX> <shipY> <shipRotDeg> <thrust> <shipAlpha> <shipAlive>
  <nAst> <nBul> <nPart>
  [x y rotDeg radius tier]*     nAst groups
  [x y vx vy]*                  nBul groups
  [x y size lifeFrac variant]*  nPart groups
```

Counts come first so the reader sizes its pools once and stops exactly where
the header promised. `phase` is `0` playing / `1` game over. `variant` selects
the particle tint (0 blue, 1 violet, 2 pale).

## Lifetime

When Quickshell destroys the `Process`, stdin hits EOF, the reader thread
stops and the main loop exits. There is no timer, no thread and no mapping
left behind — an orphan process is not possible by construction. The same
applies if the pipe breaks on the read side: the binary exits non-zero.

## Simulation

Fixed timestep at 120 Hz with an accumulator, so physics is deterministic no
matter how irregularly the scheduler runs; the backlog is capped at 30 ticks
so a suspend does not fast-forward through thousands of steps. Rendering is
decoupled at 60 Hz. Sleep-based waiting — no spin.

Measured on this machine: **~0.3% CPU**, 2 threads, 3.2 MB RSS.

## Build

```sh
./build.sh          # cargo build --release, installs to ./bin
cargo test          # 16 unit tests
```

The binary lands in `bin/` (gitignored), `CARGO_TARGET_DIR` defaults to the
cargo cache — nothing is written into the QML directory.

## Disabling

Delete or rename `modules/background/AstraStrikeOverlay.qml` and remove the
`AstraStrikeOverlay {}` line from `shell.qml`. The engine is inert until
spawned, so leaving it built costs nothing.
