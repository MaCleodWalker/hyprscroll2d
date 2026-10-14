import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    property bool loadPending: false
    property int refreshTick: 0
    property string overviewState: "none|false"
    readonly property string overviewStatusPath: Quickshell.env("XDG_RUNTIME_DIR")
        + "/hyprscroll2d-overview"
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

    function clientsForScreen(screen, tick) {
        var ignored = tick
        var monitor = Hyprland.monitorFor(screen)
        var workspace = monitor ? monitor.activeWorkspace : null
        return workspace && workspace.toplevels ? workspace.toplevels.values : []
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
                if (message) console.warn("Hyprscroll2D:", message)
            }
        }
    }

    FileView {
        id: overviewStatus
        path: root.overviewStatusPath
        watchChanges: true
        onLoaded: root.overviewState = text().trim()
        onFileChanged: reload()
        onLoadFailed: root.overviewState = "none|false"
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
                property var status: root.overviewState.split("|")
                // Thumb start and size as fractions of each track: x start, x size, y start, y size.
                readonly property var bars: {
                    var values = status.length > 2 ? status[2].split(",").map(Number) : []
                    return values.length === 4 && values.every(isFinite) ? values : [0, 1, 0, 1]
                }
                readonly property bool workspaceMatches: !!(
                    monitor
                    && monitor.activeWorkspace
                    && (status[0] === "workspace:" + monitor.activeWorkspace.id
                        || status[0] === "workspace-name:" + monitor.activeWorkspace.name)
                )

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
                visible: status[1] === "true" && workspaceMatches
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                Rectangle {
                    id: verticalTrack
                    visible: screenOverlay.bars[3] < 1
                    x: screenOverlay.screenGeometry.width - width - 4
                    y: 8
                    width: 6
                    height: screenOverlay.screenGeometry.height - 16
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
                    id: horizontalTrack
                    visible: screenOverlay.bars[1] < 1
                    x: 8
                    y: screenOverlay.screenGeometry.height - height - 4
                    width: screenOverlay.screenGeometry.width - 16
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

                Repeater {
                    model: root.clientsForScreen(screenOverlay.targetScreen, root.refreshTick)
                        .filter(client => !!client)

                    delegate: Rectangle {
                        required property var modelData

                        property var client: modelData
                        property var windowData: client && client.lastIpcObject
                            ? client.lastIpcObject : client
                        property bool intersectsScreen: windowData
                            && windowData.at
                            && windowData.size
                            && windowData.at[0]
                                < screenOverlay.screenGeometry.x + screenOverlay.screenGeometry.width
                            && windowData.at[1]
                                < screenOverlay.screenGeometry.y + screenOverlay.screenGeometry.height
                            && windowData.at[0] + windowData.size[0]
                                > screenOverlay.screenGeometry.x
                            && windowData.at[1] + windowData.size[1]
                                > screenOverlay.screenGeometry.y

                        x: windowData && windowData.at
                            ? Math.max(8, Math.min(
                                windowData.at[0] - screenOverlay.screenGeometry.x + 8,
                                screenOverlay.screenGeometry.width - width - 8
                            )) : 8
                        y: windowData && windowData.at
                            ? Math.max(8, Math.min(
                                windowData.at[1] - screenOverlay.screenGeometry.y + 8,
                                screenOverlay.screenGeometry.height - height - 8
                            )) : 8
                        width: windowData && windowData.size
                            ? Math.max(1, Math.min(
                                windowData.size[0] - 16,
                                screenOverlay.screenGeometry.width - 16,
                                titleMeasure.implicitWidth + 24
                            )) : 1
                        height: titleText.implicitHeight + 16
                        visible: !!windowData
                            && windowData.mapped !== false
                            && intersectsScreen

                        radius: 5
                        color: "#dd171923"

                        // Unwrapped copy used only to size the label to its text.
                        Text {
                            id: titleMeasure
                            visible: false
                            text: titleText.text
                            font: titleText.font
                        }

                        Text {
                            id: titleText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            text: windowData ? windowData.title || windowData.class || "" : ""
                            color: "#f4f4f5"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                    }
                }
            }
        }
    }
}
