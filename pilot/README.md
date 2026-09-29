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
| `ablations_named` | Ablation files in `pilot/ablations/` | How much of the context the team keeps has a test at all. The denominator for the two columns below it. |
| `ablations_discriminating` | Of those, the ablations whose latest result is `discriminates` | The number the readout leads with, as a share of `ablations_named`: lines shown to change what the agent does on the task written for them. |
| `ablations_no_difference` | Of those, the ablations whose latest result is `no difference (both pass)` | Lines not pulling their weight at their tier, on that task; three weeks of it makes a demotion candidate. A lean by one run and a check that fails both arms count in neither column. |

The project columns read each project's README as the projects commands write it — the Current state
block, Done when and People — and follow `.claude/projects.md` for where projects live, the entry point,
the register, and any section the team calls by another name. They read it by the same rules as the
board and the session-start line, set out under "How the files are read" in the projects plugin's
README: an honest gap such as `none found …` or `not yet named` counts as missing, a block is dated
only by the `since` on its `Blocked by:` line, and people are counted in flight by the rule under Pace
in that file.

Three options fit the script to a repository laid out differently from a kit install:
`--target <dir>` measures that repository rather than the one the command is run in, so the kit
checkout's copy can serve a repository that has none; `--out <path>` writes the CSV somewhere other
than `pilot/metrics.csv` (with `--backfill` or the daily row), relative to where the command was
typed; and `MEASURE_ALWAYS_LOADED="CLAUDE.md"` names the files the team's agents actually load at
every session, where that is not `AGENTS.md` plus `CLAUDE.md`. A CSV written by an earlier version
with fewer columns is recomputed for the same dates the next time a row is added.

## Context ablations

`ablate.sh` tests whether one line of the always-loaded or reference context changes what the
agent does on the task it was promoted for. It stays in the kit's own `pilot/` and is not copied into
a team's repository: run the kit checkout's copy with `--target` pointing here,
`<kit checkout>/pilot/ablate.sh --target <this repository>`, so every team runs the one current
version. The ablations and their results live in the target: each ablation in
`<target>/pilot/ablations/<id>.md` names the line, a realistic prompt and a Check; the runner runs the
prompt headless in a fresh worktree of HEAD with the line (`with`) and without it (`without`), grades
each run, and appends a row per run to `<target>/pilot/ablation-results.csv`, with
`pilot/ablation-report.md` beside it. A Check runs in the run's worktree with `AW_ABLATION_ARM` (the
arm it grades) and `AW_ABLATION_STREAM` (the path of the run's captured stream, for reading its tool
calls) set. `ablate.sh --help` lists the rest. Each run is a headless
`claude -p` session on the person's own subscription login, with a usage guard per run: the
ablation's `max_budget_usd`, a cap on the run's API-equivalent cost.

Three columns need reading with care. `input_tokens` is uncached input plus cache writes: with prompt
caching on, the always-loaded context lands in the cache-write figure, and that is the load being
measured; `cache_read_tokens` is separate. `cost_usd` is the run's API-equivalent cost, to six decimal
places: the CLI's `total_cost_usd`, what the tokens would cost at API prices. A run on a subscription
login is not charged it, so the report labels it "API-equivalent cost". `api_key_source` is the login
the run's init event reports; `none` means no API key, which is the subscription login. Rows written
before that column existed have thirteen fields and read as not recorded.

Runs are not meant to bill an API key. The runner refuses to start, and runs nothing, when the
environment would give Claude Code one to prefer over the login, or send it to a cloud provider's
account: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or `CLAUDE_CODE_USE_BEDROCK`, `_VERTEX` or
`_FOUNDRY` set in the environment or in the `env` block of the user, managed or committed project
settings, or an `apiKeyHelper` in any of those settings.
It stops at the first init event that reports any source other than `none`. `AW_ALLOW_API_BILLING=1`
allows both, for a team that means to pay per token. The `CLAUDE_CODE_OAUTH_TOKEN` path below is a
subscription login, not API billing.

What an arm loads: repository files come from the worktree, so ablating `CLAUDE.md`, `AGENTS.md` or
a file under `docs/` is faithful. Plugins resolve through each person's own marketplace registry,
which points at the kit checkout's working tree, so an ablation of a file inside the kit stops with
status `error` rather than run a `without` arm that changes nothing. The user-level file
(`~/.claude/CLAUDE.md`) is present in the `with` and `without` arms, as in a real session.

Two modes follow from the login. By default each arm uses the person's own Claude Code login, which
cannot follow a copied config directory, so the user-level file cannot be ablated and `file:
~user/CLAUDE.md` ablations are listed as not run. With `CLAUDE_CODE_OAUTH_TOKEN` set in the
environment (a token from `claude setup-token`), each run gets a temporary config directory holding
only `settings.json`, `CLAUDE.md`, the plugin list and the marketplace registry, and a temporary
`HOME`; both are removed on exit. User-level ablations then run against that copy. The plugin list and
registry point into the person's own plugin cache, so plugin files are still read from there; the copy
turns marketplace auto-update off and each run gets `DISABLE_AUTOUPDATER=1`, so nothing is fetched into
it. The runner passes the token through the environment to each headless run, never to a Check, and
never writes or prints it.

In either mode, `--no-session-persistence`, `CLOSEOUT_DISABLED` and two temporary state folders keep
transcripts, closeout drafts and hook state out of the config directory. Checked on the week-0 runs
(45 real runs without the token): a headless run writes the CLI's global state file `~/.claude.json`
and its rotating backups under `~/.claude/backups`, and nothing else. With the token, those land in
the run's temporary config directory and `HOME`.

`--bare` adds a third arm with every always-loaded file emptied (`MEASURE_ALWAYS_LOADED`, default
`AGENTS.md CLAUDE.md`): the whole tier off. With the token it empties the copy's user-level file too
and is recorded as `bare`; without it, it is recorded as `bare-repo` and reported as "repository tier
emptied; user-level tier present".

An ablation with a `## Judge` rubric also gets a blind comparison: run i of `with` and run i of
`without` go to `claude -p` unlabelled and in random order, with the prompt in `pilot/lib/judge.md`,
and it answers A, B or tie with one sentence. The unblinded winner goes in the `judge` column of the
`with` row, and the comparator's own tokens and API-equivalent cost go on a row of arm `judge`. The
comparator runs from an empty temporary directory with no tools, so no repository `CLAUDE.md` loads; without the
token, the person's user-level file still does. Which arm was shown as A is recorded in each pair's
`verdict.json`. `--keep` keeps each run's stream, outputs, Check output and `meta.json`, and the
verdicts, under `$TMPDIR`; the worktrees go either way. `--judge-kept DIR` judges the pairs an earlier
`--keep` run left in DIR, without running the arms again, and writes each verdict on the row of that
run's own date; a pair already judged is left alone.

The report has one row per ablation, from that ablation's own latest date, and its flag column reads
the whole history. The gap is `with` passes minus `without` passes, in runs, and the first rule that
applies wins. `stale`: the line no longer matches. `error`: a run failed; for a line inside a plugin
file the report says why. `without preferred`: the Check failed on most `with` runs and passed on most
`without` runs, so the line may hurt. `check fails both arms`: it failed on most `with` runs and
`without` did no better, whatever the gap; that says nothing about the line, so the report asks for the
check to be revised, with no rerun at a larger k. `discriminates`: it passed on most `with` runs with a
gap of 2 or more runs, at any k (at k=3: 3/3 or 2/3 against 0/3, or 3/3 against 1/3). `leans with,
rerun at k=5`: it passed on most `with` runs with a gap of exactly 1 (at k=3: 3/3 against 2/3, or 2/3
against 1/3); not discriminating and not a step toward demotion, and at k=1 the most a single pair can
show. `no difference (both pass)`: it passed on most runs of both arms with no gap or with `without`
ahead (at k=3: 2/3 against 3/3), and no comparator preferred `with`. `check blind, judge prefers with`: the same, but the comparator preferred `with`, so
the Check cannot see what the line does and needs revising. `inconclusive`: anything else. With no
Check, the comparator's pairs stand in for runs by the same gap, and `no difference (judge ties)` means
it called most pairs a tie. `regressed`: `with` passed on most runs at the previous date and does not
now. `demotion candidate`: `no difference (both pass)`, `no difference (judge ties)` or `without
preferred` in each of three consecutive ISO weeks, counting the latest date in each week once; a
failing or blind check, a lean and an inconclusive result never count. The flag proposes; the person
decides. `--report` prints the table without running anything, and `--report >
pilot/ablation-report.md` rewrites the report from the CSV, as after a change to the rules.

The weekly hygiene pass offers the run after `measure.sh`, with the number of runs and the
API-equivalent cost stated first, and the person decides; `measure.sh` then runs again so the week's row counts the new results.
The three `ablations_` columns come from `ablate.sh --outcomes`, the same rule the report's flags use,
so the two never disagree. A past row reads the ablation files and results as committed at that
revision, so backfill works; today's row reads them from the working tree, since the results are
committed with it. Without the runner (no `ablate.sh` beside `measure.sh` and no kit checkout named in
`.claude/plugins/VENDORED`), `ablations_named` is still counted and the other two are left empty.

If the team already runs a before/after pulse survey, keep it alongside these. The survey measures how
it feels; these measure what exists. A case study is stronger with both, and honest about which is
which.

## What the pilot can and cannot claim

It can claim what it counted: how many named items exist, how many people contributed, whether the
rituals ran. With one team, no comparison group and eight weeks, it cannot claim that the practice
caused a change in effectiveness, and a write-up that says so will not survive a sceptical reader.
With ablations it can also say, line by line and at a stated n, which lines of its context changed
what the agent did on the task written for them. An ablation tests what its author thought the line
was for, the same limit a unit test has, and the demotion rule only ever proposes.

A useful honesty check at week 4: if `audit_reports` has not moved and `doc_contributors_7d` is at one,
the practice has not taken hold yet. The same goes for a month in which `projects_blocked` climbs
towards `projects_active` and `projects_done` has not moved: the system is a plan, not a practice. Say
so at the week-4 check and adjust — that is a finding, not a failure.

## Confidentiality

`metrics.csv` is safe to share outside the team: it holds dates and counts. `build-list.md`, the
profiles and everything else in this repository are the team's own and stay where the team keeps
them. A case study quotes counts and, with permission, the team's own words.
