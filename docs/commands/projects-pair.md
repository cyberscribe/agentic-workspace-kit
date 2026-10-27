# /projects:pair

*Pair on a project: this session is its product manager and end-to-end tester, one Claude Code session
its engineer, and a mailbox carries everything between them.
Source: `plugins/projects/commands/pair.md`.*

## What it does

- Reads `.claude/projects.md`, the workspace's always-loaded file and the project's own guidance, and
  quotes the standing rules it finds (who commits, who pushes, attribution, deletion, sensitivity) into
  the brief. The local conventions win over the command's defaults.
- Sets up the mailbox in any folder (`pair.sh init`): a protocol README, `to-cc.md`, `to-pm.md`, a
  status file per side, and a `.gitignore` line unless the folder is outside every repository. It goes
  in `--mailbox <folder>` for one pairing, else this machine's default root (`pair.sh default`, one
  mailbox per project at `<root>/<slug>/`), else `<project>/mailbox/`; `pair.sh where` says which. An
  existing mailbox wins over a new place, and one in this two-file format is continued, ids and all.
- Writes the first brief as `PM-NNN`, with no interview: the outcome and Done when items quoted from
  the README, this phase's checks, the order of work with the person's gates, ownership, and how to
  report with evidence. It says which reading of "this phase" it took.
- Writes `KICKOFF.md` and gives the person one command, with the prompt it sends shown beneath:
  `kit/plugins/projects/scripts/pair.sh <project folder>`. On the person's machine that resumes the
  engineer's last session if its transcript is still there, and starts a new one otherwise, in auto
  permission mode, with the pairing hooks loaded for that session only. A resume starts in the
  folder the session began in, read from its transcript.
- `join`, typed in an engineer's session started some other way, attaches it in place: the Stop hook
  at the end of that turn claims it, and from then on its hooks hear the PM. `leave` detaches it.
- Takes one PM per mailbox (`.pm-session`) and message ids under a lock (`pair.sh post`), so two
  writers never share an id, and gives each command it hands the person in a paste-safe form.
- Comes back every 30 minutes while anything is open, tests what the engineer reports end to end, and
  accepts it or writes the next brief. `status` reports the pairing; `close` ends it, copies the
  mailbox's decisions to the project's log and lets the engineer's session stop.

## When to reach for it

When the work is mostly building and you want to direct and check it rather than relay between two
windows: one session holds the outcome and tests, the other does. One engineer per pairing.

## Common questions

**Why a mailbox rather than one shared log?** Each file has one writer: the PM writes `to-cc.md` and
`status-pm.md`, the engineer `to-pm.md` and `status-cc.md`. Neither side edits the other's words,
"what is open" is one line per message, and two sessions never write one file.

**Can the mailbox be in a folder copied between machines?** Yes: with one writer per file, two
machines never change one file between copies. Each side takes its own lock, `KICKOFF.md` says
`{mailbox}` for the launcher to fill in, and `pair.sh check` names any file the protocol does not
write, such as a conflict copy. Times come from the system clock, synced with network time where it
can be, with their UTC offset (`2026-10-27 20:17 +0000`). A mailbox from before this keeps editing
`Status:` in place, as its README says, and reads the same.

**What keeps the engineer reading the mailbox?** A background watch it starts, which wakes it when a
PM message arrives, and a Stop hook that points it at anything still open. Neither holds the session. See
[the pairing hooks](../hooks/projects-pair.md).

**The engineer's session was started without the launcher.** It writes reports but never hears the
PM. The PM's check-in says so once ("the engineer isn't watching the mailbox"); typing
`/projects:pair join` in that session fixes it without an exit.

**Can the engineer use ultracode?** Yes, when a phase fans out: it asks in its report, and the person
types `/effort ultracode` in that session, or launches with `--ultracode`.

**Does it run in Cowork?** Yes, as the `kit-projects-pair` skill: Cowork is the natural PM. The
engineer is always Claude Code, on the machine with the code.

## It's working if

- The person never copies a message from one window to the other.
- Every accepted `CC-NNN` names evidence the PM re-ran: a commit, a test result, the thing seen working.
- `.cc-state` reads `waiting` between phases rather than `stopped`, and the launcher resumes rather
  than starting over.
