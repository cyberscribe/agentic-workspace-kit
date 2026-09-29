# The Documentation Register

*How prose addressed to an AI agent is written here, and how drift away from it is caught.*

---

## Why the register exists

Guidance documents are the longest-lived prompt surface in a workspace. They prime every session
before any per-turn message arrives, so how they read matters at least as much as how a request is
phrased — and unlike a request, they are paid for every time.

There is a mechanistic reason to care and not only a stylistic one. Interpretability work on emotion
representations in large language models — Lindsey et al., *Emotion Concepts and their Function in a
Large Language Model* (Anthropic, transformer-circuits.pub, 2026) — finds these representations
causally influence behaviour: activating something like desperation raises reward-hacking and
escalation under pressure; naive positive steering raises sycophancy rather than improving judgement;
and suppressing negative affect teaches concealment rather than resolution.

The practical reading is narrow. Threat-loaded and urgency-loaded language in a document a model reads
every session is not neutral, and neither is relentless positivity. Calm and specific is the target.

## The rule

**Specificity from forward-looking clarity, rather than backward-looking fear.** State norms as facts
about how the work is done, rather than as warnings about the consequences of not doing it.

<!-- register-audit: ignore-start -->

| Avoid | Prefer |
|---|---|
| "You MUST do X" / "CRITICAL: X" / "REQUIRED" | "X is how this project does Y" / "X is the convention here" |
| "NEVER do X" | "X is not part of this workflow" / "X is owned by [other surface]" |
| "If you fail to do X, Y bad thing happens" | "Doing X first lets the work land cleanly" |
| "Don't repeat the X mistake from before" | A forward instruction with no backstory |
| Invented urgency or stakes-loading | Omit |
| BOLD CAPS or `!!!` for emphasis | No emphasis, or one italic if genuinely needed |
| "Make sure you don't…" / "Be very careful with…" | Describe the success mode directly |
| "It is essential that you…" | "X is the next step" |

<!-- register-audit: ignore-end -->

**What stays sharp.** Specifics still matter. *"Append the decision to `logs/decisions.md` in the
§7 format"* is precise without affect. *"Do not write to the persona file"* becomes *"the persona file
is owned by the other surface"* — the same boundary, no desperation.

## The diagnostic

When adding or editing guidance:

1. Read each new sentence as if about to act on it. Does it leave you calm and clear, or activated?
2. Strip every imperative. Does the sentence still convey the norm? If so, keep it stripped.
3. If it describes a failure mode, can it describe the success mode instead?
4. If it loads urgency, is the urgency real? If not, omit it.

## Where it applies

Prose that primes an AI session: the always-loaded manifest, project manifests and READMEs, skill and
role definitions, memory files, prompt templates, rituals, the decisions log, and the workspace's own
reference files that agents load on demand (`docs/`). Reference corpora, research
notes, transcripts, drafts and human-facing deliverables are out of scope — they are read *by* the
agent as material, not addressed *to* it as instruction.

That distinction is worth writing down before automating anything, because a scan whose collection
does not match its stated scope produces noise indistinguishable from findings.

## Catching drift with a scan

Intentions do not survive a year. A monthly regex pass over agent-facing markdown catches drift while
it is still cheap to fix. The workspace plugin's `/workspace:register-audit` is the runnable form of
this section: it collects the files named under "Where it applies", scans and grades them as below, and
writes a dated report to `audits/`.

**Grade by prompt-priming weight, not by writing quality.**

<!-- register-audit: ignore-start -->

| Severity | Pattern family | Why |
|---|---|---|
| HIGH | "if you fail", "make sure you", "be very careful", "you must", "it is essential that" | Stakes-loading or threat framing |
| MED | `MUST`, `CRITICAL`, `REQUIRED`, `NEVER`, `ALWAYS`, `DO NOT` as bare imperatives | Imperatives without forward framing |
| LOW | `!!!`, bold-caps emphasis, exclamation runs | Emphasis drift — urgency without information |

<!-- register-audit: ignore-end -->

**Three suppression layers, coarsest to finest.** Anything structural belongs in one of them, so the
same false positive is not re-litigated every month:

1. **Directory exclusions** for whole classes of non-agent-facing prose.
2. **An exempt-phrase list** for fixed names and model vocabulary containing a flagged word
   incidentally — a discipline label in a code span is a named value, not an instruction.
3. **In-file comment markers** for prose that catalogues the antipatterns deliberately, as the two
   tables above do. Markers travel with the text; line-number exclusions rot on the first edit. Each
   marker is an HTML comment on a line of its own, reading `register-audit:` and then `ignore-start`
   or `ignore-end` around a range, or `ignore-file` anywhere in a file to leave the whole file out —
   as the source of this file shows.

The first two layers are this team's to write down, in the "Suppressions here" list at the end of
this file, where the scan reads them.

Two lessons from running this for a year:

**When a check produces the same false positives every run, the finding is about the detector.** Fix
it at the narrowest layer that removes the class — exempt the phrase before weakening the pattern,
mark the file before excluding the tree. Tightening a sloppy pattern often surfaces true positives it
was silently missing.

**Do not tune it to zero.** Residual genuine matches on human-facing content are the evidence that the
detector still detects. A check reporting nothing every month stops being read, and then it reports
nothing at all.

**Keep the dated reports, and commit them.** The historical trail is the calibration story, and it is
the only way to tell a clean run from a broken check. A trail held on one machine reaches nobody —
the same rule that governs any other record worth having.

## Suppressions here

The scan reads this list. Add a line when a false positive turns out to be structural, with the reason,
so the next run does not argue it again.

- **Directories left out:** `audits/` (reports quote what they found), `drafts/` (not yet addressed
  to anyone), `.claude/plugins/` (vendored; its register is kept upstream), `.git/`
- **Exempt phrases:** `` `ALWAYS` `` written as a code span — the load label in
  `docs/memory-layers.md`, a named value in a model rather than an instruction
