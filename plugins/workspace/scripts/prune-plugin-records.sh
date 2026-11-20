#!/usr/bin/env bash
# prune-plugin-records.sh [--apply] [<file>]: Claude Code's plugin install records whose project folder no
# longer exists. By default it only counts them and changes nothing, which is how the weekly hygiene
# check runs it; with --apply it backs the file up beside itself and then removes those records.
#
# Claude Code records a project-scope install in installed_plugins.json for each folder whose
# .claude/settings.json enables a plugin. When that folder is deleted (a scratch copy, a temporary
# worktree, a project moved elsewhere) the record stays. `claude plugin uninstall --scope project` works
# only from inside the folder, which is gone, so the records are removed here instead. Only records with a
# projectPath that does not exist are touched; user-scope records and those of folders still present stay.
#
# The file is ${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/installed_plugins.json unless one is named. Quit
# Claude Code sessions before --apply: a running session can write the file back.
#
# Output: one line, "<n> install records name a project folder that no longer exists (<m> folders).",
# then, with records found and no --apply, the command that removes them. Status 0 unless the file
# cannot be read (2).
set -euo pipefail
apply=0; [[ "${1:-}" == --apply ]] && { apply=1; shift; }
f="${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json}"
command -v jq >/dev/null 2>&1 || { echo "not checked here: jq, which reads the install records, is not installed"; exit 0; }
[[ -f "$f" ]] || { echo "no install records here ($f does not exist)"; exit 0; }
jq -e '.plugins | type == "object"' "$f" >/dev/null 2>&1 || { echo "prune-plugin-records.sh: $f is not a plugin record file this script can read" >&2; exit 2; }

gone="$(jq -r '.plugins[][] | .projectPath // empty' "$f" | sort -u | while IFS= read -r p; do [[ -e "$p" ]] || printf '%s\n' "$p"; done)"
gone_json="$(printf '%s' "$gone" | jq -R . | jq -s .)"
n="$(jq --argjson g "$gone_json" '[.plugins[][] | select(.projectPath != null and (.projectPath | IN($g[])))] | length' "$f")"
echo "$n install records name a project folder that no longer exists ($(printf '%s' "$gone" | grep -c . || true) folders)."
[[ $n -gt 0 ]] || exit 0
if [[ $apply -eq 0 ]]; then
    echo "Nothing changed. To remove them, after a backup, with Claude Code closed: bash $0 --apply${1:+ $1}"
    exit 0
fi
cp -p "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"
tmp="$f.tmp.$$"
jq --argjson g "$gone_json" \
    '.plugins |= (map_values(map(select(.projectPath == null or (.projectPath | IN($g[]) | not)))) | with_entries(select(.value | length > 0)))' \
    "$f" > "$tmp" && mv "$tmp" "$f"
echo "Removed $n records; the backup is beside the file."
