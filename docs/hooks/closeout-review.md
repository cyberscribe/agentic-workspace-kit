# closeout-review (SessionStart)

*The closeout plugin's pointer at drafts a previous session left: it asks the agent to raise them in
its first response. Source: `plugins/closeout/hooks/closeout-review.sh`, wired in
`plugins/closeout/hooks/hooks.json` (matcher `startup|resume`).*

## What it does

When a session starts or resumes, it looks in `~/.claude/closeout-drafts/<folder name>/` (or under
`CLOSEOUT_DRAFT_ROOT`) for drafts written by [closeout-capture](closeout-capture.md). With none, it says
nothing. With some, it adds context for the agent, not a line on screen, asking it to:

- raise the drafts in its first response and wait for the person's go-ahead before promoting or
  deleting any;
- check each technical claim against the code as it is now, since a draft may be stale;
- treat each draft's tier as a proposal, and name what a promotion into the always-loaded tier would
  displace;
- promote with surgical edits, then delete the draft.

It names the tiers to use (the project's, the person's, or the kit's table), points at the
conventions files, and, when two or more people are known, how to handle "who needs to know": present
the table (`auto`) or offer it in one line (`ask`).

**Retention.** Each draft gets a `.seen.<draft>` marker the first time it is surfaced. A draft whose
marker is older than `CLOSEOUT_DRAFT_RETENTION_DAYS` (3) is pruned the next time a session opens in
that folder. A draft nobody has been shown yet is kept, however old.

## When to reach for it

It runs by itself once the closeout plugin is installed. The person's part is to answer the agent's
offer: promote, edit, or let a draft go.

## Common questions

**I never see a message about drafts.** The hook speaks to the agent only (SessionStart's
`additionalContext`); the agent raises the drafts in its first response.

**Drafts for a project folder I no longer open are piling up.** Retention only runs when a session
opens in that folder. `/workspace:hygiene` lists such folders in its drafts sweep and gives the
commands to clear them.

**How is it turned off?** `CLOSEOUT_DISABLED=1`. It is also silent inside the capture child
(`CLOSEOUT_HOOK_CHILD`), and when `jq` is missing.

## It's working if

- The first response of a session opened after an uncaptured session offers the drafts it names.
- A draft offered and left alone for more than three days is gone after the next session in that
  folder.
- With no drafts pending, sessions start with nothing extra said.
