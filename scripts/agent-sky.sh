#!/usr/bin/env bash
# agent-sky.sh — see the agents as stars.
#
#   agent-sky              GALAXY: your whole agent team as a living galaxy — teams are planets,
#                          agents orbit as satellites (taehyeonglim/agent-galaxy, MIT, zero deps,
#                          built from ~/.claude/agents/*.md). http://127.0.0.1:8420
#   agent-sky --live       LIVE: every running session, subagent and tool call drawn as a glowing
#                          node graph on a starry canvas (patoles/agent-flow, `npx agent-flow-app`).
#                          http://127.0.0.1:3001
#   agent-sky --stop       stop both, and remove the hooks Agent Flow adds to ~/.claude/settings.json
#   agent-sky --status     what is running
#   --no-open              (with either start) do not open the browser
#
# Agent Flow installs its own hook entries into ~/.claude/settings.json every time it starts
# (node hook.js → HTTP to the local server, 2 s timeout). While its server is down those hooks
# still spawn node on every tool call and fail — so --stop strips them again (backup first).
# Re-running install.sh also drops them; the next
# `agent-sky --live` puts them back. Everything is local (127.0.0.1); nothing leaves the Mac.

set -u
readonly GREEN=$'\033[0;32m'; readonly YELLOW=$'\033[1;33m'; readonly RED=$'\033[0;31m'; readonly BLUE=$'\033[0;34m'; readonly DIM=$'\033[2m'; readonly NC=$'\033[0m'
log()  { echo -e "${BLUE}[sky]${NC} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[fail]${NC} $*"; }

readonly STATE="${OVOZ_HOME:-$HOME/.claude/ovoz}"
readonly AGENTS_DIR="$HOME/.claude/agents"
readonly GALAXY_DIR="${CLAUDE_GALAXY_DIR:-$HOME/.claude/agent-galaxy}"
readonly GALAXY_REPO="https://github.com/taehyeonglim/agent-galaxy"
readonly GALAXY_PORT="${CLAUDE_GALAXY_PORT:-8420}"
readonly GALAXY_URL="http://127.0.0.1:$GALAXY_PORT"
readonly GALAXY_PID="$STATE/agent-galaxy.pid"
readonly GALAXY_LOG="$STATE/agent-galaxy.log"
readonly FLOW_PORT="${CLAUDE_SKY_PORT:-3001}"
readonly FLOW_URL="http://127.0.0.1:$FLOW_PORT"
readonly FLOW_PID="$STATE/agent-flow.pid"
readonly FLOW_LOG="$STATE/agent-flow.log"
readonly SETTINGS="$HOME/.claude/settings.json"

up() { curl -sS --max-time 1 -o /dev/null "$1/" 2>/dev/null; }
hooks_present() { grep -q "agent-flow/hook.js" "$SETTINGS" 2>/dev/null; }
kill_pidfile() { # pidfile
  local pid; pid="$(cat "$1" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; fi
  rm -f "$1"
}
wait_up() { # url
  for _ in $(seq 1 120); do up "$1" && return 0; sleep 0.5; done
  return 1
}

strip_flow_hooks() {
  hooks_present || return 0
  command -v jq >/dev/null 2>&1 || { warn "jq missing — cannot clean settings.json"; return 1; }
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
  local tmp; tmp="$(mktemp)"
  if jq 'walk(if type == "object" and (.hooks | type) == "array"
              then .hooks |= map(select(((.command // "") | contains("agent-flow/hook.js")) | not))
              else . end)
         | .hooks |= with_entries(.value |= map(select((.hooks | length) > 0)) | select((.value | length) > 0))' \
       "$SETTINGS" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]] && jq -e . "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$SETTINGS" && ok "Agent Flow hooks removed from settings.json (backup kept)"
  else
    rm -f "$tmp"; err "could not rewrite settings.json — left untouched"; return 1
  fi
}

start_galaxy() {
  command -v node >/dev/null 2>&1 || { err "node missing — brew install node"; return 1; }
  command -v git  >/dev/null 2>&1 || { err "git missing"; return 1; }
  if [[ ! -f "$GALAXY_DIR/galaxy.mjs" ]]; then
    log "fetching agent-galaxy (MIT, zero dependencies) into $GALAXY_DIR"
    git clone -q --depth 1 "$GALAXY_REPO" "$GALAXY_DIR" || { err "clone failed"; return 1; }
  fi
  mkdir -p "$STATE"
  if up "$GALAXY_URL"; then ok "galaxy already running on $GALAXY_URL"; return 0; fi
  ( cd "$GALAXY_DIR" && nohup node galaxy.mjs --scan "$AGENTS_DIR" --serve --port "$GALAXY_PORT" </dev/null >"$GALAXY_LOG" 2>&1 & echo $! > "$GALAXY_PID" )
  wait_up "$GALAXY_URL" || { err "galaxy did not start — see $GALAXY_LOG"; return 1; }
  ok "galaxy → $GALAXY_URL   ($(grep -o '[0-9]* agents' "$GALAXY_LOG" | tail -1 || echo 'your agents') from $AGENTS_DIR)"
  echo "     drag = orbit · wheel = zoom · hover a planet = agent roster · F = fullscreen · R = replay"
}

start_flow() {
  command -v npx >/dev/null 2>&1 || { err "node/npx missing — brew install node"; return 1; }
  mkdir -p "$STATE"
  if up "$FLOW_URL"; then ok "Agent Flow already running on $FLOW_URL"; return 0; fi
  nohup npx -y agent-flow-app --port "$FLOW_PORT" --no-open </dev/null >"$FLOW_LOG" 2>&1 &
  echo $! > "$FLOW_PID"
  wait_up "$FLOW_URL" || { err "Agent Flow did not start — see $FLOW_LOG"; return 1; }
  ok "Agent Flow → $FLOW_URL"
  log "sessions started from now on stream every subagent and tool call into the graph (hooks are read at session start)"
}

mode="galaxy"; no_open=0
for arg in "$@"; do
  case "$arg" in
    --live)    mode="flow" ;;
    --stop)    mode="stop" ;;
    --status)  mode="status" ;;
    --no-open) no_open=1 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) err "unknown option $arg"; exit 2 ;;
  esac
done

case "$mode" in
  galaxy)
    start_galaxy || exit 1
    (( no_open )) || open "$GALAXY_URL" 2>/dev/null || true
    echo "  ${DIM}live activity instead: agent-sky --live     stop: agent-sky --stop${NC}" ;;
  flow)
    start_flow || exit 1
    (( no_open )) || open "$FLOW_URL" 2>/dev/null || true
    echo "  ${DIM}stop (and remove its hooks): agent-sky --stop${NC}" ;;
  stop)
    kill_pidfile "$GALAXY_PID"; pgrep -f "galaxy.mjs --scan" >/dev/null 2>&1 && pkill -f "galaxy.mjs --scan" 2>/dev/null
    up "$GALAXY_URL" || ok "galaxy stopped"
    kill_pidfile "$FLOW_PID"; pgrep -f "agent-flow-app" >/dev/null 2>&1 && pkill -f "agent-flow-app" 2>/dev/null
    up "$FLOW_URL" || ok "Agent Flow stopped"
    strip_flow_hooks ;;
  status)
    up "$GALAXY_URL" && echo "✓ galaxy running on $GALAXY_URL" || echo "· galaxy not running (agent-sky)"
    up "$FLOW_URL" && echo "✓ Agent Flow running on $FLOW_URL" || echo "· Agent Flow not running (agent-sky --live)"
    hooks_present && echo "✓ Agent Flow hooks in settings.json (new sessions stream events)" || echo "· no Agent Flow hooks in settings.json"
    [[ -f "$GALAXY_DIR/galaxy.mjs" ]] && echo "✓ agent-galaxy fetched at $GALAXY_DIR" || echo "· agent-galaxy not fetched yet (first agent-sky run does it)" ;;
esac
