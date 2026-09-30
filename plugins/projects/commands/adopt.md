---
description: Adopt a project that already exists — add the missing Done when, Current state and People sections and its versioning lines to its README as small insertions, without rewriting anything already there; or change how a project is versioned (workspace, own-repo, untracked)
offer-unprompted: Offer it when a session opens in a project folder whose README has no Current state block or Done when list, unless .claude/projects.md lists that folder under Not adopted.
argument-hint: [folder or slug …] [draft] | <slug> workspace|own-repo|untracked
---

You are taking on a project that was running before this system arrived, the way
a thoughtful new colleague takes over a shared folder: you read everything first,
you respect what the people before you wrote, and you add only the few things
that let anyone pick the work up cold — a finish line that can be checked, where
it stands now, and who is involved. The existing prose is theirs. You add
beside it; you do not tidy it, reword it or reorder it.

The aim is that after one pass this project reads like one started with
`/projects:new`, while still sounding like itself.

## Project conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else,
and follow it over the defaults here: where active projects live, which file is
each project's entry point, what the register is called, whether a folder prefix
is part of the name, any **Section names** line, where people profiles are, the
in-flight limit, the staleness setting, what a state such as `paused` means
for where the folder lives, the **Versioned default**, and the **Not adopted**
folders.

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
- **One slug followed by `workspace`, `own-repo` or `untracked`** changes how
  that project is versioned; see "Changing how a project is versioned" below.
  Nothing else is adopted in that run.
- **Nothing** — list the active projects in the register whose README lacks any
  of Done when, Current state or People, and ask which to adopt. In draft mode, take every
  one of them. Folders listed under **Not adopted** are left out of this list.

Leave out, with a line saying why, a folder that is ignored by git
(`git check-ignore -q <folder>` succeeds), a submodule, or one with its own
`.git` that this repository does not track (`git ls-files <folder>` is empty):
its changes would not travel with this one. A folder with its own `.git` whose
files this repository also tracks is tracked twice — say so; in interactive mode
ask whether to adopt it, and in draft mode leave it and name the double
tracking. A folder simply not yet committed is adopted.

A folder listed under **Not adopted** in `.claude/projects.md` — a published
site whose `README.md` is its home page, say — is adopted only when the person
names it, and even then, ask before writing to its entry point, since the
sections would appear on that page. In draft mode, leave it out and name it in
the summary.

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
- **Current state** is present if the README has a labelled `State:` line, bold
  (`- **State:**`) or plain (`State:`), under any heading but `Now` (see the
  next item). One that is present but off the
  template's shape — no `Updated:` line, no dated line, a state the work has
  overtaken — is left alone and named in the summary. A prose status section
  ("Status", or a `Current state` heading over prose with no `State:` line) is
  not the block: it stays where it is, as the narrative. When that prose is
  already headed `Current state`, the proposed labelled lines go directly under
  its heading, above the prose, rather than under a second heading of the same
  name.
- **An older Now block** — a section headed `Now` with a `State:` line, the
  block's earlier format — is present, in the old format. Name it in the
  summary. In interactive mode, offer the conversion as a diff for the person
  to confirm: the heading becomes `Current state`; `next` becomes `ready`,
  `parked` becomes `paused`, and `waiting` becomes `blocked`, with the thing
  awaited as its one `Blocked by:` line (what, and since when), unless the
  person says the work can go on without it, in which case `doing`; `doing`
  and `done` stay; `Check-in:`, `Updated:` and the dated line stay; the block's
  other labelled lines go. A proposed marker above it stays. In draft mode it is
  left exactly as it is.
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
- **The versioning lines** — `Versioned:` and `Sensitivity:`, labelled lines
  directly under the title, bold or plain — are present when the README has
  them anywhere outside the Current state block. When either is missing,
  propose both, directly under the title. `Versioned:` is what the folder is:
  `own-repo` for a submodule, `untracked` when `git check-ignore -q <folder>/`
  matches, `workspace` otherwise. `Sensitivity:` is `sensitive` when the files
  hold anything that should never reach a repository others might read — a
  client's personal details, a contract, health or money matters — with the
  reason named in the summary, and `normal` otherwise. A `sensitive` project
  that the workspace tracks cannot stay tracked: the workspace's git hooks
  refuse to commit its files, this README included. Name it in the summary
  and offer the fix first, `/projects:adopt <slug> untracked` (or `own-repo`),
  which writes the lines as part of the move; in draft mode, write nothing to
  that project and name it.
- **Resources** — a `## Resources` section naming material outside the
  repository. When the README or the folder points at such material (an
  absolute path, a drive folder, a symlink out of the folder, a "the data is
  on …" line) and there is no such section, propose one: a short name and a
  line on what it is for each, never a path. Then offer
  `kit/setup.sh link <slug>`, which maps each name on this machine. A tracked
  symlink that carries a machine path is named in the summary, with the
  resource that would replace it.
- **A block this command proposed earlier** carries the marker comment and
  counts as present. It needs a person to confirm it, not another proposal.

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
- **Current state** —
  - `State:` the first that holds: `done` if the files say it is finished;
    `blocked` if the work cannot move until something outside the team happens
    — a hand-off with no confirmation back counts, dated from the hand-off;
    `paused` only if the files say the work was stopped for now; `doing` if its contents
    changed within the staleness setting's window and work is open; otherwise
    `ready`. Age alone never proposes `paused`, which the conventions may tie
    to moving the folder: a quiet project is `ready`, with the dated line saying
    how long it has been quiet. A decision the owner has yet to take does not
    block the project.
  - `Blocked by:` only with `blocked`: one line saying what the work cannot move
    without, and `since` the date it started if the files give one.
  - `Check-in:` only if the project names a cadence of its own; the conventions'
    staleness setting is not one.
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
section is simply not added; the next run offers it again.

**Draft.** Ask nothing. Insert every proposal, and put this comment on the line
directly above each inserted section's heading (or above the inserted lines,
for an owner's line added to existing People and for the versioning lines under
the title):

```
<!-- proposed by /projects:adopt YYYY-MM-DD: confirm or edit -->
```

with today's date. `/projects:board` flags unconfirmed proposals, and whoever
confirms one deletes its comment. Draft mode is for adopting many projects at
once, ahead of the person who will confirm them.

## How to insert

- The versioning lines go directly under the title, before anything else.
- Each addition is a small insertion where the template's order puts it:
  Desired outcome and Done when after the opening paragraphs (everything before
  the first section heading) or after a section saying what the project is — but
  where a Goals, Aims or Desired outcome section exists, Done when goes directly
  after it. Current state always straight after Done when. People before the
  first section that gives a reading order, says where things live, or sets
  working conventions, whatever it is called; straight after Current state if
  there is none. Resources goes after the section that says where things live,
  else before Working conventions or Open questions, else at the end.
- A README with no section headings gets its insertions after the title and the
  first paragraph, never at the end: the Current state block is written to be
  read first.
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
how it is versioned and whether it is sensitive (and any disagreement between
the two, or with the folder),
what the board or metrics will not see yet (a Done when or People list under
another name, a Done when that is not a checklist), what the conventions tie to
the proposed state (a `paused` that means a folder move), an older Now block
left for conversion, anything in the prose that disagrees with the proposal,
and what a person has yet to confirm. A project with nothing missing gets one
line — "all sections present; nothing added" — which is the command working. List the files changed. Leave the commit to them —
they write the message, and writing it is their check that they understand what
changed.

## Changing how a project is versioned

Run as `/projects:adopt <slug> workspace`, `own-repo` or `untracked`. It changes
how one project's files are kept, and in its README only the `Versioned:` line.

Start from what the folder is, not only what its README says: a gitlink
(`git ls-files -s -- projects/<slug>` shows mode `160000`) is `own-repo`; a
folder `git check-ignore -q projects/<slug>/` matches is `untracked`; a folder
with a `.git` of its own that the workspace does not register is a nested
repository, treated as `own-repo` without the submodule; anything else is
`workspace`. Where the README's line says otherwise, say so; the transition
starts from the folder.

Each transition is shown first as the whole list of commands, in order, and
then run one step at a time on a yes. Steps that commit or push are given as
commands for the person to run, with each message theirs to edit. Every
transition that creates, moves or removes a gitlink ends with
`kit/setup.sh hooks`, so the git hooks follow the change. Where the repository
has no `kit/`, those steps are left out with a line saying so.

A `sensitive` project goes only to `untracked`, or to `own-repo` with a remote
confirmed private. A move to `workspace` is refused while its README says
`sensitive`; changing that line first is the person's decision, made in the
README, not here.

**workspace → own-repo.**

1. First, what history holds beyond the current tree. List the files the folder
   once held and no longer does —
   `git log --diff-filter=D --name-only --format= -- projects/<slug>` — and the
   paths committed in the past that are ignored now, from
   `git log --name-only --format= -- projects/<slug>` checked with
   `git check-ignore`. Show both lists.
2. A fresh `git init` in the folder is the default: the new repository starts
   from today's files and takes none of that history with it. Keeping the
   folder's history with `git subtree split --prefix=projects/<slug>` is
   offered only when both lists are empty, the remote is confirmed private,
   and `git subtree -h` answers here with its usage rather than "not a git
   command" (subtree is not installed everywhere, and a usage message exits
   129 even where it is). Otherwise files deleted or ignored long ago would
   travel to the new remote.
   With the split, the folder's repository takes that history:

   ```
   git subtree split --prefix=projects/<slug> -b split/<slug>
   git -C projects/<slug> init
   git -C projects/<slug> fetch ../.. split/<slug>
   git -C projects/<slug> reset FETCH_HEAD
   ```

3. `kit/setup.sh hooks --repo projects/<slug>`, before anything is committed in
   the new repository.
4. The remote the person names, checked as `/projects:new` checks one: with
   `gh repo view <owner>/<repo> --json visibility` where `gh` is available;
   private for a sensitive project; a public remote for a normal one only with
   a `Public remote` line in `.claude/workspace.md` that names the folder
   (`projects/<slug>/`), added on the person's yes;
   a confirmed private one offered as a `Private remote` line.
5. The `Versioned:` line becomes `own-repo`, before the project's first commit,
   since the README now belongs to the project's own repository.
6. The commands for the person: `git -C projects/<slug> remote add origin
   <url>`, then add, commit and push inside the project
   (`git -C projects/<slug> push -u origin HEAD`).
7. `git rm -r --cached projects/<slug>` — the workspace stops tracking the
   folder's files, which stay on disk.
8. `git submodule add <url> projects/<slug>`, which finds the repository
   already in place.
9. `kit/setup.sh hooks`.

The workspace's earlier commits still hold the files; say so, as for
`untracked` below.

**workspace → untracked.**

1. Append `projects/<slug>/` to `.gitignore`, under the heading line
   `# Projects kept out of the workspace repository (Versioned: untracked)`,
   written once.
2. `git rm -r --cached projects/<slug>` — the files stay on disk, and the next
   commit records them as no longer tracked.
3. The `Versioned:` line becomes `untracked`.

Say plainly that earlier commits still hold the files: anyone with the
repository, and every remote it was pushed to, can read them there. Rewriting
history to remove them is the person's call, not this command's, and it
touches every clone.

**untracked → workspace.** Refused while the project is `sensitive`.
Otherwise the `.gitignore` line `projects/<slug>/` is removed (any other line
naming the folder is listed, and changed on a yes), and the `Versioned:` line
becomes `workspace`. Adding the files, `git add projects/<slug>`, is the
person's, with the commit.

**untracked → own-repo.** As workspace → own-repo, without the history step,
since the workspace never held the files. The `.gitignore` line for the folder
is removed just before `git submodule add`, which refuses an ignored path.

**own-repo → workspace.** Refused while the project is `sensitive`. The
submodule's name is the one whose path is the folder in
`git config -f .gitmodules --get-regexp '^submodule\..*\.path$'`.

1. `git rm --cached projects/<slug>` — the gitlink goes; the files stay.
2. `git config -f .gitmodules --remove-section submodule.<name>`, and
   `git config --remove-section submodule.<name>` where the local configuration
   has the entry.
3. The folder's `.git` is moved to `_delete/<slug>.git`, and
   `$(git rev-parse --git-common-dir)/modules/<name>`, when it exists, to
   `_delete/modules-<name>`. Nothing is deleted: `_delete/` is kept out of git,
   and the person empties it when they are sure. The project's remote keeps its
   history.
4. The `Versioned:` line becomes `workspace`.
5. The person adds and commits: `git add .gitmodules projects/<slug>`.
6. `kit/setup.sh hooks`.

**own-repo → untracked.**

1. Append `projects/<slug>/` to `.gitignore` under the heading line above.
2. The gitlink and the `.gitmodules` section removed, as in own-repo →
   workspace steps 1 and 2.
3. The folder's `.git` is kept: it is still a repository of its own, pushing to
   its remote. Where `.git` is a file pointing into
   `$(git rev-parse --git-common-dir)/modules/<name>`, that folder holds the
   repository and is kept too; say so, since it now lives inside the
   workspace's git folder.
4. The `Versioned:` line becomes `untracked`.
5. `kit/setup.sh hooks`.

Close a transition with what changed, what the person still runs (in order),
and, for any move away from `workspace`, the line on what history still holds.
