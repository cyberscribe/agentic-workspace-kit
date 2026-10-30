#!/bin/bash
# live.sh systemd|cron: the scheduler run for real inside a test container, as the non-root user, with
# the stub claude. Section 26 starts the container, copies the plugin to /opt/scheduler and this file
# beside it, and turns each PASS or FAIL line into a check; INFO lines are for the person reading.
#
#   systemd: doctor reports the backend and linger; an `every 1m` task fires at least twice (its run
#            folders, and systemctl --user list-timers); a task that fails pauses itself and removes its
#            own unit; pause stops the first (no new run in the next two minutes); delete leaves no unit
#            files and nothing in list-timers.
#   cron:    doctor reports the backend; the person's other crontab lines survive; a minute task fires
#            twice; pause takes its line out of the block and nothing more runs; delete leaves the
#            crontab exactly as the person had it.

# docker exec -u does not always set HOME; the user's own entry says where it is.
HOME="$(getent passwd "$(id -un)" | cut -d: -f6)"; export HOME
S=/opt/scheduler/scripts/schedule.sh
export SCHEDULER_CLAUDE=/usr/local/bin/claude SCHEDULER_NOTIFY_DESKTOP=0
X() { bash "$S" "$@" 2>&1; }
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; }
check() { local d="$1"; shift; if "$@"; then pass "$d"; else fail "$d"; fi; }
D="$HOME/.local/state/agentic-workspace-kit/scheduler"
UNITS="$HOME/.config/systemd/user"
mkdir -p "$HOME/work" "$HOME/gone"

nruns() { find "$D/runs/$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
nok() { grep -l '^status=ok$' "$D/runs/$1"/*/meta 2>/dev/null | wc -l | tr -d ' '; }
# until_or <secs> <command...>: polls every 3 s until the command succeeds, or the time is up.
until_or() { local t="$1" i=0; shift; while ! "$@"; do sleep 3; i=$((i + 3)); (( i >= t )) && return 1; done; return 0; }
ge() { [[ "$(nok "$1")" -ge "$2" ]]; }
timer_listed() { systemctl --user list-timers --all --no-pager 2>/dev/null | grep -q "aw-scheduler-$1"; }
no_units() { ! ls "$UNITS"/aw-scheduler-"$1"* >/dev/null 2>&1; }
crontab_is_mine() { [[ "$(crontab -l)" == "$mine" ]]; }
mine_first_and_block() { [[ "$(crontab -l | head -n 2)" == "$mine" ]] && crontab -l | grep -q ' exec tick '; }

case "${1:-}" in
systemd)
    out="$(X doctor)"
    check "doctor picks systemd" grep -q '^Backend: systemd' <<<"$out"
    check "doctor reports linger on" grep -q '^Linger: yes' <<<"$out"
    X create tick --schedule 'every 1m' --cwd "$HOME/work" --prompt 'Reply OK.' --retries 0 >/dev/null
    X create gone --schedule 'every 1m' --cwd "$HOME/gone" --prompt 'Reply OK.' --retries 0 --pause-after-failures 1 >/dev/null
    rmdir "$HOME/gone"
    both_listed() { timer_listed tick.timer && timer_listed gone.timer; }
    check "create installs both timers (list-timers)" both_listed
    check "show reports the unit installed and matching" grep -q 'installed and matching the file' <<<"$(X show tick)"
    check "an every 1m task fires twice, both ok (within 200 s)" until_or 200 ge tick 2
    echo "INFO tick runs: $(nruns tick), ok: $(nok tick)"
    check "a task whose folder is gone pauses itself" grep -q '^status: paused$' "$HOME/.config/agentic-workspace-kit/scheduler/tasks/gone.md"
    check "... and removes its own unit files" no_units gone
    gone_unlisted() { ! timer_listed gone; }
    check "... and its timer leaves list-timers" gone_unlisted
    X pause tick >/dev/null
    n="$(nruns tick)"
    sleep 120
    check "pause stops it: no new run in the next two minutes ($n before, $(nruns tick) after)" test "$(nruns tick)" -eq "$n"
    out="$(X report --since "$(date -d '-10 min' '+%Y-%m-%d %H:%M')")"
    check "report counts the runs out of the due fires" grep -q 'due fires ran' <<<"$out"
    echo "INFO $(grep '^Totals' <<<"$out")"
    X delete tick >/dev/null; X delete gone >/dev/null
    check "delete leaves no unit files" no_units ""
    none_listed() { ! timer_listed ""; }
    check "delete leaves nothing in list-timers" none_listed
    ;;
cron)
    printf 'MAILTO=""\n17 3 * * * /bin/true # a line of the person'"'"'s own\n' | crontab -
    mine="$(crontab -l)"
    out="$(X doctor)"
    check "doctor picks cron" grep -q '^Backend: cron' <<<"$out"
    check "doctor sees the cron daemon running" grep -q '^cron daemon: running' <<<"$out"
    X create tick --schedule '* * * * *' --cwd "$HOME/work" --prompt 'Reply OK.' --retries 0 >/dev/null
    check "create adds the block and keeps the person's lines first" mine_first_and_block
    check "a minute task fires twice, both ok (within 150 s)" until_or 150 ge tick 2
    echo "INFO tick runs: $(nruns tick), ok: $(nok tick)"
    check "with no jq, the run's result text is still read" grep -q '^  OK$' <<<"$(X log tick)"
    X pause tick >/dev/null
    check "pause takes the task's line out, the person's stay" crontab_is_mine
    n="$(nruns tick)"
    sleep 70
    check "pause stops it: no new run in the next minute and more ($n before, $(nruns tick) after)" test "$(nruns tick)" -eq "$n"
    X resume tick >/dev/null
    X delete tick >/dev/null
    check "delete leaves the crontab exactly as the person had it" crontab_is_mine
    ;;
*)
    echo "usage: live.sh systemd|cron" >&2; exit 2 ;;
esac
