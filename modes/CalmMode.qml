import QtQuick

import "../services"
import "../island"

// Calm mode: the island at rest as a small empty pill (calm.width wide, calm.shorterBy shorter than the
// resting island), like the idle Dynamic Island. Shown instead of the idle island while Activity.calm
// (calm.always, a fullscreen window with calm.fullscreen, or `qs ipc call island calm`). Hovering it
// shows the idle island (Activity.calmRevealed, after calm.revealDelay); a click shows it at once.
IslandMode {
    id: mode

    readonly property real restHeight: island ? island.restHeight : 0

    belowMinimum: true
    implicitWidth: Config.calm.width
    implicitHeight: Math.max(0, restHeight - Config.calm.shorterBy)

    TapHandler {
        onTapped: Activity.revealCalm()
    }
}
