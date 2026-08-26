import QtQuick
import qs.Commons

// Mode + duration/word-count chip row. Purely presentational — it just
// reflects the state it's given and signals intent back to the parent,
// which owns setMode()/setTimeOption()/setWordsOption() (and their
// mid-run no-ops). Also driven from the parent's Up/Down/Left/Right
// keyboard handling, so every chip here has a keyboard equivalent too.
Row {
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
  property int cornerRadius: 0

  signal modeSelected(string mode)
  signal timeSelected(int value)
  signal wordsSelected(int value)

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
    visible: root.testMode === "time"

    Repeater {
      model: root.timeOptions
      delegate: Chip {
        required property int modelData
        label: String(modelData)
        selected: root.timeOption === modelData
        onActivated: root.timeSelected(modelData)
      }
    }
  }

  Row {
    spacing: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    visible: root.testMode === "words"

    Repeater {
      model: root.wordsOptions
      delegate: Chip {
        required property int modelData
        label: String(modelData)
        selected: root.wordsOption === modelData
        onActivated: root.wordsSelected(modelData)
      }
    }
  }
}
