# scheduler session-start (SessionStart)

*The scheduler plugin's line that says, when a session opens in a kit workspace, which scheduled tasks
need the person. Source: `plugins/scheduler/hooks/session-start.sh`, wired in
`plugins/scheduler/hooks/hooks.json` (matcher `startup|resume`, timeout 5 seconds).*

## What it does

It reads the scheduler's state folder and task files, and nothing else: no `claude` call and no call to
launchd, systemd or cron. When something needs the person it prints one line, for example:

```
Scheduler: daily-commits failed since the last session (schedule.sh log daily-commits); news-scan awaiting your reply (schedule.sh reply news-scan '<your reply>').
```

- **Failed runs**, failed or timed out, since the last session started on this machine.
- **Tasks that paused themselves** after failing in a row, since then.
- **Runs awaiting a reply**, for as long as they wait and their reply window is open.

The same line goes to the agent with the script's path, so asking `/scheduler:tasks` about it works
straight away. It records when it ran, so the next session reports only what is new, apart from
runs still waiting.

## When to reach for it

It runs by itself. It is the counterpart of opening a cloud scheduler's task list in the morning:
anything that went wrong overnight, or is awaiting you, is said once, where you are already working.

## Common questions

**Why nothing?** Nothing failed, paused itself or is waiting since the last session. Or the session is
outside a kit workspace (`hooks/lib/boundary.sh`, the same rule as the kit's other hooks), or it is a
run nobody watches (`AW_HEADLESS_RUN=1`), which includes every scheduled run, so a run does not report
on itself. `SCHEDULER_HOOK_DISABLED=1` silences it.

**It reported a failure I have already looked at.** It reports each once: the next session starts
from when this one did. A run still waiting is the exception, since it still needs you.

**Does it slow the session down?** It reads small files with shell built-ins; the suite holds it under
100 ms.

**The first session after installing.** With no record of a last session, the last day counts.

## It's working if

- After a scheduled run fails, the next session opened in the workspace starts with a `Scheduler:` line
  naming the task and `schedule.sh log <name>`.
- The session after that says nothing more about it.
- A run awaiting a reply is named in every session until `schedule.sh reply` answers it.
