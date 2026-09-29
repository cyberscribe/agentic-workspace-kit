# projects — start a project right for agentic co-working

A Claude Code plugin for the life of a project, kept in the project's own
README so that people and agents read the same thing. Five commands, one
session-start line:

| Command | What it is for |
|---|---|
| **`/projects:new`** | Open a project the way a good kickoff does: a short interview, then its entry point. |
| **`/projects:adopt <folder>`** | For a project that already exists: add only what is missing (Done when, Current state, People) as small insertions. |
| **`/projects:board`** | Everything in flight on one page, with one-line flags for what needs attention. |
| **`/projects:close <slug>`** | The finish line, done properly: evidence, a short retrospective, who needs to hear. |
| **`/projects:pickup <slug>`** | A cold-start brief for anyone taking a project over or coming back to it. |

Most of it is optional. What it insists on, kindly, is the part that decides
whether the work ever finishes:

- **A desired outcome** — one sentence, with a finish line.
- **Done when** — three to five criteria someone else could check. This is the
  project's closeout state: later sessions reconcile against it, and when every
  box is ticked the project is finished.
- **An owner** — one person who answers for the outcome.

And what it offers, if you want it:

- **People and roles** — five roles: **owns** (answers for the outcome, one person
  per outcome), **does**, **helps**, **ask first** (consulted before a decision)
  and **keep told** (hears how it went), linked to people profiles. Two or more
  people switches on the closeout plugin's "who needs to know" step.
- **Success criteria** — how you'll know it was worth doing, as distinct from done.
- **Precedents** — it searches finished projects and decisions logs for similar
  work before asking, because a rejected alternative from last time is the most
  valuable thing to know at the start.
- **Planned steps, constraints, a check-in cadence, open questions.**

## The Current state block

Every project README carries a small block straight after Done when, so where
the project stands is the second thing anyone reads:

```
## Current state

- **State:** blocked
- **Blocked by:** the signed budget from finance — since 2026-09-14
- **Check-in:** every 2 weeks — last 2026-09-21
- **Updated:** 2026-09-24

2026-09-24 — Plan agreed; the budget is the last thing before the rollout.
```

`State:` is one of `ready`, `doing`, `blocked`, `paused`, `done`. `Blocked by:`
is there only when something stops the work: one line, saying what and since
when. `Check-in:` is there only when the project has a cadence of its own. The
labels are fixed, because the plugin's other commands and the kit's metrics
read them. An owner written as `none found …` or `not yet named` is an honest
gap and counts as missing. The dated line underneath is free prose, rewritten
rather than added to. Each working session leaves the block true when it ends.

An optional **Planned** section can follow it: the steps the team can already
see, in order. It is a plan, not a queue, and no one line in it is singled out. The register,
`projects/INDEX.md`, carries each project's state and owner too, and where the
two disagree the README wins.

### How the files are read

Every command, the session-start line and `pilot/measure.sh` read a README by the
same rules, so a project reads the same on the board, at session start and in
the metrics:

- **Labels** bold or plain: `- **State:** doing` and `State: doing` are one line.
- **Honest gaps** — a value that is empty, `-`, `—`, `none` or `n/a`, or begins
  `none found`, `not yet named` or `<` (a template stand-in), is missing.
- **Headings** — a heading's name is its text up to the first ` — `, ` – `, `(`
  or `:`, without markup, compared whole: `Done when — checklist` and
  `People *(optional)*` are Done when and People. A **Section names** line in
  `.claude/projects.md` adds names; backtick only heading names in it.
- **Done when** counts checklist lines (`- [ ]`, `- [x]`) under that heading.
- **Blocked by** — one line, dated only by the date after `since`.
- **The owner** — the **owns** line under People; with no People section, the
  register row's Owner, else a backticked **Owner:** in `.claude/projects.md`.
- **The entry point** — the one `.claude/projects.md` names, else `README.md`,
  else a `CLAUDE.md` in the folder; where there are two, the first with a
  Current state block.
- **Which projects** — every folder in the active location with an entry point,
  and every register row under Active: the union. The README's State decides: a
  register-paused project whose README reads `ready`, `doing` or `blocked` is
  active, and flagged for the register to catch up.
- **The earlier format** — a block under a `Now` heading, from before this
  version, is still read as the block. The session-start line says it is in the
  earlier format, the board lists it as not yet converted, and
  `/projects:adopt` offers the conversion.

## Adopting existing projects

`/projects:adopt` is for work that was running before the plugin arrived. It
reads the README, the folder and its history, proposes the missing sections, and
inserts them where the template's order puts them. It recognises a finishing list
or a team list under other names and leaves it alone, and it treats a prose status
section as the narrative under a new Current state block rather than replacing
it. Running it twice adds nothing the second time.

It asks before writing. Type `draft` after the command to have it ask nothing:
it inserts every proposal, each marked for a person to confirm —

```
<!-- proposed by /projects:adopt 2026-09-28: confirm or edit -->
```

— which is the way to adopt many projects at once, ahead of the person who will
confirm them. The board flags the proposals still unconfirmed; confirming one
means deleting its comment.

## Board

**`/projects:board`** shows everything in flight on one page, built from the
project READMEs. Projects are grouped by state (ready · doing · blocked · paused
· done), one line each: owner, done-when progress, days since the Current state
block was updated, and for a blocked project what blocks it. Under the board, one
line per thing that needs attention: no owner, no done-when, an `Updated:` date
older than the staleness setting, a project blocked for more than 14 days,
someone over their in-flight limit, a register row that disagrees with its
README, `/projects:adopt` proposals nobody has confirmed, and a project whose
Done when is fully ticked but not yet closed. It only reads. Type `write` after the command to
also save it as `projects/BOARD.md`, whose first line marks it as generated; the
READMEs stay canonical. On a repository with no projects it says so and suggests
`/projects:new`.

## Close

**`/projects:close <folder or slug>`** is the finish line, done properly. It goes
through Done when one item at a time and finds the evidence for each: a path, a
link or a commit. When the team has a verification standard in
`docs/verification.md`, it holds that evidence to the standard. If an item is not
met, you choose: keep working, change the criterion (with a dated line saying
why), or waive it. The people marked *ask first* are named before a waiver, and
the waiver is recorded in the README next to the item. Then comes a
three-question retrospective: what worked, what you would change, and what the
next similar project should know first. It offers to promote that last answer to
the cross-project decisions log or general reference, and to add a catalogue line
for anything reusable, but writes neither without your yes. Finally it marks the
project `State: done`, moves it to wherever `.claude/projects.md` says finished
projects go, and suggests who should hear, based on People roles. It sends
nothing, and the commit is yours.

## Pick up

**`/projects:pickup <slug>`** is a cold-start brief for anyone taking a project
over or coming back to it. It shows the desired outcome and how many Done when
criteria are ticked, the Current state block and any Planned steps with day
counts, the last three decisions and the last five commits to the folder,
anything not yet committed, the open questions, and who to ask (the owner and
the *ask first* people). It closes with a short "worth knowing" list of gaps and
stale lines. It quotes the README rather than paraphrasing it, fits in under 40
lines, and only reads. Where something needs fixing, it says what would fix it
and leaves the fixing to you.

## Session-start line

When a session opens inside a project folder, the plugin's SessionStart hook
reads the project's entry point and gives three lines: the desired outcome, Done
when progress ("2 of 4 ticked"), and the state with its owner — and what blocks
it, when something does:

```
Project: Rollout — outcome: The rollout is live for every team.
Done when: 2 of 4 ticked
State: blocked by the signed budget from finance — since 2026-09-14 — owner Sam
```

You see them at the top of the session, and the agent reads them as context. It
says so when sections are still proposals from `/projects:adopt`, and when the
block is still in the earlier Now format. Anywhere else in the repository it
says nothing, except at most once a day: one line naming the active projects
blocked for more than 14 days. A clean day prints nothing.

The hook finds projects, the entry point and any renamed sections from
`.claude/projects.md`. It needs `jq`, makes no network calls, finishes in well
under 100 ms on a repository with 20 projects, and exits silently if anything
goes wrong. `PROJECTS_HOOK_DISABLED=1` turns it off. The once-a-day marker lives
in `~/.claude/projects-hook/` (`PROJECTS_HOOK_STATE_DIR` moves it), never in the
repository. Surfaces without session hooks, such as desktop assistants that load
skills, get the same view by running the board when a session opens in a project
folder — the generated skills say so.

## Your conventions, not ours

If your repository keeps projects somewhere else, names its register's sections
differently, heads a README's Done when list another way, prefixes folders, or
has its own template, say so in
`.claude/projects.md`. Every projects command reads that file first and follows it
over its own defaults; anything it leaves out falls back to them. It is prose, not
a schema — see [`examples/projects-conventions.md`](examples/projects-conventions.md)
for an annotated example. The kit's installer lays down a default one.

It is also where the team's **in-flight limit** lives — how many projects one
person has in `doing` at once, 3 unless you say otherwise. A person's profile can
carry their own. A project counts towards someone when its People section names
them as **owns** or **does** (or, with no People section, the register names
them as owner). `/projects:new` mentions it when starting a project would take
the owner over; it is advice, never a block.

The **staleness** setting lives there too: how old a Current state block's
`Updated:` date can be before the board flags it, weekly unless you say
otherwise. A file written before this version may call it the review cadence;
the commands read either name.

## Install

Part of the [workspace context kit](https://github.com/cyberscribe/agentic-workspace-kit):

```
/plugin marketplace add cyberscribe/agentic-workspace-kit
/plugin install projects@agentic-workspace
```

The kit's `install.sh` vendors it into a team repository alongside the closeout
and workspace plugins. With `--skills-dir <path>` it also writes one thin skill
per command (`projects-new`, `projects-board`, …) for assistants that load
skills from a folder rather than plugins; each skill points at the command file,
so the procedure still has one source.

## Works with

- **closeout** — reconciles each session against the project's done-when list and
  Current state block, and uses its People roles for "who needs to know".
- **The kit's project template** — `templates/project-readme.md` carries the same
  sections, so a project started by hand, one started by interview and one
  adopted all look alike.

MIT licensed, as part of the kit.
