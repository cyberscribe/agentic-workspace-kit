# Purpose audit

*Every plugin, command, hook, template and script in the kit, read against the kit's two purposes, with
one line on why. Nothing is removed by this page; what serves neither is proposed for retirement or for
folding into something that does, and waits for a decision.*

> Audited 2026-11-12, on the `what-the-kit-is-for` branch. A new part of the kit gets a row here when it
> lands; a retired one keeps its row, marked with the date and what replaced it.

**The two purposes** (the README's *What the kit is for*):

1. **Common ground** between the person and the AI: where each kind of information lives, the words both
   use, the working standards and the person's preferences.
2. **Context the AI cannot find anywhere else.**

**The verdicts.** *Both*, *1* or *2* for a part that serves them. *Neither* comes in two kinds:

- **a rail or the plumbing**: a part that serves neither purpose itself but keeps the others working
  or the workspace private. Kept, and named so that it is a choice rather than an accident;
- **proposed to retire or fold in**: a part that serves neither and has no other part depending on it.

## Plugins and their commands

| Part | Serves | Why |
|---|---|---|
| **closeout** plugin | 2 | Its whole job is keeping what a session learned that the files do not show |
| `/closeout` | 2 | Promotes only what is not otherwise discoverable, in the person's words |
| closeout-capture hook (SessionEnd) | 2 | Drafts the candidates while the session is still in reach |
| closeout-review hook (SessionStart) | 2 | Brings an unpromoted draft back before it is lost |
| `scripts/check-evidence.sh` | 2 | Refuses a candidate the session's record does not bear out, so only true context is kept |
| **projects** plugin | Both | The project page is common ground on what is being done and why; its decisions are context nobody can derive |
| `/projects:new` | Both | The outcome and Done when, agreed in the person's words, and the three vocabulary files |
| `/projects:adopt` | Both | The same sections for a project that already exists, added without rewriting it |
| `/projects:pickup` | 1 | A shared picture of where a project stands, for whoever takes it up |
| `/projects:close` | 2 | Shows the evidence for each finish-line item and promotes what the next similar project should know |
| `/projects:hold` | 2 | Why the project stopped, and when to look again: context that is nowhere else |
| `/projects:pair` | 1 | The manager and the engineer work from one written brief and one set of gates |
| `/projects:board` | Neither, fold in | A view computed from the READMEs; nothing it shows is new. Proposed: fold into `/projects:pickup` run with no project named |
| projects session-start hook | Both | Puts the project's page in front of the agent before it acts |
| pair hooks and `scripts/pair.sh` | Rail | The mailbox plumbing that lets a pairing run without blocking either session |
| `scripts/registry.sh` | Rail | Safe edits to files several agents share |
| `scripts/slug.sh` | 1 | One name for one folder, the same from both `new` commands |
| **ongoing** plugin | Both | An area's standards are the owner's own: common ground on what good looks like, and context no file holds |
| `/ongoing:new` | Both | The desired state and the standards, in the owner's words |
| `/ongoing:review` | Both | Each standard held up against the evidence and the owner's answer |
| `/ongoing:adopt` | Both | The same for an area that already has a folder |
| `/ongoing:pause`, `/ongoing:drop` | 2 | Why an area is resting or retired, recorded where it will be read |
| **workspace** plugin | 1 | Keeps the shared places true |
| `/workspace:quick-start` | Both | Writes the team's standards, people and preferences down the first time |
| `/workspace:hygiene` | 1 | Checks that each thing is where both expect it, and the budget of what loads every time |
| `/workspace:register-audit` | 1 | Keeps guidance calm and the person's words plain |
| workspace session-start hook | Rail | Names what is out of step (hooks, the kit import, a submodule) with the command that fixes it |
| guard-git hook (PreToolUse) | Rail | Keeps an agent from stepping round the git hooks that keep the workspace private |
| `scripts/state.sh` | Rail | The read-only state the hook and hygiene report from |
| **scheduler** plugin | Neither, fold in | A general way to run Claude Code on a timetable. The kit uses it for the weekly and monthly passes and area check-ins, but nothing in it is about grounding or context. Proposed: publish it as a plugin of its own beside the kit, which the kit offers rather than ships |
| `/scheduler:tasks`, its hooks, `schedule.sh`, the pane | Neither, fold in | As the plugin |

## Templates

| Template | Serves | Why |
|---|---|---|
| `templates/project-readme.md` | Both | The project's outcome, finish line and state, in one page both read first |
| `templates/area-readme.md` | Both | An area's desired state and standards |
| `templates/project-decisions.md` | 2 | The decisions and reasons that stop a wrong turn later |
| `templates/glossary.md` | 1 | The plain words for the terms models fall into |
| `templates/terms.md` | Both | The project's or team's own terms: shared vocabulary, and context no model has |
| `templates/person-profile.md` | 1 | A person's preferences and what they own |
| `templates/team-roster.md` | 1 | Who to tell, and how each person likes to hear |
| `templates/verification-standard.md` | 1 | What counts as checked, agreed once |
| `templates/catalogue.md` | 2 | What the team has built and can reuse, which a model would not know to look for |
| `templates/workspace/CLAUDE.md` | 1 | The working standards and preferences, read every session |
| `templates/workspace/AGENTS.md` | 1 | Points other tools at the same standards |
| `templates/workspace/README.md` | 1 | The entry point for people |
| `templates/workspace/workspace-map.md` | 1 | Where each kind of fact lives |
| `templates/workspace/projects.md`, `closeout.md` | 1 | The team's conventions for projects and closeout |
| `templates/workspace/INDEX.md` | 1 | The register: what is running, in one place both read |
| `templates/workspace/decisions.md` | 2 | The cross-project decisions log |
| `templates/workspace/glossary.md` | Neither, retire | The pre-split glossary, which held terms. Replaced by `templates/glossary.md` and `templates/terms.md`; kept only so a workspace made before the split still has its template to compare against |
| `templates/workspace/people-README.md`, `audits-README.md` | 1 | Starting notes for two shared folders |
| `templates/workspace/CODEOWNERS`, `pull_request_template.md` | 1 | Who reviews a change to the standards, and the case a change has to make |
| `templates/workspace/workspace.md`, `stay-private.yml`, `templates/workspace.gitignore` | Rail | Privacy: confirmed-private remotes, a check that the repository stays private, what stays out of git |
| `templates/workspace/settings.json`, `gemini-settings.json`, `surface-rows/` | Rail | Plumbing: where each surface finds the plugins and the standards |

## Rituals, docs and scripts

| Part | Serves | Why |
|---|---|---|
| `CLAUDE.kit.md` | 1 | The kit's working standards, read every session |
| `rituals/closeout.md` | 2 | The closeout as a procedure any agent can follow |
| `rituals/weekly-hygiene.md` | 1 | The weekly pass as a procedure |
| `docs/memory-layers.md` | 1 | The information taxonomy itself |
| `docs/principles.md` | 1 | The principles of working with an AI that the kit carries out |
| `docs/documentation-register.md` | 1 | How guidance is written so it reads calmly |
| `docs/getting-started.md`, `docs/setup.md`, `docs/plugin-scope.md`, `docs/commands/`, `docs/hooks/` | Rail | How to install and run the kit |
| `docs/design-notes.md` | Rail | Decisions about the kit's own code, for whoever maintains it |
| `docs/migration.md`, `lib/setup/migrate.sh` | Neither, retire | The move from the 2.x layout. Proposed: retire once no 2.x workspace is in use, keeping the CHANGELOG's note of how to get it from an earlier tag |
| `setup.sh`, `install.sh`, `lib/` | Both | Put the stores in place and keep them current, offering each change |
| `lib/setup/developer.sh`, `scripts/build-template.sh` | Rail | Kit maintenance: a developer's checkout, and the template repository |
| `githooks/`, `scripts/check-paths.sh` | Rail | Keep the workspace's private material out of the public kit |
| `pilot/ablate.sh` (the leave-out test) | 2 | Checks that a line in the always-loaded tier changes what the agent does, so only context that matters stays |
| `pilot/measure.sh` | Neither, fold in | Adoption metrics for a pilot. The always-loaded byte count it reports is the one figure hygiene needs. Proposed: fold that count into hygiene, and keep the rest only for a team running a measured pilot |
| `pilot/reads.sh` | Neither, fold in | How often agents opened each reference file. Useful evidence for the leave-out test; proposed to fold in as one of its inputs |
| `pilot/build-list.md` | Neither, retire | A pilot's list of what it said it would build. Tracking, kept by the projects register in every other case. Proposed: retire with the pilot measures |

## What the audit proposes

Nothing here is removed in this wave. The proposals, for a decision:

1. **Publish the scheduler as its own plugin.** The kit offers it for the passes and check-ins, rather
   than shipping it as one of its own.
2. **Fold `/projects:board` into `/projects:pickup`.** Run with no project named, pickup gives the board.
3. **Retire the 2.x migration** once no 2.x workspace remains.
4. **Retire the pilot measures** except the leave-out test and the always-loaded count, which move into
   hygiene; `reads.sh` becomes an input to the leave-out test.
5. **Retire `templates/workspace/glossary.md`** once no workspace still compares against it.
