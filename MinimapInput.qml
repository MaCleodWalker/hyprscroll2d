import QtQuick

Item {
    id: root

    required property MinimapDrag controller
    required property string address
    property string title: ""
    enabled: controller.enabled

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        property point pressPoint
        onPressed: mouse => pressPoint = Qt.point(mouse.x, mouse.y)
        onReleased: mouse => {
            const dx = mouse.x - pressPoint.x
            const dy = mouse.y - pressPoint.y
            if (containsMouse && dx * dx + dy * dy < 64)
                root.controller.windowClicked(root.address)
        }
    }

    Rectangle {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.min(root.height, Math.max(28, titleText.implicitHeight + 12))
        color: "#dd171923"

        Text {
            id: titleText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            text: root.title
            textFormat: Text.PlainText
            color: "#f4f4f5"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        MouseArea {
            id: handle
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            cursorShape: pressed && root.controller.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            onPressed: mouse => {
                const origin = root.mapToItem(root.controller, 0, 0)
                root.controller.begin(root.address, Qt.rect(origin.x, origin.y, root.width, root.height),
                    handle.mapToItem(root.controller, mouse.x, mouse.y))
            }
            onPositionChanged: mouse => {
                if (pressed) root.controller.update(handle.mapToItem(root.controller, mouse.x, mouse.y))
            }
            onReleased: mouse => root.controller.finish(
                handle.mapToItem(root.controller, mouse.x, mouse.y), containsMouse)
            onCanceled: root.controller.cancel()
        }
    }
}
