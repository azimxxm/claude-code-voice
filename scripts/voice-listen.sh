#!/usr/bin/env bash
# voice-listen.sh — the ear of /ovoz: microphone → text → Claude Code, in Uzbek/Russian/English.
#
#   voice-listen.sh --loop --target PANE   the ear pane. mic.mode "ptt" (default): records only while
#                                          the talk key is held (⌥ Space via Hammerspoon) or between two
#                                          Enter presses in the pane; "vad": hands-free, stops at silence.
#                                          Either way the text is typed into the tmux pane (+ Enter).
#   voice-listen.sh --ptt-press | --ptt-release [--print]
#                                          what the hotkey calls: with an ear pane running they raise/lower
#                                          the talk flag; without one they record and type (see --start/--stop)
#   voice-listen.sh --once                 one utterance → transcript on stdout
#   voice-listen.sh --transcribe FILE.wav  transcribe a file → stdout
#   voice-listen.sh --start | --stop [--print] | --toggle
#                                          hold-to-talk for a hotkey (Hammerspoon): --start opens the
#                                          mic, --stop closes it, transcribes, copies the text to the
#                                          clipboard (and prints it with --print)
#   voice-listen.sh --server [--stop-server]  start (or stop) the local whisper-server that keeps
#                                          the model in memory — 1 s per utterance instead of 20 s
#   voice-listen.sh --check                deps + microphone + model (exit 0/1)
#
# Engines (config.json → stt.engine): whisper.cpp (free, offline, default) | gigaam (free,
# offline, uz/ru/kk/ky) | groq | openai | elevenlabs | gemini (cloud, need *_API_KEY in the
# environment — never stored here).
# Language (config.json → lang): uz | ru | en. Whisper's auto-detect mistakes Uzbek for
# Arabic-script languages, so /ovoz always sends the language explicitly.

set -u
source "$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)/voice-lib.sh" || exit 1

readonly SERVER_HOST="127.0.0.1"
readonly SERVER_PORT="${CLAUDE_VOICE_STT_PORT:-8178}"
readonly SERVER_PID="$VOICE_DIR/whisper-server.pid"
readonly SERVER_LOG="$VOICE_DIR/whisper-server.log"
readonly SERVER_MODEL="$VOICE_DIR/whisper-server.model"
readonly GIGAAM_PORT="${CLAUDE_VOICE_GIGAAM_PORT:-8000}"
readonly GIGAAM_URL="http://127.0.0.1:$GIGAAM_PORT"
readonly GIGAAM_PID="$VOICE_DIR/gigaam-server.pid"
readonly GIGAAM_LOG="$VOICE_DIR/gigaam-server.log"

mode=""; target=""; file=""; print_it=0; stop_server=0; FORCE_MODE=""
while (( $# > 0 )); do
  case "$1" in
    --loop)        mode="loop"; shift ;;
    --vad)         mode="loop"; FORCE_MODE="vad"; shift ;;
    --ptt)         mode="loop"; FORCE_MODE="ptt"; shift ;;
    --ptt-press)   mode="ptt-press"; shift ;;
    --ptt-release) mode="ptt-release"; shift ;;
    --once)        mode="once"; shift ;;
    --transcribe)  mode="transcribe"; file="${2:-}"; shift 2 || break ;;
    --start)       mode="start"; shift ;;
    --stop)        mode="stop"; shift ;;
    --toggle)      mode="toggle"; shift ;;
    --server)      mode="server"; shift ;;
    --stop-server) mode="server"; stop_server=1; shift ;;
    --check)       mode="check"; shift ;;
    --target)      target="${2:-}"; shift 2 || break ;;
    --print)       print_it=1; shift ;;
    *) echo "voice-listen: unknown option $1" >&2; exit 2 ;;
  esac
done
[[ -n "$mode" ]] || { sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 2; }

voice_ensure_config

# Per-language models: stt.models.<lang> wins when that file exists (the Uzbek
# fine-tune), otherwise stt.model (large-v3-turbo, good for ru/en).
load_config() {
  LANG_CODE="$(cfg '.lang' 'uz')"
  ENGINE="$(cfg '.stt.engine' 'whisper.cpp')"
  PROMPT="$(cfg '.stt.prompt' '')"
  PREFIX="$(cfg '.transcript_prefix' '🎙 ')"
  AUTO_SUBMIT="$(cfg '.auto_submit' 'true')"
  local per_lang
  per_lang="$(expand_home "$(cfg ".stt.models.\"$LANG_CODE\"" '')")"
  if [[ -n "$per_lang" && -f "$per_lang" ]]; then MODEL="$per_lang"
  else MODEL="$(expand_home "$(cfg '.stt.model' "$VOICE_MODELS/ggml-large-v3-turbo.bin")")"; fi
}
load_config

say_status() { printf '%s\n' "$*"; }

# ── recording ────────────────────────────────────────────────────────────────

# Wait while Claude is speaking (speaking.lock) so the mic never hears the speaker.
wait_for_silence_from_claude() {
  local i=0
  while [[ -f "$VOICE_SPEAKING_LOCK" ]] && (( i < 300 )); do sleep 0.2; i=$(( i + 1 )); done
  [[ $i -gt 0 ]] && sleep 0.4
  return 0
}

# The silence threshold. "auto" (default) measures the room for one second and sets the
# threshold to 3× the noise floor (kept between 2 % and 25 %) — a fixed 2 % never stops
# recording on a hot microphone whose noise alone peaks above it.
THR=""
calibrate_threshold() {
  local conf; conf="$(cfg '.mic.threshold' 'auto')"
  if [[ "$conf" != "auto" ]]; then THR="$conf"; return 0; fi
  local probe="$VOICE_TMP/noise-$$.wav" rms
  rec -q -r 16000 -c 1 -b 16 -e signed-integer "$probe" trim 0 1 2>/dev/null
  rms="$(sox "$probe" -n stat 2>&1 | awk '/RMS +amplitude/ {print $3}')"
  rm -f "$probe"
  THR="$(awk -v r="${rms:-0}" 'BEGIN { t = r * 100 * 3; if (t < 2) t = 2; if (t > 25) t = 25; printf "%.1f%%", t }')"
  vlog "mic noise floor rms=${rms:-?} → threshold $THR"
  printf '%s' "${rms:-0}"
}

# One utterance: starts when sound rises above the threshold, stops after N seconds of
# silence. SoX does the voice-activity detection — no extra daemon needed.
# With SHOW_METER=1 (the loop) SoX's live VU meter stays on screen while it records.
record_utterance() { # wav
  local wav="$1" stop maxsec errlog
  [[ -n "$THR" ]] || calibrate_threshold >/dev/null
  stop="$(cfg '.mic.stop_after_silence' '1.2')"
  maxsec="$(cfg '.mic.max_seconds' '30')"
  errlog="$VOICE_TMP/rec-$$.err"
  rm -f "$wav"
  if [[ "${SHOW_METER:-0}" == 1 ]]; then
    rec -S -r 16000 -c 1 -b 16 -e signed-integer "$wav" \
        silence 1 0.15 "$THR" 1 "$stop" "$THR" trim 0 "$maxsec" 2> >(tee "$errlog" >&2)
  else
    rec -q -r 16000 -c 1 -b 16 -e signed-integer "$wav" \
        silence 1 0.15 "$THR" 1 "$stop" "$THR" trim 0 "$maxsec" 2>"$errlog"
  fi
  sleep 0.1   # let the tee behind the meter flush
  if grep -q "clipped" "$errlog" 2>/dev/null; then
    CLIPPED=1
    grep -E "WARN" "$errlog" >> "$VOICE_LOG" 2>/dev/null || true
  fi
  rm -f "$errlog"
  [[ -s "$wav" ]]
}
CLIPPED=0

# Whisper hallucinates stock phrases on near-silence; drop them.
looks_like_noise() {
  local t="$1"
  [[ "${#t}" -lt 2 ]] && return 0
  printf '%s' "$t" | grep -qiE '^(\[.*\]|\(.*\)|субтитры|продолжение следует|спасибо за просмотр|thank you\.?|thanks for watching|you\.?|\.+|музыка)$' && return 0
  return 1
}

# ── transcription ───────────────────────────────────────────────────────────

server_running() {
  curl -sS --max-time 1 "http://$SERVER_HOST:$SERVER_PORT/" >/dev/null 2>&1
}

start_server() {
  command -v whisper-server >/dev/null 2>&1 || { echo "whisper-server missing — brew install whisper.cpp" >&2; return 1; }
  [[ -f "$MODEL" ]] || { echo "model missing: $MODEL — run voice-setup.sh" >&2; return 1; }
  if server_running; then
    [[ "$(cat "$SERVER_MODEL" 2>/dev/null)" == "$MODEL" ]] && return 0
    stop_server_now   # another language wants another model
  fi
  nohup whisper-server -m "$MODEL" --host "$SERVER_HOST" --port "$SERVER_PORT" -l "$LANG_CODE" -t 6 \
    </dev/null >"$SERVER_LOG" 2>&1 &
  echo $! > "$SERVER_PID"
  echo "$MODEL" > "$SERVER_MODEL"
  local i=0
  while ! server_running && (( i < 120 )); do sleep 0.5; i=$(( i + 1 )); done
  server_running
}

stop_server_now() {
  local pid; pid="$(cat "$SERVER_PID" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
  rm -f "$SERVER_PID" "$SERVER_MODEL"
  pgrep -f "whisper-server -m $VOICE_MODELS" >/dev/null 2>&1 && pkill -f "whisper-server -m $VOICE_MODELS" 2>/dev/null
  local i=0; while server_running && (( i < 20 )); do sleep 0.1; i=$(( i + 1 )); done
  return 0
}

transcribe_whisper_server() { # wav lang
  local args=(-sS --max-time 90 -F "file=@$1" -F "response_format=text" -F "temperature=0.0")
  [[ "$2" != "auto" ]] && args+=(-F "language=$2")
  [[ -n "$PROMPT" ]] && args+=(-F "prompt=$PROMPT")
  curl "${args[@]}" "http://$SERVER_HOST:$SERVER_PORT/inference" 2>>"$VOICE_LOG"
}

transcribe_whisper_cli() { # wav lang
  command -v whisper-cli >/dev/null 2>&1 || { echo "whisper-cli missing — brew install whisper.cpp" >&2; return 1; }
  [[ -f "$MODEL" ]] || { echo "model missing: $MODEL — run voice-setup.sh" >&2; return 1; }
  local args=(-m "$MODEL" -f "$1" -l "$2" -nt -np)
  [[ -n "$PROMPT" ]] && args+=(--prompt "$PROMPT")
  whisper-cli "${args[@]}" 2>>"$VOICE_LOG"
}

# GigaAM Multilingual (ai-babai/gigaam-multilingual-mlx): best measured Uzbek STT on real
# speech (7.3 % WER on FLEURS), one model for uz/ru/kk/ky, no English. Local server.
gigaam_running() { curl -sS --max-time 1 -o /dev/null "$GIGAAM_URL/v1/models" 2>/dev/null || curl -sS --max-time 1 -o /dev/null "$GIGAAM_URL/" 2>/dev/null; }
start_gigaam() {
  command -v gigaam-stt >/dev/null 2>&1 || { echo "gigaam-stt missing — uv tool install 'gigaam-multilingual-mlx[server]'" >&2; return 1; }
  gigaam_running && return 0
  nohup gigaam-stt serve --host 127.0.0.1 --port "$GIGAAM_PORT" --allow-unauthenticated </dev/null >"$GIGAAM_LOG" 2>&1 &
  echo $! > "$GIGAAM_PID"
  local i=0
  while ! gigaam_running && (( i < 240 )); do sleep 0.5; i=$(( i + 1 )); done
  gigaam_running
}
stop_gigaam() {
  local pid; pid="$(cat "$GIGAAM_PID" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
  rm -f "$GIGAAM_PID"
  pgrep -f "gigaam-stt serve" >/dev/null 2>&1 && pkill -f "gigaam-stt serve" 2>/dev/null
  # uvicorn shuts down gracefully; give it 3 s, then insist
  local i=0
  while pgrep -f "gigaam-stt serve" >/dev/null 2>&1 && (( i < 30 )); do sleep 0.1; i=$(( i + 1 )); done
  pgrep -f "gigaam-stt serve" >/dev/null 2>&1 && pkill -9 -f "gigaam-stt serve" 2>/dev/null
  return 0
}

transcribe_openai_compat() { # wav lang url key model
  local wav="$1" lang="$2" url="$3" key="$4" model="$5"
  [[ -n "$key" ]] || { echo "API key missing for $url" >&2; return 1; }
  local args=(-sS --max-time 60 "$url" -H "Authorization: Bearer $key" -F "model=$model" -F "file=@$wav" -F "response_format=text")
  [[ "$lang" != "auto" ]] && args+=(-F "language=$lang")
  [[ -n "$PROMPT" ]] && args+=(-F "prompt=$PROMPT")
  curl "${args[@]}" 2>>"$VOICE_LOG"
}

transcribe_elevenlabs() { # wav lang
  local key="${ELEVENLABS_API_KEY:-}"
  [[ -n "$key" ]] || { echo "ELEVENLABS_API_KEY missing" >&2; return 1; }
  local args=(-sS --max-time 60 "https://api.elevenlabs.io/v1/speech-to-text" -H "xi-api-key: $key" -F "model_id=$(cfg '.stt.cloud_model' 'scribe_v1')" -F "file=@$1")
  case "$2" in uz) args+=(-F language_code=uzb) ;; ru) args+=(-F language_code=rus) ;; en) args+=(-F language_code=eng) ;; esac
  curl "${args[@]}" 2>>"$VOICE_LOG" | jq -r '.text // empty'
}

transcribe_gemini() { # wav lang
  local key="${GEMINI_API_KEY:-}"
  [[ -n "$key" ]] || { echo "GEMINI_API_KEY missing" >&2; return 1; }
  local model b64file body
  model="$(cfg '.stt.cloud_model' 'gemini-2.5-flash')"
  b64file="$(mktemp "$VOICE_TMP/b64.XXXXXX")"
  base64 < "$1" | tr -d '\n' > "$b64file"
  body="$(jq -n --arg t "Transcribe this audio verbatim in $(lang_name "$2"). Uzbek must be Latin script with o' and g' apostrophes. Output only the transcript." \
              --rawfile d "$b64file" '{contents:[{parts:[{text:$t},{inline_data:{mime_type:"audio/wav",data:$d}}]}]}')"
  rm -f "$b64file"
  printf '%s' "$body" | curl -sS --max-time 60 -H 'Content-Type: application/json' -d @- \
    "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key" 2>>"$VOICE_LOG" \
    | jq -r '.candidates[0].content.parts[0].text // empty'
}

transcribe() { # wav → cleaned text on stdout
  local wav="$1" out=""
  case "$ENGINE" in
    whisper.cpp|whisper|local)
      if start_server 2>/dev/null; then out="$(transcribe_whisper_server "$wav" "$LANG_CODE")"
      else out="$(transcribe_whisper_cli "$wav" "$LANG_CODE")"; fi ;;
    gigaam)
      # GigaAM (CTC) rejects prompt conditioning — call without the vocabulary prompt
      if start_gigaam 2>/dev/null; then out="$(PROMPT="" transcribe_openai_compat "$wav" "$LANG_CODE" "$GIGAAM_URL/v1/audio/transcriptions" "local" "whisper-1")"
      else echo "gigaam server unavailable" >&2; return 1; fi ;;
    groq)       out="$(transcribe_openai_compat "$wav" "$LANG_CODE" "https://api.groq.com/openai/v1/audio/transcriptions" "${GROQ_API_KEY:-}"   "$(cfg '.stt.cloud_model' 'whisper-large-v3')")" ;;
    openai)     out="$(transcribe_openai_compat "$wav" "$LANG_CODE" "https://api.openai.com/v1/audio/transcriptions"     "${OPENAI_API_KEY:-}" "$(cfg '.stt.cloud_model' 'gpt-4o-transcribe')")" ;;
    elevenlabs) out="$(transcribe_elevenlabs "$wav" "$LANG_CODE")" ;;
    gemini)     out="$(transcribe_gemini "$wav" "$LANG_CODE")" ;;
    *) echo "unknown stt.engine '$ENGINE' (whisper.cpp | groq | openai | elevenlabs | gemini)" >&2; return 1 ;;
  esac
  out="$(printf '%s' "$out" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')"
  vlog "heard[$ENGINE/$LANG_CODE] $out"
  printf '%s' "$out"
}

# ── delivery ────────────────────────────────────────────────────────────────

deliver_to_pane() { # text
  tmux send-keys -t "$target" -l -- "${PREFIX}$1"
  if [[ "$AUTO_SUBMIT" == "true" ]]; then sleep 0.2; tmux send-keys -t "$target" Enter; fi
}

# ── modes ───────────────────────────────────────────────────────────────────

# ── the two ear loops ───────────────────────────────────────────────────────

# hands-free: SoX voice-activity detection (quiet rooms only)
run_vad_loop() {
    printf '\033[2J\033[H'
  echo "🎙  ovoz — Claude bilan gaplashing   til: $LANG_CODE   engine: $ENGINE   (to'xtatish: Ctrl-C)"
  printf '    Fon shovqini o'"'"'lchanmoqda (1 s jim turing)… '
  noise="$(calibrate_threshold)"
  echo "chegara: $THR   (bir gap ko'pi bilan $(cfg '.mic.max_seconds' '30') s; $(cfg '.mic.stop_after_silence' '1.2') s jimlik = gap tugadi)"
  echo "    Gapiring, jim bo'ling — matn yuqoridagi Claude oynasiga o'zi yoziladi. Pastdagi ko'rsatkich ovozingizni ko'rsatadi."
  echo
  wav="$VOICE_TMP/loop-$$.wav"; trap 'rm -f "$wav"; exit 0' INT TERM EXIT
  n=0
  while tmux display -p -t "$target" '#{pane_id}' >/dev/null 2>&1; do
    load_config
    wait_for_silence_from_claude
    printf '\r\033[K🎙  eshitayapman… (gapiring)\n'
    SHOW_METER=1 record_utterance "$wav" || { printf '\r\033[K'; continue; }
    printf '\r\033[K⏳  yozib olayapman…'
    text="$(transcribe "$wav")" || { printf '\r\033[K⚠️  transkripsiya xatosi (voice.log)\n'; continue; }
    if looks_like_noise "$text"; then printf '\r\033[K'; continue; fi
    printf '\r\033[K📝  %s\n' "$text"
    if (( CLIPPED )); then echo "⚠️  mikrofon juda baland (clipping) — System Settings → Sound → Input darajasini pasaytiring"; CLIPPED=0; fi
    deliver_to_pane "$text"
    n=$(( n + 1 )); (( n % 10 == 0 )) && calibrate_threshold >/dev/null
  done
}

# push-to-talk: record only while the talk key is held (ptt.on exists) or between two Enter
# presses in this pane. Nothing is recorded otherwise — office chatter never reaches Claude.
run_ptt_loop() {
  printf '\033[2J\033[H'
  echo "🎙  ovoz — Claude bilan gaplashing   til: $LANG_CODE   engine: $ENGINE   rejim: tugma   (to'xtatish: Ctrl-C)"
  echo "    ⌥ Space ni BOSIB TURIB gapiring, qo'yib yuboring — matn yuqoridagi Claude oynasiga yoziladi."
  echo "    Hotkey yo'q bo'lsa: shu oynada ⏎ = yozishni boshlash, yana ⏎ = yuborish. Tugma bosilmaganda hech narsa eshitilmaydi."
  echo
  local wav="$VOICE_TMP/ptt-$$.wav" errlog="$VOICE_TMP/ptt-$$.err" recpid key text
  echo $$ > "$VOICE_PTT_LOOP_PID"; rm -f "$VOICE_PTT_FLAG"
  trap 'rm -f "$wav" "$errlog" "$VOICE_PTT_LOOP_PID" "$VOICE_PTT_FLAG"; exit 0' INT TERM EXIT
  while tmux display -p -t "$target" '#{pane_id}' >/dev/null 2>&1; do
    load_config
    printf '\r\033[K🔘  eshitmayapman — ⌥ Space ni bosib turing (yoki ⏎)'
    until [[ -f "$VOICE_PTT_FLAG" ]]; do
      if read -r -s -t 0.15 -n 1 key 2>/dev/null; then touch "$VOICE_PTT_FLAG"; fi
      tmux display -p -t "$target" '#{pane_id}' >/dev/null 2>&1 || return 0
    done
    "$OVOZ_SCRIPTS/voice-speak.sh" --stop >/dev/null 2>&1 || true
    printf '\r\033[K🎙  yozilmoqda… (qo'"'"'yib yuboring yoki ⏎ = yuborish)\n'
    rm -f "$wav"
    rec -S -r 16000 -c 1 -b 16 -e signed-integer "$wav" trim 0 120 2> >(tee "$errlog" >&2) &
    recpid=$!
    while kill -0 "$recpid" 2>/dev/null; do
      [[ -f "$VOICE_PTT_FLAG" ]] || break
      if read -r -s -t 0.15 -n 1 key 2>/dev/null; then break; fi
    done
    kill -INT "$recpid" 2>/dev/null; wait "$recpid" 2>/dev/null
    rm -f "$VOICE_PTT_FLAG"; sleep 0.1
    if grep -q "clipped" "$errlog" 2>/dev/null; then echo "⚠️  mikrofon juda baland (clipping) — System Settings → Sound → Input darajasini pasaytiring"; fi
    [[ -s "$wav" ]] || { printf '\r\033[K'; continue; }
    if (( $(stat -f%z "$wav" 2>/dev/null || echo 0) < 16000 )); then printf '\r\033[K(juda qisqa)\n'; continue; fi   # < 0.5 s
    # silence or faint noise only → whisper would hallucinate for 20 s; skip it
    rms="$(sox "$wav" -n stat 2>&1 | awk '/RMS +amplitude/ {print $3}')"
    if awk -v r="${rms:-0}" 'BEGIN { exit (r < 0.005) ? 0 : 1 }'; then printf '\r\033[K(ovoz eshitilmadi — mikrofon darajasini tekshiring)\n'; continue; fi
    printf '\r\033[K⏳  yozib olayapman…'
    text="$(transcribe "$wav")" || { printf '\r\033[K⚠️  transkripsiya xatosi (voice.log)\n'; continue; }
    if looks_like_noise "$text"; then printf '\r\033[K(hech narsa tushunilmadi)\n'; continue; fi
    printf '\r\033[K📝  %s\n' "$text"
    deliver_to_pane "$text"
  done
}

case "$mode" in
  check)
    problems=0
    for tool in rec curl jq; do
      command -v "$tool" >/dev/null 2>&1 && echo "✓ $tool" || { echo "✗ $tool missing$([[ $tool == rec ]] && echo ' — brew install sox')"; problems=1; }
    done
    case "$ENGINE" in
      whisper.cpp|whisper|local)
        command -v whisper-cli >/dev/null 2>&1 && echo "✓ whisper.cpp" || { echo "✗ whisper.cpp missing — brew install whisper.cpp"; problems=1; }
        [[ -f "$MODEL" ]] && echo "✓ model for '$LANG_CODE': $(basename "$MODEL") ($(du -h "$MODEL" | cut -f1))" || { echo "✗ model missing: $MODEL — voice-setup.sh"; problems=1; }
        uzm="$(expand_home "$(cfg '.stt.models.uz' '')")"
        if [[ -n "$uzm" ]]; then [[ -f "$uzm" ]] && echo "✓ Uzbek fine-tune: $(basename "$uzm")" || echo "· Uzbek fine-tune not built yet — voice-setup.sh --uzbek-model (much better Uzbek than plain Whisper)"; fi
        server_running && echo "✓ whisper-server warm on :$SERVER_PORT" || echo "· whisper-server not running (claude-voice starts it; ~20 s per utterance without it)" ;;
      gigaam)
        command -v gigaam-stt >/dev/null 2>&1 && echo "✓ gigaam-stt (GigaAM Multilingual MLX: uz/ru/kk/ky)" || { echo "✗ gigaam-stt missing — uv tool install 'gigaam-multilingual-mlx[server]'"; problems=1; }
        gigaam_running && echo "✓ gigaam server warm on :$GIGAAM_PORT" || echo "· gigaam server not running (started on first use)" ;;
      *) echo "· cloud engine: $ENGINE (needs its API key in the environment)" ;;
    esac
    echo "  language: $LANG_CODE   auto-submit: $AUTO_SUBMIT"
    if mic_present; then echo "✓ microphone present"; else echo "✗ no audio INPUT device — plug in a USB mic, AirPods or use the iPhone as a mic (Continuity)"; problems=1; fi
    exit $problems ;;

  server)
    if (( stop_server )); then stop_server_now; stop_gigaam; echo "local STT servers stopped"; exit 0; fi
    case "$ENGINE" in
      gigaam) start_gigaam && echo "gigaam server ready on $GIGAAM_URL (uz/ru/kk/ky)" ;;
      *) start_server && echo "whisper-server ready on http://$SERVER_HOST:$SERVER_PORT (model $(basename "$MODEL"), lang $LANG_CODE)" ;;
    esac ;;

  transcribe)
    [[ -s "$file" ]] || { echo "no such file: $file" >&2; exit 1; }
    wav="$file"
    if [[ "$file" != *.wav ]]; then
      wav="$(mktemp "$VOICE_TMP/conv.XXXXXX").wav"
      ffmpeg -y -loglevel error -i "$file" -ar 16000 -ac 1 -c:a pcm_s16le "$wav" || exit 1
      trap 'rm -f "$wav"' EXIT
    fi
    transcribe "$wav"; echo ;;

  once)
    wav="$VOICE_TMP/once-$$.wav"; trap 'rm -f "$wav"' EXIT
    wait_for_silence_from_claude
    record_utterance "$wav" || { echo "nothing recorded" >&2; exit 1; }
    text="$(transcribe "$wav")"
    looks_like_noise "$text" && exit 1
    printf '%s\n' "$text" ;;

  start)
    # hotkey pressed: open the mic until --stop (no silence detection, hard cap 120 s)
    if [[ -f "$VOICE_REC_PID" ]] && kill -0 "$(cat "$VOICE_REC_PID")" 2>/dev/null; then exit 0; fi
    "$0" --stop >/dev/null 2>&1 || true   # discard a stale recording
    wav="$VOICE_TMP/hotkey.wav"; rm -f "$wav"
    rec -q -r 16000 -c 1 -b 16 -e signed-integer "$wav" trim 0 120 2>>"$VOICE_LOG" &
    echo $! > "$VOICE_REC_PID"
    vlog "hotkey: recording" ;;

  stop)
    # hotkey released: close the mic, transcribe, clipboard (+ stdout with --print)
    pid="$(cat "$VOICE_REC_PID" 2>/dev/null || true)"; rm -f "$VOICE_REC_PID"
    [[ -n "$pid" ]] || exit 0
    kill -INT "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    wav="$VOICE_TMP/hotkey.wav"
    [[ -s "$wav" ]] || exit 0
    text="$(transcribe "$wav")"; rm -f "$wav"
    looks_like_noise "$text" && exit 0
    printf '%s' "${PREFIX}${text}" | pbcopy
    (( print_it )) && printf '%s\n' "${PREFIX}${text}"
    exit 0 ;;

  toggle)
    if [[ -f "$VOICE_REC_PID" ]] && kill -0 "$(cat "$VOICE_REC_PID")" 2>/dev/null; then exec "$0" --stop --print; else exec "$0" --start; fi ;;

  loop)
    [[ -n "$target" ]] || { echo "--loop needs --target <tmux pane>" >&2; exit 2; }
    command -v tmux >/dev/null 2>&1 || { echo "tmux missing" >&2; exit 1; }
    command -v rec  >/dev/null 2>&1 || { echo "rec missing — brew install sox" >&2; exit 1; }
    mic_present || echo "⚠️  Mikrofon topilmadi — USB mikrofon, AirPods yoki iPhone (Continuity) ulang."
    case "$ENGINE" in
      whisper.cpp|whisper|local) start_server >/dev/null 2>&1 || echo "⚠️  whisper-server ishga tushmadi — whisper-cli bilan davom (sekinroq)" ;;
      gigaam) start_gigaam >/dev/null 2>&1 || echo "⚠️  gigaam server ishga tushmadi (voice.log)" ;;
    esac
    ear_mode="${FORCE_MODE:-$(cfg '.mic.mode' 'ptt')}"
    if [[ "$ear_mode" == "vad" ]]; then run_vad_loop; else run_ptt_loop; fi
    echo "Claude oynasi yopildi — quloq to'xtadi." ;;

  ptt-press)
    # the talk key went down
    "$OVOZ_SCRIPTS/voice-speak.sh" --stop >/dev/null 2>&1 || true   # never record Claude's own voice
    if [[ -f "$VOICE_PTT_LOOP_PID" ]] && kill -0 "$(cat "$VOICE_PTT_LOOP_PID" 2>/dev/null)" 2>/dev/null; then
      touch "$VOICE_PTT_FLAG"; exit 0            # an ear pane is listening — it records while the flag exists
    fi
    exec "$0" --start ;;                          # no ear pane: record here, type on release

  ptt-release)
    if [[ -f "$VOICE_PTT_LOOP_PID" ]] && kill -0 "$(cat "$VOICE_PTT_LOOP_PID" 2>/dev/null)" 2>/dev/null; then
      rm -f "$VOICE_PTT_FLAG"; exit 0            # the ear pane transcribes and types into Claude
    fi
    exec "$0" --stop $( (( print_it )) && echo --print ) ;;
esac
