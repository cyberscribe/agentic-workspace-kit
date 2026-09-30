# workspace — set up a shared agentic workspace, and keep it that way

A Claude Code plugin for the workspace itself rather than any one project. Three
commands, two hooks and a state check:

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

## The session-start summary

When a session starts in a workspace, a hook says what is out of step there, one
line each, with the command that fixes it — and nothing when all is in step:

```
Workspace: git hooks are not active — kit/setup.sh hooks turns them on.
Workspace: site: 2 commits not pushed; kit: pointer changed, not committed.
Workspace: 2 resources not reachable on this machine (field-study/media, field-study/survey-data) — kit/setup.sh link.
Workspace: origin is not confirmed private — kit/setup.sh records it once confirmed.
```

It covers the git hooks, the `@kit/CLAUDE.kit.md` import in `CLAUDE.md`, the kit
off `main` in developer mode, submodules out of step (the kit and projects that
are their own repository; other submodules are left alone), gitlinks with no
`.gitmodules` entry, resources absent on this machine, sensitive projects with
files the workspace tracks, an origin not confirmed private, and the kit behind
its remote. It finds the workspace from the session's folder, so a session opened
inside `kit/` or inside a project that is its own repository reports on the
workspace around it, and one opened anywhere else reports nothing.

It reads `bin/state.sh --quick`, which makes no network call, takes no lock and
never lists a resource folder (listing a cloud-drive folder can stall). It needs
jq, and it is silent on any failure. `WORKSPACE_HOOK_DISABLED=1` turns it off, and
a headless run (`AW_HEADLESS_RUN=1`) or closeout's capture child
(`CLOSEOUT_HOOK_CHILD`) gets nothing.

## The git guard

A second hook, before each shell command an agent runs, declines the ways of
getting past the workspace's git hooks: `--no-verify`, `commit -n`, and setting
`core.hooksPath` for one command or for good. The hooks decide what reaches a
remote; a refusal is reported to the person with the hook's reason, and the
person decides. It is silent on every other command, and
`AW_GIT_GUARD_DISABLED=1` in the session's environment turns it off.

## The state check

`bin/state.sh` reads a repository and reports where it stands against the kit, one
`key=value` per line. For the workspace: the git hooks, where the kit is and how
far it is from its remote, the import in `CLAUDE.md`, the origin and whether it is
recorded as confirmed private, each submodule's state (`submodule.<path>`),
gitlinks with no `.gitmodules` entry, sensitive projects and any the workspace
tracks, projects whose `Versioned:` line disagrees with the folder, each resource
(`resource.<slug>/<name>`), the skills bridge, and traces of a 2.x layout. For the
people in it: the always-loaded file and the stand-ins left in it, the person's
profile, the project conventions, the register, the decisions log, the team's own
skills, the plugins registered, and a closing `mode=` line (`fresh`, `joining`,
`existing-system` or `nothing-left`). It is written for the quick-start, the
setup wizard, the session-start summary and the board to branch on, and the tests
assert against it. Run it from the workspace, or name another folder:

```
bash kit/plugins/workspace/bin/state.sh
bash kit/plugins/workspace/bin/state.sh --quick
bash kit/plugins/workspace/bin/state.sh ../other-repo --json
bash kit/plugins/workspace/bin/state.sh --explain submodule.kit
```

`--quick` gives only the keys the session-start summary reads, at a cost that
does not grow with the number of projects. `--json` gives the same facts as one
object. `--explain` says what each key means, or one key, from the comments beside
the lines that work it out.

It writes nothing and makes no network call. It reads git only with
`--no-optional-locks`, so it leaves no `index.lock` behind, even run from a
desktop assistant's shell on a repository a session has open. It never opens a
file the workspace keeps from tools (`AGENTS.md` by default, unless the kit wrote
it): that reads `agents_md=opaque`. It needs bash 3.2 and git; jq reads the
settings files and gives `--json`.

## Install

Part of the [workspace context kit](https://github.com/cyberscribe/agentic-workspace-kit).
A workspace holds the kit as a submodule at `kit/`, and `.claude/settings.json`
registers `kit` as the `agentic-workspace` plugin marketplace, so the plugin is
read in place and updates with the kit (`kit/setup.sh update`). On its own:

```
/plugin marketplace add cyberscribe/agentic-workspace-kit
/plugin install workspace@agentic-workspace
```

For assistants that load skills from a folder, `kit/setup.sh skills` writes one
thin skill per command into `.claude/skills/`, prefixed `kit-`
(`kit-workspace-quick-start`, `kit-workspace-hygiene`,
`kit-workspace-register-audit`); each points at the command file, so the procedure
still has one source.

## Works with

- **projects** — the quick-start offers `/projects:new` for the team's first
  projects, and writes the conventions that command reads.
- **closeout** — the quick-start ends by suggesting `/closeout` at the end of the
  first real session.

MIT licensed, as part of the kit.
