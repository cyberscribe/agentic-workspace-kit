# Closeout conventions — __TEAM__

Read by the closeout plugin (`/closeout` and its end-of-session capture hook) and by the `closeout`
skill the installer generates for desktop assistants, so every surface closes out the same way. A
person's own `~/.claude/closeout.md` is read after this file and never wins over it.

## Promotion tiers

The taxonomy is `docs/memory-layers.md`. Read §2 and §3 before classifying anything: four content
types — working standards, general reference, project reference, templates — on two axes, tier and
scope, with §3 naming the destination for each in this repository.

This section names the file rather than restating the table. A second copy of a taxonomy is how two
copies drift.

## House rules for a shared repository

- **The always-loaded file is `AGENTS.md`.** `CLAUDE.md` is a one-line import of it; promotions into
  working standards go to `AGENTS.md`.
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
  `logs/decisions.md`, using the filter in `templates/project-decisions.md`.
- **Who needs to know** is set below. It is a suggestion for the person closing out; nothing is sent,
  and the table is not committed.
- **Leave the commit to the human.** The agent stages the files it touched, by name, and summarises
  the change; the person committing writes the message, as their check that they understand it. No
  broad staging command.

## Who needs to know

- **Who needs to know:** auto

`auto` ends a closeout with a short table of who should hear about what, whenever two or more people
are known for the project; `ask` offers that table in one line; `off` leaves the step out. A project
README can set its own with the same line in its People section.

People come from the project's People section first, then the team roster at `team/people.md` (from
`templates/team-roster.md`), then `memory/people/`. A role in the project's People section wins over
the roster's default relationship for that person; the roster adds anyone the project does not name
whose default relationship matches what changed. Someone named in neither is suggested only where
their work is affected. A roster row looks like this:

| Name | Role | Default relationship | Channel | Handle |
|---|---|---|---|---|
| Priya Shah | Measurement lead | keep told: anything touching measurement | Slack | @priya |

The roster holds handles only, never an email address or a phone number. Each row of the table offers
a `draft` (a short message in the closer's own voice), a `note` (a line for the next team meeting or
one-to-one) or `none`, picked per row; a draft is shown, never sent.
