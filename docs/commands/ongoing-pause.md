# /ongoing:pause

*Sets an ongoing area dormant: seasonal or set aside on purpose, with a one-line reason and, if wanted,
a date to look at it again. Source: `plugins/ongoing/commands/pause.md`.*

## What it does

- Reads `.claude/projects.md` first, then the area's README, from the slug given or a list to choose
  from.
- An area already dormant gets only its reason and date changed; an archived one is woken by
  `/ongoing:adopt`, not paused.
- Asks the reason, in the person's words, and an optional look-again date as `YYYY-MM-DD`.
- Shows the edits, then writes them on a yes: `State: dormant`; `Check-in:` set to
  `look again on YYYY-MM-DD` when a date was given, else kept and not applied while dormant; `Updated:`
  today; the dated line `<today> — Dormant: <reason>.`
- Moves the register row from Active to Dormant, creating that table if needed.

## When to reach for it

When an area rests for a season (the trees are dormant until March) or is set aside while life is full,
and will come back. For an area that no longer matters, use `/ongoing:drop`.

## Common questions

**Does a dormant area keep its standards?** Yes. Nothing about the area changes except its state, and
the board does not flag it as stale.

**What happens to its child projects?** Nothing. They keep their own states.

**How does it wake?** `/ongoing:review` on the date, or whenever the owner is ready, sets it active.

**Does it run in Cowork?** Yes, as the `kit-ongoing-pause` skill that `kit/setup.sh skills` writes.

## It's working if

- The README reads `State: dormant`, with the reason on its dated line.
- The register row sits in the Dormant section.
- `/projects:board` lists it as dormant and never as due.
