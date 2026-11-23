import QtQuick

import "../services"

// A panel's title (the network, the connected device), centred, that rolls when it changes: the old text
// slides up and fades out, the new one comes up from below (panel.roll). While `animate` is false (the
// panel is closed) it just switches.
Item {
    id: title

    property string text
    property bool animate: true
    property color color: palette.windowText
    property real pixelSize: Config.panel.nameSize

    implicitHeight: label.implicitHeight
    height: implicitHeight

    property string shown: text
    // 0 = settled; the old text leaves upwards (0 -> 1), the new one comes up from below (-1 -> 0)
    property real roll: 0
    onTextChanged: {
        if (!animate) {
            rollAnim.stop();
            roll = 0;
            shown = text;
            return;
        }
        rollAnim.restart();
    }
    SequentialAnimation {
        id: rollAnim
        NumberAnimation {
            target: title
            property: "roll"
            from: 0
            to: 1
            duration: Config.panel.roll.duration / 2
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: {
                title.shown = title.text;
                title.roll = -1;
            }
        }
        NumberAnimation {
            target: title
            property: "roll"
            to: 0
            duration: Config.panel.roll.duration / 2
            easing.type: Easing.OutCubic
        }
    }

    StyledText {
        id: label
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        // a name keeps its end (what often tells two apart: "_5G")
        elide: Text.ElideMiddle
        y: -title.roll * height * Config.panel.roll.travel
        opacity: 1 - Math.abs(title.roll)
        font.pixelSize: title.pixelSize
        color: title.color
        text: title.shown
    }
}
