# kit/setup.sh

*The one entry point for setting a workspace up and keeping it in step with the kit. Source:
`setup.sh`, which runs the scripts in `lib/setup/` and `scripts/skills-bridge.sh` for its modes.*

## What it does

With no mode, it runs ten stages. Each reads the state check (`kit/plugins/workspace/bin/state.sh`)
first, so a finished stage is skipped and a second run picks up where Ctrl-C stopped. It overwrites,
deletes and commits nothing; the last stage prints the commit to make.

| # | Stage | What it does |
|---|---|---|
| 1 | Prerequisites | bash 3.2 or later, git and jq; claude and gh are optional |
| 2 | Identity | The team, its standards owner and their handle, from flags, earlier answers or questions |
| 3 | The workspace | Starts a repository (`new`), adds the kit as a submodule at `kit/` where it is missing, then runs the engine, `kit/install.sh`, which creates the team's own files once and records them in `.claude/kit-templates.lock` |
| 4 | Remotes and privacy | Sets the git hooks, and records `origin` as private once GitHub (with `gh`) or the person confirms it |
| 5 | Submodule configuration | The git settings that keep submodules visible and pushed |
| 6 | Outside folders | Runs `link` for material projects name under `## Resources` |
| 7 | Restart Claude Code | How to trust the folder and install the three plugins from the marketplace at `kit/` |
| 8 | Cowork (with `--cowork`) | Runs the skills bridge, and names the scheduled tasks that fit |
| 9 | Verify | Each check, with the command that fixes any that fails |
| 10 | Finish | What to run next, `/workspace:quick-start`, and the commit to make |

| Mode | What it does |
|---|---|
| `kit/setup.sh new DIR` | Makes a workspace from nothing: `git init`, the kit added from `--kit-url` (else `AW_KIT_URL`, else the kit's own origin), then the ten stages |
| `kit/setup.sh update [--no-fetch]` | Advances the kit submodule, prints the CHANGELOG since the old version, offers each changed template as a diff to apply or skip, re-runs the engine, and prints the commit. A 2.x workspace is handed to `migrate --dry-run` |
| `kit/setup.sh --developer` | Puts `kit/` on `main` tracking `origin/main`, with `submodule.<name>.update=rebase` and `pull.rebase=true`, for developing the kit in place |
| `kit/setup.sh link [SLUG] [--dry-run]` | Links each resource a project names to its path on this machine, from `.claude/resources.local.md` |
| `kit/setup.sh hooks [--repo PATH] [--check]` | Sets the git hooks in the workspace, the kit and each project repository |
| `kit/setup.sh skills [--dry-run] [--check] [--no-user]` | Writes one `kit-` skill per command, and copies the team's `skills/`, into `.claude/skills/` |
| `kit/setup.sh migrate [--dry-run] [--map FILE] …` | Moves a 2.x workspace to the 3.0 layout; see `docs/migration.md` |

Every mode takes `--target DIR`. Without it, the target is the repository the kit is a submodule of,
else the current folder. `AW_WIZARD_NONINTERACTIVE=1`, or no terminal on stdin, runs unattended: every
question takes its default, and stages only a person can do are skipped. Exit status: `0` finished
(stages may be left open), `1` stopped, `2` usage, `130` interrupted; `migrate` also uses `3`.

## When to reach for it

`new` to start a workspace; the plain run after cloning one (`git clone --recurse-submodules`, then
`kit/setup.sh`), and whenever the session-start summary names it; `update` to take a newer kit; `hooks`
after a clone or a new project repository; `link` on a new machine; `skills` after an update, when the
team uses Cowork; `--developer` only when working on the kit itself.

## Common questions

**What does `--reinstall` do now?** It runs the engine again, which creates any file of yours that is
missing and changes nothing else. A newer kit arrives with `update`. Run `skills` and `hooks` from a
terminal: an agent's sandbox may refuse to write `.claude/skills/` or git settings.

**After a migration, the plugins are missing in Claude Code.** Commit the migration first. Then each
person re-points Claude Code at the marketplace in `kit/` and installs the three plugins:
`claude plugin install closeout@agentic-workspace`, `projects@agentic-workspace` and
`workspace@agentic-workspace`. That step leaves the repository alone: `git diff .claude/settings.json`
is empty afterwards. Until then, the workspace session-start line names the install command when the
bridge's `kit-` skills are present, and those skills hand over to the plugin commands in Claude Code.

**The kit folder is empty after a clone.** It was cloned without `--recurse-submodules`. The plain run
initialises it (`git submodule update --init kit`).

## It's working if

- A second run reports the finished stages as `already done` and changes nothing under the workspace,
  `.git` included.
- Stage 9 passes every check, and a new session in the workspace shows no `Workspace:` lines.
- `kit/setup.sh hooks --check` exits 0, and so does `kit/setup.sh skills --check` where the team uses
  the bridge.
