pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// Bluetooth dropdown (under the bar's Bluetooth icon), calm like the macOS menu: "Bluetooth" and a switch
// on top, then the devices (Sys.bluetoothDevices; new ones are searched for only while it's open) in two
// groups: saved (paired) devices, connected first, then the other devices nearby ("Searching…" while none
// has shown up). Each row: an icon for the kind of device, the name, at the right the battery level when
// reported, "Connecting…" / "Pairing…", what went wrong in red, or a blue check when connected. Click (or
// Up/Down + Enter): a saved device connects; a new one is paired, trusted and connected; a connected one
// disconnects (bluetooth.clickDisconnects). Space flips the switch.
// The list is a ListView fed by a ListModel updated in place (only the rows on screen exist).
// Pairing goes through BlueZ without an agent of our own: devices that pair without a code (headphones,
// speakers, mice, most controllers) work; one that asks for a PIN or a code to confirm shows the error.
IslandMode {
    id: mode

    readonly property var layout: Config.bluetooth
    // the rows' look, shared with the other list panel (PanelList)
    readonly property var rowsLook: Config.panel.list
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

    readonly property bool listShown: btOn

    // keyboard: Up/Down pick a device, Enter acts on it, Space toggles Bluetooth; Escape closes the
    // dropdown (IslandMode)
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
            } else if (!d || d.connected) {
                attempt = "";
            }
        }
    }
    Keys.onUpPressed: step(-1)
    Keys.onDownPressed: step(1)
    function step(dir) {
        if (!listShown)
            return;
        list.keyShown = true;
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
        if (listShown)
            activate(selected);
    }

    // address of the last device we tried to connect / pair ("" = none)
    property string attempt: ""
    onActiveChanged: {
        if (active) {
            devices = Qt.binding(() => Sys.bluetoothDevices);
            list.reset();
            list.keyShown = !!island && island.keyboardOpened;
        } else
            devices = devices;
    }
    // reset once fully gone, not while it animates out
    onOnScreenChanged: {
        if (!onScreen) {
            selected = 0;
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
    // what's shown: all of it, up to panel.visibleRows rows (plus a group title), then it scrolls
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

    // ---- size ----
    implicitWidth: Config.panel.width
    implicitHeight: 2 * Config.panel.padding + Config.panel.header.height + (listShown ? Config.panel.listGap + viewHeight : 0)

    // fixed-size content box, pinned to the top so nothing slides while the island grows
    Item {
        id: content
        x: Config.panel.padding
        y: Config.panel.padding
        width: mode.implicitWidth - 2 * Config.panel.padding
        height: mode.implicitHeight - 2 * Config.panel.padding

        PanelHeader {
            id: header
            title: mode.layout.title
            Switch {
                checked: mode.btOn
                onToggled: mode.toggleBluetooth()
            }
        }

        // ---- devices ----
        PanelList {
            id: list
            visible: mode.listShown
            anchors.top: header.bottom
            anchors.topMargin: Config.panel.listGap
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
                        color: palette.placeholderText
                        text: mode.layout.otherTitle
                    }
                    StyledText {
                        height: mode.rowsLook.rowHeight
                        verticalAlignment: Text.AlignVCenter
                        color: palette.placeholderText
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
                readonly property color tint: connected ? Config.colors.accent : palette.windowText
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
                        color: row.failed && row.busy === "" ? Config.colors.danger : palette.placeholderText
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
