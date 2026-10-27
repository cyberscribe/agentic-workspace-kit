# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh (SC2154); checks are "cond && ok || ko"
# (SC2015); single-quoted Markdown holds literal backticks (SC2016).
# shellcheck disable=SC2154,SC2015,SC2016
# Section 23: /projects:pair. The engineer's hooks (plugins/projects/hooks/pair.sh) against a fixture
# mailbox: inert without the launcher's variables, the session recorded, an open message sends the agent
# back, two nudges at most, the Stop hook never waits, the background watch ends on a new message or
# on .closed, .closed lets it stop. And the
# launcher's --print: a new session from KICKOFF.md, a resume when the transcript is there.
# Everything here is prefixed s23_, since the sections share one shell.

echo
echo "23 · /projects:pair: the engineer's hooks and the launcher"

s23_hook="$KIT/plugins/projects/hooks/pair.sh"
# This machine's default mailbox root is the fixture's alone, so a root the person has set never leaks in.
unset PAIR_MAILBOX_ROOT
export PAIR_CONFIG_DIR="$SCRATCH/s23/config"
s23_launch="$KIT/plugins/projects/scripts/pair.sh"
s23_p="$SCRATCH/s23/projects/00-demo"
s23_mb="$s23_p/mailbox"
mkdir -p "$s23_mb"
# The hooks keep to kit workspaces (hooks/lib/boundary.sh): the fixture's root carries a ledger as the marker.
mkdir -p "$SCRATCH/s23/.claude" && : > "$SCRATCH/s23/.claude/kit-templates.lock"

s23_reset() {
    rm -f "$s23_mb"/.cc-* "$s23_mb"/.pm-* "$s23_mb/.closed"
    printf '# To CC\n\n## PM-001 · 2026-10-10 10:00 · Brief\nBuild it.\nStatus: done 2026-10-10 11:00 abc1234\n' > "$s23_mb/to-cc.md"
    printf '# To the PM\n' > "$s23_mb/to-pm.md"
}
s23_add() { printf '\n## %s · 2026-10-10 12:00 · More\nAnd this.\nStatus: open\n' "$1" >> "$s23_mb/to-cc.md"; }
# s23_run <mode> [VAR=value...]: runs the hook with the launcher's variables; prints "<exit>|<stderr>".
s23_run() {
    local mode="$1" err rc; shift
    err="$(printf '{"session_id":"sess-123","cwd":"%s","hook_event_name":"x"}' "$s23_p" \
        | env PAIR_ROLE=cc PAIR_MAILBOX="$s23_mb" "$@" bash "$s23_hook" "$mode" 2>&1 >/dev/null)"
    rc=$?
    printf '%s|%s' "$rc" "$err"
}

s23_reset
s23_out="$(printf '{"session_id":"x"}' | env -u PAIR_ROLE -u PAIR_MAILBOX bash "$s23_hook" stop 2>&1; echo "rc=$?")"
[[ "$s23_out" == "rc=0" && ! -f "$s23_mb/.cc-state" ]] && ok "23 hook: inert without PAIR_ROLE and PAIR_MAILBOX" \
    || ko "23 hook: inert without PAIR_ROLE and PAIR_MAILBOX" "$s23_out"

s23_ctx="$(printf '{"session_id":"sess-123","cwd":"%s"}' "$s23_p" | PAIR_ROLE=cc PAIR_MAILBOX="$s23_mb" bash "$s23_hook" start)"
[[ "$(cat "$s23_mb/.cc-session" 2>/dev/null)" == "sess-123" && "$s23_ctx" == *"Nothing is open"* \
    && "$s23_ctx" == *"background command"*"pair.sh watch"* ]] \
    && ok "23 hook start: records the session id, says nothing is open and gives the watch command" \
    || ko "23 hook start: records the session id, says nothing is open and gives the watch command" "$s23_ctx"

s23_out="$(s23_run stop)"
[[ "$s23_out" == "0|" ]] && grep -q '^state: stopped' "$s23_mb/.cc-state" \
    && ok "23 hook stop: nothing open lets the session stop" || ko "23 hook stop: nothing open lets the session stop" "$s23_out"

# The Stop hook holds nothing: with nothing open it is back well inside a second or two, whatever an
# older launcher left in the environment.
s23_t0=$(date +%s)
s23_out="$(s23_run stop PAIR_WAIT_MINUTES=50)"
s23_dt=$(( $(date +%s) - s23_t0 ))
[[ "$s23_out" == "0|" && $s23_dt -lt 3 ]] && ok "23 hook stop: returns at once and never waits" \
    || ko "23 hook stop: returns at once and never waits" "$s23_out after ${s23_dt}s"

s23_add PM-002
s23_out="$(s23_run stop)"
[[ "$s23_out" == 2\|*PM-002* ]] && ok "23 hook stop: an open message sends the agent back (exit 2, naming it)" \
    || ko "23 hook stop: an open message sends the agent back (exit 2, naming it)" "$s23_out"
s23_out="$(s23_run stop)"
[[ "$s23_out" == 2\|*PM-002* ]] && ok "23 hook stop: a second nudge for the same message" || ko "23 hook stop: a second nudge for the same message" "$s23_out"
s23_out="$(s23_run stop)"
[[ "$s23_out" == "0|" ]] && ok "23 hook stop: no third nudge, so a stuck message cannot loop" || ko "23 hook stop: no third nudge, so a stuck message cannot loop" "$s23_out"

# A Status that ends a sentence, rather than starting a line, still counts; the last one holds.
s23_reset
printf '\n## PM-005 · 2026-10-10 12:00 · Inline\nDo this. Standing rules as before. Status: open\n' >> "$s23_mb/to-cc.md"
s23_out="$(s23_run stop)"
[[ "$s23_out" == 2\|*PM-005* ]] && ok "23 hook stop: a Status at the end of a sentence is read" || ko "23 hook stop: a Status at the end of a sentence is read" "$s23_out"
s23_reset
printf '\n## PM-006 · 2026-10-10 12:00 · Quoted\nSet it to `Status: open` when you write one.\n**Status:** done 12:30\n' >> "$s23_mb/to-cc.md"
s23_out="$(s23_run stop)"
[[ "$s23_out" == "0|" ]] && ok "23 hook stop: the last Status in a message is the one that holds" || ko "23 hook stop: the last Status in a message is the one that holds" "$s23_out"

# A message with no Status line was never marked, so it is still open: hiding it would leave the
# engineer deaf to it for good (2026-10-22: eight PM messages written without one went unseen).
s23_reset
printf '\n## PM-007 · 2026-10-10 12:00 · Unmarked\nDo this too.\n' >> "$s23_mb/to-cc.md"
s23_out="$(s23_run stop)"
[[ "$s23_out" == 2\|*PM-007* ]] && ok "23 hook stop: a message with no Status line counts as open" || ko "23 hook stop: a message with no Status line counts as open" "$s23_out"
s23_reset
printf '\n## PM-008 · 2026-10-10 12:00 · Unmarked last\nAnd this.\n\n## PM-009 · 2026-10-10 12:01 · Marked\nDone already.\nStatus: done 12:30\n' >> "$s23_mb/to-cc.md"
s23_out="$(s23_run stop)"
[[ "$s23_out" == 2\|*PM-008* && "$s23_out" != *PM-009* ]] && ok "23 hook stop: an unmarked message is found between marked ones" || ko "23 hook stop: an unmarked message is found between marked ones" "$s23_out"

# The start hook runs after a compaction too, so a session that lost track of the mailbox is told again.
grep -q '"startup|resume|compact"' "$KIT/plugins/projects/hooks/hooks.json" \
    && ok "23 hooks.json: the start hook runs on compact as well as startup and resume" \
    || ko "23 hooks.json: the start hook runs on compact as well as startup and resume" "matcher missing"

# The watch: a background command the agent runs. It ends when a message arrives, naming it.
s23_watch() { env PAIR_ROLE=cc PAIR_MAILBOX="$s23_mb" PAIR_POLL_SECONDS=1 bash "$s23_hook" watch </dev/null 2>&1; }
s23_reset
printf 'sess-123\n' > "$s23_mb/.cc-session"
( sleep 2; s23_add PM-003 ) &
s23_t0=$(date +%s)
s23_out="$(s23_watch; echo "rc=$?")"
s23_dt=$(( $(date +%s) - s23_t0 ))
wait
[[ "$s23_out" == *PM-003*"rc=0" && $s23_dt -lt 15 && ! -f "$s23_mb/.cc-watch" ]] && grep -q '^state: working' "$s23_mb/.cc-state" \
    && ok "23 watch: a message written while it runs ends it, naming the message (${s23_dt}s)" \
    || ko "23 watch: a message written while it runs ends it, naming the message" "$s23_out after ${s23_dt}s"
s23_out="$(s23_run stop)"
[[ "$s23_out" == 2\|*PM-003* ]] && s23_out="$(s23_run stop)" && [[ "$s23_out" == "0|" ]] \
    && ok "23 watch: a message it reported gets one more nudge from the Stop hook, then none" \
    || ko "23 watch: a message it reported gets one more nudge from the Stop hook, then none" "$s23_out"

# While a watch runs the Stop hook says waiting, a second watch stands down, and a signal ends it tidily.
s23_reset
s23_watch >/dev/null &
s23_pid=$!
s23_i=0; until [[ -f "$s23_mb/.cc-watch" || $s23_i -ge 50 ]]; do sleep 0.1; s23_i=$((s23_i + 1)); done
s23_out="$(s23_run stop)"
s23_was="$(sed -n 1p "$s23_mb/.cc-state" 2>/dev/null)"
s23_two="$(s23_watch)"
kill -TERM "$(cat "$s23_mb/.cc-watch" 2>/dev/null)" 2>/dev/null; wait "$s23_pid" 2>/dev/null
[[ "$s23_out" == "0|" && "$s23_was" == "state: waiting" && "$s23_two" == *"already running"* && ! -f "$s23_mb/.cc-watch" ]] \
    && grep -q '^state: stopped' "$s23_mb/.cc-state" \
    && ok "23 watch: the Stop hook reads waiting while it runs; a second one stands down; a signal leaves stopped" \
    || ko "23 watch: the Stop hook reads waiting while it runs; a second one stands down; a signal leaves stopped" "stop '$s23_out', was '$s23_was', second '$s23_two', now '$(sed -n 1p "$s23_mb/.cc-state" 2>/dev/null)'"

s23_reset
touch "$s23_mb/.closed"
s23_out="$(s23_watch)"
[[ "$s23_out" == *"closed the pairing"* ]] && ok "23 watch: .closed ends it at once" || ko "23 watch: .closed ends it at once" "$s23_out"

s23_reset
touch "$s23_mb/.closed"
s23_add PM-004
s23_out="$(s23_run stop)"
[[ "$s23_out" == "0|" ]] && ok "23 hook stop: .closed lets the session stop at once" || ko "23 hook stop: .closed lets the session stop at once" "$s23_out"

# ---- Joining a session that was started without the launcher ---------------------------------------
# The registry is the section's own file, never the person's: PAIR_REGISTRY is set on every call, and the
# runner's own default points at a scratch path too.
s23_reg="$SCRATCH/s23/pairings"
s23_other="$SCRATCH/s23/elsewhere"
mkdir -p "$s23_other"
# s23_bare <args...>: the hook with no launcher variables, the section's registry and no session id
# unless the call sets one.
s23_bare() { env -u PAIR_ROLE -u PAIR_MAILBOX -u CLAUDE_CODE_SESSION_ID PAIR_REGISTRY="$s23_reg" "$@"; }
# s23_hook_in <mode> <session id> <cwd> [VAR=value...]: a hook call as Claude Code makes it, with no
# launcher variables; prints "<exit>|<stderr>".
s23_hook_in() {
    local mode="$1" s="$2" c="$3" err rc; shift 3
    err="$(printf '{"session_id":"%s","cwd":"%s","hook_event_name":"x"}' "$s" "$c" \
        | s23_bare "$@" bash "$s23_hook" "$mode" 2>&1 >/dev/null)"
    rc=$?
    printf '%s|%s' "$rc" "$err"
}
s23_bound() { awk -F'\t' -v m="$(cd "$s23_mb" && pwd -P)" '$1 == m { print $2 }' "$s23_reg" 2>/dev/null; }
s23_join_reset() { s23_reset; rm -f "$s23_reg"; }

s23_join_reset
s23_out="$(cd "$s23_p" && s23_bare CLAUDE_CODE_SESSION_ID=sess-j bash "$s23_hook" join --mailbox "$s23_mb" 2>&1; echo "rc=$?")"
[[ "$s23_out" == *"watch --mailbox"*"rc=0" && "$(s23_bound)" == "-" ]] && grep -q '^session: sess-j$' "$s23_mb/.cc-join" \
    && ok "23 join: writes .cc-join with the session id, lists the mailbox unbound, and gives the watch command with --mailbox" \
    || ko "23 join: writes .cc-join with the session id, lists the mailbox unbound, and gives the watch command with --mailbox" "$s23_out"
s23_out="$(s23_hook_in stop sess-j "$s23_p")"
[[ "$s23_out" == 2\|*"joined the pairing"* && "$(cat "$s23_mb/.cc-session" 2>/dev/null)" == sess-j && "$(s23_bound)" == sess-j \
    && ! -f "$s23_mb/.cc-join" ]] && grep -q '^state: working' "$s23_mb/.cc-state" \
    && ok "23 join: the Stop hook of that session claims it — .cc-session written, registry bound, state working, .cc-join gone, the agent told" \
    || ko "23 join: the Stop hook of that session claims it — .cc-session written, registry bound, state working, .cc-join gone, the agent told" "$s23_out; bound '$(s23_bound)'"

# Where the join could see no session id, the folder decides.
s23_join_reset
(cd "$s23_p" && s23_bare bash "$s23_hook" join --mailbox "$s23_mb" >/dev/null 2>&1)
s23_out="$(s23_hook_in stop sess-k "$s23_other")"
s23_held="$( [[ "$s23_out" == "0|" && -f "$s23_mb/.cc-join" && ! -f "$s23_mb/.cc-session" ]] && echo y)"
s23_out2="$(s23_hook_in stop sess-k "$s23_p")"
[[ "$s23_held" == y && "$s23_out2" == 2\|*"joined"* && "$(s23_bound)" == sess-k ]] \
    && ok "23 join: with no session id, a session in another folder does not claim it; one in the join's folder does" \
    || ko "23 join: with no session id, a session in another folder does not claim it; one in the join's folder does" "other: $s23_out; same: $s23_out2"

s23_join_reset
(cd "$s23_p" && s23_bare CLAUDE_CODE_SESSION_ID=sess-j bash "$s23_hook" join --mailbox "$s23_mb" >/dev/null 2>&1)
s23_out="$(s23_hook_in stop sess-other "$s23_p")"
[[ "$s23_out" == "0|" && -f "$s23_mb/.cc-join" && ! -f "$s23_mb/.cc-session" ]] \
    && ok "23 join: a different session in the same folder does not claim a join that names its session" \
    || ko "23 join: a different session in the same folder does not claim a join that names its session" "$s23_out"
printf 'requested: %s\nat: old\ncwd: %s\nsession: sess-j\n' "$(( $(date +%s) - 700 ))" "$(cd "$s23_p" && pwd -P)" > "$s23_mb/.cc-join"
s23_out="$(s23_hook_in stop sess-j "$s23_p")"
[[ "$s23_out" == "0|" && ! -f "$s23_mb/.cc-session" ]] && ok "23 join: a join older than 10 minutes is not claimed" \
    || ko "23 join: a join older than 10 minutes is not claimed" "$s23_out"

# Bound, the hooks act on the session id alone; the launcher's variables still win where they are set.
s23_join_reset
(cd "$s23_p" && s23_bare CLAUDE_CODE_SESSION_ID=sess-j bash "$s23_hook" join --mailbox "$s23_mb" >/dev/null 2>&1)
s23_hook_in stop sess-j "$s23_p" >/dev/null
s23_ctx="$(printf '{"session_id":"sess-j","cwd":"%s"}' "$s23_p" | s23_bare bash "$s23_hook" start)"
s23_add PM-010
s23_out="$(s23_hook_in stop sess-j "$s23_p")"
s23_none="$(s23_hook_in stop sess-nobody "$s23_p")"
[[ "$s23_ctx" == *"engineer in a /projects:pair pairing"*"watch --mailbox"* && "$s23_ctx" != *PAIR_ROLE=* \
    && "$s23_out" == 2\|*PM-010* && "$s23_none" == "0|" ]] \
    && ok "23 join: once bound, start and stop act with no PAIR_ROLE or PAIR_MAILBOX; another session stays inert" \
    || ko "23 join: once bound, start and stop act with no PAIR_ROLE or PAIR_MAILBOX; another session stays inert" "start: $s23_ctx"$'\n'"stop: $s23_out; other: $s23_none"
s23_out="$(printf '{"session_id":"sess-123","cwd":"%s"}' "$s23_p" | env PAIR_ROLE=cc PAIR_MAILBOX="$s23_mb" PAIR_REGISTRY="$s23_reg" bash "$s23_hook" start)"
[[ "$s23_out" == *"PAIR_ROLE=cc PAIR_MAILBOX="* && "$(cat "$s23_mb/.cc-session")" == sess-123 ]] \
    && ok "23 join: the launcher's path is unchanged alongside the registry" \
    || ko "23 join: the launcher's path is unchanged alongside the registry" "$s23_out"

# The watch without the launcher's variables.
# The session id arrives while it runs, as when a join is claimed after the watch started.
s23_join_reset
( sleep 1; printf 'sess-j\n' > "$s23_mb/.cc-session"; sleep 1; s23_add PM-011 ) &
s23_out="$(s23_bare PAIR_POLL_SECONDS=1 bash "$s23_hook" watch --mailbox "$s23_mb" </dev/null 2>&1; echo "rc=$?")"
wait
[[ "$s23_out" == *PM-011*"rc=0" && ! -f "$s23_mb/.cc-watch" ]] && grep -q '^session: sess-j$' "$s23_mb/.cc-state" \
    && ok "23 watch --mailbox: runs with no PAIR_ROLE or PAIR_MAILBOX, ends on a new message, and records a session id that arrived late" \
    || ko "23 watch --mailbox: runs with no PAIR_ROLE or PAIR_MAILBOX, ends on a new message, and records a session id that arrived late" "$s23_out; $(cat "$s23_mb/.cc-state")"
s23_out="$(s23_bare bash "$s23_hook" watch </dev/null 2>&1; echo "rc=$?")"
[[ "$s23_out" == *"--mailbox"*"rc=2" ]] && ok "23 watch: with no mailbox named and none to find, it says how to name one" \
    || ko "23 watch: with no mailbox named and none to find, it says how to name one" "$s23_out"

# A join no hook claims: the watch says so, with the command that resumes this session through the launcher.
s23_join_reset
(cd "$s23_p" && s23_bare CLAUDE_CODE_SESSION_ID=sess-j bash "$s23_hook" join --mailbox "$s23_mb" >/dev/null 2>&1)
s23_out="$(s23_bare PAIR_POLL_SECONDS=1 PAIR_JOIN_GRACE=1 bash "$s23_hook" watch --mailbox "$s23_mb" </dev/null 2>&1)"
[[ "$s23_out" == *"has not been claimed"*"scripts/pair.sh"*"--session sess-j"* && ! -f "$s23_mb/.cc-join" ]] \
    && ok "23 join: unclaimed after the grace period, the watch ends and gives the launcher command for this session" \
    || ko "23 join: unclaimed after the grace period, the watch ends and gives the launcher command for this session" "$s23_out"

# leave and .closed unbind.
s23_join_reset
(cd "$s23_p" && s23_bare CLAUDE_CODE_SESSION_ID=sess-j bash "$s23_hook" join --mailbox "$s23_mb" >/dev/null 2>&1)
s23_hook_in stop sess-j "$s23_p" >/dev/null
s23_out="$(s23_bare bash "$s23_hook" leave --mailbox "$s23_mb" 2>&1)"
s23_add PM-012
s23_out2="$(s23_hook_in stop sess-j "$s23_p")"
[[ "$s23_out" == *"left the pairing"* && -z "$(s23_bound)" && "$s23_out2" == "0|" ]] && grep -q '^state: stopped' "$s23_mb/.cc-state" \
    && ok "23 leave: unbinds the session; its Stop hook no longer acts on the mailbox" \
    || ko "23 leave: unbinds the session; its Stop hook no longer acts on the mailbox" "$s23_out; then $s23_out2; bound '$(s23_bound)'"
s23_join_reset
(cd "$s23_p" && s23_bare CLAUDE_CODE_SESSION_ID=sess-j bash "$s23_hook" join --mailbox "$s23_mb" >/dev/null 2>&1)
s23_hook_in stop sess-j "$s23_p" >/dev/null
touch "$s23_mb/.closed"
s23_add PM-013
s23_out="$(s23_hook_in stop sess-j "$s23_p")"
s23_out2="$(printf '{"session_id":"sess-j","cwd":"%s"}' "$s23_p" | s23_bare bash "$s23_hook" start)"
[[ "$s23_out" == "0|" && -z "$(s23_bound)" && -z "$s23_out2" ]] \
    && ok "23 .closed: the joined session's Stop hook unbinds it, and its start hook is silent after" \
    || ko "23 .closed: the joined session's Stop hook unbinds it, and its start hook is silent after" "stop: $s23_out; start: $s23_out2; bound '$(s23_bound)'"
s23_out="$(cd "$s23_p" && s23_bare bash "$s23_hook" join --mailbox "$s23_mb" 2>&1; echo "rc=$?")"
[[ "$s23_out" == *"closed"*"rc=2" ]] && ok "23 join: a closed pairing cannot be joined" || ko "23 join: a closed pairing cannot be joined" "$s23_out"

# ---- The PM's check-in -----------------------------------------------------------------------------
s23_join_reset
s23_add PM-014
s23_out="$(s23_bare bash "$s23_hook" check --mailbox "$s23_mb")"
s23_out2="$(s23_bare bash "$s23_hook" check --mailbox "$s23_mb")"
[[ "$s23_out" == *"not started"*"PM-014"*"isn't watching the mailbox; type /projects:pair join"* && "$s23_out2" != *"isn't watching"* ]] \
    && ok "23 check: no engineer session and a message open gives the join line, once" \
    || ko "23 check: no engineer session and a message open gives the join line, once" "first: $s23_out"$'\n'"second: $s23_out2"
printf 'sess-j\n' > "$s23_mb/.cc-session"
printf 'state: waiting\nsince: 2026-10-23 12:29\nsession: sess-j\n' > "$s23_mb/.cc-state"
s23_out="$(s23_bare bash "$s23_hook" check --mailbox "$s23_mb")"
age "$s23_mb/.cc-state" 0.05
s23_out2="$(s23_bare bash "$s23_hook" check --mailbox "$s23_mb")"
s23_out3="$(s23_bare bash "$s23_hook" check --mailbox "$s23_mb")"
[[ "$s23_out" != *"isn't watching"* && "$s23_out2" == *"Engineer: waiting since 2026-10-23 12:29"*"isn't watching"* && "$s23_out3" != *"isn't watching"* ]] \
    && ok "23 check: a state an hour old with a message open gives the join line once; a fresh one does not" \
    || ko "23 check: a state an hour old with a message open gives the join line once; a fresh one does not" "fresh: $s23_out"$'\n'"old: $s23_out2"$'\n'"again: $s23_out3"
s23_reset
printf 'sess-j\n' > "$s23_mb/.cc-session"; printf 'state: waiting\nsince: x\n' > "$s23_mb/.cc-state"; age "$s23_mb/.cc-state" 0.05
s23_out="$(s23_bare bash "$s23_hook" check --mailbox "$s23_mb")"
[[ "$s23_out" == *"Open for the engineer: none"* && "$s23_out" != *"isn't watching"* ]] \
    && ok "23 check: an old state with nothing open says nothing about watching" \
    || ko "23 check: an old state with nothing open says nothing about watching" "$s23_out"

# ---- Posting under a lock, and one PM per mailbox ---------------------------------------------------
s23_reset
printf 'token: tok-a\nsince: 2026-10-23 16:00\n' > "$s23_mb/.pm-session"
for s23_i in 1 2 3 4 5 6; do
    printf 'Message %s.\n' "$s23_i" | s23_bare bash "$s23_hook" post --mailbox "$s23_mb" --from pm --pm tok-a --title "Item $s23_i" >/dev/null 2>&1 &
done
wait
s23_ids="$(grep -oE '^## PM-[0-9]+' "$s23_mb/to-cc.md" | sort | uniq -d)"
s23_n="$(grep -cE '^## PM-' "$s23_mb/to-cc.md")"
[[ -z "$s23_ids" && "$s23_n" == 7 && "$(grep -c '^Status: open$' "$s23_mb/to-cc.md")" == 6 && ! -d "$s23_mb/.pm-lock" && ! -d "$s23_mb/.post-lock" ]] \
    && ok "23 post: six PM posts at once take six different ids, each with Status: open, and leave no lock" \
    || ko "23 post: six PM posts at once take six different ids, each with Status: open, and leave no lock" "duplicates: $s23_ids; headings: $s23_n"
s23_out="$(printf 'Hello.\n' | s23_bare bash "$s23_hook" post --mailbox "$s23_mb" --from pm --pm tok-b --title "Second PM" 2>&1)"
s23_out2="$(printf 'Report.\n' | s23_bare bash "$s23_hook" post --mailbox "$s23_mb" --from cc --title "Gate A" 2>&1)"
[[ "$s23_out" == *"another PM session holds this mailbox"*PM-008* && "$s23_out2" == CC-001 ]] && grep -q '^## CC-001 · .* · Gate A$' "$s23_mb/to-pm.md" \
    && ok "23 post: a PM without the holder's token is warned and still posted; the engineer's posts go to to-pm.md as CC ids" \
    || ko "23 post: a PM without the holder's token is warned and still posted; the engineer's posts go to to-pm.md as CC ids" "$s23_out"$'\n'"$s23_out2"

# A duplicate id is flagged, not read as an amendment: check and the start hook name it.
s23_reset
printf '\n## PM-019 · 2026-10-23 12:00 · One\nFirst.\nStatus: open\n\n## PM-019 · 2026-10-23 12:05 · Two\nSecond.\nStatus: open\n' >> "$s23_mb/to-cc.md"
s23_out="$(s23_bare bash "$s23_hook" check --mailbox "$s23_mb")"
s23_ctx="$(printf '{"session_id":"sess-123","cwd":"%s"}' "$s23_p" | PAIR_ROLE=cc PAIR_MAILBOX="$s23_mb" PAIR_REGISTRY="$s23_reg" bash "$s23_hook" start)"
[[ "$s23_out" == *"share an id"*"PM-019 (2)"* && "$s23_ctx" == *"share an id"*"PM-019 (2)"* ]] \
    && ok "23 duplicate ids: check and the start hook name an id two messages share" \
    || ko "23 duplicate ids: check and the start hook name an id two messages share" "check: $s23_out"$'\n'"start: $s23_ctx"

# ---- registry.sh and the lock under it (hooks/lib/lock.sh) -----------------------------------------
s23_rs="$KIT/plugins/projects/scripts/registry.sh"
s23_b="$SCRATCH/s23/board.md"
printf '# Claims board\n' > "$s23_b"
for s23_i in 1 2 3 4 5 6 7 8 9 10 11 12; do bash "$s23_rs" add "$s23_b" "claim $s23_i" >/dev/null 2>&1 & done
wait
[[ "$(head -n 1 "$s23_b")" == "# Claims board" && "$(grep -c '^claim ' "$s23_b")" == 12 && ! -d "$s23_b.lock" ]] \
    && ok "23 registry.sh: twelve writers at once all land, the header stays and no lock is left" \
    || ko "23 registry.sh: twelve writers at once all land, the header stays and no lock is left" "$(cat "$s23_b")"
bash "$s23_rs" replace "$s23_b" "claim 12" "claim 12 done" >/dev/null && bash "$s23_rs" remove "$s23_b" "claim 3" >/dev/null
[[ "$(grep -c '^claim ' "$s23_b")" == 11 && "$(grep -c '^claim 12 done$' "$s23_b")" == 1 && "$(head -n 1 "$s23_b")" == "# Claims board" ]] \
    && ok "23 registry.sh: replace and remove change only the lines holding the text" \
    || ko "23 registry.sh: replace and remove change only the lines holding the text" "$(cat "$s23_b")"
# A change that would lose the header leaves the file as it was.
s23_before="$(cat "$s23_b")"
s23_out="$(bash -c '. "$1"; aw_rewrite "$2" tail -n +2' _ "$KIT/plugins/projects/hooks/lib/lock.sh" "$s23_b" 2>&1; echo "rc=$?")"
[[ "$s23_out" == "rc=1" && "$(cat "$s23_b")" == "$s23_before" && ! -d "$s23_b.lock" ]] \
    && ok "23 lock: a rewrite that drops the header line is refused and the file left as it was" \
    || ko "23 lock: a rewrite that drops the header line is refused and the file left as it was" "$s23_out"
# A lock whose holder has died is taken over at once, quietly; one a live holder has kept for over a
# minute is taken over with a warning that names the holder.
mkdir "$s23_b.lock" && printf '999999\n' > "$s23_b.lock/pid"
s23_t0=$(date +%s)
s23_out="$(bash "$s23_rs" add "$s23_b" "after a dead holder" 2>&1 >/dev/null)"
[[ -z "$s23_out" && $(( $(date +%s) - s23_t0 )) -lt 3 ]] && grep -q 'after a dead holder' "$s23_b" \
    && ok "23 lock: a dead holder's lock is taken over at once, with nothing said" \
    || ko "23 lock: a dead holder's lock is taken over at once, with nothing said" "$s23_out"
sleep 300 & s23_live=$!
mkdir "$s23_b.lock" && printf '%s\n' "$s23_live" > "$s23_b.lock/pid" && printf '%s\n' "$(( $(date +%s) - 95 ))" > "$s23_b.lock/since"
python3 -c 'import os,sys,time; t = time.time() - 95; os.utime(sys.argv[1], (t, t))' "$s23_b.lock"
s23_out="$(bash "$s23_rs" add "$s23_b" "after a live holder" 2>&1 >/dev/null)"
kill "$s23_live" 2>/dev/null; wait "$s23_live" 2>/dev/null
[[ "$s23_out" == *"taking over"*"from process $s23_live"*"9"[0-9]" seconds"* ]] && grep -q 'after a live holder' "$s23_b" \
    && ok "23 lock: a live holder's lock older than a minute is taken over with a warning naming the process and the time" \
    || ko "23 lock: a live holder's lock older than a minute is taken over with a warning naming the process and the time" "$s23_out"

# The guidance the model follows: these are instruction-presence checks, since the model applies them.
s23_ex="$KIT/plugins/projects/examples/pair"
s23_cmd="$KIT/plugins/projects/commands/pair.md"
s23_bad=""
grep -q 'pair.sh post' "$s23_ex/README.md" && grep -q 'not as an amendment' "$s23_ex/README.md" || s23_bad+="README: ids under post, duplicates read in full"$'\n'
grep -q 'trailing `\\`' "$s23_ex/README.md" && grep -q 'output to expect' "$s23_ex/README.md" || s23_bad+="README: the paste rule"$'\n'
grep -q 'scripts/registry.sh add|remove|replace' "$s23_ex/README.md" || s23_bad+="README: shared files through registry.sh"$'\n'
grep -q 'git commit --dry-run' "$s23_ex/KICKOFF.md" && grep -q 'first report' "$s23_ex/KICKOFF.md" || s23_bad+="KICKOFF: test each grant first"$'\n'
grep -q 'paste rule' "$s23_ex/KICKOFF.md" || s23_bad+="KICKOFF: the paste rule"$'\n'
grep -q '\*\*the grants:\*\*' "$s23_cmd" && grep -q 'paste rule' "$s23_cmd" || s23_bad+="command: grants in the brief, the paste rule for the PM"$'\n'
grep -q '^## Joining' "$s23_cmd" && grep -q 'hooks/pair.sh" join --mailbox' "$s23_cmd" && grep -q '/projects:pair join' "$s23_cmd" || s23_bad+="command: joining"$'\n'
grep -q '`.pm-session`' "$s23_cmd" && grep -q 'pair.sh check' "$s23_cmd" || s23_bad+="command: one PM per mailbox, the check"$'\n'
empty "23 guidance: ids under post, the paste rule, shared files, the grants test, join, one PM and the check are in the README, KICKOFF and command" "$s23_bad"

# ---- The launcher ---------------------------------------------------------------------------------
s23_reset
printf 'Kickoff prompt for the demo.\n' > "$s23_mb/KICKOFF.md"
s23_cfg="$SCRATCH/s23/claude-config"
mkdir -p "$s23_cfg/projects/x"
s23_out="$(CLAUDE_CONFIG_DIR="$s23_cfg" bash "$s23_launch" "$s23_p" --print 2>&1)"
[[ "$s23_out" == *"Starting a new session, demo-cc"* && "$s23_out" == *"--name demo-cc"* \
    && "$s23_out" == *"--permission-mode auto"* && "$s23_out" == *"--plugin-dir"* && "$s23_out" == *Kickoff* ]] \
    && ok "23 launcher: a new session, named without the priority prefix, auto mode, KICKOFF.md as the prompt" \
    || ko "23 launcher: a new session, named without the priority prefix, auto mode, KICKOFF.md as the prompt" "$s23_out"

printf 'sess-123\n' > "$s23_mb/.cc-session"
: > "$s23_cfg/projects/x/sess-123.jsonl"
s23_out="$(CLAUDE_CONFIG_DIR="$s23_cfg" bash "$s23_launch" "$s23_p" --print --ultracode 2>&1)"
[[ "$s23_out" == *"Resuming session sess-123"* && "$s23_out" == *"--resume sess-123"* && "$s23_out" == *"--effort ultracode"* ]] \
    && ok "23 launcher: resumes the recorded session when its transcript is there; --ultracode carried" \
    || ko "23 launcher: resumes the recorded session when its transcript is there; --ultracode carried" "$s23_out"
s23_out="$(CLAUDE_CONFIG_DIR="$s23_cfg" bash "$s23_launch" "$s23_p" --print --new 2>&1)"
[[ "$s23_out" == *"Starting a new session"* ]] && ok "23 launcher: --new starts fresh" || ko "23 launcher: --new starts fresh" "$s23_out"
rm -f "$s23_cfg/projects/x/sess-123.jsonl"
s23_out="$(CLAUDE_CONFIG_DIR="$s23_cfg" bash "$s23_launch" "$s23_p" --print 2>&1)"
[[ "$s23_out" == *"Starting a new session"* ]] && ok "23 launcher: a pruned transcript means a new session" || ko "23 launcher: a pruned transcript means a new session" "$s23_out"
# A resume starts in the folder the transcript records, since Claude Code finds a session from the
# folder it is started in; --session resumes a named one.
printf 'sess-123\n' > "$s23_mb/.cc-session"
printf '{"type":"mode"}\n{"type":"user","cwd":"%s","sessionId":"sess-123"}\n{"type":"user","cwd":"%s"}\n' "$s23_other" "$s23_p" > "$s23_cfg/projects/x/sess-123.jsonl"
s23_out="$(CLAUDE_CONFIG_DIR="$s23_cfg" bash "$s23_launch" "$s23_p" --print 2>&1)"
[[ "$s23_out" == *"--resume sess-123"* && "$s23_out" == *"cd $s23_other &&"* ]] \
    && ok "23 launcher: a resume starts in the transcript's first recorded folder, not the project folder" \
    || ko "23 launcher: a resume starts in the transcript's first recorded folder, not the project folder" "$s23_out"
printf '{"type":"user","cwd":"%s"}\n' "$s23_p" > "$s23_cfg/projects/x/sess-777.jsonl"
s23_out="$(CLAUDE_CONFIG_DIR="$s23_cfg" bash "$s23_launch" "$s23_p" --print --session sess-777 2>&1)"
s23_out2="$(CLAUDE_CONFIG_DIR="$s23_cfg" bash "$s23_launch" "$s23_p" --print --session sess-none 2>&1; echo "rc=$?")"
[[ "$s23_out" == *"--resume sess-777"* && "$s23_out2" == *"no transcript for session sess-none"*"rc=2" ]] \
    && ok "23 launcher: --session resumes that session, and refuses one with no transcript here" \
    || ko "23 launcher: --session resumes that session, and refuses one with no transcript here" "$s23_out"$'\n'"$s23_out2"
rm -f "$s23_cfg/projects/x/sess-123.jsonl" "$s23_cfg/projects/x/sess-777.jsonl"
s23_out="$(bash "$s23_launch" "$SCRATCH/s23" --print 2>&1; echo "rc=$?")"
[[ "$s23_out" == *"no mailbox"*"rc=2" ]] && ok "23 launcher: no mailbox, no launch" || ko "23 launcher: no mailbox, no launch" "$s23_out"

# ---- A mailbox anywhere: one-off, or this machine's default root (hooks/lib/mailbox.sh) -----------
s23_root="$SCRATCH/s23-outside/root"
s23_far="$SCRATCH/s23/projects/01-far"
mkdir -p "$s23_root" "$s23_far"
s23_out="$(bash "$s23_hook" default "$s23_root" 2>&1)"
s23_w="$(bash "$s23_hook" where "$s23_far" 2>&1)"
[[ "$s23_out" == *"default mailbox root: $(cd "$s23_root" && pwd -P)"* && "$s23_w" == *"mailbox: $(cd "$s23_root" && pwd -P)/far"* \
    && "$s23_w" == *"state: new"* && "$s23_w" == *"repository: none"* ]] \
    && ok "23 where: a default root puts a new mailbox at <root>/<slug>, outside every repository" \
    || ko "23 where: a default root puts a new mailbox at <root>/<slug>, outside every repository" "$s23_out"$'\n'"$s23_w"
s23_fmb="$(cd "$s23_root" && pwd -P)/far"
bash "$s23_hook" init --mailbox "$s23_fmb" --name "Far project" >/dev/null 2>&1
s23_w="$(bash "$s23_hook" where "$s23_far" 2>&1)"
[[ -f "$s23_fmb/to-cc.md" && -f "$s23_fmb/to-pm.md" && -f "$s23_fmb/status-cc.md" && -f "$s23_fmb/status-pm.md" \
    && "$(head -n 1 "$s23_fmb/README.md")" == "# Mailbox: Far project" && "$s23_w" == *"state: existing"* ]] \
    && ok "23 init: makes the protocol README, both message files and both status files in any folder" \
    || ko "23 init: makes the protocol README, both message files and both status files in any folder" "$s23_w"
printf 'Read {mailbox}/README.md, then {mailbox}/to-cc.md.\n' > "$s23_fmb/KICKOFF.md"
s23_out="$(CLAUDE_CONFIG_DIR="$SCRATCH/s23/claude-none" bash "$s23_launch" "$s23_far" --print 2>&1)"
[[ "$s23_out" == *"PAIR_MAILBOX=$s23_fmb "* && "$s23_out" == *"--add-dir $s23_fmb"* \
    && "$s23_out" == *"$s23_fmb/README.md"* && "$s23_out" != *"{mailbox}"* ]] \
    && ok "23 launcher: finds the mailbox from the default root with no --mailbox, adds its folder, and fills in {mailbox}" \
    || ko "23 launcher: finds the mailbox from the default root with no --mailbox, adds its folder, and fills in {mailbox}" "$s23_out"
s23_ctx="$(printf '{"session_id":"sess-far","cwd":"%s"}' "$s23_far" | PAIR_ROLE=cc PAIR_MAILBOX="$s23_fmb" bash "$s23_hook" start)"
[[ "$s23_ctx" == *"Nothing is open"* && "$(cat "$s23_fmb/.cc-session" 2>/dev/null)" == sess-far ]] \
    && ok "23 hook start: a mailbox outside the workspace works as one inside it" \
    || ko "23 hook start: a mailbox outside the workspace works as one inside it" "$s23_ctx"
# An existing mailbox in the project wins over the default root, and a one-off folder over both.
s23_w="$(bash "$s23_hook" where "$s23_p" 2>&1)"
s23_w2="$(bash "$s23_hook" where "$s23_p" --mailbox "$s23_other/once" 2>&1)"
[[ "$s23_w" == *"mailbox: $s23_mb"*"state: existing"* && "$s23_w2" == *"once"*"state: new"* ]] \
    && ok "23 where: a mailbox in flight in the project wins over the default root; --mailbox wins over both" \
    || ko "23 where: a mailbox in flight in the project wins over the default root; --mailbox wins over both" "$s23_w"$'\n'"$s23_w2"
bash "$s23_hook" default --clear >/dev/null 2>&1
s23_w="$(bash "$s23_hook" where "$s23_far" 2>&1)"
[[ "$s23_w" == *"mailbox: $s23_far/mailbox"*"state: new"* ]] \
    && ok "23 default --clear: back to <project>/mailbox" || ko "23 default --clear: back to <project>/mailbox" "$s23_w"

# ---- One writer per file: statuses in the reader's own file ----------------------------------------
s23_reset
: > "$s23_mb/status-cc.md"
s23_add PM-002
s23_out="$(s23_bare bash "$s23_hook" status --mailbox "$s23_mb" --from cc --id PM-002 done 4f2a91c 2>&1)"
s23_out2="$(s23_bare bash "$s23_hook" check --mailbox "$s23_mb")"
[[ "$s23_out2" == *"Open for the engineer: none"* && "$(tail -n 1 "$s23_mb/to-cc.md")" == "Status: open" ]] \
    && grep -qE '^PM-002 · [0-9-]+ [0-9:]+ [+-][0-9]{4} · done 4f2a91c$' "$s23_mb/status-cc.md" \
    && ok "23 status: the reader's line in its own file settles a message, which is left unedited; the time carries its offset" \
    || ko "23 status: the reader's line in its own file settles a message, which is left unedited; the time carries its offset" "$s23_out"$'\n'"$s23_out2"
s23_out="$(s23_bare bash "$s23_hook" status --mailbox "$s23_mb" --from cc --id PM-099 done 2>&1; echo "rc=$?")"
[[ "$s23_out" == *"no PM-099"*"rc=2" ]] && ok "23 status: refuses an id the other side never wrote" || ko "23 status: refuses an id the other side never wrote" "$s23_out"
s23_out="$(printf 'Report.\n' | s23_bare bash "$s23_hook" post --mailbox "$s23_mb" --from cc --title "Stamped" 2>&1)"
grep -qE '^## CC-[0-9]+ · [0-9-]+ [0-9:]+ [+-][0-9]{4} · Stamped$' "$s23_mb/to-pm.md" && [[ ! -d "$s23_mb/.cc-lock" ]] \
    && ok "23 post: a message's time carries its UTC offset, and the engineer's own lock is released" \
    || ko "23 post: a message's time carries its UTC offset, and the engineer's own lock is released" "$(tail -n 3 "$s23_mb/to-pm.md")"

# ---- Two machines: two copies of one mailbox, synced in both directions after each step ------------
# s23_sync: a file changed on one side since the last sync is copied to the other; a file changed on
# both comes back as the first side's version plus a conflict copy of the second's, as a two-way file
# sync does. Lock folders are left alone, being one machine's business.
s23_sim="$SCRATCH/s23-sim"
s23_sync() {
    local a="$s23_sim/a/mb" b="$s23_sim/b/mb" base="$s23_sim/base" f n ca cb
    mkdir -p "$base"
    for f in "$a"/* "$a"/.[!.]* "$b"/* "$b"/.[!.]*; do
        [ -f "$f" ] || continue; n="${f##*/}"
        cmp -s "$a/$n" "$b/$n" && { cp -p "$a/$n" "$base/$n"; continue; }
        ca=0; [ -f "$a/$n" ] && ! cmp -s "$a/$n" "$base/$n" && ca=1
        cb=0; [ -f "$b/$n" ] && ! cmp -s "$b/$n" "$base/$n" && cb=1
        if [ $ca -eq 1 ] && [ $cb -eq 0 ]; then cp -p "$a/$n" "$b/$n"; cp -p "$a/$n" "$base/$n"
        elif [ $cb -eq 1 ] && [ $ca -eq 0 ]; then cp -p "$b/$n" "$a/$n"; cp -p "$b/$n" "$base/$n"
        else
            cp -p "$b/$n" "$a/$n.conflict-copy-1"; cp -p "$b/$n" "$b/$n.conflict-copy-1"
            cp -p "$a/$n" "$b/$n"; cp -p "$a/$n" "$base/$n"
        fi
    done
}
s23_conflicts() { find "$s23_sim" -name '*conflict*' | wc -l | tr -d ' '; }
rm -rf "$s23_sim"; mkdir -p "$s23_sim/a" "$s23_sim/b/mb"
s23_A="$s23_sim/a/mb" s23_B="$s23_sim/b/mb"
bash "$s23_hook" init --mailbox "$s23_A" --name Sim >/dev/null 2>&1; s23_sync
printf 'The brief.\n' | s23_bare bash "$s23_hook" post --mailbox "$s23_A" --from pm --title Brief >/dev/null; s23_sync
s23_bare bash "$s23_hook" status --mailbox "$s23_B" --from cc --id PM-001 waiting gate 1 >/dev/null
printf 'Gate 1.\n' | s23_bare bash "$s23_hook" post --mailbox "$s23_B" --from cc --title Report >/dev/null; s23_sync
# Both machines write between one sync and the next: the PM settles the report and sends the next
# brief while the engineer settles the first.
s23_bare bash "$s23_hook" status --mailbox "$s23_A" --from pm --id CC-001 done >/dev/null
printf 'Next.\n' | s23_bare bash "$s23_hook" post --mailbox "$s23_A" --from pm --title Next >/dev/null
s23_bare bash "$s23_hook" status --mailbox "$s23_B" --from cc --id PM-001 done abc1234 >/dev/null
s23_sync
s23_ca="$(s23_bare bash "$s23_hook" check --mailbox "$s23_A")"; s23_cb="$(s23_bare bash "$s23_hook" check --mailbox "$s23_B")"
[[ "$(s23_conflicts)" == 0 && "$s23_ca" == *"Open for the engineer: PM-002"*"Open for the PM: none"* && "$s23_cb" == *"Open for the engineer: PM-002"*"Open for the PM: none"* ]] \
    && ok "23 two machines: a brief, a report and status changes, written on both sides between syncs, leave no conflict copy and read the same" \
    || ko "23 two machines: a brief, a report and status changes, written on both sides between syncs, leave no conflict copy and read the same" "conflicts: $(s23_conflicts)"$'\n'"$s23_ca"$'\n'"$s23_cb"
# The same steps with the old protocol, a status edited in place in the PM's file, do make one: the
# simulation can tell the two apart.
sed -i.bak 's/^Status: open$/Status: done 1/' "$s23_B/to-cc.md" && rm -f "$s23_B/to-cc.md.bak"
printf 'Third.\n' | s23_bare bash "$s23_hook" post --mailbox "$s23_A" --from pm --title Third >/dev/null
s23_sync
[[ "$(s23_conflicts)" != 0 ]] && ok "23 two machines: an in-place status edit in the other side's file does make a conflict copy" \
    || ko "23 two machines: an in-place status edit in the other side's file does make a conflict copy" "none made"

# ---- check names what the protocol does not write -----------------------------------------------
s23_out="$(s23_bare bash "$s23_hook" check --mailbox "$s23_A")"
: > "$s23_A/notes-fresh.txt"; : > "$s23_A/notes-old.txt"; age "$s23_A/notes-old.txt" 0.01
s23_out2="$(s23_bare bash "$s23_hook" check --mailbox "$s23_A")"
[[ "$s23_out" == *"does not write: to-cc.md.conflict-copy-1"* && "$s23_out2" == *"notes-old.txt"* && "$s23_out2" != *"notes-fresh.txt"* \
    && "$s23_out2" != *"status-pm.md,"* ]] \
    && ok "23 check: names a conflict copy at once and any other unknown file once it is five minutes old" \
    || ko "23 check: names a conflict copy at once and any other unknown file once it is five minutes old" "$s23_out"$'\n'"$s23_out2"

s23_bad=""
grep -q 'status-cc.md' "$s23_ex/README.md" && grep -q "%z" "$s23_ex/README.md" && grep -q 'network time' "$s23_ex/README.md" || s23_bad+="README: status files, offset times, a synced clock"$'\n'
grep -q '{mailbox}' "$s23_ex/KICKOFF.md" && ! grep -q '<mailbox path>' "$s23_ex/KICKOFF.md" || s23_bad+="KICKOFF: {mailbox}"$'\n'
grep -q 'pair.sh where' "$s23_cmd" && grep -q 'repository: none' "$s23_cmd" && grep -q 'pair.sh default' "$s23_cmd" && grep -q "%z" "$s23_cmd" || s23_bad+="command: where, default, no .gitignore outside a repository, offset times"$'\n'
empty "23 guidance: status files, offset times and the mailbox's location are in the README, KICKOFF and command" "$s23_bad"
