pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
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
// Two pills, like Spotlight (2026-11-24): the notch grows into the search field only (it lives in the
// notch: Mod+Space, `qs ipc call island toggle search`, the logo's menu), and a second black pill hangs
// under it (Island.below, out of the notch's clip) with everything else:
//  - nothing typed: the grid. Favorites first (Sys.pins: panels, apps, commands; each row centred), then
//    "All apps" (every app by name, a GridView: only the tiles on screen exist). One selection across
//    both; arrows move (Up / Down: the tile above / below), Page Up / Down a screenful, Home / End, Tab;
//    Enter opens; Ctrl+P (search.pins.key) or a right-click adds / removes a favorite; Ctrl+Left / Right
//    or dragging moves a favorite (the others slide aside)
//  - something typed: the results. Raycast-style: grouped under small grey section titles (Calculator,
//    Island, Commands, Applications; groups ordered by their best match), icons in rounded tiles, the
//    result's kind in grey at the right, and on the selected row what Enter does ("Open ↵"); favorites
//    show a pin. Up to search.maxResults; past search.visibleRows rows it scrolls (wheel, drag, or the
//    keys, which keep the selection in view), edges fading. A ListView (only the rows on screen exist)
//    whose model only carries each row's group, updated in place; rows read their result by index.
// The keyboard never leaves the field (typing always types); the two contents crossfade as you type or
// clear it, the pill's height springing like the notch. The pill splits off the notch once it's halfway open
// (search.panel.startAt) and merges back into it when the launcher closes.
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
        const modes = island ? island.modeList.concat(island.extraModes) : [];
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

    // ---- the grid (nothing typed): the favorites (Sys.pins: panels, apps, commands), then every app ----
    function pinKindOf(r) {
        return r.panel ? "panel" : r.app ? "app" : r.action ? "action" : "";
    }
    function pinIdOf(r) {
        return r.panel ? r.panel.name : r.app ? r.app.id : r.action ? r.action.title : "";
    }
    // Sys.pins resolved to launcher entries (an app or panel that's gone is skipped)
    readonly property var pinned: {
        const out = [];
        const modes = island ? island.modeList.concat(island.extraModes) : [];
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
    // every app, by name (Sys.apps only changes when an app is installed or removed)
    readonly property var allApps: layout.apps.show ? Sys.apps.slice().sort((a, b) => String(a.name).localeCompare(String(b.name))) : []
    // nothing typed (and no pill): the grid shows instead of results
    readonly property bool showGrid: query.trim() === "" && scope === ""
    readonly property int favCount: pinned.length
    readonly property int tileCount: favCount + allApps.length
    // the selected tile: the favorites first, then the apps (index - favCount)
    property int tileSelected: 0
    onTileSelectedChanged: pendingConfirm = ""
    function tileEntry(i) {
        if (i < favCount)
            return pinned[i] || null;
        const a = allApps[i - favCount];
        return a ? {
            "kind": "app",
            "app": a,
            "name": a.name
        } : null;
    }

    // ---- the grid's layout, in grid coordinates (0 = the favorites' top) ----
    readonly property real contentWidth: implicitWidth - 2 * layout.padding
    readonly property int columns: layout.pins.columns
    readonly property real pinTileWidth: contentWidth / columns
    readonly property real cellHeight: layout.pins.tileHeight + layout.pins.rowGap
    readonly property int pinRows: Math.ceil(favCount / columns)
    readonly property real pinsHeight: pinRows * layout.pins.tileHeight + Math.max(0, pinRows - 1) * layout.pins.rowGap
    readonly property int appRows: Math.ceil(allApps.length / columns)
    readonly property int gridRows: pinRows + appRows
    // the "All apps" title, between the favorites and the apps (none without favorites: it would title
    // the only thing there)
    readonly property bool appsTitled: favCount > 0 && allApps.length > 0
    // above the apps: the favorites, then the gap and the title
    readonly property real headerHeight: favCount === 0 ? 0 : pinsHeight + (appsTitled ? layout.pins.rowGap + layout.apps.titleHeight : 0)
    readonly property real gridFullHeight: headerHeight + appRows * cellHeight
    // what's shown: all of it, up to search.apps.visibleRows rows of tiles (+ the title), then it scrolls
    function gridHeightFor(full) {
        return Math.min(full, layout.apps.visibleRows * cellHeight + (appsTitled ? layout.apps.titleHeight : 0));
    }
    readonly property real gridViewHeight: gridHeightFor(gridFullHeight)
    // where grid coordinates start in the GridView's content (its header, the favorites, sits above the
    // first cell, at a negative y)
    readonly property real gridTop: grid.headerItem ? grid.headerItem.y : -headerHeight

    // favorites: each row centred (a short last row sits in the middle)
    function rowCount(row) {
        return Math.max(0, Math.min(columns, favCount - row * columns));
    }
    function rowLeft(row) {
        return (columns - rowCount(row)) * pinTileWidth / 2;
    }
    function slotX(i) {
        return rowLeft(Math.floor(i / columns)) + (i % columns) * pinTileWidth;
    }
    function slotY(i) {
        return Math.floor(i / columns) * (layout.pins.tileHeight + layout.pins.rowGap);
    }
    // the favorite slot under a point of the favorites (dragging)
    function slotAt(x, y) {
        const row = Math.max(0, Math.min(pinRows - 1, Math.floor(y / (layout.pins.tileHeight + layout.pins.rowGap))));
        const col = Math.max(0, Math.min(rowCount(row) - 1, Math.floor((x - rowLeft(row)) / pinTileWidth)));
        return Math.min(favCount - 1, row * columns + col);
    }
    // the favorite under a point, or -1 beside a short row (hovering the empty space selects nothing)
    function tileAt(x, y) {
        const i = slotAt(x, y);
        return x >= slotX(i) && x < slotX(i) + pinTileWidth ? i : -1;
    }
    // any tile: where it is in the grid, its row (favorites' rows, then the apps')
    function tileX(i) {
        return i < favCount ? slotX(i) : ((i - favCount) % columns) * pinTileWidth;
    }
    function tileY(i) {
        return i < favCount ? slotY(i) : headerHeight + Math.floor((i - favCount) / columns) * cellHeight;
    }
    function rowOf(i) {
        return i < favCount ? Math.floor(i / columns) : pinRows + Math.floor((i - favCount) / columns);
    }
    function rowStart(r) {
        return r < pinRows ? r * columns : favCount + (r - pinRows) * columns;
    }
    function rowEnd(r) {
        return r < pinRows ? Math.min(favCount, (r + 1) * columns) : Math.min(tileCount, favCount + (r - pinRows + 1) * columns);
    }
    // the tile under a point of the window (scene coordinates), or -1 (a gap, the title, beside a row)
    function tileAtScene(p) {
        const c = grid.contentItem.mapFromItem(null, p.x, p.y);
        const gx = c.x, gy = c.y - gridTop;
        if (gy < 0 || gx < 0 || gx >= contentWidth)
            return -1;
        const step = layout.pins.tileHeight + layout.pins.rowGap;
        if (gy < headerHeight) {
            if (gy >= pinsHeight || gy - Math.floor(gy / step) * step > layout.pins.tileHeight)
                return -1;   // the title, or the gap between two rows
            return tileAt(gx, gy);
        }
        const ay = gy - headerHeight;
        const row = Math.floor(ay / cellHeight);
        if (ay - row * cellHeight > layout.pins.tileHeight)
            return -1;
        const j = row * columns + Math.floor(gx / pinTileWidth);
        return j < allApps.length ? favCount + j : -1;
    }

    // ---- the grid's keyboard ----
    // Left / Right (and Tab): the next tile in reading order, across rows and from the favorites into the apps
    function gridMove(dir) {
        if (tileCount === 0)
            return;
        tileSelected = Math.max(0, Math.min(tileCount - 1, tileSelected + dir));
        revealTile(tileSelected);
    }
    // Up / Down (count rows; Page Up / Down: a screenful): the tile right above / below, the one nearest in
    // x (favorites' rows are centred, the apps' aren't), staying put at the first / last row
    function gridMoveRow(dir, count) {
        if (tileCount === 0)
            return;
        const from = rowOf(tileSelected);
        const r = Math.max(0, Math.min(gridRows - 1, from + dir * count));
        if (r === from)
            return;
        const centre = tileX(tileSelected) + pinTileWidth / 2;
        let best = rowStart(r);
        for (let k = rowStart(r); k < rowEnd(r); k++)
            if (Math.abs(tileX(k) + pinTileWidth / 2 - centre) < Math.abs(tileX(best) + pinTileWidth / 2 - centre))
                best = k;
        tileSelected = best;
        revealTile(tileSelected);
    }
    // Home / End
    function gridEdge(last) {
        if (tileCount === 0)
            return;
        tileSelected = last ? tileCount - 1 : 0;
        revealTile(tileSelected);
    }
    // scroll just enough to show the tile (the first row: up to the very top; the first row of apps: with
    // the title above it). Worked out from the layout (GridView only knows the cells it created).
    function revealTile(i) {
        const y0 = tileY(i);
        let top = y0;
        if (rowOf(i) === 0)
            top = 0;
        else if (appsTitled && i >= favCount && i - favCount < columns)
            top = pinsHeight + layout.pins.rowGap;
        const bottom = y0 + layout.pins.tileHeight;
        const h = gridViewHeight;
        let y = (gridScroll.running ? gridScroll.to : grid.contentY) - gridTop;
        if (top < y)
            y = top;
        else if (bottom > y + h)
            y = bottom - h;
        y = Math.max(0, Math.min(y, gridFullHeight - h));
        if (y + gridTop === grid.contentY && !gridScroll.running)
            return;
        gridScroll.stop();
        gridScroll.to = y + gridTop;
        gridScroll.start();
    }

    // ---- favorites: pin / unpin, reorder ----
    // the tiles' models: one entry per favorite / app, by key, moved in place when the order changes (a
    // favorite keeps its delegate and slides to its new slot instead of being rebuilt there)
    ListModel {
        id: pinModel
    }
    ListModel {
        id: appModel
    }
    function pinKey(r) {
        return pinKindOf(r) + ":" + pinIdOf(r);
    }
    function syncModel(model, keys) {
        for (let i = 0; i < keys.length; i++) {
            let j = -1;
            for (let k = i; k < model.count; k++)
                if (model.get(k).key === keys[i]) {
                    j = k;
                    break;
                }
            if (j < 0)
                model.insert(i, {
                    "key": keys[i]
                });
            else if (j !== i)
                model.move(j, i, 1);
        }
        if (model.count > keys.length)
            model.remove(keys.length, model.count - keys.length);
    }
    // pin / unpin: the selected tile, or the selected result (files and calculations can't be pinned). The
    // selection stays on the same thing: an app stays selected among the apps as the favorites above it
    // grow or shrink; an unpinned favorite's place goes to the next one
    function togglePinSelected() {
        const r = showGrid ? tileEntry(tileSelected) : results[selected];
        if (!r || pinKindOf(r) === "")
            return;
        const inFavs = tileSelected < favCount;
        const appIndex = tileSelected - favCount;
        Sys.togglePin(pinKindOf(r), pinIdOf(r));
        if (!showGrid)
            return;
        tileSelected = inFavs ? Math.min(tileSelected, Math.max(0, tileCount - 1)) : favCount + appIndex;
        revealTile(tileSelected);
    }
    // Ctrl+Left / Right: move the selected favorite
    function movePinSelected(step) {
        if (tileSelected >= favCount)
            return;
        const r = pinned[tileSelected];
        const target = Math.max(0, Math.min(favCount - 1, tileSelected + step));
        Sys.movePin(pinKindOf(r), pinIdOf(r), target - tileSelected);
        tileSelected = target;
    }
    onPinnedChanged: {
        syncModel(pinModel, pinned.map(pinKey));
        refit();
    }
    onAllAppsChanged: {
        syncModel(appModel, allApps.map(a => a.id));
        refit();
    }

    // ---- results: where each row goes (a section title before each group; none in a pill's search) ----
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
    // the content height the pill under the notch is sized for: grows right away, shrinks only after typing
    // pauses, so it doesn't pump up and down on every keystroke
    property real shownHeight: 0
    onPlacedChanged: {
        syncRows();
        selected = 0;
        scrollAnim.stop();
        view.contentY = 0;   // new results start at the top
        refit();
    }
    // the height wanted in the pill: the grid when nothing is typed, else the results. Worked out from the
    // sources (not the showGrid / viewHeight bindings, which may not have caught up yet inside the handler
    // that calls this: Qt doesn't order binding updates)
    function wantedHeight() {
        const grid = query.trim() === "" && scope === "";
        return grid ? gridHeightFor(gridFullHeight) : viewHeightFor(placed.height);
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
    onShownHeightChanged: syncPane()

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

    // ---- size: the notch holds only the field; the rest is in the pill under it ----
    implicitWidth: layout.width
    implicitHeight: 2 * layout.fieldPadding + layout.inputHeight

    // ---- reset on open (keyboard focus goes to `input`, see keyTarget) ----
    onActiveChanged: {
        // the pill waits for the field to appear in the notch: cleared first, on every opening and
        // closing (it stayed true from the last opening, and the reset below (refit -> shownHeight ->
        // syncPane) started the pill with the notch still tiny: every opening but the first, 2026-11-24)
        if (active) {
            scope = "";
            input.text = "";
            // the lists the results come from, fresh for this search (one short process each)
            Sys.refreshSettings();
            if (kindMode("files") === "always")
                Sys.refreshFiles();
            selected = 0;
            tileSelected = 0;
            gridHover.lastScene = Qt.point(-1, -1);
            listHover.lastScene = Qt.point(-1, -1);
            gridScroll.stop();
            grid.contentY = gridTop;
            shrinkDebounce.stop();
            shownHeight = 0;
            refit();   // the grid (nothing typed)
            // the pill comes once the notch is far enough along (paneReady)
        }
        syncPane();
    }

    // ---- keys ----
    // The keyboard never leaves the field: typing always types, these move the selection in the pill under
    // it (the grid or the results). Sets event.accepted when the key was used.
    //  - Escape closes; Enter opens the selection (Shift+Enter on a file: show it in Files)
    //  - Backspace at the very start removes the pill; Ctrl+P adds / removes a favorite
    //  - the grid: arrows move between tiles (Up / Down: the tile above / below), Ctrl+Left / Right move a
    //    favorite, Home / End the first / last tile (the field is empty there)
    //  - both: Up / Down, Tab / Shift+Tab the next / previous, Page Up / Down a screenful
    function handleKey(event) {
        const ctrl = !!(event.modifiers & Qt.ControlModifier);
        const shift = !!(event.modifiers & Qt.ShiftModifier);
        const grid = showGrid;
        const k = event.key;
        if (k === Qt.Key_Escape) {
            close();
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (grid)
                activateResult(tileEntry(tileSelected), true, false);
            else
                activate(selected, true, shift);
        } else if (k === Qt.Key_Backspace && scope !== "" && input.cursorPosition === 0 && input.selectedText === "") {
            scope = "";
        } else if (ctrl && k === layout.pins.key.toUpperCase().charCodeAt(0)) {
            // (with Ctrl held the event's text is a control character: compare the key; Qt's letter keys
            // are their upper-case character codes)
            togglePinSelected();
        } else if (k === Qt.Key_Up || k === Qt.Key_Down) {
            const dir = k === Qt.Key_Up ? -1 : 1;
            if (grid)
                gridMoveRow(dir, 1);
            else
                step(dir);
        } else if (grid && (k === Qt.Key_Left || k === Qt.Key_Right)) {
            const dir = k === Qt.Key_Left ? -1 : 1;
            if (ctrl)
                movePinSelected(dir);
            else
                gridMove(dir);
        } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            const dir = k === Qt.Key_Backtab || shift ? -1 : 1;
            if (grid)
                gridMove(dir);
            else
                step(dir);
        } else if (k === Qt.Key_PageUp || k === Qt.Key_PageDown) {
            const dir = k === Qt.Key_PageUp ? -1 : 1;
            if (grid)
                gridMoveRow(dir, Math.max(1, layout.apps.visibleRows - 1));
            else
                step(dir * Math.max(1, layout.visibleRows - 1));
        } else if (grid && (k === Qt.Key_Home || k === Qt.Key_End)) {
            gridEdge(k === Qt.Key_End);
        } else {
            return;
        }
        event.accepted = true;
    }

    // ---- the pill under the notch (search.panel.*) ----
    // Like Spotlight's Liquid Glass: the pill isn't faded in, it splits off the notch. It's born small and
    // tucked behind the notch's bottom edge, springs down and out to its place and size (search.panel.split),
    // and while the two are close a liquid neck joins them, thinning until it snaps (pane.goo: the two
    // shapes' smooth union, a metaball). Its content fades in once it's mostly out (contentFrom). Closing
    // plays it backwards, without a bounce (merge): the content goes first, the pill is drawn back into
    // the notch. It comes once the notch is search.panel.startAt of the way to its size (the notch first,
    // but not waiting for it to finish: that read as slow). While shown, its height springs like the
    // notch's (island.expand / island.shrink).
    // the notch is far enough along (the notch's size against the launcher's) for the pill to
    // come out of it. A binding on the opening itself, never a flag left from the last one (one stayed true
    // and started the pill with the notch still tiny, every opening but the first, 2026-11-24)
    // (measured here, not read from IslandMode.progress: that one says 1 while the mode is inactive, and
    // on activation this binding saw it before it updated: a one-instant true that started the pill)
    readonly property bool paneReady: active && !!island && Math.min(island.width / fullWidth, island.height / fullHeight) >= layout.panel.startAt
    onPaneReadyChanged: syncPane()
    function syncPane() {
        const target = 2 * layout.padding + shownHeight;
        if (active && paneReady && shownHeight > 0) {
            // out of sight (merged, or still settling behind the notch from the last closing): take the
            // new height at once, so it doesn't spring between two contents while it splits off
            if (!pane.visible || pane.split <= 0)
                pane.jumpTo(target);
            else
                pane.springTo(target);
            paneMerge.stop();
            if (pane.split < 1 && !paneSplit.running)
                paneSplit.start();
        } else if ((pane.split > 0 || paneSplit.running) && !paneMerge.running) {
            paneSplit.stop();
            paneMerge.start();
        }
    }
    SpringAnimation {
        id: paneSplit
        target: pane
        property: "split"
        to: 1
        spring: Config.spring(mode.layout.panel.split).spring
        damping: Config.spring(mode.layout.panel.split).damping
        epsilon: 0.001
    }
    SpringAnimation {
        id: paneMerge
        target: pane
        property: "split"
        to: 0
        spring: Config.spring(mode.layout.panel.merge).spring
        damping: Config.spring(mode.layout.panel.merge).damping
        epsilon: 0.001
    }
    // its part of the window takes the pointer (the gap above it too, so the pointer never crosses
    // "nothing" between the notch and the pill)
    Binding {
        target: mode.island ? mode.island.below : null
        property: "area"
        when: pane.visible
        value: Qt.rect(pane.x, 0, pane.width, pane.y + Math.max(pane.height, pane.bodyY + pane.bodyHeight))
        restoreMode: Binding.RestoreBindingOrValue
    }

    // ---- the field, in the notch ----
    Item {
        id: content
        x: mode.layout.padding
        y: mode.layout.fieldPadding
        width: mode.implicitWidth - 2 * mode.layout.padding
        height: mode.layout.inputHeight

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
            color: palette.placeholderText
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
                color: palette.windowText
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
                    color: palette.windowText
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
            color: palette.windowText
            selectionColor: Qt.alpha(palette.windowText, mode.layout.textSelectionOpacity)
            selectedTextColor: palette.windowText
            font.family: Config.font.family
            font.variableAxes: Config.axes(mode.layout.inputSize, Config.font.weight)
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
            // every key goes through handleKey (a test drives it with plain { key, modifiers } objects)
            Keys.onPressed: event => mode.handleKey(event)

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: mode.scope !== "" ? Config.search[mode.scope].placeholder : mode.layout.placeholder
                color: palette.placeholderText
                font.pixelSize: mode.layout.inputSize
            }
        }
    }

    // ---- the pill: hung under the notch (Island.below, set by shell.qml), out of the notch's clip ----
    // `pane` is its place at rest (the layout, the pointer's area); `body` is the shape drawn now, which
    // the split moves from behind the notch to that place. Drawn behind the notch (underNotch comes before
    // the Island in shell.qml), so whatever is still under it is hidden.
    Item {
        id: pane
        parent: mode.island && mode.island.below ? mode.island.below : mode
        x: -width / 2
        y: mode.layout.gap
        width: mode.layout.width
        height: h

        readonly property var look: mode.layout.panel
        // 0 = merged into the notch, 1 = at its place (a little past it while it bounces)
        property real split: 0
        // hidden once the body is back behind the notch (the rest of the merge spring settles out of sight)
        visible: paneSplit.running || (split > 0 && bodyY + bodyHeight > notchBottom + 0.5)

        // the notch, in the pill's coordinates (underNotch rides its bottom centre)
        readonly property Item notch: mode.island
        readonly property real notchWidth: notch ? notch.width : width
        readonly property real notchHeight: notch ? notch.height : 0
        readonly property real notchCorner: notch ? (notch.attached ? notch.attachedCorner : notch.corner) : 0
        readonly property real notchBottom: -y

        // the body now: born look.birthWidth of its width (never wider than the notch's flat bottom) and
        // look.birthHeight tall, hidden just above the notch's bottom edge; at split 1, the pane itself
        readonly property real birthWidth: Math.max(0, Math.min(width * look.birthWidth, notchWidth - 2 * notchCorner))
        readonly property real birthY: notchBottom - look.birthHeight
        readonly property real bodyWidth: Math.max(0, birthWidth + (width - birthWidth) * split)
        readonly property real bodyHeight: Math.max(0, look.birthHeight + (height - look.birthHeight) * split)
        readonly property real bodyX: (width - bodyWidth) / 2
        readonly property real bodyY: birthY + (0 - birthY) * split
        readonly property real bodyCorner: Math.min(Config.corner("island", bodyHeight), bodyHeight / 2)
        // the content: fades in over the last part of the split (and out first when merging)
        readonly property real contentShown: Math.max(0, Math.min(1, (split - look.contentFrom) / Math.max(0.001, 1 - look.contentFrom)))

        // the height: jumps when it appears, springs while it's shown (direction set before the value, so
        // the Behavior picks the right spring)
        property real h: 0
        property bool shrinking: false
        property bool jumping: false
        readonly property var motion: Config.spring(shrinking ? Config.island.shrink : Config.island.expand)
        function jumpTo(v) {
            jumping = true;
            h = v;
            jumping = false;
        }
        function springTo(v) {
            if (v === h)
                return;
            shrinking = v < h;
            h = v;
        }
        Behavior on h {
            enabled: !pane.jumping
            SpringAnimation {
                spring: pane.motion.spring
                damping: pane.motion.damping
                epsilon: 0.5
            }
        }

        // the notch's colors (it isn't inside the notch, so it doesn't inherit them)
        palette.window: Config.island.color
        palette.windowText: Config.colors.text
        palette.placeholderText: Config.colors.secondary

        // ---- the liquid between the notch and the pill ----
        // The smooth union of the two shapes (signed distances joined by a polynomial smooth-min of reach
        // look.goo): it fills the corner where the pill comes out from under the notch, then stretches into
        // a neck that thins and snaps once they're look.goo / 2 apart, the way Liquid Glass shapes split.
        // Solved row by row (each row's edge found by bisection) only while they're that close; elsewhere
        // the union is just the two shapes, already drawn. Both shapes are taken a hair inside their drawn
        // outline (look.gooInset), so only the liquid itself shows.
        function boxDistance(px, py, cx, cy, hw, hh, r) {
            const qx = Math.abs(px - cx) - hw + r, qy = Math.abs(py - cy) - hh + r;
            return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
        }
        readonly property real gap: bodyY - notchBottom
        readonly property bool liquid: visible && notch !== null && look.goo > 0 && gap < look.goo / 2 && bodyHeight > 0
        readonly property string gooPath: {
            if (!liquid)
                return "";
            const k = look.goo, inset = look.gooInset, cx = width / 2;
            // the notch: a box reaching far up (only its bottom matters), its bottom corners rounded
            const nHalfW = notchWidth / 2 - inset, nR = Math.max(0, Math.min(notchCorner - inset, nHalfW));
            const nHalfH = Math.max(notchHeight, k) * 4, nCy = notchBottom - inset - nHalfH;
            const bHalfW = bodyWidth / 2 - inset, bHalfH = bodyHeight / 2 - inset;
            if (bHalfW <= 0 || bHalfH <= 0)
                return "";
            const bR = Math.max(0, Math.min(bodyCorner - inset, bHalfW, bHalfH)), bCy = bodyY + bodyHeight / 2;
            const field = (x, y) => {
                const a = boxDistance(x, y, cx, nCy, nHalfW, nHalfH, nR);
                const b = boxDistance(x, y, cx, bCy, bHalfW, bHalfH, bR);
                const hh = Math.max(k - Math.abs(a - b), 0) / k;
                return Math.min(a, b) - hh * hh * k / 4;
            };
            // the rows where the two can blend: from the notch's corners to below the pill's top corners
            const top = notchBottom - Math.max(nR, k), bottom = Math.min(bodyY + bodyHeight, bodyY + Math.max(bR, k) + k);
            const maxHalf = Math.max(nHalfW, bHalfW) + k;
            const step = look.gooStep;
            const n = v => v.toFixed(2);
            let path = "", left = [];
            const flush = () => {
                if (left.length > 1) {
                    path += "M " + n(cx - left[0][0]) + " " + n(left[0][1]);
                    for (let i = 1; i < left.length; i++)
                        path += " L " + n(cx - left[i][0]) + " " + n(left[i][1]);
                    for (let i = left.length - 1; i >= 0; i--)
                        path += " L " + n(cx + left[i][0]) + " " + n(left[i][1]);
                    path += " Z ";
                }
                left = [];
            };
            for (let y = top; y <= bottom + step / 2; y += step) {
                if (field(cx, y) >= 0) {
                    flush();
                    continue;
                }
                let lo = 0, hi = maxHalf;
                for (let i = 0; i < 14; i++) {
                    const mid = (lo + hi) / 2;
                    if (field(cx + mid, y) < 0)
                        lo = mid;
                    else
                        hi = mid;
                }
                left.push([lo, y]);
            }
            flush();
            return path;
        }
        Shape {
            visible: pane.liquid
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Config.island.color
                strokeColor: "transparent"
                strokeWidth: -1
                PathSvg {
                    path: pane.gooPath
                }
            }
        }

        // ---- the pill's own shape ----
        Rectangle {
            x: pane.bodyX
            y: pane.bodyY
            width: pane.bodyWidth
            height: pane.bodyHeight
            visible: Config.island.cornerSmoothing <= 0
            radius: pane.bodyCorner
            color: Config.island.color
        }
        Shape {
            x: pane.bodyX
            y: pane.bodyY
            width: pane.bodyWidth
            height: pane.bodyHeight
            visible: Config.island.cornerSmoothing > 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Config.island.color
                strokeColor: "transparent"
                strokeWidth: -1
                PathSvg {
                    path: pane.bodyWidth > 0 && pane.bodyHeight > 0 ? Config.roundedRectPath(pane.bodyWidth, pane.bodyHeight, pane.bodyCorner, Config.island.cornerSmoothing) : ""
                }
            }
        }

        // the content, at its place in the pane, cut to the body while it splits
        Item {
            id: bodyClip
            x: pane.bodyX
            y: pane.bodyY
            width: pane.bodyWidth
            height: pane.bodyHeight
            clip: pane.split < 1
            opacity: pane.contentShown
            visible: opacity > 0
            Item {
                x: -bodyClip.x
                y: -bodyClip.y
                width: pane.width
                height: pane.height

                // the content, clipped to the pill while its height springs
                Item {
                    id: paneContent
                    x: mode.layout.padding
                    y: mode.layout.padding
                    width: mode.contentWidth
                    height: Math.max(0, pane.height - 2 * mode.layout.padding)
                    clip: true

                    // ---- the grid: nothing typed ----
                    Item {
                        id: gridLayer
                        width: parent.width
                        height: mode.gridViewHeight
                        opacity: mode.showGrid ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: mode.layout.panel.swap
                                easing.type: Easing.OutCubic
                            }
                        }

                        GridView {
                            id: grid
                            anchors.fill: parent
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            cellWidth: mode.pinTileWidth
                            cellHeight: mode.cellHeight
                            cacheBuffer: mode.cellHeight * mode.layout.apps.visibleRows
                            model: appModel

                            NumberAnimation {
                                id: gridScroll
                                target: grid
                                property: "contentY"
                                duration: mode.layout.scrollDuration
                                easing.type: Easing.OutCubic
                            }

                            // the favorites, then the "All apps" title: above the apps, scrolling with them
                            header: Item {
                                id: header
                                width: grid.width
                                height: mode.headerHeight

                                Item {
                                    id: pinGrid
                                    width: parent.width
                                    height: mode.pinsHeight

                                    Repeater {
                                        model: pinModel
                                        Item {
                                            id: fav
                                            required property int index
                                            required property string key
                                            readonly property var entry: mode.pinned[index] || ({})
                                            width: mode.pinTileWidth
                                            height: mode.layout.pins.tileHeight

                                            // its slot, springing there when the order changes (with the highlight:
                                            // same spring); while dragged it follows the pointer instead
                                            property bool dragging: false
                                            property real dragX: 0
                                            property real dragY: 0
                                            x: dragging ? dragX : mode.slotX(index)
                                            y: dragging ? dragY : mode.slotY(index)
                                            // the dragged tile above all, the selected one (moving with Ctrl+arrows)
                                            // above the one it swaps with
                                            z: dragging ? 3 : index === mode.tileSelected ? 2 : 1
                                            scale: dragging ? mode.layout.pins.dragScale : 1
                                            Behavior on x {
                                                enabled: !fav.dragging && gridLayer.visible
                                                SpringAnimation {
                                                    spring: Config.spring(Config.panel.list.highlight).spring
                                                    damping: Config.spring(Config.panel.list.highlight).damping
                                                    epsilon: 0.25
                                                }
                                            }
                                            Behavior on y {
                                                enabled: !fav.dragging && gridLayer.visible
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

                                            LauncherTile {
                                                width: parent.width
                                                entry: fav.entry
                                                current: fav.index === mode.tileSelected
                                                confirming: !!fav.entry.action && mode.pendingConfirm === fav.entry.name
                                            }

                                            // a click opens it, a right-click unpins it; pressing and dragging past
                                            // search.pins.dragThreshold carries it, the others sliding aside as it
                                            // passes (preventStealing: the grid would take the drag as a scroll)
                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                preventStealing: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                cursorShape: fav.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                                property point pressGrid: Qt.point(0, 0)
                                                property point grab: Qt.point(0, 0)
                                                onPositionChanged: mouse => {
                                                    const g = mapToItem(pinGrid, mouse.x, mouse.y);
                                                    if (!pressed || !(mouse.buttons & Qt.LeftButton))
                                                        return;
                                                    if (!fav.dragging && Math.hypot(g.x - pressGrid.x, g.y - pressGrid.y) > mode.layout.pins.dragThreshold) {
                                                        fav.dragX = fav.x;
                                                        fav.dragY = fav.y;
                                                        grab = Qt.point(g.x - fav.x, g.y - fav.y);
                                                        fav.dragging = true;
                                                    }
                                                    if (fav.dragging) {
                                                        fav.dragX = g.x - grab.x;
                                                        fav.dragY = g.y - grab.y;
                                                        const target = mode.slotAt(g.x, g.y);
                                                        mode.tileSelected = target;
                                                        if (target !== fav.index)
                                                            Sys.movePin(mode.pinKindOf(fav.entry), mode.pinIdOf(fav.entry), target - fav.index);
                                                    }
                                                }
                                                onPressed: mouse => pressGrid = mapToItem(pinGrid, mouse.x, mouse.y)
                                                onReleased: mouse => {
                                                    if (fav.dragging) {
                                                        // drop: back on the slot grid (the springs carry it into its place)
                                                        fav.dragging = false;
                                                        return;
                                                    }
                                                    if (mouse.button === Qt.RightButton) {
                                                        mode.tileSelected = fav.index;
                                                        mode.togglePinSelected();
                                                    } else
                                                        mode.activateResult(fav.entry, false, false);
                                                }
                                            }
                                        }
                                    }
                                }
                                StyledText {
                                    visible: mode.appsTitled
                                    x: mode.layout.iconInset
                                    y: mode.pinsHeight + mode.layout.pins.rowGap
                                    height: mode.layout.apps.titleHeight
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Config.activity.captionSize
                                    color: palette.placeholderText
                                    text: mode.layout.apps.title
                                }
                            }

                            // the selected tile's highlight: springs from tile to tile, favorites and apps alike (the
                            // lists' look and spring). In the scrolling content, behind the tiles
                            Rectangle {
                                parent: grid.contentItem
                                z: -1
                                x: mode.tileX(mode.tileSelected)
                                y: mode.tileY(mode.tileSelected) + mode.gridTop
                                width: mode.pinTileWidth
                                height: mode.layout.pins.tileHeight
                                radius: Config.corner("row", height)
                                color: palette.windowText
                                opacity: Config.panel.list.selectedOpacity
                                visible: mode.tileCount > 0
                                Behavior on x {
                                    enabled: gridLayer.visible
                                    SpringAnimation {
                                        spring: Config.spring(Config.panel.list.highlight).spring
                                        damping: Config.spring(Config.panel.list.highlight).damping
                                        epsilon: 0.25
                                    }
                                }
                                Behavior on y {
                                    enabled: gridLayer.visible
                                    SpringAnimation {
                                        spring: Config.spring(Config.panel.list.highlight).spring
                                        damping: Config.spring(Config.panel.list.highlight).damping
                                        epsilon: 0.25
                                    }
                                }
                            }

                            // The pointer selects the tile under it only when it really moves (from its own scene
                            // position: the pill scales as it appears, which moves a tile under a still pointer). The
                            // first position seen after opening only records where the pointer is. Scrolling (wheel,
                            // drag) selects the tile that ends up under it; the keyboard's own scrolling doesn't.
                            HoverHandler {
                                id: gridHover
                                enabled: mode.showGrid
                                property point lastScene: Qt.point(-1, -1)
                                cursorShape: Qt.PointingHandCursor
                                function selectUnderPointer() {
                                    if (!hovered || lastScene.x < 0)
                                        return;
                                    const i = mode.tileAtScene(lastScene);
                                    if (i >= 0 && i !== mode.tileSelected)
                                        mode.tileSelected = i;
                                }
                                onPointChanged: {
                                    const p = point.scenePosition;
                                    if (!hovered || (p.x === lastScene.x && p.y === lastScene.y))
                                        return;
                                    const first = lastScene.x < 0;
                                    lastScene = p;
                                    if (!first)
                                        selectUnderPointer();
                                }
                            }
                            onContentYChanged: {
                                if (!gridScroll.running)
                                    gridHover.selectUnderPointer();
                            }

                            // an app: a click opens it, a right-click adds it to the favorites (or takes it off)
                            delegate: Item {
                                id: cell
                                required property int index
                                required property string key
                                readonly property int tileIndex: mode.favCount + index
                                readonly property var entry: mode.tileEntry(tileIndex) || ({})
                                width: grid.cellWidth
                                height: grid.cellHeight
                                LauncherTile {
                                    width: parent.width
                                    entry: cell.entry
                                    current: cell.tileIndex === mode.tileSelected
                                }
                                TapHandler {
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onTapped: (point, button) => {
                                        if (button === Qt.RightButton) {
                                            mode.tileSelected = cell.tileIndex;
                                            mode.togglePinSelected();
                                        } else
                                            mode.activateResult(cell.entry, false, false);
                                    }
                                }
                            }
                        }
                        ScrollFade {
                            anchors.fill: grid
                            view: grid
                            size: mode.layout.scrollFade
                            active: mode.tileCount > 0
                        }
                    }

                    // ---- results: something typed ----
                    Item {
                        id: resultsLayer
                        width: parent.width
                        height: mode.viewHeight
                        opacity: mode.showGrid ? 0 : 1
                        visible: opacity > 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: mode.layout.panel.swap
                                easing.type: Easing.OutCubic
                            }
                        }
                        ListView {
                            id: view
                            anchors.fill: parent
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
                                    color: palette.placeholderText
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
                                color: palette.windowText
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
                                    readonly property color tint: row.modelData.panel || row.modelData.calc || row.modelData.url ? Config.colors.accent : palette.windowText

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
                                    color: palette.placeholderText
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
                                        color: palette.placeholderText
                                    }

                                    Rectangle {
                                        id: keycap
                                        visible: row.current && !row.confirming
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(height, keyText.implicitWidth + 2 * mode.layout.keycapPadding)
                                        height: mode.layout.keycapHeight
                                        radius: Config.corner("small", height)
                                        color: Qt.alpha(palette.windowText, mode.layout.keycapOpacity)
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
                                        color: row.confirming ? Config.colors.danger : palette.placeholderText
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
            }
        }
    }
}
