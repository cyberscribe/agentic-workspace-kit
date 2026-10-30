# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh (SC2154); checks are "cond && ok || ko"
# (SC2015); single-quoted strings hold literal cron stars and dollar signs (SC2016); run folders and
# trash files have timestamp names, so ls is safe on them (SC2012).
# shellcheck disable=SC2154,SC2015,SC2016,SC2012
# Section 26: the scheduler plugin (plugins/scheduler/scripts/schedule.sh). The cron expander against a
# table; next fire times on fixed clocks (a month end, a leap day, the OR rule); the launchd plist, the
# systemd timer and the crontab block each rendered and checked; create, edit, pause, resume, delete
# and sync on the none backend and on stubbed launchctl, systemctl and crontab; and the runner against
# a stub claude: success, a retry, a timeout, an overlap, auto-pause, once, pruning. Nothing here
# touches the machine's own scheduler: every OS tool and folder is a stub under $SCRATCH.
# Everything here is prefixed s26_, since the sections share one shell.

echo
echo "26 · The scheduler: schedules, the three backends and the runner"

s26="$SCRATCH/s26"
s26_sh="$KIT/plugins/scheduler/scripts/schedule.sh"
# The section's own Claude Code config folder and managed-settings path, so the billing check reads
# fixtures, never this machine's settings.
mkdir -p "$s26/bin" "$s26/work" "$s26/LaunchAgents" "$s26/systemd" "$s26/ccfg"
s26_backend=none

# A stub claude: what it does comes from $s26/bin/mode; it records its arguments, stdin, environment
# and folder, so the checks can read what the runner passed.
cat >"$s26/bin/claude" <<'EOF'
#!/bin/bash
d="$(dirname "$0")"; mode="$(cat "$d/mode" 2>/dev/null || echo ok)"
if [ "$1 $2" = "mcp list" ]; then
    printf 'Checking MCP server health…\n\nclaude.ai Gmail: https://example.invalid/gmail - ✔ Connected\n'
    printf 'claude.ai Google Calendar: https://example.invalid/gcal - ✔ Connected\nplugin:tools:notion: https://example.invalid/n (HTTP) - ! Needs authentication\n'
    exit 0
fi
if [ "$1 $2" = "auth status" ]; then echo '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"pro"}'; exit 0; fi
# A background session (reach: remote) and its stop, as claude prints them: the short id is the third word.
if [ "$1" = "--bg" ]; then echo "$*" >>"$d/bg-calls"; echo "backgrounded · stubbg (idle — send a prompt to start)"; exit 0; fi
if [ "$1" = "stop" ]; then echo "$*" >>"$d/stop-calls"; [ -f "$d/stop-fail" ] && exit 1; exit 0; fi
printf '%s\n' "$@" >"$d/last-args"; cat >"$d/last-stdin"; env >"$d/last-env"; pwd >"$d/last-pwd"
# The stream's first event names the API key source: none is the subscription login.
if [ "$mode" = apikey ]; then
    echo '{"type":"system","subtype":"init","apiKeySource":"ANTHROPIC_API_KEY","session_id":"x"}'
    echo apikey >>"$d/calls"; exec sleep 30
fi
echo '{"type":"system","subtype":"init","apiKeySource":"none","session_id":"x"}'
case " $* " in *" --resume "*)
    echo "resume" >>"$d/calls"
    printf '{"type":"result","is_error":false,"result":"Acted on: %s","total_cost_usd":0.005}\n' "$(tr -d '\n' <"$d/last-stdin")"
    exit 0 ;;
esac
echo "$mode" >>"$d/calls"
case "$mode" in
    ok) echo '{"type":"result","is_error":false,"result":"OK, done.","total_cost_usd":0.0125}' ;;
    fail) echo "it went wrong" >&2; exit 1 ;;
    failonce)
        if [ -f "$d/failed" ]; then echo '{"type":"result","is_error":false,"result":"second time lucky","total_cost_usd":0.01}'
        else : >"$d/failed"; echo '{"type":"result","is_error":true,"result":"no","total_cost_usd":0.002}'; exit 1; fi ;;
    hang) echo $$ >"$d/hang.pid"; exec sleep 120 ;;
    denied) echo '{"type":"result","is_error":false,"result":"I could not run date: Bash was denied.","total_cost_usd":0.001,"permission_denials":[{"tool_name":"Bash","tool_use_id":"tu1","tool_input":{"command":"date > out.txt"}}]}' ;;
    deniedonce)   # refused on the first attempt and stopped there; the second goes through
        if [ -f "$d/failed" ]; then echo '{"type":"result","is_error":false,"result":"OK, done.","total_cost_usd":0.01}'
        else : >"$d/failed"; echo '{"type":"result","is_error":false,"result":"I could not run date: Bash was denied.","total_cost_usd":0.001,"permission_denials":[{"tool_name":"Bash","tool_use_id":"tu1","tool_input":{"command":"date > out.txt"}}]}'; fi ;;
    recovered)
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"fetch.sh; echo done; ls"}}]}}'
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu2","name":"Bash","input":{"command":"bash fetch.sh"}}]}}'
        echo '{"type":"result","is_error":false,"result":"Fetched and written.","total_cost_usd":0.002,"permission_denials":[{"tool_name":"Bash","tool_use_id":"tu1","tool_input":{"command":"fetch.sh; echo done; ls"}}]}' ;;
esac
EOF
# A stub launchctl: loaded labels in a file; bootstrap reads the plist's Label.
cat >"$s26/bin/launchctl" <<'EOF'
#!/bin/bash
d="$(dirname "$0")"; echo "$*" >>"$d/launchctl.log"; touch "$d/loaded"
case "$1" in
    print) grep -qx "${2##*/}" "$d/loaded" ;;
    bootstrap) l="$(sed -n '/<key>Label<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$3")"; echo "$l" >>"$d/loaded" ;;
    bootout) grep -vx "${2##*/}" "$d/loaded" >"$d/loaded.tmp"; mv "$d/loaded.tmp" "$d/loaded"
             # launchd stops a job that boots itself out; the stub does the same to its caller.
             [ -f "$d/kill-on-bootout" ] && kill -TERM "$PPID" ;;
esac
EOF
# A stub systemctl --user: enabled-and-started timers in a file.
cat >"$s26/bin/systemctl" <<'EOF'
#!/bin/bash
d="$(dirname "$0")"; echo "$*" >>"$d/systemctl.log"; touch "$d/active"; shift
case "$1" in
    is-active) grep -qx "$2" "$d/active" ;;
    enable|restart) grep -qx "$2" "$d/active" || echo "$2" >>"$d/active" ;;
    disable) grep -vx "$3" "$d/active" >"$d/active.tmp"; mv "$d/active.tmp" "$d/active" ;;
esac
exit 0
EOF
# A stub crontab: -l prints the file (exit 1 when there is none), - replaces it from stdin.
cat >"$s26/bin/crontab" <<'EOF'
#!/bin/bash
d="$(dirname "$0")"
case "$1" in
    -l) [ -f "$d/crontab.txt" ] || { echo "no crontab for you" >&2; exit 1; }; cat "$d/crontab.txt" ;;
    -) cat >"$d/crontab.txt" ;;
esac
EOF
chmod +x "$s26/bin/"*

# s26_x <args...>: schedule.sh under bash 3.2 with every path and tool pointed at the scratch folder.
s26_x() {
    env SCHEDULER_HOME="$s26/cfg" SCHEDULER_DATA="$s26/data" SCHEDULER_BACKEND="$s26_backend" \
        SCHEDULER_NOTIFY_DESKTOP=0 SCHEDULER_CLAUDE="$s26/bin/claude" SCHEDULER_UID=501 \
        SCHEDULER_LAUNCHCTL="$s26/bin/launchctl" SCHEDULER_SYSTEMCTL="$s26/bin/systemctl" \
        SCHEDULER_CRONTAB="$s26/bin/crontab" SCHEDULER_LAUNCH_AGENTS="$s26/LaunchAgents" \
        SCHEDULER_SYSTEMD_DIR="$s26/systemd" ${s26_now:+SCHEDULER_NOW="$s26_now"} \
        CLAUDE_CONFIG_DIR="$s26/ccfg" SCHEDULER_MANAGED_SETTINGS="$s26/managed-settings.json" XDG_CONFIG_HOME="$s26/xdg" \
        "$st_bash" "$s26_sh" "$@"
}
s26_mode() { printf '%s\n' "$1" >"$s26/bin/mode"; rm -f "$s26/bin/failed"; }
s26_reset() { rm -rf "${s26:?}/cfg" "$s26/data" "$s26/LaunchAgents"/* "$s26/systemd"/* "$s26/bin"/*.log "$s26/bin/loaded" "$s26/bin/active" "$s26/bin/crontab.txt"; }
# s26_says <text> <args...>: schedule.sh's output holds the text. The suite runs under pipefail, so
# output is captured rather than piped into grep -q, which would stop the writer early.
s26_says() { local t="$1" o; shift; o="$(s26_x "$@" 2>&1)"; [[ "$o" == *"$t"* ]]; }
s26_mk() {   # name schedule [flags...]: a task on the current backend, quietly
    local n="$1" s="$2"; shift 2
    s26_x create "$n" --schedule "$s" --cwd "$s26/work" --prompt "Write the date to out.txt and reply OK." "$@" >/dev/null 2>&1
}

check "26 schedule.sh parses under $st_bash" "$st_bash" -n "$s26_sh"

# --- The cron expander -----------------------------------------------------------------------------
# Each row: the schedule, then minute|hour|day-of-month|month|day-of-week|days as `parse` prints them
# (a full field reads *), or "error: <text>" for one that is refused. As in cron, a day field written
# with a leading * (*/10) counts as unrestricted, so only two day fields both written without one
# take the OR rule.
s26_parse() {
    local out
    out="$(s26_x parse "$1" 2>&1)" || { printf 'error: %s' "${out#schedule.sh: }"; return; }
    printf '%s\n' "$out" | sed -n 's/^[a-z-]*: //p' | sed 1d | paste -sd'|' -
}
s26_bad=""
while IFS='	' read -r s26_e s26_w; do
    [[ -n "$s26_e" ]] || continue
    s26_g="$(s26_parse "$s26_e")"
    [[ "$s26_g" == "$s26_w"* ]] || s26_bad+="$s26_e: got '$s26_g', want '$s26_w'"$'\n'
done <<'TABLE'
0 9 * * *	0|9|*|*|*|both match
*/15 9-17 * * mon-fri	0 15 30 45|9 10 11 12 13 14 15 16 17|*|*|1 2 3 4 5|both match
5 4 * * 7	5|4|*|*|0|both match
5 4 * * sun,SAT	5|4|*|*|0 6|both match
0 0 1,15 * 5	0|0|1 15|*|5|either matches
0 0 13 * fri	0|0|13|*|5|either matches
0 0 */10 * 1	0|0|1 11 21 31|*|1|both match
0 0 * * */2	0|0|*|*|0 2 4 6|both match
1-5/2 * * jan,mar *	1 3 5|*|*|1 3|*|both match
30 6 * jun-aug 1-5	30|6|*|6 7 8|1 2 3 4 5|both match
10/20 * * * *	10 30 50|*|*|*|*|both match
0 0 1-31 * 1	0|0|*|*|1|either matches
0 0 1 1 *	0|0|1|1|*|both match
@hourly	0|*|*|*|*|both match
@daily	0|0|*|*|*|both match
@weekly	0|0|*|*|0|both match
@monthly	0|0|1|*|*|both match
@yearly	0|0|1|1|*|both match
0 25 * * *	error: hour: '25' is outside 0-23
0 0 30 2 *	error: '0 0 30 2 *' never fires
5-1 * * * *	error: minute: range '5-1' runs backwards
*/0 * * * *	error: minute: bad step
0 0 * * xyz	error: day of week: bad value
0 0 * *	error: '0 0 * *' is not five cron fields
@reboot	error: @reboot is not a time
TABLE
empty "26 the cron expander: 25 schedules (lists, ranges, steps, names, 7 as Sunday, aliases, the OR rule, and seven refusals)" "$s26_bad"
s26_bad=""
[[ "$(s26_x parse 'every 90m')" == *"seconds: 5400"* ]] || s26_bad+="every 90m"$'\n'
[[ "$(s26_x parse 'every 2 hours')" == *"seconds: 7200"* ]] || s26_bad+="every 2 hours"$'\n'
[[ "$(s26_x parse 'once 2027-01-01 07:30')" == *"at: 2027-01-01 07:30"* ]] || s26_bad+="once"$'\n'
s26_x parse 'once 2027-02-29 07:30' >/dev/null 2>&1 && s26_bad+="once on a 29 February that does not exist was accepted"$'\n'
s26_x parse 'every 0m' >/dev/null 2>&1 && s26_bad+="every 0m was accepted"$'\n'
empty "26 every <n>m|h|d and once YYYY-MM-DD HH:MM parse, and an impossible date or a zero interval is refused" "$s26_bad"

# --- Next fire times on fixed clocks ---------------------------------------------------------------
s26_bad=""
s26_next() { s26_x next "$1" --count "$2" --from "$3" | paste -sd'|' -; }
while IFS='	' read -r s26_e s26_c s26_f s26_w; do
    [[ -n "$s26_e" ]] || continue
    s26_g="$(s26_next "$s26_e" "$s26_c" "$s26_f")"
    [[ "$s26_g" == "$s26_w" ]] || s26_bad+="$s26_e from $s26_f: got '$s26_g', want '$s26_w'"$'\n'
done <<'TABLE'
0 9 31 * *	3	2026-01-31 09:00	2026-03-31 09:00 Tue|2026-05-31 09:00 Sun|2026-07-31 09:00 Fri
0 0 29 2 *	3	2026-10-29 12:00	2028-02-29 00:00 Tue|2032-02-29 00:00 Sun|2036-02-29 00:00 Fri
0 0 13 * 5	4	2026-01-01 00:00	2026-01-02 00:00 Fri|2026-01-09 00:00 Fri|2026-01-13 00:00 Tue|2026-01-16 00:00 Fri
0 0 29 2 1	3	2027-01-01 00:00	2027-02-01 00:00 Mon|2027-02-08 00:00 Mon|2027-02-15 00:00 Mon
30 23 31 12 *	2	2026-12-31 23:30	2027-12-31 23:30 Fri|2028-12-31 23:30 Sun
*/15 9-17 * * mon-fri	3	2026-10-30 17:50	2026-11-02 09:00 Mon|2026-11-02 09:15 Mon|2026-11-02 09:30 Mon
0 12 * * *	2	2026-02-28 12:00	2026-03-01 12:00 Sun|2026-03-02 12:00 Mon
0 12 * * *	2	2028-02-28 12:00	2028-02-29 12:00 Tue|2028-03-01 12:00 Wed
once 2027-01-01 07:30	3	2026-12-31 08:00	2027-01-01 07:30 Fri
once 2027-01-01 07:30	3	2027-01-01 07:30
TABLE
empty "26 next on fixed clocks: a month end, a leap day, the OR rule, a year end, a weekend, once before and at its time" \
    "$s26_bad"
[[ "$(s26_next 'every 90m' 2 '2026-10-29 12:00')" == "2026-10-29 13:30 Thu|2026-10-29 15:00 Thu" ]] \
    && ok "26 next for every 90m counts from the clock when there is no run yet" \
    || ko "26 next for every 90m counts from the clock when there is no run yet" "$(s26_next 'every 90m' 2 '2026-10-29 12:00')"

# --- Schedules in words ----------------------------------------------------------------------------
# parse --describe reads a schedule in words, and names a zone only when it is not this machine's own; a
# schedule with no simple form is shown as written. LZ stands for this machine's zone and FZ for another
# zone, so the table runs on any machine.
# The machine's zone as schedule.sh's local_zone reads it: TZ when it names one, else /etc/localtime.
s26_lz="${TZ:-}"; s26_lz="${s26_lz#:}"
[[ -n "$s26_lz" ]] || { s26_lz="$(readlink /etc/localtime 2>/dev/null)"; s26_lz="${s26_lz##*/zoneinfo/}"; }
s26_fz=Europe/London
[[ "$s26_lz" == Europe/London ]] && s26_fz=America/New_York
s26_bad=""
while IFS='|' read -r s26_e s26_w; do
    [[ -n "$s26_e" ]] || continue
    s26_e="${s26_e//LZ/$s26_lz}"; s26_e="${s26_e//FZ/$s26_fz}"
    s26_w="${s26_w//LZ/$s26_lz}"; s26_w="${s26_w//FZ/$s26_fz}"
    s26_g="$(s26_x parse --describe "$s26_e" 2>&1)"
    [[ "$s26_g" == "$s26_w" ]] || s26_bad+="$s26_e: got '$s26_g', want '$s26_w'"$'\n'
done <<'TABLE'
CRON_TZ=LZ 40 9 * * 1-5|weekdays 09:40
CRON_TZ=FZ 40 9 * * 1-5|weekdays 09:40 (FZ)
CRON_TZ=FZ 10 9 * * *|daily 09:10 (FZ)
10 9 * * *|daily 09:10
@daily|daily 00:00
once 2027-01-01 09:00|once, Fri 1 Jan 2027 09:00
30 8 * * 1|30 8 * * 1
*/15 9 * * *|*/15 9 * * *
0 9 1 * *|0 9 1 * *
0 9 * * 6,0|0 9 * * 6,0
every 30m|every 30m
TABLE
empty "26 schedules in words: weekdays, daily and once; a zone named only when it is not this machine's; any other schedule as written" "$s26_bad"

# list shows the same words in its schedule and next columns; JSON keeps the raw fields and adds
# schedule_words and next_words beside them. The clock is pinned on a Friday, so the next runs are known.
s26_reset
s26_now="2026-09-30 12:00"
s26_mk past 'once 2026-10-01 09:00'
s26_now="2026-10-30 12:00"
s26_mk mine "CRON_TZ=$s26_lz 40 9 * * 1-5"
s26_mk abroad "CRON_TZ=$s26_fz 40 9 * * 1-5"
s26_mk daily '10 9 * * *'
s26_mk raw '30 8 * * 1'
s26_bad=""
s26_js="$(s26_x list --json 2>&1)"
s26_jq() { printf '%s' "$s26_js" | jq -r --arg n "$1" ".[] | select(.name == \$n) | $2"; }
[[ "$(s26_jq mine '.schedule')" == "CRON_TZ=$s26_lz 40 9 * * 1-5" ]] || s26_bad+="raw schedule: $s26_js"$'\n'
[[ "$(s26_jq mine '.schedule_words + " | " + .next_words')" == "weekdays 09:40 | Mon 2 Nov 09:40" ]] || s26_bad+="mine: $(s26_jq mine '.schedule_words + " | " + .next_words')"$'\n'
[[ "$(s26_jq abroad '.schedule_words')" == "weekdays 09:40 ($s26_fz)" ]] || s26_bad+="abroad: $(s26_jq abroad '.schedule_words')"$'\n'
[[ "$(s26_jq abroad '.next_words | test("^[A-Z][a-z]{2} [0-9]{1,2} [A-Z][a-z]{2} [0-9]{2}:[0-9]{2}$")')" == true ]] || s26_bad+="abroad next: $(s26_jq abroad '.next_words')"$'\n'
[[ "$(s26_jq daily '.schedule_words + " | " + .next_words')" == "daily 09:10 | Sat 31 Oct 09:10" ]] || s26_bad+="daily: $(s26_jq daily '.schedule_words + " | " + .next_words')"$'\n'
[[ "$(s26_jq raw '.schedule_words + " | " + .next_words')" == "30 8 * * 1 | Mon 2 Nov 08:30" ]] || s26_bad+="raw: $(s26_jq raw '.schedule_words + " | " + .next_words')"$'\n'
[[ "$(s26_jq past '.schedule_words + " | " + .next_words')" == "once, Thu 1 Oct 09:00 | " ]] || s26_bad+="past once: $(s26_jq past '.schedule_words + " | " + .next_words')"$'\n'
s26_out="$(s26_x list 2>&1)"
# The list's columns are NAME, STATUS, NEXT, LAST, SCHEDULE: the schedule is last, so it reads after the next run.
[[ "$s26_out" == *"Mon 2 Nov 09:40"*"weekdays 09:40"* && "$s26_out" == *"Sat 31 Oct 09:10"*"daily 09:10"* && "$s26_out" == *"Mon 2 Nov 08:30"*"30 8 * * 1"* ]] \
    || s26_bad+="list columns: $s26_out"$'\n'
[[ "$(head -1 <<<"$s26_out" | awk '{ print $3, $4 }')" == "NEXT LAST" ]] && [[ "$s26_out" == *"SCHEDULE"* ]] \
    || s26_bad+="list header: $(head -1 <<<"$s26_out")"$'\n'
[[ "$s26_out" == *"once, Thu 1 Oct 09:00"* ]] || s26_bad+="list column for the past once: $s26_out"$'\n'
unset s26_now
empty "26 list: the schedule and next columns in words, the raw fields kept in JSON beside schedule_words and next_words; a zone shown only when it is not this machine's; a past once has no next" "$s26_bad"

# --- Rendering: launchd --------------------------------------------------------------------------
s26_reset
s26_mk weekdays '0 9 * * mon-fri'
s26_mk ordays '0 0 1,15 * 5'
s26_mk hourly '@hourly'
s26_mk twomin 'every 2m'
s26_mk later 'once 2099-03-04 05:06'
s26_mk biz '*/15 9-17 * * mon-fri'
s26_mk ormonth '0 0 1-31 * 1'
# s26_plist <name>: the rendered plist's schedule, as JSON, read back by plistlib.
s26_plist() {
    s26_x unit "$1" --backend launchd >"$s26/$1.plist" 2>&1 || { echo "render failed: $(cat "$s26/$1.plist")"; return; }
    python3 - "$s26/$1.plist" <<'PY'
import json, plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
s = p.get("StartCalendarInterval", p.get("StartInterval"))
print(json.dumps({"n": len(s) if isinstance(s, list) else 1, "s": s if not isinstance(s, list) else s[:3],
                  "args": p["ProgramArguments"][2:], "label": p["Label"]}, sort_keys=True))
PY
}
s26_bad=""
s26_want() { local g; g="$(s26_plist "$1")"; [[ "$g" == "$2" ]] || s26_bad+="$1: $g"$'\n'; }
s26_want weekdays '{"args": ["exec", "weekdays"], "label": "agentic-workspace.scheduler.weekdays", "n": 5, "s": [{"Hour": 9, "Minute": 0, "Weekday": 1}, {"Hour": 9, "Minute": 0, "Weekday": 2}, {"Hour": 9, "Minute": 0, "Weekday": 3}]}'
s26_want ordays '{"args": ["exec", "ordays"], "label": "agentic-workspace.scheduler.ordays", "n": 3, "s": [{"Day": 1, "Hour": 0, "Minute": 0}, {"Day": 15, "Hour": 0, "Minute": 0}, {"Hour": 0, "Minute": 0, "Weekday": 5}]}'
s26_want hourly '{"args": ["exec", "hourly"], "label": "agentic-workspace.scheduler.hourly", "n": 1, "s": [{"Minute": 0}]}'
s26_want twomin '{"args": ["exec", "twomin"], "label": "agentic-workspace.scheduler.twomin", "n": 1, "s": 120}'
s26_want later '{"args": ["exec", "later"], "label": "agentic-workspace.scheduler.later", "n": 1, "s": {"Day": 4, "Hour": 5, "Minute": 6, "Month": 3}}'
s26_want ormonth '{"args": ["exec", "ormonth"], "label": "agentic-workspace.scheduler.ormonth", "n": 1, "s": [{"Hour": 0, "Minute": 0}]}'
[[ "$(s26_plist biz)" == *'"n": 180'* ]] || s26_bad+="biz: $(s26_plist biz)"$'\n'
empty "26 launchd: StartCalendarInterval dicts for a weekday list, the OR rule as two sets, @hourly, once, a full OR day; every as StartInterval" "$s26_bad"
s26_bad=""
if command -v plutil >/dev/null 2>&1; then
    for s26_n in weekdays ordays hourly twomin later biz; do plutil -lint "$s26/$s26_n.plist" >/dev/null 2>&1 || s26_bad+="$s26_n"$'\n'; done
    empty "26 launchd: plutil -lint passes all six plists" "$s26_bad"
else
    for s26_n in weekdays ordays hourly twomin later biz; do
        python3 -c 'import plistlib,sys; plistlib.load(open(sys.argv[1],"rb"))' "$s26/$s26_n.plist" 2>/dev/null || s26_bad+="$s26_n"$'\n'
    done
    empty "26 launchd: all six plists load in plistlib (no plutil here)" "$s26_bad"
fi
s26_bad=""
# A full field is left out of the dicts (launchd reads a missing key as every value), so every minute
# of business hours is 45 entries; every fifth minute of the first half of each month is 1,620.
s26_mk everymin '* 9-17 * * 1-5'
[[ "$(s26_plist everymin)" == *'"n": 45, "s": [{"Hour": 9, "Weekday": 1}'* ]] || s26_bad+="everymin: $(s26_plist everymin)"$'\n'
s26_mk toomany '*/5 9-17 1-15 * *'
s26_g="$(s26_x unit toomany --backend launchd 2>&1)"
[[ "$s26_g" == *"needs 1620 launchd calendar entries, more than 400"*"'every <n>m'"* ]] || s26_bad+="toomany: $s26_g"$'\n'
empty "26 launchd: a full minute field is left out (45 entries for every minute of business hours); 1,620 entries are refused with every suggested" "$s26_bad"

# --- Rendering: systemd ---------------------------------------------------------------------------
s26_cal() { s26_x unit "$1" --backend systemd | grep -E '^(OnCalendar|OnActiveSec|OnUnitActiveSec|Persistent)=' | paste -sd'|' -; }
s26_bad=""
s26_cw() { local g; g="$(s26_cal "$1")"; [[ "$g" == "$2" ]] || s26_bad+="$1: $g"$'\n'; }
s26_cw weekdays 'OnCalendar=Mon,Tue,Wed,Thu,Fri *-*-* 09:00:00|Persistent=true'
s26_cw ordays 'OnCalendar=*-*-01,15 00:00:00|OnCalendar=Fri *-*-* 00:00:00|Persistent=true'
s26_cw hourly 'OnCalendar=*-*-* *:00:00|Persistent=true'
s26_cw twomin 'OnActiveSec=120|OnUnitActiveSec=120'
s26_cw later 'OnCalendar=2099-03-04 05:06:00|Persistent=true'
s26_cw biz 'OnCalendar=Mon,Tue,Wed,Thu,Fri *-*-* 09,10,11,12,13,14,15,16,17:00,15,30,45:00|Persistent=true'
s26_g="$(s26_x unit weekdays --backend systemd)"
[[ "$s26_g" == *"Type=oneshot"*"ExecStart=/bin/bash \"$s26/data/runner/schedule.sh\" exec weekdays"*"AccuracySec=1s"*"Unit=aw-scheduler-weekdays.service"*"WantedBy=timers.target"* ]] \
    || s26_bad+="the service and timer: $s26_g"$'\n'
empty "26 systemd: OnCalendar lines (two for the OR rule), Persistent=true, every as OnActiveSec + OnUnitActiveSec, AccuracySec=1s, a oneshot service on the runner's copy" "$s26_bad"
if command -v systemd-analyze >/dev/null 2>&1; then
    s26_bad=""
    for s26_n in weekdays ordays hourly later biz; do
        while IFS= read -r s26_l; do
            systemd-analyze calendar "${s26_l#OnCalendar=}" >/dev/null 2>&1 || s26_bad+="$s26_n: $s26_l"$'\n'
        done < <(s26_x unit "$s26_n" --backend systemd | grep '^OnCalendar=')
    done
    empty "26 systemd: systemd-analyze calendar accepts every OnCalendar line" "$s26_bad"
else
    skp "26 systemd: systemd-analyze not on PATH; OnCalendar lines checked by text only"
fi

# --- Rendering and the managed block: cron --------------------------------------------------------
s26_bad=""
s26_cl() { s26_x unit "$1" --backend cron | cut -d' ' -f1-5; }
[[ "$(s26_cl weekdays)" == "0 9 * * 1,2,3,4,5" ]] || s26_bad+="weekdays: $(s26_cl weekdays)"$'\n'
[[ "$(s26_cl ordays)" == "0 0 1,15 * 5" ]] || s26_bad+="ordays: $(s26_cl ordays)"$'\n'
# A full day-of-month under the OR rule stays a list, so cron still reads it as restricted.
[[ "$(s26_cl ormonth)" == "0 0 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31 * 1" ]] || s26_bad+="ormonth: $(s26_cl ormonth)"$'\n'
[[ "$(s26_cl later)" == "6 5 4 3 *" ]] || s26_bad+="later: $(s26_cl later)"$'\n'
[[ "$(s26_cl twomin)" == "* * * * *" ]] || s26_bad+="twomin: $(s26_cl twomin)"$'\n'
empty "26 cron: numeric fields, the OR rule kept, once as its date, every as a per-minute line the runner gates" "$s26_bad"

s26_reset
s26_backend=cron
s26_mine=$'MAILTO=""\n15 3 * * * /usr/local/bin/backup --quiet\n# my own comment\n@reboot /usr/bin/true'
printf '%s\n' "$s26_mine" >"$s26/bin/crontab.txt"
s26_mk alpha '0 9 * * *'; s26_mk beta '30 18 * * 5'
s26_ct="$(cat "$s26/bin/crontab.txt")"
s26_bad=""
[[ "$(printf '%s\n' "$s26_ct" | head -n 4)" == "$s26_mine" ]] || s26_bad+="the person's four lines were not kept first, as they were"$'\n'
[[ "$(printf '%s\n' "$s26_ct" | grep -c ' exec \(alpha\|beta\) ')" == 2 ]] || s26_bad+="not two task lines"$'\n'
[[ "$(printf '%s\n' "$s26_ct" | grep -c '^# BEGIN agentic-workspace scheduler')" == 1 && "$(printf '%s\n' "$s26_ct" | grep -c '^# END agentic-workspace scheduler')" == 1 ]] \
    || s26_bad+="not one marked block"$'\n'
s26_x pause alpha >/dev/null 2>&1
[[ "$(grep -c ' exec ' "$s26/bin/crontab.txt")" == 1 ]] && grep -q ' exec beta ' "$s26/bin/crontab.txt" || s26_bad+="pause did not leave beta alone in the block"$'\n'
s26_says 'Unit (cron): none' show alpha || s26_bad+="show does not say a paused task has no unit"$'\n'
s26_x resume alpha >/dev/null 2>&1; s26_x edit beta --schedule '45 7 * * *' >/dev/null 2>&1
grep -q '^45 7 \* \* \* .* exec beta ' "$s26/bin/crontab.txt" || s26_bad+="edit did not render beta's new line"$'\n'
s26_says 'Unit (cron): installed and matching the file' show beta || s26_bad+="show does not report beta installed"$'\n'
s26_x delete alpha >/dev/null 2>&1; s26_x delete beta >/dev/null 2>&1
[[ "$(cat "$s26/bin/crontab.txt")" == "$s26_mine" ]] || s26_bad+="after both deletes the crontab is not the person's own: $(cat "$s26/bin/crontab.txt")"$'\n'
empty "26 cron: the block written between its markers, a pause, resume and edit inside it, and after the deletes the person's crontab exactly as it was" "$s26_bad"

# --- Create, edit, pause, resume, delete and sync: none, launchd, systemd ------------------------
for s26_backend in none launchd systemd; do
    s26_reset
    s26_bad=""
    case $s26_backend in
        none) s26_unit() { printf '%s' "$s26/data/units/$1.cron"; } ;;
        launchd) s26_unit() { printf '%s' "$s26/LaunchAgents/agentic-workspace.scheduler.$1.plist"; } ;;
        systemd) s26_unit() { printf '%s' "$s26/systemd/aw-scheduler-$1.timer"; } ;;
    esac
    s26_loaded() {
        case $s26_backend in
            none) [[ -f "$(s26_unit "$1")" ]] ;;
            launchd) grep -qx "agentic-workspace.scheduler.$1" "$s26/bin/loaded" 2>/dev/null ;;
            systemd) grep -qx "aw-scheduler-$1.timer" "$s26/bin/active" 2>/dev/null ;;
        esac
    }
    s26_out="$(s26_x create daily --schedule '0 7 * * *' --cwd "$s26/work" --prompt 'Say OK.' --model haiku --dry-run 2>&1)"
    [[ "$s26_out" == *"Would write"*"schedule: 0 7 * * *"*"Next fire times:"* && ! -e "$s26/cfg/tasks/daily.md" ]] || s26_bad+="--dry-run wrote, or did not show the file and fire times"$'\n'
    s26_mk daily '0 7 * * *' --model haiku
    [[ -f "$s26/cfg/tasks/daily.md" ]] || s26_bad+="create wrote no task file"$'\n'
    [[ -f "$(s26_unit daily)" ]] && s26_loaded daily || s26_bad+="create left no loaded unit"$'\n'
    [[ -x "$s26/data/runner/schedule.sh" ]] && cmp -s "$s26_sh" "$s26/data/runner/schedule.sh" || s26_bad+="no runner copy equal to the script"$'\n'
    grep -q "^CLAUDE_BIN=.*bin/claude$" "$s26/data/env" || s26_bad+="the env file does not record claude's absolute path"$'\n'
    s26_says "Unit ($s26_backend): installed and matching the file" show daily || s26_bad+="show does not report the unit installed"$'\n'
    s26_x create daily --schedule '0 7 * * *' --cwd "$s26/work" --prompt x >/dev/null 2>&1 && s26_bad+="a second create of the same name succeeded"$'\n'
    s26_x edit daily --schedule '30 6 * * *' >/dev/null 2>&1
    grep -q '^schedule: 30 6 \* \* \*$' "$s26/cfg/tasks/daily.md" && s26_says 'installed and matching' show daily || s26_bad+="edit did not re-render the unit"$'\n'
    s26_x edit daily --schedule '0 25 * * *' >/dev/null 2>&1 && s26_bad+="an invalid edit was accepted"$'\n'
    grep -q '^schedule: 30 6 \* \* \*$' "$s26/cfg/tasks/daily.md" || s26_bad+="an invalid edit changed the file"$'\n'
    s26_x pause daily --reason 'on holiday' >/dev/null 2>&1
    grep -q '^status: paused$' "$s26/cfg/tasks/daily.md" && grep -q '^paused_reason: on holiday$' "$s26/cfg/tasks/daily.md" || s26_bad+="pause did not write status and reason"$'\n'
    [[ ! -e "$(s26_unit daily)" ]] && ! s26_loaded daily || s26_bad+="pause left the unit"$'\n'
    s26_x resume daily >/dev/null 2>&1
    grep -q '^status: active$' "$s26/cfg/tasks/daily.md" && ! grep -q '^paused_reason:' "$s26/cfg/tasks/daily.md" || s26_bad+="resume did not clear status and reason"$'\n'
    [[ -f "$(s26_unit daily)" ]] && s26_loaded daily || s26_bad+="resume left no loaded unit"$'\n'
    # sync puts right a unit removed by hand, a unit edited by hand and a unit with no task file.
    rm -f "$(s26_unit daily)"
    s26_says "missing, so it will not fire" show daily || s26_bad+="show does not report a missing unit"$'\n'
    s26_mk other '0 8 * * *'
    printf '# edited by hand\n' >>"$(s26_unit other)"
    s26_says 'differs from the file' show other || s26_bad+="show does not report a hand-edited unit"$'\n'
    s26_mk orphan '0 9 * * *'; rm -f "$s26/cfg/tasks/orphan.md"
    s26_out="$(s26_x sync 2>&1)"
    [[ "$s26_out" == *"2 active task(s) installed"*"1 orphan unit(s) removed"* ]] || s26_bad+="sync said: $s26_out"$'\n'
    s26_says 'installed and matching' show daily && s26_says 'installed and matching' show other || s26_bad+="sync did not put both units right"$'\n'
    [[ ! -e "$(s26_unit orphan)" ]] && ! s26_loaded orphan || s26_bad+="sync left the orphan's unit"$'\n'
    s26_x list --json | jq -e 'length == 2 and (map(.name) | sort == ["daily", "other"]) and all(.status == "active")' >/dev/null || s26_bad+="list --json: $(s26_x list --json)"$'\n'
    s26_x show daily --json | jq -e '.unit == "installed" and .fields.model == "haiku" and (.next | length) == 5 and .prompt == "Write the date to out.txt and reply OK."' >/dev/null \
        || s26_bad+="show --json: $(s26_x show daily --json)"$'\n'
    s26_x delete daily >/dev/null 2>&1
    s26_t=("$s26/cfg/tasks/.trash/"daily-[0-9]*-[0-9]*.md)
    [[ ! -e "$s26/cfg/tasks/daily.md" && -f "${s26_t[0]}" ]] || s26_bad+="delete did not move the file to .trash/"$'\n'
    [[ ! -e "$(s26_unit daily)" ]] && ! s26_loaded daily || s26_bad+="delete left the unit"$'\n'
    case $s26_backend in
        launchd) grep -q '^bootstrap gui/501 ' "$s26/bin/launchctl.log" && grep -q '^bootout gui/501/agentic-workspace.scheduler.daily$' "$s26/bin/launchctl.log" \
                     || s26_bad+="launchctl was not driven in the gui/501 domain: $(sort -u "$s26/bin/launchctl.log")"$'\n' ;;
        systemd) grep -q '^--user enable aw-scheduler-daily.timer$' "$s26/bin/systemctl.log" && grep -q '^--user disable --now aw-scheduler-daily.timer$' "$s26/bin/systemctl.log" \
                     && grep -q '^--user daemon-reload$' "$s26/bin/systemctl.log" && [[ ! -e "$s26/systemd/aw-scheduler-daily.service" ]] \
                     || s26_bad+="systemctl --user was not driven as expected: $(sort -u "$s26/bin/systemctl.log")"$'\n' ;;
    esac
    empty "26 $s26_backend: create (and --dry-run), a refused duplicate, edit, a refused invalid edit, pause, resume, show's unit states, sync, list and show --json, delete to .trash/" "$s26_bad"
done
s26_backend=none
unset -f s26_unit s26_loaded
s26_out="$(env -u SCHEDULER_BACKEND SCHEDULER_HOME="$s26/cfg" SCHEDULER_DATA="$s26/data" SCHEDULER_CRONTAB=/nonexistent/crontab \
    SCHEDULER_SYSTEMCTL=/nonexistent/systemctl PATH=/usr/bin:/bin "$st_bash" -c 'uname() { echo Plan9; }; export -f uname; "$0" "$@"' "$st_bash" "$s26_sh" sync 2>&1)"
[[ "$s26_out" == *"no launchd, systemd user instance or crontab found"*"doctor"* ]] \
    && ok "26 a host with no scheduler is an error naming doctor, not a quiet none backend" \
    || ko "26 a host with no scheduler is an error naming doctor, not a quiet none backend" "$s26_out"

# --- The runner -----------------------------------------------------------------------------------
s26_reset
s26_backend=none
s26_run() { s26_x run "$1" --wait >/dev/null 2>&1; }
s26_last() { ls -1d "$s26/data/runs/$1"/* 2>/dev/null | LC_ALL=C sort | tail -n 1 | sed 's#$#/#'; }
s26_meta() { sed -n "s/^$2=//p" "$(s26_last "$1")meta" 2>/dev/null | tail -n 1; }   # no run: empty, and the check fails   # a reply appends; the last line holds

s26_mode ok
s26_mk good '0 7 * * *' --model haiku --effort low --allowed-tools 'Read Write' --add-dirs "$s26/work, $s26" --max-budget-usd 0.5 --notify-on always \
    --notify 'printf "%s %s\n" "$SCHEDULER_TASK" "$SCHEDULER_STATUS" >"$SCHEDULER_RUN_DIR/../../notified"'
s26_run good
s26_d="$(s26_last good)"
s26_bad=""
[[ "$(s26_meta good status)" == ok && "$(s26_meta good attempts)" == 1 && "$(s26_meta good cost_usd)" == 0.0125 && "$(s26_meta good trigger)" == manual ]] \
    || s26_bad+="meta: $(cat "$s26_d/meta")"$'\n'
for s26_f in task.md prompt.txt attempt-1.json attempt-1.stderr meta; do [[ -e "$s26_d$s26_f" ]] || s26_bad+="no $s26_f in the run folder"$'\n'; done
cmp -s "$s26_d/task.md" "$s26/cfg/tasks/good.md" || s26_bad+="the run's task.md is not the task file"$'\n'
s26_args="$(paste -sd'|' - <"$s26/bin/last-args")"
s26_sid="$(s26_meta good session_id)"
[[ "$s26_args" == "-p|--output-format|stream-json|--verbose|--session-id|$s26_sid|--name|scheduled: good "*"|--append-system-prompt|"*"nobody is watching"*"|--permission-mode|dontAsk|--model|haiku|--effort|low|--allowedTools|Read Write|--max-budget-usd|0.5|--add-dir|$s26/work|--add-dir|$s26" ]] \
    || s26_bad+="claude's arguments: $s26_args"$'\n'
[[ "$s26_sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || s26_bad+="session id '$s26_sid' is not a uuid"$'\n'
[[ "$(cat "$s26/bin/last-stdin")" == "Write the date to out.txt and reply OK." ]] || s26_bad+="the prompt did not arrive on stdin"$'\n'
grep -qx 'AW_HEADLESS_RUN=1' "$s26/bin/last-env" && grep -qx 'CLOSEOUT_DISABLED=1' "$s26/bin/last-env" || s26_bad+="AW_HEADLESS_RUN or CLOSEOUT_DISABLED not set"$'\n'
grep -q '^CLAUDECODE=' "$s26/bin/last-env" && s26_bad+="the run inherited CLAUDECODE"$'\n'
[[ "$(cat "$s26/bin/last-pwd")" == "$(cd "$s26/work" && pwd -P)" || "$(cat "$s26/bin/last-pwd")" == "$s26/work" ]] || s26_bad+="claude ran in $(cat "$s26/bin/last-pwd")"$'\n'
[[ "$(cat "$s26/data/runs/notified" 2>/dev/null)" == "good ok" ]] || s26_bad+="the notify command did not run with the task and status"$'\n'
s26_says $'Result:\n  OK, done.' log good || s26_bad+="log does not print the result text: $(s26_x log good)"$'\n'
s26_says "claude --resume $s26_sid" show good || s26_bad+="show does not give the resume command"$'\n'
empty "26 runner: a success, with the run folder, claude's flags, the prompt on stdin, the headless environment, notify, log and the resume command" "$s26_bad"

# The appended prompt names the task's tools, one a line, a pattern kept whole; a task with none gets
# the headless lines alone.
s26_bad=""
s26_mk tooled '0 7 * * *' --retries 0 --allowed-tools 'Read, Bash(bash fetch.sh:*) Bash(git log:*)' --disallowed-tools 'WebFetch'
s26_run tooled
s26_sp="$(sed -n '/^--append-system-prompt$/,/^--permission-mode$/p' "$s26/bin/last-args" | sed '1d;$d')"
[[ "$s26_sp" == *"nobody is watching"*$'This run may use these tools, and anything else is refused without asking:\n- Read\n- Bash(bash fetch.sh:*)\n- Bash(git log:*)\n\nThese are refused:\n- WebFetch\n\nA refused call refuses that call only'*"no cd first, and no &&, ; or redirect." ]] \
    || s26_bad+="the appended prompt: $s26_sp"$'\n'
s26_mk bare-tools '0 7 * * *' --retries 0
s26_run bare-tools
s26_sp="$(sed -n '/^--append-system-prompt$/,/^--permission-mode$/p' "$s26/bin/last-args" | sed '1d;$d')"
[[ "$s26_sp" != *"This run may use"* && "$s26_sp" == *"nobody is watching"* ]] || s26_bad+="a task with no tool list got one: $s26_sp"$'\n'
empty "26 the appended prompt lists the task's tools one a line (a pattern kept whole, refused ones apart) and how a pattern matches; nothing for a task with none" "$s26_bad"

s26_mode failonce
s26_mk retry '0 7 * * *' --retries 2 --retry-delay 1s
s26_run retry
[[ "$(s26_meta retry status)" == ok && "$(s26_meta retry attempts)" == 2 && -s "$(s26_last retry)attempt-1.json" && "$(s26_meta retry cost_usd)" == 0.0120 ]] \
    && ok "26 runner: a failure is retried and the second attempt succeeds; the cost is summed over attempts" \
    || ko "26 runner: a failure is retried and the second attempt succeeds; the cost is summed over attempts" "$(cat "$(s26_last retry)meta")"

s26_mode hang
s26_mk slow '0 7 * * *' --timeout 5s --retries 0
SECONDS=0; s26_run slow; s26_secs=$SECONDS
sleep 1
# The stub wrote its pid before it became sleep; that process is gone once the timeout has stopped it.
[[ "$(s26_meta slow status)" == timeout && "$(s26_meta slow exit)" == 124 && $s26_secs -lt 30 ]] && ! kill -0 "$(cat "$s26/bin/hang.pid")" 2>/dev/null \
    && ok "26 runner: a run past its timeout is stopped with its process group and recorded as timeout (${s26_secs}s)" \
    || ko "26 runner: a run past its timeout is stopped with its process group and recorded as timeout (${s26_secs}s)" "$(cat "$(s26_last slow)meta"; ps -p "$(cat "$s26/bin/hang.pid")")"

s26_mk lap '0 7 * * *' --timeout 8s --retries 0
s26_x run lap >/dev/null 2>&1
s26_i=0; while [[ ! -d "$s26/data/locks/lap" && $s26_i -lt 50 ]]; do sleep 0.1; s26_i=$((s26_i + 1)); done
s26_run lap
s26_skip="$(s26_meta lap status)/$(s26_meta lap reason)"
s26_i=0; while [[ -d "$s26/data/locks/lap" && $s26_i -lt 150 ]]; do sleep 0.1; s26_i=$((s26_i + 1)); done
[[ "$s26_skip" == skipped/running && "$(ls "$s26/data/runs/lap" | wc -l | tr -d ' ')" == 2 ]] \
    && ok "26 runner: a run while another holds the lock is recorded skipped: running, and the first is unaffected" \
    || ko "26 runner: a run while another holds the lock is recorded skipped: running, and the first is unaffected" "$s26_skip; $(ls "$s26/data/runs/lap")"

s26_mode fail
s26_mk flaky '0 7 * * *' --retries 0 --pause-after-failures 3
s26_bad=""
s26_run flaky; s26_run flaky
grep -q '^status: active$' "$s26/cfg/tasks/flaky.md" || s26_bad+="paused after two"$'\n'
s26_run flaky
grep -q '^status: paused$' "$s26/cfg/tasks/flaky.md" || s26_bad+="not paused after three"$'\n'
grep -q '^paused_reason: paused itself after 3 failed runs in a row' "$s26/cfg/tasks/flaky.md" || s26_bad+="no reason in the file"$'\n'
[[ ! -e "$s26/data/units/flaky.cron" ]] || s26_bad+="the unit stayed"$'\n'
s26_says 'paused itself after 3 failed runs' show flaky || s26_bad+="show does not give the reason"$'\n'
s26_says 'it went wrong' log flaky || s26_bad+="log does not show the stderr tail"$'\n'
empty "26 runner: three failed runs in a row pause the task, with the reason in its file and its unit removed" "$s26_bad"
s26_mode ok
s26_x resume flaky >/dev/null 2>&1
s26_run flaky
[[ "$(cat "$s26/data/state/flaky.failures")" == 0 && -e "$s26/data/units/flaky.cron" ]] \
    && ok "26 runner: resume reinstalls the unit and a success resets the failure count" \
    || ko "26 runner: resume reinstalls the unit and a success resets the failure count"

# Scheduled (not manual) runs, through the runner's copy as the OS calls it, on a fixed clock.
s26_exec() { env -i HOME="$HOME" SCHEDULER_HOME="$s26/cfg" SCHEDULER_DATA="$s26/data" SCHEDULER_NOTIFY_DESKTOP=0 SCHEDULER_BACKEND="$s26_backend" \
    ${1:+SCHEDULER_NOW="$1"} /bin/bash "$s26/data/runner/schedule.sh" exec "$2"; }
s26_now='2026-10-29 10:00' s26_mk one 'once 2026-10-29 11:00'
s26_bad=""
s26_exec '2026-10-29 10:30' one
[[ ! -d "$s26/data/runs/one" ]] || s26_bad+="ran before its time"$'\n'
s26_exec '2026-10-29 11:00' one
[[ "$(s26_meta one status)" == ok && "$(s26_meta one trigger)" == schedule ]] || s26_bad+="did not run at its time"$'\n'
grep -q '^status: done$' "$s26/cfg/tasks/one.md" && [[ ! -e "$s26/data/units/one.cron" ]] || s26_bad+="not marked done with its unit removed"$'\n'
s26_exec '2026-10-30 11:00' one
[[ "$(ls "$s26/data/runs/one" | wc -l | tr -d ' ')" == 1 ]] || s26_bad+="a done task ran again"$'\n'
s26_x resume one >/dev/null 2>&1 && s26_bad+="a once task whose date has passed was resumed"$'\n'
s26_x create gone --schedule 'once 2020-01-01 00:00' --cwd "$s26/work" --prompt x >/dev/null 2>&1 && s26_bad+="a once in the past was created"$'\n'
empty "26 runner: once waits for its time, runs, is marked done with its unit removed, and does not run again" "$s26_bad"

s26_bad=""
s26_mk resting '0 7 * * *'; s26_x pause resting >/dev/null 2>&1
s26_exec '' resting
[[ ! -d "$s26/data/runs/resting" ]] || s26_bad+="a scheduled run of a paused task ran"$'\n'
s26_x run resting --wait >/dev/null 2>&1
[[ "$(s26_meta resting status)" == ok ]] || s26_bad+="run now of a paused task did not run"$'\n'
s26_mk broken '0 7 * * *'
sed 's/^retries: 1$/retries: lots/' "$s26/cfg/tasks/broken.md" >"$s26/cfg/tasks/broken.md.tmp" && mv "$s26/cfg/tasks/broken.md.tmp" "$s26/cfg/tasks/broken.md"
s26_exec '' broken
[[ ! -d "$s26/data/runs/broken" ]] && grep -q "broken: not run, the task file has problems: retries 'lots'" "$s26/data/logs/runner.log" || s26_bad+="an invalid task ran, or the runner log does not say why"$'\n'
s26_says "Task broken: retries 'lots' is not 0-9" doctor 2>&1 || s26_bad+="doctor does not name the invalid task"$'\n'
empty "26 runner: a paused task is skipped on schedule but runs on run-now; an invalid file is not run, and the runner log and doctor say why" "$s26_bad"

s26_mk pruned '0 7 * * *' --keep-runs 3
for s26_i in 1 2 3 4 5; do s26_run pruned; done
s26_runs="$(ls "$s26/data/runs/pruned")"
[[ "$(wc -l <<<"$s26_runs" | tr -d ' ')" == 3 ]] && [[ "$(s26_x runs pruned | grep -c ' ok ')" == 3 ]] \
    && ok "26 runner: five runs pruned to keep_runs (3), and runs lists the three kept" \
    || ko "26 runner: five runs pruned to keep_runs (3), and runs lists the three kept" "$s26_runs"
s26_x runs --json | jq -e 'length >= 10 and all(has("task") and has("status") and has("session_id"))' >/dev/null \
    && ok "26 runs with no name lists every task's runs, newest first, as JSON" \
    || ko "26 runs with no name lists every task's runs, newest first, as JSON" "$(s26_x runs --json | head -c 400)"

# Under cron, an every task fires on a per-minute line and the runner skips until its interval passes.
s26_backend=cron
: >"$s26/bin/crontab.txt"
s26_mk ninety 'every 90m'
s26_bad=""
s26_exec2() { env -i HOME="$HOME" SCHEDULER_HOME="$s26/cfg" SCHEDULER_DATA="$s26/data" SCHEDULER_NOTIFY_DESKTOP=0 SCHEDULER_NOW="$1" \
    /bin/bash "$s26/data/runner/schedule.sh" exec ninety; }
s26_exec2 '2026-10-29 10:00'; s26_exec2 '2026-10-29 10:01'; s26_exec2 '2026-10-29 11:29'; s26_exec2 '2026-10-29 11:30'
[[ "$(ls "$s26/data/runs/ninety" 2>/dev/null | wc -l | tr -d ' ')" == 2 ]] || s26_bad+="$(ls "$s26/data/runs/ninety" 2>/dev/null | wc -l | tr -d ' ') runs, want 2"$'\n'
empty "26 cron: every 90m fires on a per-minute line, and the runner lets one run through per 90 minutes" "$s26_bad"
s26_backend=none

# --- Porting features: zones, chrome, replies, result_to, late runs, connectors ----------------------
s26_reset
s26_backend=none
s26_mode ok
s26_bad=""
# The zone this machine is in reads as local; another one is kept, and next prints local times beside it.
s26_here="$(readlink /etc/localtime 2>/dev/null)"; s26_here="${s26_here##*/zoneinfo/}"
[[ -n "$s26_here" ]] || s26_here=UTC
[[ "$(TZ="$s26_here" s26_x next "CRON_TZ=$s26_here 0 9 * * *" --count 1 --from '2026-10-29 08:00')" == "2026-10-29 09:00 Thu" ]] \
    || s26_bad+="CRON_TZ naming this machine's zone is not read as local"$'\n'
[[ "$(TZ=Europe/London s26_x next 'CRON_TZ=America/New_York 0 9 * * *' --count 3 --from '2026-10-29 12:00' | paste -sd'|' -)" \
    == "2026-10-29 13:00 Thu (09:00 America/New_York)|2026-10-30 13:00 Fri (09:00 America/New_York)|2026-10-31 13:00 Sat (09:00 America/New_York)" ]] \
    || s26_bad+="New York from London: $(TZ=Europe/London s26_x next 'CRON_TZ=America/New_York 0 9 * * *' --count 3 --from '2026-10-29 12:00')"$'\n'
# The US clocks change a week after the UK's, so 09:00 in New York moves from 13:00 to 14:00 in London.
[[ "$(TZ=Europe/London s26_x next 'CRON_TZ=America/New_York 0 9 * * mon' --count 1 --from '2026-11-01 12:00')" == "2026-11-02 14:00 Mon (09:00 America/New_York)" ]] \
    || s26_bad+="the zone's clock change is not followed"$'\n'
[[ "$(s26_x parse 'CRON_TZ=Nowhere/Atlantis 0 9 * * *' 2>&1)" == *"not one this machine knows"* ]] || s26_bad+="an unknown zone is not refused"$'\n'
[[ "$(s26_x parse 'CRON_TZ=Asia/Tokyo every 5m' 2>&1)" == *"no meaning for 'every'"* ]] || s26_bad+="a zone on every is not refused"$'\n'
TZ=Europe/London s26_mk ny 'CRON_TZ=America/New_York 0 9 * * mon-fri'
[[ "$(TZ=Europe/London s26_x unit ny --backend systemd | grep '^OnCalendar=')" == "OnCalendar=Mon,Tue,Wed,Thu,Fri *-*-* 09:00:00 America/New_York" ]] \
    || s26_bad+="systemd does not carry the zone: $(TZ=Europe/London s26_x unit ny --backend systemd | grep OnCalendar)"$'\n'
for s26_b in launchd cron; do
    [[ "$(TZ=Europe/London s26_x unit ny --backend $s26_b 2>&1)" == *"$s26_b has no time zones"* ]] || s26_bad+="$s26_b does not refuse a foreign zone"$'\n'
done
s26_x create tzboth --schedule 'CRON_TZ=Asia/Tokyo 0 9 * * *' --timezone Europe/Paris --cwd "$s26/work" --prompt x >/dev/null 2>&1 \
    && s26_bad+="a CRON_TZ and a different timezone field were accepted together"$'\n'
[[ "$(TZ=Europe/London s26_x prev 'CRON_TZ=America/New_York 0 9 * * *' --at '2026-10-29 12:59')" == "2026-10-28 13:00" ]] || s26_bad+="prev in a foreign zone"$'\n'
empty "26 CRON_TZ: this machine's zone is local; another zone is followed through its clock changes, kept by systemd, refused by launchd and cron" "$s26_bad"

s26_bad=""
while IFS='	' read -r s26_e s26_at s26_w; do
    [[ -n "$s26_e" ]] || continue
    s26_g="$(s26_x prev "$s26_e" --at "$s26_at")"
    [[ "$s26_g" == "$s26_w" ]] || s26_bad+="$s26_e at $s26_at: got '$s26_g', want '$s26_w'"$'\n'
done <<'TABLE'
0 9 31 * *	2026-04-15 12:00	2026-03-31 09:00
0 0 29 2 *	2027-06-01 00:00	2024-02-29 00:00
0 0 13 * 5	2026-01-12 23:59	2026-01-09 00:00
*/15 9-17 * * mon-fri	2026-11-02 08:59	2026-10-30 17:45
30 7 * * *	2026-11-02 07:30	2026-11-02 07:30
0 0 1 1 *	2026-01-01 00:00	2026-01-01 00:00
once 2026-01-01 00:00	2026-06-01 00:00	2026-01-01 00:00
every 5m	2026-06-01 00:00	
TABLE
empty "26 prev (a run's due time): a month end, a leap day, the OR rule, a weekend, the exact minute, a year start, once; none for every" "$s26_bad"

# A late run: due at the latest fire time before its start, and marked late past five minutes.
s26_bad=""
s26_mk early '0 0 1 1 *'
s26_exec '' early
[[ "$(s26_meta early due)" == "$(date '+%Y')-01-01 00:00" ]] || s26_bad+="due: $(s26_meta early due)"$'\n'
s26_says 'late ' runs early || s26_bad+="runs does not mark it late: $(s26_x runs early)"$'\n'
s26_says 'started late ' log early || s26_bad+="log does not say it started late"$'\n'
s26_x show early --json | jq -e '.last_run.late | startswith("late ")' >/dev/null || s26_bad+="show --json has no late"$'\n'
s26_mk ontime '* * * * *'
s26_exec '' ontime
[[ -n "$(s26_meta ontime due)" ]] && ! s26_says 'late' runs ontime || s26_bad+="a run on its own minute is marked late, or has no due time"$'\n'
s26_x run ontime --wait >/dev/null 2>&1
[[ -z "$(s26_meta ontime due)" ]] || s26_bad+="a manual run has a due time"$'\n'
empty "26 a scheduled run records its due time and is marked late when it started more than five minutes after it; on time and manual runs are not" "$s26_bad"

# chrome, result_to, and the notify command's environment.
s26_bad=""
s26_mk browse '0 7 * * *' --chrome true --result-to 'out/{name}-{date}.md' --notify-on always \
    --notify 'env | grep "^SCHEDULER_" | sort >"$SCHEDULER_RUN_DIR/notify.env"'
s26_run browse
grep -qx -- '--chrome' "$s26/bin/last-args" || s26_bad+="no --chrome"$'\n'
s26_rf="$s26/work/out/browse-$(date '+%Y-%m-%d').md"
[[ "$(cat "$s26_rf" 2>/dev/null)" == "OK, done." ]] || s26_bad+="result_to: $(ls "$s26/work/out" 2>&1)"$'\n'
s26_ne="$(cat "$(s26_last browse)notify.env" 2>/dev/null)"
for s26_v in SCHEDULER_TASK=browse SCHEDULER_STATUS=ok "SCHEDULER_RUN=$(basename "$(s26_last browse)")" "SCHEDULER_RESULT_FILE=$(s26_last browse)result.txt" "SCHEDULER_RESUME=cd "; do
    grep -qF "$s26_v" <<<"$s26_ne" || s26_bad+="notify has no $s26_v"$'\n'
done
s26_x create badchrome --schedule '0 7 * * *' --cwd "$s26/work" --prompt x --chrome yes >/dev/null 2>&1 && s26_bad+="chrome: yes was accepted"$'\n'
empty "26 chrome: true passes --chrome; result_to gets the final message with {name} and {date}; notify sees the task, status, run, result file and resume command" "$s26_bad"

# A run that waits for a person: waiting, then reply continues the session and settles it.
s26_bad=""
s26_mk shortlist '0 7 * * *' --awaits-reply true --result-to 'shortlist.md' --notify 'printf "%s\n" "$SCHEDULER_STATUS" >>"$SCHEDULER_RUN_DIR/../../notified-shortlist"'
s26_run shortlist
s26_w="$(s26_last shortlist)"
[[ "$(s26_meta shortlist status)" == waiting && -f "$s26/data/state/shortlist.waiting" ]] || s26_bad+="not waiting: $(s26_meta shortlist status)"$'\n'
[[ "$(cat "$s26/data/runs/notified-shortlist" 2>/dev/null)" == waiting ]] || s26_bad+="no notification for waiting under notify_on: failure"$'\n'
s26_mk plain '0 7 * * *'; s26_run plain
[[ "$(s26_x list | sed -n 2p)" == shortlist* && "$(s26_x list)" == *"awaiting a reply since"* ]] || s26_bad+="list does not put the waiting task first: $(s26_x list)"$'\n'
[[ "$(s26_x list --json | jq -r '.[0].name + " " + .[0].waiting')" == "shortlist $(basename "$s26_w")" ]] || s26_bad+="list --json"$'\n'
s26_says "Awaiting a reply: run $(basename "$s26_w")" show shortlist || s26_bad+="show does not lead with the waiting run"$'\n'
s26_out="$(s26_x reply shortlist '1, 3 and 5' 2>&1)"
[[ "$s26_out" == *"Replied to shortlist's run"*": ok."*"Acted on: 1, 3 and 5"* ]] || s26_bad+="reply said: $s26_out"$'\n'
grep -qx -- '--resume' "$s26/bin/last-args" && grep -qx "$(s26_meta shortlist session_id)" "$s26/bin/last-args" \
    && grep -qx -- '--permission-mode' "$s26/bin/last-args" || s26_bad+="reply did not resume the run's session with the task's flags"$'\n'
[[ "$(s26_meta shortlist status)" == ok && "$(s26_meta shortlist reply_steps)" == 1 && -f "${s26_w}reply-1.json" && ! -f "$s26/data/state/shortlist.waiting" ]] \
    || s26_bad+="after the reply: $(cat "${s26_w}meta")"$'\n'
[[ "$(cat "$s26/work/shortlist.md")" == $'OK, done.\n\n---\n\nActed on: 1, 3 and 5' ]] || s26_bad+="result_to after the reply: $(cat "$s26/work/shortlist.md")"$'\n'
s26_says $'Reply 1:\n  > 1, 3 and 5' log shortlist || s26_bad+="log does not show the reply"$'\n'
s26_x reply shortlist 'again' >/dev/null 2>&1 && s26_bad+="a second reply to a settled run was accepted"$'\n'
empty "26 awaits_reply: a good run waits (notified, listed first, shown first); reply resumes its session, settles it ok, appends to result_to and is logged" "$s26_bad"
s26_bad=""
s26_mk stale '0 7 * * *' --awaits-reply true --reply-window 1h
s26_run stale
printf 'end_epoch=%s\n' "$(( $(date +%s) - 7200 ))" >>"$(s26_last stale)meta"
s26_says 'expired' runs stale || s26_bad+="runs does not show it expired"$'\n'
[[ "$(s26_x reply stale 'too late' 2>&1)" == *"has expired"* ]] || s26_bad+="reply to an expired run was not refused"$'\n'
[[ "$(s26_x list --json | jq -r '.[] | select(.name == "stale") | .waiting')" == "" ]] || s26_bad+="an expired run still lists as waiting"$'\n'
empty "26 a waiting run past its reply_window reads expired, is refused a reply, and no longer lists as waiting" "$s26_bad"

# Connectors travel as names, and doctor <name> looks for each in claude mcp list, run in the task's folder.
s26_bad=""
s26_mk mail '0 7 * * *' --requires 'Gmail, Google_Calendar, Notion, Slack'
s26_says 'requires              Gmail, Google_Calendar, Notion, Slack' show mail || s26_bad+="show does not print requires"$'\n'
s26_out="$(s26_x doctor mail 2>&1)"
[[ "$s26_out" == *"connector Gmail: claude.ai Gmail, connected"* && "$s26_out" == *"connector Google_Calendar: claude.ai Google Calendar, connected"* \
   && "$s26_out" == *"connector Notion: plugin:tools:notion, ! Needs authentication"* && "$s26_out" == *"connector Slack: not found in claude mcp list here"* \
   && "$s26_out" == *"2 problem(s)."* ]] || s26_bad+="doctor said: $s26_out"$'\n'
empty "26 requires: show prints it; doctor <name> reads claude mcp list in the task's folder and reports each connector connected, needing auth or missing" "$s26_bad"

# The session-start hook: inside a kit workspace, one line for what needs the person; silent otherwise.
s26_hook="$KIT/plugins/scheduler/hooks/session-start.sh"
s26_ws="$s26/hookws"; mkdir -p "$s26_ws/.claude" "$s26_ws/sub" "$s26/outside"; : >"$s26_ws/.claude/kit-templates.lock"
s26_h() { jq -nc --arg c "$1" '{cwd: $c, source: "startup"}' | env SCHEDULER_HOME="$s26/cfg" SCHEDULER_DATA="$s26/data" "${@:2}" "$st_bash" "$s26_hook" 2>&1; }
s26_bad=""
rm -f "$s26/data/state/session-seen"
s26_mode fail; s26_mk broken2 '0 7 * * *' --retries 0 --pause-after-failures 1; s26_run broken2
s26_o="$(s26_h "$s26_ws/sub" | jq -r '.systemMessage')"
[[ "$s26_o" == "Scheduler: "*"broken2"*"failed since the last session"*"paused itself after failing (schedule.sh show broken2)"*"shortlist"*"waiting"* ]] \
    && [[ "$s26_o" == *"stale"* ]] && s26_bad+="an expired run is reported as waiting"$'\n'
[[ "$s26_o" == "Scheduler: "*"broken2"*"failed since the last session"*"paused itself"* ]] || s26_bad+="first session: $s26_o"$'\n'
s26_mk asks '0 7 * * *' --awaits-reply true; s26_mode ok; s26_run asks
s26_o="$(s26_h "$s26_ws" | jq -r '.systemMessage')"
[[ "$s26_o" == "Scheduler: asks awaiting an answer (open it: cd '"*"' && claude --desktop --resume "*"; or schedule.sh reply asks '<your reply>')." ]] || s26_bad+="second session, failures already seen: $s26_o"$'\n'
# A resume of the waiting run's own session gets no line about itself: the person is in it.
s26_sid="$(s26_meta asks session_id)"
s26_o="$(jq -nc --arg c "$s26_ws" --arg s "$s26_sid" '{cwd: $c, source: "resume", session_id: $s}' \
    | env SCHEDULER_HOME="$s26/cfg" SCHEDULER_DATA="$s26/data" "$st_bash" "$s26_hook" 2>&1)"
[[ -z "$s26_o" ]] || s26_bad+="a resume of the waiting run's own session got a line about itself: $s26_o"$'\n'
s26_h "$s26_ws" | jq -e '.hookSpecificOutput.additionalContext | contains("scripts/schedule.sh")' >/dev/null || s26_bad+="the agent's context does not name the script"$'\n'
[[ -z "$(s26_h "$s26/outside")" ]] || s26_bad+="spoke outside a kit workspace"$'\n'
[[ -z "$(s26_h "$s26_ws" AW_HEADLESS_RUN=1)" ]] || s26_bad+="spoke in a headless run"$'\n'
s26_x reply asks 'fine' >/dev/null 2>&1
[[ -z "$(s26_h "$s26_ws")" ]] || s26_bad+="spoke with nothing to say: $(s26_h "$s26_ws")"$'\n'
s26_t0="$(python3 -c 'import time; print(int(time.time()*1000))')"
for s26_i in 1 2 3 4 5; do s26_h "$s26_ws" >/dev/null; done
s26_ms=$(( ($(python3 -c 'import time; print(int(time.time()*1000))') - s26_t0) / 5 ))
(( s26_ms < 100 )) || s26_bad+="took ${s26_ms} ms a run"$'\n'
empty "26 hook: failures and self-pauses since the last session, and runs waiting, in one line; silent outside a workspace, headless or with nothing to say; ${s26_ms} ms" "$s26_bad"

# --- port: moving tasks from a cloud scheduler, one deterministic step at a time ------------------------
s26_reset
s26_backend=none
s26_mode ok
s26_pex="$s26/export.json"
mkdir -p "$s26/fakehome/workspace/notes"
cat >"$s26_pex" <<'EXPORT'
[
 {"id": "t-111", "name": "Morning notes digest", "cron_expression": "30 7 * * 1-5", "model": "", "enabled": true,
  "mcp_connections": [{"name": "Gmail"}, {"name": "Google_Calendar"}, {"name": "Claude_Code_Remote"}],
  "derived_state": {"prompt": "Read the notes in $HOME/mnt/workspace/notes, and the gmail threads about them.\nSummarise them.\nPost the summary into this conversation.",
                    "folders": ["$HOME/mnt/workspace"], "permission_mode": "dontAsk"}},
 {"id": "t-222", "name": "Weekly cleanup", "cron_expression": "0 18 * * 5", "model": "sonnet", "enabled": false, "labels": ["x"],
  "derived_state": {"prompt": "Use device_bash to run the cleanup script.\nThen wait for my reply before deleting anything.",
                    "folders": [], "permission_mode": "bypassPermissions"}}
]
EXPORT
s26_p() { s26_x port "$@" 2>&1; }
s26_stage() { jq -r --arg n "$1" '.tasks[$n].stage' "$s26/data/port/current.json"; }
s26_bad=""
s26_out="$(s26_p start "$s26_pex" --path-map "\$HOME/mnt/workspace=$s26/fakehome/workspace" --cwd "$s26/work")"
[[ "$s26_out" == *"Importing 2 task(s)"*"morning-notes-digest: schedule 30 7 * * 1-5; prompt 3 line(s); cwd $s26/fakehome/workspace; model default; requires Gmail; 2 path substitution(s)"* ]] \
    || s26_bad+="the import report for the first task: $s26_out"$'\n'
[[ "$s26_out" == *"weekly-cleanup: schedule 0 18 * * 5; prompt 2 line(s); cwd $s26/work; model sonnet; disabled in the source; not mapped: labels"* ]] \
    || s26_bad+="the import report for the second task"$'\n'
grep -q '^status: paused$' "$s26/cfg/tasks/morning-notes-digest.md" && grep -q '^paused_reason: imported; review before resuming$' "$s26/cfg/tasks/morning-notes-digest.md" \
    || s26_bad+="an imported task is not paused for review"$'\n'
grep -qF "Read the notes in $s26/fakehome/workspace/notes, and" "$s26/cfg/tasks/morning-notes-digest.md" || s26_bad+="the path map did not reach the prompt"$'\n'
# Connectors: the one the prompt names is carried; one only attached is reported and left out; the
# cloud scheduler's own is left out and never blocks.
grep -qx 'requires: Gmail' "$s26/cfg/tasks/morning-notes-digest.md" || s26_bad+="requires is not just the named connector: $(grep '^requires' "$s26/cfg/tasks/morning-notes-digest.md")"$'\n'
[[ "$s26_out" == *"attached in the cloud, not named in the prompt; left out: Google_Calendar"* && "$s26_out" == *"the cloud scheduler's own connector, left out: Claude_Code_Remote"* ]] \
    || s26_bad+="the left-out connectors are not reported"$'\n'
[[ "$s26_out" != *"connector:Claude_Code_Remote"* && "$s26_out" != *"connector:Google_Calendar"* ]] || s26_bad+="a left-out connector was checked"$'\n'
[[ "$(jq -r '.tasks["morning-notes-digest"].substitutions | map(.where) | join(",")' "$s26/data/port/current.json")" == prompt,folder ]] || s26_bad+="substitutions not recorded"$'\n'
[[ "$(s26_stage morning-notes-digest)/$(s26_stage weekly-cleanup)" == checked/imported ]] || s26_bad+="stages after start: $(s26_stage morning-notes-digest)/$(s26_stage weekly-cleanup)"$'\n'
[[ "$s26_out" == *"[block] permission-mode"*"bypassPermissions"* && "$s26_out" == *"[block] bridge-shell:1 (prompt line 1)"* && "$s26_out" == *"[set] awaits-reply:2"* ]] \
    || s26_bad+="the second task's findings"$'\n'
grep -q '^awaits_reply: true$' "$s26/cfg/tasks/weekly-cleanup.md" || s26_bad+="the set rule did not write awaits_reply"$'\n'
empty "26 port start: the listing shape's fields mapped, only the connectors the prompt names carried (the rest and the cloud's own reported), slugged names, paused for review, the path map applied and recorded, each task checked, a report per task" "$s26_bad"

s26_bad=""
[[ "$(s26_p trial weekly-cleanup)" == *"port trial comes after port check"* ]] || s26_bad+="trial before check was not refused"$'\n'
[[ "$(s26_p activate morning-notes-digest)" == *"port activate comes after port trial"* ]] || s26_bad+="activate before trial was not refused"$'\n'
[[ "$(s26_p cloud-paused morning-notes-digest --confirmed)" == *"port cloud-paused comes after port activate"* ]] || s26_bad+="cloud-paused before activate was not refused"$'\n'
[[ "$(s26_p "done")" == *"still open: "* ]] || s26_bad+="done with tasks open was not refused"$'\n'
[[ "$(s26_p ack weekly-cleanup bridge-shell:1)" == *"a block is fixed in the task file"* ]] || s26_bad+="a block was acknowledged"$'\n'
[[ "$(s26_p ack morning-notes-digest post-conversation:3 --note 'result_to set')" == "Acknowledged post-conversation:3 on morning-notes-digest: result_to set." ]] || s26_bad+="ack of a warn"$'\n'
[[ "$(jq -r '.tasks["morning-notes-digest"].acks["post-conversation:3"].note' "$s26/data/port/current.json")" == "result_to set" ]] || s26_bad+="the ack is not in the ledger"$'\n'
s26_out="$(s26_p check morning-notes-digest)"
[[ "$s26_out" == *"1 acknowledged"* ]] || s26_bad+="a re-check loses the ack: $s26_out"$'\n'
empty "26 port: each stage refuses to run before the one it follows, a block cannot be acknowledged, a warn can and stays acknowledged across checks" "$s26_bad"

s26_bad=""
# The judgement step: the second task is fixed in its file, and check moves it on.
sed 's/^permission_mode: bypassPermissions$/permission_mode: dontAsk/; s/^Use device_bash to run the cleanup script\.$/Run the cleanup script with Bash./' \
    "$s26/cfg/tasks/weekly-cleanup.md" >"$s26/fixed.md" && mv "$s26/fixed.md" "$s26/cfg/tasks/weekly-cleanup.md"
s26_out="$(s26_p check weekly-cleanup)"
[[ "$s26_out" == "weekly-cleanup: checked — 0 block"* ]] || s26_bad+="after the fix: $s26_out"$'\n'
# --plan is a look: plan mode, which ignores the task's allowed tools, so the stage stays where it was.
s26_out="$(s26_p trial morning-notes-digest --plan)"
[[ "$s26_out" == *"Plan-mode look at morning-notes-digest: it ran cleanly."*"tests nothing about them, and morning-notes-digest stays at checked"* && "$(s26_stage morning-notes-digest)" == checked ]] \
    || s26_bad+="a plan look: $s26_out"$'\n'
[[ "$(grep -A1 -x -- '--permission-mode' "$s26/bin/last-args" | tail -n 1)" == plan && "$(grep -cx -- '--permission-mode' "$s26/bin/last-args")" == 1 ]] \
    || s26_bad+="the look was not one --permission-mode plan"$'\n'
# The trial proper is a real run with the task's own settings, and asks for a yes.
[[ "$(s26_p trial morning-notes-digest)" == *"give --yes once the person has said yes"* ]] || s26_bad+="a trial ran without --yes"$'\n'
s26_x edit morning-notes-digest --allowed-tools 'Read Grep' >/dev/null 2>&1
s26_out="$(s26_p trial morning-notes-digest --yes)"
[[ "$s26_out" == *"Trial of morning-notes-digest with its own settings (permission_mode dontAsk, its allowed tools); result_to and notify held back: passed."* \
   && "$(s26_stage morning-notes-digest)" == trialled ]] || s26_bad+="the trial: $s26_out"$'\n'
[[ "$(grep -A1 -x -- '--permission-mode' "$s26/bin/last-args" | tail -n 1)" == dontAsk && "$(grep -A1 -x -- '--allowedTools' "$s26/bin/last-args" | tail -n 1)" == "Read Grep" ]] \
    || s26_bad+="the trial did not pass the task's own --permission-mode and --allowedTools: $(paste -sd'|' - <"$s26/bin/last-args")"$'\n'
[[ "$(s26_meta morning-notes-digest trigger)" == trial-live ]] || s26_bad+="trigger $(s26_meta morning-notes-digest trigger)"$'\n'
grep -q '^status: paused$' "$s26/cfg/tasks/morning-notes-digest.md" || s26_bad+="a trial changed the task's status"$'\n'
cp "$s26/bin/claude" "$s26/bin/claude-ok"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' \
    "echo '{\"type\":\"result\",\"is_error\":false,\"result\":\"The tool mcp__claude_ai_Slack__post is not available in this session.\",\"total_cost_usd\":0.001}'" \
    >"$s26/bin/claude"
s26_out="$(s26_p trial weekly-cleanup --yes)"
cp "$s26/bin/claude-ok" "$s26/bin/claude"
[[ "$s26_out" == *"failed"*"tool-unavailable: The tool mcp__claude_ai_Slack__post is not available"* && "$(s26_stage weekly-cleanup)" == checked ]] \
    || s26_bad+="a tool-unavailable trial: $s26_out"$'\n'
empty "26 port trial: a real run with the task's own permission mode and allowed tools, on a yes, moves it on; --plan is a look that does not; a tool-unavailable line fails it" "$s26_bad"

s26_bad=""
s26_out="$(s26_p activate morning-notes-digest)"
[[ "$s26_out" == *"runs twice until that one is disabled"* && "$(s26_stage morning-notes-digest)" == double-run ]] || s26_bad+="activate: $s26_out"$'\n'
grep -q '^status: active$' "$s26/cfg/tasks/morning-notes-digest.md" && [[ -f "$s26/data/units/morning-notes-digest.cron" ]] || s26_bad+="activate did not resume it"$'\n'
[[ "$(s26_p status | sed -n 3p)" == morning-notes-digest*double-run* ]] || s26_bad+="status does not put the double-run row first: $(s26_p status)"$'\n'
[[ "$(s26_p activate morning-notes-digest)" == *"already active here"* ]] || s26_bad+="a second activate is not safe"$'\n'
[[ "$(s26_p cloud-paused morning-notes-digest)" == *"give --confirmed"* ]] || s26_bad+="cloud-paused without --confirmed"$'\n'
# The way back: rollback pauses the local task and returns the row to trialled; activate again goes on.
s26_out="$(s26_p rollback morning-notes-digest)"
[[ "$s26_out" == *"back at trialled. Re-enable its cloud task, which was paused, not deleted."* && "$(s26_stage morning-notes-digest)" == trialled ]] || s26_bad+="rollback: $s26_out"$'\n'
grep -q '^status: paused$' "$s26/cfg/tasks/morning-notes-digest.md" && grep -q '^paused_reason: rolled back to its cloud task on ' "$s26/cfg/tasks/morning-notes-digest.md" \
    || s26_bad+="rollback did not leave the local task paused with a reason"$'\n'
[[ ! -f "$s26/data/units/morning-notes-digest.cron" ]] || s26_bad+="rollback left the unit"$'\n'
s26_p activate morning-notes-digest >/dev/null
s26_p cloud-paused morning-notes-digest --confirmed >/dev/null
s26_p skip weekly-cleanup --reason 'rewriting it' >/dev/null
s26_x port status --json | jq -e '.tasks | map(.name + ":" + .stage) | sort == ["morning-notes-digest:cloud-paused", "weekly-cleanup:skipped"]' >/dev/null \
    || s26_bad+="status --json: $(s26_x port status --json)"$'\n'
s26_out="$(s26_p start "$s26_pex")"
[[ "$s26_out" == *"morning-notes-digest: already in this port, at cloud-paused; left as it is"* && ! -e "$s26/cfg/tasks/morning-notes-digest-2.md" ]] || s26_bad+="a second start duplicated: $s26_out"$'\n'
s26_out="$(s26_p "done")"
[[ "$s26_out" == "Port closed: 1 task(s) moved and running here alone, 1 skipped."*"paused in the cloud scheduler, not deleted"*"morning-notes-digest: Morning notes digest (t-111)"* && ! -f "$s26/data/port/current.json" && -n "$(ls "$s26/data/port"/done-*.json 2>/dev/null)" ]] \
    || s26_bad+="done: $s26_out"$'\n'
empty "26 port activate, cloud-paused, rollback and done: double-run listed first until cloud-paused --confirmed, rollback back to trialled with the local task paused, skip with a reason, a second start adds nothing, done closes the ledger" "$s26_bad"

# The plain export shape: name, schedule, prompt, cwd, add_dirs.
s26_bad=""
printf '%s\n' "[{\"name\": \"Plain one\", \"schedule\": \"@daily\", \"prompt\": \"Say OK.\", \"cwd\": \"$s26/work\", \"add_dirs\": [\"$s26/fakehome\"], \"permission_mode\": \"dontAsk\"},
 {\"name\": \"A rather long task name for the status table\", \"schedule\": \"@daily\", \"prompt\": \"Say OK.\", \"cwd\": \"$s26/work\", \"permission_mode\": \"dontAsk\"}]" >"$s26/plain.json"
s26_out="$(s26_p start "$s26/plain.json")"
[[ "$s26_out" == *"plain-one: schedule @daily; prompt 1 line(s); cwd $s26/work; model default"* ]] || s26_bad+="plain: $s26_out"$'\n'
grep -qx "add_dirs: $s26/fakehome" "$s26/cfg/tasks/plain-one.md" || s26_bad+="add_dirs not mapped"$'\n'
# A long name sets the width of the status table's first column, so STAGE stays a column.
s26_out="$(s26_p status)"
grep -qE '^a-rather-long-task-name-for-the-status-table  (imported|checked) ' <<<"$s26_out" && grep -qE '^plain-one {37}(imported|checked) ' <<<"$s26_out" \
    || s26_bad+="the status table's columns: $s26_out"$'\n'
empty "26 port start reads the plain shape too: name, schedule, prompt, cwd and add_dirs; the status table sizes its name column to the longest name" "$s26_bad"

# A real folder can look like a sandbox mount (a home under /sessions/, say): a mounted-path match whose
# path exists here is not a finding; one that does not exist still blocks.
s26_bad=""
mkdir -p "$s26/9/sessions/notes"; : >"$s26/9/sessions/notes/today.md"
printf '%s\n' "[{\"name\": \"Real sessions path\", \"schedule\": \"@daily\", \"cwd\": \"$s26/work\", \"permission_mode\": \"dontAsk\",
  \"prompt\": \"Read $s26/9/sessions/notes/today.md and count its lines.\"},
 {\"name\": \"Sandbox sessions path\", \"schedule\": \"@daily\", \"cwd\": \"$s26/work\", \"permission_mode\": \"dontAsk\",
  \"prompt\": \"Read /sessions/abc123/notes/today.md and count its lines.\"}]" >"$s26/mounts.json"
s26_out="$(s26_p start "$s26/mounts.json")"
[[ "$s26_out" == *"real-sessions-path: checked — 0 block"* ]] || s26_bad+="an existing path that matches the rule was blocked: $s26_out"$'\n'
[[ "$s26_out" == *"sandbox-sessions-path: imported — 1 block"*"[block] mounted-path:1"* ]] || s26_bad+="a sandbox path that does not exist was not blocked"$'\n'
empty "26 port check: a mounted-path match that exists on this machine is not a finding; one that does not exist blocks" "$s26_bad"

# The rules table, line by line: a prompt line each rule matches, and one it does not.
s26_bad=""
s26_rules="$KIT/plugins/scheduler/port-rules.tsv"
s26_rule() { awk -F'\t' -v id="$1" '$1 == id { print $3 }' "$s26_rules"; }
s26_corpus='bridge-shell	Run it through device_bash on the laptop.	Run it with Bash on this machine.
bridge-shell	Call mcp__workspace__bash with the command.	Call mcp__workspace__bashful_reader.
osascript-bridge	tell application "Terminal" to do shell script "ls"	Write a shell script that does the listing.
mounted-path	Save it under $HOME/mnt/outputs/report.md	Save it under $HOME/notes/report.md
mounted-path	Read /sessions/abc/files/data.csv	Read the sessions/ folder in the repository.
mounted-path	Put the file in the outputs dir.	Put the file in the outputs.md list.
credential	curl -H "Authorization: Bearer abcdefghijklmnopqrstu" https://example.invalid	Read the token from ~/.config/survey/token.txt and pass it in the header.
credential	api_key: sk-proj-1234567890abcdef	api_key: read it from the file named in KEY_FILE
mount-placeholder	reachable in the sandbox at `<mnt>/assessments/instruments/`	compare a <b> with <c> in the html.
mount-placeholder	Save it in <the outputs dir for this run>.	Save it in the outputs folder for this run.
system-prompt-path	(your system prompt gives the mount path for the files)	your system prompt gives the date of the run
cloud-session	Include $CLAUDE_CODE_REMOTE_SESSION_ID in the footer.	Include the session date in the footer.
cloud-session	Link https://claude.ai/code/session/123 in the note.	Link https://claude.ai/download in the note.
sandbox-install	pip install pandas --break-system-packages	pip install pandas inside the project venv.
sandbox-install	npm install -g prettier	npm install prettier --save-dev
toolsearch	ToolSearch query select:mcp__gmail__search	Search the tools list for gmail.
browser-tools	Use mcp__claude-in-chrome__navigate to open the page.	Open the page in Chrome yourself later.
awaits-reply	Wait for my reply before sending.	Send it straight away.
awaits-reply	Reply in this session with the shortlist.	Reply to the email with the shortlist.
post-conversation	Post the summary into this conversation.	Post the summary to the team channel.
sandbox-network	urllib3: Tunnel connection failed: 403 user denied	The tunnel opened and the request returned 200.
tool-unavailable	The tool mcp__slack__post is not available.	The tool worked and the post is available.
tool-unavailable	Permission to use Bash was denied.	Permission was granted for Bash.'
while IFS='	' read -r s26_id s26_hit s26_miss; do
    [[ -n "$s26_id" ]] || continue
    s26_re="$(s26_rule "$s26_id")"
    [[ -n "$s26_re" ]] || { s26_bad+="no rule $s26_id"$'\n'; continue; }
    printf '%s\n' "$s26_hit" | grep -qiE -- "$s26_re" || s26_bad+="$s26_id misses: $s26_hit"$'\n'
    printf '%s\n' "$s26_miss" | grep -qiE -- "$s26_re" && s26_bad+="$s26_id matches the near miss: $s26_miss"$'\n'
done <<<"$s26_corpus"
s26_nrules=0
while IFS= read -r s26_r; do
    s26_nrules=$((s26_nrules + 1))
    grep -q "^$s26_r	" <<<"$s26_corpus" || s26_bad+="rule $s26_r has no corpus line"$'\n'
done < <(awk -F'\t' '!/^#/ && $1 != "id" { print $1 }' "$s26_rules")
awk -F'\t' '!/^#/ && NF != 5 { print "line " NR " has " NF " fields" }' "$s26_rules" | grep -q . && s26_bad+="a rules line is not five fields"$'\n'
empty "26 port-rules.tsv: each of its $s26_nrules rules matches its corpus line and not its near miss, five fields a line" "$s26_bad"

# --- What the live Mac run found ----------------------------------------------------------------------
s26_reset
s26_backend=none
s26_bad=""
s26_mode denied
s26_mk refused '0 7 * * *' --retries 0 --pause-after-failures 2
s26_run refused
[[ "$(s26_meta refused status)" == denied && "$(s26_meta refused reason)" == "refused: Bash: date > out.txt" ]] || s26_bad+="meta: $(cat "$(s26_last refused)meta")"$'\n'
[[ "$(cat "$s26/data/state/refused.failures")" == 1 ]] || s26_bad+="a denied run did not count as a failure"$'\n'
s26_says 'denied: refused: Bash: date > out.txt' runs refused || s26_bad+="runs: $(s26_x runs refused)"$'\n'
s26_run refused
grep -q '^paused_reason: paused itself after 2 failed runs in a row' "$s26/cfg/tasks/refused.md" || s26_bad+="two denied runs did not pause it"$'\n'
s26_mode ok
empty "26 a run that ended well while a tool it reached for was refused is recorded denied, with the refused call, and counts toward pausing" "$s26_bad"

# The line: a refusal the run carried on from (another tool call after it went through) leaves it ok,
# counted and named; one it stopped at is denied, a failure.
s26_bad=""
s26_mode recovered
s26_mk carried '0 7 * * *' --retries 0
s26_exec '' carried    # a scheduled run, which is what report counts
[[ "$(s26_meta carried status)" == ok && "$(s26_meta carried refusals)" == 1 && "$(s26_meta carried refused_calls)" == "Bash: fetch.sh; echo done; ls" ]] \
    || s26_bad+="meta: $(cat "$(s26_last carried)meta")"$'\n'
[[ "$(cat "$s26/data/state/carried.failures")" == 0 ]] || s26_bad+="a recovered refusal counted as a failure"$'\n'
s26_says 'ok (1 refused)' runs carried && s26_says 'ok (1 refused)' show carried || s26_bad+="runs or show does not say ok (1 refused)"$'\n'
s26_says 'refused, and the run carried on (1): Bash: fetch.sh; echo done; ls' log carried || s26_bad+="log does not name the refused call"$'\n'
[[ "$(s26_x report --json | jq -r '.tasks[] | select(.task == "carried") | .with_refusal')" == 1 ]] || s26_bad+="report does not count the run with a refusal"$'\n'
s26_says '1 of 1 runs carried on past a refused tool call' report || s26_bad+="report's totals do not say so"$'\n'
s26_mode ok
empty "26 a refusal the run carried on from leaves it ok (1 refused), named in log and counted in report; one it stopped at is denied" "$s26_bad"

s26_bad=""
s26_now='2026-10-29 10:00' s26_mk later 'once 2099-01-01 09:00'
s26_x run later --wait >/dev/null 2>&1
grep -q '^status: active$' "$s26/cfg/tasks/later.md" && [[ -f "$s26/data/units/later.cron" ]] || s26_bad+="a manual run used up the once task"$'\n'
grep -q '^reply_window' <<<"$(s26_x show later)" && s26_bad+="show lists reply_window on a task that does not wait for replies"$'\n'
s26_mk once1 'every 5m' --retries 0 --pause-after-failures 1
mv "$s26/work" "$s26/work.away"; s26_exec '' once1; mv "$s26/work.away" "$s26/work"
grep -q 'after 1 failed run in a row' "$s26/cfg/tasks/once1.md" || s26_bad+="the reason does not read 1 failed run"$'\n'
empty "26 a manual run leaves a once task active; show leaves reply_window out unless the task waits for replies; one failure reads as one run" "$s26_bad"

# On launchd a run that pauses its own task is stopped by its bootout; the plist goes first, so none is left.
s26_reset
s26_backend=launchd
s26_bad=""
mkdir -p "$s26/gone"
s26_mk selfstop 'every 5m' --cwd "$s26/gone" --retries 0 --pause-after-failures 1
rmdir "$s26/gone"
grep -q '^SCHEDULER_LAUNCHCTL=' "$s26/data/env" || s26_bad+="the env file does not record the launchctl override for the runner"$'\n'
: >"$s26/bin/kill-on-bootout"
s26_exec '' selfstop
rm -f "$s26/bin/kill-on-bootout"
grep -q '^status: paused$' "$s26/cfg/tasks/selfstop.md" || s26_bad+="not paused"$'\n'
[[ ! -e "$s26/LaunchAgents/agentic-workspace.scheduler.selfstop.plist" ]] || s26_bad+="the plist was left behind"$'\n'
grep -qx agentic-workspace.scheduler.selfstop "$s26/bin/loaded" && s26_bad+="still loaded"$'\n'
grep -q '^bootout gui/501/agentic-workspace.scheduler.selfstop$' "$s26/bin/launchctl.log" || s26_bad+="the runner did not use the stub launchctl"$'\n'
s26_backend=none
empty "26 launchd: a run that pauses its own task removes the plist before the bootout that stops it, through the launchctl sync recorded" "$s26_bad"

# --- report: a fixture week with a miss, a late run and a pause in the middle ------------------------------
s26_reset
s26_backend=none
mkdir -p "$s26/cfg/tasks" "$s26/data/state"
# daily at 09:00, active from 16 October, paused 19 October 12:00 to 20 October 12:00 (so the 20th's fire
# is not due); runs on the 16th, the 17th two hours late, the 19th, the 21st (failed) and the 22nd, none on
# the 18th, and one by hand. hourly: every 1h, active ten hours on the 16th, eight runs.
python3 - "$s26" <<'PY'
import datetime, os, sys, time
s26 = sys.argv[1]
def ep(s): return int(time.mktime(datetime.datetime.strptime(s, "%Y-%m-%d %H:%M").timetuple()))
open(f"{s26}/data/state/daily.events", "w").write(
    f"{ep('2026-10-16 00:00')}\tactive\t0 9 * * *\n{ep('2026-10-19 12:00')}\tpaused\t0 9 * * *\n{ep('2026-10-20 12:00')}\tactive\t0 9 * * *\n")
open(f"{s26}/data/state/hourly.events", "w").write(
    f"{ep('2026-10-16 08:00')}\tactive\tevery 1h\n{ep('2026-10-16 18:00')}\tdeleted\tevery 1h\n")
# edge: created at 08:59:30 and paused at 10:00:20, so the 09:00 and 10:00 fires were due and 08:59 was not.
open(f"{s26}/data/state/edge.events", "w").write(f"{ep('2026-10-16 08:59')+30}\tactive\t* * * * *\n{ep('2026-10-16 10:00')+20}\tpaused\t* * * * *\n")
def run(task, start, due, status, trig="schedule"):
    rid = start.replace("-", "").replace(" ", "-").replace(":", "") + "05"
    d = f"{s26}/data/runs/{task}/{rid}"; os.makedirs(d, exist_ok=True)
    m = f"task={task}\nrun={rid}\ntrigger={trig}\nstart={start}:05\nstart_epoch={ep(start)+5}\nend={start}:40\nend_epoch={ep(start)+40}\nstatus={status}\nattempts=1\n"
    if due: m += f"due={due}\ndue_epoch={ep(due)}\n"
    open(f"{d}/meta", "w").write(m)
for st, due, status in [("2026-10-16 09:00", "2026-10-16 09:00", "ok"), ("2026-10-17 11:00", "2026-10-17 09:00", "ok"),
                        ("2026-10-19 09:00", "2026-10-19 09:00", "ok"), ("2026-10-21 09:00", "2026-10-21 09:00", "failed"),
                        ("2026-10-22 09:00", "2026-10-22 09:00", "ok")]:
    run("daily", st, due, status)
run("daily", "2026-10-22 15:00", "", "ok", "manual")
for h in range(9, 17):
    run("hourly", f"2026-10-16 {h:02d}:00", "", "ok")
# pinned: every minute from 11:50:20, read with the clock pinned at 12:00; runs from 11:51 to 11:57 and at
# 12:00, none at 11:58 or 11:59, which are inside the last five minutes and so pending, not missed.
open(f"{s26}/data/state/pinned.events", "w").write(f"{ep('2026-10-16 11:50')+20}\tactive\t* * * * *\n{ep('2026-10-16 12:01')}\tpaused\t* * * * *\n")
for m in list(range(51, 58)) + [60]:
    hh, mm = (12, 0) if m == 60 else (11, m)
    run("pinned", f"2026-10-16 {hh:02d}:{mm:02d}", f"2026-10-16 {hh:02d}:{mm:02d}", "ok")
PY
printf -- '---\nname: daily\nschedule: 0 9 * * *\nstatus: active\ncwd: %s\ncreated: 2026-10-15 12:00\n---\n\nSay OK.\n' "$s26/work" >"$s26/cfg/tasks/daily.md"
s26_bad=""
s26_out="$(s26_x report --since '2026-10-16 00:00' --until '2026-10-23 00:00')"
[[ "$s26_out" == *"Totals: 21 of 87 due fires ran; ok 20 of 21 runs; failed 1 of 21 runs; late 1 of 21 runs (at most 2h00m); 1 run(s) by hand, not counted against the schedule; 2026-10-16 00:00 to 2026-10-23 00:00."* ]] \
    || s26_bad+="the totals line: $s26_out"$'\n'
[[ "$s26_out" == *"daily                    due 2026-10-18 09:00"* && "$s26_out" != *"due 2026-10-20 09:00"* ]] || s26_bad+="the miss is not named, or the paused day counts"$'\n'
[[ "$s26_out" == *"hourly                   2 fewer runs than its interval gives"* ]] || s26_bad+="the every task's shortfall"$'\n'
s26_j="$(s26_x report --since '2026-10-16 00:00' --until '2026-10-23 00:00' --json)"
jq -e '(.tasks[] | select(.task == "daily")) as $d | $d.due == 6 and $d.ran == 5 and $d.ok == 4 and $d.failed == 1 and $d.late == 1 and $d.max_late_secs == 7205 and $d.missed == 1 and $d.manual == 1
       and .totals.due_ran == 21 and .totals.due == 87 and .window.since == "2026-10-16 00:00" and (.missed | map(.due // "") | index("2026-10-18 09:00")) != null' <<<"$s26_j" >/dev/null \
    || s26_bad+="report --json: $s26_j"$'\n'
s26_out="$(s26_x report --since '2026-10-20 00:00' --until '2026-10-20 23:00')"
[[ "$s26_out" == *"Totals: 0 of 0 due fires ran; ok 0 of 0 runs"* ]] || s26_bad+="a window inside the pause has fires due: $s26_out"$'\n'
[[ "$(jq -r '.tasks[] | select(.task == "edge") | .due' <<<"$s26_j")" == 61 ]] || s26_bad+="the edges of an active period: $(jq -c '.tasks[] | select(.task == "edge")' <<<"$s26_j")"$'\n'
# The clock pinned at 12:00 (SCHEDULER_NOW), the window capped at it: the run of the current minute
# counts, and the two unrun fires inside the last five minutes are pending, not missed. No part of this
# reads the wall clock.
s26_j="$(s26_now='2026-10-16 12:00' s26_x report --since '2026-10-16 11:50' --json)"
[[ "$(jq -r '(.tasks[] | select(.task == "pinned") | "\(.due) \(.ran) \(.missed)") + " " + (.totals.pending | tostring)' <<<"$s26_j")" == "8 8 0 2" ]] \
    || s26_bad+="the pinned clock: $(jq -c '[.tasks[] | select(.task == "pinned"), .totals]' <<<"$s26_j")"$'\n'
empty "26 report: a fixture week with a pause, a miss, a late run, a failure, a manual run and an every task, each figure out of its whole and with its window" "$s26_bad"

# A cloud task that moved is paused, never deleted: nothing in port, the command or the docs deletes one.
s26_bad=""
grep -n -i -E 'delete[a-z_]*(_| )(scheduled_?task|cloud)|(remove|delete) (the|its|their) cloud' \
    "$KIT/plugins/scheduler/scripts/lib/port.sh" "$KIT/plugins/scheduler/commands/tasks.md" "$KIT/plugins/scheduler/README.md" "$KIT/docs/commands/scheduler-tasks.md" \
    | grep -v -i -E 'never|not |nothing|no step' | grep -q . && s26_bad+="a line that deletes a cloud task: $(grep -n -i -E 'delete[a-z_]*(_| )(scheduled_?task|cloud)|(remove|delete) (the|its|their) cloud' "$KIT/plugins/scheduler/commands/tasks.md")"$'\n'
s26_cmd="$(tr '\n' ' ' <"$KIT/plugins/scheduler/commands/tasks.md" | tr -s ' ')"
[[ "$s26_cmd" == *"paused, never deleted"* && "$s26_cmd" == *"no step of this calls a tool that deletes a cloud task"* && "$s26_cmd" == *"port rollback"* ]] \
    || s26_bad+="the command does not say the cloud task is paused, never deleted, with the way back"$'\n'
grep -q -i 'delete' "$KIT/plugins/scheduler/scripts/lib/port.sh" && [[ "$(grep -i 'delete' "$KIT/plugins/scheduler/scripts/lib/port.sh" | grep -v -i -c 'never\|not \|nothing')" != 0 ]] && s26_bad+="port.sh has a delete that is not a negation"$'\n'
empty "26 port: a moved cloud task is paused, never deleted; the command says so and gives the way back, and no line deletes one" "$s26_bad"

# With none of the OS-tool overrides set, as on a person's machine, create still writes the env file
# the runner starts from, with claude's path in it; without it, doctor says so.
s26_bad=""
s26_plain="$s26/plain-env"; rm -rf "$s26_plain"
s26_out="$(env -u SCHEDULER_UID -u SCHEDULER_LAUNCHCTL -u SCHEDULER_SYSTEMCTL -u SCHEDULER_CRONTAB -u SCHEDULER_LAUNCH_AGENTS -u SCHEDULER_SYSTEMD_DIR \
    SCHEDULER_HOME="$s26_plain/cfg" SCHEDULER_DATA="$s26_plain/data" SCHEDULER_BACKEND=none SCHEDULER_CLAUDE="$s26/bin/claude" \
    "$st_bash" "$s26_sh" create bare --schedule '0 7 * * *' --cwd "$s26/work" --prompt 'Say OK.' 2>&1)"
[[ -f "$s26_plain/data/env" && ! -e "$(ls "$s26_plain/data"/env.tmp.* 2>/dev/null | head -n 1)" ]] || s26_bad+="no env file: $s26_out; $(ls "$s26_plain/data")"$'\n'
grep -q "^CLAUDE_BIN=.*bin/claude$" "$s26_plain/data/env" 2>/dev/null || s26_bad+="the env file has no claude path"$'\n'
rm -f "$s26_plain/data/env"
[[ "$(SCHEDULER_HOME="$s26_plain/cfg" SCHEDULER_DATA="$s26_plain/data" SCHEDULER_BACKEND=none "$st_bash" "$s26_sh" doctor 2>&1)" == *"env is missing"* ]] || s26_bad+="doctor does not report a missing env file"$'\n'
empty "26 with no OS-tool overrides set, create writes the runner's env file with claude's path; doctor reports one that is missing" "$s26_bad"

# --- Billed to the person's login, never an API key ----------------------------------------------------
s26_reset
s26_backend=none
s26_bad=""
s26_mode ok
ANTHROPIC_API_KEY=sk-test-not-a-key s26_mk paid '0 7 * * *' --retries 0 --pause-after-failures 2
grep -q 'ANTHROPIC\|CLAUDE_CODE_USE' "$s26/data/env" && s26_bad+="the env file holds an API credential"$'\n'
grep -qx "CLAUDE_CONFIG_DIR=$s26/ccfg" "$s26/data/env" || s26_bad+="the env file does not record the config folder runs read"$'\n'
ANTHROPIC_API_KEY=sk-test-not-a-key s26_run paid
grep -q '^ANTHROPIC_API_KEY=' "$s26/bin/last-env" && s26_bad+="an API key in the calling shell reached claude"$'\n'
printf 'ANTHROPIC_API_KEY=%s\nCLAUDE_CODE_USE_BEDROCK=1\n' sk-test-in-env-file >>"$s26/data/env"
s26_exec '' paid
grep -q '^ANTHROPIC_API_KEY=\|^CLAUDE_CODE_USE_BEDROCK=' "$s26/bin/last-env" && s26_bad+="a credential written into the env file reached claude"$'\n'
[[ "$(s26_meta paid status)" == ok && "$(s26_meta paid auth)" == none ]] || s26_bad+="a run on the login: $(s26_meta paid status), auth=$(s26_meta paid auth)"$'\n'
s26_says 'auth none' log paid && s26_says 'est. $' log paid && s26_says 'est. $' runs paid && s26_says ', est. $' show paid || s26_bad+="the estimate label or the auth line is missing"$'\n'
s26_says 'EST-COST' runs paid || s26_bad+="runs does not head the column as an estimate"$'\n'
empty "26 billing: no API credential in the env file or a run's environment, from the caller or the env file; auth=none recorded; costs labelled est." "$s26_bad"

s26_bad=""
s26_mode apikey
SECONDS=0; s26_run paid; s26_secs=$SECONDS
[[ "$(s26_meta paid status)" == refused && "$(s26_meta paid reason)" == "refused: api billing: the run's init event named apiKeySource ANTHROPIC_API_KEY, not the login" ]] \
    || s26_bad+="an API-key run: $(cat "$(s26_last paid)meta")"$'\n'
(( s26_secs < 10 )) || s26_bad+="it was stopped after ${s26_secs}s, not at once"$'\n'
[[ "$(s26_meta paid auth)" == ANTHROPIC_API_KEY ]] || s26_bad+="auth= not recorded"$'\n'
[[ "$(cat "$s26/data/state/paid.failures")" == 1 ]] || s26_bad+="a refused run did not count as a failure"$'\n'
empty "26 billing: a run whose init event names an API key source is stopped at once (${s26_secs}s), recorded refused with auth=, and counts as a failure" "$s26_bad"

s26_bad=""
s26_mode ok
rm -f "$s26/bin/calls"
printf '{"apiKeyHelper": "/usr/local/bin/print-key"}\n' >"$s26/ccfg/settings.json"
s26_run paid
[[ ! -s "$s26/bin/calls" ]] || s26_bad+="claude was called with an apiKeyHelper in the user settings"$'\n'
[[ "$(s26_meta paid status)" == refused && "$(s26_meta paid reason)" == "refused: api billing: $s26/ccfg/settings.json configures an apiKeyHelper" ]] || s26_bad+="meta: $(cat "$(s26_last paid)meta")"$'\n'
grep -q '^paused_reason: paused itself after 2 failed runs in a row' "$s26/cfg/tasks/paid.md" || s26_bad+="two refusals did not pause it"$'\n'
s26_says "Billing: runs are refused, since they would bill an API key, not the login: $s26/ccfg/settings.json configures an apiKeyHelper" show paid || s26_bad+="show does not name the setting"$'\n'
s26_says "its runs would bill an API key, so they are refused: $s26/ccfg/settings.json configures an apiKeyHelper" doctor || s26_bad+="doctor does not name it"$'\n'
s26_says "Login (claude auth status): claude.ai, firstParty, pro subscription" doctor || s26_bad+="doctor does not give the login line"$'\n'
rm -f "$s26/ccfg/settings.json"
printf '{"env": {"CLAUDE_CODE_USE_VERTEX": "1"}}\n' >"$s26/managed-settings.json"
mkdir -p "$s26/work/.claude"; printf '{"env": {"ANTHROPIC_AUTH_TOKEN": "x"}}\n' >"$s26/work/.claude/settings.local.json"
s26_x resume paid >/dev/null 2>&1; s26_run paid
[[ "$(s26_meta paid reason)" == *"$s26/managed-settings.json sets an API key or a cloud provider in its env block"*"$s26/work/.claude/settings.local.json sets an API key"* ]] \
    || s26_bad+="managed and project settings: $(s26_meta paid reason)"$'\n'
rm -f "$s26/managed-settings.json" "$s26/work/.claude/settings.local.json"; rmdir "$s26/work/.claude"
empty "26 billing: an apiKeyHelper or an API key in the user, managed or project settings refuses the run before claude is called, counts toward the pause, and show and doctor name the file" "$s26_bad"

# --- home: the tasks folder, remembered, and a folder the person versions ---------------------------------
s26_reset
s26_backend=none
s26_mode ok
rm -rf "$s26/xdg" "$s26/vers"
# s26_xh: as s26_x, without SCHEDULER_HOME, so the pointer file and the default are what decide.
s26_xh() { env -u SCHEDULER_HOME XDG_CONFIG_HOME="$s26/xdg" SCHEDULER_DATA="$s26/data" SCHEDULER_BACKEND=none SCHEDULER_NOTIFY_DESKTOP=0 \
    SCHEDULER_CLAUDE="$s26/bin/claude" CLAUDE_CONFIG_DIR="$s26/ccfg" SCHEDULER_MANAGED_SETTINGS="$s26/managed-settings.json" \
    "$st_bash" "$s26_sh" "$@" 2>&1; }
s26_bad=""
s26_def="$s26/xdg/agentic-workspace-kit/scheduler/tasks"
[[ "$(s26_xh home)" == "Tasks folder: $s26_def (the default)" ]] || s26_bad+="no pointer: $(s26_xh home)"$'\n'
s26_xh create first --schedule '0 7 * * *' --cwd "$s26/work" --prompt 'Say OK.' >/dev/null
s26_xh create second --schedule '0 8 * * *' --cwd "$s26/work" --prompt 'Say OK.' >/dev/null
s26_xh create third --schedule '0 9 * * *' --cwd "$s26/work" --prompt 'Say OK.' >/dev/null; s26_xh delete third >/dev/null
mkdir -p "$s26/vers"; git -C "$s26/vers" init -q
s26_out="$(s26_xh home "$s26/vers")"
[[ "$s26_out" == *"still holds 2 task file(s); 'schedule.sh home $s26/vers --move' takes them"* && ! -s "$s26/xdg/agentic-workspace-kit/scheduler/home" ]] \
    || s26_bad+="without --move: $s26_out"$'\n'
s26_vers="$(cd "$s26/vers" && pwd -P)"
s26_out="$(s26_xh home "$s26/vers" --move)"
[[ "$s26_out" == *"Tasks folder: $s26_vers (remembered in "*"2 task file(s) moved"* ]] || s26_bad+="--move said: $s26_out"$'\n'
[[ -f "$s26_vers/first.md" && -f "$s26_vers/second.md" && ! -e "$s26_def/first.md" ]] || s26_bad+="the task files did not move"$'\n'
ls "$s26_vers/.trash/"third-*.md >/dev/null 2>&1 && [[ ! -d "$s26_def/.trash" ]] || s26_bad+=".trash/ did not move"$'\n'
[[ "$(cat "$s26_vers/.gitignore" 2>/dev/null)" == ".trash/" ]] || s26_bad+="no .gitignore with .trash/"$'\n'
grep -qx "SCHEDULER_TASKS_DIR=$s26_vers" "$s26/data/env" || s26_bad+="the runner's env file does not name the new folder: $(grep TASKS "$s26/data/env")"$'\n'
[[ "$(s26_xh home)" == "Tasks folder: $s26_vers (the pointer file, "* ]] || s26_bad+="the pointer is not what decides: $(s26_xh home)"$'\n'
[[ "$(env SCHEDULER_HOME="$s26/elsewhere" XDG_CONFIG_HOME="$s26/xdg" "$st_bash" "$s26_sh" home 2>&1)" == "Tasks folder: $s26/elsewhere/tasks (SCHEDULER_HOME)" ]] \
    || s26_bad+="SCHEDULER_HOME does not win over the pointer"$'\n'
[[ "$(s26_xh show first)" == *"installed and matching the file"* ]] || s26_bad+="the unit does not match after the move"$'\n'
env -i HOME="$HOME" SCHEDULER_DATA="$s26/data" SCHEDULER_NOTIFY_DESKTOP=0 SCHEDULER_BACKEND=none /bin/bash "$s26/data/runner/schedule.sh" exec first
[[ "$(sed -n 's/^status=//p' "$(ls -1d "$s26/data/runs/first"/* | tail -n 1)/meta" | tail -n 1)" == ok ]] || s26_bad+="the runner did not find the task in its new folder"$'\n'
empty "26 home: env over pointer over default; --move takes the tasks and .trash/, writes .gitignore and syncs the runner to the new folder; without --move it refuses" "$s26_bad"

s26_bad=""
[[ "$(s26_xh show first)" == *"Git: the file is not committed to git (new or changed)."* ]] || s26_bad+="an untracked task file is not marked"$'\n'
git -C "$s26_vers" add -A && git -C "$s26_vers" -c user.name=t -c user.email=t@example.invalid commit -qm tasks
[[ "$(s26_xh show first)" != *"not committed"* ]] || s26_bad+="a committed task file is marked"$'\n'
s26_xh edit first --schedule '30 7 * * *' >/dev/null
[[ "$(s26_xh show first)" == *"Git: the file is not committed to git (new or changed)."* && "$(s26_xh doctor)" == *"Task first: the file is not committed to git (new or changed)"* ]] \
    || s26_bad+="an edited task file is not marked in show and doctor"$'\n'
[[ "$(s26_xh doctor)" != *"Task second: the file is not committed"* ]] || s26_bad+="a committed, unchanged task file is marked"$'\n'
# Two task files in a folder git has never seen (an untracked folder inside a repository, as a new home
# usually is): both read the same, in doctor, doctor <name> and show.
mkdir -p "$s26_vers/sub"; mv "$s26_vers/first.md" "$s26_vers/second.md" "$s26_vers/sub/" 2>/dev/null
s26_xh home "$s26_vers/sub" >/dev/null 2>&1
s26_d="$(s26_xh doctor)"
[[ "$s26_d" == *"Task first: the file is not committed to git (new or changed)"* && "$s26_d" == *"Task second: the file is not committed to git (new or changed)"* ]] \
    || s26_bad+="two untracked files in an untracked folder do not read the same: $(grep '^Task' <<<"$s26_d")"$'\n'
[[ "$(s26_xh doctor second)" == *"git: the file is not committed to git (new or changed)"* && "$(s26_xh show second)" == *"Git: the file is not committed"* ]] \
    || s26_bad+="doctor <name> or show does not mark it"$'\n'
s26_xh create leaky --schedule '0 7 * * *' --cwd "$s26/work" --prompt 'Post the summary.' \
    --notify 'curl -H "Authorization: Bearer abcdefghijklmnopqrstu" https://example.invalid' >/dev/null
[[ "$(s26_xh show leaky)" == *"Warning: line "*" look like a credential; keep it in a file the prompt points to."* ]] || s26_bad+="show does not warn of a credential"$'\n'
[[ "$(s26_xh doctor)" == *"Task leaky: line "*" of its file look like a credential"* ]] || s26_bad+="doctor does not warn of a credential"$'\n'
[[ "$(s26_xh show leaky | grep 'look like a credential')$(s26_xh doctor | grep 'look like a credential')" != *abcdefghijklmnopqrstu* ]] || s26_bad+="a warning printed the credential's value"$'\n'
git -C "$s26_vers" status --porcelain | grep -q '^??' || s26_bad+="the scheduler committed something"$'\n'
[[ "$(git -C "$s26_vers" rev-list --count HEAD)" == 1 ]] || s26_bad+="the scheduler made a commit"$'\n'
empty "26 home in git: an untracked or edited task file is marked alike in show, doctor and doctor <name>, two untracked ones in an untracked folder too; a credential in a task file warns without printing it; the scheduler never commits" "$s26_bad"

# --- verify, the sandbox, and a set rule already satisfied (PM-047) ----------------------------------------
s26_reset
s26_backend=none
s26_mode ok
s26_bad=""
# verify: the task's own definition of done, run after a good run in its folder, decides ok or failed.
s26_mk checked-done '0 7 * * *' --retries 0 --pause-after-failures 1 --notify-on failure \
    --verify 'test -f "$SCHEDULER_RUN_DIR/../../never-here" || { echo "the report file is missing" >&2; exit 3; }' \
    --notify 'printf "%s\n" "$SCHEDULER_STATUS" >>"$SCHEDULER_RUN_DIR/../../notified-verify"'
s26_exec '' checked-done
[[ "$(s26_meta checked-done status)" == failed && "$(s26_meta checked-done verify_exit)" == 3 \
   && "$(s26_meta checked-done reason)" == "verify: exit 3: the report file is missing "* ]] || s26_bad+="a failing verify: $(cat "$(s26_last checked-done)meta")"$'\n'
[[ "$(cat "$s26/data/runs/notified-verify" 2>/dev/null)" == failed ]] || s26_bad+="a failing verify did not notify"$'\n'
grep -q '^status: paused$' "$s26/cfg/tasks/checked-done.md" || s26_bad+="a failing verify did not count toward the self-pause"$'\n'
s26_says 'failed: verify: exit 3' runs checked-done || s26_bad+="runs does not show verify: $(s26_x runs checked-done)"$'\n'
s26_mk passes '0 7 * * *' --retries 0 --verify 'test -d "$SCHEDULER_RUN_DIR" && test -n "$SCHEDULER_RUN"'
s26_exec '' passes
[[ "$(s26_meta passes status)" == ok && "$(s26_meta passes verify_exit)" == 0 ]] || s26_bad+="a passing verify: $(cat "$(s26_last passes)meta")"$'\n'
empty "26 verify: a failing one makes a good run failed: verify (its last lines kept), notifies and counts toward the pause; a passing one leaves it ok" "$s26_bad"

# The sandbox: a network call it refused arrives in a tool result, and counts as a refusal.
s26_bad=""
cat >"$s26/bin/claude-sandbox" <<'EOF'
#!/bin/bash
cat >/dev/null
echo '{"type":"system","subtype":"init","apiKeySource":"none"}'
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"python3 sync.py"}}]}}'
echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"urllib3 error: Tunnel connection failed: 403 user denied"}]}}'
echo '{"type":"result","is_error":false,"result":"The sync failed: the network call was refused.","total_cost_usd":0.001,"permission_denials":[]}'
EOF
chmod +x "$s26/bin/claude-sandbox"; cp "$s26/bin/claude" "$s26/bin/claude-ok"; cp "$s26/bin/claude-sandbox" "$s26/bin/claude"
s26_mk netrun '0 7 * * *' --retries 0
s26_exec '' netrun
cp "$s26/bin/claude-ok" "$s26/bin/claude"
[[ "$(s26_meta netrun status)" == ok && "$(s26_meta netrun refusals)" == 1 && "$(s26_meta netrun refused_calls)" == "sandbox-network: Tunnel connection failed: 403 user denied (1 line(s))" ]] \
    || s26_bad+="a sandbox refusal: $(cat "$(s26_last netrun)meta")"$'\n'
s26_says 'ok (1 refused)' runs netrun || s26_bad+="runs does not count it"$'\n'
[[ "$(s26_x report --json | jq -r '.tasks[] | select(.task == "netrun") | .with_refusal')" == 1 ]] || s26_bad+="report does not count it"$'\n'
# show, doctor <name> and port check say whether the task's folder is sandboxed, and to which domains.
mkdir -p "$s26/work/.claude"
printf '{"sandbox": {"enabled": true, "network": {"allowedDomains": ["api.example.invalid", "*.example.org"]}}}\n' >"$s26/work/.claude/settings.json"
s26_says "Sandbox: on ($s26/work/.claude/settings.json); network calls go only to: api.example.invalid, *.example.org" show netrun || s26_bad+="show: $(s26_x show netrun | grep Sandbox)"$'\n'
s26_says "  sandbox: on ($s26/work/.claude/settings.json)" doctor netrun || s26_bad+="doctor <name> does not say so"$'\n'
printf '%s\n' "[{\"name\": \"Sandboxed one\", \"schedule\": \"@daily\", \"prompt\": \"Say OK.\", \"cwd\": \"$s26/work\", \"permission_mode\": \"dontAsk\"}]" >"$s26/sandboxed.json"
s26_out="$(s26_x port start "$s26/sandboxed.json" 2>&1)"
[[ "$s26_out" == *"[warn] sandbox: The run is sandboxed"*"network calls go only to the allowed domains; a refused one fails without asking."* ]] || s26_bad+="port check: $s26_out"$'\n'
rm -f "$s26/work/.claude/settings.json"; rmdir "$s26/work/.claude"
s26_says 'Sandbox: off' show netrun || s26_bad+="show does not say off"$'\n'
empty "26 sandbox: a refused network call in the stream counts as a refusal (runs, report); show, doctor and port check name the sandbox and its domains" "$s26_bad"

# A set rule says nothing when the field already has its value.
s26_bad=""
printf '%s\n' "[{\"name\": \"Browser one\", \"schedule\": \"@daily\", \"prompt\": \"Open the page with mcp__claude-in-chrome__navigate.\", \"cwd\": \"$s26/work\", \"permission_mode\": \"dontAsk\"}]" >"$s26/browser.json"
s26_out="$(s26_x port start "$s26/browser.json" 2>&1)"
[[ "$s26_out" == *"[set] browser-tools:1"* ]] && grep -qx 'chrome: true' "$s26/cfg/tasks/browser-one.md" || s26_bad+="the first check did not set chrome: $s26_out"$'\n'
[[ "$(s26_x port check browser-one 2>&1)" != *"[set] browser-tools"* ]] || s26_bad+="a second check still prints the set rule for chrome: true"$'\n'
empty "26 port check: a set rule reports when it sets the field, and says nothing once the task has it" "$s26_bad"

# --- Retries judged per attempt (PM-051): verify, denial, retry_on, delay lists, the billing stop -----------
s26_reset
s26_backend=none
s26_bad=""
s26_mode ok
# A verify that fails its first attempt and passes its second. Each attempt keeps its own verify output
# and sees its own clock; the verify records its environment against the attempt number.
s26_mk vonce '0 7 * * *' --retries 2 --retry-delay 1s --pause-after-failures 0 \
    --verify 'n=$(cat "$SCHEDULER_RUN_DIR/../../vc-vonce" 2>/dev/null || echo 0); n=$((n + 1)); echo $n >"$SCHEDULER_RUN_DIR/../../vc-vonce"; env | grep "^SCHEDULER_" >"$SCHEDULER_RUN_DIR/venv-$SCHEDULER_ATTEMPT"; [ "$n" -ge 2 ]'
# The counter the verify keeps lives in the runs folder, so it is cleared first; the run fires on a pinned clock
# (07:00, the task's own minute), so no wall-clock minute enters the attempts or their stamps.
rm -f "$s26/data/runs/vc-vonce"
s26_exec '2026-10-30 07:00' vonce
vonce_run="$(s26_last vonce)"
[[ "$(s26_meta vonce status)" == ok && "$(s26_meta vonce attempts)" == 2 && "$(s26_meta vonce first_failure)" == verify ]] \
    || s26_bad+="a verify failing once is not retried to ok: $(cat "$vonce_run/meta")"$'\n'
grep -qx 'attempt=1 outcome=failed: verify: exit 1' "$vonce_run/attempts" && grep -qx 'attempt=2 outcome=ok' "$vonce_run/attempts" \
    || s26_bad+="the attempts file does not give each attempt's outcome: $(cat "$vonce_run/attempts")"$'\n'
[[ -f "$vonce_run/verify-1.err" && -f "$vonce_run/verify-2.out" ]] || s26_bad+="verify output is not kept per attempt"$'\n'
grep -qE '^SCHEDULER_ATTEMPT=2$' "$vonce_run/venv-2" && grep -qE '^SCHEDULER_ATTEMPT_START=[0-9]{8}-[0-9]{4}$' "$vonce_run/venv-2" \
    && grep -qE '^SCHEDULER_RUN_START=[0-9]{8}-[0-9]{4}$' "$vonce_run/venv-2" \
    || s26_bad+="verify does not carry the attempt's clock: $(cat "$vonce_run/venv-2")"$'\n'
s26_says 'ok after 2 attempts (1 failed: verify)' runs vonce || s26_bad+="runs does not say the run recovered: $(s26_x runs vonce)"$'\n'
# retry_on: timeout leaves a verify failure unretried.
s26_mk vto '0 7 * * *' --retries 2 --retry-on timeout --retry-delay 1s --pause-after-failures 0 --verify 'exit 1'
s26_run vto
[[ "$(s26_meta vto status)" == failed && "$(s26_meta vto attempts)" == 1 && "$(s26_meta vto failed_attempts)" == verify ]] \
    || s26_bad+="retry_on timeout retried a verify failure: $(cat "$(s26_last vto)meta")"$'\n'
# A refusal the first attempt stopped at is retried under the default retry_on.
s26_mode deniedonce
s26_mk vden '0 7 * * *' --retries 1 --retry-delay 1s --pause-after-failures 0
s26_run vden
[[ "$(s26_meta vden status)" == ok && "$(s26_meta vden attempts)" == 2 && "$(s26_meta vden first_failure)" == denied ]] \
    || s26_bad+="a denied first attempt was not retried: $(cat "$(s26_last vden)meta")"$'\n'
# A run billed to an API key is stopped at once, whatever retries say.
s26_mode apikey
s26_mk vpaid '0 7 * * *' --retries 2 --retry-delay 1s --pause-after-failures 0
s26_run vpaid
[[ "$(s26_meta vpaid status)" == refused && "$(s26_meta vpaid attempts)" == 1 ]] \
    || s26_bad+="a billing refusal was retried: $(cat "$(s26_last vpaid)meta")"$'\n'
s26_mode fail
# The wait after each failed attempt, through a fake sleep that logs its argument. A single delay grows
# with the attempt (1, 2); a list is used in order and its last entry repeated (1, 2, 2).
mkdir -p "$s26/fakesleep"
# Decimal sleeps are the runner's own polling and pass through; the whole seconds the retries wait are logged.
printf '#!/bin/sh\ncase "$1" in *.*) exec /bin/sleep "$1" ;; esac\necho "$1" >>"%s/fakesleep-log"\n' "$s26" >"$s26/fakesleep/sleep"; chmod +x "$s26/fakesleep/sleep"
s26_mk vgrow '0 7 * * *' --retries 2 --retry-delay 1s --pause-after-failures 0
s26_mk vlist '0 7 * * *' --retries 3 --retry-delay '1s, 2s' --pause-after-failures 0
rm -f "$s26/fakesleep-log"; PATH="$s26/fakesleep:$PATH" s26_run vgrow
[[ "$(tr '\n' ' ' <"$s26/fakesleep-log" 2>/dev/null)" == "1 2 " ]] || s26_bad+="a single retry_delay does not grow: $(tr '\n' ' ' <"$s26/fakesleep-log" 2>/dev/null)"$'\n'
rm -f "$s26/fakesleep-log"; PATH="$s26/fakesleep:$PATH" s26_run vlist
[[ "$(s26_meta vlist attempts)" == 4 && "$(tr '\n' ' ' <"$s26/fakesleep-log" 2>/dev/null)" == "1 2 2 " ]] \
    || s26_bad+="a retry_delay list is not used in order with its last entry repeated: $(tr '\n' ' ' <"$s26/fakesleep-log" 2>/dev/null)"$'\n'
# report counts scheduled runs only, so this one fires on the schedule's clock, not by hand.
s26_mode failonce
s26_mk rsched '0 7 * * *' --retries 1 --retry-delay 1s --pause-after-failures 0
s26_exec '2026-10-30 07:00' rsched
[[ "$(s26_meta rsched trigger)" == schedule && "$(s26_meta rsched status)" == ok && "$(s26_meta rsched first_failure)" == failed ]] \
    || s26_bad+="a scheduled run that failed then recovered: $(cat "$(s26_last rsched)meta")"$'\n'
s26_x report --json | jq -e '.totals.retried >= 1 and .totals.recovered >= 1' >/dev/null \
    || s26_bad+="report does not count the scheduled run a retry recovered: $(s26_x report --json | head -c 300)"$'\n'
s26_says 'recovered on a retry' report || s26_bad+="report's totals do not name the recovered runs"$'\n'
empty "26 retries: each attempt judged in full (a failed verify is retried to ok, denial too); retry_on narrows it; billing is never retried; delays grow or follow the list; the verify sees its attempt's clock; report counts recovered runs" "$s26_bad"

# --- Answers given in a session, through the Stop hook; the question in the notification (PM-052) ---------
s26_reset
s26_backend=none
s26_bad=""
s26_mode ok
unset AW_HEADLESS_RUN
mkdir -p "$s26/ws/.claude" "$s26/outside" && : >"$s26/ws/.claude/kit-templates.lock"
# The Stop hook as Claude Code calls it: its input on stdin, from a folder (the workspace unless given).
s26_hook() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$1" "$2" "${3:-$s26/ws}" \
    | env SCHEDULER_HOME="$s26/cfg" SCHEDULER_DATA="$s26/data" bash "$KIT/plugins/scheduler/hooks/stop.sh"; }
s26_mk ask '0 7 * * *' --awaits-reply true --retries 0 --pause-after-failures 0 \
    --notify 'printf "%s\n" "$SCHEDULER_QUESTION" >"$SCHEDULER_RUN_DIR/../../notified-ask-question"'
s26_run ask
[[ "$(s26_meta ask status)" == waiting && -f "$s26/data/state/ask.waiting" ]] || s26_bad+="a run that awaits a reply is not waiting: $(s26_meta ask status)"$'\n'
[[ "$(cat "$s26/data/runs/notified-ask-question" 2>/dev/null)" == "OK, done." ]] || s26_bad+="the notify command did not get the question: $(cat "$s26/data/runs/notified-ask-question" 2>/dev/null)"$'\n'
sid="$(s26_meta ask session_id)"
tr="$s26/ask-transcript.jsonl"
cat >"$tr" <<'EOF'
{"type":"user","message":{"role":"user","content":"List the options."}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"1. A\n2. B"}]}}
{"type":"user","message":{"role":"user","content":"2"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Got it: B."}]}}
EOF
# A session that owns the waiting run is not the only one: another session, a headless one, a folder outside
# the workspace and a held lock each leave the run waiting.
s26_hook "00000000-0000-4000-8000-000000000000" "$tr"
[[ -f "$s26/data/state/ask.waiting" ]] || s26_bad+="the hook acted on another session"$'\n'
AW_HEADLESS_RUN=1 s26_hook "$sid" "$tr"
[[ -f "$s26/data/state/ask.waiting" ]] || s26_bad+="the hook acted in a headless run"$'\n'
s26_hook "$sid" "$tr" "$s26/outside"
[[ -f "$s26/data/state/ask.waiting" ]] || s26_bad+="the hook acted outside a workspace"$'\n'
mkdir -p "$s26/data/locks/ask" && echo $$ >"$s26/data/locks/ask/pid"
s26_hook "$sid" "$tr"
rm -rf "$s26/data/locks/ask"
[[ -f "$s26/data/state/ask.waiting" ]] || s26_bad+="the hook acted while a reply was going on"$'\n'
# The answer, given in the session: the last thing the person wrote is the reply, the last thing Claude
# said is the result, the run ends ok and stops waiting. A second stop records nothing more.
s26_hook "$sid" "$tr"
[[ "$(s26_meta ask status)" == ok && "$(s26_meta ask reply_via)" == session && ! -f "$s26/data/state/ask.waiting" ]] \
    || s26_bad+="a session answer does not end the run: $(cat "$(s26_last ask)meta")"$'\n'
[[ "$(cat "$(s26_last ask)reply-1.txt")" == "2" && "$(cat "$(s26_last ask)result.txt")" == "Got it: B." ]] \
    || s26_bad+="the reply or the result is not the answer: $(cat "$(s26_last ask)reply-1.txt") / $(cat "$(s26_last ask)result.txt")"$'\n'
s26_hook "$sid" "$tr"
[[ ! -f "$(s26_last ask)reply-2.txt" ]] || s26_bad+="a second stop recorded a reply again"$'\n'
s26_says 'Reply 1:' log ask || s26_bad+="log does not show the session's reply"$'\n'
empty "26 session answers: a run awaiting a reply is answered once by the Stop hook, in its own session; other sessions, headless runs, folders outside a workspace and a held lock change nothing; the notification carries the question" "$s26_bad"

# --- reach: remote (PM-058): a waiting run starts its session with Remote Control on; answering it stops that --
s26_reset
s26_backend=none
s26_bad=""
s26_mode ok
s26_mk remote1 '0 7 * * *' --awaits-reply true --reach remote --reply-window 2s --retries 0 --pause-after-failures 0
s26_run remote1
[[ "$(s26_meta remote1 status)" == waiting && "$(s26_meta remote1 reach_id)" == stubbg ]] \
    || s26_bad+="a remote run did not start its session: $(cat "$(s26_last remote1)meta")"$'\n'
grep -q -- '--remote-control remote1' "$s26/bin/bg-calls" 2>/dev/null || s26_bad+="no background session with Remote Control was started"$'\n'
s26_x reply remote1 'fine' >/dev/null 2>&1
grep -qx 'stop stubbg' "$s26/bin/stop-calls" 2>/dev/null || s26_bad+="answering the run did not stop its session"$'\n'
s26_says "reach 'phone' is not desktop or remote" create reachy --schedule '0 7 * * *' --cwd "$s26/work" --prompt hi --reach phone \
    || s26_bad+="a bad reach value is not refused by create"$'\n'
empty "26 reach: a remote run starts a background session with Remote Control on and its answer stops it; a bad reach value is refused" "$s26_bad"

# --- reach: the sweep ends a remote session once its run is over, by sync, doctor and every runner start --
# A run answered without its stop, a runner start, a run past its window. The stub logs each stop, so a
# second sweep shows as a second line. A plain run has no reach file, and its session is never stopped.
s26_reset
s26_backend=none
s26_bad=""
rm -f "$s26/bin/stop-calls" "$s26/bin/bg-calls"
s26_mode ok
s26_mk sweep-left '0 7 * * *' --awaits-reply true --reach remote --reply-window 1h --retries 0 --pause-after-failures 0
s26_mk sweep-plain '0 8 * * *' --retries 0 --pause-after-failures 0
s26_run sweep-plain
s26_run sweep-left
[[ "$(s26_meta sweep-left status)" == waiting ]] || s26_bad+="the remote run did not wait"$'\n'
s26_left="$(s26_last sweep-left)"
# The answer went through with no stop: the run is ok and its session is still there.
printf 'status=ok\n' >>"${s26_left}meta"
s26_x sync >/dev/null 2>&1
[[ "$(cat "$s26/bin/stop-calls" 2>/dev/null)" == "stop stubbg" ]] || s26_bad+="sync did not end the session of an answered run: $(cat "$s26/bin/stop-calls" 2>/dev/null)"$'\n'
grep -q '^reach_swept=' "${s26_left}reach" || s26_bad+="the sweep did not mark the reach file"$'\n'
s26_x sync >/dev/null 2>&1
[[ "$(wc -l <"$s26/bin/stop-calls" | tr -d ' ')" == 1 ]] || s26_bad+="a second sweep stopped the session again"$'\n'
empty "26 reach sweep: sync ends the session of a run answered without its stop, once; a plain run's session is not stopped" "$s26_bad"

# A stop that fails stays unswept: doctor lists the session, and the next sync tries again and clears it.
s26_bad=""
rm -f "$s26/bin/stop-calls"; : > "$s26/bin/stop-fail"
s26_mk sweep-fail '0 12 * * *' --awaits-reply true --reach remote --reply-window 1h --retries 0 --pause-after-failures 0
s26_run sweep-fail
s26_fl="$(s26_last sweep-fail)"
printf 'status=ok\n' >>"${s26_fl}meta"
s26_x sync >/dev/null 2>&1
grep -q '^reach_swept=' "${s26_fl}reach" && s26_bad+="a failed stop was marked swept"$'\n'
s26_dout="$(s26_x doctor 2>&1)"
grep -q 'sweep-fail stubbg' <<<"$s26_dout" || s26_bad+="doctor did not list the session whose stop failed: $s26_dout"$'\n'
rm -f "$s26/bin/stop-fail"
s26_x sync >/dev/null 2>&1
[[ "$(grep -c '^stop stubbg' "$s26/bin/stop-calls" 2>/dev/null)" -ge 2 ]] || s26_bad+="the next sync did not try the stop again"$'\n'
grep -q '^reach_swept=' "${s26_fl}reach" || s26_bad+="the retried stop did not mark the reach file"$'\n'
empty "26 reach sweep: a failed stop stays listed by doctor and is retried by the next sync until it succeeds" "$s26_bad"

s26_bad=""
rm -f "$s26/bin/stop-calls"
s26_mk sweep-runner '0 9 * * *' --awaits-reply true --reach remote --reply-window 1h --retries 0 --pause-after-failures 0
s26_run sweep-runner
printf 'status=ok\n' >>"$(s26_last sweep-runner)meta"
s26_x exec sweep-plain >/dev/null 2>&1
[[ "$(cat "$s26/bin/stop-calls" 2>/dev/null)" == "stop stubbg" ]] || s26_bad+="a runner start did not end an answered run's session"$'\n'
empty "26 reach sweep: a runner start ends a remote session whose run is over" "$s26_bad"

s26_bad=""
rm -f "$s26/bin/stop-calls"
s26_mk sweep-open '0 10 * * *' --awaits-reply true --reach remote --reply-window 1h --retries 0 --pause-after-failures 0
s26_run sweep-open
s26_says 'sweep-open stubbg: awaiting a reply, age 0m' doctor || s26_bad+="doctor does not list a running remote session with its age"$'\n'
[[ ! -s "$s26/bin/stop-calls" ]] || s26_bad+="doctor ended a session that is still awaiting its reply"$'\n'
empty "26 reach sweep: doctor lists a remote session still running, with its age, and leaves it running while its run awaits a reply" "$s26_bad"

s26_bad=""
rm -f "$s26/bin/stop-calls"
s26_mk sweep-expired '0 11 * * *' --awaits-reply true --reach remote --reply-window 1s --retries 0 --pause-after-failures 0
s26_run sweep-expired
sleep 2
s26_x doctor >/dev/null 2>&1
grep -q '^reach_swept=' "$(s26_last sweep-expired)reach" || s26_bad+="doctor did not sweep a run past its reply window"$'\n'
s26_says 'sweep-expired stubbg' doctor && s26_bad+="doctor still lists a session whose run has expired"$'\n'
empty "26 reach sweep: a run past its reply window is swept by doctor and no longer listed" "$s26_bad"

# --- The example, and setup -------------------------------------------------------------------
s26_reset
s26_out="$(s26_x create --file "$KIT/plugins/scheduler/examples/task.md" --cwd "$s26/work" --dry-run 2>&1)"
[[ "$s26_out" == *"name: daily-commits"*"Next fire times:"*" 07:30 "* && "$s26_out" != *" 07:30 Sat"* && "$s26_out" != *" 07:30 Sun"* ]] \
    && ok "26 examples/task.md is a valid task: create --file --dry-run shows it with weekday 07:30 fire times" \
    || ko "26 examples/task.md is a valid task: create --file --dry-run shows it with weekday 07:30 fire times" "$s26_out"
# Installed by setup like the kit's other plugins; it does nothing until someone creates a task.
s26_bad=""
grep -q '^KIT_PLUGINS="closeout projects scheduler workspace"$' "$KIT/setup.sh" || s26_bad+="setup.sh's KIT_PLUGINS: $(grep '^KIT_PLUGINS=' "$KIT/setup.sh")"$'\n'
jq -e '.enabledPlugins["scheduler@agentic-workspace"] == true' "$KIT/templates/workspace/settings.json" >/dev/null || s26_bad+="the workspace template does not enable it"$'\n'
grep -qF 'installed, it schedules nothing' "$KIT/setup.sh" || s26_bad+="setup's offer does not say that installed is not acting"$'\n'
empty "26 setup installs and the workspace template enables the scheduler, and the offer says installed schedules nothing" "$s26_bad"

# --- Live in Linux containers (opt-in): systemd on Ubuntu and Fedora, cron on Debian -----------------------
# Each container gets the plugin and tests/docker/live.sh, and a stub claude (no network, no login); the
# driver's PASS and FAIL lines become checks here. systemd runs as PID 1 with --privileged,
# --cgroupns=private and tmpfs on /run and /run/lock. The three run at once; each takes three to four
# minutes, most of it the waits for real fires and the two-minute window after a pause.
if [[ "${AW_TEST_DOCKER:-}" != 1 ]]; then
    skp "26 docker: live systemd (Ubuntu, Fedora) and cron (Debian) runs in containers — opt-in (AW_TEST_DOCKER=1)"
elif ! docker info >/dev/null 2>&1; then
    ko "26 docker: AW_TEST_DOCKER=1, but no Docker daemon answers"
else
    s26_dk="$KIT/tests/docker"
    s26_dlog="$SCRATCH/s26-docker"; mkdir -p "$s26_dlog"
    s26_dpids=()
    for s26_spec in ubuntu-systemd:systemd fedora-systemd:systemd debian-cron:cron; do
        s26_img="${s26_spec%%:*}" s26_mode="${s26_spec#*:}"
        (
            c="aw-sched-test-$s26_img-$$"
            SECONDS=0
            nice -n 10 docker build -q -t "aw-sched-test:$s26_img" -f "$s26_dk/$s26_img.Dockerfile" "$s26_dk" >/dev/null 2>"$s26_dlog/$s26_img.build" \
                || { echo "FAIL the image builds: $(tail -n 3 "$s26_dlog/$s26_img.build")"; exit 0; }
            if [[ "$s26_mode" == systemd ]]; then
                docker run -d --name "$c" --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock "aw-sched-test:$s26_img" >/dev/null
                for _ in $(seq 1 40); do
                    st="$(docker exec "$c" systemctl is-system-running 2>/dev/null)"
                    [[ "$st" == running || "$st" == degraded ]] && docker exec "$c" test -S /run/user/1001/bus && break
                    sleep 1
                done
                ex=(-e XDG_RUNTIME_DIR=/run/user/1001 -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus)
            else
                docker run -d --name "$c" "aw-sched-test:$s26_img" >/dev/null
                ex=()
            fi
            docker cp "$KIT/plugins/scheduler" "$c:/opt/scheduler" >/dev/null && docker cp "$s26_dk/live.sh" "$c:/opt/live.sh" >/dev/null
            docker exec -u runner ${ex[@]+"${ex[@]}"} "$c" bash /opt/live.sh "$s26_mode" 2>&1
            echo "TIME $SECONDS"
            docker rm -f "$c" >/dev/null 2>&1
        ) >"$s26_dlog/$s26_img.out" 2>&1 &
        s26_dpids+=($!)
    done
    for s26_p in "${s26_dpids[@]}"; do wait "$s26_p"; done
    for s26_img in ubuntu-systemd fedora-systemd debian-cron; do
        s26_secs_d="$(sed -n 's/^TIME //p' "$s26_dlog/$s26_img.out")"
        s26_info="$(grep '^INFO' "$s26_dlog/$s26_img.out")"
        grep -q '^PASS \|^FAIL ' "$s26_dlog/$s26_img.out" || ko "26 docker $s26_img: the driver ran no checks" "$(cat "$s26_dlog/$s26_img.out")"
        while IFS= read -r s26_l; do
            case "$s26_l" in
                "PASS "*) ok "26 docker $s26_img: ${s26_l#PASS }" ;;
                "FAIL "*) ko "26 docker $s26_img: ${s26_l#FAIL }" "$s26_info" ;;
            esac
        done <"$s26_dlog/$s26_img.out"
        echo "      docker $s26_img: ${s26_secs_d:-?}s; $(paste -sd';' - <<<"${s26_info//INFO /}")"
    done
fi

# The pane's command is registered as /scheduler-pane: a hooks module's command is not prefixed with the plugin's
# name, so the name carries it, and the pane's doc names the same command.
s26_pn="$(grep -c "command.register({ name: 'scheduler-pane'" "$KIT/plugins/scheduler/hooks/pane.tsx")"
[[ "$s26_pn" == 1 ]] && grep -q '/scheduler-pane' "$KIT/docs/hooks/scheduler-pane.md" \
    && ok "26 the pane registers /scheduler-pane, and its page names that command" \
    || ko "26 the pane registers /scheduler-pane, and its page names that command" "register count $s26_pn"
# --- The plugin's own tests (the pane) -------------------------------------------------------------
# claude plugin test runs each *.test.tsx under the plugin folder; a build without the subcommand prints one skip.
if command -v claude >/dev/null 2>&1 && claude plugin test --help >/dev/null 2>&1; then
    s26_ptest="$(claude plugin test "$KIT/plugins/scheduler" 2>&1)"; s26_prc=$?
    if [[ $s26_prc -eq 0 ]]; then ok "26 claude plugin test passes on the scheduler plugin"
    else ko "26 claude plugin test passes on the scheduler plugin" "$s26_ptest"; fi
else
    skp "26 claude plugin test not available in this claude build; the scheduler plugin's tests not run"
fi

# --- Shellcheck -------------------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
    check "26 shellcheck -x is clean on schedule.sh, lib/port.sh, the hook, the Docker scripts and this section" \
        shellcheck -x "$s26_sh" "$KIT/plugins/scheduler/scripts/lib/port.sh" "$KIT/plugins/scheduler/hooks/session-start.sh" \
        "$KIT/tests/docker/live.sh" "$KIT/tests/docker/claude-stub.sh" "$KIT/tests/sections/26-scheduler.sh"
else
    skp "26 shellcheck not on PATH; schedule.sh not linted"
fi
