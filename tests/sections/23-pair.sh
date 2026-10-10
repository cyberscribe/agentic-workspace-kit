# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh (SC2154); checks are "cond && ok || ko"
# (SC2015); single-quoted Markdown holds literal backticks (SC2016).
# shellcheck disable=SC2154,SC2015,SC2016
# Section 23: /projects:pair. The engineer's hooks (plugins/projects/hooks/pair.sh) against a fixture
# mailbox: inert without the launcher's variables, the session recorded, an open message sends the agent
# back, two nudges at most, a new message wakes a waiting session, .closed lets it stop. And the
# launcher's --print: a new session from KICKOFF.md, a resume when the transcript is there.
# Everything here is prefixed s23_, since the sections share one shell.

echo
echo "23 · /projects:pair: the engineer's hooks and the launcher"

s23_hook="$KIT/plugins/projects/hooks/pair.sh"
s23_launch="$KIT/plugins/projects/bin/pair.sh"
s23_p="$SCRATCH/s23/projects/00-demo"
s23_mb="$s23_p/mailbox"
mkdir -p "$s23_mb"

s23_reset() {
    rm -f "$s23_mb"/.cc-* "$s23_mb/.closed"
    printf '# To CC\n\n## PM-001 · 2026-10-10 10:00 · Brief\nBuild it.\nStatus: done 2026-10-10 11:00 abc1234\n' > "$s23_mb/to-cc.md"
    printf '# To the PM\n' > "$s23_mb/to-pm.md"
}
s23_add() { printf '\n## %s · 2026-10-10 12:00 · More\nAnd this.\nStatus: open\n' "$1" >> "$s23_mb/to-cc.md"; }
# s23_run <mode> [VAR=value...]: runs the hook with the launcher's variables; prints "<exit>|<stderr>".
s23_run() {
    local mode="$1" err rc; shift
    err="$(printf '{"session_id":"sess-123","hook_event_name":"x"}' \
        | env PAIR_ROLE=cc PAIR_MAILBOX="$s23_mb" PAIR_WAIT_MINUTES=0 "$@" bash "$s23_hook" "$mode" 2>&1 >/dev/null)"
    rc=$?
    printf '%s|%s' "$rc" "$err"
}

s23_reset
s23_out="$(printf '{"session_id":"x"}' | env -u PAIR_ROLE -u PAIR_MAILBOX bash "$s23_hook" stop 2>&1; echo "rc=$?")"
[[ "$s23_out" == "rc=0" && ! -f "$s23_mb/.cc-state" ]] && ok "23 hook: inert without PAIR_ROLE and PAIR_MAILBOX" \
    || ko "23 hook: inert without PAIR_ROLE and PAIR_MAILBOX" "$s23_out"

s23_ctx="$(printf '{"session_id":"sess-123"}' | PAIR_ROLE=cc PAIR_MAILBOX="$s23_mb" bash "$s23_hook" start)"
[[ "$(cat "$s23_mb/.cc-session" 2>/dev/null)" == "sess-123" && "$s23_ctx" == *"Nothing is open"* ]] \
    && ok "23 hook start: records the session id and says nothing is open" \
    || ko "23 hook start: records the session id and says nothing is open" "$s23_ctx"

s23_out="$(s23_run stop)"
[[ "$s23_out" == "0|" ]] && grep -q '^state: stopped' "$s23_mb/.cc-state" \
    && ok "23 hook stop: nothing open and no wait lets the session stop" || ko "23 hook stop: nothing open and no wait lets the session stop" "$s23_out"

s23_add PM-002
s23_out="$(s23_run stop)"
[[ "$s23_out" == 2\|*PM-002* ]] && ok "23 hook stop: an open message sends the agent back (exit 2, naming it)" \
    || ko "23 hook stop: an open message sends the agent back (exit 2, naming it)" "$s23_out"
s23_out="$(s23_run stop)"
[[ "$s23_out" == 2\|*PM-002* ]] && ok "23 hook stop: a second nudge for the same message" || ko "23 hook stop: a second nudge for the same message" "$s23_out"
s23_out="$(s23_run stop)"
[[ "$s23_out" == "0|" ]] && ok "23 hook stop: no third nudge, so a stuck message cannot loop" || ko "23 hook stop: no third nudge, so a stuck message cannot loop" "$s23_out"

s23_reset
( sleep 2; s23_add PM-003 ) &
s23_t0=$(date +%s)
s23_out="$(s23_run stop PAIR_WAIT_MINUTES=1 PAIR_POLL_SECONDS=1)"
s23_dt=$(( $(date +%s) - s23_t0 ))
wait
[[ "$s23_out" == 2\|*PM-003* && $s23_dt -lt 15 ]] && ok "23 hook stop: a message written while waiting wakes the session (${s23_dt}s)" \
    || ko "23 hook stop: a message written while waiting wakes the session" "$s23_out after ${s23_dt}s"

s23_reset
touch "$s23_mb/.closed"
s23_add PM-004
s23_out="$(s23_run stop PAIR_WAIT_MINUTES=1)"
[[ "$s23_out" == "0|" ]] && ok "23 hook stop: .closed lets the session stop at once" || ko "23 hook stop: .closed lets the session stop at once" "$s23_out"

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
s23_out="$(bash "$s23_launch" "$SCRATCH/s23" --print 2>&1; echo "rc=$?")"
[[ "$s23_out" == *"no mailbox"*"rc=2" ]] && ok "23 launcher: no mailbox, no launch" || ko "23 launcher: no mailbox, no launch" "$s23_out"
