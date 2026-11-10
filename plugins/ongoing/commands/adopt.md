---
description: Adopt an ongoing area that already exists — give an existing folder, or a long-running project that has no real finish line, the area's shape as small insertions: desired state, standards to keep, the Current state block in area states, its versioning lines and a register row
offer-unprompted: Offer it when someone says a project is really something they keep up rather than finish, or when a folder of ongoing work has no area README.
argument-hint: <folder or slug>
---

You are helping someone recognise what a piece of their work already is. Often a
"project" has run for months with a finish line nobody believes in, or a folder of
notes has grown around a practice. Naming it an area is not a demotion; it lets it be
measured by what keeping it up looks like, rather than by a finish it will never cross.

You add what is missing and rewrite nothing that is there. The folder move, when one is
needed, is theirs to make.

## Where this works

`/ongoing:adopt` works inside a kit workspace: the folder this session was opened in, or one
above it, holds `kit/CLAUDE.kit.md` or `.claude/kit-templates.lock`. The kit's plugins
are installed for the person, so the command is offered in every folder. Outside a
workspace, say in one line that `/ongoing:adopt` works inside a kit workspace, and do nothing
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

If the folder is still a project under `projects/`, read its README and its Done when:
a list that names a real, near finish line is a project, and stays one — say so and
stop unless they insist. A list scoped to a milestone inside a longer practice is the
common case: the practice becomes the area, and the milestone is kept, word for word,
under the area's Projects section.

## What to draft

Draft each missing section in the area template's shape, from what the files already
say. Mark each drafted block `<!-- proposed by /ongoing:adopt YYYY-MM-DD: confirm or
edit -->`, so it reads as a proposal until the owner says otherwise.

- **Versioned and Sensitivity** — under the title, as `/projects:adopt` would infer
  them: from `.gitignore`, a nested repository or submodule, and what the files hold.
- **What this is** — when absent: one paragraph naming it as an area, and the
  milestone project inside it if there is one.
- **Desired state** — from the README's goals or purpose; ask when nothing states it.
- **Standards to keep** — two to five drawn from its conventions, routines and logs;
  `- not yet named` when the files give no grounds.
- **Current state** — `State: active`, `dormant` if the files say it is set aside
  seasonally; a `Check-in:` line only when the files name a cadence; `Updated:` today;
  the dated line saying it was adopted as an area and from where. A project's dated log
  stays below, as history.
- **Projects** — the former Done when list, unchanged, under a heading naming its
  outcome, marked inline; or links to projects that already serve it.
- **Recurring** — scheduled tasks, reminders or routines the files name.

## The move and the registers

When the folder sits with the projects, show the move to the areas location and the
paths that will need repointing: `grep -rl` for the old path across the repository,
leaving out `.git` and `kit/`, split into live files (scheduled tasks, settings,
scripts, current guidance) and history (changelogs, logs, mailboxes), which stays as
written. The move and the rewrites are theirs to make, or yours on a yes; where tools
run from absolute paths into the folder (virtual environments, symlinked skills),
offer a link at the old path, kept out of git, until those are rebuilt.

The project's register row moves to the area register's Active section; when the
area register does not exist yet, create it as `/ongoing:new` does.

## Close

Show every insertion before writing it. Then one line: the area's state, its cadence
if any, and which proposed blocks the owner still has to confirm. List the files changed
and leave the commit to them.
