# Principles

*How to work with an AI and hand work to it, as the kit carries it out. Each principle names the file
that puts it into practice, so it can be taught from and checked against.*

> Part of the kit, read in place at `kit/docs/principles.md`. The two purposes these serve are in the
> README's *What the kit is for*: common ground between the person and the AI, and context the AI
> cannot find anywhere else.

---

## Handing work over

**1. Give the outcome, not the steps.** Say what finished looks like and why it matters, and leave the
how to whoever does it. A list of steps fails the moment the work meets something the list did not
expect; an outcome still says what to do then.
*In the kit:* a project's README opens with its desired outcome (`templates/project-readme.md`), and
a pairing's brief is built from it rather than from instructions (`plugins/projects/commands/pair.md`,
Starting a pairing, step 3).

**2. Say when it is finished, in checks someone else could run.** "Done" that only the doer can judge
is not a finish line. A short list of observable checks is.
*In the kit:* the Done when list (`plugins/projects/commands/new.md`), and `/projects:close`, which
shows the evidence for each item before anything is marked done (`plugins/projects/commands/close.md`,
§1).

**3. Stop where only a person can decide.** Spending, sending, publishing, committing and anything that
cannot be taken back wait for a yes. Everything short of that edge goes ahead without asking.
*In the kit:* the approval gates in a workspace's `CLAUDE.md` (`templates/workspace/CLAUDE.md`, §3);
commits left to the person by every command; anything scheduled or written on the person's behalf
offered, never installed (`plugins/workspace/commands/quick-start.md`, step 4); tools named in advance
for a run nobody watches (`plugins/scheduler/commands/tasks.md`).

## Checking the work

**4. Check against the evidence, not the report.** A report says what its writer believes happened.
Run the thing, read the file, look at the commit.
*In the kit:* the manager in a pairing tests the work itself (`plugins/projects/commands/pair.md`,
Each check-in); closeout checks each candidate against the session's record before it is kept
(`plugins/closeout/commands/closeout.md`, Verify before you record, and
`plugins/closeout/scripts/check-evidence.sh`).

**5. Two roles judge the work from two angles.** The one who builds sees how it works; the one who
holds the outcome sees whether it does the job. Each catches what the other cannot.
*In the kit:* `/projects:pair`, a manager and an engineer talking through a mailbox
(`plugins/projects/commands/pair.md`).

## Keeping common ground

**6. Say it in the person's words.** A model drifts into its own idiom. What the person reads comes
first in plain words, and a term only the model uses gets translated, not adopted.
*In the kit:* the glossary of AI-speak with the plain words beside each term (`templates/glossary.md`);
the `plain:` line every closeout candidate carries (`plugins/closeout/commands/closeout.md`); the
plain-language check in the register audit (`plugins/workspace/commands/register-audit.md`).

**7. Name things once, and keep the names where both can find them.** A project, an area, a term, a
decision: each has one place, in a plain file that both the person and the AI can read and correct.
*In the kit:* the store for each kind of fact (`docs/memory-layers.md`, §3); a project's or area's
`decisions.md`, `glossary.md` and `terms.md`; the workspace map (`templates/workspace/workspace-map.md`).

**8. Write guidance calmly.** Instructions an AI reads before it starts shape how it works. Threats,
capitals and invented urgency make it worse at the job, not better.
*In the kit:* the documentation register (`docs/documentation-register.md`) and the monthly audit that
scans for drift (`plugins/workspace/commands/register-audit.md`).

## Remembering

**9. Record only what cannot be found again.** The code, the files and their history are already there
to read. A note earns its place by holding what they do not show: a decision and why, a correction, a
fact in someone's head.
*In the kit:* the test every promotion passes first (`docs/memory-layers.md`, §1), applied by closeout
(`plugins/closeout/commands/closeout.md`).

**10. Learn first from the person's corrections.** When the person redirects the work, that is the
clearest sign of context the AI lacked. It comes before the AI's own conclusions, and generic lessons
come last.
*In the kit:* the order closeout reads a session in (`plugins/closeout/commands/closeout.md`), and the
evidence check, which counts the person's own words as the strongest anchor
(`plugins/closeout/scripts/check-evidence.sh`).

**11. Keep what loads every time small.** Whatever is read at the start of every session is paid for in
every session. It holds how to work together, and points at everything else.
*In the kit:* the always-loaded budget (`docs/memory-layers.md`), changed only with the person's yes
(`plugins/closeout/commands/closeout.md`) and measured weekly (`plugins/workspace/commands/hygiene.md`).

**12. Keep where the work stands apart from what was learned.** Status changes daily and is corrected
by checking it against reality; knowledge is promoted with care. Mixing them turns a learning pass into
a status meeting.
*In the kit:* tracking on its own rail, in each README's Current state block (`docs/memory-layers.md`,
§1), reconciled after promotion (`plugins/closeout/commands/closeout.md`, Reconcile tracking).

**13. Correct by adding, not by rewriting.** What was believed last month, and why it changed, is itself
worth keeping. A later entry supersedes an earlier one and points back at it.
*In the kit:* the decisions log's Status line (`templates/project-decisions.md`) and the CHANGELOG's
rule of appending.
