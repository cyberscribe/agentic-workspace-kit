#!/usr/bin/env bash
# Team metrics, read from git history. Counts only: no file contents, names or email addresses
# leave this script, so the CSV can be shared outside the team without review.
#
#   pilot/measure.sh                 append (or refresh) today's row in pilot/metrics.csv
#   pilot/measure.sh --backfill 8    rebuild the CSV with one row per week for the last 8 weeks
#   pilot/measure.sh --print         print today's row without writing anything
#   --out <path>                     write somewhere other than pilot/metrics.csv (with either mode)
#   MEASURE_ALWAYS_LOADED="CLAUDE.md" pilot/measure.sh
#                                    the files counted as always loaded (default: AGENTS.md CLAUDE.md)
#
# Each row is a snapshot of the repository as it stood at the end of that day, plus activity in the
# seven days up to it. Backfill works because every number is recomputed from a past commit rather
# than remembered — which is also why the numbers can be trusted in a write-up. It reads committed
# history only: before the first commit there is nothing to write, and backfill starts at the week
# of the first commit rather than inventing zero rows for the weeks before it.
set -euo pipefail

usage() { sed -n '2,16p' "$0"; exit 1; }

mode=append weeks="" out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --print) mode=print; shift ;;
        --backfill) mode=backfill; weeks="${2:-}"; [[ "$weeks" =~ ^[0-9]+$ ]] || usage; shift 2 ;;
        --out) out="${2:-}"; [[ -n "$out" ]] || usage; shift 2 ;;
        *) usage ;;
    esac
done

# A relative --out is relative to where the command was typed, as any other path argument would be.
[[ -z "$out" || "$out" == /* ]] || out="$PWD/$out"
root="$(git rev-parse --show-toplevel)"
cd "$root"
out="${out:-pilot/metrics.csv}"

# Uncommitted files are invisible to every column, so a repository with no commits yet would get a
# row of zeros that reads like a baseline. Say so and write nothing.
if ! git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    echo "measure.sh: no commits yet — commit first, then run it; nothing written" >&2
    exit 0
fi
# awk rather than head, so git log is read to the end and never meets a closed pipe.
first_day="$(TZ=UTC git log --reverse --format=%cd --date=format-local:%F 2>/dev/null | awk 'NR == 1' || true)"
mkdir -p "$(dirname "$out")"

header="date,always_loaded_bytes,decisions_logged,doc_files,people_profiles,audit_reports,build_items_named,build_items_exist,doc_commits_7d,doc_contributors_7d"
header+=",projects_active,projects_with_next_action,projects_with_done_when,projects_done,waiting_over_14d,max_in_flight_per_person,median_days_to_done"

# The always-loaded tier. In a kit install CLAUDE.md is a one-line import of AGENTS.md, and both are
# counted so that growth in either shows up. A repository whose agents load something else says so.
read -r -a always_loaded <<< "${MEASURE_ALWAYS_LOADED:-AGENTS.md CLAUDE.md}"

# Paths that count as the team's documentation, as opposed to code or pilot bookkeeping.
doc_paths=(AGENTS.md CLAUDE.md docs memory projects logs templates rituals)

# GNU date and BSD (macOS) date spell "n days ago" differently.
days_ago() { date -u -d "-$1 days" +%F 2>/dev/null || date -u -v-"$1"d +%F; }

# --- Projects -------------------------------------------------------------------------------------
# The project columns read the Now block, Done when and People sections of each project's entry
# point, as the projects commands write them (templates/project-readme.md). The rules are the ones
# under "How the files are read" in the projects plugin's README, so the board and these numbers agree:
#   - labels are read bold or plain: "- **State:** doing" and "State: doing" are the same line;
#   - a value that is empty, "-", "—", "none" or "n/a", or starts "none found", "not yet named" or
#     "<" (a template stand-in), is missing;
#   - each "Waiting on:" line is one thing awaited, dated only by the date after "since";
#   - a waiting project with a Waiting on line has what it needs, as a next action would give it;
#   - a heading's name is its text up to the first " — ", " – ", "(" or ":", compared exactly with
#     Done when, People or an alias the conventions file names; Done when counts checklist lines;
#   - in flight is the rule under Pace in the conventions: State doing, counted against each person
#     People names as owns or does, or the register's Owner where there is no People section.

# The conventions file at that revision, else today's copy (a repository that adopted it recently
# still gets its layout applied to older rows), else the kit defaults.
conventions() { git show "$1:.claude/projects.md" 2>/dev/null || cat .claude/projects.md 2>/dev/null || true; }

# Settings out of the conventions prose: one "kind value" line each. A location such as
# `projects/<slug>/` becomes a folder pattern; a Section names sentence that mentions Done when or
# People lends that section every backticked name in the sentence (both, if it mentions both). Labels
# are matched in any case and on an indented bullet, as the projects hook reads them.
settings_awk='
function first_tick(s) { return match(s, /`[^`]+`/) ? substr(s, RSTART + 1, RLENGTH - 2) : "" }
function is_label(line, name) { return tolower(line) ~ ("^[ \t]*[-*] \\*\\*" name ":\\*\\*") }
function folder(v) {
    sub(/^\.\//, "", v); sub(/\/+$/, "", v); gsub(/\./, "\\.", v)
    if (v ~ /</) gsub(/<[^>]*>/, "[^/]+", v); else v = v "/[^/]+"
    return "^" v "$"
}
function aliases(text,   n, i, parts, s, d, p, v) {
    n = split(text, parts, /(\. |; )/)
    for (i = 1; i <= n; i++) {
        s = parts[i]; d = (tolower(s) ~ /done when/); p = (tolower(s) ~ /people/)
        while ((d || p) && match(s, /`[^`]+`/)) {
            v = tolower(substr(s, RSTART + 1, RLENGTH - 2)); s = substr(s, RSTART + RLENGTH)
            if (d) print "alias", "done", v
            if (p) print "alias", "people", v
        }
    }
}
tolower($0) ~ /^[ \t]*[-*] \*\*/ && !is_label($0, "section names") { if (names != "") aliases(names); names = "" }
is_label($0, "active")   && first_tick($0) != "" { print "active", folder(first_tick($0)) }
is_label($0, "paused")   && first_tick($0) != "" { print "paused", folder(first_tick($0)) }
is_label($0, "done")     && first_tick($0) != "" { print "done",   folder(first_tick($0)) }
is_label($0, "register") && first_tick($0) != "" { print "register", first_tick($0) }
is_label($0, "entry point") && first_tick($0) != "" { print "entry", first_tick($0) }
(is_label($0, "default owner") || is_label($0, "owner")) && first_tick($0) != "" { print "owner", tolower(first_tick($0)) }
is_label($0, "section names") { if (names != "") aliases(names); names = $0; next }
names != "" && /^[ \t]+[^ \t]/ { names = names " " $0; next }
names != "" { aliases(names); names = "" }
END { if (names != "") aliases(names) }'

# One project entry point in, one tab-separated line out:
#   state  next(0/1)  done_when(0/1)  has_people(0/1)  owners(comma list)  waiting dates(space list)
# The owners are the people named owns or does, lower-cased; they are compared, never printed.
readme_awk='
function clean(v) { gsub(/`|\*\*/, "", v); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
function label(line, name,   re) {
    re = "^[ \t]*([-*+][ \t]+)?(\\*\\*)?" name "(\\*\\*)?:(\\*\\*)?"
    return match(tolower(line), re) ? clean(substr(line, RSTART + RLENGTH)) : "\001"
}
function missing(v) { v = tolower(v); return v == "" || v ~ /^(<|none found|not yet named)/ || v ~ /^(none|n\/a|-|—)$/ }
BEGIN {
    split(done_names, a, "|"); for (i in a) if (a[i] != "") is_done[a[i]] = 1
    split(people_names, a, "|"); for (i in a) if (a[i] != "") is_people[a[i]] = 1
    FS = "\n"
}
/^[ \t]*```/ { fence = !fence; next }
fence || /^[ \t]*<!--/ { next }
/^##+[ \t]/ {
    # The name is the text up to the first " — ", " – ", "(" or ":", as the projects hook reads it.
    h = tolower($0); sub(/^#+[ \t]+/, "", h); gsub(/\*|`/, "", h)
    if ((i = index(h, " — "))) h = substr(h, 1, i - 1)
    if ((i = index(h, " – "))) h = substr(h, 1, i - 1)
    if ((i = index(h, "("))) h = substr(h, 1, i - 1)
    if ((i = index(h, ":"))) h = substr(h, 1, i - 1)
    sub(/^[ \t]+/, "", h); sub(/[ \t]+$/, "", h)
    section = (h in is_done) ? "done" : (h in is_people) ? "people" : "other"
    if (section == "people") people = 1
    next
}
/^# / { section = "other"; next }
state == "" && (v = label($0, "state")) != "\001" { state = tolower(v); sub(/^[^a-z]+/, "", state); sub(/[^a-z].*/, "", state); next }
has_next == "" && (v = label($0, "next action")) != "\001" { has_next = missing(v) ? 0 : 1; next }
(v = label($0, "waiting on")) != "\001" {
    if (missing(v)) next
    # Only "since <date>" dates a line; another date on it (a due date, say) leaves it undated.
    d = "nodate"; lv = tolower(v)
    if (match(lv, /since[ \t]+[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) d = substr(lv, RSTART + RLENGTH - 10, 10)
    waits = waits " " d; next
}
section == "done" && /^[ \t]*[-*+][ \t]+\[[ xX]\]/ {
    item = $0; sub(/^[ \t]*[-*+][ \t]+\[[ xX]\][ \t]*/, "", item)
    if (!missing(clean(item))) done_when = 1
    next
}
section == "people" && /^[ \t]*[-*+][ \t]/ {
    line = $0; sub(/^[ \t]*[-*+][ \t]+/, "", line)
    n = split(line, f, / +(—|–|--|-) +/)
    name = tolower(clean(f[1])); roles = tolower(f[2])
    if (n >= 2 && !missing(name) && roles ~ /(^|[^a-z])(owns|does)([^a-z]|$)/) owners = owners (owners == "" ? "" : ",") name
}
END {
    if (state !~ /^(next|doing|waiting|parked|done)$/) state = "-"
    if (state == "waiting" && waits != "") has_next = 1
    printf "%s\t%d\t%d\t%d\t%s\t%s\n", state, has_next + 0, done_when + 0, people + 0, (owners == "" ? "-" : owners), (waits == "" ? "-" : substr(waits, 2))
}'

# state_of <rev> <path> <kind>: the State a README had at a revision. Without a State line, a
# project in a folder kept for done or paused work is read as done or parked.
state_of() {
    local s
    s="$(git show "$1:$2" 2>/dev/null | awk -v done_names="$done_names" -v people_names="$people_names" "$readme_awk" | cut -f1 || true)"
    if [[ "$s" == "-" ]]; then case "$3" in done) s=done ;; paused) s=parked ;; esac; fi
    echo "$s"
}

# kind_of <dir>: which conventions location a project folder sits in. A folder that matches the
# active location is active, however the other locations are written — in the kit default all three
# are the same folder and only State tells them apart.
kind_of() {
    if [[ "$1" =~ $loc_active ]]; then echo active
    elif [[ -n "$loc_done" && "$1" =~ $loc_done ]]; then echo done
    elif [[ -n "$loc_paused" && "$1" =~ $loc_paused ]]; then echo paused
    else echo active; fi
}

# days_to_done <rev> <path>: whole days from the commit that created the entry point to the commit
# that set it done, following the file through a move into a done folder. "Set it done" is the start
# of the unbroken run of done revisions ending at <rev>, so a project reopened and closed again
# counts from its last close.
days_to_done() {
    local line hash ct path created="" done_ct="" still=1
    while read -r line; do
        case "$line" in
            "C "*) read -r _ hash ct <<< "$line"; continue ;;
            "") continue ;;
        esac
        path="$line"; created="$ct"
        if [[ $still -eq 1 && "$(state_of "$hash" "$path" "$(kind_of "$(dirname "$path")")")" == done ]]; then done_ct="$ct"; else still=0; fi
    done < <(git log --follow --format='C %H %ct' --name-only "$1" -- "$2")
    # A README whose whole history is done (a finished project brought in from elsewhere) has no
    # measurable time to done, and is left out of the median rather than counted as zero.
    if [[ $still -eq 0 && -n "$done_ct" ]]; then echo $(( (done_ct - created + 43200) / 86400 )); fi
}

projects_row() {
    local rev="$1" day="$2" conv settings register entry_name default_owner dirs dir entry f kind rec state owners records="" durations=""
    conv="$(conventions "$rev")"
    settings="$(printf '%s\n' "$conv" | awk "$settings_awk")"
    loc_active="$(awk '$1 == "active" { print $2; exit }' <<< "$settings")"; loc_active="${loc_active:-^projects/[^/]+\$}"
    loc_paused="$(awk '$1 == "paused" { print $2; exit }' <<< "$settings")"
    loc_done="$(awk '$1 == "done" { print $2; exit }' <<< "$settings")"
    register="$(awk '$1 == "register" { print $2; exit }' <<< "$settings")"; register="${register:-projects/INDEX.md}"
    entry_name="$(awk '$1 == "entry" { print $2; exit }' <<< "$settings")"; entry_name="${entry_name:-README.md}"
    default_owner="$(awk '$1 == "owner" { $1 = ""; sub(/^ +/, ""); print; exit }' <<< "$settings")"
    done_names="$(awk '$1 == "alias" && $2 == "done" { $1 = $2 = ""; sub(/^ +/, ""); printf "|%s", $0 }' <<< "$settings")"
    done_names="done when$done_names"
    people_names="$(awk '$1 == "alias" && $2 == "people" { $1 = $2 = ""; sub(/^ +/, ""); printf "|%s", $0 }' <<< "$settings")"
    people_names="people$people_names"

    # Project folders: any folder matching a location that holds an entry point.
    dirs="$(git ls-tree -r --name-only "$rev" | { grep -E "/(README|CLAUDE)\\.md\$|/${entry_name//./\\.}\$" || true; } | sed 's#/[^/]*$##' | sort -u \
        | { grep -E "$loc_active${loc_paused:+|$loc_paused}${loc_done:+|$loc_done}" || true; })"

    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        # The entry point is the first of the conventions' entry point, README.md and CLAUDE.md that
        # carries a Now block, else the first that exists — the order the projects hook reads them in.
        entry=""
        for f in "$entry_name" README.md CLAUDE.md; do
            git cat-file -e "$rev:$dir/$f" 2>/dev/null || continue
            [[ -n "$entry" ]] || entry="$dir/$f"
            if [[ "$(state_of "$rev" "$dir/$f" -)" != "-" ]]; then entry="$dir/$f"; break; fi
        done
        [[ -n "$entry" ]] || continue
        kind="$(kind_of "$dir")"
        rec="$(git show "$rev:$entry" | awk -v done_names="$done_names" -v people_names="$people_names" "$readme_awk")"
        state="${rec%%$'\t'*}"
        if [[ "$state" == "-" ]]; then case "$kind" in done) state=done ;; paused) state=parked ;; esac; fi
        rec="$state"$'\t'"${rec#*$'\t'}"
        # No People section: the register row whose cells name this folder supplies the owner, else
        # a default owner the conventions name (- **Default owner:** `Sam`), as a one-person
        # repository might.
        if [[ "$(cut -f4 <<< "$rec")" == 0 ]]; then
            owners="$(git show "$rev:$register" 2>/dev/null | awk -F'|' -v slug="${dir##*/}" '
                /^\|/ && ocol == "" { for (i = 2; i < NF; i++) { c = tolower($i); gsub(/[ *]/, "", c); if (c == "owner") ocol = i } next }
                !/^\|/ { ocol = "" ; next }
                /^\|[ :|-]+$/ { next }
                { if (match($0, "(^|[^A-Za-z0-9_-])" slug "([^A-Za-z0-9_-]|$)")) { o = tolower($ocol); gsub(/^[ \t]+|[ \t]+$/, "", o); if (o != "" && o !~ /^(<|not yet named|none found|-)/) print o; exit } }' || true)"
            owners="${owners:-$default_owner}"
            rec="$(awk -F'\t' -v OFS='\t' -v o="${owners:--}" '{ $5 = o; print }' <<< "$rec")"
        fi
        records+="$rec"$'\n'
        [[ "$state" != done ]] || durations+="$(days_to_done "$rev" "$entry")"$'\n'
    done <<< "$dirs"

    # Active is anything not done or parked, including a project whose State cannot be read: it is
    # still work the team carries, and the missing Now block shows up as a missing next action.
    printf '%s' "$records" | awk -F'\t' -v day="$day" '
        function jdn(s,   y, m, d, a) { y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
            a = int((14 - m) / 12); y += 4800 - a; m += 12 * a - 3
            return d + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400) - 32045 }
        NF < 6 { next }
        $1 == "done" { done++; next }
        $1 == "parked" { next }
        {
            active++; nxt += $2; dw += $3
            n = split($6, w, " "); for (i = 1; i <= n; i++) if (w[i] ~ /^[0-9]/ && jdn(day) - jdn(w[i]) > 14) waiting++
            if ($1 == "doing" && $5 != "-") { n = split($5, o, ","); for (i = 1; i <= n; i++) if (!((NR SUBSEP o[i]) in seen)) { seen[NR SUBSEP o[i]] = 1; c[o[i]]++ } }
        }
        END { for (p in c) if (c[p] > max) max = c[p]
              printf "%d,%d,%d,%d,%d,%d", active, nxt, dw, done, waiting, max }'
    # The median of whole days, halves rounded up; empty when nothing has reached done yet, because
    # zero would read as instant.
    printf ',%s\n' "$(printf '%s' "$durations" | grep -E '^[0-9]+$' | sort -n | awk '{ v[NR] = $1 }
        END { if (NR) print (NR % 2 ? v[(NR + 1) / 2] : int((v[NR / 2] + v[NR / 2 + 1] + 1) / 2)) }')"
}

# --------------------------------------------------------------------------------------------------

row_for() {
    local day="$1" rev bytes=0 f s decisions doc_files people audits named exist commits authors since
    rev="$(git rev-list -1 --before="$day 23:59:59" HEAD 2>/dev/null || true)"
    if [[ -z "$rev" ]]; then echo "$day,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"; return; fi

    for f in "${always_loaded[@]}"; do
        s="$(git cat-file -s "$rev:$f" 2>/dev/null || echo 0)"
        bytes=$((bytes + s))
    done

    # Decision entries are dated level-two headings: "## [YYYY-MM-DD] Title" as in
    # templates/project-decisions.md, or "## YYYY-MM-DD — Title" as some teams' own logs write them.
    # git grep exits 1 when nothing matches, which is a count of zero rather than a failure.
    decisions="$(git grep -c -E '^## \[?[0-9]{4}-[0-9]{2}-[0-9]{2}' "$rev" -- 'logs/decisions.md' 'projects/*/decisions.md' 2>/dev/null \
        | awk -F: '{n += $NF} END {print n + 0}' || true)"

    doc_files="$(git ls-tree -r --name-only "$rev" -- docs memory projects logs templates rituals 2>/dev/null | grep -c '\.md$' || true)"
    # Each folder's README describes the folder and is not one of the things being counted.
    people="$(git ls-tree -r --name-only "$rev" -- memory/people 2>/dev/null | grep '\.md$' | grep -vc '/README\.md$' || true)"
    # Reports only: the dated markdown the hygiene pass, the register audit and the project review
    # write. A metrics CSV kept in audits/ is not a report.
    audits="$(git ls-tree -r --name-only "$rev" -- audits 2>/dev/null | grep '\.md$' | grep -vc '/README\.md$' || true)"

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

    echo "$day,$bytes,$decisions,$doc_files,$people,$audits,$named,$exist,$commits,$authors,$(projects_row "$rev" "$day")"
}

case "$mode" in
    print)
        echo "$header"; row_for "$(days_ago 0)" ;;
    backfill)
        # Weeks ending before the first commit are left out, not written as zeros.
        { echo "$header"; for ((w = weeks; w >= 0; w--)); do
            d="$(days_ago $((w * 7)))"
            [[ -z "$first_day" || "$w" -eq 0 || ! "$d" < "$first_day" ]] || continue
            row_for "$d"
        done; } > "$out"
        cat "$out" ;;
    append)
        today="$(days_ago 0)"
        if [[ -f "$out" && "$(head -n 1 "$out")" != "$header" ]]; then
            # Written by an older version with fewer columns: every row is recomputed from history, so
            # the file is rebuilt for the same dates rather than left with rows of two shapes.
            echo "measure.sh: $out has older columns; recomputing its rows" >&2
            { echo "$header"; tail -n +2 "$out" | cut -d, -f1 | grep -E '^[0-9]{4}-' | while read -r d; do row_for "$d"; done; } > "$out.tmp"
            mv "$out.tmp" "$out"
        fi
        [[ -f "$out" ]] || echo "$header" > "$out"
        grep -v "^$today," "$out" > "$out.tmp" || true
        row_for "$today" >> "$out.tmp"
        mv "$out.tmp" "$out"
        tail -n 1 "$out" ;;
esac
