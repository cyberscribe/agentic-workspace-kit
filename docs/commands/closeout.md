# /closeout

*The end-of-session pass: what this session learned goes into the workspace's durable docs, and the
project's tracking is brought up to date, reported apart. Source: `plugins/closeout/commands/closeout.md`.*

## What it does

- Reads the conventions first: `.claude/closeout.md` (the team's destinations, tiers and house rules;
  a `## Promotion tiers` section there replaces the kit's table), then the person's own
  `~/.claude/closeout.md`, then `.claude/projects.md`. The project's conventions win where they differ.
- Classifies each learning by tier (working standards, general reference, project reference, templates
  and agent roles) and by scope (shared or individual), defaulting to the cheapest tier that works.
  Promotion into the always-loaded tier is zero-sum: it names what the line displaces and asks first.
- Checks each claim against the files as they are now, and against the team's verification standard
  where there is one. A claim that cannot be checked is recorded as unverified, or left out.
- Promotes with surgical edits. The mechanical ones are made; anything that changes what loads every
  session comes back as a proposal. Nothing is deleted.
- Then, separately, reconciles tracking in the project the session worked in: ticks Done when items the
  session met, updates the Current state block, and suggests `/projects:close` when every box is ticked.
- With two or more people known for the project, suggests who needs to know, as a short table.
  Nothing is sent.
- Ends with a report and the commit commands, submodules first (inside `kit/` or an own-repo project,
  then the pointer in the workspace). It never commits.

Anything typed after the command is what the person most wants kept, and it starts there.

## When to reach for it

At the end of a working session that produced a decision, a constraint, a correction, or a change to
how the work is done. On a surface with no end-of-session hook, such as a desktop assistant, this pass
is the whole ritual; in Claude Code, the [closeout-capture](../hooks/closeout-capture.md) hook is the
backstop for a session that ends without it.

## Common questions

**Can it edit `kit/CLAUDE.kit.md`?** No. That file is the kit's: a learning about the kit is drafted
in the report, and a change there goes to the kit by pull request (see `CONTRIBUTING.md`). Promotions
into working standards go below the import line of `CLAUDE.md`.

**Where does general reference go when the skills bridge is in use?** To `skills/`. Where
`.claude/skills/.kit-generated` exists, `.claude/skills/` is the bridge's generated copy and is
rewritten on its next run.

**Why did no draft appear after I ran it?** In Claude Code it drops a per-session sentinel in the
closeout drafts folder, so the end-of-session hook writes no second, redundant draft for that session.
A sentinel older than six hours is cleared rather than honoured.

**Does it run in Cowork?** Yes, as the `kit-closeout` skill that `kit/setup.sh skills` writes. In
Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- The report lists what was promoted and at which tier, what is proposed, and tracking on its own.
- Every file it touched is named, and the commit commands name paths exactly, with no broad `git add`.
- A session that ends after it leaves no new draft under `~/.claude/closeout-drafts/`.
