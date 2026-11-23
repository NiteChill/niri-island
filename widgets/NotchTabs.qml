import QtQuick

import "../services"

// The open notch's tabs, NookNotch-style: a small black pill of its own just under the notch
// (island.tabs.*; shell.qml places it there, riding the notch's bottom as it morphs). The open section
// shows its icon and its name ("Music", "Shelf"), the other only its icon; a lit pill glides between
// them. Switching: the old name fades out at once, the widths ease to the new ones (island.tabs.resize),
// and the new name fades in once its tab has room (island.tabs.labelDelay / labelFade). Shown only while both have something (Activity.notchTabs: music, and things on the shelf) and one
// of them is open; a click switches (Tab too, from either).
Item {
    id: tabs

    readonly property var look: Config.island.tabs
    readonly property var names: ["media", "shelf"]
    readonly property var icons: [look.playerIcon, look.shelfIcon]
    readonly property var labels: [look.playerLabel, look.shelfLabel]
    readonly property int index: Activity.panel === "shelf" ? 1 : 0
    readonly property bool shown: Activity.notchTabs && Activity.panelShown && names.indexOf(Activity.panel) >= 0

    // each item's width: the open one holds its name too
    function itemWidth(i) {
        return i === index ? look.itemPadding * 2 + look.iconSize + look.labelGap + labelSizes[i] : look.itemWidth;
    }
    property var labelSizes: [0, 0]
    readonly property real contentWidth: itemWidth(0) + itemWidth(1)

    width: contentWidth + 2 * look.padding
    height: look.height
    Behavior on width {
        NumberAnimation {
            duration: tabs.look.resize
            easing.type: Easing.InOutCubic
        }
    }
    // in: it fades in and comes down from under the notch; out: the other way
    property real presence: shown ? 1 : 0
    Behavior on presence {
        NumberAnimation {
            duration: Config.motion.colorFade
            easing.type: Easing.OutCubic
        }
    }
    opacity: presence
    visible: presence > 0
    transform: Translate {
        y: (tabs.presence - 1) * tabs.look.drop
    }

    palette.windowText: Config.colors.text

    Rectangle {
        anchors.fill: parent
        radius: Config.corner("pill", height)
        color: Config.island.color
    }
    // the open one: a lit pill that springs to it and takes its width
    Rectangle {
        x: tabs.look.padding + (tabs.index === 0 ? 0 : tabs.itemWidth(0))
        y: tabs.look.padding
        width: tabs.itemWidth(tabs.index)
        height: tabs.height - 2 * tabs.look.padding
        radius: Config.corner("pill", height)
        color: Qt.alpha(palette.windowText, tabs.look.selectedOpacity)
        Behavior on x {
            NumberAnimation {
                duration: tabs.look.resize
                easing.type: Easing.InOutCubic
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: tabs.look.resize
                easing.type: Easing.InOutCubic
            }
        }
    }
    Row {
        x: tabs.look.padding
        height: parent.height
        Repeater {
            model: tabs.names.length
            delegate: Item {
                id: slot
                required property int index
                readonly property bool open: index === tabs.index
                width: tabs.itemWidth(index)
                height: tabs.height
                clip: true
                Behavior on width {
                    NumberAnimation {
                        duration: tabs.look.resize
                        easing.type: Easing.InOutCubic
                    }
                }
                Row {
                    // the icon slides from the middle to the left edge as the tab opens (with the width)
                    x: slot.open ? tabs.look.itemPadding : (tabs.look.itemWidth - tabs.look.iconSize) / 2
                    Behavior on x {
                        NumberAnimation {
                            duration: tabs.look.resize
                            easing.type: Easing.InOutCubic
                        }
                    }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: tabs.look.labelGap
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: tabs.look.iconSize
                        height: width
                        name: tabs.icons[slot.index]
                        color: palette.windowText
                        opacity: slot.open || slotHover.hovered ? 1 : tabs.look.idleOpacity
                    }
                    StyledText {
                        id: label
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: tabs.look.labelSize
                        text: tabs.labels[slot.index]
                        // driven by hand (a Behavior's timing can't depend on the change it animates)
                        opacity: slot.open ? 1 : 0
                        Connections {
                            target: slot
                            function onOpenChanged() {
                                labelIn.stop();
                                labelOut.stop();
                                if (slot.open)
                                    labelIn.start();
                                else
                                    labelOut.start();
                            }
                        }
                        SequentialAnimation {
                            id: labelIn
                            PropertyAction {
                                target: label
                                property: "opacity"
                                value: 0
                            }
                            PauseAnimation {
                                duration: tabs.look.labelDelay
                            }
                            NumberAnimation {
                                target: label
                                property: "opacity"
                                to: 1
                                duration: tabs.look.labelFade
                                easing.type: Easing.OutCubic
                            }
                        }
                        NumberAnimation {
                            id: labelOut
                            target: label
                            property: "opacity"
                            to: 0
                            duration: tabs.look.labelFade / 2
                            easing.type: Easing.OutCubic
                        }
                        Component.onCompleted: tabs.measure(slot.index, implicitWidth)
                        onImplicitWidthChanged: tabs.measure(slot.index, implicitWidth)
                    }
                }
                HoverHandler {
                    id: slotHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: Activity.open(tabs.names[slot.index])
                }
            }
        }
    }
    function measure(i, w) {
        if (labelSizes[i] === w)
            return;
        const next = labelSizes.slice();
        next[i] = w;
        labelSizes = next;
    }
}
