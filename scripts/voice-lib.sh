#!/usr/bin/env bash
# voice-lib.sh — shared helpers for ovoz. Sourced by every script, never executed.
#
# Everything ovoz keeps on disk lives under $OVOZ_HOME (default ~/.claude/ovoz):
#   config.json     what to listen with, what to speak with (see voice_config_default)
#   models/         whisper.cpp ggml models (downloaded or built by voice-setup.sh)
#   tmp/            recordings + synthesized clips, deleted after use
#   speak.on        exists → the Stop hook reads Claude's 🔊 line aloud
#   ptt.on          exists → the talk key is held: the ear records (push-to-talk mode)
#   speaking.lock   exists → the ear waits (never transcribe the speaker output)
#   voice.log       one line per event (ovoz log)

set -u

VOICE_DIR="${OVOZ_HOME:-$HOME/.claude/ovoz}"
VOICE_CONFIG="$VOICE_DIR/config.json"
VOICE_MODELS="$VOICE_DIR/models"
VOICE_TMP="$VOICE_DIR/tmp"
VOICE_SPEAK_FLAG="$VOICE_DIR/speak.on"
VOICE_SPEAKING_LOCK="$VOICE_DIR/speaking.lock"
VOICE_PLAYING_PID="$VOICE_DIR/playing.pid"
VOICE_REC_PID="$VOICE_DIR/recording.pid"
VOICE_PTT_FLAG="$VOICE_DIR/ptt.on"          # exists while the talk key is held
VOICE_PTT_LOOP_PID="$VOICE_DIR/ptt-loop.pid" # the ear pane running in push-to-talk mode
VOICE_LOG="$VOICE_DIR/voice.log"

# Where the ovoz scripts live (plugin cache, a git checkout, or ~/.claude/ovoz/bin).
OVOZ_SCRIPTS="$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"

# pipx (edge-tts), uv tools (gigaam-stt) and Homebrew are not on PATH inside hooks.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

vlog() { mkdir -p "$VOICE_DIR"; printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$VOICE_LOG" 2>/dev/null || true; }

voice_config_default() {
  cat <<'JSON'
{
  "lang": "uz",
  "auto_submit": true,
  "transcript_prefix": "🎙 ",
  "stt": {
    "engine": "whisper.cpp",
    "model": "~/.claude/ovoz/models/ggml-large-v3-turbo.bin",
    "models": {
      "uz": "~/.claude/ovoz/models/ggml-rubaistt-medium-q5_0.bin"
    },
    "cloud_model": "",
    "prompt": "Claude Code, Jarvis, agent, skill, commit, push, deploy, Swift, Kotlin, TypeScript, Go, PostgreSQL, MongoDB, Telegram bot, iOS, Android, backend, frontend, bug, test."
  },
  "tts": {
    "engine": "edge-tts",
    "lang": "uz",
    "rate": "+8%",
    "voices": {
      "uz": "uz-UZ-MadinaNeural",
      "ru": "ru-RU-SvetlanaNeural",
      "en": "en-US-AriaNeural",
      "tr": "tr-TR-EmelNeural",
      "kk": "kk-KZ-AigulNeural",
      "de": "de-DE-KatjaNeural"
    }
  },
  "mic": {
    "mode": "ptt",
    "threshold": "auto",
    "stop_after_silence": "1.2",
    "max_seconds": "30"
  }
}
JSON
}

voice_ensure_dirs() { mkdir -p "$VOICE_DIR" "$VOICE_MODELS" "$VOICE_TMP"; }

voice_ensure_config() {
  voice_ensure_dirs
  [[ -s "$VOICE_CONFIG" ]] || voice_config_default > "$VOICE_CONFIG"
}

# cfg '.stt.engine' [default] — read one value; null/missing → default. Keeps `false`.
cfg() {
  local v
  v="$(jq -r "$1 | select(. != null)" "$VOICE_CONFIG" 2>/dev/null)"
  if [[ -n "$v" ]]; then printf '%s' "$v"; else printf '%s' "${2:-}"; fi
}

# cfg_set '.lang' '"uz"' — value is raw JSON. Never leaves a truncated file behind.
cfg_set() {
  voice_ensure_config
  local tmp
  tmp="$(mktemp "$VOICE_DIR/config.XXXXXX")" || return 1
  if jq "$1 = $2" "$VOICE_CONFIG" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mv "$tmp" "$VOICE_CONFIG"
  else
    rm -f "$tmp"; return 1
  fi
}

expand_home() { printf '%s' "${1/#\~/$HOME}"; }

# Read-aloud is on for every session while $OVOZ_HOME/speak.on exists
# (claude-voice creates it, `ovoz speak on|off` toggles it).
speak_enabled() { [[ -f "$VOICE_SPEAK_FLAG" ]]; }

# Human name of a language code, for the rules shown to Claude.
lang_name() {
  case "$1" in
    uz) echo "Uzbek (Latin script)" ;;
    ru) echo "Russian" ;;
    en) echo "English" ;;
    tr) echo "Turkish" ;;
    kk) echo "Kazakh" ;;
    de) echo "German" ;;
    auto) echo "the language the user spoke" ;;
    *) echo "the language with code '$1'" ;;
  esac
}

# Is there any audio INPUT device? (a Mac mini has none until a mic is plugged in)
mic_present() {
  system_profiler SPAudioDataType 2>/dev/null | grep -q "Input Source"
}

# Put the launchers on PATH. Idempotent; safe to call from a SessionStart hook.
link_launchers() {
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$OVOZ_SCRIPTS/ovoz"            "$HOME/.local/bin/ovoz"
  ln -sfn "$OVOZ_SCRIPTS/claude-voice.sh" "$HOME/.local/bin/claude-voice"
  ln -sfn "$OVOZ_SCRIPTS/agent-sky.sh"    "$HOME/.local/bin/agent-sky"
}
