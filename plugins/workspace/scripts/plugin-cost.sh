#!/usr/bin/env bash
# plugin-cost.sh [<repository>]: what each plugin enabled for a repository adds to every session's
# context, as Claude Code itself estimates it, for the weekly hygiene report.
#
# A plugin's always-on cost is the text a session carries whether or not the plugin is used: the name and
# description of each of its skills, commands and agents. `claude plugin details <id>` states it as
# "Always-on: ~N tok"; the rest of a plugin (a skill's body, an agent's prompt) costs only when it runs.
# A plugin counts for the repository when it is enabled for the user, synced to the account, or enabled
# in the repository's own settings (scope project or local, for this path).
#
# Output, tab-separated, one line each:
#   plugin   <id>   <tokens>          or   plugin   <id>   not measured   <why>
#   total    <tokens>   <plugins counted>
#   heavy    <id>   <tokens>          each plugin at or above AW_PLUGIN_HEAVY tokens (2000 by default)
# or one line, "not measured here: <why>", where the claude command is not on this machine (Cowork's
# shell, a container), and the status is still 0: the report says so rather than failing.
#
# What it does not count: text a plugin's hooks print into the session (a session-start line, say).
# Claude Code reports hooks as costing nothing, which is true of their code and not of what they print.
# Read-only: it runs `claude plugin list --json` and `claude plugin details` and writes nothing.
set -uo pipefail

root="${1:-$PWD}"
root="$(cd "$root" 2>/dev/null && pwd -P)" || { echo "plugin-cost.sh: no such folder: ${1:-$PWD}" >&2; exit 2; }
heavy="${AW_PLUGIN_HEAVY:-2000}"

command -v claude >/dev/null 2>&1 || { echo "not measured here: the claude command is not on this machine"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "not measured here: jq, which reads Claude Code's plugin list, is not installed"; exit 0; }

list="$(cd "$root" && claude plugin list --json 2>/dev/null)" \
    || { echo "not measured here: claude plugin list --json failed"; exit 0; }
ids="$(jq -r --arg root "$root" '
    [ .[] | select(.enabled == true)
          | select(.scope == "user" or .scope == "synced"
                   or ((.scope == "project" or .scope == "local") and .projectPath == $root))
          | .id ] | unique | .[]' <<<"$list" 2>/dev/null)" \
    || { echo "not measured here: claude plugin list --json gave no list this script can read"; exit 0; }

total=0 counted=0 heavies=""
while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    out="$(cd "$root" && claude plugin details "$id" 2>&1)"
    # "Always-on:   ~771 tok", "~11,679 tok" or "~1.2k tok": the separator is dropped, and a figure in
    # thousands is turned back into tokens.
    tok="$(awk '/^ *Always-on:/ { v = $2; sub(/^~/, "", v); gsub(/,/, "", v); m = 1
                                   if (v ~ /k$/) { sub(/k$/, "", v); m = 1000 }
                                   if (v ~ /^[0-9.]+$/) printf "%d\n", v * m + 0.5; exit }' <<<"$out")"
    if [[ -z "$tok" ]]; then
        # Claude Code's own first line says why (a synced plugin it cannot find locally, say).
        printf 'plugin\t%s\tnot measured\t%s\n' "$id" "$(sed -n 1p <<<"$out" | cut -c1-120)"
        continue
    fi
    printf 'plugin\t%s\t%s\n' "$id" "$tok"
    total=$((total + tok)); counted=$((counted + 1))
    [[ $tok -ge $heavy ]] && heavies+="heavy	$id	$tok"$'\n'
done <<<"$ids"
printf 'total\t%s\t%s\n' "$total" "$counted"
printf '%s' "$heavies"
