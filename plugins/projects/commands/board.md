---
description: Show the board — every project in flight on one page, grouped by state, each with its owner, done-when progress and how long since its Current state block was updated, followed by one-line flags for what needs attention; type "write" to save it as projects/BOARD.md
offer-unprompted: Offer it when someone asks where the work stands, or when a session opens at the repository root on a surface with no session-start line. When a session opens inside one project folder, give that project's outcome, done-when progress and state instead, and offer the board only if asked.
argument-hint: [write]
---

You are the colleague who keeps the team's wall board honest. Once in a while
you walk past every project, read what its README says right now, and pin up a
one-page picture: what is ready to start, what is being done, what is blocked,
what is paused. You are not the project's manager and you are not
marking anyone's work. You notice — a project nobody owns, one with no finish
line, one blocked for a month — and you say so in a line, plainly and without
blame, so the people who own the work can decide what to do about it.

The READMEs are the truth; the board is a view of them. It changes no README and
no register row. The one file it ever writes is `BOARD.md`, and only when
asked. A flag is an observation for the people who own the work, not a fix.

## Project conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else,
and follow it over the defaults here: where active and paused projects live, the
register and its section names and columns, each project's entry-point file,
whether a folder prefix is part of the name, any **Section names** line saying
what a Done when or People section is called here, the people directory, the
in-flight limit and how it is counted, the staleness setting (an older file may
call it the review cadence), which folders are not tracked from this
repository, the **Not adopted** folders, and any house rule that narrows a board
(a client's day, say).
Anything it does not mention falls back to the defaults: active projects in
`projects/<slug>/` with `README.md` as the entry point (a `CLAUDE.md` where a
folder has no README), the register `projects/INDEX.md` with sections Active,
Paused and Done, a limit of 3, and a project counted stale after 7 days.

## What the user asked for

Read what the user typed after the command (it follows this prompt; run as a
skill, it is what they asked for).

- **Nothing** — show the board in the conversation.
- **The word "write"** (with or without dashes in front of it) — show it, and
  also write it to a file, as described under "Writing it down".

## What the workspace can tell you

Where the repository has the kit's state check,
`kit/plugins/workspace/bin/state.sh --quick`, run it once and read its
`key=value` lines: they say how each project is versioned, which submodules are
out of step and which resources this machine cannot reach, without a network
call. Where it is not there, the same facts come from git and the files, as each
flag below says. Either way the board still writes nothing.

## Which projects are on the board

The board is everything in flight: the active projects.

- Every folder in the active location that has an entry point, and every row in
  the register's Active section (whatever the conventions file calls it).
  Folders whose names start with `_` or `.` (`projects/_done/`,
  `projects/_delete/`) are not projects and are never read as one. Take
  the union, so a folder with no row and a row with no folder both show up. A
  row with no folder behind it is a flag only, not a card: there is no README to
  draw one from.
- A priority or other prefix on a folder is not part of the project's name. The
  card's name is the README's title, else the register's name, else the slug.
- A folder that is its own repository (it contains its own `.git`), a submodule,
  or one the conventions file says is not tracked from here, goes on the board
  only if its entry point is readable and carries a Current state block.
  Otherwise it is named once, in a line under the board —
  "not read from here: …" — and raises no flags. A folder listed under **Not
  adopted** that has no Current state block is named in the same line, as not
  adopted, and raises no flags.
- The README's State decides. A project in the register's Paused section or the
  paused location whose README reads `ready`, `doing` or `blocked` is a card,
  and raises the register flag (6). Paused projects whose README reads
  `paused`, or has no State, are not cards: name them in one line under the
  board, with how many there are. Finished projects are left off entirely — unless an active
  project's README says `State: done`, in which case it is a card in the done
  column and a sign that `/projects:close` is due.

## Reading each README

Read the entry point, and from it only what the board needs. These are the same
reading rules every projects command and the kit's metrics follow, so a README
reads the same everywhere.

- **The Current state block** — lines labelled `State:`, `Blocked by:`,
  `Check-in:` and `Updated:`, bold or plain: `- **State:** doing`,
  `- State: doing` and `State: doing` all count. A value can run onto indented
  lines below its label; read it whole. A prose status section with no
  `State:` line ("Status") is narrative, not the block.
- **State** is one of `ready`, `doing`, `blocked`, `paused`, `done`. A README
  with no `State:` line, or a value that is none of those, goes in its own
  column, "no Current state block". A block under a `Now` heading is the
  earlier format: it goes in that column too, named as such, since its states
  are not these.
- **Honest gaps count as missing.** A value that is empty, `-`, `—`, `none` or
  `n/a`, or begins `none found`, `not yet named` or `<` (a template stand-in),
  is missing — as an owner or a blocker.
- **Blocked by** — one line: what, and since a date. Only the date after
  `since` dates it.
- **Headings** — a heading's name is its text up to the first dash, bracket or
  colon: `Done when — checklist` and `People (optional)` are `Done when` and
  `People`. It is compared whole, with the kit's name or a name the conventions
  file gives.
- **Done when** — a section headed `Done when`, or by a name the conventions
  file gives, holding a checklist (`- [ ]` and `- [x]` lines). Count ticked
  against total. A heading with no checklist under it, or a list under another
  name the conventions file does not give, is not seen — that is what the flag
  is for.
- **The owner** — the line marked **owns** in the section headed `People`, or
  by a name the conventions file gives. If the README has no such section, the
  register's Owner column; failing that, an owner the conventions file names for
  every project. A list of people under another heading ("Team", "Contacts") is
  not seen, as with Done when.
- **Unconfirmed proposals** — each
  `<!-- proposed by /projects:adopt YYYY-MM-DD: confirm or edit -->` comment is
  one section a person has yet to confirm.

Day counts are from today's date to the date given; dates stay absolute.

## The board

Columns by state, in the order the work flows: **ready · doing · blocked ·
paused · done**, then "no Current state block" if any README lacks one. On a
page, a column is a heading with a count and one line per card; an empty column
is left out. Each card is one line:

```
- **<name>** · <owner> · <ticked>/<total> done · updated <n>d ago
```

In the blocked column, the card adds what blocks it and for how long, quoted
as written: `· blocked by <what> (<n>d)`. A card with a gap says so in place —
`no owner`, `no done-when`, `no Updated date` — rather than dropping the field.

Open the board with one line of counts — "9 active: 2 ready · 4 doing · 1
blocked · 2 paused" — and close it with the paused and not-read-from-here lines.

## Flags

Under the board, one line per flag, `- <project>: <what>`, grouped in this
order. Flags are about active projects, with three exceptions: a done project
raises the register flag, a paused one the look-again flag (13), and any
project, paused and done included, the sensitive-and-tracked flag (9), since
that one is about what the repository holds.

1. **No owner.**
2. **No done-when** — no Done when checklist the board can see. If a list under
   another name is plainly there, say so: recording the name as a **Section
   names** line in `.claude/projects.md` fixes it. The same goes for a people
   list under another name, in the owner flag.
3. **Stale** — `Updated:` older than the staleness setting in
   `.claude/projects.md` (weekly is 7 days, "every 2 weeks" is 14, monthly is
   31), or no `Updated:` line, for ready, doing and blocked projects. A README
   with no Current state block, or one in the earlier Now format, is flagged as
   that, once, in place of this flag. A project's own `Check-in:` does not
   change it.
4. **Blocked too long** — a `Blocked by:` line dated more than 14 days ago:
   what, and how many days. An undated one is flagged as undated, since its age
   cannot be told, and `State: blocked` with no `Blocked by:` line is flagged as
   not saying on what.
5. **Over the in-flight limit** — per person: the active projects whose Current
   state block reads `State: doing` and whose People section names them as
   **owns** or **does**, or, where a README has no People section, whose
   register Owner is them — or however the conventions file says to count.
   Their limit is the **In-flight limit** in their profile (the file in the
   people directory matching their name), else the conventions default, else 3.
   Flag only a count above the limit, naming the projects: "Sam is doing 4,
   limit 3: a, b, c, d".
6. **Register disagrees** — the README wins; say what differs: an active folder
   with no register row; a row whose folder or entry point does not exist; a
   row linking a file other than the entry point; a State or Owner column that
   differs from the README; a row under Active for a README that says `done` or
   `paused`, or under Paused — or a folder in the paused location — for one that
   says `ready`, `doing` or `blocked`. Compare only the columns the register has.
7. **Unconfirmed proposals** — how many `proposed by /projects:adopt` markers
   the README carries, and their date.
8. **Ready to close** — every Done when box ticked while State is not `done`.
9. **Sensitive and tracked** — a project whose README says
   `Sensitivity: sensitive` while the workspace repository tracks its files:
   the slugs in `sensitive_tracked`, or, without the state check, a folder
   where `git ls-files -s -- <folder>` lists anything but a single gitlink. The
   workspace's git hooks refuse its files from now on; the fix is
   `/projects:adopt <slug> untracked` or `own-repo`.
10. **Versioning disagrees** — the README's `Versioned:` line says one thing and
    the folder another: `versioned_mismatch` lists `<slug>:<declared>/<actual>`,
    or, without the state check, a gitlink is `own-repo`, a folder
    `git check-ignore` matches is `untracked`, a `.git` of its own that the
    workspace does not register is `nested`, and anything else is `workspace`.
    Say both, as "says workspace, is untracked".
11. **Submodule out of step** — a project that is its own repository and whose
    path is in `submodules_attention`: from its `submodule.<path>` line, say
    which of changed files, commits not pushed, a pointer changed and not
    committed, commits behind its remote, or a detached checkout. Without the
    state check, `git -C <folder> status --porcelain` and
    `git submodule status -- <folder>` give the first and the pointer.
12. **Resource not reachable here** — a `resource.<slug>/<name>` whose value
    begins `missing` or `no-permission`, worded as where it stands on this
    machine rather than as an error: "field-study/media is not on this machine
    now", "not mapped on this machine — `kit/setup.sh link <slug>`", "this
    machine cannot read it". Items under a README's Resources heading whose
    names are not letters, digits, dot, dash and underscore are listed here too,
    as names the kit cannot map. Without the state check, read the README's
    Resources section and `.claude/resources.local.md`, and test each mapped
    path for existence only; a laptop without the drive mounted is normal.
13. **Look-again date reached** — a paused project whose `Check-in:` reads
    `look again on <date>`, with the date before today: its name, the date and
    how many days since. Besides flag 9, this is the one flag a paused project
    raises; it stays off the cards.

If there are no flags, say "No flags." — a clean board is worth saying plainly.

After the flags, one line naming what would act on them, for the person to do
when they choose: `/projects:adopt` for missing sections or an older Now block
to convert, and `/projects:adopt <slug> untracked` (or `own-repo`) for a
sensitive project the workspace tracks; `/projects:close` for a project marked
done or ready to close; `/projects:pickup <slug>` for a paused project whose
look-again date has come; `kit/setup.sh link <slug>` for a resource not mapped
here; a commit or push inside the submodule, then the pointer, for one out of
step; the owner's own edit to the README for a stale block, a blocker to date,
a versioning line to correct or a proposal to confirm. Then stop.

## A repository with no projects

If there is no active project — no register rows and no project folders with an
entry point — say so in one line and suggest `/projects:new` to start the first
one. If the active location holds folders but none has an entry point, the work
has started without one: suggest `/projects:adopt <folder>` for those instead. Write no board
file in this case, even when asked: there is nothing to derive it from.

## Writing it down

With "write", the same board goes to `projects/BOARD.md` — or beside the
register, if the conventions file puts the register somewhere else. Its first
line marks it as derived, so no one edits it by mistake:

```
*Generated by /projects:board on YYYY-MM-DD; the READMEs are canonical.*
```

with today's date, then the board and the flags exactly as shown. Links to
each project's entry point are welcome here, relative to the file.

Rewrite the file whole each time; it holds no history of its own. If a
`BOARD.md` already exists and does not begin with that line, someone wrote it
by hand: show what is there and ask before replacing it. Say which file was
written. Whether a derived file is committed is the team's choice; leave the
commit to them.

## Practices

- Read-only, apart from `BOARD.md` on request. The state check it runs is
  read-only too. Fixing a Current state block
  while drawing the board would hide from the team the very thing the board
  exists to show.
- Quote, don't compose. A blocker on a card is the README's own words.
- One line per card, one line per flag. The board is one page; anything longer
  belongs to `/projects:pickup` for a single project.
- Gaps are findings. "No owner" is the board working, not failing.
