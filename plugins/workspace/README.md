# workspace — set up a shared agentic workspace, and keep it that way

A Claude Code plugin for the workspace itself rather than any one project. Three
commands:

| Command | What it is for |
|---|---|
| **`/workspace:quick-start`** | The one door into the kit: set it up for the team and for each person, and wire it into their routines. |
| **`/workspace:hygiene`** | The weekly tidy of where context lives, with the always-loaded byte count every time. |
| **`/workspace:register-audit`** | The monthly check of the register guidance files are written in. |

## Quick-start

`/workspace:quick-start` is the one door into the kit: a short
interview that turns the installed files into this team's own, then does the same
for each person on their first session.

It works out which situation it is in rather than asking — a fresh team, a
person joining a team that has already set up, or someone arriving with a system
of their own — and offers only the parts that apply:

- **The team part — once.** What the team does, who owns the standards, output
  preferences, working conventions, how the agent should show up, and the
  approval gates — written into the always-loaded file a line at a time, because
  every line there is paid for by every session.
- **The personal part — each person.** Their profile in the people directory, and
  a few lines for their own personal layer, which stays theirs and outside the
  repository.

And, if the team wants them, a few things that live in their own files so they
cost the always-loaded budget nothing:

- **How projects run here** — the default in-flight limit and the review day,
  in `.claude/projects.md`, which the projects plugin reads first.
- **What counts as checked** — a verification standard in `docs/verification.md`,
  one row per kind of work.
- **The catalogue** — what the team has built and would reuse, in
  `docs/catalogue.md`.
- **A personal in-flight limit** on each person's profile.

- **Fitting the kit to a system already in place.** A short table mapping what
  exists — an always-loaded file, a register, a decisions log, rituals, skills —
  to the kit's terms, confirmed line by line; differing conventions recorded in
  `.claude/projects.md` or `.claude/closeout.md` rather than changed; the
  proposals `/projects:adopt` left in project READMEs walked one project at a
  time; and duplicate rituals folded into one each. Nothing existing is moved or
  renamed.

Every run ends by wiring the kit into the routines the person already has, each
step optional: the commands on every surface they use, the board's next actions
in their daily review, the projects review inside their weekly one, the
session-start line, a metrics baseline, and one real next action.

It finds out where things stand before asking anything, offers what the
repository already says as suggested answers, shows every change before making
it, and leaves the commit to you.

## Weekly hygiene and the monthly register audit

`/workspace:hygiene` is the runnable form of `rituals/weekly-hygiene.md`. It
checks where context lives against the workspace's own conventions: strays, the
project register against the folders, promised files, promotion candidates,
stale guidance and waiting work. It reports the always-loaded byte count on every
run, and includes the weekly `pilot/measure.sh` run when the repository keeps
metrics.

`/workspace:register-audit` is the runnable form of the scan in
`docs/documentation-register.md`. It grades agent-facing prose by how strongly it
primes a session and counts what each suppression layer removed, so a clean month
can be told apart from a broken check.

Each command writes a dated report to `audits/`, one line per check or severity,
and says "nothing to do" when that is the result. Each then works through the
findings with you and makes no change without your yes. Type `report` after
either command for the scan alone, as a scheduled run would. If your repository
already runs its own hygiene or register scanner, the command runs that instead
of adding a second pass.

## Install

Part of the [workspace context kit](https://github.com/cyberscribe/agentic-workspace-kit):

```
/plugin marketplace add cyberscribe/agentic-workspace-kit
/plugin install workspace@agentic-workspace
```

The kit's `install.sh` vendors it into a team repository alongside the closeout and
projects plugins. With `--skills-dir <path>` it also writes one thin skill per
command (`workspace-quick-start`, `workspace-hygiene`,
`workspace-register-audit`) for assistants that load skills from a folder; each
points at the command file, so the procedure still has one source.

## Works with

- **projects** — the quick-start offers `/projects:new` for the team's first
  projects, and writes the conventions that command reads.
- **closeout** — the quick-start ends by suggesting `/closeout` at the end of the
  first real session.

MIT licensed, as part of the kit.
