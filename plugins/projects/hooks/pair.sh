#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# The engineer's side of a /projects:pair pairing: two hooks, and the watch the agent runs.
#
#   pair.sh start   SessionStart: records this session's id in the mailbox (so the launcher can
#                   resume it) and tells the agent which messages are open for it, and the command
#                   that starts the watch.
#   pair.sh stop    Stop: an open PM message the agent has not yet been pointed at twice sends it back
#                   to work (exit 2, the reason on stderr). Otherwise it returns at once.
#   pair.sh watch   Run by the agent as a background command, not by a hook. It ends, with one line
#                   naming the message, when a new open PM message arrives or the pairing is closed;
#                   a background command that ends is what wakes a session between turns.
#
# Inert unless PAIR_ROLE=cc and PAIR_MAILBOX names a mailbox folder: scripts/pair.sh sets both when it
# launches the engineer, so every other session that loads this plugin passes straight through.
#
# Why the watch is not in the Stop hook: a hook that waits holds the session. While it sleeps the
# session takes no other notification and looks busy to the person, who has to interrupt it to type.
# The hooks therefore check once and return, and the waiting happens in a background command, which
# holds nothing.
#
# Settings, from the environment:
#   PAIR_POLL_SECONDS   how often the watch reads to-cc.md (default 20)
#
# State it writes, all in the mailbox: .cc-session (the session id), .cc-state (working, waiting or
# stopped, since when; waiting means a watch is running), .cc-watch (the running watch's process id)
# and .cc-nudged (each message id it has pointed the agent at, with a count). An id is pointed at no
# more than twice, so a message the agent cannot finish leads to a stop, not a loop; the agent marks
# such a message `waiting <on what>`, and the PM picks it up.
#
# Written for bash 3.2 (macOS /bin/bash) and POSIX awk; no jq.
set -u

mode="${1:-}"
[ "${PAIR_ROLE:-}" = "cc" ] || exit 0
mb="${PAIR_MAILBOX:-}"
[ -n "$mb" ] && [ -d "$mb" ] || exit 0
cc_file="$mb/to-cc.md"
nudged="$mb/.cc-nudged"

watch_pid="$mb/.cc-watch"

# The hooks are handed the session as JSON on stdin; the watch is run by the agent and reads the
# session id the start hook recorded.
if [ "$mode" = "watch" ]; then
    sid="$(head -n 1 "$mb/.cc-session" 2>/dev/null | tr -d '[:space:]')"
else
    input="$(cat 2>/dev/null || true)"
    sid="$(printf '%s' "$input" | tr '\n' ' ' \
        | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    # The hooks keep to a kit workspace (lib/boundary.sh); the watch is the agent's own command.
    # shellcheck source=lib/boundary.sh
    . "$(dirname "$0")/lib/boundary.sh"
    [ -n "$(aw_workspace_root "$input")" ] || exit 0
fi

stamp() { date '+%Y-%m-%d %H:%M'; }
set_state() { printf 'state: %s\nsince: %s\nsession: %s\n' "$1" "$(stamp)" "$sid" > "$mb/.cc-state" 2>/dev/null; }

# The ids of messages in to-cc.md whose last Status begins "open" (bold labels allowed). The label
# counts wherever it sits in a line, since a writer may end a sentence with it; the last one in the
# message is the one that holds.
open_ids() {
    [ -f "$cc_file" ] || return 0
    awk '
        /^## [A-Za-z]+-[0-9]+/ { if (id != "" && st ~ /^open/) print id; id = $2; st = ""; next }
        /Status:/ { s = $0; while (match(s, /Status:\**[ \t]*/)) s = substr(s, RSTART + RLENGTH); st = tolower(s) }
        END { if (id != "" && st ~ /^open/) print id }
    ' "$cc_file"
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

case "$mode" in
    start)
        [ -n "$sid" ] && printf '%s\n' "$sid" > "$mb/.cc-session" 2>/dev/null
        set_state working
        ids="$(open_ids | paste -sd' ' -)"
        printf 'This session is the engineer in a /projects:pair pairing. Mailbox: %s (protocol in its README.md). ' "$mb"
        if [ -n "$ids" ]; then printf 'Open for you in to-cc.md: %s. ' "$ids"; else printf 'Nothing is open for you in to-cc.md. ' ; fi
        printf 'To hear of a new message between turns, run this as a background command and start it again each time it ends: PAIR_ROLE=cc PAIR_MAILBOX=%q bash %q watch\n' \
            "$mb" "$(cd "$(dirname "$0")" && pwd -P)/pair.sh"
        exit 0
        ;;
    stop)
        if [ -f "$mb/.closed" ]; then set_state stopped; exit 0; fi
        ids="$(due 2)"
        [ -n "$ids" ] && send_back "$ids"
        if watching; then set_state waiting; else set_state stopped; fi
        exit 0
        ;;
    watch)
        if watching; then printf 'Mailbox: a watch is already running (process %s).\n' "$(head -n 1 "$watch_pid")"; exit 0; fi
        poll="${PAIR_POLL_SECONDS:-20}"
        case "$poll" in ''|*[!0-9]*|0) poll=20 ;; esac
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
    *)
        exit 0
        ;;
esac
