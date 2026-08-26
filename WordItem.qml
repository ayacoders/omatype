import QtQuick

// One word: characters colored by correctness, with any overtyped extras
// folded into the same row so they line up with everything else. The caret
// lives one level up in WordStream, so it can glide between the words of a
// line instead of restarting inside each one.
Row {
  id: root

  required property string word
  required property string typed

  property string fontFamily: "monospace"
  property int fontSize: 16
  property color correctColor: "white"
  property color incorrectColor: "red"
  property color pendingColor: "gray"

  // Grows past the word once overtyped, so those characters get real
  // positions here rather than being a separate trailing element.
  readonly property int charCount: Math.max(word.length, typed.length)

  function charAt(index) {
    return index < word.length ? word[index] : typed[index]
  }

  function statusAt(index) {
    if (index >= word.length) return "incorrect"  // overtyped: nothing to match
    if (index >= typed.length) return "pending"
    return typed[index] === word[index] ? "correct" : "incorrect"
  }

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
