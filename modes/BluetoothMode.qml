pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

import "../services"
import "../island"
import "../widgets"

// Bluetooth panel, the Wi-Fi panel's sibling in the battery panel's language:
//  - on top, centred: the connected device's name ("Name and 2 more", "Not connected", "Off"); a new name
//    rolls in (RollingName)
//  - the Bluetooth rune, big: the small icon's (assets/icons/bluetooth.svg) stem, chevrons and arms redrawn as
//    round strokes with its own proportions (glyph.*, in the icon's 24-unit grid, times glyph.scale). Blue
//    while a device is connected, grey otherwise. Opening (and connecting a device) lights it part by part
//    (stem, then the two zigzags); while searching or connecting, a ripple runs through it; a failed
//    attempt shakes it and flashes it red (GlyphMotion, shared with the Wi-Fi panel). The rune is the switch: click it (or press Space) to turn
//    Bluetooth on / off
//  - the devices, right under the rune (or behind a pill "Devices · 4" (ExpandPill) that unfolds them,
//    panel.collapsibleList) (Sys.bluetoothDevices; new ones are searched for only
//    while this panel is open) in two groups: saved (paired) devices, connected first, then the other
//    devices nearby ("Searching…" while none has shown up). Each row: an icon for the kind of device, the
//    name, at the right the battery level when reported, "Connecting…" / "Pairing…", what went wrong in
//    red, or a blue check when connected. Click (or Up/Down + Enter): a saved device connects; a new one is
//    paired, trusted and connected; a connected one disconnects (bluetooth.clickDisconnects). Up/Down or
//    Enter unfold the list from the keyboard
// The list is a ListView fed by a ListModel updated in place (only the rows on screen exist).
// Pairing goes through BlueZ without an agent of our own: devices that pair without a code (headphones,
// speakers, mice, most controllers) work; one that asks for a PIN or a code to confirm shows the error.
IslandMode {
    id: mode

    readonly property var layout: Config.bluetooth
    // the rows' look, shared with the other list panel (PanelList)
    readonly property var rowsLook: Config.panel.list
    readonly property var look: Config.bluetooth.hero
    launcher: Config.bluetooth.launcher

    // look for new devices only while the panel is open
    Binding {
        target: Sys
        property: "bluetoothScan"
        value: mode.active
    }

    readonly property bool btOn: Sys.bluetooth.enabled
    // the devices shown: frozen while the panel animates out (discovery stops then)
    property var devices: Sys.bluetoothDevices
    readonly property bool connecting: devices.some(d => d.busy === "connecting" || d.busy === "pairing")

    // ---- the list unfolds from the pill ----
    // panel.collapsibleList: the list waits behind the pill until it's clicked; otherwise (the default) it
    // shows right away and there's no pill (Wi-Fi keeps a plain "Searching…" one until something is found)
    readonly property bool collapsible: Config.panel.collapsibleList
    property bool expanded: false
    readonly property bool listShown: btOn && (expanded || !collapsible)

    // keyboard: Up/Down pick a device, Enter acts on it (both unfold the list first), Space toggles
    // Bluetooth; Escape closes the panel (IslandMode)
    keyTarget: mode
    // the selection follows the device, not the row: when the list reorders (a device pairs and moves to
    // the saved group), Enter must still mean the same device
    property int selected: 0
    property string _selectedAddress: ""
    onSelectedChanged: {
        _selectedAddress = devices[selected] ? devices[selected].address : "";
    }
    onDevicesChanged: {
        syncRows();
        const i = devices.findIndex(d => d.address === _selectedAddress);
        selected = i >= 0 ? i : Math.min(selected, Math.max(0, devices.length - 1));
        list.syncCurrent();
        // how the last attempt went
        if (attempt !== "") {
            const d = devices.find(d => d.address === attempt);
            if (d && d.failed && d.busy === "") {
                attempt = "";
                motion.fail();
            } else if (!d || d.connected) {
                attempt = "";
            }
        }
    }
    Keys.onUpPressed: step(-1)
    Keys.onDownPressed: step(1)
    function step(dir) {
        if (!btOn)
            return;
        if (!listShown) {
            expanded = true;
            return;
        }
        selected = Math.max(0, Math.min(devices.length - 1, selected + dir));
        revealRow(selected);
    }
    Keys.onSpacePressed: toggleBluetooth()
    function toggleBluetooth() {
        if (Sys.bluetooth.available)
            Sys.setBluetoothEnabled(!btOn);
    }
    Keys.onReturnPressed: enter()
    Keys.onEnterPressed: enter()
    function enter() {
        if (!btOn)
            return;
        if (!listShown)
            expanded = true;
        else
            activate(selected);
    }

    // address of the last device we tried to connect / pair ("" = none)
    property string attempt: ""
    onActiveChanged: {
        if (active) {
            devices = Qt.binding(() => Sys.bluetoothDevices);
            list.reset();
            motion.replay(true);
        } else
            devices = devices;
    }
    // reset once fully gone, not while it animates out
    onOnScreenChanged: {
        if (!onScreen) {
            selected = 0;
            expanded = false;
        }
    }
    function activate(i) {
        const d = devices[i];
        if (!d || d.busy === "pairing" || d.busy === "connecting")
            return;
        if (d.connected) {
            if (layout.clickDisconnects)
                Sys.disconnectBluetooth(d.address);
            return;
        }
        attempt = d.address;
        Sys.connectBluetooth(d.address);
    }

    // ---- the name on top: rolls when it changes ----
    readonly property string heroName: {
        if (!Sys.bluetooth.available)
            return layout.unavailableText;
        if (!btOn)
            return look.offText;
        if (Sys.bluetooth.count > 1)
            return layout.manyConnectedText.arg(Sys.bluetooth.name).arg(Sys.bluetooth.count - 1);
        return Sys.bluetooth.connected ? Sys.bluetooth.name : layout.notConnectedText;
    }

    // ---- the rune ----
    // three parts: 0 = the stem, 1 = the upper chevron + its arm, 2 = the lower chevron + its arm. All lit
    // while a device is connected; its motion is GlyphMotion's
    GlyphMotion {
        id: motion
        active: mode.active
        parts: 3
        live: mode.btOn && Sys.bluetooth.connected ? 3 : 0
        rippling: mode.onScreen && mode.btOn && (mode.connecting || mode.devices.filter(d => !d.paired).length === 0)
        fast: mode.connecting
        hovered: glyphHover.hovered
    }

    // ---- rune geometry, in px: the icon's grid (centred on the crossing point) times glyph.scale ----
    readonly property real gs: look.glyph.scale
    readonly property real stemHalf: look.glyph.stemHalf * gs
    readonly property real chevron: look.glyph.chevron * gs
    readonly property real arm: look.glyph.arm * gs
    readonly property real stroke: look.glyph.thickness * gs
    // bounding box around the crossing point (stroke included): left arm to chevron tips, stem ends
    readonly property real glyphLeft: arm + stroke / 2
    readonly property real glyphWidth: arm + chevron + stroke
    readonly property real glyphHeight: 2 * stemHalf + stroke
    // one part as an SVG polyline: points [[x, y], ...] relative to the crossing point at (cx, cy)
    function polyline(cx, cy, points) {
        return points.map((p, i) => (i === 0 ? "M " : "L ") + (cx + p[0]).toFixed(2) + " " + (cy + p[1]).toFixed(2)).join(" ");
    }

    // one stroke of the rune
    component Stroke: ShapePath {
        property string svg
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
            path: svg
        }
    }

    // ---- rows: a ListModel kept in sync with Sys.bluetoothDevices, changed in place ----
    ListModel {
        id: rows
    }
    function syncRows() {
        const roles = ["address", "name", "kind", "paired", "connected", "busy", "failed", "battery"];
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            const item = Object.assign({
                "section": d.paired ? "saved" : "other"
            }, d);
            if (i >= rows.count) {
                rows.append(item);
                continue;
            }
            const old = rows.get(i);
            if (old.section !== item.section || roles.some(r => old[r] !== item[r]))
                rows.set(i, item);
        }
        if (rows.count > devices.length)
            rows.remove(devices.length, rows.count - devices.length);
    }

    // ---- list layout ----
    readonly property int savedCount: devices.filter(d => d.paired).length
    readonly property int otherCount: devices.length - savedCount
    // no other device found yet: the list ends with the "Other devices" title and "Searching…" (the footer)
    readonly property real footerHeight: otherCount > 0 ? 0 : (savedCount > 0 ? rowsLook.sectionGap : 0) + rowsLook.headerHeight + rowsLook.rowHeight
    // the list's full height: a title per group (+ the gap between groups), the rows, the footer
    readonly property real listHeight: (savedCount > 0 ? rowsLook.headerHeight : 0) + (otherCount > 0 ? rowsLook.headerHeight : 0) + (savedCount > 0 && otherCount > 0 ? rowsLook.sectionGap : 0) + devices.length * rowsLook.rowHeight + footerHeight
    // what's shown: all of it, up to hero.visibleRows rows (plus a group title), then it scrolls
    readonly property real viewHeight: Math.min(listHeight, Config.panel.visibleRows * rowsLook.rowHeight + rowsLook.headerHeight)

    // top of row i in the list, computed exactly (ListView only estimates rows it hasn't created yet)
    function rowTop(i) {
        let y = savedCount > 0 ? rowsLook.headerHeight : 0;
        if (i < savedCount)
            return y + i * rowsLook.rowHeight;
        return y + savedCount * rowsLook.rowHeight + (savedCount > 0 ? rowsLook.sectionGap : 0) + rowsLook.headerHeight + (i - savedCount) * rowsLook.rowHeight;
    }
    // scroll (animated) to y, kept inside the list
    function scrollTo(y) {
        list.scrollTo(y, listHeight);
    }
    // scroll (animated) just enough to show row i, with its group title if it's the first of its group.
    // Keyboard only (on hover it would scroll whenever the mouse touched a half-visible row).
    function revealRow(i) {
        if (i < 0 || i >= devices.length)
            return;
        const first = i === 0 || i === savedCount;
        const top = rowTop(i) - (first ? rowsLook.headerHeight : 0);
        const bottom = rowTop(i) + rowsLook.rowHeight;
        const from = list.scrollTarget;
        let y = from;
        if (top < y)
            y = top;
        else if (bottom > y + list.height)
            y = bottom - list.height;
        scrollTo(y);
    }

    // ---- panel size ----
    readonly property real heroHeight: nameBox.height + Config.panel.nameGap + glyphHeight
    // the pill only when the list is collapsible (the list itself says "Searching…")
    readonly property bool pillShown: btOn && collapsible
    readonly property real pillRoom: pillShown ? Config.panel.pill.gap + Config.panel.pill.height : 0
    readonly property real listRoom: listShown ? (collapsible ? Config.panel.pill.listGap : Config.panel.listGap) + viewHeight : 0

    implicitWidth: Config.panel.width
    implicitHeight: 2 * Config.panel.padding + heroHeight + pillRoom + listRoom

    // fixed-size content box, pinned to the top so nothing slides while the island grows
    Item {
        id: content
        x: Config.panel.padding
        y: Config.panel.padding
        width: mode.implicitWidth - 2 * Config.panel.padding
        height: mode.implicitHeight - 2 * Config.panel.padding

        // ---- the name ----
        RollingName {
            id: nameBox
            width: parent.width
            animate: mode.active
            color: mode.btOn ? Config.colors.text : Config.colors.secondary
            text: mode.heroName
        }

        // ---- the rune ----
        Item {
            id: glyph
            anchors.top: nameBox.bottom
            anchors.topMargin: Config.panel.nameGap
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: motion.shake
            width: mode.glyphWidth
            height: mode.glyphHeight

            // the crossing point
            readonly property real cx: mode.glyphLeft
            readonly property real cy: height / 2
            readonly property string stemPath: mode.polyline(cx, cy, [[0, -mode.stemHalf], [0, mode.stemHalf]])
            // from the stem's top to the upper chevron's tip, then down through the crossing to the lower-left arm
            readonly property string upperPath: mode.polyline(cx, cy, [[0, -mode.stemHalf], [mode.chevron, -mode.stemHalf + mode.chevron], [-mode.arm, mode.arm]])
            // from the upper-left arm through the crossing to the lower chevron's tip, then to the stem's foot
            readonly property string lowerPath: mode.polyline(cx, cy, [[-mode.arm, -mode.arm], [mode.chevron, mode.stemHalf - mode.chevron], [0, mode.stemHalf]])

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                // one stroke per part, each an opaque color (grey, blended towards the lit color by `light`):
                // the parts overlap at the crossing and the stem's ends, and see-through strokes doubled up
                // there into bright spots
                Stroke {
                    svg: glyph.stemPath
                    strokeWidth: mode.stroke
                    strokeColor: motion.partColor(0)
                }
                Stroke {
                    svg: glyph.upperPath
                    strokeWidth: mode.stroke
                    strokeColor: motion.partColor(1)
                }
                Stroke {
                    svg: glyph.lowerPath
                    strokeWidth: mode.stroke
                    strokeColor: motion.partColor(2)
                }
            }

            // the rune is the Bluetooth switch
            scale: glyphTap.pressed ? Config.motion.pressScale : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Config.motion.pressDuration
                    easing.type: Easing.OutCubic
                }
            }
            HoverHandler {
                id: glyphHover
                enabled: Sys.bluetooth.available
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: glyphTap
                enabled: Sys.bluetooth.available
                onTapped: mode.toggleBluetooth()
            }
        }

        // ---- the pill that unfolds the list ----
        ExpandPill {
            id: pill
            visible: mode.pillShown
            anchors.top: glyph.bottom
            anchors.topMargin: Config.panel.pill.gap
            anchors.horizontalCenter: parent.horizontalCenter
            expanded: mode.expanded
            text: mode.devices.length === 0 ? mode.layout.searchingText : mode.look.pillText.arg(mode.devices.length)
            onClicked: mode.expanded = !mode.expanded
        }

        // ---- devices ----
        PanelList {
            id: list
            visible: mode.listShown
            anchors.top: mode.collapsible ? pill.bottom : glyph.bottom
            anchors.topMargin: mode.collapsible ? Config.panel.pill.listGap : Config.panel.listGap
            width: parent.width
            height: mode.viewHeight
            model: rows
            selected: mode.selected
            onPointed: index => mode.selected = index
            pointerSelects: true
            savedCount: mode.savedCount
            savedTitle: mode.layout.savedTitle
            otherTitle: mode.layout.otherTitle

            // nothing new found yet: "Other devices" + "Searching…" after the saved ones
            footer: Item {
                width: list.width
                height: mode.footerHeight
                visible: mode.otherCount === 0
                Column {
                    x: mode.rowsLook.rowPadding
                    y: mode.savedCount > 0 ? mode.rowsLook.sectionGap : 0
                    StyledText {
                        height: mode.rowsLook.headerHeight
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Config.activity.captionSize
                        color: Config.colors.secondary
                        text: mode.layout.otherTitle
                    }
                    StyledText {
                        height: mode.rowsLook.rowHeight
                        verticalAlignment: Text.AlignVCenter
                        color: Config.colors.secondary
                        text: mode.layout.searchingText
                    }
                }
            }

            delegate: Item {
                id: row
                required property int index
                required property string name
                required property string kind
                required property bool connected
                required property string busy
                required property bool failed
                required property int battery
                readonly property color tint: connected ? Config.colors.accent : Config.colors.text
                readonly property string status: busy === "pairing" ? mode.layout.pairingText : busy === "connecting" ? mode.layout.connectingText : busy === "disconnecting" ? mode.layout.disconnectingText : failed ? mode.layout.failedText : battery >= 0 ? mode.layout.batteryFormat.arg(battery) : ""

                width: list.width
                height: mode.rowsLook.rowHeight

                Icon {
                    id: kindIcon
                    x: mode.rowsLook.rowPadding
                    anchors.verticalCenter: parent.verticalCenter
                    width: mode.rowsLook.iconSize
                    height: mode.rowsLook.iconSize
                    name: mode.layout.deviceIcons[row.kind] || mode.layout.deviceIcons.other
                    color: row.tint
                }
                StyledText {
                    anchors.left: kindIcon.right
                    anchors.leftMargin: mode.rowsLook.rowPadding
                    anchors.right: trailing.left
                    anchors.rightMargin: mode.rowsLook.rowPadding
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    color: row.tint
                    text: row.name
                }

                // right: state or battery, then the check when connected
                Row {
                    id: trailing
                    anchors.right: parent.right
                    anchors.rightMargin: mode.rowsLook.rowPadding
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: mode.rowsLook.trailingGap
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        font.pixelSize: mode.rowsLook.statusSize
                        color: row.failed && row.busy === "" ? Config.colors.danger : Config.colors.secondary
                        text: row.status
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.connected
                        width: mode.rowsLook.checkSize
                        height: mode.rowsLook.checkSize
                        name: mode.rowsLook.checkIcon
                        color: Config.colors.accent
                    }
                }

                HoverHandler {
                    cursorShape: row.connected && !mode.layout.clickDisconnects ? Qt.ArrowCursor : Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: mode.activate(row.index)
                }
            }
        }
    }
}
