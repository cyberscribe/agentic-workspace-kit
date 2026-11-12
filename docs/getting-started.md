# Getting started

*From an empty folder to a workspace that keeps its context: installing the kit, making it yours, and
the first run of each thing it does. Each section ends with how to tell it worked. The README explains
why the system is shaped this way; this guide is the how, in the order you will meet it.*

You will have, at the end:

- a private workspace repository with the kit at `kit/`, its hooks set and its plugins loading;
- a team and personal setup filled in by an interview;
- one real project with a checkable finish line;
- the habit that makes the rest worth it: a closeout at the end of each working session;
- and, when you want them, a build paired between two sessions, tasks that run on a schedule on your
  own machine, and the weekly and monthly upkeep.

Allow half an hour for sections 1 to 4. The rest is learned by using it.

---

## 1. Before you start

| You need | Why |
|---|---|
| macOS or Linux, with bash 3.2 or later | The scripts are written for macOS's own `/bin/bash` |
| `git` and `jq` | Setup and the state check use both |
| Claude Code | The plugins and their commands run there, in a terminal or the desktop app's Code tab |
| `gh`, the GitHub command line (optional) | Confirms that the workspace's remote is private |
| Cowork (optional) | The same commands, as skills, for work outside a code session |

A workspace is private: it will hold your projects, decisions and people. Keep its remote private, and
keep it out of your code repositories.

---

## 2. Install

There are two ways in, and both end with the same workspace.

**From the template repository**, if you want it on GitHub from the start. On
`cyberscribe/agentic-workspace-template`, choose *Use this template*, and pick Private (a fork of a
public repository cannot be made private). Then:

```bash
git clone --recurse-submodules <your private repository URL> my-workspace
cd my-workspace && kit/setup.sh --team "Data Platform" --owner "Sam" --owner-handle "@sam"
```

**With `setup.sh new`**, if you would rather start locally and add a remote later:

```bash
git clone https://github.com/cyberscribe/agentic-workspace-kit.git agentic-workspace-kit
bash agentic-workspace-kit/setup.sh new my-workspace --team "Data Platform" --owner "Sam" --owner-handle "@sam"
```

Leave out `--team` and `--owner` and setup asks for them. For one person, the team is you. Add
`--pilot` if you want to measure a pilot (section 11), and `--cowork` if you use Cowork.

Setup runs ten stages: prerequisites, identity, the workspace and its files, the git hooks and the
remote's privacy, submodule settings, outside folders, the plugins, Cowork, a verification pass, and
the finish. It changes nothing it has already done, commits nothing, and ends by printing the commit to
make. Make it. `docs/setup.md` describes every stage.

**It worked if** running `kit/setup.sh` a second time reports each stage as `already done`, and stage 9
passes every check.

---

## 3. Open a session

Start Claude Code in the workspace folder (or in any folder inside it) and trust the folder when asked.
Type `/` and look for the kit's commands: `/closeout`, the `/projects:`, `/ongoing:` and `/workspace:`
commands, and `/scheduler:tasks`.

Setup installed the kit's plugins for you, so they load in any folder inside the workspace, and their
hooks act only inside a kit workspace. If the commands are missing, install them yourself:

```bash
claude plugin install closeout@agentic-workspace
claude plugin install ongoing@agentic-workspace
claude plugin install projects@agentic-workspace
claude plugin install workspace@agentic-workspace
claude plugin install scheduler@agentic-workspace
```

`docs/plugin-scope.md` explains which folders load what, and why.

**In Cowork**, which does not read Claude Code's plugins, run `kit/setup.sh cowork`. It writes one
`.plugin` file per plugin into `.claude/cowork-plugins/`; upload each in Claude's plugin settings, and
the commands appear as skills. `kit/setup.sh skills` also copies a `kit-` skill per command, and your
team's own skills, into `.claude/skills/` for any surface that loads skills from a folder. Cowork reads
skills when a session starts, so new ones appear in the next session.

**It worked if** a new session in the workspace shows the commands and no `Workspace:` lines.

---

## 4. Make it yours: `/workspace:quick-start`

The installer lays files down; the quick-start makes them yours. Run it once, after setup:

```
/workspace:quick-start
```

It reads the repository before asking anything and picks one of four modes:

- **Fresh**, the first run: the team part (what the team does, the standards owner, output preferences,
  how projects run here, what counts as checked), then the personal part (your profile, your in-flight
  limit, how you like an agent to work with you).
- **Joining**, for each later person: the personal part only.
- **Existing system**, where a workspace of your own was here first: it maps your files and section
  names onto the kit's, and changes nothing without a yes.
- **Nothing left**: everything is filled in, so it checks the kit is reachable and running.

Every mode ends by checking the commands on each surface you use, the session-start line in one
project folder, and one real piece of work. Each step is shown first and taken or declined.

Your answers go into `CLAUDE.md`, below its first line. That first line, `@kit/CLAUDE.kit.md`, imports
the kit's working standards; everything below it is yours and wins where the two differ. `CLAUDE.md`
is loaded into every session, so keep it short: README Part 3 explains the budget.

**A teammate joining later** clones with `--recurse-submodules`, runs `kit/setup.sh`, and then
`/workspace:quick-start`, which finds them in joining mode.

**It worked if** the quick-start reports `nothing-left` on a second run.

---

## 5. Your first project

A project is anything with a finish line. If you cannot say what done looks like, it is an ongoing area
instead: something kept up rather than finished, with a desired state and standards to keep in place
of a finish line. `/ongoing:new` starts one in `ongoing/<slug>/`, and `/projects:new` hands over to it when
the interview finds no finish line.

```
/projects:new
```

The **quick** interview asks for the name, the desired outcome, three to five Done when criteria, how
the project is kept in git, and who owns it; the **full** one adds the boundary, success criteria,
people and their roles, precedents, gates and planned steps. It shows you the README first and writes
it on a yes, with a row in the register, `projects/INDEX.md`.

The project's `README.md` is its entry point. Two of its sections do most of the work:

- **Done when**: criteria someone else could check without asking you. "The client has signed off the
  plan in writing", not "the client is happy".
- **Current state**: one of five states (*ready*, *doing*, *blocked*, *paused*, *done*), what blocks it
  and since when, the date it was updated, and one line saying where it stands.

Projects you already have are brought in with `/projects:adopt`, which adds only the sections each one
lacks and rewrites nothing.

**It worked if** a session opened in `projects/<slug>/` starts with a line giving the project's
outcome, its Done when progress and its state.

---

## 6. A working day

Open the session in the project's folder. The session-start line says where it stands; the README
holds the rest, and the agent reads it before acting.

Work as you normally would. When the session decided, learned or corrected something, end with:

```
/closeout
```

Anything you type after it is what you most want kept, and the pass starts there. It then:

1. **Reviews** what the session learned, decided or corrected that a later session would otherwise
   re-derive. Finished work is not a learning; the constraint that shaped it is.
2. **Classifies** each item by where it belongs, which decides how often it is read again:
   project reference (this project only), general reference (`docs/`, any project), templates, or the
   working standards in `CLAUDE.md`, which every session pays for. It picks the cheapest that works.
3. **Checks** each claim against the files as they are now.
4. **Promotes** with small edits. Anything that would change `CLAUDE.md` comes back as a proposal for
   you to approve.
5. **Reconciles tracking**, separately: ticks the Done when items the session met and updates the
   Current state block.
6. **Reports**, with the commit for you to make. It never commits.

This is the habit the system rests on. Each closeout is small, and the next session starts from what
it recorded rather than from guesses. README §4.1 explains the levels of closeout and why the gain
compounds.

To see everything in flight at once:

```
/projects:board
```

It shows every project by state, then flags what needs a look: no owner, a stale update, blocked for
more than 14 days, someone over their in-flight limit, a project ready to close. `/projects:board write`
saves it as `projects/BOARD.md`.

**It worked if** the next session in the project picks up from the closeout's record without being
told.

---

## 7. Build in a pair: `/projects:pair`

For work that is mostly building, split it between two sessions: one holds the outcome and tests, the
other builds. You direct and decide, rather than relaying messages between windows.

1. **In the session you will direct from** (Claude Code or Cowork), in the project, type
   `/projects:pair`. That session becomes the product manager. It reads the project's README and your
   standing rules, sets up a mailbox, and writes the first brief: the outcome and Done when items, the
   order of work, and the gates where the engineer stops for you.
2. **Start the engineer.** The PM gives you one command, with the prompt it sends shown beneath it:

   ```bash
   kit/plugins/projects/scripts/pair.sh projects/<slug>
   ```

   That starts a Claude Code session as the engineer, or resumes its last one. An engineer session you
   started some other way joins with `/projects:pair join`.
3. **Let them work.** The engineer reports in the mailbox with evidence: commits, the exact test command
   and its result, how to see it working. The PM re-runs that evidence before accepting, then writes the
   next brief or a fix. Each side wakes when the other writes.
4. **Answer at the gates.** When a message is marked for you, the PM brings it to you. Commits, pushes
   and releases stay yours unless the brief grants them.
5. **Close it.** `/projects:pair close` ends the pairing and copies its decisions into the project's
   log.

The mailbox is plain Markdown: `to-cc.md` for the PM's messages, `to-pm.md` for the engineer's, and one
status file per side. Each file has one writer, so it can sit in a folder synced between two machines.
`/projects:pair status`, or `pair.sh check`, says whether the engineer is working, from evidence such
as a live process and a recent activity beat.

**It worked if** you never copy a message from one window to the other, and every accepted report
names evidence the PM re-ran. `docs/commands/projects-pair.md` has the detail.

---

## 8. Pause, hand over, finish

- **Pause:** `/projects:hold` sets the project to *paused* with a one-line reason and, if you want, a
  date to look at it again. The folder stays where it is: why it was paused is itself context.
- **Hand over or come back:** `/projects:pickup` gives a cold-start brief: the outcome, Done when
  progress, the current state, the last decisions and commits, open questions, and who to ask. It
  offers to resume a paused project.
- **Finish:** `/projects:close` goes through Done when one item at a time against its evidence, asks
  three questions (what worked, what to change, what the next similar project should know first),
  promotes the third answer where it generalises, and moves the folder to `projects/_done/<slug>/`.

**It worked if** the register's Done section lists the project, and the retrospective is the last
section of its README.

---

## 9. Keep it healthy

Two passes keep the system from drifting. Each writes a dated report to `audits/`, which you commit:
the reports are the evidence that the check still means something.

| Pass | When | Command | What it catches |
|---|---|---|---|
| Hygiene | Weekly | `/workspace:hygiene` | The size of what loads every session, files in the wrong place, the register out of step with the folders, decisions that turned out to generalise, closeout drafts never promoted |
| Register audit | Monthly | `/workspace:register-audit` | Guidance drifting toward urgency and threat ("you must", capitals for emphasis), which makes agents worse |

Each runs as a scan, then a pass through the findings with you: the uncontested fixes on one yes,
anything touching what loads every session one at a time. Type `report` after either for the scan
alone.

**It worked if** the reports accumulate in `audits/`, and the always-loaded size is a number you can
see change from week to week.

---

## 10. Schedule work: `/scheduler:tasks`

Some work should happen without you starting it: a weekly digest, a morning check, a report on the
first of the month. The scheduler runs a Claude Code task on your own machine at the times you set,
through the machine's own scheduler: launchd on macOS, a systemd user timer on Linux and WSL2, or cron.
Nothing runs in the cloud but Claude itself, and every run is billed to your Claude login, never to an
API key.

1. **Describe it.** In a session, type `/scheduler:tasks` and say what you want and when: "every
   weekday at 7:30, summarise the new feedback in `reports/` and write it to `summaries/`". It drafts
   the task, which is one Markdown file: the schedule, the folder it runs in, the model, the tools it
   may use, and the prompt as the body. It shows you the file and writes it on a yes, paused.
2. **Name its tools.** Nobody is there to answer a permission prompt during a scheduled run, so a task
   runs in `dontAsk` mode: it may use the tools in `allowed_tools` and is refused anything else. Name
   shell commands exactly (`Bash(python3 fetch.py)`) rather than allowing any command. Fixed steps go
   best in a script the task runs; the run then spends its effort on judgement.
3. **Try it once.** `/scheduler:tasks` offers a trial: one real run now, with the task's own settings.
   It reports what the run did, any tool it was refused, and whether the task's own check passed (the
   `verify` field: a command such as "today's summary file exists"). Change the file and try again until
   the trial is clean.
4. **Turn it on.** Resume the task and it is handed to your machine's scheduler. `list` shows when it
   runs next.

Day to day, ask `/scheduler:tasks` in words, or run the script,
`kit/plugins/scheduler/scripts/schedule.sh`, directly:

| To | Run |
|---|---|
| See every task and when it runs next | `schedule.sh list` |
| See one task's settings and prompt | `schedule.sh show <name>` |
| Pause it, or resume it | `schedule.sh pause <name>`, `schedule.sh resume <name>` |
| Run it now, whatever the schedule | `schedule.sh run <name>` |
| See what its runs did | `schedule.sh runs <name>`, `schedule.sh log <name>` |
| See a week at a glance: due, ran, failed, missed | `schedule.sh report` |
| Check that a task can run | `schedule.sh doctor <name>` |

An alias saves typing: `alias scheduled-tasks="bash ~/<workspace>/kit/plugins/scheduler/scripts/schedule.sh"`.

**When a run fails**, it tries again once (the `retries` field), then shows a desktop notification.
After three failed runs in a row a task pauses itself and says why. To be told somewhere else, such as
your email or phone, set `notify` to a script of your own: it runs after each run with the outcome and
the run's details in its environment.

**A task can wait for you.** With `awaits_reply: true`, a run does its part, such as drafting a
shortlist for you to choose from, then stops and waits. Answer it with
`schedule.sh reply <name> '<your answer>'`, or in the run's own session; with `reach: remote`, that
session is open in the Claude app on your phone. The run carries on from where it stopped. An answer
not given within `reply_window` (a day, by default) lets the run expire.

**Coming from a cloud scheduler?** `schedule.sh port` moves tasks one checked step at a time:

1. `start` imports them, paused.
2. `check` flags anything that only worked in the cloud.
3. `trial` runs each one once.
4. `activate` turns it on here.
5. `cloud-paused` records that you paused the cloud copy. It is paused, not deleted, so `rollback` can
   always go back.

**Where the files live.** Task files are in `~/.config/agentic-workspace-kit/scheduler/tasks/` unless
you choose a folder: `schedule.sh home ~/<workspace>/scheduled` keeps them in your workspace, so they
are versioned with everything else.

**Your machine has to be on.** If it is asleep at a run's time, macOS and systemd run it when it wakes,
and `report` counts it as late. If it is switched off, cron and launchd drop that run: `report` lists it
as missed, and `schedule.sh run <name>` runs it by hand. The scheduler never wakes your machine or
changes its power settings. On a Mac, `doctor` prints the optional command to wake it before the
earliest task, if you want that.

If the workspace turns on Claude Code's sandbox, a run's network calls reach only the domains it
allows. A run that fetches from the web needs its hosts on that list, and `doctor <name>` shows the
list.

**It worked if** a week's `schedule.sh report` shows every due run ran, and a failed or waiting run
reached you without you going to look.

---

## 11. Measure it (optional)

For a pilot, setup's `--pilot` adds `pilot/build-list.md`. Two scripts in the kit read the rest:

- `bash kit/pilot/measure.sh` counts, weekly, from the repository and its history: projects by state
  and how long they take, decisions logged, audit reports, the always-loaded size, and whether agent
  sessions read the reference material. Counts only, so safe to share outside the team.
- The ablation runner tests whether one line of context changes what an agent does on the task it was
  written for, by running that task with the line and without it. `kit/pilot/README.md` describes it.

---

## 12. Stay current

When a new kit is released:

```bash
kit/setup.sh update
```

It advances the kit, prints the changelog since your version, and offers each changed template as a
diff, applied change by change: what you already have counts as there, and what does not fit your file
is listed for you to merge by hand. It ends with the commit to make. `--yes` takes the offers without
asking, from the update after the one that brings it in. Then, after an update that changes the
plugins, update your own installed copies:

```bash
claude plugin update --scope user closeout@agentic-workspace
claude plugin update --scope user ongoing@agentic-workspace
claude plugin update --scope user projects@agentic-workspace
claude plugin update --scope user workspace@agentic-workspace
claude plugin update --scope user scheduler@agentic-workspace
```

An update that adds a plugin (the `ongoing` plugin arrived this way) needs it installed once:
`claude plugin install ongoing@agentic-workspace`.

`--scope user` matters: without it the update reaches only the copy for the folder you ran it in, and
sessions elsewhere keep the old version. In Cowork, run `kit/setup.sh cowork` again and upload the new
`.plugin` files.

---

## When something is off

| What you see | What to do |
|---|---|
| `kit/` is empty after a clone | It was cloned without `--recurse-submodules`; `kit/setup.sh` initialises it |
| No kit commands in a session | Install the plugins (section 3); `docs/plugin-scope.md` explains which folders load them |
| Cowork skills missing | They appear in the next session; `kit/setup.sh skills --check` says whether a refresh is due |
| The engineer in a pairing does not hear the PM | It was started without the launcher: type `/projects:pair join` in its session |
| A session opens with `Workspace:` lines | Each names something out of step and the command that fixes it |
| A scheduled run did not happen | `schedule.sh report` says whether it was missed (the machine was off) or failed; `schedule.sh run <name>` runs it now |
| A scheduled run is waiting | It wants your answer: `schedule.sh list` shows which, and `schedule.sh reply <name> '<answer>'` gives it |
| An update says a change does not fit a file | Your file has its own wording there; merge that change by hand, then answer n next time to stop the offer |

---

## Where next

- **The README**, for why each piece is shaped as it is: the four content types (Part 1), the budget
  for what loads every session (Part 3) and the rituals (Part 4).
- **`docs/commands/`**, one page per command: what it does, when to reach for it, common questions, and
  how to tell it is working.
- **`docs/memory-layers.md`**, the taxonomy the closeout classifies against.
- **`plugins/scheduler/README.md`**, every task field and scheduler command.
- **`CHANGELOG.md`**, for what each release changed and how to update to it.
