---
name: daily-commits
description: Weekday summary of yesterday's commits into notes/daily.md
schedule: 30 7 * * mon-fri
status: active
cwd: /path/to/your/repo
model: sonnet
permission_mode: dontAsk
allowed_tools: Read Write Bash(git log:*) Bash(git show:*)
timeout: 20m
retries: 1
retry_delay: 2m
max_budget_usd: 1.00
pause_after_failures: 3
notify_on: failure
keep_runs: 30
created: 2026-10-29 12:00
---

Summarise yesterday's commits in this repository into notes/daily.md.

Read the commits made since yesterday at 07:30 on every branch. For each one, write one line: the
author, the short hash, and what changed in plain words, taken from the diff rather than only the
message. Group the lines under Fixes, Features and Everything else, in that order, and name any
commit that touches a file under migrations/ at the top. Replace the file's contents; the previous
summary is in git.

If there were no commits, write a single line saying so. The final reply is one sentence: how many
commits were read and how many lines were written.
