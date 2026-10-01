# workspace guard-git (PreToolUse)

*A Claude Code hook that keeps an agent from stepping around the workspace's git hooks. Source:
`plugins/workspace/hooks/guard-git.sh`, wired in `plugins/workspace/hooks/hooks.json` (matcher `Bash`,
timeout 5 seconds).*

## What it does

Before each shell command an agent runs, it reads the command text. It denies the command when a
`git commit`, `push`, `merge`, `rebase`, `cherry-pick`, `am` or `pull` also carries a bypass:

- `--no-verify`;
- after `commit`, a short-option cluster holding `n` (`-n`, `-an`, `-nm`);
- `-c core.hooksPath` or `core.hooksPath=`;
- a `GIT_CONFIG_` variable naming `hooksPath`.

It also denies a `git config` that changes `core.hooksPath`; reading it (`--get`, `--list` and the
like) is fine. Commands joined with `;`, `&&` or `|` are checked piece by piece.

A denied command does not run, and the agent is told why:

```
The workspace's git hooks decide what reaches a remote. Report the hook's refusal to the person
rather than bypassing it.
```

Every other command passes untouched. It reads its input as plain text, so it needs no `jq`, and input
it cannot read is let through silently.

## When to reach for it

It runs by itself once the workspace plugin is installed. It matters when a git hook refuses a commit
or push: the agent reports the refusal and its reason instead of retrying around it.

## Common questions

**Can I still use `--no-verify` myself?** In your own terminal, yes: this hook binds agents in Claude
Code, not people. The kit's own guidance treats a refused commit as something to report, not bypass.

**How do I set the hooks path, then?** `kit/setup.sh hooks` sets it, for the workspace, the kit and
each project repository. It sets the path inside the script rather than on the command line, so the
guard lets it through.

**How is it turned off for a session?** `AW_GIT_GUARD_DISABLED=1` in the session's environment.

**Does it run in Cowork?** No. Cowork does not load the kit's plugins or hooks; the git hooks
themselves still run on every commit and push, whoever makes them.

## It's working if

- An agent asked to commit with `--no-verify` is refused, and reports the refusal to you.
- `git status`, `git log` and ordinary commits and pushes run as before.
- `git config --get core.hooksPath` still answers.
