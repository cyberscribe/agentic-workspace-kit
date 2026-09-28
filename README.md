# A Workspace That Keeps Its Context

*A working system for collaborating with AI agents over long horizons, across many projects at once.
It is a filesystem layout, four content types, three human-in-the-loop rituals, and two small checks.
Copy the files in this kit, change the names to yours, and start.*

*Nothing here is theoretical. It was extracted from a working folder shared by several agent surfaces
over a year of daily use, then stripped of everything specific to that setting. Where a claim rests
on evidence, the evidence is named; where it rests on experience, it says so.*

---

## The problem

Three failure modes show up in every long-running collaboration with an AI agent, and they compound.

**Everything ends up in the always-loaded file.** It starts as a page of conventions. A year later it
is thirty kilobytes of project state, tool notes and half-remembered gotchas, and every session pays
for all of it before answering anything. Nobody decided this; each addition was individually
reasonable.

**Knowledge lands wherever the session happened to be.** A constraint discovered in one project ends
up in a personal memory store; a decision made in a chat window never reaches the repository. The
next session re-derives it, or worse, contradicts it. The material exists — it is just not where
anyone will look.

**Nobody writes down why.** The decision survives, the reasoning does not, and the option that was
rejected for good reasons gets re-proposed next quarter with enthusiasm.

The system below addresses all three, and the first idea is the one everything else hangs from.

---

## Part 1 — The model

### 1.1 Two axes

Every durable thing you might record sits at the intersection of two questions.

**Tier** — how often is this loaded back into context? Some things shape every session. Some matter
only when a particular topic comes up. Some matter only inside one project.

**Scope** — who can see it? Shared, meaning committed to the repository and reaching your colleagues
and your other machines; or individual, meaning this machine, this surface, this user.

The tier decides the cost. The scope decides the reach. Most placement mistakes are one of these two
answered wrongly, and the expensive one is tier.

### 1.2 The four content types

| Type | What it is | The test | Loads |
|---|---|---|---|
| **Working standards** | The human–AI relationship and how to improve that layer | Does this change how we work together, in any project? | `ALWAYS` |
| **General reference** | Context and information useful on an as-needed basis | Would I want this to hand whenever the topic comes up? | `AS-NEEDED` |
| **Project reference** | Context specific to a project that persists across sessions. A project has a defined desired outcome, a finish line, or a named deliverable | Does this stop meaning anything once the project ships? | `PER PROJECT` |
| **Templates** | Reusable units for completing a *category* of work — checklists, agent role definitions, log skeletons | Is this the thing, or the mould the thing is made in? | `AS-NEEDED` |

The type is a property of the content and travels with it. The store is an accident of which surface
happened to be open. That is why the type decides placement and not the reverse: a store-first scheme
has to be re-derived every time a new tool appears, and a content-first one absorbs the new tool as
another column.

Note what the fourth type buys you. An agent role definition, a review checklist and a decisions-log
skeleton have nothing in common as documents, and everything in common as *things you deploy when a
category of work starts*. Naming that category stops each one being reinvented per project.

### 1.3 Tracking is not context

Task lists, project status, kanban columns, sprint state: these are state, not knowledge. They get
**reconciled**, not promoted. Keeping the two on separate axes is what stops an end-of-session
knowledge pass turning into a status meeting, and it is the single most common way these rituals
decay into theatre.

### 1.4 Precedence

When two stores disagree:

1. **Project reference wins inside its project scope.** It sits closer to the work and it was written
   with the finish line in view.
2. **Below that, the most specific store wins** — and the loser gets corrected rather than left to
   disagree quietly. Two sources that contradict each other are worse than one that is wrong, because
   the reader cannot tell which is stale.
3. **Working standards govern how, not what.** They set posture, register and conventions. They do
   not overrule a project's factual content.
4. **Shared beats individual.** See §3.4.

---

## Part 2 — The layout

A filesystem, not a database. Every file is human-readable, greppable, and diffable, and the whole
thing lives in version control.

```
workspace/
  MANIFEST.md            ← the always-loaded file (CLAUDE.md, AGENTS.md — whatever your surface reads)
  docs/                  ← general reference, loaded on demand
    memory-layers.md     ← the taxonomy above, as it applies to your setup
    workspace-map.md     ← the canonical-fact table and where new files go
    <topic>.md           ← one file per subsystem or convention
  projects/
    INDEX.md             ← the register: active, paused, done
    <slug>/              ← one folder per project; README, and decisions.md when it earns one
  templates/             ← reusable skeletons, copied into the project that needs one
  logs/
    decisions.md         ← cross-project decisions that generalise
  memory/                ← canonical cross-surface facts: glossary, per-topic context
  skills/                ← packaged procedures your surface can invoke
  audits/                ← dated reports from the periodic checks
```

### 2.1 The always-loaded manifest

One file, read in full at the start of every session. It holds only what should shape behaviour from
the first token: the operating stance, who the agent is working with and how they want to be worked
with, the behavioural conventions, a map of where everything else lives, and the formats for the logs.

It does not hold project state, per-language conventions, source lists, or a filesystem inventory.
Those are exactly the things that are useful when relevant and inert the rest of the time, and they
belong one hop away in `docs/` and `projects/`.

Splitting an overgrown manifest this way is usually the first thing worth doing, and in the original
workspace it cut the always-loaded file roughly in half at no loss.

**Then it grows back.** Four months after that split, the same file had regained about ten per cent,
one individually reasonable addition at a time, and had reacquired a section of pure runtime detail —
which automation path to use from which surface, a permission flag, an error code. Nobody decided to
put it back. The split is a habit rather than an event, and the thing that maintains it is the weekly
budget line in §3.1: a number, reported whether or not it moved, so that growth has to be argued for
rather than merely happening.

### 2.2 Canonical fact locations

A table, in `docs/workspace-map.md`, naming the one authoritative file for each domain: who the user
is, the glossary, the conventions for each tool, the decisions log, the project register. Everything
else *points at* those files rather than restating them.

This is the rule that does the most work, and it is worth stating in its strongest form: **duplication
is the mechanism by which drift happens.** Two copies of a fact look equally authoritative and age at
different rates, and the reader cannot tell which is which. A pointer costs one extra file read; a
second copy costs a wrong answer six months later.

**The table is a claim, not a mechanism.** Nothing enforces it until something reads two files and
compares them, so copies made before the table existed sit there quietly diverging. In the workspace
this kit came from, a profile file carried its own copy of the glossary for months; by the time anyone
checked, one term had two different definitions and the wrong one was in the file whose name suggested
it was authoritative. When you do consolidate, **merge the uniques first and point second** — a
pointer at a file missing four entries loses four entries — and where the two copies disagree, record
the losing reading in the winning file rather than deleting it. A deleted disagreement looks like
agreement.

### 2.3 One folder per project, and an index that is the register

`projects/INDEX.md` is the live list — active, paused, done — with one line per project and a link to
its folder. Paused projects move to a section rather than disappearing, because the reason something
is paused is itself context.

The folder holds a `README.md` saying what, why, current state and open questions. When a project
starts making decisions worth preserving, it gets a `decisions.md` from the template.

### 2.4 Templates as a first-class location

`templates/` holds the skeletons: a project decisions log, a project README, an agent role
definition, whatever recurring document shape your work produces. The test for whether something
belongs here is in §1.2 — does it serve a *category* of work rather than one work unit?

The subtle benefit: a template carries its own governing rules at the point of use. A decisions-log
skeleton that opens with the scope filter puts that filter in front of the person about to write an
entry, rather than in a manifest section they would have to think to consult.

### 2.5 Where new files go

Keep an explicit table in `docs/workspace-map.md` mapping kinds of content to locations — per-project
files, per-person notes, drafts, cross-project decisions, project-specific decisions, reusable
skeletons. When a referenced file does not exist yet, create it at first use; a documented-but-absent
path is a promise, not a fault.

---

## Part 3 — The economics

This is the part most systems skip, and it is why most of them silently stop working.

### 3.1 The always-loaded tier is a budget, not a folder

Every other tier is **additive**: adding a file to `docs/` costs nothing until something asks for it.
The always-loaded tier is **zero-sum**: every byte is paid by every future session, relevant or not.

So an addition there names the line it replaces, or makes the case that the budget should grow — and
a human agrees to it. Not as a side effect of an end-of-session sweep.

Put a number on it. In the workspace this came from, the always-loaded tier is about 29 KB against
roughly 60 on-demand files that cost nothing until asked. Once the number is visible weekly, growth
becomes arguable instead of invisible.

### 3.2 The bar for always-on

*A future session would go wrong without ever thinking to ask.*

That is a high bar and it is meant to be. A gotcha that bites on one task belongs with that task's
material, where the session working on that task will find it. Only a thing nobody would think to
look for earns the always-loaded tier.

### 3.3 An index is not content

One line per entry: a pointer, and a hook saying when it matters. *Read this before publishing
anything from the programme.* If you find yourself writing a paragraph in an index, the paragraph
belongs in the file the line points at.

This applies to every index in the system — the project register, the memory index, the canonical-fact
table. An index that grows bodies stops being scannable, which is the only thing an index is for.

### 3.4 The visibility rule

Individual stores reach nobody else. A gitignored working note exists only on the machine that wrote
it. A personal memory directory is narrower still — one machine, one surface, invisible even to
another agent working in the same repository.

**Promoting something others need into a personal store is the most common way to lose it.** It feels
like filing. It is closer to deletion with extra steps. If a colleague, another surface, or a future
you on a different machine would need it, it goes in the shared destination.

### 3.5 Coverage has a cost, and it lands on the human

The arguments above are about the machine's context window. This one is not, and it is the one worth
sitting with.

A store that covers everything removes every occasion to work anything out. Looking something up
means not reconstructing it, and reconstruction is the only full rehearsal. As coverage of a
knowledge store approaches completeness, unaided retention in the person using it trends toward zero.

This is not an argument against writing things down. It is an argument for the always-loaded tier
being *small*, and for noticing that "the agent has all the context" and "the human still knows the
domain" are in tension rather than aligned. Two independent arguments now point the same way: one
about tokens, one about the person. When they agree, the case is strong.

---

## Part 4 — The rituals

Three human-in-the-loop passes on three cadences. They are rituals rather than automations on purpose:
**loading is automatic, promotion is human-involved.** That asymmetry is what stops the durable stores
filling with plausible material nobody chose, and it is the design decision most worth defending when
someone suggests automating it away.

### 4.1 Closeout — at the end of a working session

Review what was learned or decided, classify it by content type, and promote what is durable. A
learning is worth recording if a future session would otherwise re-derive it. Working code and
finished deliverables are not learnings; the constraint that shaped them is.

The shape of the pass:

1. **Review.** What was learned, decided, corrected or discovered?
2. **Classify before writing.** Tier first, then scope. The tier is the expensive decision.
3. **Propose, then apply.** Surgical edits at the classified destination — the line that changed, not
   a rewrite of the file around it. Anything touching the always-loaded tier comes back as a proposal
   naming what it would displace.
4. **Verify before recording.** Check each technical claim against the current state of the code or
   file. A behaviour that changed during the session is not a finding.
5. **Reconcile tracking separately**, after promotion, and report it separately.
6. **Report**: what was promoted and at which tier, what is proposed and waiting, which files were
   touched.

**The backstop, and its limits.** Some agent harnesses expose session lifecycle hooks, in which case
an automatic capture can write candidate notes to a draft when the ritual is skipped, and the next
session offers to promote them. If yours does, use it — the habit works and people forget it. If
yours does not expose hooks, or does not persist a transcript you can read, say so plainly rather
than building a lookalike. A backstop that catches nothing is worse than a known gap, because people
stop watching for the thing it was supposed to catch. The compensating moves are to have the agent
*offer* the pass rather than wait to be asked, and to leave a draft anywhere a later session will
look.

*One implementation of the hook-based version ships in this repository as a Claude Code plugin, at
`plugins/closeout/`. The pattern matters more than the tool.*

### 4.2 Weekly hygiene — is everything where it belongs?

A scan plus a judgement pass. The scan is deterministic and reports:

- the always-loaded byte total and its change since last week;
- strays — durable content outside the conventions;
- the project register against the actual folders, both directions;
- paths the canonical-fact table promises that are absent;
- decisions inside projects that look like they generalise;
- guidance whose own "last updated" line has gone quiet;
- anything the previous rituals left waiting.

Then a person-and-agent pass classifies each finding, applies what is mechanical and uncontested, and
brings back anything that would change what loads every session.

**Commit the reports.** A dated trail is the only evidence that a check is still calibrated — and a
trail that lives on one machine reaches nobody, which is the visibility rule in §3.4 applied to your
own instruments. Keeping the reports out of version control is a common reflex, because they look like
noise. They are the record of whether the noise is meaningful.

Two rules keep it safe: **nothing is deleted** — strays move to their home, superseded material is
marked superseded and keeps its name and its pointer to what replaced it — and **promotion is
proposed, never silent.**

### 4.3 Monthly register audit — how does the guidance read?

Covered in §5.1: a scan of agent-facing prose for drift toward urgency and threat framing, followed by
a judgement pass. Monthly is enough; the drift is slow.

### 4.4 Read the rituals you already have before adding one

The set is short and nobody remembers all of it. The workspace this kit came from acquired a duplicate
weekly pass in a single morning — a new hygiene ritual built without noticing that an existing
scheduled review already covered part of the same ground. It surfaced two hours later, in an audit.

When two overlap, split them by **kind** of work rather than by subject: one produces a dated artefact
mechanically, the other reads that artefact and exercises judgement. Two rituals aimed at the same
subject with no stated difference converge on the same vague pass, and then neither gets run.

### 4.5 Why the cadences differ

Placement drifts weekly, because work happens weekly. Register drifts monthly, because prose changes
slowly. Learnings evaporate at the end of every session, so that pass is per-session. Matching the
cadence to the actual rate of change is what keeps each one worth reading — a check that mostly
reports nothing new stops being read, and then reports nothing at all.

---

## Part 5 — Writing for agents

### 5.1 The documentation register

Guidance documents are the longest-lived prompt surface you have. They prime every session before any
per-turn message, so their register matters at least as much as how you phrase a request.

There is a mechanistic reason to care, not only a stylistic one. Interpretability work on emotion
representations in large language models — Lindsey et al., *Emotion Concepts and their Function in a
Large Language Model* (Anthropic, transformer-circuits.pub, 2026) — finds that these representations
causally influence behaviour: activating something like desperation raises reward-hacking and
escalation, while naive positive steering raises sycophancy rather than improving judgement, and
suppressing negative affect teaches concealment rather than resolution. The practical reading is
narrow and useful: threat-loaded and urgency-loaded language in a document the model reads every
session is not neutral, and neither is relentless positivity. Aim for calm and specific.

**The rule: specificity from forward-looking clarity, rather than backward-looking fear.** State norms
as facts about how the work is done, rather than as warnings about the consequences of not doing it.

<!-- register-audit: ignore-start -->

| Avoid | Prefer |
|---|---|
| "You MUST do X" / "CRITICAL: X" | "X is how this project does Y" |
| "NEVER do X" | "X is not part of this workflow" / "X is owned by [other surface]" |
| "If you fail to do X, Y bad thing happens" | "Doing X first lets the work land cleanly" |
| "Don't repeat the X mistake from before" | A forward instruction with no backstory |
| Invented stakes — "this is your one chance" | Omit |
| BOLD CAPS or `!!!` for emphasis | No emphasis, or one italic if genuinely needed |
| "Make sure you don't…" / "Be very careful with…" | Describe the success mode directly |

<!-- register-audit: ignore-end -->

Specifics stay sharp. *"Append the decision to `logs/decisions.md` in the §13.2 format"* is precise
without affect. *"Do not write to the persona file"* becomes *"the persona file is owned by the other
surface"* — same boundary, no desperation.

The diagnostic when writing or editing guidance: read each sentence as if about to act on it. Does it
leave you calm and clear, or activated? Strip every imperative — does the sentence still convey the
norm? If it describes a failure mode, can it describe the success mode instead?

**Enforce it with a scan, not with intentions.** A monthly regex pass over agent-facing markdown,
graded by prompt-priming weight rather than by writing quality, catches drift while it is cheap.
Three suppression layers keep it usable: directory exclusions for whole classes of non-agent-facing
prose, an exempt-phrase list for fixed names containing a flagged word incidentally, and in-file
comment markers for prose that catalogues the antipatterns deliberately — as the table above does.
Markers travel with the text; line-number exclusions rot on the first edit.

### 5.2 The decisions log

Two logs, and the filter between them is the whole design.

**The project log** holds decisions belonging to one project. **The cross-project log** holds
decisions a future session on an unrelated project would find useful.

**The filter:** strip out every reference to the specific project, technology, file path and
stakeholder. If the entry still means something, it belongs in the cross-project log. If not, it
belongs in the project. When it is unclear, it goes in the project — promotion is cheap, demotion is
not.

The entry format:

```markdown
## [YYYY-MM-DD] Decision title

**Context**: What made this a question.
**Decision**: What was decided.
**Rationale**: Why — including the evidence, and its date if it will age.
**Alternatives considered**: What was rejected, and why.
**Generalises as**: (optional) The lesson with the project stripped out.
**Status**: Accepted / Superseded / Under review
```

Three of those fields carry most of the value:

**Alternatives considered** is the part a later reader cannot reconstruct. The decision is visible in
the code; the road not taken is visible nowhere. This is what stops the same rejected option being
re-proposed with enthusiasm next quarter.

**Generalises as** is the promotion mechanism made visible. An entry that grows one is a candidate for
the cross-project log, and a weekly scan can find them.

**Status** is what lets you correct by appending. A dated log is corrected by a later entry, never by
rewriting an earlier one — the record of what you believed in March is itself information.

### 5.3 Name the execution boundary before the first command

When work spans two execution environments — a container and a laptop, a sandbox and a host, CI and
local — say in the instructions which side each step runs on, at the top, before any command.

The reason is specific: an absence reported from the wrong side of a boundary is indistinguishable
from a real one. *File not found* means the file does not exist, or means you looked on the wrong
machine, and an agent with no memory of previous runs cannot tell which. The failure mode is not that
the agent errors; it is that it confidently reports a fact about the wrong system.

The insidious version half-succeeds: a read completes, a lock file leaks, and the damage surfaces
later as a repository that appears locked by a process that no longer exists.

### 5.4 Conformance before outcomes

When a model, pipeline or analysis produces a surprising result, check that the implementation does
what its own specification says before treating the surprise as information.

Keep a checks file stating, for each postulate, the observable signature a correct implementation
produces and what a violation would look like. Run it before reading any result and report it first.
A failed check invalidates everything downstream of it: say so and stop, rather than reporting both
and leaving the reader to work out which numbers survive.

The companion rule: **never assert behaviour from appearance.** A screenshot tests whether something
renders and reads. Behaviour is asserted from the system's own data — verification ends at the stored
record, not the rendered page.

The expensive failure is not being wrong. It is being wrong in a way that looks like a finding.

### 5.5 Two smaller rules that pay for themselves

**Provenance travels with the claim.** When a claim will be quoted away from its source, mark on the
claim itself what may be said about it in public — original work, transposed from another field,
derived from a source that described rather than prescribed. A row that carries its own provenance
survives being copied into a slide.

**Retire in the naming, keep the context addressable.** When a tool is retired but its surrounding
context is not, rename rather than delete, leave a compatibility pointer at the old location, and mark
the files dormant. Documentation describing a surface no longer in use is worse than no documentation,
because it sends a fresh session down a path that does not exist — but the context around a retired
experiment is usually the part that had the value.

---

## Part 6 — Adopting it

The whole system is more than anyone needs on day one. Here is the order that front-loads the value.

**The first hour.**
1. Split your always-loaded file. Move project state, per-language conventions and source lists into
   `docs/` and `projects/`, leaving the stance, the conventions and a map of where things are.
2. Write `docs/memory-layers.md` from the skeleton in this kit — the four types, and where each one
   lands in *your* setup. Half an hour, and it is the file everything else refers to.
3. Start `projects/INDEX.md`, one line per active project.

**The first week.**
4. Start `logs/decisions.md` with the next real decision you make. Do not backfill; the log earns its
   authority by being contemporaneous.
5. Do one closeout at the end of one session, by hand, following §4.1. It will feel slow once and
   obvious thereafter.
6. Move one project's context out of wherever it currently lives and into its project folder, leaving
   a pointer behind. Notice how much was duplicated.

**The first month.**
7. Add the weekly hygiene pass. Even by hand it takes fifteen minutes; scripted, it takes one.
8. Adopt the documentation register, and add the monthly scan once you have enough guidance prose for
   drift to be a real risk.
9. Write your first template, at the moment you notice you are writing the same document shape a
   third time.

**The minimum viable version**, if you adopt nothing else: the four content types, the always-loaded
budget with a number attached, and a decisions log with *alternatives considered* in it. Those three
carry most of the benefit.

---

## Part 7 — What it costs, and what it does not do

**A ritual on paper is a claim, not a practice.** Everything in Part 4 is easy to write down and
genuinely hard to keep doing. Be honest with yourself about which of the three you have actually run,
and how many times — a defined-but-unpractised ritual reads exactly like a working one in a document,
and only the dated artefacts it should have produced tell the difference. If a ritual has produced no
artefacts, it is a plan.

**It costs discipline at exactly the moment you have least of it** — the end of a session, when the
work is done and you want to stop. That is why the closeout is a named ritual with a defined shape
rather than a good intention, and why an automatic backstop is worth having where the platform
supports one.

**It does not survive being enforced by an agent alone.** Promotion is human-involved by design. An
agent that promotes silently will fill the always-loaded tier with plausible material within a month,
and the material will be individually defensible and collectively fatal.

**It does not replace a conversation with a colleague.** The shared destination reaches people, and
that is the point of §3.4 — but a file is a poor substitute for telling someone.

**It has a floor below which it is not worth it.** One project, one surface, a few weeks: keep a
README and skip all of this. The system earns its cost when several projects run in parallel, or
several surfaces read the same context, or the horizon is long enough that you will have forgotten
your own reasoning.

**And it can itself drift.** The registers can disagree with the disk, the audit's collection can
outgrow its stated scope, the taxonomy can end up duplicated in two files that then age apart. That is
why the checks are dated, kept, and pointed at the system as well as the work. A check that reports
nothing new every week is not evidence that all is well; it is a reason to look at the check.

---

## Deploying it to a team

Everything above is written for one person's workspace, and a person can adopt it by copying files.
A team needs more than that: one always-loaded file that every person *and* every agent surface reads,
a rule for how the shared layer and each person's own layer are arbitrated, a review path for the
always-loaded tier, and — for a pilot — a way to show afterwards what changed.

`install.sh` lays all of that down in one command, into the team's shared repository:

```bash
./install.sh --target ../team-workspace --init \
  --team "Data Platform" --owner "Sam" --owner-handle "@sam" --pilot
```

- **`AGENTS.md` is the one manifest.** Claude Code reads it through a one-line `CLAUDE.md` import;
  Gemini CLI through `.gemini/settings.json`. Tools that look for `AGENTS.md` by convention find it
  directly. The file is portable even where a filename is not.
- **§1 becomes a team rather than a person**, with a named standards owner and the arbitration rule:
  the team layer governs whatever touches someone else's work, the personal layer governs your own
  sessions, and a personal practice reaches the team by pull request.
- **The closeout plugin is wired in**, vendored by default so it is pinned, reviewable by a security
  team, and installed without network access. `.claude/closeout.md` points it at
  `docs/memory-layers.md`, so there is one taxonomy in the repository rather than the plugin's and
  the kit's side by side. Gemini CLI gets `/closeout` as a command — the live ritual, without the
  backstop, which is the honest version of §4.1.
- **`--pilot` adds `pilot/`**: a protocol, the team's own build list as the primary measure, and a
  script that reads every other number from git history — counts only, safe to share outside the team.

It never overwrites a file; a differing one gets the kit's version beside it as `.kit-incoming`.
Settings JSON is merged additively. Running it twice is safe.

What it does not do: install into the team's code repositories. The pilot is one shared workspace
repository; carrying the practice into code repositories — the plugin alone is one command there — is
the step after the pilot shows it is used.

## The files in this kit

| File | What it is |
|---|---|
| `MANIFEST.md` | Skeleton for the always-loaded file — stance, conventions, map, log formats |
| `docs/memory-layers.md` | The taxonomy: four types, two axes, precedence, budget, promotion |
| `docs/workspace-map.md` | Canonical-fact table and the conventions for where new files go |
| `docs/documentation-register.md` | The register rule, the translation table, and how to scan for drift |
| `rituals/closeout.md` | The end-of-session pass, as a procedure an agent can follow |
| `rituals/weekly-hygiene.md` | The weekly placement-and-budget pass |
| `templates/project-decisions.md` | Per-project decisions log skeleton |
| `templates/project-readme.md` | Per-project README skeleton |
| `templates/person-profile.md` | One file per person: what they own, and when to go to them |
| `plugins/closeout/` | The closeout ritual as a Claude Code plugin — `/closeout` plus the end-of-session backstop |
| `install.sh` | Deploys the kit into a team repository, with the closeout plugin, surface shims and pilot layer |
| `team/` | The installer's team overlay — see `team/README.md` |
| `pilot/` | Pilot protocol, build-list ledger and `measure.sh` |

Every one is a starting point rather than a standard. The system works because the conventions match
the work, and yours will differ.

**The plugin on its own**, in any Claude Code repository, without the rest of the kit — it is
published standalone at `github.com/cyberscribe/closeout-plugin`:

```
/plugin marketplace add cyberscribe/closeout-plugin
/plugin install closeout@closeout-marketplace
```

`plugins/closeout/` is the source of truth; the standalone repository is a mirror of it, published
with `git subtree push --prefix=plugins/closeout closeout main` (where `closeout` is a remote for
`closeout-plugin`). Edit here, then push the subtree — an edit made directly in the standalone
repository has to be pulled back with `git subtree pull` before the next push.

## Licence

Code (the installer, `pilot/measure.sh`, the plugin) is MIT. The writing — this README, `docs/`,
`rituals/`, `templates/` and the rest of the prose — is CC BY 4.0: use and adapt it freely, including
commercially, with credit. See `LICENSE`.

Maintained as used: this kit runs the author's own workspace daily, and changes land when that
workspace teaches something. Issues are read; there is no support commitment.

---

*Version 1.2 — 2026-09-28: team deployment and pilot layer added (see CHANGELOG). Version 1.1 — 2026-09-04. Revised after auditing the workspace it was extracted from against its own
claims: the manifest split needs maintaining (§2.1), a canonical-fact table does not enforce itself
(§2.2), rituals want checking against the set that already exists (§4.4), audit trails belong in
version control (§4.2), and a ritual that has produced no artefacts is a plan (Part 7).*
