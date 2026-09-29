# projects — start a project right for agentic co-working

A Claude Code plugin for the life of a project, kept in the project's own
README so that people and agents read the same thing. Eight commands, one
session-start line:

| Command | What it is for |
|---|---|
| **`/projects:new`** | Open a project the way a good kickoff does: a short interview, then its entry point. |
| **`/projects:adopt <folder>`** | For a project that already exists: add only what is missing (Done when, Now, People) as small insertions. |
| **`/projects:capture <text>`** | Get a thought into the team inbox without stopping to sort it. |
| **`/projects:board`** | Everything in flight on one page, with one-line flags for what needs attention. |
| **`/projects:review`** | The regular tracking pass: empty the inbox, walk the projects that need a look. |
| **`/projects:close <slug>`** | The finish line, done properly: evidence, a short retrospective, who needs to hear. |
| **`/projects:pickup <slug>`** | A cold-start brief for anyone taking a project over or coming back to it. |
| **`/projects:mine [name]`** | Everything on one person, as plain lines for their own task manager. |

Most of it is optional. What it insists on, kindly, is the part that decides
whether the work ever finishes:

- **A desired outcome** — one sentence, with a finish line.
- **Done when** — three to five criteria someone else could check. This is the
  project's closeout state: later sessions reconcile against it, and when every
  box is ticked the project is finished.
- **A next action** — one concrete, visible step, with who takes it.

And what it offers, if you want it:

- **People and roles** — five roles: **owns** (answers for the outcome, one person
  per outcome), **does**, **helps**, **ask first** (consulted before a decision)
  and **keep told** (hears how it went), linked to people profiles. Two or more
  people switches on the closeout plugin's "who needs to know" step.
- **Success criteria** — how you'll know it was worth doing, as distinct from done.
- **Precedents** — it searches finished projects and decisions logs for similar
  work before asking, because a rejected alternative from last time is the most
  valuable thing to know at the start.
- **Next up, Parked, constraints, a check-in cadence, open questions.**

## The Now block

Every project README carries a small tracking block straight after Done when, so
where the project stands is the second thing anyone reads:

```
## Now

- **State:** doing
- **Next action:** Priya drafts the rollout email
- **Waiting on:** Sam — the signed budget — since 2026-09-14
- **Waiting on:** Legal — the data-sharing clause — since 2026-09-20
- **Check-in:** every 2 weeks — last 2026-09-21
- **Updated:** 2026-09-24

2026-09-24 — Plan agreed; the rollout email is the last thing before sign-off.
```

`State:` is one of `next`, `doing`, `waiting`, `parked`, `done`. The labels are
fixed, because the plugin's other commands and the kit's metrics read them; each
thing awaited is its own line with the label repeated. A next action or owner
written as `none found …` or `not yet named` is an honest gap and counts as
missing. The dated line underneath is free prose, rewritten rather than added to. Each
working session leaves the block true when it ends. The register,
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
- **Waiting on** — one item per line, dated only by the date after `since`. A
  `waiting` project with a Waiting on line has what it needs in place of a next
  action.
- **The owner** — the **owns** line under People; with no People section, the
  register row's Owner, else a backticked **Owner:** in `.claude/projects.md`.
- **The entry point** — the one `.claude/projects.md` names, else `README.md`,
  else a `CLAUDE.md` in the folder; where there are two, the first with a Now
  block.
- **Which projects** — every folder in the active location with an entry point,
  and every register row under Active: the union. The README's State decides: a
  register-paused project whose README reads `next`, `doing` or `waiting` is
  active, and flagged for the register to catch up.

## The inbox

Things the team should see but nobody has decided on yet go in `inbox.md` at the
repository root (the conventions file can move it), one line each:

```
- [2026-09-24] Ask legal whether the new retention rule covers exports — Sam
```

Emptying it means deciding each line: it becomes a project, a next action or
next-up line in an existing project, something waited on, a parked idea,
reference to file, or nothing — and the line is removed. The inbox is tracking,
not reference: it is kept empty, never kept. Personal to-dos belong in each
person's own system.

## Adopting existing projects

`/projects:adopt` is for work that was running before the plugin arrived. It
reads the README, the folder and its history, proposes the missing sections, and
inserts them where the template's order puts them. It recognises a finishing list
or a team list under other names and leaves it alone, and it treats a prose status
section as the narrative under a new Now block rather than replacing it. Running
it twice adds nothing the second time.

It asks before writing. Type `draft` after the command to have it ask nothing:
it inserts every proposal, each marked for a person to confirm —

```
<!-- proposed by /projects:adopt 2026-09-28: confirm or edit -->
```

— which is the way to adopt many projects at once, ahead of the person who will
confirm them. `/projects:review` walks the proposals still unconfirmed.

## Capture

**`/projects:capture <text>`** gets a thought into the team inbox without
stopping to sort it. It adds one line to `inbox.md` (or wherever
`.claude/projects.md` says captures go) —
`- [2026-09-29] Ask legal whether exports are covered — Sam` — and confirms in
one line. It asks nothing, except for the text if you typed none. Deciding what
each line becomes is left to `/projects:review`. If the capture is plainly about
one active project, it offers to move it straight to that project's Next up, and
moves it only if you say so.

## Board

**`/projects:board`** shows everything in flight on one page, built from the
project READMEs. Projects are grouped by state (next · doing · waiting · parked ·
done), one line each: owner, next action, done-when progress, and days since the
Now block was updated. Under the board, one line per thing that needs attention:
no next action, no owner, no done-when, a Now block older than the review
cadence, something waited on for more than 14 days, someone over their in-flight
limit, a register row that disagrees with its README, and `/projects:adopt`
proposals nobody has confirmed. It only reads. Type `write` after the command to
also save it as `projects/BOARD.md`, whose first line marks it as generated; the
READMEs stay canonical. On a repository with no projects it says so and suggests
`/projects:new`.

## Review

**`/projects:review`** is the regular tracking pass. The workspace hygiene pass
asks whether things are filed in the right place; this one asks whether the work
is moving. It reads everything first and opens with a short agenda. Then it
empties the inbox one line at a time, with you deciding what each becomes. It
walks only the projects that need a look — no next action or owner, a stale Now
block, a waiting-on older than 14 days, a finish line fully ticked — and asks one
question about the rest. Nudges for things you are waiting on are drafted for you
to send, never sent or stored. After the walk it asks once about parked ideas and
paused projects, holds any check-ins that are due, and walks the proposals
`/projects:adopt` left unconfirmed. It ends by writing
`audits/review-YYYY-MM-DD.md`, which holds counts and project names only. When
nothing needs deciding, it fits on one screen. Type project names after the
command to walk only those, or a step name (`inbox`, `projects`, `parked`,
`check-ins`, `proposals`) to run just that step.

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
criteria are ticked, the Now block with day counts, the last three decisions and
the last five commits to the folder, anything not yet committed, the open
questions, and who to ask (the owner and the *ask first* people). It closes with
a short "worth knowing" list of gaps and stale lines. It quotes the README rather
than paraphrasing it, fits in under 40 lines, and only reads. Where something
needs fixing, it names the command that fixes it and leaves the fixing to you.

## Mine

**`/projects:mine [name]`** lists everything that is on one person across every
active project, as plain lines ready to paste into any personal task manager:
`- <action> — <project> @<context>`. That covers their own next actions, anything
others are waiting on them for, what they are waiting on as an owner, and
`Decide the next action` for any project they own that has none. Contexts
(`@computer`, `@call`, `@meeting`, `@waiting`) are inferred and can be changed:
in the conversation, by a **Contexts:** line in `.claude/projects.md`, or by a
Contexts row in the person's profile. The list defaults to
`git config user.name`, and the command says whose list it is before going on.
It is read-only: the kit feeds each person's own system and never becomes a
second one.

## Session-start line

When a session opens inside a project folder, the plugin's SessionStart hook
reads the project's entry point and gives three lines: the desired outcome, Done
when progress ("2 of 4 ticked"), and the next action with its owner. You see
them at the top of the session, and the agent reads them as context. It says so
when sections are still proposals from `/projects:adopt`. Anywhere else in the
repository it says nothing, except at most once a day: one line if the inbox has
items or an active project has no next action. A clean day prints nothing.

The hook finds projects, the inbox, the entry point and any renamed sections from
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
  Now block, and uses its People roles for "who needs to know".
- **The kit's project template** — `templates/project-readme.md` carries the same
  sections, so a project started by hand, one started by interview and one
  adopted all look alike.

MIT licensed, as part of the kit.
