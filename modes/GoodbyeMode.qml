import QtQuick
import QtQuick.Shapes

import "../services"
import "../island"

// Island mode (an activity, put up by Activity when the computer powers off or restarts): "bye bye"
// written by hand, like the iOS "hello": one round stroke drawn along the handwriting
// (assets/handwriting, goodbye.handwriting), then a short hold, then Sys lets the system go down.
// `qs ipc call island goodbye` plays it without shutting down (a preview).
// Sized by the writing: goodbye.size tall, as wide as its proportions say, plus the padding.
IslandMode {
    id: mode

    readonly property var look: Config.goodbye
    readonly property var art: Config.handwriting(look.handwriting)
    // viewBox units -> px
    readonly property real k: art && art.h > 0 ? look.size / art.h : 0
    readonly property real writingWidth: art ? art.w * k : 0

    implicitWidth: writingWidth + 2 * look.paddingX
    implicitHeight: look.size + 2 * look.paddingY

    // how much of the handwriting is drawn, 0 - 1
    property real written: 0
    onActiveChanged: {
        write.stop();
        written = 0;
        if (active)
            write.start();
    }
    SequentialAnimation {
        id: write
        // the island first takes its shape (and the launcher, if it started this, closes)
        PauseAnimation {
            duration: mode.look.delay
        }
        NumberAnimation {
            target: mode
            property: "written"
            from: 0
            to: 1
            duration: mode.look.duration
            easing.type: Easing.InOutSine
        }
        PauseAnimation {
            duration: mode.look.hold
        }
        // really shutting down: let the system go (the island keeps saying bye bye until the screen goes
        // dark); a preview (qs ipc call island goodbye): give the island back
        ScriptAction {
            script: Sys.shuttingDown ? Sys.releaseShutdown() : Activity.dismiss("goodbye")
        }
    }

    Shape {
        x: (mode.width - mode.writingWidth) / 2
        y: (mode.height - mode.look.size) / 2
        width: mode.writingWidth
        height: mode.look.size
        visible: mode.written > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Config.colors.text
            strokeWidth: mode.look.strokeWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            // viewBox -> the writing's box
            scale: Qt.size(mode.k, mode.k)
            trim.end: mode.written
            PathSvg {
                path: mode.art ? mode.art.path : ""
            }
        }
        // PathSvg has no offset: shift the shape instead
        transform: Translate {
            x: mode.art ? -mode.art.x * mode.k : 0
            y: mode.art ? -mode.art.y * mode.k : 0
        }
    }
}
