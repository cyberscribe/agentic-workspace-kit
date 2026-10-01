# pre-commit (git)

*The kit's pre-commit hook: what may be committed, decided by which repository the commit is in.
Source: `githooks/pre-commit`, with `githooks/lib/common.sh`.*

## What it does

Git runs it through a small stub that `kit/setup.sh hooks` writes into each repository's git folder
(`<git dir>/aw-hooks/`), with `core.hooksPath` pointing there. The stub finds the kit's hook of the same
name, in the kit itself or in the nearest `kit/` folder above, and runs it. The hook then works out its
context and checks the staged changes:

| Context | What it checks |
|---|---|
| The kit's own repository | Every staged path and added line through `scripts/check-paths.sh`: the allow-list of kit folders and root files, private-by-name and data-shaped files, symlinks, anything the workspace's `.gitignore` lists, binaries and size, the private word list, names derived from the workspace, and verbatim copies of workspace files. A change to the guard files themselves (`scripts/check-paths.sh`, `githooks/`, `.github/`, `lib/common.sh`) needs `AW_GUARD_CHANGE=1` |
| The workspace | A sensitive project's files are refused (its README says `Sensitivity: sensitive`, in the working tree or in `HEAD`), and so is a file in a project folder with no README or CLAUDE.md to say. No file over `AW_MAX_FILE_MB` (25) goes in. A file added with `git add -f` over `.gitignore` is named, and allowed. Gitlinks and deletions pass |
| A project repository | Nothing of the kit's; only the chained hook below |

Every check ends allowed, refused or could-not-run, and could-not-run refuses: a check that cannot
look is not a check that passed. A refusal prints `aw pre-commit: refused <n> item(s)`, one line per
item with its reason, and `Nothing was committed.`

After its own checks pass, it runs the hook that was in effect before the kit set its own (kept as
`aw.chainHooksPath`, else the repository's `.git/hooks/pre-commit`), with the same arguments and stdin.

## When to reach for it

It runs on every `git commit` once `kit/setup.sh` (stage 4) or `kit/setup.sh hooks` has set it up. Run
`kit/setup.sh hooks` again after a clone, after adding a project repository, or when the session-start
summary says the hooks are not active.

## Common questions

**It refused a sensitive project's file. How do I commit it?** Not in the workspace. Keep the project
untracked or in its own private repository: `/projects:adopt <slug> untracked` (or `own-repo`). A
change of a README from `sensitive` to `normal` goes in a commit of its own first.

**A file is over the size limit.** Name large material under `## Resources` in the project README, and
map it per machine with `kit/setup.sh link`. `AW_MAX_FILE_MB` sets another limit.

**It says the kit's hooks are not reachable.** The kit is not initialised, or the folder moved:
`git submodule update --init kit`, then `kit/setup.sh hooks`.

**Can I skip it?** git's `--no-verify` is the person's own choice. An agent in Claude Code is held back
from it by the [guard-git](workspace-guard-git.md) hook, and reports the refusal instead.

## It's working if

- `kit/setup.sh hooks --check` prints only `ok` lines and exits 0.
- `git config core.hooksPath` names the repository's own `aw-hooks` folder.
- Staging a file under a sensitive project folder and committing is refused, with the project named.
