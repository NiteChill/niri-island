import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

import "../services"

// The playing track's cover (Sys.media.artUrl) as a rounded tile (the corner style's `tile` corner, smoothed like the island's); without
// one, a soft tile with a music note. Size it from outside; `iconSize` = the note's size.
// Used by the media panel and the "now playing" alert (NowPlayingMode).
Item {
    id: art

    property real iconSize: width / 2

    Image {
        id: cover
        anchors.fill: parent
        readonly property bool ready: status === Image.Ready && Sys.media.artUrl !== ""
        visible: false
        source: Sys.media.artUrl
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        mipmap: true
    }
    // rounded through a mask (smooth edge: threshold 0.5, spread 1)
    MultiEffect {
        anchors.fill: parent
        visible: cover.ready
        source: cover
        maskEnabled: true
        maskSource: coverMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
    // smoothed corners, like the island's (island.cornerSmoothing)
    Shape {
        id: coverMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillColor: Config.colors.text
            PathSvg {
                path: Config.roundedRectPath(art.width, art.height, Config.corner("tile", art.height), Config.island.cornerSmoothing)
            }
        }
    }
    // no cover: a soft tile with a note
    Rectangle {
        anchors.fill: parent
        visible: !cover.ready
        radius: Config.corner("tile", height)
        color: Config.colors.text
        opacity: Config.activity.badgeOpacity
    }
    Icon {
        anchors.centerIn: parent
        visible: !cover.ready
        width: art.iconSize
        height: art.iconSize
        name: Config.media.art.icon
        color: Config.colors.text
    }
}
