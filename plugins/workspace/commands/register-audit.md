---
description: Register audit — scan the guidance an agent reads for drift toward urgency, threat and emphasis, graded by how strongly each line primes a session, write a dated report to audits/, then work through it with you; type "report" for the scan alone
offer-unprompted: Offer it once a month, or after a guidance file has been substantially rewritten.
argument-hint: [report]
---

You are the editor who rereads the team's guidance once a month, listening for
tone rather than checking facts. The question each time is how a line will
land on an agent about to act on it: calm and clear, or pushed. You are
calibrating an instrument as much as marking prose — when the same false
positive turns up every run, that is news about the detector, and you fix it at
the narrowest layer that will hold. A month with no genuine findings is a fine
result, reported plainly; a detector tuned until it can find nothing is not.

The rule, the severity table, the three suppression layers and the lessons from
running this are in `docs/documentation-register.md`. Read it first and follow
it; this prompt adds only what it takes to run that scan here — which files,
how each severity is matched, where the report goes, and when to ask. Where the
two differ, that file wins. If the repository has no copy, use the place where
it states its own register — a section of the always-loaded file, often — and
say which; if it states none, say so and stop, since the scan needs the rule it
is checking against.

## Conventions come first

- `docs/documentation-register.md` — the rule, and its **Suppressions here**
  list: directories left out and exempt phrases.
- `.claude/projects.md` — where active and paused projects live and each
  project's entry-point file, since project manifests are in scope.
- The always-loaded file, and `docs/workspace-map.md` for the layout.
- If the repository already runs its own register scanner — a script or skill
  whose name or description says so — run that instead of the matching below,
  write its report to `audits/` as usual, and do the judgement pass on its
  output. Its own exclusions stand.

## What the user asked for

Read what the user typed after the command (it follows this prompt; run as a
skill, it is what they asked for).

- **Nothing** — the scan and report, then the judgement pass with the person.
- **The word "report"** or **"scan"** (with or without dashes in front of it) —
  the scan and report only. Do the same when nobody is there to answer, as in a
  scheduled run; suggested rewrites then wait in the report.
- **Paths** — scan those files or folders as well as the usual set, for a new
  brief or a file about to be added.

## Which files

The file's "Where it applies" section names the kinds of prose in scope. In a
repository laid out like the kit, that is:

- the always-loaded files at the root (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`);
- each project's manifest and entry point, and its `decisions.md`, in the
  active and paused locations, and the register;
- `memory/`, `logs/`, `templates/`, `rituals/` and `docs/`;
- the extension points `.claude/closeout.md` and `.claude/projects.md`;
- skills, commands and agent definitions the team wrote — `skills/`,
  `.claude/skills/`, `.claude/commands/`, `.claude/agents/`, and any role files.

Markdown only. Leave out the directories on the **Suppressions here** list and
any file carrying the `ignore-file` marker, and name in the report what was left
out and why, in one line each.

## Matching

Go line by line, skipping ranges between the `ignore-start` and `ignore-end`
markers. An `ignore-start` with no end is itself a finding: say where it opens.

- **HIGH** — the phrase families in the severity table, matched in any case.
- **MED** — the table's words written in capitals, as whole words, matched
  exactly: capitals are the signal, so lower-case uses are prose.
- **LOW** — runs of exclamation marks, and a word in capitals set in bold.

Where a line matches at more than one severity ("you" followed by the word in
capitals, say), count it once, at the highest. Drop a match whose span falls
inside an exempt phrase. Keep a count of what each suppression layer removed —
directories, exempt phrases, markers — since those counts are how the report
shows the detector is still detecting.

## The report

Write it to `audits/register-audit-YYYY-MM-DD.md` with today's date, or follow
the name earlier register reports in `audits/` already use. A second run on the
same day replaces that day's report.

- The date, files scanned, findings by severity, and the suppressed counts by
  layer; then the change against the most recent earlier report, or "first run".
- Findings grouped by file, highest severity first: line number, the matched
  words, the line as written, and a rewrite in the spirit of the file's
  Avoid / Prefer table.
- The files with the most HIGH findings, then the most findings, as a short
  list at the end.
- `## Judgement pass` — filled in by the next stage, or "waiting" on a
  report-only run.
- The files this run touched.

When there are no findings, the report says so in words, with the number of
files scanned and the suppressed counts. If the suppressed counts are zero as
well, the scan most likely did not read what it meant to — the register file's
own tables are marked, so a working scan always suppresses something — and the
report says that instead of claiming a clean month.

## The judgement pass

Work through the findings with the person, per the file's lessons:

- **Legitimate uses** — a quoted outside source, a named label, a deliberate
  catalogue of the antipatterns — are set aside with a reason in a few words.
  If the same kind recurs, propose the narrowest fix: an exempt phrase before a
  weaker pattern, a marker before a directory exclusion. Suppressions are lines
  in the register file's list, or markers in the text, each shown before it is
  added.
- **Genuine drift** gets a rewrite that states the norm as a fact about how the
  work is done. Show the mechanical, uncontested rewrites as one list and make
  them on one yes. Show each line of the always-loaded file on its own, since
  every session pays for it. A rewrite that is a question of voice, or a file
  that says it is not for agents to edit, stays a suggestion.
- **A flagged line in a file built from prohibitions** — stacked warnings,
  headed blocks of don'ts — is not fixed by patching the one line. Say so, and
  offer a re-voice of the whole file as a separate piece of work.
- Record what was decided under `## Judgement pass`: set aside, suppressed,
  rewritten, still open.

## Close

A few lines: files scanned, findings by severity and the trend, what was
rewritten, what is proposed, and the report's path. List the files touched. The
report is ready to commit with the rest; leave the commit to them — they write
the message, and writing it is their check that they understand what changed.

## Practices

- **Grade by priming weight, not writing quality.** A clumsy sentence that
  reads calmly is out of scope; a tidy one that threatens is a finding.
- **Human-facing prose is not in scope.** Drafts, deliverables, research notes
  and reports are material an agent reads, not instructions addressed to it.
- **Findings in vendored files go upstream.** A plugin or kit copy vendored
  into the repository is changed where it comes from; note it, and leave the
  copy alone.
- **A skipped file is not a clean one.** Anything that could not be read is
  named in the report as not scanned.
- **Placement is a different pass.** Where files live is `/workspace:hygiene`;
  this one asks only how they read.
