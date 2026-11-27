# /workspace:commit-plan

*Paste-ready git commands that commit the workspace's uncommitted work in logical chunks, each with a
message to rewrite. Source: `plugins/workspace/commands/commit-plan.md`.*

## What it does

- Reads every repository in the workspace: the root, each submodule, and each project or area marked
  `Versioned: own-repo`, found where `.claude/projects.md` says projects and areas live. It leaves out anything untracked or sensitive, naming it in a line if it has
  changes.
- Reads the diffs and groups the changes by what they do, not by folder: a decision and the README line
  that records it go together, two unrelated changes in one file are split with `git add -p`.
- Sets aside secrets and local config, generated artefacts, work that may still be in progress, and
  anything it cannot explain, each with a line saying why and a `.gitignore` line where one fits.
- Hands over one fenced block per chunk, chained with `&&` so a failed step stops it before it commits:
  a `cd` with an absolute path, `git add` with exact, quoted paths, one to a line, and `git commit -e`
  with a short suggested message. Lines stay at about 70 characters, joined with a trailing `\`, so
  a block pastes whole from a terminal. It accounts for anything already staged, and
  says so when a merge or rebase is in progress. Then the pushes, innermost submodule first, with a
  `push -u` line for a branch that has no upstream yet.
- Runs no `git add`, `commit`, `push`, `stash` or `checkout` itself, and takes no lock another session
  could trip on.

## When to reach for it

At the end of a day or a session, before a push, or whenever `git status` has grown longer than you
want to sort by hand.

## Common questions

**What happens at the commit?** It opens your editor with the message filled in; save and close to
commit, or empty the message to cancel.

**Why doesn't it commit for me?** Writing or editing the message is how you check you understand what
changed. The suggestions are a starting point.

**What about changes inside `kit/`?** The kit is read in place, so they are listed under Leave for now
as a pull request to the kit, unless the workspace was set up for developing it. A moved `kit` pointer
is the workspace's to commit.

**A hook refused a commit.** The fix is in the change or the plan, never `--no-verify`. Ask again with
the hook's message and the plan is redone around it.

**Does it run in Cowork?** Yes, as the `kit-workspace-commit-plan` skill that `kit/setup.sh skills`
writes; the reads run in the device shell under the workspace mount.

## It's working if

- Each block runs as pasted, in the order given, in any terminal, and stops at the first step that fails.
- No block stages a secret, an artefact, or a file it did not name.
- Everything already committed and pushed gives a one-line answer.
