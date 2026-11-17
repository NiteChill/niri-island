pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

import "../services"
import "../island"
import "../widgets"

// Wi-Fi panel, an instrument like the battery panel (size, motion and the pill: the shared Panels settings):
//  - on top, centred: the network's name (or "Off" / "Not connected"); a new name rolls in (RollingName)
//  - the Wi-Fi icon, big: the idle icon's dot and two round-capped arcs with its own proportions, scaled
//    up (not the icon file: strokes, so they stay crisp and animate). Lit in blue up to the connection's
//    bars (the dot is the first), grey above. Opening (and joining a network) lights it from the dot out,
//    each part fading from grey to blue. While searching (nothing found yet) or connecting, a ripple runs
//    out through it; a failed attempt shakes it and flashes it red (the motion is GlyphMotion's, shared
//    with the Bluetooth panel). The symbol is also the switch: click it (or press Space) to turn Wi-Fi on / off. It brightens under
//    the pointer and sinks a little when pressed; turning off fades the lit parts back to grey, outer first
//  - the nearby networks, right under the symbol (or behind a pill "Networks · 7" (ExpandPill) that unfolds
//    them, panel.collapsibleList) (Sys.wifiNetworks, scanned only while this
//    panel is open) in two groups, saved then others. Each row: signal bars, the name, a lock when
//    secured, a blue check / "Connecting…" / what went wrong in red. Click (or Up/Down + Enter): saved and
//    open networks connect right away; a new secured one (or one whose last attempt failed) opens a
//    password field under its row. Enter connects; Escape, the ×, or the arrows cancel
// The list is a ListView fed by a ListModel updated in place (only the rows on screen exist; scan
// updates change rows instead of rebuilding them). Up/Down or Enter unfold it from the keyboard.
IslandMode {
    id: mode

    readonly property var layout: Config.wifi
    // the rows' look, shared with the other list panel (PanelList)
    readonly property var rowsLook: Config.panel.list
    readonly property var look: Config.wifi.hero
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

    // ---- the list unfolds from the pill ----
    // panel.collapsibleList: the list waits behind the pill until it's clicked; otherwise (the default) it
    // shows right away and there's no pill (Wi-Fi keeps a plain "Searching…" one until something is found)
    readonly property bool collapsible: Config.panel.collapsibleList
    property bool expanded: false
    readonly property bool listShown: wifiOn && (expanded || !collapsible)

    // keyboard: Up/Down pick a network, Enter connects (both unfold the list first); Escape closes the
    // panel (IslandMode), or cancels the password field when it's open
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
                motion.fail();
            } else if (!n || n.connected) {
                attempt = "";
            }
        }
    }
    Keys.onUpPressed: step(-1)
    Keys.onDownPressed: step(1)
    // move the selection with the keyboard; leaves password entry (that network is no longer the one picked)
    function step(dir) {
        if (!wifiOn)
            return;
        if (!listShown) {
            expanded = true;
            return;
        }
        if (asking !== "")
            cancelPassword();
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
        if (!wifiOn)
            return;
        if (!listShown)
            expanded = true;
        else
            activate(selected);
    }

    // name of the network asking for a password ("" = none), and of the last one we tried to join
    property string asking: ""
    property string attempt: ""
    onActiveChanged: {
        if (active) {
            networks = Qt.binding(() => Sys.wifiNetworks);
            list.reset();
            motion.replay(true);
        } else
            networks = networks;
    }
    // reset once fully gone, not while it animates out (the highlight jumped, the list collapsed)
    onOnScreenChanged: {
        if (!onScreen) {
            asking = "";
            selected = 0;
            expanded = false;
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

    // ---- the name on top: rolls when it changes ----
    readonly property string heroName: {
        if (!wifiOn)
            return look.offText;
        if (Sys.wifi.connected)
            return Sys.wifi.ssid;
        const n = networks.find(n => n.connecting);
        return n ? n.name : layout.notConnectedText;
    }

    // ---- the symbol ----
    // the idle Wi-Fi icon (assets/icons/wifi3.svg) redrawn big: a dot and two round-capped arcs with the
    // icon's own proportions (glyph.*, in the icon's 24-unit grid, times glyph.scale). The dot is the first
    // bar, like the small icons: 1 bar = the dot, 2 = + the inner arc, 3 = all. Its motion is GlyphMotion's
    GlyphMotion {
        id: motion
        active: mode.active
        parts: 3
        live: mode.wifiOn && Sys.wifi.connected ? Math.min(3, Sys.wifi.bars) : 0
        rippling: mode.onScreen && mode.wifiOn && (mode.connecting || mode.networks.length === 0)
        fast: mode.connecting
        hovered: glyphHover.hovered
    }
    // joining another network while the panel is open lights it up again
    readonly property string ssid: Sys.wifi.connected ? Sys.wifi.ssid : ""
    onSsidChanged: {
        if (active && ssid !== "")
            motion.replay(false);
    }

    // one arc of the symbol: a round-capped stroke on a circle around (cx, cy), centred on straight up
    component Arc: ShapePath {
        property real cx
        property real cy
        property real r
        property real span
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathAngleArc {
            centerX: cx
            centerY: cy
            radiusX: r
            radiusY: r
            startAngle: -90 - span / 2
            sweepAngle: span
        }
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
    // what's shown: all of it, up to hero.visibleRows rows (plus a group title), then it scrolls
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

    // ---- panel size ----
    // the symbol, in px: the icon's grid times glyph.scale. The arcs' common centre sits centerDrop below
    // the dot's centre; the outer arc's top edge is the symbol's top, the dot's bottom its bottom
    readonly property real gs: look.glyph.scale
    readonly property real glyphTop: (look.glyph.outerRadius + look.glyph.thickness / 2) * gs     // centre -> top
    readonly property real glyphHeight: glyphTop - look.glyph.centerDrop * gs + look.glyph.dotRadius * gs
    readonly property real glyphWidth: 2 * gs * (look.glyph.outerRadius * Math.sin(look.glyph.outerSpan / 2 * Math.PI / 180) + look.glyph.thickness / 2)
    readonly property real heroHeight: nameBox.height + Config.panel.nameGap + glyphHeight
    // the pill: to unfold the list, or (list always shown) just "Searching…" until a network shows up
    readonly property bool pillShown: wifiOn && (collapsible || networks.length === 0)
    readonly property real pillRoom: pillShown ? Config.panel.pill.gap + Config.panel.pill.height : 0
    readonly property real listRoom: listShown && networks.length > 0 ? (collapsible ? Config.panel.pill.listGap : Config.panel.listGap) + viewHeight : 0

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
            color: mode.wifiOn ? Config.colors.text : Config.colors.secondary
            text: mode.heroName
        }

        // ---- the symbol ----
        Item {
            id: glyph
            anchors.top: nameBox.bottom
            anchors.topMargin: Config.panel.nameGap
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: motion.shake
            width: mode.glyphWidth
            height: mode.glyphHeight

            // the arcs' centre, and the dot's
            readonly property real cx: width / 2
            readonly property real cy: mode.glyphTop
            readonly property real dotY: cy - mode.look.glyph.centerDrop * mode.gs
            readonly property real stroke: mode.look.glyph.thickness * mode.gs
            readonly property real inner: mode.look.glyph.innerRadius * mode.gs
            readonly property real outer: mode.look.glyph.outerRadius * mode.gs

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                Arc {
                    cx: glyph.cx
                    cy: glyph.cy
                    r: glyph.inner
                    span: mode.look.glyph.innerSpan
                    strokeWidth: glyph.stroke
                    strokeColor: motion.partColor(1)
                }
                Arc {
                    cx: glyph.cx
                    cy: glyph.cy
                    r: glyph.outer
                    span: mode.look.glyph.outerSpan
                    strokeWidth: glyph.stroke
                    strokeColor: motion.partColor(2)
                }
            }

            Rectangle {
                id: dot
                width: 2 * mode.look.glyph.dotRadius * mode.gs
                height: width
                radius: width / 2
                x: glyph.cx - width / 2
                y: glyph.dotY - height / 2
                color: motion.partColor(0)
            }

            // the symbol is the Wi-Fi switch
            scale: glyphTap.pressed ? Config.motion.pressScale : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Config.motion.pressDuration
                    easing.type: Easing.OutCubic
                }
            }
            HoverHandler {
                id: glyphHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: glyphTap
                onTapped: mode.toggleWifi()
            }
        }

        // ---- the pill that unfolds the list ----
        ExpandPill {
            id: pill
            visible: mode.pillShown
            anchors.top: glyph.bottom
            anchors.topMargin: Config.panel.pill.gap
            anchors.horizontalCenter: parent.horizontalCenter
            showArrow: mode.collapsible && mode.networks.length > 0
            expanded: mode.expanded
            text: mode.networks.length === 0 ? mode.layout.searchingText : mode.look.pillText.arg(mode.networks.length)
            onClicked: mode.expanded = !mode.expanded
        }

        // ---- networks ----
        PanelList {
            id: list
            visible: mode.listShown && mode.networks.length > 0
            anchors.top: mode.collapsible ? pill.bottom : glyph.bottom
            anchors.topMargin: mode.collapsible ? Config.panel.pill.listGap : Config.panel.listGap
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
                readonly property color tint: connected ? Config.colors.accent : Config.colors.text
                readonly property bool asking: mode.asking !== "" && mode.asking === name

                width: list.width
                height: mode.rowsLook.rowHeight + (asking ? mode.layout.fieldHeight + mode.layout.fieldGap : 0)

                Item {
                    id: line
                    width: parent.width
                    height: mode.rowsLook.rowHeight

                    // signal, like the idle island: all bars dimmed, the real ones bright on top
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
                            color: row.failed ? Config.colors.danger : Config.colors.secondary
                            text: row.connecting ? mode.layout.connectingText : row.failed ? mode.layout.failedText : ""
                        }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.secure
                            width: mode.layout.lockSize
                            height: mode.layout.lockSize
                            name: mode.layout.lockIcon
                            color: Config.colors.secondary
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
                        color: Qt.alpha(Config.colors.text, mode.layout.tileOpacity)
                        Component.onCompleted: password.forceActiveFocus()

                        Icon {
                            id: fieldLock
                            x: mode.rowsLook.rowPadding
                            anchors.verticalCenter: parent.verticalCenter
                            width: mode.layout.lockSize
                            height: mode.layout.lockSize
                            name: mode.layout.lockIcon
                            color: Config.colors.secondary
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
                            tint: Config.colors.text
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
                            color: Config.font.color
                            font.family: Config.font.family
                            font.variableAxes: ({
                                    "ROND": Config.font.roundness
                                })
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
                                color: Config.colors.secondary
                                text: mode.layout.passwordPlaceholder.arg(row.name)
                            }
                        }
                    }
                }
            }
        }
    }
}
