#!/usr/bin/env bash
# uninstall.sh — remove what install.sh added. Models and config stay unless --purge.
set -u
readonly HOME_DIR="${OVOZ_HOME:-$HOME/.claude/ovoz}"
readonly SETTINGS="$HOME/.claude/settings.json"
rm -f "$HOME/.local/bin/ovoz" "$HOME/.local/bin/claude-voice" "$HOME/.local/bin/agent-sky" && echo "launchers removed"
rm -rf "$HOME/.claude/skills/ovoz" && echo "skill removed"
if [[ -f "$SETTINGS" ]] && command -v jq >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
  tmp="$(mktemp)"
  jq 'walk(if type == "object" and (.hooks | type) == "array"
           then .hooks |= map(select(((.command // "") | test("voice-context.sh|voice-speak.sh")) | not)) else . end)
      | .hooks |= with_entries(.value |= map(select((.hooks | length) > 0)) | select((.value | length) > 0))' "$SETTINGS" > "$tmp" \
    && [[ -s "$tmp" ]] && jq -e . "$tmp" >/dev/null && mv "$tmp" "$SETTINGS" && echo "hooks removed from settings.json" || rm -f "$tmp"
fi
rm -rf "$HOME_DIR/bin" && echo "scripts removed"
if [[ "${1:-}" == "--purge" ]]; then rm -rf "$HOME_DIR" "$HOME/.claude/agent-galaxy" && echo "models, config and agent-galaxy removed"; else echo "kept: $HOME_DIR (models, config) — ./uninstall.sh --purge removes them"; fi
