pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// The wallpaper picker, grown out of the notch (the logo's menu, the launcher, IPC): the pictures of the
// wallpaper folder (Sys.wallpapers) in a PictureCarousel (cards in the screen's proportions; its look and
// motion are `carousel.*`, shared with the shelf).
// The wallpaper in use wears the check badge; the selected picture's name sits above the cards, or under
// them (carousel.name.position), and rolls when it changes.
// Left / Right (or the wheel, a drag, a click on a side card) pick; Enter (or a click on the front card)
// applies it (Sys.setWallpaper: the desktop Settings app's own swaybg line, so the app agrees). Past the
// ends the row bumps. Each opening starts on the wallpaper in use.
IslandMode {
    id: mode

    readonly property var look: Config.wallpaper

    launcher: Config.wallpaper.launcher

    // the pictures shown: Sys's list, frozen while the panel animates out
    property var pictures: Sys.wallpapers
    readonly property int count: pictures.length

    // the launcher's width and padding (search.width / padding)
    readonly property real padding: Config.search.padding
    implicitWidth: 2 * padding + row.stageW
    implicitHeight: 2 * padding + row.stageH + Config.carousel.name.gap + title.implicitHeight
    readonly property bool nameOnTop: Config.carousel.name.position === "top"

    // fresh openings land on the wallpaper in use (until the user picks another)
    property bool followCurrent: true

    // the list changed (or the panel opened): find the selection again by its picture, jumping
    function relocate() {
        row.relocate(followCurrent ? Sys.wallpaper : row.selectedPath);
    }
    Connections {
        target: Sys
        function onWallpaperChanged() {
            if (mode.active && mode.followCurrent)
                mode.relocate();
        }
    }

    // byKey: Enter (close() then holds the keyboard until the key is released); a click just closes
    function apply(byKey) {
        if (count === 0)
            return;
        Sys.setWallpaper(pictures[row.selected]);
        row.press();
        if (!look.applyCloses)
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
    Keys.onReturnPressed: apply(true)
    Keys.onEnterPressed: apply(true)

    onActiveChanged: {
        if (active) {
            pictures = Qt.binding(() => Sys.wallpapers);
            Sys.refreshWallpapers();
            relocate();
        } else
            pictures = pictures;
    }
    // reset once fully gone, not while it animates out
    onOnScreenChanged: {
        if (!onScreen) {
            followCurrent = true;
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
            // cards in the screen's proportions (or carousel.card.ratio)
            ratio: Config.carousel.card.ratio > 0 ? Config.carousel.card.ratio : (mode.island && mode.island.screenHeight > 0 ? mode.island.screenWidth / mode.island.screenHeight : 1)
            pictures: mode.pictures
            markedPath: Sys.wallpaper
            onPicked: mode.followCurrent = false
            // (here, not on the mode: the carousel must already have the new list)
            onPicturesChanged: if (mode.active)
                mode.relocate()
            onActivated: mode.apply(false)

            // an empty folder
            StyledText {
                anchors.centerIn: parent
                visible: mode.count === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: palette.placeholderText
                text: mode.look.emptyText
            }
        }

        // the selected picture's name, above or under the cards
        RollingName {
            id: title
            y: mode.nameOnTop ? 0 : row.height + Config.carousel.name.gap
            width: parent.width
            animate: mode.active
            text: {
                const path = mode.count > 0 ? mode.pictures[row.selected] || "" : "";
                let name = path.split("/").pop().replace(/\.[^.]+$/, "");
                if (mode.look.name.tidy && name !== "") {
                    name = name.replace(/[-_]+/g, " ").trim();
                    name = name.charAt(0).toUpperCase() + name.slice(1);
                }
                return name;
            }
        }
    }
}
