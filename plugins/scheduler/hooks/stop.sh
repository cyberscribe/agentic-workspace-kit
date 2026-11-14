#!/bin/bash
# shellcheck source-path=SCRIPTDIR
# The scheduler's Stop hook: an answer given, in its own session, to a run that is awaiting a reply. The
# person can answer in the desktop app or the terminal by resuming the run's session, instead of with
# `schedule.sh reply`; this records that answer as the reply, once. It acts only when the session is the
# one a waiting run owns, and is silent for every other session.
#
# A scheduled run and a reply both set AW_HEADLESS_RUN, so their own stops are never recorded here, and
# the runner writes a run's waiting marker only after claude has exited. Inside a kit workspace only
# (lib/boundary.sh). It reads the waiting markers and one run's meta, with no claude call.
#
# Environment:
#   AW_HEADLESS_RUN=1           a run nobody is watching: say nothing
#   SCHEDULER_HOOK_DISABLED=1   say nothing
#   SCHEDULER_HOME, SCHEDULER_DATA   as schedule.sh reads them

[[ "${AW_HEADLESS_RUN:-}" == "1" || "${SCHEDULER_HOOK_DISABLED:-}" == "1" ]] && exit 0
input=""
[[ -t 0 ]] || input="$(cat)"
# shellcheck source=lib/boundary.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/boundary.sh"
[[ -n "$(aw_workspace_root "$input")" ]] || exit 0

sid="$(printf '%s' "$input" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -n 1)"
[[ -n "$sid" ]] || exit 0
tr="$(printf '%s' "$input" | sed -n 's/.*"transcript_path" *: *"\([^"]*\)".*/\1/p' | head -n 1)"

# The state folder as schedule.sh resolves it.
data="${SCHEDULER_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/agentic-workspace-kit/scheduler}"
[[ -d "$data/state" ]] || exit 0
script="$(dirname "${BASH_SOURCE[0]}")/../scripts/schedule.sh"
for w in "$data/state"/*.waiting; do
    [[ -f "$w" ]] || continue
    name="$(basename "$w" .waiting)"
    run="$(cat "$w")"
    if grep -qx "session_id=$sid" "$data/runs/$name/$run/meta" 2>/dev/null; then
        bash "$script" record-answer "$name" "$run" "$tr" >/dev/null 2>&1
        break
    fi
done
exit 0
