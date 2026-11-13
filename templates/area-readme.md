# <Area name>

- **Versioned:** <workspace · own-repo · untracked>
- **Sensitivity:** <normal · sensitive>

*Copy to `ongoing/<slug>/README.md` and add a row to `ongoing/INDEX.md`, or run `/ongoing:new` to be
interviewed for it; `/ongoing:adopt` gives an existing folder or long-running project this shape.
Sections marked optional are deleted when they would be empty, rather than left as placeholders.
Delete this block.*

*An ongoing area is work with no finish line: a practice, a responsibility, something kept up. Where a
project has Done when, an area has Standards to keep, and it is healthy while they are met. It is
never done; it is active, dormant or archived. When a piece of an area has a finish line, that piece is
a project in `projects/`, and the area's Projects section links it. The two lines under the title work
exactly as they do for a project.*

---

## What this is

One paragraph. What is kept up here, and what is not — the neighbouring work it is often confused
with, and where that lives instead.

## Desired state

One sentence: what you want to be true here, for as long as the area is kept up — the area's
counterpart to a project's Desired outcome. It is a direction rather than a finish line, so it is not
ticked off; the standards below are how it is checked.

## Standards to keep

Two to five standards the owner holds the area to, each concrete enough that a review can say
whether it was kept. Each says what "kept up" looks like, the way a Done when item says what
"finished" looks like: "every print pulled has a row in the print log", not "keep good records".
The board and the check-in read the area against this list.

- <observable standard>
- <…>

## Current state

- **State:** <active · dormant · archived>
- **Check-in:** <every 2 weeks — last YYYY-MM-DD>
- **Standards met:** <n of m — YYYY-MM-DD>
- **Updated:** <YYYY-MM-DD>

<YYYY-MM-DD> — <one or two sentences: how the area stands against its standards, and what slipped.>

The tracking block, with the same labels a project uses so the same readers find it. `State:` is one
of three: **active** (kept up now, checked on its cadence), **dormant** (seasonal or set aside on
purpose, and not flagged as stale; `/ongoing:pause`) and **archived** (no longer relevant, kept for the
record; `/ongoing:drop`). `/ongoing:review` is the check-in against the standards. `Check-in:` is the area's own
cadence, and the board measures staleness against it, since an area checked quarterly is not stale
after a week. `Standards met:` is written by `/ongoing:review` in exactly this form (`3 of 5 — 2026-11-11`),
so the session-start line and the metrics can read it; a new area leaves it out until its first review,
and an area without it reads as not yet reviewed. `Blocked by:` is not used: a standard that cannot be met is written in the dated line.

## Projects *(optional)*

The pieces of this area that have a finish line. Each links to its project folder, whose What this is
names this area. A small one may sit here inline — its outcome and a short Done when list — until it
earns a folder of its own.

- [`<slug>`](../../projects/<slug>/README.md) — <outcome, one line>

## Recurring *(optional)*

What keeps the standards met without anyone remembering to: scheduled tasks, calendar reminders,
routines, by name and where they live.

- <name> — <what it does, and where it is defined>

## People *(optional)*

As for a project: one line per person, name — role — profile, with one person who is **accountable** for the area.

- <name> — <accountable> — `memory/people/<name>.md`

## Read before acting

1. `<file>` — <what it holds, and when it is the right thing to read>

## Where everything lives

| What | Where |
|---|---|
| <the canonical record> | `<path>` — **canonical** |

## Resources *(optional)*

Material the area uses that is not in the repository, by name, mapped per machine in
`.claude/resources.local.md`, as for a project.

- <name> — <what it is>

## Working conventions

- <the rules specific to this area that would otherwise be re-derived or broken>

## Open questions

The things not yet decided, so a session does not decide them by accident.
