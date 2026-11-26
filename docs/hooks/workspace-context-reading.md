# workspace context reading (hooks module)

*The workspace plugin's record of how full the context window is after a session's first turn. Source:
`plugins/workspace/hooks/context-reading.tsx`, named under `modules` in
`plugins/workspace/hooks/hooks.json`; read back by `plugins/workspace/scripts/context-readings.sh`. Rides on
Claude Code's early-access plugin API.*

## What it does

After the first turn of each session inside a kit workspace, it reads the figure the status line shows (the
tokens the context window holds, and the window's size) and appends one line to
`${XDG_STATE_HOME:-~/.local/state}/agentic-workspace-kit/workspace/context-readings.tsv`, outside every
repository: the time with its UTC offset, the tokens, the window, the workspace folder, the plugins with
commands in the session, and the surfaces it drew on (`headless` for a `-p` run). One line per session; later
turns add nothing. The figure is the engine's own measurement, so reading it costs nothing.

`context-readings.sh [<repository>]` prints the last five readings for that workspace, newest last, leaving
out headless runs: a scheduled task's first turn is its task, not a fresh session. `AW_CONTEXT_READINGS`
changes how many.

## When to reach for it

The weekly hygiene report puts the last readings beside the plugin cost. Read them as a trend: a jump from one
week to the next says something new is riding into every session, and the plugin cost and the always-loaded
budget then say whether it is a plugin's listing or a file.

## Common questions

**Is it the same as the plugin cost?** No. `plugin-cost.sh` is Claude Code's estimate of each plugin's
always-on listing: the names and descriptions of its skills, commands and agents. A reading is the whole
window after one turn: the system prompt, tools, skills, memory files, what the session-start hooks printed,
and the first exchange. Measured on Claude Code 2.1.332 in a scratch workspace, the kit's five plugins added
about 1,900 tokens of skills (their listing, as the plugin cost counts it) and 7,800 of messages headless,
mostly what their session-start hooks printed, which the plugin cost leaves out.

**How steady is it?** In one setup, repeated: headless runs agreed within 53 tokens, and interactive runs with
the kit's plugins agreed within 2. Without them, interactive runs fell into two readings 2,338 tokens apart.
Real sessions vary more, with the workspace's state and the first prompt, so a single reading is not a measure.

**Does it slow a session?** It runs once, after the first turn: one list of commands and one short shell call.

**What leaves the machine?** Nothing. The file is local, and the hygiene report shows tokens, times and plugin
names, never the folder.

## It's working if

- After a session's first turn in the workspace, `context-readings.sh` prints a `reading` line with today's
  time, and a second turn in the same session adds none.
- Outside a kit workspace, a session adds no line.
- With no readings for the workspace, it prints `no readings yet`.
