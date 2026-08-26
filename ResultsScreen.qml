import QtQuick
import qs.Commons

// End-of-run stats, filling the whole (much taller) results card: the
// numbers sit centered in the middle of it, and the restart/close hint is
// pinned to the very bottom rather than crowding up under the stats.
// Tab/Shift+Tab/Enter restart and Esc closes, but all of that is handled by
// the parent's single key catcher, not here.
Item {
  id: root

  required property real wpm
  required property real accuracy
  required property real rawWpm
  required property real consistency
  required property int correctChars
  required property int incorrectChars
  required property real time

  property string fontFamily: "sans-serif"
  property string monoFontFamily: "monospace"
  property color foreground: "white"
  property color accent: "white"
  property color mutedText: "gray"

  component Stat: Column {
    id: stat
    required property string label
    required property string value
    property int valueSize: Style.font.display
    property color valueColor: root.foreground
    spacing: Style.spacing.sm

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: stat.label
      color: root.mutedText
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: stat.value
      color: stat.valueColor
      font.family: root.monoFontFamily
      font.pixelSize: stat.valueSize
      font.bold: true
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(56)

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(96)

      Stat { label: "wpm"; value: Math.round(root.wpm) + ""; valueSize: Style.font.displayLarge * 2; valueColor: root.accent }
      Stat { label: "accuracy"; value: Math.round(root.accuracy) + "%"; valueSize: Style.font.displayLarge * 2 }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(64)

      Stat { label: "raw wpm"; value: Math.round(root.rawWpm) + "" }
      Stat { label: "consistency"; value: Math.round(root.consistency) + "%" }
      Stat { label: "characters"; value: root.correctChars + " / " + root.incorrectChars }
      Stat { label: "time"; value: root.time.toFixed(1) + "s" }
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    text: "Tab: new words  ·  Shift+Tab: same words  ·  Esc: close"
    color: root.mutedText
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
