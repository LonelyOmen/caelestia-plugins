pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import xlonely.astra

// Presentation layer for Astra Strike.
//
// Everything here is a view over the Rust engine's snapshot: no gameplay
// state, no timers driving simulation, no collision maths. Each frame we walk
// one numeric cursor and push values into pre-created items.
//
// Cost model, chosen for integrated graphics:
//   * entity pools are created once and reused - no per-frame allocations
//   * moving entities only take transform writes (x/y/rotation/scale/opacity),
//     which the scene graph handles as cheap node updates
//   * asteroid outlines are authored in a fixed 100u box and scaled, so a
//     size change never rebuilds geometry
//   * hidden entities are `visible: false` and get culled entirely
Item {
    id: root

    // --- pool sizes (must match the engine's) --------------------------------
    readonly property int nAst: 48
    readonly property int nBul: 16
    readonly property int nPar: 180

    // Asteroid outlines are authored inside this box and scaled to the real
    // radius. The box is the asteroid's *diameter*, hence scale = r*2/refBox.
    readonly property real refBox: 100.0
    readonly property real halfBox: refBox / 2.0

    // Accents stay inside the existing palette: structure in primary, debris
    // in tertiary, faint marks in outline. Nothing neon, no new colours.
    readonly property color colStructure: Colours.palette.m3primary
    readonly property color colDebris: Colours.palette.m3tertiary
    readonly property color colPale: Colours.palette.m3outline
    // onBackground is the one palette colour bright enough to read over both
    // the dark sky and the bright accretion disk in a space wallpaper.
    readonly property color colBright: Colours.palette.m3onBackground

    // --- view state ----------------------------------------------------------
    property int score: 0
    property int lives: 3
    property bool over: false
    property bool hintVisible: true

    focus: true

    Component.onCompleted: {
        root.forceActiveFocus();
        hintFade.restart();
    }

    // =========================================================================
    // Engine process
    // =========================================================================

    Process {
        id: proc

        // Tied to the singleton: going inactive tears the process down, and
        // its stdin EOF is what makes the engine exit. No daemon, no leak.
        running: AstraStrike.active
        command: ["astra-strike"]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => root.applyFrame(line)
        }

        onStarted: root.sendSize()

        onExited: (exitCode, exitStatus) => {
            // If the engine dies on its own (missing binary, crash), do not
            // leave a frozen frame on screen - hand the desktop back.
            if (AstraStrike.active)
                AstraStrike.stop();
        }
    }

    // =========================================================================
    // Wire protocol
    // =========================================================================

    function send(cmd): void {
        if (proc.running)
            proc.write(cmd + "\n");
    }

    function sendSize(): void {
        if (root.width > 0 && root.height > 0)
            root.send("c " + Math.round(root.width) + " " + Math.round(root.height));
    }

    onWidthChanged: Qt.callLater(root.sendSize)
    onHeightChanged: Qt.callLater(root.sendSize)

    // Rust accepts both WASD and arrow aliases; we normalise here so the
    // engine only ever sees its canonical names.
    function keyName(key): string {
        switch (key) {
        case Qt.Key_W:
        case Qt.Key_Up:
            return "w";
        case Qt.Key_S:
        case Qt.Key_Down:
            return "s";
        case Qt.Key_A:
        case Qt.Key_Left:
            return "a";
        case Qt.Key_D:
        case Qt.Key_Right:
            return "d";
        case Qt.Key_Space:
            return "space";
        default:
            return "";
        }
    }

    // =========================================================================
    // Frame application
    // =========================================================================

    // Wire format (see astra-strike/src/frame.rs):
    //   F score lives phase flash shakeX shakeY
    //     shipX shipY shipRotDeg thrust shipAlpha shipAlive
    //     nAst nBul nPart
    //     [x y rotDeg radius tier]*  [x y vx vy]*  [x y size lifeFrac variant]*
    function applyFrame(line): void {
        if (line.length < 5 || line.charCodeAt(0) !== 70) // 'F'
            return;

        const f = line.split(" ");
        let i = 1;

        root.score = +f[i++];
        root.lives = +f[i++];
        root.over = +f[i++] === 1;
        AstraStrike.score = root.score;
        AstraStrike.gameOver = root.over;

        // Engine already decays these; we only present them.
        flash.opacity = +f[i++] * 0.30;
        world.x = +f[i++];
        world.y = +f[i++];

        const sx = +f[i++];
        const sy = +f[i++];
        const srot = +f[i++];
        const thrust = +f[i++] === 1;
        const salpha = +f[i++];
        const salive = +f[i++] === 1;

        const nA = +f[i++];
        const nB = +f[i++];
        const nP = +f[i++];

        // The wire carries only live entities, never pool-sized padding. If a
        // line is truncated or the counts look wrong, drop the whole frame:
        // a NaN coordinate renders as "nothing" and is miserable to debug.
        if (!(nA >= 0 && nA <= root.nAst && nB >= 0 && nB <= root.nBul && nP >= 0 && nP <= root.nPar))
            return;

        // --- ship (one item, transform only) ---------------------------------
        ship.visible = salive;
        if (salive) {
            ship.x = sx - ship.width * 0.5;
            ship.y = sy - ship.height * 0.5;
            ship.rotation = srot;
            ship.opacity = salpha;
            plume.visible = thrust;
        }

        // --- asteroids -------------------------------------------------------
        let k = i;
        for (let a = 0; a < nA; a++) {
            const it = astRepeater.itemAt(a);
            const x = +f[k++];
            const y = +f[k++];
            const rot = +f[k++];
            const r = +f[k++];
            const tier = +f[k++];
            if (!it)
                continue;
            it.x = x - root.halfBox;
            it.y = y - root.halfBox;
            it.rotation = rot;
            it.scale = r * 2.0 / root.refBox;
            // Larger rocks read heavier; shards stay faint.
            it.opacity = tier === 0 ? 0.50 : (tier === 1 ? 0.72 : 0.92);
            it.visible = true;
        }
        for (let a = nA; a < root.nAst; a++) {
            const it = astRepeater.itemAt(a);
            if (it)
                it.visible = false;
        }

        // --- bullets (stretched along travel) --------------------------------
        for (let b = 0; b < nB; b++) {
            const it = bulRepeater.itemAt(b);
            const x = +f[k++];
            const y = +f[k++];
            const vx = +f[k++];
            const vy = +f[k++];
            if (!it)
                continue;
            it.x = x - it.width * 0.5;
            it.y = y - it.height * 0.5;
            it.rotation = Math.atan2(vy, vx) * 180.0 / Math.PI;
            it.visible = true;
        }
        for (let b = nB; b < root.nBul; b++) {
            const it = bulRepeater.itemAt(b);
            if (it)
                it.visible = false;
        }

        // --- particles -------------------------------------------------------
        for (let p = 0; p < nP; p++) {
            const it = parRepeater.itemAt(p);
            const x = +f[k++];
            const y = +f[k++];
            const sz = +f[k++];
            const life = +f[k++];
            const variant = +f[k++];
            if (!it)
                continue;
            const s = sz * 2.4 + 1.5;
            it.x = x - s * 0.5;
            it.y = y - s * 0.5;
            it.width = s;
            it.height = s;
            // life arrives as a 0..1 fraction: fade out over the tail.
            it.opacity = life * 0.9;
            it.color = variant === 0 ? root.colStructure : (variant === 1 ? root.colDebris : root.colBright);
            it.visible = true;
        }
        for (let p = nP; p < root.nPar; p++) {
            const it = parRepeater.itemAt(p);
            if (it)
                it.visible = false;
        }
    }

    // =========================================================================
    // Input
    // =========================================================================

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            AstraStrike.stop();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_R) {
            root.send("r");
            event.accepted = true;
            return;
        }
        // Held keys are already latched engine-side; auto-repeat is pure
        // pipe noise.
        if (event.isAutoRepeat) {
            event.accepted = true;
            return;
        }
        const k = root.keyName(event.key);
        if (k.length > 0) {
            root.send("k " + k + " 1");
            event.accepted = true;
        }
    }

    Keys.onReleased: event => {
        const k = root.keyName(event.key);
        if (k.length > 0) {
            root.send("k " + k + " 0");
            event.accepted = true;
        }
    }

    MouseArea {
        id: aim
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor

        onPositionChanged: mouse => {
            // Rounding doubles as a cheap dedupe: sub-pixel jitter never
            // reaches the pipe.
            root.send("m " + Math.round(mouse.x) + " " + Math.round(mouse.y));
        }
        onPressed: mouse => {
            root.forceActiveFocus();
            root.send("f 1");
        }
        onReleased: root.send("f 0")
    }

    // =========================================================================
    // Rendering
    // =========================================================================

    // Everything below shakes together; nothing outside this item moves, so
    // the compositor and the rest of the desktop stay perfectly still.
    Item {
        id: world
        anchors.fill: parent

        // --- ship ------------------------------------------------------------
        Item {
            id: ship
            width: 36
            height: 36
            visible: false
            opacity: 1.0
            transformOrigin: Item.Center

            Shape {
                anchors.fill: parent
                asynchronous: false

                ShapePath {
                    strokeWidth: 1.8
                    strokeColor: root.colStructure
                    fillColor: Qt.alpha(root.colStructure, 0.10)
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    // Nose at +x, matching the engine's rotation convention.
                    startX: 32
                    startY: 18
                    PathLine {
                        x: 4
                        y: 3
                    }
                    PathLine {
                        x: 12
                        y: 18
                    }
                    PathLine {
                        x: 4
                        y: 33
                    }
                    PathLine {
                        x: 32
                        y: 18
                    }
                }
            }

            // Exhaust: a short tapered mark behind the hull.
            Rectangle {
                id: plume
                x: -6
                y: 17
                width: 12
                height: 2
                radius: 1
                rotation: 0
                color: root.colDebris
                opacity: 0.7
                visible: false
            }
        }

        // --- asteroids -------------------------------------------------------
        Repeater {
            id: astRepeater
            model: root.nAst

            delegate: Shape {
                id: rock
                width: root.refBox
                height: root.refBox
                // Scaling/rotating about the centre keeps x,y as the body's
                // true position regardless of size.
                transformOrigin: Item.Center
                asynchronous: false
                visible: false
                opacity: 0

                ShapePath {
                    // Authored stroke is divided back out of the scale so the
                    // on-screen line weight stays constant from shard to
                    // boulder.
                    strokeWidth: 1.7 / Math.max(rock.scale, 0.01)
                    strokeColor: root.colStructure
                    fillColor: Qt.alpha(root.colStructure, 0.06)
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    startX: 50
                    startY: 0
                    PathLine {
                        x: 92
                        y: 26
                    }
                    PathLine {
                        x: 100
                        y: 70
                    }
                    PathLine {
                        x: 58
                        y: 100
                    }
                    PathLine {
                        x: 12
                        y: 88
                    }
                    PathLine {
                        x: 0
                        y: 44
                    }
                    PathLine {
                        x: 22
                        y: 12
                    }
                    PathLine {
                        x: 50
                        y: 0
                    }
                }
            }
        }

        // --- bullets ---------------------------------------------------------
        Repeater {
            id: bulRepeater
            model: root.nBul

            // A bolt is a near-white core inside a soft themed halo. The core
            // has to cut across a busy space wallpaper, so it uses onBackground
            // rather than the mid-grey outline, which vanishes on dark scenes.
            delegate: Item {
                id: bolt
                width: 24
                height: 10
                opacity: 0.95
                visible: false

                Rectangle {
                    anchors.centerIn: parent
                    width: 24
                    height: 9
                    radius: 4.5
                    color: Qt.rgba(root.colDebris.r, root.colDebris.g, root.colDebris.b, 0.30)
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 18
                    height: 3.5
                    radius: 1.75
                    antialiasing: true
                    color: root.colBright
                }
            }
        }

        // --- particles -------------------------------------------------------
        Repeater {
            id: parRepeater
            model: root.nPar

            delegate: Rectangle {
                width: 3
                height: 3
                radius: 1.5
                antialiasing: true
                color: root.colDebris
                opacity: 0
                visible: false
            }
        }

        // --- impact flash ----------------------------------------------------
        Rectangle {
            id: flash
            anchors.fill: parent
            color: Colours.palette.m3onBackground
            opacity: 0
            visible: opacity > 0.001
        }
    }

    // =========================================================================
    // HUD
    // =========================================================================

    Row {
        id: livesRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small
        z: 10
        opacity: root.over ? 0.35 : 0.75

        Repeater {
            model: Math.max(0, root.lives)

            delegate: Rectangle {
                width: 6
                height: 6
                radius: 3
                color: root.colStructure
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    StyledText {
        id: scoreText
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        z: 10
        text: String(root.score).padStart(6, "0")
        color: root.colPale
        font: Tokens.font.mono.builders.small.weight(Font.Medium).build()
        opacity: 0.8
    }

    // One-time control reminder, then it gets out of the way.
    Column {
        id: hint
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 40
        spacing: Tokens.spacing.small
        z: 10
        opacity: root.hintVisible && !root.over ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("WASD or mouse to steer - Space to fire - Esc to exit")
            color: root.colPale
            font: Tokens.font.body.small
            opacity: 0.7
        }

        Timer {
            id: hintFade
            interval: 5000
            onTriggered: root.hintVisible = false
        }
    }

    Column {
        id: overPanel
        anchors.centerIn: parent
        spacing: Tokens.spacing.medium
        z: 10
        visible: root.over
        opacity: root.over ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("A S T R A   S T R I K E")
            color: root.colStructure
            font: Tokens.font.title.builders.medium.weight(Font.Bold).build()
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Final score %1").arg(String(root.score).padStart(6, "0"))
            color: root.colPale
            font: Tokens.font.mono.builders.small.build()
            opacity: 0.8
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("R to retry - Esc to return to the desktop")
            color: root.colPale
            font: Tokens.font.body.small
            opacity: 0.6
        }
    }
}
