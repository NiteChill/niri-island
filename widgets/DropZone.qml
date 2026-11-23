import QtQuick
import QtQuick.Shapes

import "../services"

// The drop zone's look (island.drop.*): a dashed rounded outline inset in the notch, a download arrow and
// two lines of text. Live (DropMode: something is being dragged over the notch): the arrow in the accent,
// bobbing gently, the text white. Muted (the empty shelf: where things go): everything grey and still
// (island.drop.mutedOpacity).
Item {
    id: zone

    property bool muted: false
    property string text
    property string caption
    // the notch's corner, for the outline to be concentric with it
    property real outerCorner: 0

    readonly property var look: Config.island.drop

    // the arrow bobs while live and on screen
    property bool running: false
    property real bob: 0.5
    SequentialAnimation on bob {
        running: zone.running && !zone.muted
        loops: Animation.Infinite
        NumberAnimation {
            to: 1
            duration: zone.look.bobDuration / 2
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0
            duration: zone.look.bobDuration / 2
            easing.type: Easing.InOutSine
        }
    }

    Item {
        anchors.fill: parent
        opacity: zone.muted ? zone.look.mutedOpacity : 1

        Shape {
            x: zone.look.inset
            y: zone.look.inset
            width: zone.width - 2 * zone.look.inset
            height: zone.height - 2 * zone.look.inset
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Qt.alpha(palette.windowText, zone.look.fillOpacity)
                strokeColor: Qt.alpha(palette.windowText, zone.look.lineOpacity)
                strokeWidth: zone.look.lineWidth
                strokeStyle: ShapePath.DashLine
                dashPattern: [zone.look.dash, zone.look.dashGap]
                PathSvg {
                    path: Config.roundedRectPath(zone.width - 2 * zone.look.inset, zone.height - 2 * zone.look.inset, Config.inner(zone.outerCorner, zone.look.inset, zone.height - 2 * zone.look.inset), Config.island.cornerSmoothing)
                }
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: zone.look.gap
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: (zone.bob - 0.5) * zone.look.bobTravel
                width: zone.look.iconSize
                height: width
                name: zone.look.icon
                color: zone.muted ? palette.placeholderText : Config.colors.accent
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(Math.max(zoneTitle.implicitWidth, zoneCaption.implicitWidth), zone.width - 2 * zone.look.inset - 2 * zone.look.gap - zone.look.iconSize - zone.look.gap)
                StyledText {
                    id: zoneTitle
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: zone.look.titleSize
                    color: zone.muted ? palette.placeholderText : palette.windowText
                    text: zone.text
                }
                StyledText {
                    id: zoneCaption
                    visible: text !== ""
                    width: parent.width
                    elide: Text.ElideMiddle
                    font.pixelSize: zone.look.captionSize
                    color: palette.placeholderText
                    text: zone.caption
                }
            }
        }
    }
}
