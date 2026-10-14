import QtQuick
import qs.Ui
import qs.Commons

// One setting in the menu: a label with a -/+ stepper, or an on/off switch.
Item {
  id: root

  property string label: ""
  property string note: ""
  property bool isToggle: false
  property bool checked: false
  property real value: 0
  property real from: 0
  property real to: 100
  property real step: 1
  // Shown value = value * displayScale, so fractions can read as percentages.
  property real displayScale: 1
  property string suffix: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal edited(var newValue)

  function stepBy(direction) {
    var shown = Math.round(root.value * root.displayScale * 1000) / 1000
    var next = Math.max(root.from * root.displayScale, Math.min(root.to * root.displayScale, shown + direction * root.step))
    root.edited(Math.round(next / root.displayScale * 10000) / 10000)
  }

  implicitHeight: Math.max(labelColumn.implicitHeight, Style.space(28))

  Column {
    id: labelColumn
    anchors.left: parent.left
    anchors.right: controls.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter

    Text {
      width: parent.width
      text: root.label
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: root.note !== ""
      text: root.note
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Item {
    id: controls
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: root.isToggle ? toggle.width : stepper.width
    height: Style.space(28)

    ToggleSwitch {
      id: toggle
      visible: root.isToggle
      anchors.verticalCenter: parent.verticalCenter
      checked: root.checked
      onToggled: root.edited(!root.checked)
    }

    Row {
      id: stepper
      visible: !root.isToggle
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Button {
        text: "−"
        enabled: root.value > root.from
        fontFamily: root.fontFamily
        onClicked: root.stepBy(-1)
      }

      Text {
        width: Style.space(52)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: Math.round(root.value * root.displayScale) + root.suffix
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Button {
        text: "+"
        enabled: root.value < root.to
        fontFamily: root.fontFamily
        onClicked: root.stepBy(1)
      }
    }
  }
}
