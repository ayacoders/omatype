// Pure helpers for the typing test — no QML/UI state, deterministic given
// their arguments.

// Parses the bundled MonkeyType word-list JSON ({ words: [...] }). Returns []
// on failure rather than throwing into FileView's onLoaded.
function parseWordList(raw) {
  try {
    var data = JSON.parse(raw)
    if (data && Array.isArray(data.words)) return data.words
  } catch (e) {}
  return []
}

// Random words with no immediate repeat. `count` may exceed pool.length.
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

// Per-character correctness for one word. Anything typed past the target's
// length is overtyped, so it counts as incorrect.
function tallyWord(target, typed) {
  var correct = 0
  for (var i = 0; i < typed.length; i++) {
    if (i < target.length && typed[i] === target[i]) correct++
  }
  return { correct: correct, incorrect: typed.length - correct }
}

// Groups word indices into lines, each rendered centered on its own (see
// WordStream.qml). Monospace-only: a word's width is its length times the
// fixed advance width, so no glyph measuring is needed. Deliberately ignores
// mid-typing overtyped characters — a line's balance can drift a hair, in
// exchange for not re-wrapping on every keystroke.
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

// Where the caret sits along its line, in pixels from the line's left edge.
// charCounts holds the rendered character count of each word on that line —
// a word gets wider as it's overtyped, so this tracks what's on screen
// rather than the target words. Monospace, so every character advances by
// charWidth.
function caretOffset(charCounts, indexInLine, caretChars, charWidth, spaceWidth) {
  var x = 0
  for (var i = 0; i < indexInLine && i < charCounts.length; i++) {
    x += charCounts[i] * charWidth + spaceWidth
  }
  return x + caretChars * charWidth
}

// Standard scoring: a "word" is 5 characters. `wpm` counts only correct
// characters, `rawWpm` counts everything typed.
function computeStats(correctChars, incorrectChars, seconds) {
  var minutes = Math.max(seconds, 0.001) / 60
  var totalChars = correctChars + incorrectChars
  return {
    wpm: (correctChars / 5) / minutes,
    rawWpm: (totalChars / 5) / minutes,
    accuracy: totalChars > 0 ? (correctChars / totalChars) * 100 : 0
  }
}

// How *even* the pace was, not how fast: 100 minus the coefficient of
// variation (stddev / mean) of the per-second WPM samples. Steady typing
// scores near 100; bursts and pauses score low. Too few samples to say
// anything reads as 100 rather than a misleadingly harsh number.
function computeConsistency(samples) {
  if (!samples || samples.length < 2) return 100

  var sum = 0
  for (var i = 0; i < samples.length; i++) sum += samples[i]
  var mean = sum / samples.length
  if (mean <= 0) return 100

  var squaredDiffs = 0
  for (var j = 0; j < samples.length; j++) {
    var diff = samples[j] - mean
    squaredDiffs += diff * diff
  }

  var coefficientOfVariation = Math.sqrt(squaredDiffs / samples.length) / mean
  return Math.max(0, Math.min(100, 100 * (1 - coefficientOfVariation)))
}
