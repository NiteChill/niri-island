pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// Battery dropdown (under the bar's battery), calm like the macOS menu:
//  - "Battery" and the percentage on top; under it in grey, "Full in 1h 20m" while charging, "3h 10m left"
//    on battery, "Fully charged" once full (each its own minute-rounded number, Sys.batteryTimeToFull /
//    ToEmpty)
//  - "Power mode": the three modes as rows (icon, name, a blue check on the one in use); a click (or Up /
//    Down + Enter / Space) switches. The highlight springs to the row under the pointer or the keyboard's.
IslandMode {
    id: mode

    readonly property var layout: Config.battery
    readonly property var rowsLook: Config.panel.list
    launcher: Config.battery.launcher

    // the power modes, in Sys.battery.profile's names, in the order shown
    readonly property var profiles: ["powerSaver", "balanced", "performance"]
    function profileText(p) {
        return p === "powerSaver" ? Config.quickSettings.power.saverText : p === "performance" ? Config.quickSettings.power.performanceText : Config.quickSettings.power.balancedText;
    }
    function profileIcon(p) {
        return p === "powerSaver" ? Config.quickSettings.power.saverIcon : p === "performance" ? Config.quickSettings.power.performanceIcon : Config.quickSettings.power.balancedIcon;
    }

    // "Full in 1h 20m" / "3h 10m left" / "Fully charged" / nothing yet
    readonly property int estimate: Sys.battery.charging ? Sys.batteryTimeToFull : Sys.batteryTimeToEmpty
    readonly property string estimateText: {
        if (Sys.battery.full)
            return layout.fullText;
        if (estimate <= 0)
            return "";
        const minutes = Math.round(estimate / 60);
        const h = Math.floor(minutes / 60), m = minutes % 60;
        const t = h > 0 ? layout.hoursFormat.arg(h).arg(m) : layout.minutesFormat.arg(m);
        return (Sys.battery.charging ? layout.fullInText : layout.leftText).arg(t);
    }

    // keyboard: Up / Down pick a mode, Enter / Space switch to it; Escape closes (IslandMode)
    keyTarget: mode
    property int selected: Math.max(0, profiles.indexOf(Sys.battery.profile))
    property bool keyShown: false
    onActiveChanged: {
        if (active) {
            selected = Math.max(0, profiles.indexOf(Sys.battery.profile));
            keyShown = !!island && island.keyboardOpened;
        }
    }
    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onReturnPressed: pick(selected)
    Keys.onEnterPressed: pick(selected)
    Keys.onSpacePressed: pick(selected)
    // one selection for the pointer and the keys: the pointer sets it only when it moves, so with the
    // pointer resting on a row the keys take over (and the next move of the pointer takes it back)
    function move(dir) {
        if (keyShown || rows.pointerIn)
            selected = Math.max(0, Math.min(profiles.length - 1, selected + dir));
        keyShown = true;
    }
    function pick(i) {
        Sys.setPowerProfile(profiles[i]);
    }

    implicitWidth: Config.panel.width
    implicitHeight: 2 * Config.panel.padding + Config.panel.header.height + (estimateText !== "" ? layout.estimateHeight : 0) + Config.panel.listGap + rowsLook.headerHeight + profiles.length * rowsLook.rowHeight

    Item {
        id: content
        x: Config.panel.padding
        y: Config.panel.padding
        width: mode.implicitWidth - 2 * Config.panel.padding
        height: mode.implicitHeight - 2 * Config.panel.padding

        PanelHeader {
            id: header
            title: mode.layout.title
            StyledText {
                font.pixelSize: Config.panel.header.titleSize
                font.features: {
                    "tnum": 1
                }
                color: Sys.battery.charging ? Config.theme.charging : Sys.battery.low ? Config.colors.danger : palette.windowText
                text: Sys.battery.percentage + "%"
            }
        }
        StyledText {
            id: estimateLine
            visible: mode.estimateText !== ""
            anchors.top: header.bottom
            x: mode.rowsLook.rowPadding
            height: mode.layout.estimateHeight
            verticalAlignment: Text.AlignTop
            color: palette.placeholderText
            text: mode.estimateText
        }

        StyledText {
            id: modesTitle
            y: header.height + (mode.estimateText !== "" ? mode.layout.estimateHeight : 0) + Config.panel.listGap
            x: mode.rowsLook.rowPadding
            height: mode.rowsLook.headerHeight
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Config.activity.captionSize
            color: palette.placeholderText
            text: mode.layout.modesTitle
        }

        Item {
            id: rows
            anchors.top: modesTitle.bottom
            width: parent.width
            height: mode.profiles.length * mode.rowsLook.rowHeight

            // the highlight: the selection, while the pointer is over the rows or after a key (RowHighlight)
            readonly property bool pointerIn: hover.hovered
            readonly property int lit: hover.hovered || mode.keyShown ? mode.selected : -1
            MovedHover {
                id: hover
                cursorShape: Qt.PointingHandCursor
                onMoved: position => {
                    mode.keyShown = false;
                    mode.selected = Math.max(0, Math.min(mode.profiles.length - 1, Math.floor(position.y / mode.rowsLook.rowHeight)));
                }
            }
            RowHighlight {
                height: mode.rowsLook.rowHeight
                rowY: Math.max(0, rows.lit) * mode.rowsLook.rowHeight
                shown: rows.lit >= 0
            }
            Repeater {
                model: mode.profiles
                delegate: Item {
                    id: row
                    required property int index
                    required property string modelData
                    readonly property bool current: Sys.battery.profile === modelData
                    y: index * mode.rowsLook.rowHeight
                    width: rows.width
                    height: mode.rowsLook.rowHeight
                    Icon {
                        id: rowIcon
                        x: mode.rowsLook.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: mode.rowsLook.iconSize
                        height: mode.rowsLook.iconSize
                        name: mode.profileIcon(row.modelData)
                        color: row.current ? (row.modelData === "powerSaver" ? Config.theme.powerSaver : row.modelData === "performance" ? Config.colors.performance : Config.colors.accent) : palette.windowText
                    }
                    StyledText {
                        anchors.left: rowIcon.right
                        anchors.leftMargin: mode.rowsLook.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        text: mode.profileText(row.modelData)
                    }
                    Icon {
                        visible: row.current
                        anchors.right: parent.right
                        anchors.rightMargin: mode.rowsLook.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: mode.rowsLook.checkSize
                        height: mode.rowsLook.checkSize
                        name: mode.rowsLook.checkIcon
                        color: Config.colors.accent
                    }
                    TapHandler {
                        onTapped: mode.pick(row.index)
                    }
                }
            }
        }
    }
}
