# closeout-capture (SessionEnd)

*The closeout plugin's end-of-session backstop: a separate, detached run reads the session that just
ended and writes candidate doc notes to a draft outside the repository. Source:
`plugins/closeout/hooks/closeout-capture.sh`, wired in `plugins/closeout/hooks/hooks.json`.*

## What it does

When a Claude Code session ends, the hook starts a headless `claude -p` in the background and returns
at once, so the person's exit is never held up. That child:

- reads the session transcript and keeps only durable learnings: decisions, non-obvious constraints,
  the state of work in progress, gotchas;
- classifies each by tier and scope, using the project's own promotion tiers (`.claude/closeout.md`),
  the person's (`~/.claude/closeout.md`), or the kit's default table, in that order of precedence;
- writes them to `~/.claude/closeout-drafts/<folder name>/<session id>.md`, one section per item with
  its tier, scope, destination and reason; when nothing durable was learned, it is told to write no
  file at all;
- ends the draft with a "Who needs to know" section when two or more people are known for the
  repository and the setting is not `off`.

The child runs from the drafts folder with the Read and Write tools only, so the repository is not
one of its auto-approved folders. It proposes; a person approves before anything is promoted.

It does nothing when the session ended with `/clear`, when there is no transcript, when the transcript
is under `CLOSEOUT_MIN_LINES` lines (6), when `jq` or `claude` cannot be found, or when `/closeout`
already ran in that session (its sentinel, if under six hours old).

## When to reach for it

It runs by itself once the closeout plugin is installed. It is the safety net for a session that ends
without `/closeout`; running `/closeout` in the session is still the better pass, since the session's
own context is there.

## Common questions

**Where do the drafts show up?** The next session opened in the same folder is pointed at them by the
[closeout-review](closeout-review.md) hook.

**How is it turned off?** `CLOSEOUT_DISABLED=1` in the environment. Other settings:
`CLOSEOUT_DRAFT_ROOT` (the drafts folder), `CLOSEOUT_MODEL` (default `sonnet`),
`CLOSEOUT_CLAUDE_BIN` (the `claude` to run) and `CLOSEOUT_MIN_LINES`.

**Does the child start another capture when it ends?** No. It runs with `CLOSEOUT_HOOK_CHILD` set,
and the hook exits at once when it sees that.

**Does it run in Cowork?** No. Cowork does not load the kit's plugins or hooks, so there `/closeout`,
as the `kit-closeout` skill, is the whole ritual.

## It's working if

- After a substantial session ended without `/closeout`, a new `.md` file appears under
  `~/.claude/closeout-drafts/<folder name>/` shortly after, once the background run finishes.
- After a session that ran `/closeout`, no draft appears for it.
- Exiting Claude Code is no slower with the plugin installed.
