# /projects:close

*Finishes a project: the finish line checked item by item, a short retrospective, what travels
promoted, and the folder archived. Source: `plugins/projects/commands/close.md`.*

## What it does

1. **The finish line.** Goes through the Done when list one item at a time, finds the evidence first (a
   path, a link, a commit) and asks the person to confirm it. Where the team has a verification
   standard (`docs/verification.md`), the evidence is held to its row. An item not met is kept open
   (the close ends there), changed with a dated line saying why, or waived, with the reason and whether
   the **ask first** people were consulted.
2. **A retrospective.** Three questions: what worked, what to change, what the next similar project
   should know first. The answers go into the README as its last section.
3. **Promotion.** The third answer is tested with the kit's filter. What survives goes to
   `logs/decisions.md` or `docs/<topic>.md` on a yes; a reusable thing gets a catalogue line on a yes.
   It does not write to the always-loaded file; that is raised as a proposal.
4. **Marking it done.** Open Planned steps are let go or moved elsewhere; the Current state block is
   set to `done`; the folder moves to `projects/_done/<slug>/` (or the conventions' **Done**
   location); the register row moves to its Done section.
5. **Who needs to know**, as a short table, when People names anyone else. Nothing is sent.

How the folder moves depends on how the project is versioned, checked against the folder itself:

| Versioned | Move |
|---|---|
| `workspace` | `git mv projects/<slug> projects/_done/<slug>` |
| `own-repo` | the same `git mv`, which updates `.gitmodules`, then `kit/setup.sh hooks` |
| `untracked` | a plain `mv`, with the `.gitignore` line rewritten around it so the folder is never visible to git |

With the conventions' **Folder moves** line set to the person, the commands are printed and nothing
moves. Either way, the commit is the person's.

## When to reach for it

When every Done when box is ticked, when the board flags a project as ready to close, or when a
project is stopping for good. A project set aside to come back to is `/projects:hold`'s instead.

## Common questions

**Can a project close with an item not met?** Yes, if the person waives it. The box stays unticked,
with the waiver, its date, who waived it and why beside it: an unticked box with its reason is the
honest record.

**What about files elsewhere that name the old path?** They are listed and left as they are: a dated
record keeps its wording, and the rest is the person's call.

**Does it run in Cowork?** Yes, as the `kit-projects-close` skill that `kit/setup.sh skills` writes.
In Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- Every Done when item is ticked with evidence, changed with a dated line, or waived with its reason.
- The README ends with a dated Retrospective section and reads `State: done`.
- The folder is under `projects/_done/`, the register row is in the Done section, and `/projects:board`
  no longer shows it.
