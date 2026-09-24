#!/usr/bin/env bash
# install.sh — the non-plugin way in: copies the scripts to ~/.claude/ovoz/bin, installs the
# /ovoz skill, adds the two hooks to ~/.claude/settings.json (backup first, idempotent) and
# links ovoz / claude-voice / agent-sky into ~/.local/bin. Then run: ovoz setup
#
# Prefer the plugin route when you can — it does the same without touching settings.json:
#   claude plugin marketplace add azimxxm/ovoz && claude plugin install ovoz@ovoz
#
#   ./install.sh            install / update
#   ./install.sh --setup    install, then run `ovoz setup` (tools + models) right away

set -u
readonly GREEN=$'\033[0;32m'; readonly YELLOW=$'\033[1;33m'; readonly RED=$'\033[0;31m'; readonly NC=$'\033[0m'
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[fail]${NC} $*"; }

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOME_DIR="${OVOZ_HOME:-$HOME/.claude/ovoz}"
readonly BIN="$HOME_DIR/bin"
readonly SKILL_DST="$HOME/.claude/skills/ovoz"
readonly SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null 2>&1 || { err "jq is required (brew install jq)"; exit 1; }

mkdir -p "$BIN" "$HOME/.claude/skills"
rsync -a --delete "$REPO/scripts/" "$BIN/" && chmod +x "$BIN"/* && ok "scripts → $BIN"
rsync -a --delete "$REPO/skills/ovoz/" "$SKILL_DST/" && ok "skill → $SKILL_DST (/ovoz)"

# hooks — add ours if missing, never touch anything else
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
tmp="$(mktemp)"
jq --arg ctx "f=\"$BIN/voice-context.sh\"; if [ -x \"\$f\" ]; then \"\$f\" 2>/dev/null || true; fi" \
   --arg spk "f=\"$BIN/voice-speak.sh\"; if [ -x \"\$f\" ]; then \"\$f\" --hook 2>/dev/null || true; fi" '
  .hooks //= {}
  | .hooks.UserPromptSubmit //= []
  | (if ([.hooks.UserPromptSubmit[]?.hooks[]?.command // empty] | any(contains("voice-context.sh"))) then . else .hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":$ctx}]}] end)
  | .hooks.Stop //= []
  | (if ([.hooks.Stop[]?.hooks[]?.command // empty] | any(contains("voice-speak.sh"))) then . else .hooks.Stop += [{"hooks":[{"type":"command","command":$spk}]}] end)
' "$SETTINGS" > "$tmp" && [[ -s "$tmp" ]] && jq -e . "$tmp" >/dev/null && mv "$tmp" "$SETTINGS" && ok "hooks in $SETTINGS (UserPromptSubmit, Stop)" || { rm -f "$tmp"; err "could not update settings.json — left untouched"; }

"$BIN/ovoz" link >/dev/null && ok "ovoz, claude-voice, agent-sky → ~/.local/bin"
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "add ~/.local/bin to PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo
if [[ "${1:-}" == "--setup" ]]; then "$BIN/ovoz" setup; else echo "next: ovoz setup   (tools + models, ~10 minutes)   then: claude-voice"; fi
echo "hooks are read when a Claude Code session starts — open a new session afterwards."
