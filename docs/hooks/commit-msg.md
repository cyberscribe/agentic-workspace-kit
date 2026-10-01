# commit-msg (git)

*In the kit's own repository, the commit message is checked for the private word list and for
attribution trailers. Source: `githooks/commit-msg`.*

## What it does

Git passes the file holding the message being committed. The hook works out its context as the other
kit hooks do:

| Context | What it checks |
|---|---|
| The kit's own repository | `scripts/check-paths.sh --message`: no word from the private word list or from the workspace's `.claude/private-terms.local`, and no attribution trailer, such as a co-author line naming an AI tool |
| The workspace | Nothing of the kit's; only the chained hook |
| A project repository | Nothing of the kit's; only the chained hook |

The private word list is found in the same order everywhere the kit looks for it: `AW_BANNED_WORDS_FILE`,
then the `Private word list` line in the workspace's `.claude/workspace.md`, then
`~/.config/agentic-workspace-kit/banned-words.txt`. With no list, it notes that the word check did not
run and goes on. A list that is named but cannot be read, or that sits inside the kit, refuses. A
word found is never printed: the finding names the message and the line.

A refusal prints `aw commit-msg: refused <n> item(s)`, one line per finding, and
`Nothing was committed.` After its own check passes, it runs the repository's earlier commit-msg hook,
with the same arguments.

## When to reach for it

It runs by itself on every commit in `kit/` once `kit/setup.sh hooks` (or `kit/setup.sh --developer`)
has set the hooks. It matters most to someone committing a change to the kit, whether the kit's
developer or a contributor working from a fork (see `CONTRIBUTING.md`).

## Common questions

**Why only in the kit?** The kit is public. The workspace is private, and its commit messages are the
team's own business; a hook the team already had for them still runs.

**The message was refused. Is my work lost?** No. Git keeps the staged changes; fix the message and
commit again. `git commit -e -F "$(git rev-parse --git-dir)/COMMIT_EDITMSG"` starts from the refused
message.

**I have no private word list. Is that a problem?** No. The attribution check still runs, and the note
says the word check did not. A contributor can keep a list of their own at the path above.

## It's working if

- A kit commit whose message carries an attribution trailer is refused as `attribution trailer`.
- An ordinary kit commit message passes with no output beyond any word-list note.
- Commits in the workspace are unaffected by this hook.
