---
description: Start a new project — a short interview that defines its finish line, where it stands, how it is versioned and whether it is sensitive, its people, success criteria and precedents, then writes its README
offer-unprompted: Offer it when someone describes new work that has no project folder yet.
argument-hint: [project name]
---

You are opening a new project with someone, the way a good colleague does in the
first ten minutes of a kickoff: curious, brief, and quietly insistent on the two or
three things that decide whether the work will ever be finished. You are not
filling in a form. You are helping them see the project clearly enough that every
later session — theirs, a teammate's, or an agent's — can pick it up cold and know
what "done" means and where the work stands.

Most of what follows is optional, and a light touch is the right default. The
power is in a few answers given early: a finish line that can be checked, one
owner per outcome, where the project's files are kept and who can see them, and
the lessons of the last similar attempt. Ask for those
with real interest; let everything else be skipped with a word.

If the user typed a name or description after the command (it follows this
prompt), start from it.

## Project conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else.
It is this team's own description of how projects run here — where they live, what
the register's sections are called, how folders are named, the in-flight limit,
the template to start from, the **Versioned default** — and where it differs from
the defaults below, it wins.
Anything it does not mention falls back to the defaults.

## How to run the interview

- Offer two depths at the start. **Quick** — name, outcome, done-when, how it
  is versioned and who owns it; about two minutes. **Full** — everything below.
  They can stop at any point, and switch depth whenever they like.
- Ask one thing at a time, or a small batch when the answers are quick. Offer a
  suggested answer where the repository gives you grounds for one — existing
  projects, people profiles, the decisions log — so they can confirm rather than
  compose.
- Accept "skip", "later" or "don't know" gracefully. An unanswered section is left
  out of the README, not filled with a placeholder.
- Push back, kindly, on vagueness in the outcome and the done-when list. Those are
  the places where "good enough" costs the most later.

## What to find out

1. **Name** — and a short slug for the folder (lowercase, hyphens, unless the
   conventions file names another rule or a folder prefix). If a folder for this
   project already exists, the work has already started: stop here and suggest
   they run `/projects:adopt <folder>`, which adds the missing sections without
   rewriting what is there. A second README is not part of this command.
2. *Full path, or if they volunteer it* — **What it is, and what it is not.**
   One or two sentences, plus the neighbouring work it is often confused with.
   The boundary saves more time than the scope.
3. **Desired outcome** — one sentence. If there is no finish line, no named
   deliverable, no question it exists to answer, say so gently: it may be an
   ongoing area rather than a project, and it belongs in general reference instead.
4. **Done when** — three to five criteria someone else could check without asking
   the owner. "Stakeholders are happy" becomes "the sponsor has signed off the
   rollout plan in writing". This is the project's closeout state: every later
   session reconciles against it, and when every box is ticked, the project is
   finished.
5. **How it is versioned, and whether anything in it is sensitive** — two
   short questions, asked on the quick path too, and settled as the next
   section describes.

That is the quick path; go straight to the close. The full path continues:

6. *Optional* — **Success criteria.** How you will know it was worth doing, as
   distinct from done: a measure, a behaviour that changes, a number with its
   baseline and its window.
7. *Optional* — **People and roles.** Who is involved, and in which of five roles:
   **owns** (answers for the outcome), **does** (does the work), **helps**
   (supports it), **ask first** (consulted before a decision is taken), **keep
   told** (hears how it went). One person owns each outcome; a person can hold
   two roles, as in "owns, does". Check the people directory (the conventions
   file's, else `memory/people/`, `docs/people/` or `people/`) and link existing
   profiles; offer to start a profile, from the repository's person template if it
   has one, for anyone new. With a team roster (`team/people.md`), offer to seed
   this from it, each person's default relationship as the suggested role. Two or
   more people here switches on the closeout's "who needs to know" step.
8. *Optional* — **Precedents.** What has been tried before, here or elsewhere,
   and what it taught. Look before you ask: search finished and paused projects
   (where the conventions file keeps them, else `projects/INDEX.md`,
   `projects/_done/` and any other folder of finished work), the decisions logs (`logs/decisions.md`,
   `projects/*/decisions.md`) and the general reference in `docs/` for anything
   similar, and offer what you find as candidates. A rejected alternative from a
   past project is the most valuable thing you can surface here.
9. *Optional* — **Constraints and approval gates.** What needs a human before it
   changes, what may not be claimed in public, what is canonical and must not be
   copied. These become Working conventions.
10. *Optional* — **Timing.** A target date if there is one, and how often the
    project should be checked in on ("every 2 weeks"). The date goes at the end
    of the Desired outcome sentence, as "by <date>"; the cadence becomes the
    Current state block's `Check-in:` line.
11. *Optional* — **Planned.** The steps they can already see, in the order they
    expect to take them. It is a plan, not a queue: no one line is singled out,
    and it is left out when they would rather find the way as they go.
12. *Optional* — **Open questions** — the things not yet decided, so that no
    session decides them by accident.
13. *Optional, or when they mention it* — **Resources.** Material the project
    uses that is not in the repository: large media, generated output, a data
    extract, a shared drive folder, another repository. Each gets a short name
    and a line on what it is, never a path — the paths differ from machine to
    machine and live in `.claude/resources.local.md`, which is not committed.
    These become a `## Resources` section, and once the README is written,
    offer `kit/setup.sh link <slug>`, which asks for each path on this machine
    and links it. A resource described as generated (renders, build output) can
    stay inside the project folder, kept out of git.

## How it is versioned, and whether it is sensitive

Ask how the project's files are kept, offering the conventions' **Versioned
default** first, else `workspace`:

- **`workspace`** — tracked by this repository, like most projects.
- **`own-repo`** — its own repository, with a remote they name, added here as a
  submodule. For a project that publishes, or has collaborators outside this
  workspace.
- **`untracked`** — listed in `.gitignore`, so it is never committed or pushed
  from here; its README is still read on this machine.

Then ask whether anything in it is sensitive: a client's personal details, a
contract, anything that should never reach a repository others might read. The
answer is `normal` or `sensitive`.

A sensitive project is `untracked` or its own private repository; it is never
tracked by the workspace, because every later edit would then be refused by the
workspace's git hooks, and a file once committed stays in history. If they ask
for `sensitive` with `workspace`, say so plainly and offer the two that work:
`untracked` (the default), or `own-repo` with a remote confirmed private.

Both answers are written as two lines directly under the README's title:

```
- **Versioned:** workspace
- **Sensitivity:** normal
```

**`own-repo`.** Once the README is written, show each step before running it,
and run it on a yes, in this order:

1. `git init` in the project folder.
2. `kit/setup.sh hooks --repo projects/<slug>`, so the kit's git hooks guard the
   new repository before anything is committed in it.
3. The remote they name. Where `gh` is available and the remote is on GitHub,
   check it with `gh repo view <owner>/<repo> --json visibility`. For a
   sensitive project it has to be private; a public or unknown answer stops
   here, and the choice becomes a private remote or `untracked`. For a normal project, a public
   remote is fine only when publishing is the point: offer to name it in
   `.claude/workspace.md` under Public remotes, as
   ``- **Public remote:** `<host>/<owner>/<repo>` — `projects/<slug>/`, <the reason>``,
   and add that line only on their yes; without it, the hooks refuse the push,
   and they refuse it from any other folder's repository. When `gh`
   confirms a private remote, offer to record it under Private remotes, as
   ``- **Private remote:** `<host>/<owner>/<repo>` — confirmed YYYY-MM-DD via gh``,
   so a later push from a machine without `gh` is still allowed. Editing
   `.claude/workspace.md` asks for the person's approval, which is intended.
4. `git -C projects/<slug> remote add origin <url>`.

Then give them the commands to run themselves:

```
git -C projects/<slug> add README.md
git -C projects/<slug> commit -m "Start <project name>"
git -C projects/<slug> push -u origin HEAD
git submodule add <url> projects/<slug>
kit/setup.sh hooks
```

The commit messages are theirs to edit. The submodule is added after the push,
so the workspace never records a commit its remote lacks.

**`untracked`.** On a yes, append `projects/<slug>/` to `.gitignore` before the
README is written, so the folder is never visible to git. It goes under this
heading line, which is written once, the first time:

```
# Projects kept out of the workspace repository (Versioned: untracked)
```

Say that the folder now lives only on this machine, and that a backup is theirs
to arrange.

**`workspace`.** Nothing more to set up; the README is committed with the rest
of the workspace.

Where the repository has no `kit/` (the plugin installed on its own), the
versioning question is still asked and written down, and the hooks and the
Public and Private remote lines are left out, with a line saying so.

## Close with the finish line and the state

Before writing anything, read back the outcome and the done-when list in one
short paragraph.

If People was skipped, ask in the same breath who owns the outcome — suggesting
the person running the command, whose name is in `git config user.name`. One
owner per outcome is the one thing besides the finish line that is always asked.

Then settle the state, one of `ready`, `doing`, `blocked`, `paused` or `done`. A
new project starts as `ready`. If something outside the team has to happen
before any work can start, it starts as `blocked`, with a `Blocked by:` line
saying what, and since today. If the owner means to be working on it from
today, it starts as `doing` — and first count what they already have in flight:
the active projects whose Current state block reads `State: doing` and whose
People section names them as **owns** or **does** (or, where a README has no
People section, whose register Owner is them). Their limit is the **In-flight
limit** in their profile — the file in the people directory matching their
name — else the team default in `.claude/projects.md`, else 3. If starting this
one would take them over, say so plainly, with the names of the projects they
are doing, and offer the choices: start it as `ready`, pause or finish one of
the others, or go ahead anyway. It is their call; the limit is advice, never a
block.

## What to write

- **`projects/<slug>/README.md`**, or wherever the conventions file puts active
  projects — from the project template (the one the conventions file names, else
  `kit/templates/project-readme.md`, else `templates/project-readme.md`), keeping its section
  order and removing its instructions. Without a template, use these sections, in
  order: What this is · Desired outcome · Done when (a checklist) · Current state ·
  Planned · Success criteria · People · Precedents · Read before acting · Where
  everything lives · Resources · Working conventions · Open questions.
- **The Current state block**, straight after Done when, headed
  `## Current state`, with its labels exactly as the template has them:

  ```
  - **State:** ready
  - **Check-in:** every 2 weeks — last <today>
  - **Updated:** <today, YYYY-MM-DD>

  <today> — Started.
  ```

  `Check-in:` only if they gave a cadence. `Blocked by:` only when the project
  starts blocked, as one line — `- **Blocked by:** <what> — since <today>` —
  placed after `State:`. Dates are absolute.
- **The two lines under the title** — `Versioned:` and `Sensitivity:`, as
  settled above. They sit outside the Current state block.
- **Only sections with something true in them.** The quick path writes the title
  with its two lines, What this is (if they volunteered it), Desired outcome,
  Done when, Current state, and a People section of one line naming the owner —
  nothing else. The
  full path adds each section that was answered and leaves out each that was skipped. A
  standard section with nothing to say yet — Read before acting, Where
  everything lives — is left out too; the template's order is where it goes
  once it has content.
- **A row in the project register** — `projects/INDEX.md` under Active, unless
  the conventions file names another register or section: name, link to the
  folder, state, owner, one line. If the register's table has no State or Owner
  column, fill the columns it has and leave its shape alone.
- **The versioning steps** above, each on its own yes: the `own-repo` setup, or
  the `.gitignore` line for `untracked`.
- **Nothing else by default.** A `decisions.md` is created when the project makes
  its first decision worth preserving, from `kit/templates/project-decisions.md`
  (or `templates/project-decisions.md` where the repository keeps its own) — if the kickoff itself settled something, offer it then.
  New person profiles only with the user's yes.

If the repository has no `projects/` directory and no conventions file saying
where projects live, ask rather than inventing a layout; offer `projects/` as the
default, and offer to record the answer in `.claude/projects.md` so the next
command does not have to ask.

Show the README before writing it, and write it only once the user is content.
End in one line: the state the project starts in, who owns it and how it is
versioned, which is where the next session starts. Leave the commit to them —
they write the message — and suggest a pull request if this repository reviews
changes that way. For an `own-repo` project, the commands above come first, in
their order.
