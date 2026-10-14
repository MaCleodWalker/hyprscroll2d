pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import ".." as Plugin

Item {
    width: 1000
    height: 800

    Plugin.MinimapDrag {
        id: minimap
        anchors.fill: parent
    }

    Repeater {
        id: inputs
        model: minimap.tiles
        delegate: Plugin.MinimapInput {
            required property var modelData
            controller: minimap
            address: modelData.address
            title: "Test window"
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
        }
    }

    SignalSpy { id: clicks; target: minimap; signalName: "windowClicked" }
    SignalSpy { id: moves; target: minimap; signalName: "moveRequested" }

    TestCase {
        name: "MinimapDrag"
        when: windowShown

        function init() {
            minimap.enabled = true
            minimap.cancel()
            minimap.workspace = "workspace:9"
            minimap.grid = { x: 40, y: 100, w: 200, h: 160, gapX: 20, gapY: 20,
                columns: [0, 1, 2], rows: [0, 1] }
            minimap.tiles = [
                { address: "0xA", x: 40, y: 100, w: 200, h: 160 },
                { address: "0xB", x: 260, y: 100, w: 200, h: 160 }
            ]
            clicks.clear()
            moves.clear()
        }

        function test_click_and_small_motion() {
            mousePress(minimap, 100, 116)
            mouseMove(minimap, 104, 119)
            compare(minimap.dragging, false)
            mouseRelease(minimap, 104, 119)
            compare(clicks.count, 1)
            compare(clicks.signalArguments[0][0], "0xA")
            compare(moves.count, 0)
        }

        function test_drag_to_occupied_cell() {
            mousePress(minimap, 100, 116)
            mouseMove(minimap, 320, 160)
            compare(minimap.dragging, true)
            compare(minimap.previewX, 260)
            compare(minimap.destination.col, 1)
            mouseRelease(minimap, 320, 160)
            compare(clicks.count, 0)
            compare(moves.count, 1)
            compare(Array.from(moves.signalArguments[0]), ["0xA", 1, 0])
            compare(minimap.dragging, false)
        }

        function test_drag_to_empty_cell_and_adjacent_axes() {
            mousePress(minimap, 100, 116)
            mouseMove(minimap, 320, 340)
            compare(minimap.destination.row, 1)
            mouseRelease(minimap, 320, 340)
            compare(Array.from(moves.signalArguments[0]), ["0xA", 1, 1])
            compare(minimap.destinationAt(900, 160).col, 3)
            compare(minimap.destinationAt(0, 160).col, -1)
            compare(minimap.destinationAt(100, 0).row, -1)
            compare(minimap.destinationAt(100, 700).row, 2)
        }

        function test_drag_threshold_is_eight_pixels() {
            mousePress(minimap, 100, 116)
            mouseMove(minimap, 107, 116)
            compare(minimap.dragging, false)
            mouseMove(minimap, 108, 116)
            compare(minimap.dragging, true)
            mouseRelease(minimap, 108, 116)
            compare(clicks.count, 0)
        }

        function test_outside_drop_cancels() {
            mousePress(minimap, 100, 116)
            mouseMove(minimap, 1100, 160)
            compare(minimap.destination, null)
            mouseRelease(minimap, 1100, 160)
            compare(moves.count, 0)
            compare(clicks.count, 0)
            compare(minimap.address, "")
        }

        function test_blank_press_does_not_move_or_click() {
            mousePress(minimap, 320, 340)
            mouseMove(minimap, 100, 160)
            mouseRelease(minimap, 100, 160)
            compare(moves.count, 0)
            compare(clicks.count, 0)
        }

        function test_workspace_change_cancels() {
            mousePress(minimap, 100, 116)
            mouseMove(minimap, 320, 160)
            minimap.workspace = "workspace:10"
            mouseRelease(minimap, 320, 160)
            compare(moves.count, 0)
            compare(clicks.count, 0)
        }

        function test_source_closure_cancels() {
            mousePress(minimap, 100, 116)
            mouseMove(minimap, 320, 160)
            minimap.tiles = minimap.tiles.slice(1)
            mouseRelease(minimap, 320, 160)
            compare(moves.count, 0)
            compare(clicks.count, 0)
        }

        function test_closing_overview_cancels() {
            mousePress(minimap, 100, 116)
            mouseMove(minimap, 320, 160)
            minimap.enabled = false
            mouseRelease(minimap, 320, 160)
            compare(moves.count, 0)
            compare(clicks.count, 0)
            compare(minimap.dragging, false)
        }

        function test_scrolled_sparse_grid_and_gaps() {
            minimap.grid = { x: -180, y: 100, w: 200, h: 160, gapX: 20, gapY: 20,
                columns: [-10, 30, 70], rows: [-20, 50] }
            compare(minimap.destinationAt(100, 160).col, 30)
            compare(minimap.destinationAt(320, 340).col, 70)
            compare(minimap.destinationAt(320, 340).row, 50)
            compare(minimap.destinationAt(100, 160).x, 40)
            compare(minimap.destinationAt(249, 160).col, 30)
            compare(minimap.destinationAt(250, 160).col, 70)
            minimap.grid = null
            compare(minimap.destinationAt(100, 160), null)
        }

        function test_autoscroll_updates_target_without_moving_preview() {
            mousePress(minimap, 100, 116)
            mouseMove(minimap, 320, 160)
            compare(minimap.destination.col, 1)
            const previewX = minimap.previewX
            minimap.grid = { x: -180, y: 100, w: 200, h: 160, gapX: 20, gapY: 20,
                columns: [0, 1, 2], rows: [0, 1] }
            compare(minimap.destination.col, 2)
            compare(minimap.previewX, previewX)
            mouseRelease(minimap, 320, 160)
            compare(Array.from(moves.signalArguments[0]), ["0xA", 2, 0])
        }

        function test_body_click_enters_but_cannot_drag() {
            mouseClick(minimap, 100, 200)
            compare(clicks.count, 1)
            compare(clicks.signalArguments[0][0], "0xA")
            clicks.clear()
            mousePress(minimap, 100, 200)
            mouseMove(minimap, 320, 200)
            compare(minimap.dragging, false)
            mouseRelease(minimap, 320, 200)
            compare(moves.count, 0)
            compare(clicks.count, 0)
        }

        function test_handle_uses_rendered_frame_and_viewport_coordinates() {
            const tile = inputs.itemAt(0)
            tile.x += 15
            tile.y += 25
            tile.width = 170
            tile.height = 110
            mousePress(minimap, 100, 140)
            compare(minimap.sourceBox, Qt.rect(55, 125, 170, 110))
            mouseMove(minimap, 320, 200)
            compare(minimap.previewX, 275)
            compare(minimap.previewY, 185)
            mouseRelease(minimap, 320, 200)
            compare(Array.from(moves.signalArguments[0]), ["0xA", 1, 0])
            tile.x = Qt.binding(() => tile.modelData.x)
            tile.y = Qt.binding(() => tile.modelData.y)
            tile.width = Qt.binding(() => tile.modelData.w)
            tile.height = Qt.binding(() => tile.modelData.h)
        }

        function test_handle_without_motion_clicks_window() {
            mouseClick(minimap, 100, 116)
            compare(clicks.count, 1)
            compare(moves.count, 0)
        }

        function test_missing_runtime_grid_does_not_claim_a_move() {
            minimap.grid = null
            mousePress(minimap, 100, 116)
            ignoreWarning("Omalattice: the running layout has no drop grid; install the updated plugin and relaunch Hyprland")
            mouseMove(minimap, 320, 160)
            mouseRelease(minimap, 320, 160)
            compare(moves.count, 0)
            compare(clicks.count, 0)
        }
    }
}
