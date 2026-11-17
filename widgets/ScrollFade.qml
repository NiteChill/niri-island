import QtQuick
import QtQuick.Effects

import "../services"

// Edge fades of a scrolling list (Wi-Fi, Bluetooth, search): the top / bottom edge fades out when there's
// more to scroll that way, over `size` px. Two ways, picked by the island:
//  - opaque island: a gradient in the island color drawn over the list (costs nothing);
//  - blurred island (island.blur, see-through): a band in the island color would show as a dark stripe over
//    the blur, so the list itself fades out through an opacity mask. The list renders into a layer for
//    that (only while blur is on): give it  layer.enabled: fade.masked  and  layer.effect: fade.effect.
Item {
    id: fade

    // the list (a Flickable) this sits over; place this item over it (anchors.fill: the list)
    required property Flickable view
    property real size: 0
    // false = no fade at all (e.g. no results)
    property bool active: true

    readonly property bool masked: Config.island.blur
    readonly property bool fadeTop: active && !view.atYBeginning
    readonly property bool fadeBottom: active && !view.atYEnd

    // for the list's layer.effect (blurred island)
    readonly property Component effect: Component {
        MultiEffect {
            maskEnabled: true
            maskSource: mask
            // the mask's alpha as a smooth 0-1 ramp: the defaults (0, 0) show anything above 0 fully
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    // ---- opaque island: gradients over the list ----
    Rectangle {
        visible: !fade.masked && fade.fadeTop
        width: parent.width
        height: fade.size
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Config.island.color
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Config.island.color, 0)
            }
        }
    }
    Rectangle {
        visible: !fade.masked && fade.fadeBottom
        anchors.bottom: parent.bottom
        width: parent.width
        height: fade.size
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(Config.island.color, 0)
            }
            GradientStop {
                position: 1
                color: Config.island.color
            }
        }
    }

    // ---- blurred island: the mask (opaque = list shown, transparent = faded out) ----
    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: fade.masked

        Rectangle {
            id: maskTop
            width: parent.width
            height: fade.size
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: fade.fadeTop ? "transparent" : "white"
                }
                GradientStop {
                    position: 1
                    color: "white"
                }
            }
        }
        Rectangle {
            anchors.top: maskTop.bottom
            anchors.bottom: maskBottom.top
            width: parent.width
            color: "white"
        }
        Rectangle {
            id: maskBottom
            anchors.bottom: parent.bottom
            width: parent.width
            height: fade.size
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "white"
                }
                GradientStop {
                    position: 1
                    color: fade.fadeBottom ? "transparent" : "white"
                }
            }
        }
    }
}
