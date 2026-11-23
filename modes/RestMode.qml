import QtQuick

import "../services"
import "../island"

// The notch at rest: a small empty black shape (island.rest.width x island.rest.height), like a MacBook's
// notch or the iPhone's resting Dynamic Island. It's what the notch shows when nothing happens.
// A click opens it on the player or the shelf (Activity.openNotch); no hover effect (it made the music's
// cover and bars jump while the notch eased to the new width).
IslandMode {
    id: mode

    readonly property var look: Config.island.rest

    belowMinimum: true
    implicitWidth: look.width
    implicitHeight: look.height

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: Activity.openNotch()
    }
}
