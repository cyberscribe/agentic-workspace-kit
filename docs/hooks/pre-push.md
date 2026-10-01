# pre-push (git)

*Where a push may go, and in the kit, what each pushed commit may hold. Source: `githooks/pre-push`,
with `githooks/lib/common.sh`.*

## What it does

Git passes the remote's name and URL, and one line per ref being pushed. The URL is normalised
(`github.com/<owner>/<repo>`, or `local:<path>`), with any user or token left out of every message.

| Context | What it checks |
|---|---|
| The workspace | The remote has to be confirmed private: GitHub says `PRIVATE` or `INTERNAL` (asked with `gh`, within 10 seconds), or it is listed under Private remotes in `.claude/workspace.md`, or it is a local path under the temporary folder. A remote GitHub reports as public is refused |
| A project repository (own-repo, or a standalone repository in a project folder) | Confirmed private as above; or listed as a Public remote in `.claude/workspace.md` on a line that names this project's folder, for a project whose README does not say `Sensitivity: sensitive`. A sensitive project goes only to a confirmed private remote |
| The kit's own repository | No visibility rule, since the kit is public. Every commit each ref sends is checked, one at a time, by `scripts/check-paths.sh` with the content rules; with `aw.mirror.<remote>.prefix` set, paths are judged under that prefix |

A Private remote line written by a person (`via person`) is trusted only when someone is at a terminal,
so an unattended push without `gh` cannot rest on it. A refusal says why and ends with
`Nothing was pushed.` After its own checks pass, it runs the repository's earlier pre-push hook, with
the same arguments and stdin.

## When to reach for it

It runs on every `git push` once `kit/setup.sh hooks` has set the hooks. Setup's stage 4 asks GitHub
about `origin` and records a private one in `.claude/workspace.md`, so pushes from a machine without
`gh` are allowed too.

## Common questions

**The push was refused as "not confirmed private".** Without `gh`, or with `gh` not answering, the
remote has to be listed under Private remotes. Run `kit/setup.sh` at a terminal: stage 4 confirms and
records it.

**I mean to push to a public remote, once.** `AW_ALLOW_PUBLIC=<normalised remote> git push …` allows
that one remote for that one command, and says so. It never covers a sensitive project.

**A project publishes to a public repository.** Add a Public remote line in `.claude/workspace.md` that
names the project's folder; `/projects:new` and `/projects:adopt` offer it. The same remote is refused
from any other folder's repository.

**A local folder remote was refused.** Only local paths under the temporary folder are allowed as they
are: a synced folder can be shared. List it under Private remotes once confirmed.

## It's working if

- A push to the workspace's private origin goes through with no extra output.
- A push of the workspace to a public repository is refused, naming the normalised remote.
- In the kit, `git push` checks each commit and names any refused path with its reason.
