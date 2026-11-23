pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What is open and what the notch shows.
//
// Open (one at a time; opening one closes the others):
//  - a dropdown under the bar (`dropdown`: "wifi", "battery", "calendar", "search"...), opened from its bar
//    icon, the keyboard or IPC. The calendar (the clock) brings the notification center under it (`center`)
//  - a panel grown out of the notch (`panel`): the player ("media") or the shelf ("shelf"): a click on the
//    notch (openNotch picks which; tabs switch when both have something, notchTabs), or IPC; and the
//    launcher ("search": Mod+Space, the logo's menu) and the wallpaper picker ("wallpaper")
// Something dragged over the notch turns it into a small drop zone (`dropping`, DropMode); what's dropped
// goes on the shelf, which opens on it.
//
// The notch: everything that wants it is an activity in one queue: the open media controls, volume /
// brightness / microphone feedback, messages from scripts, system alerts (low battery, charging, Wi-Fi
// connected, headphones connected), and the music playing (the base layer: it stays while music plays,
// under everything else). One is on screen at a time; the rules (logic only, the data comes from Sys):
//
//  - The one whose priority class comes first in island.priority wins. By default what the user does
//    (key presses, the media controls they open) comes before what the system does (alerts), and the music
//    playing comes last.
//  - The most recent user interaction always wins: opening the media controls clears the volume /
//    brightness feedback, and pressing a volume key over them shows the volume (they come back after).
//  - Anything covered keeps its remaining time and comes back afterwards.
//  - Same key = same activity: volume, brightness and microphone share the key "osd", so pressing
//    volume five times (or brightness right after) updates one activity instead of queueing five.
//  - Hovering the notch pauses the shown activity's timer; leaving resumes it with at least
//    island.leaveDelay left.
//  - Powering off / restarting clears everything: the island says goodbye (see "goodbye" below).
// Notifications don't use the notch: they drop under it as cards (Inbox, surfaces/NotificationStack).
//
// IPC (bind keys in niri):  qs ipc call osd volume up|down|mute   qs ipc call osd mic mute
//                            qs ipc call osd brightness up|down    qs ipc call osd message "text" "icon.svg"
Singleton {
    id: root

    // ---- state read by the UI ----
    // the activity shown: { key, kind, cls, timeout, data, seq, since (ms, when it first came) } or null.
    // `kind` = the notch mode's name ("volume", "media", "nowPlaying"...); null = the notch at rest.
    property var current: null
    // the panel grown out of the notch ("media", or "" = none), shown or covered by something more important
    readonly property string panel: _panel
    // the notch is showing that panel right now (not covered)
    readonly property bool panelShown: !!current && current.key === "panel"
    // the dropdown open under the bar ("" = none)
    property string dropdown: ""
    // the notification center is open: it comes with the calendar, under the clock
    readonly property bool center: dropdown === "calendar"
    // anything open that takes clicks outside it and the keyboard
    readonly property bool anyOpen: dropdown !== "" || _panel !== ""
    // something is being dragged over the notch (shell.qml's DropArea): the shelf is open to take it
    property bool dropping: false
    // set by shell.qml: mouse over the notch, its timer pauses
    property bool hovered: false
    // a picture is being dragged out (PictureCarousel.dragOut): what's open stays open and the
    // click-outside layer steps aside, so the drop reaches the window under the pointer
    property bool draggingOut: false
    // the shown activity hit its limit (volume at max, brightness at min...): sliders bounce
    signal bumped(string kind, int direction)

    // ---- opening and closing ----
    // the panels that grow out of the notch, and the dropdowns (modes/AllDropdowns.qml); other names are
    // ignored ("time" is the calendar's old name)
    readonly property var notchPanels: ["media", "shelf", "search", "wallpaper"]
    readonly property var dropdowns: ["wifi", "bluetooth", "battery", "calendar", "quickSettings", "app", "system", "tray"]
    // older names: "time" was the calendar, "screenshots" the shelf, the center lives with the calendar
    readonly property var _aliases: ({ "time": "calendar", "screenshots": "shelf", "notifications": "calendar" })
    // (search was a dropdown under the notch until 2026-11-23; it's the notch's own panel now)
    property string _panel: ""
    function open(name) {
        if (name === "" || name === "idle") {
            closeAll();
            return;
        }
        name = _aliases[name] || name;
        if (_goodbye || (notchPanels.indexOf(name) < 0 && dropdowns.indexOf(name) < 0))
            return;
        if (notchPanels.indexOf(name) >= 0) {
            dropdown = "";
            _panel = name;
            // the user moved on from the key they pressed: don't make them wait for its feedback to time out
            _items = _items.filter(i => i.key !== "osd");
            show(name, "panel", "panel", null, 0);
            return;
        }
        _closePanel();
        dropdown = name;
    }
    // a tray icon's menu (the "tray" dropdown, drawn by the shell: TrayMenuMode): which app's (its tray id)
    property string trayId: ""
    function openTray(id) {
        trayId = id;
        open("tray");
    }
    function toggleTray(id) {
        if (dropdown === "tray" && trayId === id)
            closeAll();
        else
            openTray(id);
    }
    function isOpen(name) {
        name = _aliases[name] || name;
        return notchPanels.indexOf(name) >= 0 ? _panel === name : dropdown === name;
    }
    function toggle(name) {
        open(isOpen(name) ? "" : name);
    }
    function closeAll() {
        dropdown = "";
        _closePanel();
    }

    // ---- opening the notch (a click on it): the player or the shelf ----
    // Both are panels grown out of the notch; with something in both (music, and things on the shelf) a
    // small navbar of icons sits on top to switch (NotchTabs, `notchTabs`). A click opens the one that
    // matters now: something put on the shelf in the last island.tabs.recent seconds (a drop, a
    // screenshot), else the music when there is some, else the shelf (empty: where things go).
    readonly property bool notchTabs: Sys.media.active && Sys.shelf.length > 0
    function openNotch() {
        if (_goodbye)
            return;
        const recent = Sys.shelfTouched > 0 && Date.now() - Sys.shelfTouched < Config.island.tabs.recent * 1000;
        open(recent || !Sys.media.active ? "shelf" : "media");
    }
    // the other tab (Tab / a click on its icon)
    function switchNotchTab() {
        if (notchTabs && notchPanels.indexOf(_panel) >= 0)
            open(_panel === "media" ? "shelf" : "media");
    }

    // dragged over the notch: it becomes a small drop zone (DropMode, class "drop", first in
    // island.priority); dropped, the shelf opens on what came in (Sys.shelfAdded)
    onDroppingChanged: {
        if (dropping)
            show("drop", "drop", "drop", null, 0);
        else
            dismiss("drop");
    }
    Connections {
        target: Sys
        function onShelfAdded(path) {
            root.open("shelf");
        }
    }
    function _closePanel() {
        if (_panel === "")
            return;
        _panel = "";
        dismiss("panel");
    }

    // ---- goodbye: the computer is powering off or restarting (Sys.shuttingDown, goodbye.enabled) ----
    // Everything goes (whatever is open closes), the island writes "bye bye" (GoodbyeMode), then the system
    // goes down. Not in island.priority: it clears the queue and nothing can be added until the shutdown is
    // cancelled.
    property bool _goodbye: false
    Connections {
        target: Sys
        function onShuttingDownChanged() {
            if (Sys.shuttingDown && Config.goodbye.enabled) {
                root.closeAll();
                root._items = [];
                root._goodbye = true;
                root.show("goodbye", "goodbye", "goodbye", null, 0);
            } else if (!Sys.shuttingDown && root._goodbye) {
                root._goodbye = false;
                root.dismiss("goodbye");
            }
        }
    }

    // the goodbye without any shutdown (qs ipc call island goodbye): plays over everything, keeps the
    // queue and the system as they are, then GoodbyeMode dismisses it
    function previewGoodbye() {
        if (!_goodbye)
            show("goodbye", "goodbye", "goodbye", null, 0);
    }

    // ---- queue ----
    property var _items: []
    property int _seq: 0

    // add or update an activity. timeout in ms, 0 = stays until dismissed.
    function show(kind, key, cls, data, timeout) {
        // saying goodbye: nothing else gets the island any more
        if (_goodbye && key !== "goodbye")
            return;
        const items = _items.filter(i => i.key !== key);
        const old = _items.find(i => i.key === key);
        if (!old)
            sound(kind);
        items.push({
            "key": key,
            "kind": kind,
            "cls": cls,
            "data": data,
            "timeout": timeout,
            "remaining": timeout,
            "seq": old && old.cls === cls ? old.seq : ++_seq,
            "since": old ? old.since : Date.now()
        });
        _items = items;
        _pick();
    }
    // ---- sounds: a new alert or notification (not an update in place) plays its sound (Config.sounds: per
    // kind, quiet during Focus except low battery, one sound per sounds.minGap) ----
    property double _lastSound: 0
    function sound(kind) {
        const all = Config.sounds;
        const one = all[kind];
        if (!all.enabled || !one || !one.enabled)
            return;
        if (all.respectFocus && doNotDisturb && kind !== "lowBattery")
            return;
        const now = Date.now();
        if (now - _lastSound < all.minGap)
            return;
        _lastSound = now;
        Sys.playSound(one.file);
    }
    function dismiss(key) {
        if (!_items.some(i => i.key === key))
            return;
        _items = _items.filter(i => i.key !== key);
        _pick();
    }

    // where an activity class sits in island.priority (unknown classes go last; the goodbye goes first)
    function _rank(cls) {
        if (cls === "goodbye")
            return -1;
        const i = Config.island.priority.indexOf(cls);
        return i < 0 ? Config.island.priority.length : i;
    }
    // choose what's shown
    function _pick() {
        _pause();
        let best = null;
        for (const i of _items) {
            if (!best)
                best = i;
            else {
                const a = _rank(i.cls), b = _rank(best.cls);
                if (a < b || (a === b && i.seq < best.seq))
                    best = i;
            }
        }
        current = best;
        _resume();
    }

    // ---- timer of the shown activity ----
    property double _startedAt: 0
    function _pause() {
        if (!timer.running || !current)
            return;
        timer.stop();
        current.remaining = Math.max(0, current.remaining - (Date.now() - _startedAt));
    }
    function _resume() {
        if (!current || current.timeout <= 0 || hovered)
            return;
        timer.interval = Math.max(1, current.remaining);
        _startedAt = Date.now();
        timer.restart();
    }
    onHoveredChanged: {
        if (hovered)
            _pause();
        else if (current) {
            current.remaining = Math.max(current.remaining, Config.island.leaveDelay);
            _resume();
        }
    }
    Timer {
        id: timer
        onTriggered: {
            if (root.current)
                root.dismiss(root.current.key);
        }
    }

    // ---- sources ----

    // volume / brightness / microphone: one shared slot (key "osd"). The keys still change the level when
    // the pop-up is switched off (volume.enabled...); only the island stays as it is.
    // Quick settings open already shows the volume and brightness bars (they bounce there) and the mic
    // switch: no pop-up.
    function feedback(kind) {
        if (_inQuickSettings())
            return;
        const on = kind === "volume" ? Config.volume.enabled : kind === "brightness" ? Config.brightness.enabled : Config.microphone.enabled;
        if (!on)
            return;
        const timeout = kind === "volume" ? Config.volume.timeout : kind === "brightness" ? Config.brightness.timeout : Config.microphone.timeout;
        show(kind, "osd", kind, null, timeout);
    }
    // quick settings is open: pop-ups for what it already shows (levels, mic, Wi-Fi network, Bluetooth
    // device) are skipped
    function _inQuickSettings() {
        return dropdown === "quickSettings";
    }
    function volume(action) {
        if (!Sys.audio.ready)
            return;
        if (action === "mute")
            Sys.toggleMute();
        else {
            const dir = action === "down" ? -1 : 1;
            const moved = Sys.changeVolume(dir);
            // the pop-up first, then the bounce: its slider holds the bounce until it's on screen
            feedback("volume");
            if (!moved)
                bumped("volume", dir);
            return;
        }
        feedback("volume");
    }
    function brightness(action) {
        if (!Sys.brightness.ready)
            return;
        const dir = action === "down" ? -1 : 1;
        const moved = Sys.changeBrightness(dir);
        feedback("brightness");
        if (!moved)
            bumped("brightness", dir);
    }
    function microphone() {
        if (!Sys.audio.micReady)
            return;
        Sys.toggleMicMute();
        feedback("microphone");
    }

    // ---- system alerts: low battery, charging, Wi-Fi connected, headphones connected ----
    // Only real changes pop up: whatever is already there when the shell starts (or within
    // system.startupQuiet of it, while services report in) is taken as the starting point.
    property double _startedTime: Date.now()
    function _quiet() {
        return Date.now() - _startedTime < Config.system.startupQuiet;
    }

    // low battery: once per level in lowBattery.levels while discharging (15 % then 5 %...);
    // plugging in clears the alert and re-arms every level.
    // charging: plugged in (charging or already full) pops the charging alert; unplugging clears it.
    property int _warnedLevel: _noLevel
    readonly property int _noLevel: 101
    property bool _wasCharging: false
    property bool _batteryKnown: false
    function _checkBattery() {
        const b = Sys.battery;
        if (!b.ready)
            return;
        if (b.charging !== _wasCharging || !_batteryKnown) {
            const pluggedIn = b.charging && _batteryKnown;
            _wasCharging = b.charging;
            _batteryKnown = true;
            if (pluggedIn && Config.charging.enabled && !_quiet())
                show("charging", "charging", "charging", null, Config.charging.timeout);
            else if (!b.charging)
                dismiss("charging");
        }
        if (b.charging) {
            _warnedLevel = _noLevel;
            dismiss("lowBattery");
            return;
        }
        if (!Config.lowBattery.enabled)
            return;
        let hit = _noLevel;
        for (const l of Config.lowBattery.levels)
            if (b.percentage <= l)
                hit = Math.min(hit, l);
        if (hit < _warnedLevel) {
            _warnedLevel = hit;
            show("lowBattery", "lowBattery", "lowBattery", null, Config.lowBattery.timeout);
        }
    }

    // Wi-Fi: joined a network (or switched to another one)
    property string _lastSsid: ""
    function _checkWifi() {
        const ssid = Sys.wifi.connected ? Sys.wifi.ssid : "";
        if (ssid === _lastSsid)
            return;
        _lastSsid = ssid;
        // (the Wi-Fi dropdown shows the network itself)
        if (ssid !== "" && Config.wifiConnected.enabled && !_quiet() && dropdown !== "wifi" && !_inQuickSettings())
            show("wifiConnected", "wifiConnected", "wifiConnected", {
                "ssid": ssid
            }, Config.wifiConnected.timeout);
    }

    // headphones: an external audio output became the one in use (Bluetooth, USB, jack)
    property string _lastAudioDevice: ""
    function _checkHeadphones() {
        const name = Sys.audio.connectedDevice.trim();
        if (name === _lastAudioDevice)
            return;
        _lastAudioDevice = name;
        // Bluetooth ones: the Bluetooth dropdown / quick settings show them
        if (name !== "" && Config.headphones.enabled && !_quiet() && !(Sys.bluetooth.audioConnected && (_inQuickSettings() || dropdown === "bluetooth")))
            show("headphones", "headphones", "headphones", {
                "name": name
            }, Config.headphones.timeout);
        else if (name === "")
            dismiss("headphones");
    }

    // ---- the music playing: the notch's base layer ----
    // While music plays, the notch shows it (cover at the left, bars at the right, NowPlayingMode) under
    // everything else (nowPlaying is last in island.priority): an alert covers it, then it comes back.
    // Paused, it stays nowPlaying.linger seconds (a click on it opens the controls to start it again).
    // While the music's own window (or browser tab) is in front, it stays out of the notch
    // (nowPlaying.hideWhenFocused, Sys.mediaFocused); it comes back when you leave it.
    function _checkMedia() {
        const playing = Sys.media.playing && Sys.media.active;
        const looking = Config.nowPlaying.hideWhenFocused && Sys.mediaFocused;
        if (!Config.nowPlaying.enabled || !Sys.media.active || looking) {
            nowPlayingLinger.stop();
            dismiss("nowPlaying");
            return;
        }
        if (playing) {
            nowPlayingLinger.stop();
            if (!_items.some(i => i.key === "nowPlaying"))
                show("nowPlaying", "nowPlaying", "nowPlaying", {}, 0);
        } else if (_items.some(i => i.key === "nowPlaying") && !nowPlayingLinger.running)
            nowPlayingLinger.restart();
    }
    Timer {
        id: nowPlayingLinger
        interval: Config.nowPlaying.linger * 1000
        onTriggered: {
            if (!Sys.media.playing)
                root.dismiss("nowPlaying");
        }
    }

    Component.onCompleted: {
        _checkMedia();
        _checkBattery();
        _checkWifi();
        _checkHeadphones();
    }
    Connections {
        target: Sys
        function onBatteryChanged() {
            root._checkBattery();
        }
        function onWifiChanged() {
            root._checkWifi();
        }
        function onAudioChanged() {
            root._checkHeadphones();
        }
        function onMediaChanged() {
            root._checkMedia();
        }
        function onMediaFocusedChanged() {
            root._checkMedia();
        }
    }
    Connections {
        target: Config
        function onDataChanged() {
            root._checkMedia();
        }
    }

    // do not disturb (the Focus switch): notifications go to the center without a card dropping in, except
    // critical ones (notifications.dndAllowsCritical). It's the desktop's setting (Sys.systemFocus,
    // gsettings show-banners), so the settings app shows the same and it survives restarts.
    readonly property bool doNotDisturb: Sys.systemFocus === true
    function setDoNotDisturb(on) {
        Sys.setSystemFocus(on);
    }

    IpcHandler {
        target: "osd"
        function volume(action: string): void {
            root.volume(action);
        }
        function brightness(action: string): void {
            root.brightness(action);
        }
        function mic(action: string): void {
            root.microphone();
        }
        function message(text: string, icon: string): void {
            if (!Config.message.enabled)
                return;
            root.show("message", "message", "message", {
                "text": text,
                "icon": icon !== "" ? icon : Config.message.icon
            }, Config.message.timeout);
        }
    }
}
