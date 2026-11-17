pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// Screenshots panel: the pictures of screenshot.folder (Sys.screenshots), newest first, in the same
// PictureCarousel as the wallpaper panel (carousel.*). Each card takes its picture's proportions, held
// between screenshots.card.minRatio and maxRatio (a thin region gets a normal card, cropped around its
// centre); pictures fill their card. Above (or under) the cards, when it was taken: "Today at 19:52".
// Left / Right, the wheel, a drag or a click on a side card pick; Enter or a click on the front card
// copies the picture to the clipboard (Sys.copyImage) and tags it "Copied" (a copy glyph + the word);
// Shift+Enter or a right click on it shows it in the file manager, selected (Sys.revealFile); drag the front
// card up or down out of the island to drop the file anywhere that takes one (a mail being written,
// a browser's upload area, a chat, a folder); sandboxed apps get it through the file transfer portal
// (Sys.fileTransfer, on while the panel is on screen). Each opening starts on the newest.
IslandMode {
    id: mode

    readonly property var look: Config.screenshots

    launcher: Config.screenshots.launcher
    // the panel stays open while a picture is dragged out of it
    autoClose: !Activity.draggingOut

    // the screenshots shown: Sys's list, frozen while the panel animates out
    property var shots: Sys.screenshots
    readonly property var pictures: shots.map(s => s.path)
    readonly property var ratios: shots.map(s => s.height > 0 ? s.width / s.height : 0)

    // the file transfer portal helper, while dragging out is possible
    Binding {
        target: Sys
        property: "fileTransfer"
        value: mode.onScreen && mode.look.dragOut
    }
    readonly property int count: shots.length

    readonly property real padding: Config.search.padding
    implicitWidth: 2 * padding + row.stageW
    implicitHeight: 2 * padding + row.stageH + Config.carousel.name.gap + title.implicitHeight
    readonly property bool nameOnTop: Config.carousel.name.position === "top"

    // the picture last copied (check badge); forgotten when the panel is gone
    property string copied: ""

    // byKey: Enter (close() then holds the keyboard until the key is released); a click just closes
    function copy(byKey) {
        if (count === 0)
            return;
        const path = pictures[row.selected];
        Sys.copyImage(path);
        copied = path;
        row.press();
        if (!look.copyCloses)
            return;
        if (byKey)
            close();
        else
            requestState("idle");
    }

    // "Today at 19:52", "Yesterday at 08:10", "Monday 16 November at 21:03" (screenshots.name.*)
    function when(time) {
        if (!time)
            return "";
        const d = new Date(time);
        const day = Qt.formatDate(d, "yyyy-MM-dd");
        const [y, m, dd] = Sys.today.split("-").map(Number);
        const yesterday = Qt.formatDate(new Date(y, m - 1, dd - 1), "yyyy-MM-dd");
        const dayText = day === Sys.today ? look.name.today : day === yesterday ? look.name.yesterday : Qt.formatDate(d, look.name.dateFormat);
        const timeText = Qt.formatTime(d, Sys.hour24 ? look.name.timeFormat : look.name.timeFormat12h);
        return look.name.format.replace("{day}", dayText).replace("{time}", timeText);
    }

    // show it in the file manager, selected (Shift+Enter, right click); byKey as in copy()
    function reveal(byKey) {
        if (count === 0)
            return;
        Sys.revealFile(pictures[row.selected]);
        if (!look.revealCloses)
            return;
        if (byKey)
            close();
        else
            requestState("idle");
    }

    // ---- keyboard ----
    keyTarget: mode
    Keys.onLeftPressed: row.step(-1)
    Keys.onRightPressed: row.step(1)
    Keys.onReturnPressed: event => event.modifiers & Qt.ShiftModifier ? reveal(true) : copy(true)
    Keys.onEnterPressed: event => event.modifiers & Qt.ShiftModifier ? reveal(true) : copy(true)

    // each opening lands on the newest, also when the list read on opening brings a new one (the list
    // shown at first is the previous opening's); once you've moved, a new screenshot arriving while it's
    // open keeps you on the picture you're on
    // (reacting from the carousel's own onPicturesChanged: the mode's handler ran before the carousel had
    // the new list, so its selection named the old picture)
    property bool followNewest: true
    onActiveChanged: {
        if (active) {
            followNewest = true;
            shots = Qt.binding(() => Sys.screenshots);
            Sys.refreshScreenshots();
            row.select(0, false);
        } else
            shots = shots;
    }
    // reset once fully gone, not while it animates out
    onOnScreenChanged: {
        if (!onScreen) {
            copied = "";
            row.wheelSum = 0;
        }
    }

    Item {
        id: content
        x: mode.padding
        y: mode.padding
        width: mode.implicitWidth - 2 * mode.padding
        height: mode.implicitHeight - 2 * mode.padding

        PictureCarousel {
            id: row
            y: mode.nameOnTop ? title.height + Config.carousel.name.gap : 0
            width: parent.width
            height: stageH
            availableWidth: Config.search.width - 2 * mode.padding
            ratio: Config.carousel.card.ratio > 0 ? Config.carousel.card.ratio : (mode.island && mode.island.screenHeight > 0 ? mode.island.screenWidth / mode.island.screenHeight : 1)
            pictures: mode.pictures
            ratios: mode.ratios
            minRatio: mode.look.card.minRatio
            maxRatio: mode.look.card.maxRatio
            markedPath: mode.copied
            markIcon: mode.look.copied.icon
            markLabel: mode.look.copied.label
            dragOut: mode.look.dragOut
            onActivated: mode.copy(false)
            onSecondaryActivated: mode.reveal(false)
            onPicked: mode.followNewest = false
            onPicturesChanged: if (mode.active) {
                if (mode.followNewest)
                    select(0, false);
                else
                    relocate(selectedPath);
            }

            // no screenshots yet
            StyledText {
                anchors.centerIn: parent
                visible: mode.count === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Config.colors.secondary
                text: mode.look.emptyText
            }
        }

        // when the selected one was taken, above or under the cards
        RollingName {
            id: title
            y: mode.nameOnTop ? 0 : row.height + Config.carousel.name.gap
            width: parent.width
            animate: mode.active
            text: mode.count > 0 ? mode.when((mode.shots[row.selected] || {}).time) : ""
        }
    }
}
