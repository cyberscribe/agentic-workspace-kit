# /projects:overnight

*Sets up work to run while the person is away: a short pre-flight that settles, before they leave, the
outcome they want to wake up to and every call they would otherwise be woken for, then a brief with its
bounds, and one summary in the morning. Source: `plugins/projects/commands/overnight.md`.*

## What it does

- Asks two questions every time: what the person wants to wake up to, and what would make it excellent,
  in their own words.
- Asks, each with a recommended default, the calls a night's work can run into: spend (an API cap, with
  the key's credit checked by a one-token call, and a subscription cap), what may leave the machine, what
  may be committed, pushed, published or sent, deletion, the machine (awake, shared resources, a stop
  time), and wake time with how the results should arrive.
- Tries each kind of write the night needs before the person leaves (`git commit --dry-run`, a scratch
  file, `git push --dry-run`), so a refusal is fixed now or routed round with a patch series and one
  morning script.
- Suggests one agent or a manager–engineer pairing, with the reason, and hands over to `/projects:pair`
  on a yes.
- Writes the bounds block into the brief: the answers, "take the reversible reading, note it, carry
  on", and what waits for the morning.
- Puts the mechanisms that keep a night running into the brief, and ends with one morning summary: what
  was done with its evidence, what is open, decisions as questions for whoever is accountable, one
  script, the files to read.

## When to reach for it

At the end of the day, before leaving work to run unattended: a build to finish, a study to run, a
report to draft. Most nights that build and test are a pairing; reading or one contained task is a
single agent.

## Common questions

**Why `/projects:overnight` and not `/overnight`?** A plugin's commands carry its name. It lives in the
projects plugin because it starts from a project's outcome and hands over to `/projects:pair`. In
Cowork it is the `kit-projects-overnight` skill.

**What does it never do overnight?** Spend past a cap, publish, send a message to a person, delete, or
type a credential. A stop that leaves a clear question for the morning counts as a good result.

**Does it ask everything every time?** Only the two outcome questions. The rest are asked when the
night's work could run into them, and a default is an answer.

## It's working if

- The brief or the pairing's first message carries the bounds block, filled in.
- Each write the night needs was tried before the person left.
- The morning summary is where the person looks first, with one script and the decisions as questions.
