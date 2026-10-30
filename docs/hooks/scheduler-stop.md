# scheduler stop (Stop)

*The scheduler plugin's Stop hook: when a session answers a run that is awaiting a reply, it records that
answer as the reply, so the run settles without `schedule.sh reply`. Source:
`plugins/scheduler/hooks/stop.sh`, wired in `plugins/scheduler/hooks/hooks.json` (timeout 5 seconds).*

## What it does

Each time a session stops, it reads the session's id from the hook input and looks for a waiting run that
owns that session: a run's session id is in its folder, and a waiting run has a marker in the state
folder. When one matches, it calls `schedule.sh record-answer`, which:

- takes the last thing the person wrote in the transcript as the run's reply, and the last thing Claude
  said as its result;
- settles the run `ok`, with `reply_via=session` in its meta, and removes the waiting marker;
- writes the result to the task's `result_to`, appended, as a `reply` does.

Without `jq` the transcript is named rather than read, so the reply records that the answer is in the
session. Nothing is called for any other session, so most stops cost one file read.

## When to reach for it

Answering a question in the desktop app or the terminal is the natural way to reply to a task that
asks one. Resuming the run's session and typing the answer there counts the same as `schedule.sh reply`.

## Common questions

**Why did it not record my answer?** It acts only inside a kit workspace (`hooks/lib/boundary.sh`, the
same rule as the kit's other hooks). A session in a folder outside one still needs `schedule.sh reply`.
It also does nothing while a reply or a run of that task is going on, and it does nothing if the run is
no longer waiting, for example after its reply window.

**Could it record a scheduled run's own end?** No. A scheduled run and a reply both set
`AW_HEADLESS_RUN=1`, and the hook exits on that; the runner also writes the waiting marker only after
`claude` has exited.

**Does it slow a stop down?** With a waiting run in the state folder but a different session, about 30 ms
on a Mac, most of it bash starting up. With nothing waiting, it is a single directory test.

**Does it print anything?** No. It is silent whether it records or not.

## It's working if

- A run that asked a question is awaiting a reply, and you answer in its session. Then `schedule.sh show
  <name>` shows the run `ok`, with `reply_via=session` in its meta and your answer under `Reply 1:` in
  `schedule.sh log <name>`.
- A second stop in the same session records nothing more.
- Any other session, a headless run, or a folder outside a workspace leaves the run waiting.
