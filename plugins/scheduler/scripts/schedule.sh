#!/bin/bash
# schedule.sh: scheduled Claude Code tasks on this machine, rendered into the host's own scheduler.
#
# A task is one Markdown file: flat "key: value" front matter for its configuration, and a body that is
# the prompt. The file is the truth; the OS unit (a LaunchAgent, a systemd user timer or a line in a
# managed crontab block) is rendered from it, and `sync` renders all of them again. The OS calls this
# script's `exec`, the runner, from a copy kept in the state folder, so units outlive the plugin moving.
#
#   Tasks:  the folder `schedule.sh home` names: $SCHEDULER_HOME/tasks, else the folder the pointer file
#           (~/.config/agentic-workspace-kit/scheduler/home) names, else
#           ${XDG_CONFIG_HOME:-~/.config}/agentic-workspace-kit/scheduler/tasks/<name>.md
#   State:  ${SCHEDULER_DATA:-${XDG_STATE_HOME:-~/.local/state}/agentic-workspace-kit/scheduler}/
#           runner/schedule.sh and env (written by sync), runs/<name>/<run>/, state/, locks/, logs/, units/
#
# Bash 3.2 (macOS's /bin/bash): no associative arrays, no mapfile. No python at runtime; jq is used to
# read Claude's JSON output when it is on PATH, with a sed fallback.
#
# Environment, mostly for tests: SCHEDULER_BACKEND (launchd, systemd, cron, none), SCHEDULER_LAUNCHCTL,
# SCHEDULER_SYSTEMCTL, SCHEDULER_CRONTAB, SCHEDULER_SCHTASKS (the OS tools), SCHEDULER_CLAUDE (the claude
# binary sync records), SCHEDULER_LAUNCH_AGENTS, SCHEDULER_SYSTEMD_DIR (where units are written),
# SCHEDULER_NOW ("YYYY-MM-DD HH:MM", a fixed clock), SCHEDULER_NOTIFY_DESKTOP=0 (no desktop notices),
# SCHEDULER_UID (the launchd domain's uid).

# The task's fields live in t_<field> and their defaults in D_<field>, set and read by name (printf -v,
# ${!v}), which shellcheck cannot follow (SC2034, SC2154); the env file is written at sync (SC1091); and
# "test && ok || fail" lines are meant as written (SC2015); a zone or a run's environment is set inside a
# subshell on purpose, so it reaches that one command and nothing after it (SC2030, SC2031).
# shellcheck disable=SC2034,SC2154,SC1091,SC2015,SC2030,SC2031

VERSION=0.1.0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"

FIELDS="name description schedule timezone status paused_reason cwd model effort fallback_model permission_mode allowed_tools disallowed_tools add_dirs chrome requires max_budget_usd timeout retries retry_delay retry_on pause_after_failures verify awaits_reply reply_window reach result_to notify notify_on keep_runs created"
# Fields a flag may set; name, status, paused_reason and created belong to create, pause and resume.
SETTABLE="description schedule timezone cwd model effort fallback_model permission_mode allowed_tools disallowed_tools add_dirs chrome requires max_budget_usd timeout retries retry_delay retry_on pause_after_failures verify awaits_reply reply_window reach result_to notify notify_on keep_runs"
D_status=active D_permission_mode=dontAsk D_timeout=30m D_retries=1 D_retry_delay=2m D_retry_on=all D_reach=desktop
D_pause_after_failures=3 D_notify_on=failure D_keep_runs=30 D_reply_window=24h
LAUNCHD_MAX=400
LABEL_PREFIX=agentic-workspace.scheduler
UNIT_PREFIX=aw-scheduler
CRON_BEGIN="# BEGIN agentic-workspace scheduler (rendered by schedule.sh sync; edits inside are replaced)"
CRON_END="# END agentic-workspace scheduler"
HEADLESS_PROMPT="This session was started by a schedule on this machine, and nobody is watching it. No one will answer a question or approve a tool, so work with the tools already allowed and finish what can be finished. When something stops the work, the final reply says what it was and what would unblock it; that reply is kept as the run's record."

die() { printf 'schedule.sh: %s\n' "$*" >&2; exit 1; }
usage_die() { printf 'schedule.sh: %s\n' "$*" >&2; echo "Run 'schedule.sh help' for usage." >&2; exit 2; }
warn() { printf 'schedule.sh: %s\n' "$*" >&2; }

# --- Paths ---------------------------------------------------------------------------------------------
S_HOME="${SCHEDULER_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/agentic-workspace-kit/scheduler}"
if [[ -z "${SCHEDULER_DATA:-}" && "$SELF_DIR" == */runner && -f "$SELF_DIR/../env" ]]; then
    S_DATA="$(cd "$SELF_DIR/.." && pwd)"     # the runner's copy finds its state folder from where it sits
else
    S_DATA="${SCHEDULER_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/agentic-workspace-kit/scheduler}"
fi
# The tasks folder: SCHEDULER_HOME's tasks/, else the folder the pointer file names (set by
# `schedule.sh home <dir>`, so a person can keep tasks in a folder they version), else the default.
# The runner is handed the folder sync resolved (SCHEDULER_TASKS_DIR), so it never resolves it again.
POINTER="${XDG_CONFIG_HOME:-$HOME/.config}/agentic-workspace-kit/scheduler/home"
resolve_tasks() {
    if [[ -n "${SCHEDULER_TASKS_DIR:-}" ]]; then S_TASKS="$SCHEDULER_TASKS_DIR" S_TASKS_WHY="recorded by sync"
    elif [[ -n "${SCHEDULER_HOME:-}" ]]; then S_TASKS="$SCHEDULER_HOME/tasks" S_TASKS_WHY="SCHEDULER_HOME"
    elif [[ -s "$POINTER" ]] && read -r S_TASKS <"$POINTER" && [[ -n "$S_TASKS" ]]; then S_TASKS_WHY="the pointer file, $POINTER"
    else S_TASKS="$S_HOME/tasks" S_TASKS_WHY="the default"; fi
}
resolve_tasks
# The OS tools and unit folders, overridable for tests; sync records any override in the env file, so
# the runner (which starts from a bare environment) acts on the same ones.
TOOL_VARS="SCHEDULER_LAUNCHCTL SCHEDULER_SYSTEMCTL SCHEDULER_CRONTAB SCHEDULER_SCHTASKS SCHEDULER_LAUNCH_AGENTS SCHEDULER_SYSTEMD_DIR SCHEDULER_UID SCHEDULER_MANAGED_SETTINGS CLAUDE_CONFIG_DIR"
set_tools() {
    LAUNCHCTL="${SCHEDULER_LAUNCHCTL:-launchctl}"
    SYSTEMCTL="${SCHEDULER_SYSTEMCTL:-systemctl}"
    CRONTAB="${SCHEDULER_CRONTAB:-crontab}"
    SCHTASKS="${SCHEDULER_SCHTASKS:-schtasks.exe}"
    LA_DIR="${SCHEDULER_LAUNCH_AGENTS:-$HOME/Library/LaunchAgents}"
    SD_DIR="${SCHEDULER_SYSTEMD_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"
    UIDN="${SCHEDULER_UID:-$(id -u)}"
}
set_tools
RUNNER="$S_DATA/runner/schedule.sh"

# --- Small helpers -------------------------------------------------------------------------------------
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }   # single-quote for sh
xml() { local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"; }
json_str() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"
    printf '"%s"' "$s"
}
valid_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; }
pad2() { if (( $1 < 10 )); then printf '0%d' "$1"; else printf '%d' "$1"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

# dur_secs <text>: 90s, 30m, 2h, 1d, or a plain number of seconds, into DS.
dur_secs() {
    local t; t="$(lower "$1")"
    if [[ "$t" =~ ^([0-9]+)(s|m|h|d)?$ ]]; then
        DS=$((10#${BASH_REMATCH[1]}))
        case "${BASH_REMATCH[2]}" in m) DS=$((DS * 60)) ;; h) DS=$((DS * 3600)) ;; d) DS=$((DS * 86400)) ;; esac
        return 0
    fi
    return 1
}

# --- Clock ---------------------------------------------------------------------------------------------
# Local time throughout. NOW_* is the current minute, or SCHEDULER_NOW for a fixed clock.
now_parts() {
    local s="${SCHEDULER_NOW:-$(date '+%Y-%m-%d %H:%M')}"
    [[ "$s" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})[[:space:]]+([0-9]{1,2}):([0-9]{2})$ ]] || die "SCHEDULER_NOW is not YYYY-MM-DD HH:MM: $s"
    NOW_Y=$((10#${BASH_REMATCH[1]})) NOW_M=$((10#${BASH_REMATCH[2]})) NOW_D=$((10#${BASH_REMATCH[3]}))
    NOW_H=$((10#${BASH_REMATCH[4]})) NOW_MI=$((10#${BASH_REMATCH[5]}))
    NOW_STR="$(printf '%04d-%s-%s %s:%s' "$NOW_Y" "$(pad2 "$NOW_M")" "$(pad2 "$NOW_D")" "$(pad2 "$NOW_H")" "$(pad2 "$NOW_MI")")"
}
now_epoch() {
    if [[ -n "${SCHEDULER_NOW:-}" ]]; then local_to_epoch "$SCHEDULER_NOW"; else date +%s; fi
}
# local_to_epoch "YYYY-MM-DD HH:MM" and epoch_fmt <epoch> <format>: BSD date first, then GNU.
local_to_epoch() {
    date -j -f '%Y-%m-%d %H:%M:%S' "$1:00" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}
epoch_fmt() { date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null; }

# Civil-calendar arithmetic in integers (Howard Hinnant's days_from_civil), so fire times are computed
# a day at a time from the calendar rather than by stepping minutes.
days_from_civil() {   # y m d -> DFC (days since 1970-01-01)
    local y=$1 m=$2 d=$3 era yoe doy doe
    (( m <= 2 )) && y=$((y - 1))
    if (( y >= 0 )); then era=$((y / 400)); else era=$(((y - 399) / 400)); fi
    yoe=$((y - era * 400))
    if (( m > 2 )); then doy=$(((153 * (m - 3) + 2) / 5 + d - 1)); else doy=$(((153 * (m + 9) + 2) / 5 + d - 1)); fi
    doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
    DFC=$((era * 146097 + doe - 719468))
}
weekday() { days_from_civil "$1" "$2" "$3"; WD=$(((DFC % 7 + 11) % 7)); }   # 0 = Sunday
days_in_month() {
    case $2 in
        1|3|5|7|8|10|12) DIM=31 ;; 4|6|9|11) DIM=30 ;;
        2) if (( ($1 % 4 == 0 && $1 % 100 != 0) || $1 % 400 == 0 )); then DIM=29; else DIM=28; fi ;;
    esac
}
DOW_NAMES=(Sun Mon Tue Wed Thu Fri Sat)
MON_NAMES=(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

# --- Time zones ----------------------------------------------------------------------------------------
# The machine's own zone: TZ when it names one, else the zoneinfo file /etc/localtime points at.
local_zone() {
    local z="${TZ:-}"
    z="${z#:}"
    if [[ -z "$z" ]]; then
        z="$(readlink /etc/localtime 2>/dev/null)"
        z="${z##*/zoneinfo/}"
    fi
    printf '%s' "$z"
}
zone_exists() {
    local d
    for d in /usr/share/zoneinfo /var/db/timezone/zoneinfo /usr/lib/zoneinfo; do [[ -f "$d/$1" ]] && return 0; done
    return 1
}

# --- Schedule parsing ----------------------------------------------------------------------------------
# parse_field <text> <lo> <hi> <kind>: one cron field into PF (sorted, space-separated numbers).
name_num() {   # kind text -> NN, or return 1
    local k="$1" t; t="$(lower "$2")"
    if [[ "$t" =~ ^[0-9]+$ ]]; then NN=$((10#$t)); return 0; fi
    local i names
    case "$k" in
        mon) names="jan feb mar apr may jun jul aug sep oct nov dec"; i=1 ;;
        dow) names="sun mon tue wed thu fri sat"; i=0 ;;
        *) return 1 ;;
    esac
    local n
    for n in $names; do [[ "$t" == "$n" ]] && { NN=$i; return 0; }; i=$((i + 1)); done
    return 1
}
parse_field() {
    local text="$1" lo="$2" hi="$3" kind="$4" part base step a b v
    local -a mark=() parts=()
    [[ -n "$text" ]] || { PERR="empty field"; return 1; }
    [[ "$text" != *,  && "$text" != ,* && "$text" != *,,* ]] || { PERR="empty list item in '$text'"; return 1; }
    IFS=, read -r -a parts <<<"$text"
    for part in "${parts[@]}"; do
        step=1 base="$part"
        if [[ "$part" == */* ]]; then
            base="${part%%/*}" step="${part#*/}"
            [[ "$step" =~ ^[0-9]+$ ]] && (( 10#$step >= 1 )) || { PERR="bad step in '$part'"; return 1; }
            step=$((10#$step))
        fi
        if [[ "$base" == '*' ]]; then a=$lo b=$hi
        elif [[ "$base" == *-* ]]; then
            name_num "$kind" "${base%%-*}" || { PERR="bad value in '$part'"; return 1; }; a=$NN
            name_num "$kind" "${base#*-}" || { PERR="bad value in '$part'"; return 1; }; b=$NN
        else
            name_num "$kind" "$base" || { PERR="bad value '$base'"; return 1; }; a=$NN
            if [[ "$part" == */* ]]; then b=$hi; else b=$a; fi
        fi
        (( a >= lo && b <= hi )) || { PERR="'$part' is outside $lo-$hi"; return 1; }
        (( a <= b )) || { PERR="range '$part' runs backwards"; return 1; }
        for ((v = a; v <= b; v += step)); do
            if [[ "$kind" == dow && $v -eq 7 ]]; then mark[0]=1; else mark[v]=1; fi
        done
    done
    PF=""
    [[ "$kind" == dow ]] && hi=6
    for ((v = lo; v <= hi; v++)); do [[ -n "${mark[v]:-}" ]] && PF+="$v "; done
    PF="${PF% }"
    return 0
}
full_set() {   # list lo hi
    local want="" v
    for ((v = $2; v <= $3; v++)); do want+="$v "; done
    [[ "$1" == "${want% }" ]]
}

# parse_schedule <text>: sets SK (cron, every, once) and its fields, or SERR and returns 1.
#   cron:  C_MIN C_HOUR C_DOM C_MON C_DOW (lists), C_OR (1 when day of month and day of week are both
#          restricted, so either may match, as cron has it), C_TEXT (the five fields as written)
#   every: E_N, E_U (m h d), E_SECS
#   once:  O_STR (YYYY-MM-DD HH:MM), O_Y O_M O_D O_H O_MI
#   Every kind: SZ, the zone the schedule is written in (empty for local time), from a CRON_TZ= prefix
#   or the task's timezone field (t_timezone); a zone that is the machine's own counts as local.
parse_schedule() {
    local s; s="$(trim "$1")"
    SERR="" SZ=""
    local re_tz='^CRON_TZ=([^[:space:]]+)[[:space:]]+(.*)$' z=""
    if [[ "$s" =~ $re_tz ]]; then z="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"; fi
    if [[ -n "${t_timezone:-}" ]]; then
        [[ -z "$z" || "$z" == "$t_timezone" ]] || { SERR="the schedule's CRON_TZ=$z and the timezone field ($t_timezone) differ"; return 1; }
        z="$t_timezone"
    fi
    if [[ -n "$z" ]]; then
        zone_exists "$z" || { SERR="time zone '$z' is not one this machine knows"; return 1; }
        [[ "$z" == "$(local_zone)" ]] || SZ="$z"
    fi
    local lc; lc="$(lower "$s")"
    case "$lc" in
        @yearly|@annually) s="0 0 1 1 *" ;; @monthly) s="0 0 1 * *" ;; @weekly) s="0 0 * * 0" ;;
        @daily|@midnight) s="0 0 * * *" ;; @hourly) s="0 * * * *" ;;
        @reboot) SERR="@reboot is not a time; this scheduler runs tasks at times"; return 1 ;;
        @*) SERR="unknown alias '$s'"; return 1 ;;
    esac
    local re_every='^every[[:space:]]+([0-9]+)[[:space:]]*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)$'
    local re_once='^once[[:space:]]+([0-9]{4})-([0-9]{2})-([0-9]{2})[[:space:]]+([0-9]{1,2}):([0-9]{2})$'
    if [[ "$lc" =~ $re_every ]]; then
        SK=every E_N=$((10#${BASH_REMATCH[1]})) E_U="${BASH_REMATCH[2]:0:1}"
        (( E_N >= 1 )) || { SERR="every needs a count of at least 1"; return 1; }
        case "$E_U" in m) E_SECS=$((E_N * 60)) ;; h) E_SECS=$((E_N * 3600)) ;; d) E_SECS=$((E_N * 86400)) ;; esac
        [[ -z "$SZ" ]] || { SERR="a time zone has no meaning for 'every'"; return 1; }
        return 0
    fi
    if [[ "$lc" =~ $re_once ]]; then
        SK=once O_Y=$((10#${BASH_REMATCH[1]})) O_M=$((10#${BASH_REMATCH[2]})) O_D=$((10#${BASH_REMATCH[3]}))
        O_H=$((10#${BASH_REMATCH[4]})) O_MI=$((10#${BASH_REMATCH[5]}))
        (( O_M >= 1 && O_M <= 12 )) || { SERR="month $O_M is not 1-12"; return 1; }
        days_in_month "$O_Y" "$O_M"
        (( O_D >= 1 && O_D <= DIM )) || { SERR="day $O_D is not in that month"; return 1; }
        (( O_H <= 23 && O_MI <= 59 )) || { SERR="time is not HH:MM"; return 1; }
        O_STR="$(printf '%04d-%s-%s %s:%s' "$O_Y" "$(pad2 "$O_M")" "$(pad2 "$O_D")" "$(pad2 "$O_H")" "$(pad2 "$O_MI")")"
        [[ -z "$SZ" ]] || { SERR="'once' takes this machine's local time, not $SZ"; return 1; }
        return 0
    fi
    local -a f=()
    read -r -a f <<<"$s"
    if [[ ${#f[@]} -ne 5 ]]; then
        SERR="'$1' is not five cron fields, an @alias, 'every <n>m|h|d' or 'once YYYY-MM-DD HH:MM'"; return 1
    fi
    SK=cron C_TEXT="${f[*]}"
    parse_field "${f[0]}" 0 59 min || { SERR="minute: $PERR"; return 1; }; C_MIN="$PF"
    parse_field "${f[1]}" 0 23 hour || { SERR="hour: $PERR"; return 1; }; C_HOUR="$PF"
    parse_field "${f[2]}" 1 31 dom || { SERR="day of month: $PERR"; return 1; }; C_DOM="$PF"
    parse_field "${f[3]}" 1 12 mon || { SERR="month: $PERR"; return 1; }; C_MON="$PF"
    parse_field "${f[4]}" 0 7 dow || { SERR="day of week: $PERR"; return 1; }; C_DOW="$PF"
    C_OR=0
    [[ "${f[2]}" != '*'* && "${f[4]}" != '*'* ]] && C_OR=1
    # A schedule that never fires (30 February) is refused rather than installed to wait forever.
    cron_next 2000 1 1 0 0 1
    [[ -n "$NX" ]] || { SERR="'$1' never fires (no matching date in 32 years)"; return 1; }
    return 0
}

first_ge() {   # value list -> FG (first member >= value), or return 1
    local x
    for x in $2; do (( x >= $1 )) && { FG=$x; return 0; }; done
    return 1
}
day_matches() {   # y m d, against the parsed cron day fields
    local dom_ok=1 dow_ok=1
    in_list "$3" "$C_DOM" || dom_ok=0
    weekday "$1" "$2" "$3"; in_list "$WD" "$C_DOW" || dow_ok=0
    if [[ $C_OR -eq 1 ]]; then (( dom_ok || dow_ok )); else (( dom_ok && dow_ok )); fi
}
# cron_next y m d h mi count: the next <count> fire times strictly after the given minute, into NX
# (one "YYYY-MM-DD HH:MM Dow" per line). Moves a month, a day or an hour at a time; never a minute.
cron_next() {
    local y=$1 mo=$2 d=$3 h=$4 mi=$(($5 + 1)) count=$6 found=0 limit=$(($1 + 28 + 4 * $6))
    NX=""
    while :; do
        if (( mi > 59 )); then mi=0; h=$((h + 1)); fi
        if (( h > 23 )); then h=0; mi=0; d=$((d + 1)); fi
        if (( mo > 12 )); then mo=1; y=$((y + 1)); d=1; h=0; mi=0; fi
        (( y > limit )) && break
        days_in_month "$y" "$mo"
        if (( d > DIM )); then d=1; h=0; mi=0; mo=$((mo + 1)); continue; fi
        if ! in_list "$mo" "$C_MON"; then mo=$((mo + 1)); d=1; h=0; mi=0; continue; fi
        if ! day_matches "$y" "$mo" "$d"; then d=$((d + 1)); h=0; mi=0; continue; fi
        if ! first_ge "$h" "$C_HOUR"; then d=$((d + 1)); h=0; mi=0; continue; fi
        if (( FG > h )); then h=$FG; mi=0; fi
        if ! first_ge "$mi" "$C_MIN"; then h=$((h + 1)); mi=0; continue; fi
        mi=$FG
        weekday "$y" "$mo" "$d"
        local line_
        printf -v line_ '%04d-%02d-%02d %02d:%02d %s' "$y" "$mo" "$d" "$h" "$mi" "${DOW_NAMES[WD]}"
        NX+="$line_"$'\n'
        found=$((found + 1))
        (( found >= count )) && break
        mi=$((mi + 1))
    done
    NX="${NX%$'\n'}"
}

last_le() {   # value list -> LL (last member <= value), or return 1
    local x found=1
    for x in $2; do (( x <= $1 )) && { LL=$x; found=0; }; done
    return $found
}
# cron_prev y m d h mi: the latest fire time at or before the given minute, into PV ("YYYY-MM-DD HH:MM"),
# or empty when there is none in the 32 years before. The mirror of cron_next.
cron_prev() {
    local y=$1 mo=$2 d=$3 h=$4 mi=$5 limit=$(($1 - 32))
    PV=""
    while :; do
        if (( mi < 0 )); then mi=59; h=$((h - 1)); fi
        if (( h < 0 )); then h=23; mi=59; d=$((d - 1)); fi
        if (( d < 1 )); then
            mo=$((mo - 1)); if (( mo < 1 )); then mo=12; y=$((y - 1)); fi
            days_in_month "$y" "$mo"; d=$DIM; h=23; mi=59
        fi
        (( y < limit )) && return 0
        if ! in_list "$mo" "$C_MON"; then d=0; continue; fi
        if ! day_matches "$y" "$mo" "$d"; then d=$((d - 1)); h=23; mi=59; continue; fi
        if ! last_le "$h" "$C_HOUR"; then d=$((d - 1)); h=23; mi=59; continue; fi
        if (( LL < h )); then h=$LL; mi=59; fi
        if ! last_le "$mi" "$C_MIN"; then h=$((h - 1)); mi=59; continue; fi
        PV="$(printf '%04d-%s-%s %s:%s' "$y" "$(pad2 "$mo")" "$(pad2 "$d")" "$(pad2 "$h")" "$(pad2 "$LL")")"
        return 0
    done
}
# due_time <epoch>: after parse_schedule, the fire time a run started then answers, into DUE (local
# "YYYY-MM-DD HH:MM") and DUE_E; both empty for every, or when there is none.
due_time() {
    local e="$1" p
    DUE="" DUE_E=""
    case "$SK" in
        once) DUE="$O_STR" ;;
        cron)
            if [[ -n "$SZ" ]]; then
                p="$(export TZ="$SZ"; epoch_fmt "$e" '%Y %m %d %H %M')"
            else
                p="$(epoch_fmt "$e" '%Y %m %d %H %M')"
            fi
            # shellcheck disable=SC2086
            set -- $p
            cron_prev "$((10#$1))" "$((10#$2))" "$((10#$3))" "$((10#$4))" "$((10#$5))"
            [[ -n "$PV" ]] || return 0
            if [[ -n "$SZ" ]]; then
                DUE_E="$(export TZ="$SZ"; local_to_epoch "$PV")"; DUE="$(epoch_fmt "$DUE_E" '%Y-%m-%d %H:%M')"
            else DUE="$PV"; fi ;;
        *) return 0 ;;
    esac
    [[ -n "$DUE_E" ]] || DUE_E="$(local_to_epoch "$DUE")"
}
# late_of <rundir>: "late 2h13m" when a scheduled run started more than five minutes after its due time.
late_of() {
    local de se l
    de="$(meta_get "$1" due_epoch)"; se="$(meta_get "$1" start_epoch)"
    [[ -n "$de" && -n "$se" ]] || return 0
    l=$((se - de))
    (( l > 300 )) || return 0
    if (( l >= 86400 )); then printf 'late %dd%dh' $((l / 86400)) $((l % 86400 / 3600))
    elif (( l >= 3600 )); then printf 'late %dh%02dm' $((l / 3600)) $((l % 3600 / 60))
    else printf 'late %dm' $((l / 60)); fi
}

# next_times <count> [<base epoch for every>]: after parse_schedule and now_parts, into NX.
next_times() {
    local count=$1 base="${2:-}" now t i
    NX=""
    case "$SK" in
        cron)
            if [[ -z "$SZ" ]]; then cron_next "$NOW_Y" "$NOW_M" "$NOW_D" "$NOW_H" "$NOW_MI" "$count"; return; fi
            # A schedule in another zone: the fire times are found in that zone's own calendar, then each
            # is turned into an instant and printed in local time, with the zone's own time beside it.
            local zn ze line out=""
            now="$(local_to_epoch "$NOW_STR")"
            zn="$(export TZ="$SZ"; epoch_fmt "$now" '%Y %m %d %H %M')"
            # shellcheck disable=SC2086
            set -- $zn
            cron_next "$((10#$1))" "$((10#$2))" "$((10#$3))" "$((10#$4))" "$((10#$5))" "$count"
            while IFS= read -r line; do
                [[ -n "$line" ]] || continue
                ze="$(export TZ="$SZ"; local_to_epoch "${line:0:16}")"
                out+="$(epoch_fmt "$ze" '%Y-%m-%d %H:%M %a') (${line:11:5} $SZ)"$'\n'
            done <<<"$NX"
            NX="${out%$'\n'}" ;;
        once) [[ "$O_STR" > "$NOW_STR" ]] && { weekday "$O_Y" "$O_M" "$O_D"; NX="$O_STR ${DOW_NAMES[WD]}"; } ;;
        every)
            now="$(local_to_epoch "$NOW_STR")"
            [[ -n "$base" ]] || base=$now
            t=$((base + E_SECS))
            (( t <= now )) && t=$((t + ((now - t) / E_SECS + 1) * E_SECS))
            for ((i = 0; i < count; i++)); do
                NX+="$(epoch_fmt "$t" '%Y-%m-%d %H:%M %a')"$'\n'
                t=$((t + E_SECS))
            done
            NX="${NX%$'\n'}" ;;
    esac
}
describe_schedule() {   # after parse_schedule
    case "$SK" in
        every) printf 'every %s%s' "$E_N" "$E_U" ;;
        once) printf 'once %s' "$O_STR" ;;
        cron) printf '%s%s' "${SZ:+CRON_TZ=$SZ }" "$C_TEXT" ;;
    esac
}
# day_words <y> <m> <d> (plain integers): "Fri 1 Jan" into DW. The weekday comes from the calendar
# arithmetic, not date, so the words are the same on BSD and GNU systems.
# day_words Y M D: "Mon 2 Nov" into DW, with the year after the month when it is not the current one.
day_words() {
    local now="${SCHEDULER_NOW:-$(date '+%Y-%m-%d %H:%M')}"
    weekday "$1" "$2" "$3"
    DW="${DOW_NAMES[WD]} $3 ${MON_NAMES[$(($2 - 1))]}"
    (( 10#${now:0:4} == $1 )) || DW+=" $1"
}
# describe_words: after a successful parse_schedule, the schedule in words into DWORDS ("daily 09:10",
# "weekdays 09:40", "once, Fri 1 Jan 2027 09:00"). A zone is named only when parse_schedule left SZ set,
# that is when it is not this machine's own. Returns 1 when no simple form fits, so the caller shows the
# schedule as written rather than inventing words for it.
describe_words() {
    local zone="" t
    [[ -z "$SZ" ]] || zone=" ($SZ)"
    case "$SK" in
        once)
            day_words "$O_Y" "$O_M" "$O_D"
            DWORDS="once, $DW $(printf '%02d:%02d' "$O_H" "$O_MI")"
            return 0 ;;
        cron)
            [[ "$C_MIN" != *" "* && "$C_HOUR" != *" "* ]] || return 1
            full_set "$C_DOM" 1 31 && full_set "$C_MON" 1 12 || return 1
            t="$(printf '%02d:%02d' "$C_HOUR" "$C_MIN")"
            if full_set "$C_DOW" 0 6; then DWORDS="daily $t$zone"
            elif [[ "$C_DOW" == "1 2 3 4 5" ]]; then DWORDS="weekdays $t$zone"
            else return 1; fi
            return 0 ;;
    esac
    return 1
}
# schedule_words <text>: the schedule as words, or the text as written when it is invalid or has no simple
# form. Called inside $(...), so its parse does not overwrite NX for a caller.
schedule_words() {
    if parse_schedule "$1" && describe_words; then printf '%s' "$DWORDS"; else printf '%s' "$1"; fi
}
# next_word "YYYY-MM-DD HH:MM ..." (a local fire time): "Mon 2 Nov 09:40" into NW.
next_word() {
    day_words "$((10#${1:0:4}))" "$((10#${1:5:2}))" "$((10#${1:8:2}))"
    NW="$DW ${1:11:5}"
}

# --- Task files ----------------------------------------------------------------------------------------
task_file() { printf '%s/%s.md' "$S_TASKS" "$1"; }
task_clear() { local f; for f in $FIELDS; do printf -v "t_$f" '%s' ""; done; T_EXTRA="" T_BODY=""; }
# task_load <file>: the front matter into t_<field>, unknown lines kept in T_EXTRA, the prompt in T_BODY.
task_load() {
    local file="$1" line st=0 key val body=""
    task_clear
    [[ -f "$file" ]] || { TERR="no task file at $file"; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        case $st in
            0) [[ "$line" == "---" ]] || { TERR="$file does not start with a --- front matter line"; return 1; }; st=1 ;;
            1)
                if [[ "$line" == "---" ]]; then st=2; continue; fi
                [[ -n "$(trim "$line")" ]] || continue
                key="${line%%:*}"
                if [[ "$line" == *:* ]] && in_list "$key" "$FIELDS"; then
                    val="$(trim "${line#*:}")"
                    printf -v "t_$key" '%s' "$val"
                else
                    T_EXTRA+="$line"$'\n'
                fi ;;
            2) body+="$line"$'\n' ;;
        esac
    done <"$file"
    [[ $st -eq 2 ]] || { TERR="$file has no closing --- line"; return 1; }
    body="${body#$'\n'}"
    while [[ "$body" == *$'\n' ]]; do body="${body%$'\n'}"; done
    T_BODY="$body"
    return 0
}
task_render() {
    local f v
    echo "---"
    for f in $FIELDS; do v="t_$f"; [[ -n "${!v}" ]] && printf '%s: %s\n' "$f" "${!v}"; done
    printf '%s' "$T_EXTRA"
    echo "---"
    echo
    printf '%s\n' "$T_BODY"
}
task_save() {   # file
    local tmp="$1.tmp.$$"
    mkdir -p "$(dirname "$1")"
    task_render >"$tmp" && mv "$tmp" "$1"
}
tv() { local v="t_$1" d="D_$1"; if [[ -n "${!v}" ]]; then printf '%s' "${!v}"; else printf '%s' "${!d:-}"; fi; }

# validate_task: the loaded task, into VERR (one problem per line); returns 1 when there are any.
validate_task() {
    VERR=""
    local v
    valid_name "$t_name" || VERR+="name '$t_name' is not lowercase letters, digits and hyphens (at most 63)"$'\n'
    if [[ -z "$t_schedule" ]]; then VERR+="schedule is empty"$'\n'
    elif ! parse_schedule "$t_schedule"; then VERR+="schedule: $SERR"$'\n'; fi
    in_list "$(tv status)" "active paused done" || VERR+="status '$t_status' is not active, paused or done"$'\n'
    if [[ -z "$t_cwd" ]]; then VERR+="cwd is empty"$'\n'
    elif [[ "$t_cwd" != /* ]]; then VERR+="cwd '$t_cwd' is not an absolute path"$'\n'; fi
    in_list "$(tv permission_mode)" "default acceptEdits auto bypassPermissions manual dontAsk plan" \
        || VERR+="permission_mode '$t_permission_mode' is not one claude accepts"$'\n'
    [[ -z "$t_effort" ]] || in_list "$t_effort" "low medium high xhigh max" || VERR+="effort '$t_effort' is not low, medium, high, xhigh or max"$'\n'
    [[ -z "$t_max_budget_usd" || "$t_max_budget_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]] || VERR+="max_budget_usd '$t_max_budget_usd' is not a number"$'\n'
    dur_secs "$(tv timeout)" || VERR+="timeout '$(tv timeout)' is not a duration (90s, 30m, 2h)"$'\n'
    dur_secs "$(tv timeout)" && (( DS < 5 )) && VERR+="timeout is under five seconds"$'\n'
    [[ "$(tv retries)" =~ ^[0-9]$ ]] || VERR+="retries '$t_retries' is not 0-9"$'\n'
    # retry_delay is one duration, or a list of them used in order (2m, 15m, 1h); retry_on names the
    # outcomes that earn another attempt.
    local rds rw ron
    rds="$(tv retry_delay)"; ron="$(tv retry_on)"
    [[ -n "${rds//[ ,]/}" ]] || VERR+="retry_delay is empty"$'\n'
    for rw in ${rds//,/ }; do dur_secs "$rw" || VERR+="retry_delay '$rds' has '$rw', not a duration (90s, 30m, 2h)"$'\n'; done
    for rw in ${ron//,/ }; do in_list "$rw" "all failed timeout denied verify" || VERR+="retry_on '$ron' has '$rw'; use all, or failed, timeout, denied, verify"$'\n'; done
    [[ "$(tv pause_after_failures)" =~ ^[0-9]+$ ]] || VERR+="pause_after_failures '$t_pause_after_failures' is not a whole number"$'\n'
    [[ "$(tv keep_runs)" =~ ^[0-9]+$ ]] && (( $(tv keep_runs) >= 1 )) || VERR+="keep_runs '$t_keep_runs' is not a whole number of at least 1"$'\n'
    local b
    for b in chrome awaits_reply; do
        v="t_$b"; [[ -z "${!v}" ]] || in_list "${!v}" "true false" || VERR+="$b '${!v}' is not true or false"$'\n'
    done
    dur_secs "$(tv reply_window)" || VERR+="reply_window '$(tv reply_window)' is not a duration (24h, 90m)"$'\n'
    in_list "$(tv notify_on)" "failure always never" || VERR+="notify_on '$t_notify_on' is not failure, always or never"$'\n'
    in_list "$(tv reach)" "desktop remote" || VERR+="reach '$t_reach' is not desktop or remote"$'\n'
    [[ -n "$T_BODY" ]] || VERR+="the prompt (the body under the front matter) is empty"$'\n'
    [[ -z "$T_EXTRA" ]] || VERR+="unknown front matter lines: $(printf '%s' "$T_EXTRA" | tr '\n' ';')"$'\n'
    VERR="${VERR%$'\n'}"
    [[ -z "$VERR" ]]
}
load_named() {   # name -> loaded task or die
    valid_name "$1" || die "'$1' is not a task name"
    task_load "$(task_file "$1")" || die "$TERR"
    [[ "$t_name" == "$1" ]] || die "$(task_file "$1") names itself '$t_name'; the name and the file name agree"
}
task_names() {
    local f
    for f in "$S_TASKS"/*.md; do [[ -f "$f" ]] && basename "$f" .md; done
}

# --- Backends ------------------------------------------------------------------------------------------
# The backend: SCHEDULER_BACKEND, else what the host has. Nothing found is an error rather than a
# quiet `none`, which would install tasks that never fire.
detect_backend() {
    if [[ -n "${SCHEDULER_BACKEND:-}" ]]; then
        in_list "$SCHEDULER_BACKEND" "launchd systemd cron none" || die "SCHEDULER_BACKEND '$SCHEDULER_BACKEND' is not launchd, systemd, cron or none"
        BACKEND="$SCHEDULER_BACKEND" BACKEND_WHY="SCHEDULER_BACKEND"; return 0
    fi
    case "$(uname -s)" in
        Darwin) BACKEND=launchd BACKEND_WHY="macOS"; return 0 ;;
        Linux)
            if have "$SYSTEMCTL" && "$SYSTEMCTL" --user show-environment >/dev/null 2>&1; then
                BACKEND=systemd BACKEND_WHY="a systemd user instance is running"; return 0
            fi ;;
    esac
    if have "$CRONTAB"; then BACKEND=cron BACKEND_WHY="crontab is on PATH"; return 0; fi
    BACKEND="" BACKEND_WHY="no launchd, systemd user instance or crontab found"
    return 1
}
need_backend() { [[ -n "${BACKEND:-}" ]] || detect_backend || die "$BACKEND_WHY; run 'schedule.sh doctor'"; }

label_of() { printf '%s.%s' "$LABEL_PREFIX" "$1"; }
unit_of() { printf '%s-%s' "$UNIT_PREFIX" "$1"; }
plist_path() { printf '%s/%s.plist' "$LA_DIR" "$(label_of "$1")"; }

# launchd: StartCalendarInterval dicts are the product of the restricted fields (a full field is left
# out, as launchd reads a missing key as "every"). The cron OR rule becomes two sets of dicts.
launchd_dicts() {   # after parse_schedule (cron) -> LD (dict XML lines) or LERR
    local sets="" combos c v k list count
    LD="" LERR=""
    local mins="" hours="" doms="" mons="" dows=""
    full_set "$C_MIN" 0 59 || mins="$C_MIN"
    full_set "$C_HOUR" 0 23 || hours="$C_HOUR"
    full_set "$C_MON" 1 12 || mons="$C_MON"
    local domfull=0 dowfull=0
    full_set "$C_DOM" 1 31 && domfull=1
    full_set "$C_DOW" 0 6 && dowfull=1
    if [[ $C_OR -eq 1 ]]; then
        if (( domfull || dowfull )); then sets="none"; else sets="dom dow"; fi
    else
        (( domfull )) || doms="$C_DOM"
        (( dowfull )) || dows="$C_DOW"
        sets="and"
    fi
    count=0
    local set n
    for set in $sets; do
        n=1
        for list in "$mins" "$hours" "$mons"; do [[ -n "$list" ]] && n=$((n * $(wc -w <<<"$list"))); done
        case "$set" in
            and) [[ -n "$doms" ]] && n=$((n * $(wc -w <<<"$doms"))); [[ -n "$dows" ]] && n=$((n * $(wc -w <<<"$dows"))) ;;
            dom) n=$((n * $(wc -w <<<"$C_DOM"))) ;;
            dow) n=$((n * $(wc -w <<<"$C_DOW"))) ;;
        esac
        count=$((count + n))
    done
    if (( count > LAUNCHD_MAX )); then
        LERR="'$C_TEXT' needs $count launchd calendar entries, more than $LAUNCHD_MAX; an 'every <n>m' schedule, or fewer listed values, renders in a few"
        return 1
    fi
    for set in $sets; do
        local d_list="" w_list=""
        case "$set" in and) d_list="$doms" w_list="$dows" ;; dom) d_list="$C_DOM" ;; dow) w_list="$C_DOW" ;; esac
        combos=("")
        for k in Minute Hour Day Weekday Month; do
            case $k in Minute) list="$mins" ;; Hour) list="$hours" ;; Day) list="$d_list" ;; Weekday) list="$w_list" ;; Month) list="$mons" ;; esac
            [[ -n "$list" ]] || continue
            local -a next=()
            for c in "${combos[@]}"; do
                for v in $list; do next+=("$c<key>$k</key><integer>$v</integer>"); done
            done
            combos=("${next[@]}")
        done
        for c in "${combos[@]}"; do LD+="		<dict>$c</dict>"$'\n'; done
    done
}

render_plist() {   # name (task loaded, schedule parsed)
    local name="$1"
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$(label_of "$name")</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$(xml "$RUNNER")</string>
		<string>exec</string>
		<string>$name</string>
	</array>
EOF
    case "$SK" in
        every) printf '\t<key>StartInterval</key>\n\t<integer>%s</integer>\n' "$E_SECS" ;;
        once)
            printf '\t<key>StartCalendarInterval</key>\n\t<dict><key>Minute</key><integer>%s</integer><key>Hour</key><integer>%s</integer><key>Day</key><integer>%s</integer><key>Month</key><integer>%s</integer></dict>\n' \
                "$O_MI" "$O_H" "$O_D" "$O_M" ;;
        cron)
            launchd_dicts || return 1
            printf '\t<key>StartCalendarInterval</key>\n\t<array>\n%s\t</array>\n' "$LD" ;;
    esac
    cat <<EOF
	<key>StandardOutPath</key>
	<string>$(xml "$S_DATA/logs/$name.out")</string>
	<key>StandardErrorPath</key>
	<string>$(xml "$S_DATA/logs/$name.out")</string>
</dict>
</plist>
EOF
}

sd_list() {   # list lo hi [names] -> comma list, or * when the set is full
    local list="$1" out="" v
    if full_set "$list" "$2" "$3"; then printf '*'; return; fi
    for v in $list; do
        if [[ -n "${4:-}" ]]; then out+="${DOW_NAMES[v]},"; else out+="$(pad2 "$v"),"; fi
    done
    printf '%s' "${out%,}"
}
oncalendar_lines() {   # after parse_schedule -> OnCalendar= lines
    local tm mon
    case "$SK" in
        once) printf 'OnCalendar=%s:00\n' "$O_STR"; return ;;
        every) return ;;
    esac
    tm="$(sd_list "$C_HOUR" 0 23):$(sd_list "$C_MIN" 0 59):00${SZ:+ $SZ}"
    mon="$(sd_list "$C_MON" 1 12)"
    local dom dow
    dom="$(sd_list "$C_DOM" 1 31)"; dow="$(sd_list "$C_DOW" 0 6 names)"
    if [[ $C_OR -eq 1 ]]; then
        if [[ "$dom" == '*' || "$dow" == '*' ]]; then printf 'OnCalendar=*-%s-* %s\n' "$mon" "$tm"
        else printf 'OnCalendar=*-%s-%s %s\nOnCalendar=%s *-%s-* %s\n' "$mon" "$dom" "$tm" "$dow" "$mon" "$tm"; fi
    else
        if [[ "$dow" == '*' ]]; then printf 'OnCalendar=*-%s-%s %s\n' "$mon" "$dom" "$tm"
        else printf 'OnCalendar=%s *-%s-%s %s\n' "$dow" "$mon" "$dom" "$tm"; fi
    fi
}
render_service() {
    cat <<EOF
[Unit]
Description=Scheduled Claude Code task $1 (agentic-workspace scheduler)

[Service]
Type=oneshot
ExecStart=/bin/bash "$RUNNER" exec $1
TimeoutStartSec=infinity
EOF
}
render_timer() {
    echo "[Unit]"
    echo "Description=Timer for the scheduled Claude Code task $1"
    echo
    echo "[Timer]"
    if [[ "$SK" == every ]]; then
        printf 'OnActiveSec=%s\nOnUnitActiveSec=%s\n' "$E_SECS" "$E_SECS"
    else
        oncalendar_lines
        echo "Persistent=true"
    fi
    # systemd lets a timer fire up to AccuracySec late (a minute by default), which would let an every-1m
    # task drift to two minutes and a 09:00 task to 09:01; to the second costs nothing at this scale.
    echo "AccuracySec=1s"
    echo "Unit=$(unit_of "$1").service"
    echo
    echo "[Install]"
    echo "WantedBy=timers.target"
}
cron_list() {   # list lo hi [keep] -> a cron field: * when full, unless keep
    if [[ "${4:-}" != keep ]] && full_set "$1" "$2" "$3"; then printf '*'; else printf '%s' "${1// /,}"; fi
}
# cron: the fields as explicit numbers (cron takes names only as single values). Under the OR rule a
# full day field stays a list, so cron still reads it as restricted. `every` fires on a coarser cron
# line and the runner skips until the interval has passed (cron has no "every 90 minutes").
cron_fields() {
    local mi ho dom dow
    case "$SK" in
        once) printf '%s %s %s %s *' "$O_MI" "$O_H" "$O_D" "$O_M" ;;
        every)
            local cm=0 ch=0
            [[ "$t_created" =~ ([0-9]{2}):([0-9]{2})$ ]] && { ch=$((10#${BASH_REMATCH[1]})); cm=$((10#${BASH_REMATCH[2]})); }
            case "$E_U" in m) printf '* * * * *' ;; h) printf '%s * * * *' "$cm" ;; d) printf '%s %s * * *' "$cm" "$ch" ;; esac ;;
        cron)
            mi="$(cron_list "$C_MIN" 0 59)"; ho="$(cron_list "$C_HOUR" 0 23)"
            if [[ $C_OR -eq 1 ]]; then dom="$(cron_list "$C_DOM" 1 31 keep)"; dow="$(cron_list "$C_DOW" 0 6 keep)"
            else dom="$(cron_list "$C_DOM" 1 31)"; dow="$(cron_list "$C_DOW" 0 6)"; fi
            printf '%s %s %s %s %s' "$mi" "$ho" "$dom" "$(cron_list "$C_MON" 1 12)" "$dow" ;;
    esac
}
render_cronline() {
    local cmd
    cmd="/bin/bash $(sq "$RUNNER") exec $1 >>$(sq "$S_DATA/logs/$1.out") 2>&1"
    printf '%s %s\n' "$(cron_fields)" "${cmd//%/\\%}"
}

# render_unit <name> <backend>: the unit text for a loaded task, or URERR.
render_unit() {
    URERR=""
    parse_schedule "$t_schedule" || { URERR="$SERR"; return 1; }
    if [[ -n "$SZ" && ( "$2" == launchd || "$2" == cron ) ]]; then
        URERR="$2 has no time zones, and this schedule is in $SZ while this machine is in $(local_zone); write it in local time, or use systemd"
        return 1
    fi
    case "$2" in
        launchd) render_plist "$1" || { URERR="$LERR"; return 1; } ;;
        systemd) printf '# %s.service\n' "$(unit_of "$1")"; render_service "$1"; printf '# %s.timer\n' "$(unit_of "$1")"; render_timer "$1" ;;
        cron|none) render_cronline "$1" ;;
    esac
}

cron_current() { "$CRONTAB" -l 2>/dev/null || true; }
cron_without_block() {
    awk -v b="$CRON_BEGIN" -v e="$CRON_END" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip'
}
# cron_apply: the managed block rebuilt from every active task; the person's other lines are kept
# as they were, and an empty block is removed rather than written.
cron_apply() (   # a subshell, since it loads every task and the caller's task stays loaded
    local cur rest block="" n
    cur="$(cron_current)"
    rest="$(printf '%s\n' "$cur" | cron_without_block)"
    for n in $(task_names); do
        task_load "$(task_file "$n")" || continue
        [[ "$(tv status)" == active ]] || continue
        parse_schedule "$t_schedule" || continue
        block+="$(render_cronline "$n")"$'\n'
    done
    {
        [[ -n "$rest" ]] && printf '%s\n' "$rest"
        if [[ -n "$block" ]]; then printf '%s\n%s%s\n' "$CRON_BEGIN" "$block" "$CRON_END"; fi
    } | "$CRONTAB" -
)

launchd_loaded() { "$LAUNCHCTL" print "gui/$UIDN/$(label_of "$1")" >/dev/null 2>&1; }
# unit_install <name>: the loaded task's unit written and loaded into the OS.
unit_install() {
    local name="$1" content p
    need_backend
    mkdir -p "$S_DATA/logs" "$S_DATA/state"
    case "$BACKEND" in
        launchd)
            content="$(render_unit "$name" launchd)" || { warn "$URERR"; return 1; }
            p="$(plist_path "$name")"
            mkdir -p "$LA_DIR"
            launchd_loaded "$name" && "$LAUNCHCTL" bootout "gui/$UIDN/$(label_of "$name")" >/dev/null 2>&1
            printf '%s\n' "$content" >"$p"
            if ! "$LAUNCHCTL" bootstrap "gui/$UIDN" "$p" >/dev/null 2>&1; then
                sleep 1   # a bootout can still be finishing; one retry covers it
                "$LAUNCHCTL" bootstrap "gui/$UIDN" "$p" >/dev/null 2>&1 || { warn "launchctl bootstrap refused $p"; return 1; }
            fi ;;
        systemd)
            parse_schedule "$t_schedule" || return 1
            mkdir -p "$SD_DIR"
            render_service "$name" >"$SD_DIR/$(unit_of "$name").service"
            render_timer "$name" >"$SD_DIR/$(unit_of "$name").timer"
            "$SYSTEMCTL" --user daemon-reload >/dev/null 2>&1
            "$SYSTEMCTL" --user enable "$(unit_of "$name").timer" >/dev/null 2>&1 || { warn "systemctl --user enable $(unit_of "$name").timer failed"; return 1; }
            "$SYSTEMCTL" --user restart "$(unit_of "$name").timer" >/dev/null 2>&1 || { warn "systemctl --user restart $(unit_of "$name").timer failed"; return 1; } ;;
        cron)
            parse_schedule "$t_schedule" || return 1
            cron_apply || { warn "crontab refused the managed block"; return 1; } ;;
        none)
            content="$(render_unit "$name" none)" || return 1
            mkdir -p "$S_DATA/units"
            printf '%s\n' "$content" >"$S_DATA/units/$name.cron" ;;
    esac
    epoch_now_stamp >"$S_DATA/state/$name.loaded"
    return 0
}
epoch_now_stamp() { now_epoch; }
# unit_remove <name>: the task's unit gone from the OS; nothing to remove is not an error.
unit_remove() {
    local name="$1"
    need_backend
    case "$BACKEND" in
        launchd)
            # The file goes first: when a run removes its own unit, bootout stops that run with it.
            rm -f "$(plist_path "$name")"
            launchd_loaded "$name" && "$LAUNCHCTL" bootout "gui/$UIDN/$(label_of "$name")" >/dev/null 2>&1 ;;
        systemd)
            if [[ -f "$SD_DIR/$(unit_of "$name").timer" ]]; then
                "$SYSTEMCTL" --user disable --now "$(unit_of "$name").timer" >/dev/null 2>&1
                rm -f "$SD_DIR/$(unit_of "$name").timer" "$SD_DIR/$(unit_of "$name").service"
                "$SYSTEMCTL" --user daemon-reload >/dev/null 2>&1
            fi ;;
        cron)
            cron_current | grep -qF " exec $name >>" && cron_apply_except "$name" ;;
        none) rm -f "$S_DATA/units/$name.cron" ;;
    esac
    rm -f "$S_DATA/state/$name.loaded"
    return 0
}
cron_apply_except() {   # the block rebuilt without one task, whatever its file says
    local cur rest block="" n
    cur="$(cron_current)"
    rest="$(printf '%s\n' "$cur" | cron_without_block)"
    block="$(printf '%s\n' "$cur" | awk -v b="$CRON_BEGIN" -v e="$CRON_END" '$0 == b { on = 1; next } $0 == e { on = 0; next } on' \
        | grep -vF " exec $1 >>")"
    {
        [[ -n "$rest" ]] && printf '%s\n' "$rest"
        if [[ -n "$block" ]]; then printf '%s\n%s\n%s\n' "$CRON_BEGIN" "$block" "$CRON_END"; fi
    } | "$CRONTAB" -
}
# unit_state <name>: for a loaded task, US is installed, not-loaded, differs, missing, absent (no unit,
# as a paused or done task should be) or stale (a unit for a task that is not active).
unit_state() {
    local name="$1" want=0 present=0 match=1 loaded=1 exp
    need_backend
    [[ "$(tv status)" == active ]] && want=1
    case "$BACKEND" in
        launchd)
            if [[ -f "$(plist_path "$name")" ]]; then
                present=1
                exp="$(render_unit "$name" launchd 2>/dev/null)"
                [[ "$exp" == "$(cat "$(plist_path "$name")")" ]] || match=0
                launchd_loaded "$name" || loaded=0
            fi ;;
        systemd)
            if [[ -f "$SD_DIR/$(unit_of "$name").timer" ]]; then
                present=1
                parse_schedule "$t_schedule" 2>/dev/null
                [[ "$(render_timer "$name")" == "$(cat "$SD_DIR/$(unit_of "$name").timer")" \
                    && "$(render_service "$name")" == "$(cat "$SD_DIR/$(unit_of "$name").service" 2>/dev/null)" ]] || match=0
                "$SYSTEMCTL" --user is-active "$(unit_of "$name").timer" >/dev/null 2>&1 || loaded=0
            fi ;;
        cron)
            local line
            line="$(cron_current | awk -v b="$CRON_BEGIN" -v e="$CRON_END" '$0 == b { on = 1; next } $0 == e { on = 0; next } on' | grep -F " exec $name >>")"
            if [[ -n "$line" ]]; then
                present=1
                [[ "$line" == "$(render_unit "$name" cron 2>/dev/null)" ]] || match=0
            fi ;;
        none)
            if [[ -f "$S_DATA/units/$name.cron" ]]; then
                present=1
                [[ "$(render_unit "$name" none 2>/dev/null)" == "$(cat "$S_DATA/units/$name.cron")" ]] || match=0
            fi ;;
    esac
    if (( want )); then
        if (( ! present )); then US=missing
        elif (( ! match )); then US=differs
        elif (( ! loaded )); then US=not-loaded
        else US=installed; fi
    else
        if (( present )); then US=stale; else US=absent; fi
    fi
}

# --- The runner's copy and environment -----------------------------------------------------------------
# refresh_runner: the copy the units call, and the environment it starts from. launchd and cron start
# jobs with a minimal PATH, so claude's absolute path and this session's PATH are recorded here.
refresh_runner() {
    local claude path
    need_backend
    mkdir -p "$S_DATA/runner" "$S_DATA/logs" "$S_DATA/state" "$S_DATA/runs" "$S_DATA/locks"
    if [[ "$SELF" != "$RUNNER" ]]; then
        cp "$SELF" "$RUNNER.tmp.$$" && chmod 755 "$RUNNER.tmp.$$" && mv "$RUNNER.tmp.$$" "$RUNNER"
        # The rules table goes with it: the runner reads its refusal patterns.
        local rf; rf="$(rules_file)"
        [[ -f "$rf" ]] && cp "$rf" "$S_DATA/runner/port-rules.tsv"
    fi
    claude="${SCHEDULER_CLAUDE:-$(command -v claude 2>/dev/null)}"
    if [[ -z "$claude" ]]; then
        claude="$(. "$S_DATA/env" 2>/dev/null; printf '%s' "${CLAUDE_BIN:-}")"
        [[ -n "$claude" ]] || warn "no claude on PATH; scheduled runs will fail until 'schedule.sh sync' runs where claude is"
    fi
    [[ -z "$claude" || "$claude" == /* ]] || claude="$(cd "$(dirname "$claude")" && pwd)/$(basename "$claude")"
    path="${claude:+$(dirname "$claude"):}$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    path="$(printf '%s' "$path" | tr ':' '\n' | awk 'NF && !seen[$0]++' | paste -sd: -)"
    {
        printf 'SCHEDULER_HOME=%q\n' "$S_HOME"
        printf 'SCHEDULER_TASKS_DIR=%q\n' "$S_TASKS"
        printf 'CLAUDE_BIN=%q\n' "$claude"
        printf 'PATH=%q\n' "$path"
        printf 'SCHEDULER_SYNCED_BACKEND=%q\n' "$BACKEND"
        printf 'SCHEDULER_SYNCED_AT=%q\n' "$(date '+%Y-%m-%d %H:%M')"
        local tv_
        for tv_ in $TOOL_VARS; do
            if [[ -n "${!tv_:-}" ]]; then printf '%s=%q\n' "$tv_" "${!tv_}"; fi
        done
    } >"$S_DATA/env.tmp.$$" && mv "$S_DATA/env.tmp.$$" "$S_DATA/env" \
        || die "could not write $S_DATA/env, which scheduled runs start from"
}

# --- Runs ----------------------------------------------------------------------------------------------
meta_get() { [[ -f "$1/meta" ]] && sed -n "s/^$2=//p" "$1/meta" | tail -n 1; }
runs_of() {   # oldest first; a second run in the same second is <id>-2, which sorts after <id> in C order
    local d
    for d in "$S_DATA/runs/$1"/*; do [[ -d "$d" ]] && printf '%s\n' "$d"; done | LC_ALL=C sort
}
last_run() { runs_of "$1" | tail -n 1; }
# run_status <dir>: a running run whose lock holder is gone reads as interrupted, and a waiting one past
# its reply window as expired.
run_status() {
    local st; st="$(meta_get "$1" status)"
    if [[ "$st" == waiting ]]; then
        local w e; w="$(meta_get "$1" reply_window_secs)"; e="$(meta_get "$1" end_epoch)"
        [[ -n "$w" && -n "$e" ]] && (( $(date +%s) - e > w )) && st=expired
    fi
    if [[ "$st" == running ]]; then
        local pid; pid="$(cat "$S_DATA/locks/$(basename "$(dirname "$1")")/pid" 2>/dev/null)"
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || st=interrupted
    fi
    printf '%s' "$st"
}
# status_text <dir>: run_status, with the attempts when a run took more than one:
# "ok after 2 attempts (1 failed: verify)".
status_text() {
    local st n f commas; st="$(run_status "$1")"; n="$(meta_get "$1" attempts)"; f="$(meta_get "$1" failed_attempts)"
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n > 1 )) && [[ -n "$f" ]]; then
        commas="${f//[^,]/}"
        st="$st after $n attempts ($(( ${#commas} + 1 )) failed: ${f//,/, })"
    fi
    printf '%s' "$st"
}
# stream_api_source <stream>: the init event's apiKeySource ("none" on a subscription login).
stream_api_source() {
    grep -m 1 '"subtype":"init"' "$1" 2>/dev/null | sed -nE 's/.*"apiKeySource":"([^"]*)".*/\1/p'
}
# stream_result <stream> <json>: the stream's result event, the last line of type result, to <json>,
# which the readers below take as the run's JSON output.
stream_result() {
    grep '"type":"result"' "$1" 2>/dev/null | tail -n 1 >"$2"
}
# billing_refusal: for the loaded task, why a run would be billed to an API key or a cloud account
# rather than the person's login, into BR (empty when it would not). Claude Code prefers a key to a
# login when it finds one, so the settings a run reads are checked for one: the user's, the managed
# ones and the task folder's project settings. Only presence is tested; no value is read or printed.
billing_refusal() {
    BR=""
    local v f cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" files=() root
    for v in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY; do
        [[ -n "${!v:-}" ]] && BR+="$v is set in the run's environment; "
    done
    files=("$cfg/settings.json")
    if [[ -n "${SCHEDULER_MANAGED_SETTINGS+set}" ]]; then
        local managed=(); IFS=: read -r -a managed <<<"$SCHEDULER_MANAGED_SETTINGS"; files+=(${managed[@]+"${managed[@]}"})
    else
        files+=("/Library/Application Support/ClaudeCode/managed-settings.json" "/etc/claude-code/managed-settings.json")
    fi
    if [[ -d "$t_cwd" ]]; then
        files+=("$t_cwd/.claude/settings.json" "$t_cwd/.claude/settings.local.json")
        root="$(git -C "$t_cwd" rev-parse --show-toplevel 2>/dev/null)"
        [[ -n "$root" && "$root" != "$t_cwd" ]] && files+=("$root/.claude/settings.json" "$root/.claude/settings.local.json")
    fi
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        if have jq; then
            jq -e 'type == "object" and has("apiKeyHelper")' "$f" >/dev/null 2>&1 && BR+="$f configures an apiKeyHelper; "
            jq -e '.env | objects | has("ANTHROPIC_API_KEY") or has("ANTHROPIC_AUTH_TOKEN") or has("CLAUDE_CODE_USE_BEDROCK") or has("CLAUDE_CODE_USE_VERTEX") or has("CLAUDE_CODE_USE_FOUNDRY")' "$f" >/dev/null 2>&1 \
                && BR+="$f sets an API key or a cloud provider in its env block; "
        else
            grep -q '"apiKeyHelper"' "$f" && BR+="$f configures an apiKeyHelper; "
            grep -qE '"(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|CLAUDE_CODE_USE_BEDROCK|CLAUDE_CODE_USE_VERTEX|CLAUDE_CODE_USE_FOUNDRY)"' "$f" \
                && BR+="$f names an API key or a cloud provider; "
        fi
    done
    BR="${BR%; }"
}
# sandbox_state: for the loaded task, whether Claude Code's sandbox applies in its folder, from the same
# settings files the billing check reads (user, managed, the task folder's project and local settings).
# SB_ON is yes or no; SB_DOMAINS the allowed network domains, joined; SB_FROM the files that enable it.
sandbox_state() {
    SB_ON=no SB_DOMAINS="" SB_FROM=""
    have jq || { SB_ON=unknown; return 0; }
    local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" files=() f root dom
    files=("$cfg/settings.json")
    if [[ -n "${SCHEDULER_MANAGED_SETTINGS+set}" ]]; then
        local managed=(); IFS=: read -r -a managed <<<"$SCHEDULER_MANAGED_SETTINGS"; files+=(${managed[@]+"${managed[@]}"})
    else
        files+=("/Library/Application Support/ClaudeCode/managed-settings.json" "/etc/claude-code/managed-settings.json")
    fi
    if [[ -d "$t_cwd" ]]; then
        root="$(git -C "$t_cwd" rev-parse --show-toplevel 2>/dev/null)"
        [[ -n "$root" && "$root" != "$t_cwd" ]] && files+=("$root/.claude/settings.json" "$root/.claude/settings.local.json")
        files+=("$t_cwd/.claude/settings.json" "$t_cwd/.claude/settings.local.json")
    fi
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        case "$(jq -r 'if (.sandbox | type) == "object" and (.sandbox | has("enabled")) then (.sandbox.enabled | tostring) else "" end' "$f" 2>/dev/null)" in
            true) SB_ON=yes SB_FROM+="${SB_FROM:+, }$f" ;;
            false) SB_ON=no SB_FROM="" ;;
        esac
        dom="$(jq -r '[.sandbox.network.allowedDomains[]? | tostring] | join(", ")' "$f" 2>/dev/null)"
        [[ -n "$dom" ]] && SB_DOMAINS+="${SB_DOMAINS:+, }$dom"
    done
}
sandbox_line() {   # one line for show and doctor
    sandbox_state
    case "$SB_ON" in
        yes) printf 'on (%s); network calls go only to: %s' "$SB_FROM" "${SB_DOMAINS:-no domains}" ;;
        no) printf 'off' ;;
        *) printf 'not read (no jq)' ;;
    esac
}
BILLING_VARS="ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY"

result_text() {   # attempt json -> the result text
    local f="$1"
    [[ -s "$f" ]] || return 0
    if have jq; then jq -r 'if type == "object" then (.result // "") else "" end' "$f" 2>/dev/null
    else sed -nE 's/.*"result":"(([^"\\]|\\.)*)".*/\1/p' "$f" | head -n 1 | sed 's/\\n/\
/g; s/\\"/"/g'; fi
}
# denials_of <attempt json>: the tool calls Claude Code refused in a run, as "Tool: input; Tool: input",
# or nothing. Without jq, a non-empty permission_denials list reads as "a tool was refused".
denials_of() {
    [[ -s "$1" ]] || return 0
    if have jq; then
        jq -r 'if type == "object" then [(.permission_denials // [])[] | "\(.tool_name): \((.tool_input.command // .tool_input.file_path // "") | tostring | .[0:80])"] | join("; ") else "" end' "$1" 2>/dev/null
    else
        grep -q '"permission_denials":\[{' "$1" && printf 'a tool was refused'
    fi
}
# denial_outcome <stream>: whether a run carried on after the tool calls Claude Code refused it.
# recovered: after the last refused call, the run made another tool call that was not refused, so it
# found another way and the refusal does not decide the run. ended: nothing after it, so the refusal is
# where the run stopped. none: nothing was refused. Without jq the answer is ended, the careful reading.
denial_outcome() {
    [[ -s "$1" ]] || { echo none; return; }
    have jq || { grep -q '"permission_denials":\[{' "$1" && echo ended || echo none; return; }
    jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .id] as $ids
        | ([.[] | select(.type == "result") | .permission_denials[]?.tool_use_id] | map(select(. != null))) as $den
        | if ($den | length) == 0 then "none"
          else ([$den[] | . as $d | $ids | index($d)] | map(select(. != null)) | max) as $last
            | if $last == null then "ended"
              elif ([$ids[($last + 1):][] | select(. as $x | ($den | index($x)) == null)] | length) > 0 then "recovered"
              else "ended" end
          end' "$1" 2>/dev/null || echo ended
}
denial_count() {   # result json -> how many calls were refused
    if have jq; then jq -r 'if type == "object" then ((.permission_denials // []) | length) else 0 end' "$1" 2>/dev/null || echo 0
    else grep -o '"tool_use_id"' "$1" 2>/dev/null | wc -l | tr -d ' '; fi
}
json_field() {   # file key -> a scalar from Claude's JSON
    local f="$1" k="$2"
    [[ -s "$f" ]] || return 0
    if have jq; then jq -r --arg k "$k" 'if type == "object" then (.[$k] // empty | tostring) else empty end' "$f" 2>/dev/null
    else sed -nE "s/.*\"$k\":(\"[^\"]*\"|[^,}]*).*/\1/p" "$f" | head -n 1 | tr -d '"'; fi
}
new_uuid() {
    if have uuidgen; then uuidgen | tr '[:upper:]' '[:lower:]'
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid
    else od -An -N16 -tx1 /dev/urandom | tr -d ' \n' | sed 's/^\(.\{8\}\)\(.\{4\}\).\(.\{3\}\).\(.\{3\}\)\(.\{12\}\)$/\1-\2-4\3-a\4-\5/'; fi
}

# run_with_timeout <secs> <out> <err> <in> <cmd...>: the command in its own process group, so a
# timeout stops claude and everything it started. macOS has no timeout(1). Returns 124 on a timeout.
# The shell reports a job it killed ("Terminated: 15") on stderr, so the waiting is done with stderr
# closed off; the command's own stderr goes to <err>.
run_with_timeout() { rwt_inner "$@" 2>/dev/null; }
# With RWT_BILLING_GUARD=1 the output is claude's stream: as soon as its init event names an API key
# source other than none (the subscription login), the run is stopped, returning 125, so it spends
# nothing on a key it was never meant to use. The first seconds are watched closely for that event.
rwt_inner() {
    local secs="$1" out="$2" err="$3" in="$4" pid waited=0 rc ticks=0 seen=0 src
    shift 4
    set -m
    ( exec "$@" <"$in" >"$out" 2>"$err" ) &
    pid=$!
    set +m
    while kill -0 "$pid" 2>/dev/null; do
        if [[ "${RWT_BILLING_GUARD:-}" == 1 && $seen -eq 0 ]] && grep -q '"subtype":"init"' "$out" 2>/dev/null; then
            seen=1
            src="$(stream_api_source "$out")"
            if [[ -n "$src" && "$src" != none ]]; then
                kill -TERM -- "-$pid" 2>/dev/null; sleep 1; kill -KILL -- "-$pid" 2>/dev/null
                { wait "$pid"; } 2>/dev/null
                return 125
            fi
        fi
        if (( ticks < 25 && seen == 0 )); then sleep 0.2; ticks=$((ticks + 1)); (( ticks % 5 == 0 )) && waited=$((waited + 1)); continue; fi
        if (( waited >= secs )); then
            kill -TERM -- "-$pid" 2>/dev/null
            local g=0
            while kill -0 "$pid" 2>/dev/null && (( g < 10 )); do sleep 1; g=$((g + 1)); done
            kill -KILL -- "-$pid" 2>/dev/null
            { wait "$pid"; } 2>/dev/null
            return 124
        fi
        sleep 1; waited=$((waited + 1))
    done
    { wait "$pid"; } 2>/dev/null; rc=$?
    return $rc
}

# notify_run <name> <status> <summary> <rundir>: a desktop notice and the task's notify command. A run
# awaiting a reply counts as needing the person, as a failure does.
notify_run() {
    local name="$1" st="$2" summary="$3" dir="$4" on resume
    on="$(tv notify_on)"
    case "$on" in never) return 0 ;; failure) [[ "$st" == ok ]] && return 0 ;; esac
    resume="$(resume_cmd "$dir")"
    # A waiting run's question is its whole final message, trimmed, for a notify script; the desktop
    # notification shows the start of it.
    local question="" title="Scheduled task $name: $st" msg="${summary:0:180}"
    [[ "$st" == waiting && -s "$dir/result.txt" ]] && question="$(trim "$(cat "$dir/result.txt")")"
    if [[ "$st" == waiting ]]; then
        title="Scheduled task $name is awaiting your reply"
        msg="${question//$'\n'/ }"; msg="${msg:0:180}"
        [[ -n "$msg" ]] || msg="schedule.sh reply $name '<your reply>'"
    fi
    if [[ "${SCHEDULER_NOTIFY_DESKTOP:-1}" != 0 ]]; then
        if have osascript; then
            osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$title" "$msg" >/dev/null 2>&1
        elif have notify-send; then
            notify-send "$title" "$msg" >/dev/null 2>&1
        fi
    fi
    if [[ -n "$t_notify" ]]; then
        : >"$dir/notify.err"
        SCHEDULER_TASK="$name" SCHEDULER_STATUS="$st" SCHEDULER_RUN="$(basename "$dir")" SCHEDULER_RUN_DIR="$dir" \
            SCHEDULER_SUMMARY="$msg" SCHEDULER_QUESTION="$question" SCHEDULER_RESUME="$resume" SCHEDULER_RESULT_FILE="$dir/result.txt" \
            run_with_timeout 60 "$dir/notify.out" "$dir/notify.err" /dev/null /bin/sh -c "$t_notify" \
            || printf 'notify command exited %s\n' "$?" >>"$dir/notify.err"
    fi
}

# write_result_to <rundir> replace|append: the run's final message to the task's result_to path, with
# {date} and {name} filled in; a relative path is taken from the task's folder. A reply appends.
write_result_to() {
    [[ -n "$t_result_to" ]] || return 0
    local p="$t_result_to" dir="$1" mode="$2"
    p="${p//\{date\}/$(date '+%Y-%m-%d')}"; p="${p//\{name\}/$t_name}"
    [[ "$p" == \~/* ]] && p="$HOME/${p#\~/}"
    [[ "$p" == /* ]] || p="$t_cwd/$p"
    mkdir -p "$(dirname "$p")" 2>/dev/null || { runner_log "$t_name: result_to folder for $p could not be made"; return 0; }
    if [[ "$mode" == append && -s "$p" ]]; then
        { printf '\n---\n\n'; cat "$dir/result.txt"; } >>"$p"   # the file already ends in a newline
    else
        cp "$dir/result.txt" "$p"
    fi
    printf 'result_to=%s\n' "$p" >>"$dir/meta"
}

runner_log() { mkdir -p "$S_DATA/logs"; printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$S_DATA/logs/runner.log"; }

# split_tools <list>: a tool list as claude takes it (comma or space separated) one tool a line, keeping
# a pattern whole: "Bash(git log:*)" holds a space inside its parentheses.
split_tools() {
    local s="$1" out="" cur="" depth=0 i c
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            "(") depth=$((depth + 1)); cur+="$c" ;;
            ")") depth=$((depth - 1)); cur+="$c" ;;
            " "|","|$'\t') if (( depth > 0 )); then cur+="$c"; else [[ -n "$cur" ]] && out+="$cur"$'\n'; cur=""; fi ;;
            *) cur+="$c" ;;
        esac
    done
    [[ -n "$cur" ]] && out+="$cur"$'\n'
    printf '%s' "$out"
}
# tools_prompt: for a task with a tool list, the lines appended to the run's system prompt that name its
# tools, so the run does not read one refusal as all of them being off. Nothing for a task with none.
tools_prompt() {
    [[ -n "$t_allowed_tools$t_disallowed_tools" ]] || return 0
    local l
    if [[ -n "$t_allowed_tools" ]]; then
        printf '\n\nThis run may use these tools, and anything else is refused without asking:\n'
        while IFS= read -r l; do [[ -n "$l" ]] && printf -- '- %s\n' "$l"; done < <(split_tools "$t_allowed_tools")
    fi
    if [[ -n "$t_disallowed_tools" ]]; then
        printf '\nThese are refused:\n'
        while IFS= read -r l; do [[ -n "$l" ]] && printf -- '- %s\n' "$l"; done < <(split_tools "$t_disallowed_tools")
    fi
    printf '\nA refused call refuses that call only; the tools listed above still work. Each Bash(...) pattern matches one command run on its own: no cd first, and no &&, ; or redirect.'
}
# task_args: the loaded task's settings as claude flags, into TA; a run and a reply to it share them.
task_args() {
    TA=(--append-system-prompt "$HEADLESS_PROMPT$(tools_prompt)" --permission-mode "${PERM_OVERRIDE:-$(tv permission_mode)}")
    [[ -n "$t_model" ]] && TA+=(--model "$t_model")
    [[ -n "$t_effort" ]] && TA+=(--effort "$t_effort")
    [[ -n "$t_fallback_model" ]] && TA+=(--fallback-model "$t_fallback_model")
    [[ -n "$t_allowed_tools" ]] && TA+=(--allowedTools "$t_allowed_tools")
    [[ -n "$t_disallowed_tools" ]] && TA+=(--disallowedTools "$t_disallowed_tools")
    [[ -n "$t_max_budget_usd" ]] && TA+=(--max-budget-usd "$t_max_budget_usd")
    [[ "$t_chrome" == true ]] && TA+=(--chrome)
    if [[ -n "$t_add_dirs" ]]; then
        local ad; local -a ads=()
        IFS=, read -r -a ads <<<"$t_add_dirs"
        for ad in "${ads[@]}"; do ad="$(trim "$ad")"; [[ -n "$ad" ]] && TA+=(--add-dir "$ad"); done
    fi
}

# set_status <file> <status> <reason>: rewrites the task file's status, keeping everything else.
set_status() {
    t_status="$2" t_paused_reason="$3"
    task_save "$1"
    task_event "$t_name" "$2"
}
# task_event <name> <status>: appends "<epoch><TAB><status><TAB><schedule>" to state/<name>.events, the
# record report reads to count only the fires due while a task was active, on the schedule it had then.
task_event() {
    mkdir -p "$S_DATA/state"
    printf '%s\t%s\t%s\n' "$(date +%s)" "$2" "$t_schedule" >>"$S_DATA/state/$1.events"
}

# cmd_exec <name> [--manual]: one run, as the OS starts it. It never asks anything and never waits for
# a person: everything it learns goes into the run folder, the task file or the runner log.
# reach_remote <name> <rundir> <session id> <reply window secs>: a waiting run of a task with reach: remote
# starts its session in the background with Remote Control on, so the person can answer it from a phone.
# The answer stops it (reach_stop), and so does the reply window ending: a timer, which may not outlive the
# runner under launchd, so an expiry stop is best effort. The run folder's reach file names the session.
reach_remote() {
    local name="$1" dir="$2" sid="$3" window="$4" out id
    if [[ -z "${CLAUDE_BIN:-}" || ! -x "$CLAUDE_BIN" ]]; then runner_log "$name: reach remote not started: no claude binary recorded"; return 0; fi
    out="$(cd "$t_cwd" && "$CLAUDE_BIN" --bg --resume "$sid" --remote-control "$name" </dev/null 2>&1)"
    printf '%s\n' "$out" >"$dir/reach.out"
    id="$(printf '%s\n' "$out" | awk '/^backgrounded/ { print $3; exit }')"
    if [[ -z "$id" ]]; then runner_log "$name: reach remote did not start, see reach.out"; return 0; fi
    printf 'reach=remote\nreach_id=%s\nreach_start=%s\n' "$id" "$(now_epoch)" >"$dir/reach"
    ( sleep "$window"; reach_stop "$dir" ) </dev/null >/dev/null 2>&1 &
}
# reach_stop <rundir>: stops the run's remote session, if it has one. Silent; a session already stopped is fine.
reach_stop() {
    local id; id="$(sed -n 's/^reach_id=//p' "$1/reach" 2>/dev/null | tail -n 1)"
    [[ -n "$id" ]] || return 0
    "${CLAUDE_BIN:-claude}" stop "$id" >/dev/null 2>&1 || true
}
# reach_sweep: ends the remote session of each reach run that no longer awaits a reply (answered, failed,
# expired past its reply_window, or interrupted). The answer and the timer already do this where they run;
# the sweep is the certain path for when they did not: a timer that died with the runner, or a stop that
# never ran. Each reach file is swept once: claude stop runs, and reach_swept records its time and exit
# code, so later sweeps skip it. Only sessions named in a run's reach file are stopped. Silent when nothing
# is left. Called from sync, from doctor and at every runner start. The claude binary comes from the
# runner environment file, because sync and doctor run without it.
reach_sweep() {
    local f dir id st cb rc
    cb="$(. "$S_DATA/env" 2>/dev/null; printf '%s' "${CLAUDE_BIN:-}")"
    for f in "$S_DATA"/runs/*/*/reach; do
        [[ -f "$f" ]] || continue
        grep -q '^reach_swept=' "$f" && continue
        dir="$(dirname "$f")"
        id="$(sed -n 's/^reach_id=//p' "$f" | tail -n 1)"
        st="$(run_status "$dir")"
        [[ -n "$id" && "$st" != waiting && -n "$cb" && -x "$cb" ]] || continue
        "$cb" stop "$id" >/dev/null 2>&1; rc=$?
        # Marked swept only when the stop succeeded. A failed stop stays unswept, so the next sync, doctor or
        # runner start tries again, and doctor keeps listing the session until it is really stopped.
        if (( rc == 0 )); then
            printf 'reach_swept=%s\nreach_stop_exit=%s\n' "$(now_epoch)" "$rc" >>"$f"
            runner_log "$(basename "$(dirname "$dir")"): remote session $id ended with its run ($st)"
        else
            runner_log "$(basename "$(dirname "$dir")"): remote session $id ($st) did not stop (exit $rc); it stays listed and is tried again"
        fi
    done
}
# reach_list: the remote sessions a sweep has not ended, one a line: the task and session, the run's state
# and the age from the reach file's start. Prints nothing when none is left.
reach_list() {
    local f dir id st start age_s age
    for f in "$S_DATA"/runs/*/*/reach; do
        [[ -f "$f" ]] || continue
        grep -q '^reach_swept=' "$f" && continue
        dir="$(dirname "$f")"
        id="$(sed -n 's/^reach_id=//p' "$f" | tail -n 1)"
        start="$(sed -n 's/^reach_start=//p' "$f" | tail -n 1)"
        st="$(run_status "$dir")"
        if [[ "$st" == waiting ]]; then st="awaiting a reply"; else st="run $st, not stopped"; fi
        age="age unknown"
        if [[ "$start" =~ ^[0-9]+$ ]]; then age_s=$(( $(now_epoch) - start )); (( age_s < 0 )) && age_s=0; age="age $(fmt_dur "$age_s")"; fi
        printf '%s %s: %s, %s\n' "$(basename "$(dirname "$dir")")" "$id" "$st" "$age"
    done
}

cmd_exec() {
    local name="$1" manual=0 trial="" file dir runid start start_e attempts=0 rc=1 st="" sid="" cost="0" a secs delay
    [[ "${2:-}" == --manual ]] && manual=1
    # A trial (schedule.sh port trial) runs once by hand, in plan mode unless it is live, and leaves the
    # task as it was: no failure count, no pause, no waiting, no result_to and no notification.
    if [[ "${2:-}" == --trial ]]; then manual=1 trial="${3:-plan}"; fi
    [[ -f "$S_DATA/env" ]] && . "$S_DATA/env"
    # shellcheck disable=SC2086
    unset $BILLING_VARS    # a run is billed to the person's login, whatever the env file or caller held
    S_HOME="${SCHEDULER_HOME:-$S_HOME}"; resolve_tasks
    set_tools
    BACKEND="${SCHEDULER_BACKEND:-${SCHEDULER_SYNCED_BACKEND:-}}"
    export PATH
    reach_sweep    # before the task runs: a remote session left by an earlier run is ended here, not later
    file="$(task_file "$name")"
    if ! task_load "$file"; then runner_log "$name: $TERR"; return 0; fi
    if ! validate_task; then runner_log "$name: not run, the task file has problems: ${VERR//$'\n'/; }"; return 0; fi
    now_parts
    if (( ! manual )); then
        [[ "$(tv status)" == active ]] || return 0
        if [[ "$SK" == once && "$NOW_STR" < "$O_STR" ]]; then return 0; fi
        # Under cron, an `every` task fires on a coarser line; skip until the interval has passed.
        if [[ "$SK" == every && "$BACKEND" == cron ]]; then
            local last_e now_e
            last_e="$(cat "$S_DATA/state/$name.fired" 2>/dev/null)"; now_e="$(now_epoch)"
            [[ -n "$last_e" ]] && (( now_e - last_e < E_SECS - 60 )) && return 0
            printf '%s\n' "$now_e" >"$S_DATA/state/$name.fired"
        fi
    fi
    mkdir -p "$S_DATA/runs/$name" "$S_DATA/locks" "$S_DATA/state"
    runid="$(date '+%Y%m%d-%H%M%S')"
    local n=2 base="$runid"
    while [[ -e "$S_DATA/runs/$name/$runid" ]]; do runid="$base-$n"; n=$((n + 1)); done
    dir="$S_DATA/runs/$name/$runid"
    mkdir -p "$dir"
    start="$(date '+%Y-%m-%d %H:%M:%S')"; start_e="$(date +%s)"
    local trig=schedule; (( manual )) && trig=manual; [[ -n "$trial" ]] && trig="trial-$trial"
    # due: the fire time this run answers, the latest at or before its start, so a run held back by a
    # sleeping machine shows as late. A manual run, or an every task, has none.
    local due="" due_e=""
    if (( ! manual )); then due_time "$start_e"; due="$DUE" due_e="$DUE_E"; fi
    # The lock: a folder holding the runner's pid. A holder that is gone leaves a lock that is taken.
    local lock="$S_DATA/locks/$name"
    if ! mkdir "$lock" 2>/dev/null; then
        local holder; holder="$(cat "$lock/pid" 2>/dev/null)"
        if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
            printf 'task=%s\nrun=%s\ntrigger=%s\nstart=%s\nstart_epoch=%s\nend=%s\nstatus=skipped\nreason=running\nattempts=0\n' \
                "$name" "$runid" "$trig" "$start" "$start_e" "$start" >"$dir/meta"
            [[ -n "$due" ]] && printf 'due=%s\ndue_epoch=%s\n' "$due" "$due_e" >>"$dir/meta"
            prune_runs "$name"
            return 0
        fi
        rm -rf "$lock"; mkdir "$lock" 2>/dev/null || { runner_log "$name: could not take the lock"; return 0; }
    fi
    printf '%s\n' "$$" >"$lock/pid"
    trap 'rm -rf "'"$lock"'"' EXIT
    cp "$file" "$dir/task.md"
    printf '%s\n' "$T_BODY" >"$dir/prompt.txt"
    printf 'task=%s\nrun=%s\ntrigger=%s\nstart=%s\nstart_epoch=%s\nstatus=running\ncwd=%s\n' \
        "$name" "$runid" "$trig" "$start" "$start_e" "$t_cwd" >"$dir/meta"

    dur_secs "$(tv timeout)"; secs=$DS
    # retry_delay: one duration grows with each attempt (2m, 4m, ...); a list is used in order, its last
    # entry repeated. The lock stays held across the waits, so a fire during them is skipped: running.
    local -a RD=()
    local rds rw ron
    rds="$(tv retry_delay)"; for rw in ${rds//,/ }; do dur_secs "$rw" && RD+=("$DS"); done
    # retry_on: the outcomes that earn another attempt. A refusal for billing never does.
    ron="$(tv retry_on)"; [[ "$ron" == *all* ]] && ron="failed timeout denied verify"
    local tries=$(( $(tv retries) + 1 ))
    [[ -n "$trial" ]] && tries=1
    local run_start att_start
    run_start="$(epoch_fmt "$start_e" '%Y%m%d-%H%M')"
    local -a args
    # A setting that would bill an API key refuses the run before claude is called.
    billing_refusal
    local auth="" refused="" fail_kinds="" first_kind="" kind outcome wait_s i
    local denied="" nref=0 netref="" vrc=""
    if [[ -n "$BR" ]]; then refused="api billing: $BR"; tries=0; st=refused; rc=125; fi
    for ((a = 1; a <= tries; a++)); do
        attempts=$a
        sid="$(new_uuid)"
        att_start="$(date '+%Y%m%d-%H%M')"
        args=(-p --output-format stream-json --verbose --session-id "$sid" --name "scheduled: $name $runid")
        PERM_OVERRIDE=""; [[ "$trial" == plan ]] && PERM_OVERRIDE=plan
        task_args; args+=(${TA[@]+"${TA[@]}"})
        printf 'attempt=%s session_id=%s\n' "$a" "$sid" >>"$dir/attempts"
        denied="" nref=0 netref="" vrc="" kind=""
        if [[ -z "${CLAUDE_BIN:-}" || ! -x "$CLAUDE_BIN" ]]; then
            printf 'no claude binary recorded (CLAUDE_BIN=%s); run schedule.sh sync where claude is on PATH\n' "${CLAUDE_BIN:-}" >"$dir/attempt-$a.stderr"
            : >"$dir/attempt-$a.json"; rc=127
        elif [[ ! -d "$t_cwd" ]]; then
            printf 'the task folder %s does not exist\n' "$t_cwd" >"$dir/attempt-$a.stderr"
            : >"$dir/attempt-$a.json"; rc=1
        else
            ( cd "$t_cwd" && export AW_HEADLESS_RUN=1 CLOSEOUT_DISABLED=1 RWT_BILLING_GUARD=1 && unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT \
                && run_with_timeout "$secs" "$dir/attempt-$a.stream" "$dir/attempt-$a.stderr" "$dir/prompt.txt" "$CLAUDE_BIN" "${args[@]}" )
            rc=$?
            stream_result "$dir/attempt-$a.stream" "$dir/attempt-$a.json"
            auth="$(stream_api_source "$dir/attempt-$a.stream")"
            printf 'attempt=%s auth=%s\n' "$a" "${auth:-unknown}" >>"$dir/attempts"
            if [[ $rc -eq 125 ]]; then
                refused="api billing: the run's init event named apiKeySource $auth, not the login"; st=refused
                printf 'attempt=%s outcome=refused\n' "$a" >>"$dir/attempts"
                break
            fi
        fi
        local c; c="$(json_field "$dir/attempt-$a.json" total_cost_usd)"
        [[ "$c" =~ ^[0-9.eE+-]+$ ]] && cost="$(awk -v a="$cost" -v b="$c" 'BEGIN { printf "%.4f", a + b }')"
        if [[ $rc -eq 0 && "$(json_field "$dir/attempt-$a.json" is_error)" != true ]]; then st=ok
        elif [[ $rc -eq 124 ]]; then st=timeout
        else st=failed; fi
        # Judged in full, per attempt. A refusal the run stopped at makes it denied; one it carried on
        # past is counted and named, and leaves it ok. A plan-mode look is not judged against the task.
        if [[ "$st" == ok && "$trial" != plan && -s "$dir/attempt-$a.stream" ]]; then
            local rid rsev rpat rmsg rfix rhit
            while IFS='	' read -r rid rsev rpat rmsg rfix; do
                [[ "$rsev" == refusal ]] || continue
                rhit="$(grep -o -i -E -- "$rpat" "$dir/attempt-$a.stream" 2>/dev/null | head -n 1)"
                [[ -n "$rhit" ]] && netref+="${netref:+; }$rid: $rhit ($(grep -c -i -E -- "$rpat" "$dir/attempt-$a.stream") line(s))"
            done <"$(rules_file)"
        fi
        if [[ "$st" == ok && "$trial" != plan ]]; then
            denied="$(denials_of "$dir/attempt-$a.json")"
            if [[ -n "$denied" ]]; then
                nref="$(denial_count "$dir/attempt-$a.json")"
                if [[ "$(denial_outcome "$dir/attempt-$a.stream")" != recovered ]]; then st=denied; fi
            fi
        fi
        if [[ -n "$netref" && "$st" == ok ]]; then
            nref=$((nref + 1)); denied="${denied:+$denied; }$netref"
        fi
        # verify: the task's own definition of done, a shell command run after a good run in its folder,
        # outside Claude, so its answer is deterministic. Non-zero makes this attempt failed: verify.
        # SCHEDULER_RUN_START is the run's clock; SCHEDULER_ATTEMPT_START is this attempt's, so a check
        # can match its own output rather than anything from earlier the same day.
        if [[ "$st" == ok && -n "$t_verify" && "$trial" != plan ]]; then
            ( cd "$t_cwd" 2>/dev/null && export SCHEDULER_TASK="$name" SCHEDULER_RUN="$runid" SCHEDULER_RUN_DIR="$dir" \
                SCHEDULER_RUN_START="$run_start" SCHEDULER_ATTEMPT="$a" SCHEDULER_ATTEMPT_START="$att_start" \
                && run_with_timeout 300 "$dir/verify-$a.out" "$dir/verify-$a.err" /dev/null /bin/sh -c "$t_verify" )
            vrc=$?
            if [[ $vrc -ne 0 ]]; then st=failed; kind=verify; fi
        fi
        outcome="$st"
        [[ "$kind" == verify ]] && outcome="failed: verify: exit $vrc"
        printf 'attempt=%s outcome=%s\n' "$a" "$outcome" >>"$dir/attempts"
        [[ "$st" == ok ]] && break
        kind="${kind:-$st}"
        fail_kinds+="${fail_kinds:+,}$kind"
        [[ -n "$first_kind" ]] || first_kind="$kind"
        # Retried while attempts remain and the outcome is one retry_on names. The wait after attempt a
        # is retry_delay's a-th entry, or a multiple of a single one.
        in_list "$kind" "$ron" && (( a < tries )) || break
        if (( ${#RD[@]} == 1 )); then wait_s=$((RD[0] * a))
        else i=$((a - 1)); (( i < ${#RD[@]} )) || i=$((${#RD[@]} - 1)); wait_s=${RD[$i]}; fi
        sleep "$wait_s"
    done
    (( attempts == 0 )) && : >"$dir/attempt-0.json"
    local end; end="$(date '+%Y-%m-%d %H:%M:%S')"
    # A task that waits for a person ends a good run as waiting; reply continues its session.
    local window=""
    if [[ "$st" == ok && "$t_awaits_reply" == true && -z "$trial" ]]; then
        st=waiting
        dur_secs "$(tv reply_window)"; window=$DS
        printf '%s\n' "$runid" >"$S_DATA/state/$name.waiting"
        [[ "$(tv reach)" == remote ]] && reach_remote "$name" "$dir" "$sid" "$window"
    fi
    result_text "$dir/attempt-$attempts.json" >"$dir/result.txt"
    local summary; summary="$(head -n 3 "$dir/result.txt" | tr '\n' ' ')"
    [[ -n "$summary" ]] || summary="$(tail -n 3 "$dir/attempt-$attempts.stderr" 2>/dev/null | tr '\n' ' ')"
    {
        printf 'task=%s\nrun=%s\ntrigger=%s\nstart=%s\nstart_epoch=%s\nend=%s\nend_epoch=%s\nstatus=%s\nattempts=%s\nexit=%s\nsession_id=%s\ncost_usd=%s\ncwd=%s\n' \
            "$name" "$runid" "$trig" "$start" "$start_e" "$end" "$(date +%s)" "$st" "$attempts" "$rc" "$sid" "$cost" "$t_cwd"
        [[ -n "$due" ]] && printf 'due=%s\ndue_epoch=%s\n' "$due" "$due_e"
        [[ -n "$window" ]] && printf 'reply_window_secs=%s\n' "$window"
        if [[ -n "$denied" && "$st" == denied ]]; then printf 'reason=refused: %s\n' "$denied"
        elif [[ -n "$denied" ]]; then printf 'refusals=%s\nrefused_calls=%s\n' "$nref" "$denied"; fi
        if [[ -n "$vrc" ]]; then
            printf 'verify_exit=%s\n' "$vrc"
            [[ $vrc -eq 0 ]] || printf 'reason=verify: exit %s: %s\n' "$vrc" "$(cat "$dir/verify-$attempts.err" "$dir/verify-$attempts.out" 2>/dev/null | tail -n 3 | tr '\n' ' ' | cut -c1-200)"
        fi
        [[ -n "$refused" ]] && printf 'reason=refused: %s\n' "$refused"
        [[ -n "$fail_kinds" ]] && printf 'failed_attempts=%s\nfirst_failure=%s\n' "$fail_kinds" "$first_kind"
        [[ -s "$dir/reach" ]] && cat "$dir/reach"
        printf 'auth=%s\n' "${auth:-unknown}"
    } >"$dir/meta"
    if [[ -n "$trial" ]]; then
        prune_runs "$name"; runner_log "$name: $runid trial ($trial) $st"
        rm -rf "$lock"; trap - EXIT
        return 0
    fi
    [[ "$st" == ok || "$st" == waiting ]] && write_result_to "$dir" replace

    # Consecutive failures, and the task pausing itself after pause_after_failures of them. The unit is
    # removed last, since on launchd removing it stops this job too.
    local fails=0 remove_unit=0 limit
    if [[ "$st" == ok || "$st" == waiting ]]; then
        printf '0\n' >"$S_DATA/state/$name.failures"
    else
        fails=$(( $(cat "$S_DATA/state/$name.failures" 2>/dev/null || echo 0) + 1 ))
        printf '%s\n' "$fails" >"$S_DATA/state/$name.failures"
    fi
    task_load "$file" || true    # the file may have been edited while the run was going
    limit="$(tv pause_after_failures)"
    if [[ "$SK" == once && "$(tv status)" == active && $manual -eq 0 ]]; then
        if [[ "$st" == ok || "$st" == waiting ]]; then set_status "$file" "done" ""
        else set_status "$file" paused "its one run, $runid, ended $st; give it a new date with edit, then resume"; fi
        remove_unit=1
    elif [[ "$st" != ok && "$st" != waiting && "$limit" -gt 0 && $fails -ge $limit && "$(tv status)" == active ]]; then
        local runs_word=runs; (( fails == 1 )) && runs_word=run
        set_status "$file" paused "paused itself after $fails failed $runs_word in a row, the last $runid; schedule.sh log $name shows why"
        remove_unit=1
        summary="paused after $fails failed $runs_word in a row. $summary"
    fi
    notify_run "$name" "$st" "$summary" "$dir"
    prune_runs "$name"
    runner_log "$name: $runid $st after $attempts attempt(s)"
    rm -rf "$lock"; trap - EXIT
    if (( remove_unit )) && [[ -n "$BACKEND" ]]; then unit_remove "$name"; fi
    return 0
}

# cmd_reply <name> [--run <id>] (<text> | --file <file|->): answers a run that is awaiting a reply by
# continuing its session headlessly (claude -p --resume) with the task's own flags. The answer and
# what came back are saved as a further step in the same run folder, and the run gets its final status.
cmd_reply() {
    [[ $# -ge 1 ]] || usage_die "reply needs a name"
    local name="$1" run="" text="" have_text=0; shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run) run="${2:-}"; shift 2 ;;
            --file)
                [[ $# -ge 2 ]] || usage_die "--file needs a file or -"
                if [[ "$2" == - ]]; then text="$(cat)"; else [[ -f "$2" ]] || die "no file $2"; text="$(cat "$2")"; fi
                have_text=1; shift 2 ;;
            --*) usage_die "unknown option $1" ;;
            *) text="$1"; have_text=1; shift ;;
        esac
    done
    (( have_text )) && [[ -n "$text" ]] || usage_die "reply needs the answer, as text or --file"
    load_named "$name"
    [[ -n "$run" ]] || run="$(cat "$S_DATA/state/$name.waiting" 2>/dev/null)"
    [[ -n "$run" ]] || die "no run of $name is awaiting a reply"
    local dir="$S_DATA/runs/$name/$run" st
    [[ -d "$dir" ]] || die "no run $run for $name"
    st="$(run_status "$dir")"
    case "$st" in
        waiting) ;;
        expired) die "run $run waited past its reply window ($(tv reply_window)) and has expired; 'schedule.sh run $name' starts a fresh one" ;;
        *) die "run $run is $st, not awaiting a reply" ;;
    esac
    [[ -f "$S_DATA/env" ]] && . "$S_DATA/env"
    local lock="$S_DATA/locks/$name"
    mkdir "$lock" 2>/dev/null || die "a run of $name is going now; reply once it ends"
    printf '%s\n' "$$" >"$lock/pid"
    trap 'rm -rf "'"$lock"'"' EXIT
    local sid n=1 rc secs
    sid="$(meta_get "$dir" session_id)"
    while [[ -e "$dir/reply-$n.json" ]]; do n=$((n + 1)); done
    printf '%s\n' "$text" >"$dir/reply-$n.txt"
    dur_secs "$(tv timeout)"; secs=$DS
    task_args
    # shellcheck disable=SC2086
    unset $BILLING_VARS
    billing_refusal
    local auth=""
    if [[ -n "$BR" ]]; then
        echo "refused: api billing: $BR" >"$dir/reply-$n.stderr"; : >"$dir/reply-$n.json"; rc=125
    elif [[ -z "${CLAUDE_BIN:-}" || ! -x "$CLAUDE_BIN" ]]; then
        echo "no claude binary recorded; run schedule.sh sync" >"$dir/reply-$n.stderr"; : >"$dir/reply-$n.json"; rc=127
    else
        ( cd "$t_cwd" && export AW_HEADLESS_RUN=1 CLOSEOUT_DISABLED=1 RWT_BILLING_GUARD=1 && unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT \
            && run_with_timeout "$secs" "$dir/reply-$n.stream" "$dir/reply-$n.stderr" "$dir/reply-$n.txt" \
                "$CLAUDE_BIN" -p --output-format stream-json --verbose --resume "$sid" ${TA[@]+"${TA[@]}"} )
        rc=$?
        stream_result "$dir/reply-$n.stream" "$dir/reply-$n.json"
        auth="$(stream_api_source "$dir/reply-$n.stream")"
    fi
    local c cost; cost="$(meta_get "$dir" cost_usd)"; c="$(json_field "$dir/reply-$n.json" total_cost_usd)"
    [[ "$c" =~ ^[0-9.eE+-]+$ ]] && cost="$(awk -v a="${cost:-0}" -v b="$c" 'BEGIN { printf "%.4f", a + b }')"
    if [[ $rc -eq 0 && "$(json_field "$dir/reply-$n.json" is_error)" != true ]]; then st=ok
    elif [[ $rc -eq 125 ]]; then st=refused; else
        if [[ $rc -eq 124 ]]; then st=timeout; else st=failed; fi; fi
    [[ $rc -eq 125 && -z "$BR" ]] && printf 'reason=refused: api billing: the init event named apiKeySource %s, not the login\n' "$auth" >>"$dir/meta"
    [[ -n "$BR" ]] && printf 'reason=refused: api billing: %s\n' "$BR" >>"$dir/meta"
    printf 'auth=%s\n' "${auth:-unknown}" >>"$dir/meta"
    local denied=""
    if [[ "$st" == ok ]]; then denied="$(denials_of "$dir/reply-$n.json")"; [[ -n "$denied" ]] && st=denied; fi
    [[ -n "$denied" ]] && printf 'reason=refused: %s\n' "$denied" >>"$dir/meta"
    result_text "$dir/reply-$n.json" >"$dir/result.txt"
    printf 'replied=%s\nreply_steps=%s\nend=%s\nend_epoch=%s\nstatus=%s\ncost_usd=%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$n" "$(date '+%Y-%m-%d %H:%M:%S')" "$(date +%s)" "$st" "$cost" >>"$dir/meta"
    rm -f "$S_DATA/state/$name.waiting"
    reach_stop "$dir"
    [[ "$st" == ok ]] && write_result_to "$dir" append
    rm -rf "$lock"; trap - EXIT
    [[ "$st" == ok ]] || notify_run "$name" "$st" "the reply to $run ended $st" "$dir"
    runner_log "$name: $run replied, $st"
    echo "Replied to $name's run $run: $st."
    if [[ -s "$dir/result.txt" ]]; then echo; sed 's/^/  /' "$dir/result.txt"; fi
    [[ "$st" == ok ]]
}

# cmd_record_answer <name> <run> [<transcript>]: called by the Stop hook when a session that a waiting run
# owns has just answered, in the desktop app or the terminal rather than with reply. The last thing the
# person wrote becomes the reply and the last thing Claude said the result; the run ends ok. Silent, and
# does nothing, unless the run is still waiting and no reply or run of the task is going on.
cmd_record_answer() {
    local name="${1:-}" run="${2:-}" tr="${3:-}"
    valid_name "$name" || return 0
    task_load "$(task_file "$name")" || return 0
    local dir="$S_DATA/runs/$name/$run"
    [[ -n "$run" && -d "$dir" && "$(run_status "$dir")" == waiting ]] || return 0
    local holder; holder="$(cat "$S_DATA/locks/$name/pid" 2>/dev/null)"
    if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then return 0; fi
    local n=1 answer="" result=""
    while [[ -e "$dir/reply-$n.txt" ]]; do n=$((n + 1)); done
    if have jq && [[ -s "$tr" ]]; then
        answer="$(jq -rs '[.[] | select(.type == "user") | .message.content
            | if type == "string" then . else [.[]? | select(.type == "text") | .text] | join("\n") end
            | select(. != "")] | last // empty' "$tr" 2>/dev/null)"
        result="$(jq -rs '[.[] | select(.type == "assistant") | [.message.content[]? | select(.type == "text") | .text]
            | join("\n") | select(. != "")] | last // empty' "$tr" 2>/dev/null)"
    fi
    # Without jq the transcript is named, not read: the answer is there, the record is not.
    [[ -n "$answer" ]] || answer="(answered in the session; its transcript is $tr)"
    printf '%s\n' "$answer" >"$dir/reply-$n.txt"
    printf '%s\n' "$result" >"$dir/result.txt"
    printf '{"type":"result","is_error":false,"result":%s}\n' "$(json_str "$result")" >"$dir/reply-$n.json"
    printf 'replied=%s\nreply_steps=%s\nreply_via=session\nend=%s\nend_epoch=%s\nstatus=ok\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$n" "$(date '+%Y-%m-%d %H:%M:%S')" "$(date +%s)" >>"$dir/meta"
    rm -f "$S_DATA/state/$name.waiting"
    reach_stop "$dir"
    write_result_to "$dir" append
    runner_log "$name: $run answered in its session"
}

prune_runs() {   # name: keep the newest keep_runs run folders
    local keep total
    keep="$(tv keep_runs)"; [[ "$keep" =~ ^[0-9]+$ ]] || keep=$D_keep_runs
    total="$(runs_of "$1" | wc -l | tr -d ' ')"
    (( total > keep )) || return 0
    runs_of "$1" | head -n $((total - keep)) | while IFS= read -r d; do rm -rf "$d"; done
}

# --- Commands ------------------------------------------------------------------------------------------
usage() {
    cat <<'EOF'
schedule.sh: scheduled Claude Code tasks on this machine, in the host's own scheduler (launchd,
systemd user timers or cron). A task is one Markdown file; the OS unit is rendered from it.

Usage:
  schedule.sh create <name> --schedule <when> --cwd <dir> (--prompt <text> | --prompt-file <file|->)
                     [--<field> <value>]... [--dry-run]
  schedule.sh create --file <task.md> [--dry-run]
  schedule.sh edit <name> [--<field> <value>]... [--unset <field>]... [--prompt ... | --prompt-file ...]
                     [--dry-run]                 with no changes and a terminal, opens $EDITOR
  schedule.sh list [--json]
  schedule.sh show <name> [--json]
  schedule.sh pause <name> [--reason <text>]
  schedule.sh resume <name>
  schedule.sh run <name> [--wait]                run now, whatever the schedule or status
  schedule.sh delete <name>                      the file moves to tasks/.trash/
  schedule.sh runs [<name>] [--since 'YYYY-MM-DD HH:MM'] [--limit <n>] [--json]   (alias: history)
  schedule.sh log <name> [<run>|last]
  schedule.sh report [--since 'YYYY-MM-DD HH:MM'] [--until ...] [--json]   due fires, runs, misses; 7 days
  schedule.sh reply <name> [--run <id>] (<text> | --file <file|->)   answer a run awaiting a reply
  schedule.sh next <name|when> [--count <n>] [--from 'YYYY-MM-DD HH:MM']
  schedule.sh unit <name> [--backend launchd|systemd|cron|none]
  schedule.sh sync                               render every unit again from the files
  schedule.sh home [<dir> [--move]]              the tasks folder, and moving it (a folder you version)
  schedule.sh doctor [<name>]                    a task's connectors are checked against claude mcp list
  schedule.sh keepalive install|remove|status    WSL2: keep the distro running so timers fire
  schedule.sh port start|status|check|ack|trial|activate|cloud-paused|rollback|skip|done   move tasks from a
                                                 cloud scheduler, a step at a time ('port help')
  schedule.sh exec <name> [--manual]             the runner, as the OS calls it
  schedule.sh parse [--describe] <when>          how a schedule reads (cron fields expanded); --describe in words
  schedule.sh prev <when> [--at 'YYYY-MM-DD HH:MM']   the latest fire time at or before then

When:
  five-field cron (lists, ranges, steps, month and day names; when day of month and day of week are
  both restricted, either matching fires it, as in cron), @hourly @daily @weekly @monthly @yearly,
  'every <n>m|h|d', or 'once YYYY-MM-DD HH:MM'. Local time; a cron schedule may start with
  CRON_TZ=<zone> (systemd only, unless it is this machine's zone).

Fields (--<field> with hyphens or underscores):
  description, schedule, cwd, model, effort, fallback_model, permission_mode (default dontAsk),
  allowed_tools, disallowed_tools, add_dirs (comma-separated), max_budget_usd, timeout (30m),
  retries (1), retry_delay (2m, growing per attempt; or a list, 2m 15m 1h, used in order),
  retry_on (all: failed, timeout, denied, verify; or a list of those), pause_after_failures (3; 0 never),
  notify (a shell command run after a run), notify_on (failure | always | never), keep_runs (30),
  timezone, chrome (true: --chrome), requires (connector names, for doctor), awaits_reply (true: a
  good run ends awaiting a reply), reply_window (24h), reach (desktop: answer in the app or the terminal;
  remote: a waiting run also starts a Remote Control session, so it can be answered from a phone),
  result_to (a path; {date} and {name} filled)

Files:
  tasks   the folder 'schedule.sh home' names (default ~/.config/agentic-workspace-kit/scheduler/tasks/)
  state   ${SCHEDULER_DATA:-~/.local/state/agentic-workspace-kit/scheduler}/
EOF
}

# apply_flags: --<field> value, --unset field, --prompt, --prompt-file into the loaded task; CHANGED
# counts what was set. Unknown flags are refused.
apply_flags() {
    CHANGED=0 DRY=0 PROMPT_SET=0
    local k v
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY=1; shift; continue ;;
            --prompt) [[ $# -ge 2 ]] || usage_die "--prompt needs text"; T_BODY="$2"; PROMPT_SET=1; CHANGED=$((CHANGED + 1)); shift 2; continue ;;
            --prompt-file)
                [[ $# -ge 2 ]] || usage_die "--prompt-file needs a file or -"
                if [[ "$2" == - ]]; then T_BODY="$(cat)"; else [[ -f "$2" ]] || die "no prompt file $2"; T_BODY="$(cat "$2")"; fi
                PROMPT_SET=1; CHANGED=$((CHANGED + 1)); shift 2; continue ;;
            --unset)
                [[ $# -ge 2 ]] || usage_die "--unset needs a field"
                k="${2//-/_}"; in_list "$k" "$SETTABLE" || usage_die "'$2' is not a field that can be unset"
                [[ "$k" == schedule || "$k" == cwd ]] && usage_die "$k cannot be unset"
                printf -v "t_$k" '%s' ""; CHANGED=$((CHANGED + 1)); shift 2; continue ;;
            --*)
                k="${1#--}"; k="${k//-/_}"
                in_list "$k" "$SETTABLE" || usage_die "unknown option $1"
                [[ $# -ge 2 ]] || usage_die "$1 needs a value"
                v="$2"
                [[ "$v" != *$'\n'* ]] || usage_die "$1: a value is one line"
                if [[ "$k" == cwd ]]; then
                    [[ -d "$v" ]] || die "cwd $v is not a folder"
                    v="$(cd "$v" && pwd)"
                fi
                printf -v "t_$k" '%s' "$(trim "$v")"; CHANGED=$((CHANGED + 1)); shift 2 ;;
            *) usage_die "unexpected argument '$1'" ;;
        esac
    done
}

show_preview() {   # the task file, then its next fire times
    task_render
    parse_schedule "$t_schedule" && now_parts && next_times 3
    echo
    if [[ -n "$NX" ]]; then echo "Next fire times:"; printf '%s\n' "$NX" | sed 's/^/  /'
    else echo "Next fire times: none"; fi
}

cmd_create() {
    local name="" from=""
    task_clear
    if [[ "${1:-}" == --file ]]; then
        [[ $# -ge 2 ]] || usage_die "--file needs a task file"
        from="$2"; shift 2
        task_load "$from" || die "$TERR"
        name="$t_name"
    else
        [[ $# -ge 1 && "$1" != --* ]] || usage_die "create needs a name"
        name="$1"; shift
        t_name="$name"
    fi
    apply_flags "$@"
    valid_name "$name" || die "'$name' is not a task name: lowercase letters, digits and hyphens"
    [[ -e "$(task_file "$name")" ]] && die "a task called $name exists; edit it, or delete it first"
    [[ -n "$t_cwd" ]] || die "--cwd is needed: the folder the run starts in"
    [[ -d "$t_cwd" ]] && t_cwd="$(cd "$t_cwd" && pwd)"
    local f d v
    for f in status permission_mode timeout retries retry_delay retry_on pause_after_failures notify_on keep_runs; do
        d="D_$f" v="t_$f"; [[ -n "${!v}" ]] || printf -v "t_$f" '%s' "${!d}"
    done
    t_status=active t_paused_reason=""
    [[ -n "$t_created" ]] || t_created="$(date '+%Y-%m-%d %H:%M')"
    validate_task || die "$(printf 'the task is not valid:\n%s' "$VERR" | sed '2,$s/^/  /')"
    [[ -d "$t_cwd" ]] || die "cwd $t_cwd is not a folder"
    now_parts
    if [[ "$SK" == once && ! "$O_STR" > "$NOW_STR" ]]; then die "once $O_STR has already passed"; fi
    need_backend
    render_unit "$name" "$BACKEND" >/dev/null || die "$URERR"
    if [[ $DRY -eq 1 ]]; then
        echo "Would write $(task_file "$name"), with a $BACKEND unit:"; echo
        show_preview; return 0
    fi
    mkdir -p "$S_TASKS"
    task_save "$(task_file "$name")"
    refresh_runner
    task_event "$name" active
    unit_install "$name" || die "the task file is written, but its $BACKEND unit is not installed; 'schedule.sh doctor' says more"
    echo "Created $name: $(task_file "$name"), $BACKEND unit installed."
    now_parts; next_times 3
    [[ -n "$NX" ]] && { echo "Next fire times:"; printf '%s\n' "$NX" | sed 's/^/  /'; }
}

cmd_edit() {
    [[ $# -ge 1 ]] || usage_die "edit needs a name"
    local name="$1"; shift
    load_named "$name"
    local file; file="$(task_file "$name")"
    apply_flags "$@"
    if [[ $CHANGED -eq 0 ]]; then
        [[ -t 0 && -t 1 ]] || usage_die "nothing to change: give --<field> <value>, --unset or --prompt (with a terminal, edit alone opens \$EDITOR)"
        local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/schedule-$name.XXXXXX")"
        cp "$file" "$tmp"
        "${EDITOR:-vi}" "$tmp"
        task_load "$tmp" || { rm -f "$tmp"; die "$TERR"; }
        rm -f "$tmp"
        [[ "$t_name" == "$name" ]] || die "the name cannot change in an edit; create the new task and delete this one"
    fi
    [[ -n "$t_cwd" && -d "$t_cwd" ]] || die "cwd $t_cwd is not a folder"
    validate_task || die "$(printf 'the edit leaves the task invalid; nothing written:\n%s' "$VERR" | sed '2,$s/^/  /')"
    need_backend
    render_unit "$name" "$BACKEND" >/dev/null || die "$URERR"
    if [[ $DRY -eq 1 ]]; then echo "Would write $file:"; echo; show_preview; return 0; fi
    task_save "$file"
    task_event "$name" "$(tv status)"
    refresh_runner
    if [[ "$(tv status)" == active ]]; then
        unit_install "$name" || die "the file is written, but its $BACKEND unit is not installed"
        echo "Edited $name; $BACKEND unit rendered again."
    else
        echo "Edited $name ($(tv status); no unit installed)."
    fi
}

cmd_pause() {
    [[ $# -ge 1 ]] || usage_die "pause needs a name"
    local name="$1" reason=""; shift
    [[ "${1:-}" == --reason ]] && reason="${2:-}"
    load_named "$name"
    [[ "$(tv status)" == "done" ]] && die "$name is done; it has nothing left to pause"
    [[ -n "$reason" ]] || reason="paused by hand on $(date '+%Y-%m-%d %H:%M')"
    set_status "$(task_file "$name")" paused "$reason"
    unit_remove "$name"
    echo "Paused $name; its $BACKEND unit is removed."
}

cmd_resume() {
    [[ $# -ge 1 ]] || usage_die "resume needs a name"
    local name="$1"
    load_named "$name"
    validate_task || die "$(printf 'the task file has problems; fix them with edit first:\n%s' "$VERR")"
    now_parts
    if [[ "$SK" == once && ! "$O_STR" > "$NOW_STR" ]]; then
        die "$name was for once $O_STR, which has passed; give it a new date with edit --schedule, then resume"
    fi
    set_status "$(task_file "$name")" active ""
    printf '0\n' >"$S_DATA/state/$name.failures" 2>/dev/null || true
    refresh_runner
    unit_install "$name" || die "$name is active in its file, but its unit is not installed"
    echo "Resumed $name; $BACKEND unit installed."
    next_times 3; [[ -n "$NX" ]] && { echo "Next fire times:"; printf '%s\n' "$NX" | sed 's/^/  /'; }
}

cmd_delete() {
    [[ $# -ge 1 ]] || usage_die "delete needs a name"
    local name="$1"
    valid_name "$name" || die "'$name' is not a task name"
    local file; file="$(task_file "$name")"
    [[ -f "$file" ]] || die "no task called $name"
    task_load "$file" || true
    unit_remove "$name"
    task_event "$name" deleted
    mkdir -p "$S_TASKS/.trash"
    local dest; dest="$S_TASKS/.trash/$name-$(date '+%Y%m%d-%H%M%S').md"
    mv "$file" "$dest"
    rm -f "$S_DATA/state/$name.failures" "$S_DATA/state/$name.fired"
    echo "Deleted $name: unit removed, file moved to $dest. Its runs stay in $S_DATA/runs/$name/."
}

cmd_run() {
    [[ $# -ge 1 ]] || usage_die "run needs a name"
    local name="$1" wait=0
    [[ "${2:-}" == --wait ]] && wait=1
    load_named "$name"
    refresh_runner
    # The run starts from a clean environment, as the OS would start it, so a run begun from inside a
    # Claude Code session is not a child of that session.
    local -a envv=(env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-${USER:-}}" TMPDIR="${TMPDIR:-/tmp}"
                   SCHEDULER_HOME="$S_HOME" SCHEDULER_TASKS_DIR="$S_TASKS" SCHEDULER_DATA="$S_DATA")
    [[ -n "${SCHEDULER_NOTIFY_DESKTOP:-}" ]] && envv+=(SCHEDULER_NOTIFY_DESKTOP="$SCHEDULER_NOTIFY_DESKTOP")
    [[ -n "${SCHEDULER_BACKEND:-}" ]] && envv+=(SCHEDULER_BACKEND="$SCHEDULER_BACKEND")
    if (( wait )); then
        "${envv[@]}" /bin/bash "$RUNNER" exec "$name" --manual
        local d; d="$(last_run "$name")"
        echo "Run $(basename "$d"): $(run_status "$d"), $(meta_get "$d" attempts) attempt(s). schedule.sh log $name shows it."
    else
        set -m
        ( trap '' HUP; exec "${envv[@]}" /bin/bash "$RUNNER" exec "$name" --manual ) </dev/null >/dev/null 2>&1 &
        set +m
        echo "Started $name in the background. 'schedule.sh runs $name' lists it; 'schedule.sh log $name' shows it once it ends."
    fi
}

next_for_task() {   # count: after the task is loaded
    local base=""
    parse_schedule "$t_schedule" || { NX=""; return; }
    now_parts
    if [[ "$SK" == every ]]; then
        local lr loaded
        lr="$(last_run "$t_name")"; [[ -n "$lr" ]] && base="$(meta_get "$lr" start_epoch)"
        loaded="$(cat "$S_DATA/state/$t_name.loaded" 2>/dev/null)"
        [[ -n "$loaded" && ( -z "$base" || "$loaded" -gt "$base" ) ]] && base="$loaded"
    fi
    next_times "$1" "$base"
}

cmd_list() {
    local json=0 n rows_w="" rows="" row
    [[ "${1:-}" == --json ]] && json=1
    # Tasks with a run awaiting a reply come first: they are the ones that need the person.
    for n in $(task_names); do
        local st sched sched_w nxt="" nxt_w="" last="" lr="" lst="" wait=""
        if ! task_load "$(task_file "$n")"; then
            (( json )) || rows+="$(printf '%-24s %-7s %s' "$n" "?" "$TERR")"$'\n'
            continue
        fi
        st="$(tv status)"; sched="$t_schedule"; sched_w="$(schedule_words "$sched")"
        if [[ "$st" == active ]]; then
            next_for_task 1; nxt="${NX:0:16}"
            [[ -n "$nxt" ]] && { next_word "$nxt"; nxt_w="$NW"; }
        fi
        lr="$(last_run "$n")"
        if [[ -n "$lr" ]]; then lst="$(run_status "$lr")"; last="$lst $(meta_get "$lr" start | cut -c1-16)"; fi
        local w; w="$(cat "$S_DATA/state/$n.waiting" 2>/dev/null)"
        [[ -n "$w" && "$(run_status "$S_DATA/runs/$n/$w")" == waiting ]] && wait="$w"
        if (( json )); then
            row="$(printf '{"name":%s,"status":%s,"schedule":%s,"next":%s,"last_status":%s,"last_start":%s,"waiting":%s,"description":%s,"schedule_words":%s,"next_words":%s}' \
                "$(json_str "$n")" "$(json_str "$st")" "$(json_str "$sched")" "$(json_str "$nxt")" \
                "$(json_str "$lst")" "$(json_str "$( [[ -n "$lr" ]] && meta_get "$lr" start)")" "$(json_str "$wait")" "$(json_str "$t_description")" \
                "$(json_str "$sched_w")" "$(json_str "$nxt_w")")"
        else
            [[ -n "$wait" ]] && last="awaiting a reply since $(meta_get "$S_DATA/runs/$n/$wait" end | cut -c1-16)"
            row="$(printf '%-24s %-7s %-21s %-30s %s' "$n" "$st" "${nxt_w:--}" "${last:--}" "$sched_w")"
        fi
        if [[ -n "$wait" ]]; then rows_w+="$row"$'\n'; else rows+="$row"$'\n'; fi
    done
    if (( json )); then
        printf '[%s]\n' "$(printf '%s%s' "$rows_w" "$rows" | sed '/^$/d' | paste -sd, -)"
    else
        printf '%-24s %-7s %-21s %-30s %s\n' NAME STATUS NEXT LAST SCHEDULE
        printf '%s%s' "$rows_w" "$rows"
    fi
}

# resume_cmd <rundir>: the command that opens the run's session in the desktop app, which Robert has
# checked answers a waiting run there. resume_cmd_term is the terminal form, for a person at the Mac
# who prefers it.
resume_cmd() {
    local sid cwd
    sid="$(meta_get "$1" session_id)"; cwd="$(meta_get "$1" cwd)"
    [[ -n "$sid" ]] && printf 'cd %s && claude --desktop --resume %s' "$(sq "$cwd")" "$sid"
}
resume_cmd_term() {
    local sid cwd
    sid="$(meta_get "$1" session_id)"; cwd="$(meta_get "$1" cwd)"
    [[ -n "$sid" ]] && printf 'cd %s && claude --resume %s' "$(sq "$cwd")" "$sid"
}

cmd_show() {
    [[ $# -ge 1 ]] || usage_die "show needs a name"
    local name="$1" json=0
    [[ "${2:-}" == --json ]] && json=1
    load_named "$name"
    need_backend
    unit_state "$name"
    local valid=1; validate_task || valid=0
    NX=""; [[ "$(tv status)" == active ]] && next_for_task 5
    local lr; lr="$(last_run "$name")"
    if (( json )); then
        local f v first=1
        printf '{"name":%s,"file":%s,"backend":%s,"unit":%s,"valid":%s,"problems":%s,"fields":{' \
            "$(json_str "$name")" "$(json_str "$(task_file "$name")")" "$(json_str "$BACKEND")" "$(json_str "$US")" \
            "$( ((valid)) && echo true || echo false)" "$(json_str "$VERR")"
        for f in $FIELDS; do
            v="$(tv "$f")"; [[ -n "$v" ]] || continue
            (( first )) || printf ','; first=0
            printf '%s:%s' "$(json_str "$f")" "$(json_str "$v")"
        done
        printf '},"prompt":%s,"next":[' "$(json_str "$T_BODY")"
        first=1
        while IFS= read -r v; do [[ -n "$v" ]] || continue; (( first )) || printf ','; first=0; printf '%s' "$(json_str "$v")"; done <<<"$NX"
        printf '],"last_run":'
        if [[ -n "$lr" ]]; then
            printf '{"run":%s,"status":%s,"late":%s,"due":%s,"start":%s,"end":%s,"attempts":%s,"cost_usd":%s,"session_id":%s,"resume":%s}' \
                "$(json_str "$(basename "$lr")")" "$(json_str "$(run_status "$lr")")" "$(json_str "$(late_of "$lr")")" \
                "$(json_str "$(meta_get "$lr" due)")" "$(json_str "$(meta_get "$lr" start)")" \
                "$(json_str "$(meta_get "$lr" end)")" "$(json_str "$(meta_get "$lr" attempts)")" "$(json_str "$(meta_get "$lr" cost_usd)")" \
                "$(json_str "$(meta_get "$lr" session_id)")" "$(json_str "$(resume_cmd "$lr")")"
        else printf 'null'; fi
        printf '}\n'
        return 0
    fi
    echo "Task $name  ($(task_file "$name"))"
    git_dirty "$(task_file "$name")" && echo "  Git: $GIT_MARK."
    local cl; cl="$(credential_lines "$(task_file "$name")")"
    [[ -n "$cl" ]] && echo "  Warning: $cl look like a credential; keep it in a file the prompt points to."
    local w; w="$(cat "$S_DATA/state/$name.waiting" 2>/dev/null)"
    if [[ -n "$w" && "$(run_status "$S_DATA/runs/$name/$w")" == waiting ]]; then
        echo
        echo "Awaiting a reply: run $w, since $(meta_get "$S_DATA/runs/$name/$w" end). Answer it with"
        echo "  schedule.sh reply $name '<your reply>'"
        echo "or open the session: $(resume_cmd "$S_DATA/runs/$name/$w")"
    fi
    echo
    local f v
    for f in $FIELDS; do
        v="$(tv "$f")"
        [[ "$f" == reply_window && "$t_awaits_reply" != true ]] && continue
        [[ -n "$v" && "$f" != name ]] && printf '  %-21s %s\n' "$f" "$v"
    done
    (( valid )) || printf '\n  Problems:\n%s\n' "$(printf '%s\n' "$VERR" | sed 's/^/    /')"
    echo
    echo "Prompt:"
    printf '%s\n' "$T_BODY" | sed 's/^/  /'
    echo
    local ustr
    case "$US" in
        installed) ustr="installed and matching the file" ;;
        not-loaded) ustr="written and matching the file, but not loaded in $BACKEND; 'schedule.sh sync' loads it" ;;
        differs) ustr="installed, but it differs from the file; 'schedule.sh sync' renders it again" ;;
        missing) ustr="missing, so it will not fire; 'schedule.sh sync' installs it" ;;
        absent) ustr="none, as a $(tv status) task has none" ;;
        stale) ustr="still installed although the task is $(tv status); 'schedule.sh sync' removes it" ;;
    esac
    echo "Unit ($BACKEND): $ustr"
    billing_refusal
    [[ -n "$BR" ]] && echo "Billing: runs are refused, since they would bill an API key, not the login: $BR"
    echo "Sandbox: $(sandbox_line)"
    if [[ -n "$NX" && "$(tv status)" == active ]]; then
        [[ "$SK" == every ]] && echo "Next fire times (about, counted from the last run or load):" || echo "Next fire times:"
        printf '%s\n' "$NX" | sed 's/^/  /'
    fi
    echo
    if [[ -n "$lr" ]]; then
        local lt; lt="$(late_of "$lr")"
        local rfs; rfs="$(meta_get "$lr" refusals)"
        echo "Last run $(basename "$lr"): $(status_text "$lr")${rfs:+ ($rfs refused)}${lt:+, $lt}, started $(meta_get "$lr" start), est. \$$(meta_get "$lr" cost_usd)"
        local rc; rc="$(resume_cmd "$lr")"; [[ -n "$rc" ]] && echo "  Open it: $rc"
        rc="$(resume_cmd_term "$lr")"; [[ -n "$rc" ]] && echo "  Or in the terminal: $rc"
        echo "  Its log: schedule.sh log $name"
    else
        echo "No runs yet."
    fi
}

cmd_runs() {
    local name="" since="" limit=20 json=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since) since="${2:-}"; shift 2 ;;
            --limit) limit="${2:-}"; shift 2 ;;
            --json) json=1; shift ;;
            --*) usage_die "unknown option $1" ;;
            *) name="$1"; shift ;;
        esac
    done
    [[ "$limit" =~ ^[0-9]+$ ]] || usage_die "--limit needs a number"
    local -a dirs=()
    local d n
    if [[ -n "$name" ]]; then
        valid_name "$name" || die "'$name' is not a task name"
        while IFS= read -r d; do [[ -n "$d" ]] && dirs+=("$d"); done < <(runs_of "$name")
    else
        for n in "$S_DATA/runs"/*/; do
            [[ -d "$n" ]] || continue
            while IFS= read -r d; do [[ -n "$d" ]] && dirs+=("$d"); done < <(runs_of "$(basename "$n")")
        done
    fi
    # newest first, by start time
    local sorted
    sorted="$(for d in ${dirs[@]+"${dirs[@]}"}; do printf '%s\t%s\n' "$(meta_get "$d" start)" "$d"; done | sort -r | \
        awk -F'\t' -v s="$since" 's == "" || $1 >= s' | head -n "$limit" | cut -f2)"
    local first=1
    if (( json )); then printf '['; else printf '%-24s %-19s %-9s %-24s %-8s %-8s %s\n' TASK RUN TRIGGER STATUS ATTEMPTS DURATION EST-COST; fi
    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        local se ee dur="" st
        se="$(meta_get "$d" start_epoch)"; ee="$(meta_get "$d" end_epoch)"
        [[ -n "$se" && -n "$ee" ]] && dur="$((ee - se))s"
        st="$(run_status "$d")"
        if (( json )); then
            (( first )) || printf ','; first=0
            printf '{"task":%s,"run":%s,"trigger":%s,"status":%s,"late":%s,"due":%s,"start":%s,"end":%s,"attempts":%s,"cost_usd":%s,"session_id":%s}' \
                "$(json_str "$(meta_get "$d" task)")" "$(json_str "$(basename "$d")")" "$(json_str "$(meta_get "$d" trigger)")" \
                "$(json_str "$st")" "$(json_str "$(late_of "$d")")" "$(json_str "$(meta_get "$d" due)")" "$(json_str "$(meta_get "$d" start)")" "$(json_str "$(meta_get "$d" end)")" \
                "$(json_str "$(meta_get "$d" attempts)")" "$(json_str "$(meta_get "$d" cost_usd)")" "$(json_str "$(meta_get "$d" session_id)")"
        else
            local reason lt rf; st="$(status_text "$d")"; reason="$(meta_get "$d" reason)"; lt="$(late_of "$d")"; rf="$(meta_get "$d" refusals)"
            [[ -n "$rf" ]] && st="$st ($rf refused)"
            [[ -n "$lt" ]] && reason="${reason:+$reason, }$lt"
            local cu; cu="$(meta_get "$d" cost_usd)"
            printf '%-24s %-19s %-9s %-24s %-8s %-8s %s\n' "$(meta_get "$d" task)" "$(basename "$d")" "$(meta_get "$d" trigger)" \
                "$st${reason:+: $reason}" "$(meta_get "$d" attempts)" "${dur:--}" "${cu:+est. \$$cu}"
        fi
    done <<<"$sorted"
    if (( json )); then printf ']\n'; fi
}

# --- report: the evidence for a review of a window ----------------------------------------------------
fmt_dur() {   # seconds -> 2h13m, 45m, 3d4h
    local l="$1"
    if (( l >= 86400 )); then printf '%dd%dh' $((l / 86400)) $((l % 86400 / 3600))
    elif (( l >= 3600 )); then printf '%dh%02dm' $((l / 3600)) $((l % 3600 / 60))
    else printf '%dm' $((l / 60)); fi
}
# fires_between <from> <to>: after parse_schedule, the fire times f with from <= f < to, both local
# "YYYY-MM-DD HH:MM" strings, into FB (one a line). They sort as text, so they compare as text.
fires_between() {
    local from="$1" to="$2" line last="" fe
    FB=""
    fe="$(local_to_epoch "$from")"; fe=$((fe - 60))
    SCHEDULER_NOW="$(epoch_fmt "$fe" '%Y-%m-%d %H:%M')" now_parts
    while :; do
        next_times 500
        [[ -n "$NX" ]] || break
        while IFS= read -r line; do
            line="${line:0:16}"
            [[ "$line" < "$to" ]] || { last=""; break 2; }
            [[ "$line" < "$from" ]] || FB+="$line"$'\n'
            last="$line"
        done <<<"$NX"
        [[ "$SK" == once || -z "$last" ]] && break
        SCHEDULER_NOW="$last" now_parts
    done
    FB="${FB%$'\n'}"
}
# cmd_report [--since T] [--until T] [--json]: per task, the fires due in the window while it was active
# (from its event log: the status and schedule at each change), the scheduled runs that started and
# how they ended, the late ones, and each due fire with no run. Every figure is given out of its whole,
# with the window. The default window is the last seven days.
cmd_report() {
    local json=0 since="" until=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since) since="${2:-}"; shift 2 ;;
            --until) until="${2:-}"; shift 2 ;;
            --json) json=1; shift ;;
            *) usage_die "unknown option $1" ;;
        esac
    done
    local now_e se ue
    # SCHEDULER_NOW pins the clock, half a minute into the minute it names, so a check can be exact.
    if [[ -n "${SCHEDULER_NOW:-}" ]]; then now_e=$(( $(local_to_epoch "$SCHEDULER_NOW") + 30 )); else now_e="$(date +%s)"; fi
    # Capped at now, the window's end takes in this second, so a run that has just started counts.
    if [[ -n "$until" ]]; then ue="$(local_to_epoch "$until")" || die "--until is not YYYY-MM-DD HH:MM"; else ue=$((now_e + 1)); fi
    (( ue > now_e + 1 )) && ue=$((now_e + 1))
    if [[ -n "$since" ]]; then se="$(local_to_epoch "$since")" || die "--since is not YYYY-MM-DD HH:MM"; else se=$((ue - 7 * 86400)); fi
    (( se < ue )) || die "--since comes after --until"
    since="$(epoch_fmt "$se" '%Y-%m-%d %H:%M')"; until="$(epoch_fmt "$ue" '%Y-%m-%d %H:%M')"
    local names n f
    names="$( { task_names; for f in "$S_DATA/runs"/*/; do [[ -d "$f" ]] && basename "$f"; done
               for f in "$S_DATA/state"/*.events; do [[ -f "$f" ]] && basename "$f" .events; done; } | sort -u)"
    local T_retried=0 T_recovered=0 T_withref=0 T_refused=0 T_pending=0 T_missedn=0 T_due=0 T_ran=0 T_ok=0 T_failed=0 T_timeout=0 T_denied=0 T_waiting=0 T_expired=0 T_skipped=0 T_late=0 T_maxlate=0 T_manual=0
    local rows="" jrows="" misses="" jmiss=""
    for n in $names; do
        # The active segments, from the event log; a task with none counts from its creation.
        local segs="" ev_e ev_s ev_sch prev_e="" prev_s="" prev_sch=""
        if [[ -f "$S_DATA/state/$n.events" ]]; then
            while IFS=$'\t' read -r ev_e ev_s ev_sch; do
                [[ -n "$prev_e" && "$prev_s" == active ]] && segs+="$prev_e|$ev_e|$prev_sch"$'\n'
                prev_e="$ev_e" prev_s="$ev_s" prev_sch="$ev_sch"
            done <"$S_DATA/state/$n.events"
            [[ "$prev_s" == active ]] && segs+="$prev_e|$ue|$prev_sch"$'\n'
        elif task_load "$(task_file "$n")" 2>/dev/null && [[ "$(tv status)" == active ]]; then
            local ce; ce="$(local_to_epoch "$t_created" 2>/dev/null)"; [[ -n "$ce" ]] || ce=$se
            segs="$ce|$ue|$t_schedule"$'\n'
        fi
        local due=0 every_due=0 fires="" a b sch
        while IFS='|' read -r a b sch; do
            [[ -n "$a" ]] || continue
            (( a < se )) && a=$se; (( b > ue )) && b=$ue
            (( a < b )) || continue
            t_timezone=""
            parse_schedule "$sch" || continue
            if [[ "$SK" == every ]]; then
                every_due=$((every_due + (b - a) / E_SECS))
            else
                # A fire at minute m is due when the task was active at m:00, so both ends round up to
                # the next whole minute: created at 13:49:03, the 13:49 fire was not its.
                fires_between "$(epoch_fmt $((a + 59)) '%Y-%m-%d %H:%M')" "$(epoch_fmt $((b + 59)) '%Y-%m-%d %H:%M')"
                [[ -n "$FB" ]] && fires+="$FB"$'\n'
            fi
        done <<<"$segs"
        local nf=0; [[ -n "$fires" ]] && nf="$(printf '%s' "$fires" | sed '/^$/d' | wc -l | tr -d ' ')"
        due=$((nf + every_due))
        # The scheduled runs that started in the window, and the fires they answer.
        local withref=0 ran=0 ok=0 failed=0 timeout=0 denied=0 refused=0 waiting=0 expired=0 skipped=0 late=0 maxlate=0 manual=0 answered="" d st trig ds
        while IFS= read -r d; do
            [[ -n "$d" ]] || continue
            ds="$(meta_get "$d" start_epoch)"
            [[ -n "$ds" ]] && (( ds >= se && ds < ue )) || continue
            trig="$(meta_get "$d" trigger)"
            if [[ "$trig" != schedule ]]; then manual=$((manual + 1)); continue; fi
            ran=$((ran + 1))
            st="$(run_status "$d")"
            case "$st" in
                ok) ok=$((ok + 1)) ;; timeout) timeout=$((timeout + 1)) ;; denied) denied=$((denied + 1)) ;;
                waiting) waiting=$((waiting + 1)) ;; expired) expired=$((expired + 1)) ;; skipped) skipped=$((skipped + 1)) ;;
                refused) refused=$((refused + 1)) ;;
                *) failed=$((failed + 1)) ;;
            esac
            [[ -n "$(meta_get "$d" refusals)" ]] && withref=$((withref + 1))
            if [[ -n "$(meta_get "$d" first_failure)" ]]; then
                T_retried=$((T_retried + 1)); [[ "$st" == ok ]] && T_recovered=$((T_recovered + 1))
            fi
            answered+="$(meta_get "$d" due)"$'\n'
            local de se2; de="$(meta_get "$d" due_epoch)"; se2="$(meta_get "$d" start_epoch)"
            if [[ -n "$de" && -n "$se2" ]] && (( se2 - de > 300 )); then
                late=$((late + 1)); (( se2 - de > maxlate )) && maxlate=$((se2 - de))
            fi
        done < <(runs_of "$n")
        local missed=0 fz pend_cut
        # A fire in the last five minutes before now with no run yet is pending, not missed: its run
        # may still be starting.
        pend_cut="$(epoch_fmt $((now_e - 300)) '%Y-%m-%d %H:%M')"
        while IFS= read -r fz; do
            [[ -n "$fz" ]] || continue
            grep -qxF "$fz" <<<"$answered" && continue
            if [[ ! "$fz" < "$pend_cut" ]]; then due=$((due - 1)); T_pending=$((T_pending + 1)); continue; fi
            missed=$((missed + 1)); misses+="$(printf '  %-24s due %s' "$n" "$fz")"$'\n'
            jmiss+="$(printf '{"task":%s,"due":%s}' "$(json_str "$n")" "$(json_str "$fz")"),"
        done <<<"$fires"
        if (( every_due > 0 )); then
            local ran_every=$((ran - nf + missed)); (( ran_every < 0 )) && ran_every=0
            if (( every_due > ran_every )); then
                local short=$((every_due - ran_every)); missed=$((missed + short))
                misses+="$(printf '  %-24s %s fewer runs than its interval gives, %s to %s' "$n" "$short" "$since" "$until")"$'\n'
                jmiss+="$(printf '{"task":%s,"fewer_runs":%s}' "$(json_str "$n")" "$short"),"
            fi
        fi
        (( due == 0 && ran == 0 && manual == 0 )) && continue
        local ml="-"; (( maxlate > 0 )) && ml="$(fmt_dur "$maxlate")"
        rows+="$(printf '%-24s %4s %4s %4s %6s %7s %6s %7s %7s %7s %4s %8s %6s %6s' "$n" "$due" "$ran" "$ok" "$failed" "$timeout" "$denied" "$waiting" "$expired" "$skipped" "$late" "$ml" "$missed" "$manual")"$'\n'
        jrows+="$(printf '{"task":%s,"due":%s,"ran":%s,"ok":%s,"failed":%s,"timeout":%s,"denied":%s,"refused":%s,"waiting":%s,"expired":%s,"skipped":%s,"late":%s,"max_late_secs":%s,"missed":%s,"manual":%s,"with_refusal":%s}' \
            "$(json_str "$n")" "$due" "$ran" "$ok" "$failed" "$timeout" "$denied" "$refused" "$waiting" "$expired" "$skipped" "$late" "$maxlate" "$missed" "$manual" "$withref"),"
        T_due=$((T_due + due)) T_ran=$((T_ran + ran)) T_ok=$((T_ok + ok)) T_failed=$((T_failed + failed)) T_timeout=$((T_timeout + timeout))
        T_denied=$((T_denied + denied)) T_refused=$((T_refused + refused)) T_waiting=$((T_waiting + waiting)) T_expired=$((T_expired + expired)) T_skipped=$((T_skipped + skipped))
        T_late=$((T_late + late)) T_manual=$((T_manual + manual)) T_missedn=$((T_missedn + missed)) T_withref=$((T_withref + withref)); (( maxlate > T_maxlate )) && T_maxlate=$maxlate
    done
    local T_missed=$T_missedn
    # A due fire that ran is one a scheduled run answered: the due fires less the misses.
    local fires_ran=$((T_due - T_missedn)); (( fires_ran < 0 )) && fires_ran=0
    if (( json )); then
        printf '{"window":{"since":%s,"until":%s},"tasks":[%s],"totals":{"due":%s,"due_ran":%s,"ran":%s,"ok":%s,"failed":%s,"timeout":%s,"denied":%s,"waiting":%s,"expired":%s,"skipped":%s,"late":%s,"max_late_secs":%s,"manual":%s,"pending":%s,"with_refusal":%s,"retried":%s,"recovered":%s},"missed":[%s]}\n' \
            "$(json_str "$since")" "$(json_str "$until")" "${jrows%,}" "$T_due" "$fires_ran" "$T_ran" "$T_ok" "$T_failed" "$T_timeout" "$T_denied" "$T_waiting" "$T_expired" "$T_skipped" "$T_late" "$T_maxlate" "$T_manual" "$T_pending" "$T_withref" "$T_retried" "$T_recovered" "${jmiss%,}"
        return 0
    fi
    echo "Scheduled runs, $since to $until (local time)"
    echo
    printf '%-24s %4s %4s %4s %6s %7s %6s %7s %7s %7s %4s %8s %6s %6s\n' TASK DUE RAN OK FAILED TIMEOUT DENIED WAITING EXPIRED SKIPPED LATE MAX-LATE MISSED MANUAL
    printf '%s' "$rows"
    echo
    local tl="$fires_ran of $T_due due fires ran; ok $T_ok of $T_ran runs"
    local k v
    for k in failed timeout denied refused waiting expired skipped; do v="T_$k"; (( ${!v} > 0 )) && tl+="; $k ${!v} of $T_ran runs"; done
    (( T_withref > 0 )) && tl+="; $T_withref of $T_ran runs carried on past a refused tool call"
    (( T_retried > 0 )) && tl+="; $T_recovered of $T_retried runs with a failed first attempt recovered on a retry"
    tl+="; late $T_late of $T_ran runs"; (( T_maxlate > 0 )) && tl+=" (at most $(fmt_dur "$T_maxlate"))"
    tl+="; $T_manual run(s) by hand, not counted against the schedule"
    (( T_pending > 0 )) && tl+="; $T_pending fire(s) in the last five minutes not yet run, left out"
    tl+="; $since to $until"
    echo "Totals: $tl."
    if [[ -n "$misses" ]]; then echo; echo "Missed ($T_missed):"; printf '%s' "$misses"; fi
}

cmd_log() {
    [[ $# -ge 1 ]] || usage_die "log needs a name"
    local name="$1" which="${2:-last}" d
    valid_name "$name" || die "'$name' is not a task name"
    if [[ "$which" == last ]]; then d="$(last_run "$name")"; else d="$S_DATA/runs/$name/$which"; fi
    [[ -n "$d" && -d "$d" ]] || die "no run ${which/last/yet} for $name"
    local a st; a="$(meta_get "$d" attempts)"; st="$(run_status "$d")"
    echo "Run $(basename "$d") of $name: $(status_text "$d")$( r="$(meta_get "$d" reason)"; [[ -n "$r" ]] && printf ' (%s)' "$r")"
    local due lt; due="$(meta_get "$d" due)"; lt="$(late_of "$d")"
    [[ -n "$due" ]] && echo "  due $due${lt:+, started $lt}"
    if [[ "$st" == running || "$st" == interrupted ]]; then
        echo "  started $(meta_get "$d" start); $st"
    else
        echo "  started $(meta_get "$d" start), ended $(meta_get "$d" end), $a attempt(s), exit $(meta_get "$d" exit), est. \$$(meta_get "$d" cost_usd), auth $(meta_get "$d" auth)"
    fi
    [[ "$st" == waiting ]] && echo "  awaiting a reply: schedule.sh reply $name '<your reply>'"
    local rfc; rfc="$(meta_get "$d" refused_calls)"
    [[ -n "$rfc" ]] && echo "  refused, and the run carried on ($(meta_get "$d" refusals)): $rfc"
    local rc; rc="$(resume_cmd "$d")"; [[ -n "$rc" ]] && echo "  open it: $rc"
    echo "  folder: $d"
    [[ -n "$a" && "$a" != 0 ]] || return 0
    echo
    echo "Result:"
    local r; r="$(result_text "$d/attempt-$a.json")"
    if [[ -n "$r" ]]; then printf '%s\n' "$r" | sed 's/^/  /'; else echo "  (no result text)"; fi
    if [[ -s "$d/attempt-$a.stderr" ]]; then
        echo
        echo "Stderr (last 20 lines):"
        tail -n 20 "$d/attempt-$a.stderr" | sed 's/^/  /'
    fi
    local n=1
    while [[ -e "$d/reply-$n.txt" ]]; do
        echo
        echo "Reply $n:"; sed 's/^/  > /' "$d/reply-$n.txt"
        r="$(result_text "$d/reply-$n.json")"
        echo "Then:"
        if [[ -n "$r" ]]; then printf '%s\n' "$r" | sed 's/^/  /'; else echo "  (no result text)"; tail -n 10 "$d/reply-$n.stderr" 2>/dev/null | sed 's/^/  /'; fi
        n=$((n + 1))
    done
}

cmd_next() {
    [[ $# -ge 1 ]] || usage_die "next needs a task name or a schedule"
    local what="$1" count=5; shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --count) count="${2:-}"; shift 2 ;;
            --from) export SCHEDULER_NOW="${2:-}"; shift 2 ;;
            *) usage_die "unknown option $1" ;;
        esac
    done
    [[ "$count" =~ ^[0-9]+$ ]] || usage_die "--count needs a number"
    if valid_name "$what" && [[ -f "$(task_file "$what")" ]]; then
        load_named "$what"; next_for_task "$count"
    else
        parse_schedule "$what" || die "$SERR"
        now_parts; next_times "$count"
    fi
    [[ -n "$NX" ]] && printf '%s\n' "$NX"
    return 0
}

# cmd_prev <when> [--at 'YYYY-MM-DD HH:MM']: the fire time a run started then would answer (its due
# time), the latest at or before that minute; the runner records it to mark late runs.
cmd_prev() {
    [[ $# -ge 1 ]] || usage_die "prev needs a schedule"
    local what="$1" at=""; shift
    [[ "${1:-}" == --at ]] && at="${2:-}"
    parse_schedule "$what" || die "$SERR"
    local e; if [[ -n "$at" ]]; then e="$(local_to_epoch "$at")" || die "--at is not YYYY-MM-DD HH:MM"; else e="$(date +%s)"; fi
    due_time "$e"
    [[ -n "$DUE" ]] && printf '%s\n' "$DUE"
    return 0
}
parse_show() { if full_set "$1" "$2" "$3"; then echo '*'; else echo "$1"; fi; }
cmd_parse() {
    [[ $# -ge 1 ]] || usage_die "parse needs a schedule"
    if [[ "$1" == --describe ]]; then
        shift
        [[ $# -ge 1 ]] || usage_die "parse --describe needs a schedule"
        parse_schedule "$*" || die "$SERR"
        if describe_words; then echo "$DWORDS"; else echo "$*"; fi
        return 0
    fi
    parse_schedule "$*" || die "$SERR"
    echo "kind: $SK"
    case "$SK" in
        every) echo "seconds: $E_SECS" ;;
        once) echo "at: $O_STR" ;;
        cron)
            echo "minute: $(parse_show "$C_MIN" 0 59)"; echo "hour: $(parse_show "$C_HOUR" 0 23)"
            echo "day-of-month: $(parse_show "$C_DOM" 1 31)"; echo "month: $(parse_show "$C_MON" 1 12)"
            echo "day-of-week: $(parse_show "$C_DOW" 0 6)"
            if [[ $C_OR -eq 1 ]]; then echo "days: either matches"; else echo "days: both match"; fi ;;
    esac
}

cmd_unit() {
    [[ $# -ge 1 ]] || usage_die "unit needs a name"
    local name="$1" b=""
    [[ "${2:-}" == --backend ]] && b="${3:-}"
    load_named "$name"
    if [[ -z "$b" ]]; then need_backend; b="$BACKEND"; fi
    in_list "$b" "launchd systemd cron none" || usage_die "--backend is launchd, systemd, cron or none"
    render_unit "$name" "$b" || die "$URERR"
}

cmd_sync() {
    need_backend
    refresh_runner
    reach_sweep
    local n ok=0 off=0 bad=0
    for n in $(task_names); do
        if ! task_load "$(task_file "$n")"; then warn "$n: $TERR"; bad=$((bad + 1)); continue; fi
        if ! validate_task; then warn "$n: not rendered: ${VERR//$'\n'/; }"; unit_remove "$n"; bad=$((bad + 1)); continue; fi
        if [[ "$(tv status)" == active ]]; then
            if unit_install "$n"; then ok=$((ok + 1)); else bad=$((bad + 1)); fi
        else
            unit_remove "$n"; off=$((off + 1))
        fi
    done
    # Units left behind by a task file that is gone.
    local orphan=0 p
    case "$BACKEND" in
        launchd) for p in "$LA_DIR/$LABEL_PREFIX".*.plist; do
                     [[ -f "$p" ]] || continue
                     n="${p##*/"$LABEL_PREFIX".}"; n="${n%.plist}"
                     [[ -f "$(task_file "$n")" ]] || { task_clear; unit_remove "$n"; orphan=$((orphan + 1)); }
                 done ;;
        systemd) for p in "$SD_DIR/$UNIT_PREFIX"-*.timer; do
                     [[ -f "$p" ]] || continue
                     n="${p##*/"$UNIT_PREFIX"-}"; n="${n%.timer}"
                     [[ -f "$(task_file "$n")" ]] || { task_clear; unit_remove "$n"; orphan=$((orphan + 1)); }
                 done ;;
        cron) cron_apply ;;
        none) for p in "$S_DATA/units"/*.cron; do
                  [[ -f "$p" ]] || continue
                  n="$(basename "$p" .cron)"; [[ -f "$(task_file "$n")" ]] || { rm -f "$p"; orphan=$((orphan + 1)); }
              done ;;
    esac
    echo "Synced on $BACKEND: $ok active task(s) installed, $off paused or done with no unit, $bad with problems, $orphan orphan unit(s) removed."
    [[ $bad -eq 0 ]]
}

# --- home: where the task files live -----------------------------------------------------------------------
# in_git <dir>: the folder sits in a git repository. git_dirty <file>: it has changes git has not
# committed (or is untracked). Both read with --no-optional-locks, so they never take git's lock.
in_git() { have git && git --no-optional-locks -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; }
# An untracked file and a modified one read the same: both are not in a commit. The folder's whole
# status is asked for (untracked files listed one by one, not collapsed to their folder) and the file
# looked for in it, so every task file in an untracked folder is marked alike.
git_dirty() {
    local d f; d="$(dirname "$1")"; f="$(basename "$1")"
    in_git "$d" || return 1
    git --no-optional-locks -C "$d" status --porcelain --untracked-files=all -- . 2>/dev/null \
        | sed 's/^.. //; s#^"##; s#"$##' | while IFS= read -r p; do [[ "${p##*/}" == "$f" ]] && { echo y; break; }; done | grep -q y
}
GIT_MARK="the file is not committed to git (new or changed)"
# rules_file: port-rules.tsv, beside the plugin's scripts/ folder, or beside the runner's copy (sync puts
# one there), or SCHEDULER_PORT_RULES.
rules_file() {
    if [[ -n "${SCHEDULER_PORT_RULES:-}" ]]; then printf '%s' "$SCHEDULER_PORT_RULES"
    elif [[ -f "$SELF_DIR/port-rules.tsv" ]]; then printf '%s' "$SELF_DIR/port-rules.tsv"
    else printf '%s' "$(cd "$SELF_DIR/.." 2>/dev/null && pwd)/port-rules.tsv"; fi
}
# credential_lines <file>: the lines of a task file shaped like a credential, by the credential rule in
# port-rules.tsv, as "N: text"; the value itself is not printed.
credential_lines() {
    local rules pat; rules="$(rules_file)"
    [[ -f "$rules" ]] || return 0
    pat="$(awk -F'\t' '$1 == "credential" { print $3 }' "$rules")"
    [[ -n "$pat" ]] || return 0
    grep -n -i -E -- "$pat" "$1" 2>/dev/null | cut -d: -f1 | sed 's/^/line /' | paste -sd, - | sed 's/,/, /g'
}

# cmd_home [<dir> [--move]]: with no folder, the tasks folder in use and why. With one, it is remembered
# in the pointer file. --move takes the task files there (and .trash/), then syncs, so the runner is
# handed the new folder; without --move a folder that still holds tasks is not left behind. The state
# folder (runs, ledgers, the runner's copy) stays where it is.
cmd_home() {
    if [[ $# -eq 0 ]]; then
        echo "Tasks folder: $S_TASKS ($S_TASKS_WHY)"
        in_git "$S_TASKS" && echo "  in a git repository; the scheduler never commits, so changes there are yours to commit"
        return 0
    fi
    local dir="$1" move=0 old="$S_TASKS" f n=0
    [[ "${2:-}" == --move ]] && move=1
    [[ "$dir" == \~/* ]] && dir="$HOME/${dir#\~/}"
    mkdir -p "$dir" || die "could not make $dir"
    dir="$(cd "$dir" && pwd -P)"
    [[ -n "${SCHEDULER_HOME:-}" ]] && warn "SCHEDULER_HOME is set in this environment and wins over the pointer; unset it to use $dir"
    [[ -d "$old" ]] && old="$(cd "$old" && pwd -P)"
    if [[ "$dir" == "$old" ]]; then echo "The tasks folder is already $dir."; return 0; fi
    for f in "$old"/*.md; do [[ -f "$f" ]] && n=$((n + 1)); done
    if (( n > 0 && ! move )); then
        die "$old still holds $n task file(s); 'schedule.sh home $1 --move' takes them to $dir"
    fi
    if (( move )); then
        for f in "$old"/*.md; do
            [[ -f "$f" ]] || continue
            [[ -e "$dir/$(basename "$f")" ]] && die "$dir already has $(basename "$f"); nothing moved"
        done
        for f in "$old"/*.md; do [[ -f "$f" ]] && mv "$f" "$dir/"; done
        if [[ -d "$old/.trash" ]]; then mkdir -p "$dir/.trash" && mv "$old/.trash"/* "$dir/.trash/" 2>/dev/null; rmdir "$old/.trash" 2>/dev/null; fi
    fi
    mkdir -p "$(dirname "$POINTER")"
    printf '%s\n' "$dir" >"$POINTER.tmp.$$" && mv "$POINTER.tmp.$$" "$POINTER"
    if in_git "$dir" && [[ ! -e "$dir/.gitignore" ]]; then printf '.trash/\n' >"$dir/.gitignore"; echo "Wrote $dir/.gitignore (.trash/)."; fi
    S_TASKS="$dir" S_TASKS_WHY="the pointer file, $POINTER"
    echo "Tasks folder: $dir (remembered in $POINTER)$( (( move )) && printf '; %s task file(s) moved from %s' "$n" "$old")."
    if (( move )) || [[ -f "$S_DATA/env" ]]; then cmd_sync; fi
}

is_wsl() { [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; }

# connector_states: for the loaded task, each name in requires against `claude mcp list` run in its
# folder (no model call), into CS as "<name>|<server>|<state>" lines; state is connected,
# missing, unchecked (no claude or no folder) or the line's own status ("! Needs authentication").
# "Google_Calendar" matches "claude.ai Google Calendar" or "plugin:<x>:google-calendar": case,
# underscores and hyphens aside. MCP_LIST, once filled, is reused for the next task.
connector_states() {
    CS=""
    local cb r norm line nm ln found reqs=()
    IFS=, read -r -a reqs <<<"$t_requires"
    if [[ -z "${MCP_LIST+set}" ]]; then
        # The claude runs use: the one sync records (SCHEDULER_CLAUDE first), else the one on PATH.
        cb="${SCHEDULER_CLAUDE:-${CLAUDE_BIN:-$(. "$S_DATA/env" 2>/dev/null; printf '%s' "${CLAUDE_BIN:-}")}}"
        [[ -n "$cb" ]] || cb="$(command -v claude 2>/dev/null)"
        if [[ -z "$cb" || ! -d "$t_cwd" ]]; then
            for r in "${reqs[@]}"; do r="$(trim "$r")"; [[ -n "$r" ]] && CS+="$r||unchecked"$'\n'; done
            return 0
        fi
        local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/schedule-mcp.XXXXXX")"
        ( cd "$t_cwd" && unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT && run_with_timeout 120 "$tmp" /dev/null /dev/null "$cb" mcp list )
        MCP_LIST="$(cat "$tmp")"; rm -f "$tmp"
    fi
    for r in "${reqs[@]}"; do
        r="$(trim "$r")"; [[ -n "$r" ]] || continue
        norm="$(lower "$r" | tr '_-' '  ')"
        found=""
        while IFS= read -r line; do
            nm="${line%%: *}"; [[ "$nm" != "$line" ]] || continue
            ln="$(lower "$nm" | tr '_-' '  ')"; ln="${ln##*:}"
            if [[ "$ln" == "$norm" || "$ln" == "claude.ai $norm" ]]; then found="$line"; break; fi
        done <<<"$MCP_LIST"
        if [[ -z "$found" ]]; then CS+="$r||missing"$'\n'
        elif [[ "$found" == *Connected* ]]; then CS+="$r|${found%%: *}|connected"$'\n'
        else CS+="$r|${found%%: *}|${found##* - }"$'\n'; fi
    done
}

# doctor_task <name>: one task's file, unit and connectors. Each name in requires is looked for in
# `claude mcp list` run in the task's folder (no model call): "Google_Calendar" matches a server named
# "claude.ai Google Calendar" or "plugin:<x>:google-calendar", underscores and hyphens read as spaces.
doctor_task() {
    local name="$1" problems=0
    load_named "$name"
    echo "Task $name ($(task_file "$name"))"
    if validate_task; then echo "  file: valid"; else echo "  file: ${VERR//$'\n'/; }"; problems=$((problems + 1)); fi
    git_dirty "$(task_file "$name")" && echo "  git: $GIT_MARK"
    if need_backend 2>/dev/null; then
        unit_state "$name"; echo "  unit ($BACKEND): $US"
        case "$US" in installed|absent) ;; *) problems=$((problems + 1)) ;; esac
    fi
    [[ -d "$t_cwd" ]] && echo "  folder: $t_cwd" || { echo "  folder: $t_cwd does not exist"; problems=$((problems + 1)); }
    echo "  sandbox: $(sandbox_line)"
    if [[ -n "$t_requires" ]]; then
        connector_states
        local r srv state
        while IFS='|' read -r r srv state; do
            [[ -n "$r" ]] || continue
            case "$state" in
                connected) echo "  connector $r: $srv, connected" ;;
                missing) echo "  connector $r: not found in claude mcp list here"; problems=$((problems + 1)) ;;
                unchecked) echo "  connectors: not checked (no claude, or no folder to run it in)"; problems=$((problems + 1)); break ;;
                *) echo "  connector $r: $srv, $state"; problems=$((problems + 1)) ;;
            esac
        done <<<"$CS"
    fi
    echo
    if (( problems )); then echo "$problems problem(s)."; return 1; fi
    echo "No problems."
}

cmd_doctor() {
    [[ $# -ge 1 ]] && { doctor_task "$1"; return; }
    local problems=0
    echo "schedule.sh $VERSION"
    if detect_backend; then echo "Backend: $BACKEND ($BACKEND_WHY)"; else echo "Backend: none found. $BACKEND_WHY."; problems=$((problems + 1)); fi
    echo "Tasks: $S_TASKS ($(task_names | wc -l | tr -d ' ') task(s); $S_TASKS_WHY)"
    echo "State: $S_DATA"
    if [[ -x "$RUNNER" ]]; then
        if cmp -s "$SELF" "$RUNNER"; then echo "Runner copy: current"; else echo "Runner copy: differs from this script; 'schedule.sh sync' refreshes it"; fi
    else echo "Runner copy: not written yet; 'schedule.sh sync' writes it"; fi
    if [[ ! -f "$S_DATA/env" ]]; then
        echo "Runner environment: $S_DATA/env is missing, so scheduled runs have no claude to call; 'schedule.sh sync' writes it"
        problems=$((problems + 1))
    else
        local cb; cb="$(. "$S_DATA/env"; printf '%s' "${CLAUDE_BIN:-}")"
        if [[ -n "$cb" && -x "$cb" ]]; then echo "claude for runs: $cb ($("$cb" --version 2>/dev/null | head -n 1))"
        else echo "claude for runs: '$cb' is not executable; 'schedule.sh sync' where claude is on PATH"; problems=$((problems + 1)); fi
    fi
    have jq && echo "jq: yes" || echo "jq: no (the sed fallback reads Claude's output)"
    # The login runs are billed to, from `claude auth status`, which makes no model call.
    local cbin; cbin="${SCHEDULER_CLAUDE:-$( [[ -f "$S_DATA/env" ]] && . "$S_DATA/env"; printf '%s' "${CLAUDE_BIN:-$(command -v claude 2>/dev/null)}")}"
    if [[ -n "$cbin" && -x "$cbin" ]]; then
        local as; as="$(env -u CLAUDECODE "$cbin" auth status --json </dev/null 2>/dev/null)"
        if have jq && [[ -n "$as" ]]; then
            echo "Login (claude auth status): $(jq -r '"\(.authMethod // "?"), \(.apiProvider // "?")\(if .subscriptionType then ", " + .subscriptionType + " subscription" else "" end)\(if .loggedIn == false then ", not logged in" else "" end)"' <<<"$as")"
        else
            echo "Login: $(env -u CLAUDECODE "$cbin" auth status --text </dev/null 2>/dev/null | head -n 1)"
        fi
    fi
    echo "Billing: each run's settings are checked for an API key first (${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json, the managed settings, and the task folder's .claude/settings*.json); a run whose init event names an API key source is stopped"
    case "${BACKEND:-}" in
        systemd)
            local linger; linger="$(loginctl show-user "${USER:-$(id -un)}" -p Linger 2>/dev/null)"
            if [[ "$linger" == "Linger=yes" ]]; then echo "Linger: yes (timers fire while logged out)"
            else echo "Linger: no; timers fire only while you are logged in. 'loginctl enable-linger' lets them fire after logout"; fi ;;
        cron)
            if pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1; then echo "cron daemon: running"
            else echo "cron daemon: not seen running; nothing in the crontab fires without it"; problems=$((problems + 1)); fi ;;
    esac
    if is_wsl; then
        echo "WSL: yes. The distro stops when idle, and its timers stop with it; 'schedule.sh keepalive install'"
        echo "     adds a Windows logon task that keeps it running."
    fi
    if have osascript || have notify-send; then echo "Desktop notifications: yes"; else echo "Desktop notifications: none available; a task's notify command still runs"; fi
    local n
    for n in $(task_names); do
        git_dirty "$(task_file "$n")" && echo "Task $n: $GIT_MARK"
        if ! task_load "$(task_file "$n")"; then echo "Task $n: $TERR"; problems=$((problems + 1)); continue; fi
        if ! validate_task; then echo "Task $n: ${VERR//$'\n'/; }"; problems=$((problems + 1)); continue; fi
        billing_refusal
        if [[ -n "$BR" ]]; then echo "Task $n: its runs would bill an API key, so they are refused: $BR"; problems=$((problems + 1)); fi
        local cl; cl="$(credential_lines "$(task_file "$n")")"
        [[ -n "$cl" ]] && echo "Task $n: $cl of its file look like a credential; keep it in a file the prompt points to"
        [[ -n "${BACKEND:-}" ]] || continue
        unit_state "$n"
        case "$US" in
            installed|absent) echo "Task $n: $(tv status), unit $US" ;;
            *) echo "Task $n: $(tv status), unit $US; 'schedule.sh sync' puts it right"; problems=$((problems + 1)) ;;
        esac
    done
    # Remote sessions: the sweep ends those whose run is over; what it leaves is still running (its run awaits
    # a reply) or could not be stopped, and is listed with its age.
    reach_sweep
    local rl; rl="$(reach_list)"
    if [[ -n "$rl" ]]; then echo "Remote sessions still running (reach: remote):"; printf '%s\n' "$rl" | sed 's/^/  /'; fi
    # A Mac asleep at a fire time runs the job when it wakes, late; a wake schedule avoids that. pmset
    # needs sudo, so it is given for the person to run, not run here.
    if [[ "$(uname -s)" == Darwin ]] && have pmset; then
        local sched; sched="$(pmset -g sched 2>/dev/null | sed '/^$/d')"
        echo "Wake schedule (pmset -g sched): ${sched:-none}"
        local earliest="" t
        for n in $(task_names); do
            task_load "$(task_file "$n")" || continue
            [[ "$(tv status)" == active ]] && parse_schedule "$t_schedule" 2>/dev/null && [[ "$SK" != every ]] || continue
            next_for_task 1; t="${NX:11:5}"
            [[ -n "$t" && ( -z "$earliest" || "$t" < "$earliest" ) ]] && earliest="$t"
        done
        if [[ -n "$earliest" ]]; then
            local h=$((10#${earliest%:*})) m=$((10#${earliest#*:} - 5))
            (( m < 0 )) && { m=$((m + 60)); h=$(((h + 23) % 24)); }
            echo "  Optional: this Mac runs a task that was asleep at its fire time late, when it wakes. To have it"
            echo "  wake five minutes before the earliest task, you can run the line below. It changes the power"
            echo "  settings of the whole machine, replaces any repeat wake already set, and needs sudo. Undo it with:"
            echo "  sudo pmset repeat cancel"
            echo "    sudo pmset repeat wakeorpoweron MTWRFSU $(pad2 $h):$(pad2 $m):00"
        fi
    fi
    if [[ -s "$S_DATA/logs/runner.log" ]]; then echo "Runner log, last 3 lines:"; tail -n 3 "$S_DATA/logs/runner.log" | sed 's/^/  /'; fi
    echo
    if (( problems )); then echo "$problems problem(s)."; return 1; fi
    echo "No problems."
}

# keepalive: WSL2 stops an idle distro, and timers inside it stop with it. A Windows task at logon
# starts a long sleep in the distro, which keeps it running. Untested on Windows by the kit's suite.
cmd_keepalive() {
    local act="${1:-status}" distro="${WSL_DISTRO_NAME:-}" tn
    is_wsl || [[ -n "${SCHEDULER_SCHTASKS:-}" ]] || die "keepalive is for WSL2; this is not WSL"
    [[ -n "$distro" ]] || die "WSL_DISTRO_NAME is not set, so the distro to keep running is unknown"
    tn="agentic-workspace scheduler keepalive ($distro)"
    case "$act" in
        install)
            "$SCHTASKS" /Create /F /TN "$tn" /SC ONLOGON /TR "wsl.exe -d $distro --exec /bin/sleep infinity" >/dev/null \
                || die "schtasks.exe /Create failed"
            "$SCHTASKS" /Run /TN "$tn" >/dev/null 2>&1
            echo "Installed the Windows logon task '$tn', and started it." ;;
        remove)
            "$SCHTASKS" /Delete /F /TN "$tn" >/dev/null || die "schtasks.exe /Delete failed"
            echo "Removed the Windows logon task '$tn'. A sleep it started runs until the distro stops." ;;
        status)
            if "$SCHTASKS" /Query /TN "$tn" >/dev/null 2>&1; then echo "Installed: '$tn'"; else echo "Not installed"; fi ;;
        *) usage_die "keepalive takes install, remove or status" ;;
    esac
}

main() {
    local cmd="${1:-help}"
    [[ $# -gt 0 ]] && shift
    case "$cmd" in
        create) cmd_create "$@" ;;
        edit) cmd_edit "$@" ;;
        list|ls) cmd_list "$@" ;;
        show) cmd_show "$@" ;;
        pause) cmd_pause "$@" ;;
        resume) cmd_resume "$@" ;;
        run|run-now) cmd_run "$@" ;;
        delete|rm) cmd_delete "$@" ;;
        runs|history) cmd_runs "$@" ;;
        log) cmd_log "$@" ;;
        report) cmd_report "$@" ;;
        reply) cmd_reply "$@" ;;
        record-answer) cmd_record_answer "$@" ;;   # the Stop hook's call; prints nothing
        next) cmd_next "$@" ;;
        parse) cmd_parse "$@" ;;
        prev) cmd_prev "$@" ;;
        unit) cmd_unit "$@" ;;
        sync) cmd_sync "$@" ;;
        home) cmd_home "$@" ;;
        doctor) cmd_doctor "$@" ;;
        keepalive) cmd_keepalive "$@" ;;
        exec) [[ $# -ge 1 ]] || usage_die "exec needs a name"; cmd_exec "$@" ;;
        port)
            # shellcheck source=lib/port.sh
            . "$SELF_DIR/lib/port.sh" || die "lib/port.sh is missing beside this script"
            cmd_port "$@" ;;
        help|-h|--help) usage ;;
        --version|version) echo "$VERSION" ;;
        *) usage_die "unknown command '$cmd'" ;;
    esac
}

main "$@"
