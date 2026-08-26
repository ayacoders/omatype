import QtQuick
import qs.Commons

// Mode + option chips with a keybinding legend underneath. Presentational
// only: it reflects the state it's given and signals intent back to the
// parent, which owns the setters and their mid-run no-ops. Every chip has a
// keyboard equivalent (the parent's arrow keys); the legend advertises it.
Column {
  id: root

  required property string testMode
  required property int timeOption
  required property int wordsOption
  required property var timeOptions
  required property var wordsOptions
  required property bool running

  property string fontFamily: "sans-serif"
  property color foreground: "white"
  property color border: "gray"
  property color selectedBg: "gray"
  property color accent: "white"
  property color mutedText: Qt.rgba(1, 1, 1, 0.4)
  property int cornerRadius: 0

  signal modeSelected(string mode)
  // The parent knows which mode is active, so one signal covers both the
  // duration and word-count chips.
  signal optionSelected(int value)

  readonly property bool timed: root.testMode === "time"

  spacing: Style.spacing.sm
  opacity: root.running ? 0.35 : 1
  enabled: !root.running

  Behavior on opacity { NumberAnimation { duration: 150 } }

  component Chip: Rectangle {
    id: chip
    required property string label
    required property bool selected
    signal activated()

    width: chipLabel.implicitWidth + Style.spacing.xxl * 2
    height: Style.space(36)
    radius: root.cornerRadius
    color: chip.selected ? root.selectedBg : "transparent"

    Text {
      id: chipLabel
      anchors.centerIn: parent
      text: chip.label
      color: chip.selected ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea { anchors.fill: parent; onClicked: chip.activated() }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.spacing.huge

    Row {
      spacing: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter

      Repeater {
        model: ["time", "words"]
        delegate: Chip {
          required property string modelData
          label: modelData
          selected: root.testMode === modelData
          onActivated: root.modeSelected(modelData)
        }
      }
    }

    Rectangle {
      width: 1
      height: Style.space(22)
      color: root.border
      anchors.verticalCenter: parent.verticalCenter
    }

    Row {
      spacing: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter

      Repeater {
        model: root.timed ? root.timeOptions : root.wordsOptions
        delegate: Chip {
          required property int modelData
          label: String(modelData)
          selected: modelData === (root.timed ? root.timeOption : root.wordsOption)
          onActivated: root.optionSelected(modelData)
        }
      }
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: "↑ ↓ switch mode  ·  ← → change option"
    color: root.mutedText
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
