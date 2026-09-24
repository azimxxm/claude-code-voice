#!/usr/bin/env bash
# claude-voice.sh — talk to Claude Code like a person: one tmux window, Claude on top,
# the ear at the bottom, Claude's answers read aloud in Uzbek.
#
#   claude-voice [name]              start (or re-attach to) a voice session for this project folder
#   claude-voice --ear [session]     add the ear pane to a tmux session that is already running
#                                    (the one you are in by default, or any named session)
#   claude-voice --list              running voice sessions
#   claude-voice --stop [name]       stop one (Claude, the ear and the whisper-server go with it)
#   claude-voice --status            what works, what is missing
#   -- <args>                        everything after -- goes to `claude` as is
#
# What happens: the bottom pane runs voice-listen.sh --loop (SoX records until you fall
# silent, whisper.cpp transcribes in the language from ~/.claude/ovoz/config.json, tmux
# types the text into Claude's pane and presses Enter). Two hooks do the rest:
# voice-context.sh tells Claude the conversation is spoken, voice-speak.sh reads the
# 🔊 line of every answer with a free Microsoft neural voice (edge-tts).

set -u

readonly GREEN=$'\033[0;32m'; readonly YELLOW=$'\033[1;33m'; readonly RED=$'\033[0;31m'
readonly BLUE=$'\033[0;34m'; readonly DIM=$'\033[2m'; readonly NC=$'\033[0m'
log()  { echo -e "${BLUE}[voice]${NC} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[fail]${NC} $*"; }

readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/voice-lib.sh" || exit 1
readonly LISTEN="$SCRIPT_DIR/voice-listen.sh"
readonly SETUP="$SCRIPT_DIR/voice-setup.sh"
readonly PREFIX_SESSION="voice-"
readonly EAR_HEIGHT=4

action="start"; name=""; ear_session=""; extra_args=()
while (( $# > 0 )); do
  case "$1" in
    --ear)    action="ear"; if [[ -n "${2:-}" && "${2:-}" != -* ]]; then ear_session="$2"; shift; fi; shift ;;
    --list)   action="list"; shift ;;
    --stop)   action="stop"; shift ;;
    --status) action="status"; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --) shift; extra_args=("$@"); break ;;
    -*) err "unknown option $1"; exit 2 ;;
    *)  name="$1"; shift ;;
  esac
done

need_tmux() { command -v tmux >/dev/null 2>&1 || { err "tmux missing — brew install tmux"; exit 1; }; }
default_name() { basename "$PWD" | tr -c 'A-Za-z0-9_-\n' '-'; }
session_name() { echo "${PREFIX_SESSION}$1"; }

# Split the window of $1 (a tmux session or pane) and run the ear against the pane
# that is active right now — that is where Claude is.
attach_ear() { # session
  local sess="$1" claude_pane
  claude_pane="$(tmux display -p -t "$sess" '#{pane_id}' 2>/dev/null)" || { err "no tmux session '$sess'"; return 1; }
  if tmux list-panes -t "$sess" -F '#{pane_start_command}' 2>/dev/null | grep -q "voice-listen.sh --loop"; then
    warn "the ear is already listening in $sess"; return 0
  fi
  local ear_pane
  ear_pane="$(tmux split-window -v -l "$EAR_HEIGHT" -t "$claude_pane" -c "$PWD" -P -F '#{pane_id}' "$LISTEN --loop --target $claude_pane")" \
    || { err "tmux could not open the ear pane"; return 1; }
  # tmux grows panes proportionally when the window is resized; keep the ear at its height
  tmux set-hook -t "$sess" client-resized "resize-pane -t $ear_pane -y $EAR_HEIGHT" 2>/dev/null || true
  tmux set-hook -t "$sess" window-layout-changed "resize-pane -t $ear_pane -y $EAR_HEIGHT" 2>/dev/null || true
  tmux resize-pane -t "$ear_pane" -y "$EAR_HEIGHT" 2>/dev/null || true
  tmux select-pane -t "$claude_pane"
  speak_on_for "$(tmux display -p -t "$claude_pane" '#{pane_current_path}' 2>/dev/null || echo "$PWD")"
  ok "ear attached to $sess — speak; read-aloud is ON (/ovoz speak off turns it off)"
}

case "$action" in
  list)
    need_tmux
    tmux list-sessions -F '#{session_name} #{session_windows}w #{?session_attached,attached,detached}' 2>/dev/null | grep "^${PREFIX_SESSION}" || echo "no voice sessions" ;;

  status)
    "$SETUP" --status ;;

  stop)
    need_tmux
    target="$(session_name "${name:-$(default_name)}")"
    if tmux has-session -t "=$target" 2>/dev/null; then
      tmux kill-session -t "=$target" && ok "stopped $target"
    else
      warn "no session named $target"
    fi
    "$LISTEN" --stop-server >/dev/null 2>&1 || true
    rm -f "$VOICE_SPEAK_FLAG"
    ok "read-aloud OFF, whisper-server stopped" ;;

  ear)
    need_tmux
    if [[ -z "$ear_session" ]]; then
      [[ -n "${TMUX:-}" ]] || { err "not inside tmux — name the session: claude-voice --ear my-session"; exit 1; }
      ear_session="$(tmux display -p '#{session_name}')"
    fi
    attach_ear "$ear_session" ;;

  start)
    need_tmux
    command -v claude >/dev/null 2>&1 || { err "claude is not on PATH"; exit 1; }
    if [[ "$PWD" == "$HOME" ]]; then
      err "start it from a project folder — Claude Code never saves workspace trust for your home directory"
      exit 1
    fi
    if ! "$LISTEN" --check >/dev/null 2>&1; then
      warn "voice setup is incomplete:"; "$LISTEN" --check 2>&1 | sed 's/^/     /'
      echo "     fix with: $SETUP   (or inside Claude: /ovoz setup)"
    fi
    name="${name:-$(default_name)}"
    target="$(session_name "$name")"
    if tmux has-session -t "=$target" 2>/dev/null; then
      log "$target is already running — attaching (detach: Ctrl-b d)"
      [[ -t 1 ]] && exec tmux attach -t "=$target"
      exit 0
    fi
    claude_cmd="$(printf '%q ' claude ${extra_args[@]+"${extra_args[@]}"})"
    tmux new-session -d -s "$target" -c "$PWD" -e "CLAUDE_VOICE_MODE=1" "$claude_cmd" \
      || { err "tmux could not start the session"; exit 1; }
    attach_ear "$target" || true
    echo ""
    echo "  ${GREEN}✓${NC} Claude Code — top pane (type there any time, voice and keyboard mix freely)"
    echo "  ${GREEN}✓${NC} the ear — bottom pane: speak in $(cfg '.lang' 'uz'), pause, the text is sent"
    echo "  ${GREEN}✓${NC} answers read aloud with $(cfg ".tts.voices.\"$(cfg '.tts.lang' 'uz')\"" 'edge-tts')"
    echo ""
    echo "  change language → /ovoz uz | ru | en      quiet → /ovoz speak off      stop → claude-voice --stop ${name}"
    echo "  ${DIM}detach with Ctrl-b d — Claude keeps running; claude-voice ${name} re-attaches.${NC}"
    echo ""
    [[ -t 1 ]] && exec tmux attach -t "=$target" ;;
esac
