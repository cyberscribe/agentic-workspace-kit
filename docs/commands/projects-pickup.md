# /projects:pickup

*A cold-start brief for anyone taking a project over or coming back to it. Read-only while briefing.
Source: `plugins/projects/commands/pickup.md`.*

## What it does

- Reads `.claude/projects.md` first, then finds the project: a slug or folder (a priority prefix on a
  folder is not part of its name), the project folder the session is in, or a choice from the active
  list. Several names give one brief each.
- Reads the entry point top to bottom, the project's decisions log (or entries naming it in
  `logs/decisions.md`), `git log -5` for the folder and `git status` for work not yet committed. A
  folder that is its own repository is read inside it.
- Writes a brief of under 40 lines, quoting the README's own words: the outcome; Done when progress
  and what is still open; the Current state block; planned steps; the last three decisions; the last
  five commits; open questions; who to ask; how it is kept (`Versioned:`, `Sensitivity:`, resources);
  what to read first; and a **Worth knowing** line for gaps and staleness.
- A missing section is said in its one line rather than left out: a missing finish line is the most
  useful thing a newcomer can learn.
- After the brief, names what would fix any gap, for the person to do.

For a paused project, it then offers one write, on a yes: resuming it. `State: ready` (or `doing`,
after counting the owner's projects in flight), the look-again `Check-in:` line removed, `Updated:`
today, the dated line `<today> — Resumed.`, and the register row moved back to the active section.

## When to reach for it

When someone takes a project over, comes back to one after time away, or is about to change something
in a project they did not start. It is also how a paused project is resumed.

## Common questions

**Why does it not fix a stale Current state block?** Correcting it while briefing would hide the one
thing the new owner most needs to see. It names it; the edit is the person's.

**The brief says "no done-when". Is the command broken?** No. Gaps are findings. `/projects:adopt`
adds the missing sections.

**The brief mentions the project is sensitive.** Its files stay out of the workspace repository and out
of anything shared; that is worth knowing before anything else.

**Does it run in Cowork?** Yes, as the `kit-projects-pickup` skill that `kit/setup.sh skills` writes.
In Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- The brief fits under 40 lines and every line is traceable to the README, the log or git.
- `git status` shows no change after a brief with no resume.
- A resumed project reads `State: ready` or `doing`, and its register row is back under Active.
