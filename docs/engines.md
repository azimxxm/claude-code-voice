# Engines

`ovoz engine <name>` sets `stt.engine` in `~/.claude/ovoz/config.json`. Cloud keys are read from
your shell environment only.

| Engine | Command | Needs | Language handling |
| --- | --- | --- | --- |
| `local` | whisper.cpp `whisper-server` on 127.0.0.1:8178 | `brew install whisper.cpp`, models from `ovoz setup` | `stt.models.<lang>` if present, else `stt.model`; language always passed |
| `gigaam` | `gigaam-stt serve --allow-unauthenticated` on 127.0.0.1:8000 (OpenAI-compatible) | `brew install uv && uv tool install 'gigaam-multilingual-mlx[server]'` (int8 model, 0.7 GB) | uz / ru / kk / ky, no English; no vocabulary prompt |
| `gemini` | `generateContent` with inline WAV | `GEMINI_API_KEY` (free tier) | any; told the language |
| `groq` | `/openai/v1/audio/transcriptions`, `whisper-large-v3` | `GROQ_API_KEY` (free tier) | plain Whisper — weak Uzbek |
| `elevenlabs` | `/v1/speech-to-text`, `scribe_v1` | `ELEVENLABS_API_KEY` | `uzb` / `rus` / `eng` |
| `openai` | `/v1/audio/transcriptions`, `gpt-4o-transcribe` | `OPENAI_API_KEY` | any |

Ports: `CLAUDE_VOICE_STT_PORT` (whisper-server, 8178), `CLAUDE_VOICE_GIGAAM_PORT` (8000).
`ovoz stop` or `voice-listen.sh --stop-server` stops the local servers.

## Text-to-speech

`tts.engine` is `edge-tts`; `tts.voices.<lang>` maps a language to a voice (`ovoz voice list <locale>`
prints what exists). Without a network, Russian and English fall back to macOS `say`; there is no
offline Uzbek voice.
