# Hotkey: hold ⌥ Space to talk

`ovoz setup --hotkey` installs Hammerspoon (Homebrew cask) and writes a block between
`-- >>> ovoz >>>` / `-- <<< ovoz <<<` markers into `~/.hammerspoon/init.lua` (backup kept, block
replaced on re-run). Hold **⌥ Space**, speak, release: the text is typed where the cursor is — a
Claude Code prompt, a browser field, a document — and Enter is pressed when `auto_submit` is true.

macOS needs one permission: System Settings → Privacy & Security → Accessibility → Hammerspoon.
Then Hammerspoon menu → Reload Config.

Why Hammerspoon and not the terminal: a hold-to-talk key needs key-down/key-up events across
apps; Hammerspoon gives that in ten lines and types the result with `hs.eventtap.keyStrokes`.
Under the hood it calls `voice-listen.sh --start` and `--stop --print`.

Change the key: edit the `hs.hotkey.bind({"alt"}, "space", …)` line. Alfred users may want
`{"ctrl","alt"}, "space"`.
