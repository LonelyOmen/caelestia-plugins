pragma ComponentBehavior: Bound

import QtQuick
import qs.components.controls
import qs.services
import xlonely.astra

// Quick toggle for Astra Strike. Matches the shell's momentary toggles: same
// container colour as `settings`, only the icon colour is overridden.
IconButton {
    id: root

    fillWidth: true
    shapeMorph: true

    icon: "rocket_launch"
    isToggle: false
    isRound: true

    inactiveColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
    inactiveOnColour: Colours.palette.m3onSurfaceVariant

    onClicked: AstraStrike.toggle()
}
