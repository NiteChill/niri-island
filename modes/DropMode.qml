import QtQuick

import "../services"
import "../island"
import "../widgets"

// The notch while something is dragged over it (Activity.dropping, shell.qml's dropZone): a small,
// inviting drop zone (island.drop.*, widgets/DropZone), not the whole shelf: a dashed rounded outline, a
// download arrow that bobs gently, "Drop to keep it" and, in grey, where it will go (the shelf's folder).
// Dropped, the shelf opens on what came in (Activity, Sys.shelfAdded). The empty shelf is the same zone,
// muted.
IslandMode {
    id: mode

    readonly property var look: Config.island.drop

    belowMinimum: true
    implicitWidth: look.width
    implicitHeight: look.height

    DropZone {
        anchors.fill: parent
        running: mode.onScreen
        outerCorner: Config.corner(Config.attached ? "attached" : "island", mode.height)
        text: mode.look.text
        caption: mode.look.caption.arg(Config.shelf.folder.replace(/\/+$/, "").split("/").pop())
    }
}
