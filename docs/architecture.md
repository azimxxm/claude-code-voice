# Architecture

ovoz is seven shell scripts, one skill and two hooks. No daemon of its own: the "server"
parts are whisper.cpp's `whisper-server` (model kept in memory) and, optionally, GigaAM's.

## The loop

```
┌────────────┐  rec (SoX)   ┌───────────────┐  POST wav  ┌────────────────┐  tmux send-keys  ┌────────────┐
│ microphone │─────────────►│ voice-listen  │───────────►│ whisper-server │─────────────────►│ Claude Code│
└────────────┘ stops at     │ --loop        │  text      │ (ggml model)   │  "🎙 …" + Enter  │ (tmux pane)│
               silence      └───────────────┘◄───────────└────────────────┘                  └─────┬──────┘
                                    ▲ waits while speaking.lock exists                              │ turn ends
┌────────────┐  afplay      ┌───────────────┐  mp3       ┌────────────────┐   last_assistant_message │
│  speakers  │◄─────────────│ voice-speak   │◄───────────│    edge-tts    │◄─────────── Stop hook ───┘
└────────────┘              │ --hook        │            └────────────────┘   picks the 🔊 line
                            └───────────────┘
```

1. **Ear.** `voice-listen.sh --loop --target <pane>` runs in a small tmux pane under Claude. SoX's
   `silence` effect does the voice-activity detection: recording starts when sound rises above
   `mic.threshold` and stops after `mic.stop_after_silence` seconds of quiet. The WAV (16 kHz mono)
   goes to `whisper-server` (`/inference`, language passed explicitly, a vocabulary prompt for tech
   terms), the text is typed into Claude's pane with `tmux send-keys -l` and Enter.
2. **Rules for Claude.** The `UserPromptSubmit` hook (`voice-context.sh`) adds a short note to every
   prompt while `speak.on` exists: answer in the conversation language, expect speech-to-text errors,
   restate multi-step goals as `Maqsad: …`, end with one `🔊` line. Prompts that start with 🎙 get the
   extra "this came from speech" note. Slash commands are left alone.
3. **Voice.** The `Stop` hook (`voice-speak.sh --hook`) reads `last_assistant_message` from the hook
   payload (no transcript parsing), takes the 🔊 line (or the first 350 characters of prose if
   there is none), synthesizes it with edge-tts and plays it detached, so the hook returns at once.
   While the clip plays, `speaking.lock` exists and the ear does not record — Claude never hears
   itself.

## Files

| File | Role |
| --- | --- |
| `scripts/voice-lib.sh` | paths, config defaults, `cfg`/`cfg_set`, flags, language names, launcher links |
| `scripts/voice-listen.sh` | ear: `--loop`, `--once`, `--transcribe`, hotkey `--start/--stop/--toggle`, `--server`, `--check`; engines |
| `scripts/voice-speak.sh` | voice: speak now, `--hook`, `--stop`, `--check`, `--extract` |
| `scripts/voice-context.sh` | UserPromptSubmit hook |
| `scripts/voice-setup.sh` | idempotent installer: tools, models, config, launchers, hotkey, mic check, status |
| `scripts/claude-voice.sh` | tmux launcher: Claude pane + ear pane; `--ear` for an existing session |
| `scripts/agent-sky.sh` | agent-galaxy (roster) and Agent Flow (live) visualizers |
| `scripts/ovoz` | the CLI the skill and the user call |
| `skills/ovoz/SKILL.md` | `/ovoz` — routing + how Claude behaves in a spoken conversation |
| `hooks/hooks.json` | plugin hooks: SessionStart (link launchers), UserPromptSubmit, Stop |

State lives in `~/.claude/ovoz/` (`$OVOZ_HOME`): `config.json`, `models/`, `tmp/`, `speak.on`,
`speaking.lock`, `voice.log`, server pid/log files.

## Why these choices

- **tmux, not a global keystroke injector.** Typing into the pane by name works whether or not the
  terminal is frontmost, needs no Accessibility permission, and works inside remote/tmux sessions.
  The optional Hammerspoon hotkey covers the "type anywhere" case.
- **whisper-server, not whisper-cli.** Loading a 0.5–1.6 GB model takes ~20 s; kept warm it answers in
  0.6 s. One server per model; switching language swaps the model automatically.
- **Language always explicit.** Whisper's auto-detect misreads Uzbek as an Arabic-script language.
- **Per-language models.** The Uzbek fine-tune transliterates Russian into Latin letters, so
  Russian and English go to `large-v3-turbo`.
- **`last_assistant_message`, not the transcript file.** Claude Code's docs recommend it for
  read-aloud hooks; the transcript may not contain the final message yet when Stop fires.
- **Detached playback.** A hook whose child keeps stdout open blocks Claude Code until the audio
  ends. `voice-speak.sh` closes stdin/stdout/stderr on the player.
- **`speak.on` flag, not a setting.** Hooks read it in microseconds; `/ovoz speak off` works
  instantly for every session without restarting anything.
