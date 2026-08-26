import QtQuick
import qs.Commons
import "TypingTestModel.js" as TypingTestModel

// Fixed-height viewport onto the word list — MonkeyType-style: never
// renders more than a few lines at once. Lines are computed up front
// (computeLines(), monospace-width math) and rendered as individually
// centered rows, poem-style, rather than one ragged left-aligned block.
// Time mode keeps the model bounded by trimming a completed line out of
// `words` entirely (see TypingTest.qml's trimCompletedLine(), which reads
// `lines` below to know where that boundary falls); words mode has a fixed
// total so it just scrolls instead.
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
  property int wordSpacing: 16
  property color correctColor: "white"
  property color incorrectColor: "red"
  property color pendingColor: "gray"
  property color caretColor: "white"

  // [[wordIndex, ...], ...] — recomputed whenever the word list or
  // available width changes. Exposed so the parent's trimCompletedLine()
  // can drop a whole line by index count alone, no layout geometry needed.
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

  function lineIndexFor(wordIndex) {
    for (var i = 0; i < root.lines.length; i++) {
      if (root.lines[i].indexOf(wordIndex) !== -1) return i
    }
    return -1
  }

  // Words mode only: snaps straight to the current line's top the moment
  // the cursor reaches it, so a finished line leaves the viewport as a
  // whole instead of scrolling word-by-word.
  function ensureVisible(idx) {
    var item = lineRepeater.itemAt(root.lineIndexFor(idx))
    if (!item) return
    if (item.y !== contentY) contentY = item.y
  }

  Column {
    id: wordColumn
    width: root.width
    spacing: root.lineSpacing

    // Time mode drops the completed line from `words` in one batch (see
    // trimCompletedLine()) rather than scrolling past it — this is what
    // actually animates that: remaining lines glide up into their new
    // position instead of popping there.
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
