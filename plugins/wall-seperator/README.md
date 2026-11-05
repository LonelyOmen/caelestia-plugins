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
   ./plugins/wall-seperator/install.sh
   ```

   It leaves an existing plugin or helper untouched. If you intentionally want to update an older
   install, use `./plugins/wall-seperator/install.sh --update`; it backs up the old plugin/helper
   under `~/.local/state/caelestia/wall-seperator/backups/` before updating. The installer does not
   use `sudo` or change shell files in the default mode.

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

## Optional: install the `>wallpaper` launcher integration

The plugin alone adds the Nexus page and Utilities shortcut. The launcher carousel, its All/Static/Live
filters, and video entries in Caelestia's wallpaper service come from the separate per-user overlay
in `user-config/`.

Run the installer with its explicit overlay option:

```sh
./plugins/wall-seperator/install.sh --with-shell-overlay
```

The installer shows which QML files it will change and asks before proceeding. It backs up any
different versions of those files under `~/.local/state/caelestia/wall-seperator/backups/`. If no
user shell config exists, it starts from the installed system config. It refuses to follow symlinks
for the affected directories or files, and leaves `shell.json` and unrelated shell files alone.
On systems where the shell config is outside the XDG config directories, create the user shell
config from the installed Caelestia config first, then rerun the installer.

To use the official crossfade transition, merge this setting into the existing `background` object
in `~/.config/caelestia/shell.json` (do not replace the rest of that object):

```json
"wallpaperTransition": "Crossfade"
```

Reload Caelestia after installing the overlay:

```sh
caelestia shell -r
```

The plugin uses the wallpaper entries exposed by the installed shell. If that shell does not expose
video files through its `Wallpapers` service, the plugin's Live filter will have no videos to show.
The modified `>wallpaper` carousel and Static/Live launcher filters described in this repository
are a separate, user-local shell integration; installing this plugin alone does not add them to
the launcher's `>wallpaper` view.

The metadata helper scans the XDG Pictures directory's `Wallpapers` and `Live-Wallpapers` folders
by default. It does not transcode or alter wallpaper files. The user-config overlay is version
specific to the installed Caelestia shell and may need adapting after shell updates.
