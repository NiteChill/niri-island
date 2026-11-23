import QtQuick

// A HoverHandler that only reports real moves of the pointer (`moved`, with the position in its item): rows
// change and lists scroll under a still pointer, and a still pointer must leave the keyboard in charge (a
// key moves the selection; only the pointer's next move takes it back). Compares the scene position.
HoverHandler {
    id: handler

    signal moved(point position)

    property point _lastScene: Qt.point(-1, -1)
    onPointChanged: {
        const s = point.scenePosition;
        if (!hovered || (s.x === _lastScene.x && s.y === _lastScene.y))
            return;
        _lastScene = s;
        moved(point.position);
    }
}
