# Wall-Seperator

Wall-Seperator adds a small wallpaper manager to Nexus and a quick toggle that opens Caelestia's
native wallpaper launcher. It mirrors the Live/Static, color, random, refresh, file-format, and
resolution controls from [Caelestia Live Wallpapers Integration](https://github.com/SunnydeuS/Caelestia-Live-Wallpapers-Integration).

For the matching carousel in `>wallpaper`, install the user-local Caelestia view integration as
well. The plugin itself uses Caelestia's wallpaper service to apply selections, so the shell remains
responsible for playback, dynamic colors, and transition effects.

The plugin's launcher shortcut is available in **Nexus → Utilities**. Its controls and compact
wallpaper grid appear under **Nexus → Wallpaper & style**.

## Install

1. Clone the plugin repository, or open your existing checkout:

   ```sh
   git clone https://github.com/LonelyOmen/caelestia-plugins.git
   cd caelestia-plugins
   ```

2. Install the plugin and its metadata helper:

   ```sh
   mkdir -p ~/.local/share/caelestia/plugins
   cp -r plugins/wall-seperator ~/.local/share/caelestia/plugins/
   install -Dm755 plugins/wall-seperator/tools/wall-seperator-metadata \
     ~/.local/bin/wall-seperator-metadata
   ```

3. Install the helper dependencies. On Arch Linux:

   ```sh
   sudo pacman -S ffmpeg python-pillow
   ```

4. In Caelestia, open **Nexus → Plugins** and enable **Wall-Seperator**. Then reload the shell:

   ```sh
   caelestia shell -r
   ```

5. Open **Nexus → Wallpaper & style** to use the plugin controls. Its shortcut is in **Nexus →
   Utilities**. Press **Refresh** to scan the wallpaper folders and create thumbnails and metadata.

The plugin uses the wallpaper entries exposed by the installed shell. If that shell does not expose
video files through its `Wallpapers` service, the plugin's Live filter will have no videos to show.
The modified `>wallpaper` carousel and Static/Live launcher filters described in this repository
are a separate, user-local shell integration; installing this plugin alone does not add them to
the launcher's `>wallpaper` view.

The metadata helper scans `~/Pictures/Wallpapers` and `~/Pictures/Live-Wallpapers` by default. It
does not transcode or alter wallpaper files.
