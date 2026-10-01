# /projects:adopt

*Brings a project that already exists into the kit's shape by small insertions, or changes how a
project is versioned. Source: `plugins/projects/commands/adopt.md`.*

## What it does

- Reads `.claude/projects.md` first: locations, entry point, section-name aliases, the people
  directory, the **Versioned default** and the **Not adopted** folders.
- Looks for each section by what it does, not only by its heading: Desired outcome, Done when, the
  Current state block, People, the `Versioned:` and `Sensitivity:` lines, and Resources. A section
  that is present is not touched, so a second run adds nothing.
- Drafts only what is missing, from the README, the folder's files and `git log` for the folder: three
  to five Done when criteria (ticked only with evidence), a Current state block with a proposed state
  and a dated line saying what it was drawn from, and People with one of five roles each.
- Inserts each addition where the template's order puts it. Everything already in the file stays byte
  for byte as it was.
- An older `Now` block is named, and in interactive mode offered for conversion to Current state.

It runs two ways:

| Run as | What happens |
|---|---|
| `/projects:adopt <folder or slug>` | Interactive: each proposal shown as a diff, confirmed, edited or skipped |
| `/projects:adopt draft` | Every proposal inserted with a `proposed by /projects:adopt` marker, for a person to confirm later |
| `/projects:adopt <slug> workspace` (or `own-repo`, `untracked`) | Changes how one project is versioned, and only its `Versioned:` line in the README |

A versioning change is shown as the whole list of commands first, then run a step at a time on a yes.
Steps that commit or push are given to the person. Any change that creates, moves or removes a gitlink
ends with `kit/setup.sh hooks`.

## When to reach for it

When a session opens in a project folder whose README has no Current state block or Done when list;
when the quick-start maps a system that was here first; or when a project needs to become its own
repository, leave the workspace's history, or come back into it.

## Common questions

**A sensitive project is tracked by the workspace.** The workspace's git hooks refuse its files, this
README included. `/projects:adopt <slug> untracked` (or `own-repo`, with a remote confirmed private)
moves it out and writes the versioning lines as part of the move.

**Does moving a project to `untracked` remove it from history?** No. Earlier commits still hold the
files, on every clone and remote. Rewriting history is the person's decision, not this command's.

**Which folders does it leave out?** Folders git ignores, submodules, and folders with a `.git` of
their own that the workspace does not track, each named with the reason. A **Not adopted** folder, such
as a published site's home page, is adopted only when named, and asked about before writing.

**Does it run in Cowork?** Yes, as the `kit-projects-adopt` skill that `kit/setup.sh skills` writes.
In Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- A second run on the same project reports "all sections present; nothing added".
- After an adoption run, `git diff` on the README shows only insertions; after a versioning change,
  only the `Versioned:` line differs.
- `/projects:board` shows the project as a card, with any unconfirmed proposals flagged.
