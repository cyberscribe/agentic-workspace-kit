# /workspace:unblock

*One card of what only you can do, right now, so the work in a session can move.
Source: `plugins/workspace/commands/unblock.md`.*

## What it does

- Looks back over the session for whatever needs you: a decision, a review, an approval held
  back, a command the session cannot run itself, or something only you have (a credential, a file, a
  fact).
- Clears what it can first (a stale check, a wrong path) and re-checks the rest against
  the live state, so the card is true when you read it.
- Orders the items by how much each one frees, and gives each a time, what it unblocks, why it needs
  you, and the action itself: a command ready to paste with real paths, the file to review with the
  question to look at it with, or a decision with lettered options and a recommendation.
- When nothing in the session is blocked, it says so in one line and makes one quick pass over work
  stalled elsewhere in the workspace: an unanswered question in a pairing's mailbox, unpushed commits,
  a scheduled run that needs a reply, a stale claim on a job board where the workspace keeps one.
- Sends nothing, and writes nothing beyond what it clears itself: reversible steps the session was
  already allowed to take.

## When to reach for it

When you come back to a session that has stopped, when you are about to step away and want to leave
nothing waiting, or whenever you want to know "what do you need from me?".

## Common questions

**Is it a status report?** No. Progress, findings and anything interesting but not blocking stay off
the card.

**Does it work outside a kit workspace?** No. Like the kit's other commands, it says in one line that it
works inside one. The pass beyond the session reads the workspace's own places: its pairing mailboxes,
scheduled runs and repositories.

**What about learnings nobody has written down?** They belong to `/closeout`, and drift in the
workspace to `/workspace:hygiene`; the card names one of them in a line when it is worth running.

**Does it run in Cowork?** Yes, as the `kit-workspace-unblock` skill that `kit/setup.sh skills` writes.
In Cowork a file to review is shown as a preview as well as by its path.

## It's working if

- You can act on the card top to bottom without opening a file to find out what it meant.
- Each command runs as pasted.
- An empty card is one line, and nothing on it is news rather than a blocker.
