# Contributing to the kit

The kit is public, and the workspace it sits in is private. A change to the kit starts from something a
team learned in its own workspace, and reaches the kit as a pull request, with the team's material left
behind. This file is how that goes.

## Is it a kit change?

Strip the change of every client, project, person and machine it came from. If something useful is
left (a rule, a template field, a check a command should make), it belongs in the kit. If nothing is
left, it was a lesson for the workspace, and it stays there.

## The flow

The kit already sits in your workspace at `kit/`, as a submodule. You work on it there, pointed at a
fork, so your projects never leave the workspace and the fork never sees them.

1. **Fork the kit** on GitHub: `cyberscribe/agentic-workspace-kit`, to your own account.
2. **Point the workspace's `kit/` at the fork**, and start a branch there from the fork's `main`:

   ```bash
   git submodule set-url kit https://github.com/<you>/agentic-workspace-kit.git
   git -C kit fetch origin
   git -C kit switch -c <topic> origin/main
   kit/setup.sh hooks
   ```

   `git submodule set-url` changes `.gitmodules` and the kit's `origin`. `kit/setup.sh hooks` makes
   sure the kit's own git hooks run on your commits there.
3. **Commit in `kit/`.** Edit, run the tests (below), then commit inside the submodule, naming each
   path:

   ```bash
   git -C kit add <paths>
   git -C kit commit -m "<what changed, and why>"
   ```

4. **Push to the fork**: `git -C kit push -u origin <topic>`.
5. **Open a pull request** from `<you>:<topic>` against `cyberscribe/agentic-workspace-kit`, `main`,
   on GitHub or with `gh pr create --repo cyberscribe/agentic-workspace-kit`.

In the workspace, `git status` now shows `.gitmodules` and `kit` as changed. Leave both uncommitted
while the pull request is open, unless the team means to run on the fork: a team on a fork points
`.gitmodules` at it and commits that. Once the pull request is merged, point `kit/` back and take the
release as everyone does:

```bash
git submodule set-url kit https://github.com/cyberscribe/agentic-workspace-kit.git
kit/setup.sh update
```

## What the kit's hooks check

In `kit/`, the pre-commit, commit-msg and pre-push hooks run `scripts/check-paths.sh`, and so does CI
on every pull request. A commit is refused when it adds a file outside the kit's folders and root
files, a file private by its name or shaped like data, a symlink, an unlisted binary, a large file,
anything the workspace's `.gitignore` lists, a word from your private word list, a name derived from
your workspace (a project, a person, a remote, a machine path), a verbatim copy of a workspace file,
or an AI attribution trailer. Each refusal names the item and the reason; fix it and commit again. A
change to the guard files themselves (`scripts/check-paths.sh`, `githooks/`, `.github/`,
`lib/common.sh`) needs `AW_GUARD_CHANGE=1` for that commit, and is reviewed by the maintainer.
`docs/hooks/` has a page for each hook.

## Running the tests

From the kit's folder (`kit/` in a workspace, or a clone of its own):

```bash
bash tests/run.sh                      # everything; one PASS, FAIL or SKIP line per check, then a count
AW_SECTIONS="12 9" bash tests/run.sh   # only the named sections, for work on one of them
```

The suite needs `git`, `jq` and `python3` (3.11 or later), and builds everything under one temporary
folder that it removes on exit (`AW_KEEP=1` keeps it). It runs child scripts under `/bin/bash` where
there is one, since the kit's scripts are written for bash 3.2; `AW_BASH32=0` leaves `PATH` alone.
Checks that start Claude Code are skipped unless `AW_TEST_CLAUDE=1`. `tests/README.md` lists every
section and flag. Passing is the bar for every change.

## Shellcheck

Every script is linted with `shellcheck -x`, which section 11 of the suite runs when `shellcheck` is on
`PATH`. To run it yourself:

```bash
shellcheck -x setup.sh install.sh lib/*.sh lib/setup/*.sh scripts/*.sh githooks/pre-commit \
    githooks/pre-merge-commit githooks/commit-msg githooks/pre-push githooks/stub.sh githooks/lib/common.sh \
    plugins/workspace/bin/state.sh plugins/*/hooks/*.sh plugins/closeout/hooks/lib/config.sh \
    pilot/*.sh tests/run.sh tests/sections/*.sh
```

## Along with the change

- A changed command or hook updates its page in `docs/commands/` or `docs/hooks/`; section 12 checks
  every command and hook has one, in the four parts.
- A change to anything under `templates/` goes in the CHANGELOG entry's `### Template changes` list,
  which `kit/setup.sh update` shows a team before it offers the diff.
- Guidance states norms as facts about how the work is done. `docs/documentation-register.md` has the
  rule, and section 8 of the suite fails capitals used for emphasis.
- Scripts run under macOS's `/bin/bash` 3.2: no associative arrays, no `mapfile`.
