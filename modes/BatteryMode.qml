pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// Battery panel, an instrument: one strong number, one bold scale, one control (the power modes are
// meant for a quick settings panel, not here).
//  - the level on an ArcGauge (shared with the time panel): a thick curved band filled in the accent, chunky
//    ticks cut into it, every 5 % by default
//  - on top, centred: the percentage, the real level (RollingNumber: a short, subtle roll when it
//    changes), a small grey %; in grey under it, "Full in 1h 20m" while charging, "3h 10m left" otherwise
//  - under the bar, centred, one labelled button: "Power saver" (solid in its yellow when on, Space toggles)
// Opening sweeps the fill up from 0 (ArcGauge).
// The accent follows Sys.battery.color: charging > power saver > low > performance > balanced.
IslandMode {
    id: mode

    readonly property var look: Config.battery.gauge

    // animated copy of the battery color (Sys.battery.color) so every part fades together
    property color tint: Sys.battery.color
    Behavior on tint {
        ColorAnimation {
            duration: Config.motion.colorFade
        }
    }

    trOverride: Config.battery.transition
    launcher: Config.battery.launcher
    implicitWidth: Config.panel.width
    // a known estimate under the number: "Full in 1h 20m" while charging, "3h 10m left" on battery (the panel
    // grows by that line)
    readonly property int estimate: Sys.battery.charging ? Sys.batteryTimeToFull : Sys.batteryTimeToEmpty
    readonly property bool fullInShown: estimate > 0
    readonly property string fullInText: {
        const minutes = Math.round(estimate / 60);
        const h = Math.floor(minutes / 60), m = minutes % 60;
        const t = h > 0 ? look.fullIn.hoursFormat.arg(h).arg(m) : look.fullIn.minutesFormat.arg(m);
        return (Sys.battery.charging ? look.fullIn.text : look.fullIn.leftText).arg(t);
    }
    readonly property real fullInRoom: fullInShown ? Config.panel.caption.gap + fullIn.implicitHeight : 0
    // from the content: the number (+ the estimate), the bar, the button
    implicitHeight: 2 * Config.panel.padding + percent.height + fullInRoom + Config.panel.arc.gapAbove + gauge.implicitHeight + Config.panel.arc.gapBelow + Config.panel.button.height

    // keyboard: Space toggles power saver; Escape closes the panel (handled by IslandMode)
    keyTarget: mode
    Keys.onSpacePressed: mode.toggleSaver()

    readonly property bool saverOn: Sys.battery.profile === "powerSaver"
    function toggleSaver() {
        Sys.setPowerProfile(saverOn ? "balanced" : "powerSaver");
    }

    // fixed-size content box, pinned to the top so nothing slides while the island grows
    Item {
        id: content
        x: Config.panel.padding
        y: Config.panel.padding
        width: mode.implicitWidth - 2 * Config.panel.padding
        height: mode.implicitHeight - 2 * Config.panel.padding

        // ---- the percentage, centred on top (the real level: it rolls only when the level changes) ----
        Item {
            id: percent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: digits.width + mode.look.number.unitGap + unit.width
            height: digits.height
            RollingNumber {
                id: digits
                value: Sys.battery.percentage
                // a short roll from the old number to the new one
                Behavior on value {
                    NumberAnimation {
                        duration: Config.panel.number.rollDuration
                        easing.type: Easing.OutCubic
                    }
                }
                pixelSize: Config.panel.number.size
                weight: Config.panel.number.weight
                fade: Config.panel.number.rollFade
                travel: Config.panel.number.rollTravel
            }
            StyledText {
                id: unit
                anchors.left: digits.right
                anchors.leftMargin: mode.look.number.unitGap
                anchors.baseline: digits.baseline
                font.pixelSize: Config.panel.number.smallSize
                font.weight: Config.panel.number.weight
                color: Config.colors.secondary
                text: "%"
            }
        }

        // ---- under the number, in grey: "Full in 1h 20m" / "3h 10m left" ----
        StyledText {
            id: fullIn
            visible: mode.fullInShown
            anchors.top: percent.bottom
            anchors.topMargin: Config.panel.caption.gap
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Config.panel.caption.size
            color: Config.colors.secondary
            text: mode.fullInText
        }

        // ---- the bar (ArcGauge, the look shared with the time panel) ----
        ArcGauge {
            id: gauge
            anchors.top: mode.fullInShown ? fullIn.bottom : percent.bottom
            anchors.topMargin: Config.panel.arc.gapAbove
            width: parent.width
            value: Sys.battery.percentage / 100
            tint: mode.tint
            active: mode.active
            ticks: mode.look.ticks.count
            majorEvery: mode.look.ticks.majorEvery
        }

        // ---- power saver, centred under the bar: a labelled soft / solid capsule (PillButton) ----
        PillButton {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            icon: mode.look.saver.icon
            text: mode.look.saver.text
            tint: mode.saverOn ? Config.colors.powerSaver : Config.colors.text
            solid: mode.saverOn
            onClicked: mode.toggleSaver()
        }
    }
}
