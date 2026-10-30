# scheduler — scheduled Claude Code tasks on this machine

A Claude Code plugin for the work you want done at a time rather than now: "every weekday at 7:30,
summarise the overnight build failures", "on the first of the month, tidy the downloads folder",
"once, next Tuesday at 6, draft the agenda". Each task runs on your own machine, from your own files,
started by the machine's own scheduler, and keeps running after the session that made it has ended.
The only network traffic is Claude itself and whatever tools you allow the task.

| Command | What it is for |
|---|---|
| **`/scheduler:tasks`** | Turn a plain request into a task, and look after the tasks you have: list, show, edit, pause, resume, run now, delete, explain what a run did or why it failed, answer a run awaiting you, and move tasks over from a cloud scheduler. |

And one hook: a session-start line, inside a kit workspace, naming the runs that failed and the tasks
that paused themselves since the last session, and the runs awaiting a reply
(`docs/hooks/scheduler-session-start.md`).

**The pane** is a hooks module (`hooks/pane.tsx`), not a hook. It rides on Claude Code's early-access plugin
API, which can change between releases; if it breaks, `schedule.sh` and `/scheduler:tasks` stand on their own.
Page: `docs/hooks/scheduler-pane.md`.

## The Scheduled tasks pane (early access)

`hooks/pane.tsx` is a hooks module that opens a "Scheduled tasks" pane in Claude Code, with the
`/scheduler-pane` slash command to open it. A hooks module names its command `/<name>`, not
`/<plugin>:<name>` the way the plugin's Markdown commands do, so the name carries the plugin's own name. The command is registered when the session starts. In the desktop app the composer can also show "isn't a command here" beside the pane's answer: the engine's composer, not the pane, does that, and the pane's answer is the one that runs. The pane shows what needs your answer (with an answer field and an Open session
action), the tasks that need attention (failed, denied or self-paused), and every task with Run now,
Pause or Resume, and View log. It reads only through `scripts/schedule.sh` (`list --json`,
`show --json`, `log`) and makes each action a CLI call whose output it shows. It has no delete action;
deleting stays in the CLI. On mobile it draws the same lists with buttons only.

On the terminal the pane is a view, not a control. Each task is one row of text, and a waiting run's question
is shown whole, with no buttons or answer field; the pane's hint says to ask Claude, or use `/scheduler:tasks`,
to act. This is because the terminal did not give the pane the keyboard on Claude Code 2.1.314 (observed
2026-10-30: `ctrl+x`, then Tab, moved the conversation to the background instead). Acting from the pane is on the
desktop app, which draws its buttons and answer field.

The pane rides on Claude Code's early-access plugin API, which can change between releases. If it
breaks, `schedule.sh` and `/scheduler:tasks` stand on their own: every action the pane offers runs one of
their commands, except Open session, which shows the command to run. Outside a kit workspace the pane does
nothing and the `/scheduler-pane` command says so.

`kit/setup.sh` installs it with the kit's other plugins. Installed, it schedules nothing until
someone creates a task. The command works in any folder, not only inside a kit workspace, since a
task names the folder it runs in.

## A task is one file

A task is a Markdown file in `~/.config/agentic-workspace-kit/scheduler/tasks/<name>.md`: flat
`key: value` front matter for its settings, and a body that is the prompt. `examples/task.md` is a
complete one. The file is the truth; the scheduler's unit is rendered from it, and
`schedule.sh sync` renders every unit again.

| Field | Default | Meaning |
|---|---|---|
| `name` | | Lowercase letters, digits and hyphens; the file's name |
| `description` | | One line, for `list` and for finding the task by what it does |
| `schedule` | | Five-field cron (`0 9 * * mon-fri`), `@daily` and the other aliases, `every 30m`, or `once 2026-11-02 07:30`. Local time, or cron with a `CRON_TZ=<zone>` prefix |
| `timezone` | | The zone a cron schedule is written in, as `CRON_TZ=` gives it. This machine's own zone is local; another works on systemd only. The zone is compared by name, so write this machine's zone by its own name (`Europe/London`), not an alias such as `GB` or `UTC` on a machine set to `Etc/UTC`: an alias is shown as a foreign zone |
| `status` | `active` | `active`, `paused` or `done` (a `once` task after its run) |
| `paused_reason` | | Why it is paused, written by `pause` or by the task pausing itself |
| `cwd` | | The folder each run starts in |
| `model`, `effort`, `fallback_model` | the person's defaults | Passed to `claude` |
| `permission_mode` | `dontAsk` | A tool not allowed is denied, never waited on |
| `allowed_tools`, `disallowed_tools` | | As `claude --allowedTools`: `Read Write Bash(git log:*) mcp__server__tool` |
| `add_dirs` | | Other folders the run may use, comma-separated |
| `chrome` | | `true` passes `--chrome`, for a task that drives the browser |
| `requires` | | The connectors the task relies on, by name (`Gmail, Google_Calendar`); `doctor <name>` looks for each in `claude mcp list` |
| `max_budget_usd` | | A cap on one run's spend |
| `timeout` | `30m` | A run past it is stopped, with everything it started |
| `retries`, `retry_delay` | `1`, `2m` | Another attempt after a failure; the delay grows with each attempt, or a list (`5m, 30m`) is used in order |
| `retry_on` | `all` | The outcomes that earn another attempt: `failed`, `timeout`, `denied`, `verify`, or a list of them |
| `verify` | | A shell command run after a good run, in `cwd`, outside Claude (`SCHEDULER_TASK`, `SCHEDULER_RUN`, `SCHEDULER_RUN_DIR`, `SCHEDULER_RUN_START`, `SCHEDULER_ATTEMPT`, `SCHEDULER_ATTEMPT_START` set): its exit status decides `ok` (0) or `failed: verify`, with its last lines kept. The task's own definition of done |
| `pause_after_failures` | `3` | Failed runs in a row before the task pauses itself (`0`: never) |
| `awaits_reply`, `reply_window` | none, `24h` | `true`: a good run ends `waiting`, and `reply` continues its session; unanswered past the window, it expires |
| `result_to` | | A file the final message is also written to, `{date}` and `{name}` filled in; relative to `cwd`. A reply is appended |
| `notify`, `notify_on` | none, `failure` | A shell command run after a run, and when to notify (`failure`, `always`, `never`). A desktop notification goes with it |
| `keep_runs` | `30` | Run folders kept |
| `created` | | When it was made |

When day of month and day of week are both restricted, a cron schedule fires when either matches,
as cron has it (`0 0 1,15 * fri` is the 1st, the 15th and every Friday). A day field written with a
leading `*` (`*/10`) counts as unrestricted.

## Keeping the task files in a folder you version

`schedule.sh home ~/notes/scheduled --move` moves the task files (and `.trash/`) to a folder of your
choosing, remembers it in a one-line pointer file (`~/.config/agentic-workspace-kit/scheduler/home`),
and syncs, so the runner is handed the new folder. `schedule.sh home` says which folder is in use and
why: `SCHEDULER_HOME` first, then the pointer, then the default. Without `--move`, a folder that still
holds tasks is not left behind. Runs, ledgers and the runner's copy stay in the state folder.

When the folder is in a git repository, every prompt edit can be a reviewed commit. The scheduler never
commits. `show` and `doctor` mark a task file with changes git has not committed, `home` writes a
`.gitignore` with `.trash/` when there is none, and a task file that holds something shaped like a
credential (a token after `token=`, `api_key:`, a bearer header) gets a warning in `show`, `doctor` and
`port check`: credentials belong in a file the prompt points to. The runner itself edits a task file
when it pauses itself or a `once` task finishes (`status`, `paused_reason`), so that shows as a diff,
which is useful: a self-pause is visible in `git status`.

## The machine's scheduler

| Host | Backend | What a task becomes |
|---|---|---|
| macOS | launchd | A LaunchAgent in `~/Library/LaunchAgents/`, loaded in your login session's `gui/<uid>` domain so the keychain login works. Cron becomes `StartCalendarInterval` entries; `every` becomes `StartInterval` |
| Linux, WSL2 with systemd | systemd user timers | A oneshot `.service` and a `.timer` with `Persistent=true`, so a run missed while the machine was off happens at the next start. `every` is `OnActiveSec` + `OnUnitActiveSec` |
| Anything with `crontab` | cron | A line in one marked block of your crontab; every other line of it is left as it was |

`SCHEDULER_BACKEND` picks one by hand. A host with none of them is an error rather than a quiet no-op.

The scheduler never changes power, wake or sleep settings on any host: no timer sets a wake (no `WakeSystem=`,
no `rtcwake`), and a task missed while the machine slept runs late when it wakes, which `report` counts.

On Linux, user timers fire only while you are logged in unless lingering is on
(`loginctl enable-linger`); `schedule.sh doctor` says which. On WSL2 the distro stops when it is
idle, and its timers stop with it: `schedule.sh keepalive install` adds a Windows logon task that
keeps it running, and `keepalive remove` takes it away. The keepalive has not been tested on Windows
by the kit's suite.

The kit's suite runs every backend against stubs, and with `AW_TEST_DOCKER=1` runs the systemd backend
live in containers (Ubuntu 24.04 and Fedora 41, systemd as PID 1, a lingering user) and the cron
backend live on Debian 12. WSL2 is not among them: a container cannot stand in for a distro that
Windows stops when it is idle.

## A run

The scheduler calls a copy of `schedule.sh` kept in `~/.local/state/agentic-workspace-kit/scheduler/`,
which `sync` refreshes, so tasks keep working if the plugin moves. Each run:

- is skipped unless the task is active (and, for `once`, its time has come), and recorded
  `skipped: running` if the last run is still going;
- gets a folder under `runs/<name>/` holding a copy of the task file, the prompt, each attempt's JSON
  output and stderr, and a `meta` file of start, end, status, attempts, exit, session id and cost;
- calls `claude -p` with JSON output, a session id of its own (so `claude --resume <id>` opens it
  afterwards), the task's settings, and a short appended prompt saying nobody is watching (and, for a
  task with a tool list, naming each tool it may use, one a line, with how a `Bash(...)` pattern
  matches: one command on its own, no `cd`, `&&`, `;` or redirect), with
  `AW_HEADLESS_RUN=1` and `CLOSEOUT_DISABLED=1` so the kit's own hooks stay quiet;
- finds `claude` by the absolute path recorded at sync, since launchd and cron start jobs with a
  minimal `PATH`.

A refused tool call is judged from the run's own stream. When the run made another tool call after
the last refused one, and that one went through, it carried on: the run stays `ok`, shown as
`ok (1 refused)` in `runs` and `show`, with the refused calls in `log` and a count in `report`. When
nothing followed, the refusal is where the run stopped, though it says so only in its reply: it is
recorded `denied`, with the refused calls, and counts as a failure. (Without jq, a refusal reads as
`denied`.) The fix is usually a broader `allowed_tools` entry (`Bash(date:*)` does not cover
`date > out.txt`), or the task's fixed steps moved into one script it may run.

After `pause_after_failures` failed runs in a row the task pauses itself: the reason goes into its
file and its unit is removed, so nothing keeps failing unseen.

Every run is a `claude -p` on your own Claude Code login, and never falls through to an API key. Its
environment carries no `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or `CLAUDE_CODE_USE_BEDROCK` /
`_VERTEX` / `_FOUNDRY`, whatever the calling shell held. Before calling `claude`, it checks the
settings a run would read (your user settings, the managed settings, and the task folder's
`.claude/settings*.json`) for an `apiKeyHelper` or one of those variables in an `env` block; finding
one, it ends the run `refused: api billing`, which counts as a failure. The call streams its events,
and a run whose init event names an API key source other than `none` (the login) is stopped at once
and recorded the same way. Each run's `meta` records that source as `auth=`. There is no override.
`doctor` shows the login in use, from `claude auth status` (no model call). The dollar figures in
`show`, `runs` and `log` are labelled `est.`: on a subscription, `total_cost_usd` is Claude Code's
estimate of what the run's tokens would cost at API prices, not a charge.

A run can end `ok` while the work it was for did not happen: its own script failed, and the model said
so in its reply. `verify` is how a task makes its own definition of done count: a command such as
`test -s reports/$(date +%F).md && ! grep -q ERROR reports/$(date +%F).md`, run after the run, whose
exit status decides. Claude Code's sandbox is the other usual cause: when the task's folder has
`sandbox.enabled`, a network call to a domain not on `sandbox.network.allowedDomains` is refused
without asking. `show`, `doctor <name>` and `port check` say whether the run is sandboxed, and to which
domains, and a refusal the sandbox gives in a tool result counts as a refusal (`ok (1 refused)`, and
in `report`). Two macOS details for a task that runs a script inside the sandbox: its `/tmp` allowance
does not cover `/private/tmp`, and `/usr/bin/curl` (LibreSSL) opens `/private/etc/ssl/openssl.cnf`
whatever `OPENSSL_CONF` says, so it cannot run under a sandbox that denies `/etc`. A Homebrew curl can.
A script's exit status is the cheapest honest signal, so a task that runs one should set a `verify`.

Retries are for transient failures: the network, a machine just woken, a busy API. Each attempt is
judged in full (the claude result, a refusal, `verify`), and a failed one is retried while attempts
remain, if its outcome is in `retry_on` (default `all`: `failed`, `timeout`, `denied`, `verify`). A
refusal for billing is never retried. `retry_delay` is one duration, which grows with each attempt
(`2m`, then `4m`), or a list used in order with its last entry repeated (`5m, 30m`). The lock is held
across the waits, so a fire during them is recorded `skipped: running`. A fault in the setup (a path,
a missing tool, a bad `verify`) fails every attempt the same way; `verify`, the notification and the
self-pause are what catch it. `runs`, `show` and `log` read `ok after 2 attempts (1 failed: verify)`;
the run folder's `attempts` file has one `attempt=N outcome=…` line per attempt; and `report` counts the
runs a retry recovered, out of the runs with a failed first attempt. Notifications go on the run's final outcome only.

A `verify` command runs with `SCHEDULER_RUN_START` (the run's start, `YYYYmmdd-HHMM`), `SCHEDULER_ATTEMPT`
and `SCHEDULER_ATTEMPT_START` (this attempt's), so it can check the output of this attempt rather than
anything from earlier the same day. Its output is kept per attempt, in `verify-N.out` and `verify-N.err`.

A scheduled run records `due`, the fire time it answers (the latest at or before its start), and a run
that started more than five minutes after it is marked `late`, as one held back by a sleeping machine
is. On a Mac, `doctor` shows the wake schedule and, as an optional line for you to run, the `pmset` line
that wakes it before the earliest task (it needs `sudo`, and changes the machine's power settings).

The `notify` command runs with `SCHEDULER_TASK`, `SCHEDULER_STATUS` (`ok`, `failed`, `timeout` or
`waiting`), `SCHEDULER_RUN` (the run's id), `SCHEDULER_RUN_DIR`, `SCHEDULER_SUMMARY`,
`SCHEDULER_RESUME` (the `claude --resume` command for the run), `SCHEDULER_RESULT_FILE` (the final
message) and `SCHEDULER_QUESTION` (for a waiting run, that message trimmed; empty otherwise) in its
environment, so a script of your own can forward a failure, or a question awaiting you, to a phone.

## A run that waits for you

With `awaits_reply: true`, a task does its part and ends the run `waiting`; you are notified, `list`
and `show` put it first, and the session-start line names it. `schedule.sh reply <name> '<answer>'`
continues that run's own session headlessly (`claude -p --resume`) with the task's flags, saves the
answer and what came back as a further step in the run folder, and settles the run `ok` or `failed`.
In Claude Code, "reply to the news scan: 1, 3, 5" does the same through `/scheduler:tasks`.

You can also answer in the session itself. The run's session id is in its folder, so resuming that
session (in the terminal, or the desktop app) and answering there is a reply too: a Stop hook in the
scheduler plugin sees the session is the one a waiting run owns, and records the last thing you wrote as
the reply and the last thing Claude said as the result, once. It runs only inside a kit workspace, so an
answer given in a session outside one still needs `schedule.sh reply`. The hook takes about 30 ms on a
Stop that has nothing to record, and it says nothing either way. The notification carries the question:
the start of the run's final message on the desktop, and the whole of it, trimmed, as
`SCHEDULER_QUESTION` for a notify command.

The command that opens a waiting run's session leads with the desktop app, `claude --desktop --resume
<session id>`, which opened the run and took an answer on 2026-10-30. The terminal form, `claude --resume`,
follows it. On that day the desktop app asked for a sign-in to Claude once; its cause is not known, and
the prompt has not been seen since.

### Reach: remote

`reach` is `desktop` by default, and a waiting run then starts no session of its own. With `reach: remote`
on a task that awaits a reply, the run also starts its session in the background with Remote Control on
(`claude --bg --resume <session id> --remote-control <task>`), so the question can be answered from a phone.
The run folder's `reach` file names that session and when it started.

A remote session ends with its run, whichever way the run ends: the answer (a reply, or an answer in the
session), the reply window passing, or the run failing. The window's timer ends it where the runner is still
alive. Every `sync`, every `doctor`, and every runner start also sweeps the reach files: a session whose run
is no longer awaiting a reply is stopped once, and the file records the stop. A session a run's reach file does
not name is never stopped. `doctor` lists any remote session still running with its run's state and its age,
so a session that will not stop shows up there.

## Moving tasks from a cloud scheduler

`schedule.sh port` takes a JSON export of cloud scheduled tasks and moves them one step at a time, each
step decided by the script and recorded in a ledger (`port status` shows it), so the move can stop
anywhere and pick up later:

| Step | What it does |
|---|---|
| `port start <export> [--path-map FROM=TO]` | Imports every task paused, maps folders, and checks each |
| `port check [<name>]` | The schedule, its zone, the folders, the connectors, and a prompt lint from `port-rules.tsv`: bridge tools, sandbox paths, cloud session variables, install steps, browser tools (which set `chrome`), a wait for a reply (which sets `awaits_reply`). A `block` holds the task back until it is fixed in its file |
| `port ack <name> <finding>` | Records that a `warn` finding was read |
| `port trial <name> --yes` | One run with the task's own settings (its permission mode and allowed tools), which is the test of whether its tools are enough; `result_to` and `notify` are held back. It fails on a refusal the run stopped at or a tool it could not reach. `--plan` is a look in plan mode instead, which ignores the allowed tools and does not move the task on; Claude Code may run it on a model of its own choosing, so it can cost more than the real run |
| `port activate <name>` | Resumes it here; it is `double-run` until its cloud twin is off |
| `port cloud-paused <name> --confirmed` | Records that the cloud task is paused. It is never deleted: it stays in the cloud scheduler as the way back |
| `port rollback <name>` | Pauses the local task with a reason, puts the row back at `trialled`, and says to re-enable the cloud task |
| `port skip`, `port done` | Leave a task out; close the move once every task is cloud-paused or skipped, listing the cloud tasks left paused |

## Looking at it

```
schedule.sh list                      # every task, its next fire time and its last run
schedule.sh show <name>               # config, prompt, the unit's state, next fire times, the last run
schedule.sh runs --since '2026-10-28 18:00'   # what ran overnight
schedule.sh log <name>                # the last run's result and stderr, and any reply
schedule.sh doctor [<name>]           # the backend, the runner, each task's unit; one task's connectors
schedule.sh report --since '2026-10-30 00:00'   # due fires, runs and how they ended, late runs, misses
```

`list`, `show` and `report` take `--json`. `report` counts only the fires due while a task was active,
on the schedule it had then, from an event log that create, edit, pause, resume and delete append to
(`state/<name>.events`), and gives every figure with its whole and the window: `5 of 6 due fires ran;
ok 4 of 5 runs; late 1 of 5 runs (at most 2h00m); 2026-10-16 00:00 to 2026-10-23 00:00`, then each
due fire that had no run.

## Environment

For tests and unusual setups: `SCHEDULER_HOME` (the tasks' folder's parent), `SCHEDULER_DATA` (the
state folder), `SCHEDULER_BACKEND`, `SCHEDULER_LAUNCHCTL`, `SCHEDULER_SYSTEMCTL`, `SCHEDULER_CRONTAB`,
`SCHEDULER_SCHTASKS` (the OS tools), `SCHEDULER_LAUNCH_AGENTS`, `SCHEDULER_SYSTEMD_DIR` (where units
go), `SCHEDULER_CLAUDE` (the `claude` to record), `SCHEDULER_NOW` (a fixed clock) and
`SCHEDULER_NOTIFY_DESKTOP=0`, `SCHEDULER_PORT_RULES` (another rules table) and
`SCHEDULER_HOOK_DISABLED=1` (silences the session-start line). Section 26 of the kit's suite runs
every backend against stubs.
