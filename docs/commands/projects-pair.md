# /projects:pair

*Pair on a project: this session is its product manager and end-to-end tester, one Claude Code session
its engineer, and a mailbox in the project folder carries everything between them.
Source: `plugins/projects/commands/pair.md`.*

## What it does

- Reads `.claude/projects.md`, the workspace's always-loaded file and the project's own guidance, and
  quotes the standing rules it finds (who commits, who pushes, attribution, deletion, sensitivity) into
  the brief. The local conventions win over the command's defaults.
- Sets up the mailbox (`<project>/mailbox/`, or where the conventions say): a protocol README,
  `to-cc.md` and `to-pm.md`, and a `.gitignore` line. An existing mailbox in this two-file format is continued, ids
  and all.
- Writes the first brief as `PM-NNN`, with no interview: the outcome and Done when items quoted from
  the README, this phase's checks, the order of work with the person's gates, ownership, and how to
  report with evidence. It says which reading of "this phase" it took.
- Writes `KICKOFF.md` and gives the person one command, with the prompt it sends shown beneath:
  `kit/plugins/projects/bin/pair.sh <project folder>`. On the person's machine that resumes the
  engineer's last session if its transcript is still there, and starts a new one otherwise, in auto
  permission mode, with the pairing hooks loaded for that session only.
- Comes back every 30 minutes while anything is open, tests what the engineer reports end to end, and
  accepts it or writes the next brief. `status` reports the pairing; `close` ends it, copies the
  mailbox's decisions to the project's log and lets the engineer's session stop.

## When to reach for it

When the work is mostly building and you want to direct and check it rather than relay between two
windows: one session holds the outcome and tests, the other does. One engineer per pairing.

## Common questions

**Why a mailbox rather than one shared log?** Two files, each written by one side, with a `Status:`
line as the only edit, mean neither side ever edits the other's words, and "what is open" is one
line per message.

**What keeps the engineer reading the mailbox?** Its Stop hook. When a turn ends with nothing open, the
session waits for the next PM message (up to 50 minutes) instead of going idle. See
[the pairing hooks](../hooks/projects-pair.md).

**Can the engineer use ultracode?** Yes, when a phase fans out: it asks in its report, and the person
types `/effort ultracode` in that session, or launches with `--ultracode`.

**Does it run in Cowork?** Yes, as the `kit-projects-pair` skill: Cowork is the natural PM. The
engineer is always Claude Code, on the machine with the code.

## It's working if

- The person never copies a message from one window to the other.
- Every accepted `CC-NNN` names evidence the PM re-ran: a commit, a test result, the thing seen working.
- `.cc-state` reads `waiting` between phases rather than `stopped`, and the launcher resumes rather
  than starting over.
