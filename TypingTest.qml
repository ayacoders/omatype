import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "TypingTestModel.js" as TypingTestModel

// Local, offline typing speed test — MonkeyType's mechanics, run entirely
// inside the shell process. Word list is bundled (see words/english_1k.json
// and ATTRIBUTION.md); nothing here ever touches the network.
//
// This file owns all the state and logic; ConfigBar/WordStream/WordItem/
// ResultsScreen are pure rendering — they take props and emit signals,
// nothing here relies on them holding state of their own.
Item {
  id: root

  property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/aya.omatype"
  property var shell: null
  property var manifest: null

  property string fontFamily: Style.font.menuFamily
  property string monoFontFamily: "monospace"

  property bool opened: false
  property string phase: "idle" // idle | running | done
  property string testMode: "time" // time | words
  property int timeOption: 30
  property int wordsOption: 25
  readonly property var timeOptions: [15, 30, 60, 120]
  readonly property var wordsOptions: [10, 25, 50, 100]

  property var wordPool: []
  property var words: []
  // Full word sequence for this test, append-only — `words` above gets
  // trimmed from the front as lines complete (see trimCompletedLine()), so
  // it stops being "the whole test" partway through. This is what
  // restartSame() replays.
  property var originalWords: []
  property var submittedWords: [] // typed strings, index-aligned with words, length == currentWordIndex
  property int currentWordIndex: 0
  property string currentInput: ""

  property int correctChars: 0
  property int incorrectChars: 0
  property real elapsed: 0
  property real remaining: 0
  property real startTimestamp: 0

  // Once-a-second raw-WPM samples for the consistency stat — see
  // TypingTestModel.computeConsistency().
  property var wpmSamples: []
  property int lastSampleSecond: 0
  property int charsAtLastSample: 0

  property real resultWpm: 0
  property real resultRawWpm: 0
  property real resultAccuracy: 0
  property real resultConsistency: 0
  property real resultTime: 0

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  // A big, roomy typing surface, not a compact popup — generous padding
  // throughout rather than the stock menu's tight metrics.
  property int contentMargin: Style.space(56)
  property int rowSpacing: Style.space(32)
  property int wordFontSize: Style.font.display
  property int headerHeight: Style.space(44)
  // A narrower, centered reading column rather than a full-bleed card —
  // closer to MonkeyType's composed look than edge-to-edge text.
  property int cardWidth: Math.min(Style.space(1375), panel.width - Style.gapsOut * 4)
  // Word area is capped to a fixed number of visible lines (see
  // wordAreaHeight below) — the actual word list is a bounded rolling
  // window (see ensureBuffer()/trimCompletedLine()), it just also never
  // renders more than this many lines tall.
  readonly property int visibleLines: 3
  readonly property int wordLineSpacing: Style.spacing.xxl
  readonly property int wordLineHeight: Math.round(root.wordFontSize * 1.5)
  readonly property int wordAreaHeight: root.visibleLines * root.wordLineHeight
    + (root.visibleLines - 1) * root.wordLineSpacing
  // One tall, near-square card for every phase — the typing view centers
  // its content in it the same way the results screen does, rather than
  // sizing the card to hug three lines of words.
  property int cardHeight: Math.min(Style.space(618), panel.height - Style.gapsOut * 4)

  readonly property color pendingColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.38)
  readonly property color correctColor: root.foreground
  // Theme's error/danger token — same one polkit and the lock screen use
  // for their own error states — not a hardcoded color.
  readonly property color incorrectColor: Color.urgent
  readonly property color selectedChipBg: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    root.opened = true
    root.newTest()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    testTimer.stop()
  }

  function dismiss() {
    root.opened = false
    testTimer.stop()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "aya.omatype")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadWords(raw) {
    root.wordPool = TypingTestModel.parseWordList(raw)
    if (root.opened) root.newTest()
  }

  function targetWordCount() {
    // Time mode only ever needs enough to fill the rolling window —
    // ensureBuffer() tops it up as the test progresses.
    return root.testMode === "time" ? root.wordsAheadBuffer : root.wordsOption
  }

  // Shared by newTest() and restartSame() — everything about a run except
  // which words are in it.
  function resetRunState() {
    testTimer.stop()
    root.phase = "idle"
    root.submittedWords = []
    root.currentWordIndex = 0
    root.currentInput = ""
    root.correctChars = 0
    root.incorrectChars = 0
    root.elapsed = 0
    root.remaining = root.timeOption
    root.startTimestamp = 0
    root.wpmSamples = []
    root.lastSampleSecond = 0
    root.charsAtLastSample = 0
    Qt.callLater(function() { wordStream.scrollToTop() })
  }

  function newTest() {
    root.words = root.wordPool.length > 0 ? TypingTestModel.pickWords(root.wordPool, root.targetWordCount()) : []
    root.originalWords = root.words.slice()
    root.resetRunState()
  }

  // Retypes the exact same words as the run just finished (or the one in
  // progress), instead of generating a fresh random set — useful for
  // comparing your speed on identical text.
  function restartSame() {
    if (root.originalWords.length === 0) { root.newTest(); return }
    root.words = root.originalWords.slice()
    root.resetRunState()
  }

  function setMode(mode) {
    if (root.phase === "running") return
    root.testMode = mode
    root.newTest()
  }

  function setTimeOption(value) {
    if (root.phase === "running") return
    root.timeOption = value
    if (root.testMode === "time") root.newTest()
  }

  function setWordsOption(value) {
    if (root.phase === "running") return
    root.wordsOption = value
    if (root.testMode === "words") root.newTest()
  }

  // Keyboard-only config, mirroring the chip clicks: Up/Down swap the mode
  // tab, Left/Right step the option within it. Arrow keys are otherwise
  // unused here, so nothing is stolen from the typing itself. The setters
  // above already no-op mid-run, so no need to guard phase here too.
  function cycleMode() {
    root.setMode(root.testMode === "time" ? "words" : "time")
  }

  function cycleOption(direction) {
    if (root.testMode === "time") {
      var i = root.timeOptions.indexOf(root.timeOption)
      root.setTimeOption(root.timeOptions[(i + direction + root.timeOptions.length) % root.timeOptions.length])
    } else {
      var j = root.wordsOptions.indexOf(root.wordsOption)
      root.setWordsOption(root.wordsOptions[(j + direction + root.wordsOptions.length) % root.wordsOptions.length])
    }
  }

  // MonkeyType never keeps an unbounded word list mounted: top up ahead of
  // the cursor so the renderer never runs dry.
  readonly property int wordsAheadBuffer: 40

  function ensureBuffer() {
    if (root.testMode !== "time") return
    if (root.words.length - root.currentWordIndex < root.wordsAheadBuffer) {
      var extra = TypingTestModel.pickWords(root.wordPool, 60)
      root.words = root.words.concat(extra)
      // Keep in sync so restartSame() can still replay a run that ran long
      // enough to need topping up.
      root.originalWords = root.originalWords.concat(extra)
    }
  }

  // Drops the top rendered line as a single batch once the cursor has
  // moved two lines past it — trimming word-by-word (the original
  // approach) reflowed the whole word stream on every single word once the
  // buffer filled, which read as words constantly jittering away
  // mid-typing. Keeping one full trailing line around also gives
  // backspace-across-word-boundary somewhere to land right after a line
  // break. Time mode only — words mode's total is fixed and must stay
  // intact for the X/N progress count and finish check.
  function trimCompletedLine() {
    if (root.testMode !== "time") return
    var lines = wordStream.lines
    if (lines.length === 0) return

    var cursorLine = wordStream.lineIndexFor(root.currentWordIndex)
    if (cursorLine < 2) return // keep at least one trailing line + the current one

    var drop = lines[0].length
    root.words = root.words.slice(drop)
    root.submittedWords = root.submittedWords.slice(drop)
    root.currentWordIndex -= drop
  }

  function beginIfIdle() {
    if (root.phase !== "idle") return
    root.phase = "running"
    root.startTimestamp = Date.now()
    testTimer.start()
  }

  // Caps how far a word can be over-typed with wrong characters — without
  // this, mashing keys against a word you're stuck on grows `currentInput`
  // (and the "extra" characters rendered after it) without bound.
  readonly property int maxExtraChars: 10

  function typeChar(ch) {
    if (root.phase === "done" || root.wordPool.length === 0) return
    root.beginIfIdle()
    var target = root.words[root.currentWordIndex] || ""
    if (root.currentInput.length >= target.length + root.maxExtraChars) return
    root.currentInput += ch
  }

  // Un-tallies and steps back into the previous word. Shared by backspace()
  // (which then restores what was typed there) and backspaceWord() (which
  // wipes it instead). Returns the word's previously-typed text, or null if
  // there's no previous word to step into (start of the rolling
  // buffer/test — see trimCompletedLine()).
  function stepIntoPreviousWord() {
    if (root.currentWordIndex === 0) return null

    var idx = root.currentWordIndex - 1
    var typed = root.submittedWords[idx] || ""
    var target = root.words[idx] || ""
    var tally = TypingTestModel.tallyWord(target, typed)
    root.correctChars -= tally.correct
    root.incorrectChars -= tally.incorrect

    root.submittedWords = root.submittedWords.slice(0, idx)
    root.currentWordIndex = idx
    return typed
  }

  function backspace() {
    if (root.phase !== "running") return

    if (root.currentInput.length > 0) {
      root.currentInput = root.currentInput.slice(0, -1)
      return
    }

    var typed = root.stepIntoPreviousWord()
    if (typed !== null) root.currentInput = typed
  }

  // Ctrl+Backspace: erases the whole current word's input in one go, like a
  // text editor's delete-previous-word. At the start of a word (nothing
  // left to erase there), steps back and erases the previous word entirely
  // too, rather than restoring it the way plain Backspace does.
  function backspaceWord() {
    if (root.phase !== "running") return

    if (root.currentInput.length > 0) {
      root.currentInput = ""
      return
    }

    root.stepIntoPreviousWord()
    root.currentInput = ""
  }

  function submitWord() {
    if (root.phase !== "running" || root.currentInput.length === 0) return

    var target = root.words[root.currentWordIndex] || ""
    var typed = root.currentInput
    var tally = TypingTestModel.tallyWord(target, typed)
    root.correctChars += tally.correct
    root.incorrectChars += tally.incorrect

    root.submittedWords = root.submittedWords.concat([typed])
    root.currentWordIndex++
    root.currentInput = ""

    root.ensureBuffer()

    if (root.testMode === "words" && root.currentWordIndex >= root.words.length) {
      root.finish()
      return
    }

    if (root.testMode === "time") {
      // wordStream.lines is a plain binding off root.words, so it's already
      // up to date here — no need to wait for a layout pass the way the
      // old geometry-based version of this did.
      root.trimCompletedLine()
    } else {
      // ensureVisible reads actual rendered row positions, which do need a
      // tick to settle after the model change above.
      Qt.callLater(function() { wordStream.ensureVisible(root.currentWordIndex) })
    }
  }

  // Once-a-second raw-WPM samples, feeding the consistency stat — a rough
  // measure (coefficient of variation, see TypingTestModel.computeConsistency())
  // of how *even* the typing speed was, not just its average. Sampled off
  // total characters typed so far, right or wrong and including the
  // in-progress word, so it tracks cadence rather than accuracy.
  function sampleWpm() {
    var currentSecond = Math.floor(root.elapsed)
    if (currentSecond <= root.lastSampleSecond) return

    var totalChars = root.correctChars + root.incorrectChars + root.currentInput.length
    var deltaChars = totalChars - root.charsAtLastSample
    var deltaSeconds = currentSecond - root.lastSampleSecond
    root.wpmSamples.push((deltaChars / 5) / (deltaSeconds / 60))
    root.lastSampleSecond = currentSecond
    root.charsAtLastSample = totalChars
  }

  function finish() {
    // Take the last sample before folding the in-progress word's characters
    // into correctChars/incorrectChars below — sampleWpm() expects those to
    // still exclude currentInput, same as every tick during the run.
    root.sampleWpm()

    // Score whatever was left mid-word so a time-out doesn't drop it.
    if (root.currentInput.length > 0) {
      var target = root.words[root.currentWordIndex] || ""
      var tally = TypingTestModel.tallyWord(target, root.currentInput)
      root.correctChars += tally.correct
      root.incorrectChars += tally.incorrect
    }

    testTimer.stop()
    var seconds = root.testMode === "time"
      ? root.timeOption - root.remaining
      : Math.max(0.001, (Date.now() - root.startTimestamp) / 1000)
    var stats = TypingTestModel.computeStats(root.correctChars, root.incorrectChars, seconds)

    root.resultWpm = stats.wpm
    root.resultRawWpm = stats.rawWpm
    root.resultAccuracy = stats.accuracy
    root.resultConsistency = TypingTestModel.computeConsistency(root.wpmSamples)
    root.resultTime = seconds
    root.phase = "done"
  }

  Timer {
    id: testTimer
    interval: 100
    repeat: true
    onTriggered: {
      root.elapsed = (Date.now() - root.startTimestamp) / 1000
      root.sampleWpm()
      if (root.testMode === "time") {
        root.remaining = Math.max(0, root.timeOption - root.elapsed)
        if (root.remaining <= 0) root.finish()
      }
    }
  }

  FileView {
    path: root.pluginDir + "/words/english_1k.json"
    onLoaded: root.loadWords(text())
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "aya-omatype"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.phase === "running") root.newTest()
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            if (event.modifiers & Qt.ShiftModifier) root.restartSame()
            else root.newTest()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (event.modifiers & Qt.ControlModifier) root.backspaceWord()
            else root.backspace()
            event.accepted = true
          } else if (event.key === Qt.Key_Space) {
            root.submitWord()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.phase === "done") root.newTest()
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            root.cycleMode()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.cycleOption(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.cycleOption(1)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.typeChar(event.text)
            event.accepted = true
          }
        }
      }

      // Two independent layouts sharing the same tall card: ConfigBar
      // stays pinned to the top (it's a toolbar, not part of the "content"
      // being read), while the actual content — the word stream, or the
      // results stats — centers itself in the space below it, the same
      // way ResultsScreen centers its own stats.
      Item {
        id: contentArea
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        ConfigBar {
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          height: root.headerHeight
          visible: root.phase !== "done"
          testMode: root.testMode
          timeOption: root.timeOption
          wordsOption: root.wordsOption
          timeOptions: root.timeOptions
          wordsOptions: root.wordsOptions
          running: root.phase === "running"
          fontFamily: root.fontFamily
          foreground: root.foreground
          border: root.border
          selectedBg: root.selectedChipBg
          accent: Color.accent
          cornerRadius: root.cornerRadius
          onModeSelected: function(mode) { root.setMode(mode) }
          onTimeSelected: function(value) { root.setTimeOption(value) }
          onWordsSelected: function(value) { root.setWordsOption(value) }
        }

        Column {
          anchors.centerIn: parent
          spacing: root.rowSpacing
          visible: root.phase !== "done"

          // Live readout while running. Always occupies its row (opacity,
          // not visible) so nothing shifts switching between idle and
          // running.
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.phase === "running" ? 1 : 0
            text: root.testMode === "time"
              ? Math.ceil(root.remaining) + "s"
              : root.currentWordIndex + " / " + root.words.length
            color: Color.accent
            font.family: root.monoFontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true

            Behavior on opacity { NumberAnimation { duration: 150 } }
          }

          WordStream {
            id: wordStream
            width: contentArea.width
            height: root.wordAreaHeight
            words: root.words
            submittedWords: root.submittedWords
            currentWordIndex: root.currentWordIndex
            currentInput: root.currentInput
            isDone: root.phase === "done"
            fontFamily: root.monoFontFamily
            fontSize: root.wordFontSize
            lineSpacing: root.wordLineSpacing
            wordSpacing: root.wordLineSpacing
            correctColor: root.correctColor
            incorrectColor: root.incorrectColor
            pendingColor: root.pendingColor
            caretColor: Color.accent
          }
        }

        ResultsScreen {
          anchors.fill: parent
          visible: root.phase === "done"
          wpm: root.resultWpm
          accuracy: root.resultAccuracy
          rawWpm: root.resultRawWpm
          consistency: root.resultConsistency
          correctChars: root.correctChars
          incorrectChars: root.incorrectChars
          time: root.resultTime
          fontFamily: root.fontFamily
          monoFontFamily: root.monoFontFamily
          foreground: root.foreground
          accent: Color.accent
          mutedText: root.pendingColor
        }
      }
    }
  }
}
