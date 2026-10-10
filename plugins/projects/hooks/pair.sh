#!/usr/bin/env bash
# The engineer's side of a /projects:pair pairing, as two hooks:
#
#   pair.sh start   SessionStart: records this session's id in the mailbox (so the launcher can
#                   resume it) and tells the agent which messages are open for it.
#   pair.sh stop    Stop: keeps the session with the mailbox. An open PM message it has not yet been
#                   pointed at sends it back to work (exit 2, the reason on stderr). With nothing open,
#                   it waits for the next message, polling to-cc.md, and then lets the session stop.
#
# Inert unless PAIR_ROLE=cc and PAIR_MAILBOX names a mailbox folder: bin/pair.sh sets both when it
# launches the engineer, so every other session that loads this plugin passes straight through.
#
# Why a waiting Stop hook: a session that has ended its turn reads nothing until someone types into
# it, so a PM message written after the engineer's last turn used to sit unread until the person
# relayed it. A hook that sleeps costs no tokens; the session stays attentive to the mailbox and
# nothing else. Esc interrupts the wait when the person wants to type into the session.
#
# Settings, from the environment:
#   PAIR_WAIT_MINUTES   how long to wait for a message before letting the session stop (default 50;
#                       capped at 55 to stay inside the hook's 3600-second timeout; 0 = do not wait)
#   PAIR_POLL_SECONDS   how often to-cc.md is read while waiting (default 20)
#
# State it writes, all in the mailbox: .cc-session (the session id), .cc-state (working, waiting or
# stopped, since when) and .cc-nudged (each message id it has pointed the agent at, with a count).
# An id is pointed at no more than twice, so a message the agent cannot finish leads to a stop, not a
# loop; the agent marks such a message `waiting <on what>`, and the PM picks it up.
#
# Written for bash 3.2 (macOS /bin/bash) and POSIX awk; no jq.
set -u

mode="${1:-}"
[ "${PAIR_ROLE:-}" = "cc" ] || exit 0
mb="${PAIR_MAILBOX:-}"
[ -n "$mb" ] && [ -d "$mb" ] || exit 0
cc_file="$mb/to-cc.md"
nudged="$mb/.cc-nudged"

input="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$input" | tr '\n' ' ' \
    | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

stamp() { date '+%Y-%m-%d %H:%M'; }
set_state() { printf 'state: %s\nsince: %s\nsession: %s\n' "$1" "$(stamp)" "$sid" > "$mb/.cc-state" 2>/dev/null; }

# The ids of messages in to-cc.md whose last Status line begins "open" (bold labels allowed).
open_ids() {
    [ -f "$cc_file" ] || return 0
    awk '
        /^## [A-Za-z]+-[0-9]+/ { if (id != "" && st ~ /^open/) print id; id = $2; st = ""; next }
        /^\**Status:\**/ { s = $0; sub(/^\**Status:\**[ \t]*/, "", s); st = tolower(s) }
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
        if [ -n "$ids" ]; then printf 'Open for you in to-cc.md: %s.\n' "$ids"; else printf 'Nothing is open for you in to-cc.md.\n'; fi
        exit 0
        ;;
    stop)
        if [ -f "$mb/.closed" ]; then set_state stopped; exit 0; fi
        ids="$(due 2)"
        [ -n "$ids" ] && send_back "$ids"

        wait_min="${PAIR_WAIT_MINUTES:-50}"
        case "$wait_min" in ''|*[!0-9]*) wait_min=50 ;; esac
        [ "$wait_min" -gt 55 ] && wait_min=55
        poll="${PAIR_POLL_SECONDS:-20}"
        case "$poll" in ''|*[!0-9]*|0) poll=20 ;; esac
        if [ "$wait_min" -eq 0 ]; then set_state stopped; exit 0; fi

        set_state waiting
        end=$(( $(date +%s) + wait_min * 60 ))
        while [ "$(date +%s)" -lt "$end" ]; do
            sleep "$poll"
            if [ -f "$mb/.closed" ]; then set_state stopped; exit 0; fi
            # Only messages the agent has never been pointed at wake it from a wait.
            ids="$(due 1)"
            [ -n "$ids" ] && send_back "$ids"
        done
        set_state stopped
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
