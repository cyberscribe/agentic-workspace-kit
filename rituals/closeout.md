# Closeout

*The end-of-session pass: promote what this session learned into durable documentation, before it
evaporates.*

> Written as a procedure an agent can follow. Where your surface supports packaged procedures — a
> skill, a saved command, a slash command — this is the content to put in one, so it can be invoked
> in three words rather than re-explained.

---

## Why this exists

Sessions end and their learnings evaporate. The decision made, the constraint discovered, the
approach that turned out not to work — all of it lives in a transcript nobody will read again.

The habit that fixes it is asking the agent to review what it learned and update the docs before
closing. The habit works. People forget it. That is the entire problem, and it is why this is a named
ritual with a defined shape rather than a good intention.

## What counts as a learning

**A learning is worth recording if a future session would otherwise re-derive it.**

Working code and finished deliverables are not learnings — they are the work, and they are already
saved. The *constraint that shaped them* is the learning. So are: a decision and the option it beat, a
behaviour of a tool that is not in its documentation, a correction to something previously believed, a
boundary that turned out to matter.

## The pass

### 1. Review

What was learned, decided, corrected or discovered this session?

### 2. Classify before writing

Two axes, from `docs/memory-layers.md`. **Tier** — working standards, general reference, project
reference, or template — decides how often it is loaded back. **Scope** — shared or individual —
decides who it reaches.

Default to the cheapest tier that works. Most things are project reference.

**Promotion into the always-loaded tier is zero-sum.** Every future session pays for it. Name what it
displaces, or make the case that the budget should grow, and get a human to agree. Every other tier is
additive and needs no such justification.

**A learning others need is worthless in an individual store.** Prefer the committed destination.

### 3. Verify before recording

Check each technical claim against the current state of the code or file. A behaviour that changed
during this session is not a finding, and a claim recorded from memory of what happened two hours ago
is how a wrong fact gets a permanent home.

One summarised page-fetch is not verification either.

Where the team has written down what counts as checked — a verification standard, `docs/verification.md`
by default — check each item to the row for its kind of work, and say what evidence was kept. Something
that cannot yet meet that standard is recorded as unverified, with what is missing, or left out.

### 4. Propose, then apply

Surgical updates: the line that changed, not a rewrite of the file around it.

Apply what is mechanical and uncontested. Bring back as a proposal anything that changes what loads
every session, anything that is a judgement call about voice or framing, and any file the workspace
has fenced from agent editing.

Nothing is deleted. Superseded material is marked superseded, keeps its name and wording, and carries
a pointer to what replaced it.

### 5. Reconcile tracking — separately, and after

Context and tracking are different axes. Promote learnings first, then confirm that task and status
files reflect reality, and release any locks or claims this session holds. Where the project README
has a **Done when** list, tick what this session completed and say in a line how far the project is
from its finish line; when every box is ticked, propose closing the project, which is its own
ritual with its own evidence walk. Report the two separately; merging them is how the ritual decays
into a status update.

Where the README has a **Current state** block, bring it up to date: the **State** changed only when
it plainly moved (`ready`, `doing`, `blocked`, `paused`, `done`), with pausing and finishing left to
the person; a **Blocked by** line — what, and since which date — set when the work cannot move until
something outside it happens, and removed once that clears; `Updated:` to today's date; and a dated
line saying where the work stands, added when the block has none and otherwise rewritten rather than
added to. A block still marked as a proposal keeps its marker: confirming it is the person's.

### 6. Who needs to know — when the project has more than one person

*Optional. It applies when the project names two or more people: profiles in the people directory
(`memory/people/`), a People or Team section in the project's README or in the local closeout
conventions, or an explicit team list in the configuration. With one person or none, skip it without
comment.*

Where the project README's People section gives roles, the roles do most of the choosing: whoever
**owns** the outcome and whoever is to be **kept told** hear about progress on it — a criterion
ticked, the finish line reached or moved, ownership changing, the project now blocked; whoever is to be **asked
first** hears about decisions not yet taken — a proposal left open, a criterion someone wants to
change or waive — before the decision rather than after it; and whoever **does** or **helps** hears
where their own work is affected.

Promotion decides where a learning is kept. This step decides who should hear about it now — because a
file that changed without anyone knowing reaches nobody until they happen to open it. It is the other
half of the visibility rule.

For each item promoted or proposed, ask whether a specific person's work is affected: they own the
area it touches, a decision changes what they are doing, it blocks or unblocks them, or their profile
says they are the one to go to for it. The output is a short table:

| Who | What they need to know | Why them | Where it is recorded |
|---|---|---|---|
| <name> | <one line> | <owns / keep told / ask first / blocked by / go-to for> | `<path it was promoted to>` |

- **Name someone only with a reason.** "Nobody in particular" is a common and correct answer; say it
  in one line.
- **If everyone needs to know, it may be a working standard** rather than a broadcast. Raise it as a
  promotion question instead.
- **Point rather than restate.** The message is the pointer to where the learning now lives, so the
  record stays single and the note stays short.
- **Nothing is sent.** A message to a colleague goes out in a person's own voice, from them. Draft one
  only when asked.
- **An unknown owner is a finding.** If the right person cannot be named, that is a gap in the people
  directory worth filling.
- **The table stays out of the repository.** It is communication, not context or tracking, and it is
  stale the moment it has been read.

### 7. Report

- What was promoted, and at which tier.
- What is proposed and still needs a decision.
- Tracking, apart from the learnings: boxes ticked, distance to the finish line, the new state and
  any blocker.
- Who needs to know what, if step 6 applied.
- Which files were touched, new against modified.
- Anything left unfinished.

Leave the commit to the human. The agent's part is to stage what it touched, by name, and summarise
the change; the person committing writes the message, and writing it is their check that they
understand what changed. A broad staging command sweeps unrelated in-flight work into it.

## The backstop

Some agent harnesses expose session lifecycle hooks. Where yours does, the pattern is: on session end,
a detached headless agent reads the transcript and writes candidate notes to a draft outside the
repository; on the next session in that project, the agent surfaces the draft and offers to promote
it — confirming the tier, verifying each claim against current code, then promoting and deleting the
draft, only with a human's go-ahead.

That backstop is a net under the sessions where the ritual was skipped. It is not a replacement for
doing it live, which is the higher-quality path because the context is still there.

**Where your surface has no hooks, or no readable transcript, say so plainly rather than building a
lookalike.** A backstop that catches nothing is worse than a known gap, because people stop watching
for the thing it was supposed to catch. The compensating moves:

- Have the agent **offer** the pass when a session has produced a decision or a constraint, rather
  than waiting to be asked.
- When a promotion cannot be finished, leave a draft wherever a later session will look, and have the
  weekly pass report drafts left waiting.

*A hook-based implementation for Claude Code ships with this kit at `plugins/closeout/`. The pattern
matters more than the tool.*

## Whether you are actually running it

This is the ritual most likely to exist only on paper, because it costs attention at the moment the
work is finished and the attention is gone. The check is artefacts: closeouts leave dated entries and
touched files behind. If a month of sessions has produced none, the ritual is a plan rather than a
practice, and the honest response is either to run it or to say plainly that promotion here happens
inside the work instead.

## Local conventions

Where a workspace has its own tiers, destinations or house rules, keep them in one file that this
procedure defers to — and have that file *point at* the taxonomy rather than restating it. Two copies
of a tier table drift silently, because both look authoritative.

A person can keep a second, personal layer above every repository they work in — an extra destination
of their own, a house rule, a line they want in every report. It is read after the repository's file,
and where the two disagree the repository's wins: a team's conventions are not overridden by one
member's habits. Where the repository's file is silent, the personal one stands over the defaults.
(The Claude Code plugin reads it from `~/.claude/closeout.md`.)
