# Closeout conventions — __TEAM__

Read by the closeout plugin (`/closeout` and its end-of-session capture hook) and by the `kit-closeout`
skill the skills bridge writes for Cowork, so every surface closes out the same way. A person's own
`~/.claude/closeout.md` is read after this file and never wins over it.

## Promotion tiers

The taxonomy is `kit/docs/memory-layers.md`. Read §2 and §3 before classifying anything: four content
types — working standards, general reference, project reference, templates — on two axes, tier and
scope, with §3 naming the destination for each in a workspace.

This section names the file rather than restating the table. A second copy of a taxonomy is how two
copies drift.

## House rules for a shared repository

- **The always-loaded file is `CLAUDE.md`.** Its first line imports `kit/CLAUDE.kit.md`, which is the
  kit's and changes by pull request to the kit; promotions into working standards go below that line.
- **The kit's standards count in the budget.** `kit/CLAUDE.kit.md`'s bytes are loaded every session
  too, and are reviewed upstream, in the kit, not in a closeout.
- **A change to the always-loaded tier is a proposal.** Write it on a branch and open a pull request
  naming what it displaces; the standards owner reviews it. Every other tier is additive and can land
  in the normal way.
- **A promotion to the always-loaded tier or general reference is offered an ablation.** The question
  is what task would go worse without the line; where there is one, a proposed ablation file in
  `pilot/ablations/` goes in the same pull request. It is offered, not required. Where nobody can name
  a task, that is evidence about the tier.
- **Shared beats individual.** If a teammate or another surface would need it, it goes in a committed
  file. A personal memory store is where a team learning goes to be lost.
- **Project reference lives in `projects/<slug>/`.** A cross-project decision goes in
  `logs/decisions.md`, using the filter in `kit/templates/project-decisions.md`.
- **Who needs to know** is set below. It is a suggestion for the person closing out; nothing is sent,
  and the table is not committed.
- **Leave the commit to the person.** List what you touched, by name (a broad staging command sweeps
  in unrelated work), and give the commands for them to run, with each message editable. Where a file
  you touched sits inside a submodule — for example the kit at `kit/`, or a project that is its own
  repository — the commands come in this order: inside the submodule, add, commit and push; then, in
  the workspace, add the submodule's path (`git add kit`) with the other files, and commit. The
  workspace then never records a commit that the submodule's remote lacks, and
  `push.recurseSubmodules=check` refuses such a push anyway.

## Who needs to know

- **Who needs to know:** auto

`auto` ends a closeout with a short table of who should hear about what, whenever two or more people
are known for the project; `ask` offers that table in one line; `off` leaves the step out. A project
README can set its own with the same line in its People section.

People come from the project's People section first, then the team roster at `team/people.md` (from
`kit/templates/team-roster.md`), then `memory/people/`. A role in the project's People section wins
over the roster's default relationship for that person; the roster adds anyone the project does not
name whose default relationship matches what changed. Someone named in neither is suggested only where
their work is affected. A roster row looks like this:

| Name | Role | Default relationship | Channel | Handle |
|---|---|---|---|---|
| Priya Shah | Measurement lead | keep told: anything touching measurement | Slack | @priya |

The roster holds handles only, never an email address or a phone number. Each row of the table offers
a `draft` (a short message in the closer's own voice), a `note` (a line for the next team meeting or
one-to-one) or `none`, picked per row; a draft is shown, never sent.
