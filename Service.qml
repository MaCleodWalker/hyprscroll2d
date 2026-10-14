import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    property bool loadPending: false
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

    Component.onCompleted: loadTimer.start()

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event && event.name === "configreloaded") loadTimer.restart()
        }
    }

    Timer {
        id: loadTimer
        interval: 150
        onTriggered: root.loadLayout()
    }

    Process {
        id: loader

        onRunningChanged: {
            if (!running && root.loadPending) {
                root.loadPending = false
                loadTimer.restart()
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
    }

    Repeater {
        model: Quickshell.screens

        delegate: Item {
            id: screenDelegate

            required property var modelData
            property var targetScreen: modelData

            Repeater {
                model: Hyprland.toplevels.values

                delegate: PanelWindow {
                    id: titleOverlay

                    required property var modelData
                    property var client: modelData
                    property rect screenGeometry: Qt.rect(
                        screenDelegate.targetScreen.x,
                        screenDelegate.targetScreen.y,
                        screenDelegate.targetScreen.width,
                        screenDelegate.targetScreen.height
                    )
                    property var status: overviewStatus.text().trim().split("|")

                    readonly property bool workspaceMatches:
                        client.workspace
                        && (status[0] === "workspace:" + client.workspace.id
                            || status[0] === "workspace-name:" + client.workspace.name)

                    screen: screenDelegate.targetScreen
                    anchors {
                        top: true
                        left: true
                    }
                    margins {
                        top: client.at ? client.at.y - screenGeometry.y + 8 : 0
                        left: client.at ? client.at.x - screenGeometry.x + 8 : 0
                    }
                    width: client.size
                        ? Math.max(1, Math.min(client.size.x - 16, titleText.implicitWidth + 24))
                        : 1
                    height: 30
                    visible: status[1] === "true"
                        && workspaceMatches
                        && client.mapped
                        && client.at
                        && client.size
                        && client.at.x < screenGeometry.x + screenGeometry.width
                        && client.at.y < screenGeometry.y + screenGeometry.height
                        && client.at.x + client.size.x > screenGeometry.x
                        && client.at.y + client.size.y > screenGeometry.y

                    color: "transparent"
                    exclusiveZone: 0
                    focusable: false
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: "#dd171923"

                        Text {
                            id: titleText
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            text: client.title || client.appId || ""
                            color: "#f4f4f5"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
