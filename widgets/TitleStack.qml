import QtQuick

import "../services"

// Two lines, the Dynamic Island way: a small grey caption ("Connected", "mobile") above a white title
// (the device, the caller). Both elide to the given width (the title in the middle: it's a name). Sizes: activity.captionSize / titleSize.
Column {
    id: stack

    property string caption: ""
    property string title: ""
    property color captionColor: palette.placeholderText
    property color titleColor: palette.windowText
    // widest of the two lines, for modes that size themselves to the text
    readonly property real naturalWidth: Math.max(captionText.implicitWidth, titleText.implicitWidth)

    spacing: Config.activity.lineSpacing

    StyledText {
        id: captionText
        width: Math.min(implicitWidth, stack.width)
        visible: text !== ""
        elide: Text.ElideRight
        font.pixelSize: Config.activity.captionSize
        color: stack.captionColor
        text: stack.caption
    }
    StyledText {
        id: titleText
        width: Math.min(implicitWidth, stack.width)
        // the title is a name (device, network): cut in the middle so its end stays
        elide: Text.ElideMiddle
        font.pixelSize: Config.activity.titleSize
        color: stack.titleColor
        text: stack.title
    }
}
