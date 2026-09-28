#!/usr/bin/env bash
# Pilot metrics, read from git history. Counts only: no file contents, names or email addresses
# leave this script, so metrics.csv can be shared outside the team without review.
#
#   pilot/measure.sh              append (or refresh) today's row in pilot/metrics.csv
#   pilot/measure.sh --backfill 8 rebuild metrics.csv with one row per week for the last 8 weeks
#   pilot/measure.sh --print      print today's row without writing anything
#
# Each row is a snapshot of the repository as it stood at the end of that day, plus activity in the
# seven days up to it. Backfill works because every number is recomputed from a past commit rather
# than remembered — which is also why the numbers can be trusted in a write-up.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"
out="pilot/metrics.csv"
header="date,always_loaded_bytes,decisions_logged,doc_files,people_profiles,audit_reports,build_items_named,build_items_exist,doc_commits_7d,doc_contributors_7d"

# Paths that count as the team's documentation, as opposed to code or pilot bookkeeping.
doc_paths=(AGENTS.md CLAUDE.md docs memory projects logs templates rituals)

# GNU date and BSD (macOS) date spell "n days ago" differently.
days_ago() { date -u -d "-$1 days" +%F 2>/dev/null || date -u -v-"$1"d +%F; }

row_for() {
    local day="$1" rev bytes=0 f s decisions doc_files people audits named exist commits authors since
    rev="$(git rev-list -1 --before="$day 23:59:59" HEAD 2>/dev/null || true)"
    if [[ -z "$rev" ]]; then echo "$day,0,0,0,0,0,0,0,0,0"; return; fi

    # The always-loaded tier. CLAUDE.md is normally a one-line import of AGENTS.md; both are counted
    # so that growth in either shows up.
    for f in AGENTS.md CLAUDE.md; do
        s="$(git cat-file -s "$rev:$f" 2>/dev/null || echo 0)"
        bytes=$((bytes + s))
    done

    # Decision entries use the "## [YYYY-MM-DD] Title" heading from templates/project-decisions.md.
    decisions="$(git grep -c -E '^## \[[0-9]{4}-' "$rev" -- 'logs/decisions.md' 'projects/*/decisions.md' 2>/dev/null \
        | awk -F: '{n += $NF} END {print n + 0}')"

    doc_files="$(git ls-tree -r --name-only "$rev" -- docs memory projects logs templates rituals 2>/dev/null | grep -c '\.md$' || true)"
    # Each folder's README describes the folder and is not one of the things being counted.
    people="$(git ls-tree -r --name-only "$rev" -- memory/people 2>/dev/null | grep '\.md$' | grep -vc '/README\.md$' || true)"
    audits="$(git ls-tree -r --name-only "$rev" -- audits 2>/dev/null | grep -vc '/README\.md$' || true)"

    # The adoption ledger: rows of the build-list table, and those whose status column says exists.
    named=0; exist=0
    if git cat-file -e "$rev:pilot/build-list.md" 2>/dev/null; then
        read -r named exist < <(git show "$rev:pilot/build-list.md" | awk -F'|' '
            /^\| *[0-9]+ *\|/ { n++; s = tolower($6); gsub(/ /, "", s); if (s == "exists") e++ }
            END { print n + 0, e + 0 }')
    fi

    since="$(date -u -d "$day -7 days" +%F 2>/dev/null || date -u -j -v-7d -f %F "$day" +%F)"
    commits="$(git log --since="$since 23:59:59" --until="$day 23:59:59" --format=%H -- "${doc_paths[@]}" | wc -l | tr -d ' ')"
    authors="$(git log --since="$since 23:59:59" --until="$day 23:59:59" --format=%ae -- "${doc_paths[@]}" | sort -u | grep -c . || true)"

    echo "$day,$bytes,$decisions,$doc_files,$people,$audits,$named,$exist,$commits,$authors"
}

case "${1:-}" in
    --print)
        echo "$header"; row_for "$(days_ago 0)" ;;
    --backfill)
        weeks="${2:?--backfill needs a number of weeks}"
        { echo "$header"; for ((w = weeks; w >= 0; w--)); do row_for "$(days_ago $((w * 7)))"; done; } > "$out"
        cat "$out" ;;
    "")
        today="$(days_ago 0)"
        [[ -f "$out" ]] || echo "$header" > "$out"
        grep -v "^$today," "$out" > "$out.tmp" || true
        row_for "$today" >> "$out.tmp"
        mv "$out.tmp" "$out"
        tail -n 1 "$out" ;;
    *)
        sed -n '2,12p' "$0"; exit 1 ;;
esac
