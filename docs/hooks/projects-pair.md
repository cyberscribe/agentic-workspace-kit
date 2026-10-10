# projects pair (SessionStart, Stop)

*The engineer's side of a `/projects:pair` pairing: it records the session and keeps it with the
mailbox between turns. Source: `plugins/projects/hooks/pair.sh`, wired in
`plugins/projects/hooks/hooks.json` (SessionStart `startup|resume`, timeout 5 seconds; Stop, timeout
3600 seconds).*

## What it does

It does nothing unless `PAIR_ROLE=cc` and `PAIR_MAILBOX` are set, which only
`plugins/projects/bin/pair.sh` does when it launches the engineer. Every other session passes through.

**At session start** it writes the session id to `.cc-session` in the mailbox, so the launcher can
resume it later, sets `.cc-state` to `working`, and tells the agent which PM messages are open for it.

**At the end of each turn:**

- A PM message with `Status: open` that the agent has not yet been pointed at twice sends it back to
  work: exit 2, with the ids and the file on stderr.
- Otherwise it sets `.cc-state` to `waiting` and reads `to-cc.md` every 20 seconds. A new open message
  sends the agent back to work; after 50 minutes with none, it sets `stopped` and lets the session end.
- `.closed` in the mailbox, written when the PM closes the pairing, lets the session stop at once.

`PAIR_WAIT_MINUTES` (0 to 55) and `PAIR_POLL_SECONDS` change the wait. It runs under bash 3.2 and needs
no jq.

## When to reach for it

You do not call it: the launcher turns it on. Read this page when the engineer's session seems to be
ignoring the mailbox, or will not stop.

## Common questions

**The session looks busy but is doing nothing.** It is watching the mailbox. Press Esc to type into
it; it waits again at the end of its next turn.

**Why at most two nudges per message?** A message the agent cannot finish would otherwise loop. After
two, it waits for new messages only; the agent marks the stuck one `waiting <on what>` for the PM.

**Does waiting cost tokens?** No. The hook is a shell loop; the model is not called until a message
arrives.

## It's working if

- A PM message written while the engineer was between turns is picked up within a poll.
- Sessions not started by the launcher show no sign of the hook.
- `.cc-state` names the state and the time it began.
