pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell

import "../services"
import "../widgets"

// The bar across the top of the screen, like the macOS menu bar. Its icons are always white, over a
// gradient from black to transparent (bar.gradient), so they read on any wallpaper.
//  - left: the distribution's logo (bar.logo: a menu of places, the launcher and the session), the
//    focused app's name (bar.appName: a menu of what to do with its window), then the workspaces of this
//    screen as dots (bar.workspaces: the active one a longer pill; a click on a dot goes there, a click
//    elsewhere on them opens niri's overview)
//  - right: the apps' tray icons (bar.tray), then Bluetooth, Wi-Fi, battery, quick settings and the clock,
//    each opening its dropdown under it (BarItem; anchorFor tells the dropdown where). The clock's is the
//    calendar with the notification center under it; a dot by the clock = new notifications
// The notch sits in the middle (shell.qml), over the bar. With bar.hideInFullscreen, a fullscreen window
// slides it all away (the notch stays).
// Switching dropdowns by moving along the bar (the macOS menu bar's way) waits while the pointer heads
// into the open dropdown (aimTo): going from quick settings down-left to its Wi-Fi switch crosses the
// battery, and that mustn't switch to the battery's dropdown.
Item {
    id: bar

    // the window, for the tray's menus (set by shell.qml)
    property var window: null
    // the open dropdown's card, in the bar's (the window's) coordinates (set by shell.qml)
    property rect card: Qt.rect(0, 0, 0, 0)
    readonly property bool hidden: Config.bar.hideInFullscreen && Sys.fullscreen
    // where a dropdown hangs: the middle of its bar item, in the bar's coordinates (-1 = not from the bar)
    function anchorFor(name) {
        const items = {
            "system": logoItem,
            "app": appItem,
            "wifi": wifiItem,
            "bluetooth": bluetoothItem,
            "battery": batteryItem,
            "quickSettings": quickItem,
            "calendar": clockItem
        };
        let it = items[name];
        // the tray's menu hangs under the icon of the app it belongs to
        if (name === "tray")
            for (let i = 0; i < tray.count; i++) {
                const t = tray.itemAt(i);
                if (t && t.modelData && t.modelData.id === Activity.trayId)
                    it = t;
            }
        if (!it || !it.visible)
            return -1;
        return it.mapToItem(bar, it.width / 2, 0).x;
    }

    // ---- aiming at the open dropdown ----
    // The pointer's last two positions, a few px apart (bar.aim.minMove). Moving onto another item while a
    // dropdown is open switches to it at once, unless the pointer is inside the triangle between where it
    // came from and the open card's top corners (heading into the card): then it waits bar.aim.delay and
    // switches only if the pointer is still on that item and has stopped (or turned away).
    property point _from: Qt.point(-1, -1)
    property point _at: Qt.point(-1, -1)
    property string _pending: ""
    function track(p) {
        if (_at.x < 0 || Math.hypot(p.x - _at.x, p.y - _at.y) >= Config.bar.aim.minMove) {
            _from = _at.x < 0 ? p : _at;
            _at = p;
        }
        if (_pending !== "" && !aiming())
            _switch();
    }
    function _side(p, a, b) {
        return (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y);
    }
    // the pointer is heading into the open card: inside the triangle (from, card's top-left, top-right),
    // the card's corners widened by bar.aim.slack
    function aiming() {
        if (Activity.dropdown === "" || card.width <= 0 || _from.x < 0)
            return false;
        const a = _from, p = _at;
        const l = Qt.point(card.x - Config.bar.aim.slack, card.y), r = Qt.point(card.x + card.width + Config.bar.aim.slack, card.y);
        if (p.y <= a.y)
            return false;
        const d1 = _side(p, a, l), d2 = _side(p, l, r), d3 = _side(p, r, a);
        return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
    }
    function aimTo(name) {
        _pending = name;
        if (aiming())
            aimTimer.restart();
        else
            _switch();
    }
    function aimCancel(name) {
        if (_pending === name) {
            _pending = "";
            aimTimer.stop();
        }
    }
    function _switch() {
        aimTimer.stop();
        const name = _pending;
        _pending = "";
        // "tray:<id>": that app's tray menu
        if (name.startsWith("tray:")) {
            const id = name.slice(5);
            if (Activity.dropdown !== "" && !(Activity.dropdown === "tray" && Activity.trayId === id))
                Activity.openTray(id);
        } else if (name !== "" && Activity.dropdown !== "" && Activity.dropdown !== name)
            Activity.open(name);
    }
    Timer {
        id: aimTimer
        interval: Config.bar.aim.delay
        // still heading in: the pointer is moving on, wait again; stopped there: it wanted this one
        onTriggered: {
            if (bar._pending !== "" && bar.aiming() && bar._movedRecently)
                restart();
            else
                bar._switch();
        }
    }
    // the pointer moved within the last bar.aim.delay
    property bool _movedRecently: false
    Timer {
        id: stillTimer
        interval: Config.bar.aim.delay
        onTriggered: bar._movedRecently = false
    }
    HoverHandler {
        onPointChanged: {
            bar._movedRecently = true;
            stillTimer.restart();
            bar.track(point.position);
        }
    }

    height: Config.bar.height
    palette.windowText: Config.colors.text
    palette.placeholderText: Config.colors.secondary

    opacity: hidden ? 0 : 1
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation {
            duration: Config.bar.hideDuration
            easing.type: Easing.OutCubic
        }
    }
    transform: Translate {
        y: bar.hidden ? -Config.bar.height : 0
        Behavior on y {
            NumberAnimation {
                duration: Config.bar.hideDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    // ---- the gradient behind it all ----
    // Eased, not straight: the shade is (1 - y)^bar.gradient.curve of its top strength, so it thins out
    // gently and has no end you can see (a straight fade stopped at a visible line). Nine stops follow
    // the curve.
    Rectangle {
        id: shade
        width: parent.width
        height: Config.bar.gradient.height
        function at(p) {
            return Qt.alpha(Config.bar.gradient.color, Config.bar.gradient.opacity * Math.pow(1 - p, Config.bar.gradient.curve));
        }
        gradient: Gradient {
            GradientStop {
                position: 0/8
                color: shade.at(0/8)
            }
            GradientStop {
                position: 1/8
                color: shade.at(1/8)
            }
            GradientStop {
                position: 2/8
                color: shade.at(2/8)
            }
            GradientStop {
                position: 3/8
                color: shade.at(3/8)
            }
            GradientStop {
                position: 4/8
                color: shade.at(4/8)
            }
            GradientStop {
                position: 5/8
                color: shade.at(5/8)
            }
            GradientStop {
                position: 6/8
                color: shade.at(6/8)
            }
            GradientStop {
                position: 7/8
                color: shade.at(7/8)
            }
            GradientStop {
                position: 8/8
                color: shade.at(8/8)
            }
        }
    }

    // ---- a click on the bar's empty space closes what's open, like a click outside (the outside layer
    // lies under the bar's window, so it never gets those). A parent TapHandler also fires for its
    // children's taps: it only acts when no clickable item is under the click. ----
    signal emptyClicked
    // where the notch is (in the bar's coordinates): it's not empty space, it has its own clicks
    property rect notch: Qt.rect(0, 0, 0, 0)
    function clickableAt(x, y) {
        if (x >= notch.x && x <= notch.x + notch.width && y >= notch.y && y <= notch.y + notch.height)
            return true;
        for (const row of [leftRow, rightRow]) {
            const p = row.mapFromItem(bar, x, y);
            const it = row.childAt(p.x, p.y);
            if (it && it.clickable && it.visible)
                return true;
        }
        return false;
    }
    TapHandler {
        enabled: Config.island.clickOutsideCloses && Activity.anyOpen
        acceptedButtons: Qt.AllButtons
        gesturePolicy: TapHandler.WithinBounds
        onTapped: (point, button) => {
            if (!bar.clickableAt(point.position.x, point.position.y))
                bar.emptyClicked();
        }
    }

    // ---- left: the logo, the focused app, the workspaces ----
    Row {
        id: leftRow
        x: Config.bar.edge
        height: parent.height

        BarItem {
            id: logoItem
            dropdown: "system"
            shown: Config.bar.logo.show
            onWantsOpen: bar.aimTo(dropdown)
            onLeftItem: bar.aimCancel(dropdown)
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: Config.bar.logo.size
                height: width
                name: Config.bar.logo.icons[Sys.distro] || Config.bar.logo.fallbackIcon
                color: Config.colors.text
            }
        }
        BarItem {
            id: appItem
            dropdown: "app"
            shown: Config.bar.appName.show && Sys.focusedApp !== ""
            onWantsOpen: bar.aimTo(dropdown)
            onLeftItem: bar.aimCancel(dropdown)
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                font.weight: Config.bar.appName.weight
                text: Sys.focusedApp
            }
        }

        // the dots: a click on one goes to it, a click around them opens the overview (one handler for both:
        // a dot's own handler fired, then the item's too, so it switched and then opened the overview)
        BarItem {
            id: spaces
            shown: Config.bar.workspaces.show && Sys.workspaces.length > 0
            clickable: true
            onClicked: (button, position) => {
                for (let i = 0; i < dots.count; i++) {
                    const d = dots.itemAt(i);
                    if (d && d.contains(d.mapFromItem(spaces, position.x, position.y))) {
                        Sys.focusWorkspace(d.modelData.idx);
                        return;
                    }
                }
                Sys.toggleOverview();
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    id: dots
                    model: Sys.workspaces
                    delegate: Item {
                        id: space
                        required property int index
                        required property var modelData
                        // the dot and half the gap on each side: a bigger target than the dot itself
                        width: dot.width + (index > 0 ? Config.bar.workspaces.gap / 2 : 0) + (index < dots.count - 1 ? Config.bar.workspaces.gap / 2 : 0)
                        height: Config.bar.item.height
                        Rectangle {
                            id: dot
                            x: space.index > 0 ? Config.bar.workspaces.gap / 2 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: space.modelData.active ? Config.bar.workspaces.activeWidth : Config.bar.workspaces.size
                            height: Config.bar.workspaces.size
                            radius: height / 2
                            color: Config.colors.text
                            opacity: space.modelData.active ? 1 : space.modelData.windows ? Config.bar.workspaces.busyOpacity : Config.bar.workspaces.emptyOpacity
                            Behavior on width {
                                SpringAnimation {
                                    spring: Config.spring(Config.bar.workspaces.spring).spring
                                    damping: Config.spring(Config.bar.workspaces.spring).damping
                                    epsilon: 0.25
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Config.motion.colorFade
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- right: tray, status, quick settings, clock ----
    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: Config.bar.edge
        height: parent.height

        // the apps' own icons (StatusNotifierItem): a click (left or right) opens its menu under it (the
        // "tray" dropdown, drawn by the shell), or does the app's main thing when it has no menu; middle
        // click = the main thing. Lit on hover only when a click does something (Sys.trayClickable).
        // Optionally white (tray.monochrome)
        Repeater {
            id: tray
            model: Config.tray.enabled ? Sys.trayItems : []
            delegate: BarItem {
                id: trayItem
                required property var modelData
                readonly property string trayId: modelData ? modelData.id : ""
                readonly property bool hasMenu: !!modelData && modelData.hasMenu
                clickable: Sys.trayClickable(modelData)
                lit: Activity.dropdown === "tray" && Activity.trayId === trayId
                switchable: hasMenu
                onWantsOpen: bar.aimTo("tray:" + trayId)
                onLeftItem: bar.aimCancel("tray:" + trayId)
                onClicked: button => {
                    if (button !== Qt.MiddleButton && trayItem.hasMenu)
                        Activity.toggleTray(trayItem.trayId);
                    else
                        Sys.trayMain(trayItem.trayId);
                }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => Sys.trayScroll(trayItem.modelData, event.angleDelta.y)
                }
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Config.tray.size
                    height: Config.tray.size
                    Image {
                        id: trayIcon
                        anchors.fill: parent
                        source: trayItem.modelData.icon || ""
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        visible: !Config.tray.monochrome
                        mipmap: true
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: Config.tray.monochrome
                        source: trayIcon
                        colorization: 1
                        colorizationColor: Config.colors.text
                        brightness: 1
                    }
                }
            }
        }

        BarItem {
            id: bluetoothItem
            onWantsOpen: bar.aimTo(dropdown)
            onLeftItem: bar.aimCancel(dropdown)
            dropdown: "bluetooth"
            shown: Config.bar.bluetooth.show && Sys.bluetooth.available
            Bluetooth {}
        }
        BarItem {
            id: wifiItem
            onWantsOpen: bar.aimTo(dropdown)
            onLeftItem: bar.aimCancel(dropdown)
            dropdown: "wifi"
            shown: Config.bar.wifi.show
            Item {
                width: Config.bar.wifi.size
                height: parent.height
                Wifi {
                    visible: Sys.wifi.enabled
                    level: Sys.wifi.connected ? Sys.wifi.bars : 0
                }
                Icon {
                    visible: !Sys.wifi.enabled
                    anchors.centerIn: parent
                    width: Config.bar.wifi.size
                    height: Config.bar.wifi.size
                    name: Config.bar.wifi.offIcon
                    color: Config.colors.text
                }
            }
        }
        BarItem {
            id: batteryItem
            onWantsOpen: bar.aimTo(dropdown)
            onLeftItem: bar.aimCancel(dropdown)
            dropdown: "battery"
            shown: Config.bar.battery.show && Sys.battery.ready
            Row {
                height: parent.height
                spacing: Config.bar.battery.percentGap
                StyledText {
                    visible: Config.bar.battery.showPercent
                    anchors.verticalCenter: parent.verticalCenter
                    font.features: {
                        "tnum": 1
                    }
                    text: Sys.battery.percentage + "%"
                }
                // like the iPhone: charging = a bolt, power saver = a plus, cut into the battery's right end
                // (bar.battery.badge); the bolt wins when both
                CutoutBadge {
                    readonly property var cfg: Config.bar.battery.badge
                    readonly property bool bolt: cfg.charging && Sys.battery.charging
                    readonly property bool plus: cfg.saver && Sys.battery.profile === "powerSaver"
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    width: implicitWidth
                    shown: bolt || plus
                    centered: true
                    icon: bolt ? cfg.chargingIcon : cfg.saverIcon
                    size: bolt ? cfg.chargingSize : cfg.saverSize
                    overhangX: size / 2 + cfg.offset
                    gap: cfg.gap
                    contentWidth: Config.bar.battery.size
                    contentHeight: barBattery.drawnHeight
                    Battery {
                        id: barBattery
                        tint: Config.colors.text
                    }
                }
            }
        }
        BarItem {
            id: quickItem
            onWantsOpen: bar.aimTo(dropdown)
            onLeftItem: bar.aimCancel(dropdown)
            dropdown: "quickSettings"
            shown: Config.bar.quickSettings.show
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: Config.bar.quickSettings.size
                height: Config.bar.quickSettings.size
                name: Config.bar.quickSettings.icon
                color: Config.colors.text
            }
        }
        BarItem {
            id: clockItem
            onWantsOpen: bar.aimTo(dropdown)
            onLeftItem: bar.aimCancel(dropdown)
            dropdown: "calendar"
            Row {
                height: parent.height
                spacing: Config.bar.clock.spacing
                // same-width digits, so the clock doesn't shift every minute
                readonly property var features: Config.bar.clock.tabularDigits ? {
                    "tnum": 1
                } : {}
                StyledText {
                    visible: Config.bar.clock.dateFormat !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(Sys.time, Config.bar.clock.dateFormat)
                    font.features: parent.features
                }
                StyledText {
                    readonly property string format: Sys.hour24 ? Config.bar.clock.timeFormat : Config.bar.clock.timeFormat12h
                    visible: format !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(Sys.time, format)
                    font.features: parent.features
                }
                // new notifications since the center was last open (it comes with the clock's calendar)
                Rectangle {
                    visible: Config.bar.clock.unseenDot && Inbox.unseen > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Config.bar.clock.dotSize
                    height: width
                    radius: width / 2
                    color: Config.colors.notificationDot
                }
            }
        }
    }
}
