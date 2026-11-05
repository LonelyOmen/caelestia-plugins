pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Models
import Caelestia.Plugins
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.utils
import qs.modules.nexus.common

ColumnLayout {
    id: root

    required property SettingsObject settings

    property var metadataCache: ({})
    readonly property bool hasNativeFilters: typeof Wallpapers.filterMode === "number"
    readonly property int filterMode: root.hasNativeFilters ? Wallpapers.filterMode : Number(root.settings.filterMode ?? 2)
    readonly property string colorFilter: root.hasNativeFilters ? String(Wallpapers.colorFilter ?? "") : String(root.settings.colorFilter ?? "")

    readonly property var palette: [
        { id: "red", label: "Red", hex: "#E53935" },
        { id: "orange", label: "Orange", hex: "#FB8C00" },
        { id: "yellow", label: "Yellow", hex: "#FDD835" },
        { id: "green", label: "Green", hex: "#4CAF50" },
        { id: "blue", label: "Blue", hex: "#2196F3" },
        { id: "purple", label: "Purple", hex: "#9C27B0" },
        { id: "pink", label: "Pink", hex: "#EC407A" },
        { id: "white", label: "White", hex: "#FFFFFF" },
        { id: "black", label: "Black", hex: "#1A1A1A" }
    ]

    function selectRandom(): void {
        const entries = root.filteredEntries;
        if (entries.length > 0)
            Wallpapers.setWallpaper(entries[Math.floor(Math.random() * entries.length)].path);
        else
            Wallpapers.setRandom();
    }

    function setMode(mode: int): void {
        root.settings.filterMode = mode;
        if (root.hasNativeFilters)
            Wallpapers.filterMode = mode;
    }

    function setColor(color: string): void {
        root.settings.colorFilter = color;
        if (root.hasNativeFilters)
            Wallpapers.colorFilter = color;
    }

    function isLive(path: string): bool {
        return /\.(mp4|m4v|mkv|webm|avi|mov)$/i.test(path);
    }

    function localImageUrl(path: string): string {
        const value = String(path || "");
        return value.startsWith("file://") ? value : `file://${value}`;
    }

    function metadataFor(path: string): var {
        const clean = String(path || "").replace(/^file:\/\//, "");
        return root.metadataCache[clean] || root.metadataCache[path] || ({});
    }

    readonly property var filteredEntries: {
        const entries = Wallpapers.list || [];
        return entries.filter(entry => {
            const live = root.isLive(String(entry.path));
            if (root.filterMode === 0 && live)
                return false;
            if (root.filterMode === 1 && !live)
                return false;
            if (!root.colorFilter)
                return true;
            const metadata = root.metadataFor(entry.path);
            return metadata.color === root.colorFilter || (Array.isArray(metadata.colors) && metadata.colors.includes(root.colorFilter));
        });
    }

    FileView {
        id: metadataFile

        path: `${Paths.home}/.cache/caelestia/wallpaper_properties.json`
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                root.metadataCache = JSON.parse(text().trim());
            } catch (error) {
                root.metadataCache = {};
            }
        }
    }

    Component.onCompleted: {
        if (root.hasNativeFilters) {
            Wallpapers.filterMode = Number(root.settings.filterMode ?? 2);
            Wallpapers.colorFilter = String(root.settings.colorFilter ?? "");
        }
    }

    function refreshMetadata(): void {
        if (!metadataRefresh.running)
            metadataRefresh.running = true;
    }

    Process {
        id: metadataRefresh

        command: [
            `${Paths.home}/.local/bin/wall-seperator-metadata`,
            Paths.wallsdir,
            Quickshell.env("CAELESTIA_LIVE_WALLPAPERS_DIR") || `${Paths.wallsdir.substring(0, Paths.wallsdir.lastIndexOf("/"))}/Live-Wallpapers`
        ]
        onExited: metadataFile.reload()
    }

    SectionHeader {
        text: "Wall-Seperator"
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        text: Tr.tr("Browse wallpapers by type and color. Caelestia applies the selected wallpaper.")
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    }

    Row {
        Layout.alignment: Qt.AlignHCenter
        spacing: Tokens.spacing.small

        IconTextButton {
            icon: "collections"
            text: Tr.tr("All")
            isToggle: true
            checked: root.filterMode === 2
            onClicked: root.setMode(2)
        }
        IconTextButton {
            icon: "image"
            text: Tr.tr("Static")
            isToggle: true
            checked: root.filterMode === 0
            onClicked: root.setMode(0)
        }
        IconTextButton {
            icon: "smart_display"
            text: Tr.tr("Live")
            isToggle: true
            checked: root.filterMode === 1
            onClicked: root.setMode(1)
        }
        IconTextButton {
            icon: "shuffle"
            text: Tr.tr("Random")
            onClicked: root.selectRandom()
        }
        IconTextButton {
            icon: "refresh"
            text: Tr.tr("Refresh")
            onClicked: root.refreshMetadata()
        }
    }

    Flickable {
        Layout.fillWidth: true
        implicitHeight: 38
        contentWidth: colorRow.implicitWidth
        contentHeight: height
        clip: true
        flickableDirection: Flickable.HorizontalFlick

        Row {
            id: colorRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                text: Tr.tr("All colors")
                isToggle: true
                checked: root.colorFilter === ""
                onClicked: root.setColor("")
            }

            Repeater {
                model: root.palette

                delegate: Item {
                    id: swatch
                    required property var modelData
                    width: 30
                    height: 30

                    Rectangle {
                        anchors.centerIn: parent
                        width: root.colorFilter === swatch.modelData.id ? 24 : 20
                        height: width
                        radius: Tokens.rounding.full
                        color: swatch.modelData.hex
                        border.width: root.colorFilter === swatch.modelData.id || swatch.modelData.id === "white" || swatch.modelData.id === "black" ? 2 : 0
                        border.color: Colours.palette.m3outline

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: root.setColor(root.colorFilter === swatch.modelData.id ? "" : swatch.modelData.id)
                        }
                    }
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        visible: Wallpapers.actualCurrent !== ""
        text: Tr.tr("Current: %1").arg(Wallpapers.actualCurrent.split("/").pop())
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
        elide: Text.ElideMiddle
    }

    GridView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 360)
        cellWidth: 164
        cellHeight: 138
        clip: true
        model: root.filteredEntries

        delegate: Item {
            id: card
            required property var modelData
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight

            readonly property var details: root.metadataFor(modelData.path)
            readonly property string format: {
                const path = String(modelData.path);
                const match = path.match(/\.([^.]+)$/);
                return match ? match[1].toUpperCase() : "IMAGE";
            }
            readonly property string resolution: String(details.info || "").split(",")[0] || ""

            ClipRect {
                id: preview
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 92
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainer

                Image {
                    anchors.fill: parent
                    source: root.localImageUrl(root.isLive(String(card.modelData.path))
                        ? `${Paths.home}/.cache/caelestia/live_thumbs/${String(card.modelData.path).split("/").pop()}.jpg`
                        : String(card.modelData.path))
                    asynchronous: true
                    smooth: true
                    fillMode: Image.PreserveAspectCrop
                }

                StyledRect {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: Tokens.spacing.extraSmall
                    radius: Tokens.rounding.small
                    color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.9)
                    implicitWidth: typeLabel.implicitWidth + Tokens.padding.small
                    implicitHeight: typeLabel.implicitHeight + 4

                    StyledText {
                        id: typeLabel
                        anchors.centerIn: parent
                        text: card.format
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.label.small
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: Wallpapers.setWallpaper(card.modelData.path)
                }
            }

            StyledText {
                anchors.top: preview.bottom
                anchors.topMargin: Tokens.spacing.extraSmall
                anchors.left: parent.left
                anchors.right: parent.right
                text: card.resolution || card.modelData.name
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: root.filteredEntries.length === 0
            text: root.colorFilter !== "" ? Tr.tr("No wallpapers match this color.") : Tr.tr("No wallpapers found.")
            color: Colours.palette.m3outline
            font: Tokens.font.label.medium
        }
    }
}
