import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    property bool loadPending: false
    property int refreshTick: 0
    readonly property var closedOverview: ({ workspace: "none", overview: false })
    property var overview: closedOverview
    readonly property string overviewStatusPath: Quickshell.env("XDG_RUNTIME_DIR")
        + "/omalattice-overview"
    // How far a touchpad swipe has opened the overview, written by the layout.
    readonly property var idleSwipe: ({ progress: 0, dragging: false })
    property var swipe: idleSwipe
    readonly property string wallpaperUrl: "file://" + Quickshell.env("HOME")
        + "/.local/state/omarchy/current/background"
    readonly property string bootstrapPath: decodeURIComponent(
        Qt.resolvedUrl("integration/plugin.lua").toString().replace(/^file:\/\//, "")
    )

    function luaQuote(value) {
        return "\"" + value
            .replace(/\\/g, "\\\\")
            .replace(/\"/g, "\\\"")
            .replace(/\n/g, "\\n")
            .replace(/\r/g, "\\r") + "\""
    }

    function loadLayout() {
        if (loader.running) {
            root.loadPending = true
            return
        }
        loader.command = ["hyprctl", "eval", "dofile(" + root.luaQuote(root.bootstrapPath) + ")"]
        loader.running = true
    }

    function refreshLayout() {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        refreshTick += 1
    }

    function parseOverview(text) {
        try {
            const value = JSON.parse(text)
            return value && typeof value === "object" ? value : root.closedOverview
        } catch (error) {
            return root.closedOverview
        }
    }

    function parseSwipe(text) {
        try {
            const value = JSON.parse(text)
            if (!value || typeof value.progress !== "number") return root.idleSwipe
            return { progress: Math.max(0, Math.min(1, value.progress)), dragging: value.dragging === true }
        } catch (error) {
            return root.idleSwipe
        }
    }

    // Hyprland reports addresses with and without the 0x prefix; keep hex digits only.
    function normalizeAddress(address) {
        return String(address || "").replace(/^0x/, "").replace(/[^0-9a-fA-F]/g, "")
    }

    function toplevelFor(address, tick) {
        var ignored = tick
        var wanted = root.normalizeAddress(address)
        var values = Hyprland.toplevels.values
        for (var index = 0; index < values.length; index++) {
            if (values[index] && root.normalizeAddress(values[index].address) === wanted) return values[index]
        }
        return null
    }

    // Clicking a thumbnail enters that window and closes the overview.
    function enterWindow(address) {
        Quickshell.execDetached([
            "hyprctl", "eval",
            "hl.dispatch(hl.dsp.focus({ window = \"address:0x" + root.normalizeAddress(address) + "\" }))"
                + " hl.dispatch(hl.dsp.layout(\"overview-exit click\"))"
        ])
    }

    Component.onCompleted: {
        refreshLayout()
        loadTimer.start()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event && event.name === "configreloaded") loadTimer.restart()
            const name = event && event.name ? event.name : ""
            if (name === "workspace" || name === "focusedmon" || name === "openwindow"
                || name === "closewindow" || name === "movewindow" || name === "activewindow") {
                root.refreshLayout()
            }
        }
    }

    Timer {
        id: loadTimer
        interval: 150
        onTriggered: root.loadLayout()
    }

    Timer {
        interval: 180
        repeat: true
        running: true
        onTriggered: root.refreshLayout()
    }

    Process {
        id: loader

        onRunningChanged: {
            if (!running) {
                overviewStatus.reload()
                if (root.loadPending) {
                    root.loadPending = false
                    loadTimer.restart()
                }
            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const message = text.trim()
                if (message) console.warn("Omalattice:", message)
            }
        }
    }

    FileView {
        id: overviewStatus
        path: root.overviewStatusPath
        watchChanges: true
        onLoaded: {
            root.overview = root.parseOverview(text())
            // The swipe file may appear after the shell starts, before it can be watched.
            overviewSwipe.reload()
        }
        onFileChanged: reload()
        onLoadFailed: root.overview = root.closedOverview
    }

    FileView {
        id: overviewSwipe
        path: root.overviewStatusPath + "-progress"
        watchChanges: true
        onLoaded: root.swipe = root.parseSwipe(text())
        onFileChanged: reload()
        onLoadFailed: root.swipe = root.idleSwipe
    }

    Variants {
        model: Quickshell.screens.filter(screen => !!screen)

        delegate: Component {
            PanelWindow {
                id: screenOverlay
                required property var modelData

                property var targetScreen: modelData
                readonly property var monitor: {
                    var ignored = root.refreshTick
                    return Hyprland.monitorFor(targetScreen)
                }
                property rect screenGeometry: Qt.rect(
                    targetScreen.x,
                    targetScreen.y,
                    targetScreen.width,
                    targetScreen.height
                )
                readonly property var liveOverview: root.overview
                // The latest overview with thumbnails, kept while it closes so they
                // can shrink back into their windows.
                property var shownOverview: null
                readonly property var overview: shownOverview || liveOverview

                function onThisScreen(status) {
                    return !!(status && monitor && monitor.activeWorkspace
                        && (status.workspace === "workspace:" + monitor.activeWorkspace.id
                            || status.workspace === "workspace-name:" + monitor.activeWorkspace.name))
                }

                readonly property bool active: liveOverview.overview === true && onThisScreen(liveOverview)
                readonly property bool shownHere: onThisScreen(shownOverview)
                // A swipe sets the progress directly; otherwise it animates to open or closed.
                readonly property bool dragging: root.swipe.dragging === true && shownHere
                // 0 draws each window where it is, 1 draws it as its overview tile.
                property real progress: 0
                readonly property var tiles: shownHere && overview.thumbnails === true && overview.tiles
                    ? overview.tiles : []

                function syncProgress() {
                    if (dragging) {
                        settle.stop()
                        progress = root.swipe.progress
                        return
                    }
                    const goal = active ? 1 : 0
                    if (progress === goal && !settle.running) {
                        // A swipe that ends fully closed still waits for the windows.
                        if (!active && shownOverview) linger.restart()
                        return
                    }
                    settle.to = goal
                    settle.restart()
                }

                onLiveOverviewChanged: {
                    // A closed status keeps its tiles on disk, so only follow it while
                    // the overlay is still showing; a later reload must not bring it back.
                    if (liveOverview.thumbnails === true && liveOverview.tiles
                        && (liveOverview.overview === true || shownOverview !== null)) {
                        shownOverview = liveOverview
                    }
                    syncProgress()
                }
                onActiveChanged: syncProgress()
                onDraggingChanged: syncProgress()
                onProgressChanged: if (!active && !dragging && progress <= 0) linger.restart()

                Connections {
                    target: root
                    function onSwipeChanged() { screenOverlay.syncProgress() }
                }

                NumberAnimation {
                    id: settle
                    target: screenOverlay
                    property: "progress"
                    duration: 260
                    easing.type: Easing.OutCubic
                }

                // The windows slide back under the closed overview, so keep covering
                // them a moment longer.
                Timer {
                    id: linger
                    interval: 160
                    onTriggered: if (!screenOverlay.active && !screenOverlay.dragging) screenOverlay.shownOverview = null
                }

                readonly property var bars: overview.bars && overview.bars.length === 4
                    ? overview.bars : [0, 1, 0, 1]
                // The tiled area of the screen, in this screen's coordinates.
                readonly property rect area: overview.area
                    ? Qt.rect(overview.area.x - screenGeometry.x, overview.area.y - screenGeometry.y,
                        overview.area.w, overview.area.h)
                    : Qt.rect(0, 0, screenGeometry.width, screenGeometry.height)

                screen: targetScreen
                color: "transparent"
                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }
                exclusiveZone: -1
                focusable: false
                visible: active || dragging || progress > 0 || linger.running
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                // Only the thumbnail area takes input, and only while thumbnails are drawn.
                mask: Region {
                    x: screenOverlay.area.x
                    y: screenOverlay.area.y
                    width: screenOverlay.active && screenOverlay.tiles.length > 0 ? screenOverlay.area.width : 0
                    height: screenOverlay.active && screenOverlay.tiles.length > 0 ? screenOverlay.area.height : 0
                }

                Item {
                    id: viewport
                    x: screenOverlay.area.x
                    y: screenOverlay.area.y
                    width: screenOverlay.area.width
                    height: screenOverlay.area.height
                    clip: true

                    // The windows are stacked underneath for capture, so redraw the wallpaper
                    // over them the way Omarchy's background does.
                    Rectangle {
                        anchors.fill: parent
                        visible: screenOverlay.tiles.length > 0 && wallpaper.status !== Image.Ready
                        color: "#101216"
                    }

                    Image {
                        id: wallpaper
                        visible: screenOverlay.tiles.length > 0
                        x: -viewport.x
                        y: -viewport.y
                        width: screenOverlay.screenGeometry.width
                        height: screenOverlay.screenGeometry.height
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        source: screenOverlay.tiles.length > 0 ? root.wallpaperUrl : ""
                    }

                    // Each thumbnail grows out of its window as the overview opens and
                    // shrinks back into it as it closes.
                    Item {
                        id: tileLayer
                        anchors.fill: parent

                        Repeater {
                            // Delegates are kept while the window count is unchanged, so
                            // their captures keep running as the tiles move.
                            model: screenOverlay.tiles.length

                            delegate: Item {
                                id: cell
                                required property int index

                                readonly property var modelData: screenOverlay.tiles[index] || ({})
                                readonly property real t: screenOverlay.progress
                                readonly property real fromX: modelData.fx !== undefined ? modelData.fx : modelData.x
                                readonly property real fromY: modelData.fy !== undefined ? modelData.fy : modelData.y
                                readonly property real fromW: modelData.fw !== undefined ? modelData.fw : modelData.w
                                readonly property real fromH: modelData.fh !== undefined ? modelData.fh : modelData.h
                                readonly property var toplevel: root.toplevelFor(modelData.address, root.refreshTick)
                                readonly property var info: toplevel && toplevel.lastIpcObject
                                    ? toplevel.lastIpcObject : null
                                readonly property bool selected: !!Hyprland.activeToplevel
                                    && root.normalizeAddress(Hyprland.activeToplevel.address)
                                        === root.normalizeAddress(modelData.address)

                                x: fromX + (modelData.x - fromX) * t - screenOverlay.overview.area.x
                                y: fromY + (modelData.y - fromY) * t - screenOverlay.overview.area.y
                                width: fromW + (modelData.w - fromW) * t
                                height: fromH + (modelData.h - fromH) * t

                                // The thumbnail keeps the window's proportions inside its cell.
                                Item {
                                    id: frame
                                    readonly property real fit: shot.hasContent
                                        && shot.sourceSize.width > 0 && shot.sourceSize.height > 0
                                        ? Math.min(cell.width / shot.sourceSize.width, cell.height / shot.sourceSize.height)
                                        : 0
                                    width: fit > 0 ? shot.sourceSize.width * fit : cell.width
                                    height: fit > 0 ? shot.sourceSize.height * fit : cell.height
                                    anchors.centerIn: parent

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#1b1e28"
                                    }

                                    ScreencopyView {
                                        id: shot
                                        anchors.fill: parent
                                        live: true
                                        captureSource: cell.toplevel ? cell.toplevel.wayland : null
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        opacity: cell.t
                                        radius: 4
                                        color: "transparent"
                                        border.width: cell.selected ? 3 : 1
                                        border.color: cell.selected ? "#e8a838" : "#55ffffff"
                                    }

                                    Rectangle {
                                        id: titleBar
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        height: titleText.implicitHeight + 12
                                        opacity: cell.t
                                        color: "#dd171923"

                                        Text {
                                            id: titleText
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            text: cell.info ? cell.info.title || cell.info.class || "" : ""
                                            color: "#f4f4f5"
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.enterWindow(cell.modelData.address)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: screenOverlay.bars[3] < 1
                        opacity: screenOverlay.progress
                        x: parent.width - width - 4
                        y: 8
                        width: 6
                        height: parent.height - 16
                        radius: 3
                        color: "#55171923"

                        Rectangle {
                            width: parent.width
                            y: screenOverlay.bars[2] * parent.height
                            height: Math.max(24, screenOverlay.bars[3] * parent.height)
                            radius: 3
                            color: "#ccf4f4f5"
                        }
                    }

                    Rectangle {
                        visible: screenOverlay.bars[1] < 1
                        opacity: screenOverlay.progress
                        x: 8
                        y: parent.height - height - 4
                        width: parent.width - 16
                        height: 6
                        radius: 3
                        color: "#55171923"

                        Rectangle {
                            height: parent.height
                            x: screenOverlay.bars[0] * parent.width
                            width: Math.max(24, screenOverlay.bars[1] * parent.width)
                            radius: 3
                            color: "#ccf4f4f5"
                        }
                    }
                }
            }
        }
    }
}
