pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notifications: every one that arrives is kept in a history (the notification center, under the
// notch), and drops in as a card under the notch for a while (a banner). Several cards can be on screen
// at once (notifications.maxVisible, newest on top). The history survives restarts and reboots
// (notifications.json in Quickshell's state folder, notifications.historyLimit at most).
//
//  - Focus (Activity.doNotDisturb) on: no card drops in (critical ones still do, dndAllowsCritical); it
//    goes to the center quietly. Low urgency ones only drop in with notifications.showLowUrgency.
//  - Hovering the cards pauses their time; leaving gives each at least island.leaveDelay.
//  - niri's "Screenshot captured" (screenshot.summaries) becomes a screenshot card: the picture itself.
//    A new screenshot joins the latest screenshot card still in the history (its pile grows, the card
//    comes back on top), so several screenshots read as one stack; clicking it opens the shelf in the
//    notch (where every screenshot also goes, Sys.shelfKeep). The file is the notification's, else the
//    newest in screenshot.folder (Sys.findScreenshot).
//  - An app taking its notification back (closing it) removes it; one updating it updates its card.
//  - NEW / OLD in the center: new = arrived since the center was last closed (`lastSeen`); the bar's
//    clock shows a dot while there are some (bar.clock.unseenDot).
// The UI reads two ListModels updated in place (only what changed moves): `model` (the history, newest
// first) and `banners` (the cards on screen). Each row is plain values (uid, kind, app, entry, icon, image,
// summary, body, urgency, time, pile (JSON list of pictures), section).
Singleton {
    id: root

    readonly property ListModel model: ListModel {}
    readonly property ListModel banners: ListModel {}
    // when the center was last closed (ms); what came after is new
    property double lastSeen: 0
    readonly property int count: _count
    readonly property int unseen: _unseen
    property int _count: 0
    property int _unseen: 0
    // the mouse is over the cards: their time is paused (set by the stack)
    property bool hovered: false
    // goes up whenever a row changes (the cards read their row by uid: this makes them read it again)
    property int revision: 0

    // live notification objects by uid, while the app still has them (actions, opening its window)
    property var _live: ({})
    property int _uidSeq: 0
    function _newUid() {
        return "u" + Date.now().toString(36) + "-" + (++_uidSeq);
    }
    function _index(uid) {
        for (let i = 0; i < model.count; i++)
            if (model.get(i).uid === uid)
                return i;
        return -1;
    }
    function get(uid) {
        const i = _index(uid);
        return i >= 0 ? model.get(i) : null;
    }
    function pile(row) {
        try {
            return row && row.pile ? JSON.parse(row.pile) : [];
        } catch (e) {
            return [];
        }
    }
    function _recount() {
        revision++;
        _count = model.count;
        let n = 0;
        for (let i = 0; i < model.count; i++)
            if (model.get(i).time > lastSeen)
                n++;
        _unseen = n;
    }

    // ---- arrivals ----
    Connections {
        target: Sys
        function onNotified(n) {
            root._arrive(n, false);
        }
    }
    function _arrive(n, plain) {
        // switched off (notifications.enabled): apps still deliver them, the shell just doesn't show them
        if (!Config.notifications.enabled)
            return;
        if (!plain && Config.screenshot.enabled && Config.screenshot.summaries.indexOf(n.summary) >= 0) {
            Sys.findScreenshot(n, (path, w, h) => {
                if (path === "")
                    root._arrive(n, true);
                else
                    root._screenshot(n, path, w, h);
            });
            return;
        }
        const info = Sys.notificationInfo(n);
        const uid = _newUid();
        const row = {
            "uid": uid,
            "kind": "notification",
            "nid": n.id,
            "app": info.appName || "",
            "entry": n.desktopEntry || "",
            "icon": info.icon || "",
            "image": info.image || "",
            "summary": info.summary || "",
            "body": info.body || "",
            "urgency": info.urgency,
            "time": Date.now(),
            "pile": "",
            "width": 0,
            "height": 0,
            "section": "new",
            "leaving": false
        };
        _insert(row);
        _live[uid] = n;
        n.closed.connect(reason => {
            delete root._live[uid];
            // the app took it back: it's gone from the center too
            if (reason === NotificationCloseReason.CloseRequested)
                root._remove(uid);
        });
        // an app replacing its notification updates the same object
        const update = () => root._update(uid, n);
        n.summaryChanged.connect(update);
        n.bodyChanged.connect(update);
        n.imageChanged.connect(update);

        const cfg = Config.notifications;
        const critical = info.urgency === "critical";
        if (Activity.doNotDisturb && !(critical && cfg.dndAllowsCritical))
            return;
        if (info.urgency === "low" && !cfg.showLowUrgency)
            return;
        const timeout = critical ? cfg.criticalTimeout : info.timeout > 0 && cfg.respectAppTimeout ? info.timeout : cfg.timeout;
        _showBanner(uid, timeout);
        Activity.sound("notification");
    }
    function _update(uid, n) {
        const i = _index(uid);
        if (i < 0)
            return;
        const info = Sys.notificationInfo(n);
        model.set(i, {
            "summary": info.summary || "",
            "body": info.body || "",
            "image": info.image || ""
        });
        revision++;
        _restartBanner(uid);
        _save.restart();
    }
    // a screenshot: onto the latest screenshot card's pile (it comes back on top), else a new card. niri's
    // notification is closed: the card holds the file itself.
    function _screenshot(n, path, w, h) {
        Sys.dismissNotification(n);
        // the island holds it too (shelf.keepScreenshots)
        Sys.shelfKeep(path);
        let i = -1;
        for (let j = 0; j < model.count; j++)
            if (model.get(j).kind === "screenshot") {
                i = j;
                break;
            }
        let uid;
        if (i >= 0) {
            const row = model.get(i);
            uid = row.uid;
            const pics = pile(row).filter(p => p !== path);
            pics.unshift(path);
            model.set(i, {
                "pile": JSON.stringify(pics.slice(0, Config.screenshot.pileLimit)),
                "width": w,
                "height": h,
                "time": Date.now(),
                "section": "new"
            });
            if (i > 0)
                model.move(i, 0, 1);
            _recount();
            _save.restart();
        } else {
            uid = _newUid();
            _insert({
                "uid": uid,
                "kind": "screenshot",
                "nid": -1,
                "app": "",
                "entry": "",
                "icon": "",
                "image": "",
                "summary": n.summary || "",
                "body": "",
                "urgency": "normal",
                "time": Date.now(),
                "pile": JSON.stringify([path]),
                "width": w,
                "height": h,
                "section": "new",
                "leaving": false
            });
        }
        _showBanner(uid, Config.screenshot.timeout);
    }
    function _insert(row) {
        model.insert(0, row);
        while (model.count > Config.notifications.historyLimit) {
            const last = model.get(model.count - 1);
            _hideBanner(last.uid, true);
            _forget(last.uid);
            model.remove(model.count - 1);
        }
        _recount();
        _save.restart();
    }

    // ---- what the user does ----
    // clicking a card: what the notification opens (its action, the window that sent it, the app), then
    // it's done with (notifications.clickDismisses); a screenshot card opens the shelf
    function open(uid) {
        const row = get(uid);
        if (!row)
            return;
        if (row.kind === "screenshot") {
            _hideBanner(uid);
            Activity.open("shelf");
            return;
        }
        const n = _live[uid];
        // gone (after a restart, or expired by the app): bring up the app that sent it
        Sys.openNotification(n || {
            "id": -1,
            "actions": [],
            "desktopEntry": row.entry,
            "appName": row.app
        });
        const hasDefault = !!n && (n.actions || []).some(a => a.identifier === "default");
        if (Config.notifications.clickDismisses || !hasDefault)
            dismiss(uid);
        else
            _hideBanner(uid);
    }
    // one of the notification's own buttons
    function action(uid, id) {
        Sys.notificationAction(_live[uid], id);
        dismiss(uid);
    }
    function actions(uid) {
        const n = _live[uid];
        return n ? Sys.notificationInfo(n).actions.slice(0, Config.notifications.maxActions) : [];
    }
    // gone for good (the ×, swiping it right in the center, clicking it); the card's exit has played already
    function dismiss(uid) {
        _hideBanner(uid, true);
        _forget(uid);
        _remove(uid);
    }
    // the card leaves the screen (its exit has played: a swipe); the notification stays in the center
    function hide(uid) {
        _hideBanner(uid, true);
    }
    function clearAll() {
        while (banners.count > 0)
            _hideBanner(banners.get(0).uid, true);
        for (let i = 0; i < model.count; i++)
            _forget(model.get(i).uid);
        model.clear();
        _recount();
        _save.restart();
    }
    function _forget(uid) {
        const n = _live[uid];
        delete _live[uid];
        Sys.dismissNotification(n);
    }
    function _remove(uid) {
        _hideBanner(uid, true);
        const i = _index(uid);
        if (i >= 0) {
            model.remove(i);
            _recount();
            _save.restart();
        }
    }

    // the center opening: the cards on screen go into it; closing it: what was new is now old
    Connections {
        target: Activity
        function onCenterChanged() {
            if (Activity.center) {
                while (root.banners.count > 0)
                    root._hideBanner(root.banners.get(0).uid, true);
                return;
            }
            root.lastSeen = Date.now();
            for (let i = 0; i < root.model.count; i++)
                if (root.model.get(i).section !== "old")
                    root.model.setProperty(i, "section", "old");
            root._recount();
            root._save.restart();
        }
    }

    // ---- the cards on screen (banners): each has its own time, paused while hovered ----
    // A card leaving the screen plays its own exit first (NotificationCard: it slides out to the right, then
    // folds its height so the others glide up), then calls _dropBanner: removed at once, the list snapped.
    property var _timing: ({})
    function _showBanner(uid, timeout) {
        if (Activity.center)
            return;
        // the time since the last tick belongs to the cards already there, not to this one: counted
        // first (charged to a new card, it was hours after a quiet spell: it expired the moment it came)
        _elapse();
        let i = -1;
        for (let j = 0; j < banners.count; j++)
            if (banners.get(j).uid === uid)
                i = j;
        if (i >= 0 && banners.get(i).leaving)
            banners.setProperty(i, "leaving", false);
        if (i > 0)
            banners.move(i, 0, 1);
        else if (i < 0)
            banners.insert(0, {
                "uid": uid,
                "leaving": false
            });
        _timing[uid] = {
            "timeout": timeout,
            "remaining": timeout
        };
        // too many: the oldest leave the screen (they're still in the center)
        let shown = 0;
        for (let j = 0; j < banners.count; j++)
            if (!banners.get(j).leaving && ++shown > Config.notifications.maxVisible)
                _hideBanner(banners.get(j).uid);
        _schedule();
    }
    function _restartBanner(uid) {
        _elapse();
        const t = _timing[uid];
        if (t)
            t.remaining = Math.max(t.remaining, t.timeout);
        _schedule();
    }
    // the card leaves the screen: with its exit (it calls _dropBanner at the end), or at once (`instant`:
    // the center opening takes them all)
    function _hideBanner(uid, instant) {
        _elapse();
        for (let j = 0; j < banners.count; j++)
            if (banners.get(j).uid === uid) {
                if (instant)
                    banners.remove(j);
                else
                    banners.setProperty(j, "leaving", true);
                break;
            }
        delete _timing[uid];
        _schedule();
    }
    function _dropBanner(uid) {
        for (let j = 0; j < banners.count; j++)
            if (banners.get(j).uid === uid) {
                banners.remove(j);
                break;
            }
    }
    // one timer, set to the card that leaves first
    property double _tickedAt: Date.now()
    function _elapse() {
        const now = Date.now(), spent = now - _tickedAt;
        _tickedAt = now;
        if (hovered)
            return;
        for (const uid in _timing)
            if (_timing[uid].timeout > 0)
                _timing[uid].remaining -= spent;
    }
    function _schedule() {
        _elapse();
        bannerTimer.stop();
        if (hovered)
            return;
        let next = -1;
        for (const uid in _timing) {
            const t = _timing[uid];
            if (t.timeout <= 0)
                continue;
            if (t.remaining <= 0) {
                Qt.callLater(() => root._hideBanner(uid));
                continue;
            }
            if (next < 0 || t.remaining < next)
                next = t.remaining;
        }
        if (next > 0) {
            bannerTimer.interval = Math.max(1, next);
            bannerTimer.start();
        }
    }
    Timer {
        id: bannerTimer
        onTriggered: root._schedule()
    }
    onHoveredChanged: {
        _elapse();
        if (!hovered)
            for (const uid in _timing)
                _timing[uid].remaining = Math.max(_timing[uid].remaining, Config.island.leaveDelay);
        _schedule();
    }

    // ---- saved across restarts ----
    // plain values only; a picture that came as data (not a file) can't outlive the shell, so it's dropped
    readonly property var _savedRoles: ["uid", "kind", "app", "entry", "icon", "image", "summary", "body", "urgency", "time", "pile", "width", "height"]
    function _serialize() {
        const list = [];
        for (let i = 0; i < model.count; i++) {
            const r = model.get(i), o = {};
            for (const k of _savedRoles)
                o[k] = r[k];
            if (!/^(\/|file:)/.test(o.image))
                o.image = "";
            list.push(o);
        }
        return JSON.stringify({
            "lastSeen": lastSeen,
            "items": list
        });
    }
    property Timer _save: Timer {
        interval: Config.system.saveDelay
        onTriggered: historyFile.setText(root._serialize())
    }
    // a change still waiting when the shell reloads or quits is written right away, not lost
    Component.onDestruction: if (_save.running)
        historyFile.setText(_serialize())
    FileView {
        id: historyFile
        path: Quickshell.statePath("notifications.json")
        printErrors: false   // no file yet = no history
        onLoaded: {
            let v;
            try {
                v = JSON.parse(text());
            } catch (e) {
                return;
            }
            root.lastSeen = Number(v.lastSeen) || 0;
            root.model.clear();
            for (const o of (v.items || []).slice(0, Config.notifications.historyLimit)) {
                if (!o || typeof o.uid !== "string")
                    continue;
                const row = {
                    "nid": -1,
                    "section": o.time > root.lastSeen ? "new" : "old",
                    "leaving": false
                };
                for (const k of root._savedRoles)
                    row[k] = o[k] === undefined || o[k] === null ? (k === "time" || k === "width" || k === "height" ? 0 : "") : o[k];
                root.model.append(row);
            }
            root._recount();
        }
    }
}
