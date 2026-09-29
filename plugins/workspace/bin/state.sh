#!/usr/bin/env bash
# State check: a read-only report of where a repository stands against the kit, one key=value per line.
#
#   state.sh [DIR]            report on DIR (default: the repository this is run in)
#   state.sh --target DIR     the same
#   state.sh --json           the same facts as one JSON object (needs jq)
#   state.sh --verbose        say on stderr what could not be read; silent otherwise
#
# It is written to be the one answer to "what state is this repository in" for the quick-start and
# the setup wizard to branch on, rather than working it out again; the tests assert against it now,
# and the other consumers adopt it as they arrive. It writes nothing, makes no
# network call, and reads git only with --no-optional-locks, so running it from a shell that shares
# the repository with a live session (a desktop assistant's device shell, say) leaves no index.lock
# behind. It runs under bash 3.2 and needs only git; jq is used when present, for the settings file
# and --json. Its awk is POSIX awk without character classes, so an older mawk reads it the same.
#
# Keys (the meaning of each is in the comment beside the line that works it out):
#   state_version target in_git commits uncommitted authors author_names person person_slug
#   always_loaded agents_md claude_md gemini_md standins_remaining surface_standins
#   people_dir person_profile person_profile_path person_profile_candidates people_profiles
#   projects_conventions projects_dir paused_dir done_dir conventions_not_set in_flight_limit
#   staleness default_owner
#   register register_path register_rows project_folders projects_without_current_state
#   adopt_proposals glossary glossary_terms build_list verification catalogue readme codeowners
#   decisions_log decisions_log_other own_skills foreign_skills kit_incoming
#   settings plugins_registered plugins_mode plugins_path vendored_commit kit_checkout
#   closeout_conventions surfaces gemini_commands measure_script metrics_csv
#   closeout_drafts_pending signs mode
# Lists are comma-separated; an empty value means none. A key that could not be judged reads unknown.

VERBOSE=0 JSON=0 dir=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) dir="${2:-}"; shift 2 ;;
        --json) JSON=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) printf 'error=unknown option %s\n' "$1"; exit 2 ;;
        *) dir="$1"; shift ;;
    esac
done

note() { [[ $VERBOSE -eq 1 ]] && printf 'state.sh: %s\n' "$*" >&2; return 0; }

dir="${dir:-$PWD}"
if [[ ! -d "$dir" ]]; then printf 'error=not a directory: %s\n' "$dir"; exit 2; fi
# The one door to git. Optional locks off, so even `status` never refreshes and rewrites the index.
g() { git --no-optional-locks -C "$T" "$@" 2>/dev/null; }
# A folder inside a repository is reported on as the repository it belongs to.
T="$(git --no-optional-locks -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$T" ]] || T="$(cd "$dir" && pwd -P)"

out=""
emit() { out+="$1=$(printf '%s' "$2" | tr '\n' ' ')"$'\n'; }
# join: stdin lines as one comma-separated list.
join() { sed '/^$/d' | tr -d ',' | paste -sd, - ; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
# table_rows <file>: rows of every markdown table, header rows (the row above a |---| line) left out.
table_rows() {
    awk '/^[ \t]*\|/ { if ($0 ~ /^[ \t]*\|[-:| ]+\|[ \t]*$/) { if (prev) hdr++; next } rows++; prev = 1; next }
         { prev = 0 } END { print rows - hdr + 0 }' "$1" 2>/dev/null || echo 0
}
# conv <label>: the first backticked value on the "- **Label:**" bullet of .claude/projects.md — the
# one habit that file keeps, which the projects hook reads the same way.
conv() {
    [[ -f "$T/.claude/projects.md" ]] || return 0
    awk -v want="$(lower "$1")" '
        /^[ \t]*[-*] \*\*[^*]+:\*\*/ {
            l = $0; sub(/^[ \t]*[-*] \*\*/, "", l); lab = l; sub(/:\*\*.*/, "", lab)
            if (tolower(lab) == want) { if (match(l, /`[^`]*`/)) print substr(l, RSTART + 1, RLENGTH - 2); exit }
        }' "$T/.claude/projects.md" 2>/dev/null
}
# standins <file> <team|surfaces>: angle-bracketed stand-ins — a phrase with a space in it, the
# installer's own test, so path patterns like memory/people/<name>.md never count. "team" is §1–§3
# of a numbered manifest (the whole file when it has no numbered sections, as a team's own CLAUDE.md
# may not); "surfaces" is the §4 surface table. Fenced code blocks are skipped.
standins() {
    awk -v scope="$2" '
        NR == FNR { if ($0 ~ /^## [0-9]+[.]/) numbered = 1; next }
        /^[ \t]*```/ { fence = !fence; next }
        fence { next }
        /^## / { sec = -1; if ($0 ~ /^## [0-9]+[.]/) { s = $0; sub(/^## /, "", s); sub(/[.].*/, "", s); sec = s + 0 } }
        { if (numbered) { if ((scope == "team" && sec >= 1 && sec <= 3) || (scope == "surfaces" && sec == 4)) print }
          else if (scope == "team") print }' "$1" "$1" 2>/dev/null \
        | tr '\n' ' ' | grep -o '<[A-Za-z][^<>]* [^<>]*>' | wc -l | tr -d ' '
}

emit state_version 1
emit target "$T"

# --- Git: history, working tree, who is here --------------------------------------------------------
# in_git: yes | no | refused (a repository git will not read here, such as one owned by another user on
# a mounted folder: see git's safe.directory). Refused is not no: the history keys below then read 0.
if g rev-parse --git-dir >/dev/null; then in_git=yes
elif git --no-optional-locks -C "$T" rev-parse --git-dir 2>&1 | grep -qi 'dubious ownership\|safe.directory'; then
    in_git=refused; note "git refuses to read $T here (safe.directory)"
else in_git=no; note "$T is not a git repository"; fi
emit in_git "$in_git"
commits=0
[[ $in_git == yes ]] && commits="$(g rev-list --count HEAD || echo 0)"
emit commits "${commits:-0}"                        # 0 means the metrics baseline waits for a first commit
emit uncommitted "$( [[ $in_git == yes ]] && g status --porcelain | wc -l | tr -d ' ' || echo 0)"
if [[ "${commits:-0}" -gt 0 ]]; then
    shortlog="$(g shortlog -sn HEAD)"
    emit authors "$(printf '%s\n' "$shortlog" | sed '/^$/d' | wc -l | tr -d ' ')"   # one author: offer Default owner
    emit author_names "$(printf '%s\n' "$shortlog" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' | join)"
else
    emit authors 0; emit author_names ""
fi
# The person in front of the agent, from git config: a suggestion to confirm, never an assumption.
person="$(git --no-optional-locks -C "$T" config user.name 2>/dev/null)"
person_slug="$(lower "$person" | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')"
emit person "$person"
emit person_slug "$person_slug"

# --- The always-loaded file ---------------------------------------------------------------------------
# agents_md: kit (the installer's "Team Manifest" heading) | own (any other AGENTS.md, a router for
# other tools included) | unreadable (present, but this shell may not read it) | missing
# A sandbox that denies reads can deny the stat as well, so the file looks absent to -e. It counts as
# present when -e sees it, or when ls fails for any reason other than there being no such file.
agents_there=no
if [[ -e "$T/AGENTS.md" ]]; then agents_there=yes
else
    lserr="$(LC_ALL=C ls -d "$T/AGENTS.md" 2>&1 >/dev/null)"
    [[ -n "$lserr" && "$lserr" != *"No such file"* ]] && agents_there=yes
fi
if [[ $agents_there == yes ]] && { [[ ! -e "$T/AGENTS.md" || ! -r "$T/AGENTS.md" ]] || ! head -c 1 "$T/AGENTS.md" >/dev/null 2>&1; }; then
    agents_md=unreadable; note "AGENTS.md is present but cannot be read here"
elif [[ -f "$T/AGENTS.md" ]]; then
    if grep -qE '^# .*Team Manifest[[:space:]]*$' "$T/AGENTS.md" 2>/dev/null; then agents_md=kit; else agents_md=own; fi
else
    agents_md=missing
fi
# claude_md: shim (nothing but the @AGENTS.md import, comments and blank lines aside) | own | missing
if [[ -f "$T/CLAUDE.md" ]]; then
    body="$(awk '{ line = $0
                   while (1) { if (inc) { i = index(line, "-->"); if (!i) { line = ""; break } line = substr(line, i + 3); inc = 0 }
                               i = index(line, "<!--"); if (!i) break
                               rest = substr(line, i + 4); j = index(rest, "-->")
                               if (j) line = substr(line, 1, i - 1) substr(rest, j + 3); else { line = substr(line, 1, i - 1); inc = 1; break } }
                   gsub(/^[ \t\r]+|[ \t\r]+$/, "", line); if (line != "") print line }' "$T/CLAUDE.md" 2>/dev/null)"
    if [[ "$body" == "@AGENTS.md" ]]; then claude_md=shim; else claude_md=own; fi
else
    claude_md=missing
fi
[[ -f "$T/GEMINI.md" ]] && gemini_md=present || gemini_md=missing   # the kit never lays one down
# always_loaded: the file this surface actually loads, where the team part is judged and filled.
# A CLAUDE.md of the repository's own wins; AGENTS.md is it when CLAUDE.md is the kit's import or
# absent (other tools read AGENTS.md directly).
if [[ $claude_md == own ]]; then always_loaded=CLAUDE.md
elif [[ $agents_md != missing ]]; then always_loaded=AGENTS.md
else always_loaded=none; fi
emit always_loaded "$always_loaded"
emit agents_md "$agents_md"
emit claude_md "$claude_md"
emit gemini_md "$gemini_md"
# standins_remaining: stand-ins left in the always-loaded file's §1–§3. Above 0, the team part is open.
if [[ $always_loaded == none ]]; then standins=0 surf_standins=0
elif [[ $always_loaded == AGENTS.md && $agents_md == unreadable ]]; then standins=unknown surf_standins=unknown
else
    standins="$(standins "$T/$always_loaded" team)"; surf_standins="$(standins "$T/$always_loaded" surfaces)"
fi
emit standins_remaining "${standins:-0}"
emit surface_standins "${surf_standins:-0}"          # a stand-in row in §4: fill with the other surface, or remove

# --- Project conventions (.claude/projects.md) --------------------------------------------------------
# projects_conventions: kit (a "Project conventions" heading, projects in projects/<slug>/, the register
# at projects/INDEX.md) | foreign (another layout, or no such heading) | missing
active="$(conv Active)" register_path="$(conv Register)"
active="${active:-projects/<slug>/}" register_path="${register_path:-projects/INDEX.md}"
register_path="${register_path#./}"
if [[ ! -f "$T/.claude/projects.md" ]]; then pc=missing
elif grep -qiE '^#+[[:space:]]+Project conventions' "$T/.claude/projects.md" 2>/dev/null \
     && [[ "${active%/}" == "projects/<slug>" && "$register_path" == "projects/INDEX.md" ]]; then pc=kit
else pc=foreign; fi
emit projects_conventions "$pc"
# Where projects live: the Active pattern, and where paused and done ones go (the same, unless the
# conventions say otherwise). A value with prose after the path, as the kit's own lines have, is cut
# to the path.
emit projects_dir "$active"
paused="$(conv Paused)"; done_at="$(conv Done)"
emit paused_dir "${paused:-$active}"
emit done_dir "${done_at:-$active}"
n="$(grep -E '^[[:space:]]*[-*] \*\*' "$T/.claude/projects.md" 2>/dev/null | grep -ci 'not set yet')"
emit conventions_not_set "${n:-0}"               # each is a team-part question
emit in_flight_limit "$(conv In-flight\ limit)"
emit staleness "$(conv Staleness)"
default_owner="$(conv Default\ owner)"; [[ -n "$default_owner" ]] || default_owner="$(conv Owner)"
emit default_owner "$default_owner"

# --- People -------------------------------------------------------------------------------------------
# The people directory is the one .claude/projects.md names; the profile is <full-name-slug>.md there.
people="$(conv People)"; people="${people:-memory/people/<name>.md}"
case "$people" in *'<'*) people="${people%%<*}" ;; esac
people="${people%/}"; people="${people#./}"
emit people_dir "$people"
if [[ -z "$person_slug" ]]; then prof=unknown prof_path=""; note "git config user.name is not set"
elif [[ -f "$T/$people/$person_slug.md" ]]; then prof=present prof_path="$people/$person_slug.md"
else prof=missing prof_path=""; fi
emit person_profile "$prof"
emit person_profile_path "$prof_path"
# Profiles that might be this person's under another name (first name only, say): for the agent to confirm.
first="${person_slug%%-*}"
# Markdown files in the people folder, README aside, matched without regard to case; a glob, not ls, so
# any file name reads as itself.
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
cand="" n=0
if [[ -d "$T/$people" ]]; then
    for f in "$T/$people"/*; do
        f="${f##*/}" l="$(lc "${f##*/}")"
        [[ -f "$T/$people/$f" && "$l" == *.md && "$l" != readme.md ]] || continue
        n=$((n + 1))
        [[ -n "$first" && "$l" == *"$(lc "$first")"* && "$f" != "$person_slug.md" ]] && cand+="$people/$f"$'\n'
    done
fi
emit person_profile_candidates "$(printf '%s' "$cand" | join)"
emit people_profiles "$n"

# --- The register and the projects in it --------------------------------------------------------------
# register: kit (Active, Paused and Done sections, as the installer writes it) | foreign | missing
if [[ ! -f "$T/$register_path" ]]; then reg=missing
elif [[ $(grep -cE '^## +(Active|Paused|Done)([^[:alnum:]]|$)' "$T/$register_path" 2>/dev/null) -ge 3 ]] \
     && grep -qE '^## +Active' "$T/$register_path" && grep -qE '^## +Paused' "$T/$register_path" && grep -qE '^## +Done' "$T/$register_path"; then reg=kit
else reg=foreign; fi
emit register "$reg"
emit register_path "$register_path"
emit register_rows "$( [[ -f "$T/$register_path" ]] && table_rows "$T/$register_path" || echo 0)"   # projects already listed
# Project folders under the Active pattern, each with its entry point (README.md, else CLAUDE.md).
glob="$(printf '%s' "${active%/}" | sed 's/<[^>]*>/*/g')"
nproj=0 nostate=0 nprop=0
for d in "$T"/$glob/; do
    [[ -d "$d" ]] || continue
    ep=""; [[ -f "$d/README.md" ]] && ep="$d/README.md"; [[ -z "$ep" && -f "$d/CLAUDE.md" ]] && ep="$d/CLAUDE.md"
    [[ -n "$ep" ]] || continue
    nproj=$((nproj + 1))
    grep -qiE '^#+[[:space:]]+Current state' "$ep" 2>/dev/null || nostate=$((nostate + 1))
    grep -q 'proposed by /projects:adopt' "$ep" 2>/dev/null && nprop=$((nprop + 1))
done
emit project_folders "$nproj"
emit projects_without_current_state "$nostate"     # with no adopt proposals either: offer /projects:adopt draft
emit adopt_proposals "$nprop"                       # READMEs still carrying "proposed by /projects:adopt" blocks

# --- Other canonical files ----------------------------------------------------------------------------
if [[ -f "$T/memory/glossary.md" ]]; then emit glossary present; emit glossary_terms "$(table_rows "$T/memory/glossary.md")"
else emit glossary missing; emit glossary_terms 0; fi
if [[ -f "$T/pilot/build-list.md" ]]; then emit build_list present; else emit build_list missing; fi
if [[ -f "$T/docs/verification.md" ]]; then emit verification present; else emit verification missing; fi   # what counts as checked
if [[ -f "$T/docs/catalogue.md" ]]; then emit catalogue present; else emit catalogue missing; fi
readme=""; for f in README.md README readme.md README.rst; do [[ -f "$T/$f" ]] && { readme="$f"; break; }; done
emit readme "$readme"
co=""; for f in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS .gitlab/CODEOWNERS; do [[ -f "$T/$f" ]] && { co="$f"; break; }; done
emit codeowners "$co"

# --- The decisions log --------------------------------------------------------------------------------
# decisions_log: kit (logs/decisions.md, every entry headed "## [YYYY-MM-DD] Title") | foreign (other
# headings, or a decisions log kept somewhere else) | missing. Per-project logs inside project folders
# are the kit's own shape and are not counted as elsewhere.
prune=()
for p in "$active" "$(conv Paused)" "$(conv Done)" templates .claude/plugins; do
    p="${p%%/*}"; [[ -n "$p" && "$p" != "<"* ]] && prune+=(-o -path "$T/$p")
done
other="$(find "$T" -maxdepth 3 \( -path "$T/.git" -o -name node_modules ${prune[@]+"${prune[@]}"} \) -prune -o \
            \( -type f \( -iname decisions.md -o -iname decision-log.md -o -iname decisions-log.md -o -iname decision_log.md \) -print \) -o \
            \( -type d \( -iname adr -o -iname adrs -o -iname decisions \) -print \) 2>/dev/null \
         | sed "s#^$T/##" | grep -vx 'logs/decisions.md' | sort | join)"
if [[ -f "$T/logs/decisions.md" ]]; then
    offform="$(grep -E '^## ' "$T/logs/decisions.md" 2>/dev/null | grep -cvE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] ')"
    if [[ "${offform:-0}" -gt 0 || -n "$other" ]]; then dl=foreign; else dl=kit; fi
elif [[ -n "$other" ]]; then dl=foreign
else dl=missing; fi
emit decisions_log "$dl"
emit decisions_log_other "$other"

# --- Skills and commands of the team's own ------------------------------------------------------------
# own_skills: every skill (.claude/skills/, skills/) and command (.claude/commands/) the installer did
# not generate. foreign_skills: those whose name says they do a kit command's job — closeout, the
# board, hygiene and the rest. The name match is a first pass; the agent reads own_skills for the rest.
own=""
for base in .claude/skills skills; do
    for s in "$T/$base"/*/; do
        [[ -d "$s" ]] || continue
        grep -qs 'Generated by install.sh from plugins/' "$s/SKILL.md" && continue
        own+="$base/$(basename "$s")"$'\n'
    done
done
if [[ -d "$T/.claude/commands" ]]; then
    own+="$(cd "$T" && find .claude/commands -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
        grep -qs 'Generated by install.sh from plugins/' "$f" || printf '%s\n' "$f"; done | sort)"$'\n'
fi
emit own_skills "$(printf '%s' "$own" | join)"
emit foreign_skills "$(printf '%s' "$own" | grep -iE 'close-?out|wrap-?up|board|hygiene|tidy|pick-?up|adopt|quick-?start|onboard|register-audit' | join)"

# --- Kit versions written beside the team's own files, to merge by hand ------------------------------
emit kit_incoming "$(cd "$T" && find . -maxdepth 6 \( -path ./.git -o -name node_modules \) -prune -o -type f -name '*.kit-incoming' -print 2>/dev/null | sed 's#^\./##' | sort | join)"

# --- Plugins, surfaces, measurement -------------------------------------------------------------------
settings="$T/.claude/settings.json"
plugins="" pmode=none ppath="" kit_checkout="" vcommit=""
if [[ -f "$settings" ]]; then
    emit settings present
    if command -v jq >/dev/null 2>&1; then
        # plugins_registered: the kit's plugins enabled from the agentic-workspace marketplace.
        plugins="$(jq -r '(.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key
                          | select(endswith("@agentic-workspace")) | sub("@agentic-workspace$"; "")' "$settings" 2>/dev/null | sort | join)"
        # plugins_mode: vendor (a copy in .claude/plugins) | directory (a kit checkout elsewhere, such as
        # a submodule) | github (fetched by Claude Code) | none
        src="$(jq -r '.extraKnownMarketplaces["agentic-workspace"].source // {} | "\(.source // "")\t\(.path // "")"' "$settings" 2>/dev/null)"
        case "${src%%$'\t'*}" in
            directory) ppath="${src#*$'\t'}"; ppath="${ppath#./}"; ppath="${ppath%/}"
                       if [[ "$ppath" == ".claude/plugins" ]]; then pmode=vendor; else pmode=directory; fi ;;
            github) pmode=github ;;
        esac
    else
        plugins=unknown pmode=unknown; note "jq is not on PATH; the settings file was not read"
    fi
else
    emit settings missing
fi
emit plugins_registered "$plugins"
emit plugins_mode "$pmode"
emit plugins_path "$ppath"
if [[ -f "$T/.claude/plugins/VENDORED" ]]; then
    vcommit="$(sed -n 's/^kit commit: //p' "$T/.claude/plugins/VENDORED" | head -n 1)"
    kit_checkout="$(sed -n 's/^kit checkout: \(.*\) (on the machine.*/\1/p' "$T/.claude/plugins/VENDORED" | head -n 1)"
fi
# A directory marketplace that is a kit checkout (one with pilot/measure.sh) is the kit checkout.
[[ $pmode == directory && -f "$T/$ppath/pilot/measure.sh" ]] && kit_checkout="$ppath"
emit vendored_commit "$vcommit"
emit kit_checkout "$kit_checkout"
if [[ -f "$T/.claude/closeout.md" ]]; then emit closeout_conventions present; else emit closeout_conventions missing; fi
surfaces=""
{ [[ -f "$settings" || $claude_md != missing ]]; } && surfaces="claude"
[[ -f "$T/.gemini/settings.json" ]] && surfaces="${surfaces:+$surfaces,}gemini"
emit surfaces "$surfaces"
emit gemini_commands "$( [[ -d "$T/.gemini/commands" ]] && find "$T/.gemini/commands" -type f -name '*.toml' 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
# measure_script: the metrics script to run, in the repository or in the kit checkout.
ms=""
if [[ -f "$T/pilot/measure.sh" ]]; then ms="pilot/measure.sh"
elif [[ -n "$kit_checkout" ]]; then
    case "$kit_checkout" in /*) [[ -f "$kit_checkout/pilot/measure.sh" ]] && ms="$kit_checkout/pilot/measure.sh" ;;
                            *) [[ -f "$T/$kit_checkout/pilot/measure.sh" ]] && ms="$kit_checkout/pilot/measure.sh" ;; esac
fi
emit measure_script "$ms"
if [[ -f "$T/pilot/metrics.csv" ]]; then emit metrics_csv present; else emit metrics_csv missing; fi   # joining: the baseline is taken
# Closeout drafts a prior session left for this repository, where the closeout hooks keep them.
dd="${CLOSEOUT_DRAFT_ROOT:-$HOME/.claude/closeout-drafts}/$(basename "$T")"
n=0
for f in "$dd"/*.md; do [[ -f "$f" ]] && n=$((n + 1)); done
emit closeout_drafts_pending "$n"

# --- Mode ---------------------------------------------------------------------------------------------
# signs: what says a system was here first — anything the installer did not lay down. The kit's own
# files, as installed or as filled in, are not signs, and neither is a .kit-incoming beside one.
signs=""
[[ $claude_md == own ]] && signs+="claude_md,"
[[ $agents_md == own ]] && signs+="agents_md,"
[[ $gemini_md == present ]] && signs+="gemini_md,"
[[ $reg == foreign ]] && signs+="register,"
[[ $dl == foreign ]] && signs+="decisions_log,"
[[ $pc == foreign ]] && signs+="projects_conventions,"
printf '%s' "$out" | grep -q '^foreign_skills=.' && signs+="foreign_skills,"
signs="${signs%,}"
emit signs "$signs"
# mode, the first that fits, in the quick-start's order:
#   joining         the kit's Team Manifest is the always-loaded file, no stand-ins are left, and this
#                   person has no profile: the personal part only
#   existing-system any sign above: the kit adopts rather than installs
#   fresh           stand-ins still in the always-loaded file (or none to judge yet): team part, then personal
#   nothing-left    filled in, and they have a profile: the last section on its own
if [[ $agents_md == kit && $always_loaded == AGENTS.md && "$standins" == 0 && $prof != present ]]; then mode=joining
elif [[ -n "$signs" ]]; then mode=existing-system
elif [[ "$standins" != 0 || $always_loaded == none ]]; then mode=fresh
else mode=nothing-left; fi
emit mode "$mode"

if [[ $JSON -eq 1 ]]; then
    printf '%s' "$out" | jq -Rn '[inputs | select(length > 0) | capture("^(?<key>[^=]+)=(?<value>.*)$")] | from_entries' 2>/dev/null \
        || { printf 'error=--json needs jq\n'; exit 2; }
else
    printf '%s' "$out"
fi
