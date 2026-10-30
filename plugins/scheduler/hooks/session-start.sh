#!/bin/bash
# shellcheck source-path=SCRIPTDIR
# The scheduler's SessionStart line: what needs the person since the last session saw it. Inside a kit
# workspace only (lib/boundary.sh), and silent when nothing does.
#
#   - runs that failed or timed out since the last session started;
#   - tasks that paused themselves since then (the reason in the task file names its last run);
#   - runs awaiting a reply, for as long as they wait.
#
# It reads only the scheduler's state folder and the task files, with no claude call and no call to the
# OS scheduler, so it is quick. The lines go out twice: as systemMessage, which the person sees, and as
# additionalContext, which the agent reads, with the script's path so it can act on them.
#
# Environment:
#   AW_HEADLESS_RUN=1           a run nobody is watching, a scheduled one included: say nothing
#   SCHEDULER_HOOK_DISABLED=1   say nothing
#   SCHEDULER_HOME, SCHEDULER_DATA   the task and state folders, as schedule.sh reads them (with the
#                                    pointer file schedule.sh home writes)

[[ "${AW_HEADLESS_RUN:-}" == "1" || "${SCHEDULER_HOOK_DISABLED:-}" == "1" ]] && exit 0
input=""
[[ -t 0 ]] || input="$(cat)"
# shellcheck source=lib/boundary.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/boundary.sh"
[[ -n "$(aw_workspace_root "$input")" ]] || exit 0
# The session starting now: a waiting run that is this session needs no line, since the person is in it.
own_sid="$(printf '%s' "$input" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -n 1)"

# The tasks folder as schedule.sh resolves it: SCHEDULER_HOME's tasks/, else the pointer file, else the
# default.
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/agentic-workspace-kit/scheduler"
if [[ -n "${SCHEDULER_HOME:-}" ]]; then tasks="$SCHEDULER_HOME/tasks"
elif [[ -s "$cfg/home" ]]; then read -r tasks <"$cfg/home"
else tasks="$cfg/tasks"; fi
data="${SCHEDULER_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/agentic-workspace-kit/scheduler}"
[[ -d "$data/runs" ]] || exit 0

# The stamp is a run id (YYYYmmdd-HHMMSS) of when the last session started; run folders are named the
# same way, so "since then" is a string comparison. With no stamp, the last day counts.
stamp="$data/state/session-seen"
seen=""
[[ -f "$stamp" ]] && read -r seen <"$stamp"
now_e="$(date +%s)"
if [[ -z "$seen" ]]; then
    seen="$(date -r $((now_e - 86400)) '+%Y%m%d-%H%M%S' 2>/dev/null || date -d "@$((now_e - 86400))" '+%Y%m%d-%H%M%S')"
fi
mkdir -p "$data/state" && date '+%Y%m%d-%H%M%S' >"$stamp"

has() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }
failed="" paused="" waiting=""
for d in "$data/runs"/*/*; do
    [[ -f "$d/meta" ]] || continue
    id="${d##*/}"
    [[ "$id" > "$seen" ]] || continue
    st="" tk=""
    while IFS='=' read -r k v; do
        case "$k" in status) st="$v" ;; task) tk="$v" ;; esac
    done <"$d/meta"
    case "$st" in failed|timeout|denied|refused) has "$failed" "$tk" || failed+="$tk " ;; esac
done
for f in "$tasks"/*.md; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
        [[ "$line" == "---" && -n "${in_fm:-}" ]] && break
        [[ "$line" == "---" ]] && { in_fm=1; continue; }
        case "$line" in
            "paused_reason: paused itself"*)
                last="${line##* the last }"; last="${last%%;*}"
                tk="${f##*/}"; [[ "$last" > "$seen" ]] && paused+="${tk%.md} " ;;
        esac
    done <"$f"
    in_fm=""
done
for w in "$data/state"/*.waiting; do
    [[ -f "$w" ]] || continue
    tk="$(basename "$w" .waiting)"; read -r id <"$w"
    st="" end="" win="" sid="" wcwd=""
    while IFS='=' read -r k v; do
        case "$k" in status) st="$v" ;; end_epoch) end="$v" ;; reply_window_secs) win="$v" ;; session_id) sid="$v" ;; cwd) wcwd="$v" ;; esac
    done <"$data/runs/$tk/$id/meta" 2>/dev/null
    [[ "$st" == waiting ]] || continue
    [[ -n "$end" && -n "$win" ]] && (( now_e - end > win )) && continue
    [[ -n "$own_sid" && "$sid" == "$own_sid" ]] && continue
    waiting+="$tk "
    # The first waiting run's session opens in the desktop app, the way schedule.sh show gives it.
    [[ -z "$open_cmd" && -n "$sid" ]] && open_cmd="cd '$wcwd' && claude --desktop --resume $sid"
done

parts=()
# The name lists are space-separated task names, which have no spaces, so they split as intended.
list() { local x out=""; for x in $1; do out+="${out:+, }$x"; done; printf '%s' "$out"; }
first() { printf '%s' "${1%% *}"; }
if [[ -n "$failed" ]]; then
    n=0; for x in $failed; do n=$((n + 1)); done
    if (( n == 1 )); then parts+=("$(first "$failed") failed since the last session (schedule.sh log $(first "$failed"))")
    else parts+=("$n tasks had failed runs since the last session: $(list "$failed") (schedule.sh log <name>)"); fi
fi
[[ -n "$paused" ]] && parts+=("$(list "$paused") paused itself after failing (schedule.sh show $(first "$paused"))")
[[ -n "$waiting" ]] && parts+=("$(list "$waiting") awaiting an answer (open it: ${open_cmd:-schedule.sh show $(first "$waiting")}; or schedule.sh reply $(first "$waiting") '<your reply>')")
[[ ${#parts[@]} -gt 0 ]] || exit 0

msg="Scheduler: "
for i in "${!parts[@]}"; do (( i > 0 )) && msg+="; "; msg+="${parts[i]}"; done
msg+="."
script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/schedule.sh"
ctx="$msg The script is $script; /scheduler:tasks answers these (log, show, reply)."
esc() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "$s"; }
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$(esc "$msg")" "$(esc "$ctx")"
