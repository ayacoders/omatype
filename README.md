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
  edits within the current word (can't step back into a previous word yet).
- **Tab** restarts with a fresh word set at any point. **Esc** aborts a
  running test back to idle, or closes the overlay when idle/done.
- Results screen shows net WPM (correct chars only), raw WPM (everything
  typed), accuracy, and elapsed time.

## Keybinding

In `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT CTRL + T", "Omatype", "omarchy-shell shell toggle aya.omatype")
```

## Known limitations (v1)

- No persistence — results aren't saved between runs.
- Backspace can't cross back into a previously submitted word.
- One word list (`english_1k`, MonkeyType's 1000 most common English words).

## Dev loop

```bash
omarchy plugin validate "$HOME/.config/omarchy/plugins/aya.omatype"
qmllint -I "$OMARCHY_PATH/shell" "$HOME/.config/omarchy/plugins/aya.omatype/TypingTest.qml"
omarchy-shell shell rescanPlugins
omarchy plugin enable aya.omatype
omarchy-shell shell summon aya.omatype '{}'
omarchy-shell shell hide aya.omatype
```

Saving any file under the plugin directory hot-reloads it automatically.
