---
description: Set an ongoing area dormant — seasonal or set aside on purpose, with a one-line reason and, if wanted, a date to look at it again; it keeps its standards, is not flagged as stale, and its register row moves to the Dormant section
offer-unprompted: Offer it when someone says an area is resting for a season or being set aside for now.
argument-hint: [folder or slug] [reason]
---

You are helping someone let an area rest without losing it. Some things are seasonal;
some wait while life is full. A dormant area keeps its standards and its history, and
nobody is nagged about it until the date they chose.

This is small: one reason, an optional date, a few edits, each shown first.

## Where this works

`/ongoing:pause` works inside a kit workspace: the folder this session was opened in, or one
above it, holds `kit/CLAUDE.kit.md` or `.claude/kit-templates.lock`. The kit's plugins
are installed for the person, so the command is offered in every folder. Outside a
workspace, say in one line that `/ongoing:pause` works inside a kit workspace, and do nothing
else.

## Conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else, and
follow it over the defaults here. Its **Areas**, **Area register** and **Area template**
lines say where areas live, what the register is and which template to use; the rest
of it (people directory, versioning default, house rules) applies to areas as it does
to projects. Anything it does not mention falls back to the defaults: areas in
`ongoing/<slug>/` with `README.md` as the entry point, the register
`ongoing/INDEX.md` with the sections Active, Dormant and Archived (each a table of
Area · Folder · One-liner), and the template `kit/templates/area-readme.md`, else
`templates/area-readme.md`.

## Which area

Read what the user typed after the command (it follows this prompt; run as a skill,
it is what they asked for). A folder or slug names the area, found where the
conventions keep areas; anything after it is the rest of their request. If nothing
was named, list the areas with their state and when each was last checked, and ask
which one. Read the area's README and its Current state block, bold or plain.

- **Already dormant.** Say so, with its reason and date, and offer to change only those.
- **Archived.** An archived area is woken by `/ongoing:adopt`, not paused; say so and stop.

## What to ask

1. **The reason** — one line, in their words ("the trees are dormant until March").
2. **A date to look at it again** — optional, absolute, `YYYY-MM-DD`.

## The edits

Shown together, written on a yes:

- `State: dormant`.
- `Check-in:` becomes `look again on YYYY-MM-DD` when a date was given; otherwise the
  cadence line is kept, and the board does not apply it while the area is dormant.
- `Updated:` today, and the dated line rewritten as `<today> — Dormant: <reason>.`
- The register row moves from Active to Dormant (the sections as the conventions name
  them), creating the Dormant table with the Active table's columns if it has none.

Nothing else changes. The folder stays where it is, still versioned, and its child
projects keep their own states.

## Close

Say how it wakes: `/ongoing:review` on the date, or whenever they are ready, sets it
`active` again. List the files changed and leave the commit to them.
