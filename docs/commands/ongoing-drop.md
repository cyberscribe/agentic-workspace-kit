# /ongoing:drop

*Archives an ongoing area that is no longer relevant, with its reason written down and its child
projects settled. Source: `plugins/ongoing/commands/drop.md`.*

## What it does

- Reads `.claude/projects.md` first, then the area's README, from the slug given or a list to choose
  from.
- Offers `/ongoing:pause` instead when what the person describes is only resting.
- Asks the reason, then each open child project's fate: closed with `/projects:close`, held with
  `/projects:hold`, or kept going on its own without naming the area.
- Asks once whether there is know-how worth promoting to the general reference before it goes.
- Shows the edits, then writes them on a yes: `State: archived`, `Check-in:` removed, `Updated:` today,
  the dated line `<today> — Archived: <reason>.`, and the register row moved to Archived.
- Leaves the folder where it is, still versioned, unless the conventions name an archive location, in
  which case it shows the move.

## When to reach for it

When an area is no longer relevant: a practice ended, a responsibility moved to someone else, an
interest faded. Writing that down is better than letting it go stale on the board.

## Common questions

**Is anything deleted?** No. The folder and its history stay; only its state and register row change.

**Can it come back?** Yes. `/ongoing:adopt` takes it up again.

**What if it is only for a season?** Use `/ongoing:pause`, which keeps it live and quiet.

**Does it run in Cowork?** Yes, as the `kit-ongoing-drop` skill that `kit/setup.sh skills` writes.

## It's working if

- The README reads `State: archived`, with the reason on its dated line.
- Its child projects are closed, held or no longer name it.
- The register row sits in the Archived section, and `/projects:board` leaves it off.
