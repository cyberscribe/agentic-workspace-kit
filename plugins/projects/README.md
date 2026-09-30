# projects — start a project right for agentic co-working

A Claude Code plugin for the life of a project, kept in the project's own
README so that people and agents read the same thing. Six commands, one
session-start line:

| Command | What it is for |
|---|---|
| **`/projects:new`** | Open a project the way a good kickoff does: a short interview, then its entry point. |
| **`/projects:adopt <folder>`** | For a project that already exists: add only what is missing (Done when, Current state, People, the versioning lines) as small insertions; or change how a project is versioned. |
| **`/projects:hold <slug>`** | Set a project aside on purpose: paused, with a reason and a date to look again; the folder stays where it is, still versioned. |
| **`/projects:board`** | Everything in flight on one page, with one-line flags for what needs attention. |
| **`/projects:close <slug>`** | The finish line, done properly: evidence, a short retrospective, who needs to hear, and the folder archived to `projects/_done/`. |
| **`/projects:pickup <slug>`** | A cold-start brief for anyone taking a project over or coming back to it; it offers to resume a paused one. |

Most of it is optional. What it insists on, kindly, is the part that decides
whether the work ever finishes:

- **A desired outcome** — one sentence, with a finish line.
- **Done when** — three to five criteria someone else could check. This is the
  project's closeout state: later sessions reconcile against it, and when every
  box is ticked the project is finished.
- **An owner** — one person who answers for the outcome.
- **How it is kept** — whether the workspace tracks it, it is its own
  repository, or it stays out of git, and whether anything in it is sensitive.

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
- **Resources** — material the project uses that lives outside the repository,
  named in the README and mapped to real paths on each machine.

## How a project is kept

Two lines sit directly under each README's title, outside the Current state
block:

```
- **Versioned:** workspace
- **Sensitivity:** normal
```

| Versioned | What it means | Use it for |
|---|---|---|
| `workspace` | Tracked by the workspace repository | Most projects |
| `own-repo` | Its own repository, with its own remote, added to the workspace as a submodule | Work that publishes, or has collaborators outside the workspace |
| `untracked` | Listed in the workspace's `.gitignore`; the README is still read on this machine | Material that stays on one machine |

`Sensitivity:` is `normal` or `sensitive`. A sensitive project is `untracked`
or its own private repository; it is never tracked by the workspace, and the
workspace's git hooks refuse to stage its files. An absent line reads as
`normal`. `/projects:new` asks both questions, `/projects:adopt` proposes the
lines for an older project, and `/projects:adopt <slug> own-repo` (or
`workspace`, or `untracked`) moves a project from one way to another, showing
every command first and saying plainly what the workspace's history still
holds.

## Resources

A project names the material it uses that is not in the repository — large
media, generated output, a data extract, a shared drive folder — by name, never
by path:

```
## Resources

- media — raw interview recordings (large; kept outside git)
- exports — generated renders; rebuilt by `make render`
```

Each machine maps the names in `.claude/resources.local.md`, which is not
committed (`field-study/media  ~/Shared drives/Field study/recordings`), and
`kit/setup.sh link <slug>` links them at `projects/<slug>/.resources/<name>`
and grants the folders to Claude Code. A resource described as generated, and
mapped nowhere, lives inside the project folder and is kept out of git. The
session-start line offers the mapping once when a name is not mapped here, and
the board flags a resource this machine cannot reach, as a fact about the
machine rather than an error.
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
README, `/projects:adopt` proposals nobody has confirmed, a project whose
Done when is fully ticked but not yet closed, a sensitive project the workspace
still tracks, a `Versioned:` line that disagrees with the folder, a project
repository out of step with its pointer, a resource this machine cannot reach,
and a paused project whose look-again date has come. Where the kit's state
check is present (`kit/plugins/workspace/bin/state.sh --quick`) it reads those
facts from it. It only reads. Type `write` after the command to
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
project `State: done`, moves the folder to `projects/_done/<slug>/` (or wherever
`.claude/projects.md` says finished projects go) with `git mv`, so its history
follows — a plain move and a rewritten `.gitignore` line for an untracked
project — moves the register row to Done, and suggests who should hear, based
on People roles. It lists the other files that still name the old path rather
than rewriting them. It sends nothing, and the commit is yours.

## Hold

**`/projects:hold <slug> [reason]`** sets a project aside on purpose. It sets
`State: paused`, writes the reason as the dated line (carrying any `Blocked by:`
text into it), turns `Check-in:` into `look again on YYYY-MM-DD` when you give a
date, and moves the register row to the paused section, whatever your register
calls it. The folder stays where it is and stays versioned, so resting never
means losing history. The board flags the project once its look-again date has
passed, and `/projects:pickup` resumes it.

## Pick up

**`/projects:pickup <slug>`** is a cold-start brief for anyone taking a project
over or coming back to it. It shows the desired outcome and how many Done when
criteria are ticked, the Current state block and any Planned steps with day
counts, the last three decisions and the last five commits to the folder,
anything not yet committed, the open questions, and who to ask (the owner and
the *ask first* people). It closes with a short "worth knowing" list of gaps and
stale lines. It quotes the README rather than paraphrasing it, fits in under 40
lines, and reads while it briefs. Where something needs fixing, it says what
would fix it and leaves the fixing to you. For a paused project, it then offers
one write: resuming it — `State: ready` (or `doing`, after the in-flight
count), the look-again date removed, a dated `Resumed.` line, and the register
row back under Active — on your yes.

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
block is still in the earlier Now format. When the README names resources this
machine has not mapped, a fourth line says which —

```
Resources not mapped on this machine: media, survey-data — kit/setup.sh link field-study maps them.
```

— and the agent offers once to map them, asking you for each path. The offer
comes once per set of unmapped names per machine. A folder listed under **Not
adopted** in `.claude/projects.md` whose README has no Current state block gets
a note for the agent alone, so `/projects:adopt` is not offered there
unprompted. Anywhere else in the repository it
says nothing, except at most once a day: one line naming the active projects
blocked for more than 14 days. A clean day prints nothing.

The hook finds projects, the entry point and any renamed sections from
`.claude/projects.md`. It needs `jq`, makes no network calls, finishes in well
under 100 ms on a repository with 20 projects, and exits silently if anything
goes wrong. `PROJECTS_HOOK_DISABLED=1` turns it off. The once-a-day marker and
the resource-offer markers live in `~/.claude/projects-hook/`
(`PROJECTS_HOOK_STATE_DIR` moves them), never in the repository. Folders under
`projects/` whose names start with `_` or `.` (`_done`, `_delete`) are not
projects: the once-a-day scan skips them, and a finished project in
`projects/_done/<slug>/` reads as done. Surfaces without session hooks, such as desktop assistants that load
skills, get the same view by running the board when a session opens in a project
folder — the generated skills say so.

## Your conventions, not ours

If your repository keeps projects somewhere else, names its register's sections
differently, heads a README's Done when list another way, prefixes folders, or
has its own template, say so in
`.claude/projects.md`. Every projects command reads that file first and follows it
over its own defaults; anything it leaves out falls back to them. It is prose, not
a schema — see [`examples/projects-conventions.md`](examples/projects-conventions.md)
for an annotated example. The kit's setup lays down a default one, from
`kit/templates/workspace/projects.md`, which is yours from then on.

Four lines there shape the 3.0 lifecycle:

- **Done** — where `/projects:close` moves a finished project;
  `projects/_done/<slug>/` by default.
- **Folder moves** — `the command` (the default) has close and hold make the
  moves they show, on a yes; `the person` has them print the commands instead.
- **Versioned default** — what `/projects:new` offers first.
- **Not adopted** — folders whose README is not a project README, such as a
  published site's home page; the commands leave them alone unless asked.

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

Part of the [workspace context kit](https://github.com/cyberscribe/agentic-workspace-kit).
In a workspace made with the kit, the kit sits at `kit/` and is the plugin
marketplace: `.claude/settings.json` points `agentic-workspace` at it, and the
plugin is read in place, so a kit update reaches it by pull. On its own:

```
/plugin marketplace add cyberscribe/agentic-workspace-kit
/plugin install projects@agentic-workspace
```

For assistants that load skills from a folder rather than plugins,
`kit/setup.sh skills` writes one thin skill per command (`kit-projects-new`,
`kit-projects-hold`, …) into `.claude/skills/`; each skill points at the command
file, so the procedure still has one source.

## Works with

- **closeout** — reconciles each session against the project's done-when list and
  Current state block, and uses its People roles for "who needs to know".
- **The kit's project template** — `kit/templates/project-readme.md` carries the
  same sections, so a project started by hand, one started by interview and one
  adopted all look alike.
- **The workspace plugin** — its state check reports each project's versioning,
  sensitivity, submodule and resource state, which the board reads, and its own
  session-start line names what is out of step across the workspace.
- **`kit/setup.sh`** — `link <slug>` maps resources, and `hooks` (with
  `--repo <folder>` for a project that is its own repository) keeps the git
  hooks running after a project moves.

MIT licensed, as part of the kit.
