pragma ComponentBehavior: Bound

import QtQuick

import "../services"

// A quick settings switch that opens into a menu (the power mode). At rest it's a QuickToggle: a round
// badge with the current choice's icon (solid in its tint, soft when the tint is the text color, e.g.
// balanced) and the choice's word in grey under it. Pressed: the badge sinks, and before the sink is over
// (handoff) the badge itself morphs into a menu of every choice, at (menuX, menuY) from this item (the
// mode opens it down and to the left, kept inside the panel): position, size and corner on one spring that
// doesn't overshoot, the glyph and the word fading out, the rows fading and sliding in one after another.
// A row picks its choice and closes; so does `close()` (the mode calls it for Escape and clicks elsewhere).
// The open menu keeps the badge's own soft color (the current choice's tint over the island, made opaque so
// it covers what's under it), no outline; the mode blurs the rest of the panel behind it (`t`).
// Keyboard (driven by the mode, which also highlights the badge's tile): openFromKeys() opens it with the
// current row lit, moveKey(±1) moves the lit row, pickKey() picks it. The pointer lights rows the same way.
// Settings: quickSettings.toggle (the badge, the word), quickSettings.power.menu (the menu and the motion).
Item {
    id: menu

    // choices: [{ icon, text, tint }]
    property var model: []
    property int current: 0
    // where the open menu sits, from this item's top-left
    property real menuX: 0
    property real menuY: 0
    signal picked(int index)

    readonly property bool open: _open
    function close() {
        _open = false;
    }

    // ---- keyboard ----
    // the lit row (keyboard or pointer); -1 = none
    property int keyRow: -1
    function openFromKeys() {
        if (_open)
            return;
        keyRow = current;
        _pressed();
    }
    function moveKey(step) {
        keyRow = Math.max(0, Math.min(model.length - 1, (keyRow < 0 ? current : keyRow) + step));
    }
    function pickKey() {
        if (keyRow >= 0)
            picked(keyRow);
        close();
    }
    on_OpenChanged: if (!_open)
        keyRow = -1

    readonly property var cfg: Config.quickSettings.power.menu
    readonly property var toggle: Config.quickSettings.toggle
    readonly property var choice: model.length > current ? model[current] : null
    readonly property color tint: choice ? choice.tint : Config.colors.text
    // solid in the choice's color; soft when that color is plain text (balanced: nothing special on)
    readonly property bool solid: !Qt.colorEqual(tint, Config.colors.text)
    // the open menu's surface: the soft badge's color, opaque (the current choice's tint over the island)
    readonly property color surface: Qt.tint(Config.island.color, Qt.alpha(tint, Config.activity.badgeOpacity))

    // ---- sizes ----
    readonly property real badgeSize: toggle.badgeSize
    readonly property real badgeX: (width - badgeSize) / 2
    readonly property real menuWidth: cfg.width
    readonly property real menuHeight: 2 * cfg.inset + model.length * cfg.rowHeight + Math.max(0, model.length - 1) * cfg.rowGap
    // rows round like pills, the menu concentric around them
    readonly property real rowCorner: Config.corner("pill", cfg.rowHeight)
    readonly property real menuCorner: Math.min(rowCorner + cfg.inset, menuHeight / 2)

    implicitHeight: toggle.badgeSize + toggle.wordGap + word.implicitHeight

    // ---- state ----
    property bool _open: false
    // 0 = the badge, 1 = the menu: position, size, corner and fill all follow this one spring
    property real openness: _open ? 1 : 0
    Behavior on openness {
        SpringAnimation {
            spring: Config.spring(menu.cfg.spring).spring
            damping: Config.spring(menu.cfg.spring).damping
            epsilon: 0.002
        }
    }
    readonly property real t: Math.max(0, Math.min(1, openness))

    // the press: sink fast, and open while the sink is still running (there's never a still frame)
    property real press: 1
    NumberAnimation {
        id: pressAnim
        target: menu
        property: "press"
        easing.type: Easing.OutQuint
    }
    function _sinkTo(value, duration) {
        pressAnim.stop();
        pressAnim.to = value;
        pressAnim.duration = duration;
        pressAnim.start();
    }
    property real _contentOut: 1
    NumberAnimation {
        id: contentOut
        target: menu
        property: "_contentOut"
        from: 1
        to: 0
        duration: menu.cfg.labelFade
        easing.type: Easing.OutCubic
    }
    // the hover tint, only for a pointer really on the badge: the HoverHandler is off while the menu is
    // open and keeps its stale "hovered" from the press when it comes back on, so the closing shape landed
    // in the hover color, then flashed to the normal one. Lit again only once the pointer moves over it.
    property bool _hoverSeen: true
    readonly property bool _hoverLit: hover.hovered && !_open && _hoverSeen
    function _pressed() {
        _hoverSeen = false;
        _sinkTo(Config.motion.pressScale, cfg.sinkDuration);
        handoff.restart();
    }
    Timer {
        id: handoff
        interval: menu.cfg.handoff
        onTriggered: {
            menu._sinkTo(1, menu.cfg.releaseDuration);
            contentOut.restart();
            menu._open = true;
        }
    }
    // opening: the glyph and word fade out over labelFade; closing: they come back only as the shape gets
    // near the badge again (labelReturn), so they never show over the rows
    readonly property real contentOpacity: _open ? _contentOut : Math.max(0, 1 - openness / cfg.labelReturn)

    // ---- the shape: the badge's fill cross-fading into the menu's surface ----
    Item {
        id: body
        x: menu.badgeX + (menu.menuX - menu.badgeX) * menu.openness
        y: menu.menuY * menu.openness
        width: menu.badgeSize + (menu.menuWidth - menu.badgeSize) * menu.openness
        height: menu.badgeSize + (menu.menuHeight - menu.badgeSize) * menu.openness
        scale: menu.press
        readonly property real corner: Math.min(height / 2, menu.badgeSize / 2 + (menu.menuCorner - menu.badgeSize / 2) * menu.t)

        // the menu's surface, under the badge's fill: the soft badge's color made opaque, from the first
        // frame of the press, so nothing under the growing shape shows through and the color doesn't change
        // as it opens (at rest it's off: with island.blur the soft badge stays see-through)
        Rectangle {
            anchors.fill: parent
            radius: body.corner
            color: menu.surface
            visible: menu.openness > 0.001 || menu.press < 1
        }
        Rectangle {
            anchors.fill: parent
            radius: body.corner
            color: menu.solid ? menu.tint : Qt.alpha(menu.tint, menu._hoverLit ? Config.activity.badgeHoverOpacity : Config.activity.badgeOpacity)
            opacity: 1 - menu.t
            Behavior on color {
                ColorAnimation {
                    duration: Config.motion.colorFade
                }
            }
        }
        Icon {
            anchors.centerIn: parent
            width: menu.toggle.glyphSize
            height: menu.toggle.glyphSize
            name: menu.choice ? menu.choice.icon : ""
            color: menu.solid ? Config.onColor(menu.tint) : menu.tint
            opacity: menu.contentOpacity
        }
        HoverHandler {
            id: hover
            enabled: !menu._open
            onPointChanged: if (enabled && hovered)
                menu._hoverSeen = true
            onHoveredChanged: if (!hovered)
                menu._hoverSeen = true
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: !menu._open
            onTapped: menu._pressed()
        }
    }

    StyledText {
        id: word
        y: menu.toggle.badgeSize + menu.toggle.wordGap
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: menu.toggle.wordSize
        color: Config.colors.secondary
        opacity: menu.contentOpacity
        text: menu.choice ? menu.choice.text : ""
    }

    // ---- the rows, inside the open menu: clipped to the growing shape, so none shows outside it ----
    Item {
        x: body.x
        y: body.y
        width: body.width
        height: body.height
        scale: body.scale
        clip: true
        visible: menu.openness > 0.001
        // the open menu takes every click on it (between and around the rows too): nothing under it reacts
        MouseArea {
            anchors.fill: parent
            enabled: menu._open
        }
        // the lit row (keyboard or pointer): one highlight that springs from row to row (the Wi-Fi /
        // Bluetooth lists' look, opacity and spring: panel.list); it fades in where it is, then slides
        Rectangle {
            id: lit
            readonly property int row: Math.max(0, menu.keyRow)
            x: menu.menuX + menu.cfg.inset - parent.x
            y: menu.menuY + menu.cfg.inset - parent.y + row * (menu.cfg.rowHeight + menu.cfg.rowGap)
            width: menu.menuWidth - 2 * menu.cfg.inset
            height: menu.cfg.rowHeight
            radius: menu.rowCorner
            color: Config.colors.text
            opacity: menu.keyRow >= 0 && menu._open ? Config.panel.list.selectedOpacity : 0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Config.motion.hoverFade
                }
            }
            Behavior on y {
                enabled: lit.visible
                SpringAnimation {
                    spring: Config.spring(Config.panel.list.highlight).spring
                    damping: Config.spring(Config.panel.list.highlight).damping
                    epsilon: 0.25
                }
            }
        }
        Column {
            x: menu.menuX + menu.cfg.inset - parent.x
            y: menu.menuY + menu.cfg.inset - parent.y
            width: menu.menuWidth - 2 * menu.cfg.inset
            spacing: menu.cfg.rowGap
            enabled: menu._open

            Repeater {
                model: menu.model
                Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: menu.cfg.rowHeight

                    // fade + slide in, one after another; out all at once
                    property real shown: 0
                    opacity: shown
                    transform: Translate {
                        y: (1 - row.shown) * menu.cfg.rowTravel
                    }
                    Connections {
                        target: menu
                        function onOpenChanged() {
                            rowIn.stop();
                            wait.duration = menu._open ? menu.cfg.rowDelay + row.index * menu.cfg.rowStagger : 0;
                            fade.to = menu._open ? 1 : 0;
                            fade.duration = menu._open ? menu.cfg.rowSlide : menu.cfg.labelFade;
                            rowIn.start();
                        }
                    }
                    SequentialAnimation {
                        id: rowIn
                        PauseAnimation {
                            id: wait
                        }
                        NumberAnimation {
                            id: fade
                            target: row
                            property: "shown"
                            easing.type: Easing.OutQuint
                        }
                    }

                    Icon {
                        id: rowIcon
                        x: menu.cfg.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: menu.cfg.iconSize
                        height: menu.cfg.iconSize
                        name: row.modelData.icon
                        color: row.modelData.tint
                    }
                    StyledText {
                        anchors.left: rowIcon.right
                        anchors.leftMargin: menu.cfg.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: menu.cfg.textSize
                        text: row.modelData.text || ""
                    }
                    Icon {
                        visible: row.index === menu.current
                        anchors.right: parent.right
                        anchors.rightMargin: menu.cfg.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: Config.panel.list.checkSize
                        height: Config.panel.list.checkSize
                        name: Config.panel.list.checkIcon
                        color: Config.colors.text
                    }
                    HoverHandler {
                        id: rowHover
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: if (hovered)
                            menu.keyRow = row.index
                    }
                    // a MouseArea, not a TapHandler: it takes the click, so the switch under the menu (the
                    // mic) doesn't get it too (a TapHandler only listens, the tap went through)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            menu.picked(row.index);
                            menu.close();
                        }
                    }
                }
            }
        }
    }
}
