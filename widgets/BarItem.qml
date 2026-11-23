import QtQuick

import "../services"

// One thing in the bar (an icon, the clock, the workspaces): a pill lights up behind it under the pointer
// (bar.item.hoverOpacity) and stays lit while its dropdown is open (bar.item.openOpacity), like the macOS
// menu bar. Only something that does something when clicked lights up or shows the hand (`clickable`):
// a highlight promises a click. A click opens its dropdown (`dropdown`: Activity's name for it) or closes
// it; without a dropdown the click is the owner's (`clicked`, with the button and where, in the item).
// While any dropdown is open, moving onto another item asks the bar to switch to its dropdown
// (`wantsOpen`); the bar decides when (Bar.aimTo: not while the pointer is heading into the open one).
Item {
    id: item

    property string dropdown: ""
    property bool shown: true
    property bool clickable: dropdown !== ""
    default property alias content: holder.data
    signal clicked(int button, point position)
    signal wantsOpen
    signal leftItem

    readonly property bool open: dropdown !== "" && Activity.dropdown === dropdown
    // lit as "open": its dropdown is the open one (a tray icon sets it: they share the "tray" dropdown)
    property bool lit: open
    // moving onto it while a dropdown is open may switch to its own (a tray icon with a menu)
    property bool switchable: dropdown !== ""
    readonly property bool hovered: hover.hovered
    readonly property real pillHeight: Config.bar.item.height

    visible: shown
    width: shown ? holder.childrenRect.width + 2 * Config.bar.item.padding : 0
    height: parent ? parent.height : Config.bar.height

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: item.pillHeight
        radius: Config.corner("pill", height)
        color: Config.colors.text
        opacity: item.lit ? Config.bar.item.openOpacity : item.clickable && hover.hovered ? Config.bar.item.hoverOpacity : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Config.motion.hoverFade
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: item.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: {
            if (!hovered)
                item.leftItem();
            else if (item.switchable && Activity.dropdown !== "" && !item.lit)
                item.wantsOpen();
        }
    }
    TapHandler {
        enabled: item.clickable
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onTapped: (point, button) => {
            if (item.dropdown !== "" && button === Qt.LeftButton)
                Activity.toggle(item.dropdown);
            else
                item.clicked(button, point.position);
        }
    }

    Item {
        id: holder
        x: Config.bar.item.padding
        height: parent.height
        width: childrenRect.width
    }
}
