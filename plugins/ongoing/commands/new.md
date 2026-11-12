---
description: Start an ongoing area — work with no finish line, kept up rather than finished — with a short interview for its desired state, the standards to keep, who is involved, how often it is checked, how it is versioned and whether it is sensitive, then write its README and register row
offer-unprompted: Offer it when someone describes a practice, responsibility or anything they keep up that has no finish line, or when /projects:new finds no finish line.
argument-hint: [name or description]
---

You are helping someone name a part of their life or work that is never finished:
a practice, a responsibility, a collection, a craft. It deserves the same clarity a
project gets, measured differently. A project is done when its boxes are ticked; an
area is healthy while its standards are met. Your job in the first ten minutes is to
help them say what they want to be true here, and how anyone would know it is.

Most of what follows is optional, and a light touch is the right default. The power is
in three answers: the desired state, standards someone else could check, and one owner.

If the user typed a name or description after the command, start from it.

## Where this works

`/ongoing:new` works inside a kit workspace: the folder this session was opened in, or one
above it, holds `kit/CLAUDE.kit.md` or `.claude/kit-templates.lock`. The kit's plugins
are installed for the person, so the command is offered in every folder. Outside a
workspace, say in one line that `/ongoing:new` works inside a kit workspace, and do nothing
else.

## Conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else, and
follow it over the defaults here. Its **Areas**, **Area register** and **Area template**
lines say where areas live, what the register is and which template to use; the rest
of it (people directory, versioning default, house rules) applies to areas as it does
to projects. Anything it does not mention falls back to the defaults: areas in
`ongoing/<slug>/` with `README.md` as the entry point, the register
`ongoing/INDEX.md` with the sections Active, Dormant and Archived (each a table of
Area · Folder · One-liner), and the template `kit/templates/area-readme.md`, else
`templates/area-readme.md`.

## How to run the interview

- Offer two depths. **Quick** — name, desired state, standards, cadence, how it is
  versioned and who owns it; about two minutes. **Full** — everything below. They can
  stop at any point and switch depth whenever they like.
- Ask one thing at a time, or a small batch when the answers are quick. Offer a
  suggested answer where the repository gives grounds for one — reminders or scheduled
  tasks that already serve it, people profiles, notes elsewhere — so they can confirm
  rather than compose.
- Accept "skip", "later" or "don't know" gracefully. An unanswered optional section is
  left out of the README, not filled with a placeholder.
- Push back, kindly, on vague standards. They are where "good enough" costs the most.

## What to find out

1. **Name** — and a short slug for the folder. If a folder for it already exists, in
   the areas location or among the projects, suggest `/ongoing:adopt <folder>` instead;
   a second README is not part of this command. If what they describe has a finish
   line after all, say so and offer `/projects:new` — the kit's command for work that
   ends.
2. *Full path, or if they volunteer it* — **What it is, and what it is not.** One or
   two sentences, plus the neighbouring work it is often confused with.
3. **Desired state** — one sentence: what they want to be true here, for as long as
   the area is kept up ("the collection in optimal health and looking its best"). It
   is a direction, not a finish line, so it may be broad; the standards make it
   checkable.
4. **Standards to keep** — two to five, each one someone else could check without
   asking the owner, together covering the desired state. "Look after the trees"
   becomes "no tree dries out in the growing season" and "each tree is photographed
   from the same front each season". Offer candidates drawn from what they have said.
   When they cannot name standards yet, write `- not yet named` rather than inventing
   them; `/ongoing:review` comes back to it.
5. **Check-in cadence** — how often the area should be looked at against its
   standards ("every 2 weeks", "monthly", "each season"). It becomes the `Check-in:`
   line, and the board measures the area against it rather than against the
   workspace's staleness setting.
6. **How it is versioned, and whether anything in it is sensitive** — asked on the
   quick path too, settled as `/projects:new` settles them: `workspace` (the
   conventions' **Versioned default** first), `own-repo` or `untracked`, and `normal`
   or `sensitive`, with the same rule that a sensitive area is never tracked by the
   workspace and the same setup steps, each shown and run on a yes.

That is the quick path; go to the close. The full path continues:

7. *Optional* — **People and roles.** Who is involved, in the five roles projects use:
   **owns** (answers for the area; one person), **does**, **helps**, **ask first**,
   **keep told**. Check the people directory (the conventions file's, else
   `memory/people/`, `docs/people/` or `people/`) and link existing profiles; offer to
   start a profile for anyone new, and with a team roster (`team/people.md`) offer to
   seed this from it. Two or more people switches on the closeout's "who needs to know"
   step for this area too.
8. *Optional* — **Recurring.** What keeps the standards met without anyone
   remembering: scheduled tasks, calendar reminders, routines. Look before asking —
   the scheduler's task files, the conventions' sources — and offer what you find.
9. *Optional* — **Projects.** Any piece of the area that has a finish line now (a
   season's repot, an exam). Each becomes a project through `/projects:new`, whose
   What this is names the area; a small one may sit inline under Projects with its
   outcome and a short Done when list.
10. *Optional* — **Precedents.** What has been tried before and what it taught, from
    finished projects, decisions logs and general reference, offered as candidates.
11. *Optional* — **Constraints.** What needs a human before it changes, what is
    canonical and must not be copied. These become Working conventions.
12. *Optional* — **Open questions**, and **Resources** (material outside the
    repository, named, never a path; `kit/setup.sh link <slug>` maps them per machine).

## Close with the desired state and the standards

Before writing anything, read back the desired state and the standards in one short
paragraph. If People was skipped, ask in the same breath who owns it, suggesting the
person running the command (`git config user.name`).

The state is `active`, or `dormant` when it is seasonal or set aside from today. Areas
do not count against the in-flight limit.

## What to write

- **`ongoing/<slug>/README.md`**, or where the conventions put areas, from the area
  template, keeping its section order and removing its instructions: the title with its
  `Versioned:` and `Sensitivity:` lines, then only the sections with something true in
  them. The quick path writes What this is (if volunteered), Desired state, Standards to
  keep, Current state and a one-line People section naming the owner.
- **The Current state block**, after Standards to keep, labels exactly as the template
  has them:

  ```
  - **State:** active
  - **Check-in:** every 2 weeks — last <today>
  - **Updated:** <today, YYYY-MM-DD>

  <today> — Started.
  ```

  No `Standards met:` line yet: `/ongoing:review` adds it at the first check-in, and until
  then the area reads as not yet reviewed.

- **A row in the area register** under its Active section (Dormant for a dormant
  area): name, link to the folder, one line. When the register does not exist yet,
  create it with a one-paragraph header saying what an area is and its three sections.
  For a sensitive area the line stays neutral.
- **The versioning steps**, each on its own yes.
- **Nothing else by default.** New person profiles only with the user's yes.

Show the README before writing it, and write it only once the user is content. End in
one line: the state, the check-in cadence, who owns it and how it is versioned. Leave
the commit to them — they write the message.
