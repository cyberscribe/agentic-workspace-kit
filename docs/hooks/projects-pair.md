# projects pair (SessionStart, Stop)

*The engineer's side of a `/projects:pair` pairing: it records the session and points it at open
mailbox messages, and never holds a turn. Source: `plugins/projects/hooks/pair.sh`, wired in
`plugins/projects/hooks/hooks.json` (SessionStart `startup|resume` and Stop, timeout 5 seconds each).*

## What it does

It does nothing unless `PAIR_ROLE=cc` and `PAIR_MAILBOX` are set, which only
`plugins/projects/scripts/pair.sh` does when it launches the engineer. Every other session passes through.

**At session start** it writes the session id to `.cc-session` in the mailbox, so the launcher can
resume it later, sets `.cc-state` to `working`, and tells the agent which PM messages are open for it
and the command that starts the watch.

**At the end of each turn:**

- A PM message with `Status: open` that the agent has not yet been pointed at twice sends it back to
  work: exit 2, with the ids and the file on stderr.
- Otherwise it returns at once, setting `.cc-state` to `waiting` when a watch is running and
  `stopped` when none is. `.closed`, written when the PM closes the pairing, always reads `stopped`.
- `Status:` is read wherever it sits in a line, and the last one in a message holds.

**The watch** (`pair.sh watch`) is a background command the agent runs, not a hook. It reads
`to-cc.md` every 20 seconds (`PAIR_POLL_SECONDS`) and ends, naming the message, when a new open one
arrives or `.closed` appears; a background command ending is what wakes a session between turns. One
watch runs at a time (`.cc-watch` holds its process id). It runs under bash 3.2 and needs no jq.

## When to reach for it

You do not call it: the launcher turns it on. Read this page when the engineer's session seems to be
ignoring the mailbox, or will not stop.

## Common questions

**Does it run outside a kit workspace?** No. Setup installs the plugins for the person, so they load in
every session, and the hook first looks for `kit/CLAUDE.kit.md` or `.claude/kit-templates.lock` in the
session's folder or a folder above it (by its real path, so a symbolic link counts). Finding neither, it
exits 0 with nothing said. The rule is `hooks/lib/boundary.sh`: `docs/plugin-scope.md`.

**Why is the watch not in the Stop hook?** A hook that waits holds the session: it takes no other
notification and the person has to interrupt it to type. The hooks check once; the watch waits.

**Why at most two nudges per message?** A message the agent cannot finish would otherwise loop. After
two, only new messages wake it; the agent marks the stuck one `waiting <on what>` for the PM.

**Does watching cost tokens?** No. The watch is a shell loop; the model is not called until a message
arrives.

## It's working if

- A PM message written while the engineer was between turns is picked up within a poll.
- The session is never busy with nothing to do: the person can type into it at any time.
- Sessions not started by the launcher show no sign of the hook.
- `.cc-state` names the state and the time it began.
