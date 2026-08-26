// TypingTestModel.js — pure helpers for the typing test overlay. No QML/UI
// state; everything here is deterministic given its arguments, so it can be
// reasoned about (and tested) independently of the shell.

// Parses the bundled MonkeyType word-list JSON ({ words: [...] }). Returns
// [] on any parse failure rather than throwing into the FileView's onLoaded.
function parseWordList(raw) {
  try {
    var data = JSON.parse(raw)
    if (data && Array.isArray(data.words)) return data.words
  } catch (e) {}
  return []
}

// Random words with no immediate repeat. `count` may exceed pool.length —
// words repeat once the no-repeat window resets.
function pickWords(pool, count) {
  var out = []
  if (!pool || pool.length === 0) return out
  var lastIndex = -1
  for (var i = 0; i < count; i++) {
    var idx = Math.floor(Math.random() * pool.length)
    if (pool.length > 1 && idx === lastIndex) idx = (idx + 1) % pool.length
    lastIndex = idx
    out.push(pool[idx])
  }
  return out
}

// Per-character correctness for one submitted/typed word against its
// target. Characters typed past the target's length count as incorrect —
// the caller renders those separately as "extra" characters.
function tallyWord(target, typed) {
  var correct = 0
  var incorrect = 0
  for (var i = 0; i < typed.length; i++) {
    if (i < target.length && typed[i] === target[i]) correct++
    else incorrect++
  }
  return { correct: correct, incorrect: incorrect }
}

// Groups word indices into lines for a poem-style centered display, where
// each line is centered independently rather than the whole block being
// one ragged left-aligned paragraph. Assumes a monospace font, so a word's
// width is just its character count times the font's fixed advance width —
// no need to measure actual rendered glyphs. Recomputed only when the word
// list (or available width) changes, not on every keystroke — it ignores
// mid-typing "extra" overtyped characters, a rare case where a line's
// balance can drift very slightly in exchange for not re-laying-out on
// every keystroke.
function computeLines(words, charWidth, spaceWidth, availableWidth) {
  var lines = []
  var current = []
  var currentWidth = 0

  for (var i = 0; i < words.length; i++) {
    var wordWidth = words[i].length * charWidth
    var nextWidth = current.length === 0 ? wordWidth : currentWidth + spaceWidth + wordWidth

    if (current.length > 0 && nextWidth > availableWidth) {
      lines.push(current)
      current = [i]
      currentWidth = wordWidth
    } else {
      current.push(i)
      currentWidth = nextWidth
    }
  }
  if (current.length > 0) lines.push(current)
  return lines
}

// Standard typing-test scoring: a "word" is 5 characters. `wpm` (net) counts
// only correctly typed characters; `rawWpm` counts everything typed, right
// or wrong. `accuracy` is correct / total typed, as a percentage.
function computeStats(correctChars, incorrectChars, seconds) {
  var minutes = Math.max(seconds, 0.001) / 60
  var totalChars = correctChars + incorrectChars
  var rawWpm = (totalChars / 5) / minutes
  var wpm = (correctChars / 5) / minutes
  var accuracy = totalChars > 0 ? (correctChars / totalChars) * 100 : 0
  return { wpm: wpm, rawWpm: rawWpm, accuracy: accuracy }
}

// Rough approximation of MonkeyType's consistency stat: how *even* the
// typing speed was across the run, not just its average. Takes once-a-
// second raw-WPM samples (see TypingTest.qml's sampleWpm()) and expresses
// their spread as 100 minus the coefficient of variation (stddev / mean)
// as a percentage — a smooth, unwavering pace scores near 100; one that
// swings wildly between bursts and pauses scores low. Too few samples
// (a very short run) to say anything meaningful reads as 100 rather than
// a misleadingly harsh number.
function computeConsistency(samples) {
  if (!samples || samples.length < 2) return 100

  var mean = samples.reduce(function(sum, v) { return sum + v }, 0) / samples.length
  if (mean <= 0) return 100

  var variance = samples.reduce(function(sum, v) { return sum + Math.pow(v - mean, 2) }, 0) / samples.length
  var stddev = Math.sqrt(variance)
  var coefficientOfVariation = stddev / mean

  return Math.max(0, Math.min(100, 100 * (1 - coefficientOfVariation)))
}
