# /ongoing:new

*Starts an ongoing area — work with no finish line, kept up rather than finished — with a short
interview, then writes its README and register row. Source: `plugins/ongoing/commands/new.md`.*

## What it does

- Reads `.claude/projects.md` first: the **Areas**, **Area register** and **Area template** lines, the
  people directory and the versioning default. Without them, areas go in `ongoing/<slug>/`, registered
  in `ongoing/INDEX.md` (Active / Dormant / Archived), from `kit/templates/area-readme.md`.
- Offers two depths. The quick path asks the name, the **desired state** (what you want to be true here,
  in one sentence), two to five **standards to keep** that someone else could check, the check-in
  cadence, how it is versioned and whether it is sensitive, and the owner.
- The full path adds people and their five roles, recurring routines that keep the standards met, child
  projects, precedents, constraints, open questions and resources.
- Pushes back on vague standards, and writes `- not yet named` rather than inventing them.
- Shows the README, writes it on a yes with `State: active` (or `dormant`), adds the register row, and
  runs the versioning steps, each on its own yes.

## When to reach for it

For a practice, a responsibility or a collection: a language you are learning, a craft, a garden, a
team's on-call. `/projects:new` hands over to it when its interview finds no finish line. For work that
ends, use `/projects:new`.

## Common questions

**How is an area different from a project?** A project is finished when its Done when boxes are ticked.
An area is healthy while its standards are met, and is never done: it is active, dormant or archived.

**What if part of it has an end?** That part is a project. Start it with `/projects:new`; its What this
is names the area, and the area's Projects section links it. A small one can sit inline under Projects.

**Do areas count against the in-flight limit?** No. They are not in flight; they are kept up.

**Does it run in Cowork?** Yes, as the `kit-ongoing-new` skill that `kit/setup.sh skills` writes.

## It's working if

- `ongoing/<slug>/README.md` has a Desired state, Standards to keep and a Current state block.
- `ongoing/INDEX.md` lists it under Active.
- `/projects:board` shows it in its Ongoing areas section with its cadence.
