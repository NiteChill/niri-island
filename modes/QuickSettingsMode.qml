pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

import "../services"
import "../island"
import "../widgets"

// Quick settings dropdown (the bar's quick settings icon, Mod+S = `qs ipc call island toggle quickSettings`,
// or the launcher):
//  - one centred row of round switches (QuickToggle: the activity badges' look, solid in the accent when on,
//    one grey word under each, the state): Wi-Fi, Bluetooth, Focus (do not disturb), microphone (solid blue
//    = live, crossed out when muted), power mode (MenuBadge: the badge morphs into a menu of saver /
//    balanced / performance, the rest of the dropdown blurred behind it; Escape or a click elsewhere puts
//    it away). The word under Wi-Fi / Bluetooth opens their dropdown
//  - brightness and volume as the pop-ups' rows (widgets/LevelRow), the icon at the left (the speaker
//    mutes), the value in grey at the right. Brightness only with a backlight.
//  - the sound output: where the sound goes, a click unfolds the outputs to pick another (Sys.audioOutputs)
// Fully usable from the keyboard (see "keyboard" below). Settings: quickSettings.* (its own padding: more
// air than the other dropdowns around a row of small things), panel.* (width).
IslandMode {
    id: mode

    readonly property var layout: Config.quickSettings
    launcher: Config.quickSettings.launcher
    trOverride: Config.quickSettings.transition
    keyTarget: mode
    // Escape closes the power menu first
    escapeCloses: !power.open
    onEscaped: power.close()
    onActiveChanged: {
        if (!active)
            return;
        keySpot = 0;
        lastSwitch = 0;
        // opened from the keyboard (launcher, shortcut): the first switch is selected right away
        keyShown = !!island && island.keyboardOpened;
    }
    // reset once fully gone: while it animates out the menu and the highlight stay as they were
    onOnScreenChanged: {
        if (onScreen)
            return;
        power.close();
        keyShown = false;
        outputsOpen = false;
    }

    // ---- the sound output, under the volume: a click unfolds the outputs ----
    property bool outputsOpen: false
    readonly property var outputs: Sys.audioOutputs
    readonly property bool outputsShown: outputs.length > 0
    readonly property real outputsHeight: !outputsShown ? 0 : layout.outputs.gapAbove + layout.outputs.rowHeight + (outputsOpen ? outputs.length * layout.outputs.rowHeight : 0)

    // ---- keyboard: everything works without the mouse ----
    // One spot has the focus: a switch's tile (badge + word) on the top row, or the brightness / volume row,
    // shown by one grey highlight that springs from spot to spot (the Wi-Fi / Bluetooth lists' highlight).
    // Opened from the keyboard, the first switch is selected at once; opened with the mouse, the focus
    // shows from the first arrow or Tab.
    //   Left / Right: the next switch; on a level row, the level (bumps at the ends)
    //   Up / Down: between the switches and the level rows (back up to the switch you came from)
    //   Tab / Shift+Tab: every spot in order
    //   Space: toggle the switch (the volume row: mute); Enter: the same, except Wi-Fi / Bluetooth open
    //   their panel and the power switch opens its menu
    //   The sound output: its line is a spot (Space / Enter unfold the outputs, the focus going to the one in
    //   use; again on the line folds them), then each output while unfolded (Space / Enter pick it)
    //   In the power menu: Up / Down move, Space / Enter pick, Escape closes it
    readonly property var switchSpots: ["wifi", "bluetooth", "focus", "mic", "power"]
    readonly property var levelSpots: Sys.brightness.ready ? ["brightness", "volume"] : ["volume"]
    readonly property var spots: switchSpots.concat(levelSpots, outputsShown ? ["output"] : [], outputsOpen ? outputs.map((o, i) => "output:" + i) : [])
    readonly property int outputSpot: switchSpots.length + levelSpots.length
    // folding the outputs with the focus on one of them puts it back on the line
    onOutputsOpenChanged: if (!outputsOpen && keySpot > outputSpot)
        keySpot = outputSpot
    property int keySpot: 0
    property bool keyShown: false
    property int lastSwitch: 0
    readonly property string spot: keyShown ? spots[Math.min(keySpot, spots.length - 1)] : ""
    function goTo(i) {
        keySpot = Math.max(0, Math.min(spots.length - 1, i));
        if (keySpot < switchSpots.length)
            lastSwitch = keySpot;
    }
    function switchItem(name) {
        return name === "wifi" ? wifiToggle : name === "bluetooth" ? bluetoothToggle : name === "focus" ? focusToggle : name === "mic" ? micToggle : null;
    }
    function nudge(kind, dir) {
        const moved = kind === "volume" ? Sys.changeVolume(dir) : Sys.changeBrightness(dir);
        if (!moved)
            Activity.bumped(kind, dir);
    }
    function use(enter) {
        const name = spot;
        if (name === "output") {
            outputsOpen = !outputsOpen;
            if (outputsOpen)
                goTo(outputSpot + 1 + Math.max(0, outputs.findIndex(o => o.active)));
        } else if (name.startsWith("output:")) {
            const o = outputs[Number(name.slice(7))];
            if (o)
                Sys.setAudioOutput(o.name);
        } else if (name === "power")
            power.openFromKeys();
        else if (name === "volume")
            Sys.toggleMute();
        else if (name !== "brightness") {
            const item = switchItem(name);
            if (!item || !item.available)
                return;
            if (enter && item.opens) {
                mode.holdKeyboard();
                item.opened();
            } else
                item.toggled();
        }
    }
    // (a function, so a test copy can drive it with plain { key, accepted } objects: never real keys)
    Keys.onPressed: event => handleKey(event)
    function handleKey(event) {
        const k = event.key;
        const enter = k === Qt.Key_Return || k === Qt.Key_Enter;
        if (power.open) {
            if (k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Backtab || k === Qt.Key_Tab)
                power.moveKey(k === Qt.Key_Up || k === Qt.Key_Backtab ? -1 : 1);
            else if (enter || k === Qt.Key_Space)
                power.pickKey();
            else
                return;
            event.accepted = true;
            return;
        }
        const nav = [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_Tab, Qt.Key_Backtab].indexOf(k) >= 0;
        if (nav && !keyShown) {
            // the first move only shows where the focus is
            keyShown = true;
            event.accepted = true;
            return;
        }
        const onSwitch = keySpot < switchSpots.length;
        if (k === Qt.Key_Tab)
            goTo((keySpot + 1) % spots.length);
        else if (k === Qt.Key_Backtab)
            goTo((keySpot + spots.length - 1) % spots.length);
        else if (k === Qt.Key_Left || k === Qt.Key_Right) {
            const dir = k === Qt.Key_Left ? -1 : 1;
            if (onSwitch)
                goTo(Math.max(0, Math.min(switchSpots.length - 1, keySpot + dir)));
            else if (keySpot < outputSpot)
                nudge(spot, dir);
        } else if (k === Qt.Key_Down)
            goTo(onSwitch ? switchSpots.length : keySpot + 1);
        else if (k === Qt.Key_Up)
            goTo(keySpot - 1 < switchSpots.length ? lastSwitch : keySpot - 1);
        else if (enter || k === Qt.Key_Space) {
            if (!keyShown)
                return;
            use(enter);
        } else
            return;
        event.accepted = true;
    }

    readonly property real contentWidth: Config.panel.width - 2 * layout.padding
    // the switches share the width equally (their words elide to it)
    readonly property int switchCount: 5
    readonly property real cellWidth: contentWidth / switchCount

    implicitWidth: Config.panel.width
    // from the content's sizes, not column.implicitHeight: a Column skips hidden children, and the whole
    // panel is hidden until it fades in, so the island first sprang to a shorter size, then changed course
    // mid-opening (a visible jolt)
    readonly property int meterCount: Sys.brightness.ready ? 2 : 1
    readonly property real rowHeight: Math.max(layout.levels.iconSize, Config.slider.height)
    implicitHeight: 2 * layout.padding + power.implicitHeight + layout.levels.gapAbove + meterCount * rowHeight + (meterCount - 1) * layout.levels.rowGap + outputsHeight

    // the power modes, in Sys.battery.profile's names, in the order shown
    readonly property var profiles: ["powerSaver", "balanced", "performance"]

    // the keyboard's highlight, under the content: a switch's whole tile or a level row, padded by
    // quickSettings.focus.padding; it springs between spots (panel.list.highlight) and fades in and out
    readonly property rect spotRect: {
        const pad = layout.focus.padding;
        const i = Math.min(keySpot, spots.length - 1);
        // a tile shows no edge of its own, so its highlight can reach a bit past its cell (tileOverhang)
        if (i < switchSpots.length)
            return Qt.rect(column.x + i * cellWidth - layout.focus.tileOverhang, column.y - pad, cellWidth + 2 * layout.focus.tileOverhang, power.implicitHeight + 2 * pad + layout.focus.tileBottom);
        const levelsTop = column.y + power.implicitHeight + layout.levels.gapAbove;
        if (i < outputSpot) {
            const top = levelsTop + (i - switchSpots.length) * (rowHeight + layout.levels.rowGap);
            return Qt.rect(column.x - pad, top - pad, contentWidth + 2 * pad, rowHeight + 2 * pad);
        }
        // the output line and its rows: exactly the rows' own hover highlight
        const outTop = levelsTop + meterCount * rowHeight + (meterCount - 1) * layout.levels.rowGap + layout.outputs.gapAbove;
        return Qt.rect(column.x, outTop + (i - outputSpot) * layout.outputs.rowHeight, contentWidth, layout.outputs.rowHeight);
    }
    Rectangle {
        id: focusWash
        x: mode.spotRect.x
        y: mode.spotRect.y
        width: mode.spotRect.width
        height: mode.spotRect.height
        radius: Config.corner("row", height)
        color: palette.windowText
        opacity: mode.keyShown && !power.open ? Config.panel.list.selectedOpacity : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: Config.motion.hoverFade
            }
        }
        // springs only while shown: appearing, it starts where it should be
        Behavior on x {
            enabled: focusWash.visible
            SpringAnimation {
                spring: Config.spring(Config.panel.list.highlight).spring
                damping: Config.spring(Config.panel.list.highlight).damping
                epsilon: 0.25
            }
        }
        Behavior on y {
            enabled: focusWash.visible
            SpringAnimation {
                spring: Config.spring(Config.panel.list.highlight).spring
                damping: Config.spring(Config.panel.list.highlight).damping
                epsilon: 0.25
            }
        }
        Behavior on width {
            enabled: focusWash.visible
            SpringAnimation {
                spring: Config.spring(Config.panel.list.highlight).spring
                damping: Config.spring(Config.panel.list.highlight).damping
                epsilon: 0.25
            }
        }
        Behavior on height {
            enabled: focusWash.visible
            SpringAnimation {
                spring: Config.spring(Config.panel.list.highlight).spring
                damping: Config.spring(Config.panel.list.highlight).damping
                epsilon: 0.25
            }
        }
    }

    Column {
        id: column
        x: layout.padding
        y: layout.padding
        width: mode.contentWidth
        // behind the open power menu: blurred (the layer only exists while the menu is out)
        layer.enabled: power.t > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: power.t * mode.layout.power.menu.backdropBlur
            blurMax: mode.layout.power.menu.backdropBlurMax
        }

        Row {
            id: switches
            QuickToggle {
                id: wifiToggle
                width: mode.cellWidth
                icon: mode.layout.wifi.icon
                word: !Sys.wifi.enabled ? mode.layout.offText : Sys.wifi.connected ? Sys.wifi.ssid : mode.layout.onText
                on: Sys.wifi.enabled
                tint: Config.colors.accent
                opens: true
                onToggled: Sys.setWifiEnabled(!Sys.wifi.enabled)
                onOpened: mode.requestState("wifi")
            }
            QuickToggle {
                id: bluetoothToggle
                width: mode.cellWidth
                icon: mode.layout.bluetooth.icon
                word: !Sys.bluetooth.available ? mode.layout.missingText : !Sys.bluetooth.enabled ? mode.layout.offText : Sys.bluetooth.connected ? Sys.bluetooth.name : mode.layout.onText
                available: Sys.bluetooth.available
                on: Sys.bluetooth.enabled
                tint: Config.colors.accent
                opens: true
                onToggled: Sys.setBluetoothEnabled(!Sys.bluetooth.enabled)
                onOpened: mode.requestState("bluetooth")
            }
            QuickToggle {
                id: focusToggle
                width: mode.cellWidth
                icon: mode.layout.focus.icon
                word: mode.layout.focus.word
                on: Activity.doNotDisturb
                tint: Config.colors.accent
                onToggled: Activity.setDoNotDisturb(!Activity.doNotDisturb)
            }
            // solid blue while the mic is live, soft white with the crossed-out mic when muted
            QuickToggle {
                id: micToggle
                width: mode.cellWidth
                icon: Sys.audio.micMuted ? Config.microphone.mutedIcon : Config.microphone.icon
                word: !Sys.audio.micReady ? mode.layout.missingText : Sys.audio.micMuted ? mode.layout.mutedText : mode.layout.onText
                available: Sys.audio.micReady
                on: !Sys.audio.micMuted
                tint: Config.colors.accent
                onToggled: Sys.toggleMicMute()
            }
            // room for the power switch; the switch itself (MenuBadge) sits above everything at this spot,
            // so its menu opens over the rest
            Item {
                id: powerSlot
                width: mode.cellWidth
                height: power.implicitHeight
            }
        }

        Column {
            width: parent.width
            topPadding: mode.layout.levels.gapAbove
            spacing: mode.layout.levels.rowGap
            LevelRow {
                visible: Sys.brightness.ready
                kind: "brightness"
                live: mode.hasAppeared
                starting: mode.active && !mode.hasAppeared
                width: parent.width
                height: mode.rowHeight
                iconSize: mode.layout.levels.iconSize
                gap: mode.layout.levels.gap
                valueSize: mode.layout.levels.valueSize
                valueColor: palette.placeholderText
            }
            LevelRow {
                kind: "volume"
                live: mode.hasAppeared
                starting: mode.active && !mode.hasAppeared
                width: parent.width
                height: mode.rowHeight
                iconSize: mode.layout.levels.iconSize
                gap: mode.layout.levels.gap
                valueSize: mode.layout.levels.valueSize
                valueColor: palette.placeholderText
            }
        }

        // where the sound goes; unfolds into the outputs
        Item {
            id: outputBox
            visible: mode.outputsShown
            width: parent.width
            height: mode.outputsHeight
            clip: true
            Behavior on height {
                SpringAnimation {
                    spring: Config.spring(Config.island.expand).spring
                    damping: Config.spring(Config.island.expand).damping
                    epsilon: 0.5
                }
            }
            readonly property var current: mode.outputs.find(o => o.active) || null
            Item {
                id: outputLine
                y: mode.layout.outputs.gapAbove
                width: parent.width
                height: mode.layout.outputs.rowHeight
                StyledText {
                    id: outputTitle
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: mode.layout.outputs.textSize
                    color: palette.placeholderText
                    text: mode.layout.outputs.title
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: mode.layout.outputs.chevronGap
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        // what the title and the arrow leave (and at most nameMaxWidth of the line)
                        width: Math.min(implicitWidth, outputLine.width * mode.layout.outputs.nameMaxWidth, outputLine.width - outputTitle.implicitWidth - 2 * mode.layout.outputs.chevronGap - mode.layout.outputs.chevronSize - mode.layout.outputs.titleGap)
                        elide: Text.ElideMiddle
                        font.pixelSize: mode.layout.outputs.textSize
                        text: outputBox.current ? outputBox.current.description : ""
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: mode.layout.outputs.chevronSize
                        height: width
                        name: Config.panel.expandIcon
                        color: palette.placeholderText
                        rotation: mode.outputsOpen ? 180 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: Config.motion.colorFade
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: mode.outputsOpen = !mode.outputsOpen
                }
            }
            Repeater {
                model: mode.outputsOpen ? mode.outputs : []
                delegate: Item {
                    id: output
                    required property int index
                    required property var modelData
                    y: outputLine.y + outputLine.height + index * mode.layout.outputs.rowHeight
                    width: outputBox.width
                    height: mode.layout.outputs.rowHeight
                    Rectangle {
                        anchors.fill: parent
                        radius: Config.corner("row", height)
                        color: palette.windowText
                        opacity: outputHover.hovered && !mode.keyShown ? Config.panel.list.selectedOpacity : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Config.motion.hoverFade
                            }
                        }
                    }
                    StyledText {
                        x: mode.layout.outputs.indent
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 2 * mode.layout.outputs.indent - Config.panel.list.checkSize
                        elide: Text.ElideMiddle
                        font.pixelSize: mode.layout.outputs.textSize
                        text: output.modelData.description
                    }
                    Icon {
                        visible: output.modelData.active
                        anchors.right: parent.right
                        anchors.rightMargin: mode.layout.outputs.indent
                        anchors.verticalCenter: parent.verticalCenter
                        width: Config.panel.list.checkSize
                        height: width
                        name: Config.panel.list.checkIcon
                        color: Config.colors.accent
                    }
                    MovedHover {
                        id: outputHover
                        cursorShape: Qt.PointingHandCursor
                        onMoved: mode.keyShown = false
                    }
                    TapHandler {
                        onTapped: Sys.setAudioOutput(output.modelData.name)
                    }
                }
            }
        }
    }

    // while the power menu is open, a click anywhere else in the panel puts it away and does nothing else.
    // It stays until the button is released: hidden on the press itself, it let the press fall through to the
    // switch or slider under it (toggled by mistake). The wheel is swallowed too (no volume change behind it).
    MouseArea {
        id: menuCatcher
        property bool holding: false
        anchors.fill: parent
        visible: power.open || holding
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            holding = true;
            power.close();
        }
        onReleased: holding = false
        onCanceled: holding = false
        onWheel: wheel => wheel.accepted = true
    }
    MenuBadge {
        id: power
        readonly property real slotX: switches.x + powerSlot.x
        readonly property real slotY: switches.y + powerSlot.y
        x: column.x + slotX
        y: column.y + slotY
        width: mode.cellWidth
        // the menu drops from the badge's top, down and to the left (its right edge on the badge cell's),
        // kept inside the panel's content
        menuX: Math.max(-slotX, Math.min(mode.contentWidth - menuWidth - slotX, width - menuWidth))
        menuY: Math.max(-slotY, Math.min(column.height - menuHeight - slotY, 0))
        current: Math.max(0, mode.profiles.indexOf(Sys.battery.profile))
        model: [
            {
                "icon": mode.layout.power.saverIcon,
                "text": mode.layout.power.saverText,
                "tint": Config.colors.powerSaver
            },
            {
                "icon": mode.layout.power.balancedIcon,
                "text": mode.layout.power.balancedText,
                "tint": palette.windowText
            },
            {
                "icon": mode.layout.power.performanceIcon,
                "text": mode.layout.power.performanceText,
                "tint": Config.colors.performance
            }
        ]
        onPicked: i => Sys.setPowerProfile(mode.profiles[i])
    }
}
