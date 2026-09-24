#!/usr/bin/env bash
# Context-budget hook: when the conversation's context reaches a threshold
# (default 30% of the window), tell Claude to write a handoff and move the
# work to a fresh session. Fires at most once per session.
#
# Context size = input + cache_read + cache_creation tokens of the latest
# assistant turn in the session transcript.
# Env overrides: CONTEXT_WINDOW_TOKENS (default 1000000),
#                CONTEXT_HANDOFF_FRACTION (default 0.30).
set -u
input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // "UserPromptSubmit"')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
session=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

marker="${TMPDIR:-/tmp}/claude-context-handoff-${session}"
[ -e "$marker" ] && exit 0

used=$(tail -n 400 "$transcript" \
  | jq -r 'select(.type == "assistant" and .message.usage != null)
           | .message.usage
           | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))' 2>/dev/null \
  | tail -n 1)
[ -n "$used" ] || exit 0

window=${CONTEXT_WINDOW_TOKENS:-1000000}
fraction=${CONTEXT_HANDOFF_FRACTION:-0.30}
limit=$(awk -v w="$window" -v f="$fraction" 'BEGIN { printf "%d", w * f }')
[ "$used" -ge "$limit" ] || exit 0

touch "$marker"
pct=$(awk -v u="$used" -v w="$window" 'BEGIN { printf "%d", 100 * u / w }')
msg="CONTEXT BUDGET REACHED (~${pct}% of the context window, ${used} tokens). Follow the 'Context budget' section of CLAUDE.md now, in order: (1) finish or park the current step; (2) update docs/dev/HANDOFF.md; (3) commit and push; (4) give the user the ready-to-paste prompt for the next session in chat; (5) only then create the new session with that same prompt and tell the user to continue there."
jq -n --arg e "$event" --arg m "$msg" \
  '{systemMessage: "Context budget reached: preparing handoff to a new session.",
    hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}'
