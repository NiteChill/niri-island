pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What the island shows. Everything that wants the island is an activity in one queue: the panel the
// user opened (search, battery, wifi), volume / brightness / microphone feedback, messages from scripts,
// system alerts (low battery, charging, Wi-Fi connected, headphones connected), notifications (not while do
// not disturb is on, see doNotDisturb). One is on screen at a time; the rules (logic only, the data comes
// from Sys):
//
//  - The one whose priority class comes first in island.priority wins. By default what the user does
//    (key presses, panels they open) comes before what the system does (messages, notifications).
//  - The most recent user interaction always wins: opening a panel clears the volume/brightness
//    feedback, and pressing a volume key over an open panel shows the volume (the panel comes back after).
//  - Anything covered keeps its remaining time and comes back afterwards: a notification that arrives
//    while you're in the launcher waits, and shows (with its full time) once you close it.
//  - Same key = same activity: volume, brightness and microphone share the key "osd", so pressing
//    volume five times (or brightness right after) updates one activity instead of queueing five.
//  - Hovering the island pauses the shown activity's timer; leaving resumes it with at least
//    island.leaveDelay left.
//  - Powering off / restarting clears everything: the island says goodbye (see "goodbye" below).
//
// IPC (bind keys in niri):  qs ipc call osd volume up|down|mute   qs ipc call osd mic mute
//                            qs ipc call osd brightness up|down    qs ipc call osd message "text" "icon.svg"
Singleton {
    id: root

    // ---- state read by the UI ----
    // the activity shown: { key, kind, cls, timeout, data, seq, since (ms, when it first came) } or null.
    // `kind` = the island mode's name ("battery", "volume", "notification"...).
    property var current: null
    // the panel the user has open ("" = none), shown or covered by something more important
    readonly property string panel: _panel
    // the island is showing the open panel right now (not covered)
    readonly property bool panelShown: !!current && current.key === "panel"
    // set by shell.qml: mouse over the island, timers pause
    property bool hovered: false
    // a picture is being dragged out of the island (PictureCarousel.dragOut): the panel stays open and
    // the click-outside layer steps aside, so the drop reaches the window under the pointer
    property bool draggingOut: false
    // the shown activity hit its limit (volume at max, brightness at min...): sliders bounce
    signal bumped(string kind, int direction)

    // ---- panels (user interaction) ----
    property string _panel: ""
    function openPanel(name) {
        if (name === "" || name === "idle") {
            closePanel();
            return;
        }
        _panel = name;
        // the user moved on from the key they pressed: don't make them wait for its feedback to time out
        _items = _items.filter(i => i.key !== "osd");
        show(name, "panel", "panel", null, 0);
    }
    function closePanel() {
        _panel = "";
        dismiss("panel");
    }

    // ---- goodbye: the computer is powering off or restarting (Sys.shuttingDown, goodbye.enabled) ----
    // Everything goes (the open panel included: the launcher that started it closes), the island writes
    // "bye bye" (GoodbyeMode), then the system goes down. Not in island.priority: it clears the queue and
    // nothing can be added until the shutdown is cancelled.
    property bool _goodbye: false
    Connections {
        target: Sys
        function onShuttingDownChanged() {
            if (Sys.shuttingDown && Config.goodbye.enabled) {
                root._panel = "";
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
            _sound(kind);
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
    // ---- sounds: a new notification or alert (not an update in place) plays its sound (Config.sounds:
    // per kind, quiet during Focus except low battery, one sound per sounds.minGap) ----
    property double _lastSound: 0
    function _sound(kind) {
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
                const newer = Config.notifications.newestFirst && i.kind === "notification" ? i.seq > best.seq : i.seq < best.seq;
                if (a < b || (a === b && newer))
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
            const item = root.current;
            if (!item)
                return;
            if (item.kind === "notification")
                Sys.expireNotification(item.data);   // Sys emits closed -> dismiss
            if (item.kind === "screenshot")
                Sys.expireNotification(item.data.notification);   // niri's notification goes with it
            root.dismiss(item.key);
        }
    }

    // ---- sources ----

    // volume / brightness / microphone: one shared slot (key "osd"). The keys still change the level when
    // the pop-up is switched off (volume.enabled...); only the island stays as it is.
    // Quick settings on screen already shows the volume and brightness bars (they bounce there) and the mic
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
    // quick settings is on screen: pop-ups for what it already shows (levels, mic, Wi-Fi network, Bluetooth
    // device) are skipped
    function _inQuickSettings() {
        return panelShown && _panel === "quickSettings";
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

    // ---- system alerts: low battery, charging, Wi-Fi connected, headphones connected, now playing ----
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
        // (the network's name is under quick settings' Wi-Fi switch)
        if (ssid !== "" && Config.wifiConnected.enabled && !_quiet() && !_inQuickSettings())
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
        // Bluetooth ones: their name is under quick settings' Bluetooth switch
        if (name !== "" && Config.headphones.enabled && !_quiet() && !(Sys.bluetooth.audioConnected && _inQuickSettings()))
            show("headphones", "headphones", "headphones", {
                "name": name
            }, Config.headphones.timeout);
        else if (name === "")
            dismiss("headphones");
    }

    // now playing: music starts after a quiet spell (nothing played for nowPlaying.quietGap). The next song
    // of a playlist, a resume after a short pause, a track change while playing: no alert. Pausing takes
    // it down. Not while the media panel is on screen (it already shows the music) or another panel is open.
    property bool _mediaPlaying: false
    property double _mediaStoppedAt: 0
    function _checkMedia() {
        const playing = Sys.media.playing && Sys.media.active;
        if (playing === _mediaPlaying)
            return;
        _mediaPlaying = playing;
        if (!playing) {
            _mediaStoppedAt = Date.now();
            dismiss("nowPlaying");
            return;
        }
        const quiet = _mediaStoppedAt === 0 || Date.now() - _mediaStoppedAt > Config.nowPlaying.quietGap * 1000;
        if (quiet && Config.nowPlaying.enabled && !_quiet() && !panelShown)
            show("nowPlaying", "nowPlaying", "nowPlaying", {}, Config.nowPlaying.timeout);
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
    }

    // do not disturb (the quick settings tile): notifications arrive but the island doesn't show them, except
    // critical ones (notifications.dndAllowsCritical). It's the desktop's setting (Sys.systemFocus, gsettings
    // show-banners), so the settings app shows the same and it survives restarts.
    readonly property bool doNotDisturb: Sys.systemFocus === true
    function setDoNotDisturb(on) {
        Sys.setSystemFocus(on);
    }

    // notifications: one activity each, key "n<id>"; updated in place when the app replaces it
    property var _hooked: ({})
    function _notify(n, plain) {
        // switched off (notifications.enabled): apps still deliver them, the island just doesn't show them
        if (!Config.notifications.enabled)
            return;
        // niri's "Screenshot captured": the screenshot itself (ScreenshotMode), shown even in Focus (you
        // just took it). One key for all of them: a new screenshot takes the place of the one shown (the
        // older notification is closed), instead of queueing behind it. Sized before it shows.
        // (`plain`: no file found, shown as a normal notification instead)
        if (!plain && Config.screenshot.enabled && Config.screenshot.summaries.indexOf(n.summary) >= 0) {
            Sys.findScreenshot(n, (path, w, h) => {
                if (path === "")
                    root._notify(n, true);
                else {
                    const old = root._items.find(i => i.key === "screenshot");
                    if (old && old.data.notification !== n)
                        Sys.dismissNotification(old.data.notification);
                    root.show("screenshot", "screenshot", "screenshot", {
                        "path": path,
                        "width": w,
                        "height": h,
                        "notification": n
                    }, Config.screenshot.timeout);
                }
            });
            return;
        }
        const info = Sys.notificationInfo(n);
        const cls = info.urgency === "critical" ? "criticalNotification" : info.urgency === "low" ? "lowNotification" : "notification";
        if (doNotDisturb && !(cls === "criticalNotification" && Config.notifications.dndAllowsCritical))
            return;
        if (cls === "lowNotification" && !Config.notifications.showLowUrgency)
            return;
        const cfg = Config.notifications;
        const timeout = cls === "criticalNotification" ? cfg.criticalTimeout : info.timeout > 0 && cfg.respectAppTimeout ? info.timeout : cfg.timeout;
        show("notification", "n" + n.id, cls, n, timeout);
    }
    Connections {
        target: Sys
        function onNotified(n) {
            const key = "n" + n.id;
            if (!root._hooked[key]) {
                root._hooked[key] = true;
                n.closed.connect(() => {
                    delete root._hooked[key];
                    root.dismiss(key);
                });
                // an app replacing its notification updates the same object: show it again
                n.summaryChanged.connect(() => root._notify(n));
                n.bodyChanged.connect(() => root._notify(n));
            }
            root._notify(n);
        }
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
