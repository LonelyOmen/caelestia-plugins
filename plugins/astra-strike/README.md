# Astra Strike

A small Asteroids-style easter egg for the Caelestia shell. The desktop briefly becomes a
starfield, and the game runs on top of it.

The plugin is only the QML frontend. The simulation is a standalone Rust binary
(`astra-strike`) that talks to the QML process over stdin/stdout.

## Requirements

- Caelestia shell with the plugin system
- `cargo` / Rust (only to build the engine)

## Build the engine

From this directory:

```sh
cd engine
./build.sh
install -m755 bin/astra-strike "$HOME/.local/bin/"
```

Make sure `$HOME/.local/bin` is in `PATH`. If you prefer Cargo's install location:

```sh
cargo install --path engine
```

That installs `astra-strike` into `~/.cargo/bin` (also expected to be in `PATH`).

The QML side prefers `engine/bin/astra-strike` when present, then falls back to `astra-strike` in
`PATH`. It does not bundle a prebuilt binary because the engine is architecture-specific. If
neither executable can start, the preview and overlay are dismissed and the shell shows an error.

## Install the plugin

Copy this directory to the plugin directory:

```sh
cp -r astra-strike ~/.local/share/caelestia/plugins/
```

Then enable **Astra Strike** from Nexus → Plugins, or add `xlonely/astra` to
`~/.config/caelestia/plugins.json`.

The plugin adds a quick toggle and an IPC handler. Astra Strike runs one game session on the first
available screen, including on multi-monitor desktops, so there is a single score and keyboard
focus target.

```sh
qs -c caelestia ipc call astra toggle
qs -c caelestia ipc call astra start
qs -c caelestia ipc call astra stop
qs -c caelestia ipc call astra isActive
```

## How it works

- `AstraStrike.qml` owns the active flag and temporarily previews the bundled space wallpaper
  through the shell's `Wallpapers` service.
- `AstraStrikeOverlay.qml` creates the fullscreen surfaces.
- `AstraStrikeGame.qml` spawns the engine and renders its frame snapshots.
- `engine/` contains the Rust source and build script.

The wallpaper path is resolved relative to `AstraStrike.qml`, so the plugin works no matter what
directory the installer chooses.

## License

GPL-3.0-only. See the repository [`LICENSE`](../../LICENSE).
