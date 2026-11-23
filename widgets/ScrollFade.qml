import QtQuick

// Edge fades of a scrolling list (Wi-Fi, Bluetooth, search): the top / bottom edge fades into the surface
// (palette.window: the dropdown's card color) when there's more to scroll that way, over `size` px. A
// gradient drawn over the list: costs nothing.
Item {
    id: fade

    // the list (a Flickable) this sits over; place this item over it (anchors.fill: the list)
    required property Flickable view
    property real size: 0
    // false = no fade at all (e.g. no results)
    property bool active: true

    readonly property bool fadeTop: active && !view.atYBeginning
    readonly property bool fadeBottom: active && !view.atYEnd

    Rectangle {
        visible: fade.fadeTop
        width: parent.width
        height: fade.size
        gradient: Gradient {
            GradientStop {
                position: 0
                color: palette.window
            }
            GradientStop {
                position: 1
                color: Qt.alpha(palette.window, 0)
            }
        }
    }
    Rectangle {
        visible: fade.fadeBottom
        anchors.bottom: parent.bottom
        width: parent.width
        height: fade.size
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(palette.window, 0)
            }
            GradientStop {
                position: 1
                color: palette.window
            }
        }
    }
}
