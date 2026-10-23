# projects pair (SessionStart, Stop)

*The engineer's side of a `/projects:pair` pairing: it records the session and points it at open
mailbox messages, and never holds a turn. Source: `plugins/projects/hooks/pair.sh`, wired in
`plugins/projects/hooks/hooks.json` (SessionStart `startup|resume|compact` and Stop, timeout 5 seconds each).*

## What it does

It acts for one session only: the one `plugins/projects/scripts/pair.sh` launched (`PAIR_ROLE=cc` and
`PAIR_MAILBOX`), or one that joined with `/projects:pair join`. A joined session is found by its id in
the registry, `~/.config/agentic-workspace-kit/pairings` (`PAIR_REGISTRY`). Every other session passes
through.

**At session start** it writes the session id to `.cc-session`, sets `.cc-state` to `working`, and
tells the agent which PM messages are open and the command that starts the watch. It runs again after
a compaction, and names any id two messages share.

**At the end of each turn:**

- A join no more than 10 minutes old is claimed by the session that asked for it, matched by the
  session id `join` recorded or, where there was none, by folder: `.cc-session` written, the registry
  bound, `.cc-join` removed, and the agent told.
- A PM message open (a `Status:` that reads `open`, or none at all) that the agent has not been pointed
  at twice sends it back to work: exit 2, with the ids on stderr.
- Otherwise it returns at once: `.cc-state` reads `waiting` with a watch running, else `stopped`.
  `.closed` reads `stopped`, and unbinds a joined session.

**The watch** (`pair.sh watch [--mailbox DIR]`) is a background command the agent runs. It reads
`to-cc.md` every 20 seconds (`PAIR_POLL_SECONDS`) and ends, naming the message, when a new open one
arrives or `.closed` appears. A join still unclaimed after 180 seconds (`PAIR_JOIN_GRACE`) ends it
with the launcher command that resumes this session (`--session <id>`). One watch runs at a time.

**For either side,** `pair.sh check` prints the engineer's state, what is open each way, and once per
spell that the engineer is not watching; `pair.sh post` appends a message under the next id, taken
under a lock (`hooks/lib/lock.sh`). It runs under bash 3.2 and needs no jq.

## When to reach for it

You do not call the hooks: the launcher or `/projects:pair join` turns them on. Read this page when
the engineer's session seems to be ignoring the mailbox, or will not stop.

## Common questions

**Does it run outside a kit workspace?** No. The hook first looks for `kit/CLAUDE.kit.md` or
`.claude/kit-templates.lock` in the session's folder or above it (`hooks/lib/boundary.sh`), and finding
neither exits 0 with nothing said: `docs/plugin-scope.md`.

**Why is the watch not in the Stop hook?** A hook that waits holds the session; the person would have
to interrupt it to type. The hooks check once; the watch waits.

**My session was started without the launcher.** Type `/projects:pair join` in it: no exit, nothing
lost. It needs projects 3.3.0 or later loaded in that session; without it no hook claims the join, and
the watch says so with the command to resume through the launcher.

**Why at most two nudges per message?** A message the agent cannot finish would otherwise loop; it
marks it `waiting <on what>` for the PM.

## It's working if

- A PM message written while the engineer was between turns is picked up within a poll.
- The person can type into the engineer's session at any time.
- A joined session's `.cc-session` holds its id and the registry binds it.
- `pair.sh check` stays quiet while the engineer is listening.
