import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "TypingTestModel.js" as TypingTestModel

// Local, offline typing speed test with MonkeyType's mechanics, run inside
// the shell process. The word list is bundled (words/english_1k.json, see
// ATTRIBUTION.md) — nothing here touches the network.
//
// This file owns all state and logic; ConfigBar/WordStream/WordItem/
// ResultsScreen are pure rendering driven by props and signals.
Item {
  id: root

  property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/aya.omatype"
  readonly property string wordsPath: root.pluginDir + "/words/english_1k.json"
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
  // Set once a load has been tried, so the notice below doesn't flash while
  // the file is still being read.
  property bool wordsLoadAttempted: false
  readonly property bool wordsFailed: root.wordsLoadAttempted && root.wordPool.length === 0

  // originalWords is the canonical sequence for this test and only ever
  // grows; `words` is the window of it currently mounted, trimmed from the
  // front as lines complete. mountedCount tracks how far into the sequence
  // that window reaches, so a replay re-mounts the same continuation.
  property var originalWords: []
  property var words: []
  property int mountedCount: 0
  property var submittedWords: [] // index-aligned with words; length == currentWordIndex
  property int currentWordIndex: 0
  property string currentInput: ""

  property int correctChars: 0
  property int incorrectChars: 0
  property real elapsed: 0
  property real remaining: 0
  property real startTimestamp: 0

  // Per-second WPM samples feeding the consistency stat.
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
  // Roomy typing surface rather than the stock menu's compact metrics.
  property int contentMargin: Style.space(56)
  property int rowSpacing: Style.space(32)
  property int wordFontSize: Style.font.display
  property int cardWidth: Math.min(Style.space(1375), panel.width - Style.gapsOut * 4)
  // Caps the viewport at a few lines; the word list itself stays bounded via
  // ensureBuffer()/trimCompletedLine().
  readonly property int visibleLines: 3
  readonly property int wordLineSpacing: Style.spacing.xxl
  readonly property int wordLineHeight: Math.round(root.wordFontSize * 1.5)
  readonly property int wordAreaHeight: root.visibleLines * root.wordLineHeight
    + (root.visibleLines - 1) * root.wordLineSpacing
  // One near-square card for every phase; each view centers itself in it.
  property int cardHeight: Math.min(Style.space(618), panel.height - Style.gapsOut * 4)

  readonly property color pendingColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.38)
  readonly property color correctColor: root.foreground
  // Theme's error token, as used by polkit and the lock screen.
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
    root.wordsLoadAttempted = true
    if (root.opened) root.newTest()
  }

  function targetWordCount() {
    // Time mode just needs to fill the rolling window; ensureBuffer() tops
    // it up as the run progresses.
    return root.testMode === "time" ? root.wordsAheadBuffer : root.wordsOption
  }

  // Everything about a run except which words are in it.
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
    root.originalWords = TypingTestModel.pickWords(root.wordPool, root.targetWordCount())
    root.startSequence()
  }

  // Retypes the same words instead of drawing a fresh set, for comparing
  // runs over identical text.
  function restartSame() {
    if (root.originalWords.length === 0) { root.newTest(); return }
    root.startSequence()
  }

  // Clears the run and mounts the opening window of originalWords.
  function startSequence() {
    root.words = []
    root.mountedCount = 0
    root.resetRunState()
    root.mountNext(root.targetWordCount())
  }

  // Appends the next `count` words of the sequence to the mounted window,
  // extending the sequence with fresh picks only once it runs out. Replays
  // therefore follow the original words rather than diverging into new ones.
  function mountNext(count) {
    var shortfall = root.mountedCount + count - root.originalWords.length
    if (shortfall > 0)
      root.originalWords = root.originalWords.concat(TypingTestModel.pickWords(root.wordPool, shortfall))

    var next = root.originalWords.slice(root.mountedCount, root.mountedCount + count)
    root.mountedCount += next.length
    root.words = root.words.concat(next)
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

  // Arrow-key config, mirroring the chips. The setters above already no-op
  // mid-run, so there's no phase guard here.
  function cycleMode() {
    root.setMode(root.testMode === "time" ? "words" : "time")
  }

  function cycleOption(direction) {
    var timed = root.testMode === "time"
    var options = timed ? root.timeOptions : root.wordsOptions
    var index = options.indexOf(timed ? root.timeOption : root.wordsOption)
    var next = options[(index + direction + options.length) % options.length]

    if (timed) root.setTimeOption(next)
    else root.setWordsOption(next)
  }

  // Keeps a bounded window mounted: roughly the visible lines plus enough
  // ahead of the cursor that the renderer never runs dry. Topping up in
  // small chunks keeps the mounted count near this figure instead of
  // overshooting it by a wide margin.
  readonly property int wordsAheadBuffer: 40
  readonly property int wordsTopUpChunk: 20

  function ensureBuffer() {
    if (root.testMode !== "time") return
    if (root.words.length - root.currentWordIndex >= root.wordsAheadBuffer) return
    root.mountNext(root.wordsTopUpChunk)
  }

  // Drops the top line in one batch once the cursor is two lines past it.
  // Trimming word-by-word instead re-wrapped the stream on every submission,
  // which read as words jittering away mid-typing; holding a trailing line
  // also gives backspace-across-words somewhere to land after a line break.
  // Time mode only — words mode's total must stay intact for its X/N count
  // and finish check.
  function trimCompletedLine() {
    if (root.testMode !== "time") return
    if (wordStream.lines.length === 0) return
    // Below 2 also covers -1 (index past the end).
    if (wordStream.lineIndexFor(root.currentWordIndex) < 2) return

    var drop = wordStream.lines[0].length
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

  // Bounds overtyping, so mashing keys at a word can't grow currentInput
  // (and its rendered extras) without limit.
  readonly property int maxExtraChars: 10

  function typeChar(ch) {
    if (root.phase === "done" || root.wordPool.length === 0) return
    root.beginIfIdle()

    var target = root.words[root.currentWordIndex] || ""
    if (root.currentInput.length >= target.length + root.maxExtraChars) return
    root.currentInput += ch
  }

  // Un-tallies the previous word and moves onto it, returning what had been
  // typed there — or null at the start of the buffer. backspace() restores
  // that text; backspaceWord() discards it.
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

  // Ctrl+Backspace, like a text editor's delete-previous-word. At the start
  // of a word it steps back and clears the previous one outright, rather
  // than restoring it the way plain Backspace does.
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
      // wordStream.lines binds off root.words, so it's already current —
      // no layout pass to wait for.
      root.trimCompletedLine()
    } else {
      // ensureVisible reads rendered row positions, which need a tick to
      // settle after the model change above.
      Qt.callLater(function() { wordStream.ensureVisible(root.currentWordIndex) })
    }
  }

  // Samples raw WPM once per elapsed second. Counts every character typed,
  // right or wrong, including the in-progress word, so consistency tracks
  // cadence rather than accuracy.
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
    // Sample before folding currentInput into the tallies below — sampleWpm()
    // counts it separately, as it does on every tick during the run.
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

  // A failed read routes through loadWords too, so an unreadable file and a
  // malformed one land in the same empty-pool state.
  FileView {
    path: root.wordsPath
    onLoaded: root.loadWords(text())
    onLoadFailed: root.loadWords("")
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
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            // Shift+Tab arrives as Key_Backtab, not Key_Tab with a modifier,
            // so the key code is the reliable signal rather than the flag.
            if (event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)) root.restartSame()
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

      // ConfigBar pins to the top as a toolbar; the content below it — word
      // stream or results — centers itself in the rest of the card.
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
          mutedText: root.pendingColor
          accent: Color.accent
          cornerRadius: root.cornerRadius
          onModeSelected: function(mode) { root.setMode(mode) }
          onOptionSelected: function(value) {
            if (root.testMode === "time") root.setTimeOption(value)
            else root.setWordsOption(value)
          }
        }

        Column {
          anchors.centerIn: parent
          spacing: root.rowSpacing
          visible: root.phase !== "done"

          // Live readout. Always occupies its row (opacity, not visible) so
          // nothing shifts between idle and running.
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

          // Without this the overlay would just sit blank and swallow every
          // keystroke, with nothing to say the word list is missing.
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.wordsFailed
            text: "Couldn't read the word list.\n" + root.wordsPath
            horizontalAlignment: Text.AlignHCenter
            color: root.incorrectColor
            font.family: root.monoFontFamily
            font.pixelSize: Style.font.body
          }

          WordStream {
            id: wordStream
            visible: !root.wordsFailed
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
