---
description: Rename a project — a new slug and name for its folder, README title, register row and resource map, with every path that named the old folder shown and updated on a yes; history keeps the old name
offer-unprompted: Offer it when someone says a project's name no longer fits, or asks to call a project something else.
argument-hint: [folder or slug] [new name]
---

You are helping someone give a project a better name, the way a careful
colleague renames a shared folder: once, everywhere it is pointed at, without
breaking a link or losing where it came from. A name that has drifted from the
work is a small daily friction; a rename that orphans the register row, the
resource map or a link in someone's notes is a worse one. This command does the
first without the second.

It changes names and paths, nothing else. The outcome, Done when, state and the
history of the project stay as they are.

## Where this works

`/projects:rename` works inside a kit workspace: the folder this session was opened in, or one
above it, holds `kit/CLAUDE.kit.md` or `.claude/kit-templates.lock`. The kit's plugins
are installed for the person, so the command is offered in every folder. Outside a
workspace, say in one line that `/projects:rename` works inside a kit workspace, and do nothing
else.

## Project conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else,
and follow it over the defaults here: where active, paused and finished projects
live, the register, the entry-point file, whether a folder prefix is part of the
name, any **Section names** line, and the **Folder moves** line. Anything it does
not mention falls back to the defaults: projects in `projects/<slug>/`, finished
ones in `projects/_done/<slug>/`, and the register `projects/INDEX.md`.

## Which project, and the new name

Read what the user typed after the command (it follows this prompt; run as a
skill, it is what they asked for). The first word names the project, found as
`/projects:close` finds one, in any of the conventions' locations: a project is
renamed where it lives, active, paused or done. Anything after it is the new
name. If nothing was named, list the projects with their state and ask which
one; if no new name was given, ask for it.

From the new name, `kit/plugins/projects/scripts/slug.sh <new name>` gives the
new slug, and the name as given is the new title ("Field trial" is
`field-trial`). Given a slug alone, the title is the slug with hyphens as
spaces and its first letter capitalised. Show both; the person can give another
of either.

A priority or other prefix on the folder is not part of the name and stays:
`00-pilot-study` becomes `00-field-trial`.

Stop before any edit, saying why, when:

- **The new folder exists.** Name it, and ask for another slug.
- **The slug is unchanged.** Only the title changes: offer the README title and
  the register name cell, and nothing else.
- **A pairing is open on the project.** A mailbox in or for the folder whose
  pairing has not been closed holds absolute paths, and a running engineer has
  the folder as its working directory. Say to finish with `/projects:pair close`
  first, then rename.

## What changes

Read the project's entry point, then find every place the old folder is named:
`grep -rlF` over the repository for `<old folder>/` and for the register's
relative link (`<old slug>/`), leaving out `.git`, `kit/` and the project folder
itself. Sort what turns up into the groups below, show them all, and make the
edits on a yes. A short list is shown and confirmed once.

**The folder.** Moved according to how the project is versioned:

- Tracked by the workspace: `git mv <old folder> <new folder>`.
- Its own repository as a submodule: `git mv` too; git rewrites the path in
  `.gitmodules` (the section keeps its old name, which is harmless), and
  `kit/setup.sh hooks` afterwards keeps its hooks running from the new place.
- Its own repository, not a submodule, or untracked: rewrite its `.gitignore`
  line to the new path first, then a plain `mv`, so the folder is never visible
  to git at either place.

With **Folder moves** set to the person, print these commands for them to run,
and make the other edits once they say the folder has moved.

**The README.** The title, when it is the old name or the old slug, becomes the
new title. In the Current state block, `Updated:` becomes today and a dated line
`<today> — Renamed from <old slug> to <new slug>.` goes above the latest one,
which stays. Paths in the README that name its own old folder are rewritten.
The old name in its prose is listed, not changed: whether "the pilot" still
reads right in a sentence is the person's call.

**The register.** The row keeps its place and section; its name cell becomes
the new title, and its link text and target the new folder.

**The resource map.** In `.claude/resources.local.md` on this machine, each
`<old slug>/<name>` line becomes `<new slug>/<name>`. The file is not
committed, so say that every other machine needs the same edit; until it has
one, the session-start line there offers the mapping again. Then
`kit/setup.sh link <new slug>` re-links `.resources/` and grants the folders to
Claude Code under the new path.

**Folders outside the repository named for the slug.** A Drive or shared
folder the README or `.gitignore` names with the old slug in its path
(`~/Google Drive/<old slug>/`, say) is listed with the `mv` that would rename it.
Where this session can reach it, the move is made on a yes, separately from the
rest; otherwise the command is printed. The README's line naming it is updated
either way, so the README never points at a folder that is not there.

**Other files that name the old path.** Path references in current guidance,
other projects' READMEs and notes are rewritten on a yes. Records of what was
true at the time are listed and left as they are: decisions and experiments
logs, changelogs, retrospectives, dated status lines and handoff logs. A
reference there to a folder that has since moved is history, not a broken link.

## Close

List the files changed and anything printed for the person to do: other
machines' resource maps, a folder outside the repository they will move
themselves. Where the workspace keeps aliases for its projects (a terms or
memory file), offer to add the old name as one, so "the pilot" still finds the
project.

Suggest a commit message, `<New title>: renamed from <old slug>`, and leave the
commit to them.

## Practices

- **One name, everywhere it is used.** A rename that leaves the register, the
  resource map or a link on the old path has made two projects out of one.
- **History keeps its names.** Logs and dated lines say what was true when they
  were written; they are never rewritten to the new name.
- **Show, then write.** Every edit is shown before it is made, and a move
  outside the repository is its own yes.
- **Names and paths only.** The outcome, Done when, state and People stay as
  their authors wrote them.
