# closeout-private (UserPromptSubmit)

*The closeout plugin's private marker: a message holding `#private` keeps the whole session out of the
closeout capture. Source: `plugins/closeout/hooks/closeout-private.sh`, wired in
`plugins/closeout/hooks/hooks.json`.*

## What it does

It reads each message as it is sent. When a message holds the word `#private` on its own (not inside a
longer word or tag such as `#private-notes`, nor in a path), it marks the session private:

- it writes a flag named by the session id, in `~/.claude/closeout-drafts/.private/` (or under
  `CLOSEOUT_DRAFT_ROOT`), outside any repository;
- it says so once, in one line the person sees ("Private session: closeout will keep no draft of it…"),
  and tells the agent the same, including how a `/closeout` in that session behaves;
- later mentions in the same session are quiet.

When the session ends, [closeout-capture](closeout-capture.md) finds the flag, removes it and keeps
nothing. It also reads the person's own messages in the transcript for the word, so a session whose
flag was never written still keeps nothing. With no draft, [closeout-review](closeout-review.md) has
nothing to say about the session next time.

## When to reach for it

Write `#private` in any message, at any point, when a session should leave nothing behind: something
personal, a confidential conversation, a draft you would rather not see summarised. It covers the
whole session, the part before the word included. A `/closeout` you ask for in that session still runs,
and asks before writing anything.

## Common questions

**Can a session be unmarked?** No. A session that was private in part is treated as private.

**Does it cost anything in an ordinary session?** No context: it prints nothing unless the word is
there. It runs on every message, and stops at a text match in bash before reading anything else.

**Does it run outside a kit workspace?** It stays silent there, since the capture keeps nothing outside
a workspace anyway (`hooks/lib/boundary.sh`).

**What about a sensitive project?** `Sensitivity: sensitive` keeps a project's files inside its folder
and out of the workspace's repository; the marker is per session, for anything.

## It's working if

- Writing `#private` shows the one-line confirmation, once.
- The session after a private one opens with no closeout draft offered for it.
- An ordinary session is captured as before.
