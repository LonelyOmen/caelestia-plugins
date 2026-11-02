pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.components.containers
import xlonely.astra

// Screen-sized, fully transparent host for the Astra Strike overlay.
//
// Mirrors BadAppleOverlay's layer choices for the same reasons: Bottom sits
// above the wallpaper and visualiser but under the drawers, panels and
// desktop lyrics, and the "drawers" namespace inherits Hyprland's fade rule
// instead of the default slide.
//
// The window only exists while the game is running - an empty model destroys
// every instance - so an inactive game costs no surface, no renderer and no
// input handling at all.
Variants {
    model: AstraStrike.active ? Quickshell.screens : []

    StyledWindow {
        id: root
        required property ShellScreen modelData
        screen: modelData
        name: "drawers"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        // The game is a temporary full-screen takeover; take the keyboard
        // while it exists and give it back by destroying the window.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        // Full-surface input region: the game needs pointer aim and keys.
        mask: Region {
            width: root.width
            height: root.height
        }

        Item {
            id: stage
            anchors.fill: parent

            // Soft vignette so the play area stays legible against a busy
            // wallpaper. Sits behind the game so the HUD never gets dimmed.
            // Shape + RadialGradient is the pattern this shell already uses
            // (see StateLayer); Rectangle.gradient only accepts linear.
            Shape {
                anchors.fill: parent
                asynchronous: false

                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: "transparent"

                    startX: 0
                    startY: 0

                    PathLine {
                        x: root.width
                        y: 0
                    }
                    PathLine {
                        x: root.width
                        y: root.height
                    }
                    PathLine {
                        x: 0
                        y: root.height
                    }
                    PathLine {
                        x: 0
                        y: 0
                    }

                    fillGradient: RadialGradient {
                        centerX: root.width * 0.5
                        centerY: root.height * 0.5
                        centerRadius: Math.max(root.width, root.height) * 0.62
                        focalX: centerX
                        focalY: centerY

                        GradientStop {
                            position: 0.0
                            color: "transparent"
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(0.0, 0.0, 0.0, 0.32)
                        }
                    }
                }
            }

            AstraStrikeGame {
                anchors.fill: parent
            }
        }
    }
}
