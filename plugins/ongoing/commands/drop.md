---
description: Archive an ongoing area that is no longer relevant — with a one-line reason, its open child projects settled, its state set to archived and its register row moved to the Archived section, the folder kept for the record or moved where the conventions say
offer-unprompted: Offer it when someone says they no longer keep an area up, or that it no longer matters to them.
argument-hint: [folder or slug] [reason]
---

You are helping someone put down something they used to carry. People change; a
practice ends; a responsibility moves on. Dropping an area on purpose, with the reason
written down, is better than letting it go stale on a board, and it leaves a clean
record for whoever wonders later what happened to it.

## Where this works

`/ongoing:drop` works inside a kit workspace: the folder this session was opened in, or one
above it, holds `kit/CLAUDE.kit.md` or `.claude/kit-templates.lock`. The kit's plugins
are installed for the person, so the command is offered in every folder. Outside a
workspace, say in one line that `/ongoing:drop` works inside a kit workspace, and do nothing
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

- **Already archived.** Say so, with its reason, and stop.
- **Only resting.** If what they describe is seasonal or temporary, offer
  `/ongoing:pause` instead, which keeps the area live and quiet.

## What to ask

1. **The reason** — one line: why it is no longer relevant.
2. **Open child projects** — list the projects its Projects section links that are not
   done. For each, ask: close it (`/projects:close`), hold it (`/projects:hold`), or
   keep it going on its own, in which case its What this is stops naming the area.
3. **Anything worth keeping** — one question: is there know-how here a later area or
   project should start from? If so, offer to promote it to the general reference
   (`docs/`) before archiving, as `/projects:close` does.

## The edits

Shown together, written on a yes:

- `State: archived`; `Check-in:` removed; `Updated:` today; the dated line rewritten as
  `<today> — Archived: <reason>.`
- The register row moves to the Archived section (as the conventions name it), its
  one-liner kept.
- **The folder** stays where it is by default, still versioned, so its history and
  links hold. Where the conventions name an archive location, show the move (`git mv`
  for a tracked folder) and make it on a yes, or print it when the conventions say the
  person moves folders; then list files that still name the old path, without
  rewriting them.

## Close

One line: what was archived and why, and where its child projects ended up. Say that
`/ongoing:adopt` brings it back if it ever matters again. List the files changed and
leave the commit to them.
