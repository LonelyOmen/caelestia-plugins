# Wall-Seperator

Wall-Seperator adds a small wallpaper manager to Nexus and a quick toggle that opens Caelestia's
native wallpaper launcher. It mirrors the Live/Static, color, random, refresh, file-format, and
resolution controls from [Caelestia Live Wallpapers Integration](https://github.com/SunnydeuS/Caelestia-Live-Wallpapers-Integration).

For the matching carousel in `>wallpaper`, install the user-local Caelestia view integration as
well. The plugin itself uses Caelestia's wallpaper service to apply selections, so the shell remains
responsible for playback, dynamic colors, and transition effects.

The plugin's launcher shortcut is available in **Nexus → Utilities**. Its controls and compact
wallpaper grid appear under **Nexus → Wallpaper & style**.

The refresh action uses `wall-seperator-metadata` to generate video thumbnails and the metadata
cache. Install the included helper at `~/.local/bin/wall-seperator-metadata`; `ffmpeg` and
`python-pillow` are required. The helper does not transcode or alter wallpaper files.
