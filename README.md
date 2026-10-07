# A Workspace That Keeps Its Context

*A working system for collaborating with AI agents over long horizons, across many projects at once.
It is a filesystem layout, four content types, a tracking axis kept in each project's README, three
human-in-the-loop rituals, and two small checks.
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

![The four content types held twice — shared and individual — on the human side, loaded automatically into the session loop on the AI side, and promoted back out by a human. Tracking runs on its own axis.](docs/images/context-taxonomy.svg)

*The whole model on one page: context types on the left, colour-keyed wherever the same thing is held
twice; tracking on its own axis in the middle; the session loop on the right, loaded automatically and
promoted from with a human in the loop.*

Note what the fourth type buys you. An agent role definition, a review checklist and a decisions-log
skeleton have nothing in common as documents, and everything in common as *things you deploy when a
category of work starts*. Naming that category stops each one being reinvented per project.

### 1.3 Tracking is not context

Task lists, project status, columns on a board, who is doing what this week: these are state, not
knowledge. They get **reconciled**, not promoted. Keeping the two on separate axes is what stops an
end-of-session knowledge pass turning into a status meeting, and it is the single most common way
these rituals decay into theatre.

Tracking still needs a home, or it leaks into the context files. Here it has two. Each project's
README carries a **Current state** block under its Desired outcome and **Done when** checklist: the
state (ready, doing, blocked, paused or done), what blocks it and since when, how often it is checked
in on, when it was last updated, and one dated line saying where it stands. An optional **Planned**
list after it holds the steps foreseen from there, in order. The register lists every project with
its state and owner. Three moments keep them true: the closeout brings the Current state block up to
date at the end of a session, a board reads every block on demand and flags what needs a look, and a
close ticks each Done-when box against evidence before a project is marked done. None of the three
writes to the context tiers.

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
  CLAUDE.md              ← the always-loaded file; its first line imports the kit's standards
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

The folder holds a `README.md` saying what, why, when it is done (the Done when checklist), where it
stands now (the Current state block, §1.3) and what is still open. When a project starts making
decisions worth preserving, it gets a `decisions.md` from the template.

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
6. **Who needs to know** — optional, and only when the project names more than one person. A
   `Who needs to know: auto | ask | off` line in `.claude/closeout.md` sets it, and a team roster
   (`templates/team-roster.md`) seeds it; each row offers a draft, a note or nothing, and nothing is
   sent. For each item, name a teammate only where their work is affected, point at where the learning
   now lives, and send nothing: a message to a colleague goes out in a person's own voice. "Nobody in particular" is
   a common answer; "everybody" is a sign the item may be a working standard instead.
7. **Report**: what was promoted and at which tier, what is proposed and waiting, who needs to know,
   which files were touched.

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
- anything the previous rituals left pending;
- session drafts the closeout backstop left behind, oldest first, each with a proposal to promote,
  clear or leave.

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
scheduled pass already covered part of the same ground. It surfaced two hours later, in an audit.

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

`kit/setup.sh` lays all of that down, with the kit as a submodule of the team's private repository at
`kit/`, read in place. There are two ways to start, and both end in the same workspace:

**From the template repository.** On GitHub, choose *Use this template* on
`cyberscribe/agentic-workspace-template` and pick Private. A fork of a public repository cannot be
made private, so the template is used, not forked. Then clone it with its submodule and run setup:

```bash
git clone --recurse-submodules <your private repository URL> team-workspace
cd team-workspace && kit/setup.sh --team "Data Platform" --owner "Sam" --owner-handle "@sam" --pilot
```

**With `setup.sh new`.** Clone the kit anywhere, and let it start the workspace in a new folder, with
no GitHub needed. Add a private remote as `origin` later, and run `kit/setup.sh` again to confirm it:

```bash
git clone https://github.com/cyberscribe/agentic-workspace-kit.git agentic-workspace-kit
bash agentic-workspace-kit/setup.sh new team-workspace --team "Data Platform" --owner "Sam" --owner-handle "@sam" --pilot
```

Either way, setup runs the same ten stages, changes nothing it has already done when run again, and
commits nothing: it ends by printing the commit to make. `docs/setup.md` describes each stage and mode.

- **`CLAUDE.md` is the team's always-loaded file.** Its first line, `@kit/CLAUDE.kit.md`, imports the
  kit's working standards, which update with the kit; everything below it is the team's own and wins
  where the two differ. `AGENTS.md` routes tools that look for that name to the same two files.
- **The kit is read in place, not copied.** The plugins, rituals, docs and project templates stay in
  `kit/`; `kit/setup.sh update` advances the kit and offers any change to a file the team owns as a
  diff to apply or skip. Files the team owns are created once and never overwritten.
- **Three plugins, ten commands, are wired in** from the directory marketplace at `kit`:
  - **closeout** — `/closeout` and the end-of-session backstop. `.claude/closeout.md` points it at
    `kit/docs/memory-layers.md`, so there is one taxonomy.
  - **projects** — `/projects:new`, `adopt`, `board`, `hold`, `close` and `pickup`, the life of a
    project from its first interview to done, kept in each project's README, with a session-start
    line that says where the folder's project stands. `.claude/projects.md` holds the team's own
    conventions.
  - **workspace** — `/workspace:quick-start`, the first-time interview and the door into the kit;
    `/workspace:hygiene`, the weekly tidy; `/workspace:register-audit`, the monthly register check;
    and a session-start summary of what is out of step.
- **Git hooks keep the workspace private and the kit clean.** `kit/setup.sh hooks` sets them in the
  workspace, the kit and each project repository. A hook the person already had runs after the kit's.
- **`kit/setup.sh skills` writes one `kit-` skill per command** into `.claude/skills/`, beside the
  team's own skills, for surfaces that load skills rather than plugins, such as Cowork.
- **`--pilot` adds `pilot/build-list.md`**; the protocol and `kit/pilot/measure.sh` stay in the kit,
  and the script reads every other number from git history — counts only, safe to share outside the
  team.

A 2.x workspace moves to this layout with `kit/setup.sh migrate --dry-run`, then without
`--dry-run`; `docs/migration.md` describes it.

The scripts run under macOS's own `/bin/bash` (3.2). That bash ignores `TMPDIR` for a here-document's
temporary file and tries `/var/tmp`, then `/tmp`, then the current folder. In a sandbox where neither
of the first two is writable, such as an agent's, the file lands for a moment in the folder the script
was started from, and in a read-only folder the script stops. Start the scripts from a writable
folder there, or with a newer bash first on `PATH`.

What it does not do: install into the team's code repositories. The pilot is one shared workspace
repository; carrying the practice into code repositories — the plugin alone is one command there — is
the step after the pilot shows it is used.

### The first run: `/workspace:quick-start`

The installer lays files down; the quick-start makes them the team's own. It reads the repository
before asking anything, decides which of three modes it is in, and says so in two lines:

- **Fresh** — the always-loaded file still has stand-ins. The team part, ideally with the standards
  owner (the team, its rules, how projects run here, what counts as checked), then the personal part.
  Where an earlier run already answered something, it asks only what is still open.
- **Joining** — the team part is done and this person has no profile yet. The personal part only:
  their profile (what they own, when to come to them), their own in-flight limit, how they like an
  agent to work with them. The team's staleness setting and metrics are read, not asked again.
- **Existing system** — a system was here first: its own always-loaded file, a register with other
  section names, its own closeout, board or hygiene skill. The kit adopts rather than installs. It
  proposes a mapping — their file for the kit's, their section names for the kit's — writes it into
  `.claude/projects.md` and `.claude/closeout.md` only on a yes, runs `/projects:adopt draft` over
  their projects, and folds their overlapping skills into the kit's commands instead of running two.

When everything is already set up it says so. Every mode ends the same way, by making sure the kit
is reachable and running: the commands on every surface the person uses, checked in the folder their
desktop assistant actually loads skills from; the session-start line checked in one project folder;
a metrics baseline once there is history to read; and one real piece of work in one real project.
Each step is offered, shown, and taken or declined. The close names the first thing to do and leaves
the commit to them.

### Tracking, day to day

The **projects** plugin keeps the §1.3 tracking axis, one command per moment:

| When | Command | What it does |
|---|---|---|
| Starting | `/projects:new`, `/projects:adopt` | A short interview for the Desired outcome, Done when, Current state and People; or, for a project that already exists, only the sections it is missing, with an older status block offered for conversion |
| Opening a session | *(session-start line)* | Inside a project folder: outcome, Done-when progress, and the state with its owner and anything blocking it |
| Any time | `/projects:board` | Every project in flight, grouped by state, with one-line flags: no owner, no Done when, a stale `Updated:`, blocked for more than 14 days, someone over their in-flight limit, the register out of step, adopt proposals unconfirmed, a project ready to close |
| End of a session | `/closeout` | Learnings promoted; Done when and the Current state block brought up to date, reported apart |
| Handing over | `/projects:pickup` | A cold-start brief for whoever takes the project on |
| Finishing | `/projects:close` | Each Done-when box checked against the verification standard, a short retrospective, the register row moved to Done |

The **workspace** plugin holds the upkeep: `/workspace:hygiene` weekly and `/workspace:register-audit`
monthly, each running its ritual from `rituals/`. On a surface without session hooks, each skill's
description says when to offer it unprompted: the board when someone asks where the work stands, a project's
own line when a session opens in its folder, the closeout near the end of a session that decided
something.

### Commands and hooks, one page each

Each command and hook has a page in `docs/`, in the same four parts: what it does, when to reach for
it, common questions, and how to tell it is working.

| Command | Plugin | For | Page |
|---|---|---|---|
| `/closeout` | closeout | The end of a working session: learnings promoted, tracking reconciled | [docs/commands/closeout.md](docs/commands/closeout.md) |
| `/projects:new` | projects | Starting a project with a checkable finish line | [docs/commands/projects-new.md](docs/commands/projects-new.md) |
| `/projects:adopt` | projects | A project that already exists, or a change to how one is versioned | [docs/commands/projects-adopt.md](docs/commands/projects-adopt.md) |
| `/projects:board` | projects | Every project in flight on one page, with flags | [docs/commands/projects-board.md](docs/commands/projects-board.md) |
| `/projects:hold` | projects | Pausing a project with its reason and a look-again date | [docs/commands/projects-hold.md](docs/commands/projects-hold.md) |
| `/projects:pickup` | projects | A cold-start brief, and resuming a paused project | [docs/commands/projects-pickup.md](docs/commands/projects-pickup.md) |
| `/projects:close` | projects | Finishing: evidence, retrospective, archive | [docs/commands/projects-close.md](docs/commands/projects-close.md) |
| `/workspace:quick-start` | workspace | The first-time interview, and the check that the kit is reachable | [docs/commands/workspace-quick-start.md](docs/commands/workspace-quick-start.md) |
| `/workspace:hygiene` | workspace | The weekly pass over where context lives | [docs/commands/workspace-hygiene.md](docs/commands/workspace-hygiene.md) |
| `/workspace:register-audit` | workspace | The monthly pass over how guidance reads | [docs/commands/workspace-register-audit.md](docs/commands/workspace-register-audit.md) |

The hooks: the closeout plugin's [closeout-capture](docs/hooks/closeout-capture.md) and
[closeout-review](docs/hooks/closeout-review.md); the projects plugin's
[session-start line](docs/hooks/projects-session-start.md); the workspace plugin's
[session-start summary](docs/hooks/workspace-session-start.md) and
[git guard](docs/hooks/workspace-guard-git.md); and the git hooks in `githooks/`,
[pre-commit](docs/hooks/pre-commit.md), [pre-merge-commit](docs/hooks/pre-merge-commit.md),
[commit-msg](docs/hooks/commit-msg.md) and [pre-push](docs/hooks/pre-push.md).

## The files in this kit

| File | What it is |
|---|---|
| `CLAUDE.kit.md` | The kit's working standards — stance, conventions, map, log formats — imported by the first line of a workspace's `CLAUDE.md` |
| `docs/memory-layers.md` | The taxonomy: four types, two axes, precedence, budget, promotion; §3 pre-filled for a team sharing one repository |
| `docs/documentation-register.md` | The register rule, the translation table, and how to scan for drift |
| `rituals/closeout.md` | The end-of-session pass, as a procedure an agent can follow |
| `rituals/weekly-hygiene.md` | The weekly placement-and-budget pass |
| `templates/project-decisions.md` | Per-project decisions log skeleton |
| `templates/project-readme.md` | Per-project README skeleton |
| `templates/person-profile.md` | One file per person: what they own, and when to go to them |
| `templates/verification-standard.md` | What counts as checked, per kind of work |
| `templates/catalogue.md` | What the team has built and would reuse |
| `templates/team-roster.md` | The team roster, copied to `team/people.md`: each person's default relationship to the work and how they like to hear, by handle only; seeds the closeout's "who needs to know" step |
| `plugins/closeout/` | The closeout ritual as a Claude Code plugin — `/closeout` plus the end-of-session backstop |
| `plugins/projects/` | Projects from start to done — six commands and a session-start line |
| `plugins/workspace/` | `/workspace:quick-start`, `/workspace:hygiene`, `/workspace:register-audit`, `bin/state.sh` (the read-only state check), the session-start summary and the git guard |
| `setup.sh` | The guided setup: ten stages, and `new`, `update`, `--developer`, `link`, `hooks`, `skills` and `migrate` |
| `install.sh` | The engine setup runs: creates the files a workspace owns, once, and records them in `.claude/kit-templates.lock` |
| `lib/` | The shared shell library and the scripts behind setup's subcommands (`lib/setup/`) |
| `githooks/`, `scripts/check-paths.sh` | The git hooks and the one checker of paths and content they, and CI, run |
| `scripts/skills-bridge.sh`, `scripts/build-template.sh` | The skills bridge, and the builder of the template repository |
| `docs/migration.md` | Moving a 2.x workspace to the 3.0 layout, and the map file format |
| `docs/setup.md` | `kit/setup.sh`: the ten stages and every mode |
| `docs/commands/`, `docs/hooks/` | One page per command and per hook, in four parts: what it does, when to reach for it, common questions, how to tell it is working |
| `CONTRIBUTING.md` | Changing the kit: fork it, point the workspace's `kit/` at the fork, commit there, and open a pull request; running the tests and shellcheck |
| `templates/workspace/` | The files a workspace starts from and then owns — see the table below |
| `pilot/` | Pilot protocol, build-list ledger, `measure.sh`, and `ablate.sh` for context ablations (run from the kit checkout with `--target`; not copied into a team's repository) |
| `tests/run.sh` | The kit's own checks: installs, hooks, metrics, and the vocabulary and register rules — `bash tests/run.sh` |

The files in `templates/workspace/` are sources for the installer, not files to copy by hand. Each lands
once in the workspace and is the workspace's from then on:

| File | Lands at | What it does |
|---|---|---|
| `CLAUDE.md` | `CLAUDE.md` | The team's always-loaded file: who the team is, its standards owner, and the rule that arbitrates the team layer against each person's own |
| `workspace-map.md` | `docs/workspace-map.md` | The workspace's canonical-fact table and the conventions for where new files go |
| `AGENTS.md` | `AGENTS.md` | A router: the kit's standards, then the team's `CLAUDE.md` |
| `README.md` | `README.md` | The workspace's own README, opening with how it started |
| `workspace.md` | `.claude/workspace.md` | Confirmed private remotes, published public ones, the private word list, and the skills the bridge leaves out |
| `INDEX.md`, `decisions.md`, `glossary.md`, `people-README.md`, `audits-README.md` | `projects/INDEX.md`, `logs/decisions.md`, `memory/glossary.md`, `memory/people/README.md`, `audits/README.md` | The register, the decisions log, the glossary and the starting notes for people and audits |
| `stay-private.yml` | `.github/workflows/stay-private.yml` | Fails a push when the workspace repository is public (a repository marked as a template, as the published one is, is skipped) |
| `closeout.md` | `.claude/closeout.md` | Points the closeout plugin (and the `kit-closeout` skill) at `kit/docs/memory-layers.md`, so there is one taxonomy rather than two |
| `projects.md` | `.claude/projects.md` | The team's project conventions — where projects live, register sections, naming, in-flight limit, staleness — read first by every projects command |
| `settings.json` | `.claude/settings.json` | Registers the kit's directory marketplace at `kit` and enables its closeout, projects and workspace plugins; asks before an agent edits `kit/` or `.claude/workspace.md`; lets the agent delete a promoted draft |
| `gemini-settings.json` | `.gemini/settings.json` (merged) | With `--surfaces claude,gemini` only: makes Gemini CLI load `AGENTS.md` as its context file |
| `CODEOWNERS` | `.github/CODEOWNERS` | Routes changes to the always-loaded tier through the standards owner |
| `pull_request_template.md` | `.github/pull_request_template.md` | Asks a documentation PR which tier it touches, and what it displaces |

`templates/workspace.gitignore` becomes the workspace's `.gitignore`; a later kit's new lines are
offered by `kit/setup.sh update`, and none is removed.

Commands for other surfaces are generated, not kept here: `kit/setup.sh skills` writes a thin form of
each `plugins/<plugin>/commands/<command>.md` as a `kit-` skill, and `install.sh --surfaces
claude,gemini` writes a Gemini CLI wrapper, so each procedure has one source.

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

Code (the installer, the `pilot/` scripts, the plugins, `tests/`) is MIT. The writing — this README, `docs/`,
`rituals/`, `templates/` and the rest of the prose — is CC BY 4.0: use and adapt it freely, including
commercially, with credit. See `LICENSE`.

Maintained as used: this kit runs the author's own workspace daily, and changes land when that
workspace teaches something. Issues are read; there is no support commitment.

---

*Version 3.0 — 2026-09-30: the kit is a submodule of the workspace at `kit/`, read in place; setup,
the engine and the migration; git hooks for privacy; versioning, sensitivity and resources for
projects; the skills bridge (see CHANGELOG). Version 2.2 — 2026-09-29: context ablations, the state check, a validation gate, a lighter
quick-start and closeout, and a who-needs-to-know setting with a team roster (see CHANGELOG).
Version 2.1 — 2026-09-29: the Current state block, Planned and five project states; nine commands
across three plugins (see CHANGELOG). Version 2.0 — 2026-09-29: the tracking axis, skills, and the
quick-start's three modes. Version 1.2 — 2026-09-28: team deployment and pilot layer added. Version 1.1 — 2026-09-04. Revised after auditing the workspace it was extracted from against its own
claims: the manifest split needs maintaining (§2.1), a canonical-fact table does not enforce itself
(§2.2), rituals want checking against the set that already exists (§4.4), audit trails belong in
version control (§4.2), and a ritual that has produced no artefacts is a plan (Part 7).*
