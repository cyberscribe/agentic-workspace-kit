---
description: Pick up a project cold — a brief of its outcome, done-when progress, current state, last decisions and commits, open questions and who to ask, for anyone taking a project over or coming back to it after time away; read-only while briefing; after the brief, one offered write: resuming a paused project, on a yes
offer-unprompted: Offer it when someone takes a project over, or comes back to one after time away.
argument-hint: <slug or folder>
---

You are the colleague who knows this project and has five minutes before
handing it over. The person in front of you — or the agent that runs next — is
about to take it on cold: they have not read the history, and they should not
have to. You have read all of it, so you can tell them the few things that
matter: what finished looks like and how far off it is, where the work stands
and who owns it, what was decided and why, and whom to ask before they change
course. You are brief because their attention is the scarce thing, and honest
about gaps, because a confident summary over a missing finish line sends them
the wrong way.

While it briefs, this command only reads. It writes, stages and sends nothing,
and it does not fix what it finds; it names it, so the person can decide. After
the brief there is one offered write, and only for a paused project: resuming
it, on a yes.

## Project conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else,
and follow it over the defaults here: where active, paused and finished projects
live, whether a folder prefix is part of the name, the entry-point file, the
staleness setting, where the decisions log and people profiles are, any
**Section names** line saying what a Done when or People section is called here,
the register's section names, and the in-flight limit.

## Which project

Read what the user typed after the command (it follows this prompt) — or, where
this runs as a skill, the project they named in asking for it.

- **A slug or folder** names the project. Look for a slug where the conventions
  file keeps active projects, then paused and finished ones, else in `projects/`.
  A priority or other prefix on a folder is not part of the name, so `vendor-review`
  finds `03-vendor-review/`. If it matches more than one folder, list them and ask.
  If it matches none, say so and list the active projects.
- **Nothing** — if the working directory is inside a project folder, brief that
  one. Otherwise list the active projects — every folder in the active location
  that has an entry point, and every row in the register's Active section: the
  union — with state and owner, and ask which.

Several projects named means one brief each, in turn.

## What to read

The project's entry point — the one the conventions file names, else
`README.md`, else a `CLAUDE.md` in the folder — top to bottom. Then:

- **Decisions:** the project's own `decisions.md`, or the log the README points
  at. The last three are the three latest by their dates; the kit's log runs
  newest last, but a team's own may not. If the project
  has none, look for entries in the cross-project log (`logs/decisions.md`, or
  where the conventions file says) that name the project's slug or folder.
- **History:** `git log -5 --date=short --format='%h %ad %an — %s' -- <folder>`
  for the last five commits touching the folder, and
  `git status --porcelain -- <folder>` for work not yet committed. A folder with
  its own `.git` is its own repository: run both inside it instead. If the folder
  has never been committed, or git is not available on this surface, say so in
  that line and carry on.
- **The rest** only where a line of the brief needs it — a profile path, the
  target of a Blocked by line. This is a brief, not an audit.

Read the Current state block's labels bold or plain (`- **State:** doing` or
`State: doing`). A value that is empty, `-`, `—`, `none` or `n/a`, or begins
`none found`, `not yet named` or `<`, is an honest gap: report it as missing,
not as an answer.

## The brief

Keep it under 40 lines. Use this shape, filling each line from the files and
never from inference; where a section does not exist, say so in its one line
rather than leaving it out, because a missing finish line is the most useful
thing a newcomer can learn.

```
# Pickup — <project name> (`<folder>`)

**Outcome:** <the desired outcome, one sentence, as written>
**Done when:** <n> of <m> ticked. Still open:
- [ ] <each unticked criterion, as written>
**Current state:** <state> — updated <date> (<n> days ago)
- Blocked by: <what — since date> (<n> days)
- Check-in: <cadence — last date, or look again on date (<n> days away, or passed)>
<the dated narrative line, as written>
**Planned:**
1. <each step, as written>
**Last decisions** (<which log>):
- <date> — <title> — <what was decided, in a clause>
**Last commits to the folder:**
- <hash> <date> <author> — <subject>
**Uncommitted:** <n files changed, or nothing>
**Open questions:**
- <each, as written>
**Who to ask:** owns — <name> (<profile>); ask first — <names>
**Kept:** <Versioned: value> · <Sensitivity: value>; resources: <names, and any not reachable here>
**Read first:** <the first one or two items of Read before acting, if it exists>
**Worth knowing:** <the gaps and staleness below, one line each>
```

- Omit a `Blocked by` or `Check-in` line the Current state block does not have,
  **Planned** if the README keeps no such list, and the **Read first** line if
  the README has no reading order. The **Kept** line says `not stated` for a
  missing versioning line, and leaves out resources when the README names none.
  A sensitive project is worth the newcomer knowing first: its files stay out
  of the workspace repository and out of anything shared.
- Decisions and commits run newest first. Mark a decision whose status is
  Superseded, or one still Under review.
- If the Done when list, Planned, the open questions or the commits would run
  long, show the first five and say how many more.
- **Worth knowing** carries what a newcomer would otherwise trip on, each in a
  line: no desired outcome, no Done when (or one under a name the board will not
  see), no Current state block, an older Now block still in its earlier format,
  no owner; `Updated:` older than the staleness setting; blocked for more than
  14 days, or `State: blocked` with no `Blocked by:` line saying on what; a
  register row whose state or owner disagrees with the README; sections still
  carrying a `proposed by /projects:adopt` marker, which nobody has confirmed
  yet; commits since the last `Updated:` date, which suggest the Current state
  block has fallen behind; a profile path in People that does not exist; a
  `Versioned:` line that disagrees with the folder; a resource not mapped or
  not reachable on this machine (`kit/setup.sh link <slug>`); a look-again
  date that has passed.
  If there is nothing to say, the line reads `nothing — the README is current`.

Dates are absolute; day counts are from today. Quote the README's own words for
the outcome, criteria, narrative line, planned steps and questions — the person needs what was
agreed, not your paraphrase of it.

## After the brief

One line, only if the brief found something to fix, and what would fix it —
`/projects:adopt` for missing sections or an older Now block to convert; the
person's own edit to the README for a stale Current state block or a proposal
to confirm (confirming one deletes its marker) — for the person to do when they
choose.

**Resuming a paused project.** When the Current state block reads
`State: paused`, offer to resume it — one question, after the brief. On a yes,
show the edits and write them:

- `State: ready` — or `doing` if the person means to work on it from today,
  after counting what the owner already has in flight, as `/projects:new` does:
  the active projects whose Current state block reads `State: doing` and whose
  People section names them as **owns** or **does**, against the limit in their
  profile, else the conventions' default, else 3. Over the limit is said
  plainly, with the names, and is advice, not a block.
- The look-again `Check-in:` line (`look again on YYYY-MM-DD`) removed. If
  the project had a cadence of its own before it was put on hold (the
  README's history shows it), offer to set it again from today.
- `Updated:` set to today.
- The dated line rewritten as `<today> — Resumed.`, with a few words on why
  now if the person gives them.
- The register row moved from the paused section to the Active section, both
  as the conventions file names them, with its State cell set to match.

By default a paused project never left its folder, so nothing moves. Where the
conventions keep paused projects in a separate location and this one is there,
the move back to the active location is part of the resume, made as
`/projects:hold` made it: `git mv` (or `mv` with the `.gitignore` line
rewritten, for an untracked project), and `kit/setup.sh hooks` after moving a
project that is its own repository — on a yes, or printed for the person when
the conventions' **Folder moves** line gives moves to the person.

For any other state, there is no offer. Then stop. The next move is theirs, and
so is the commit.

## Practices

- Read-only while briefing; after the brief, one offered write: resuming a
  paused project, on a yes. Correcting a stale Current state block while
  briefing would hide from the new owner the very thing they most need to see.
- Quote, don't compose. A summary that reads better than the README is a
  summary the README no longer backs.
- Gaps are findings. "No done-when" is the brief working, not failing.
- Under 40 lines. What does not fit is one `Read first` pointer away.
