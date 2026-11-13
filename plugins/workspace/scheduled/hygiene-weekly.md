---
name: workspace-hygiene
description: Weekly hygiene, report only — writes audits/hygiene-<date>.md and changes nothing else
schedule: 0 9 * * mon
status: active
cwd: /path/to/your/workspace
permission_mode: dontAsk
allowed_tools: Read Glob Grep Skill Edit(audits/**) Bash(bash kit/plugins/workspace/scripts/state.sh:*) Bash(bash kit/scripts/skills-bridge.sh --check:*) Bash(bash kit/pilot/measure.sh:*) Bash(git status:*) Bash(git log:*) Bash(git ls-files:*) Bash(git diff:*) Bash(wc:*) Bash(ls:*) Bash(date:*)
timeout: 20m
retries: 1
retry_delay: 10m
notify_on: failure
keep_runs: 12
catch_up: 3d
---

Run this workspace's weekly hygiene in report mode, with nobody here to answer.

Invoke the workspace plugin's hygiene skill (`workspace:hygiene`) with the argument `report`. If it is
not available here, read `kit/plugins/workspace/commands/hygiene.md` and follow it as a report-only run.

Write the dated report to `audits/` and change nothing else: no file moved, deleted, staged or
committed. The judgement pass waits in the report as proposals, for the person to work through with
`/workspace:hygiene` in a session.

The final reply is one sentence: the report's path and how many findings it lists.
