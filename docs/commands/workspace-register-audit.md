# /workspace:register-audit

*The monthly read of the guidance an agent loads, for drift toward urgency, threat and emphasis,
graded by how strongly each line primes a session. Source:
`plugins/workspace/commands/register-audit.md`.*

## What it does

- Reads the rule first: `kit/docs/documentation-register.md`, with its severity table and its
  **Suppressions here** list. A workspace adds its own suppressions in a `## Suppressions here` section
  of its own `docs/documentation-register.md`, read after the kit's.
- Scans the Markdown an agent reads as guidance: the always-loaded files, each project's entry point
  and `decisions.md`, the register, `memory/`, `logs/`, `docs/`, the `.claude/` conventions files, and
  the team's own skills, commands and agent definitions. `kit/` is left out: it is audited in the kit's
  repository, and the imported `kit/CLAUDE.kit.md` is named as such in the report.
- Matches line by line, skipping ranges between the audit's `ignore-start` and `ignore-end` markers
  (comments that name the audit, used where the words are quoted as examples):

| Severity | What it matches |
|---|---|
| HIGH | The phrase families in the severity table, in any case |
| MED | The table's words written in capitals, as whole words |
| LOW | Runs of exclamation marks, and a word in capitals set in bold |
| Contact detail | An email address or phone number in the team roster, `team/people.md` |

- Writes `audits/register-audit-YYYY-MM-DD.md`: counts by severity and by suppression layer, the
  change since the last report, findings by file with a rewrite for each, and a `## Judgement pass`
  section.
- Works the findings with the person: legitimate uses set aside with a reason (and the narrowest
  suppression proposed if they recur), mechanical rewrites as one list on one yes, each line of the
  always-loaded file shown on its own.

## When to reach for it

Once a month, or after a guidance file has been substantially rewritten. Typed with `report` (or
`scan`), or run with nobody to answer, it writes the report and leaves the judgement pass waiting.
Paths typed after the command are scanned as well as the usual set, for a new brief or a file about to
be added.

## Common questions

**The report says zero findings and zero suppressed.** The scan most likely did not read what it
meant to, since the register file's own tables are marked and a working scan always suppresses
something. The report says so rather than claiming a clean month.

**A finding is in a file under `kit/`.** Note it and leave the file alone: a change to the kit goes
upstream by pull request (see `CONTRIBUTING.md`).

**How is this different from hygiene?** Hygiene asks where files live; this asks how they read.

**Does it run in Cowork?** Yes, as the `kit-workspace-register-audit` skill that `kit/setup.sh skills`
writes. In Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- `audits/` gains a dated register report each month, with the trend against the last.
- The suppressed counts are above zero, showing the detector is still detecting.
- Rewrites state norms as facts about how the work is done, and nothing under `kit/` was edited.
