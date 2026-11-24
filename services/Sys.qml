pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray

// System state for the UI: the ONLY place components get system data from and change the system through
// (battery, power profile, audio output, volume, microphone, brightness, Wi-Fi, Bluetooth, media, clock, apps,
// files, notifications). Components bind to Sys.<thing>.<field> and never import UPower, Pipewire,
// DesktopEntries... themselves. Everything is event-driven (bindings on Quickshell services,
// `pactl subscribe`); nothing polls. Derived values shared by several components (battery percentage
// and color, the week, volume / brightness limits, file paths) are computed here once.
Singleton {
    id: root

    // ==========================================
    // BATTERY + POWER PROFILE
    // ==========================================

    // battery: {
    //   ready: bool          UPower has reported (before that, the other values are placeholders),
    //   percentage: int 0-100, level: real 0-1,
    //   charging: bool       plugged in and charging or full,
    //   full: bool           UPower says fully charged (often below 100 % with a charge limit),
    //   profile: string      "powerSaver" | "balanced" | "performance",
    //   color: color         the one battery color used everywhere (the bar's icon too, unless bar.battery.colored is off):
    //                        charging > power saver > low (bar.battery.dangerLevel, not charging) >
    //                        performance > balanced
    //   low: bool            below bar.battery.dangerLevel and not charging
    // }
    readonly property var battery: {
        const dev = UPower.displayDevice;
        const ready = dev && dev.ready;
        const state = ready ? dev.state : UPowerDeviceState.Unknown;
        const charging = state === UPowerDeviceState.Charging || state === UPowerDeviceState.FullyCharged;
        const level = ready ? Math.max(0, Math.min(1, dev.percentage)) : 0;
        const percentage = Math.round(level * 100);
        const profile = PowerProfiles.profile === PowerProfile.PowerSaver ? "powerSaver" : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced";
        const low = !charging && percentage <= Config.bar.battery.dangerLevel;
        const c = Config.colors;
        return {
            "ready": !!ready,
            "level": level,
            "percentage": percentage,
            "charging": charging,
            "full": state === UPowerDeviceState.FullyCharged,
            "profile": profile,
            "color": charging ? c.charging : profile === "powerSaver" ? c.powerSaver : low ? c.danger : profile === "performance" ? c.performance : c.balanced,
            "low": low
        };
    }

    // seconds until the battery is full while charging, to the minute (0 = not charging / unknown yet). Its
    // own int: UPower refines the estimate every few seconds, and the `battery` object (a new object, which
    // always notifies) would be rebuilt each time
    readonly property int batteryTimeToFull: {
        const dev = UPower.displayDevice;
        if (!dev || !dev.ready || dev.state !== UPowerDeviceState.Charging)
            return 0;
        return Math.round(dev.timeToFull / 60) * 60;
    }
    // same, seconds until the battery is empty while discharging (0 = charging / unknown yet)
    readonly property int batteryTimeToEmpty: {
        const dev = UPower.displayDevice;
        if (!dev || !dev.ready || dev.state !== UPowerDeviceState.Discharging)
            return 0;
        return Math.round(dev.timeToEmpty / 60) * 60;
    }

    // profile: "powerSaver" | "balanced" | "performance"
    function setPowerProfile(profile) {
        const p = profile === "powerSaver" ? PowerProfile.PowerSaver : profile === "performance" ? PowerProfile.Performance : PowerProfile.Balanced;
        if (PowerProfiles.profile !== p)
            PowerProfiles.profile = p;
    }

    // ==========================================
    // CLOCK
    // ==========================================

    // current date/time. Ticks once a minute; once a second only while something needs seconds: the bar's
    // clock format shows them, or a component sets timeSeconds.
    // (clock.date is briefly undefined while the shell reloads)
    readonly property date time: clock.date ? clock.date : new Date()
    // a moment saved as ms since 1970 (a notification's arrival), written with a Qt date format
    function formatStamp(ms, format) {
        return Qt.formatDateTime(new Date(ms), format);
    }
    property bool timeSeconds: false
    SystemClock {
        id: clock
        precision: root.timeSeconds || /s/.test((hour24 ? Config.bar.clock.timeFormat : Config.bar.clock.timeFormat12h) + Config.bar.clock.dateFormat) ? SystemClock.Seconds : SystemClock.Minutes
    }

    // 24-hour clock or not, for every clock in the island: the system's choice (gsettings clock-format,
    // what the settings app and GTK apps use) while time.followSystemClock is on, else time.hour24
    readonly property bool hour24: Config.time.followSystemClock && _desktop.clockFormat ? _desktop.clockFormat !== "12h" : Config.time.hour24

    // ==========================================
    // DESKTOP SETTINGS (gsettings org.gnome.desktop.interface)
    // ==========================================

    // the few desktop-wide settings the island follows, as written by the settings app (or GNOME, or
    // `gsettings set`): { accent: "blue" | "teal" | ... | "" (unknown), clockFormat: "24h" | "12h" | "" }.
    // (Not the color scheme: there's one glass look, no light theme.)
    // Read once at startup, then from `gsettings monitor`, which prints a line per change (nothing polls).
    // Replaced only when one of these values changes.
    property var _desktop: ({ "accent": "", "clockFormat": "" })
    readonly property var _desktopKeys: ({ "accent-color": "accent", "clock-format": "clockFormat" })
    // one line of `gsettings get`/`list-recursively` ("org.gnome.desktop.interface accent-color 'blue'")
    // or `gsettings monitor` ("accent-color: 'blue'")
    function _desktopLine(line) {
        const m = line.match(/(?:^|\s)([a-z-]+):?\s+'([^']*)'\s*$/);
        if (!m || !(m[1] in _desktopKeys))
            return;
        const field = _desktopKeys[m[1]];
        if (_desktop[field] === m[2])
            return;
        const next = Object.assign({}, _desktop);
        next[field] = m[2];
        _desktop = next;
    }
    // the desktop's accent name, for Config.colors (which maps it to a color: colors.systemAccents)
    Binding {
        target: Config
        property: "systemAccent"
        value: root._desktop.accent
    }
    Process {
        id: desktopRead
        command: ["gsettings", "list-recursively", "org.gnome.desktop.interface"]
        running: true
        stdout: SplitParser {
            onRead: line => root._desktopLine(line)
        }
    }
    Process {
        id: desktopEvents
        command: ["gsettings", "monitor", "org.gnome.desktop.interface"]
        running: true
        stdout: SplitParser {
            onRead: line => root._desktopLine(line)
        }
        onExited: desktopEventsRestart.start()
    }
    Timer {
        id: desktopEventsRestart
        interval: Config.system.restartDelay
        // a change made while the monitor was down would be missed: read everything again too
        onTriggered: {
            desktopEvents.running = true;
            desktopRead.running = true;
        }
    }

    // Do not disturb (the Focus switch) is the desktop's: gsettings org.gnome.desktop.notifications
    // show-banners (false = Focus on), like GNOME. The settings app and the island both follow it, and it
    // survives restarts. systemFocus: true while it's on; null until read.
    property var systemFocus: null
    function _focusLine(line) {
        const m = line.match(/(?:^|\s)show-banners:?\s+(true|false)\s*$/);
        if (m)
            systemFocus = m[1] === "false";
    }
    function setSystemFocus(on) {
        systemFocus = on;
        run(["gsettings", "set", "org.gnome.desktop.notifications", "show-banners", on ? "false" : "true"]);
    }
    Process {
        id: focusRead
        command: ["gsettings", "get", "org.gnome.desktop.notifications", "show-banners"]
        running: true
        stdout: SplitParser {
            onRead: line => root._focusLine("show-banners " + line)
        }
    }
    Process {
        id: focusEvents
        command: ["gsettings", "monitor", "org.gnome.desktop.notifications", "show-banners"]
        running: true
        stdout: SplitParser {
            onRead: line => root._focusLine(line)
        }
        onExited: focusEventsRestart.start()
    }
    Timer {
        id: focusEventsRestart
        interval: Config.system.restartDelay
        onTriggered: {
            focusEvents.running = true;
            focusRead.running = true;
        }
    }

    // ==========================================
    // NIRI: workspaces, the focused app, fullscreen
    // ==========================================

    // Kept from niri's event stream (windows, their sizes, workspaces) as plain maps: no polling.
    //  - workspaces: the bar's screen's (Quickshell.screens[0], like shell.qml), in order:
    //    [{ id, idx, name, active, windows: bool }]; replaced only when what's shown changes
    //  - focusedApp: the focused window's app name (its desktop entry's, else its app id), "" = none
    //  - fullscreen (bar.hideInFullscreen): niri's JSON has no fullscreen flag, so fullscreen = the active
    //    window of the active workspace on that screen is as big as the screen (a window maximized to the
    //    edges counts too), and the overview is closed
    property var workspaces: []
    property string _workspacesSignature: ""
    property string focusedApp: ""
    // the focused window's niri id (-1 = none: an empty workspace), title and app id
    property int focusedWindow: -1
    property string focusedTitle: ""
    property string _focusedAppId: ""
    // what the focused window is now, for the app menu's rows (Float / Tile, Maximize / Restore...):
    // { floating, maximized, fullscreen }. niri says floating; fullscreen = the window is the output's size;
    // maximized = its column takes at least bar.appMenu.maximizedShare of the output's width (niri has no
    // flag for either)
    property var focusedState: ({ "floating": false, "maximized": false, "fullscreen": false })
    property bool overview: false
    property bool fullscreen: false
    property var _niriWindows: ({})
    property var _niriWorkspaces: ({})
    property var _niriOutputs: ({})
    property bool _niriOverview: false
    property bool _niriDown: false
    readonly property bool _fullscreenWatch: Config.bar.hideInFullscreen
    on_FullscreenWatchChanged: _fullscreenCheck()
    Process {
        id: niriEvents
        command: ["niri", "msg", "--json", "event-stream"]
        running: !root._niriDown
        stdout: SplitParser {
            onRead: line => root._niriEvent(line)
        }
        onExited: {
            root._niriDown = true;
            niriEventsRestart.start();
        }
    }
    Timer {
        id: niriEventsRestart
        interval: Config.system.restartDelay
        onTriggered: root._niriDown = false
    }
    // the outputs' logical sizes, read again whenever the workspaces change (outputs come and go with them)
    Process {
        id: niriOutputs
        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._niriOutputs = JSON.parse(text) || {};
                } catch (e) {
                    root._niriOutputs = {};
                }
                root._fullscreenCheck();
            }
        }
        onExited: {
            if (root._outputsAgain) {
                root._outputsAgain = false;
                Qt.callLater(() => niriOutputs.running = true);
            }
        }
    }
    // a change while a read runs reads again once it's done (the running one may predate the change)
    property bool _outputsAgain: false
    function _readOutputs() {
        if (niriOutputs.running)
            _outputsAgain = true;
        else
            niriOutputs.running = true;
    }
    // the island's screen can change (a monitor plugged in or out)
    Connections {
        target: Quickshell
        function onScreensChanged() {
            root._fullscreenCheck();
            root._publishNiri();
        }
    }
    function _byId(list) {
        const map = {};
        for (const x of list || [])
            map[x.id] = x;
        return map;
    }
    function _niriEvent(line) {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        const wins = _niriWindows, spaces = _niriWorkspaces;
        if (ev.WorkspacesChanged) {
            _niriWorkspaces = _byId(ev.WorkspacesChanged.workspaces);
            _readOutputs();   // checks once read
            _publishNiri();
            return;
        } else if (ev.WorkspaceActivated) {
            const on = spaces[ev.WorkspaceActivated.id];
            if (!on)
                return;
            for (const id in spaces) {
                if (spaces[id].output === on.output)
                    spaces[id].is_active = spaces[id] === on;
                if (ev.WorkspaceActivated.focused)
                    spaces[id].is_focused = spaces[id] === on;
            }
        } else if (ev.WindowFocusChanged) {
            for (const id in wins)
                wins[id].is_focused = wins[id].id === ev.WindowFocusChanged.id;
        } else if (ev.WorkspaceActiveWindowChanged) {
            const e = ev.WorkspaceActiveWindowChanged, ws = spaces[e.workspace_id];
            if (ws)
                ws.active_window_id = e.active_window_id;
        } else if (ev.WindowsChanged)
            _niriWindows = _byId(ev.WindowsChanged.windows);
        else if (ev.WindowOpenedOrChanged) {
            const w = ev.WindowOpenedOrChanged.window;
            if (w.is_focused)
                for (const id in wins)
                    wins[id].is_focused = false;
            wins[w.id] = w;
        }
        else if (ev.WindowClosed)
            delete wins[ev.WindowClosed.id];
        else if (ev.WindowLayoutsChanged) {
            for (const change of ev.WindowLayoutsChanged.changes)
                if (wins[change[0]])
                    wins[change[0]].layout = change[1];
        } else if (ev.OverviewOpenedOrClosed) {
            _niriOverview = ev.OverviewOpenedOrClosed.is_open;
            overview = _niriOverview;
        } else
            return;
        _fullscreenCheck();
        _publishNiri();
    }
    // what the bar shows, from the maps: replaced only when it changes (window titles change all the time)
    function _publishNiri() {
        const screen = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
        const busy = {};
        let focused = null;
        for (const id in _niriWindows) {
            const w = _niriWindows[id];
            busy[w.workspace_id] = true;
            if (w.is_focused)
                focused = w;
        }
        // the bar's own window taking the keyboard (a dropdown open) leaves niri with no focused window:
        // the app is still the active window of the focused workspace (an empty workspace has none)
        if (!focused)
            for (const id in _niriWorkspaces) {
                const ws = _niriWorkspaces[id];
                if (ws.is_focused && ws.active_window_id !== null && ws.active_window_id !== undefined)
                    focused = _niriWindows[ws.active_window_id] || null;
            }
        const list = [];
        for (const id in _niriWorkspaces) {
            const ws = _niriWorkspaces[id];
            if (ws.output === screen || screen === "")
                list.push({ "id": ws.id, "idx": ws.idx, "name": ws.name || "", "active": !!ws.is_active, "windows": !!busy[ws.id] });
        }
        list.sort((a, b) => a.idx - b.idx);
        const sig = JSON.stringify(list);
        if (sig !== _workspacesSignature) {
            _workspacesSignature = sig;
            workspaces = list;
        }
        const name = focused ? _appName(focused.app_id) : "";
        if (name !== focusedApp)
            focusedApp = name;
        const id = focused ? focused.id : -1;
        if (id !== focusedWindow)
            focusedWindow = id;
        const title = focused ? focused.title || "" : "";
        if (title !== focusedTitle)
            focusedTitle = title;
        const appId = focused ? focused.app_id || "" : "";
        if (appId !== _focusedAppId)
            _focusedAppId = appId;
        const out = _niriOutputs[screen];
        const size = focused && focused.layout ? focused.layout.window_size : null;
        const tile = focused && focused.layout ? focused.layout.tile_size : null;
        const full = !!size && !!out && !!out.logical && size[0] >= Math.floor(out.logical.width) && size[1] >= Math.floor(out.logical.height);
        const state = {
            "floating": !!focused && !!focused.is_floating,
            "fullscreen": full,
            "maximized": !full && !!tile && !!out && !!out.logical && !(focused && focused.is_floating) && tile[0] >= out.logical.width * Config.bar.appMenu.maximizedShare
        };
        if (JSON.stringify(state) !== JSON.stringify(focusedState))
            focusedState = state;
    }
    // an app id ("org.gnome.Nautilus", "zen") -> its name ("Files", "Zen Browser"), from its desktop entry
    property var _appNames: ({})
    function _appName(appId) {
        if (!appId)
            return "";
        if (appId in _appNames)
            return _appNames[appId];
        const entry = _entryFor([appId, _lastPart(appId)]);
        const last = _lastPart(appId);
        const name = entry ? entry.name : last.charAt(0).toUpperCase() + last.slice(1);
        _appNames[appId] = name;
        return name;
    }
    // the distribution's id ("fedora", "arch"...: /etc/os-release ID), for the bar's logo; "" = unknown
    readonly property string distro: {
        const m = /^ID="?([^"\n]*)"?$/m.exec(osRelease.text() || "");
        return m ? m[1] : "";
    }
    FileView {
        id: osRelease
        path: "/etc/os-release"
        blockLoading: true
        printErrors: false
    }
    // run a menu item's command: {id} = the focused window's id, ~ at the start of an argument = home
    function runMenuCommand(command) {
        run(command.map(a => a.replace("{id}", String(focusedWindow)).replace(/^~(?=\/|$)/, home)));
    }

    // switch to the workspace at `idx` (1-based, the bar's screen), open / close the overview
    function focusWorkspace(idx) {
        run(Config.bar.workspaces.focusCommand.map(a => a.replace("{idx}", String(idx))));
    }
    function toggleOverview() {
        run(Config.bar.workspaces.overviewCommand);
    }
    function _fullscreenCheck() {
        const screen = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
        const out = _niriOutputs[screen];
        let full = false;
        if (_fullscreenWatch && out && out.logical && !_niriOverview) {
            for (const id in _niriWorkspaces) {
                const ws = _niriWorkspaces[id];
                if (ws.output !== screen || !ws.is_active)
                    continue;
                const win = _niriWindows[ws.active_window_id];
                const size = win && win.layout ? win.layout.window_size : null;
                full = !!size && size[0] >= Math.floor(out.logical.width) && size[1] >= Math.floor(out.logical.height);
            }
        }
        fullscreen = full;
    }

    // ==========================================
    // TRAY (apps' status icons: StatusNotifierItem)
    // ==========================================

    // the live list, for the bar's Repeater only (never kept: an item goes when its app quits)
    readonly property var trayItems: SystemTray.items.values
    // An icon's menu is drawn by the shell (the "tray" dropdown, TrayMenuMode, from trayMenu(id)): the
    // system's own drawing (item.display) needs Quickshell running as a widgets app and did nothing here.
    // Click (left or right): its menu when it has one (like a macOS menu bar extra: many apps, DashBeam
    // for one, do nothing on the plain "activate"), else the app's main action; middle click = the main
    // action. Items are looked up by id each time (an item goes when its app quits).
    function trayItem(id) {
        return SystemTray.items.values.find(i => i.id === id) || null;
    }
    function trayMenu(id) {
        const item = trayItem(id);
        return item && item.hasMenu ? item.menu : null;
    }
    function trayTitle(id) {
        const item = trayItem(id);
        return item ? item.tooltipTitle || item.title || "" : "";
    }
    function trayMain(id) {
        const item = trayItem(id);
        if (item)
            item.activate();
    }
    // a click on it does something: it has a menu, or it isn't only a menu (it has a main action)
    function trayClickable(item) {
        return !!item && (item.hasMenu || !item.onlyMenu);
    }
    function trayScroll(item, delta) {
        if (item)
            item.scroll(delta, false);
    }

    // ---- calendar: a month as weeks of days, `offset` months from today's (the calendar dropdown) ----
    // { title (calendar.titleFormat), weeks: [{ number (ISO week), days: [{ day, inMonth, today }] }] }.
    // Depends on the date (_today), not on `time`.
    function calendarMonth(offset) {
        const [y, m, d] = _today.split("-").map(Number);
        const first = new Date(y, m - 1 + offset, 1);
        const start = new Date(first.getFullYear(), first.getMonth(), 1 - ((first.getDay() - Config.time.weekStart + 7) % 7));
        const weeks = [];
        for (let w = 0; w < 6; w++) {
            const days = [];
            for (let i = 0; i < 7; i++) {
                const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + w * 7 + i);
                days.push({
                    "day": day.getDate(),
                    "inMonth": day.getMonth() === first.getMonth(),
                    "today": day.getFullYear() === y && day.getMonth() === m - 1 && day.getDate() === d
                });
            }
            const thursday = new Date(Date.UTC(start.getFullYear(), start.getMonth(), start.getDate() + w * 7 + 3));
            thursday.setUTCDate(thursday.getUTCDate() + 4 - (thursday.getUTCDay() || 7));
            const yearStart = new Date(Date.UTC(thursday.getUTCFullYear(), 0, 1));
            // a sixth row only when the month reaches it
            if (w === 5 && !days.some(x => x.inMonth))
                break;
            weeks.push({ "number": Math.ceil(((thursday - yearStart) / 86400000 + 1) / 7), "days": days });
        }
        return { "title": Qt.formatDate(first, Config.time.titleFormat), "weeks": weeks };
    }
    // the weekday names in the calendar's order (calendar headers), from Config.time.weekStart
    function weekdayNames(format) {
        const names = [];
        for (let i = 0; i < 7; i++)
            names.push(Qt.formatDate(new Date(2024, 0, 7 + (Config.time.weekStart + i) % 7), format));   // 2024-01-07 was a Sunday
        return names;
    }

    // the current week, for the time panel: 7 days from Config.time.weekStart (0 = Sunday, 1 = Monday...)
    // [{ date: Date, day: int (day of month), weekday: int 0-6, today: bool }]. Only recomputed when the
    // date changes (it depends on _today, not on `time`, which ticks every second while the panel is open).
    readonly property string _today: Qt.formatDate(time, "yyyy-MM-dd")
    // today's date, "yyyy-MM-dd" (changes once a day; for "Today" / "Yesterday" labels), and yesterday's
    readonly property string today: _today
    readonly property string yesterday: {
        const [y, m, d] = _today.split("-").map(Number);
        return Qt.formatDate(new Date(y, m - 1, d - 1), "yyyy-MM-dd");
    }
    // the ISO week number of today (1-53), for the time panel; changes only with the date
    readonly property int weekNumber: {
        const [y, m, d] = _today.split("-").map(Number);
        const t = new Date(Date.UTC(y, m - 1, d));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));   // the Thursday of this week decides the year
        const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - yearStart) / 86400000 + 1) / 7);
    }
    readonly property var week: {
        const [y, m, d] = _today.split("-").map(Number);
        const now = new Date(y, m - 1, d);
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() - Config.time.weekStart + 7) % 7));
        const days = [];
        for (let i = 0; i < 7; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            days.push({
                "date": d,
                "day": d.getDate(),
                "weekday": d.getDay(),
                "today": d.getDate() === now.getDate() && d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()
            });
        }
        return days;
    }

    // ==========================================
    // APPS, COMMANDS (for the launcher)
    // ==========================================

    // installed desktop apps that want to be listed (recomputed only when apps are (un)installed)
    readonly property var apps: DesktopEntries.applications.values.filter(a => !a.noDisplay)

    // run a command (list: program then arguments) detached from the shell
    function run(command) {
        Quickshell.execDetached(command);
    }
    function copyText(text) {
        Quickshell.execDetached(["wl-copy", text]);
    }

    // ==========================================
    // PINS (the launcher's pinned tiles)
    // ==========================================

    // pins: [{ kind: "app" | "panel" | "action", id }] in the user's order (app = its desktop entry id,
    // panel = the mode's name, action = its title). Kept in the shell's state folder (pins.json), written
    // system.saveDelay after they last changed, read once at startup. The launcher resolves them (a missing app is skipped).
    property var pins: []
    function isPinned(kind, id) {
        return pins.some(p => p.kind === kind && p.id === id);
    }
    function togglePin(kind, id) {
        const next = isPinned(kind, id) ? pins.filter(p => !(p.kind === kind && p.id === id)) : pins.concat([{
                "kind": kind,
                "id": id
            }]);
        pins = next;
        pinsSave.restart();
    }
    // move a pin by `step` places (keyboard reordering in the launcher)
    function movePin(kind, id, step) {
        const i = pins.findIndex(p => p.kind === kind && p.id === id);
        const j = i + step;
        if (i < 0 || j < 0 || j >= pins.length)
            return;
        const next = pins.slice();
        next.splice(j, 0, next.splice(i, 1)[0]);
        pins = next;
        pinsSave.restart();
    }
    // written once the changes pause (dragging a tile moves it many times)
    Timer {
        id: pinsSave
        interval: Config.system.saveDelay
        onTriggered: pinsFile.setText(JSON.stringify(root.pins))
    }
    // a change still waiting when the shell reloads or quits is written right away, not lost
    Component.onDestruction: if (pinsSave.running)
        pinsFile.setText(JSON.stringify(root.pins))
    FileView {
        id: pinsFile
        path: Quickshell.statePath("pins.json")
        printErrors: false   // no file yet = no pins
        onLoaded: {
            try {
                const v = JSON.parse(text());
                root.pins = Array.isArray(v) ? v.filter(p => p && typeof p.kind === "string" && typeof p.id === "string") : [];
            } catch (e) {
                root.pins = [];
            }
        }
    }

    // ==========================================
    // SOUNDS
    // ==========================================

    // play one of assets/sounds (a short WAV) through PipeWire, at sounds.volume; one short detached
    // process per sound (they're rare: notifications and alerts). Muted output: nothing to play.
    function playSound(file) {
        if (!file || audio.muted)
            return;
        const path = decodeURIComponent(Qt.resolvedUrl("../assets/sounds/" + file).toString().replace(/^file:\/\//, ""));
        Quickshell.execDetached(["pw-play", "--volume", String(Config.sounds.volume), path]);
    }

    // ==========================================
    // FILES (for the launcher's file search)
    // ==========================================

    // files: [{ path, name, dir: bool, ext: lowercase extension ("" for folders), parent, depth }]
    // Everything under search.files.root, minus skipped folders. Not watched: listed on demand
    // (refreshFiles, called when file search opens), which costs a few ms for a tidy home folder and
    // nothing the rest of the time. Searching then filters this list in memory: instant per keystroke.
    property var files: []
    readonly property string home: Quickshell.env("HOME")
    readonly property string _filesRoot: Config.search.files.root.replace(/^~(?=\/|$)/, home)

    function refreshFiles() {
        if (!listFiles.running)
            listFiles.running = true;
    }

    // ---- settings: the desktop Settings app's own list of its settings (search.settings.indexCommand,
    // `settings --index`: [{ page, pageLabel, icon, title }]), read when the search opens (one short
    // process, nothing while it's closed). Without the app, the command fails and the list stays empty.
    property var settingsIndex: []
    function refreshSettings() {
        if (Config.search.settings.mode !== "off" && !listSettings.running)
            listSettings.running = true;
    }
    Process {
        id: listSettings
        command: Config.search.settings.indexCommand
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (Array.isArray(d))
                        root.settingsIndex = d.filter(e => e && e.page && e.title);
                } catch (e) {
                    // no app, or not its list: no settings in the results
                }
            }
        }
    }
    // open the Settings app on a page ("mouse"), scrolled to a setting ("Tap to click")
    function openSettings(page, title) {
        run(Config.search.settings.openCommand.map(a => a.replace("{page}", page).replace("{title}", title || "")));
    }

    // ==========================================
    // WALLPAPER (the wallpaper panel)
    // ==========================================

    // wallpapers: the pictures in wallpaper.folders (paths, sorted by name); wallpaper: the one shown now.
    // Both read by bin/wallpaper when the panel opens (two short processes, nothing while it's closed).
    // Applied the desktop Settings app's way (its swaybg line in niri's settings.kdl), so the app agrees.
    property var wallpapers: []
    property string wallpaper: ""
    readonly property string _wallpaperTool: decodeURIComponent(Qt.resolvedUrl("../bin/wallpaper").toString().replace(/^file:\/\//, ""))
    function refreshWallpapers() {
        if (!listWallpapers.running)
            listWallpapers.running = true;
        if (!readWallpaper.running)
            readWallpaper.running = true;
    }
    // shown as the one in use right away; read back once the tool is done, so a failed save doesn't stay
    function setWallpaper(path) {
        wallpaper = path;
        applyWallpaper.command = [_wallpaperTool, "set", path];
        applyWallpaper.running = true;
    }
    Process {
        id: applyWallpaper
        onExited: readWallpaper.running = true
    }
    Process {
        id: listWallpapers
        command: [root._wallpaperTool, "list", Config.wallpaper.extensions.join(","), String(Config.wallpaper.depth)].concat(Config.wallpaper.folders)
        stdout: StdioCollector {
            onStreamFinished: {
                const next = text.split("\n").filter(l => l);
                // replaced only when it changed: the panel keeps its cards otherwise
                if (next.join("\n") !== root.wallpapers.join("\n"))
                    root.wallpapers = next;
            }
        }
    }
    Process {
        id: readWallpaper
        command: [root._wallpaperTool, "current"]
        stdout: StdioCollector {
            onStreamFinished: root.wallpaper = text.trim()
        }
    }

    // ==========================================
    // SCREENSHOTS (niri's "Screenshot captured": the screenshot card, the shelf)
    // ==========================================

    // screenshots: the pictures in screenshot.folder, newest first: [{ path, time (ms since 1970), width,
    // height (0 = unknown) }], read when the panel opens by bin/screenshots (one short process: sizes from
    // the files' headers, nothing decoded; nothing while it's closed). Replaced only when it changed.
    // ---- the shelf: the folder the notch holds files in (shelf.folder; bin/shelf) ----
    // shelf: [{ path, name, time (ms), width, height (the preview's), preview (a picture path, "" = none:
    // the file type's icon), mime, icon (the file type's theme icon) }], newest first. Read when the shelf
    // opens and after each change made here (nothing watches the folder).
    property var shelf: []
    readonly property string shelfFolder: Config.shelf.folder.replace(/^~(?=\/|$)/, home)
    readonly property string _shelfTool: decodeURIComponent(Qt.resolvedUrl("../bin/shelf").toString().replace(/^file:\/\//, ""))
    property bool _shelfAgain: false
    function refreshShelf() {
        if (listShelf.running)
            _shelfAgain = true;
        else
            listShelf.running = true;
    }
    // things dropped on the notch (file:// or http(s):// addresses): copied / downloaded into the folder;
    // once there, shelfFocus names the first one (the shelf opens on it) and shelfAdded is emitted
    property string shelfFocus: ""
    signal shelfAdded(string path)
    // when something was last put on the shelf (ms; a drop or a screenshot): a click on the notch opens
    // the shelf for a little while after (Activity.openNotch)
    property double shelfTouched: 0
    function shelfAdd(urls) {
        const list = (urls || []).map(u => String(u)).filter(u => /^(file|https?):\/\//.test(u));
        if (list.length === 0)
            return;
        const proc = shelfProc.createObject(root, {
            "command": [_shelfTool, "add", shelfFolder].concat(list),
            "reports": true
        });
        proc.running = true;
    }
    // a screenshot (shelf.keepScreenshots): hard-linked into the folder
    function shelfKeep(path) {
        if (!Config.shelf.keepScreenshots || !path)
            return;
        const proc = shelfProc.createObject(root, {
            "command": [_shelfTool, "keep", shelfFolder, path]
        });
        proc.running = true;
    }
    // off the shelf: to the trash (shelf.removeCommand), never deleted outright
    function shelfRemove(path) {
        // off the list at once (the trash and the next read take a moment)
        shelf = shelf.filter(s => s.path !== path);
        const proc = shelfProc.createObject(root, {
            "command": _fill(Config.shelf.removeCommand, path)
        });
        proc.running = true;
    }
    // copy a picture to the clipboard, as an image (shelf.copyCommand)
    function copyImage(path) {
        run(_fill(Config.shelf.copyCommand, path));
    }
    Component {
        id: shelfProc
        Process {
            id: sp
            property bool reports: false
            stdout: StdioCollector {
                onStreamFinished: {
                    const first = text.split("\n").find(l => l.startsWith("/")) || "";
                    if (first !== "")
                        root.shelfTouched = Date.now();
                    if (sp.reports && first !== "") {
                        // on the shelf at once (its type's icon comes with the next read, its preview after)
                        if (!root.shelf.some(s => s.path === first))
                            root.shelf = [{
                                    "path": first,
                                    "name": first.slice(first.lastIndexOf("/") + 1),
                                    "time": Date.now(),
                                    "width": 0,
                                    "height": 0,
                                    "preview": "",
                                    "mime": "",
                                    "icon": ""
                                }].concat(root.shelf);
                        root.shelfFocus = first;
                        root.shelfAdded(first);
                    }
                    root.refreshShelf();
                    sp.destroy();
                }
            }
        }
    }
    // The list comes at once with the thumbnails already made (--cached); the missing ones are made
    // afterwards (bin/shelf thumbnails, a PDF's takes a second), then the folder is read again. Waiting for
    // them left a just-dropped file off the shelf for that second.
    Process {
        id: shelfThumbnails
        command: [root._shelfTool, "thumbnails", root.shelfFolder]
        stdout: StdioCollector {
            onStreamFinished: {
                if (Number(text) > 0)
                    root.refreshShelf();
            }
        }
    }
    Process {
        id: listShelf
        command: [root._shelfTool, "list", root.shelfFolder, "--cached"]
        stdout: StdioCollector {
            onStreamFinished: {
                const next = [];
                for (const l of text.split("\n")) {
                    const f = l.split("\t");
                    if (f.length < 7)
                        continue;
                    const path = f[3];
                    next.push({
                        "path": path,
                        "name": path.slice(path.lastIndexOf("/") + 1),
                        "time": Math.round(Number(f[0]) * 1000),
                        "width": Number(f[1]) || 0,
                        "height": Number(f[2]) || 0,
                        "preview": f[4],
                        "mime": f[5],
                        // the file type's icon, found by bin/shelf in the icon theme (Quickshell's own lookup
                        // doesn't know the desktop's theme: it found no type icons)
                        "icon": f[6] !== "" ? "file://" + f[6].split("/").map(encodeURIComponent).join("/") : ""
                    });
                }
                if (JSON.stringify(next) !== JSON.stringify(root.shelf))
                    root.shelf = next;
            }
        }
        onExited: {
            if (root._shelfAgain) {
                root._shelfAgain = false;
                Qt.callLater(() => listShelf.running = true);
            } else if (!shelfThumbnails.running)
                shelfThumbnails.running = true;
        }
    }
    Component.onCompleted: refreshShelf()

    // Handing a file to another app by drag and drop (a picture dragged out of the island): sandboxed apps
    // (a Flatpak browser, which can only read Downloads) can't open a path we give them, so the file also
    // goes through the desktop's file transfer portal, like Files does: offerFile(path) gets a key for it
    // (transferKeys[path], a moment later), dropped as application/vnd.portal.filetransfer; the app gets
    // its own readable copy of the file. bin/shelf transfer runs only while `fileTransfer` (the shelf
    // binds it while on screen); the keys last as long as it runs.
    property bool fileTransfer: false
    property var transferKeys: ({})
    property var _transferQueue: []
    function offerFile(path) {
        if (!path || transferKeys[path] || _transferQueue.indexOf(path) >= 0)
            return;
        _transferQueue.push(path);
        if (transferProc.running && transferProc.ready)
            _flushTransfers();
    }
    function _flushTransfers() {
        for (const path of _transferQueue)
            transferProc.write(path + "\n");
        _transferQueue = [];
    }
    Process {
        id: transferProc
        property bool ready: false
        command: [root._shelfTool, "transfer"]
        running: root.fileTransfer
        stdinEnabled: true
        onStarted: {
            ready = true;
            root._flushTransfers();
        }
        onRunningChanged: if (!running) {
            ready = false;
            root.transferKeys = {};
            root._transferQueue = [];
        }
        stdout: SplitParser {
            onRead: line => {
                const tab = line.indexOf("\t");
                if (tab <= 0 || line.startsWith("error"))
                    return;
                const keys = Object.assign({}, root.transferKeys);
                keys[line.slice(tab + 1)] = line.slice(0, tab);
                root.transferKeys = keys;
            }
        }
    }

    Process {
        id: listFiles
        // find <root> -mindepth 1 ( -name .* -o -name node_modules ... ) -prune -o -printf "%y<TAB>%p<NL>"
        command: {
            const cfg = Config.search.files;
            const names = (cfg.showHidden ? [] : [".*"]).concat(cfg.exclude);
            let skip = [];
            for (const n of names)
                skip = skip.concat(skip.length ? ["-o", "-name", n] : ["-name", n]);
            return ["find", root._filesRoot, "-mindepth", "1"].concat(skip.length ? ["("].concat(skip, [")", "-prune", "-o"]) : [], ["-printf", "%y\\t%p\\n"]);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const base = root._filesRoot.split("/").length;
                const out = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const path = line.slice(tab + 1);
                    const slash = path.lastIndexOf("/");
                    const name = path.slice(slash + 1);
                    const dir = line.slice(0, tab) === "d";
                    const dot = name.lastIndexOf(".");
                    out.push({
                        "path": path,
                        "name": name,
                        "dir": dir,
                        "ext": !dir && dot > 0 ? name.slice(dot + 1).toLowerCase() : "",
                        "parent": path.slice(0, slash),
                        "depth": path.split("/").length - base
                    });
                    if (out.length >= Config.search.files.maxEntries)
                        break;
                }
                root.files = out;
            }
        }
    }

    // "~/Documents" style display of a path
    function prettyPath(path) {
        return path === home || path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
    }

    // command from config with {path} / {uri} filled in (uri: file:// address, safe inside quotes)
    function _fill(command, path) {
        const uri = "file://" + encodeURI(path).replace(/'/g, "%27");
        return command.map(a => a.replace("{path}", path).replace("{uri}", uri));
    }
    // open in the default app (folders: the file manager)
    function openFile(path) {
        run(_fill(Config.search.files.openCommand, path));
    }
    // ---- screenshots: niri says "Screenshot captured" with a notification (screenshot.summaries) ----
    // the picture's path from the notification (its image, else an icon given as a file path), "" if none
    function screenshotPath(n) {
        if (!n || Config.screenshot.summaries.indexOf(n.summary) < 0)
            return "";
        for (const s of [n.image || "", n.appIcon || ""]) {
            // a file:// address is percent-encoded; a plain path is used as it is (a "%" in a name stays)
            const f = s.startsWith("file://") ? decodeURIComponent(s.slice(7)) : s;
            if (f.startsWith("/"))
                return f;
        }
        return "";
    }
    // done(path, width, height): the screenshot's file (the notification's, else the newest file saved in
    // screenshot.folder in the last screenshot.recent seconds; "" = none: show it as a plain notification)
    // and its size in pixels (0 x 0 when unknown), read from its header by `file` (one short process, no
    // decoding: the island takes the picture's shape before it opens)
    function findScreenshot(n, done) {
        const proc = shotProc.createObject(root, {
            "command": ["sh", "-c", "p=$1; [ -n \"$p\" ] || p=$(find \"$2\" -maxdepth 1 -type f -newermt \"-$3 seconds\" -printf '%T@ %p\\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-); [ -f \"$p\" ] || exit 0; echo \"$p\"; file -b -- \"$p\"", "sh", screenshotPath(n), Config.screenshot.folder.replace(/^~(?=\/|$)/, home), String(Config.screenshot.recent)],
            "done": done
        });
        proc.running = true;
    }
    Component {
        id: shotProc
        Process {
            id: p
            property var done
            stdout: StdioCollector {
                onStreamFinished: {
                    const lines = text.split("\n");
                    const m = /(\d+)\s*x\s*(\d+)/.exec(lines[1] || "");
                    p.done(lines[0] || "", m ? Number(m[1]) : 0, m ? Number(m[2]) : 0);
                    p.destroy();
                }
            }
        }
    }

    // open a web address in the default browser (the launcher's web search)
    // Opens a link in the browser, then brings the browser forward (search.web.focusBrowser): a running
    // browser opens it in a tab of a window that may sit on another workspace or behind, so it looked like
    // nothing had happened. The default browser (search.web.browserCommand: its desktop file) is matched
    // against niri's windows like a notification's app (_senderWindow); not running = its new window
    // takes the focus by itself.
    function openUrl(url) {
        run(Config.search.web.command.map(a => a.replace("{url}", url)));
        if (Config.search.web.focusBrowser)
            _focusBrowser();
    }
    function _focusBrowser() {
        const which = windowsProc.createObject(root, {
            "command": Config.search.web.browserCommand,
            "done": out => {
                const id = String(out || "").trim();
                if (id === "")
                    return;
                const names = [id];
                const entry = root._entryFor(names);
                const list = windowsProc.createObject(root, {
                    "command": Config.notifications.open.windowsCommand,
                    "done": json => {
                        let windows = [];
                        try {
                            windows = JSON.parse(json);
                        } catch (e) {
                            return;
                        }
                        const w = root._senderWindow(windows, [], names, entry);
                        if (w)
                            root.run(Config.notifications.open.focusCommand.map(a => a.replace("{id}", String(w.id))));
                    }
                });
                list.running = true;
            }
        });
        which.running = true;
    }
    // show in the file manager, selected
    function revealFile(path) {
        run(_fill(Config.search.files.revealCommand, path));
    }

    // ==========================================
    // WI-FI
    // ==========================================

    // wifi: { enabled: bool, connected: bool, ssid: string, name: string, bars: int 0-3 (0 = no signal) }
    readonly property var wifi: ({
            "enabled": !!Networking.wifiEnabled,
            "connected": _wifiActive !== null,
            "ssid": _wifiActive ? (_wifiActive.ssid || _wifiActive.name || "") : "",
            "name": _wifiActive ? (_wifiActive.name || "") : "",
            "bars": _wifiBars
        })
    // signal bars of the current connection. Its own int, so `wifi` (a new object, which always notifies)
    // is rebuilt only when the bar count changes, not each time NetworkManager updates the strength
    // (the active network can be half gone while NetworkManager swaps it: its strength read as nothing and
    // the int got undefined, a warning; anything not a number counts as no signal)
    readonly property int _wifiBars: {
        const s = _wifiActive ? Number(_wifiActive.signalStrength) : 0;
        const q = isNaN(s) ? 0 : s * 100;
        return q > 66 ? 3 : q > 33 ? 2 : q > 0 ? 1 : 0;
    }

    // Nearby networks, for the Wi-Fi panel. Scanning (and this list) only runs while something sets
    // wifiScan (the panel, while it's open): no radio scans the rest of the time.
    // wifiNetworks: [{ name, level: int 0 to idle.wifi.icons.length - 1 (signal bars), secure: bool,
    //                  known: bool (saved), connected: bool, connecting: bool, failed: bool (last attempt failed) }]
    // Same-name access points are merged (strongest kept). Order: connected, saved, then bars, then name, so
    // signal noise doesn't shuffle the rows. The list is only replaced when something shown changes:
    // signal strength moves several times a second while scanning, and each new list rebuilds every row.
    property bool wifiScan: false
    Binding {
        when: root._wifiDevice !== null
        target: root._wifiDevice
        property: "scannerEnabled"
        value: root.wifiScan
    }
    property var wifiNetworks: []
    property string _wifiSignature: ""
    readonly property var _wifiScanned: {
        if (!wifiScan || !_wifiDevice || !_wifiDevice.networks)
            return [];
        const levels = Config.bar.wifi.icons.length;
        const byName = {};
        for (const n of _wifiDevice.networks.values) {
            if (!n.name)
                continue;
            const strength = n.signalStrength;
            const item = {
                "name": n.name,
                "strength": strength,
                "level": Math.max(0, Math.min(levels - 1, Math.floor(strength * levels))),
                "secure": n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe,
                "known": n.known,
                "connected": n.connected,
                "connecting": n.state === ConnectionState.Connecting,
                "failed": n.name === _wifiFailed
            };
            const old = byName[n.name];
            if (!old || item.connected || (!old.connected && strength > old.strength))
                byName[n.name] = item;
        }
        const rank = n => n.connected ? 2 : n.known ? 1 : 0;
        return Object.values(byName).sort((a, b) => rank(b) - rank(a) || b.level - a.level || a.name.localeCompare(b.name));
    }
    on_WifiScannedChanged: {
        const shown = _wifiScanned.map(n => ({
                    "name": n.name,
                    "level": n.level,
                    "secure": n.secure,
                    "known": n.known,
                    "connected": n.connected,
                    "connecting": n.connecting,
                    "failed": n.failed
                }));
        const signature = JSON.stringify(shown);
        if (signature === _wifiSignature)
            return;
        _wifiSignature = signature;
        wifiNetworks = shown;
    }
    // the live network object for a name: the connected one, else the strongest
    function _wifiNetwork(name) {
        if (!_wifiDevice || !_wifiDevice.networks)
            return null;
        let best = null;
        for (const n of _wifiDevice.networks.values) {
            if (n.name !== name)
                continue;
            if (n.connected)
                return n;
            if (!best || n.signalStrength > best.signalStrength)
                best = n;
        }
        return best;
    }

    function setWifiEnabled(on) {
        Networking.wifiEnabled = on;
    }
    // name: a network's name from wifiNetworks. psk: password for a secured network ("" = use the saved one)
    function connectWifi(name, psk) {
        const network = _wifiNetwork(name);
        if (!network)
            return;
        _wifiFailed = "";
        _wifiPending = network;
        if (psk)
            network.connectWithPsk(psk);
        else
            network.connect();
    }
    // name of the network whose last connection attempt failed ("" = none)
    property string _wifiFailed: ""
    property var _wifiPending: null
    Connections {
        target: root._wifiPending
        ignoreUnknownSignals: true
        function onConnectionFailed(reason) {
            root._wifiFailed = root._wifiPending ? root._wifiPending.name : "";
        }
    }

    readonly property var _wifiDevice: {
        const devs = Networking.devices ? Networking.devices.values : [];
        return devs.find(d => d.type === DeviceType.Wifi) || null;
    }
    readonly property var _wifiActive: {
        if (!_wifiDevice || !_wifiDevice.networks)
            return null;
        return _wifiDevice.networks.values.find(n => n.connected) || null;
    }

    // ==========================================
    // BLUETOOTH
    // ==========================================

    // bluetooth: {
    //   available: bool       there is a Bluetooth adapter,
    //   enabled: bool         it's on,
    //   connected: bool       at least one device is connected,
    //   name: string          the first connected device ("" = none), count: int (connected devices),
    //   audioConnected: bool  a connected device is headphones / a speaker,
    //   otherConnected: bool  a connected device is something else (mouse, keyboard, phone...)
    // }
    readonly property var bluetooth: {
        const a = _btAdapter;
        const on = !!a && a.enabled;
        const connected = on ? a.devices.values.filter(d => d.connected) : [];
        const audio = connected.filter(d => _btKind(d.icon) === "headphones" || _btKind(d.icon) === "speaker");
        return {
            "available": !!a,
            "enabled": on,
            "connected": connected.length > 0,
            "name": connected.length > 0 ? connected[0].name : "",
            "count": connected.length,
            "audioConnected": audio.length > 0,
            "otherConnected": connected.length > audio.length
        };
    }

    // Devices, for the Bluetooth panel. Discovery (looking for new devices, and this list) only runs while
    // something sets bluetoothScan (the panel, while it's open): the radio doesn't search the rest of the time.
    // bluetoothDevices: [{ address, name, kind: "headphones"|"speaker"|"mouse"|"keyboard"|"gamepad"|"phone"|
    //                      "computer"|"other", paired: bool (saved), connected: bool, busy: "" | "connecting" |
    //                      "disconnecting" | "pairing", failed: bool (last attempt failed),
    //                      battery: int 0-100 (-1 = unknown) }]
    // Order: connected, paired, then name. Devices without a name are left out unless paired (most are
    // anonymous BLE beacons). Only replaced when something shown changes.
    property bool bluetoothScan: false
    Binding {
        when: root.bluetoothScan && root._btAdapter !== null && root._btAdapter.enabled
        target: root._btAdapter
        property: "discovering"
        value: true
    }
    property var bluetoothDevices: []
    property string _btSignature: ""
    readonly property var _btScanned: {
        const a = _btAdapter;
        if (!bluetoothScan || !a || !a.enabled)
            return [];
        const out = [];
        for (const d of a.devices.values) {
            if (!d.paired && (d.deviceName || "") === "")
                continue;
            const pending = _btPending === d;
            out.push({
                "address": d.address,
                "name": d.name || d.address,
                "kind": _btKind(d.icon),
                "paired": d.paired,
                "connected": d.connected,
                "busy": d.pairing || (pending && _btStep === "pair") ? "pairing" : d.state === BluetoothDeviceState.Connecting || pending ? "connecting" : d.state === BluetoothDeviceState.Disconnecting ? "disconnecting" : "",
                "failed": d.address === _btFailed,
                "battery": d.batteryAvailable ? Math.round(d.battery * 100) : -1
            });
        }
        const rank = d => d.connected ? 2 : d.paired ? 1 : 0;
        return out.sort((x, y) => rank(y) - rank(x) || x.name.localeCompare(y.name));
    }
    on_BtScannedChanged: {
        const signature = JSON.stringify(_btScanned);
        if (signature === _btSignature)
            return;
        _btSignature = signature;
        bluetoothDevices = _btScanned;
    }

    function setBluetoothEnabled(on) {
        if (_btAdapter)
            _btAdapter.enabled = on;
    }
    // address: a device's address from bluetoothDevices. A saved device connects; a new one is paired first,
    // then trusted (so it can reconnect by itself later) and connected.
    function connectBluetooth(address) {
        const d = _btDevice(address);
        if (!d || d.connected)
            return;
        _btFailed = "";
        _btSawConnecting = false;
        _btPending = d;
        btAttempt.restart();
        if (d.paired) {
            _btStep = "connect";
            d.connect();
        } else {
            _btStep = "pair";
            d.pair();
        }
    }
    function disconnectBluetooth(address) {
        const d = _btDevice(address);
        if (!d)
            return;
        if (_btPending === d)
            _btDone("");
        d.disconnect();
    }

    // the attempt in progress: the live device, and "pair" or "connect"
    property var _btPending: null
    property string _btStep: ""
    property bool _btSawConnecting: false
    // address of the device whose last attempt failed ("" = none)
    property string _btFailed: ""
    function _btDone(failedAddress) {
        btAttempt.stop();
        _btFailed = failedAddress;
        _btPending = null;
        _btStep = "";
    }
    Connections {
        target: root._btPending
        ignoreUnknownSignals: true
        function onPairedChanged() {
            const d = root._btPending;
            if (!d.paired || root._btStep !== "pair")
                return;
            d.trusted = true;
            root._btStep = "connect";
            root._btSawConnecting = false;
            d.connect();
        }
        function onPairingChanged() {
            const d = root._btPending;
            if (!d.pairing && !d.paired && root._btStep === "pair")
                root._btDone(d.address);
        }
        function onConnectedChanged() {
            if (root._btPending.connected)
                root._btDone("");
        }
        function onStateChanged() {
            const d = root._btPending;
            if (d.state === BluetoothDeviceState.Connecting)
                root._btSawConnecting = true;
            else if (d.state === BluetoothDeviceState.Disconnected && root._btSawConnecting && root._btStep === "connect")
                root._btDone(d.address);
        }
    }
    // no answer in time (device out of range, asleep): give up on it
    Timer {
        id: btAttempt
        interval: Config.bluetooth.attemptTimeout
        onTriggered: {
            const d = root._btPending;
            if (!d)
                return;
            if (root._btStep === "pair")
                d.cancelPair();
            root._btDone(d.connected ? "" : d.address);
        }
    }

    readonly property var _btAdapter: Bluetooth.defaultAdapter
    function _btDevice(address) {
        return _btAdapter ? _btAdapter.devices.values.find(d => d.address === address) || null : null;
    }
    // BlueZ's icon name ("audio-headset", "input-mouse"...) -> the kinds the panel has icons for
    function _btKind(icon) {
        const i = icon || "";
        if (/^audio-head/.test(i))
            return "headphones";
        if (/^audio-/.test(i))
            return "speaker";
        if (i === "input-mouse" || i === "input-tablet")
            return "mouse";
        if (i === "input-keyboard")
            return "keyboard";
        if (i === "input-gaming")
            return "gamepad";
        if (i === "phone")
            return "phone";
        if (i === "computer")
            return "computer";
        return "other";
    }

    // ==========================================
    // AUDIO OUTPUT
    // ==========================================

    // audio: {
    //   connectedDevice: string  "" when playing through the built-in speakers,
    //   ready: bool              there is an output to control,
    //   volume: real             0 - volume.max (1 = 100 %),
    //   muted: bool,
    //   micReady: bool, micMuted: bool   default input (microphone)
    // }
    readonly property var audio: {
        const sink = Pipewire.defaultAudioSink;
        const src = Pipewire.defaultAudioSource;
        const out = sink && sink.audio ? sink.audio : null;
        const mic = src && src.audio ? src.audio : null;
        return {
            "connectedDevice": _audioExternalName,
            "ready": out !== null,
            "volume": out ? _level(out) : 0,
            "muted": out ? out.muted : false,
            "micReady": mic !== null,
            "micMuted": mic ? mic.muted : false
        };
    }
    property string _audioExternalName: ""

    // volume/mute are only live on nodes that are tracked
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    // A node's volume = its loudest channel. Pipewire's `volume` is the channels' average, and setting
    // it gives every channel the same level: that erased the left / right balance set in the settings
    // app (and the average sinks as the balance moves). So read the loudest channel, and change the
    // volume by scaling every channel, which keeps the balance.
    function _level(a) {
        const vs = a.volumes || [];
        return vs.length ? Math.max(...vs) : a.volume;
    }
    function _setLevel(a, v) {
        const vs = a.volumes || [];
        const top = vs.length ? Math.max(...vs) : 0;
        if (vs.length > 1 && top > 0)
            a.volumes = vs.map(c => c * v / top);
        else
            a.volume = v;
    }

    // set the output volume (1 = 100 %), clamped to 0 - volume.max. Returns false if it was already
    // at that limit (nothing to change), so the caller can show the "hit the end" bounce.
    function setVolume(v) {
        const sink = Pipewire.defaultAudioSink;
        if (!sink || !sink.audio)
            return false;
        const target = Math.max(0, Math.min(Config.volume.max, v));
        const changed = Math.abs(target - _level(sink.audio)) > 0.0005;
        if (changed)
            _setLevel(sink.audio, target);
        if (Config.volume.unmuteOnChange && sink.audio.muted && target > 0)
            sink.audio.muted = false;
        return changed;
    }
    // one step up (+1) or down (-1), snapped to the step grid
    function changeVolume(direction) {
        const step = Config.volume.step;
        return setVolume((Math.round(audio.volume / step) + direction) * step);
    }
    function toggleMute() {
        const sink = Pipewire.defaultAudioSink;
        if (sink && sink.audio)
            sink.audio.muted = !sink.audio.muted;
    }
    function toggleMicMute() {
        const src = Pipewire.defaultAudioSource;
        if (src && src.audio)
            src.audio.muted = !src.audio.muted;
    }

    // the outputs sound can go to (quick settings' list under the volume): [{ name, description, active }],
    // the one in use first. Plain values: setAudioOutput looks the node up again by name.
    readonly property var audioOutputs: {
        const def = Pipewire.defaultAudioSink;
        const list = Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio).map(n => ({
                    "name": n.name,
                    "description": n.description || n.nickname || n.name,
                    "active": !!def && def.name === n.name
                }));
        list.sort((a, b) => (b.active - a.active) || a.description.localeCompare(b.description));
        return list;
    }
    function setAudioOutput(name) {
        const node = Pipewire.nodes.values.find(n => n.name === name && n.isSink && !n.isStream);
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }

    // Pipewire doesn't expose the sink's active port (speaker vs headphone jack), so ask pactl,
    // only when something changes (pactl subscribe below), debounced
    Process {
        id: getAudioSinks
        command: ["pactl", "--format=json", "list", "sinks"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const sinks = JSON.parse(text);
                    const def = Pipewire.defaultAudioSink;
                    const sink = def ? sinks.find(s => s.name === def.name) : null;
                    if (!sink) {
                        root._audioExternalName = "";
                        return;
                    }
                    const port = (sink.ports || []).find(p => p.name === sink.active_port);
                    const portName = String(sink.active_port || "").toLowerCase();
                    const isBluetooth = sink.name.startsWith("bluez_");
                    const isUsb = sink.name.startsWith("alsa_output.usb");
                    const isWiredPort = /headphone|headset|lineout|hdmi|displayport/.test(portName);

                    if (isBluetooth || isUsb)
                        root._audioExternalName = sink.description || sink.name;
                    else if (isWiredPort)
                        root._audioExternalName = (port && port.description) || sink.description || "Headphones";
                    else
                        root._audioExternalName = "";
                } catch (e) {
                    console.warn("Sys: failed to parse pactl sinks:", e);
                }
            }
        }
    }
    // bursts of events (a plug-in fires several) trigger a single refresh
    Timer {
        id: audioRefresh
        interval: Config.system.audioDebounce
        onTriggered: getAudioSinks.running = true
    }
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            audioRefresh.restart();
        }
    }
    // sink / server events: plugging a jack, a Bluetooth headset connecting...
    Process {
        id: audioEvents
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf(" on sink #") !== -1 || line.indexOf(" on server") !== -1)
                    audioRefresh.restart();
            }
        }
        // the stream ends if PipeWire restarts: start it again, and re-check since events were missed
        onExited: audioEventsRestart.start()
    }
    Timer {
        id: audioEventsRestart
        interval: Config.system.restartDelay
        onTriggered: {
            audioEvents.running = true;
            audioRefresh.restart();
        }
    }

    // ==========================================
    // MEDIA (MPRIS: what's playing, in any app that publishes it)
    // ==========================================

    // media: {
    //   active: bool       a player has a track (playing or paused)
    //   playing: bool
    //   title, artist, album, app: string     app = the player's name ("Spotify", "Firefox")
    //   artUrl: string     cover art (file:// or https://), "" if none
    //   length: real       seconds (0 = unknown, e.g. a live stream). If the player stops giving it
    //                      mid-track, the one it gave before (Sys then counts the position; canSeek false)
    //   canPlayPause, canNext, canPrevious, canSeek: bool
    // }
    // The player shown: the one playing, else the last one that played, else any with a track.
    readonly property var media: {
        const p = _mediaPlayer;
        if (!p)
            return {
                "active": false,
                "playing": false,
                "title": "",
                "artist": "",
                "album": "",
                "app": "",
                "artUrl": "",
                "length": 0,
                "canPlayPause": false,
                "canNext": false,
                "canPrevious": false,
                "canSeek": false
            };
        return {
            "active": (p.trackTitle || "") !== "",
            "playing": p.isPlaying,
            "title": p.trackTitle || "",
            "artist": p.trackArtist || "",
            "album": p.trackAlbum || "",
            "app": p.identity || "",
            "artUrl": p.trackArtUrl || "",
            "length": _mediaLengthGuessed ? _knownLength : _reportedLength,
            "canPlayPause": p.canTogglePlaying,
            "canNext": p.canGoNext,
            "canPrevious": p.canGoPrevious,
            "canSeek": p.canSeek && p.positionSupported && !_mediaLengthGuessed
        };
    }
    // The length the player gave for this track, kept in case it stops giving it. Zen/Firefox guess the
    // length and position from the page's <video>/<audio> when the site doesn't report them (YouTube Music
    // doesn't), and give up while the tab has more than one (Firefox's MediaPlaybackStatus: "Count != 1"),
    // e.g. YouTube Music's short clip on the song's page: no length, position 0, no signals. A track that
    // started with a length keeps it (same player, title and artist) and Sys counts the time on from the
    // last real position, pausing with the player. A track that never gave one has no timeline.
    readonly property real _reportedLength: _freshLength()
    readonly property string _trackKey: _freshKey()
    property real _knownLength: 0
    property string _knownLengthKey: ""
    readonly property bool _mediaLengthGuessed: _reportedLength <= 0 && _knownLength > 0 && _knownLengthKey === _trackKey && _trackKey !== ""
    // read straight from the player: Quickshell updates a new track's title, artist and length one by one,
    // in no set order, so the bindings above can lag behind for a moment (see CLAUDE.md, QML gotchas)
    function _freshLength() {
        const p = _mediaPlayer;
        return p && p.lengthSupported && p.length > 0 ? p.length : 0;
    }
    function _freshKey() {
        const p = _mediaPlayer;
        return p ? [p.dbusName, p.trackTitle || "", p.trackArtist || ""].join("\n") : "";
    }
    function _lengthLost() {
        return _freshLength() <= 0 && _knownLength > 0 && _knownLengthKey === _freshKey();
    }
    // once the player's change has fully landed (callLater): a new track learns its own length (or none,
    // so the last song's can't carry over), a length that comes back makes the position real again
    function _relearnLength() {
        const len = _freshLength(), key = _freshKey();
        if (len > 0 || key !== _knownLengthKey) {
            _knownLength = len;
            _knownLengthKey = key;
        }
        if (len > 0)
            _readMediaPosition();
    }
    on_ReportedLengthChanged: Qt.callLater(_relearnLength)
    on_TrackKeyChanged: Qt.callLater(_relearnLength)
    // where the track is. Players only say it now and then (a seek, play / pause, a new track: Quickshell's
    // positionChanged), so Sys keeps an anchor (position + when + how fast) and works the rest out itself;
    // nothing polls. mediaTimelineChanged fires when the anchor moves (a jump or a speed change): whoever
    // shows the position reads mediaPositionNow() then and animates from there at mediaRate.
    // Quickshell's own estimate isn't used between reports: it jumps when the rate changes, and Zen/Firefox
    // set the rate to 0 for a moment after a seek (buffering) while still "Playing", which froze the bar.
    signal mediaTimelineChanged
    readonly property real mediaRate: _anchorRate
    function mediaPositionNow() {
        const pos = _anchorPos + (Date.now() - _anchorAt) / 1000 * _anchorRate;
        return Math.max(0, media.length > 0 ? Math.min(media.length, pos) : pos);
    }
    property real _anchorPos: 0
    property real _anchorAt: 0
    property real _anchorRate: 0
    // playing = moves at the player's rate (a rate of 0 while "Playing" is a buffering blip: taken as 1)
    readonly property real _mediaSpeed: {
        const p = _mediaPlayer;
        if (!p || !media.playing)
            return 0;
        return p.rate > 0 ? p.rate : 1;
    }
    function _anchorTo(pos) {
        _anchorPos = pos;
        _anchorAt = Date.now();
        _anchorRate = _mediaSpeed;
        mediaTimelineChanged();
    }
    // the speed changed: carry on from where the old speed got to
    on_MediaSpeedChanged: _anchorTo(mediaPositionNow())
    function _readMediaPosition() {
        const p = _mediaPlayer;
        // the player has no position while its length is gone (it reads 0): keep counting
        if (_lengthLost()) {
            _anchorTo(mediaPositionNow());
            return;
        }
        _anchorTo(p && p.positionSupported ? p.position : 0);
    }
    Connections {
        target: root._mediaPlayer
        ignoreUnknownSignals: true
        // a report from the player (Seeked, a re-read, our own seek): Quickshell's value is fresh right now
        function onPositionChanged() {
            root._readMediaPosition();
        }
        function onPostTrackChanged() {
            root._readMediaPosition();
        }
    }
    on_MediaPlayerChanged: {
        _readMediaPosition();
        if (_mediaPlayer && _mediaPlayer.isPlaying)
            _mediaLast = _mediaPlayer.dbusName;
    }

    // ---- the music's real levels, for the bars (cava) ----
    // mediaLevels: one 0-1 level per band, low to high (as many bands as the most bars shown anywhere),
    // mediaLevelsLive: they're flowing (cava installed and running). cava (a separate program) listens to
    // what PipeWire plays, only while music plays and a MediaBars is on screen (each one counts itself in
    // mediaLevelUsers), media.bars.realSound on. Without cava the bars fall back to their own dance.
    readonly property var mediaLevels: _mediaLevels
    readonly property bool mediaLevelsLive: levelStream.running && _mediaLevels.length > 0
    property var _mediaLevels: []
    property int mediaLevelUsers: 0
    // cava missing or failing: the bars dance on their own until the next start (no retry loop)
    property bool _cavaMissing: false
    readonly property bool _levelsWanted: mediaLevelUsers > 0 && media.playing && Config.media.bars.realSound
    // a short gap with no bars on screen (the music in the notch covered by a pop-up for a moment) keeps cava
    // running: it stops media.bars.stopDelay after the last one goes
    property bool _levelsOn: false
    on_LevelsWantedChanged: {
        if (_levelsWanted) {
            levelStop.stop();
            if (!_levelsOn)
                _cavaMissing = false; // installed since? one cheap check per start
            _levelsOn = true;
        } else
            levelStop.restart();
    }
    Timer {
        id: levelStop
        interval: Config.media.bars.stopDelay
        onTriggered: {
            root._levelsOn = false;
            root._mediaLevels = [];
        }
    }
    readonly property int mediaLevelBands: Math.max(Config.media.bars.count, Config.nowPlaying.count)
    readonly property string _cavaConfig: ["[general]", "bars = " + mediaLevelBands, "framerate = " + Config.media.bars.framerate, "autosens = 1", "lower_cutoff_freq = " + Config.media.bars.lowFrequency, "higher_cutoff_freq = " + Config.media.bars.highFrequency, "[input]", "method = pulse", "source = auto", "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii", "ascii_max_range = 1000", "bar_delimiter = 59", "frame_delimiter = 10", "channels = mono", "mono_option = average", "[smoothing]", "noise_reduction = " + Config.media.bars.smoothing, ""].join("\n")
    Process {
        id: levelStream
        // Fedora's cava has no PipeWire input: it listens through PipeWire's PulseAudio side (the default
        // output's monitor). Exit 127 = no cava.
        command: ["bash", "-c", "command -v cava >/dev/null || exit 127; exec cava -p <(printf '%s' \"$1\")", "cava", root._cavaConfig]
        running: root._levelsOn && !root._cavaMissing
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";");
                const levels = [];
                for (const v of parts)
                    if (v !== "")
                        levels.push(Math.min(1, Number(v) / 1000));
                root._mediaLevels = levels;
            }
        }
        // ended while still wanted (no cava, a config cava rejects, the sound server restarting): fall back
        // to the dance until music starts again or the bars come back
        onExited: code => {
            root._mediaLevels = [];
            if (!root._levelsOn)
                return; // we stopped it
            root._cavaMissing = true;
            if (code !== 15) // 15 = terminated (the shell reloading)
                console.warn("cava stopped (exit " + code + "): the music bars dance on their own until the next start");
        }
    }

    function mediaPlayPause() {
        const p = _mediaPlayer;
        if (p && p.canTogglePlaying)
            p.togglePlaying();
    }
    function mediaNext() {
        const p = _mediaPlayer;
        if (p && p.canGoNext)
            p.next();
    }
    function mediaPrevious() {
        const p = _mediaPlayer;
        if (p && p.canGoPrevious)
            p.previous();
    }
    // seconds from the start of the track
    function mediaSeek(seconds) {
        const p = _mediaPlayer;
        if (!p || !media.canSeek)
            return;
        // Quickshell then reports the new position (positionChanged), which moves the anchor
        p.position = Math.max(0, Math.min(p.lengthSupported ? p.length : seconds, seconds));
    }

    // the cover's color (ColorQuantizer, off the main thread, once per cover): the brightest of a few
    // average colors, lifted so it reads on black. media.accent.fallback without a cover.
    readonly property color mediaColor: {
        const cs = artColors.colors || [];
        let best = null, score = -1;
        for (const c of cs) {
            // saturated and bright wins over grey or dark
            const s = c.hsvSaturation * Config.media.accent.saturationWeight + c.hsvValue;
            if (s > score) {
                score = s;
                best = c;
            }
        }
        if (!best || !media.artUrl.startsWith("file://"))
            return Config.media.accent.fallback;
        return Qt.hsva(best.hsvHue, Math.min(1, best.hsvSaturation * Config.media.accent.saturate), Math.max(Config.media.accent.minBrightness, best.hsvValue), 1);
    }
    ColorQuantizer {
        id: artColors
        // local covers only (ColorQuantizer can't fetch https: those use the fallback)
        source: root.media.artUrl.startsWith("file://") ? root.media.artUrl : ""
        depth: Config.media.accent.depth
        rescaleSize: Config.media.accent.sampleSize
    }

    property string _mediaLast: ""
    // the music's own window is in front (Activity then keeps it out of the notch: you're looking at it).
    // The player's app (its desktop entry / name) against the focused window's app id; for a browser
    // (nowPlaying.browsers) the playing tab must be the one in front too: MPRIS doesn't say which tab
    // plays, but the window's title is the active tab's: it holds the track ("Gemstone - YouTube"), or the
    // name of a music site (nowPlaying.musicSites: YouTube Music's tab is often just "YouTube Music").
    // Anything else: the notch keeps showing it.
    readonly property bool mediaFocused: {
        const p = _mediaPlayer;
        const id = _norm(_focusedAppId);
        if (!p || id === "")
            return false;
        const names = [p.desktopEntry, _lastPart(p.desktopEntry), p.identity].map(_norm).filter(n => n.length > 1);
        const sameApp = names.some(n => n === id || n === _norm(_lastPart(_focusedAppId)) || (n.length > 2 && id.includes(n)));
        if (!sameApp)
            return false;
        const browser = Config.nowPlaying.browsers.some(b => id.includes(_norm(b)) || names.includes(_norm(b)));
        if (!browser)
            return true;
        const title = focusedTitle.toLowerCase();
        const track = (p.trackTitle || "").trim().toLowerCase();
        return (track !== "" && title.includes(track)) || Config.nowPlaying.musicSites.some(s => s !== "" && title.includes(s.toLowerCase()));
    }
    readonly property var _mediaPlayer: {
        const ps = Mpris.players.values;
        const playing = ps.find(p => p.isPlaying);
        if (playing)
            return playing;
        // one with a track first: a player left with no track (a closed tab's) never hides the one that has one
        const titled = p => (p.trackTitle || "") !== "";
        return ps.find(p => p.dbusName === _mediaLast && titled(p)) || ps.find(titled) || ps.find(p => p.dbusName === _mediaLast) || null;
    }
    // remember which one played last, so pausing it keeps it shown (not another paused one)
    Connections {
        target: root._mediaPlayer
        ignoreUnknownSignals: true
        function onIsPlayingChanged() {
            if (root._mediaPlayer && root._mediaPlayer.isPlaying)
                root._mediaLast = root._mediaPlayer.dbusName;
        }
    }
    // ==========================================
    // BRIGHTNESS
    // ==========================================

    // brightness: { ready: bool, level: real 0-1 }
    // Read once at startup, then kept by our own changes (writes go through brightnessctl, which
    // works without root via logind). sysfs can't notify, so a change made by another program shows
    // up the next time brightness changes here; nothing polls.
    readonly property var brightness: ({
            "ready": _backlightMax > 0,
            "level": _backlightMax > 0 ? _backlightRaw / _backlightMax : 0
        })
    property string _backlight: Config.brightness.device
    property real _backlightRaw: 0
    property real _backlightMax: 0
    property real _backlightPending: -1

    // set the level (0-1), clamped to brightness.min - 1. Returns false if it was already at that limit.
    function setBrightness(level) {
        if (_backlightMax <= 0)
            return false;
        const target = Math.round(Math.max(Config.brightness.min, Math.min(1, level)) * _backlightMax);
        if (target === Math.round(_backlightRaw))
            return false;
        _backlightRaw = target;      // the UI follows right away; the write catches up
        _backlightPending = target;
        if (!setBacklight.running)
            _flushBrightness();
        return true;
    }
    function changeBrightness(direction) {
        const step = Config.brightness.step;
        return setBrightness((Math.round(brightness.level / step) + direction) * step);
    }
    // one brightnessctl at a time: a burst of key repeats / slider moves only writes the latest value
    function _flushBrightness() {
        if (_backlightPending < 0 || _backlight === "")
            return;
        setBacklight.command = ["brightnessctl", "-q", "-d", _backlight, "set", String(_backlightPending)];
        _backlightPending = -1;
        setBacklight.running = true;
    }
    Process {
        id: setBacklight
        onExited: root._flushBrightness()
    }
    // device: brightness.device, or the first backlight the kernel lists
    Process {
        id: findBacklight
        running: root._backlight === ""
        command: ["ls", "/sys/class/backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const first = text.split("\n").find(l => l.trim() !== "");
                if (first)
                    root._backlight = first.trim();
            }
        }
    }
    FileView {
        path: root._backlight !== "" ? "/sys/class/backlight/" + root._backlight + "/max_brightness" : ""
        onLoaded: root._backlightMax = parseInt(text()) || 0
    }
    FileView {
        path: root._backlight !== "" ? "/sys/class/backlight/" + root._backlight + "/brightness" : ""
        onLoaded: root._backlightRaw = parseInt(text()) || 0
    }

    // ==========================================
    // NOTIFICATIONS
    // ==========================================

    // The shell is the notification daemon (org.freedesktop.Notifications). Each new notification is
    // emitted once through `notified`; Activity decides when the island shows it. The object stays live
    // (an app replacing it updates it in place) until it's dismissed, expires, or the app closes it.
    signal notified(var notification)

    // notification fields used by the UI, as plain values
    // { appName, summary, body, icon (url or ""), image (url or ""), urgency: "low"|"normal"|"critical",
    //   actions: [{ id, text }], hasDefault, timeout: ms (0 = the app didn't say) }
    function notificationInfo(n) {
        if (!n)
            return null;
        const icon = n.appIcon === "" ? "" : n.appIcon.startsWith("/") || n.appIcon.includes("://") ? n.appIcon : Quickshell.iconPath(n.appIcon, true);
        return {
            "appName": n.appName,
            "summary": n.summary,
            "body": n.body,
            "icon": icon || (n.desktopEntry !== "" ? Quickshell.iconPath(n.desktopEntry, true) : ""),
            "image": n.image,
            "urgency": n.urgency === NotificationUrgency.Critical ? "critical" : n.urgency === NotificationUrgency.Low ? "low" : "normal",
            "actions": (n.actions || []).filter(a => a.identifier !== "default").map(a => ({
                        "id": a.identifier,
                        "text": a.text
                    })),
            "hasDefault": (n.actions || []).some(a => a.identifier === "default"),
            "timeout": n.expireTimeout > 0 ? n.expireTimeout : 0
        };
    }
    // run one of the notification's actions ("default" = clicking the notification itself)
    function notificationAction(n, id) {
        const a = n ? (n.actions || []).find(x => x.identifier === id) : null;
        if (a)
            a.invoke();
    }
    // the user closed it (an already-closed notification has tracked = false, or is gone: nothing to do)
    function dismissNotification(n) {
        if (n && n.tracked)
            n.dismiss();
    }
    // its time ran out
    function expireNotification(n) {
        if (n && n.tracked)
            n.expire();
    }

    NotificationServer {
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: n => {
            n.tracked = true;
            root._noteSender(n);
            root.notified(n);
        }
    }

    // ---- clicking a notification: back to whatever sent it ----
    // 1. its own main action, if it has one (the app opens the conversation, the tab...);
    // 2. a system sender (notifications.open.systemApps: NetworkManager, printers...) without one: the
    //    Settings app on that page;
    // 3. the sender's window to the front (niri): the window of the process that sent it or of one of its
    //    parents (a terminal for a command run in it, like Claude Code's notify-send), else a window of
    //    the same app (its id / desktop entry / name);
    // 4. no window: the app itself is started (only for a known desktop app, without a main action).
    // The sender's process chain is read at arrival (sender-pid hint, /proc/<pid>/stat, synchronously:
    // ~1 ms; a notify-send has exited by the time you click). Plain values only, kept until it closes.
    property var _senders: ({})
    function _noteSender(n) {
        const o = Config.notifications.open;
        const pid = Number(n.hints ? n.hints["sender-pid"] : 0) || 0;
        if (!o.focusApp || pid <= 1)
            return;
        const chain = [];
        let p = pid;
        for (let i = 0; i < o.ancestors && p > 1; i++) {
            const f = statFile.createObject(root, { "path": "/proc/" + p + "/stat" });
            const t = f.text() || "";
            f.destroy();
            if (t === "")
                break;
            chain.push(p);
            // "pid (name) state ppid ...": the name can hold spaces and parentheses
            p = Number(t.slice(t.lastIndexOf(")") + 2).split(" ")[1]) || 0;
        }
        const id = n.id;
        _senders[id] = chain;
        n.closed.connect(() => delete root._senders[id]);
    }
    Component {
        id: statFile
        FileView {
            blockLoading: true
            printErrors: false   // the sender (a notify-send) may already be gone: the chain just ends there
        }
    }
    // letters and digits only, lower case: "org.gnome.Nautilus" ~ "nautilus", "Zen Browser" ~ "zenbrowser"
    function _norm(s) {
        return String(s || "").toLowerCase().replace(/\.desktop$/, "").replace(/[^a-z0-9]/g, "");
    }
    function _lastPart(s) {
        const parts = String(s || "").replace(/\.desktop$/, "").split(".");
        return parts[parts.length - 1];
    }
    // the desktop entry of an app named `names` (its desktop entry id first, then an exact name)
    function _entryFor(names) {
        for (const n of names) {
            const e = DesktopEntries.byId(String(n).replace(/\.desktop$/, ""));
            if (e)
                return e;
        }
        const wanted = names.map(n => String(n).toLowerCase());
        return apps.find(a => wanted.includes(String(a.name).toLowerCase())) || null;
    }
    // the Settings page for a system sender, "" if it's not one
    function _systemPage(names) {
        const map = Config.notifications.open.systemApps || {};
        for (const n of names) {
            const page = map[_norm(n)];
            if (page)
                return page;
        }
        return "";
    }
    // the window to bring up, from niri's list: the sender's process (or a parent's), else the app's
    function _senderWindow(windows, pids, names, entry) {
        for (const pid of pids) {
            const w = windows.find(w => w.pid === pid);
            if (w)
                return w;
        }
        const keys = new Set();
        const add = v => {
            if (v) {
                keys.add(_norm(v));
                keys.add(_norm(_lastPart(v)));
            }
        };
        names.forEach(add);
        if (entry) {
            add(entry.id);
            add(entry.startupClass);
            add(entry.name);
        }
        keys.delete("");
        const same = windows.filter(w => keys.has(_norm(w.app_id)) || keys.has(_norm(_lastPart(w.app_id))));
        const t = w => w.focus_timestamp ? w.focus_timestamp.secs * 1e9 + w.focus_timestamp.nanos : 0;
        same.sort((a, b) => t(b) - t(a));
        return same[0] || null;
    }
    function openNotification(n) {
        if (!n)
            return;
        const o = Config.notifications.open;
        const hasDefault = (n.actions || []).some(a => a.identifier === "default");
        const names = [n.desktopEntry, n.appName].filter(x => !!x);
        const pids = (_senders[n.id] || []).slice();
        if (hasDefault)
            notificationAction(n, "default");
        const page = o.systemSettings && !hasDefault ? _systemPage(names) : "";
        if (page !== "") {
            openSettings(page, "");
            return;
        }
        if (!o.focusApp)
            return;
        const entry = _entryFor(names);
        const proc = windowsProc.createObject(root, {
            "command": o.windowsCommand,
            "done": out => {
                let windows = [];
                try {
                    windows = JSON.parse(out);
                } catch (e) {
                    return;
                }
                const w = root._senderWindow(windows, pids, names, entry);
                if (w)
                    root.run(o.focusCommand.map(a => a.replace("{id}", String(w.id))));
                else if (!hasDefault && o.launchApp && entry)
                    entry.execute();
            }
        });
        proc.running = true;
    }
    Component {
        id: windowsProc
        Process {
            id: wp
            property var done
            stdout: StdioCollector {
                onStreamFinished: {
                    wp.done(text);
                    wp.destroy();
                }
            }
        }
    }

    // ==========================================
    // SHUTDOWN (the island's goodbye)
    // ==========================================

    // shuttingDown: logind announced a power off or a restart (PrepareForShutdown), from anywhere (the
    // launcher, systemctl, the power button). While goodbye.enabled, Sys holds a logind "delay" lock, so the
    // system waits for releaseShutdown() before going down (at most logind's InhibitDelayMaxSec, 5 s by
    // default; goodbye.maxWait releases it earlier in any case). Cancelled shutdowns take the lock again.
    readonly property bool shuttingDown: _shuttingDown
    property bool _shuttingDown: false
    property bool _shutdownReleased: false
    // the lock is held while this is true (set imperatively: a Process stops being `running` by itself
    // when it exits, which would break a binding)
    readonly property bool _holdShutdown: Config.goodbye.enabled && !_shutdownReleased
    on_HoldShutdownChanged: shutdownLock.running = _holdShutdown
    function releaseShutdown() {
        shutdownSafety.stop();
        _shutdownReleased = true;
    }
    // the lock lives as long as this process: `cat` keeps it open and ends when its input closes, so
    // the lock goes away with the shell too (a crashed shell never delays a shutdown)
    Process {
        id: shutdownLock
        command: ["systemd-inhibit", "--what=shutdown", "--mode=delay", "--who=Quickshell", "--why=Saying goodbye in the island", "cat"]
        stdinEnabled: true
        Component.onCompleted: running = root._holdShutdown
        onExited: {
            if (root._holdShutdown)
                shutdownLockRestart.start();
        }
    }
    Timer {
        id: shutdownLockRestart
        interval: Config.system.restartDelay
        onTriggered: shutdownLock.running = root._holdShutdown
    }
    // logind's signals, as they come (one line each):
    //   /org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (true,)
    Process {
        id: shutdownEvents
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/\.PrepareForShutdown \((true|false)\b/);
                if (m)
                    root._shutdownAnnounced(m[1] === "true");
            }
        }
        onExited: shutdownEventsRestart.start()
    }
    Timer {
        id: shutdownEventsRestart
        interval: Config.system.restartDelay
        onTriggered: shutdownEvents.running = true
    }
    function _shutdownAnnounced(on) {
        _shuttingDown = on;
        if (on) {
            shutdownSafety.restart();
        } else {
            // cancelled: hold the lock again for next time
            shutdownSafety.stop();
            _shutdownReleased = false;
        }
    }
    // never keep the system waiting longer than goodbye.maxWait, whatever the island is doing
    Timer {
        id: shutdownSafety
        interval: Config.goodbye.maxWait
        onTriggered: root.releaseShutdown()
    }
}
