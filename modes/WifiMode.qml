pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// Wi-Fi dropdown (under the bar's Wi-Fi icon), calm like the macOS menu: "Wi-Fi" and a switch on top,
// then the nearby networks (Sys.wifiNetworks, scanned only while it's open) in two groups, saved then
// others (PanelList). Each row: signal bars, the name, a lock when secured, a blue check / "Connecting…" /
// what went wrong in red. Click (or Up/Down + Enter): saved and open networks connect right away; a new
// secured one (or one whose last attempt failed) opens a password field under its row. Enter connects;
// Escape, the ×, or the arrows cancel. Space flips the switch.
// The list is a ListView fed by a ListModel updated in place (only the rows on screen exist; scan
// updates change rows instead of rebuilding them). It scrolls past panel.visibleRows.
IslandMode {
    id: mode

    readonly property var layout: Config.wifi
    // the rows' look, shared with the other list panel (PanelList)
    readonly property var rowsLook: Config.panel.list
    launcher: Config.wifi.launcher
    // don't collapse when the mouse leaves while a password is being typed, and Escape then cancels the
    // password instead of closing the panel
    autoClose: asking === ""
    escapeCloses: asking === ""
    onEscaped: cancelPassword()

    // scan only while the panel is open
    Binding {
        target: Sys
        property: "wifiScan"
        value: mode.active
    }

    readonly property bool wifiOn: Sys.wifi.enabled
    // the networks shown: frozen while the panel animates out (scanning stops then)
    property var networks: Sys.wifiNetworks
    readonly property bool connecting: networks.some(n => n.connecting)

    readonly property bool listShown: wifiOn && networks.length > 0

    // keyboard: Up/Down pick a network, Enter connects, Space flips the switch; Escape closes the
    // dropdown (IslandMode), or cancels the password field when it's open
    keyTarget: mode
    // the selection follows the network, not the row: when the list reorders (a network connects and
    // moves to the saved group, a new one shows up above), Enter must still mean the same network
    property int selected: 0
    property string _selectedName: ""
    onSelectedChanged: {
        _selectedName = networks[selected] ? networks[selected].name : "";
    }
    onNetworksChanged: {
        syncRows();
        const i = networks.findIndex(n => n.name === _selectedName);
        selected = i >= 0 ? i : Math.min(selected, Math.max(0, networks.length - 1));
        list.syncCurrent();
        // the network asking for a password went out of range: leave password entry
        if (asking !== "" && !networks.some(n => n.name === asking))
            cancelPassword();
        // how the last attempt went
        if (attempt !== "") {
            const n = networks.find(n => n.name === attempt);
            if (n && n.failed) {
                attempt = "";
            } else if (!n || n.connected) {
                attempt = "";
            }
        }
    }
    Keys.onUpPressed: step(-1)
    Keys.onDownPressed: step(1)
    // move the selection with the keyboard; leaves password entry (that network is no longer the one picked)
    function step(dir) {
        if (!listShown)
            return;
        if (asking !== "")
            cancelPassword();
        list.keyShown = true;
        selected = Math.max(0, Math.min(networks.length - 1, selected + dir));
        revealRow(selected);
    }
    Keys.onSpacePressed: toggleWifi()
    function toggleWifi() {
        Sys.setWifiEnabled(!wifiOn);
    }
    Keys.onReturnPressed: enter()
    Keys.onEnterPressed: enter()
    function enter() {
        if (listShown)
            activate(selected);
    }

    // name of the network asking for a password ("" = none), and of the last one we tried to join
    property string asking: ""
    property string attempt: ""
    onActiveChanged: {
        if (active) {
            networks = Qt.binding(() => Sys.wifiNetworks);
            list.reset();
            list.keyShown = !!island && island.keyboardOpened;
        } else
            networks = networks;
    }
    // reset once fully gone, not while it animates out (the highlight jumped, the list collapsed)
    onOnScreenChanged: {
        if (!onScreen) {
            asking = "";
            selected = 0;
        }
    }
    function activate(i) {
        const n = networks[i];
        if (!n || n.connected)
            return;
        if (n.secure && (!n.known || n.failed)) {
            asking = n.name;   // the row grows its password field and focuses it
            selected = i;
            centerRow(i);
            return;
        }
        asking = "";
        attempt = n.name;
        Sys.connectWifi(n.name, "");
    }
    function submitPassword(psk) {
        if (asking !== "" && psk !== "") {
            attempt = asking;
            Sys.connectWifi(asking, psk);
        }
        cancelPassword();
    }
    function cancelPassword() {
        asking = "";
        mode.forceActiveFocus();
    }

    // ---- rows: a ListModel kept in sync with Sys.wifiNetworks, changed in place ----
    ListModel {
        id: rows
    }
    function syncRows() {
        const roles = ["name", "level", "secure", "known", "connected", "connecting", "failed"];
        for (let i = 0; i < networks.length; i++) {
            const n = networks[i];
            const item = Object.assign({
                "section": n.connected || n.known ? "saved" : "other"
            }, n);
            if (i >= rows.count) {
                rows.append(item);
                continue;
            }
            const old = rows.get(i);
            if (old.section !== item.section || roles.some(r => old[r] !== item[r]))
                rows.set(i, item);
        }
        if (rows.count > networks.length)
            rows.remove(networks.length, rows.count - networks.length);
    }

    // ---- list layout ----
    readonly property int askingIndex: networks.findIndex(n => n.name === asking)
    readonly property real fieldRoom: askingIndex >= 0 ? layout.fieldHeight + layout.fieldGap : 0
    // the list's full height: a title per group (+ the gap between groups), the rows, the password field
    readonly property int savedCount: networks.filter(n => n.connected || n.known).length
    readonly property int otherCount: networks.length - savedCount
    readonly property real listHeight: networks.length === 0 ? 0 : (savedCount > 0 ? rowsLook.headerHeight : 0) + (otherCount > 0 ? rowsLook.headerHeight : 0) + (savedCount > 0 && otherCount > 0 ? rowsLook.sectionGap : 0) + networks.length * rowsLook.rowHeight + fieldRoom
    // what's shown: all of it, up to panel.visibleRows rows (plus a group title), then it scrolls
    readonly property real viewHeight: Math.min(listHeight, Config.panel.visibleRows * rowsLook.rowHeight + rowsLook.headerHeight)

    // top of row i in the list, computed exactly (ListView only estimates rows it hasn't created yet)
    function rowTop(i) {
        let y = savedCount > 0 ? rowsLook.headerHeight : 0;
        if (i < savedCount)
            y += i * rowsLook.rowHeight;
        else
            y += savedCount * rowsLook.rowHeight + (savedCount > 0 ? rowsLook.sectionGap : 0) + rowsLook.headerHeight + (i - savedCount) * rowsLook.rowHeight;
        return y + (askingIndex >= 0 && askingIndex < i ? fieldRoom : 0);
    }
    // scroll (animated) to y, kept inside the list
    function scrollTo(y) {
        list.scrollTo(y, listHeight);
    }
    // centre row i and its password field in the list (when typing starts)
    function centerRow(i) {
        const height = rowsLook.rowHeight + (i === askingIndex ? fieldRoom : 0);
        scrollTo(rowTop(i) + height / 2 - list.height / 2);
    }
    // scroll (animated) just enough to show row i (with its group title if it's the first of its group,
    // and its password field). Keyboard and password field only, never on hover.
    function revealRow(i) {
        if (i < 0 || i >= networks.length)
            return;
        const first = i === 0 || i === savedCount;
        const top = rowTop(i) - (first ? rowsLook.headerHeight : 0);
        const bottom = rowTop(i) + rowsLook.rowHeight + (i === askingIndex ? fieldRoom : 0);
        const from = list.scrollTarget;
        let y = from;
        if (top < y)
            y = top;
        else if (bottom > y + list.height)
            y = bottom - list.height;
        scrollTo(y);
    }

    // ---- size ----
    // still searching (on, nothing found yet): one grey line where the list goes
    readonly property bool searching: wifiOn && networks.length === 0
    implicitWidth: Config.panel.width
    implicitHeight: 2 * Config.panel.padding + Config.panel.header.height + (listShown ? Config.panel.listGap + viewHeight : searching ? Config.panel.listGap + rowsLook.rowHeight : 0)

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
                checked: mode.wifiOn
                onToggled: mode.toggleWifi()
            }
        }

        StyledText {
            visible: mode.searching
            anchors.top: header.bottom
            anchors.topMargin: Config.panel.listGap
            x: mode.rowsLook.rowPadding
            height: mode.rowsLook.rowHeight
            verticalAlignment: Text.AlignVCenter
            color: palette.placeholderText
            text: mode.layout.searchingText
        }

        // ---- networks ----
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
            pointerSelects: mode.asking === ""
            savedCount: mode.savedCount
            savedTitle: mode.layout.savedTitle
            otherTitle: mode.layout.otherTitle

            delegate: Item {
                id: row
                required property int index
                required property string name
                required property int level
                required property bool secure
                required property bool connected
                required property bool connecting
                required property bool failed
                readonly property color tint: connected ? Config.colors.accent : palette.windowText
                readonly property bool asking: mode.asking !== "" && mode.asking === name

                width: list.width
                height: mode.rowsLook.rowHeight + (asking ? mode.layout.fieldHeight + mode.layout.fieldGap : 0)

                Item {
                    id: line
                    width: parent.width
                    height: mode.rowsLook.rowHeight

                    // signal, like the bar's icon: all bars dimmed, the real ones bright on top
                    Wifi {
                        id: bars
                        x: mode.rowsLook.rowPadding
                        height: size
                        size: mode.rowsLook.iconSize
                        level: row.level + 1
                        tint: row.tint
                    }
                    StyledText {
                        anchors.left: bars.right
                        anchors.leftMargin: mode.rowsLook.rowPadding
                        anchors.right: trailing.left
                        anchors.rightMargin: mode.rowsLook.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideMiddle
                        color: row.tint
                        text: row.name
                    }

                    // right: state (connecting / failed), then the lock, then the check when connected
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
                            color: row.failed ? Config.colors.danger : palette.placeholderText
                            text: row.connecting ? mode.layout.connectingText : row.failed ? mode.layout.failedText : ""
                        }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.secure
                            width: mode.layout.lockSize
                            height: mode.layout.lockSize
                            name: mode.layout.lockIcon
                            color: palette.placeholderText
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
                        cursorShape: row.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: mode.activate(row.index)
                    }
                }

                // password field (only on the row asking for it)
                Loader {
                    active: row.asking
                    y: mode.rowsLook.rowHeight
                    width: parent.width
                    height: mode.layout.fieldHeight
                    sourceComponent: Rectangle {
                        radius: Config.corner("pill", height)
                        color: Qt.alpha(palette.windowText, mode.layout.tileOpacity)
                        Component.onCompleted: password.forceActiveFocus()

                        Icon {
                            id: fieldLock
                            x: mode.rowsLook.rowPadding
                            anchors.verticalCenter: parent.verticalCenter
                            width: mode.layout.lockSize
                            height: mode.layout.lockSize
                            name: mode.layout.lockIcon
                            color: palette.placeholderText
                        }
                        // × : cancel
                        Badge {
                            id: cancel
                            anchors.right: parent.right
                            anchors.rightMargin: mode.layout.cancelInset
                            anchors.verticalCenter: parent.verticalCenter
                            height: parent.height - 2 * mode.layout.cancelInset
                            // concentric with the field it sits in
                            outerCorner: parent.radius
                            inset: mode.layout.cancelInset
                            icon: mode.layout.cancelIcon
                            glyphSize: mode.layout.cancelGlyphSize
                            tint: palette.windowText
                            clickable: true
                            onClicked: mode.cancelPassword()
                        }
                        TextInput {
                            id: password
                            anchors.left: fieldLock.right
                            anchors.leftMargin: mode.rowsLook.rowPadding
                            anchors.right: cancel.left
                            anchors.rightMargin: mode.rowsLook.rowPadding
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: TextInput.Password
                            color: palette.windowText
                            font.family: Config.font.family
                            font.variableAxes: Config.axes(Config.font.size, Config.font.weight)
                            font.weight: Config.font.weight
                            font.pixelSize: Config.font.size
                            clip: true
                            Keys.onReturnPressed: mode.submitPassword(text)
                            Keys.onEnterPressed: mode.submitPassword(text)
                            Keys.onEscapePressed: mode.cancelPassword()
                            // another network picked with the arrows: leave password entry
                            Keys.onUpPressed: mode.step(-1)
                            Keys.onDownPressed: mode.step(1)

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: password.text.length === 0
                                color: palette.placeholderText
                                text: mode.layout.passwordPlaceholder.arg(row.name)
                            }
                        }
                    }
                }
            }
        }
    }
}
