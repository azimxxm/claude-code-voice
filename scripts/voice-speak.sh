#!/usr/bin/env bash
# voice-speak.sh — text → speech for /ovoz (Uzbek, Russian, English).
#
#   voice-speak.sh "matn"                speak now, in the configured language
#   voice-speak.sh --lang ru "текст"     pick the language (uz | ru | en) for this call
#   voice-speak.sh --voice NAME "matn"   pick an edge-tts voice for this call (uz-UZ-SardorNeural, …)
#   voice-speak.sh --wait "matn"         block until playback ends (default: return at once)
#   voice-speak.sh --hook                Stop hook: read the 🔊 line of Claude's last message aloud
#   voice-speak.sh --stop                stop whatever is playing
#   voice-speak.sh --check               is text-to-speech ready? (exit 0/1)
#   voice-speak.sh --extract < reply.md  print the line that would be spoken (no audio) — for tests
#
# Engine: edge-tts (free Microsoft neural voices — the only free Uzbek voices that sound
# human: uz-UZ-MadinaNeural / uz-UZ-SardorNeural). Falls back to macOS `say` for ru/en
# when there is no network; there is no offline Uzbek voice on macOS.
#
# Hook mode never fails the turn (always exit 0) and never blocks it: synthesis and
# playback run detached, with stdout/stderr closed so Claude Code does not wait on them.

set -u
source "$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)/voice-lib.sh" || exit 1

mode="say"; lang=""; voice_override=""; wait_for_it=0; text=""
while (( $# > 0 )); do
  case "$1" in
    --hook)  mode="hook"; shift ;;
    --stop)  mode="stop"; shift ;;
    --check) mode="check"; shift ;;
    --extract) mode="extract"; shift ;;
    --wait)  wait_for_it=1; shift ;;
    --lang)  lang="${2:-}"; shift 2 || break ;;
    --voice) voice_override="${2:-}"; shift 2 || break ;;
    *)       text="${text:+$text }$1"; shift ;;
  esac
done

voice_ensure_config
[[ -n "$lang" ]] || lang="$(cfg '.tts.lang' 'uz')"

fail() { [[ "$mode" == "hook" ]] && exit 0; echo "voice-speak: $1" >&2; exit 1; }

stop_playback() {
  local pid
  pid="$(cat "$VOICE_PLAYING_PID" 2>/dev/null || true)"
  if [[ -n "$pid" ]]; then
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$VOICE_PLAYING_PID" "$VOICE_SPEAKING_LOCK"
}

# Play a clip detached. The lock file tells voice-listen.sh to keep the mic closed
# meanwhile, so the ear never transcribes Claude's own voice.
play_clip() {
  local clip="$1"
  nohup bash -c '
    lock="$1"; pidf="$2"; clip="$3"
    echo $$ > "$pidf"; echo $$ > "$lock"
    afplay "$clip"
    rm -f "$clip" "$lock" "$pidf"
  ' _ "$VOICE_SPEAKING_LOCK" "$VOICE_PLAYING_PID" "$clip" </dev/null >/dev/null 2>&1 &
  local pid=$!
  (( wait_for_it )) && wait "$pid"
  return 0
}

speak() { # text lang
  local say_text="$1" say_lang="$2" engine voice rate clip
  engine="$(cfg '.tts.engine' 'edge-tts')"
  voice="${voice_override:-$(cfg ".tts.voices.\"$say_lang\"" '')}"
  rate="$(cfg '.tts.rate' '+0%')"
  stop_playback
  voice_ensure_dirs
  clip="$VOICE_TMP/say-$$-$RANDOM.mp3"
  if [[ "$engine" == "edge-tts" && -n "$voice" ]] && command -v edge-tts >/dev/null 2>&1; then
    if edge-tts --voice "$voice" --rate="$rate" --text "$say_text" --write-media "$clip" >/dev/null 2>>"$VOICE_LOG" && [[ -s "$clip" ]]; then
      vlog "speak[$voice] ${say_text:0:80}"
      play_clip "$clip"
      return 0
    fi
    vlog "edge-tts failed (offline?) — trying macOS say"
    rm -f "$clip"
  fi
  # offline fallback — macOS ships Russian and English voices, no Uzbek one
  case "$say_lang" in
    ru) nohup say -v Milena "$say_text" </dev/null >/dev/null 2>&1 & ;;
    en) nohup say "$say_text" </dev/null >/dev/null 2>&1 & ;;
    *)  vlog "no offline voice for '$say_lang' — nothing spoken"; return 1 ;;
  esac
  (( wait_for_it )) && wait
  return 0
}

# The 🔊 line if Claude wrote one; otherwise the first ~350 characters of plain prose.
spoken_line() {
  local body="$1" line
  line="$(printf '%s\n' "$body" | grep -m1 '🔊' | sed 's/.*🔊[[:space:]]*//')"
  if [[ -z "$line" ]]; then
    line="$(printf '%s\n' "$body" \
      | sed -e '/^```/,/^```/d' -e '/^[[:space:]]*|/d' \
      | tr '\n' ' ' \
      | sed -E 's/`[^`]*`//g; s#https?://[^ ]+##g; s/[*_#>~]//g; s/  +/ /g' \
      | python3 -c 'import sys; print(sys.stdin.read().strip()[:350])' 2>/dev/null)"
  fi
  printf '%s' "$line"
}

last_assistant_text_from_transcript() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  jq -r -s '
    map(select(.type == "assistant"))
    | map(.message.content
          | if type == "array" then map(select(.type == "text") | .text) | join("\n") else tostring end)
    | map(select(length > 0))
    | last // empty' "$path" 2>/dev/null
}

case "$mode" in
  extract)
    body="$(cat 2>/dev/null || true)"; spoken_line "$body"; echo; exit 0 ;;
  stop)
    stop_playback; echo "stopped"; exit 0 ;;

  check)
    problems=0
    if command -v edge-tts >/dev/null 2>&1; then echo "✓ edge-tts ($(edge-tts --version 2>/dev/null | head -1))"; else echo "✗ edge-tts missing — pipx install edge-tts"; problems=1; fi
    command -v afplay >/dev/null 2>&1 && echo "✓ afplay" || { echo "✗ afplay missing"; problems=1; }
    echo "  voice uz: $(cfg '.tts.voices.uz' '-')   ru: $(cfg '.tts.voices.ru' '-')   en: $(cfg '.tts.voices.en' '-')"
    if speak_enabled; then echo "✓ read-aloud ON (speak.on exists)"; else echo "· read-aloud off — claude-voice or /ovoz speak on turns it on"; fi
    exit $problems ;;

  hook)
    [[ -f "$VOICE_SPEAK_FLAG" ]] || exit 0
    payload="$(cat 2>/dev/null || true)"
    [[ -n "$payload" ]] || exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    speak_enabled "$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
    body="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
    if [[ -z "$body" ]]; then
      transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
      body="$(last_assistant_text_from_transcript "$transcript")"
    fi
    [[ -n "$body" ]] || exit 0
    line="$(spoken_line "$body")"
    [[ -n "$line" ]] || exit 0
    speak "$line" "$lang" || true
    exit 0 ;;

  say)
    [[ -n "$text" ]] || fail "nothing to say — usage: voice-speak.sh \"matn\""
    speak "$text" "$lang" ;;
esac
