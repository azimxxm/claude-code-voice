# The talk key: hold ⌥ Space

`ovoz hotkey` (= `ovoz setup --hotkey`) installs Hammerspoon (Homebrew cask) and writes a block between
`-- >>> ovoz >>>` / `-- <<< ovoz <<<` markers into `~/.hammerspoon/init.lua` (backup kept, block
replaced on re-run). macOS needs one permission: System Settings → Privacy & Security →
Accessibility → Hammerspoon; then Hammerspoon menu → Reload Config.

Hold **⌥ Space**, speak, release:

- with the ear pane open (`claude-voice`), the text goes into Claude's tmux pane — from any app, the
  terminal does not need focus; the ear pane shows 🎙 while the key is held;
- without an ear pane, the text is typed where the cursor is (a browser field, a chat, a document)
  and Enter is pressed when `auto_submit` is true.

Between presses **nothing is recorded** — this is why push-to-talk is the default ear mode
(`ovoz mode ptt`): in an office, hands-free detection either never stops (noise above the
threshold) or cuts quiet words (threshold above the speech). Hands-free stays available for quiet
rooms: `ovoz mode vad` (threshold auto-measured from the room, 30 s cap per sentence).

No Hammerspoon? Press ⏎ in the ear pane to start, ⏎ again to send.

Change the key: edit the `hs.hotkey.bind({"alt"}, "space", …)` line. Alfred users may want
`{"ctrl","alt"}, "space"`. The key calls `~/.local/bin/ovoz ptt press|release`, so any other hotkey
tool (skhd, Karabiner, a Stream Deck) can drive it the same way.
