# Caelestia plugins by xLonely

Plugins for the [Caelestia shell](https://github.com/caelestia-dots/shell):

- **[Better Lyrics](plugins/better-lyrics/)** — desktop lyrics sourced from
  [Better Lyrics](https://api.betterlyrics.org), with the shell's LRCLIB/NetEase lyrics as a fallback.
- **[Astra Strike](plugins/astra-strike/)** — a tiny Asteroids-style game that takes over the desktop,
  rendered by a small Rust engine.
- **[Wall-Seperator](plugins/wall-seperator/)** — wallpaper manager with Live/Static and color
  filters, metadata cards, and quick access to Caelestia's native wallpaper picker.

These plugins target the plugin system in the Caelestia shell and can also be installed by copying
their directories into `~/.local/share/caelestia/plugins/`.

## Quick install (manual)

```sh
git clone https://github.com/LonelyOmen/caelestia-plugins.git
mkdir -p ~/.local/share/caelestia/plugins

cp -r caelestia-plugins/plugins/better-lyrics ~/.local/share/caelestia/plugins/
cp -r caelestia-plugins/plugins/astra-strike ~/.local/share/caelestia/plugins/
cp -r caelestia-plugins/plugins/wall-seperator ~/.local/share/caelestia/plugins/
install -Dm755 caelestia-plugins/plugins/wall-seperator/tools/wall-seperator-metadata \
  ~/.local/bin/wall-seperator-metadata
```

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

Each plugin directory is self-contained. Wall-Seperator's local shell view integration is included
in this user's `~/.config/quickshell/caelestia` overlay; installing the plugin elsewhere provides
the Nexus controls, while the adapted launcher view needs the matching shell overlay. The plugin
uses Caelestia's native wallpaper service for playback and transitions. The metadata helper is
adapted from [SunnydeuS/Caelestia-Live-Wallpapers-Integration](https://github.com/SunnydeuS/Caelestia-Live-Wallpapers-Integration)
under GPL-3.0 and generates local thumbnails and color/resolution metadata.

The plugin system identifies a plugin by the
`author`/`name` pair in its `manifest.json`, not by the directory name, so the directory can be
renamed by the installer (for example to `xlonely-betterlyrics`).

## License

GPL-3.0-only. See [`LICENSE`](LICENSE). The Better Lyrics QML surface is derived from the
desktop-lyrics plugin in `deeadly137/caelestia-plugins`, which is also GPL-3.0.
