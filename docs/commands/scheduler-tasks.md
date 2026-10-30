# /scheduler:tasks

*Scheduled Claude Code tasks that run on this machine and outlast the session: a plain request becomes
a task file and a unit in the machine's own scheduler. Source: `plugins/scheduler/commands/tasks.md`,
with the script `plugins/scheduler/scripts/schedule.sh` and its `port` step in `scripts/lib/port.sh`.*

## What it does

- Turns "every weekday at 7:30, summarise yesterday's commits into notes/daily.md" into a schedule
  in local time, a folder to run in, a prompt written for a run nobody watches, and the smallest set
  of allowed tools, asking only what it cannot infer: usually the tools, since runs use
  `permission_mode: dontAsk`.
- Shows the task file and its next three fire times as a dry run, and writes it on a yes. The unit
  goes into launchd on macOS, systemd user timers on Linux, or a marked block of the crontab elsewhere.
- Answers the everyday questions through the same script: `list`, `show`, `edit`, `pause`, `resume`,
  `run` now, `delete` (to `tasks/.trash/`), `runs --since` for what ran overnight (late runs marked),
  `log` for why one failed, `reply` for a run awaiting the person, `report` for a week's due fires,
  runs, late runs and misses, and `doctor`.
- Moves tasks from a cloud scheduler with `port`: an export, then start, check, trial (a real run on a yes),
  activate and cloud-paused, each step decided by the script and kept in a ledger. A moved cloud task
  is paused, never deleted, and `port rollback` goes back to it.

## When to reach for it

For work that should happen at a time rather than now, on your own machine and from your own files: a
morning digest, a weekly tidy, a one-off reminder next Tuesday. Also to move a set of cloud scheduled
tasks home. Claude Code's `/schedule` runs routines in the cloud and its session cron tools end with
the session; this one is local and lasts.

## Common questions

**What happens when a run fails?** It is retried once by default, each attempt judged in full (a failed
`verify` or a denied tool counts), then recorded as failed with its stderr, a desktop notification says
so, and the next session in a kit workspace names it. A billing refusal is never retried. After three
failed runs in a row the task pauses itself, with the reason in its file. `log <name>` shows why.

**Can a run wait for me?** A task with `awaits_reply: true` ends a good run `waiting`;
`reply <name> '<answer>'` continues that run's session, here or from any later session.

**What if the machine was asleep?** systemd timers catch up at the next start, and launchd starts a
missed calendar job when the Mac wakes; `runs` marks such a run `late`, and `doctor` gives the
`pmset` wake command to run yourself. A run already going is never doubled.

**Time zones?** Local time, or a `CRON_TZ=` prefix; another zone than the machine's works on systemd,
and launchd and cron refuse it with a line saying so.

**Does porting send anything?** Only the trial, which is a real run with the task's own tools, so it
asks first (`--plan` is a look that changes nothing). The cloud task is paused only on your yes, and
stays recorded `double-run` until it is. Nothing deletes it.

## It's working if

- `schedule.sh show <name>` says the unit is installed and matching the file, with fire times.
- After its first fire time, `schedule.sh runs <name>` lists a run with status `ok`.
- `schedule.sh doctor` ends with "No problems.", and `port status` ends with every row cloud-paused.
