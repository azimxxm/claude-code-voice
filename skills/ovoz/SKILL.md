---
name: ovoz
description: Talk to Claude Code by voice in Uzbek (or Russian, English, Turkish, Kazakh, German) and hear the answers spoken back — free, offline-first (SoX mic → whisper.cpp with an Uzbek fine-tuned model → tmux types the text into Claude; edge-tts neural voices read Claude's 🔊 line). `/ovoz` status, `/ovoz setup`, `/ovoz start` (ear in this tmux session), `/ovoz uz|ru|en`, `/ovoz speak on|off`, `/ovoz voice madina|sardor`, `/ovoz engine gigaam|gemini`, `/ovoz sky`, `/ovoz test`. Use when the user types /ovoz, says "ovozli", "gaplashamiz", "voice mode", "talk to you", "mikrofon", "o'zbekcha gapir", "говори голосом", or asks how to control Claude Code by voice.
argument-hint: "[setup | hotkey | start | stop | status | mode ptt|vad | uz | ru | en | lang <code> | speak on|off | voice <name>|list | engine <name> | sky [live|off] | test | say <text>]"
---

# /ovoz — spoken conversation with Claude Code

Everything runs through one command, `ovoz` (on PATH after `/ovoz setup`, otherwise at `~/.claude/ovoz/bin/ovoz` or the plugin's `scripts/ovoz`). Run it with Bash, relay the output in the user's language, keep it short.

| `$ARGUMENTS`                         | Run                                   | Then                                                                                                   |
| ------------------------------------ | ------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| empty / `status`                     | `ovoz status`                         | relay the ✓/✗ table; for every ✗ give the one-line fix. No audio input device → say plainly that this Mac has no microphone and name the three fixes (USB mic, AirPods, iPhone as mic via Continuity). |
| `setup …`                            | `ovoz setup $ARGS`                    | long step (model downloads); report what got installed, then `ovoz status`.                             |
| `start`                              | `ovoz start`                          | only works when Claude runs inside tmux (`$TMUX` set). Otherwise tell the user to open a new terminal in the project folder and run `claude-voice`. Never try to start tmux around this session. |
| `stop`                               | `ovoz stop`                           | ear closed, servers stopped, read-aloud off.                                                            |
| `mode ptt|vad`                       | `ovoz mode …`                         | ptt (default): records only while ⌥ Space is held or between two ⏎ in the ear pane; vad: hands-free (quiet room). Restart the ear to apply. |
| `hotkey`                             | `ovoz hotkey`                         | installs the ⌥ Space talk key (Hammerspoon); the user must grant Accessibility once and reload Hammerspoon. |
| `uz` / `ru` / `en` / `lang <code>`   | `ovoz lang <code>`                    | confirm in that language. `auto` exists but whisper mistakes Uzbek for Arabic-script languages with it. |
| `speak on|off`                       | `ovoz speak on|off`                   | `on` also means: from now on end every reply with the 🔊 line (rules below).                            |
| `voice <name>|madina|sardor|list`    | `ovoz voice …`                        | `list <locale>` shows edge-tts voices, e.g. `tr-TR`.                                                    |
| `engine <name>`                      | `ovoz engine <name>`                  | cloud engines need their key in the user's shell (`GEMINI_API_KEY`, `GROQ_API_KEY`, `ELEVENLABS_API_KEY`, `OPENAI_API_KEY`) — never write a key into any file; say which variable to export. |
| `sky` / `sky live` / `sky off`       | `ovoz sky …`                          | galaxy of the agent team / live activity graph / stop both.                                             |
| `test`                               | `ovoz test`                           | speaks a sentence and transcribes it back — a full check without a microphone.                          |
| `say <text>`                         | `ovoz say "<text>"`                   |                                                                                                        |
| anything else                        | —                                     | treat it as a spoken sentence and answer in voice-conversation style.                                   |

## How to behave while the conversation is spoken

Read-aloud on (`~/.claude/ovoz/speak.on` exists, or the prompt starts with `🎙`) means the user is talking, not typing. The `voice-context.sh` hook injects these rules on every prompt; follow them even when it did not fire:

- **The ear is push-to-talk by default**: the user holds ⌥ Space (or presses ⏎ in the ear pane) while speaking; between presses nothing is recorded, so silence from the user means they are busy, not that the mic broke.
- **Answer in the conversation language** (`tts.lang` in config.json — Uzbek by default). Short spoken sentences; the screen is the side channel, the ear is the main one.
- **Speech-to-text is imperfect.** Expect missing apostrophes (`o'`, `g'`), Turkish-looking spellings, phonetic English (`gitxab`, `pusht`), mixed languages in one sentence. Infer the intent, never comment on typos, never ask the user to repeat unless the sentence carries no meaning.
- **Spoken tasks are confirmed before the work starts.** When a 🎙 prompt is a task (build, change, run, check), reply with only `Maqsad: …` (what you understood, precise) plus `🔊 <maqsad qisqacha>. Boshlaymi?` and end the turn. The user hears what you understood while the transcript may still be wrong. Start on the next message: "ha", "boshla", "davom et", "qil", "да", "go" → go, no second question; a correction → fix the goal, ask once more; "yo'q" / "to'xta" → stop. Questions and one-step requests are answered directly.
- **End every reply with exactly one `🔊 …` line** — one or two plain sentences in the conversation language: what happened or what the answer is. No code, paths, URLs, markdown or long numbers in that line: it is read aloud; everything else on screen stays silent. The line is spoken when the turn ENDS, so during a long task the user hears nothing until the report — keep long turns short or split them.

## Facts worth knowing

- Claude Code's built-in `/voice` (hold Space) streams audio to Anthropic and supports 20 dictation languages — Russian and English yes, Uzbek no (it falls back to English). It is input only. `ovoz` is the two-way, any-language alternative; both can be on at once.
- Plain Whisper is weak on Uzbek (spells it Turkish-style; `-l auto` picks Arabic script). `ovoz` always passes the language and uses the Uzbek fine-tune `islomov/rubaistt_v2_medium` for `uz`; other languages use `large-v3-turbo`. Optional engines: `gigaam` (GigaAM Multilingual MLX, offline, uz/ru/kk/ky, 7.3 % WER on FLEURS Uzbek), `gemini` (free tier, best on real conversational Uzbek in `uzbek-stt-bench`), `groq`, `elevenlabs`, `openai`.
- Free Uzbek text-to-speech that sounds human exists only through `edge-tts` (`uz-UZ-MadinaNeural`, `uz-UZ-SardorNeural`). ElevenLabs, Google Cloud TTS and macOS `say` have no Uzbek voice. `edge-tts` breaks occasionally when Microsoft rotates its token: `pipx upgrade edge-tts`.
- No tool draws Claude Code agents literally as stars; `ovoz sky` opens the two closest: agent-galaxy (your agent roster as a 3D galaxy) and Agent Flow (live sessions, subagents and tool calls as glowing nodes).

## Autonomy

Cosmetic and technical defaults are yours to decide; never ask about them. The only interactive parts are physically the user's: plugging in a microphone, granting macOS permissions (Microphone for the terminal app, Accessibility for Hammerspoon), and speaking.
