# Changelog

Versions of the workspace context kit. Newest first. Entries are corrected by appending, not by
rewriting — the record of what a version claimed is part of what the version is.

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
