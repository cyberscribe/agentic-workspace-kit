# /workspace:quick-start

*The first-time interview that makes a workspace the team's own, then a check that the kit is reachable
and running. Source: `plugins/workspace/commands/quick-start.md`.*

## What it does

It runs the state check first (`kit/plugins/workspace/bin/state.sh`, read-only, no git lock left) and
decides its mode from `mode=` rather than asking:

| Mode | When | What it offers |
|---|---|---|
| `fresh` | `CLAUDE.md` still has angle-bracketed stand-ins | The team part, then the personal part |
| `joining` | The team part is done; this person has no profile | The personal part only |
| `existing-system` | Signs of a system that was here first | A mapping of that system onto the kit, changing nothing without a yes |
| `nothing-left` | Everything is filled in | The last section on its own |

- **The team part** fills `CLAUDE.md` §1–§3 below its import line (what the team does, the standards
  owner, output preferences, working conventions, how the agent should show up, approval gates), and
  optionally the glossary, `.claude/projects.md` settings, the first projects, the team roster, a
  verification standard, the catalogue and the pilot build list.
- **The personal part** writes the person's profile into the people directory, with their own
  in-flight limit if they want one, and drafts lines for their personal agent settings for them to add.
- **Fitting an existing system** shows a table of what exists against the kit's terms, records the
  team's names in `.claude/projects.md` and `.claude/closeout.md`, offers the `@kit/CLAUDE.kit.md`
  import line for their own `CLAUDE.md`, walks `/projects:adopt` proposals, and proposes folding
  rituals that do the same job into one.
- **Reachable and running** ends every mode: the commands on each surface the person uses (the plugins
  in Claude Code; `kit/setup.sh skills` for Cowork), the session-start line in one project folder, a
  metrics baseline with `bash kit/pilot/measure.sh --backfill 8` once there is a commit, and the first
  real piece of work.

## When to reach for it

Once, after `kit/setup.sh` finishes, and then once per person on their first session. It is offered
when `CLAUDE.md` still has stand-ins, or when a person working here has no profile yet.

## Common questions

**It says a setting is `kit/setup.sh`'s to set.** Hooks, the kit import and the origin are wired by
setup, run from a terminal. The quick-start names the command and leaves running it to the person.

**Can it edit `kit/CLAUDE.kit.md`?** No; that file is the kit's and changes by pull request to the kit.
The team's answers go into `CLAUDE.md` below the import line.

**Why are my Cowork skills missing?** Cowork reads skills when a session starts, so skills the bridge
writes now appear in the next session. `kit/setup.sh skills --check` says whether a refresh is due.

**Does it run in Cowork?** Yes, as the `kit-workspace-quick-start` skill that `kit/setup.sh skills`
writes. In Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- The state check's `mode` reads `joining` for the next person, then `nothing-left` once they finish.
- A session opened in a project folder shows the projects session-start line.
- Every change was shown before it was made, and the commit is left to the person.
