import QtQuick
import QtQuick.Effects

// Edge fades of a scrolling list (Wi-Fi, Bluetooth, search): the top / bottom edge fades out when there's
// more to scroll that way, over `size` px. Two ways, by the surface (palette.window):
//  - opaque (the notch's search): a gradient in the surface's color drawn over the list; costs nothing
//  - see-through (the frosted dropdowns, panel.blur): the list itself fades, through an alpha mask on it
//    (MultiEffect, only while an edge fades). A gradient in a see-through color stacked on the card's own
//    and read as a dark band (2026-11-25)
Item {
    id: fade

    // the list (a Flickable) this sits over; place this item over it (anchors.fill: the list)
    required property Flickable view
    property real size: 0
    // false = no fade at all (e.g. no results)
    property bool active: true

    readonly property bool fadeTop: active && !view.atYBeginning
    readonly property bool fadeBottom: active && !view.atYEnd
    readonly property bool masking: palette.window.a < 1

    // ---- opaque surface: gradients over the list ----
    Rectangle {
        visible: !fade.masking && fade.fadeTop
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
        visible: !fade.masking && fade.fadeBottom
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

    // ---- see-through surface: the list masked (opaque in the middle, clear at a fading edge) ----
    Item {
        id: mask
        width: fade.view.width
        height: fade.view.height
        visible: false
        // its texture exists only while it's used
        layer.enabled: fade.masking && (fade.fadeTop || fade.fadeBottom)
        Rectangle {
            width: parent.width
            height: fade.size
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: fade.fadeTop ? "transparent" : "black"
                }
                GradientStop {
                    position: 1
                    color: "black"
                }
            }
        }
        Rectangle {
            y: fade.size
            width: parent.width
            height: Math.max(0, parent.height - 2 * fade.size)
            color: "black"
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: fade.size
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "black"
                }
                GradientStop {
                    position: 1
                    color: fade.fadeBottom ? "transparent" : "black"
                }
            }
        }
    }
    Component {
        id: maskEffect
        // threshold 0.5 + spread 1: a smooth ramp along the gradient (see CLAUDE.md, Lists)
        MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }
    Binding {
        target: fade.view.layer
        property: "enabled"
        value: fade.masking && (fade.fadeTop || fade.fadeBottom)
    }
    Component.onCompleted: view.layer.effect = maskEffect
}
