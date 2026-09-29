# Changelog

Versions of the workspace context kit. Newest first. Entries are corrected by appending, not by
rewriting — the record of what a version claimed is part of what the version is.

---

## v2.0.0 — 2026-09-29

**A work system on top of the context system: every project carries its own finish line and next
action, twelve commands across three plugins keep them true, and the same commands reach assistants
that load skills rather than plugins.**

**The tracking axis.** `templates/project-readme.md` takes its final order: What this is, Desired
outcome, **Done when** (a checklist), a **Now** block (State · Next action · Waiting on · Check-in ·
Updated, then one dated line, rewritten rather than appended), and optional Next up, Success
criteria, People, Precedents and Parked. People uses five roles: owns, does, helps, ask first, keep
told. The register gains State and Owner columns; `inbox.md` is the team inbox; the person profile
gains an optional in-flight limit; `templates/verification-standard.md` (what counts as checked, per
kind of work) and `templates/catalogue.md` (what the team has built and would reuse) are new. The
taxonomy names tracking's three homes. README §1.3 and §2.3 describe the axis, and a new
"Tracking, day to day" section maps each moment to its command.

**projects plugin, 1.1.0 (new).** `/projects:new` and `/projects:adopt` set the outcome, finish line
and first next action — adopt adds only what an existing project lacks, as small insertions, with a
`draft` mode that marks every proposal for later confirmation. `/projects:capture` fills the inbox;
`/projects:board` shows every project with one-line flags; `/projects:review` empties the inbox and
walks the flagged projects; `/projects:close` ticks each Done-when box against evidence, keeps a
short retrospective and moves the register row; `/projects:pickup` briefs whoever takes a project
over; `/projects:mine` lists one person's actions for their own task manager. A session-start hook
gives the folder's project in three lines, and elsewhere at most one line a day about what is
waiting. `.claude/projects.md` holds a team's own layout, section names, in-flight limit and review
cadence, mirroring `.claude/closeout.md`; one reading contract (how labels, gaps, headings and
owners are read) is written once in the plugin README and followed by every command and script.
Versioned 1.1.0 because 1.0.0 was installed in test repositories while the plugin had one command;
neither version was published before this one.

**workspace plugin, 1.0.0 (new).** `/workspace:quick-start` moves here from `team/` and gains three
modes — fresh, joining, and existing system, where the kit adopts a system that was there first
through a confirmed mapping rather than installing over it — and a closing pass that wires the kit
into the daily and weekly routines people already run. `/workspace:hygiene` and
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
`inbox.md`, `.claude/projects.md` and the two new templates, and vendors all three plugins, with
`VENDORED` naming each version, the kit commit and checkout, and "+ uncommitted changes" when the kit
tree was dirty. A repository that keeps its own `CLAUDE.md` is detected before anything is placed:
the Next message and `.claude/closeout.md` then work with that file rather than asking for it to be
replaced. Rendered files are 0644 and `measure.sh` 0755. `$schema` is gone from the marketplace
files.

**Metrics.** `pilot/measure.sh` gains seven columns after the established ten (active projects, with
a next action, with a Done when, done, waiting over 14 days, most in flight per person, median days
to done), all recomputed by `--backfill`; `--out` and `MEASURE_ALWAYS_LOADED`; with no commits it
says so and writes nothing, and backfill skips weeks before the first commit.

**Tests (new).** `bash tests/run.sh`, plain bash with git, jq and python3: installs run twice and
interactively, every JSON parses, versions and marketplaces agree, the closeout hooks (team
detection, capture prompt, retention, the personal layer), the session-start line, `measure.sh` over
a dated fixture history, the twelve commands vendored and as skills from one source each, and three
rules over the whole kit — no method-brand vocabulary, no AI-vendor attribution in files or history,
no capitals-for-emphasis in prompts, templates and rituals.

**The commit stays with the person.** The agent stages what it touched, by name, and summarises the
change; the person committing writes the message, as their check that they understand it. Stated in
`rituals/closeout.md`, `/closeout`, the team closeout conventions and the quick-start's close.

**What the walkthrough changed.** Before release the kit was run end to end as an agent against two
scratch repositories: a fresh install for a three-person team (quick-start, both kinds of
`/projects:new`, capture, board, review, closeout, close), and the quick-start in existing-system mode
against a one-person system with its own always-loaded file, register, decisions log and skills.
Twenty-six findings, all fixed, two in part. The quick-start's modes now cover every state (fresh no
longer needs an empty register); it names the stand-in paragraph to replace or delete, waits for a
project before checking the session-start line, takes the metrics baseline only after the first
commit, reads the team's review day instead of asking each joiner, runs adopt in the same sitting
after the mapping, lists leftover `.kit-incoming` files as commands the person runs, and spares a
one-person team the pull-request advice. The conventions gain an Entry point line (the conventions'
file, else `README.md`, else the folder's `CLAUDE.md`) that every command, the hook and the metrics
now share, a Default owner line, and one profile filename rule. `/projects:close` asks what becomes
of Parked and open Next up lines; `/projects:new` puts a target date in the Desired outcome;
`/closeout` holds a Done-when tick to the verification standard; the board's stale flag uses the team
cadence. The session-start line reports a done project as done and names a missing section rather
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
