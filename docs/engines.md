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

| Engine | Set with | Needs | Notes |
| --- | --- | --- | --- |
| `omnivoice` | `ovoz --config` (then `ovoz --clone FILE.wav`) | Apple Silicon, ~2.3 GB disk, ~3 GB RAM while speaking | offline, any of 646 languages, cloned voice from a 6–10 s clip; weights CC-BY-NC-4.0 |
| `edge-tts` | `ovoz tts edge` | network | Microsoft neural voices, `tts.voices.<lang>` (`ovoz voice list <locale>`) |

OmniVoice settings live under `tts.omnivoice` in config.json: `model` (`mlx-community/OmniVoice-bf16`),
`steps` (32; 16 is faster, rougher), `speed` (1.0; `ovoz speed 1.2` = 20 % faster, cloned voice only — edge-tts uses `tts.rate`), `ref_audio` + `ref_text` (set by `--clone`), `port` (8179),
`idle_seconds` (600). Cloned clips are kept in `~/.claude/ovoz/voices/<name>/`. When OmniVoice fails,
the same sentence is spoken with edge-tts. Without a network and without OmniVoice, Russian and
English fall back to macOS `say`.
