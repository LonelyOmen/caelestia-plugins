pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.services
import xlonely.astra

// Activation state for the Astra Strike easter egg.
//
// Deliberately tiny: it owns the on/off flag and the wallpaper round-trip, and
// nothing else. All simulation lives in the Rust process, and all drawing
// lives in AstraStrikeOverlay / AstraStrikeGame - this singleton never holds a
// frame of game state.
Item {
    id: root

    property bool active: false
    property int score: 0
    property bool gameOver: false

    // True while the space backdrop is up *and* we were the ones who put it
    // there. Stopping a preview we never started would hand another
    // component's rollback back to the user mid-flight, so every teardown path
    // checks this first.
    property bool ownsWallpaperPreview: false

    // Bundled starfield (black hole + drifting asteroids) - on-theme, and
    // resolved relative to this plugin instead of the shell install, because
    // plugins do not live under the shell's config directory. Using
    // Qt.resolvedUrl keeps this working when Nexus installs the plugin into a
    // directory named after its id (for example `xlonely-astra`).
    readonly property string spaceWallpaper: String(Qt.resolvedUrl("assets/Gravitation.png")).replace(/^file:\/\//, "").split("?")[0]

    // Prefer a build installed alongside the plugin, where it remains
    // discoverable even when the compositor's PATH omits ~/.local/bin.
    readonly property string bundledEngine: CUtils.toLocalFile(Qt.resolvedUrl("engine/bin/astra-strike"))
    readonly property string engineCommand: CUtils.fileExists(root.bundledEngine) ? root.bundledEngine : "astra-strike"

    signal started
    signal stopped

    function play(): void {
        if (root.active)
            return;

        // preview() captures the live wallpaper first, so stop() hands back
        // the exact one that was showing - including its mode. It never writes
        // the state files, so an unexpected shell exit simply reverts.
        Wallpapers.preview(root.spaceWallpaper);
        root.ownsWallpaperPreview = true;

        root.score = 0;
        root.gameOver = false;
        root.active = true;
        root.started();
    }

    function engineFailed(): void {
        root.stop();
    }

    function stop(): void {
        if (!root.active && !root.ownsWallpaperPreview)
            return;

        // Flip first: the overlay watches `active` and tears its window down
        // the moment it drops, so the backdrop is restored underneath a
        // surface that is already going away.
        root.active = false;

        if (root.ownsWallpaperPreview) {
            root.ownsWallpaperPreview = false;
            Wallpapers.stopPreview();
        }

        root.stopped();
    }

    function toggle(): void {
        if (root.active)
            root.stop();
        else
            root.play();
    }

    IpcHandler {
        function start(): void {
            root.play();
        }

        function toggle(): void {
            root.toggle();
        }

        function stop(): void {
            root.stop();
        }

        function isActive(): bool {
            return root.active;
        }

        function currentScore(): int {
            return root.score;
        }

        target: "astra"
    }
}
