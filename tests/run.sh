#!/usr/bin/env bash
# tests/run.sh — no microphone, no network: syntax, config, hook payloads, the 🔊 extractor.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export OVOZ_HOME="$(mktemp -d "${TMPDIR:-/tmp}/ovoz-test.XXXXXX")"
pass=0; fail=0
t() { if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ ${TEST_NAME:-$*}"; else fail=$((fail+1)); echo "  ✗ ${TEST_NAME:-$*}"; fi; }

echo "syntax"
for f in scripts/*.sh scripts/ovoz install.sh uninstall.sh; do TEST_NAME="bash -n $f" t bash -n "$f"; done
TEST_NAME="hooks.json is valid JSON" t jq -e . hooks/hooks.json
TEST_NAME="plugin.json is valid JSON" t jq -e . .claude-plugin/plugin.json
TEST_NAME="marketplace.json is valid JSON" t jq -e . .claude-plugin/marketplace.json

echo "config"
source scripts/voice-lib.sh
voice_ensure_config
TEST_NAME="default config is valid JSON" t jq -e . "$VOICE_CONFIG"
TEST_NAME="default language is uz" t test "$(cfg '.lang')" = "uz"
cfg_set '.lang' '"ru"'
TEST_NAME="cfg_set writes a value" t test "$(cfg '.lang')" = "ru"
TEST_NAME="cfg keeps false" t test "$(jq '.auto_submit=false' "$VOICE_CONFIG" > "$VOICE_CONFIG.t" && mv "$VOICE_CONFIG.t" "$VOICE_CONFIG"; cfg '.auto_submit' 'x')" = "false"

echo "hooks"
rm -f "$VOICE_SPEAK_FLAG"
TEST_NAME="context hook is silent while read-aloud is off" t test -z "$(printf '{"prompt":"salom"}' | scripts/voice-context.sh)"
touch "$VOICE_SPEAK_FLAG"
TEST_NAME="context hook injects the 🔊 rule while read-aloud is on" t bash -c 'printf "{\"prompt\":\"salom\"}" | scripts/voice-context.sh | grep -q "🔊"'
TEST_NAME="context hook flags speech-to-text prompts" t bash -c 'printf "{\"prompt\":\"🎙 salom\"}" | scripts/voice-context.sh | grep -q "speech-to-text"'
TEST_NAME="context hook ignores slash commands" t test -z "$(printf '{"prompt":"/ovoz status"}' | scripts/voice-context.sh)"
printf '%s' "/tmp/some/project" > "$VOICE_SPEAK_FLAG"
TEST_NAME="scoped flag: other folders stay silent" t test -z "$(printf '{"prompt":"salom","cwd":"/tmp/other"}' | scripts/voice-context.sh)"
TEST_NAME="scoped flag: the project folder gets the rules" t bash -c 'printf "{\"prompt\":\"salom\",\"cwd\":\"/tmp/some/project\"}" | scripts/voice-context.sh | grep -q "🔊"'

rm -f "$VOICE_SPEAK_FLAG"
TEST_NAME="stop hook exits 0 and stays silent while read-aloud is off" t bash -c 'out=$(printf "{\"last_assistant_message\":\"🔊 x\"}" | scripts/voice-speak.sh --hook); test $? -eq 0 && test -z "$out"'

echo "🔊 extractor"
TEST_NAME="picks the 🔊 line" t test "$(printf 'Fayl yaratildi.\n\n```swift\nlet x = 1\n```\n\n🔊 Tayyor, fayl yaratildi.' | scripts/voice-speak.sh --extract)" = "Tayyor, fayl yaratildi."
TEST_NAME="falls back to plain prose without code" t bash -c 'out=$(printf "Salom **dunyo** `code` https://x.y/z\n\n```\nnoise\n```\n" | scripts/voice-speak.sh --extract); test "$out" = "Salom dunyo"'

rm -rf "$OVOZ_HOME"
echo; echo "passed: $pass  failed: $fail"
(( fail == 0 ))
