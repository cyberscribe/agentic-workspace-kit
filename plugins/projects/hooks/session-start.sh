#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# SessionStart line for the projects plugin.
#
# Inside a project folder whose entry point carries a Current state block, it
# gives the session three lines — the desired outcome, Done when progress, and the
# state with its owner (and what blocks it, when something does) — so the person
# and the agent start from where the project stands. Anywhere else it says
# nothing, except at most once a day per repository: one line when an active
# project has been blocked for more than 14 days. A clean day prints nothing and
# records nothing.
#
# The lines go out twice: as systemMessage, which the person sees, and as
# additionalContext, which the agent reads. Only SessionStart accepts the latter.
#
# Hook-environment rules, shared with the closeout plugin's hooks: jq is
# required, there is no network, the timeout is 5 seconds (hooks/hooks.json), and
# any failure is silent — this line is a convenience, never a gate, so every path
# out of the script exits 0 with nothing on stderr.
#
# Environment:
#   PROJECTS_HOOK_DISABLED=1     turn the hook off
#   AW_HEADLESS_RUN=1            a headless run (an ablation arm): say nothing and record nothing
#   PROJECTS_HOOK_STATE_DIR      where the once-a-day stamps live
#                                (default ~/.claude/projects-hook; outside any repo)
#   PROJECTS_HOOK_TODAY          YYYY-MM-DD to use as today (for tests)
#
# Wired from hooks/hooks.json -> hooks.SessionStart (matcher startup|resume).
# Written for bash 3.2, since macOS runs hooks with /bin/bash when it is first on PATH.

exec 2>/dev/null
trap 'exit 0' EXIT

# Read the hook input before any early exit, so the writer never meets a closed pipe
# (SIGPIPE, exit 141) — the same order as the closeout hooks.
input="$(cat)"

[[ "${PROJECTS_HOOK_DISABLED:-}" == "1" ]] && exit 0
# A headless run has no person to tell, and its once-a-day stamp would hide the line from the next real session.
[[ "${AW_HEADLESS_RUN:-}" == "1" ]] && exit 0
# The closeout plugin's capture child is itself a session; it has no one to tell.
[[ -n "${CLOSEOUT_HOOK_CHILD:-}" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

here="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/config.sh
source "$here/lib/config.sh" || exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
cwd="${cwd:-$PWD}"
cwd="${cwd%/}"
[[ -d "$cwd" ]] || exit 0

root="$(projects_root "$cwd")"
[[ -n "$root" ]] || exit 0
projects_config "$root"

# emit <lines for the person> <context for the agent>
emit() {
    jq -nc --arg m "$1" --arg c "$2" \
        '{systemMessage:$m, hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$c}}'
    exit 0
}

# parse <file>... — one record per file from lib/readme.awk.
parse() {
    awk -v alias_outcome="$ALIAS_OUTCOME" -v alias_done="$ALIAS_DONE" -v alias_people="$ALIAS_PEOPLE" \
        -f "$here/lib/readme.awk" "$@"
}


# ---- Inside a project folder -------------------------------------------------

rel=""
[[ "$cwd" == "$root" ]] || rel="${cwd#"$root"/}"
project=""
if [[ -n "$rel" ]]; then
    # The longest match wins, so work/_paused/<slug> beats work/<slug>.
    for pattern in "$ACTIVE_PATTERN" "$PAUSED_PATTERN" "$DONE_PATTERN"; do
        [[ -n "$pattern" ]] || continue
        m="$(projects_match "$pattern" "$rel")"
        [[ ${#m} -gt ${#project} ]] && project="$m"
    done
fi

if [[ -n "$project" ]]; then
    files=()
    for f in "$ENTRY_POINT" README.md CLAUDE.md; do
        [[ -f "$root/$project/$f" ]] && files+=("$root/$project/$f")
    done
    [[ ${#files[@]} -gt 0 ]] || exit 0

    # The first entry point with a Current state block speaks for the project.
    record=""
    while IFS= read -r line; do
        IFS=$'\x1f' read -r _f has_block _rest <<EOF
$line
EOF
        [[ "$has_block" == "1" ]] && { record="$line"; break; }
    done <<EOF
$(parse "${files[@]}")
EOF
    [[ -n "$record" ]] || exit 0

    IFS=$'\x1f' read -r file _has state outcome done_found done_total done_ticked owner proposed title people_found \
        blocked_by _since updated old_format <<EOF
$record
EOF
    name="${title:-${project##*/}}"

    # With no People section, the owner is the register row naming this folder, else the one owner
    # the conventions name for every project — the same order the board and the metrics follow.
    if [[ -z "$owner" && "$people_found" != "1" ]]; then
        if [[ -f "$root/$REGISTER_FILE" ]]; then
            owner="$(awk -F'|' -v slug="${project##*/}" '
                /^\|/ && ocol == "" { for (i = 2; i < NF; i++) { c = tolower($i); gsub(/[ *]/, "", c); if (c == "owner") ocol = i } next }
                !/^\|/ { ocol = ""; next }
                /^\|[ :|-]+$/ { next }
                { if (match($0, "(^|[^A-Za-z0-9_-])" slug "([^A-Za-z0-9_-]|$)")) { o = $ocol; gsub(/^[ \t]+|[ \t]+$/, "", o); gsub(/\*|`/, "", o)
                    if (o != "" && tolower(o) !~ /^(<|not yet named|none found|-$|—$|none$|n\/a$)/) print o; exit } }' "$root/$REGISTER_FILE")"
        fi
        owner="${owner:-$DEFAULT_OWNER}"
    fi

    line1="Project: $name"
    [[ "$proposed" == "1" ]] && line1="$line1 (proposed)"
    if [[ -n "$outcome" ]]; then
        [[ ${#outcome} -gt 200 ]] && outcome="${outcome:0:197}…"
        line1="$line1 — outcome: $outcome"
    else
        # Said as what this line can read, not as a judgement on the file: the outcome may be
        # there in a form it does not know (a Goal line, a prose paragraph).
        line1="$line1 — no Desired outcome section found"
    fi

    if [[ "$done_found" == "1" && "$done_total" -gt 0 ]]; then
        line2="Done when: $done_ticked of $done_total ticked"
    elif [[ "$done_found" == "1" ]]; then
        line2="Done when: a section with no checklist yet"
    else
        line2="Done when: no checklist found"
    fi

    if [[ "$state" == "done" ]]; then
        # A finished project's close is recorded in the file; its Updated: date is when.
        line3="Done${updated:+ $updated}; how it ended is recorded in ${file##*/}"
    else
        line3="State: ${state:-not set}"
        if [[ -n "$blocked_by" ]]; then
            [[ "$state" == "blocked" ]] && line3="$line3 by $blocked_by" || line3="$line3 — blocked by $blocked_by"
        fi
        if [[ -n "$owner" ]]; then
            line3="$line3 — owner $owner"
        else
            [[ "$people_found" == "1" ]] && line3="$line3 — no owner in People" || line3="$line3 — no owner named"
        fi
        # The block's earlier format (a Now heading) is still read; its states may be ones the
        # kit no longer uses, so the line says where they came from.
        [[ "$old_format" == "1" ]] && line3="$line3 — from an older Now block; /projects:adopt converts it"
    fi

    lines="$line1
$line2
$line3"
    context="Where this session's project stands, from the projects plugin's session-start line (read from ${file#"$root"/}; the file is canonical, and this is a summary of it):
$lines"
    [[ "$proposed" == "1" ]] && context="$context
Sections marked \"proposed\" were drafted by /projects:adopt and are still for the person to confirm or edit."
    emit "$lines" "$context"
fi

# ---- Anywhere else: at most one line a day ----------------------------------

today="${PROJECTS_HOOK_TODAY:-$(date +%Y-%m-%d)}"
state_dir="${PROJECTS_HOOK_STATE_DIR:-$HOME/.claude/projects-hook}"
key="${root//\//-}"
stamp="$state_dir/${key#-}.last"
[[ -f "$stamp" && "$(cat "$stamp")" == "$today" ]] && exit 0

# Every active project folder with an entry point, other than one that is its own
# repository (its tracking travels with that repository, not this one).
glob="$(printf '%s' "$ACTIVE_PATTERN" | sed 's/<[^>]*>/*/g')"
files=()
for dir in "$root"/$glob; do
    [[ -d "$dir" && ! -e "$dir/.git" ]] || continue
    for f in "$ENTRY_POINT" README.md CLAUDE.md; do
        [[ -f "$dir/$f" ]] && files+=("$dir/$f")
    done
done
[[ ${#files[@]} -gt 0 ]] || exit 0

# A project is read from its first entry point with a Current state block. It is
# named when its Blocked by line is dated more than 14 days before today and it is
# neither done nor paused. Projects are named by their title, as every command
# names them; a prefix is not a name. Day counts use a day number computed in awk,
# since date(1) arithmetic differs between macOS and Linux.
blocked="$(parse "${files[@]}" | awk -F '\037' -v today="$today" '
    function dayno(d,   y, m, a) {
        y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0
        a = int((14 - m) / 12); y = y + 4800 - a; m = m + 12 * a - 3
        return substr(d, 9, 2) + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400)
    }
    { d = $1; sub(/\/[^\/]*$/, "", d)
      if ($2 != "1" || (d in seen)) next
      seen[d] = 1
      if ($13 == "" || $3 == "done" || $3 == "paused") next
      if (dayno(today) - dayno($13) <= 14) next
      if ($10 != "") print $10; else { sub(/.*\//, "", d); print d } }')"
[[ -n "$blocked" ]] || exit 0

count="$(printf '%s\n' "$blocked" | grep -c .)"
names="$(printf '%s\n' "$blocked" | head -3 | paste -sd, - | sed 's/,/, /g')"
[[ "$count" -gt 3 ]] && names="$names, …"
if [[ "$count" == "1" ]]; then
    line="Projects: 1 active project blocked for more than 14 days ($names). /projects:board shows it."
else
    line="Projects: $count active projects blocked for more than 14 days ($names). /projects:board shows them."
fi

mkdir -p "$state_dir" && printf '%s\n' "$today" > "$stamp"

emit "$line" "From the projects plugin's once-a-day session-start line for this repository:
$line
Mention it only if the person's first request leaves room; it is a nudge, not a task."
