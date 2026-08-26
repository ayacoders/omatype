# Omatype

A local, offline MonkeyType-style typing speed test, running as an Omarchy
shell overlay. No network calls — the word list is bundled at
`words/english_1k.json` (see `ATTRIBUTION.md`).

## Usage

- Summon: `omarchy-shell shell toggle aya.omatype` (bound to
  `SUPER SHIFT CTRL + T`, see below)
- Fully keyboard-driven, no mouse required: **Up/Down** swap the time/words
  mode tab, **Left/Right** step the duration or word-count option — or click
  the chips instead. Disabled mid-run either way.
- Start typing to begin. **Space** submits the current word. **Backspace**
  edits within the current word, and steps back into the previous one once
  you're at the start of the current word (reaches back one full line —
  see Known limitations). **Ctrl+Backspace** erases the whole current word
  in one go instead of one character at a time (and the whole previous word
  if pressed again right at the start of a word). Mistyping into a word
  stops accepting more characters 10 past its correct length.
- **Tab** restarts with a fresh, random word set. **Shift+Tab** restarts
  with the *same* words you just typed, for comparing your speed on
  identical text. **Esc** aborts a running test back to idle, or closes the
  overlay when idle/done.
- Results screen shows net WPM (correct chars only), raw WPM (everything
  typed), accuracy, consistency (how even your pace was, not just its
  average — see `TypingTestModel.computeConsistency()`), and elapsed time.

## Keybinding

In `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT CTRL + T", "Omatype", "omarchy-shell shell toggle aya.omatype")
```

## Known limitations (v1)

- No persistence — results aren't saved between runs.
- Backspace only reaches back as far as the rolling render window keeps
  (one full completed line) — see `trimCompletedLine()` in `TypingTest.qml`.
- One word list (`english_1k`, MonkeyType's 1000 most common English words).

## Files

- `TypingTest.qml` — all state and test logic; composes the rest
- `WordItem.qml` — one word: character coloring, caret
- `WordStream.qml` — the centered, line-wrapped word viewport
- `ConfigBar.qml` — mode/duration/word-count chips
- `ResultsScreen.qml` — end-of-run stats
- `TypingTestModel.js` — pure logic: word picking, line wrapping, scoring

## Dev loop

```bash
omarchy plugin validate "$HOME/.config/omarchy/plugins/aya.omatype"
for f in "$HOME"/.config/omarchy/plugins/aya.omatype/*.qml; do
  qmllint -I "$OMARCHY_PATH/shell" "$f"
done
omarchy-shell shell rescanPlugins
omarchy plugin enable aya.omatype
omarchy-shell shell summon aya.omatype '{}'
omarchy-shell shell hide aya.omatype
```

Saving any file under the plugin directory hot-reloads it — except an
already-open (`keepLoaded: true`) instance doesn't pick up the change until
its next full mount; run `omarchy-restart-shell` if edits don't seem to
take effect.
