pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// The shelf, grown out of the notch: what the island holds, the files of its folder (shelf.folder,
// Sys.shelf), newest first, in the carousel the wallpaper picker uses (PictureCarousel, carousel.*).
// Empty, it's just the drop zone, muted (widgets/DropZone, at its size). Things get here two ways: dropped on the notch (copied into the folder; a web picture downloaded), and
// every screenshot, by itself (shelf.keepScreenshots). Each card shows the file: a picture as itself, any
// other file as the desktop's thumbnail of it (a PDF's first page, a video's frame), else its type's icon
// and its name. Above the cards, the file's name and when it arrived.
// Left / Right, the wheel, a drag or a click on a side card pick; a click or Enter on the front card opens
// it (Sys.openFile); Shift+Enter or a right click shows it in Files; Ctrl+C copies a picture; Delete or
// the × on the front card moves it to the trash; drag the front card up or down out of the island to drop
// the file anywhere (through the file transfer portal for sandboxed apps, Sys.fileTransfer). After a drop
// on the notch it opens on what was dropped (Sys.shelfFocus).
IslandMode {
    id: mode

    readonly property var look: Config.shelf

    launcher: Config.shelf.launcher
    // what's held: Sys's list, frozen while the shelf animates out
    property var items: Sys.shelf
    readonly property var pictures: items.map(s => s.path)
    readonly property var previews: items.map(s => s.preview)
    readonly property var icons: items.map(s => s.icon)
    readonly property var names: items.map(s => s.name)
    readonly property var ratios: items.map(s => s.preview !== "" && s.height > 0 ? s.width / s.height : look.card.iconRatio)
    readonly property int count: items.length
    readonly property var current: count > 0 ? items[row.selected] || null : null

    // the file transfer portal helper, while dragging out is possible
    Binding {
        target: Sys
        property: "fileTransfer"
        value: mode.onScreen && mode.look.dragOut
    }

    readonly property real padding: look.padding
    // empty: just the drop zone, muted (where things go), at the drop zone's size
    readonly property bool empty: count === 0
    belowMinimum: empty
    implicitWidth: empty ? Config.island.drop.width : 2 * padding + row.stageW
    implicitHeight: empty ? Config.island.drop.height : 2 * padding + row.stageH + Config.carousel.name.gap + title.implicitHeight
    readonly property bool nameOnTop: Config.carousel.name.position === "top"

    // the picture last copied (its tag); forgotten when the shelf is gone
    property string copied: ""

    // byKey: from the keyboard (close() then holds the keyboard until the key is released)
    function finish(byKey, closes) {
        if (!closes)
            return;
        if (byKey)
            close();
        else
            requestState("idle");
    }
    function open(byKey) {
        if (!current)
            return;
        row.press();
        Sys.openFile(current.path);
        finish(byKey, look.openCloses);
    }
    function reveal(byKey) {
        if (!current)
            return;
        Sys.revealFile(current.path);
        finish(byKey, look.revealCloses);
    }
    function copy() {
        if (!current || current.preview !== current.path)
            return;
        Sys.copyImage(current.path);
        copied = current.path;
        row.press();
    }
    // off the shelf: its card shrinks and fades (carousel.leave), then it goes to the trash; the selection
    // stays where it was (the next one slides into its place, PictureCarousel.relocate)
    function remove() {
        if (!current || removeLater.running)
            return;
        row.leavingPath = current.path;
        followNewest = false;
        removeLater.start();
    }
    Timer {
        id: removeLater
        interval: Config.carousel.leave.duration
        onTriggered: {
            Sys.shelfRemove(row.leavingPath);
            row.leavingPath = "";
        }
    }

    // "Today at 19:52", "Yesterday at 08:10", "Monday 16 November at 21:03" (shelf.name.*)
    function when(time) {
        if (!time)
            return "";
        const day = Sys.formatStamp(time, "yyyy-MM-dd");
        const dayText = day === Sys.today ? look.name.today : day === Sys.yesterday ? look.name.yesterday : Sys.formatStamp(time, look.name.dateFormat);
        const timeText = Sys.formatStamp(time, Sys.hour24 ? look.name.timeFormat : look.name.timeFormat12h);
        return look.name.format.replace("{day}", dayText).replace("{time}", timeText);
    }

    // ---- keyboard ----
    keyTarget: mode
    Keys.onLeftPressed: row.step(-1)
    Keys.onRightPressed: row.step(1)
    Keys.onReturnPressed: event => event.modifiers & Qt.ShiftModifier ? reveal(true) : open(true)
    Keys.onEnterPressed: event => event.modifiers & Qt.ShiftModifier ? reveal(true) : open(true)
    Keys.onDeletePressed: remove()
    Keys.onTabPressed: Activity.switchNotchTab()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            copy();
            event.accepted = true;
        }
    }

    // each opening lands on the newest, also when the list read on opening brings a new one; once you've
    // moved, something arriving while it's open keeps you on the card you're on
    property bool followNewest: true
    onActiveChanged: {
        if (active) {
            followNewest = true;
            items = Qt.binding(() => Sys.shelf);
            Sys.refreshShelf();
            const focus = pictures.indexOf(Sys.shelfFocus);
            row.select(focus >= 0 ? focus : 0, false);
            if (focus >= 0) {
                Sys.shelfFocus = "";
                followNewest = false;
            }
        } else
            items = items;
    }
    onOnScreenChanged: {
        if (!onScreen) {
            copied = "";
            row.wheelSum = 0;
        }
    }

    DropZone {
        visible: mode.empty
        width: Config.island.drop.width
        height: Config.island.drop.height
        x: (mode.width - width) / 2
        muted: true
        outerCorner: Config.corner(Config.attached ? "attached" : "island", height)
        text: mode.look.emptyText
    }

    Item {
        id: content
        visible: !mode.empty
        x: mode.padding
        y: mode.padding
        width: mode.implicitWidth - 2 * mode.padding
        height: mode.implicitHeight - 2 * mode.padding

        PictureCarousel {
            id: row
            y: mode.nameOnTop ? title.height + Config.carousel.name.gap : 0
            width: parent.width
            height: stageH
            availableWidth: mode.look.width - 2 * mode.padding
            ratio: mode.look.card.iconRatio
            pictures: mode.pictures
            previews: mode.previews
            icons: mode.icons
            names: mode.names
            ratios: mode.ratios
            minRatio: mode.look.card.minRatio
            maxRatio: mode.look.card.maxRatio
            markedPath: mode.copied
            markIcon: mode.look.copied.icon
            markLabel: mode.look.copied.label
            dragOut: mode.look.dragOut
            // the × on the front card: off the shelf (to the trash)
            removeIcon: mode.look.remove.icon
            removeSize: mode.look.remove.size
            removeInset: mode.look.remove.inset
            removeGlyph: mode.look.remove.glyphSize
            onRemoveRequested: mode.remove()
            onActivated: mode.open(false)
            onSecondaryActivated: mode.reveal(false)
            onPicked: mode.followNewest = false
            onPicturesChanged: if (mode.active) {
                // what was just dropped, once it's in the list (Sys.shelfFocus): straight to it
                const focus = mode.pictures.indexOf(Sys.shelfFocus);
                if (focus >= 0) {
                    select(focus, false);
                    Sys.shelfFocus = "";
                    mode.followNewest = false;
                } else if (mode.followNewest)
                    select(0, false);
                else
                    relocate(selectedPath);
            }
        }



        // the file's name and when it arrived, above or under the cards
        RollingName {
            id: title
            y: mode.nameOnTop ? 0 : row.height + Config.carousel.name.gap
            width: parent.width
            animate: mode.active
            pixelSize: Config.panel.nameSize
            text: !mode.current ? "" : mode.current.name + mode.look.name.separator + mode.when(mode.current.time)
        }
    }
}
