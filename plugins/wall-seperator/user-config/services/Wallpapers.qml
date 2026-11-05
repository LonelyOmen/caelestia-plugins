pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import Caelestia.State
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    // The user's own "Play wallpaper" toggle stays authoritative. A plugin may mask playback (for
    // example while a fullscreen window is visible) through the `wallpapers.paused` hook; removing
    // the plugin restores normal playback without touching the toggle.
    readonly property bool pausedByPlugin: Hooks.value("wallpapers.paused", false) === true
    readonly property bool playing: PersistentState.wallpaperPlaying && !root.pausedByPlugin

    // A plugin can draw the wallpaper outside the shell (for example a Wallpaper Engine process on
    // the background layer). While a provider is registered, the shell's background window goes
    // transparent so the external surface shows through. The value is the owning plugin id; a
    // provider must only clear it when it still owns it.
    property string externalProvider
    readonly property bool externalActive: root.externalProvider !== ""

    // Wallpaper folders exposed by the launcher's wallpaper picker. The stock shell does not group
    // wallpapers; a plugin can supply a grouping through the `wallpapers.*` hooks. Empty categories
    // means the picker shows every wallpaper in a single list.
    readonly property var categories: Hooks.call("wallpapers.categories", [root.list]) ?? []
    readonly property var grouped: Hooks.call("wallpapers.grouped", [root.list]) ?? ({})

    // The launcher picker owns these filters. Wallpaper setting and transitions remain native.
    property int filterMode: 0 // 0: static, 1: live, 2: all
    property string colorFilter: ""
    property var propertiesCache: ({})

    FileView {
        id: propertiesFile

        path: `${Paths.home}/.cache/caelestia/wallpaper_properties.json`
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                root.propertiesCache = JSON.parse(text().trim());
            } catch (error) {
                root.propertiesCache = {};
                console.warn("Wall-Seperator: could not read wallpaper metadata", error);
            }
        }
    }

    function metadata(path: string): var {
        const clean = String(path || "").replace(/^file:\/\//, "");
        return root.propertiesCache[clean] || root.propertiesCache[path] || ({});
    }

    function matchesColor(path: string, color: string): bool {
        if (!color)
            return true;
        const entry = root.metadata(path);
        return entry.color === color || (Array.isArray(entry.colors) && entry.colors.includes(color));
    }

    function thumbnailPath(path: string): string {
        const clean = String(path || "").replace(/^file:\/\//, "");
        if (/\.(mp4|m4v|mkv|webm|avi|mov)$/i.test(clean))
            return `${Paths.home}/.cache/caelestia/live_thumbs/${clean.split("/").pop()}.jpg`;
        return clean;
    }

    function cycleFilterMode(reverse = false): void {
        const order = [2, 0, 1];
        let index = order.indexOf(root.filterMode);
        if (index < 0)
            index = 0;
        root.filterMode = order[(index + (reverse ? order.length - 1 : 1)) % order.length];
    }

    function cycleColorFilter(reverse = false): void {
        const colors = ["", "red", "orange", "yellow", "green", "blue", "purple", "pink", "white", "black"];
        let index = colors.indexOf(root.colorFilter);
        if (index < 0)
            index = 0;
        root.colorFilter = colors[(index + (reverse ? colors.length - 1 : 1)) % colors.length];
    }

    function refreshWallpapers(): void {
        if (!refreshProc.running)
            refreshProc.running = true;
    }

    readonly property var allEntries: {
        const values = [];
        if (root.filterMode === 0 || root.filterMode === 2)
            values.push(...(wallpapers.entries || []));
        if (root.filterMode === 1 || root.filterMode === 2) {
            values.push(...(liveWallpapers.entries || []));
            values.push(...(extraLiveWallpapers.entries || []));
        }
        if (!root.colorFilter)
            return values;
        return values.filter(entry => root.matchesColor(entry.path, root.colorFilter));
    }

    Process {
        id: refreshProc

        command: [
            `${Paths.home}/.local/bin/wall-seperator-metadata`,
            Paths.wallsdir,
            extraLiveWallpapers.path
        ]
        onExited: {
            propertiesFile.reload();
            const staticPath = wallpapers.path;
            const livePath = liveWallpapers.path;
            const extraPath = extraLiveWallpapers.path;
            wallpapers.path = "";
            liveWallpapers.path = "";
            extraLiveWallpapers.path = "";
            Qt.callLater(() => {
                wallpapers.path = staticPath;
                liveWallpapers.path = livePath;
                extraLiveWallpapers.path = extraPath;
            });
        }
    }

    function getCategoryFor(w: FileSystemEntry): string {
        const hooked = Hooks.call("wallpapers.categoryFor", [w]);
        if (hooked !== undefined && hooked !== null)
            return hooked;

        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: allEntries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    FileSystemModel {
        id: liveWallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Videos
    }

    FileSystemModel {
        id: extraLiveWallpapers

        recursive: true
        path: Quickshell.env("CAELESTIA_LIVE_WALLPAPERS_DIR") || `${Paths.wallsdir.substring(0, Paths.wallsdir.lastIndexOf("/"))}/Live-Wallpapers`
        filter: FileSystemModel.Videos
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
