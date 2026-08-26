// Tests for TypingTestModel.js — the pure logic behind scoring, line
// wrapping, and the consistency stat. qmllint can't check any of this, and
// it's the part most likely to break silently.
//
//   node --test tests/
//
// The module is a QML JavaScript resource, so it has no exports. Rather than
// adding test-only plumbing to it, evaluate the source and hand back its
// declarations.

const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const source = fs.readFileSync(path.join(__dirname, "..", "TypingTestModel.js"), "utf8")
const model = new Function(`
  ${source}
  return {
    parseWordList, pickWords, tallyWord, computeLines,
    caretOffset, computeStats, computeConsistency
  }
`)()

test("parseWordList reads the bundled list shape", () => {
  assert.deepEqual(model.parseWordList('{"words":["a","b"]}'), ["a", "b"])
})

test("parseWordList returns [] rather than throwing on bad input", () => {
  assert.deepEqual(model.parseWordList("not json"), [])
  assert.deepEqual(model.parseWordList('{"nope":1}'), [])
  assert.deepEqual(model.parseWordList('{"words":"a"}'), [])
  assert.deepEqual(model.parseWordList(""), [])
  assert.deepEqual(model.parseWordList(null), [])
})

test("pickWords returns the requested count, even past pool size", () => {
  assert.equal(model.pickWords(["a", "b", "c"], 10).length, 10)
  assert.equal(model.pickWords(["a"], 3).length, 3)
})

test("pickWords never repeats a word back to back", () => {
  const pool = ["a", "b", "c", "d"]
  for (let run = 0; run < 200; run++) {
    const words = model.pickWords(pool, 20)
    for (let i = 1; i < words.length; i++) {
      assert.notEqual(words[i], words[i - 1], "adjacent duplicate")
    }
  }
})

test("pickWords handles an empty or missing pool", () => {
  assert.deepEqual(model.pickWords([], 5), [])
  assert.deepEqual(model.pickWords(null, 5), [])
})

test("tallyWord scores a perfect word", () => {
  assert.deepEqual(model.tallyWord("hello", "hello"), { correct: 5, incorrect: 0 })
})

test("tallyWord counts position-wise, not as a set", () => {
  // Transposed letters: 'h', 'l', 'o' land right, 'e'/'l' swapped do not.
  assert.deepEqual(model.tallyWord("hello", "hlelo"), { correct: 3, incorrect: 2 })
})

test("tallyWord treats overtyped characters as incorrect", () => {
  assert.deepEqual(model.tallyWord("hi", "hixyz"), { correct: 2, incorrect: 3 })
})

test("tallyWord only scores what was typed, not what was skipped", () => {
  // An unfinished word contributes nothing for its untyped tail.
  assert.deepEqual(model.tallyWord("hello", "he"), { correct: 2, incorrect: 0 })
  assert.deepEqual(model.tallyWord("hello", ""), { correct: 0, incorrect: 0 })
})

test("tallyWord totals always equal the typed length", () => {
  const cases = [["hello", "hello"], ["hello", "help"], ["a", "abcdef"], ["abc", ""]]
  for (const [target, typed] of cases) {
    const { correct, incorrect } = model.tallyWord(target, typed)
    assert.equal(correct + incorrect, typed.length)
  }
})

test("computeLines packs words until the width runs out", () => {
  // 10px per char, 5px space. Each word is 50px, so a pair needs 105px.
  const words = ["aaaaa", "bbbbb", "ccccc"]
  assert.deepEqual(model.computeLines(words, 10, 5, 110), [[0, 1], [2]])
})

test("computeLines counts the space between words", () => {
  // 100px fits two 50px words only if the separator is ignored — it isn't.
  const words = ["aaaaa", "bbbbb", "ccccc"]
  assert.deepEqual(model.computeLines(words, 10, 5, 100), [[0], [1], [2]])
})

test("computeLines keeps every index exactly once, in order", () => {
  // lineIndexFor() walks cumulative lengths, so it relies on lines being a
  // contiguous, ordered partition of the word indices.
  const words = Array.from({ length: 137 }, (_, i) => "x".repeat((i % 9) + 1))
  const lines = model.computeLines(words, 10, 5, 300)
  assert.deepEqual(lines.flat(), words.map((_, i) => i))
})

test("computeLines never emits an empty line", () => {
  const words = Array.from({ length: 40 }, () => "word")
  for (const width of [1, 10, 45, 200, 5000]) {
    const lines = model.computeLines(words, 10, 5, width)
    assert.ok(lines.every(line => line.length > 0), `empty line at width ${width}`)
  }
})

test("computeLines puts an over-long word on its own line rather than looping", () => {
  const lines = model.computeLines(["tiny", "enormouslylongword"], 10, 5, 60)
  assert.deepEqual(lines, [[0], [1]])
})

test("computeLines handles no words", () => {
  assert.deepEqual(model.computeLines([], 10, 5, 100), [])
})

test("caretOffset starts at the line's left edge", () => {
  assert.equal(model.caretOffset([5, 3], 0, 0, 10, 5), 0)
  assert.equal(model.caretOffset([], 0, 0, 10, 5), 0)
})

test("caretOffset advances within a word", () => {
  assert.equal(model.caretOffset([5, 3], 0, 3, 10, 5), 30)
})

test("caretOffset skips preceding words and their separators", () => {
  // 5 chars (50px) + one 5px space, then 2 chars into the second word.
  assert.equal(model.caretOffset([5, 3], 1, 2, 10, 5), 75)
  // Two words behind: 50 + 5 + 30 + 5 = 90.
  assert.equal(model.caretOffset([5, 3, 4], 2, 0, 10, 5), 90)
})

test("caretOffset accounts for overtyped words being wider", () => {
  // The first word rendered 8 characters even though its target was shorter.
  assert.equal(model.caretOffset([8, 3], 1, 0, 10, 5), 85)
})

test("caretOffset lands past the last character when a word is complete", () => {
  assert.equal(model.caretOffset([5], 0, 5, 10, 5), 50)
})

test("computeStats uses the standard 5-characters-per-word convention", () => {
  // 50 correct chars in 60s = 10 words per minute.
  const stats = model.computeStats(50, 0, 60)
  assert.equal(stats.wpm, 10)
  assert.equal(stats.rawWpm, 10)
  assert.equal(stats.accuracy, 100)
})

test("computeStats separates net wpm from raw wpm", () => {
  const stats = model.computeStats(50, 50, 60)
  assert.equal(stats.wpm, 10)   // correct only
  assert.equal(stats.rawWpm, 20) // everything typed
  assert.equal(stats.accuracy, 50)
})

test("computeStats does not divide by zero", () => {
  const stats = model.computeStats(0, 0, 0)
  assert.ok(Number.isFinite(stats.wpm))
  assert.equal(stats.accuracy, 0)
})

test("computeConsistency reports a steady pace as 100", () => {
  assert.equal(model.computeConsistency([40, 40, 40, 40]), 100)
})

test("computeConsistency needs at least two samples to judge", () => {
  assert.equal(model.computeConsistency([]), 100)
  assert.equal(model.computeConsistency([42]), 100)
  assert.equal(model.computeConsistency(null), 100)
})

test("computeConsistency penalises an uneven pace", () => {
  const steady = model.computeConsistency([40, 41, 39, 40])
  const uneven = model.computeConsistency([80, 5, 70, 10])
  assert.ok(uneven < steady, "uneven should score below steady")
  assert.ok(steady > 90, `steady scored ${steady}`)
})

test("computeConsistency stays within 0-100", () => {
  const cases = [[100, 0, 100, 0], [1, 1000], [0, 0, 0], [5, 5, 5, 500]]
  for (const samples of cases) {
    const value = model.computeConsistency(samples)
    assert.ok(value >= 0 && value <= 100, `${value} out of range for ${samples}`)
  }
})
