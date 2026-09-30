#!/usr/bin/env bash
# Team metrics, read from git history. Counts only: no file contents, names or email addresses
# leave this script, so the CSV can be shared outside the team without review.
#
#   pilot/measure.sh                 append (or refresh) today's row in pilot/metrics.csv
#   pilot/measure.sh --backfill 8    rebuild the CSV with one row per week for the last 8 weeks
#   pilot/measure.sh --print         print today's row without writing anything
#   --out <path>                     write somewhere other than pilot/metrics.csv (with either mode)
#   --target <dir>                   measure that repository (default: the one the command is run in,
#                                    so bash kit/pilot/measure.sh from a workspace's root measures it)
#   MEASURE_ALWAYS_LOADED="CLAUDE.md" pilot/measure.sh
#                                    the files counted as always loaded (default: CLAUDE.md AGENTS.md
#                                    kit/CLAUDE.kit.md), with every file they import by an @path line
#
# Each row is a snapshot of the repository as it stood at the end of that day, plus activity in the
# seven days up to it. Backfill works because every number is recomputed from a past commit rather
# than remembered — which is also why the numbers can be trusted in a write-up. It reads committed
# history only: before the first commit there is nothing to write, and backfill starts at the week
# of the first commit rather than inventing zero rows for the weeks before it.
set -euo pipefail

# Every git call reads only: optional locks off, so a run beside a live session never leaves an
# index.lock behind.
git() { command git --no-optional-locks "$@"; }

usage() { sed -n '2,19p' "$0"; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

mode=append weeks="" out="" target=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --print) mode=print; shift ;;
        --backfill) mode=backfill; weeks="${2:-}"; [[ "$weeks" =~ ^[0-9]+$ ]] || usage; shift 2 ;;
        --out) out="${2:-}"; [[ -n "$out" ]] || usage; shift 2 ;;
        --target) target="${2:-}"; [[ -n "$target" ]] || usage; shift 2 ;;
        *) usage ;;
    esac
done

# A relative --out is relative to where the command was typed, as any other path argument would be.
[[ -z "$out" || "$out" == /* ]] || out="$PWD/$out"
root="$(git -C "${target:-.}" rev-parse --show-toplevel)"
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
header+=",projects_active,projects_blocked,projects_with_done_when,projects_done,blocked_over_14d,max_in_flight_per_person,median_days_to_done"
header+=",ablations_named,ablations_discriminating,ablations_no_difference"

# The always-loaded tier. In a workspace built on the kit, CLAUDE.md starts with an import of the kit's
# working standards, kit/CLAUDE.kit.md, and AGENTS.md routes other tools to the same file; a 2.x install
# has CLAUDE.md as a one-line import of AGENTS.md. Every file on the list is counted, and so is every file
# they import with an @path line, each once, so growth in any of them shows up. A repository whose
# agents load something else says so.
read -r -a always_loaded <<< "${MEASURE_ALWAYS_LOADED:-CLAUDE.md AGENTS.md kit/CLAUDE.kit.md}"
# Files some workspaces keep for other tools and do not let tools read (AW_OPAQUE_PATHS, as the kit's
# engine reads it: unset means these two, set but empty means none). Their size is counted from git's
# record of them; their content is never read, so an import inside one is not followed. One the kit's
# engine created itself (a created or accepted line in .claude/kit-templates.lock) stays readable.
opaque_paths="${AW_OPAQUE_PATHS-AGENTS.md copilot-instructions.md}"

# Paths that count as the team's documentation, as opposed to code or pilot bookkeeping.
doc_paths=(AGENTS.md CLAUDE.md docs memory projects logs templates rituals)

# GNU date and BSD (macOS) date spell "n days ago" differently.
days_ago() { date -u -d "-$1 days" +%F 2>/dev/null || date -u -v-"$1"d +%F; }

# --- Projects -------------------------------------------------------------------------------------
# The project columns read the Current state block, Done when and People sections of each project's
# entry point, as the projects commands write them (templates/project-readme.md). The rules are the
# ones under "How the files are read" in the projects plugin's README, so the board and these numbers
# agree:
#   - labels are read bold or plain: "- **State:** doing" and "State: doing" are the same line;
#   - State is one of ready, doing, blocked, paused or done; anything else is unread;
#   - a value that is empty, "-", "—", "none" or "n/a", or starts "none found", "not yet named" or
#     "<" (a template stand-in), is missing;
#   - a project is blocked when its State reads blocked or it carries a Blocked by line; the block is
#     dated only by the date after "since" on that line;
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
# shellcheck disable=SC2016  # an awk program: its $ fields are awk's, not the shell's
settings_awk='
function first_tick(s) { return match(s, /`[^`]+`/) ? substr(s, RSTART + 1, RLENGTH - 2) : "" }
function is_label(line, name) { return tolower(line) ~ ("^[ \t]*[-*] \\*\\*" name ":\\*\\*") }
# A folder whose name starts with _ or . is reserved, not a project (projects/_done, projects/_delete),
# so a <slug> placeholder never matches one.
function folder(v) {
    sub(/^\.\//, "", v); sub(/\/+$/, "", v); gsub(/\./, "\\.", v)
    if (v ~ /</) gsub(/<[^>]*>/, "[^/_.][^/]*", v); else v = v "/[^/_.][^/]*"
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
#   state  blocked(0/1)  done_when(0/1)  has_people(0/1)  owners(comma list)  blocked since(date)
# The owners are the people named owns or does, lower-cased; they are compared, never printed.
# shellcheck disable=SC2016  # an awk program, as above
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
state == "" && (v = label($0, "state")) != "\001" { if (missing(v)) next; state = tolower(v); sub(/^[^a-z]+/, "", state); sub(/[^a-z].*/, "", state); next }
by == "" && (v = label($0, "blocked by")) != "\001" {
    if (missing(v)) next
    # Only "since <date>" dates the block; another date on the line (a due date, say) leaves it undated.
    by = "nodate"; lv = tolower(v)
    if (match(lv, /since[ \t]+[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) by = substr(lv, RSTART + RLENGTH - 10, 10)
    next
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
    if (state !~ /^(ready|doing|blocked|paused|done)$/) state = "-"
    blocked = (state == "blocked" || by != "")
    printf "%s\t%d\t%d\t%d\t%s\t%s\n", state, blocked, done_when + 0, people + 0, (owners == "" ? "-" : owners), (by == "" ? "-" : by)
}'

# state_of <rev> <path> <kind>: the State a README had at a revision. Without a State line, a
# project in a folder kept for done or paused work is read as done or paused.
state_of() {
    local s
    s="$(git show "$1:$2" 2>/dev/null | awk -v done_names="$done_names" -v people_names="$people_names" "$readme_awk" | cut -f1 || true)"
    if [[ "$s" == "-" ]]; then case "$3" in "done") s="done" ;; paused) s=paused ;; esac; fi
    echo "$s"
}

# kind_of <dir>: which conventions location a project folder sits in. A folder that matches the
# active location is active, however the other locations are written — in the kit default all three
# are the same folder and only State tells them apart.
kind_of() {
    if [[ "$1" =~ $loc_active ]]; then echo active
    elif [[ -n "$loc_done" && "$1" =~ $loc_done ]]; then echo "done"
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
        if [[ $still -eq 1 && "$(state_of "$hash" "$path" "$(kind_of "$(dirname "$path")")")" == "done" ]]; then done_ct="$ct"; else still=0; fi
    done < <(git log --follow --format='C %H %ct' --name-only "$1" -- "$2")
    # A README whose whole history is done (a finished project brought in from elsewhere) has no
    # measurable time to done, and is left out of the median rather than counted as zero.
    if [[ $still -eq 0 && -n "$done_ct" ]]; then echo $(( (done_ct - created + 43200) / 86400 )); fi
}

projects_row() {
    local rev="$1" day="$2" conv settings register entry_name default_owner dirs dir entry f kind rec state owners records="" durations=""
    conv="$(conventions "$rev")"
    settings="$(printf '%s\n' "$conv" | awk "$settings_awk")"
    loc_active="$(awk '$1 == "active" { print $2; exit }' <<< "$settings")"; loc_active="${loc_active:-^projects/[^/_.][^/]*\$}"
    loc_paused="$(awk '$1 == "paused" { print $2; exit }' <<< "$settings")"
    loc_done="$(awk '$1 == "done" { print $2; exit }' <<< "$settings")"
    # With no conventions file at all, the kit's own default applies: finished projects in projects/_done/.
    [[ -n "$conv" ]] || loc_done='^projects/_done/[^/_.][^/]*$'
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
        # carries a readable State, else the first that exists — the order the projects hook reads
        # them in.
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
        if [[ "$state" == "-" ]]; then case "$kind" in "done") state="done" ;; paused) state=paused ;; esac; fi
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
        [[ "$state" != "done" ]] || durations+="$(days_to_done "$rev" "$entry")"$'\n'
    done <<< "$dirs"

    # Active is anything not done or paused, including a project whose State cannot be read: it is
    # still work the team carries. Blocked projects are active; blocked_over_14d counts those whose
    # block is dated more than 14 days before the row's day.
    printf '%s' "$records" | awk -F'\t' -v day="$day" '
        function jdn(s,   y, m, d, a) { y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
            a = int((14 - m) / 12); y += 4800 - a; m += 12 * a - 3
            return d + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400) - 32045 }
        NF < 6 { next }
        $1 == "done" { done++; next }
        $1 == "paused" { next }
        {
            active++; blk += $2; dw += $3
            if ($2 && $6 ~ /^[0-9]/ && jdn(day) - jdn($6) > 14) stuck++
            if ($1 == "doing" && $5 != "-") { n = split($5, o, ","); for (i = 1; i <= n; i++) if (!((NR SUBSEP o[i]) in seen)) { seen[NR SUBSEP o[i]] = 1; c[o[i]]++ } }
        }
        END { for (p in c) if (c[p] > max) max = c[p]
              printf "%d,%d,%d,%d,%d,%d", active, blk, dw, done, stuck, max }'
    # The median of whole days, halves rounded up; empty when nothing has reached done yet, because
    # zero would read as instant.
    printf ',%s\n' "$(printf '%s' "$durations" | grep -E '^[0-9]+$' | sort -n | awk '{ v[NR] = $1 }
        END { if (NR) print (NR % 2 ? v[(NR + 1) / 2] : int((v[NR / 2] + v[NR / 2 + 1] + 1) / 2)) }')"
}

# --- Ablations ------------------------------------------------------------------------------------
# ablations_named is the number of ablation files in pilot/ablations/; of those, the other two count
# the ablations whose latest result on or before the row's day is `discriminates`, or `no difference
# (both pass)`. The result comes from ablate.sh --outcomes, the rule its report flags with, so these
# counts and the report agree; `leans with, rerun at k=5`, `check fails both arms`, `inconclusive` and
# the comparator-only results count in neither.
# Past rows read the files and pilot/ablation-results.csv as committed at that revision, so backfill
# works. Today's row reads them from the working tree: the runner writes results that are committed
# with the row, and the weekly pass measures again after it runs the ablations.
# The runner is the kit's: beside this script in a kit checkout, else in the workspace's kit/, else
# (a 2.x install) in the checkout the installer recorded when it vendored the plugins here.
ablate_sh="$here/ablate.sh"
[[ -f "$ablate_sh" ]] || ablate_sh="$root/kit/pilot/ablate.sh"
if [[ ! -f "$ablate_sh" ]]; then
    kit_checkout="$(sed -n 's/^kit checkout: \(.*\) (on the machine that ran the installer)$/\1/p' .claude/plugins/VENDORED 2>/dev/null | awk 'NR == 1' || true)"
    ablate_sh="${kit_checkout:+$kit_checkout/pilot/ablate.sh}"
fi
results_tmp="$(mktemp "${TMPDIR:-/tmp}/measure.XXXXXX")"
blob_tmp="$(mktemp "${TMPDIR:-/tmp}/measure.XXXXXX")"
trap 'rm -f "$results_tmp" "$results_tmp.day" "$blob_tmp"' EXIT

ablations_row() {
    local rev="$1" day="$2" names outcomes
    if [[ "$day" == "$(days_ago 0)" && -d pilot/ablations ]]; then
        names="$(find pilot/ablations -maxdepth 1 -name '*.md' ! -name README.md | sed 's#.*/##; s#\.md$##')"
        cat pilot/ablation-results.csv > "$results_tmp" 2>/dev/null || : > "$results_tmp"
    else
        names="$(git ls-tree --name-only "$rev" -- pilot/ablations/ 2>/dev/null | { grep '\.md$' || true; } \
            | { grep -v '/README\.md$' || true; } | sed 's#.*/##; s#\.md$##')"
        git show "$rev:pilot/ablation-results.csv" > "$results_tmp" 2>/dev/null || : > "$results_tmp"
    fi
    if [[ -z "$names" ]]; then printf '0,0,0'; return; fi
    # Results dated after the row's day are not yet known on that day. Without the runner there is no
    # rule to read them by, so the two counts are left empty rather than guessed.
    if [[ ! -f "$ablate_sh" ]]; then printf '%d,,' "$(grep -c . <<< "$names")"; return; fi
    awk -F, -v day="$day" 'NR == 1 || $1 <= day' "$results_tmp" > "$results_tmp.day" && mv "$results_tmp.day" "$results_tmp"
    outcomes="$(bash "$ablate_sh" --target "$root" --outcomes "$results_tmp" 2>/dev/null || true)"
    awk -F'\t' -v names="$(paste -sd, - <<< "$names")" '
        BEGIN { n = split(names, a, ","); for (i = 1; i <= n; i++) named[a[i]] = 1 }
        ($1 in named) && $3 == "discriminates" { d++ }
        ($1 in named) && $3 == "no difference (both pass)" { nd++ }
        END { printf "%d,%d,%d", n, d, nd }' <<< "$outcomes"
}

# --- The always-loaded tier -----------------------------------------------------------------------
# A file inside a submodule is read at the commit the revision records for that submodule, from the
# submodule's own objects: the workspace's history holds only the pointer. So kit/CLAUDE.kit.md counts
# as it stood at the kit commit the workspace had committed that day, and a kit update shows in the row
# for the week its pointer was committed, not before.

# blob_at <rev> <path>: the file's bytes at that revision, into $blob_tmp. Status 1 when it is not
# there: never committed, or inside a submodule whose recorded commit this checkout does not have.
blob_at() {
    local rev="$1" path="$2" sub sha
    : > "$blob_tmp"
    if git cat-file -e "$rev:$path" 2>/dev/null; then git cat-file blob "$rev:$path" > "$blob_tmp"; return 0; fi
    sub="$path"
    while [[ "$sub" == */* ]]; do
        sub="${sub%/*}"
        sha="$(git ls-tree "$rev" -- "$sub" 2>/dev/null | awk '$1 == "160000" { print $3; exit }')"
        [[ -n "$sha" ]] || continue
        [[ -e "$sub/.git" ]] || return 1
        # The submodule is another repository: git's own variables, if a hook set them, point elsewhere.
        ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX
          git -C "$sub" cat-file blob "$sha:${path#"$sub"/}" ) > "$blob_tmp" 2>/dev/null || { : > "$blob_tmp"; return 1; }
        return 0
    done
    return 1
}

# is_opaque <path>: status 0 when the path is one whose content is not read here (see opaque_paths).
is_opaque() {
    local p
    for p in $opaque_paths; do
        [[ "$1" == "$p" ]] || continue
        awk -F'\t' -v d="$1" '$1 == d && ($5 == "created" || $5 == "accepted") { found = 1 } END { exit !found }' \
            .claude/kit-templates.lock 2>/dev/null && return 1
        return 0
    done
    return 1
}

# imports_of <file>: the @path imports in the file at $blob_tmp, one per line, as written. An import is
# an @ at the start of a line or after a space, followed by a path; code spans and fenced blocks are
# skipped, as Claude Code skips them.
# shellcheck disable=SC2016  # an awk program: its $ fields are awk's, not the shell's
imports_awk='
/^[ \t]*(```|~~~)/ { fence = !fence; next }
fence { next }
{
    line = $0; gsub(/`[^`]*`/, "", line)
    while (match(line, /(^|[ \t])@[^ \t]+/)) {
        tok = substr(line, RSTART, RLENGTH); sub(/^[ \t]*@/, "", tok); sub(/[.,;:)]+$/, "", tok)
        if (tok != "") print tok
        line = substr(line, RSTART + RLENGTH)
    }
}'

# resolve <importing file> <import>: the import as a repository-relative path, or nothing when it leaves
# the repository (a home-directory or absolute path, or one that climbs above the root).
resolve() {
    local from="$1" imp="$2" dir out="" seg rest
    case "$imp" in "~"*|/*) return 0 ;; esac
    dir="$(dirname "$from")/"
    [[ "$dir" != ./ ]] || dir=""
    rest="$dir$imp/"
    while [[ -n "$rest" ]]; do
        seg="${rest%%/*}"; rest="${rest#*/}"
        case "$seg" in
            ""|.) ;;
            ..) [[ -n "$out" ]] || return 0
                if [[ "$out" == */* ]]; then out="${out%/*}"; else out=""; fi ;;
            *) out="${out:+$out/}$seg" ;;
        esac
    done
    printf '%s' "$out"
}

# always_bytes <rev>: the bytes of the always-loaded files and everything they import, each file once,
# imports followed up to five deep as Claude Code follows them.
always_bytes() {
    local rev="$1" bytes=0 seen=" " queue=() depth=() i=0 f d s imp p
    for f in "${always_loaded[@]}"; do queue+=("$f"); depth+=(0); done
    while [[ $i -lt ${#queue[@]} ]]; do
        f="${queue[$i]}" d="${depth[$i]}"; i=$((i + 1))
        case "$seen" in *" $f "*) continue ;; esac
        seen+="$f "
        if is_opaque "$f"; then
            s="$(git cat-file -s "$rev:$f" 2>/dev/null || echo 0)"; bytes=$((bytes + s)); continue
        fi
        blob_at "$rev" "$f" || continue
        bytes=$((bytes + $(wc -c < "$blob_tmp")))
        [[ $d -lt 5 ]] || continue
        while IFS= read -r imp; do
            p="$(resolve "$f" "$imp")"
            [[ -n "$p" ]] || continue
            queue+=("$p"); depth+=($((d + 1)))
        done < <(awk "$imports_awk" "$blob_tmp")
    done
    echo "$bytes"
}

# --------------------------------------------------------------------------------------------------

row_for() {
    local day="$1" rev bytes=0 decisions doc_files people audits named exist commits authors since
    rev="$(git rev-list -1 --before="$day 23:59:59" HEAD 2>/dev/null || true)"
    if [[ -z "$rev" ]]; then echo "$day,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,,0,0,0"; return; fi

    bytes="$(always_bytes "$rev")"

    # Decision entries are dated level-two headings: "## [YYYY-MM-DD] Title" as in
    # templates/project-decisions.md, or "## YYYY-MM-DD — Title" as some teams' own logs write them.
    # git grep exits 1 when nothing matches, which is a count of zero rather than a failure.
    decisions="$(git grep -c -E '^## \[?[0-9]{4}-[0-9]{2}-[0-9]{2}' "$rev" -- 'logs/decisions.md' 'projects/*/decisions.md' 2>/dev/null \
        | awk -F: '{n += $NF} END {print n + 0}' || true)"

    doc_files="$(git ls-tree -r --name-only "$rev" -- docs memory projects logs templates rituals 2>/dev/null | grep -c '\.md$' || true)"
    # Each folder's README describes the folder and is not one of the things being counted.
    people="$(git ls-tree -r --name-only "$rev" -- memory/people 2>/dev/null | grep '\.md$' | grep -vc '/README\.md$' || true)"
    # Reports only: the dated markdown the hygiene pass and the register audit write. A metrics CSV kept in audits/ is not a report.
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

    echo "$day,$bytes,$decisions,$doc_files,$people,$audits,$named,$exist,$commits,$authors,$(projects_row "$rev" "$day"),$(ablations_row "$rev" "$day")"
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
