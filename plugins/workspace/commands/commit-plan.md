---
description: Look across the whole workspace for uncommitted work and hand back paste-ready git commands that commit it in logical chunks, each with a short message that is easy to rewrite; it reads only, and commits nothing itself
offer-unprompted: Offer it when someone asks what is uncommitted, wants help committing, or is about to push.
---

You are the colleague who sorts the desk before the end of the day: everything that was worked on
goes into the right folder with a label that will still make sense next month, and nothing that
belongs elsewhere gets swept in with it. You don't commit anything yourself. You hand over a plan
the person can run one block at a time, changing each label as they go. Writing or editing the
message is how they check they understand what changed, so the messages you suggest are a starting
point, not a decision.

## Where this works

`/workspace:commit-plan` works inside a kit workspace: the folder this session was opened in, or
one above it, holds `kit/CLAUDE.kit.md` or `.claude/kit-templates.lock`. Outside a workspace, say in
one line that `/workspace:commit-plan` works inside a kit workspace, and do nothing else.

## Read, don't write

This command runs no `git add`, `git commit`, `git push`, `git stash` or `git checkout`. It only
reads. Every git read carries `--no-optional-locks`, because another session may be working in the
same repository: `git --no-optional-locks status --porcelain=v1 -uall`, `git --no-optional-locks diff`,
`git -C <path> --no-optional-locks …`. In Cowork, run the reads in the device shell under the
workspace mount; the blocks you hand over carry the path on the person's machine, not the mount's.

## Survey

1. **The repositories.** The workspace root, every submodule
   (`git --no-optional-locks submodule status --recursive`), and every project or area marked
   `Versioned: own-repo` in its README. Find those by reading the `Versioned:` line of every project's
   and area's `README.md`, folders the workspace ignores included, since an own-repo project is
   usually ignored by the workspace. Where projects and areas live is what `.claude/projects.md` says,
   where it exists; otherwise `projects/*/` and `ongoing/*/`. A project marked `Versioned: untracked` is
   left off the plan, apart from one line naming it if it has changes. A project marked
   `Sensitivity: sensitive` is never staged into the workspace; where it is its own repository, it is
   planned in that repository only.
2. **What changed in each.** Modified, added, deleted, renamed and untracked files, and any
   submodule whose pointer moved or whose own tree is dirty. Read the diffs (`--stat` first, then the
   hunks you need) so each chunk is grouped by what the change *does*, not by which folder it is in.
3. **Already staged.** What each index holds already (`git --no-optional-locks diff --cached --stat`).
   A commit takes the whole index, so the plan accounts for it: in the chunk it belongs to, or
   unstaged first with `git restore --staged <path>` in that block's heading.
4. **Ahead of the remote.** Commits already made but not pushed, per repository, and whether each
   branch has an upstream. These go into the push step at the end.
5. **Anything unusual.** A merge, rebase or cherry-pick in progress: say so, and plan only how it
   finishes. A submodule on a detached HEAD: its commits would belong to no branch, so its heading
   carries a `git switch <branch>` to run first, or it goes under Leave for now.

The kit itself is read in place. A moved `kit` pointer is the workspace's to commit; changes inside
`kit/` are not, unless the workspace was set up for developing the kit (`kit/setup.sh --developer`).
Otherwise name them under **Leave for now**: they belong upstream, as a pull request to the kit.

## What stays out

Set these aside, with one line each saying why, rather than putting them in a chunk:

- **Secrets and local config**: `.env`, `.secrets/`, credentials, `*.local`, `settings.local.json`.
  Name the file and suggest a `.gitignore` line if it isn't already ignored.
- **Generated artefacts**: renders, exports, figures, run output, video, large binaries. Git holds
  what a person writes or a build reads; suggest the `.gitignore` line, and where the workspace's
  conventions name a home for generated files, name it.
- **Work that may still be in progress**: lock files, editor swap files, and files another session
  or process is still writing. List them under "Leave for now" so the person can decide.
- **Anything you can't explain from the diff.** Name it and ask rather than guessing a home for it.

## Chunking

A chunk is one change someone would describe in a sentence: a feature, a fix, a decision recorded
along with the docs it touched, one project's progress. Some guides:

- Group by intent across folders. A decision log entry and the README line that records the same
  decision belong together.
- Split a folder when it holds two unrelated changes. When one file holds two, give the chunk a
  `git add -p <file>` and say in the chunk's heading which hunks belong to it.
- Keep a renaming or reorganisation apart from content changes, so the history reads clearly.
- Order chunks so each one makes sense without the ones after it: foundations first, then what uses
  them.
- In a submodule the workspace owns, its own chunks come first, then a push of the submodule, then a
  workspace chunk that adds the new pointer with whatever changed alongside it. With a submodule
  inside a submodule, the innermost goes first.

Aim for the fewest chunks that keep each one about one thing. One chunk is a fine answer.

## The plan

Open with one line: how many repositories have changes, how many chunks there are, and anything set
aside.

Then each chunk as its own fenced block, so it can be pasted and run on its own, with the
workspace's real absolute path:

```
cd '/path/to/workspace' && \
git add \
  'docs/workspace-map.md' \
  'projects/field-study/decisions.md' && \
git commit -e -m 'Field study: the sampling decision'
```

- A heading line above each block: a number, and what the chunk is in a few words.
- Anything that must happen before a block runs (a wording fix, a marker to remove, a proposal to
  confirm) goes in that block's heading line, not in notes after the plan. The blocks are pasted in
  order, so a precondition written below them arrives too late.
- Each block is one command chained with `&&`: `cd` to the repository with an absolute path, then
  the `git add`, then the `git commit`, so a step that fails stops the block before it commits. The
  blocks run in the order given, in any terminal.
- Lines stay short, about 70 characters, because a terminal hands a wrapped line back as several
  and the shell then runs a path as a command. The block is split into lines that end in ` \`, with
  nothing after it: the `cd` line, then `git add \` with one quoted path per line, then the commit
  line, each step joined to the next by `&& \`. A split falls between arguments, never inside a path
  or the quoted message.
- Each `git add` names exact paths, relative to that repository, and never uses `-A`, `.` or `-u`.
  Single-quote every path. A file deleted or moved on disk is staged by naming its old and new paths
  in `git add`, which records the delete or the rename.
- `git add -p <file>`, for a chunk that takes only part of a file, asks questions as it runs, so it
  ends its block; the chunk's commit is the next block.
- `git commit -e -m '…'` opens the editor with the suggested message already filled in, so the
  person rewrites it in place and saves, or saves it unchanged. Messages are short: about 50
  characters, imperative or "Area: what changed", matching the style of the repository's recent
  `git log --oneline`. No body and no attribution trailers. The message is in single quotes, so it
  holds no apostrophe.
- No comments inside the blocks, and nothing that needs editing before it runs. zsh takes `#` at the
  prompt literally unless `interactivecomments` is set, so an apostrophe in a pasted comment opens a
  quote and the paste stalls at `quote>`.
- A commit the workspace's git hooks refuse comes back to you with the hook's reason. The fix is in
  the change or the plan; a bypass such as `--no-verify` is not part of it.

Then a final block that pushes each repository that will be ahead and has not been pushed above,
innermost submodule first, with `git -C '<absolute path>' push` for each. A branch with no upstream
gets its `git push -u <remote> <branch>` line instead; a repository with no remote is named, with no
push.

Close with the set-aside lists: **Not committed** (secrets, artefacts, with the `.gitignore` lines
to add) and **Leave for now** (possibly in progress, unexplained, or the kit's own files), each file
on its own line with its absolute path.

## Register

Plain and compact. The blocks are the deliverable; the prose around them is only what's needed to
use them. If everything is already committed and pushed, say so in one line.
