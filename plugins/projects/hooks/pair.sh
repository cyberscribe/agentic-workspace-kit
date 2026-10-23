#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# The engineer's side of a /projects:pair pairing: two hooks, the watch the agent runs, and the few
# commands the pair skill runs for either side.
#
#   pair.sh start   SessionStart (startup, resume and compact): records this session's id in the
#                   mailbox (so the launcher can resume it) and tells the agent which messages are
#                   open for it, and the command that starts the watch. After a compaction the agent
#                   has lost track of the mailbox, so it is told again.
#   pair.sh stop    Stop: claims a fresh join for this session (below); then an open PM message the
#                   agent has not yet been pointed at twice sends it back to work (exit 2, the reason
#                   on stderr). Otherwise it returns at once.
#   pair.sh watch [--mailbox DIR]
#                   Run by the agent as a background command, not by a hook. It ends, with one line
#                   naming the message, when a new open PM message arrives or the pairing is closed;
#                   a background command that ends is what wakes a session between turns.
#   pair.sh join --mailbox DIR [--cwd DIR]
#                   /projects:pair join, run in a session that was started without the launcher. It
#                   asks for this session to become the engineer: the Stop hook at the end of the turn
#                   claims the request, which proves the hooks are loaded here.
#   pair.sh leave [--mailbox DIR]
#                   /projects:pair leave: unbinds the session from the mailbox and ends its watch.
#   pair.sh check --mailbox DIR
#                   The PM's check-in: the engineer's state, what is open each way, and once per stale
#                   spell the line that says the engineer is not watching the mailbox.
#   pair.sh post --mailbox DIR --from pm|cc --title TEXT [--pm TOKEN]
#                   Appends the message on stdin to the other side's file under the next id, taken
#                   under a lock, with Status: open. --pm names the PM's token from .pm-session; a
#                   PM post without the holder's token is written, with a warning.
#
# How a session is found. The launcher (scripts/pair.sh) sets PAIR_ROLE=cc and PAIR_MAILBOX, and those
# still win. A session started any other way joins: join writes .cc-join in the mailbox and lists the
# mailbox in the registry, a machine-local file of "<mailbox><TAB><session id or ->" lines. The Stop
# hook claims a join no more than 10 minutes old whose session id (or, where the join could not see
# one, whose folder) is this session's, and binds the session in the registry; from then on the hooks
# find the mailbox by the session id the hook input carries. Every other session passes straight
# through: with no variables and no registry entry, the hooks exit at once.
#
# Why the watch is not in the Stop hook: a hook that waits holds the session. While it sleeps the
# session takes no other notification and looks busy to the person, who has to interrupt it to type.
# The hooks therefore check once and return, and the waiting happens in a background command, which
# holds nothing.
#
# Settings, from the environment:
#   PAIR_POLL_SECONDS   how often the watch reads to-cc.md (default 20)
#   PAIR_REGISTRY       the registry file (default ~/.config/agentic-workspace-kit/pairings)
#   PAIR_JOIN_GRACE     seconds a join may wait for its claim before the watch says it has not been
#                       claimed (default 180)
#
# State it writes, all in the mailbox: .cc-session (the session id), .cc-state (working, waiting or
# stopped, since when; waiting means a watch is running), .cc-watch (the running watch's process id),
# .cc-nudged (each message id it has pointed the agent at, with a count), .cc-join (a join no Stop hook has
# claimed yet) and .pm-warned (the stale spell the PM has already been told about). An id is pointed at
# no more than twice, so a message the agent cannot finish leads to a stop, not a loop; the agent marks
# such a message `waiting <on what>`, and the PM picks it up.
#
# Written for bash 3.2 (macOS /bin/bash) and POSIX awk; no jq.
set -u

mode="${1:-}"
[ $# -gt 0 ] && shift
opt_mb="" opt_cwd="" opt_from="" opt_title="" opt_pm=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mailbox) opt_mb="${2:-}"; shift 2 2>/dev/null || shift ;;
        --cwd) opt_cwd="${2:-}"; shift 2 2>/dev/null || shift ;;
        --from) opt_from="${2:-}"; shift 2 2>/dev/null || shift ;;
        --title) opt_title="${2:-}"; shift 2 2>/dev/null || shift ;;
        --pm) opt_pm="${2:-}"; shift 2 2>/dev/null || shift ;;
        *) shift ;;
    esac
done

registry="${PAIR_REGISTRY:-$HOME/.config/agentic-workspace-kit/pairings}"
here="$(cd "$(dirname "$0")" && pwd -P)"
stamp() { date '+%Y-%m-%d %H:%M'; }
say() { printf 'pair: %s\n' "$*"; }

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
# The value of one "key: value" line in a small state file.
field() { sed -n "s/^$2: //p" "$1" 2>/dev/null | head -n 1; }
# older <path> <minutes>: 0 when the path was last written more than that many minutes ago.
older() { [ -n "$(find "$1" -prune -mmin +"$2" 2>/dev/null)" ]; }

# ---- Which mailbox, and which session --------------------------------------------------------------
mb="" sid="" input=""
case "$mode" in
    start|stop)
        input="$(cat 2>/dev/null || true)"
        sid="$(printf '%s' "$input" | tr '\n' ' ' \
            | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        if [ "${PAIR_ROLE:-}" = "cc" ] && [ -n "${PAIR_MAILBOX:-}" ]; then
            mb="$PAIR_MAILBOX"
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
    join|check|post)
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
    reg_bind "$mb" "$sid"
    rm -f "$mb/.cc-join"
    printf 'state: working\nsince: %s\nsession: %s\n' "$(stamp)" "$sid" > "$mb/.cc-state"
    printf 'Mailbox: this session has joined the pairing at %s as its engineer; from now on its hooks point it at PM messages. Tell the person in one line, and keep the watch running.\n' "$mb" >&2
    exit 2
fi

if [ ! -d "$mb" ]; then
    # A bound mailbox that has gone: the binding goes with it, quietly.
    case "$mode" in start|stop) [ "${PAIR_ROLE:-}" = "cc" ] || reg_drop "$mb"; exit 0 ;; esac
    say "no mailbox at $mb"; exit 2
fi
mb="$(cd "$mb" && pwd -P)"
cc_file="$mb/to-cc.md"
nudged="$mb/.cc-nudged"
watch_pid="$mb/.cc-watch"
# The watch and the commands read the session id the hooks recorded.
[ -n "$sid" ] || sid="$(head -n 1 "$mb/.cc-session" 2>/dev/null | tr -d '[:space:]')"

# A watch started before its join was claimed learns the session id only from .cc-session, later.
set_state() {
    [ -n "$sid" ] || sid="$(head -n 1 "$mb/.cc-session" 2>/dev/null | tr -d '[:space:]')"
    printf 'state: %s\nsince: %s\nsession: %s\n' "$1" "$(stamp)" "$sid" > "$mb/.cc-state" 2>/dev/null
}

# The ids of messages in a mailbox file whose last Status begins "open" (bold labels allowed), or that
# have no Status at all. The label counts wherever it sits in a line, since a writer may end a sentence
# with it; the last one in the message is the one that holds. A message the writer forgot to mark is
# still unanswered, and treating it as settled would hide it from the engineer for good.
open_ids() {
    local f="${1:-$cc_file}"
    [ -f "$f" ] || return 0
    awk '
        function emit() { if (id != "" && (st == "" || st ~ /^open/)) print id }
        /^## [A-Za-z]+-[0-9]+/ { emit(); id = $2; st = ""; next }
        /Status:/ { s = $0; while (match(s, /Status:\**[ \t]*/)) s = substr(s, RSTART + RLENGTH); st = tolower(s); if (st == "") st = "open" }
        END { emit() }
    ' "$f"
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
# How many times the agent has been pointed at an id.
times_nudged() { [ -f "$nudged" ] && awk -v id="$1" '$1 == id { n = $2 } END { print n + 0 }' "$nudged" || echo 0; }
mark_nudged() {
    local n; n=$(( $(times_nudged "$1") + 1 ))
    { [ -f "$nudged" ] && awk -v id="$1" '$1 != id' "$nudged"; printf '%s %s\n' "$1" "$n"; } > "$nudged.tmp" \
        && mv "$nudged.tmp" "$nudged"
}
# Open ids pointed at fewer than <limit> times, space-separated.
due() {
    local limit="$1" id out=""
    for id in $(open_ids); do [ "$(times_nudged "$id")" -lt "$limit" ] && out="$out $id"; done
    printf '%s' "${out# }"
}
watching() { [ -f "$watch_pid" ] && kill -0 "$(head -n 1 "$watch_pid" 2>/dev/null)" 2>/dev/null; }
send_back() {
    local id
    for id in $1; do mark_nudged "$id"; done
    set_state working
    printf 'Mailbox: %s open for you in %s. Read it and act on it; then set its Status: line (done, declined or waiting <on what>) and report in %s/to-pm.md.\n' \
        "$1" "$cc_file" "$mb" >&2
    exit 2
}
watch_cmd() { printf 'bash %q watch --mailbox %q' "$here/pair.sh" "$mb"; }

case "$mode" in
    start)
        # A joined session whose pairing has closed is unbound, and hears nothing more of it.
        if [ -f "$mb/.closed" ] && [ "${PAIR_ROLE:-}" != "cc" ]; then reg_drop "$mb"; exit 0; fi
        [ -n "$sid" ] && printf '%s\n' "$sid" > "$mb/.cc-session" 2>/dev/null
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
        # A closed pairing unbinds a joined session: its hooks go quiet from here on.
        if [ -f "$mb/.closed" ]; then
            [ "${PAIR_ROLE:-}" = "cc" ] || reg_drop "$mb"
            set_state stopped; exit 0
        fi
        ids="$(due 2)"
        [ -n "$ids" ] && send_back "$ids"
        if watching; then set_state waiting; else set_state stopped; fi
        exit 0
        ;;
    watch)
        if watching; then printf 'Mailbox: a watch is already running (process %s).\n' "$(head -n 1 "$watch_pid")"; exit 0; fi
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
            at="$(field "$mb/.cc-join" requested)"
            case "$at" in ''|*[!0-9]*) at="" ;; esac
            if [ -n "$at" ] && [ $(( $(date +%s) - at )) -ge "$grace" ]; then
                js="$(field "$mb/.cc-join" session)"
                rm -f "$mb/.cc-join" "$watch_pid"
                printf 'Mailbox: the join has not been claimed, so the projects plugin'"'"'s hooks are not loaded in this session and it will not hear PM messages. Tell the person to exit and run, from the workspace root: kit/plugins/projects/scripts/pair.sh <project folder>%s\n' \
                    "${js:+ --session $js}"
                exit 0
            fi
            # Only messages the agent has never been pointed at end the watch.
            ids="$(due 1)"
            if [ -n "$ids" ]; then
                for id in $ids; do mark_nudged "$id"; done
                rm -f "$watch_pid"; set_state working
                printf 'Mailbox: %s open for you in %s. Read it and act on it; then set its Status: line (done, declined or waiting <on what>), report in %s/to-pm.md, and start the watch again.\n' \
                    "$ids" "$cc_file" "$mb"
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
        st="$(field "$mb/.cc-state" state)"; since="$(field "$mb/.cc-state" since)"
        to_cc="$(open_ids "$cc_file" | paste -sd' ' -)"
        to_pm="$(open_ids "$mb/to-pm.md" | paste -sd' ' -)"
        printf 'Engineer: %s%s\n' "${st:-not started}" "${since:+ since $since}"
        printf 'Open for the engineer: %s\n' "${to_cc:-none}"
        printf 'Open for the PM: %s\n' "${to_pm:-none}"
        dup_line "$cc_file"
        dup_line "$mb/to-pm.md"
        # Not watching: a PM message is open and either no session has ever been recorded, or the
        # state has not changed for an hour. A live watch turns waiting into working within a poll of
        # a new message, and every turn's end rewrites the state, so an hour of silence over an open
        # message means no session is listening. The person is told once per spell.
        if [ -n "$to_cc" ] && [ ! -f "$mb/.closed" ]; then
            spell=""
            if [ ! -f "$mb/.cc-session" ]; then spell="no session"
            elif [ ! -f "$mb/.cc-state" ] || older "$mb/.cc-state" 59; then spell="$st $since"
            fi
            if [ -n "$spell" ] && [ "$(cat "$mb/.pm-warned" 2>/dev/null)" != "$spell" ]; then
                printf '%s\n' "$spell" > "$mb/.pm-warned"
                printf 'For the person: the engineer isn'"'"'t watching the mailbox; type /projects:pair join in its session.\n'
            fi
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
        aw_lock "$mb/.post-lock" || { say "the mailbox is locked ($mb/.post-lock)"; exit 2; }
        if [ "$opt_from" = pm ] && [ -f "$mb/.pm-session" ]; then
            holder="$(field "$mb/.pm-session" token)"
            [ "$holder" = "$opt_pm" ] || printf 'pair: warning: another PM session holds this mailbox (since %s); two PMs writing one to-cc.md give the engineer two briefs. Posted anyway.\n' \
                "$(field "$mb/.pm-session" since)" >&2
        fi
        last="$(grep -oE "^## $prefix-[0-9]+" "$file" 2>/dev/null | sed "s/^## $prefix-//" | sed 's/^0*//' | sort -n | tail -n 1)"
        id="$(printf '%s-%03d' "$prefix" $(( ${last:-0} + 1 )))"
        printf '\n## %s · %s · %s\n%s\nStatus: open\n' "$id" "$(stamp)" "$opt_title" "$body" >> "$file"
        aw_unlock "$mb/.post-lock"
        printf '%s\n' "$id"
        exit 0
        ;;
esac
