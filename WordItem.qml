import QtQuick
import qs.Commons

// One word: characters colored by correctness, with any overtyped extras
// folded into the same row so the caret can track through them.
//
// Plain Item rather than Row, because the caret sets its own x and
// positioners fight that (reassigning it every relayout, which surfaces as a
// binding loop). charRow lays out the characters; the caret is its sibling.
Item {
  id: root

  required property string word
  required property string typed
  required property bool isCurrent

  property string fontFamily: "monospace"
  property int fontSize: 16
  property color correctColor: "white"
  property color incorrectColor: "red"
  property color pendingColor: "gray"
  property color caretColor: "white"

  readonly property int caretIndex: typed.length
  // Grows past the word once overtyped, so those characters get real
  // positions in charRow instead of being a separate trailing element.
  readonly property int charCount: Math.max(word.length, typed.length)

  function charAt(index) {
    return index < word.length ? word[index] : typed[index]
  }

  function statusAt(index) {
    if (index >= word.length) return "incorrect"  // overtyped: nothing to match
    if (index >= typed.length) return "pending"
    return typed[index] === word[index] ? "correct" : "incorrect"
  }

  width: charRow.width
  height: charRow.height

  Row {
    id: charRow

    Repeater {
      model: root.charCount
      delegate: Text {
        required property int index
        readonly property string status: root.statusAt(index)

        text: root.charAt(index)
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        color: status === "correct" ? root.correctColor
          : status === "incorrect" ? root.incorrectColor
          : root.pendingColor

        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }
  }

  Rectangle {
    visible: root.isCurrent
    width: Math.max(2, Style.space(3))
    height: charRow.height
    radius: width / 2
    color: root.caretColor

    // Monospace, so every character advances the same width — derive the
    // caret's offset arithmetically rather than reading a delegate's
    // geometry, which QML wouldn't re-evaluate reliably. caretIndex ==
    // charCount (whole word typed) parks it just past the last character.
    x: root.charCount === 0 ? 0 : root.caretIndex * (charRow.width / root.charCount)

    Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
  }
}
