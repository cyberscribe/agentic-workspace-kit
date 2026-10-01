# /workspace:hygiene

*The weekly pass over where context lives: a scan against the workspace's own conventions, a dated
report in `audits/`, then a judgement pass with the person. Source:
`plugins/workspace/commands/hygiene.md`.*

## What it does

It follows the ritual in `kit/rituals/weekly-hygiene.md`, which wins where the two differ, and reads the
workspace's conventions first: `.claude/projects.md`, `docs/workspace-map.md` and
`kit/docs/memory-layers.md`. Where the repository already runs a hygiene scan of its own, that scan is
Stage 1, and the command fills any check it lacks.

**Stage 1, the scan**, read-only. Every check is recorded, clean or not:

| Check | What it reads |
|---|---|
| Always-loaded budget | Bytes of `CLAUDE.md` and what it imports, as two lines (the kit's, the workspace's) and a total, with the change since the last report |
| Submodules | `state.sh --quick`: a table of every submodule, then hooks, the kit import, the origin, orphan gitlinks, unreachable resources, sensitive and tracked, versioning mismatches |
| Strays, registers, promised files | The root and `projects/` against the workspace map; folders against register rows; paths the canonical-fact table names that are not there yet |
| Promotion candidates, staleness, pending work | Project decisions marked *Generalises as*; guidance whose "Last updated" line is over 120 days old; unconfirmed adopt proposals |
| Drafts sweep | Every closeout draft under `~/.claude/closeout-drafts/` for this workspace and its projects, oldest first, each with a proposed move |
| Version control, metrics, ablations | Modified and untracked counts; `skills-bridge.sh --check`; `bash kit/pilot/measure.sh`; the ablation runner's flags, and a run offered with its cost |

**The report** goes to `audits/hygiene-YYYY-MM-DD.md` (or the name earlier reports use): the budget
lines first, the submodules table, one line per check, the findings with the move for each, and a
`## Judgement pass` section.

**Stage 2, the judgement pass**, works the report with the person: uncontested moves as one list on one
yes, anything touching what loads every session one by one, drafts one folder at a time.

## When to reach for it

Once a week, or when files have piled up outside the places the workspace map names. Typed as
`/workspace:hygiene report` (or `scan`), or run with nobody to answer, as in a scheduled task, it does
Stage 1 and leaves the judgement pass waiting in the report.

## Common questions

**Does it delete anything?** No. Moves are `git mv` (or `mv`), superseded material is marked with a
pointer, and clearing drafts is given as commands for the person to run.

**The bridge check says it is out of date.** Run `kit/setup.sh skills` from a terminal; an agent's
sandbox may not write `.claude/skills/`.

**The kit's budget line grew.** That arrived with a kit update, not the team's drift: name the update,
and take any concern to the kit as a pull request.

**Does it run in Cowork?** Yes, as the `kit-workspace-hygiene` skill that `kit/setup.sh skills`
writes. In Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- `audits/` gains one dated report per week, each comparing its budget lines with the last.
- A clean week still has the budget lines and one line per check, and says there is nothing to do.
- A check that could not run says `not run` and why, rather than reading as clean.
