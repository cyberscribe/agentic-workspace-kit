#!/usr/bin/env bash
# context-readings.sh [<repository>]: the last few readings of how full the context window was after a
# session's first turn in this workspace, for the weekly hygiene report. hooks/context-reading.tsx writes
# them, one line per session, to the kit's state folder outside the repository:
#   ${XDG_STATE_HOME:-~/.local/state}/agentic-workspace-kit/workspace/context-readings.tsv
#
# This measures something different from plugin-cost.sh. plugin-cost.sh is Claude Code's estimate of each
# plugin's always-on listing (skill, command and agent names and descriptions). A reading is the whole
# window a real session carried after one turn: system prompt, tools, skills, memory files, what the
# session-start hooks printed and the first exchange. A reading moves with the workspace's state and the
# first prompt, so read it as a trend, not a per-plugin cost. A headless run (a scheduled task) is left out:
# its first turn is its task.
#
# Output, tab-separated, newest last, at most AW_CONTEXT_READINGS (5 by default):
#   reading   <time>   <tokens>   <window>   <plugins>   <surfaces>
# or one line, "no readings yet", where the file holds none for this workspace. Read-only.
set -uo pipefail

repo="${1:-.}"
root="$(cd "$repo" 2>/dev/null && pwd -P)" || { echo "context-readings.sh: no folder $repo" >&2; exit 2; }
file="${XDG_STATE_HOME:-$HOME/.local/state}/agentic-workspace-kit/workspace/context-readings.tsv"
n="${AW_CONTEXT_READINGS:-5}"

rows=""
[[ -f "$file" ]] && rows="$(awk -F '\t' -v root="$root" '$4 == root && $6 != "headless" { printf "reading\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $5, $6 }' "$file" | tail -n "$n")"
if [[ -z "$rows" ]]; then
    echo "no readings yet"
else
    printf '%s\n' "$rows"
fi
