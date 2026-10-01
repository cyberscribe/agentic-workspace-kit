# workspace session-start (SessionStart)

*The workspace plugin's summary of what is out of step in the workspace, one line per item, each
naming the command that fixes it. Source: `plugins/workspace/hooks/session-start.sh`, wired in
`plugins/workspace/hooks/hooks.json` (matcher `startup`, timeout 10 seconds).*

## What it does

It finds the workspace from the session's folder: the nearest folder, upward, that holds
`kit/CLAUDE.kit.md` or `.claude/kit-templates.lock`. A session opened inside `kit/`, or inside a project
that is its own repository, reports on the workspace around it; one opened anywhere else reports
nothing. It reads the workspace through `kit/plugins/workspace/bin/state.sh --quick`, which makes no
network call and takes no lock, and prints a line only for what is off:

```
Workspace: git hooks are not active — kit/setup.sh hooks turns them on.
Workspace: CLAUDE.md does not import the kit's standards — its first line is @kit/CLAUDE.kit.md.
Workspace: kit/ is detached from main (developer mode) — kit/setup.sh --developer puts it back.
Workspace: kit: pointer changed, not committed.
Workspace: 1 gitlink has no .gitmodules entry (<path>) — kit/setup.sh migrate --dry-run names the two fixes.
Workspace: 2 resources not reachable on this machine (<slug>/<name>, …) — kit/setup.sh link.
Workspace: 1 sensitive project has files tracked by the workspace (<slug>) — /projects:adopt <slug> untracked.
Workspace: origin is not confirmed private — kit/setup.sh records it once confirmed.
Workspace: the kit is 3 commits behind its remote — kit/setup.sh update.
```

When the kit's plugins are not loaded for this person but the skills bridge's `kit-` skills are in
`.claude/skills/`, one line says so and names `claude plugin install <plugin>@agentic-workspace`.

A workspace in step gets nothing. The lines go out as a message the person sees and as context the
agent reads.

## When to reach for it

It runs by itself once the workspace plugin is installed, at the start of each new session (not on
resume). Read its lines as a to-do list for the terminal: each names the command to run.

## Common questions

**A submodule line lists several things.** They come in a fixed order: changed files, commits not
pushed, pointer changed and not committed, commits behind its remote, detached. Commit and push
inside the submodule first, then commit its pointer in the workspace.

**How is it turned off?** `WORKSPACE_HOOK_DISABLED=1`. It is also silent in a headless run
(`AW_HEADLESS_RUN=1`) and inside the closeout capture child (`CLOSEOUT_HOOK_CHILD`).

**It said nothing, but I expected a warning.** It needs `jq`, and any failure is silent by design:
the summary is a convenience, never a gate. `bash kit/plugins/workspace/bin/state.sh --quick` shows the
keys it reads.

## It's working if

- A freshly set-up workspace opens with no `Workspace:` lines.
- Running the command a line names, then opening a new session, makes that line go.
- A session opened in a folder outside any workspace shows nothing from it.
