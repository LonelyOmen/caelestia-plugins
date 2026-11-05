pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components.controls
import qs.services

IconButton {
    id: root

    fillWidth: true
    shapeMorph: true
    icon: "wallpaper"
    isToggle: false
    isRound: true
    inactiveColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
    inactiveOnColour: Colours.palette.m3onSurfaceVariant

    onClicked: {
        if (typeof Wallpapers.filterMode === "number") {
            Wallpapers.filterMode = 2;
            Wallpapers.colorFilter = "";
        }
        ShellState.launcherInitialSearch = `${GlobalConfig.launcher.actionPrefix}wallpaper `;
        const state = ShellState.forActive();
        if (state) {
            state.utilities = false;
            state.launcher = true;
        }
    }
}
