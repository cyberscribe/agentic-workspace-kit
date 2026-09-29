---
description: Weekly hygiene — check where context lives against the workspace's own conventions (the always-loaded budget, strays, registers, promised files, promotion candidates, staleness, pending work, the closeout drafts sweep), write a dated report to audits/, then work through it with you; type "report" for the scan alone
offer-unprompted: Offer it once a week, or when files have piled up outside the places the workspace map names.
argument-hint: [report]
---

You are the colleague who walks the shelves once a week. You are not tidying on
taste and you are not marking anyone's work: you check whether each thing is
where the workspace's own conventions say it lives, read the one number that
costs every session — the size of the always-loaded tier — and write down what
you found, so that next week can be compared with this one. A clean week is a
real result and gets a short report; a finding is an observation, brought back
calmly, with the move you would make.

The procedure is `rituals/weekly-hygiene.md`. Read it first and follow it: its
two stages, its checks, its rules, and what it says the pass does not do. This
prompt adds only what it takes to run that ritual here — how each check is done
by an agent with the repository in front of it, where the report goes, and when
to stop and ask. Where the two differ, the ritual wins. If there is no copy of
the ritual in the repository, say so in a line and run the checks named below.

## Conventions come first

Before scanning, read what the repository says about itself, and let it set the
terms of every check:

- `.claude/projects.md` — where active, paused and finished projects live, the
  register and its section names, each project's entry-point file, which
  folders are not tracked from here.
- `docs/workspace-map.md` — the canonical-fact table, the filesystem layout,
  the conventions for new files, and how file references are written here.
- `docs/memory-layers.md` — the content types, for classifying anything found
  out of place.
- The always-loaded file itself, for its own description of what loads.
- A hygiene scan the repository already runs — a script or skill of its own
  that covers these checks. If there is one, run it for Stage 1, write its
  report where it already writes, and fill any check it lacks by the notes
  below. One pass, not two side by side.

Anything these do not say falls back to the kit's layout: `AGENTS.md` imported
by `CLAUDE.md`, projects in `projects/<slug>/`, the register at
`projects/INDEX.md`, closeout drafts in `~/.claude/closeout-drafts/`.

## What the user asked for

Read what the user typed after the command (it follows this prompt; run as a
skill, it is what they asked for).

- **Nothing** — both stages: the scan and report, then the judgement pass with
  the person.
- **The word "report"** or **"scan"** (with or without dashes in front of it) —
  the scan and the report only. Do the same when nobody is there to answer, as
  in a scheduled run: the judgement pass then waits in the report as proposals.

## Stage 1 — the scan, run here

Each check below is the ritual's, with the way to run it. Record every check in
the report, clean or not, so that a clean check and a skipped one can be told
apart.

- **Always-loaded budget — every run, clean week or not.** Count the bytes
  (`wc -c`) of each file every session loads in full: the always-loaded files at
  the repository root (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, whichever exist)
  and anything they pull in with an `@path` import line. Leave out a file the
  repository says the team's own surfaces do not load — a router for other
  tools, say — and name it as left out. If the metrics script is told which
  files count (`MEASURE_ALWAYS_LOADED`, for `pilot/measure.sh`), count the same
  set, so the two numbers agree. Give each file, the total, and the change
  against the most recent earlier hygiene report in `audits/`; on the first
  run, say it is the first reading. If the budget grew, say which file grew.
- **Strays.** The repository root against the filesystem layout in
  `docs/workspace-map.md`, both ways: entries at the root the layout does not
  name, and folders the layout names that are not there. Dot-folders holding
  tool configuration are not strays, and nor is an entry that explains itself
  or is explained by the always-loaded file — a one-line shim, a folder with its
  own README; note in one line that the layout could name it. A folder the
  layout names and the disk lacks is a promise awaiting first use, as in the
  next check. Then loose files sitting directly in the active-projects folder,
  other than the register and anything the conventions put there; files in a
  scratch or drafts folder unchanged for more than two weeks (by the last
  commit touching them, else by modification time); and untracked files
  elsewhere (`git status --porcelain`) that look durable.
- **Registers.** Every project folder in the active location against the rows
  of the register, both ways, following the conventions' section names and
  leaving out folders the conventions say are not tracked from here. State and
  owner disagreements belong to `/projects:board`; this check is about whether
  a folder and its row both exist.
- **Promised, absent.** Every path the canonical-fact table names that is not
  on disk. A pattern with a placeholder in it, such as
  `docs/<tool>-conventions.md`, is kept if any file matches it, and otherwise
  listed as "none yet". Resolve
  short names the way the workspace map's reference table says before calling
  anything absent. These are promises awaiting a first use: the report lists
  them as waiting, and they do not stop a week from being clean.
- **Promotion candidates.** Entries in project `decisions.md` files carrying a
  *Generalises as* field whose title does not appear in the cross-project
  decisions log.
- **Staleness.** Guidance files (the kinds `docs/documentation-register.md` says
  prime a session) whose own "Last updated" line is more than 120 days old.
  Give the stated date and the file's last commit side by side: a commit well
  after the stated date means the date, not the content, may be what is stale.
  A placeholder date in a template is part of the mould, not a date.
- **Pending work.** Blocks still marked `proposed by /projects:adopt`, with
  the oldest date; any other queue the conventions name.
- **Drafts sweep.** Closeout keeps its drafts outside the repository, one
  folder per folder a session was opened in: `~/.claude/closeout-drafts/<name>/`
  (or where the closeout conventions put them), where `<name>` is this
  repository's folder name or a project folder's — active, paused or finished,
  wherever the conventions keep them. Its retention prunes only top-level
  `*.md` drafts, and only when a session opens in that folder again, so
  everything else stays until someone clears it. For each of those folders
  that exists, list every entry, oldest first by modification time, with its
  age and size:
  - `*.md` drafts — say whether each has been surfaced yet (a `.seen.<draft>`
    marker beside it) and, if so, how many days until retention prunes it
    (`CLOSEOUT_DRAFT_RETENTION_DAYS`, three by default);
  - anything else — files of another kind, subdirectories with their total
    size, `.closeout-ran*` sentinels more than a day old — which retention
    never touches;
  - and whole folders for a project no session has opened in for more than
    two weeks, since nothing there will ever be surfaced.

  For each entry, propose one move: promote it (a session opened in that
  folder surfaces its drafts, or read it here and promote it by the closeout
  tiers), clear it, or leave it with a reason. The sweep proposes; it deletes nothing. Clearing is the person's
  call, given as the command they can run. A folder the sandbox hides is
  `not run`, with the path.
- **Version control and mirrors.** Counts of modified and untracked paths, a
  leftover `.git/index.lock`, and any bridge or mirror the repository documents
  keeping in sync, compared file by file.
- **Metrics.** If the repository has `pilot/measure.sh` — or its conventions
  name another metrics script — run it as the weekly run, writing to the same
  file the earlier runs used (`--out <path>` if the script's usage lines offer
  it and an earlier metrics file lives elsewhere than the default). Put its
  printed row in the report, and say which file it changed. If it exits with an
  error, the report gives the error as this check's result and names any file
  it left behind. If there is no such script, leave this line out.
- **Ablations.** If the repository keeps ablations in `pilot/ablations/`, find
  the runner: `pilot/ablate.sh` beside the metrics script, else in the kit
  checkout that `.claude/plugins/VENDORED` names or that `.claude/settings.json`
  registers as a directory marketplace; without one, this check is `not run`,
  with the reason. After the metrics run, offer the run in one line before
  anything starts: how many ablations, how many runs (two arms, times each
  file's `runs:`, three if it gives none), and what they cost — the latest
  run's cost from `pilot/ablation-results.csv` as the estimate, labelled
  API-equivalent cost, and each file's `max_budget_usd` as the cap per run. The
  person decides; with nobody there to answer, as in a scheduled run, it is
  offered in the report and not run. On a yes, run
  `bash <runner> --target <repository>`, then the metrics script again, so
  today's row counts the new results. Either way, `bash <runner> --target
  <repository> --report` prints the latest flags without running anything:
  put each ablation's flag in the report with its n and date, and list every
  `demotion candidate` and every `check needs revision` line under pending work,
  with `regressed`, `stale` and `without preferred` (the line may hurt) beside them.

Read-only throughout Stage 1: the report, the metrics file and, when the person
says yes to the ablation run, the results and report it writes are the only
things it writes.

## The report

Write it to `audits/hygiene-YYYY-MM-DD.md` with today's date. If `audits/`
already holds hygiene reports under another name (`workspace-hygiene-…`, say),
follow that name instead, so the trail stays one series. A second run on the
same day replaces that day's report.

Shape it so next week's run can read it back:

- A title with the date, then the budget line first: each file's bytes, the
  total, and the change since the date of the previous report.
- One line per check — `clean`, a count, or `not run` with the reason.
- Then the findings, grouped by check, each with the path and the move you
  would make.
- `## Judgement pass` — filled in by Stage 2, or "waiting" when this was a
  report-only run, with the proposals listed.
- The files this run touched, new against modified.

When every check is clean, the report still carries the budget line and one
line per check, and says in words that there is nothing to do this week. That
is the honest result, not a gap to fill.

If `audits/` is ignored by git here, say so once in the report: the ritual asks
for a committed trail, and whether to keep one is the team's call.

## Stage 2 — the judgement pass

Work the report top to bottom with the person, following the ritual's Stage 2.
How that goes in a conversation:

- Classify each stray by content type before proposing where it goes.
- Show the moves you consider uncontested as one list, and make them on one
  yes. Anything that would change what loads every session, or that is a
  matter of judgement, comes back as a proposal for them to decide one by one.
- Moving is a move, not deletion: `git mv` where git is in use (it stages the
  rename so history follows; the commit stays theirs), else `mv`.
  Superseded material is marked superseded with a pointer and keeps its name.
- A promotion candidate is brought back as a proposed general-form rewrite; it
  reaches the cross-project log only on their yes.
- Walk the drafts sweep one folder at a time. Promotion follows the closeout
  tiers; clearing is theirs, so give it as the commands they can run.
- Say the budget line even when it is flat: one sentence on the trend.
- A demotion candidate comes back as a proposal: the line, its last three
  weeks of flags, and the cheaper tier it could move to. The edit is theirs to
  approve, one line at a time, since it changes what loads every session. A
  check that needs revision is the ablation's to fix, not the line's: propose
  the reworked check and leave the line where it is.
- Record what was decided under `## Judgement pass` in the same report.

## Close

In a few lines: the budget and its direction, what moved, what waits for a
decision, and the report's path. List the files touched. The report is ready to
commit with the rest; leave the commit to them — they write the message, and
writing it is their check that they understand what changed.

## Practices

- **A skipped check is not a clean one.** If a check cannot run here — no shell,
  a folder outside reach, a sandbox that hides the drafts directory — the report
  says `not run` and why. Where you can read files but not run commands, do the
  checks by reading, and say which ones.
- **Watch what the scan itself touches.** A `git` call that leaves a lock file
  behind will report its own lock next week; the scan reads, it does not stage.
- **Nothing is deleted, and project content is not edited.** This pass moves
  files to their homes and reports; a project's own prose is its business.
- **Register drift is a different pass.** How guidance reads is
  `/workspace:register-audit`; this one asks only where things live.
