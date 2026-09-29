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
- **Shared beats individual.** If a teammate or another surface would need it, it goes in a committed
  file. A personal memory store is where a team learning goes to be lost.
- **Project reference lives in `projects/<slug>/`.** A cross-project decision goes in
  `logs/decisions.md`, using the filter in `templates/project-decisions.md`.
- **Who needs to know** comes from `memory/people/`: with two or more profiles there, the closeout
  ends with a short table of who should hear about what. It is a suggestion for the person closing
  out; nothing is sent, and it is not committed.
- **Leave the commit to the human.** The agent stages the files it touched, by name, and summarises
  the change; the person committing writes the message, as their check that they understand it. No
  broad staging command.
