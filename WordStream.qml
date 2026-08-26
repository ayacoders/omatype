import QtQuick
import qs.Commons
import "TypingTestModel.js" as TypingTestModel

// Fixed-height viewport onto the word list, wrapped into individually
// centered lines (poem-style) rather than one ragged left-aligned block.
// Time mode stays bounded by trimming completed lines out of `words`
// upstream; words mode has a fixed total and scrolls instead.
Flickable {
  id: root

  required property var words
  required property var submittedWords
  required property int currentWordIndex
  required property string currentInput
  required property bool isDone

  property string fontFamily: "monospace"
  property int fontSize: 16
  property int lineSpacing: 8
  property int wordSpacing: lineSpacing
  property color correctColor: "white"
  property color incorrectColor: "red"
  property color pendingColor: "gray"
  property color caretColor: "white"

  // [[wordIndex, ...], ...], contiguous and in order. Recomputed only when
  // the word list or width changes — not per keystroke.
  readonly property var lines: TypingTestModel.computeLines(
    root.words, fontMetrics.advanceWidth("0"), root.wordSpacing, root.width)

  FontMetrics {
    id: fontMetrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  clip: true
  contentHeight: wordColumn.height
  boundsBehavior: Flickable.StopAtBounds
  Behavior on contentY { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  function typedFor(index) {
    if (index < root.currentWordIndex) return root.submittedWords[index] || ""
    if (index === root.currentWordIndex) return root.currentInput
    return ""
  }

  function scrollToTop() { contentY = 0 }

  // Lines partition the word indices contiguously, so walking cumulative
  // lengths finds the owning line without scanning each line's contents.
  // -1 when the index is past the end.
  function lineIndexFor(wordIndex) {
    var end = 0
    for (var i = 0; i < root.lines.length; i++) {
      end += root.lines[i].length
      if (wordIndex < end) return i
    }
    return -1
  }

  // Words mode only: snaps to the current line's top as the cursor reaches
  // it, so a finished line leaves the viewport whole.
  function ensureVisible(idx) {
    var item = lineRepeater.itemAt(root.lineIndexFor(idx))
    if (item && item.y !== contentY) contentY = item.y
  }

  Column {
    id: wordColumn
    width: root.width
    spacing: root.lineSpacing

    // Time mode drops a completed line from the model rather than scrolling
    // past it; this glides the survivors up instead of popping them.
    move: Transition {
      NumberAnimation { property: "y"; duration: 180; easing.type: Easing.OutCubic }
    }

    Repeater {
      id: lineRepeater
      model: root.lines

      delegate: Row {
        id: lineRow
        required property var modelData

        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.wordSpacing

        Repeater {
          model: lineRow.modelData

          delegate: WordItem {
            required property int modelData
            word: root.words[modelData] || ""
            typed: root.typedFor(modelData)
            isCurrent: modelData === root.currentWordIndex && !root.isDone

            fontFamily: root.fontFamily
            fontSize: root.fontSize
            correctColor: root.correctColor
            incorrectColor: root.incorrectColor
            pendingColor: root.pendingColor
            caretColor: root.caretColor
          }
        }
      }
    }
  }
}
