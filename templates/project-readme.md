# <Project name>

*Copy to `projects/<slug>/README.md` and add a row to `projects/INDEX.md`, or run `/projects:new` to be
interviewed for it; `/projects:adopt` adds the tracking sections to a project that already has a
README. Sections marked optional are deleted when they would be empty, rather than left as
placeholders. Delete this block.*

*This file is the project's entry point. An agent picking the project up reads it top to bottom, then
opens only what the task touches — so it carries orientation and pointers rather than content.*

---

## What this is

One paragraph. What the project is, and what it is **not** — the neighbouring work it is often
confused with, and where that lives instead. Naming the boundary saves more time than describing the
scope.

## Desired outcome

What finishing looks like. A project has a defined outcome, a finish line, or a named deliverable;
if this section is hard to write, the thing may be an ongoing area rather than a project, and it
belongs in general reference instead.

## Done when

The project's closeout state: three to five criteria someone else could check without asking the
owner. Each working session reconciles against this list; when every box is ticked, the project has
crossed its finish line and moves to done.

- [ ] <observable criterion — "the sponsor has signed off the plan in writing", not "stakeholders are happy">
- [ ] <…>

## Now

- **State:** <next · doing · waiting · parked · done>
- **Next action:** <who does one concrete, visible step — "Priya drafts the rollout email", not "work on comms">
- **Waiting on:** <who — what — since YYYY-MM-DD>
- **Check-in:** <every 2 weeks — last YYYY-MM-DD>
- **Updated:** <YYYY-MM-DD>

<YYYY-MM-DD> — <one or two sentences: where it stands, what moved last, what is stuck and on whom.>

The tracking block, straight after Done when so it is read second. The labels stay exactly as
written: the projects board, the session-start line and the metrics read them. Each thing awaited is
its own line with the label repeated — a second one reads
`- **Waiting on:** Sam — the signed budget — since 2026-09-14` — and there is no such line when
nothing is awaited; `Check-in:` is there only if the project has a cadence. A next action or an
owner written as `none found …` or `not yet named` (or `none`, `n/a`, `-`) is an honest gap, and
counts as missing wherever the block is read. The dated line underneath is rewritten rather than added to — git keeps the
history. This block goes stale fastest, so it is the first thing to check when picking the project
up, and the first thing to fix when it disagrees with reality.

## Next up *(optional)*

The short ordered list of what comes after the next action. When the next action is done, the top
line here usually becomes the new one.

1. <…>

## Success criteria *(optional)*

How you will know it was worth doing, as distinct from done — a measure with its baseline and window,
or a behaviour that changes.

## People *(optional)*

One line per person: name — role — profile. The five roles are **owns** (answers for the outcome;
one person per outcome), **does** (does the work), **helps** (supports it), **ask first** (consulted
before a decision is taken) and **keep told** (hears how it went). A person can hold two, as in
"owns, does". Point at their profile in `memory/people/` rather than restating it. When two or more
people are named, the closeout ritual adds a "who needs to know" step. A one-person project keeps
only the owner's line, which is how the board and the register know whose it is.

- <name> — <owns> — `memory/people/<name>.md`

## Precedents *(optional)*

What has been tried before, and what it taught. Point at the finished project, decision entry or
reference doc rather than restating it; the rejected alternative is the most valuable line here.

- `<path>` — <what it tried, and the lesson that applies here>

## Read before acting

A numbered reading order, shortest first, saying what each file is for and which is the most current.
Where two files could both look authoritative, say plainly which one wins.

1. `<file>` — <what it holds, and when it is the right thing to read>
2. `<file>` — <…>

## Where everything lives

| What | Where |
|---|---|
| <the canonical data or artefact> | `<path>` — **canonical.** Read it there; do not copy it here |
| <derived or companion files> | `<path>` — regenerate after any change to the canonical source |

Marking which files are canonical and which are derived is the single most useful thing in a project
folder. A companion treated as authoritative is the failure this prevents.

## Working conventions

The rules that are specific to this project and would otherwise be re-derived or violated:

- <what is canonical, and what must be regenerated alongside it>
- <what needs a human's approval before it changes>
- <what is never deleted, and how superseded material is marked instead>
- <what may not be claimed in public about this work, and where the provenance lives>

## Parked *(optional)*

Ideas deliberately set aside, so they stop being re-proposed and are easy to revive. Looked at in
the regular review.

- <YYYY-MM-DD> — <the idea, and why it waits>

## Open questions

The things not yet decided, so a session does not decide them by accident.
