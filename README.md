# claude-code-voice (`ovoz`)

**Talk to Claude Code in Uzbek (or Russian, English, Turkish…) and hear it answer.**
Free, offline-first, one command. The plugin, the skill and the CLI are called `ovoz` — "voice" in Uzbek.

Uzbek model, ready for whisper.cpp: **https://huggingface.co/azimxxm/rubaistt-v2-medium-ggml** (516 MB, Apache-2.0).

```bash
claude plugin marketplace add azimxxm/claude-code-voice && claude plugin install ovoz@ovoz
# then, inside Claude Code:   /ovoz setup        (tools + models, ~10 minutes, one time)
# then, in a project folder:  claude-voice       (Claude on top, the ear below — just speak)
```

Claude Code ships its own `/voice` dictation (hold Space), but it knows 20 languages, Uzbek is not one of them, and it never speaks back. ovoz fills both gaps: it listens in the language you choose with a model that actually understands Uzbek, types what you said into Claude, and reads Claude's answer aloud with a natural neural voice. Nothing leaves your Mac unless you pick a cloud engine yourself.

## What you get

| Part | What | Runs where |
| --- | --- | --- |
| **ear** | SoX records until you pause → whisper.cpp transcribes (Metal; `whisper-server` keeps the model warm, ≈ 1 s per sentence). Uzbek uses a fine-tuned Whisper ([`islomov/rubaistt_v2_medium`](https://huggingface.co/islomov/rubaistt_v2_medium), Apache-2.0, ≈ 17 % WER); other languages use `large-v3-turbo`. | on the Mac |
| **voice** | [`edge-tts`](https://github.com/rany2/edge-tts) — Microsoft neural voices `uz-UZ-MadinaNeural` / `uz-UZ-SardorNeural` (the only free Uzbek voices that sound human), plus ru/en/tr/kk/de voices. Reads the `🔊` line Claude ends every answer with. | network, no key |
| **glue** | tmux types the transcript into Claude's pane and presses Enter. Two hooks: `UserPromptSubmit` tells Claude the conversation is spoken; `Stop` speaks the answer. | plugin |
| **`/ovoz`** | the skill: status, setup, language, voice, engine, sky, test — Claude runs the `ovoz` command for you. | plugin |
| **`agent-sky`** | your agent team as a 3D galaxy ([agent-galaxy](https://github.com/taehyeonglim/agent-galaxy)); `--live`: sessions, subagents and tool calls as glowing nodes ([Agent Flow](https://github.com/patoles/agent-flow)). | browser, local |
| **hotkey** (optional) | Hammerspoon: hold **⌥ Space**, speak, release → the text is typed wherever the cursor is — Claude Code, a chat, a document. | on the Mac |

## Install

**Plugin (recommended)** — skill and hooks register themselves, nothing else is touched:

```bash
claude plugin marketplace add azimxxm/claude-code-voice
claude plugin install ovoz@ovoz
```

**Plain files** — same scripts copied to `~/.claude/ovoz/bin`, hooks merged into `~/.claude/settings.json` (backup kept), `./uninstall.sh` reverses it:

```bash
git clone https://github.com/azimxxm/claude-code-voice && cd claude-code-voice && ./install.sh
```

Then, once:

```bash
ovoz setup              # brew: sox, whisper.cpp, edge-tts (pipx); models: large-v3-turbo 1.6 GB + Uzbek 0.5 GB (ready ggml on Hugging Face)
ovoz setup --hotkey     # optional: Hammerspoon hold-to-talk
```

Requirements: macOS on Apple Silicon (Metal), Homebrew, `python3`, `tmux`, a **microphone** (a Mac mini has none — USB mic, AirPods or your iPhone via Continuity), a Claude Code session in a project folder. The first recording asks for the Microphone permission for your terminal app.

## Use

```bash
cd ~/code/my-project
claude-voice                 # tmux: Claude on top, the ear below. Speak, pause, it is sent.
claude-voice --ear my-sess   # add the ear to a tmux session that is already running
claude-voice --stop
```

Inside Claude Code, or from any shell:

```
/ovoz                 status                 ovoz status
/ovoz uz | ru | en    conversation language  ovoz lang tr
/ovoz speak off       silent mode            ovoz speak on
/ovoz voice sardor    male Uzbek voice       ovoz voice list tr-TR
/ovoz engine gigaam   another ear            ovoz engine gemini   (needs GEMINI_API_KEY)
/ovoz sky             agents as a galaxy     ovoz sky live · ovoz sky off
/ovoz test            self-test, no mic      ovoz say "Salom"
```

While read-aloud is on, Claude answers in your language, short, restates a multi-step request in one line (`Maqsad: …`) before working, and ends every reply with one `🔊 …` line — that line is what you hear. Type and talk in the same session; they mix freely.

## Engines

| `ovoz engine …` | Where | Uzbek | Notes |
| --- | --- | --- | --- |
| `local` (default) | offline | fine-tuned Whisper-medium, ≈ 17 % WER | ru/en/… via `large-v3-turbo`; 0.6–0.7 s per sentence warm |
| `gigaam` | offline | 7.3 % WER on FLEURS ([benchmark](https://github.com/ai-babai/gigaam-multilingual-mlx)) | uz/ru/kk/ky only, no English; `uv tool install 'gigaam-multilingual-mlx[server]'` |
| `gemini` | cloud, free tier | 15.3 % WER on real conversational Uzbek ([uzbek-stt-bench](https://github.com/avazibra/uzbek-stt-bench)) | `GEMINI_API_KEY` |
| `groq` | cloud, free tier | plain Whisper large-v3 | `GROQ_API_KEY` |
| `elevenlabs` | cloud | Scribe, "good" tier (10–25 % WER) | `ELEVENLABS_API_KEY` |
| `openai` | cloud | `gpt-4o-transcribe` | `OPENAI_API_KEY` |

Keys stay in your shell environment; ovoz never writes them to disk. See [docs/engines.md](docs/engines.md) and [docs/models.md](docs/models.md) for measurements and how the Uzbek model was picked.

## How it works

```
 you speak ──► rec (SoX, stops at silence) ──► whisper-server ──► "🎙 …" typed into Claude's tmux pane + Enter
                                                                            │
 you hear ◄── afplay ◄── edge-tts ◄── Stop hook: the 🔊 line ◄── Claude answers (UserPromptSubmit hook set the rules)
```

Details, file map and the reasoning behind each choice: [docs/architecture.md](docs/architecture.md). Problems: [docs/troubleshooting.md](docs/troubleshooting.md). Uzbek README: [README.uz.md](README.uz.md). Where the Uzbek model goes next (v3, v4 — own voice, developer vocabulary, open data, what comes from where): [docs/roadmap-model-v3.md](docs/roadmap-model-v3.md).

## Other languages

Set `ovoz lang <code>` and a voice with `ovoz voice list <locale>` + `ovoz voice <name>`. Recognition uses `large-v3-turbo` for every language except the ones with a per-language model in `config.json` (`stt.models`). Adding a fine-tune for your language is one config line once you have a ggml file — [docs/models.md](docs/models.md) shows the conversion.

## License

MIT. Models and tools keep their own licenses: rubaiSTT and Whisper are Apache-2.0 / MIT, edge-tts is LGPL-3.0 and relies on an unofficial Microsoft endpoint, agent-galaxy is MIT, Agent Flow is Apache-2.0.
