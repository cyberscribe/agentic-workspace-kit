# /projects:hold

*Puts a project on hold on purpose: paused, with a one-line reason and, if wanted, a date to look at it
again. The folder stays where it is, still versioned. Source: `plugins/projects/commands/hold.md`.*

## What it does

- Reads `.claude/projects.md` first: locations, the register and what its paused section is called
  ("On hold", say), the entry point, and the **Folder moves** line.
- Takes the project from the command (`/projects:hold <slug> <reason>`), or lists the active projects
  and asks. A project already `done` belongs to `/projects:close`; one already `paused` gets only its
  reason and date changed.
- Asks two things: the reason, in the person's words, and an optional look-again date, written as an
  absolute `YYYY-MM-DD`.
- Shows each edit, then writes them on a yes. In the Current state block: `State: paused`;
  `Blocked by:` removed, its text carried into the dated line; `Check-in:` set to
  `look again on YYYY-MM-DD` when a date was given, removed otherwise; `Updated:` today; the dated line
  rewritten as `<today> — Paused: <reason>.` Nothing else in the README changes.
- Moves the register row from the active section to the paused one, with a folder link so the board can
  still match it, and its State cell set to `paused`.
- Says what the hold frees under the owner's in-flight limit, and how the project comes back.

## When to reach for it

When a project is stopping for now and will be picked up later: the budget returns next quarter, a
site closes for the summer, someone is away. For work that is finished or stopping for good, use
`/projects:close`.

## Common questions

**Does the folder move?** Not by default. A paused project stays at `projects/<slug>/` and keeps being
versioned however it is kept. Where the conventions name a separate paused location that git tracks,
the move is shown and made on a yes (or printed, when **Folder moves** gives moves to the person).

**The conventions put paused projects in a folder git ignores.** It moves nothing, since that would
stop versioning the project, and says the convention predates the 3.0 layout. It offers to point the
Paused line at the active location, as a separate edit.

**How does it come back?** `/projects:pickup <slug>` briefs whoever takes it up and offers to resume
it: `State: ready` (or `doing`), the look-again line removed, and the register row moved back.

**Does it run in Cowork?** Yes, as the `kit-projects-hold` skill that `kit/setup.sh skills` writes. In
Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- The README reads `State: paused`, with the reason on its dated line.
- The register row sits in the paused section.
- `/projects:board` counts it in the paused line, and flags it once its look-again date has passed.
