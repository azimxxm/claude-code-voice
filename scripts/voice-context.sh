#!/usr/bin/env bash
# voice-context.sh — UserPromptSubmit hook for /ovoz.
#
# While read-aloud is on (~/.claude/ovoz/speak.on exists) every prompt gets a short
# note appended to Claude's context: the conversation is spoken, answer in the chosen
# language, expect speech-to-text errors when the prompt starts with 🎙, and end the
# reply with ONE "🔊 …" line — the only part voice-speak.sh reads aloud.
#
# Never fails the prompt: any problem → exit 0 with no output.

set -u
source "$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)/voice-lib.sh" 2>/dev/null || exit 0

[[ -f "$VOICE_SPEAK_FLAG" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
voice_ensure_config 2>/dev/null || exit 0

payload="$(cat 2>/dev/null || true)"
speak_enabled "$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null)"

# Slash commands and empty prompts are not conversation.
[[ -z "$prompt" || "$prompt" == /* ]] && exit 0

lang="$(cfg '.tts.lang' 'uz')"
lname="$(lang_name "$lang")"
prefix="$(cfg '.transcript_prefix' '🎙 ')"
prefix="${prefix%% *}"   # the emoji only

echo "[ovoz] Voice conversation mode is ON. Reply in ${lname}, conversational and short — the reply is spoken, not read."
if [[ -n "$prefix" && "$prompt" == "$prefix"* ]]; then
  echo "This prompt came from speech-to-text (${prefix}): expect recognition errors — o'/g' apostrophes, English tech terms spelled phonetically, Uzbek/Russian/English mixed in one sentence. Infer the intent, never ask about typos. If it is a TASK (something to build, change, run or check) rather than a question: reply with ONLY one line \"Maqsad: …\" (what you understood, precise) and the 🔊 line asking for a go-ahead (e.g. 🔊 <maqsad, qisqa>. Boshlaymi?) — then END the turn without starting the work. Start when the next message confirms (ha, boshla, davom et, qil, да, yes, go) or gives a correction. Questions and one-step requests: answer directly."
fi
echo "End your reply with exactly one line that starts with \"🔊 \" — one or two plain sentences in ${lname} that summarize the answer or the result. No code, file paths, URLs, numbers-heavy lists or markdown in that line: it is read aloud by a text-to-speech voice when the turn ends. During a long task you may speak a short progress line before the end by running (Bash) \`ovoz say \"…\"\` — one plain sentence in ${lname}, at most once per milestone, never for routine steps."
exit 0
