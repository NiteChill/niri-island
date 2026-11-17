pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import "../services"
import "../island"
import "../widgets"

// Spotlight-style search: type to find island panels, actions (trash, reboot, power off...) and apps
// (Enter opens/runs/launches) or a calculation (Enter copies the result). Actions come from
// config search.actions; ones marked "confirm" need Enter twice. Panels are every mode with a `launcher` entry, so new ones show up automatically.
// Kinds of results with a mode each (search.<kind>.mode): calculator (calc), files, settings (the
// desktop Settings app's own list, Sys.settingsIndex; Enter opens the app on that page) and the web.
// "always" = mixed into the results (files and settings: their best few, search.<kind>.mixedResults),
// "prefix" = only after one of its prefixes, "off" = never. Typing a prefix (search.<kind>.prefixes: f:,
// s:, =, w:...) at the start turns into that kind's pill and searches only it, whatever its mode;
// Backspace on an empty field removes the pill. Files: Enter opens, Shift+Enter shows in the file manager.
// Pins: with nothing typed, the launcher shows the pinned panels, apps and commands (Sys.pins) as tiles:
// arrows move between them, Enter opens, Ctrl+Left / Right moves the tile (it slides with the highlight),
// dragging a tile reorders them (the others slide aside). Ctrl+P (search.pins.key) or a right-click pins /
// unpins the selected result or tile; pinned results show a pin.
// Opened from the keyboard: `qs ipc call island toggle search`. Grows with the number of results.
// Look (Raycast-style launcher): a magnifier in front of the field, a hairline under it, results grouped
// under small grey section titles (Calculator, Island, Commands, Applications; groups ordered by their
// best match), icons in rounded tiles, the result's kind in grey at the right, and on the selected row
// what Enter does ("Open ↵").
// Up to search.maxResults results; past search.visibleRows rows the list scrolls (wheel, drag, or Up/Down
// which keep the selection in view), edges fading into the island. Same list as the Wi-Fi panel: a
// ListView (only the rows on screen exist) whose model only carries each row's group, updated in place;
// rows read their result from `results` by index.
IslandMode {
    id: mode

    readonly property var layout: Config.search
    // keyboard-driven: stays open until Escape / an action, even when the mouse leaves
    autoClose: false
    keyTarget: input

    // ---- results ----
    // the kinds with a mode and prefixes; scope "" = everything, else only that kind (shown as a pill)
    readonly property var kinds: ["calc", "files", "settings", "web"]
    function kindMode(k) {
        return Config.search[k].mode;
    }
    // shown with nothing chosen: the kinds in "always" mode
    function mixed(k) {
        return scope === "" && kindMode(k) === "always";
    }
    property string scope: ""
    // the pill keeps the last kind's look while it fades out
    property string pillKind: "files"
    onScopeChanged: {
        if (scope !== "")
            pillKind = scope;
        if (scope === "files")
            Sys.refreshFiles();
    }
    // the longest prefix of a kind that isn't off the text starts with, e.g. "files:" before "f:":
    // { kind, prefix }, or null
    function prefixOf(text) {
        const t = text.toLowerCase();
        let best = null;
        for (const k of kinds) {
            if (kindMode(k) === "off")
                continue;
            for (const p of Config.search[k].prefixes)
                if ((!best || p.length > best.prefix.length) && t.startsWith(p.toLowerCase()))
                    best = { "kind": k, "prefix": p };
        }
        return best;
    }

    property string query: ""
    property int selected: 0
    // title of the action waiting for a second Enter (confirm: true), "" = none
    property string pendingConfirm: ""
    onQueryChanged: pendingConfirm = ""
    onSelectedChanged: pendingConfirm = ""

    // a calculation if the query is only numbers/operators, e.g. "12*(3+4)" or "2^10"
    readonly property var calc: {
        if (scope !== "calc" && !mixed("calc"))
            return null;
        const q = query.trim();
        if (!/^[\d\s+\-*/().%^,]+$/.test(q) || !/\d/.test(q) || !/[+\-*/%^]/.test(q))
            return null;
        try {
            // safe: the charset above can only express arithmetic
            const v = Function('"use strict"; return (' + q.replace(/\^/g, "**").replace(/,/g, ".") + ")")();
            if (typeof v !== "number" || !isFinite(v))
                return null;
            return {
                "calc": true,
                "kind": "calc",
                "name": String(Math.round(v * 1e10) / 1e10),
                "subtitle": ""
            };
        } catch (e) {
            return null;
        }
    }

    // the web: searching for what's typed, or opening it if it's an address ("rust-lang.org"); always the
    // last result, so it's the one Enter picks when nothing else matches
    readonly property var web: {
        const cfg = layout.web;
        const q = query.trim();
        if (q.length === 0 || (scope !== "web" && !mixed("web")))
            return null;
        const address = cfg.openAddresses && /^(https?:\/\/)?[^\s\/.]+(\.[^\s\/.]+)*\.[a-z]{2,}(:\d+)?(\/\S*)?$/i.test(q);
        return {
            "kind": address ? "link" : "web",
            "url": address ? (/^https?:\/\//i.test(q) ? q : "https://" + q) : cfg.url.replace("{query}", encodeURIComponent(q)),
            "name": q,
            "subtitle": address ? "" : cfg.engine,
            "icon": cfg.icon
        };
    }

    function score(app, q) {
        const name = (app.name || "").toLowerCase();
        if (name.startsWith(q))
            return 4;
        if (name.split(/[\s\-_]/).some(w => w.startsWith(q)))
            return 3;
        if (name.includes(q))
            return 2;
        const extra = ((app.genericName || "") + " " + (app.keywords || []).join(" ") + " " + (app.comment || "")).toLowerCase();
        return extra.includes(q) ? 1 : 0;
    }

    // file search: name starts with the query > a word in the name does > name contains it > path does;
    // then folders first, shallower first, then by name
    function fileResults(q) {
        const cfg = Config.search.files;
        const scored = [];
        for (const f of Sys.files) {
            const name = f.name.toLowerCase();
            let s = 0;
            if (name.startsWith(q))
                s = 4;
            else if (name.split(/[\s\-_.]/).some(w => w.startsWith(q)))
                s = 3;
            else if (name.includes(q))
                s = 2;
            else if (Sys.prettyPath(f.path).toLowerCase().includes(q))
                s = 1;
            if (s > 0)
                scored.push({ "s": s, "f": f });
        }
        scored.sort((a, b) => b.s - a.s || b.f.dir - a.f.dir || a.f.depth - b.f.depth || a.f.name.localeCompare(b.f.name));
        return scored.slice(0, layout.maxResults).map(r => ({
                    "s": r.s,
                    "file": r.f,
                    "kind": r.f.dir ? "folder" : "file",
                    "name": r.f.name,
                    "subtitle": Sys.prettyPath(r.f.parent),
                    "icon": r.f.dir ? cfg.folderIcon : cfg.imageExtensions.includes(r.f.ext) ? cfg.imageIcon : cfg.fileIcon
                }));
    }

    // settings: by their name, then by their page's; a page itself is listed as a setting too
    function settingResults(q) {
        const scored = [];
        for (const e of Sys.settingsIndex) {
            const s = score({ "name": e.title, "genericName": e.pageLabel, "keywords": [], "comment": "" }, q);
            if (s > 0)
                scored.push({ "s": s, "e": e });
        }
        scored.sort((a, b) => b.s - a.s || a.e.title.localeCompare(b.e.title));
        return scored.slice(0, layout.maxResults).map(r => ({
                    "s": r.s,
                    "setting": r.e,
                    "kind": "setting",
                    "name": r.e.title,
                    "subtitle": r.e.title === r.e.pageLabel ? "" : r.e.pageLabel,
                    // the page's own icon from the Settings app (its index gives the file), else the gear
                    "icon": Config.search.settings.pageIcons && r.e.iconFile ? r.e.iconFile : Config.search.settings.icon,
                    "flip": Config.search.settings.pageIcons && !!r.e.flip
                }));
    }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (q.length === 0)
            return [];
        if (scope === "files")
            return fileResults(q);
        if (scope === "settings")
            return settingResults(q);
        if (scope === "calc")
            return calc ? [calc] : [];
        if (scope === "web")
            return web ? [web] : [];
        let out = [];
        const apps = Sys.apps;
        const scored = [];
        // island panels first on equal score (+0.5)
        const modes = island ? island.modeList : [];
        for (let i = 0; i < modes.length; i++) {
            const l = modes[i].launcher;
            if (!l || modes[i] === mode)
                continue;
            const s = score({ "name": l.title, "genericName": l.subtitle, "keywords": (l.keywords || "").split(/\s+/), "comment": "" }, q);
            if (s > 0)
                scored.push({ "s": s + 0.5, "panel": modes[i] });
        }
        for (let i = 0; i < apps.length; i++) {
            const s = score(apps[i], q);
            if (s > 0)
                scored.push({ "s": s, "app": apps[i] });
        }
        // actions from config (+0.25 on equal score: after panels, before apps)
        const actions = layout.actions || [];
        for (let i = 0; i < actions.length; i++) {
            const a = actions[i];
            const s = score({ "name": a.title, "genericName": a.subtitle, "keywords": (a.keywords || "").split(/\s+/), "comment": "" }, q);
            if (s > 0)
                scored.push({ "s": s + 0.25, "action": a });
        }
        // files and settings shown always: their best few, just after apps on an equal score
        if (mixed("files"))
            // by their name only: a match deep in a path is too vague among everything else
            for (const r of fileResults(q).filter(r => r.s >= 2).slice(0, Config.search.files.mixedResults))
                scored.push({ "s": r.s - 0.1, "item": r });
        if (mixed("settings"))
            for (const r of settingResults(q).slice(0, Config.search.settings.mixedResults))
                scored.push({ "s": r.s - 0.05, "item": r });
        const label = r => r.item ? r.item.name : r.panel ? r.panel.launcher.title : r.action ? r.action.title : r.app.name;
        scored.sort((a, b) => b.s - a.s || label(a).localeCompare(label(b)));
        for (let i = 0; i < scored.length && out.length < layout.maxResults - (calc ? 1 : 0) - (web ? 1 : 0); i++) {
            const r = scored[i];
            if (r.item) {
                out.push(r.item);
                continue;
            }
            out.push(r.panel ? {
                "s": r.s,
                "kind": "panel",
                "panel": r.panel,
                "name": r.panel.launcher.title,
                "subtitle": r.panel.launcher.subtitle || "",
                "icon": r.panel.launcher.icon
            } : r.action ? {
                "s": r.s,
                "kind": "action",
                "action": r.action,
                "name": r.action.title,
                "subtitle": r.action.subtitle || "",
                "icon": r.action.icon
            } : {
                "s": r.s,
                "kind": "app",
                "app": r.app,
                "name": r.app.name,
                "subtitle": r.app.genericName || r.app.comment || ""
            });
        }
        // group by kind, groups in order of their best match (out is sorted, so first seen = best);
        // a calculation always comes first
        const group = r => r.kind === "folder" ? "file" : r.kind;
        const order = [];
        for (const r of out) {
            if (!order.includes(group(r)))
                order.push(group(r));
        }
        const grouped = calc ? [calc] : [];
        for (const k of order)
            for (const r of out)
                if (group(r) === k)
                    grouped.push(r);
        if (web)
            grouped.push(web);
        return grouped;
    }

    // ---- pins: Sys.pins resolved to launcher entries (an app or panel that's gone is skipped) ----
    function pinKindOf(r) {
        return r.panel ? "panel" : r.app ? "app" : r.action ? "action" : "";
    }
    function pinIdOf(r) {
        return r.panel ? r.panel.name : r.app ? r.app.id : r.action ? r.action.title : "";
    }
    readonly property var pinned: {
        const out = [];
        const modes = island ? island.modeList : [];
        const actions = layout.actions || [];
        for (const p of Sys.pins) {
            if (p.kind === "panel") {
                const m = modes.find(x => x.name === p.id && x.launcher);
                if (m)
                    out.push({ "kind": "panel", "panel": m, "name": m.launcher.title, "icon": m.launcher.icon });
            } else if (p.kind === "app") {
                const a = Sys.apps.find(x => x.id === p.id);
                if (a)
                    out.push({ "kind": "app", "app": a, "name": a.name });
            } else if (p.kind === "action") {
                const a = actions.find(x => x.title === p.id);
                if (a)
                    out.push({ "kind": "action", "action": a, "name": a.title, "icon": a.icon });
            }
        }
        return out;
    }
    // nothing typed (and no Files pill): the pins show instead of results
    readonly property bool showPins: query.trim() === "" && scope === "" && pinned.length > 0
    property int pinSelected: 0
    onPinSelectedChanged: pendingConfirm = ""
    readonly property real contentWidth: implicitWidth - 2 * layout.padding
    readonly property real pinTileWidth: contentWidth / layout.pins.columns
    readonly property int pinRows: Math.ceil(pinned.length / layout.pins.columns)
    readonly property real pinsHeight: pinRows * layout.pins.tileHeight + Math.max(0, pinRows - 1) * layout.pins.rowGap
    function slotX(i) {
        return (i % layout.pins.columns) * pinTileWidth;
    }
    function slotY(i) {
        return Math.floor(i / layout.pins.columns) * (layout.pins.tileHeight + layout.pins.rowGap);
    }
    // the slot under a point of the grid (dragging)
    function slotAt(x, y) {
        const col = Math.max(0, Math.min(layout.pins.columns - 1, Math.floor(x / pinTileWidth)));
        const row = Math.max(0, Math.min(pinRows - 1, Math.floor(y / (layout.pins.tileHeight + layout.pins.rowGap))));
        return Math.min(pinned.length - 1, row * layout.pins.columns + col);
    }
    // the tiles' model: one entry per pin, by key, moved in place when the order changes (so a tile keeps its
    // delegate and slides to its new slot instead of being rebuilt there)
    ListModel {
        id: pinModel
    }
    function pinKey(r) {
        return pinKindOf(r) + ":" + pinIdOf(r);
    }
    function syncPins() {
        const keys = pinned.map(pinKey);
        for (let i = 0; i < keys.length; i++) {
            let j = -1;
            for (let k = i; k < pinModel.count; k++)
                if (pinModel.get(k).key === keys[i]) {
                    j = k;
                    break;
                }
            if (j < 0)
                pinModel.insert(i, {
                    "key": keys[i]
                });
            else if (j !== i)
                pinModel.move(j, i, 1);
        }
        if (pinModel.count > keys.length)
            pinModel.remove(keys.length, pinModel.count - keys.length);
    }
    function pinMove(dir) {
        pinSelected = Math.max(0, Math.min(pinned.length - 1, pinSelected + dir));
    }
    // pin / unpin: the selected tile, or the selected result (files and calculations can't be pinned)
    function togglePinSelected() {
        const r = showPins ? pinned[pinSelected] : results[selected];
        if (!r || pinKindOf(r) === "")
            return;
        Sys.togglePin(pinKindOf(r), pinIdOf(r));
        if (showPins)
            pinSelected = Math.min(pinSelected, Math.max(0, pinned.length - 1));
    }
    function movePinSelected(step) {
        const r = pinned[pinSelected];
        if (!r)
            return;
        const target = Math.max(0, Math.min(pinned.length - 1, pinSelected + step));
        Sys.movePin(pinKindOf(r), pinIdOf(r), target - pinSelected);
        pinSelected = target;
    }
    onPinnedChanged: {
        syncPins();
        refit();
    }

    // where each row goes: a section title before each group (not in file search: the pill says it)
    readonly property bool showHeaders: scope === ""
    readonly property var placed: {
        const rows = [], headers = [], sections = [];
        let y = 0, prev = "";
        for (let i = 0; i < results.length; i++) {
            const k = results[i].kind;
            const section = k === "folder" ? "file" : k;
            if (showHeaders && section !== prev) {
                headers.push({
                    "title": layout.sections[section],
                    "y": y
                });
                y += layout.headerHeight;
            }
            prev = section;
            sections.push(showHeaders ? section : "");
            rows.push(y);
            y += layout.rowHeight;
        }
        return {
            "rows": rows,
            "headers": headers,
            "sections": sections,
            "height": y
        };
    }
    // what's shown: all of it, up to visibleRows rows (plus a group title), then it scrolls
    function viewHeightFor(listHeight) {
        return Math.min(listHeight, layout.visibleRows * layout.rowHeight + layout.headerHeight);
    }
    readonly property real viewHeight: viewHeightFor(placed.height)

    // the ListView's model: one row per result, carrying only its group (for the group titles)
    ListModel {
        id: rows
    }
    function syncRows() {
        const sections = placed.sections;
        for (let i = 0; i < sections.length; i++) {
            if (i >= rows.count)
                rows.append({
                    "section": sections[i]
                });
            else if (rows.get(i).section !== sections[i])
                rows.setProperty(i, "section", sections[i]);
        }
        if (rows.count > sections.length)
            rows.remove(sections.length, rows.count - sections.length);
    }

    // keyboard: move the selection, scrolling just enough to keep it in view (with its group title if
    // it's the first of its group). Positions come from `placed` (exact; ListView only estimates rows it
    // hasn't created yet).
    function step(dir) {
        selected = Math.max(0, Math.min(results.length - 1, selected + dir));
        revealRow(selected);
    }
    function revealRow(i) {
        const rowTop = placed.rows[i];
        if (rowTop === undefined)
            return;
        const titled = placed.headers.some(h => h.y + layout.headerHeight === rowTop);
        const top = rowTop - (titled ? layout.headerHeight : 0);
        const bottom = rowTop + layout.rowHeight;
        let y = scrollAnim.running ? scrollAnim.to : view.contentY;
        if (top < y)
            y = top;
        else if (bottom > y + view.height)
            y = bottom - view.height;
        y = Math.max(0, Math.min(y, placed.height - view.height));
        if (y === view.contentY && !scrollAnim.running)
            return;
        scrollAnim.stop();
        scrollAnim.to = y;
        scrollAnim.start();
    }
    // list height the island is sized for: grows right away, shrinks only after typing pauses,
    // so the island doesn't pump up and down on every keystroke
    property real shownHeight: 0
    onPlacedChanged: {
        syncRows();
        selected = 0;
        scrollAnim.stop();
        view.contentY = 0;   // new results start at the top
        refit();
    }
    // the height wanted below the field: the pins' grid when nothing is typed, else the results. Worked
    // out from the sources (not the showPins / viewHeight bindings, which may not have caught up yet inside
    // the handler that calls this: Qt doesn't order binding updates)
    function wantedHeight() {
        const pins = query.trim() === "" && scope === "" && pinned.length > 0;
        return pins ? pinsHeight : viewHeightFor(placed.height);
    }
    function refit() {
        const target = wantedHeight();
        if (target >= shownHeight) {
            shrinkDebounce.stop();
            shownHeight = target;
        } else {
            shrinkDebounce.restart();
        }
    }
    Timer {
        id: shrinkDebounce
        interval: mode.layout.shrinkDebounce
        onTriggered: mode.shownHeight = mode.wantedHeight()
    }

    // fromKey: triggered by Enter, so hold the keyboard until it's released. Only once we know the mode
    // closes/switches: holding moves focus away from the field, which killed the launcher if it stayed open.
    // reveal: Shift+Enter on a file shows it in the file manager instead of opening it
    function activate(i, fromKey, reveal) {
        activateResult(results[i], fromKey, reveal);
    }
    function activateResult(r, fromKey, reveal) {
        if (!r)
            return;
        if (r.action && r.action.confirm && pendingConfirm !== r.action.title) {
            pendingConfirm = r.action.title;
            return;
        }
        if (fromKey)
            mode.holdKeyboard();
        if (r.panel) {
            mode.requestState(r.panel.name);
            return;
        }
        if (r.setting) {
            Sys.openSettings(r.setting.page, r.setting.title === r.setting.pageLabel ? "" : r.setting.title);
        } else if (r.file) {
            if (reveal)
                Sys.revealFile(r.file.path);
            else
                Sys.openFile(r.file.path);
        } else if (r.action)
            Sys.run(r.action.command);
        else if (r.calc)
            Sys.copyText(r.name);
        else if (r.url)
            Sys.openUrl(r.url);
        else
            r.app.execute();
        mode.requestState("idle");
    }

    // ---- size: just the field when empty, grows one row per result ----
    implicitWidth: layout.width
    implicitHeight: 2 * layout.padding + layout.inputHeight + (shownHeight > 0 ? 2 * layout.gap + shownHeight : 0)

    // ---- reset on open (keyboard focus goes to `input`, see keyTarget) ----
    onActiveChanged: {
        if (active) {
            scope = "";
            input.text = "";
            // the lists the results come from, fresh for this search (one short process each)
            Sys.refreshSettings();
            if (kindMode("files") === "always")
                Sys.refreshFiles();
            selected = 0;
            pinSelected = 0;
            pinHover.lastScene = Qt.point(-1, -1);
            shrinkDebounce.stop();
            shownHeight = 0;
            refit();   // the pins, if any (nothing typed)
        }
    }

    Item {
        id: content
        x: mode.layout.padding
        y: mode.layout.padding
        width: mode.implicitWidth - 2 * mode.layout.padding
        height: mode.implicitHeight - 2 * mode.layout.padding

        // ---- search field ----
        // pill for the current scope ("Files"), in front of the text. Appears: the text slides aside
        // (room spring), then the pill pops in (scale spring + fade). Removed: the reverse.
        property real pillRoom: mode.scope !== "" ? pill.width + Config.search.pill.gap : 0
        Behavior on pillRoom {
            SpringAnimation {
                spring: Config.spring(Config.search.pill.room).spring
                damping: Config.spring(Config.search.pill.room).damping
                epsilon: 0.25
            }
        }
        Icon {
            id: magnifier
            anchors.left: parent.left
            anchors.verticalCenter: input.verticalCenter
            width: mode.layout.searchIconSize
            height: mode.layout.searchIconSize
            name: mode.layout.searchIcon
            color: Config.colors.secondary
        }
        Item {
            id: pill
            anchors.left: magnifier.right
            anchors.leftMargin: mode.layout.searchIconGap
            anchors.verticalCenter: input.verticalCenter
            width: pillRow.implicitWidth + 2 * Config.search.pill.padding
            height: Config.search.pill.height
            transformOrigin: Item.Left
            opacity: mode.scope !== "" ? 1 : 0
            scale: mode.scope !== "" ? 1 : Config.search.pill.pop.from
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Config.search.pill.fade
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                SpringAnimation {
                    spring: Config.spring(Config.search.pill.pop).spring
                    damping: Config.spring(Config.search.pill.pop).damping
                    epsilon: 0.001
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Config.corner("pill", height)
                color: Config.colors.text
                opacity: Config.search.pill.opacity
            }
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Config.search.pill.spacing
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Config.search.pill.iconSize
                    height: Config.search.pill.iconSize
                    name: Config.search[mode.pillKind].pillIcon
                    color: Config.colors.text
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Config.search[mode.pillKind].label
                    font.pixelSize: Config.search.pill.textSize
                }
            }
        }

        TextInput {
            id: input
            anchors.left: magnifier.right
            anchors.leftMargin: mode.layout.searchIconGap + content.pillRoom
            anchors.right: parent.right
            anchors.top: parent.top
            height: mode.layout.inputHeight
            verticalAlignment: TextInput.AlignVCenter
            color: Config.font.color
            selectionColor: Qt.rgba(1, 1, 1, mode.layout.textSelectionOpacity)
            font.family: Config.font.family
            font.variableAxes: ({
                    "ROND": Config.font.roundness,
                    "wght": Config.font.weight
                })
            font.weight: Config.font.weight
            font.pixelSize: mode.layout.inputSize
            clip: true
            onTextChanged: {
                // a prefix typed (or pasted) at the start becomes the pill
                const p = mode.scope === "" ? mode.prefixOf(text) : null;
                if (p) {
                    mode.scope = p.kind;
                    text = text.slice(p.prefix.length).replace(/^\s+/, "");   // re-enters here with the rest
                    return;
                }
                mode.query = text;
            }
            // Backspace at the very start removes the pill; Ctrl+P pins / unpins; on the pins (nothing typed)
            // Left / Right move between tiles, Ctrl+Left / Right move the tile itself
            Keys.onPressed: event => {
                const ctrl = !!(event.modifiers & Qt.ControlModifier);
                if (event.key === Qt.Key_Backspace && mode.scope !== "" && cursorPosition === 0 && selectedText === "") {
                    mode.scope = "";
                    event.accepted = true;
                } else if (ctrl && event.key === mode.layout.pins.key.toUpperCase().charCodeAt(0)) {
                    // (with Ctrl held the event's text is a control character: compare the key; Qt's letter
                    // keys are their upper-case character codes)
                    mode.togglePinSelected();
                    event.accepted = true;
                } else if (mode.showPins && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                    const dir = event.key === Qt.Key_Left ? -1 : 1;
                    if (ctrl)
                        mode.movePinSelected(dir);
                    else
                        mode.pinMove(dir);
                    event.accepted = true;
                }
            }

            Keys.onUpPressed: mode.showPins ? mode.pinMove(-mode.layout.pins.columns) : mode.step(-1)
            Keys.onDownPressed: mode.showPins ? mode.pinMove(mode.layout.pins.columns) : mode.step(1)
            Keys.onEscapePressed: mode.close()
            Keys.onReturnPressed: event => mode.showPins ? mode.activateResult(mode.pinned[mode.pinSelected], true, false) : mode.activate(mode.selected, true, !!(event.modifiers & Qt.ShiftModifier))
            Keys.onEnterPressed: event => mode.showPins ? mode.activateResult(mode.pinned[mode.pinSelected], true, false) : mode.activate(mode.selected, true, !!(event.modifiers & Qt.ShiftModifier))

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: mode.scope !== "" ? Config.search[mode.scope].placeholder : mode.layout.placeholder
                color: Config.colors.secondary
                font.pixelSize: mode.layout.inputSize
            }
        }

        // hairline between the field and the results
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: input.bottom
            anchors.topMargin: mode.layout.gap
            height: mode.layout.dividerWidth
            color: Config.colors.text
            opacity: mode.results.length > 0 || mode.showPins ? mode.layout.dividerOpacity : 0
        }

        // ---- pins: tiles, nothing typed ----
        Item {
            id: pinGrid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: input.bottom
            anchors.topMargin: 2 * mode.layout.gap
            height: mode.pinsHeight
            visible: mode.showPins

            // the selected tile's highlight: springs from tile to tile (the lists' look and spring)
            Rectangle {
                id: pinHighlight
                readonly property int col: mode.pinSelected % mode.layout.pins.columns
                readonly property int row: Math.floor(mode.pinSelected / mode.layout.pins.columns)
                x: col * mode.pinTileWidth
                y: row * (mode.layout.pins.tileHeight + mode.layout.pins.rowGap)
                width: mode.pinTileWidth
                height: mode.layout.pins.tileHeight
                radius: Config.corner("row", height)
                color: Config.colors.text
                opacity: Config.panel.list.selectedOpacity
                visible: mode.pinned.length > 0
                Behavior on x {
                    enabled: pinGrid.visible
                    SpringAnimation {
                        spring: Config.spring(Config.panel.list.highlight).spring
                        damping: Config.spring(Config.panel.list.highlight).damping
                        epsilon: 0.25
                    }
                }
                Behavior on y {
                    enabled: pinGrid.visible
                    SpringAnimation {
                        spring: Config.spring(Config.panel.list.highlight).spring
                        damping: Config.spring(Config.panel.list.highlight).damping
                        epsilon: 0.25
                    }
                }
            }
            // The pointer selects the tile under it only when it really moves. Read from the pointer's own
            // scene position: mapping a tile's local position to the scene changes by fractions of a pixel
            // every frame while the island opens and scales the content, which looked like a move and
            // picked the tile under a still pointer. The first position seen after opening only records
            // where the pointer is.
            HoverHandler {
                id: pinHover
                property point lastScene: Qt.point(-1, -1)
                onPointChanged: {
                    const p = point.scenePosition;
                    if (!hovered || (p.x === lastScene.x && p.y === lastScene.y))
                        return;
                    const first = lastScene.x < 0;
                    lastScene = p;
                    if (first)
                        return;
                    const g = pinGrid.mapFromItem(null, p.x, p.y);
                    const step = mode.layout.pins.tileHeight + mode.layout.pins.rowGap;
                    if (g.y - Math.floor(g.y / step) * step > mode.layout.pins.tileHeight)
                        return;   // in the gap between two rows
                    mode.pinSelected = mode.slotAt(g.x, g.y);
                }
            }
            Repeater {
                model: pinModel
                Item {
                    id: tile
                    required property int index
                    required property string key
                    // the pin this tile shows (the model only carries its key)
                    readonly property var modelData: mode.pinned[index] || ({})
                    readonly property bool current: index === mode.pinSelected
                    readonly property bool confirming: !!modelData.action && mode.pendingConfirm === modelData.name
                    width: mode.pinTileWidth
                    height: mode.layout.pins.tileHeight

                    // its slot, springing there when the order changes (with the highlight: same spring); while
                    // dragged it follows the pointer instead
                    property bool dragging: false
                    property real dragX: 0
                    property real dragY: 0
                    x: dragging ? dragX : mode.slotX(index)
                    y: dragging ? dragY : mode.slotY(index)
                    // the dragged tile above all, the selected one (moving with Ctrl+arrows) above the one it swaps with
                    z: dragging ? 3 : current ? 2 : 1
                    scale: dragging ? mode.layout.pins.dragScale : 1
                    Behavior on x {
                        enabled: !tile.dragging && pinGrid.visible
                        SpringAnimation {
                            spring: Config.spring(Config.panel.list.highlight).spring
                            damping: Config.spring(Config.panel.list.highlight).damping
                            epsilon: 0.25
                        }
                    }
                    Behavior on y {
                        enabled: !tile.dragging && pinGrid.visible
                        SpringAnimation {
                            spring: Config.spring(Config.panel.list.highlight).spring
                            damping: Config.spring(Config.panel.list.highlight).damping
                            epsilon: 0.25
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Config.motion.pressDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    // the icon: an app's own, or a glyph on a soft rounded tile (panels in the accent)
                    Item {
                        id: tileIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: mode.layout.pins.padding
                        width: mode.layout.pins.iconSize
                        height: mode.layout.pins.iconSize
                        readonly property color tint: tile.modelData.panel ? Config.colors.accent : Config.colors.text
                        Rectangle {
                            anchors.fill: parent
                            visible: !tile.modelData.app
                            radius: Config.corner("tile", height)
                            color: Qt.alpha(tileIcon.tint, Config.activity.badgeOpacity)
                        }
                        Image {
                            anchors.fill: parent
                            visible: !!tile.modelData.app
                            source: tile.modelData.app ? Quickshell.iconPath(tile.modelData.app.icon, "application-x-executable") : ""
                            sourceSize.width: width * 2
                            sourceSize.height: height * 2
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: !tile.modelData.app
                            width: parent.width * mode.layout.panelIconScale
                            height: width
                            name: tile.modelData.icon || ""
                            color: tileIcon.tint
                        }
                    }
                    StyledText {
                        anchors.top: tileIcon.bottom
                        anchors.topMargin: mode.layout.pins.nameGap
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 2 * mode.layout.pins.padding
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: mode.layout.pins.nameSize
                        color: tile.confirming ? Config.colors.danger : tile.current ? Config.colors.text : Config.colors.secondary
                        text: tile.confirming ? mode.layout.confirmText : tile.modelData.name || ""
                    }

                    // pointer (hover selection: pinHover, on the grid); a click opens it, a right-click unpins it; pressing and
                    // dragging past search.pins.dragThreshold carries it, the others sliding aside as it passes
                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        property point pressGrid: Qt.point(0, 0)
                        property point grab: Qt.point(0, 0)
                        onPositionChanged: mouse => {
                            const g = mapToItem(pinGrid, mouse.x, mouse.y);
                            if (pressed && mouse.buttons & Qt.LeftButton) {
                                if (!tile.dragging && Math.hypot(g.x - pressGrid.x, g.y - pressGrid.y) > mode.layout.pins.dragThreshold) {
                                    tile.dragX = tile.x;
                                    tile.dragY = tile.y;
                                    grab = Qt.point(g.x - tile.x, g.y - tile.y);
                                    tile.dragging = true;
                                }
                                if (tile.dragging) {
                                    tile.dragX = g.x - grab.x;
                                    tile.dragY = g.y - grab.y;
                                    const target = mode.slotAt(g.x, g.y);
                                    mode.pinSelected = target;
                                    if (target !== tile.index)
                                        Sys.movePin(mode.pinKindOf(tile.modelData), mode.pinIdOf(tile.modelData), target - tile.index);
                                }
                                return;
                            }
                        }
                        onPressed: mouse => pressGrid = mapToItem(pinGrid, mouse.x, mouse.y)
                        onReleased: mouse => {
                            if (tile.dragging) {
                                // drop: back on the slot grid (the springs carry it into its place)
                                tile.dragging = false;
                                return;
                            }
                            if (mouse.button === Qt.RightButton) {
                                mode.pinSelected = tile.index;
                                mode.togglePinSelected();
                            } else
                                mode.activateResult(tile.modelData, false, false);
                        }
                    }
                }
            }
        }

        // ---- results ----
        ListView {
            id: view
            // blurred island: faded through a mask instead of a band in the island color (ScrollFade)
            layer.enabled: edgeFade.masked
            layer.effect: edgeFade.effect
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: input.bottom
            anchors.topMargin: 2 * mode.layout.gap
            height: mode.viewHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: mode.layout.rowHeight * mode.layout.visibleRows
            model: rows

            NumberAnimation {
                id: scrollAnim
                target: view
                property: "contentY"
                duration: mode.layout.scrollDuration
                easing.type: Easing.OutCubic
            }

            // group titles (none in file search: the section is "" and its title takes no room)
            section.property: "section"
            section.delegate: Item {
                id: sectionItem
                required property string section
                width: view.width
                height: section === "" ? 0 : mode.layout.headerHeight
                StyledText {
                    visible: sectionItem.section !== ""
                    x: mode.layout.iconInset
                    height: mode.layout.headerHeight
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Config.activity.captionSize
                    color: Config.colors.secondary
                    text: mode.layout.sections[sectionItem.section] || ""
                }
            }

            // highlight that springs to the selected row: in the scrolling content, behind the rows.
            // `parent` is explicit: an Item declared inside a ListView stays a child of the view itself (it
            // didn't scroll and was clipped away once the list scrolled), unlike pointer handlers
            Rectangle {
                parent: view.contentItem
                z: -1
                width: view.width
                height: mode.layout.rowHeight
                radius: Config.corner("row", height)
                color: Config.colors.text
                // the same look and spring as every list highlight (panel.list.selectedOpacity / highlight)
                opacity: mode.results.length > 0 ? Config.panel.list.selectedOpacity : 0
                y: mode.placed.rows.length > 0 ? mode.placed.rows[Math.min(mode.selected, mode.placed.rows.length - 1)] : 0
                Behavior on y {
                    SpringAnimation {
                        spring: Config.spring(Config.panel.list.highlight).spring
                        damping: Config.spring(Config.panel.list.highlight).damping
                        epsilon: 0.25
                    }
                }
            }

            // The pointer selects the row under it only when it actually moves (typing changes the results
            // under a still pointer; selecting on plain hover made Enter open the row under the mouse instead
            // of the first result). Scrolling with the wheel / a drag does select the row that ends up under
            // the pointer; the keyboard's own scrolling doesn't.
            // A handler declared inside a ListView lands on its contentItem (point.position is in content
            // coordinates and moves with the scroll): work from the scene position, mapped to the view.
            HoverHandler {
                id: listHover
                property point lastScene: Qt.point(-1, -1)
                cursorShape: Qt.PointingHandCursor
                function selectUnderPointer() {
                    if (!hovered)
                        return;
                    const p = view.mapFromItem(null, lastScene.x, lastScene.y);
                    const i = view.indexAt(p.x, p.y + view.contentY);
                    if (i >= 0 && i !== mode.selected)
                        mode.selected = i;
                }
                onPointChanged: {
                    const p = point.scenePosition;
                    if (p.x === lastScene.x && p.y === lastScene.y)
                        return;   // the rows moved, not the mouse
                    lastScene = p;
                    selectUnderPointer();
                }
            }
            onContentYChanged: {
                if (!scrollAnim.running)
                    listHover.selectUnderPointer();
            }

            delegate: Item {
                id: row

                required property int index
                // the result this row shows (the model only carries the group)
                readonly property var modelData: mode.results[index] || ({})
                readonly property bool current: index === mode.selected
                readonly property bool confirming: !!modelData.action && mode.pendingConfirm === modelData.name

                width: view.width
                height: mode.layout.rowHeight

                // icon: app icons as they are; everything else a glyph on a soft rounded tile
                // (island panels, calculations and the web tinted with the accent)
                Item {
                    id: iconBox
                    x: mode.layout.iconInset
                    width: mode.layout.iconSize
                    height: mode.layout.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property color tint: row.modelData.panel || row.modelData.calc || row.modelData.url ? Config.colors.accent : Config.colors.text

                    Rectangle {
                        anchors.fill: parent
                        visible: !row.modelData.app
                        radius: Config.corner("tile", height)
                        color: Qt.alpha(iconBox.tint, Config.activity.badgeOpacity)
                    }
                    Image {
                        anchors.fill: parent
                        visible: !!row.modelData.app
                        source: row.modelData.app ? Quickshell.iconPath(row.modelData.app.icon, "application-x-executable") : ""
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    // island panel / action / file: monochrome icon from assets/icons.
                    // Only created when the row has one (app rows show their own image above)
                    Loader {
                        anchors.centerIn: parent
                        active: !!row.modelData.icon
                        sourceComponent: Icon {
                            id: glyph
                            width: iconBox.width * mode.layout.panelIconScale
                            height: width
                            color: iconBox.tint
                            // a settings page whose icon the Settings app draws upside down
                            rotation: row.modelData.flip ? 180 : 0
                            // when the row turns into an app, `active` and this may update in either order:
                            // keep the last icon until the Loader drops it (never an undefined name)
                            Binding on name {
                                when: !!row.modelData.icon
                                value: row.modelData.icon
                                restoreMode: Binding.RestoreNone
                            }
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: !!row.modelData.calc
                        text: "="
                        color: iconBox.tint
                        font.pixelSize: mode.layout.iconSize * mode.layout.calcSymbolScale
                    }
                }

                // name, then its subtitle in grey on the same line
                StyledText {
                    id: name
                    anchors.left: iconBox.right
                    anchors.leftMargin: mode.layout.rowPadding
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, trailing.x - x - mode.layout.rowPadding)
                    text: row.modelData.name || ""
                    // names keep their end ("report-v3.pdf"), like the Finder
                    elide: Text.ElideMiddle
                }
                StyledText {
                    anchors.left: name.right
                    anchors.leftMargin: mode.layout.subtitleGap
                    anchors.right: trailing.left
                    anchors.rightMargin: mode.layout.rowPadding
                    anchors.baseline: name.baseline
                    visible: width > 0
                    text: row.modelData.subtitle || ""
                    // a file's or folder's path keeps both ends (~/…/project); an app's description is a sentence
                    elide: row.modelData.kind === "file" || row.modelData.kind === "folder" ? Text.ElideMiddle : Text.ElideRight
                    color: Config.colors.secondary
                    font.pixelSize: mode.layout.subtitleSize
                }

                // right: the kind in grey; on the selected row what Enter does + the key;
                // an action waiting for confirmation says so in red
                Item {
                    id: trailing
                    anchors.right: parent.right
                    anchors.rightMargin: mode.layout.rowPadding
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    readonly property real keyRoom: keycap.visible ? keycap.width + mode.layout.keycapGap : 0
                    readonly property bool pinned: Sys.pins.length > 0 && mode.pinKindOf(row.modelData) !== "" && Sys.isPinned(mode.pinKindOf(row.modelData), mode.pinIdOf(row.modelData))
                    readonly property real pinRoom: pinned ? mode.layout.pins.markSize + mode.layout.keycapGap : 0
                    width: label.width + keyRoom + pinRoom

                    // pinned: a small pin before the kind
                    Icon {
                        visible: trailing.pinned
                        anchors.right: label.left
                        anchors.rightMargin: mode.layout.keycapGap
                        anchors.verticalCenter: parent.verticalCenter
                        width: mode.layout.pins.markSize
                        height: width
                        name: mode.layout.pins.markIcon
                        color: Config.colors.secondary
                    }

                    Rectangle {
                        id: keycap
                        visible: row.current && !row.confirming
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(height, keyText.implicitWidth + 2 * mode.layout.keycapPadding)
                        height: mode.layout.keycapHeight
                        radius: Config.corner("small", height)
                        color: Qt.alpha(Config.colors.text, mode.layout.keycapOpacity)
                        StyledText {
                            id: keyText
                            anchors.centerIn: parent
                            font.pixelSize: mode.layout.subtitleSize
                            text: mode.layout.enterKey
                        }
                    }
                    StyledText {
                        id: label
                        anchors.right: parent.right
                        anchors.rightMargin: trailing.keyRoom
                        anchors.verticalCenter: parent.verticalCenter
                        // implicitWidth only depends on the text, so no loop with the row
                        width: Math.min(implicitWidth, view.width * mode.layout.subtitleMaxWidth - trailing.keyRoom)
                        elide: Text.ElideRight
                        font.pixelSize: mode.layout.subtitleSize
                        color: row.confirming ? Config.colors.danger : Config.colors.secondary
                        // (|| "": a row past the end of new, shorter results is briefly without a result)
                        text: (row.confirming ? mode.layout.confirmText : row.current ? mode.layout.verbs[row.modelData.kind] : mode.layout.kinds[row.modelData.kind]) || ""
                    }
                }

                // left: open; right: pin / unpin
                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (point, button) => {
                        if (button === Qt.RightButton) {
                            mode.selected = row.index;
                            mode.togglePinSelected();
                        } else
                            mode.activate(row.index);
                    }
                }
            }
        }

        // edges fade into the island when there's more to scroll that way (a mask when blurred)
        ScrollFade {
            id: edgeFade
            anchors.fill: view
            view: view
            size: mode.layout.scrollFade
            active: mode.results.length > 0
        }
    }
}
