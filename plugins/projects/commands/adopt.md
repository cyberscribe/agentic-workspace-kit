---
description: Adopt a project that already exists — add the missing Done when, Now and People sections to its README as small insertions, without rewriting anything already there
offer-unprompted: Offer it when a session opens in a project folder whose README has no Now block or Done when list.
argument-hint: [folder or slug …] [draft]
---

You are taking on a project that was running before this system arrived, the way
a thoughtful new colleague takes over a shared folder: you read everything first,
you respect what the people before you wrote, and you add only the few things
that let anyone pick the work up cold — a finish line that can be checked, where
it stands now and what happens next, and who is involved. The existing prose is
theirs. You add beside it; you do not tidy it, reword it or reorder it.

The aim is that after one pass this project reads like one started with
`/projects:new`, while still sounding like itself.

## Project conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else,
and follow it over the defaults here: where active projects live, which file is
each project's entry point, what the register is called, whether a folder prefix
is part of the name, any **Section names** line, where people profiles are, the
in-flight limit, the review cadence, and what a state such as `parked` means for
where the folder lives.

Below, "the README" means the entry point, found as the session-start line and
the metrics find it: the one the conventions file names, else `README.md`, else a
`CLAUDE.md` in the folder. The sections go there even when the README says
another file is authoritative for the work; that file keeps its authority, and
the tracking lives where every command reads it.

## What the user asked for

Read what the user typed after the command (it follows this prompt).

- **Folders or slugs** name the projects to adopt. A slug is found where the
  conventions file keeps active projects, else in `projects/`. A priority or other
  prefix on a folder is not part of the project's name.
- **The word "draft"** (with or without dashes in front of it) switches to draft
  mode, below.
- **Nothing** — list the active projects in the register whose README lacks any
  of Done when, Now or People, and ask which to adopt. In draft mode, take every
  one of them.

Leave out, with a line saying why, a folder that is ignored by git
(`git check-ignore -q <folder>` succeeds), a submodule, or one with its own
`.git` that this repository does not track (`git ls-files <folder>` is empty):
its changes would not travel with this one. A folder with its own `.git` whose
files this repository also tracks is tracked twice — say so; in interactive mode
ask whether to adopt it, and in draft mode leave it and name the double
tracking. A folder simply not yet committed is adopted.

## What counts as already there

Look for each section by what it does, not only by its heading.

- **Done when** is present if the README has a list of finishing criteria under
  any name — "Definition of done", "Acceptance criteria", "Exit criteria",
  "Finish line". A hand-written one is left exactly as it is. The board, the
  session-start line and the metrics see a `Done when` checklist, or the heading
  names `.claude/projects.md` gives, so when it is under another name or not a
  checklist, say in the summary that they will not see it yet. In interactive
  mode, offer one small fix: record the name as a **Section names** line in
  `.claude/projects.md`, or insert a `Done when` heading above an unheaded list.
  Criteria written only as prose (a "Finish line" paragraph) get a proposed
  `Done when` checklist drawn from that text, inserted directly after it, the
  prose left as it is.
- **Now** is present if the README has the labelled lines `State:` and
  `Next action:`, bold (`- **State:**`) or plain (`State:`). One that is present
  but off the template's shape — an empty `Waiting on: —`, no dated line, a
  next action the work has overtaken — is left alone and named in the summary
  for `/projects:review`. A prose status section ("Current state", "Status") is
  not a Now block: it stays where it is.
- **People** is present if the README names who is involved under any heading,
  or in a bold inline label such as `**Contacts.**` — "Team", "Who",
  "Stakeholders". Leave it as written. If no one there is marked as owning the
  outcome, propose one `- <name> — owns` line (or `- not yet named — owns` when
  the files give no grounds) directly after it; an **owns** line, even
  `not yet named`, means this is done. The board, the session-start line and the
  metrics see People only under a `People` heading or a **Section names** alias,
  so under any other heading say so in the summary, and in interactive mode
  offer to record the name in `.claude/projects.md`.
- **Desired outcome** is present if the README, or a file it names as holding
  the goals, says what finishing looks like — a section such as "Goals", "Aims"
  or "Objective" counts. A statement of scope or purpose, or a plan with no end
  point, does not. If nothing does, propose one sentence, just before Done
  when: criteria need an outcome to be checked against. An outcome stated only
  as an unheaded line (a `Goal:` bullet) is there for a person but not for the
  session-start line: propose a `Desired outcome` heading with that sentence,
  inserted directly after it.
- **A block this command proposed earlier** carries the marker comment and
  counts as present. It is waiting for a person, not for another proposal.

A section that is present is not touched. That is what makes the command safe to
run twice: the second run finds everything present and adds nothing.

## Reading the project to propose

Read the README top to bottom, then what it points at, the folder's other files,
its `decisions.md` if it has one, and its history:
`git log --diff-filter=ACDM --date=short -- <folder>` for the commits that
changed its contents, their dates and authors (a commit that only moved or
renamed the folder is not activity). A folder git has never committed is judged
by its files' modification dates instead, and its people by what the files name.
If the README or the conventions file names another repository where the work
happens, its log counts too when you can read it. Evidence behind a symlink or
outside the repository can be read, but say so where you cite it, since a
colleague may not be able to check it. Draft each missing section in the
template's shape (`templates/project-readme.md`, or the one the conventions file
names):

- **Done when** — three to five criteria someone else could check, drawn from the
  README's goals, deliverables, milestones and open work. Tick one only where the
  files show it met, with the evidence in a few words; a milestone dated today
  or earlier with no confirmation in the files stays unticked. For a long-running
  practice or a goal years off, scope the list to the nearest milestone the files
  name, and say so in the dated line and the summary: it may be an area rather
  than a project, which is the person's call.
- **Now** —
  - `State:` the first that holds: `done` if the files say it is finished;
    `waiting` if the next step is someone other than the owner's — handed off
    with no confirmation back counts, dated from the hand-off; `parked` only if
    the files say it was set aside; `doing` if its contents changed within the
    review cadence and work is open; otherwise `next`. Age alone never proposes
    `parked`, which the conventions may tie to moving the folder: a quiet
    project is `next`, with the dated line saying how long it has been quiet.
    Decisions waiting on the owner are next actions, not waiting.
  - `Next action:` the most concrete open step the files name, with who takes it.
    If the files name none, write exactly `none found — decide at the next review`
    rather than inventing one; the board and the metrics read that as missing.
  - `Waiting on:` one line for each thing awaited from someone else, the label
    repeated on each — who, what, and `since` the date it started if the files
    give one. No line when nothing is awaited.
  - `Check-in:` only if the project names a cadence of its own; the conventions'
    review cadence is not one.
  - `Updated:` today.
  - Underneath, the dated line saying what the proposal was drawn from — "the
    last commit (2026-09-10)", or "the Status section below and the last commit
    (2026-09-10)". Where a prose status and other evidence disagree (a date that
    has passed, a later audit), the line names both and which one it trusted.
    Later updates rewrite this line and leave the prose alone.
- **People** — one line per person the README, the folder's files or the commit
  history names, with one of the five roles (**owns**, **does**, **helps**,
  **ask first**, **keep told**) and their profile if one exists. Name an owner
  only where the files, or an owner rule in the conventions file, give grounds;
  otherwise `- not yet named — owns`, which the board and metrics read as missing.

A proposal the person can confirm in a word is the aim; a confident guess is
harder to catch than an honest gap.

## Two ways to run

**Interactive — the default.** For each project, say in two lines what is there
and what is missing, then show the proposals as the diff they would make to the
README. Offer the quick path — "these look right, add them all" — or one section
at a time: confirm, edit, or skip. Write only what they confirm. A skipped
section is simply not added; the next run, or the next review, offers it again.

**Draft.** Ask nothing. Insert every proposal, and put this comment on the line
directly above each inserted section's heading (or above the inserted line, for
an owner's line added to existing People):

```
<!-- proposed by /projects:adopt YYYY-MM-DD: confirm or edit -->
```

with today's date. `/projects:review` lists unconfirmed proposals, and whoever
confirms one deletes its comment. Draft mode is for adopting many projects at
once, ahead of the person who will confirm them.

## How to insert

- Each addition is a small insertion where the template's order puts it:
  Desired outcome and Done when after the opening paragraphs (everything before
  the first section heading) or after a section saying what the project is — but
  where a Goals, Aims or Desired outcome section exists, Done when goes directly
  after it. Now always straight after Done when. People before the first section
  that gives a reading order, says where things live, or sets working
  conventions, whatever it is called; straight after Now if there is none.
- A README with no section headings gets its insertions after the title and the
  first paragraph, never at the end: the Now block is written to be read first.
  Then one more heading goes directly after them, `About this project`, so the
  file's remaining prose sits under its own heading rather than reading as part of
  People. In draft mode it carries the same proposed comment as the rest, and is
  confirmed with them.
- Inserted headings take the level of the README's existing section headings, so
  the outline stays whole: `###` in a README whose sections are `###`.
- Everything already in the file stays byte for byte as it was: no rewording,
  no reflowing, no reordering, no fixing of other things noticed on the way.
- A folder whose only entry point is its own `CLAUDE.md` takes the sections
  there. Only a folder with neither gets a README written: the title, the
  sections proposed here, and a first line saying what the folder already
  contains — shown first in interactive mode, marked in draft mode.
- The project register is left as it is. If the project has no row in it, say so
  in the summary and offer to add one (interactive mode only).

## Close

Summarise per project in a line or two: what was added, what was left alone,
what the board or metrics will not see yet (a Done when or People list under
another name, a Done when that is not a checklist), what the conventions tie to
the proposed state (a `parked` that means a folder move), anything in the prose
that disagrees with the proposal, and what is waiting for confirmation. A project
with nothing missing gets one line — "all sections present; nothing added" —
which is the command working. List the files changed. Leave the commit to them —
they write the message, and writing it is their check that they understand what
changed.
