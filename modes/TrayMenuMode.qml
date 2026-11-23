pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import "../services"
import "../island"
import "../widgets"

// A tray icon's menu (the "tray" dropdown, under the icon of Activity.trayId's app), drawn by the shell in
// the menus' look (panel.menu.*): the app's name, then its menu's rows (Sys.trayMenu: the app's own
// DBus menu, read with QsMenuOpener): a name and its icon, groups split by a thin line, a check on the
// ticked ones, a › on those that open a submenu (a click goes into it, "‹ Back" comes out), dimmed ones
// do nothing. A click runs the row in the app and closes the menu. Keyboard: Up / Down, Enter / Space,
// Left / Backspace = back. (The system's own drawing of these menus needs Quickshell running as a widgets
// app: it did nothing here.)
IslandMode {
    id: mode

    readonly property var look: Config.panel.menu
    readonly property string trayId: Activity.trayId
    readonly property string title: Sys.trayTitle(trayId)

    // the submenus opened, deepest last (a new app's menu starts at the top)
    property var stack: []
    onTrayIdChanged: stack = []
    onActiveChanged: {
        if (active) {
            stack = [];
            selected = 0;
            keyShown = !!island && island.keyboardOpened;
        }
    }
    QsMenuOpener {
        id: top
        menu: Sys.trayMenu(mode.trayId)
    }
    QsMenuOpener {
        id: sub
        menu: mode.stack.length > 0 ? mode.stack[mode.stack.length - 1] : null
    }
    // the rows shown: the submenu's, after a "back" row, or the menu's own
    readonly property bool inSub: stack.length > 0
    readonly property var entries: (inSub ? sub.children : top.children) ? (inSub ? sub.children : top.children).values : []
    readonly property int count: entries.length + (inSub ? 1 : 0)
    function entry(i) {
        return inSub ? (i === 0 ? null : entries[i - 1]) : entries[i];
    }
    function isSeparator(i) {
        const e = entry(i);
        return !!e && e.isSeparator;
    }
    function rowHeight(i) {
        return isSeparator(i) ? look.separatorHeight : look.rowHeight;
    }
    function rowY(i) {
        let y = 0;
        for (let j = 0; j < i; j++)
            y += rowHeight(j);
        return y;
    }
    readonly property real rowsHeight: {
        let y = 0;
        for (let j = 0; j < count; j++)
            y += rowHeight(j);
        return y;
    }
    function rowAt(y) {
        for (let i = 0; i < count; i++)
            if (y >= rowY(i) && y < rowY(i) + rowHeight(i))
                return isSeparator(i) ? -1 : i;
        return -1;
    }
    function usable(i) {
        if (inSub && i === 0)
            return true;
        const e = entry(i);
        return !!e && !e.isSeparator && e.enabled;
    }
    // the app's label without its keyboard-shortcut marks ("_Quit", "&Open"; doubled = a real one)
    function label(e) {
        return String(e.text || "").replace(/__/g, "\u0001").replace(/&&/g, "\u0002").replace(/[_&]/g, "").replace(/\u0001/g, "_").replace(/\u0002/g, "&");
    }

    function pick(i, byKey) {
        if (!usable(i))
            return;
        if (inSub && i === 0) {
            stack = stack.slice(0, -1);
            selected = 0;
            return;
        }
        const e = entry(i);
        if (e.hasChildren) {
            stack = stack.concat([e]);
            selected = 0;
            return;
        }
        e.triggered();
        if (byKey)
            holdKeyboard();
        requestState("idle");
    }

    // ---- keyboard ----
    keyTarget: mode
    property int selected: 0
    property bool keyShown: false
    // one selection for the pointer and the keys: the pointer sets it only when it moves, so with the
    // pointer resting on a row the keys take over (and the next move of the pointer takes it back)
    function move(dir) {
        if (keyShown || rows.pointerIn) {
            let i = selected;
            do
                i += dir;
            while (i >= 0 && i < count && !usable(i));
            if (i >= 0 && i < count)
                selected = i;
        }
        // the first key shows the highlight; on a row that can't be used (a greyed status line), it goes to
        // the first one that can
        else if (!usable(selected))
            for (let i = 0; i < count; i++)
                if (usable(i)) {
                    selected = i;
                    break;
                }
        keyShown = true;
    }
    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onReturnPressed: pick(selected, true)
    Keys.onEnterPressed: pick(selected, true)
    Keys.onSpacePressed: pick(selected, true)
    Keys.onLeftPressed: if (inSub)
        pick(0, true)
    Keys.onRightPressed: {
        const e = entry(selected);
        if (e && e.hasChildren)
            pick(selected, true);
    }

    readonly property real headerHeight: title === "" ? 0 : look.titleHeight + look.headerGap
    implicitWidth: look.width
    implicitHeight: 2 * Config.panel.padding + headerHeight + Math.max(rowsHeight, look.rowHeight)

    Item {
        x: Config.panel.padding
        y: Config.panel.padding
        width: mode.implicitWidth - 2 * Config.panel.padding
        height: mode.implicitHeight - 2 * Config.panel.padding

        StyledText {
            visible: mode.title !== ""
            x: Config.panel.list.rowPadding
            width: parent.width - 2 * Config.panel.list.rowPadding
            height: mode.look.titleHeight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            font.pixelSize: Config.panel.header.titleSize
            font.weight: Config.panel.header.titleWeight
            text: mode.title
        }

        // the app's menu is still being read
        StyledText {
            visible: mode.count === 0
            x: Config.panel.list.rowPadding
            y: mode.headerHeight
            height: mode.look.rowHeight
            verticalAlignment: Text.AlignVCenter
            color: palette.placeholderText
            text: Config.tray.emptyText
        }

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
                model: mode.count
                delegate: Item {
                    id: row
                    required property int index
                    readonly property var e: mode.entry(index)
                    readonly property bool back: mode.inSub && index === 0
                    readonly property bool separator: !!e && e.isSeparator
                    y: mode.rowY(index)
                    width: rows.width
                    height: mode.rowHeight(index)
                    opacity: separator || mode.usable(index) ? 1 : mode.look.disabledOpacity

                    Rectangle {
                        visible: row.separator
                        x: Config.panel.list.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 2 * Config.panel.list.rowPadding
                        height: mode.look.separatorWidth
                        color: palette.windowText
                        opacity: mode.look.separatorOpacity
                    }
                    // the app's icon for the row (an image from the app), or the back arrow
                    Item {
                        id: rowIcon
                        visible: !row.separator
                        x: Config.panel.list.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: row.back || (row.e && row.e.icon !== "") ? mode.look.iconSize : 0
                        height: mode.look.iconSize
                        Icon {
                            visible: row.back
                            anchors.fill: parent
                            name: Config.tray.backIcon
                            color: palette.windowText
                        }
                        Image {
                            visible: !row.back
                            anchors.fill: parent
                            source: row.e && !row.back ? row.e.icon || "" : ""
                            sourceSize.width: width * 2
                            sourceSize.height: height * 2
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                    }
                    StyledText {
                        visible: !row.separator
                        anchors.left: rowIcon.right
                        anchors.leftMargin: rowIcon.width > 0 ? mode.look.iconGap : 0
                        anchors.right: trailing.left
                        anchors.rightMargin: Config.panel.list.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.back ? Config.tray.backText : row.e ? mode.label(row.e) : ""
                    }
                    // a check on a ticked row, a › on one that opens a submenu
                    Icon {
                        id: trailing
                        visible: !row.separator && !row.back && !!row.e && ((row.e.buttonType > 0 && row.e.checkState === Qt.Checked) || row.e.hasChildren)
                        anchors.right: parent.right
                        anchors.rightMargin: Config.panel.list.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: mode.look.iconSize
                        height: width
                        name: row.e && row.e.hasChildren ? Config.tray.submenuIcon : Config.panel.list.checkIcon
                        color: row.e && row.e.hasChildren ? palette.placeholderText : Config.colors.accent
                    }
                    TapHandler {
                        onTapped: mode.pick(row.index, false)
                    }
                }
            }
        }
    }
}
