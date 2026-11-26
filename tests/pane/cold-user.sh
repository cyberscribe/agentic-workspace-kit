#!/usr/bin/env bash
# tests/pane/cold-user.sh: a person who has never seen the scheduler pane, played by a headless Claude Code
# agent that can only press keys and look at the screen, works toward one goal at a time. It reads no README
# and no source: its only tools are ./press (send keys to the terminal, then see it) and ./screen. Each run
# is judged from the scheduler's own state afterwards, not from what the agent says.
#
#   cold-user.sh [--out DIR] [--sizes "80x24 120x40 170x40"] [--modes "classic fullscreen"]
#                [--goals "run pause log answer find"] [--repeats 3] [--budget 30] [--jobs 3] [--plugin DIR]
#                [--fixture DIR]   (a 20-task fixture the pane harness built; built here when not given)
#
# Goals, on a fixture of 20 tasks (task-01 waits for an answer, task-03 failed, task-04 is paused):
#   run     run task-07 now
#   pause   pause task-06, then resume it
#   log     read task-03's last log and say what it says
#   answer  answer task-01's waiting question with 2
#   find    open task-15 and say when it next runs
# A run passes only if it reaches the goal within the key budget, every key it pressed changed the screen,
# and it ends "BLOCKING: none": nothing it needed went unread, no guess could have acted on the wrong thing,
# and it could tell each action happened. A missing or empty BLOCKING line fails. Its NOTES line (slow or
# awkward, not blocking) is kept in the results. A goal passes only if every repeat does. Every key pressed, and each
# press that left the screen unchanged (a key that did nothing), is in the run's log.
set -uo pipefail
# The sessions run on a tmux server of the harness's own (its own socket folder), so the person's tmux is not
# touched, and that server has focus events on, as a terminal set up for Claude Code does: without them Claude
# Code draws a "focus-events off" warning that a person's screen does not show.
export TMUX_TMPDIR="${TMPDIR:-/tmp}/aw-pane-tmux"
mkdir -p "$TMUX_TMPDIR"
printf 'set -g focus-events on\n' >"$TMUX_TMPDIR/tmux.conf"
unset TMUX

KIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
OUT="${TMPDIR:-/tmp}/aw-cold-user"
SIZES="80x24 120x40 170x40"
MODES="classic fullscreen"
GOALS="run pause log answer find"
REPEATS=3
BUDGET=30
JOBS=3
SOURCE=""
FIXTURE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --sizes) SIZES="$2"; shift 2 ;;
        --modes) MODES="$2"; shift 2 ;;
        --goals) GOALS="$2"; shift 2 ;;
        --repeats) REPEATS="$2"; shift 2 ;;
        --budget) BUDGET="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --plugin) SOURCE="$2"; shift 2 ;;
        --fixture) FIXTURE="$2"; shift 2 ;;
        *) echo "cold-user.sh: unknown argument $1" >&2; exit 2 ;;
    esac
done
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd -P)"
: >"$OUT/results.tsv"
nap() { perl -e "select(undef,undef,undef,$1)"; }

# bind_hooks <plugin copy> <fixture>: the plugin's own hooks (session start, stop) read and write the scheduler's
# state too, so the copy's hooks are bound to the fixture as the wrapper binds schedule.sh, whatever the
# environment the session hands them.
bind_hooks() {
    local h
    for h in "$1/hooks/session-start.sh" "$1/hooks/stop.sh"; do
        [[ -f "$h" ]] || continue
        perl -0pi -e "s{\\A(#![^\\n]*\\n)}{\$1export SCHEDULER_HOME='$2/cfg' SCHEDULER_DATA='$2/data' SCHEDULER_BACKEND=none\\n}" "$h"
    done
}

# The person's own scheduler: nothing under these may change while the runs go.
REAL_DIRS=("$HOME/.config/agentic-workspace-kit" "$HOME/.local/state/agentic-workspace-kit" "$HOME/Library/LaunchAgents")
START_MARK="$OUT/.started"; : >"$START_MARK"

goal_text() {
    case "$1" in
        run) echo "Run the scheduled task called task-07 now, once." ;;
        pause) echo "Pause the scheduled task called task-06, then resume it, so it ends up active again." ;;
        log) echo "Read the last run's log of the scheduled task called task-03 and tell me, in one sentence, how that run ended." ;;
        answer) echo "The scheduled task called task-01 is awaiting an answer to a question. Answer it with: 2" ;;
        find) echo "Find the scheduled task called task-15, open it, and tell me when it next runs." ;;
    esac
}

# judge <goal> <fixture> <agent's answer file> <screens it saw>: whether the scheduler's state, and for the
# reading goals what was on screen, show the goal reached.
judge() {
    local g="$1" fx="$2" ans="$3"
    local env=(SCHEDULER_HOME="$fx/cfg" SCHEDULER_DATA="$fx/data" SCHEDULER_BACKEND=none)
    local sh="$KIT/plugins/scheduler/scripts/schedule.sh"
    case "$g" in
        run) [[ -n "$(ls "$fx/data/runs/task-07" 2>/dev/null)" ]] ;;
        pause) grep -q $'\tpaused\t' "$fx/data/state/task-06.events" 2>/dev/null \
                && [[ "$(env "${env[@]}" bash "$sh" list --json | jq -r '.[] | select(.name == "task-06") | .status')" == active ]] ;;
        log) grep -qE 'exit 1|: failed' "$4" && grep -qiE 'fail|went wrong|error|exit' "$ans" ;;
        answer) [[ "$(env "${env[@]}" bash "$sh" list --json | jq -r '.[] | select(.name == "task-01") | .waiting')" == "" ]] \
                && grep -rqs 'Acted on: 2' "$fx/data/runs/task-01" ;;
        find) local next; next="$(env "${env[@]}" bash "$sh" list --json | jq -r '.[] | select(.name == "task-15") | .next_words')"
              grep -qF -- "${next##* }" "$ans" && grep -q 'task-15 ·' "$4" ;;
    esac
}

run_one() {  # run_one <goal> <size> <mode> <repeat>
    local g="$1" size="$2" mode="$3" r="$4" cols="${2%x*}" rows="${2#*x}"
    local id="$g-$size-$mode-$r" s="aw-cold-$g-$size-$mode-$r" dir fx tool
    dir="$OUT/$id"; rm -rf "$dir"; mkdir -p "$dir/tool"
    # A fresh fixture and a plugin copy bound to it, from the pane harness.
    fx="$dir/fixture"
    cp -R "$OUT/fixture-20" "$fx"
    mkdir -p "$dir/plugin"; cp -R "${SOURCE:-$KIT/plugins/scheduler}" "$dir/plugin/scheduler"
    rm -rf "$dir/plugin/scheduler/.claude-plugin/types" "$dir/plugin/scheduler/tsconfig.json"
    bind_hooks "$dir/plugin/scheduler" "$fx"
    cat >"$dir/plugin/scheduler/scripts/schedule.sh" <<WRAP
#!/usr/bin/env bash
export SCHEDULER_HOME="$fx/cfg" SCHEDULER_DATA="$fx/data" SCHEDULER_BACKEND=none SCHEDULER_NOTIFY_DESKTOP=0 SCHEDULER_CLAUDE="$fx/bin/claude"
exec bash "$KIT/plugins/scheduler/scripts/schedule.sh" "\$@"
WRAP
    local settings=""
    [[ "$mode" == fullscreen ]] && { printf '{"tui":"fullscreen"}\n' >"$dir/fullscreen.json"; settings="--settings $dir/fullscreen.json"; }
    tmux kill-session -t "$s" 2>/dev/null
    tmux -f "$TMUX_TMPDIR/tmux.conf" new-session -d -s "$s" -x "$cols" -y "$rows" -c "$fx/work" \
        "env -u PAIR_ROLE -u PAIR_MAILBOX SCHEDULER_HOME=$fx/cfg SCHEDULER_DATA=$fx/data SCHEDULER_BACKEND=none claude --setting-sources project $settings --plugin-dir $dir/plugin/scheduler; sleep 900"
    tmux set -g focus-events on
    local scr
    for _ in $(seq 1 60); do
        scr="$(tmux capture-pane -p -t "$s" 2>/dev/null)"
        grep -q "Yes, I trust" <<<"$scr" && { tmux send-keys -t "$s" Down Enter; nap 1; continue; }
        grep -qE "shift\+tab|\? for" <<<"$scr" && break
        nap 0.5
    done
    # The agent's two tools. press sends each argument as one key (tmux names: Up, Down, Enter, Escape, Tab,
    # BTab, Left, Right, a letter, or text in quotes typed as it is), then shows the screen.
    tool="$dir/tool"
    cat >"$tool/screen" <<SCR
#!/usr/bin/env bash
export TMUX_TMPDIR="$TMUX_TMPDIR"
tmux capture-pane -p -t "$s"
SCR
    cat >"$tool/press" <<PRESS
#!/usr/bin/env bash
export TMUX_TMPDIR="$TMUX_TMPDIR"
used=\$(grep -c . "$dir/keys.log" 2>/dev/null || true); used=\${used:-0}
for k in "\$@"; do
    if [[ \$used -ge $BUDGET ]]; then echo "No keys left: the budget of $BUDGET is spent."; exit 1; fi
    before="\$(tmux capture-pane -p -t "$s")"
    case "\$k" in
        Up|Down|Left|Right|Enter|Escape|Tab|BTab|Space|BSpace|C-d|C-c|[a-zA-Z0-9]) tmux send-keys -t "$s" "\$k" ;;
        *) tmux send-keys -t "$s" -l "\$k" ;;
    esac
    perl -e 'select(undef,undef,undef,1.2)'
    after="\$(tmux capture-pane -p -t "$s")"
    used=\$((used + 1))
    if [[ "\$before" == "\$after" ]]; then printf '%s\tno-change\n' "\$k" >>"$dir/keys.log"; else printf '%s\tchanged\n' "\$k" >>"$dir/keys.log"; fi
    printf '%s\n' "\$after" >>"$dir/screens.log"
done
tmux capture-pane -p -t "$s"
PRESS
    chmod +x "$tool/screen" "$tool/press"
    : >"$dir/keys.log"; : >"$dir/screens.log"

    local prompt
    prompt="You are at a computer terminal running Claude Code, a command-line program. You have never used its
'Scheduled tasks' pane before and have no manual. You can only use two commands: ./screen shows the
terminal, and ./press sends keys and then shows the terminal. Pass each key as one argument, using these
names: Up Down Left Right Enter Escape Tab BTab Space BSpace, a single letter or digit, or text in quotes,
which is typed as it is (for example: ./press '/scheduler-pane' Enter). You have $BUDGET key presses in
all, so look before you press. The Scheduled tasks pane opens when you type /scheduler-pane at the prompt
and press Enter.

Your goal: $(goal_text "$g")

When the goal is done, or you are stuck, stop and say in one or two sentences what you did and what you
saw. Then end with two lines of their own. First, BLOCKING: none, or BLOCKING: followed by each place where
you could not read something the goal needed, had to guess what a key would do and a wrong guess would have
acted on the wrong thing, could not tell whether an action had happened, or pressed a key that did nothing.
Second, NOTES: followed by anything that was slow or awkward but did not block you (or NOTES: none)."
    (cd "$tool" && env -u PAIR_ROLE -u PAIR_MAILBOX perl -e 'alarm 600; exec @ARGV' claude -p "$prompt" \
        --setting-sources project --permission-mode dontAsk \
        --allowedTools "Bash(./press:*)" "Bash(./screen)" \
        --disallowedTools "Read" "Edit" "Write" "Glob" "Grep" "WebFetch" "WebSearch" "Task" "NotebookEdit" \
        --output-format stream-json --verbose </dev/null >"$dir/agent.jsonl" 2>&1)
    python3 -I -c '
import json, sys
out = ""
for l in open(sys.argv[1]):
    try: d = json.loads(l)
    except Exception: continue
    if d.get("type") == "result": out = d.get("result") or ""
open(sys.argv[2], "w").write(out)
' "$dir/agent.jsonl" "$dir/answer.txt"
    local keys dead
    keys="$(grep -c . "$dir/keys.log")"; dead="$(grep -c 'no-change' "$dir/keys.log")"
    local blocking notes
    blocking="$(grep -E '^\**BLOCKING:' "$dir/answer.txt" | tail -n 1 | tr -d '*')"
    notes="$(grep -E '^\**NOTES:' "$dir/answer.txt" | tail -n 1 | tr -d '*')"
    if judge "$g" "$fx" "$dir/answer.txt" "$dir/screens.log" && [[ "$dead" -eq 0 && "$blocking" =~ ^BLOCKING:\ *[Nn]one([^a-z]|$) ]]; then
        printf '%s\t%s\t%s\t%s\tpass\t%s keys, %s did nothing; %s\n' "$g" "$size" "$mode" "$r" "$keys" "$dead" "${notes:-no NOTES line}" >>"$OUT/results.tsv"
    else
        printf '%s\t%s\t%s\t%s\tfail\t%s keys, %s did nothing; %s; said: %s\n' "$g" "$size" "$mode" "$r" "$keys" "$dead" "${blocking:-no BLOCKING line}" "$(tr '\n' ' ' <"$dir/answer.txt" | cut -c1-200)" >>"$OUT/results.tsv"
    fi
    tmux kill-session -t "$s" 2>/dev/null
}

# The fixture, once: the pane harness builds it.
if [[ -n "$FIXTURE" ]]; then
    rm -rf "$OUT/fixture-20"; cp -R "$FIXTURE" "$OUT/fixture-20"
elif [[ ! -f "$OUT/fixture-20/ready" ]]; then
    bash "$KIT/tests/pane/harness.sh" --out "$OUT/build" --fixtures 20 --sizes 80x24 --modes classic --seeds 1 --keys 1 --no-turn --jobs 1 >/dev/null 2>&1
    rm -rf "$OUT/fixture-20"; cp -R "$OUT/build/fixtures/20" "$OUT/fixture-20"
fi

running=0
for g in $GOALS; do for size in $SIZES; do for mode in $MODES; do for ((r = 1; r <= REPEATS; r++)); do
    run_one "$g" "$size" "$mode" "$r" &
    running=$((running + 1))
    if [[ $running -ge $JOBS ]]; then wait; running=0; fi
done; done; done; done
wait

touched="$(for d in "${REAL_DIRS[@]}"; do [[ -d "$d" ]] && find "$d" -newer "$START_MARK" -print 2>/dev/null; done)"
if [[ -n "$touched" ]]; then printf 'isolation\t-\t-\t-\tfail\tthe person'"'"'s scheduler changed during the runs: %s\n' "$(tr '\n' ' ' <<<"$touched")" >>"$OUT/results.tsv"
else printf 'isolation\t-\t-\t-\tpass\tnothing under the person'"'"'s scheduler home, state or LaunchAgents changed\n' >>"$OUT/results.tsv"; fi

awk -F'\t' '{ k = $1 "\t" $2 "\t" $3; n[k]++; if ($5 == "pass") p[k]++ }
    END { for (k in n) printf "%s\t%d/%d\t%s\n", k, p[k] + 0, n[k], (p[k] == n[k] ? "pass" : "fail") }' "$OUT/results.tsv" | sort >"$OUT/summary.tsv"
cat "$OUT/summary.tsv"
! grep -q $'\tfail$' "$OUT/summary.tsv"
