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

## Before you publish

The checks above read text and paths. They cannot read meaning, so a pull request to the public kit has a
short read by a person first. Go down this list before you push.

| Check | Runs | Catches | Cannot catch |
|---|---|---|---|
| `check-paths.sh` path rules | pre-commit, pre-push, CI (`kit paths`) | a file outside the kit's folders, one private by its name, a symlink, anything the workspace's `.gitignore` lists | a private fact inside an allowed file |
| Binary and size rules (R1, R2) | the same | an unlisted binary, a large file; a `.png` only with its row in `docs/images/SOURCES.md` | what a listed image shows, or the text in an `.svg` |
| Private word list (R3) | pre-commit, commit-msg, pre-push; CI with the `AW_BANNED_WORDS` secret | a word or pattern from your list, as a whole word in any case | a word not on the list, a paraphrase, a misspelling |
| Derived names (R4) | pre-commit, pre-push | a project, person, remote or machine path taken from your workspace | a name the workspace does not hold, such as a client mentioned only in conversation |
| Copy check (R5) | pre-commit, pre-push | a verbatim copy of a workspace file | a close paraphrase, or a copy from somewhere other than the workspace |
| Attribution (R6) | commit-msg, pre-push | an AI attribution trailer in a commit or tag message | attribution in a file's text |
| The suite (`tests/run.sh`) | by hand, CI | broken behaviour, missing docs pages, a tool with no row in `docs/dependencies.md` | anything above |

Then read the change yourself for what no check sees:

- **The situation behind it.** A client's problem, an incident or a colleague's habit described without
  names can still identify them. Write the general pattern, not the case it came from.
- **Pasted material.** Transcripts, logs, terminal captures and test fixtures carry paths, session ids,
  prompts and names. Write fixtures by hand rather than copying real runs.
- **Images.** A screenshot or diagram can show a folder tree, a calendar or a message. Look at each one.
- **Where you committed from.** From a checkout outside the workspace (a worktree in a scratch folder),
  the hooks find no workspace and say "the workspace checks did not run". Run
  `scripts/check-paths.sh --content --staged --workspace <your workspace>` yourself before each commit.
- **The word list itself.** It catches only what is on it. Add a term the day it becomes private.
- **Licences.** Code you did not write needs its licence checked and a row in `docs/dependencies.md`,
  or it stays out.

## Running the tests

From the kit's folder (`kit/` in a workspace, or a clone of its own):

```bash
bash tests/run.sh --changed=staged     # before a commit: the sections the staged paths map to
bash tests/run.sh                      # before a push: everything, up to four sections at once
AW_JOBS=1 bash tests/run.sh            # to debug: everything, one section after another
AW_SECTIONS="12 9" bash tests/run.sh   # only the named sections, for work on one of them
```

One `PASS`, `FAIL` or `SKIP` line per check, then a count; a parallel run prints the same lines, in
the same order, as a serial one. `--changed` reads the path map in `tests/README.md`, runs everything
when a changed path has no row there, and holds back the slow tier (sections 10, 15, 16, 20 and 25,
one `SKIP` line each) unless `AW_SLOW=1`; the full run before a push, and a release with
`AW_REQUIRE_CLAUDE=1`, run them. A new folder or root file gets a row in the path map along with it.

The order of work: `--changed` (or `AW_SECTIONS`) while building, the full run at a gate and before a
push, and, once CI is switched on for the repository, its run on each push and pull request as the
record. Every run ends with where its time went: the wall time, the slowest sections, and the file
(`AW_TIMES`) with every section, check and failure timed; `tests/README.md` (*Where the time goes*) says
how to read it. A failure is listed there by the part it ran in, such as `15b`.

CI reads the word list from the repository secret `AW_BANNED_WORDS`. Set it from your list without its
comment lines, `grep -v '^#' <your word list> | gh secret set AW_BANNED_WORDS`: GitHub hides each line of
a secret wherever that text appears in the run's logs, so a comment line, a lone `#` above all, hides its
text in every log. CI warns when the secret holds one.

The suite needs `git`, `jq` and `python3` (3.11 or later), and builds everything under one temporary
folder that it removes on exit (`AW_KEEP=1` keeps it). It runs child scripts under `/bin/bash` where
there is one, since the kit's scripts are written for bash 3.2; `AW_BASH32=0` leaves `PATH` alone.
Checks that start Claude Code are skipped unless `AW_TEST_CLAUDE=1`, and the scheduler's live runs in
Linux containers unless `AW_TEST_DOCKER=1` (about four minutes, with a Docker daemon). `tests/README.md` lists every
section and flag. Passing is the bar for every change.

To time a hook by hand, give it an empty stdin: `bash githooks/pre-commit </dev/null`. The hooks read
stdin whenever it is not a terminal, as git hands a pre-push hook its refs that way, so a hook started
from a script or an agent's shell waits on stdin until it is closed. For a check whose cost depends on
the lines a commit adds, time it with lines copied from real files. Generated lines that share a
prefix can make a slow search look fast.

## Shellcheck

Every script is linted with `shellcheck -x`, which section 11 of the suite runs when `shellcheck` is on
`PATH`. To run it yourself:

```bash
shellcheck -x setup.sh install.sh lib/*.sh lib/setup/*.sh scripts/*.sh githooks/pre-commit \
    githooks/pre-merge-commit githooks/commit-msg githooks/pre-push githooks/stub.sh githooks/lib/common.sh \
    plugins/workspace/scripts/state.sh plugins/*/hooks/*.sh plugins/closeout/hooks/lib/config.sh \
    plugins/projects/hooks/lib/*.sh plugins/projects/scripts/*.sh plugins/scheduler/scripts/*.sh plugins/closeout/scripts/*.sh pilot/*.sh \
    tests/run.sh tests/sections/*.sh tests/sections/lib/*.sh
```

A pipe whose reader can stop before its writer is done (`awk` with `exit`, `head`, `grep -q` or `-m`,
`sed`'s `q`, a lone `read`) is the one shape shellcheck does not flag that the kit keeps out. bash writes
a line at a time, so the writer's next line can meet a closed pipe: the pipe then fails under
`pipefail`, and where SIGPIPE is ignored, as on CI, bash prints `write error: Broken pipe`. It happens
only when the reader wins the race, which is why a passing run proves little. The kit's forms are a
here-string for a variable (`awk '…' <<<"$var"`, not `printf '%s\n' "$var" | awk '…'`), and a reader
that reads to the end for a command (`sed -n 1p` for `head -n 1`, a flag in place of awk's `exit`,
`grep … >/dev/null` for `grep -q`). Section 11 looks for the shape in every script the kit ships.

## Along with the change

- A changed command or hook updates its page in `docs/commands/` or `docs/hooks/`; section 12 checks
  every command and hook has one, in the four parts.
- A change to anything under `templates/` goes in the CHANGELOG entry's `### Template changes` list,
  which `kit/setup.sh update` shows a team before it offers the diff.
- Guidance states norms as facts about how the work is done. `docs/documentation-register.md` has the
  rule, and section 8 of the suite fails capitals used for emphasis.
- Scripts run under macOS's `/bin/bash` 3.2: no associative arrays, no `mapfile`.
