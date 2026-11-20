#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# UserPromptSubmit: the private marker. A message holding the word #private marks the whole session
# private, from any point in it: the SessionEnd capture writes no draft for it, so the next session's
# review reminder has nothing to say about it, and a live /closeout runs only when the person asks for
# it, asking before it writes anything. The marker is a flag file named by the session id, outside any
# repository, beside the drafts; the capture hook removes it when the session ends.
#
# It runs on every message, so it does nothing but read its input unless the word is there: no config
# is read and nothing is printed. When it first sees the word in a session it says so once, to the
# person and to the agent; later mentions are quiet. There is no way to unmark a session: a session
# that was private in part is private.
#
# Wired from hooks/hooks.json -> hooks.UserPromptSubmit. Receives the hook JSON on stdin.
set -uo pipefail

# Read the input first: a hook that exits with stdin unread can leave the writer on a closed pipe.
input="$(cat)"
[[ -n "${CLOSEOUT_HOOK_CHILD:-}" ]] && exit 0

# The cheap test first, in bash alone: most messages stop here.
low="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
[[ "$low" == *"#private"* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' | tr '[:upper:]' '[:lower:]')"
# The word on its own: not part of a longer word or tag (#privateer, #private-notes), nor a path or URL.
grep -qE '(^|[^[:alnum:]_#/-])#private([^[:alnum:]_/-]|$)' <<<"$prompt" || exit 0

# Outside a kit workspace the capture keeps nothing anyway, so there is nothing to say (lib/boundary.sh).
# shellcheck source=lib/boundary.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/boundary.sh"
[[ -n "$(aw_workspace_root "$input")" ]] || exit 0
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
[[ -n "$session_id" ]] || exit 0
flags="${CLOSEOUT_DRAFT_ROOT:-$HOME/.claude/closeout-drafts}/.private"
mkdir -p "$flags" 2>/dev/null || exit 0
# Flags of sessions that ended without the capture hook (a crash, a killed terminal) go after a day.
find "$flags" -maxdepth 1 -type f -mmin +1440 -delete 2>/dev/null || true
[[ -f "$flags/$session_id" ]] && exit 0
date '+%Y-%m-%d %H:%M %z' > "$flags/$session_id" 2>/dev/null || exit 0

jq -nc \
    --arg m "Private session: closeout will keep no draft of it, and the next session's reminder will say nothing about it. This holds for the rest of the session." \
    --arg c "The person marked this session private (#private). The closeout capture writes nothing for it when it ends. A /closeout in this session runs only if the person asks for it, and asks before writing anything. Confirm it in one line, then carry on with what they asked." \
    '{systemMessage: $m, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
exit 0
