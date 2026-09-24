#!/usr/bin/env bash
# voice-setup.sh — make this Mac ready to talk with Claude Code (free stack, Uzbek by default).
#
#   ovoz setup                       install + check everything (idempotent, safe to re-run)
#   ovoz setup --no-uzbek-model      skip the Uzbek fine-tune (ru/en/… only)
#   ovoz setup --model NAME          general whisper model: large-v3-turbo (default, 1.6 GB),
#                                    large-v3-turbo-q5_0 (0.6 GB), medium, small, base
#   ovoz setup --hotkey              the talk key (Hammerspoon, ⌥ Space): hold, speak, release → the
#                                    ear pane sends it to Claude; without an ear pane it types where
#                                    the cursor is. Recommended: push-to-talk is the default ear mode
#   ovoz setup --reset-config        rewrite config.json with defaults (backup kept)
#   voice-setup.sh --status          the ✓/✗ table only, no changes
#
# The Uzbek model: islomov/rubaistt_v2_medium (Whisper-medium fine-tune, Apache-2.0, ~17 % WER).
# Setup first tries a ready ggml copy (0.5 GB download); if that mirror is not there it builds
# the model itself: ~3 GB download + conversion with whisper.cpp's converter (torch in a venv,
# removed sources afterwards). Nothing leaves the Mac unless you pick a cloud engine.

set -u

readonly GREEN=$'\033[0;32m'; readonly YELLOW=$'\033[1;33m'; readonly RED=$'\033[0;31m'
readonly BLUE=$'\033[0;34m'; readonly DIM=$'\033[2m'; readonly NC=$'\033[0m'
log()  { echo -e "${BLUE}[ovoz]${NC} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[fail]${NC} $*"; }
step() { echo -e "\n${BLUE}==>${NC} $*"; }

source "$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)/voice-lib.sh" || exit 1
readonly LISTEN="$OVOZ_SCRIPTS/voice-listen.sh"
readonly SPEAK="$OVOZ_SCRIPTS/voice-speak.sh"
readonly HF_WHISPER="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
readonly UZ_REPO="islomov/rubaistt_v2_medium"
readonly UZ_GGML="$VOICE_MODELS/ggml-rubaistt-medium-q5_0.bin"
# a ready-made ggml copy of the Uzbek model (same Apache-2.0 weights, already converted)
readonly UZ_GGML_URL="${OVOZ_UZ_GGML_URL:-https://huggingface.co/azimxxm/rubaistt-v2-medium-ggml/resolve/main/ggml-rubaistt-medium-q5_0.bin}"
readonly VENV="$VOICE_DIR/venv"
readonly BUILD="$VOICE_DIR/build"
readonly HS_INIT="$HOME/.hammerspoon/init.lua"
readonly MARK_BEGIN="-- >>> ovoz >>>"
readonly MARK_END="-- <<< ovoz <<<"

status_only=0; want_uz=1; want_hotkey=0; reset_config=0; model_name="large-v3-turbo"
while (( $# > 0 )); do
  case "$1" in
    --status)          status_only=1; shift ;;
    --uzbek-model)     want_uz=1; shift ;;
    --no-uzbek-model)  want_uz=0; shift ;;
    --hotkey)          want_hotkey=1; shift ;;
    --reset-config)    reset_config=1; shift ;;
    --model)           model_name="${2:-large-v3-turbo}"; shift 2 || break ;;
    -h|--help)         sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) err "unknown option $1"; exit 2 ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }

print_status() {
  echo -e "\n${BLUE}ovoz — status${NC}"
  echo "ear (speech → text)"
  "$LISTEN" --check 2>&1 | sed 's/^/  /'
  echo "voice (text → speech)"
  "$SPEAK" --check 2>&1 | sed 's/^/  /'
  echo "glue"
  have tmux && echo "  ✓ tmux" || echo "  ✗ tmux missing — brew install tmux"
  [[ -x "$HOME/.local/bin/ovoz" && -x "$HOME/.local/bin/claude-voice" ]] && echo "  ✓ ovoz, claude-voice, agent-sky on PATH (~/.local/bin)" || echo "  · launchers not linked yet — ovoz setup (or ovoz link)"
  local settings="$HOME/.claude/settings.json"
  if have jq && [[ -f "$settings" ]]; then
    local hooks; hooks="$(jq -r '[.hooks.UserPromptSubmit, .hooks.Stop] | tostring' "$settings" 2>/dev/null)"
    if [[ "$hooks" == *voice-context.sh* && "$hooks" == *voice-speak.sh* ]]; then echo "  ✓ hooks in ~/.claude/settings.json (install.sh route)"
    elif ls "$HOME"/.claude/plugins/cache/*/ovoz >/dev/null 2>&1; then echo "  ✓ hooks come from the ovoz plugin"
    else echo "  ✗ hooks missing — /plugin install ovoz@ovoz, or ./install.sh"; fi
    [[ "$(jq -r '.voice.enabled // .voiceEnabled // false' "$settings")" == "true" ]] && echo "  ✓ Claude Code built-in /voice enabled (hold Space; en/ru and 18 more, no Uzbek)" || echo "  · built-in /voice off — type /voice in Claude Code (English/Russian dictation)"
  fi
  if [[ -f "$HS_INIT" ]] && grep -q "$MARK_BEGIN" "$HS_INIT" 2>/dev/null; then echo "  ✓ talk key: Hammerspoon ⌥ Space (hold to talk)"; else echo "  · talk key not installed — ovoz hotkey (recommended: push-to-talk is the default ear mode; without it press ⏎ in the ear pane)"; fi
  echo "  ear mode: $(cfg '.mic.mode' 'ptt')   (ovoz mode ptt|vad)"
  echo "  config: $VOICE_CONFIG   log: $VOICE_LOG"
  echo
}

if (( status_only )); then voice_ensure_config; print_status; exit 0; fi

# ── 1. tools ────────────────────────────────────────────────────────────────
step "tools"
have brew || { err "Homebrew missing — https://brew.sh"; exit 1; }
if have rec; then ok "sox (rec)"; else brew install sox && ok "sox installed" || warn "sox failed — brew install sox"; fi
if have whisper-cli && have whisper-server; then ok "whisper.cpp"; else brew install whisper.cpp && ok "whisper.cpp installed" || warn "whisper.cpp failed — brew install whisper.cpp"; fi
have ffmpeg || brew install ffmpeg || warn "ffmpeg failed (only needed for non-wav input)"
have jq || brew install jq
have tmux || brew install tmux
if ! have pipx; then brew install pipx && pipx ensurepath >/dev/null 2>&1; fi
if have edge-tts; then ok "edge-tts"; else pipx install edge-tts >/dev/null 2>&1 && ok "edge-tts installed (pipx)" || warn "edge-tts failed — pipx install edge-tts"; fi

# ── 2. general whisper model (ru/en/… and the fallback for everything) ─────
step "whisper model: $model_name"
voice_ensure_dirs
case "$model_name" in
  large-v3-turbo|large-v3-turbo-q5_0|medium|small|base) ;;
  *) err "unknown model '$model_name' (large-v3-turbo | large-v3-turbo-q5_0 | medium | small | base)"; exit 2 ;;
esac
general_model="$VOICE_MODELS/ggml-$model_name.bin"
if [[ -s "$general_model" ]]; then
  ok "$(basename "$general_model") present ($(du -h "$general_model" | cut -f1))"
else
  log "downloading ggml-$model_name.bin from Hugging Face (resumable)…"
  if curl -L --fail --retry 3 -C - -o "$general_model.part" "$HF_WHISPER/ggml-$model_name.bin" && mv "$general_model.part" "$general_model"; then
    ok "downloaded $(basename "$general_model") ($(du -h "$general_model" | cut -f1))"
  else
    err "download failed — check the network and re-run"; rm -f "$general_model.part"
  fi
fi

# ── 3. config ───────────────────────────────────────────────────────────────
step "config"
if (( reset_config )) && [[ -f "$VOICE_CONFIG" ]]; then
  cp "$VOICE_CONFIG" "$VOICE_CONFIG.bak.$(date +%Y%m%d-%H%M%S)" && rm -f "$VOICE_CONFIG" && log "old config backed up"
fi
voice_ensure_config
cfg_set '.stt.model' "\"${general_model/#$HOME/~}\"" || warn "could not write stt.model"
ok "$VOICE_CONFIG (lang=$(cfg '.lang' 'uz'), engine=$(cfg '.stt.engine' 'whisper.cpp'))"

# ── 4. Uzbek fine-tuned model ───────────────────────────────────────────────
if (( want_uz )); then
  step "Uzbek model: $UZ_REPO → whisper.cpp"
  if [[ -s "$UZ_GGML" ]]; then
    ok "$(basename "$UZ_GGML") present ($(du -h "$UZ_GGML" | cut -f1))"
  else
    log "trying the ready-made ggml copy (0.5 GB)…"
    if curl -L --fail --retry 2 -C - -o "$UZ_GGML.part" "$UZ_GGML_URL" 2>/dev/null && mv "$UZ_GGML.part" "$UZ_GGML"; then
      ok "downloaded $(basename "$UZ_GGML") ($(du -h "$UZ_GGML" | cut -f1))"
    else
      rm -f "$UZ_GGML.part"
      log "no ready copy — building it from $UZ_REPO (3 GB download + conversion, one time)"
      have whisper-quantize || { err "whisper-quantize missing (brew install whisper.cpp)"; exit 1; }
      have git || { err "git missing"; exit 1; }
      mkdir -p "$BUILD" "$VOICE_DIR/hf"
      py="$(command -v python3.14 || command -v python3.13 || command -v python3.12 || command -v python3)"
      [[ -x "$VENV/bin/python" ]] || "$py" -m venv "$VENV" || { err "venv failed"; exit 1; }
      log "python deps (torch, transformers) into $VENV — a few minutes the first time"
      "$VENV/bin/pip" install -q --upgrade pip >/dev/null 2>&1
      "$VENV/bin/pip" install -q torch transformers numpy safetensors huggingface_hub || { err "pip install failed"; exit 1; }
      "$VENV/bin/hf" download "$UZ_REPO" --local-dir "$VOICE_DIR/hf/rubaistt_v2_medium" >/dev/null || { err "download failed"; exit 1; }
      [[ -d "$BUILD/whisper" ]] || git clone -q --depth 1 https://github.com/openai/whisper "$BUILD/whisper" || { err "clone openai/whisper failed (mel filters needed)"; exit 1; }
      curl -sSL --fail --max-time 60 -o "$BUILD/convert-h5-to-ggml.py" \
        https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/models/convert-h5-to-ggml.py || { err "could not fetch the converter"; exit 1; }
      rm -rf "$BUILD/out-uz"; mkdir -p "$BUILD/out-uz"
      log "converting to ggml (f16)…"
      "$VENV/bin/python" "$BUILD/convert-h5-to-ggml.py" "$VOICE_DIR/hf/rubaistt_v2_medium" "$BUILD/whisper" "$BUILD/out-uz" >/dev/null 2>&1 \
        || { err "conversion failed — see $BUILD"; exit 1; }
      f16="$(ls "$BUILD"/out-uz/*.bin 2>/dev/null | head -1)"
      [[ -s "$f16" ]] || { err "converter produced no .bin"; exit 1; }
      log "quantizing to q5_0 (5× smaller, same words)…"
      whisper-quantize "$f16" "$UZ_GGML" q5_0 >/dev/null 2>&1 || { err "quantize failed"; exit 1; }
      rm -rf "$BUILD/out-uz" "$VOICE_DIR/hf/rubaistt_v2_medium" "$VENV"   # 4 GB of build material — the ggml is all we keep
      ok "built $(basename "$UZ_GGML") ($(du -h "$UZ_GGML" | cut -f1))"
    fi
  fi
  cfg_set '.stt.models.uz' "\"${UZ_GGML/#$HOME/~}\"" && ok "config: Uzbek uses the fine-tune, other languages use $(basename "$general_model")" || warn "could not write stt.models.uz"
fi

# ── 5. Claude Code: built-in dictation on, launchers on PATH ───────────────
step "Claude Code"
settings="$HOME/.claude/settings.json"
if have jq && [[ -f "$settings" ]] && [[ "$(jq -r '.voice.enabled // .voiceEnabled // false' "$settings")" != "true" ]]; then
  cp "$settings" "$settings.bak.$(date +%Y%m%d-%H%M%S)"
  tmp="$(mktemp)"
  if jq '.voice = ((.voice // {}) + {enabled: true, mode: ((.voice.mode) // "hold")})' "$settings" > "$tmp" && [[ -s "$tmp" ]]; then mv "$tmp" "$settings"; ok "built-in /voice enabled (hold Space — English/Russian dictation)"; else rm -f "$tmp"; warn "could not update settings.json"; fi
fi
link_launchers && ok "ovoz, claude-voice, agent-sky → ~/.local/bin"
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "~/.local/bin is not on PATH in this shell — add: export PATH=\"\$HOME/.local/bin:\$PATH\""

# ── 6. hotkey (optional) ────────────────────────────────────────────────────
if (( want_hotkey )); then
  step "hotkey: Hammerspoon ⌥ Space hold-to-talk"
  if ! brew list --cask hammerspoon >/dev/null 2>&1; then
    brew install --cask hammerspoon && ok "Hammerspoon installed" || warn "Hammerspoon install failed"
  else ok "Hammerspoon present"; fi
  mkdir -p "$(dirname "$HS_INIT")"; touch "$HS_INIT"
  cp "$HS_INIT" "$HS_INIT.bak.$(date +%Y%m%d-%H%M%S)"
  tmp="$(mktemp)"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$HS_INIT" > "$tmp"
  if (( $(wc -c < "$tmp") + 200 < $(wc -c < "$HS_INIT") )) && ! grep -q "$MARK_BEGIN" "$HS_INIT"; then
    warn "init.lua filter looked wrong — keeping the original untouched"; rm -f "$tmp"
  else
    mv "$tmp" "$HS_INIT"
    cat >> "$HS_INIT" <<'LUA'
-- >>> ovoz >>>
-- Talk key for Claude Code: hold ⌥ Space, speak, release.
-- With the ear pane open (claude-voice) the text goes into Claude's tmux pane, wherever you are.
-- Without it, the text is typed where the cursor is.
local ovozBin = os.getenv("HOME") .. "/.local/bin/ovoz"
local ovozConfig = os.getenv("HOME") .. "/.claude/ovoz/config.json"
local ovozAlert
hs.hotkey.bind({"alt"}, "space",
  function()
    hs.execute(ovozBin .. " ptt press", true)
    ovozAlert = hs.alert.show("🎙", 120)
  end,
  function()
    if ovozAlert then hs.alert.closeSpecific(ovozAlert) end
    local out = hs.execute(ovozBin .. " ptt release --print", true) or ""
    out = out:gsub("^%s+", ""):gsub("%s+$", "")
    if out == "" then return end
    hs.eventtap.keyStrokes(out)
    local auto = hs.execute("/usr/bin/env jq -r '.auto_submit' \"" .. ovozConfig .. "\"", true) or ""
    if auto:match("true") then hs.timer.doAfter(0.2, function() hs.eventtap.keyStroke({}, "return") end) end
  end)
-- <<< ovoz <<<
LUA
    ok "hotkey block written to $HS_INIT"
  fi
  open -a Hammerspoon 2>/dev/null || true
  warn "first time: System Settings → Privacy & Security → Accessibility → enable Hammerspoon, then Hammerspoon menu → Reload Config"
fi

# ── 7. microphone ──────────────────────────────────────────────────────────
step "microphone"
if mic_present; then ok "audio input device found"; else
  warn "no audio INPUT device (a Mac mini has no microphone) — plug in a USB mic, connect AirPods, or use your iPhone as a mic (Continuity). The ear picks it up automatically."
fi

print_status
echo "next:  claude-voice     ${DIM}(in a project folder — Claude on top, the ear below)${NC}"
echo "       /ovoz            ${DIM}(inside Claude Code — status, language, speak on/off, sky)${NC}"
