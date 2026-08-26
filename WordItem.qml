import QtQuick
import qs.Commons

// A single word in the stream: characters colored by correctness against
// what's actually been typed, any overtyped "extra" characters folded into
// the same character row (not a separate element — see charAt()/statusAt(),
// and why that matters below), and a blinking | caret when this is the word
// being typed.
//
// Plain Item, not Row: the caret needs to sit at an arbitrary x within the
// word, and Row/Column positioners fight any child that sets its own x
// (they reassign it every relayout, which shows up as a binding-loop
// warning). charRow below handles the actual character layout; the caret
// is a free-positioned sibling of it.
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
  // Extends past word.length once overtyped — keeping those characters as
  // real positions in the same repeater (rather than a separate trailing
  // Text, as an earlier version of this file did) is what lets the caret
  // below track through them via itemAt() instead of getting stuck at the
  // end of the word itself.
  readonly property int charCount: Math.max(word.length, typed.length)

  function charAt(index) {
    return index < word.length ? word[index] : typed[index]
  }

  // Characters past the word's own length are always "incorrect" — they're
  // overtyped, there's no correct answer for them to match.
  function statusAt(index) {
    if (index >= word.length) return "incorrect"
    if (index >= typed.length) return "pending"
    return typed[index] === word[index] ? "correct" : "incorrect"
  }

  width: charRow.width
  height: charRow.height

  Row {
    id: charRow

    Repeater {
      id: charRepeater
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

    // Sits just before the character at caretIndex, or past the last
    // character once every character — including any overtyped extras —
    // has been typed.
    x: {
      if (charRepeater.count === 0) return 0
      var atEnd = root.caretIndex >= charRepeater.count
      var item = charRepeater.itemAt(atEnd ? charRepeater.count - 1 : root.caretIndex)
      if (!item) return 0
      return atEnd ? item.x + item.width : item.x
    }

    // Glides to the next character instead of teleporting — only within
    // this word (each word owns its own caret instance, shown only while
    // current), but that's the vast majority of caret movement anyway.
    Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
  }
}
