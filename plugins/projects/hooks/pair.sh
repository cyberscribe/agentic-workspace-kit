#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# The pairing's hooks and the watches the agents run, for both sides of a /projects:pair pairing, and
# the few commands the pair skill runs for either side.
#
#   pair.sh start   SessionStart (startup, resume and compact): records this session's id and its
#                   claude process id in the mailbox, clears any ended mark, and tells the agent which
#                   messages are open for it, and the command that starts the watch. After a compaction
#                   the agent has lost track of the mailbox, so it is told again. The PM's session
#                   (PAIR_ROLE=pm) has no engineer state, so start does nothing for it.
#   pair.sh stop    Stop: claims a fresh join for this session (below); then an open PM message the
#                   agent has not yet been pointed at twice sends it back to work (exit 2, the reason
#                   on stderr). With the pairing open and no watch running, the turn is sent back once
#                   to start the watch; the second Stop lets it end, and the counter goes back to zero,
#                   so the next turn is sent back once more. Otherwise it returns at once. For the PM
#                   (PAIR_ROLE=pm) the stop is the no-watch rule alone, against the PM's watch.
#   pair.sh beat [--prompt]
#                   UserPromptSubmit and PostToolUse: records that the session is active, at most every
#                   30 seconds. With --prompt (UserPromptSubmit) it also clears the no-watch counter.
#                   Silent, and it returns before reading its input outside a pairing. The PM's beats
#                   clear only the PM's counter.
#   pair.sh end     SessionEnd: records that the session has ended (the engineer's; a PM's end does nothing).
#   pair.sh watch [--role cc|pm] [--mailbox DIR]
#                   Run by the agent as a background command, not by a hook. It ends, with one line
#                   naming the message, when a new open message arrives for its side or the pairing is
#                   closed; a background command that ends is what wakes a session between turns. The
#                   engineer's watch (cc, the default) watches to-cc.md; the PM's (pm) watches to-pm.md.
#   pair.sh join --mailbox DIR [--cwd DIR]
#                   /projects:pair join, run in a session that was started without the launcher. It
#                   asks for this session to become the engineer: the Stop hook at the end of the turn
#                   claims the request, which proves the hooks are loaded here.
#   pair.sh leave [--mailbox DIR]
#                   /projects:pair leave: unbinds the session from the mailbox and ends its watch.
#   pair.sh check --mailbox DIR
#                   The PM's check-in: the engineer's state, derived from evidence (below), what is open
#                   each way, when each side last picked a message up, any header dated later than its
#                   file was written, and once per spell the line that says the engineer needs a
#                   session or a watch.
#   pair.sh post --mailbox DIR --from pm|cc --title TEXT [--pm TOKEN]
#                   Appends the message on stdin to the other side's file under the next id, taken
#                   under a lock, with Status: open. --pm names the PM's token from .pm-session; a
#                   PM post without the holder's token is written, with a warning.
#   pair.sh status --mailbox DIR --from pm|cc --id ID TEXT...
#                   Sets the status of a message the other side wrote (done, declined, or waiting
#                   and why): one line appended to the reader's own status file, under its lock.
#   pair.sh init --mailbox DIR --name NAME
#                   Makes a mailbox in DIR, any folder: the protocol README and the four files below.
#                   A folder that already holds a mailbox is left as it is.
#   pair.sh where PROJECT [--mailbox DIR]
#                   Prints where the project's mailbox is (lib/mailbox.sh), whether it exists yet,
#                   and the git repository around it, or none.
#   pair.sh default [DIR | --clear]
#                   Prints, sets or clears this machine's default mailbox root: a new mailbox goes
#                   in <root>/<slug> rather than <project>/mailbox.
#
# One writer per file. A mailbox may live in a folder that is copied between machines, and a file two
# machines change between copies comes back as two versions. So no file has two writers: the PM writes
# to-cc.md, status-pm.md and the .pm-* files; the engineer writes to-pm.md, status-cc.md and the .cc-*
# files. A message's status is the last line for its id in its reader's status file ("PM-007 · <time> ·
# done ..."), or, where there is none, the last Status: line in the message itself. A mailbox made
# before the status files existed has its Status: lines edited in place by the reader, and still reads
# the same. Each side takes its own lock (.pm-lock, .cc-lock), because a lock only means something to
# processes on one machine.
#
# Times are this machine's clock, written with its UTC offset ("2026-10-27 20:17 +0000"), so two
# machines in different zones still agree on the order of events. Headers are written by pair.sh post,
# or headed with the output of date, never typed; check flags a header later than its file's last write.
#
# How a session is found. The launcher (scripts/pair.sh) sets PAIR_ROLE and PAIR_MAILBOX, and those still
# win: PAIR_ROLE=cc is the engineer's session, PAIR_ROLE=pm the PM's, and a PM with no PAIR_MAILBOX is not
# in a pairing at all. A session started any other way joins: join writes .cc-join in the mailbox and lists the
# mailbox in the registry, a machine-local file of "<mailbox><TAB><session id or ->" lines. The Stop
# hook claims a join no more than 10 minutes old whose session id (or, where the join could not see
# one, whose folder) is this session's, and binds the session in the registry; from then on the hooks
# find the mailbox by the session id the hook input carries. Every other session passes straight
# through: with no variables and no registry entry, the hooks exit at once.
#
# Liveness comes from evidence, not from a stored word. The start hook records the claude process
# (.cc-pid, found by walking up from the hook to the first process named claude). The beat hooks keep
# .cc-beat, the epoch of the last activity, rewritten at most every 30 seconds; the end hook writes
# .cc-ended. check and status derive the engineer's state from these and the watch, each with its
# evidence:
#   ended     .cc-ended exists, or the recorded process is not running (kill -0)
#   working   the last activity is under 2 minutes old
#   watching  the engineer's watch process is running
#   idle      the process is running, with no recent activity and no watch
# .cc-state is kept as a cache for older readers; check labels it "cached".
#
# Why the watch is not in the Stop hook: a hook that waits holds the session. While it sleeps the
# session takes no other notification and looks busy to the person, who has to interrupt it to type.
# The hooks therefore check once and return, and the waiting happens in a background command, which
# holds nothing.
#
# Settings, from the environment:
#   PAIR_POLL_SECONDS   how often the watch reads the messages addressed to it (default 20)
#   PAIR_REGISTRY       the registry file (default ~/.config/agentic-workspace-kit/pairings)
#   PAIR_JOIN_GRACE     seconds a join may wait for its claim before the watch says it has not been
#                       claimed (default 180)
#
# State it writes, all in the mailbox: .cc-session (the session id), .cc-pid (the claude process id),
# .cc-beat and .cc-ended (above), .cc-nowatch and .pm-nowatch (1 once the Stop hook has sent a turn back for
# want of a watch, each side's own; the second Stop clears it), .cc-state (the cache: working, waiting or stopped, since when), .cc-watch (the running
# engineer's watch process id), .cc-nudged (each message id it has pointed the agent at, with a count),
# .cc-join (a join no Stop hook has claimed yet), .pm-watch and .pm-nudged (the PM's watch), and
# .pm-warned (the spell the PM has already been told about). An id is pointed at no more than twice, so
# a message the agent cannot finish leads to a stop, not a loop; the agent marks such a message
# `waiting <on what>`, and the PM picks it up. The first time an id is pointed at, the reader's status
# file gets a "received" line, so the other side can see how long a message waited.
#
# Written for bash 3.2 (macOS /bin/bash) and POSIX awk; no jq.
set -u

mode="${1:-}"
[ $# -gt 0 ] && shift
# beat and end run on every tool call, so outside a pairing they leave before anything else is read.
if [ "$mode" = beat ] || [ "$mode" = end ]; then
    [ -n "${PAIR_ROLE:-}" ] || [ -f "${PAIR_REGISTRY:-$HOME/.config/agentic-workspace-kit/pairings}" ] || exit 0
fi
opt_mb="" opt_cwd="" opt_from="" opt_title="" opt_pm="" opt_id="" opt_name="" opt_clear=0 opt_role="" opt_prompt=0 rest=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mailbox) opt_mb="${2:-}"; shift 2 2>/dev/null || shift ;;
        --cwd) opt_cwd="${2:-}"; shift 2 2>/dev/null || shift ;;
        --from) opt_from="${2:-}"; shift 2 2>/dev/null || shift ;;
        --title) opt_title="${2:-}"; shift 2 2>/dev/null || shift ;;
        --pm) opt_pm="${2:-}"; shift 2 2>/dev/null || shift ;;
        --id) opt_id="${2:-}"; shift 2 2>/dev/null || shift ;;
        --name) opt_name="${2:-}"; shift 2 2>/dev/null || shift ;;
        --role) opt_role="${2:-}"; shift 2 2>/dev/null || shift ;;
        --prompt) opt_prompt=1; shift ;;
        --clear) opt_clear=1; shift ;;
        *) rest="${rest:+$rest }$1"; shift ;;
    esac
done

registry="${PAIR_REGISTRY:-$HOME/.config/agentic-workspace-kit/pairings}"
here="$(cd "$(dirname "$0")" && pwd -P)"
stamp() { date '+%Y-%m-%d %H:%M %z'; }
say() { printf 'pair: %s\n' "$*"; }

# ---- Clock and file helpers: BSD date and stat first, GNU after, so one file runs on either ----------
# hms <epoch>: the local time of day, seconds included.
hms() { date -r "$1" '+%H:%M:%S' 2>/dev/null || date -d "@$1" '+%H:%M:%S' 2>/dev/null; }
# stamp_of <epoch>: the epoch written the way a message header is.
stamp_of() { date -r "$1" '+%Y-%m-%d %H:%M %z' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M %z' 2>/dev/null; }
# epoch_of <header stamp>: the epoch of "YYYY-MM-DD HH:MM +ZZZZ", nothing when it does not parse. BSD date -j
# fills the fields a format leaves out from the current time, so the seconds are given as :00 explicitly.
epoch_of() {
    local s="$1"
    s="${s% *}:00 ${s##* }"
    date -j -f '%Y-%m-%d %H:%M:%S %z' "$s" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}
# mtime_of <file>: the epoch of the file's last write. GNU stat -f prints a filesystem field rather than
# a number, so its output is checked before the GNU form is tried.
mtime_of() {
    local m
    m="$(stat -f %m "$1" 2>/dev/null)"
    case "$m" in ''|*[!0-9]*) m="$(stat -c %Y "$1" 2>/dev/null)" ;; esac
    printf '%s' "$m"
}
# The value of one "key: value" line in a small state file.
field() { sed -n "s/^$2: //p" "$1" 2>/dev/null | head -n 1; }

# claude_pid: the claude process this hook runs under. A hook runs in a child of the claude process, and
# not always directly, so the parent chain is walked (six levels) to the first process whose executable,
# or whose argv[0], is named claude. The name is matched exactly, not the whole command line: a shell
# wrapper's command line can hold a path such as ~/.claude/shell-snapshots, and that is not the session.
# With no match, nothing is printed: the hook's own parent is a shell that exits when the hook does, so its pid
# would read as ended. The state then rests on the beat and the end mark.
claude_pid() {
    local p="$PPID" i=0 c a
    while [ "$i" -lt 6 ] && [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
        c="$(ps -o comm= -p "$p" 2>/dev/null)"
        a="$(ps -o args= -p "$p" 2>/dev/null)"
        a="${a%% *}"
        if [ "${c##*/}" = claude ] || [ "${a##*/}" = claude ]; then printf '%s\n' "$p"; return 0; fi
        p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
        i=$((i + 1))
    done
    return 0
}

# ---- The registry ----------------------------------------------------------------------------------
# One "<mailbox><TAB><session id or ->" line per mailbox under a header line, changed only through
# lib/lock.sh, so two sessions joining or leaving at once cannot lose each other's line.
# shellcheck source=lib/lock.sh
. "$here/lib/lock.sh"
# reg_mailbox <session id>: the mailbox this session is bound to, or nothing.
reg_mailbox() { [ -n "$1" ] && [ -f "$registry" ] && awk -F'\t' -v s="$1" '$2 == s { print $1; exit }' "$registry"; }
# reg_bind <mailbox> <session id or ->: one line per mailbox, and a session bound to one mailbox only.
reg_bind() {
    if [ ! -f "$registry" ]; then
        mkdir -p "$(dirname "$registry")" 2>/dev/null || return 0
        printf '# Pairings joined on this machine: mailbox, then session id (- until claimed). Written by the projects plugin'"'"'s pair.sh.\n' > "$registry"
    fi
    # The awk program is single-quoted on purpose (aw_rewrite runs it).
    # shellcheck disable=SC2016
    aw_rewrite "$registry" awk -F'\t' -v m="$1" -v s="$2" '/^#/ || ($1 != m && (s == "-" || $2 != s)) { print } END { print m "\t" s }'
}
# The awk program is single-quoted on purpose (aw_rewrite runs it).
# shellcheck disable=SC2016
reg_drop() { [ -f "$registry" ] && aw_rewrite "$registry" awk -F'\t' -v m="$1" '/^#/ || $1 != m'; return 0; }

# ---- Commands that need no mailbox yet --------------------------------------------------------------
# shellcheck source=lib/mailbox.sh
. "$here/lib/mailbox.sh"
case "$mode" in
    where)
        [ -n "$rest" ] || { say "name the project folder: pair.sh where <project folder>"; exit 2; }
        [ -d "$rest" ] || { say "$rest is not a folder"; exit 2; }
        proj="$(cd "$rest" && pwd -P)"
        line="$(aw_mb_resolve "$proj" "$opt_mb")"
        tab="$(printf '\t')"; at="${line%%"$tab"*}"
        # The nearest folder that exists says which repository the mailbox would sit in.
        up="$at"; while [ ! -d "$up" ] && [ "$up" != / ] && [ -n "$up" ]; do up="$(dirname "$up")"; done
        [ -d "$at" ] && at="$(cd "$at" && pwd -P)"
        repo="$(git -C "$up" rev-parse --show-toplevel 2>/dev/null)"
        printf 'mailbox: %s\nstate: %s\nrepository: %s\n' "$at" "${line##*"$tab"}" "${repo:-none}"
        exit 0
        ;;
    default)
        conf="$(aw_mb_config)"
        if [ $opt_clear -eq 1 ]; then rm -f "$conf"; say "no default mailbox root on this machine now"; exit 0; fi
        if [ -n "$rest" ]; then
            [ -d "$rest" ] || { say "$rest is not a folder"; exit 2; }
            mkdir -p "$(dirname "$conf")" || exit 2
            printf '%s\n' "$(cd "$rest" && pwd -P)" > "$conf"
        fi
        r="$(aw_mb_root)"
        if [ -z "$r" ]; then say "no default mailbox root on this machine; a new mailbox goes in <project>/mailbox"
        elif [ -n "${PAIR_MAILBOX_ROOT:-}" ]; then say "default mailbox root: $r (from PAIR_MAILBOX_ROOT)"
        else say "default mailbox root: $r (from $conf)"
        fi
        exit 0
        ;;
    init)
        [ -n "$opt_mb" ] || { say "name the folder: pair.sh init --mailbox <folder> --name <project name>"; exit 2; }
        if [ -f "$opt_mb/to-cc.md" ]; then say "$opt_mb already holds a mailbox; it is left as it is"; exit 0; fi
        mkdir -p "$opt_mb" || { say "cannot make $opt_mb"; exit 2; }
        name="${opt_name:-$(basename "$opt_mb")}"
        tpl="$here/../examples/pair/README.md"
        # The project's name goes in with awk, so no character in it can act as a sed command.
        [ -f "$opt_mb/README.md" ] || awk -v n="$name" '{ gsub(/<project name>/, n); print }' "$tpl" > "$opt_mb/README.md"
        printf '# To the engineer: %s\n\nMessages from the PM, ids PM-001 on. Protocol: README.md.\n' "$name" > "$opt_mb/to-cc.md"
        printf '# To the PM: %s\n\nMessages from the engineer, ids CC-001 on. Protocol: README.md.\n' "$name" > "$opt_mb/to-pm.md"
        printf '# Statuses the engineer has set on PM messages: id · time · status. The last line for an id holds.\n' > "$opt_mb/status-cc.md"
        printf '# Statuses the PM has set on CC messages: id · time · status. The last line for an id holds.\n' > "$opt_mb/status-pm.md"
        say "mailbox made in $(cd "$opt_mb" && pwd -P)"
        exit 0
        ;;
esac

# ---- Which mailbox, and which session --------------------------------------------------------------
# The side a watch serves: the engineer's by default, the PM's with --role pm.
role="${opt_role:-cc}"
case "$role" in cc|pm) ;; *) say "--role is cc or pm"; exit 2 ;; esac
mb="" sid="" input=""
case "$mode" in
    start|stop|beat|end)
        input="$(cat 2>/dev/null || true)"
        sid="$(printf '%s' "$input" | tr '\n' ' ' \
            | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        # A PM session with no mailbox bound is outside any pairing: it must not claim a join or touch a registry line.
        [ "${PAIR_ROLE:-}" = pm ] && [ -z "${PAIR_MAILBOX:-}" ] && exit 0
        if { [ "${PAIR_ROLE:-}" = cc ] || [ "${PAIR_ROLE:-}" = pm ]; } && [ -n "${PAIR_MAILBOX:-}" ]; then
            mb="$PAIR_MAILBOX"
            role="$PAIR_ROLE"
        else
            # No registry, or this session in none of it and no join waiting: not a pairing session.
            [ -f "$registry" ] || exit 0
            mb="$(reg_mailbox "$sid")"
            if [ -z "$mb" ]; then
                [ "$mode" = stop ] && [ -n "$sid" ] || exit 0
                joins=""
                while IFS="$(printf '\t')" read -r cand _; do
                    [ -f "$cand/.cc-join" ] && joins="$joins$cand
"
                done < "$registry"
                [ -n "$joins" ] || exit 0
            fi
        fi
        # The hooks keep to a kit workspace (lib/boundary.sh).
        # shellcheck source=lib/boundary.sh
        . "$here/lib/boundary.sh"
        [ -n "$(aw_workspace_root "$input")" ] || exit 0
        ;;
    watch|leave)
        mb="$opt_mb"
        [ -n "$mb" ] || { [ "${PAIR_ROLE:-}" = "cc" ] && mb="${PAIR_MAILBOX:-}"; }
        [ -n "$mb" ] || [ -z "${CLAUDE_CODE_SESSION_ID:-}" ] || mb="$(reg_mailbox "$CLAUDE_CODE_SESSION_ID")"
        [ -n "$mb" ] || { say "name the mailbox: pair.sh $mode --mailbox <folder>"; exit 2; }
        ;;
    join|check|post|status)
        mb="$opt_mb"
        [ -n "$mb" ] || { say "name the mailbox: pair.sh $mode --mailbox <folder>"; exit 2; }
        ;;
    *)
        exit 0
        ;;
esac

# ---- Claiming a join (the Stop hook) ---------------------------------------------------------------
# A join is claimed by the session that asked for it: the session id it recorded, or, where it could
# record none, its folder, matched against the folder in the hook input. A join older than 10 minutes
# is left alone, so a request no hook answered cannot be picked up later by another session by chance.
if [ "$mode" = stop ] && [ -z "$mb" ]; then
    want_cwd="$(cd "$(aw_input_cwd "$input")" 2>/dev/null && pwd -P)"
    now="$(date +%s)"
    while IFS= read -r cand; do
        [ -n "$cand" ] || continue
        at="$(field "$cand/.cc-join" requested)"
        case "$at" in ''|*[!0-9]*) continue ;; esac
        [ $(( now - at )) -le 600 ] || continue
        js="$(field "$cand/.cc-join" session)"
        if [ -n "$js" ]; then [ "$js" = "$sid" ] || continue
        else [ -n "$want_cwd" ] && [ "$(field "$cand/.cc-join" cwd)" = "$want_cwd" ] || continue
        fi
        mb="$cand"
        break
    done <<EOJ
$joins
EOJ
    [ -n "$mb" ] || exit 0
    printf '%s\n' "$sid" > "$mb/.cc-session"
    claude_pid > "$mb/.cc-pid"
    rm -f "$mb/.cc-ended"
    reg_bind "$mb" "$sid"
    rm -f "$mb/.cc-join"
    printf 'state: working\nsince: %s\nsession: %s\n' "$(stamp)" "$sid" > "$mb/.cc-state"
    printf 'Mailbox: this session has joined the pairing at %s as its engineer; from now on its hooks point it at PM messages. Tell the person in one line, and keep the watch running.\n' "$mb" >&2
    exit 2
fi

if [ ! -d "$mb" ]; then
    # A bound mailbox that has gone: the binding goes with it, quietly.
    case "$mode" in start|stop|beat|end) [ -n "${PAIR_ROLE:-}" ] || reg_drop "$mb"; exit 0 ;; esac
    say "no mailbox at $mb"; exit 2
fi
mb="$(cd "$mb" && pwd -P)"
cc_file="$mb/to-cc.md"
# The file a side reads, its nudged file and its watch's pid file: the engineer's are the .cc- files, the PM's
# the .pm- files. The functions below read these, so one code path serves both sides.
if [ "$role" = pm ]; then
    reads="$mb/to-pm.md"; nudged="$mb/.pm-nudged"; watch_pid="$mb/.pm-watch"
else
    reads="$cc_file"; nudged="$mb/.cc-nudged"; watch_pid="$mb/.cc-watch"
fi
# The watch and the commands read the session id the hooks recorded.
[ -n "$sid" ] || sid="$(head -n 1 "$mb/.cc-session" 2>/dev/null | tr -d '[:space:]')"

# A watch started before its join was claimed learns the session id only from .cc-session, later. The
# state file is the engineer's cache alone.
set_state() {
    [ "$role" = cc ] || return 0
    [ -n "$sid" ] || sid="$(head -n 1 "$mb/.cc-session" 2>/dev/null | tr -d '[:space:]')"
    printf 'state: %s\nsince: %s\nsession: %s\n' "$1" "$(stamp)" "$sid" > "$mb/.cc-state" 2>/dev/null
}

# status_file <mailbox file>: the status file its reader writes (to-cc.md is read by the engineer).
status_file() { case "$1" in *to-cc.md) printf '%s/status-cc.md' "$mb" ;; *) printf '%s/status-pm.md' "$mb" ;; esac; }
# The ids of messages in a mailbox file whose status begins "open", or that have no status at all. A
# line for the id in the reader's status file holds over the message's own Status: lines. Within a
# message the label counts wherever it sits in a line (bold allowed), since a writer may end a
# sentence with it, and the last one holds. A message the writer forgot to mark is still unanswered,
# and treating it as settled would hide it from the engineer for good. A "received" line records a
# pickup, not a settlement, so it is passed over.
open_ids() {
    local f="${1:-$reads}" sf
    [ -f "$f" ] || return 0
    sf="$(status_file "$f")"; [ -f "$sf" ] || sf=/dev/null
    awk '
        function emit() { if (id != "") { if (id in set) st = set[id]; if (st == "" || st ~ /^open/) print id } }
        FILENAME == sf { if ($0 !~ /^#/ && match($0, / · [^·]* · /)) { t = tolower(substr($0, RSTART + RLENGTH)); if (t !~ /^received/) set[$1] = t }; next }
        /^## [A-Za-z]+-[0-9]+/ { emit(); id = $2; st = ""; next }
        /Status:/ { s = $0; while (match(s, /Status:\**[ \t]*/)) s = substr(s, RSTART + RLENGTH); st = tolower(s); if (st == "") st = "open" }
        END { emit() }
    ' sf="$sf" "$sf" "$f"
}
# dup_ids <file>: ids that head more than one message, as "PM-019 (2)". A second writer that took an id
# by hand files a separate message under it; read as an amendment, it would be half lost.
dup_ids() {
    [ -f "$1" ] || return 0
    awk '/^## [A-Za-z]+-[0-9]+/ { n[$2]++; if (n[$2] == 2) o[++k] = $2 } END { for (i = 1; i <= k; i++) printf "%s%s (%d)", (i > 1 ? ", " : ""), o[i], n[o[i]] }' "$1"
}
dup_line() {
    local d; d="$(dup_ids "$1")"
    [ -z "$d" ] || printf 'Two or more messages share an id in %s: %s. Each is a separate message, not an amendment of the one before: read every one.\n' "$1" "$d"
}
# How many times the reader has been pointed at an id.
times_nudged() { [ -f "$nudged" ] && awk -v id="$1" '$1 == id { n = $2 } END { print n + 0 }' "$nudged" || echo 0; }
# mark_received <id>: the first time a reader is pointed at a message, one line in its status file, so the
# other side can see how long the message waited. Written under the reader's own lock.
mark_received() {
    local sf; sf="$(status_file "$reads")"
    aw_lock "$mb/.$role-lock" || return 0
    [ -f "$sf" ] || printf '# Statuses set by the %s side: id · time · status. The last line for an id holds.\n' "$role" > "$sf"
    printf '%s · %s · received\n' "$1" "$(stamp)" >> "$sf"
    aw_unlock "$mb/.$role-lock"
}
mark_nudged() {
    local n; n=$(( $(times_nudged "$1") + 1 ))
    { [ -f "$nudged" ] && awk -v id="$1" '$1 != id' "$nudged"; printf '%s %s\n' "$1" "$n"; } > "$nudged.tmp" \
        && mv "$nudged.tmp" "$nudged"
    [ "$n" -eq 1 ] && mark_received "$1"
    return 0
}
# Open ids pointed at fewer than <limit> times, space-separated.
due() {
    local limit="$1" id out=""
    for id in $(open_ids); do [ "$(times_nudged "$id")" -lt "$limit" ] && out="$out $id"; done
    printf '%s' "${out# }"
}
# watching: this side's watch is running. A stored pid counts only when that process is a pair.sh watch of
# this side's role: a pid left by a killed watch can be reused by an unrelated process.
watching() {
    local wp c
    [ -f "$watch_pid" ] || return 1
    wp="$(head -n 1 "$watch_pid" 2>/dev/null)"
    kill -0 "$wp" 2>/dev/null || return 1
    c="$(ps -o command= -p "$wp" 2>/dev/null)"
    case "$c" in *pair.sh*" watch"*) ;; *) return 1 ;; esac
    case "$c" in *"--role pm"*) [ "$role" = pm ] ;; *) [ "$role" != pm ] ;; esac
}
# The no-watch counter of this side: 1 once the Stop hook has sent a turn back for want of a watch.
nowatch_file() { if [ "$role" = pm ]; then printf '%s' "$mb/.pm-nowatch"; else printf '%s' "$mb/.cc-nowatch"; fi; }
nowatch_get() { head -n 1 "$(nowatch_file)" 2>/dev/null | tr -d '[:space:]'; }
nowatch_set() { printf '%s\n' "$1" > "$(nowatch_file)" 2>/dev/null; }
send_back() {
    local id
    for id in $1; do mark_nudged "$id"; done
    set_state working
    printf 'Mailbox: %s open for you in %s. Read it and act on it; then set its status (done, declined or waiting <on what>) as the mailbox README says and report in %s/to-pm.md.\n' \
        "$1" "$cc_file" "$mb" >&2
    exit 2
}
watch_cmd() {
    if [ "$role" = pm ]; then printf 'bash %q watch --role pm --mailbox %q' "$here/pair.sh" "$mb"
    else printf 'bash %q watch --mailbox %q' "$here/pair.sh" "$mb"
    fi
}

# derive_state: the engineer's state from evidence, into ds_state (not-started, ended, working, watching
# or idle) and ds_ev (the same word with its evidence, as check prints it).
derive_state() {
    local pid now beat wp
    pid="$(head -n 1 "$mb/.cc-pid" 2>/dev/null | tr -d '[:space:]')"
    if [ -z "$pid" ] && [ ! -f "$mb/.cc-session" ]; then
        ds_state=not-started; ds_ev="not started: no session has been recorded"; return 0
    fi
    if [ -f "$mb/.cc-ended" ]; then
        ds_state=ended; ds_ev="ended: session ended at $(sed -n 1p "$mb/.cc-ended")"; return 0
    fi
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        ds_state=ended; ds_ev="ended: no running process for pid $pid"; return 0
    fi
    now="$(date +%s)"
    beat="$(head -n 1 "$mb/.cc-beat" 2>/dev/null | tr -d '[:space:]')"
    case "$beat" in ''|*[!0-9]*) beat=0 ;; esac
    if [ $(( now - beat )) -lt 120 ]; then
        ds_state=working; ds_ev="working: last activity $(hms "$beat")${pid:+, pid $pid alive}"; return 0
    fi
    wp="$(head -n 1 "$mb/.cc-watch" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$wp" ] && kill -0 "$wp" 2>/dev/null; then
        ds_state=watching; ds_ev="watching: watch running (process $wp)${pid:+, pid $pid alive}"; return 0
    fi
    ds_state=idle
    if [ "$beat" -gt 0 ]; then ds_ev="idle: last activity $(hms "$beat")${pid:+, pid $pid alive}, no watch running"
    else ds_ev="idle: no activity recorded${pid:+, pid $pid alive}, no watch running"
    fi
}

# clock_check <message file>: names each header dated later than the file's last write. A header is made
# by pair.sh post or by date, so one that runs ahead of the file's mtime was typed, or copied from a
# machine whose clock is wrong, and every lateness reading built on it is wrong too.
clock_check() {
    local f="$1" m id s e
    [ -f "$f" ] || return 0
    m="$(mtime_of "$f")"
    case "$m" in ''|*[!0-9]*) return 0 ;; esac
    awk -F' · ' '/^## [A-Za-z]+-[0-9]+ · / { sub(/^## /, "", $1); print $1 "|" $2 }' "$f" \
    | while IFS='|' read -r id s; do
        e="$(epoch_of "$s")"
        case "$e" in ''|*[!0-9]*) continue ;; esac
        [ "$e" -gt "$m" ] || continue
        printf 'Clock: %s is headed %s, later than %s was last written (%s). Headers come from pair.sh post or from date, never typed; check the clock of the machine that wrote it.\n' \
            "$id" "$s" "${f##*/}" "$(stamp_of "$m")"
    done
}

# last_received <status file>: "<id> at <HH:MM>" for the last line its writer recorded as received.
last_received() {
    [ -f "$1" ] || return 0
    awk -F' · ' '$3 == "received" { id = $1; t = $2 } END { if (id != "") printf "%s at %s\n", id, substr(t, 12, 5) }' "$1"
}

case "$mode" in
    start)
        # The PM's session has no engineer state to record, and its prompt carries its own watch command.
        [ "$role" = pm ] && exit 0
        # A joined session whose pairing has closed is unbound, and hears nothing more of it.
        if [ -f "$mb/.closed" ] && [ "${PAIR_ROLE:-}" != "cc" ]; then reg_drop "$mb"; exit 0; fi
        [ -n "$sid" ] && printf '%s\n' "$sid" > "$mb/.cc-session" 2>/dev/null
        claude_pid > "$mb/.cc-pid" 2>/dev/null
        rm -f "$mb/.cc-ended"
        nowatch_set 0
        set_state working
        ids="$(open_ids | paste -sd' ' -)"
        printf 'This session is the engineer in a /projects:pair pairing. Mailbox: %s (protocol in its README.md). ' "$mb"
        if [ -n "$ids" ]; then printf 'Open for you in to-cc.md: %s. ' "$ids"; else printf 'Nothing is open for you in to-cc.md. ' ; fi
        dup_line "$cc_file" | tr '\n' ' '
        if [ "${PAIR_ROLE:-}" = "cc" ]; then
            printf 'To hear of a new message between turns, run this as a background command and start it again each time it ends: PAIR_ROLE=cc PAIR_MAILBOX=%q bash %q watch\n' \
                "$mb" "$here/pair.sh"
        else
            printf 'To hear of a new message between turns, run this as a background command and start it again each time it ends: %s\n' "$(watch_cmd)"
        fi
        exit 0
        ;;
    stop)
        # The PM's Stop is the no-watch rule alone: no send-back of due messages (those go to the engineer)
        # and no state file. A closed pairing or a running PM watch lets the turn end.
        if [ "$role" = pm ]; then
            [ -f "$mb/.closed" ] && exit 0
            if watching; then nowatch_set 0; exit 0; fi
            if [ "$(nowatch_get)" = 1 ]; then nowatch_set 0; exit 0; fi
            nowatch_set 1
            printf 'Mailbox: this pairing is open and no PM watch is running, so messages from the engineer would not reach this session. Start the watch as a background command, then end the turn: %s\n' "$(watch_cmd)" >&2
            exit 2
        fi
        # A closed pairing unbinds a joined session: its hooks go quiet from here on.
        if [ -f "$mb/.closed" ]; then
            [ "${PAIR_ROLE:-}" = "cc" ] || reg_drop "$mb"
            set_state stopped; exit 0
        fi
        ids="$(due 2)"
        [ -n "$ids" ] && send_back "$ids"
        if watching; then set_state waiting; nowatch_set 0; exit 0; fi
        # The pairing is open and no watch runs, so a PM message would reach no one. The turn is sent back
        # once, with the watch command; the second Stop ends it and clears the counter, so the next turn is
        # sent back once more. Each turn gets one block, and this cannot loop.
        if [ "$(nowatch_get)" = 1 ]; then nowatch_set 0; set_state stopped; exit 0; fi
        nowatch_set 1
        set_state working
        printf 'Mailbox: this pairing is open and no watch is running, so messages from the PM would not reach this session. Start the watch as a background command, then end the turn: %s\n' "$(watch_cmd)" >&2
        exit 2
        ;;
    beat)
        # The PM's activity is not the engineer's liveness: its beat clears only its own counter.
        if [ "$role" = pm ]; then [ "$opt_prompt" -eq 1 ] && nowatch_set 0; exit 0; fi
        [ "$opt_prompt" -eq 1 ] && nowatch_set 0
        now="$(date +%s)"
        last=0
        [ -f "$mb/.cc-beat" ] && read -r last < "$mb/.cc-beat"
        case "$last" in ''|*[!0-9]*) last=0 ;; esac
        [ $(( now - last )) -gt 30 ] && printf '%s\n' "$now" > "$mb/.cc-beat" 2>/dev/null
        [ -s "$mb/.cc-pid" ] || claude_pid > "$mb/.cc-pid" 2>/dev/null
        rm -f "$mb/.cc-ended"
        exit 0
        ;;
    end)
        [ "$role" = pm ] && exit 0
        stamp > "$mb/.cc-ended" 2>/dev/null
        set_state stopped
        exit 0
        ;;
    watch)
        if watching; then printf 'Mailbox: a watch is already running (process %s).\n' "$(head -n 1 "$watch_pid")"; exit 0; fi
        # A watch start does not clear the no-watch counter: a watch that exits at once must leave the release armed.
        # The PM's session records its id in .pm-session, so a later launch can resume it.
        if [ "$role" = pm ] && [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && [ -f "$mb/.pm-session" ] \
            && ! grep -q "^session: $CLAUDE_CODE_SESSION_ID\$" "$mb/.pm-session"; then
            awk -v s="$CLAUDE_CODE_SESSION_ID" '/^session: / { next } { print } END { print "session: " s }' "$mb/.pm-session" \
                > "$mb/.pm-session.tmp.$$" && mv "$mb/.pm-session.tmp.$$" "$mb/.pm-session"
        fi
        poll="${PAIR_POLL_SECONDS:-20}"
        case "$poll" in ''|*[!0-9]*|0) poll=20 ;; esac
        grace="${PAIR_JOIN_GRACE:-180}"
        case "$grace" in ''|*[!0-9]*) grace=180 ;; esac
        printf '%s\n' "$$" > "$watch_pid" 2>/dev/null
        # The sleep runs in the background because bash holds a trap until a foreground command returns.
        nap=""
        trap '[ -n "$nap" ] && kill "$nap" 2>/dev/null; rm -f "$watch_pid"; set_state stopped; exit 0' HUP INT TERM
        while :; do
            if [ -f "$mb/.closed" ]; then
                rm -f "$watch_pid"; set_state stopped
                printf 'Mailbox: the PM has closed the pairing. No further watch is needed.\n'
                exit 0
            fi
            # A join no Stop hook has claimed: the projects plugin's hooks are not loaded in that session.
            if [ "$role" = cc ]; then
                at="$(field "$mb/.cc-join" requested)"
                case "$at" in ''|*[!0-9]*) at="" ;; esac
                if [ -n "$at" ] && [ $(( $(date +%s) - at )) -ge "$grace" ]; then
                    js="$(field "$mb/.cc-join" session)"
                    rm -f "$mb/.cc-join" "$watch_pid"
                    printf 'Mailbox: the join has not been claimed, so the projects plugin'"'"'s hooks are not loaded in this session and it will not hear PM messages. Tell the person to exit and run, from the workspace root: kit/plugins/projects/scripts/pair.sh <project folder>%s\n' \
                        "${js:+ --session $js}"
                    exit 0
                fi
            fi
            # Only messages the reader has never been pointed at end the watch.
            ids="$(due 1)"
            if [ -n "$ids" ]; then
                for id in $ids; do mark_nudged "$id"; done
                rm -f "$watch_pid"
                if [ "$role" = pm ]; then
                    printf 'Mailbox: %s open for the PM in %s. Read it, test what it claims, answer it with pair.sh post --from pm (or set its status with pair.sh status --from pm), and start the PM watch again.\n' \
                        "$ids" "$reads"
                else
                    set_state working
                    printf 'Mailbox: %s open for you in %s. Read it and act on it; then set its status (done, declined or waiting <on what>) as the mailbox README says, report in %s/to-pm.md, and start the watch again.\n' \
                        "$ids" "$cc_file" "$mb"
                fi
                exit 0
            fi
            # The session that started the watch has gone when the mailbox has, or when this process
            # has been handed to init.
            [ -d "$mb" ] || exit 0
            [ "$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')" = "1" ] && { rm -f "$watch_pid"; set_state stopped; exit 0; }
            sleep "$poll" & nap=$!
            wait "$nap"
        done
        ;;
    join)
        [ -f "$cc_file" ] || { say "$mb has no to-cc.md: the PM sets the mailbox up with /projects:pair"; exit 2; }
        [ ! -f "$mb/.closed" ] || { say "the pairing at $mb is closed; the PM reopens it by removing .closed"; exit 2; }
        if [ "${PAIR_ROLE:-}" = "cc" ] && [ "${PAIR_MAILBOX:-}" -ef "$mb" ]; then
            say "this session was started by the launcher for this pairing; it is already the engineer"; exit 0
        fi
        cwd="$(cd "${opt_cwd:-$PWD}" 2>/dev/null && pwd -P)"
        printf 'requested: %s\nat: %s\ncwd: %s\nsession: %s\n' "$(date +%s)" "$(stamp)" "$cwd" "${CLAUDE_CODE_SESSION_ID:-}" \
            > "$mb/.cc-join" || { say "cannot write $mb/.cc-join"; exit 2; }
        # Listed, unbound, so the Stop hook knows where to look; the claim binds it.
        awk -F'\t' -v m="$mb" '$1 == m { f = 1 } END { exit !f }' "$registry" 2>/dev/null || reg_bind "$mb" -
        say "join requested for $mb. End this turn: the Stop hook claims it and says so. Start the watch first, as a background command:"
        printf '%s\n' "$(watch_cmd)"
        exit 0
        ;;
    leave)
        reg_drop "$mb"
        rm -f "$mb/.cc-join"
        if watching; then kill -TERM "$(head -n 1 "$watch_pid")" 2>/dev/null; fi
        rm -f "$watch_pid"
        set_state stopped
        say "this session has left the pairing at $mb; its hooks and watch no longer act on it."
        [ "${PAIR_ROLE:-}" = "cc" ] && say "it was started by the launcher, so its hooks still read PAIR_MAILBOX until it exits."
        exit 0
        ;;
    check)
        derive_state
        cached="$(field "$mb/.cc-state" state)"; cached_since="$(field "$mb/.cc-state" since)"
        to_cc="$(open_ids "$cc_file" | paste -sd' ' -)"
        to_pm="$(open_ids "$mb/to-pm.md" | paste -sd' ' -)"
        printf 'Engineer: %s\n' "$ds_ev"
        [ -z "$cached" ] || printf 'Cached state (.cc-state, written at the last hook event): %s since %s\n' "$cached" "${cached_since:-?}"
        printf 'Open for the engineer: %s\n' "${to_cc:-none}"
        printf 'Open for the PM: %s\n' "${to_pm:-none}"
        pick="$(last_received "$mb/status-cc.md")"
        [ -z "$pick" ] || printf 'Last picked up: %s\n' "$pick"
        pick="$(last_received "$mb/status-pm.md")"
        [ -z "$pick" ] || printf 'Last picked up by the PM: %s\n' "$pick"
        dup_line "$cc_file"
        dup_line "$mb/to-pm.md"
        clock_check "$cc_file"
        clock_check "$mb/to-pm.md"
        # Files the protocol does not write. A copy of a file that two machines changed between copies
        # holds the other version, and nothing reads it: it is named at once when its name says
        # "conflict", and any other unknown file once it is five minutes old (a copy in progress is not).
        strays=""
        for f in "$mb"/* "$mb"/.[!.]*; do
            [ -e "$f" ] || continue
            n="${f##*/}"
            case "$n" in
                README.md|KICKOFF.md|PM-KICKOFF.md|to-cc.md|to-pm.md|status-cc.md|status-pm.md|.closed|.post-lock) continue ;;
                *[Cc]onflict*) ;;
                .cc-*|.pm-*|*.tmp.[0-9]*) continue ;;
                *) [ -n "$(find "$f" -prune -mmin +5 2>/dev/null)" ] || continue ;;
            esac
            strays="${strays:+$strays, }$n"
        done
        [ -z "$strays" ] || printf 'Files in the mailbox that the protocol does not write: %s. A copy made when two machines changed one file between copies holds the other version: compare it with the original, keep what is missing, then delete the copy.\n' "$strays"
        # Not watching: a PM message is open and the engineer is neither working nor watched. Each such
        # spell is said once; a working or watching engineer clears it.
        if [ -n "$to_cc" ] && [ ! -f "$mb/.closed" ]; then
            case "$ds_state" in
                working|watching) rm -f "$mb/.pm-warned" ;;
                ended)
                    if [ "$(cat "$mb/.pm-warned" 2>/dev/null)" != ended ]; then
                        printf 'ended\n' > "$mb/.pm-warned"
                        printf 'For the person: the engineer'"'"'s session has ended with a message open for it; resume it with kit/plugins/projects/scripts/pair.sh <project folder>.\n'
                    fi ;;
                *)
                    if [ "$(cat "$mb/.pm-warned" 2>/dev/null)" != "$ds_state" ]; then
                        printf '%s\n' "$ds_state" > "$mb/.pm-warned"
                        printf 'For the person: the engineer isn'"'"'t watching the mailbox; type /projects:pair join in its session.\n'
                    fi ;;
            esac
        fi
        exit 0
        ;;
    post)
        case "$opt_from" in pm) file="$cc_file"; prefix=PM ;; cc) file="$mb/to-pm.md"; prefix=CC ;;
            *) say "post needs --from pm or --from cc"; exit 2 ;; esac
        [ -n "$opt_title" ] || { say "post needs --title"; exit 2; }
        body="$(cat)"
        [ -n "$body" ] || { say "post reads the message from stdin, and it was empty"; exit 2; }
        # The id is read and the message appended under one lock (lib/lock.sh), so two writers cannot
        # take the same id.
        aw_lock "$mb/.$opt_from-lock" || { say "the mailbox is locked ($mb/.$opt_from-lock)"; exit 2; }
        if [ "$opt_from" = pm ] && [ -f "$mb/.pm-session" ]; then
            holder="$(field "$mb/.pm-session" token)"
            [ "$holder" = "$opt_pm" ] || printf 'pair: warning: another PM session holds this mailbox (since %s); two PMs writing one to-cc.md give the engineer two briefs. Posted anyway.\n' \
                "$(field "$mb/.pm-session" since)" >&2
        fi
        last="$(grep -oE "^## $prefix-[0-9]+" "$file" 2>/dev/null | sed "s/^## $prefix-//" | sed 's/^0*//' | sort -n | tail -n 1)"
        id="$(printf '%s-%03d' "$prefix" $(( ${last:-0} + 1 )))"
        printf '\n## %s · %s · %s\n%s\nStatus: open\n' "$id" "$(stamp)" "$opt_title" "$body" >> "$file"
        aw_unlock "$mb/.$opt_from-lock"
        printf '%s\n' "$id"
        exit 0
        ;;
    status)
        # The reader sets the status of the other side's message, in its own file.
        case "$opt_from" in cc) file="$cc_file" ;; pm) file="$mb/to-pm.md" ;;
            *) say "status needs --from pm or --from cc"; exit 2 ;; esac
        [ -n "$opt_id" ] && [ -n "$rest" ] || { say "status needs --id <message id> and the status (done, declined or waiting <on what>)"; exit 2; }
        grep -q "^## $opt_id " "$file" 2>/dev/null || { say "no $opt_id in $file"; exit 2; }
        sf="$(status_file "$file")"
        aw_lock "$mb/.$opt_from-lock" || { say "the mailbox is locked ($mb/.$opt_from-lock)"; exit 2; }
        [ -f "$sf" ] || printf '# Statuses set by the %s side: id · time · status. The last line for an id holds.\n' "$opt_from" > "$sf"
        printf '%s · %s · %s\n' "$opt_id" "$(stamp)" "$(printf '%s' "$rest" | tr '\n' ' ')" >> "$sf"
        aw_unlock "$mb/.$opt_from-lock"
        printf '%s %s\n' "$opt_id" "$rest"
        exit 0
        ;;
esac
