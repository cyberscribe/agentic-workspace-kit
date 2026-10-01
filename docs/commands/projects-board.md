# /projects:board

*Every project in flight on one page, grouped by state, with one-line flags for what needs attention.
Source: `plugins/projects/commands/board.md`.*

## What it does

- Reads `.claude/projects.md` first, then each active project's README. The READMEs are the truth;
  the board is a view of them.
- Where the kit's state check is there, runs `kit/plugins/workspace/bin/state.sh --quick` once for
  versioning, submodules and resources. It makes no network call and writes nothing.
- Lays out cards in columns by state, in the order the work flows: ready, doing, blocked, paused,
  done, then "no Current state block". One line per card: name, owner, Done when progress, and days
  since `Updated:`. A blocked card quotes what blocks it and for how long.
- Lists flags under the board, one line each: no owner, no Done when, stale, blocked more than 14
  days, over the in-flight limit, register disagrees with the README, unconfirmed adopt proposals,
  ready to close, sensitive and tracked, versioning disagrees with the folder, submodule out of step,
  resource not reachable on this machine, and a paused project's look-again date reached.
- Ends with one line naming what would act on the flags, for the person to do when they choose.

Typed as `/projects:board write`, it also writes the same board to `projects/BOARD.md` (or beside the
register), with a first line marking it as generated.

## When to reach for it

When someone asks where the work stands, before a team check-in, or when a session opens at the
repository root on a surface with no session-start line. For one project, the session-start line or
`/projects:pickup` says more.

## Common questions

**It says "no done-when", but the README has a list.** The board sees a `Done when` checklist, or a
heading named in the **Section names** line of `.claude/projects.md`. Recording the other name there,
or `/projects:adopt`, fixes it.

**Why is a paused project not a card?** Paused projects whose README reads `paused` are counted in one
line under the board. A paused project raises only two flags: its look-again date, and sensitive and
tracked.

**Will it fix what it flags?** No. It is read-only apart from `BOARD.md` on request, and a hand-written
`BOARD.md` without the generated first line is shown and asked about before it is replaced.

**Does it run in Cowork?** Yes, as the `kit-projects-board` skill that `kit/setup.sh skills` writes.
In Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- The first line counts the active projects by state, and every active folder with an entry point
  appears as a card or in a "not read from here" line.
- A clean board ends with "No flags."
- `git status` shows no change after a run without `write`.
