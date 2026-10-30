# projects pair (SessionStart, UserPromptSubmit, PostToolUse, Stop, SessionEnd)

*The pairing's hooks for both sides of a `/projects:pair` pairing, none of which holds a turn. Source:
`plugins/projects/hooks/pair.sh`, wired in `plugins/projects/hooks/hooks.json`, timeout 5 seconds each.*

## What it does

It acts for one session only: the one `scripts/pair.sh` launched (`PAIR_ROLE=cc` or `pm`, with `PAIR_MAILBOX`), or,
for the engineer, one that joined with `/projects:pair join`, found by id in the registry (`PAIR_REGISTRY`, by default
`~/.config/agentic-workspace-kit/pairings`). Every other session passes through.

**At session start** it records the session id (`.cc-session`) and the claude process id (`.cc-pid`), clears any
ended mark, and tells the agent which PM messages are open, the command that starts the watch, and any id two
messages share. It runs again after a compaction.

**Activity.** `beat` (UserPromptSubmit and PostToolUse) rewrites `.cc-beat` at most every 30 seconds and is silent.
The prompt beat also clears the no-watch counter. `end` (SessionEnd) writes `.cc-ended`. About 11 ms per call
outside a pairing and 33 ms inside, measured on the author's machine.

**At the end of each turn:**

- A join no more than 10 minutes old is claimed by the session that asked for it: `.cc-session` written, the
  registry bound, `.cc-join` removed, the agent told.
- A PM message open (not settled by its status) that the agent has not been pointed at twice sends the turn
  back to work: exit 2, with the ids on stderr.
- With the pairing open and no watch running, the turn is sent back once (exit 2) with the watch command; the next
  Stop ends it and clears the counter. A prompt or a watch start clears it too.
- The PM's session (`PAIR_ROLE=pm`) gets the same rule against `watch --role pm` (`.pm-nowatch`), and no send-back
  or engineer state. With no `PAIR_MAILBOX` it is outside any pairing.
- Otherwise it returns at once. `.closed` unbinds a joined session.

**The watch** (`pair.sh watch [--mailbox DIR]`) is a background command the agent runs. It reads `to-cc.md` every
20 seconds (`PAIR_POLL_SECONDS`) and ends, naming the message, when a new open one arrives or `.closed` appears.
A join unclaimed after 180 seconds (`PAIR_JOIN_GRACE`) ends it with the launcher command that resumes the session.
`watch --role pm` does the same for the PM, on `to-pm.md`, and writes no engineer state.

**For either side,** `pair.sh check` derives the engineer's state from evidence and prints the evidence: `working`
(activity within two minutes), `watching`, `idle` or `ended`. It also prints what is open each way, when each side
last picked a message up, any header dated later than its file was written, and once per spell that the engineer
is not watching. `.cc-state` is a cache, labelled as one. `pair.sh post` appends a message under the next id, taken
under a lock (`hooks/lib/lock.sh`). It runs under bash 3.2 and needs no jq.

## When to reach for it

You do not call the hooks: the launcher or `/projects:pair join` turns them on. Read this page when the engineer's
session seems to be ignoring the mailbox, or will not stop.

## Common questions

**Does it run outside a kit workspace?** No. The hook looks for `kit/CLAUDE.kit.md` or
`.claude/kit-templates.lock` in the session's folder or above it (`hooks/lib/boundary.sh`), and finding neither
exits 0 with nothing said: `docs/plugin-scope.md`.

**Why is the watch not in the Stop hook?** A hook that waits holds the session; the person would have to interrupt
it to type. The hooks check once; the watch waits.

**My session was started without the launcher.** Type `/projects:pair join` in it: no exit, nothing lost. It needs
projects 3.3.0 or later loaded in that session.

**Why is a pickup recorded?** The first time the watch or a hook points the reader at a message, its status file
gets a `received <time>` line. It settles nothing; it lets the PM see how long a message waited.

**Why at most two nudges per message?** A message the agent cannot finish would otherwise loop; it marks it
`waiting <on what>` for the PM.

## It's working if

- A PM message written while the engineer was between turns is picked up within a poll.
- The person can type into the engineer's session at any time.
- `pair.sh check` names the engineer's state with its evidence, and stays quiet while the engineer is listening.
