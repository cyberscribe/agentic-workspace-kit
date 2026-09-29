# Pilot protocol

*How to run this repository as a time-boxed pilot of shared standards and documentation — across the
team, and with the team's agents — so that at the end there is something countable to say about it.*

---

## What the pilot is testing

Whether a team that keeps its working standards, reference and decisions in one shared, versioned
place — read by every person and every agent surface — ends up with more of that material in use by
more of its members, rather than held in one person's head or one person's personal memory store.

It is not testing whether the team got faster. Most teams already report that speed is solved. The
question here is control: shared language, shared verification standards, knowing who to go to, and
not re-deriving the same decision twice.

## Roles

| Role | Who | What it involves |
|---|---|---|
| **Standards owner** | __OWNER__ | Reviews pull requests that touch `AGENTS.md` or `docs/memory-layers.md`. Holds the always-loaded budget. |
| **Ritual keeper** | <name; can rotate monthly> | Runs the weekly hygiene pass and `pilot/measure.sh`, commits both outputs. |
| **Everyone** | The whole team | Runs `/closeout` at the end of working sessions; owns their row(s) in `build-list.md` and their own `memory/people/` profile. |
| **External reviewer** | <optional> | One critique pass at week 4–6: reads what exists, comments, builds nothing. |

## Timeline

| When | What happens | What it leaves behind |
|---|---|---|
| **Week 0** — 90 minutes together | Install (below). Fill §1 of `AGENTS.md`. Transfer the team's own list of what to build into `build-list.md`, one owner and one date per row. Each person drafts their profile. Run one `/closeout` together on a real session. | `AGENTS.md` §1, `build-list.md`, first profiles, first closeout, first `metrics.csv` row |
| **Weeks 1–8** | Normal work. `/closeout` at the end of sessions. Documentation changes by pull request; always-loaded changes reviewed by the standards owner. | Commits, decision entries, promoted drafts |
| **Weekly** — 15 minutes | Ritual keeper: `rituals/weekly-hygiene.md`, then `pilot/measure.sh`. Commit the report into `audits/` and the updated `metrics.csv`. | A dated trail |
| **Week 4–6** | External review pass, if there is one. Update `build-list.md` statuses honestly. | Review notes |
| **Week 8** | Final `measure.sh`. Readout: the numbers below, plus the team's own account of what changed. | The case study |

## Install

From a checkout of the kit, into this repository:

```bash
./install.sh --target <path-to-this-repo> --team "<team name>" --owner "<owner name>" --owner-handle "@<handle>" --pilot
```

Then, per person, once:

- **Claude Code**: open the repository, accept the folder trust prompt, and approve the closeout
  plugin's hooks when asked. Without that approval the hooks never run and only `/closeout` works.
  Needs `jq` on the machine.

## What gets measured

Every number is read from git history, so it can be recomputed for any past date and checked by
anyone with read access. `metrics.csv` contains counts only.

| Column | What it shows | Why it matters |
|---|---|---|
| `build_items_named`, `build_items_exist` | The team's own list, and how much of it exists | **The primary measure.** "Of the N things this team said it would build, M exist after eight weeks." |
| `doc_contributors_7d` | Distinct people who changed documentation that week | Whether this is a team practice or one enthusiast's. The most important secondary number. |
| `doc_commits_7d` | Documentation commits that week | Activity. Read alongside contributors, never alone. |
| `decisions_logged` | Entries in the decisions logs | Whether reasoning is being kept, not just outcomes |
| `people_profiles` | Files in `memory/people/` | The "who to go to" directory |
| `audit_reports` | Markdown reports in `audits/` — hygiene and register audit — not its README or a metrics CSV kept there | Whether the weekly ritual is being run — a ritual with no artefacts is a plan |
| `always_loaded_bytes` | Size of `AGENTS.md` + `CLAUDE.md` | Should stay roughly flat. Steady growth means the budget rule is not holding. |
| `projects_active` | Projects not yet done or paused | The denominator for the project columns below it. |
| `projects_blocked` | Active projects whose `State:` reads `blocked`, or that carry a `Blocked by:` line | How much of the work in flight cannot move until something outside it changes. |
| `projects_with_done_when` | Active projects with a Done when checklist | Whether the tracking is kept, not just started. A project without a finish line has no way to end. |
| `projects_done` | Projects whose Current state block reads `State: done`, or that sit in a done location the conventions name | Finish lines crossed — the practice's output, counted. |
| `blocked_over_14d` | Blocked projects whose `Blocked by:` line is dated `since` more than 14 days ago | What has been stuck long enough to need someone to act on the block itself. |
| `max_in_flight_per_person` | The most projects any one person is doing at once | Compare with the in-flight limit in `.claude/projects.md`. Above it, work is started faster than it is finished. |
| `median_days_to_done` | Median whole days from the commit that created a project's README to the one that set it done | How long finishing takes. Empty until a project finishes; a project that arrived already done is left out. |

The project columns read each project's README as the projects commands write it — the Current state
block, Done when and People — and follow `.claude/projects.md` for where projects live, the entry point,
the register, and any section the team calls by another name. They read it by the same rules as the
board and the session-start line, set out under "How the files are read" in the projects plugin's
README: an honest gap such as `none found …` or `not yet named` counts as missing, a block is dated
only by the `since` on its `Blocked by:` line, and people are counted in flight by the rule under Pace
in that file.

Two options fit the script to a repository laid out differently from a kit install:
`--out <path>` writes the CSV somewhere other than `pilot/metrics.csv` (with `--backfill` or the
daily row), and `MEASURE_ALWAYS_LOADED="CLAUDE.md"` names the files the team's agents actually load
at every session, where that is not `AGENTS.md` plus `CLAUDE.md`. A CSV written by an earlier version
with fewer columns is recomputed for the same dates the next time a row is added.

If the team already runs a before/after pulse survey, keep it alongside these. The survey measures how
it feels; these measure what exists. A case study is stronger with both, and honest about which is
which.

## What the pilot can and cannot claim

It can claim what it counted: how many named items exist, how many people contributed, whether the
rituals ran. With one team, no comparison group and eight weeks, it cannot claim that the practice
caused a change in effectiveness, and a write-up that says so will not survive a sceptical reader.

A useful honesty check at week 4: if `audit_reports` has not moved and `doc_contributors_7d` is at one,
the practice has not taken hold yet. The same goes for a month in which `projects_blocked` climbs
towards `projects_active` and `projects_done` has not moved: the system is a plan, not a practice. Say
so at the week-4 check and adjust — that is a finding, not a failure.

## Confidentiality

`metrics.csv` is safe to share outside the team: it holds dates and counts. `build-list.md`, the
profiles and everything else in this repository are the team's own and stay where the team keeps
them. A case study quotes counts and, with permission, the team's own words.
