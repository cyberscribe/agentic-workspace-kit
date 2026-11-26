#!/usr/bin/env bash
# tests/pane/harness.sh: drives the scheduler pane in a real Claude Code session, the way a person at a
# terminal does, and checks the rules a terminal list keeps on every frame. It needs tmux and a signed-in
# claude, so the suite runs it only when asked (AW_TEST_PANE=1, section 30).
#
#   harness.sh [--out DIR] [--sizes "80x24 120x40 170x40"] [--modes "classic fullscreen"]
#              [--fixtures "0 1 3 20 60"] [--seeds "1 2 3"] [--keys 300] [--mutate NAME] [--jobs 3]
#              [--no-turn] [--plugin DIR] [--trail]
#
# For each fixture, size and mode it starts claude in a detached tmux session on a scratch workspace,
# opens /scheduler-pane, and checks:
#   R1 the selection is visible: in the list, the focus ring is on a task's row; in a task, its name shows
#   R2 the key line is visible
#   R3 every task can be reached with Down from the first
#   R4 in classic mode the pane sits above the prompt across the full width
#   R5 Escape leaves: at most three presses close the pane from anywhere
#   R6 Ctrl+D twice then quits Claude Code
#   R7 every key the key line names changes the screen
#   R8 every action in a task's view can be reached with Up and Down
#   R9 actions drawn side by side on one line can be reached with Right
# then presses a few hundred random keys per seed, checking R1 and R2 after each and R5 when it closes.
# The seed fixes the keys, so a failure can be replayed.
#
# Isolation does not trust the environment. The pane runs from a scratch copy of the plugin whose
# scripts/schedule.sh is a wrapper that sets the fixture's scheduler home, data folder and the none
# backend itself, then runs the kit's own script; a session that lost its environment (Claude Code's
# agents view can do that) still reaches only the fixture. Each wrapper call that arrived without the
# fixture's home is logged as env-lost in the cell's folder.
#
# Output: DIR/<cell>/ holds frames and a log; DIR/results.tsv one line per rule check
# (cell, rule, pass|fail, detail); the exit status is 1 when any check failed. With --trail, DIR/trail-<session>.txt
# also keeps every key sent and every frame read, in order and timed, so a failure can be read frame by frame.
# A && B || C is the suite's idiom here: record never fails (SC2015). ps is read on one tty (SC2009).
# has_name reads the names file the loop around it reads, and writes nothing (SC2094).
# shellcheck disable=SC2015,SC2009,SC2013,SC2094
set -uo pipefail

KIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
OUT="${TMPDIR:-/tmp}/aw-pane-harness"
SIZES="80x24 120x40 170x40"
MODES="classic fullscreen"
FIXTURES="0 1 3 20 60"
SEEDS="1 2 3"
KEYS=300
MUTATE=""
JOBS=3
TURN=1
SOURCE=""
TRAIL=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --sizes) SIZES="$2"; shift 2 ;;
        --modes) MODES="$2"; shift 2 ;;
        --fixtures) FIXTURES="$2"; shift 2 ;;
        --seeds) SEEDS="$2"; shift 2 ;;
        --keys) KEYS="$2"; shift 2 ;;
        --mutate) MUTATE="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --no-turn) TURN=0; shift ;;
        --plugin) SOURCE="$2"; shift 2 ;;
        --trail) TRAIL=1; shift ;;
        *) echo "harness.sh: unknown argument $1" >&2; exit 2 ;;
    esac
done
command -v tmux >/dev/null 2>&1 || { echo "harness.sh: needs tmux" >&2; exit 2; }
command -v claude >/dev/null 2>&1 || { echo "harness.sh: needs claude" >&2; exit 2; }
# The sessions run on a tmux server of the harness's own (its own socket folder), so the person's tmux is not
# touched, and that server has focus events on, as a terminal set up for Claude Code does: without them Claude
# Code draws a "focus-events off" warning that a person's screen does not show.
export TMUX_TMPDIR="${TMPDIR:-/tmp}/aw-pane-tmux"
mkdir -p "$TMUX_TMPDIR"
printf 'set -g focus-events on\n' >"$TMUX_TMPDIR/tmux.conf"
unset TMUX
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd -P)"
# The person's own scheduler: nothing under these may change while the harness runs (checked at the end).
REAL_DIRS=("$HOME/.config/agentic-workspace-kit" "$HOME/.local/state/agentic-workspace-kit" "$HOME/Library/LaunchAgents")
: >"$OUT/.started"
: >"$OUT/results.tsv"
FRAME="$KIT/tests/pane/frame.pl"

nap() { perl -e "select(undef,undef,undef,$1)"; }

# --- Fixtures -------------------------------------------------------------------------------------------
# fixture <n>: a scheduler home with n tasks under $OUT/fixtures/<n>, built once. Two names are long. From
# three tasks on, one run waits for an answer, one failed and one task is paused. A stub claude answers
# the runs: a prompt holding FAIL fails, one holding ASK ends on a question, the rest end OK.
fixture() {
    local n="$1" d="$OUT/fixtures/$1" i name prompt flags
    [[ -f "$d/ready" ]] && { printf '%s\n' "$d"; return; }
    mkdir -p "$d/cfg" "$d/data" "$d/bin" "$d/work/.claude"
    : >"$d/work/.claude/kit-templates.lock"
    cat >"$d/bin/claude" <<'STUB'
#!/bin/bash
if [ "$1 $2" = "auth status" ]; then echo '{"loggedIn":true}'; exit 0; fi
if [ "$1 $2" = "mcp list" ]; then exit 0; fi
in="$(cat)"; args="$*"
echo '{"type":"system","subtype":"init","apiKeySource":"none","session_id":"fixture-session"}'
case " $args " in *" --resume "*) printf '{"type":"result","is_error":false,"result":"Acted on: %s","total_cost_usd":0}\n' "$(printf '%s' "$in" | tr -d '\n')"; exit 0 ;; esac
case "$args$in" in
  *FAIL*) echo "it went wrong" >&2; exit 1 ;;
  *ASK*) echo '{"type":"result","is_error":false,"result":"Which branch should the review use?\n1. main\n2. the feature branch\n\nReply with the number of your pick.","total_cost_usd":0}' ;;
  *) echo '{"type":"result","is_error":false,"result":"OK, done.","total_cost_usd":0}' ;;
esac
STUB
    chmod +x "$d/bin/claude"
    local env=(SCHEDULER_HOME="$d/cfg" SCHEDULER_DATA="$d/data" SCHEDULER_BACKEND=none SCHEDULER_NOTIFY_DESKTOP=0
        SCHEDULER_CLAUDE="$d/bin/claude" SCHEDULER_RETRIES=0)
    for ((i = 1; i <= n; i++)); do
        name="$(printf 'task-%02d' "$i")"
        [[ $i -eq 2 ]] && name="a-scheduled-task-with-a-long-descriptive-name-$i"
        [[ $i -eq 5 ]] && name="another-task-whose-name-runs-past-the-column-$i"
        prompt="Reply OK." flags=()
        [[ $n -ge 3 && $i -eq 1 ]] && { prompt="ASK which branch"; flags=(--awaits-reply true); }
        [[ $n -ge 3 && $i -eq 3 ]] && { prompt="FAIL now"; flags=(--retries 0); }
        env "${env[@]}" bash "$KIT/plugins/scheduler/scripts/schedule.sh" create "$name" \
            --schedule "$(( (i * 7) % 60 )) $(( 6 + i % 12 )) * * 1-5" --cwd "$d/work" --prompt "$prompt" ${flags[@]+"${flags[@]}"} >/dev/null 2>&1 \
            || { echo "harness.sh: could not create $name" >&2; return 1; }
        printf '%s\n' "$name" >>"$d/names"
    done
    if [[ $n -ge 3 ]]; then
        env "${env[@]}" bash "$KIT/plugins/scheduler/scripts/schedule.sh" pause "$(sed -n 4p "$d/names")" >/dev/null 2>&1
        env "${env[@]}" bash "$KIT/plugins/scheduler/scripts/schedule.sh" run "$(sed -n 1p "$d/names")" >/dev/null 2>&1
        env "${env[@]}" bash "$KIT/plugins/scheduler/scripts/schedule.sh" run "$(sed -n 3p "$d/names")" >/dev/null 2>&1
        for i in $(seq 1 30); do
            env "${env[@]}" bash "$KIT/plugins/scheduler/scripts/schedule.sh" list | grep -q running || break
            nap 0.5
        done
    fi
    : >>"$d/names"
    : >"$d/ready"
    printf '%s\n' "$d"
}

# plugin <fixture dir> <cell dir>: a scratch copy of the scheduler plugin bound to the fixture, with the
# mutation applied when one is named.
plugin() {
    local fx="$1" cell="$2" p="$2/plugin/scheduler"
    mkdir -p "$cell/plugin"
    rm -rf "$p"
    # --plugin tests another copy of the pane (an earlier commit's, say) against the same rules.
    cp -R "${SOURCE:-$KIT/plugins/scheduler}" "$p"
    rm -rf "$p/.claude-plugin/types" "$p/tsconfig.json"
    cat >"$p/scripts/schedule.sh" <<WRAP
#!/usr/bin/env bash
# The harness's wrapper: the fixture's scheduler, whatever the calling environment holds.
[[ "\${SCHEDULER_HOME:-}" == "$fx/cfg" ]] || printf '%s env-lost %s\n' "\$(date '+%H:%M:%S')" "\$*" >>"$cell/env-lost.log"
export SCHEDULER_HOME="$fx/cfg" SCHEDULER_DATA="$fx/data" SCHEDULER_BACKEND=none SCHEDULER_NOTIFY_DESKTOP=0 SCHEDULER_CLAUDE="$fx/bin/claude"
exec bash "$KIT/plugins/scheduler/scripts/schedule.sh" "\$@"
WRAP
    chmod +x "$p/scripts/schedule.sh"
    # The plugin's own hooks (session start, stop) read and write the scheduler's state too: bound the same way.
    local hk
    for hk in "$p/hooks/session-start.sh" "$p/hooks/stop.sh"; do
        [[ -f "$hk" ]] && perl -0pi -e "s{\\A(#![^\\n]*\\n)}{\$1export SCHEDULER_HOME='$fx/cfg' SCHEDULER_DATA='$fx/data' SCHEDULER_BACKEND=none\\n}" "$hk"
    done
    [[ -n "$MUTATE" ]] && mutate "$p/hooks/pane.tsx"
    printf '%s\n' "$p"
}

# mutate <pane.tsx>: one deliberate fault per rule, so each rule is shown to catch what it is for.
mutate() {
    local f="$1"
    cp "$f" "$f.orig"
    case "$MUTATE" in
        cap9) perl -0pi -e 's/const window = b\.tasks\.slice\(top, top \+ shown\)/const window = b.tasks.slice(0, 9)/' "$f" ;;
        nohint) perl -0pi -e 's/(Esc close|Esc leaves|Esc back|c close|b back)/quiet/g' "$f" ;;
        noring) perl -0pi -e 's/autoFocus=\{[^}]*\}//g; s/ autoFocus\b//g; s/(async function focusOn\([^)]*\) \{)/$1\n  return/' "$f" ;;
        escstays) perl -0pi -e "s/on\('ui\.close', \{ id: PANE \}, async \(\\\$, e, next\) => \{/on('ui.close', { id: PANE }, async (\\\$, e, next) => { if (e.origin.kind === 'person') return { value: undefined }/" "$f" ;;
        deadkey) perl -0pi -e 's/↑↓ select · Enter\$/x export · ↑↓ select · Enter\$/' "$f" ;;
        # R6: an answer field holding the focus in the list takes Ctrl+D, as a text field does.
        inputfocus) perl -0pi -e 's/(  return \(\n    <Box flexDirection="column">\n      \{total === 0)/  return (\n    <Box flexDirection="column">\n      <Input key="trap" label="x" autoFocus onSubmit={() => undefined} \/>\n      {total === 0/' "$f" ;;
        # R8: actions drawn as text, which no arrow reaches.
        textactions) perl -0pi -e 's/<Button key=\{a\.key\} plain hotkey=\{a\.hotkey\}[^>]*>\n\s*\{`[^`]*`\}\n\s*<\/Button>/<Text key={a.key}>{a.hotkey}: {a.label}<\/Text>/' "$f" ;;
        # R9: actions forced onto one line, where Right moves nothing.
        rowactions) perl -0pi -e 's/const stacked = [^\n]*\n/const stacked = false\n/' "$f" ;;
        *) echo "harness.sh: no mutation called $MUTATE" >&2; exit 2 ;;
    esac
    # A mutation that no longer matches the pane's code would test nothing and pass: that stops the run.
    cmp -s "$f" "$f.orig" && { rm -f "$f.orig"; echo "harness.sh: mutation $MUTATE changed nothing in pane.tsx; update its pattern" >&2; exit 2; }
    rm -f "$f.orig"
}

# --- One session ----------------------------------------------------------------------------------------
# A cell is one fixture, size and mode. Its frames are read through frame.pl into shell variables.
frame() {   # frame <session> <cols> <file>: captures and parses; sets F_OPEN F_RING F_HINT F_TOP F_TOPEND F_DOCK F_AGENTS
    tmux capture-pane -e -p -t "$1" >"$3.ansi" 2>/dev/null
    perl "$FRAME" "$2" <"$3.ansi" >"$3"
    [[ "$TRAIL" == 1 ]] && { printf '=== frame %s %s\n' "${EPOCHREALTIME:-}" "${3##*/}"; cat "$3.ansi"; } >>"$OUT/trail-$1.txt"
    F_OPEN="$(sed -n 's/^open=//p' "$3")"; F_RING="$(sed -n 's/^ring=//p' "$3")"; F_HINT="$(sed -n 's/^hint=//p' "$3")"
    F_TOP="$(sed -n 's/^top=//p' "$3")"; F_TOPEND="$(sed -n 's/^topend=//p' "$3")"; F_DOCK="$(sed -n 's/^dock=//p' "$3")"
    F_AGENTS="$(sed -n 's/^agents=//p' "$3")"; F_BOLD="$(sed -n 's/^bold=//p' "$3")"
}
text_of() { sed -n 's/^text=//p' "$1"; }

record() {  # record <cell> <rule> <pass|fail> <detail>
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$OUT/results.tsv"
}

key() {
    [[ "$TRAIL" == 1 ]] && printf '>>> key %s %s\n' "$2" "${EPOCHREALTIME:-}" >>"$OUT/trail-$1.txt"
    tmux send-keys -t "$1" "$2"; nap "${3:-0.45}"
}

start_session() {  # start_session <session> <cols> <rows> <mode> <fixture dir> <plugin dir>
    local s="$1" fx="$5" plug="$6" settings=""
    [[ "$4" == fullscreen ]] && { printf '{"tui":"fullscreen"}\n' >"$OUT/fullscreen.json"; settings="--settings $OUT/fullscreen.json"; }
    tmux kill-session -t "$s" 2>/dev/null
    tmux -f "$TMUX_TMPDIR/tmux.conf" new-session -d -s "$s" -x "$2" -y "$3" -c "$fx/work" \
        "env -u PAIR_ROLE -u PAIR_MAILBOX SCHEDULER_HOME=$fx/cfg SCHEDULER_DATA=$fx/data SCHEDULER_BACKEND=none SCHEDULER_NOTIFY_DESKTOP=0 SCHEDULER_CLAUDE=$fx/bin/claude claude --setting-sources project $settings --plugin-dir $plug; sleep 600"
    tmux set -g focus-events on
    local i
    for i in $(seq 1 60); do
        local scr; scr="$(tmux capture-pane -p -t "$s" 2>/dev/null)"
        if grep -q "Yes, I trust" <<<"$scr"; then tmux send-keys -t "$s" Down Enter; nap 1; continue; fi
        grep -qE "shift\+tab|for shortcuts|\? for" <<<"$scr" && return 0
        nap 0.5
    done
    return 1
}

open_pane() {  # open_pane <session>
    tmux send-keys -t "$1" C-a C-k; nap 0.2
    tmux send-keys -t "$1" -l '/scheduler-pane'; nap 0.5
    tmux send-keys -t "$1" Enter; nap 1
    # The first read of a large scheduler takes a few seconds; the pane says Loading until it lands.
    local i
    for i in $(seq 1 30); do tmux capture-pane -p -t "$1" | grep -q 'Loading the scheduled tasks' || break; nap 0.5; done
    nap 0.5
}

# entry_digit <names>: the digit that opens a task which is not awaiting an answer (whose view would put
# the focus in its answer field): the second row when there are two or more.
entry_digit() { [[ "$(grep -c . "$1" 2>/dev/null)" -ge 2 ]] && echo 2 || echo 1; }

claude_alive() {  # claude_alive <session>: is claude still running on the session's terminal?
    local tty; tty="$(tmux display -p -t "$1" '#{pane_tty}' 2>/dev/null | sed 's#/dev/##')"
    [[ -n "$tty" ]] && ps -t "$tty" -o command= 2>/dev/null | grep -q '^claude'
}

# has_name <text> <name> <names file>: the text shows the task's name, whole or cut short with "…" (a narrow
# pane, the dock say, cuts a long name to its first characters). A cut form counts when it keeps ten or more
# characters and they begin exactly one name in the fixture, so a fixture whose names share a prefix fails
# rather than passing on the wrong task.
has_name() {
    local t="$1" n="$2" w
    [[ "$t" == *"$n"* ]] && return 0
    for w in $t; do
        [[ "$w" == *… ]] || continue
        w="${w%…}"
        (( ${#w} >= 10 )) && [[ "$n" == "$w"* ]] || continue
        [[ "$(awk -v p="$w" 'index($0, p) == 1' "$3" | grep -c .)" == 1 ]] && return 0
    done
    return 1
}

# Is the selection visible? In the list the ring is on a task's row; in a task its name is on screen.
selection_ok() {  # selection_ok <frame file> <names file>
    local view n
    # The pane's close mark is one of Claude Code's own focus stops (Shift+Tab reaches it); a ring there is fine.
    [[ "$F_RING" == "✕" && -n "$F_HINT" ]] && return 0
    if [[ "$F_HINT" == *select* ]]; then
        [[ ! -s "$2" ]] && return 0
        # The ring is on a task's row; or it is on another of the pane's controls (an action, a "more" row)
        # while the selected task's row is still marked, in bold.
        while IFS= read -r n; do [[ -n "$n" ]] && has_name "$F_RING" "$n" "$2" && return 0; done <"$2"
        if [[ -n "$F_RING" ]]; then
            while IFS= read -r n; do [[ -n "$n" ]] && has_name "$F_BOLD" "$n" "$2" && return 0; done <"$2"
        fi
        return 1
    fi
    [[ -n "$F_HINT" ]] && return 0
    return 1
}

run_cell() {  # run_cell <fixture n> <cols>x<rows> <mode>
    local n="$1" size="$2" mode="$3" cols="${2%x*}" rows="${2#*x}"
    local cell="$n-tasks-$size-$mode" s="aw-pane-$n-$size-$mode" fx plug dir
    dir="$OUT/$cell"; mkdir -p "$dir"
    fx="$(fixture "$n")" || { record "$cell" setup fail "fixture"; return; }
    # Each cell works on its own copy, so cells running side by side never change each other's tasks.
    rm -rf "$dir/fixture"; cp -R "$fx" "$dir/fixture"; fx="$dir/fixture"
    plug="$(plugin "$fx" "$dir")"
    start_session "$s" "$cols" "$rows" "$mode" "$fx" "$plug" || { record "$cell" setup fail "claude did not start"; return; }
    local names="$fx/names" total; total="$(grep -c . "$names")"

    # Open: R1, R2, R4.
    open_pane "$s"; frame "$s" "$cols" "$dir/open.txt"
    [[ "$F_OPEN" == 1 ]] && record "$cell" R0-opens pass "" || record "$cell" R0-opens fail "no pane after /scheduler-pane"
    selection_ok "$dir/open.txt" "$names" && record "$cell" R1-selection pass "" || record "$cell" R1-selection fail "ring='$F_RING'"
    [[ -n "$F_HINT" ]] && record "$cell" R2-hint pass "$F_HINT" || record "$cell" R2-hint fail "no key line on open"
    if [[ "$mode" == classic ]]; then
        [[ "$F_TOP" == 0 && "$F_TOPEND" -ge $((cols - 2)) && "$F_DOCK" == 0 ]] && record "$cell" R4-full-width pass "" \
            || record "$cell" R4-full-width fail "top=$F_TOP topend=$F_TOPEND dock=$F_DOCK cols=$cols"
    fi

    # R3: Down from the first row reaches every task.
    local seen="$dir/seen.txt" i
    : >"$seen"; printf '%s\n' "$F_RING" >>"$seen"
    for ((i = 0; i < total + 3; i++)); do key "$s" Down 0.35; frame "$s" "$cols" "$dir/down.txt"; printf '%s\n' "$F_RING" >>"$seen"; done
    local missing=""
    local ln hit
    while IFS= read -r nm; do
        [[ -n "$nm" ]] || continue
        hit=0
        while IFS= read -r ln; do has_name "$ln" "$nm" "$names" && { hit=1; break; }; done <"$seen"
        (( hit )) || missing+="$nm "
    done <"$names"
    [[ -z "$missing" ]] && record "$cell" R3-reach pass "$total tasks" || record "$cell" R3-reach fail "not reached: $missing"

    # R5 from the list.
    esc_leaves "$s" "$cols" "$dir" "$cell" list

    # With no tasks there is no task to open: the task-view rules have nothing to look at.
    if [[ "$total" -eq 0 ]]; then
        open_pane "$s"; frame "$s" "$cols" "$dir/r7-list.txt"
        keys_change "$s" "$cols" "$dir" "$cell" list
        local r
        for r in R1-task R2-task-hint R8-arrows-reach-actions R9-row-right R7-keys-task R5-esc-task; do record "$cell" "$r" pass "no tasks to open"; done
    else
    # R7: each key the list's key line names changes the screen; then the same in a task's view.
    open_pane "$s"; frame "$s" "$cols" "$dir/r7-list.txt"
    keys_change "$s" "$cols" "$dir" "$cell" list
    open_pane "$s"; key "$s" "$(entry_digit "$names")" 1.2; frame "$s" "$cols" "$dir/task.txt"
    selection_ok "$dir/task.txt" "$names" && record "$cell" R1-task pass "" || record "$cell" R1-task fail "hint='$F_HINT'"
    [[ -n "$F_HINT" ]] && record "$cell" R2-task-hint pass "$F_HINT" || record "$cell" R2-task-hint fail "no key line in a task"
    # R8: every action drawn in a task's view ("r: run now", ...) can be reached with Up and Down. Left is
    # Claude Code's own key (it opens the agents view), so it is not pressed here.
    local acts a unreached=""
    acts="$(text_of "$dir/task.txt" | grep -oE '(^|[│ ])[a-z]: [a-z]+( [a-z]+)?' | sed -E 's/^[│ ]//' | sort -u)"
    : >"$dir/r8-ring.txt"; printf '%s\n' "$F_RING" >>"$dir/r8-ring.txt"
    for i in 1 2 3 4 5 6 7 8; do key "$s" Down 0.35; frame "$s" "$cols" "$dir/r8.txt"; printf '%s\n' "$F_RING" >>"$dir/r8-ring.txt"; done
    for i in 1 2 3 4 5 6 7 8; do key "$s" Up 0.35; frame "$s" "$cols" "$dir/r8.txt"; printf '%s\n' "$F_RING" >>"$dir/r8-ring.txt"; done
    while IFS= read -r a; do [[ -n "$a" ]] && ! grep -qF -- "$a" "$dir/r8-ring.txt" && unreached+="'$a' "; done <<<"$acts"
    [[ -n "$acts" && -z "$unreached" ]] && record "$cell" R8-arrows-reach-actions pass "$(tr '\n' ',' <<<"$acts")" \
        || record "$cell" R8-arrows-reach-actions fail "actions: $(tr '\n' ',' <<<"$acts") not reached with Up/Down: $unreached"
    # R9: actions drawn side by side on one line are a row a person reaches across with Left and Right, so Right
    # has to move the ring along it; actions one under another are reached with Up and Down (R8).
    esc_close "$s" "$cols" "$dir" >/dev/null; open_pane "$s"; key "$s" "$(entry_digit "$names")" 1.2; frame "$s" "$cols" "$dir/r9.txt"
    if text_of "$dir/r9.txt" | grep -qE '[a-z]: [a-z]+( [a-z]+)? +[a-z]: [a-z]'; then
        local r9from="$F_RING"
        key "$s" Right 0.6; frame "$s" "$cols" "$dir/r9.txt"
        [[ -n "$F_RING" && "$F_RING" != "$r9from" ]] && record "$cell" R9-row-right pass "'$r9from' to '$F_RING'" \
            || record "$cell" R9-row-right fail "actions on one line, and Right left the ring on '$F_RING' (was '$r9from')"
    else
        record "$cell" R9-row-right pass "actions one to a line"
    fi
    esc_close "$s" "$cols" "$dir" >/dev/null; open_pane "$s"; key "$s" "$(entry_digit "$names")" 1.2; frame "$s" "$cols" "$dir/task.txt"
    keys_change "$s" "$cols" "$dir" "$cell" task
    esc_leaves "$s" "$cols" "$dir" "$cell" task
    fi

    # Reopen after a turn: the pane opens in the same place.
    if [[ $TURN -eq 1 ]]; then
        tmux send-keys -t "$s" C-a C-k; tmux send-keys -t "$s" -l 'Reply with the single word OK.'; nap 0.3; tmux send-keys -t "$s" Enter
        for i in $(seq 1 60); do tmux capture-pane -p -t "$s" | grep -qE "^⏺ OK" && break; nap 1; done
        open_pane "$s"; frame "$s" "$cols" "$dir/after-turn.txt"
        if [[ "$mode" == classic ]]; then
            [[ "$F_TOP" == 0 && "$F_DOCK" == 0 ]] && record "$cell" R4-after-turn pass "" || record "$cell" R4-after-turn fail "top=$F_TOP dock=$F_DOCK"
        fi
        [[ -n "$F_HINT" ]] && record "$cell" R2-after-turn pass "" || record "$cell" R2-after-turn fail "no key line"
        esc_leaves "$s" "$cols" "$dir" "$cell" after-turn
    fi

    # Random keys, one run per seed.
    local seed
    for seed in $SEEDS; do random_keys "$s" "$cols" "$dir" "$cell" "$seed" "$names"; done

    # R6: Ctrl+D twice quits Claude Code with the pane open and holding the keyboard, as it does without the pane.
    open_pane "$s"
    key "$s" C-d 0.6; key "$s" C-d 2
    claude_alive "$s" && record "$cell" R6-ctrl-d fail "claude still running" || record "$cell" R6-ctrl-d pass ""
    [[ -s "$dir/env-lost.log" ]] && record "$cell" isolation note "$(wc -l <"$dir/env-lost.log" | tr -d ' ') wrapper calls without the fixture's environment"
    tmux kill-session -t "$s" 2>/dev/null
}

esc_close() {  # presses Escape until the pane closes, at most three times; returns 1 if it stays
    local s="$1" cols="$2" dir="$3" i
    for i in 1 2 3; do key "$s" Escape 0.6; frame "$s" "$cols" "$dir/esc.txt"; [[ "$F_OPEN" == 0 ]] && return 0; done
    return 1
}
esc_leaves() {  # esc_leaves <session> <cols> <dir> <cell> <where>
    esc_close "$1" "$2" "$3" && record "$4" "R5-esc-$5" pass "" || record "$4" "R5-esc-$5" fail "pane still open after three Escapes"
}

# keys_change: reads the key line, presses each key it names from a fresh frame, and checks the screen
# changed. Escape is R5's; it is left out here.
keys_change() {  # keys_change <session> <cols> <dir> <cell> <view>
    local s="$1" cols="$2" dir="$3" cell="$4" view="$5" hint="$F_HINT" k tok before after dead=""
    local toks=()
    [[ "$hint" == *"↑↓"* ]] && toks+=(Down)
    [[ "$hint" == *"←→"* ]] && toks+=(Right)
    [[ "$hint" == *Enter* ]] && toks+=(Enter)
    for tok in $(grep -oE '(^|· )[a-z0-9](:| )' <<<"$hint" | grep -oE '[a-z0-9]' ); do toks+=("$tok"); done
    for k in "${toks[@]}"; do
        before="$dir/r7-before.txt"; after="$dir/r7-after.txt"
        frame "$s" "$cols" "$before"
        key "$s" "$k" 1.0
        frame "$s" "$cols" "$after"
        # The pane's own lines and its ring: a key the pane does not take goes to the prompt, which is not the
        # pane changing, and takes the ring with it, which is a dead key too rather than a change. The ring is
        # compared as well as the text, since the text is read without the selection mark, and an arrow that
        # only moves the ring between actions changes nothing else.
        if { cmp -s <(text_of "$before" | grep '│') <(text_of "$after" | grep '│') \
            && [[ "$(sed -n 's/^ring=//p' "$before")" == "$(sed -n 's/^ring=//p' "$after")" ]]; } \
            || [[ -n "$(sed -n 's/^ring=//p' "$before")" && -z "$(sed -n 's/^ring=//p' "$after")" ]]; then
            dead+="$k "
        fi
        esc_close "$s" "$cols" "$dir" >/dev/null
        open_pane "$s"
        [[ "$view" == task ]] && key "$s" "$(entry_digit "$dir/fixture/names")" 1.2
    done
    [[ -z "$dead" ]] && record "$cell" "R7-keys-$view" pass "${toks[*]}" || record "$cell" "R7-keys-$view" fail "no change on: $dead(line: $hint)"
}

# random_keys: the seed fixes the sequence. After each key, R1 and R2 while the pane is open; when it has
# closed, the prompt is cleared and the pane reopened, so no key reaches the model.
random_keys() {  # random_keys <session> <cols> <dir> <cell> <seed> <names>
    local s="$1" cols="$2" dir="$3" cell="$4" seed="$5" names="$6"
    # Keys a person would press here: the arrows, Enter, Escape, Tab both ways, and the keys the view binds (its
    # letters, and digits up to the rows shown). A printable key the view does not bind is Claude Code's to hand to
    # the prompt, where a person types to Claude, so it is not part of the pane's contract.
    local base=(Up Down Up Down Enter Escape Tab BTab Right)
    local i k bad=0 first="" log="$dir/random-$seed.log" pool digits d
    : >"$log"
    RANDOM="$seed"
    open_pane "$s"
    frame "$s" "$cols" "$dir/rk.txt"
    for ((i = 1; i <= KEYS; i++)); do
        pool=("${base[@]}")
        if [[ "$F_HINT" == *select* ]]; then
            pool+=(r p l)
            digits="$(grep -oE '1-[0-9]' <<<"$F_HINT" | cut -c3)"; digits="${digits:-1}"
            for ((d = 1; d <= digits; d++)); do pool+=("$d"); done
        elif [[ "$F_HINT" == *"type the answer"* ]]; then
            pool+=(1 2)
        else
            # The letters this view draws as keys ("r: run now"); a short pane's log view draws none, and a
            # letter it does not draw goes to the prompt, as with any pane.
            for d in r p l b; do text_of "$dir/rk.txt" | grep -qE "(^|[ │])$d: " && pool+=("$d"); done
        fi
        k="${pool[RANDOM % ${#pool[@]}]}"
        key "$s" "$k" 0.35
        frame "$s" "$cols" "$dir/rk.txt"
        printf '%s\t%s\topen=%s\tring=%s\n' "$i" "$k" "$F_OPEN" "$F_RING" >>"$log"
        if [[ "$F_AGENTS" == 1 ]]; then key "$s" Escape 0.6; frame "$s" "$cols" "$dir/rk.txt"; fi
        if [[ "$F_OPEN" == 1 ]]; then
            if ! selection_ok "$dir/rk.txt" "$names" || [[ -z "$F_HINT" ]]; then
                bad=$((bad + 1))
                [[ -z "$first" ]] && { first="key $i ($k): ring='$F_RING' hint='$F_HINT'"; cp "$dir/rk.txt.ansi" "$dir/random-$seed-first-fail.ansi"; }
            fi
            # No ring on an open pane may mean the keys now go to the prompt: clear it and start the pane again
            # before another key, so no key can reach the model.
            [[ -z "$F_RING" && "$F_HINT" != *"type the answer"* ]] && { esc_close "$s" "$cols" "$dir" >/dev/null; open_pane "$s"; frame "$s" "$cols" "$dir/rk.txt"; }
        else
            # Reopened, the pane is its list again: the next key is chosen from this frame, not the closed one.
            open_pane "$s"; frame "$s" "$cols" "$dir/rk.txt"
        fi
    done
    [[ $bad -eq 0 ]] && record "$cell" "random-seed-$seed" pass "$KEYS keys" || record "$cell" "random-seed-$seed" fail "$bad of $KEYS frames broke R1 or R2; first: $first"
    esc_close "$s" "$cols" "$dir" >/dev/null
}

# A named mutation is tried once on a copy before any session starts, so one that no longer matches stops here.
if [[ -n "$MUTATE" ]]; then
    mkdir -p "$OUT/mutation-check"
    cp "${SOURCE:-$KIT/plugins/scheduler}/hooks/pane.tsx" "$OUT/mutation-check/pane.tsx"
    mutate "$OUT/mutation-check/pane.tsx"
fi

# --- The grid -------------------------------------------------------------------------------------------
cells=()
for n in $FIXTURES; do fixture "$n" >/dev/null || exit 1; for size in $SIZES; do for mode in $MODES; do cells+=("$n $size $mode"); done; done; done
running=0
for c in "${cells[@]}"; do
    # shellcheck disable=SC2086 # three words on purpose
    run_cell $c &
    running=$((running + 1))
    if [[ $running -ge $JOBS ]]; then wait -n 2>/dev/null || wait; running=$((running - 1)); fi
done
wait

touched="$(for d in "${REAL_DIRS[@]}"; do [[ -d "$d" ]] && find "$d" -newer "$OUT/.started" -print 2>/dev/null; done)"
# The person's own tasks keep firing while the harness runs. A run their scheduler started (its meta says
# trigger=schedule) writes its run folder, the task's state files, the runner log and a lock; those are set aside,
# and named, rather than counted as the harness reaching the person's scheduler. Anything else that changed,
# a run started any other way, or a change to the task files or the LaunchAgents, fails.
state="$HOME/.local/state/agentic-workspace-kit/scheduler"
own=() other=()
while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if [[ "$p" =~ ^$state/runs/([^/]+)/([^/]+) ]] && grep -qx 'trigger=schedule' "$state/runs/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/meta" 2>/dev/null; then
        own+=("${BASH_REMATCH[1]}/${BASH_REMATCH[2]}")
    else
        other+=("$p")
    fi
done <<<"$touched"
if [[ ${#own[@]} -gt 0 ]]; then
    tasks="$(printf '%s\n' "${own[@]}" | cut -d/ -f1 | sort -u)"
    rest=()
    for p in "${other[@]}"; do
        t="${p#"$state"/}"
        case "$t" in
            logs | logs/runner.log | locks | locks/* | state | runs) continue ;;
            runs/* | state/*) n="${t#*/}"; n="${n%%/*}"; n="${n%%.*}"; grep -qx "$n" <<<"$tasks" && continue ;;
        esac
        rest+=("$p")
    done
    other=("${rest[@]}")
    record all isolation note "the person's own scheduled runs fired meanwhile: $(printf '%s\n' "${own[@]}" | sort -u | tr '\n' ' ')"
fi
if [[ ${#other[@]} -gt 0 ]]; then record all isolation fail "the person's scheduler changed during the run: ${other[*]}"
else record all isolation pass "nothing under the person's scheduler home, state or LaunchAgents changed, beyond their own scheduled runs"; fi
fails="$(awk -F'\t' '$3 == "fail"' "$OUT/results.tsv" | wc -l | tr -d ' ')"
passes="$(awk -F'\t' '$3 == "pass"' "$OUT/results.tsv" | wc -l | tr -d ' ')"
printf '%s checks passed, %s failed (%s)\n' "$passes" "$fails" "$OUT/results.tsv"
[[ "$fails" -eq 0 ]]
