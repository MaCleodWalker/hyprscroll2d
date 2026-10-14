import QtQuick

Item {
    id: root

    property var tiles: []
    property var grid: null
    property string workspace: ""
    property string address: ""
    property bool dragging: false
    property point pressPoint
    property point pointer
    property rect sourceBox
    readonly property real previewX: sourceBox.x + pointer.x - pressPoint.x
    readonly property real previewY: sourceBox.y + pointer.y - pressPoint.y
    readonly property var destination: dragging ? destinationAt(pointer.x, pointer.y) : null

    signal windowClicked(string address)
    signal moveRequested(string address, int col, int row)

    function cancel() {
        address = ""
        dragging = false
    }

    function begin(sourceAddress, box, point) {
        if (!enabled) return
        address = sourceAddress
        pressPoint = point
        pointer = point
        sourceBox = box
        dragging = false
    }

    function update(point) {
        if (!address) return
        pointer = point
        const dx = pointer.x - pressPoint.x
        const dy = pointer.y - pressPoint.y
        if (!dragging && dx * dx + dy * dy >= 64) {
            if (!grid) console.warn("Omalattice: the running layout has no drop grid; install the updated plugin and relaunch Hyprland")
            dragging = true
        }
    }

    function finish(point, clickAllowed) {
        if (!address) return
        update(point)
        if (dragging) {
            const target = destination
            if (target) moveRequested(address, target.col, target.row)
        } else if (clickAllowed) {
            windowClicked(address)
        }
        cancel()
    }

    function destinationAt(x, y) {
        if (!grid || !grid.columns.length || !grid.rows.length
            || grid.w <= 0 || grid.h <= 0 || x < 0 || y < 0 || x >= width || y >= height) return null
        const c = Math.max(-1, Math.min(grid.columns.length,
            Math.floor((x - grid.x + grid.gapX / 2) / (grid.w + grid.gapX))))
        const r = Math.max(-1, Math.min(grid.rows.length,
            Math.floor((y - grid.y + grid.gapY / 2) / (grid.h + grid.gapY))))
        return {
            col: c < 0 ? grid.columns[0] - 1
                : c >= grid.columns.length ? grid.columns[grid.columns.length - 1] + 1 : grid.columns[c],
            row: r < 0 ? grid.rows[0] - 1
                : r >= grid.rows.length ? grid.rows[grid.rows.length - 1] + 1 : grid.rows[r],
            x: grid.x + c * (grid.w + grid.gapX),
            y: grid.y + r * (grid.h + grid.gapY),
            w: grid.w, h: grid.h
        }
    }

    onEnabledChanged: if (!enabled) cancel()
    onWorkspaceChanged: cancel()
    onTilesChanged: {
        if (address && !tiles.some(tile => tile.address === address)) cancel()
    }

    Rectangle {
        visible: root.destination !== null
        x: root.destination ? root.destination.x : 0
        y: root.destination ? root.destination.y : 0
        width: root.destination ? root.destination.w : 0
        height: root.destination ? root.destination.h : 0
        color: "#33e8a838"
        border.color: "#e8a838"
        border.width: 3
        radius: 4
    }

}
