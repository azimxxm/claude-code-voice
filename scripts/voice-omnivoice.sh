#!/usr/bin/env bash
# voice-omnivoice.sh — local OmniVoice voice for ovoz (offline Uzbek TTS + voice cloning).
#
#   ovoz --config                      install / repair: Python venv + mlx-audio + model (~2.3 GB), make it the voice
#   ovoz --clone FILE.wav [--text "exact words"] [--name NAME]
#                                      clone a voice from a 6–10 s recording; without --text the words are
#                                      transcribed with the ovoz ear (check them: they must match the audio)
#   ovoz --clone off                   back to OmniVoice's own voice (no reference)
#   voice-omnivoice.sh --synth "text" OUT.wav [--lang uz]   what voice-speak.sh calls
#   voice-omnivoice.sh --check         ✓/✗ lines for `ovoz status`
#   voice-omnivoice.sh --stop          stop the background model server (frees ~3 GB RAM)
#   voice-omnivoice.sh --remove        delete the venv and the downloaded model (cloned voices stay)
#
# Needs an Apple Silicon Mac (mlx). Weights: k2-fsa/OmniVoice, CC-BY-NC-4.0 — personal and
# non-commercial use only. The model server starts on first use and exits after 10 idle minutes.

set -u
source "$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)/voice-lib.sh" || exit 1

readonly OMNI_DIR="$VOICE_DIR/omnivoice"
readonly OMNI_VENV="$OMNI_DIR/venv"
readonly OMNI_PY="$OMNI_VENV/bin/python"
readonly OMNI_SCRIPT="$OVOZ_SCRIPTS/omnivoice.py"
readonly OMNI_PID="$OMNI_DIR/server.pid"
readonly OMNI_LOG="$OMNI_DIR/server.log"
readonly VOICES_DIR="$VOICE_DIR/voices"
readonly MLX_AUDIO_PIN="mlx-audio==0.6.4"   # the version tested with OmniVoice on Uzbek
readonly MIN_FREE_GB=4
readonly REF_MAX_SECONDS=10

GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()  { echo -e "${BLUE}[ovoz]${NC} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[fail]${NC} $*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

voice_ensure_config
model_id() { cfg '.tts.omnivoice.model' 'mlx-community/OmniVoice-bf16'; }
port()     { cfg '.tts.omnivoice.port' '8179'; }

model_cache_dir() { # where huggingface_hub keeps the weights
  local hub="${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}"
  printf '%s/models--%s' "$hub" "$(model_id | sed 's#/#--#g')"
}

model_downloaded() { ls "$(model_cache_dir)"/snapshots/*/model.safetensors >/dev/null 2>&1; }

find_python() { # Python 3.10+ (mlx wheels exist for 3.10 … 3.14)
  local c
  for c in python3.13 python3.12 python3.11 python3.14 python3.10 python3; do
    if have "$c" && "$c" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
      command -v "$c"; return 0
    fi
  done
  return 1
}

free_gb() { df -k "$HOME" | awk 'NR==2 {print int($4/1048576)}'; }

# --- install ---------------------------------------------------------------------

do_config() {
  log "OmniVoice — offline o'zbekcha ovoz (mlx-audio)"
  [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || { err "Apple Silicon Mac kerak (M1/M2/M3/M4…); bu mashina: $(uname -sm). edge-tts qoladi."; exit 1; }
  ok "Apple Silicon ($(sysctl -n machdep.cpu.brand_string 2>/dev/null))"

  local free; free="$(free_gb)"
  if ! model_downloaded || [[ ! -x "$OMNI_PY" ]]; then
    (( free >= MIN_FREE_GB )) || { err "diskda ${free} GB bo'sh — kamida ${MIN_FREE_GB} GB kerak (model 1.6 GB + venv 0.6 GB + zaxira)"; exit 1; }
  fi
  ok "disk: ${free} GB bo'sh"

  local py; py="$(find_python)"
  if [[ -z "$py" ]]; then
    have brew || { err "Python 3.10+ topilmadi va Homebrew yo'q — https://brew.sh o'rnating, keyin: brew install python"; exit 1; }
    log "Python o'rnatilyapti (brew install python)…"; brew install python || { err "brew install python bajarilmadi"; exit 1; }
    py="$(find_python)" || { err "Python 3.10+ hali ham topilmadi"; exit 1; }
  fi
  ok "python: $py ($("$py" --version 2>&1))"
  if ! have ffmpeg; then
    if have brew; then log "ffmpeg o'rnatilyapti (ovoz klonlash uchun)…"; brew install ffmpeg || warn "ffmpeg o'rnatilmadi — --clone ishlamaydi"; else warn "ffmpeg yo'q — --clone uchun: brew install ffmpeg"; fi
  fi

  mkdir -p "$OMNI_DIR" "$VOICES_DIR"
  if [[ ! -x "$OMNI_PY" ]] || ! "$OMNI_PY" -c 'import sys' 2>/dev/null; then
    rm -rf "$OMNI_VENV"
    log "venv yaratilyapti: $OMNI_VENV"
    "$py" -m venv "$OMNI_VENV" || { err "venv yaratilmadi"; exit 1; }
  fi
  log "kutubxonalar: $MLX_AUDIO_PIN, soundfile (~0.6 GB, bir necha daqiqa)…"
  "$OMNI_PY" -m pip install -q -U pip >/dev/null 2>&1 || true
  "$OMNI_PY" -m pip install -q "$MLX_AUDIO_PIN" soundfile huggingface_hub || { err "pip install bajarilmadi — internetni tekshiring, keyin: ovoz --config"; exit 1; }
  ok "mlx-audio $("$OMNI_PY" -m pip show mlx-audio 2>/dev/null | awk '/^Version/ {print $2}')"

  log "model yuklanyapti: $(model_id) (1.6 GB)…"
  "$OMNI_PY" -I "$OMNI_SCRIPT" download --model "$(model_id)" >/dev/null || { err "model yuklanmadi — qayta: ovoz --config"; exit 1; }
  ok "model: $(model_cache_dir)"

  cfg_set '.tts.engine' '"omnivoice"' && cfg_set '.tts.omnivoice.model' "\"$(model_id)\"" && cfg_set '.tts.omnivoice.steps' "$(cfg '.tts.omnivoice.steps' '32')" || { err "config.json yozilmadi"; exit 1; }
  ok "ovoz dvigateli: omnivoice (edge-tts zaxira bo'lib qoladi)"
  print_sizes
  if [[ -z "$(cfg '.tts.omnivoice.ref_audio' '')" ]]; then
    echo "keyingi qadam — o'z ovozingiz: ovoz --clone ~/Movies/my_voice.wav --text \"yozuvdagi aniq so'zlar\""
  fi
  log "namuna gapiryapti (birinchi marta model xotiraga ~10–100 s yuklanadi)…"
  "$OVOZ_SCRIPTS/voice-speak.sh" --wait --lang uz "Assalomu alaykum. Endi men shu ovozda, internetsiz gapiraman." || warn "namuna gapirilmadi — ovoz log"
}

print_sizes() {
  local venv model
  venv="$(du -sh "$OMNI_VENV" 2>/dev/null | cut -f1)"; model="$(du -shL "$(model_cache_dir)/snapshots" 2>/dev/null | cut -f1)"
  echo "  disk: venv ${venv:-0} + model ${model:-0}   (RAM ishlayotganda ~3 GB)"
}

# --- clone -----------------------------------------------------------------------

# The ear is not set up yet (no ovoz setup)? Use whisper-cli with any ggml model on this Mac.
transcribe_any_whisper() { # wav16k
  have whisper-cli || return 0
  local model
  for model in "$VOICE_MODELS"/ggml-rubaistt-*.bin "$VOICE_MODELS"/ggml-*.bin "$HOME"/.cache/whisper/ggml-*.bin; do
    [[ -f "$model" ]] || continue
    whisper-cli -m "$model" -l "$(cfg '.lang' 'uz')" -nt -np -f "$1" 2>/dev/null | tr '\n' ' ' | sed 's/^ *//; s/ *$//'
    return 0
  done
}

do_clone() {
  local src="" text="" name=""
  while (( $# > 0 )); do
    case "$1" in
      --text) text="${2:-}"; shift 2 || break ;;
      --name) name="${2:-}"; shift 2 || break ;;
      *)      src="$1"; shift ;;
    esac
  done
  if [[ "$src" == "off" ]]; then
    cfg_set '.tts.omnivoice.ref_audio' '""' && cfg_set '.tts.omnivoice.ref_text' '""' && echo "klon o'chirildi — OmniVoice o'z ovozida gapiradi"; return 0
  fi
  src="$(expand_home "$src")"
  [[ -f "$src" ]] || { err "fayl topilmadi: ${src:-?}   usage: ovoz --clone FILE.wav [--text \"...\"] [--name NAME]"; exit 2; }
  have ffmpeg || { err "ffmpeg kerak: brew install ffmpeg"; exit 1; }
  [[ -x "$OMNI_PY" ]] && model_downloaded || { log "OmniVoice hali o'rnatilmagan — avval o'rnataman"; do_config || exit 1; }

  [[ -n "$name" ]] || name="$(basename "${src%.*}" | tr -cs 'A-Za-z0-9_-' '-' | sed 's/-*$//')"
  local dir="$VOICES_DIR/$name"; mkdir -p "$dir"
  local ref="$dir/ref.wav" probe="$dir/ref16k.wav"
  # trim silence at both ends, cut rumble, even loudness, mono 24 kHz, at most 10 s
  ffmpeg -y -loglevel error -i "$src" -af "silenceremove=start_periods=1:start_threshold=-42dB,areverse,silenceremove=start_periods=1:start_threshold=-42dB,areverse,highpass=f=70,loudnorm=I=-18:TP=-2:LRA=11" \
    -ac 1 -ar 24000 -t "$REF_MAX_SECONDS" "$ref" || { err "audio o'qilmadi: $src"; exit 1; }
  local seconds; seconds="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$ref" 2>/dev/null)"
  ok "namuna: $ref (${seconds%.*} s)"
  awk -v s="$seconds" 'BEGIN { exit !(s < 3) }' && warn "namuna juda qisqa (${seconds} s) — 6–10 s tavsiya qilinadi"

  if [[ -z "$text" ]]; then
    log "yozuvdagi so'zlar aniqlanyapti (ovoz ear, $(cfg '.lang' 'uz'))…"
    ffmpeg -y -loglevel error -i "$ref" -ar 16000 -ac 1 -c:a pcm_s16le "$probe" && text="$("$OVOZ_SCRIPTS/voice-listen.sh" --transcribe "$probe" 2>/dev/null)"
    [[ -n "$text" ]] || text="$(transcribe_any_whisper "$probe")"
    rm -f "$probe"
    [[ -n "$text" ]] || { err "so'zlarni aniqlab bo'lmadi — o'zingiz bering: ovoz --clone \"$src\" --text \"...\""; exit 1; }
    warn "avtomatik matn: \"$text\""
    warn "agar yozuvdagi so'zlar boshqacha bo'lsa — aniq matn bilan qayta: ovoz --clone \"$src\" --text \"...\" (ton barqarorligi shunga bog'liq)"
  fi
  printf '%s\n' "$text" > "$dir/ref.txt"
  cfg_set '.tts.engine' '"omnivoice"' && cfg_set '.tts.omnivoice.ref_audio' "\"$ref\"" \
    && cfg_set '.tts.omnivoice.ref_text' "$(jq -Rn --arg t "$text" '$t')" && cfg_set '.tts.omnivoice.voice' "\"$name\"" \
    || { err "config.json yozilmadi"; exit 1; }
  ok "ovoz klonlandi: $name — endi hamma javoblar shu ovozda"
  "$OVOZ_SCRIPTS/voice-speak.sh" --wait --lang uz "Salom! Endi men sizning ovozingizda gapiraman. Qanday chiqdi?" || warn "namuna gapirilmadi — ovoz log"
}

# --- server + synth --------------------------------------------------------------

server_up() { curl -s --max-time 2 "http://127.0.0.1:$(port)/health" 2>/dev/null | grep -q '"ok": true'; }

start_server() {
  server_up && return 0
  [[ -x "$OMNI_PY" ]] || return 1
  mkdir -p "$OMNI_DIR"
  nohup "$OMNI_PY" -I "$OMNI_SCRIPT" serve --model "$(model_id)" --port "$(port)" --idle "$(cfg '.tts.omnivoice.idle_seconds' '600')" \
    </dev/null >>"$OMNI_LOG" 2>&1 &
  echo $! > "$OMNI_PID"
  local i
  for (( i = 0; i < 240; i++ )); do # first load after a reboot can take ~2 min
    server_up && return 0
    kill -0 "$(cat "$OMNI_PID")" 2>/dev/null || return 1
    sleep 0.5
  done
  return 1
}

stop_server() {
  local pid; pid="$(cat "$OMNI_PID" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null && echo "omnivoice server stopped ($pid)"
  rm -f "$OMNI_PID"
}

do_synth() { # text out [--lang xx]
  local text="$1" out="$2" lang
  lang="$(cfg '.tts.lang' 'uz')"
  [[ "${3:-}" == "--lang" && -n "${4:-}" ]] && lang="$4"
  local ref ref_text steps
  ref="$(expand_home "$(cfg '.tts.omnivoice.ref_audio' '')")"; ref_text="$(cfg '.tts.omnivoice.ref_text' '')"; steps="$(cfg '.tts.omnivoice.steps' '32')"
  [[ -n "$ref" && ! -f "$ref" ]] && { vlog "omnivoice: ref audio missing ($ref) — own voice"; ref=""; }
  [[ -n "$ref" ]] || ref_text=""
  if start_server; then
    local body resp
    body="$(jq -n --arg text "$text" --arg out "$out" --arg lang "$lang" --arg ref "$ref" --arg rt "$ref_text" --argjson steps "$steps" \
      '{text:$text, out:$out, lang:$lang, ref:$ref, ref_text:$rt, steps:$steps}')"
    resp="$(curl -s --max-time 120 -H 'Content-Type: application/json' -d "$body" "http://127.0.0.1:$(port)/synth")"
    if [[ "$resp" == *'"ok": true'* && -s "$out" ]]; then vlog "omnivoice ${resp}"; return 0; fi
    vlog "omnivoice server failed: ${resp:-no answer}"
  fi
  [[ -x "$OMNI_PY" ]] || return 1
  # server could not start — one shot (slower: loads the model each time)
  "$OMNI_PY" -I "$OMNI_SCRIPT" synth --model "$(model_id)" --lang "$lang" --steps "$steps" --text "$text" --out "$out" \
    ${ref:+--ref "$ref" --ref-text "$ref_text"} 2>>"$VOICE_LOG" && [[ -s "$out" ]]
}

do_check() {
  local problems=0
  if [[ "$(uname -m)" != "arm64" ]]; then echo "· omnivoice: Apple Silicon emas — edge-tts ishlatiladi"; return 0; fi
  [[ -x "$OMNI_PY" ]] && echo "✓ omnivoice venv ($OMNI_VENV)" || { echo "✗ omnivoice o'rnatilmagan — ovoz --config"; problems=1; }
  model_downloaded && echo "✓ omnivoice model $(model_id)" || { echo "✗ omnivoice model yuklanmagan — ovoz --config"; problems=1; }
  local ref; ref="$(cfg '.tts.omnivoice.ref_audio' '')"
  if [[ -n "$ref" && -f "$(expand_home "$ref")" ]]; then echo "✓ klon ovoz: $(cfg '.tts.omnivoice.voice' '?') ($ref)"
  else echo "· klon yo'q — OmniVoice o'z ovozida (ovoz --clone FILE.wav)"; fi
  server_up && echo "✓ model server ishlayapti (127.0.0.1:$(port))" || echo "· model server to'xtagan — birinchi gapda o'zi ishga tushadi"
  return $problems
}

do_remove() {
  stop_server >/dev/null
  rm -rf "$OMNI_VENV" && echo "o'chirildi: $OMNI_VENV"
  rm -rf "$(model_cache_dir)" && echo "o'chirildi: $(model_cache_dir)"
  cfg_set '.tts.engine' '"edge-tts"' && echo "ovoz dvigateli: edge-tts (klonlangan namunalar qoldi: $VOICES_DIR)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  --config|config|setup) do_config ;;
  --clone|clone)         do_clone "$@" ;;
  --synth)               [[ $# -ge 2 ]] || { err "usage: --synth \"text\" OUT.wav [--lang uz]"; exit 2; }; do_synth "$@" ;;
  --check)               do_check ;;
  --serve)               start_server && echo "omnivoice server: 127.0.0.1:$(port)" ;;
  --stop)                stop_server ;;
  --remove)              do_remove ;;
  --sizes)               print_sizes ;;
  -h|--help|"")          sed -n '2,15p' "${BASH_SOURCE[0]}" ;;
  *)                     err "unknown: $cmd"; sed -n '2,15p' "${BASH_SOURCE[0]}" >&2; exit 2 ;;
esac
