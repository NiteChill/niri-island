pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

import "../services"
import "../island"
import "../widgets"

// Island mode (an activity, put up by Activity): a screenshot you just took. Instead of niri's "Screenshot
// captured" notification, the island holds the picture itself, like the iPhone's: a card in the
// screenshot's own proportions (screenshot.height tall, at most screenshot.maxWidth wide), island around it
// (screenshot.paddingX / paddingY), small corners scaled with it (screenshot.roundness), on purpose not
// concentric (the user's reference, 2026-11-17); the island itself rounder than usual around it
// (screenshot.islandRoundness -> cornerScale). Nothing else. It springs up from screenshot.appear.from
// once on screen.
// Click: opens it in the default image viewer (Sys.openFile, search.files.openCommand) and closes.
// Right-click: shows it in its folder (Sys.revealFile, search.files.revealCommand) and closes.
// A new screenshot takes the place of the one shown (one Activity key): it springs in again.
// Scroll up: dismisses it. Hovering holds it (like every activity).
// The size comes from the file's header (Sys.findScreenshot), read before it shows, so the island opens
// straight to the right shape.
IslandMode {
    id: mode

    readonly property var layout: Config.screenshot
    // the island rounder around the picture than the corner style (screenshot.islandRoundness)
    cornerScale: layout.islandRoundness

    // the screenshot shown { path, width, height, notification }, latched so it stays while fading out
    property var shot: null
    Connections {
        target: Activity
        function onCurrentChanged() {
            const c = Activity.current;
            if (c && c.kind === "screenshot") {
                if (mode.shot && c.data.path !== mode.shot.path && mode.hasAppeared)
                    mode.enter();
                mode.shot = c.data;
            }
        }
    }
    readonly property string source: shot ? "file://" + shot.path.split("/").map(encodeURIComponent).join("/") : ""

    // ---- size: the picture's proportions (the screen's until known) ----
    readonly property real ratio: shot && shot.width > 0 && shot.height > 0 ? shot.width / shot.height : (island && island.screenHeight > 0 ? island.screenWidth / island.screenHeight : 1)
    readonly property real tileW: Math.min(layout.maxWidth, layout.height * ratio)
    readonly property real tileH: tileW / ratio
    implicitWidth: tileW + 2 * layout.paddingX
    implicitHeight: tileH + 2 * layout.paddingY
    // a card's corner, not the island's: a share of the picture's height (screenshot.roundness), so it
    // stays the same shape whatever the picture's size (the user's choice over a corner style role)
    readonly property real corner: Math.min(tileW, tileH) * layout.roundness

    // ---- entrance: the picture springs up once it's on screen ----
    property real grow: 1
    function enter() {
        growSpring.stop();
        grow = 0;
        if (hasAppeared)
            growSpring.start();
    }
    onActiveChanged: if (active)
        enter()
    onAppeared: growSpring.start()
    SpringAnimation {
        id: growSpring
        target: mode
        property: "grow"
        to: 1
        spring: Config.spring(mode.layout.appear.spring).spring
        damping: Config.spring(mode.layout.appear.spring).damping
        epsilon: 0.001
    }

    function done() {
        Sys.dismissNotification(shot.notification);
        Activity.dismiss("screenshot");
    }
    function open() {
        if (!shot)
            return;
        Sys.openFile(shot.path);
        done();
    }
    function reveal() {
        if (!shot)
            return;
        Sys.revealFile(shot.path);
        done();
    }

    // ---- input ----
    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => button === Qt.RightButton ? mode.reveal() : mode.open()
    }
    WheelHandler {
        onWheel: event => {
            if (event.angleDelta.y > 0 && mode.shot)
                mode.done();
        }
    }

    // ---- the picture ----
    Item {
        id: tile
        // centred: a tall screenshot is narrower than the island's smallest width
        x: (mode.width - width) / 2
        y: (mode.height - height) / 2
        width: mode.tileW
        height: mode.tileH
        scale: (mode.layout.appear.from + (1 - mode.layout.appear.from) * mode.grow) * (hover.hovered ? mode.layout.hoverScale : 1)
        Behavior on scale {
            enabled: mode.grow >= 1
            NumberAnimation {
                duration: Config.motion.hoverFade
                easing.type: Easing.OutCubic
            }
        }

        Image {
            id: picture
            anchors.fill: parent
            visible: false
            source: mode.source
            // decoded at the tile's size (a screenshot can be 6400 px wide), off the main thread
            sourceSize.width: Math.ceil(mode.tileW * 2)
            sourceSize.height: Math.ceil(mode.tileH * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            mipmap: true
        }
        // still loading: a soft tile in its place
        Rectangle {
            anchors.fill: parent
            visible: picture.status !== Image.Ready
            radius: mode.corner
            color: Qt.alpha(Config.colors.text, Config.activity.badgeOpacity)
        }
        MultiEffect {
            anchors.fill: parent
            visible: picture.status === Image.Ready
            source: picture
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        Shape {
            id: mask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillColor: Config.colors.text
                PathSvg {
                    path: Config.roundedRectPath(tile.width, tile.height, mode.corner, Config.island.cornerSmoothing)
                }
            }
        }
    }
}
