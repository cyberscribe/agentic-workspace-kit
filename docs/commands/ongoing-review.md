# /ongoing:review

*The check-in for an ongoing area: each standard walked with the owner, the Current state block brought
up to date, and a slipped standard whose fix has an end turned into a project. Source:
`plugins/ongoing/commands/review.md`.*

## What it does

- Reads `.claude/projects.md` first, then the area's README, from the slug given or a list to choose
  from.
- Reads the Desired state back in one line, then takes each standard in turn: met, slipped or not
  known, with whatever the repository can show (a log, a scheduled task's last run, a dated record)
  offered before asking.
- For a slipped standard: a routine to restore it goes under Recurring or into the owner's task list; a
  fix with a finish line becomes a project through `/projects:new`, linked under the area's Projects.
- Lets the owner reword, drop or add a standard, and asks once whether the Desired state still holds.
- Shows the edits, then writes them on a yes: `Check-in:` last date, `Updated:` today, and the dated line
  `<today> — Reviewed: <n> of <m> standards met; <what slipped and what was set in motion>.`

## When to reach for it

When an area is due for its check-in (the board flags it), when someone asks how an area is going, or
when they look over their work as a whole. An area with no standards yet starts here too: the review names them first.

## Common questions

**Does it mark a standard met on its own?** No. It looks where the repository can show a standard and
says what it looked at, but the owner's answer decides.

**What about a dormant area?** It asks whether the area is waking. A yes sets it active as part of the
review; a no reviews it as it stands.

**Does it run in Cowork?** Yes, as the `kit-ongoing-review` skill that `kit/setup.sh skills` writes.

## It's working if

- The area's `Check-in:` line carries today's date, and the dated line names how many standards are met.
- Anything that slipped has a next step or a linked project.
- `/projects:board` no longer flags the area as due.
