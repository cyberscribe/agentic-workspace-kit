---
name: workspace-register-audit
description: Monthly register audit, report only — writes audits/register-audit-<date>.md and changes nothing else
schedule: 0 9 1 * *
status: active
cwd: /path/to/your/workspace
permission_mode: dontAsk
allowed_tools: Read Glob Grep Skill Edit(audits/**) Bash(git status:*) Bash(git log:*) Bash(git ls-files:*) Bash(wc:*) Bash(ls:*) Bash(date:*)
timeout: 20m
retries: 1
retry_delay: 10m
notify_on: failure
keep_runs: 12
catch_up: 7d
---

Run this workspace's monthly register audit in report mode, with nobody here to answer.

Invoke the workspace plugin's register-audit skill (`workspace:register-audit`) with the argument
`report`. If it is not available here, read `kit/plugins/workspace/commands/register-audit.md` and
follow it as a report-only run.

Write the dated report to `audits/` and change nothing else: no guidance file edited, nothing staged
or committed. Proposed rewrites wait in the report, for the person to work through with
`/workspace:register-audit` in a session.

The final reply is one sentence: the report's path and how many lines it grades.
