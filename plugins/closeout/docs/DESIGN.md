# Design notes

Background for anyone modifying the plugin. The README covers use; this covers
why it is shaped the way it is.

## The constraint that determines the architecture

Claude Code hooks differ in one decisive way: whether their output reaches an
active agent.

| Hook | Fires | Can inject context? |
|---|---|---|
| `SessionStart` | before the agent loop | **yes** (`additionalContext`) |
| `UserPromptSubmit` | before each turn | **yes** |
| `SessionEnd`, `PreCompact` | after the agent loop has exited | **no** |

Capture has to happen at session end — that is when the transcript is complete.
But nothing at session end can talk to an agent, because there is no longer an
agent. So capture spawns its own headless `claude -p`, and the *result* is
surfaced one session later through `SessionStart`, the earliest point where
injection is possible again.

Everything else follows from that split: the draft file exists because capture
and review happen in different processes, hours or days apart.

## Why drafts live outside the repo

`~/.claude/closeout-drafts/<project-basename>/<session-id>.md`

- Never committed by accident — a half-formed automated note is not team content.
- Per-user: your forgotten sessions are your business.
- Survives reboots, unlike `/tmp`.
- Keyed by project so a draft only nudges in the repo it came from.

The cost is that the directory sits outside a sandboxed session's writable set,
which is why the README asks for an `allowWrite` entry: otherwise the agent can
read a draft and promote it but never delete it, and the same draft nudges
forever. `closeout-review.sh` runs unsandboxed and prunes drafts past the
retention window as a backstop. Retention counts from the first session that
surfaced the draft, recorded by a `.seen.<draft>` marker, never from capture time:
a draft written before a week away is still waiting after it, and only a draft
that has been offered and left for the window is pruned.

## The sentinel handshake

`/closeout` and the capture hook can both fire for the same session. If both run,
the draft duplicates work the agent already did properly, with full context —
strictly worse output, and it nags on the next session.

So `/closeout` writes `.closeout-ran.<session-id>` into the draft directory, and
the capture hook consumes exactly the sentinel matching the ending session, then
skips.

**Keying by session id, not project, is load-bearing.** An earlier version used a
single bare `.closeout-ran` per project. With concurrent sessions or git
worktrees, the first session to end consumed the shared sentinel and every other
session wrote a spurious draft. Per-session keying means a closeout in one session
suppresses only that session's capture; the others keep their safety net.

A sentinel older than 6h is cleared but **not** honored, so a closeout followed by
a long-running session can never mute captures indefinitely.

## Blast radius of the capture child

The child is an unattended agent run triggered by exiting a session. That deserves
tight bounds:

- `--allowedTools "Read,Grep,Write"` — no Bash, no network. Grep reads nothing Read
  cannot already reach; it lets the child search the transcript for a later mention
  of the same subject without paging through it.
- It runs from the draft directory, so writes to the repository fall outside the
  directories `acceptEdits` approves unprompted, and a headless run has nobody to
  approve them. `--add-dir` adds to the working directory rather than
  restricting it; spawned from the project, the whole repo would be approved.
- The transcript's directory is the one grant beyond the draft directory. It
  holds the project's other transcripts and, for Claude Code, its `memory/`
  folder; the child is prompted to write only its scratch file, and that part of
  the bound is prompt-enforced.
- The review hook exits at once inside the child (`CLOSEOUT_HOOK_CHILD`), so the
  child is never told to surface drafts to a user it does not have.
- `--permission-mode acceptEdits` — scoped by the working directory above; the
  transcript-directory write is prompt-enforced.
- It starts without the ending session's identity. A session inside a pairing
  carries `PAIR_*` (its role and mailbox), and every Claude Code session carries
  its own id and messaging variables (`CLAUDECODE`, `CLAUDE_CODE_SESSION_ID` and
  the rest). Inherited, they made a child act as the pairing's engineer: it took
  the mailbox's nudge meant for the live session. The hook drops them, as the
  leave-out test runner does, and sets `AW_HEADLESS_RUN=1`, which quiets the
  session-start lines nobody is there to read.

Promotion into real documentation happens later, interactively, with a human
approving. The unattended half of the system can only ever produce a file in a
scratch directory.

## The recursion guard

The capture child is itself a Claude Code session, so it triggers `SessionEnd` on
exit — which would spawn another child, forever. `CLOSEOUT_HOOK_CHILD=1` is set on
the child's environment and the script early-exits when it sees it.

This is the single most important line in the plugin. Do not remove it.

## Detaching

`setsid nohup … &` is the clean detach, but `setsid` is not on stock macOS (only
via MacPorts or Homebrew) and is frequently missing from the stripped PATH a hook
runs under. `nohup … & disown` is the fallback and survives parent exit on any
POSIX shell. Both are used; presence decides which.

The detach matters for a mundane reason: without it, quitting Claude Code would
block for the 20–40s the child's API call takes.

## Why promotion is tiered

The first version promoted into one undifferentiated bucket: "durable docs". That
answers *is this worth keeping?* and stops there, which is the wrong question to
stop on.

What actually costs something is not storage, it is **load rate**. A note in an
always-loaded file is paid for by every future session in that project, forever,
whether or not it is relevant to the task at hand. A note in a reference file that
loads on demand costs nothing until something asks for it. Those are different
decisions by orders of magnitude, and a flat destination list hides the difference.

So promotion classifies on two axes:

- **Tier** — how often it is loaded back. Four by default: always-loaded working
  standards, cross-project general reference, per-project reference, and templates
  or agent role definitions.
- **Scope** — shared (committed, reaches teammates) or individual (one machine,
  one user). A learning a teammate needs is worthless in an individual destination,
  and this is the axis people get wrong most often.

The rule that makes the taxonomy do work rather than just describe things:
**promotion into the always-loaded tier is bounded.** It updates or condenses
where it can and justifies the growth where it adds; every other tier is additive. Without
that, an always-on file only ever grows — each individual addition is defensible,
the aggregate is not, and nobody is ever in the room where the aggregate is
decided. A capture-and-promote loop makes that erosion faster, not slower, which
is exactly why the loop needs the constraint.

The agent is also told to default to the cheapest tier that works. The bias has to
be explicit, because "put it where it will definitely be seen" is the locally
rational choice every time.

## Leave-out tests, offered at promotion

The budget rule stops the always-loaded tier growing unexamined; it does nothing
about a line already in it. A line promoted there is never retired unless
something tests it. So when a line lands in either of the two most-loaded tiers,
`/closeout` asks what task would go worse without it, and where the repository
runs leave-out tests it drafts one: that task as a prompt, a Check, and the exact lines
just promoted, which a runner later removes to compare a session with the line
against one without it. The question is asked at promotion because that is the
only moment someone knows what the line was for.

It is offered, not required. Required is the stronger discipline, but it adds a
step to every closeout at the point a new team decides whether the ritual is
worth its weight. The offer still does work when it is declined: a person who
cannot name a task that would go worse has said something about the tier, and
the command says so. A leave-out test checks only what its author thought the line was
for, the same limit a unit test has, and a no-difference result proposes a
demotion; it never makes one.

## Checked against the record before promotion

Checking a claim against the files as they are now catches a fact that has gone
stale. It does not catch a session that misremembered itself: a fix believed to
work and later reverted, a cause named before a test showed another. The capture
child and the closing agent both summarise from memory of a long conversation,
and the first plausible line is the one that sticks. Anthropic's write-up of its
agent-memory experiments ("The components of agent memory", November 2026)
reports the cost: in a long game run, an offline pass that checked a wrong
memory note against the session transcript and rewrote it let the run reach a
goal that the run carrying the uncorrected note never reached.

So every candidate is checked against the session's own record before it is
promoted, and gets one of three results. **Supported** may be promoted as fact.
**Contradicted** is promoted as its correction or dropped, and the report says
which. **Unsupported** is never promoted as fact. A contradiction usually sits
later than the claim, in a turn that reverses it, so the check reads the record
to its end and the latest word holds.

The record depends on where the closeout runs:

| Surface | Record | Found by |
|---|---|---|
| `/closeout` in Claude Code | the session's transcript (JSONL) | `CLAUDE_CODE_SESSION_ID`, under `CLAUDE_CONFIG_DIR` or `~/.claude`, in `projects/*/<id>.jsonl` |
| The capture child | the transcript it is given | `transcript_path`; it writes it as the draft's first line, `transcript: <path>` |
| A draft promoted later | that transcript, while it exists | the `transcript:` line, else the draft's name (`<session-id>.md`) |
| A draft whose transcript is gone | the draft's own quotes | the report says so |
| Cowork and other surfaces | the conversation in context | the report says so |

**Evidence travels with the candidate.** Each item carries its `plain:` line,
its `source:`, its result and `evidence: L<n> "<quote>"` lines: a line of the
transcript and a short span copied from it. A contradicted item adds `was:`
(what the record said first) and `correction:` or `dropped:`; an unsupported
one, `missing:`; an already-written one, `found:`. The line number is stable
because a transcript is only appended to, and the quote is what a person
approving the item reads.

**The quoting rule.** The quote runs from the first `"` after `L<n>` to the next
`"` that is not escaped with a backslash, and anything after it is a note. Inside
it, `\"` is a quotation mark, `\\` a backslash, and `\n` or `\t` a line break or a
tab. The study found the rule missing: four of thirteen refused anchors quoted
JSON tool output, whose quotation marks a draft can only write escaped, and a
span across a line break had no way to be written. Whitespace is collapsed on
both sides before the comparison, so a line break and a space compare equal.

**A run's prompt is a turn.** A scheduled or queued run is given its prompt in a
record that is not a user turn: a queue record that enqueues it, or a
`queued_command` attachment. A draft that quotes the task it was given cited a
line the checker called "not a turn", five anchors in the study. Both now count
as the prompt's turn, shown as `(prompt)`; a queued command that is a task
notification is the system speaking, and still does not. For the always-loaded
tier, a prompt counts as words other than the agent's, since a person wrote the
task.

**The always-loaded tier gets the strictest check.** A wrong line there is read
by every session. A line goes there only when it is supported, every cited line
resolves, and at least one is the person's own words or a tool's output. The
agent's own statement that something works is evidence that it believed so; a
test result, or the person deciding, is evidence that it holds. A correction
bound for that tier is restated as its own supported candidate, so it passes the
same check.

**What is checked by script, and what is judged.** `scripts/check-evidence.sh`
is deterministic: the format, each anchor resolving (the line exists, is a turn
of the conversation rather than a hook injection or an attachment, and holds the
quote), who spoke on it, a contradiction's evidence sitting later than what it
reverses, the gate for the always-loaded tier, and the three source rules (a
`plain:` line on every item, no general lesson for the always-loaded tier, a
correction cited in the person's words). Whether an item is otherwise
discoverable, which source it truly has, and whether its plain sentence says
what the record does are the model's judgement, and then the person's. Whether a quote supports its
claim, whether a later turn reverses it, and which result a candidate gets are
the model's judgement, and then the person's. The script proves the evidence is
where it is said to be; it cannot prove the reading. Section 4 of the kit's suite
runs it against a fixture transcript; the judged half has no test.

The review hook names the script rather than running it, which keeps session
start fast. The capture child cannot run it (it has no shell); the next session
does.

## Not otherwise discoverable, and where learnings come from

The kit is there for two things: common ground between the person and the AI, and
context the AI cannot find anywhere else. A model that can read a whole codebase
does not need the codebase written down for it; what it cannot learn by reading
is what only this person or team knows. So one test comes before tier or scope:
**is it otherwise discoverable?** Could a later session find it by itself, in the
code, the files, the docs, `git log` or a tool's own help? If so, it is not
promoted. The draft says `already-written`, with `found:` naming where. The
10 November capture study showed why the answer is worth giving rather than
staying silent: 24 of 40 proposed items were already written, each with the line
that says it, which is evidence that the habits work and costs the person
nothing to approve.

What passes is looked for in an order:

1. **The person's interventions**: what they redirected, corrected, refused or
   explained. A correction is the plainest evidence of context the session did
   not have, and the record check already counts the person's words as the
   strongest evidence.
2. **The agent's own mistakes, read as missing context.** The question is where
   more context would have helped. If it arrived later in the session, that
   context is the learning, usually project or general reference. If it never
   arrived, the draft proposes asking the person for it.
3. **Only then a general lesson**, sparingly, favouring the specific and
   practical.

This replaces a broader brief that promoted standards and lessons. In practice
that produced lines in the model's own idiom, opaque to the person who had to
approve them, and leaning toward generic, AI-wide advice rather than the concrete
gap that would have made the next session better. The order is where to look
first, not a list of kinds to record, which keeps faith with the finding below
that a list of kinds narrows what gets noticed.

**The bias guard.** An item bound for the always-loaded tier comes from a
correction or a gap in context, with the incident and the person's words behind
it. A generic lesson with no incident is not promoted there: it costs every
session and changes nothing a session would otherwise get wrong. The draft says
which source an item has (`source: correction | missing-context | general`), and
`check-evidence.sh` refuses a working-standards item whose source is `general`,
and a `correction` with no evidence line in the person's own words.

**Observed, cause unknown.** A capture that saw something it could not explain
(in the study, a run that replied "Green" when the person answered "1", and 1
was Red) used to leave it out for want of a cause, and the observation was lost
with the session. It now writes the item as `observed`, cited, never promoted as
fact, so the person can find the cause.

## Plain words first

The person approves every promotion, so every candidate is written first in the
person's words: a `plain:` line, one everyday sentence, which is what the review
shows before anything else. The agent's own phrasing may stay in the record next
to it. A term that is not plain goes through the glossary: `memory/glossary.md`,
or the project's or area's own `glossary.md`, which maps the terms models
converge on to the words a person uses. The closeout uses a row's plain words,
or proposes a new row when a person had to ask what a term meant. The checker
refuses an item with no `plain:` line.

The difference, on one learning:

- Before: "If ablation is the crux of the spine of synthesis, conjugate the nominal as an irreversible prime."
- After: "Avoid writing to files another agent is already working on."

Routes follow the vocabulary: a decision goes to the `decisions.md` it belongs
to, a term of the work to `terms.md`, a translation of AI-speak to the glossary.

## Guidance says what memory is for

The same write-up reports that telling an agent what memory is for helps, and
telling it what to record does not: one added rule, "record only failures", cut
the gain from memory on a database task by 0.150 to 0.234, depending on the
model. A list of kinds narrows what gets noticed to the kinds listed.

So the capture prompt, the command and the ritual say what the next session
needs (to start without this conversation, and act on what the files tell it)
and leave the judgement of what serves that to the session. Three things stay as
rules, because they are boundaries rather than advice about what is worth
keeping: privacy (a sensitive project's learnings stay in its folder, the
roster's contact-detail filter, nothing sent), the bounded always-loaded tier,
and commit ownership with no attribution lines.

## Two levels of override, and why not a schema

Teams disagree about tiers. Some want three, some want six, some already have a
vocabulary ("playbooks", "runbooks", "standing orders") that a plugin has no
business renaming.

Encoding that as configuration means inventing a schema — tier objects with names,
load rates, destination globs, scope mappings — that will not survive contact with
the third team to adopt it.

So there are two levels instead:

- **Destinations move by environment variable** (`CLOSEOUT_TIER_ALWAYS` and
  friends). Keeps the default four tiers, points them at your files. One line each
  in `.claude/settings.json`, no file to write.
- **The taxonomy is replaced by prose.** A `## Promotion tiers` heading in
  `.claude/closeout.md` and the plugin's own table is suppressed entirely — both
  prompts then carry the project's section and nothing else. Detection is a single
  `grep -qiE` for the heading.

The suppression matters more than it looks. An earlier shape appended the project
table *after* the default one, and the model had to reconcile two tier lists that
disagreed; it split the difference roughly half the time. A taxonomy is not
additive. Either the plugin's applies or the project's does.

## Who needs to know, and why the hook computes the team

A learning promoted into a file nobody knows has changed reaches nobody until
they happen to open it. So when a project names two or more people, the closeout
ends with a short "who needs to know" table.

Three choices shape it:

- **The team is computed by the hook, not the child.** The capture child runs from the
  draft directory and cannot see the repository's people directory from there. `lib/config.sh` resolves the list and passes it in.
- **It is advice, not delivery.** Nothing is sent. A message to a colleague goes
  out in a person's own voice; an unattended agent writing to someone's
  colleagues on exit is the wrong blast radius entirely.
- **It never reaches the repository.** It is communication — a third axis beside
  context and tracking — and it goes stale as soon as it is read.
- **It is optional, set once.** `Who needs to know: auto | ask | off` in the
  conventions file, overridable per project in the README's People section. Some
  teams hear everything in a regular meeting and want no table; the setting says so once
  rather than having the step skipped by hand every session. The hooks read only
  the repository's setting: under `off` they say nothing, and a README override is
  applied by `/closeout`, which reads the project's README.
- **The hooks count the repository, the prompt decides the project.** A hook
  cannot tell which project a session worked in or what changed, so it counts
  everyone the repository knows — the roster included — and hands the per-project
  condition (two or more for this project, or a scoped match) to the prompt.
- **A roster seeds it, and the project wins.** `team/people.md` gives each person
  a default relationship and a channel, so the step can name the measurement lead
  for a measurement change on a project that forgot to list them. The project's
  own People section overrides it, because who is on a project is the project's to
  say. The roster holds handles only: the hook drops any cell that looks like an
  email address or phone number before it reaches a prompt, since the repository
  is shared and contact details belong to the person.
- **Offers, not messages.** Each row offers a draft, a note for the next team
  meeting, or none. A connected mail or chat tool changes only where a draft can
  be left, on an explicit yes; it never changes who presses send.

## Extension via `.claude/closeout.md`

Teams have their own closeout rules — a tracking queue to reconcile, locks to
release, a house style for doc edits. Encoding those as plugin configuration
means inventing a schema that will never fit the next team.

Instead, an optional `.claude/closeout.md` in the consuming project is read
verbatim by both the command and the capture prompt. Prose in, prose out. It costs
one file check and covers arbitrary conventions — including replacing the
promotion taxonomy outright, as above.

## A personal layer, and why the project wins

Some conventions belong to a person rather than a team: a destination only they
use (learnings about a tool they maintain, routed to its own repository), a line
they want in every report. Written into each project's `.claude/closeout.md`, they
would leak one person's habits into every team they work with. So there is a
second file, `~/.claude/closeout.md`, read by the command, appended to the capture
prompt and named in the review reminder.

Precedence is project, then person, then plugin defaults. The project wins because
it is shared: a teammate closing out in the same repository must get the same
answer about where a learning goes, and a personal file they cannot see must not
change that. The personal file still outranks the defaults, because the defaults
are only a guess made without knowing either. Tiers follow the same order: a
personal `## Promotion tiers` section replaces the default table only in projects
that define no tiers of their own. Team detection ignores the personal file —
who is on a project is the project's to say.

The capture child sees both files as text in one prompt, with no way to tell which
came from where, so the prompt says the precedence in words rather than relying on
order alone. `CLOSEOUT_USER_CONVENTIONS` exists so the tests, and anyone
debugging, can point the hooks at a known file or at none.

## Tracking, reconciled after the learnings

`/closeout` ends by bringing the project's tracking up to date — ticking its Done
when list and refreshing the Current state block: its state, its `Blocked by:`
line, its date and the dated line that says where the work stands. It is a
separate step, reported separately, because context and tracking are different
axes: merged, the closeout becomes a status update and the learnings stop being
recorded. Tracking is reconciled but never invented. The state moves only when
the session plainly moved it, and a blocker is written down with the date it
began, so the projects board can flag one that has lasted too long; adding a
missing Current state block, converting an older block, pausing a project or
marking it done are left to the person and the projects commands that own them. The capture child
does none of this: it cannot read the repository, and tracking changed
unattended is tracking nobody trusts.

## Committing is left to the person, in submodule order

The command ends with commands, not a commit. Writing or editing the message is
the person's check that they understand what changed, and a broad staging
command sweeps in whatever else was in flight, so each path is named. Some
workspaces keep every commit with a person as a house rule; the plan fits them
unchanged, because it is always a list of commands to run.

A workspace can hold other repositories as submodules: the kit at `kit/`, and
projects that are their own repositories. A file changed inside one needs two
commits, and their order matters. Committed the other way round, the
workspace records a pointer to a commit its submodule's remote does not have
yet, and every other clone of the workspace then fails to check it out. So the
plan runs innermost first: add, commit and push inside the submodule; then add
its path in the workspace with the other files, and commit. Git's
`push.recurseSubmodules=check`, which the kit sets, refuses the wrong order at
push time; the plan avoids reaching that refusal.

## `.claude/skills/` as a destination

In a workspace built on the kit, `.claude/skills/` is generated: the skills
bridge writes the kit's commands there as skills, with copies of the team's own
skills from `skills/`, and rewrites what its manifest,
`.claude/skills/.kit-generated`, lists on its next run. A learning promoted
into it would be overwritten or left unlisted, so while that manifest exists the
general-reference destination is `skills/`, where the bridge copies from. A
repository without the bridge keeps the earlier default.

## Troubleshooting

**No drafts ever appear.**

1. Confirm the plugin is installed and enabled, in a folder Claude Code trusts —
   `/hooks` lists what is active. A plugin's hooks come with it and need no
   approval of their own; they run only while the plugin is enabled.
2. Confirm `jq` and `claude` resolve in a minimal environment:
   `env -i bash -c 'command -v jq claude'`. If `claude` is missing, set
   `CLOSEOUT_CLAUDE_BIN`.
3. Remember the skip conditions: `/clear` exits, transcripts under
   `CLOSEOUT_MIN_LINES`, and sessions where the child judged nothing durable
   happened. All three are correct behaviour.

**To see what the hook actually did**, run it by hand against a real transcript:

```bash
echo '{"reason":"exit","transcript_path":"<path>","session_id":"manual-test","cwd":"'"$PWD"'"}' \
  | bash hooks/closeout-capture.sh
```

Then watch `~/.claude/closeout-drafts/<basename>/manual-test.md` appear (or not)
over the next minute.

**A draft nudges every session and never goes away.** The agent could not delete
it — check the `Bash(rm *closeout-drafts*)` permission and the sandbox
`allowWrite` entry, and note that a sandbox change needs a fresh session.
