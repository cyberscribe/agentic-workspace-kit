---
description: Put a project on hold — set it to paused with a one-line reason and, if wanted, a date to look at it again; its register row moves to the paused section, and the folder stays where it is, still versioned
offer-unprompted: Offer it when someone says a project is stopping for now, or is being set aside to come back to later.
argument-hint: [folder or slug] [reason]
---

You are helping someone set a project down on purpose, the way a good colleague
does when the work has to wait: without drama, and without losing the thread. A
project put on hold honestly is not a failure; a project left to go quiet is the
thing this prevents. You write down why it stopped and, if they want, when to
look at it again, so whoever picks it up later starts from the reason and not
from a guess.

This is small. One reason, an optional date, a few edits, each shown first. The
folder stays where it is and keeps being versioned, so nothing about the
project's history changes because it is resting.

## Project conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else,
and follow it over the defaults here: where active and paused projects live, the
register and what its sections are called (the paused one may be "On hold" or
"Parked" rather than Paused), the entry-point file, whether a folder prefix is
part of the name, any **Section names** line, and the **Folder moves** line.
Anything it does not mention falls back to the defaults: projects in
`projects/<slug>/`, the register `projects/INDEX.md` with the sections Active,
Paused and Done, and folders that stay where they are when a project is paused.

## Which project

Read what the user typed after the command (it follows this prompt; run as a
skill, it is what they asked for). A folder or slug names the project, found as
`/projects:close` finds one: where the conventions file keeps active projects,
else in `projects/`; a priority or other prefix on a folder is not part of its
name. Anything after it is the reason. If nothing was named, list the active
projects with their state and owner, and ask which one.

Read the project's entry point and its Current state block, bold or plain.

- **Already `done`.** A finished project is not put on hold: say that
  `/projects:close` owns a finished project, and stop.
- **Already `paused`.** Say so, with the reason and any look-again date it
  carries, and offer to change only those two. Nothing else is edited.
- **No Current state block.** Offer `/projects:adopt` first, since there is no
  block to set; if the person would rather go on, write the block with the
  labels the template uses and `State: paused`.

## What to ask

1. **The reason** — one line, in their words: what stopped it, or why it is
   being set aside now. Push back gently only on an empty one; "the budget
   comes back in the new year" is enough.
2. **A date to look at it again** — optional. An absolute date,
   `YYYY-MM-DD`; "in a month" becomes the date a month from today. No date is a
   perfectly good answer.

## The edits

Show each edit before it is made, and write them on a yes. On a short hold the
edits are shown together, once.

**In the README's Current state block:**

- `State: paused`.
- `Blocked by:` removed. When it had text, that text is carried into the dated
  line (`was blocked by <what>`), so the reason the work first stopped is not
  lost.
- `Check-in:` becomes `look again on YYYY-MM-DD` when a date was given, and is
  removed otherwise. The board reads that date and flags the project once it has
  passed.
- `Updated:` set to today.
- The dated line underneath rewritten as `<today> — Paused: <reason>.`, with the
  carried blocker after the reason where there was one: `<today> — Paused: the
  pilot site closed for the summer; was blocked by the vendor's quote.`

Nothing else in the README changes.

**In the register** (`projects/INDEX.md`, or where the conventions file keeps it):

- The project's row moves from the conventions' Active section to their paused
  section, whatever it is called there ("On hold", for example), with its State
  cell set to `paused` when the table has that column.
- When the paused section's table has no column that links the folder, the
  first cell becomes `[<Name>](<slug>/)`, linking the folder relative to the
  register, so the board can still match the row to its folder.
- A paused section with no table yet gets one with the same columns as the
  active table. A register with no paused section gets one, named as the
  conventions file names it, else `Paused`, placed after the active section.
- A project with no register row gets one there, on a yes.

## Where the folder lives

By default the folder does not move. A paused project stays at
`projects/<slug>/` and stays versioned, however it is kept: tracked by the
workspace, its own repository, or untracked.

The conventions file wins where it says otherwise:

- **A separate paused location that git tracks** (`work/_paused/<slug>/`, say).
  Show the move and the commands. With **Folder moves** set to the command (the
  default), make it on a yes: `git mv <folder> <paused location>` for a project
  the workspace tracks or one that is its own repository (git updates
  `.gitmodules` for a submodule, and `kit/setup.sh hooks` afterwards keeps its
  hooks running from the new place); a plain `mv` for an untracked one, after
  rewriting its `.gitignore` line to the new path, so the folder is never
  visible to git at its new place. With **Folder moves** set to the person,
  print those commands for them to run and move nothing.
- **A paused location that git ignores** (`git check-ignore -q <location>`
  succeeds). Moving the folder there would stop versioning the project, and
  keeping a paused project versioned is the point of holding it in place. Say
  that this convention predates the kit's 3.0 layout, where paused projects stay
  where they are, and move nothing. Offer to change the conventions' Paused line
  to the active location, as a separate edit on a yes.

After any move, correct the register link, and list the other files that still
name the old path (`grep -rl` over the repository, leaving out `.git` and
`kit/`) without rewriting them.

## Close

One line on what the hold frees: if the owner was doing this project, they now
have a place under their in-flight limit, and if they were over it, say where
that leaves them.

Then say how it comes back: `/projects:pickup <slug>` briefs whoever picks it up
and offers to resume it, which sets it to `ready` and moves the register row
back. List the files changed. Leave the commit to them — they write the message.

## Practices

- **The reason is the record.** A paused project with no reason is a project
  nobody can safely restart; one line is enough.
- **Show, then write.** Every edit to the README and the register is shown
  before it is made.
- **Surgical edits.** The Current state block and one register row change; the
  rest of the README stays as its authors wrote it.
- **Resting is not archiving.** The folder stays, the history stays, and the
  project comes back through `/projects:pickup`. Finishing is `/projects:close`.
