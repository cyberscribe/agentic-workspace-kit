# scheduler pane (hooks module)

*The scheduler plugin's Scheduled tasks pane: a panel beside the chat that lists what needs your answer,
what needs attention, and every task. Source: `plugins/scheduler/hooks/pane.tsx`, named under `modules` in
`plugins/scheduler/hooks/hooks.json`. Rides on Claude Code's early-access plugin API.*

## What it does

Opens a pane titled "Scheduled tasks" with the `/scheduler-pane` slash command. It draws, in order:

1. **Needs your answer**, first, when a run is awaiting a reply: the task, how long it has waited, the question
   (the run's result, trimmed), an answer field that calls `schedule.sh reply`, and an Open session button that
   shows the `claude --resume <session id>` command. The button does not run it.
2. **Needs attention**: failed, denied, timed-out or self-paused tasks, each with its reason and a View log button.
3. **All tasks**: name, status, schedule, next fire, last run, and Run now, Pause or Resume, and View log.
4. **Footer**: backend, tasks folder, and the time the pane last refreshed.

On the terminal the pane is a list that takes the keyboard when it opens: a row per task, Up and Down to move,
Enter or a row's digit to open one, and `r` run now, `p` pause or resume, `l` log for the row the cursor is on,
drawn on screen with their keys. Each row leads with a state word; more tasks than fit scroll as a window with
`↑ N more` and `↓ N more` rows and the position in the key line. A key says what it started at once and the
result follows on its own line. An open task lists its actions one under another; its log scrolls a line at a
time like a pager; a waiting run's shows the whole question with the answer field focused, so answering is type,
then Enter. Escape goes back from a task to the list, then closes the pane. The pane asks for all the height it
can get and fits itself to it, and its first open draws the last list it read while it reads the new one. In fullscreen
from 110 columns Claude Code docks the pane in a column beside the conversation; rows are cut, keys never.
When the terminal has no room to seat a pane, the same view is drawn in the band above the prompt, with `c` to
close it.

Every action is a `schedule.sh` call, and its output is shown in the pane. The pane reads through `schedule.sh`
(`list`, `show`, `log`, `home`) and keeps what it read in the plugin's state atom, which persists, so it is
not stateless. It has no delete action; deleting stays in the CLI.

It acts only inside a kit workspace. Outside one, the pane says so, and the command says the CLI works anywhere.

## When to reach for it

When you want the scheduler's state in view while you work, rather than at the start of a session. The
session-start line tells you once; the pane stays put and answers a waiting run in place. On a phone it shows
the same lists with buttons only, and a waiting run says how to answer it from a Mac.

## Common questions

**Is it the same as `/scheduler:tasks`?** It reads the same data and makes the same calls. The pane is a view
over `schedule.sh`; `/scheduler:tasks` is a conversation that can also create, edit and delete tasks.

**How fresh is it?** It refreshes when it opens, after each action, and every 60 seconds while it is placed.
The footer shows the time of the last refresh. A closed pane runs no timer.

**Does it run anything on its own?** No. Scheduled runs happen in the machine's own scheduler, as they always
did. The pane reads state on open, after each action, and every 60 seconds while it is placed, so a session with the pane
open makes those reads without a press. The actions it offers are the ones you press for.

**The pane stopped working after a Claude Code update. Are my tasks affected?** No. The early-access API
can change between releases. The tasks, their runs and the CLI do not depend on the pane.

## It's working if

- The `pane` command opens a "Scheduled tasks" pane, and the footer shows the backend and tasks folder.
- A run that needs an answer appears under "Needs your answer" with its question. Answering it leaves `schedule.sh show <name>`
  reporting the run `ok`.
- On the desktop app, Run now, Pause and Resume each show the `schedule.sh` output in the pane, and the task list
  matches `schedule.sh list` afterwards.
- On the terminal, Down then `p` pauses the second task: its row then reads `paused`, and `schedule.sh list`
  agrees. Enter opens a task and Escape comes back to the list.
- Outside a kit workspace, the pane states that it works inside one.

**If the pane breaks:** `schedule.sh` and `/scheduler:tasks` stand on their own. Every action the pane offers is
one of their commands, so `schedule.sh list`, `schedule.sh reply <name> --run <id> --file -` and
`schedule.sh run <name>` do the same work.
