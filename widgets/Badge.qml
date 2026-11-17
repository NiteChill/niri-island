import QtQuick

import "../services"

// Round (or capsule) badge holding a glyph, the Dynamic Island way: sized and placed by the mode so it
// sits concentric with the island's rounded end (activity.inset from the edge). Two looks:
//  - soft (default): the tint at activity.badgeOpacity behind a glyph in the tint
//  - solid: filled with the tint, glyph in `glyphColor` (Silent-style "this is on" state): by default white
//    on a dark or saturated tint, black on a light one (Config.onColor)
// Optional hover + click (hover brightens the soft fill). Optional `label`: the badge widens into a
// capsule, the glyph then the word (activity.badgeLabel.*), e.g. a "Copied" tag.
Rectangle {
    id: badge

    // API
    property string icon: ""
    property color tint: Config.colors.text
    property bool solid: false
    property color glyphColor: Config.onColor(tint)
    property real glyphSize: Config.activity.glyphSize
    property real glyphRotation: 0
    property bool clickable: false
    property string label: ""
    signal clicked

    // corner: concentric with what it sits in (see Config.inner); default: an activity badge,
    // activity.inset inside the resting island
    property real outerCorner: Config.restCorner
    property real inset: Config.activity.inset

    readonly property var labelLook: Config.activity.badgeLabel
    width: label === "" ? height : labelLook.padding + glyphSize + labelLook.gap + labelText.implicitWidth + labelLook.padding
    radius: Config.inner(outerCorner, inset, height)
    color: solid ? tint : Qt.alpha(tint, clickable && hover.hovered ? Config.activity.badgeHoverOpacity : Config.activity.badgeOpacity)
    Behavior on color {
        ColorAnimation {
            duration: Config.motion.colorFade
        }
    }
    scale: tap.pressed ? Config.motion.pressScale : 1
    Behavior on scale {
        NumberAnimation {
            duration: Config.motion.pressDuration
        }
    }

    Icon {
        id: glyph
        x: badge.label === "" ? (badge.width - width) / 2 : badge.labelLook.padding
        anchors.verticalCenter: parent.verticalCenter
        width: badge.glyphSize
        height: badge.glyphSize
        rotation: badge.glyphRotation
        name: badge.icon
        color: badge.solid ? badge.glyphColor : badge.tint
    }

    StyledText {
        id: labelText
        visible: badge.label !== ""
        x: glyph.x + glyph.width + badge.labelLook.gap
        anchors.verticalCenter: parent.verticalCenter
        text: badge.label
        font.pixelSize: badge.labelLook.size
        color: badge.solid ? badge.glyphColor : badge.tint
    }

    HoverHandler {
        id: hover
        enabled: badge.clickable
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: tap
        enabled: badge.clickable
        onTapped: badge.clicked()
    }
}
