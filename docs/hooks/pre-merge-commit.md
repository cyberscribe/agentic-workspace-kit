# pre-merge-commit (git)

*The same checks as pre-commit, for a merge commit. Source: `githooks/pre-merge-commit`.*

## What it does

A merge that completes without conflicts makes its commit without running pre-commit. This hook closes
that gap: it runs [pre-commit](pre-commit.md) under its own name, so the same checks apply to what the
merge brings in, and its messages read `aw pre-merge-commit:`.

| Context | What it checks |
|---|---|
| The kit's own repository | The allow-list and content rules of `scripts/check-paths.sh` on the staged merge result, and the guard-file rule |
| The workspace | Sensitive projects' files, the size limit, and files force-added over `.gitignore` |
| A project repository | Only the chained hook |

A refusal ends with `Nothing was committed.` and leaves the merge in progress, for the person to fix or
abort. After its own checks pass, it runs the repository's earlier `pre-merge-commit` hook, if there
was one.

A merge that stops on conflicts is finished with `git commit`, which runs pre-commit itself.

## When to reach for it

It runs by itself on `git merge` and `git pull` (when the pull merges) once `kit/setup.sh hooks` has
set the hooks. Most often it matters in the workspace, when a teammate's branch brings in a file under
a project that has since been marked sensitive.

## Common questions

**The merge was refused. What state is the repository in?** The merge is not committed. Fix what the
refusal names, then `git commit`, or `git merge --abort` to go back.

**Does it check the commits on the other branch one by one?** No. It checks the merge result being
committed, as pre-commit checks the index. In the kit, the commits a push sends are checked one at a
time by [pre-push](pre-push.md).

**How are the settings the same as pre-commit's?** It is the same script. `AW_MAX_FILE_MB` and
`AW_GUARD_CHANGE` work the same way here.

## It's working if

- `ls "$(git rev-parse --git-dir)/aw-hooks"` lists `pre-merge-commit` beside the other three stubs.
- A clean merge of ordinary work completes as before.
- A merge that would add a file under a sensitive project folder is refused with that path named.
