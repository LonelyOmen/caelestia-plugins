# Caelestia plugins by xLonely

Plugins for the [Caelestia shell](https://github.com/caelestia-dots/shell):

- **[Better Lyrics](plugins/better-lyrics/)** — desktop lyrics sourced from
  [Better Lyrics](https://api.betterlyrics.org), with the shell's LRCLIB/NetEase lyrics as a fallback.
- **[Astra Strike](plugins/astra-strike/)** — a tiny Asteroids-style game that takes over the desktop,
  rendered by a small Rust engine.
- **[Wall-Seperator](plugins/wall-seperator/)** — wallpaper manager with Live/Static and color
  filters, metadata cards, and quick access to Caelestia's native wallpaper picker.

These plugins target the plugin system in the Caelestia shell. Wall-Seperator includes an installer
that leaves existing plugin files untouched and can optionally install its backed-up, per-user
launcher overlay.

## Quick install

```sh
git clone https://github.com/LonelyOmen/caelestia-plugins.git
mkdir -p ~/.local/share/caelestia/plugins

cp -r caelestia-plugins/plugins/better-lyrics ~/.local/share/caelestia/plugins/
cp -r caelestia-plugins/plugins/astra-strike ~/.local/share/caelestia/plugins/
cd caelestia-plugins
./plugins/wall-seperator/install.sh
```

To also install the optional per-user `>wallpaper` launcher integration, run
`./plugins/wall-seperator/install.sh --with-shell-overlay`. The installer asks before changing
shell QML files and backs up replaced files under `~/.local/state/caelestia/wall-seperator/`.

Then enable the plugins from **Nexus → Plugins**, or add their ids to
`~/.config/caelestia/plugins.json`:

```json
[
  "xlonely/betterlyrics",
  "xlonely/astra",
  "xlonely/wallseperator"
]
```

Astra Strike also needs its engine binary; see
[`plugins/astra-strike/README.md`](plugins/astra-strike/README.md#build-the-engine).

The registry entries for these plugins are in [`index.json`](index.json).

## Layout

```
plugins/better-lyrics/   QML plugin (manifest id: xlonely/betterlyrics)
plugins/astra-strike/    QML plugin + Rust engine source (manifest id: xlonely/astra)
plugins/wall-seperator/   QML wallpaper manager (manifest id: xlonely/wallseperator)
index.json               registry entries for a Nexus index PR
```

Each plugin directory is self-contained. Wall-Seperator's optional local shell view integration is
bundled in `plugins/wall-seperator/user-config/`; installing the plugin alone provides the Nexus
controls, while the adapted launcher view needs the matching per-user shell overlay. The plugin
uses Caelestia's native wallpaper service for playback and transitions. The metadata helper is
adapted from [SunnydeuS/Caelestia-Live-Wallpapers-Integration](https://github.com/SunnydeuS/Caelestia-Live-Wallpapers-Integration)
under GPL-3.0 and generates local thumbnails and color/resolution metadata.

The plugin system identifies a plugin by the
`author`/`name` pair in its `manifest.json`, not by the directory name, so the directory can be
renamed by the installer (for example to `xlonely-betterlyrics`).

## License

GPL-3.0-only. See [`LICENSE`](LICENSE). The Better Lyrics QML surface is derived from the
desktop-lyrics plugin in `deeadly137/caelestia-plugins`, which is also GPL-3.0.
