# workspace — set up a shared agentic workspace, and keep it that way

A Claude Code plugin for the workspace itself rather than any one project. Three
commands:

| Command | What it is for |
|---|---|
| **`/workspace:quick-start`** | The one door into the kit: set it up for the team and for each person, and check it is reachable on every surface they use. |
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

- **How projects run here** — the default in-flight limit and the staleness
  setting (how old a project's `Updated:` date can be before the board flags
  it), in `.claude/projects.md`, which the projects plugin reads first.
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

Every run ends by checking the kit is reachable and running, each step optional:
the commands on every surface the person uses — for a desktop assistant, each
generated skill present in the folder it actually scans, with the sync step when
one is missing and a note that new skills appear from the next session — the
session-start line in a project folder, a metrics baseline, and the first thing
to do in one real project.

It finds out where things stand before asking anything, offers what the
repository already says as suggested answers, shows every change before making
it, and leaves the commit to you.

## Weekly hygiene and the monthly register audit

`/workspace:hygiene` is the runnable form of `rituals/weekly-hygiene.md`. It
checks where context lives against the workspace's own conventions: strays, the
project register against the folders, promised files, promotion candidates,
stale guidance, unconfirmed proposals, and a sweep of closeout's drafts for this
repository and each project folder — oldest first, including the files of other
kinds and subdirectories that the drafts' retention never touches, each with a
proposed move and nothing deleted. It reports the always-loaded byte count on
every run, and includes the weekly `pilot/measure.sh` run when the repository
keeps metrics.

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

## The state check

`bin/state.sh` reads a repository and reports where it stands against the kit, one
`key=value` per line: the always-loaded file and the stand-ins left in it, the
person's profile, the project conventions, the register, the decisions log, the
team's own skills, the plugins registered, and a closing `mode=` line (`fresh`,
`joining`, `existing-system` or `nothing-left`). It is written for the
quick-start and the setup wizard to branch on, and the tests assert against it.
Run it in the repository, or name another folder; `--json` gives the same facts
as one object:

```
bash .claude/plugins/workspace/bin/state.sh
bash .claude/plugins/workspace/bin/state.sh ../other-repo --json
```

It writes nothing and makes no network call. It reads git only with
`--no-optional-locks`, so it leaves no `index.lock` behind, even run from a
desktop assistant's shell on a repository a session has open. It needs bash 3.2
and git; jq reads the settings file and gives `--json`.

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
