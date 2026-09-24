# Troubleshooting

`ovoz status` first — it names the missing piece and the fix.

| Symptom | Cause | Fix |
| --- | --- | --- |
| `✗ no audio INPUT device` | no microphone (Mac mini) | USB mic, AirPods, or iPhone as mic (Continuity); then `ovoz status` again |
| the ear pane says "eshitmayapman" and nothing happens | push-to-talk mode: hold ⌥ Space (talk key) or press ⏎ in the ear pane while speaking | `ovoz hotkey` installs the key; `ovoz mode vad` for hands-free in a quiet room |
| hands-free never stops / cuts words | room noise vs. threshold | `ovoz mode ptt` (default); or lower the mic input level in System Settings → Sound |
| the ear pane says nothing after you speak | terminal has no Microphone permission | System Settings → Privacy & Security → Microphone → your terminal; if it is not listed: `tccutil reset Microphone`, quit the terminal fully, start again |
| Claude does not end with 🔊 / nothing is spoken | hooks are read at session start | start a new Claude Code session; `ovoz speak on` |
| `edge-tts` 403 / 503 | Microsoft rotated its token | `pipx upgrade edge-tts` |
| Uzbek comes out Turkish-looking | the Uzbek model is missing, plain Whisper is used | `ovoz setup` (builds `ggml-rubaistt-medium-q5_0.bin`); `ovoz status` shows which model serves `uz` |
| Russian comes out in Latin letters | the Uzbek model was used for Russian | `ovoz lang ru` (language switches the model) |
| first sentence takes 20 s | whisper-server was not running | `claude-voice` starts it; or `voice-listen.sh --server` |
| the ear hears Claude's own voice | `speaking.lock` missing (playback killed) | `ovoz speak off && ovoz speak on`; check `~/.claude/ovoz/voice.log` |
| `agent-sky --live` hooks slow every tool call | Agent Flow's hooks stay after its server stops | `agent-sky --stop` strips them |
| `ovoz: command not found` | `~/.local/bin` not on PATH | `export PATH="$HOME/.local/bin:$PATH"`; the plugin re-links launchers on every session start |

Logs: `ovoz log` (`~/.claude/ovoz/voice.log`), `~/.claude/ovoz/whisper-server.log`, `gigaam-server.log`.
