import QtQuick

// An image that keeps the previous picture until the next one has loaded: two Images take turns, so a
// new source (the next track's cover) never leaves an empty frame (an Image goes blank while it loads).
// Its Images are hidden: draw `current` through an effect (MultiEffect { source: swap.current }).
// No source / a failed load switches at once (ready goes false).
Item {
    id: swap

    property url source
    property size sourceSize
    property int fillMode: Image.PreserveAspectCrop
    property bool mipmap: false

    property bool useB: false
    readonly property Image current: useB ? b : a
    readonly property Image next: useB ? a : b
    readonly property bool ready: current.status === Image.Ready && current.source.toString() !== ""
    // the loaded picture's width / height (1 without one)
    readonly property real ratio: ready && current.implicitHeight > 0 ? current.implicitWidth / current.implicitHeight : 1

    onSourceChanged: {
        next.source = source;
        check();
    }
    function check() {
        if (next.source.toString() !== source.toString() || next.source.toString() === current.source.toString())
            return;
        if (source.toString() === "" || next.status === Image.Ready || next.status === Image.Error)
            useB = !useB;
    }

    Image {
        id: a
        anchors.fill: parent
        visible: false
        sourceSize: swap.sourceSize
        fillMode: swap.fillMode
        asynchronous: true
        smooth: true
        mipmap: swap.mipmap
        onStatusChanged: swap.check()
    }
    Image {
        id: b
        anchors.fill: parent
        visible: false
        sourceSize: swap.sourceSize
        fillMode: swap.fillMode
        asynchronous: true
        smooth: true
        mipmap: swap.mipmap
        onStatusChanged: swap.check()
    }
}
