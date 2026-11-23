pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// A menu dropdown, like a macOS menu: an optional title (and a grey line under it), then rows (icon +
// name), in groups split by a thin line. Used by the bar's app name (the window's actions) and its logo
// (the system's). `items` is a menuList setting: each row runs its `command` ({id} = the focused window,
// Sys.runMenuCommand) or opens something (`open`: a dropdown, "notifications", "media"); `confirm` asks for
// a second click (the row says panel.menu.confirmText for panel.menu.confirmTimeout); `danger` = red;
// `separator` = a line above it. A row whose command needs the focused window ({id}) is dimmed and does
// nothing without one. The highlight springs to the row under the pointer or the keyboard's (Up / Down,
// Enter / Space); a picked row closes the menu.
IslandMode {
    id: mode

    property string title
    property string subtitle
    property var items: []
    // a row's title and icon now: a row with `state` (a key of Sys.focusedState: floating, maximized,
    // fullscreen) shows its `onTitle` / `onIcon` while that state is on (Float -> Tile, Maximize -> Restore)
    function stateOn(it) {
        return !!it && !!it.state && !!Sys.focusedState[it.state];
    }
    function titleOf(it) {
        return stateOn(it) && it.onTitle ? it.onTitle : it.title;
    }
    function iconOf(it) {
        return stateOn(it) && it.onIcon ? it.onIcon : it.icon || "";
    }

    readonly property var look: Config.panel.menu
    readonly property real headerHeight: title === "" ? 0 : look.titleHeight + (subtitle !== "" ? look.subtitleHeight : 0) + look.headerGap

    // y of row i inside the rows, and the rows' total height (each separator adds its own band)
    function rowY(i) {
        let y = 0;
        for (let j = 0; j < i; j++)
            y += look.rowHeight + (items[j + 1] && items[j + 1].separator ? look.separatorHeight : 0);
        return y + (items[0] && items[0].separator ? look.separatorHeight : 0);
    }
    readonly property real rowsHeight: items.length === 0 ? 0 : rowY(items.length - 1) + look.rowHeight
    function rowAt(y) {
        for (let i = 0; i < items.length; i++)
            if (y >= rowY(i) && y < rowY(i) + look.rowHeight)
                return i;
        return -1;
    }
    function usable(i) {
        const it = items[i];
        return !!it && !(Sys.focusedWindow < 0 && (it.command || []).some(a => a.indexOf("{id}") >= 0));
    }

    implicitWidth: look.width
    implicitHeight: 2 * Config.panel.padding + headerHeight + rowsHeight

    // ---- picking ----
    property int armed: -1
    Timer {
        id: disarm
        interval: mode.look.confirmTimeout
        onTriggered: mode.armed = -1
    }
    // (from the keyboard: hold the key until it's released, see IslandMode.close)
    function pick(i, byKey) {
        if (!usable(i))
            return;
        const it = items[i];
        if (it.confirm && armed !== i) {
            armed = i;
            disarm.restart();
            return;
        }
        armed = -1;
        if (byKey)
            holdKeyboard();
        if (it.open) {
            requestState(it.open);
            return;
        }
        if (it.command)
            Sys.runMenuCommand(it.command);
        requestState("idle");
    }

    // ---- keyboard ----
    keyTarget: mode
    property int selected: 0
    property bool keyShown: false
    onActiveChanged: {
        if (active) {
            selected = 0;
            armed = -1;
            keyShown = !!island && island.keyboardOpened;
        }
    }
    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onReturnPressed: pick(selected, true)
    Keys.onEnterPressed: pick(selected, true)
    Keys.onSpacePressed: pick(selected, true)
    // one selection for the pointer and the keys: the pointer sets it only when it moves, so with the
    // pointer resting on a row the keys take over (and the next move of the pointer takes it back)
    function move(dir) {
        if (keyShown || rows.pointerIn) {
            let i = selected;
            do
                i += dir;
            while (i >= 0 && i < items.length && !usable(i));
            if (i >= 0 && i < items.length)
                selected = i;
        }
        // the first key shows the highlight; on a row that can't be used (a greyed status line), it goes to
        // the first one that can
        else if (!usable(selected))
            for (let i = 0; i < items.length; i++)
                if (usable(i)) {
                    selected = i;
                    break;
                }
        keyShown = true;
    }

    Item {
        x: Config.panel.padding
        y: Config.panel.padding
        width: mode.implicitWidth - 2 * Config.panel.padding
        height: mode.implicitHeight - 2 * Config.panel.padding

        // ---- title ----
        Column {
            visible: mode.title !== ""
            x: Config.panel.list.rowPadding
            width: parent.width - 2 * Config.panel.list.rowPadding
            StyledText {
                width: parent.width
                height: mode.look.titleHeight
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.pixelSize: Config.panel.header.titleSize
                font.weight: Config.panel.header.titleWeight
                text: mode.title
            }
            StyledText {
                visible: mode.subtitle !== ""
                width: parent.width
                height: mode.look.subtitleHeight
                verticalAlignment: Text.AlignTop
                elide: Text.ElideRight
                font.pixelSize: mode.look.subtitleSize
                color: palette.placeholderText
                text: mode.subtitle
            }
        }

        // ---- rows ----
        Item {
            id: rows
            y: mode.headerHeight
            width: parent.width
            height: mode.rowsHeight

            readonly property bool pointerIn: hover.hovered
            readonly property int lit: hover.hovered || mode.keyShown ? mode.selected : -1
            MovedHover {
                id: hover
                cursorShape: mode.usable(mode.rowAt(point.position.y)) ? Qt.PointingHandCursor : Qt.ArrowCursor
                onMoved: position => {
                    const i = mode.rowAt(position.y);
                    if (i >= 0) {
                        mode.keyShown = false;
                        mode.selected = i;
                    }
                }
            }
            RowHighlight {
                height: mode.look.rowHeight
                rowY: mode.rowY(Math.max(0, rows.lit))
                shown: rows.lit >= 0 && mode.usable(rows.lit)
            }
            Repeater {
                model: mode.items
                delegate: Item {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property color tint: modelData.danger ? Config.colors.danger : palette.windowText
                    y: mode.rowY(index)
                    width: rows.width
                    height: mode.look.rowHeight
                    opacity: mode.usable(index) ? 1 : mode.look.disabledOpacity

                    // a thin line above a new group
                    Rectangle {
                        visible: !!row.modelData.separator
                        x: Config.panel.list.rowPadding
                        y: -mode.look.separatorHeight / 2
                        width: parent.width - 2 * Config.panel.list.rowPadding
                        height: mode.look.separatorWidth
                        color: palette.windowText
                        opacity: mode.look.separatorOpacity
                    }
                    Icon {
                        id: rowIcon
                        x: Config.panel.list.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: mode.look.iconSize
                        height: width
                        name: mode.iconOf(row.modelData)
                        color: row.tint
                    }
                    StyledText {
                        anchors.left: rowIcon.right
                        anchors.leftMargin: mode.look.iconGap
                        anchors.right: parent.right
                        anchors.rightMargin: Config.panel.list.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        color: row.tint
                        text: mode.armed === row.index ? mode.look.confirmText.arg(mode.titleOf(row.modelData)) : mode.titleOf(row.modelData)
                    }
                    TapHandler {
                        onTapped: mode.pick(row.index, false)
                    }
                }
            }
        }
    }
}
