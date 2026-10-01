# projects session-start (SessionStart)

*The projects plugin's line that says where a folder's project stands when a session opens in it.
Source: `plugins/projects/hooks/session-start.sh`, wired in `plugins/projects/hooks/hooks.json`
(matcher `startup|resume`, timeout 5 seconds).*

## What it does

**Inside a project folder** whose entry point (by default `README.md`, as `.claude/projects.md` sets)
carries a Current state block, it shows three lines:

```
Project: field-study — outcome: <the desired outcome>
Done when: 2 of 5 ticked
State: doing — owner Sam
```

A blocked project names what blocks it and since when; a finished one gives its date. When the README
names resources under `## Resources` that this machine has not mapped in `.claude/resources.local.md`,
a fourth line names them and `kit/setup.sh link <slug>`, once per set of unmapped names per machine.

A folder listed under **Not adopted** in `.claude/projects.md` with no Current state block gets a note
for the agent only: it is not offered `/projects:adopt` unprompted.

**Anywhere else** in the repository it says nothing, except at most once a day: one line naming the
active projects blocked for more than 14 days, pointing at `/projects:board`.

The lines go out twice: as a message the person sees, and as context the agent reads.

## When to reach for it

It runs by itself once the projects plugin is installed. Open a session in a project's folder to get
the line; open one at the repository root for the once-a-day check.

## Common questions

**The line says "no Desired outcome section found" or "no checklist found".** It reads what it can
parse. `/projects:adopt` adds the missing sections, or a **Section names** line in
`.claude/projects.md` records the team's own heading.

**It says "from an older Now block".** The README keeps the earlier format; `/projects:adopt` offers
the conversion.

**How is it turned off?** `PROJECTS_HOOK_DISABLED=1`. It is also silent in a headless run
(`AW_HEADLESS_RUN=1`), which records no stamp. The once-a-day and resource stamps live in
`~/.claude/projects-hook` (`PROJECTS_HOOK_STATE_DIR`), outside any repository.

**Can it hold a session up?** No. It needs `jq`, makes no network call, and any failure is silent:
every path out exits 0 with nothing on stderr.

## It's working if

- A session opened in a project folder shows the three lines, matching its README.
- Editing the README's Current state block changes the line in the next session.
- A second session on the same day at the root says nothing more.
