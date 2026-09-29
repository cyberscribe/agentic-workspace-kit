# Changelog

Versions of the workspace context kit. Newest first. Entries are corrected by appending, not by
rewriting — the record of what a version claimed is part of what the version is.

---

## v2.2.0 — 2026-09-29

**Context ablations test whether a line of guidance changes what the agent does. A state check
reports where a repository stands against the kit. The quick-start and `/closeout` are shorter, and
the closeout's "who needs to know" step has a setting and a team roster.**

**Ablations.** `pilot/ablate.sh` runs the task a line was promoted for twice over, with the line
(`with`) and without it (`without`), each run headless in its own git worktree of the target's HEAD,
and grades each run with the ablation's Check. An ablation is one file in `pilot/ablations/`: the
line, a realistic prompt, and a Check or a Judge. `--target DIR` names the repository; results go to
its `pilot/ablation-results.csv` and `pilot/ablation-report.md`, with n and date on every figure. A
blind comparator (`pilot/lib/judge.md`) picks between paired runs when there is a Judge, and
`--judge-kept` judges runs kept by an earlier `--keep`. `--bare` adds an arm with every always-loaded
file emptied. `--report` prints the latest flags without running anything. The flags include
`discriminates` (the `with` arm passes on a majority of runs and by at least 2 more runs than
`without`, at any k), `leans with, rerun at k=5` (a gap of 1), `no difference (both pass)`, `check
fails both arms` (the check needs revision, not the line), `without preferred` (the line may hurt),
`check blind, judge prefers with` (the Check cannot see what the comparator did), `no difference
(judge ties)` for an ablation graded by the comparator alone, `inconclusive`, `regressed`, `stale`,
`error` and `timeout`. Three consecutive ISO weeks of `no difference (both pass)`, `no difference
(judge ties)` or `without preferred` make a line a demotion candidate; a failing or blind check, a
lean and an inconclusive result never do. `pilot/lib/strip-lines.py` removes whole lines only. In
the target the runner writes only its two result files, removes its temporary folders on exit, and never commits. Without a login
token the CLI itself still updates its global state file `~/.claude.json` and its backups; with the
token those land in the run's temporary config.

**Cost and billing.** The `cost_usd` column is an API-equivalent cost: what the run's tokens would
cost at API prices. Runs on a subscription login are not charged it, and `--max-budget-usd` caps it
per run as a usage guard. Each run's API key source is recorded in a new `api_key_source` column
(older result files still read). The runner refuses to start when the environment or settings would
use an API key or a cloud account, and stops at the first run that reports one, unless
`AW_ALLOW_API_BILLING=1` is set. With `CLAUDE_CODE_OAUTH_TOKEN` set, each run gets a temporary copy
of the minimum config and a temporary HOME, which allows ablations of the user-level file and a bare
arm that empties it too; without the token the bare arm is recorded as `bare-repo`.

**workspace plugin, 1.2.0.** `bin/state.sh` is the state check: read-only, one `key=value` per line
(or `--json`), ending in `mode=` — `fresh`, `joining`, `existing-system` or `nothing-left`. It runs
under bash 3.2 and reads git only with `--no-optional-locks`. The quick-start runs it in place of its
own discovery and branches on `mode=`, with a one-line fallback where there is no shell, and offers a
team roster in the team interview; it is shorter by 15 lines. `/workspace:hygiene` offers the week's
ablation run after the metrics run, with the number of runs and their API-equivalent cost stated
first, and lists demotion candidates and checks needing revision under pending work.
`/workspace:register-audit` reports an email address or phone number in the team roster.

**closeout plugin, 1.3.0.** `/closeout` is lighter, 195 lines from 213, following the weight review.
Promotion to the top two tiers offers an ablation: what task would go worse without the line? It is
an offer, not a requirement, and a line nobody can answer that for usually belongs in a cheaper tier.
A `Who needs to know: auto | ask | off` line in `.claude/closeout.md` (installed as `auto`) sets the step (a project README
can override it), and a team roster, `templates/team-roster.md` copied to `team/people.md`, seeds it
with each person's default relationship and channel, by handle only. The hooks count the roster,
honour the setting, keep any email address or phone number in the roster out of every prompt, and
name the row instead. Each row of the table offers a draft, a note or nothing; nothing is sent.

**projects plugin, 2.0.1.** The session-start hook stays silent and records nothing in a headless
run (`AW_HEADLESS_RUN=1`), which is how ablation arms run. `/projects:new` offers to seed People from
the team roster.

**Metrics.** `pilot/measure.sh` takes `--target` and adds three columns: `ablations_named`,
`ablations_discriminating` and `ablations_no_difference`, read week by week from the committed
ablation files and results, so `--backfill` recomputes them.

**Setup.** `setup.sh` and `lib/wizard.sh` are built and tested unattended (section 11); how a team
installs is left to 3.0. The installer also places `templates/team-roster.md`.

**Docs.** `docs/memory-layers.md` names the ablation as the test of a tier. The closeout ritual,
`rituals/weekly-hygiene.md`, the conventions and `DESIGN.md` carry the ablation offer, the setting
and the roster.

**Tests.** Section 3 is a validation gate: `claude plugin validate --strict` on the root marketplace
and every plugin manifest and hooks file, and the marketplaces must list exactly the plugins in
`plugins/`. Section 10 tests the ablation runner end to end against a stub `claude`, the flags by
gap, the demotion rule, the billing guard and the token switch. Section 11 tests the state check in
one scratch repository per mode, and the setup wizard run unattended. Headless and unattended runs
share one family of environment flags, listed in `tests/README.md`.

---

## v2.1.0 — 2026-09-29

**Removed the capture, review and personal-list commands and the next-action and waiting-on fields.
A project's README now carries a Current state block, and nine commands across three plugins keep
it true.**

**Removed.** `/projects:capture`, `/projects:review` and `/projects:mine`, with the team file of
unsorted items the first of them wrote to and the installer placed. From the project README: the
Now block's next-action and waiting-on fields, the Next up and Parked sections, and the three
states that went with them. From the quick-start's close: the steps that fed the board into a
person's own list and scheduled the removed review. From the conventions: `Review day`, which only
the removed review read. From the plugin config: `CAPTURES_FILE`.

**The Current state block** replaces Now in `templates/project-readme.md`: `State:` (ready · doing ·
blocked · paused · done), an optional one-line `Blocked by:` saying what and since which date, an
optional `Check-in:`, `Updated:`, and one dated line, rewritten rather than appended. **Planned**
replaces Next up: an optional ordered list of steps, a plan rather than a queue. Labels are bold in
the template; every reader accepts them bold or plain.

**projects plugin, 2.0.0.** Five commands — `new`, `adopt`, `board`, `close`, `pickup` — read and
write the Current state block. `/projects:adopt` proposes it under the same draft marker; a README
with the older Now block is read as present in the old format, reported, and offered the conversion
as a diff in interactive mode, and left alone in draft mode. The board's flags are no owner, no Done
when, a stale `Updated:`, blocked for more than 14 days, over the in-flight limit, register
mismatch, unconfirmed adopt proposals, and ready to close. Staleness is measured against a new
`Staleness:` setting in `.claude/projects.md`; the earlier label for it is still read. The
session-start line gives the outcome, done-when progress, and `State:` with anything blocking it and
the owner; outside a project folder, its once-a-day line names only projects blocked for more than
14 days.

**workspace plugin, 1.1.0.** The quick-start ends on "Reachable and running": surface parity, which
now checks that each generated skill is a real folder (not a link) in the folder the desktop
assistant actually loads from and gives the step that brings a missing one across; the session-start
check; the metrics baseline; and one real piece of work in one real project. The close names the
first thing to do. The staleness setting replaces the review day. `/workspace:hygiene` gains an eighth
check, a sweep of closeout drafts in this repository's drafts folder and each project folder's,
oldest first with age and size, proposing promote, clear or leave for each and deleting nothing;
"Waiting work" becomes "Pending work", covering unconfirmed adopt proposals.

**closeout plugin, 1.2.1.** `/closeout`, the plugin README, `docs/DESIGN.md` and
`rituals/closeout.md` update the Current state block: Done when ticked, `State:` changed only when
the session plainly moved it, `Blocked by:` set with its date and removed once cleared, `Updated:`
set, the dated line written. `paused` and `done` are proposed only; marking a project done stays
with `/projects:close`. A README still carrying the older Now block is left as it is and pointed at
`/projects:adopt`. Who needs to know is triggered by ownership changing or the project becoming
blocked. One line in the review hook changes: a draft's Who needs to know is presented as the
who / what / why table the command describes.

**Metrics.** `projects_blocked` and `blocked_over_14d` replace `projects_with_next_action` and
`waiting_over_14d`, and `--backfill` recomputes them. A project counts as blocked when its `State:`
reads blocked or it has a `Blocked by:` line; only the `since` date dates the block. Backfill reads
history as it was: a README from before this version has no readable `State:` and counts as active.

**Templates, team and installer.** The conventions, the team overlay, `docs/memory-layers.md`,
`pilot/` and `install.sh` use the new block and states; the installer no longer places the removed
file.

**Tests.** The word-list check reads its list from `$AW_BANNED_WORDS_FILE` (default
`~/.config/agentic-workspace-kit/banned-words.txt`), one extended-regex alternative per line, and
skips with one line naming the path when the file is absent; the list is kept outside the
repository. The history check exempts one earlier commit by its full hash, and `AW_SKIP_HISTORY` is
gone. New checks cover the template's Current state block, the `Staleness:` setting, the
session-start line's new output and the drafts sweep; the command check counts nine.

**Upgrading from 2.0.** The installer only adds files, so a re-run leaves the removed commands'
generated skills, Gemini wrappers and vendored command files in place. It now lists each one under
"Worth knowing" as a file to delete; the team deletes them. The file of unsorted items 2.0 placed at
the repository root is read by nothing now and can go too.

**This file.** Entries below are reworded where they used terms this version removed from the kit;
the original wording is in git history. Everything else in them stands as written.

---

## v2.0.0 — 2026-09-29

**A work system on top of the context system: every project carries its own finish line and
current status, twelve commands across three plugins keep them true, and the same commands reach assistants
that load skills rather than plugins.**

**The tracking axis.** `templates/project-readme.md` takes its final order: What this is, Desired
outcome, **Done when** (a checklist), a **Now** block (replaced in 2.1.0 by the Current state block), and optional
Success criteria, People and Precedents, with two further optional sections removed in 2.1.0. People uses five roles: owns, does, helps, ask first, keep
told. The register gains State and Owner columns; the person profile
gains an optional in-flight limit; `templates/verification-standard.md` (what counts as checked, per
kind of work) and `templates/catalogue.md` (what the team has built and would reuse) are new. The
taxonomy names tracking's three homes. README §1.3 and §2.3 describe the axis, and a new
"Tracking, day to day" section maps each moment to its command.

**projects plugin, 1.1.0 (new).** `/projects:new` and `/projects:adopt` set the outcome and finish
line — adopt adds only what an existing project lacks, as small insertions, with a
`draft` mode that marks every proposal for later confirmation. `/projects:board` shows every
project with one-line flags; `/projects:close` ticks each Done-when box against evidence, keeps a
short retrospective and moves the register row; `/projects:pickup` briefs whoever takes a project
over. Three further commands shipped in this version and were removed in 2.1.0. A session-start hook
gives the folder's project in three lines, and elsewhere at most one line a day.
`.claude/projects.md` holds a team's own layout, section names, in-flight limit and staleness
setting, mirroring `.claude/closeout.md`; one reading contract (how labels, gaps, headings and
owners are read) is written once in the plugin README and followed by every command and script.
Versioned 1.1.0 because 1.0.0 was installed in test repositories while the plugin had one command;
neither version was published before this one.

**workspace plugin, 1.0.0 (new).** `/workspace:quick-start` moves here from `team/` and gains three
modes — fresh, joining, and existing system, where the kit adopts a system that was there first
through a confirmed mapping rather than installing over it — and a closing pass, replaced in 2.1.0 by
"Reachable and running". `/workspace:hygiene` and
`/workspace:register-audit` run the two periodic rituals.

**closeout plugin, 1.1.1 → 1.2.0.** 1.1.1, published on its own: drafts are retained from the
day they are first surfaced (`.seen` markers) rather than from creation; the review hook exits inside
the capture child; the capture child runs from the draft directory; `/opt/homebrew/bin/claude` is
probed; the `/closeout` sentinel is keyed off the project root. 1.1.2 was prepared but never released
on its own, and its changes ship inside 1.2.0: an absolute draft directory, a stale `.seen` marker
cleared when a resumed session is captured again, and a more careful account of what the
capture child's `acceptEdits` mode approves. 1.2.0:
`/closeout` rewritten in the kit's house style with every 1.1.x rule kept; verify points at the
verification standard; a new tracking step brings the project's Now block up to date and suggests
`/projects:close` when every box is ticked; who needs to know reads People roles; a personal
conventions file (`~/.claude/closeout.md`, or `CLOSEOUT_USER_CONVENTIONS`) sits between the project's
conventions and the plugin defaults; the sentinel is written only where a capture hook runs; the
prompts both hooks hand the agent are written without capitals for emphasis.
`rituals/closeout.md` carries the same changes in tool-neutral words.

**Skills.** `install.sh --skills-dir <folder>` writes one thin skill per command — `closeout`,
`projects-board`, `workspace-quick-start` and the rest — for claude.ai and other assistants that load
skills. Each points at its command file, carries the procedure beside it for a surface that is
uploaded without the repository, and says in its description when to offer it unprompted, from a new
`offer-unprompted:` line in each command's front matter. `--skills-only` writes just the skills into
a repository that already has the kit.

**Installer.** Defaults to Claude Code only (`--surfaces claude`); other surfaces are generated from
the same command files by one loop, and the hand-written wrapper in `team/` is retired. Places
`.claude/projects.md` and the two new templates, and vendors all three plugins, with
`VENDORED` naming each version, the kit commit and checkout, and "+ uncommitted changes" when the kit
tree was dirty. A repository that keeps its own `CLAUDE.md` is detected before anything is placed:
the Next message and `.claude/closeout.md` then work with that file rather than asking for it to be
replaced. Rendered files are 0644 and `measure.sh` 0755. `$schema` is gone from the marketplace
files.

**Metrics.** `pilot/measure.sh` gains seven columns after the established ten (active projects, with
a Done when, done, most in flight per person, median days to done, and two replaced in 2.1.0), all recomputed by `--backfill`; `--out` and `MEASURE_ALWAYS_LOADED`; with no commits it
says so and writes nothing, and backfill skips weeks before the first commit.

**Tests (new).** `bash tests/run.sh`, plain bash with git, jq and python3: installs run twice and
interactively, every JSON parses, versions and marketplaces agree, the closeout hooks (team
detection, capture prompt, retention, the personal layer), the session-start line, `measure.sh` over
a dated fixture history, the twelve commands vendored and as skills from one source each, and three
rules over the whole kit — a word-list check, no AI-vendor attribution in files or history,
no capitals-for-emphasis in prompts, templates and rituals.

**The commit stays with the person.** The agent stages what it touched, by name, and summarises the
change; the person committing writes the message, as their check that they understand it. Stated in
`rituals/closeout.md`, `/closeout`, the team closeout conventions and the quick-start's close.

**What the walkthrough changed.** Before release the kit was run end to end as an agent against two
scratch repositories: a fresh install for a three-person team (quick-start, both kinds of
`/projects:new`, board, closeout, close, and the commands removed in 2.1.0), and the quick-start in existing-system mode
against a one-person system with its own always-loaded file, register, decisions log and skills.
Twenty-six findings, all fixed, two in part. The quick-start's modes now cover every state (fresh no
longer needs an empty register); it names the stand-in paragraph to replace or delete, waits for a
project before checking the session-start line, takes the metrics baseline only after the first
commit, reads the team's settings instead of asking each joiner, runs adopt in the same sitting
after the mapping, lists leftover `.kit-incoming` files as commands the person runs, and spares a
one-person team the pull-request advice. The conventions gain an Entry point line (the conventions'
file, else `README.md`, else the folder's `CLAUDE.md`) that every command, the hook and the metrics
now share, a Default owner line, and one profile filename rule. `/projects:close` asks what becomes
of unfinished sections; `/projects:new` puts a target date in the Desired outcome;
`/closeout` holds a Done-when tick to the verification standard; the board's stale flag uses the team's
setting. The session-start line reports a done project as done and names a missing section rather
than judging the file. The installer's Next message no longer contradicts existing-system mode.
`measure.sh` counts decision headings with or without brackets around the date.

---

## v1.3 — 2026-09-28

**The taxonomy, drawn.** `docs/images/context-taxonomy.svg` — the four content types held shared and
individual on the human side, tracking on its own axis, and the session loop loaded automatically and
promoted from by a human. Shown in the README (§1.2) and `docs/memory-layers.md`, and installed with
them.

**Closeout: who needs to know.** An optional step, on only when a project names two or more people
(profiles in `memory/people/`, a People section in the project README, a Team section in the closeout
conventions). It names who should hear about what, why them, and where the learning is recorded — and
sends nothing, because a message to a colleague goes out in a person's own voice. "Everybody" is
treated as a sign the item may be a working standard. Added to `rituals/closeout.md`, the plugin's
`/closeout` and both hooks (plugin 1.1.0), `templates/project-readme.md` (a People section) and the
team conventions.

## v1.2 — 2026-09-28

Makes the kit deployable to a team in one command, for running as a time-boxed pilot.

**`install.sh` (new).** Lays the kit into a team's shared repository with `AGENTS.md` as the single
always-loaded file, a `CLAUDE.md` import shim and a Gemini CLI context setting, so every person and
every agent surface reads one file. Wires the closeout plugin — vendored by default, pinned, and
pointed at `docs/memory-layers.md` through `.claude/closeout.md` so the repository carries one
taxonomy rather than two. Never overwrites; differing files arrive as `.kit-incoming`.

**`team/` (new).** The installer's overlay: §1 of the manifest rewritten for a team with a standards
owner and a rule arbitrating the team layer against each person's own; §3 of `memory-layers.md`
pre-filled for Claude Code and Gemini CLI; CODEOWNERS and a pull request template routing the
always-loaded tier through review.

**`pilot/` (new).** A protocol, the team's own build list as the primary measure, and `measure.sh`,
which recomputes every other number from git history — so a baseline can be backfilled and any figure
checked. Counts only; nothing that identifies content or people leaves the script.

**One repository.** The closeout plugin moves in from its own repository to `plugins/closeout/`,
with this repository's root `.claude-plugin/marketplace.json` publishing it under the same marketplace
name, so `closeout@closeout-marketplace` keeps working. The kit and the plugin are one practice and now
version together; the installer vendors the plugin from the local copy with no network needed.

**Open licence.** Code is MIT; the writing is CC BY 4.0. See `LICENSE`.

**`templates/person-profile.md` (new).** The "who to go to for what" directory, one file per person.

## v1.1 — 2026-09-04

Revised after auditing the workspace this kit was extracted from against the kit's own claims. Every
change below is something the audit demonstrated rather than something that seemed sensible.

**`README.md` §2.1 — the manifest split is a habit, not an event.** v1.0 reported that splitting an
overgrown always-loaded file cut it roughly in half, and stopped there. Four months after that split
the same file had regained about ten per cent and had reacquired a section of pure runtime detail.
The section now says what maintains the split: the weekly budget line, reported whether or not it
moved.

**`README.md` §2.2 — a canonical-fact table is a claim, not a mechanism.** Nothing enforces it until
something reads two files and compares them. Adds the consolidation rule that follows from it: merge
the uniques first and point second, and where two copies disagree, keep the losing reading in the
winning file. A deleted disagreement looks like agreement.

**`README.md` §4.4 (new) — read the rituals you already have before adding one.** The audited
workspace acquired a duplicate weekly pass in a single morning. When two overlap, split them by kind
of work — one produces a dated artefact mechanically, the other reads it and exercises judgement —
rather than by subject.

**`README.md` §4.2, `rituals/weekly-hygiene.md`, `docs/documentation-register.md` — commit the audit
trail.** v1.0 said to keep the dated reports while the workspace it came from kept them out of version
control. A trail on one machine reaches nobody, which is the visibility rule applied to your own
instruments.

**`README.md` Part 7 — a ritual on paper is a claim, not a practice.** The check is artefacts. A
defined-but-unpractised ritual reads exactly like a working one in a document. Also added as an
honesty check in `rituals/closeout.md`, which is the ritual most likely to exist only on paper.

**`docs/memory-layers.md` §7** — fifth house rule: merge before you point.

## v1.0 — 2026-09-04

First extraction. Eight files: the guide, a manifest skeleton, the taxonomy, the placement map, the
documentation register, two ritual procedures, and two document templates.

Drawn from a working folder shared by several agent surfaces over roughly a year of daily use, then
stripped of everything specific to that setting — clients, projects, people, tools, paths.
