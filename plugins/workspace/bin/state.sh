#!/usr/bin/env bash
# State check: a read-only report of where a repository stands against the kit, one key=value per line.
#
#   state.sh [DIR]            report on DIR (default: the repository this is run in)
#   state.sh --target DIR     the same
#   state.sh --quick          only the keys the session-start summary reads, cheaply (see below)
#   state.sh --json           the same facts as one JSON object (needs jq)
#   state.sh --verbose        say on stderr what could not be read; silent otherwise
#   state.sh --explain [KEY]  what each key means (or one key), read from this file's own comments
#
# It is written to be the one answer to "what state is this repository in" for the quick-start, the
# setup wizard, the session-start summary and the board to branch on, rather than working it out
# again; the tests assert against it. It writes nothing, makes no network call, and reads git only
# with --no-optional-locks, so running it from a shell that shares the repository with a live session
# (a desktop assistant's device shell, say) leaves no index.lock behind. It runs under bash 3.2 and
# needs only git; jq is used when present, for the settings files and --json. Its awk is POSIX awk
# without character classes, so an older mawk reads it the same.
#
# It is self-contained, since a plugin cannot rely on files outside its own directory: the few
# functions it shares with the kit's lib/common.sh (aw_norm_url, aw_private_remotes, aw_is_opaque,
# aw_word_list) are copies, and the tests check that the copies agree. Project READMEs are read with
# the projects plugin's lib/readme.awk, taken from the workspace's own kit checkout (or the sibling
# plugin); where neither is there, the keys that need it read unknown.
#
# --quick emits only: state_version target in_git hooks kit_hooks kit_path kit_submodule kit_commit
# kit_version kit_branch kit_behind kit_import origin origin_visibility origin_confirmed submodules
# submodule_recurse submodule.* submodules_attention orphan_gitlinks sensitive_projects
# sensitive_tracked versioned_mismatch external_paths external_paths_missing resource.* skills_bridge
# plugins_loaded plugins_not_loaded quick=1.
# Its git calls do not grow with the number of project folders, and it never lists a resource folder
# (ls on a cloud-drive folder can stall a session hook): a resource is tested with -e and -d only.
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
#   settings plugins_registered plugins_mode plugins_path plugins_loaded plugins_not_loaded
#   vendored_commit kit_checkout
#   closeout_conventions surfaces gemini_commands measure_script metrics_csv
#   closeout_drafts_pending
#   hooks hooks_chain kit_path kit_submodule kit_commit kit_version kit_branch kit_behind kit_hooks
#   kit_import kit_untracked_refused origin origin_visibility origin_confirmed workspace_conventions
#   word_list ledger submodules submodule.<path> submodule_config submodule_recurse
#   submodules_attention orphan_gitlinks sensitive_projects sensitive_tracked versioned_mismatch
#   external_paths resource.<slug>/<name> external_paths_missing resources_file skills_bridge
#   skills_bridge_count skills_bridge_stale legacy
#   signs mode quick
# Lists are comma-separated; an empty value means none. A key that could not be judged reads unknown.

VERBOSE=0 JSON=0 QUICK=0 EXPLAIN=0 explain_key="" dir=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) dir="${2:-}"; shift 2 ;;
        --json) JSON=1; shift ;;
        --quick) QUICK=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        --explain)
            EXPLAIN=1
            if [[ $# -gt 1 && "$2" != -* ]]; then explain_key="$2"; shift; fi
            shift ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) printf 'error=unknown option %s\n' "$1"; exit 2 ;;
        *) dir="$1"; shift ;;
    esac
done

# --explain: each key's meaning, from the "# <key>: <meaning>" comment above the line that emits it,
# with the comment lines that follow it. Only keys named in the header's key list count, so a helper
# function's comment is never taken for a key. A per-item key (submodule.kit) is explained by its
# pattern (submodule.<path>). Exit 1 when the key is not one this script emits.
if [[ $EXPLAIN -eq 1 ]]; then
    awk -v want="$explain_key" '
        /^# Keys/ { inkeys = 1; next }
        inkeys && /^# Lists are/ { inkeys = 0 }
        inkeys { l = $0; sub(/^#[ \t]*/, "", l); n = split(l, a, /[ \t]+/)
                 for (i = 1; i <= n; i++) if (a[i] != "" && !(a[i] in keys)) { keys[a[i]] = 1; order[++nk] = a[i] }
                 next }
        /^[ \t]*#/ {
            t = $0; sub(/^[ \t]*#[ \t]?/, "", t)
            if (match(t, /^[a-z][a-z0-9_.<>\/]*: /)) {
                k = substr(t, 1, RLENGTH - 2)
                if ((k in keys) && !(k in text)) { cur = k; text[k] = substr(t, RLENGTH + 1); next }
            }
            if (cur != "" && t != "") { text[cur] = text[cur] " " t; next }
            cur = ""; next
        }
        { cur = "" }
        END {
            for (k in text) { gsub(/[ \t]+/, " ", text[k]); sub(/ $/, "", text[k]) }
            if (want != "") {
                if (!(want in keys) && want ~ /^submodule\./) want = "submodule.<path>"
                if (!(want in keys) && want ~ /^resource\./) want = "resource.<slug>/<name>"
                if (!(want in text)) exit 1
                print want ": " text[want]; exit 0
            }
            for (i = 1; i <= nk; i++) if (order[i] in text) print order[i] ": " text[order[i]]
        }' "$0"
    exit $?
fi

note() { [[ $VERBOSE -eq 1 ]] && printf 'state.sh: %s\n' "$*" >&2; return 0; }

dir="${dir:-$PWD}"
if [[ ! -d "$dir" ]]; then printf 'error=not a directory: %s\n' "$dir"; exit 2; fi
# Claude Code's Bash sandbox denies /etc, and git stops outright on a system config it cannot read, so
# every call here would fail and the report would read in_git=no. Nothing this report needs lives in the
# system config, so it is not read; gx inherits this too.
export GIT_CONFIG_NOSYSTEM=1
# The one door to git for this repository. Optional locks off, so even `status` never refreshes and
# rewrites the index.
g() { git --no-optional-locks -C "$T" "$@" 2>/dev/null; }
# gx <dir> <args...>: git in another repository (the kit, a submodule), with any git environment the
# caller inherited cleared, so it reads that repository and no other.
gx() {
    local d="$1"; shift
    ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX \
          GIT_ALTERNATE_OBJECT_DIRECTORIES
      git --no-optional-locks -C "$d" "$@" 2>/dev/null )
}
# A folder inside a repository is reported on as the repository it belongs to.
T="$(git --no-optional-locks -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$T" ]] || T="$(cd "$dir" && pwd -P)"

out=""
# emit <key> <value>. With --quick only the session-start keys are kept.
emit() {
    if [[ $QUICK -eq 1 ]]; then
        case "$1" in
            state_version|target|in_git|hooks|kit_hooks|kit_path|kit_submodule|kit_commit|kit_version) ;;
            kit_branch|kit_behind|kit_import|origin|origin_visibility|origin_confirmed|submodules) ;;
            submodule_recurse|submodule.*|submodules_attention|orphan_gitlinks|sensitive_projects) ;;
            sensitive_tracked|versioned_mismatch|external_paths|external_paths_missing|resource.*|quick) ;;
            skills_bridge|plugins_loaded|plugins_not_loaded) ;;
            *) return 0 ;;
        esac
    fi
    out+="$1=$(printf '%s' "$2" | tr '\n' ' ')"$'\n'
}
# join: stdin lines as one comma-separated list.
join() { sed '/^$/d' | tr -d ',' | paste -sd, - ; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
# count: a trimmed line count of stdin (BSD wc pads its count).
count() { awk 'END { print NR }'; }
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
# of a numbered file (the whole file when it has no numbered sections, as a team's own CLAUDE.md
# may not); "surfaces" is the §4 surface table. Fenced code blocks are skipped. kit/CLAUDE.kit.md
# has unnumbered headings, so this reads only the workspace's own file.
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
# first_line <file>: the first non-empty line, trimmed, with HTML comments removed.
first_line() {
    awk '{ line = $0
           while (1) { if (inc) { i = index(line, "-->"); if (!i) { line = ""; break } line = substr(line, i + 3); inc = 0 }
                       i = index(line, "<!--"); if (!i) break
                       rest = substr(line, i + 4); j = index(rest, "-->")
                       if (j) line = substr(line, 1, i - 1) substr(rest, j + 3); else { line = substr(line, 1, i - 1); inc = 1; break } }
           gsub(/^[ \t\r]+|[ \t\r]+$/, "", line); if (line != "") { print line; exit } }' "$1" 2>/dev/null
}
# in_list <item> <comma list>: exit 0 when the item is one of the list's.
in_list() { case ",$2," in *",$1,"*) return 0 ;; esac; return 1; }

# ---- Copies of lib/common.sh (kept identical; tests/sections/16-state.sh compares them) ------------

# aw_norm_url URL
# One spelling per remote, so a URL written by hand, one git reports, and one GitHub knows compare
# equal: github.com/owner/repo. The scheme, any user or token before an @, a port, a trailing .git and
# a trailing slash are dropped, and the scp form's first colon becomes a slash. A local path (or a
# file:// URL) becomes local:<absolute path>, resolved through symlinks when it exists; a local path
# keeps its case, since some file systems are case-sensitive.
aw_norm_url() {
    local u="$1" hostpart rest path lhs first re
    # Trim surrounding space.
    u="${u#"${u%%[![:space:]]*}"}"
    u="${u%"${u##*[![:space:]]}"}"
    [[ -n "$u" ]] || return 0
    case "$u" in
        local:/*)
            # Already normalised.
            printf '%s\n' "$u"
            return 0 ;;
        file://*)
            path="${u#file://}"
            # file://host/path is rare; file:///path is the usual form.
            [[ "$path" == /* ]] || path="/${path#*/}"
            _aw_norm_local "$path"
            return 0 ;;
        *://*)
            u="${u#*://}" ;;
        *)
            lhs="${u%%:*}" first="${u%%/*}"
            re='^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)*$'
            if [[ "$u" == *:* && "$lhs" != */* && -n "$lhs" ]]; then
                # The scp form, [user@]host:path.
                u="${lhs}/${u#*:}"
            elif [[ "$first" =~ $re && "$u" == */*/* && ! -e "$u" && ! -e "$first" ]]; then
                # host/owner/repo with no scheme: the normalised form itself, as .claude/workspace.md
                # records a remote (a host alias included). The first segment reads as a host name and
                # nothing by that name exists here, so a relative path is not mistaken for one.
                :
            else
                _aw_norm_local "$u"
                return 0
            fi ;;
    esac
    hostpart="${u%%/*}"
    if [[ "$u" == */* ]]; then rest="/${u#*/}"; else rest=""; fi
    # user[:token]@host
    hostpart="${hostpart##*@}"
    # host:port, or a scheme URL written with the scp colon (ssh://host:owner/repo).
    if [[ "$hostpart" == *:* ]]; then
        case "${hostpart#*:}" in
            ''|*[!0-9]*) rest="/${hostpart#*:}$rest"; hostpart="${hostpart%%:*}" ;;
            *) hostpart="${hostpart%%:*}" ;;
        esac
    fi
    u="$hostpart$rest"
    while :; do
        case "$u" in
            */) u="${u%/}" ;;
            *.git) u="${u%.git}" ;;
            *) break ;;
        esac
    done
    printf '%s\n' "$u" | tr '[:upper:]' '[:lower:]'
}

_aw_norm_local() {
    local p="$1" d b
    case "$p" in
        "~") p="$HOME" ;;
        \~/*) p="$HOME/${p:2}" ;;
        /*) ;;
        *) p="$PWD/$p" ;;
    esac
    while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
    if [[ -d "$p" ]]; then
        p="$(cd "$p" && pwd -P)"
    elif [[ -e "$p" ]]; then
        d="$(dirname "$p")" b="$(basename "$p")"
        p="$(cd "$d" && pwd -P)/$b"
    fi
    printf 'local:%s\n' "$p"
}

# _aw_remote_lines WS LABEL
# The bullets of .claude/workspace.md that carry the bold label, skipping fenced blocks and HTML
# comments (the template's examples sit in comments).
_aw_remote_lines() {
    local file="$1/.claude/workspace.md" label="$2"
    [[ -f "$file" ]] || return 0
    awk -v lab="**$label:**" '
        /^[ \t]*```/ { fence = !fence; next }
        fence { next }
        {
            line = $0
            if (cmt) { if (index(line, "-->")) { cmt = 0; line = substr(line, index(line, "-->") + 3) } else next }
            while (index(line, "<!--")) {
                pre = substr(line, 1, index(line, "<!--") - 1); post = substr(line, index(line, "<!--") + 4)
                if (index(post, "-->")) line = pre substr(post, index(post, "-->") + 3)
                else { line = pre; cmt = 1 }
            }
            t = line; sub(/^[ \t]*/, "", t)
            if ((substr(t, 1, 2) == "- " || substr(t, 1, 2) == "* ") && index(substr(t, 3), lab) == 1) print line
        }' "$file" 2>/dev/null
}

# aw_private_remotes WS
# url<TAB>via<TAB>date per Private remote. A line with no "confirmed <date> via gh|person" part reads
# as via person, with no date.
aw_private_remotes() {
    local line url via date re
    # The backticks are literal: the value sits in the first backticked span of the bullet.
    # shellcheck disable=SC2016
    re='^[ '$'\t'']*[-*] \*\*Private remote:\*\*[^`]*`([^`]+)`(.*confirmed ([0-9]{4}-[0-9]{2}-[0-9]{2}) via (gh|person))?'
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$line" =~ $re ]]; then
            url="$(aw_norm_url "${BASH_REMATCH[1]}")"
            date="${BASH_REMATCH[3]}"
            via="${BASH_REMATCH[4]:-person}"
            [[ -n "$url" ]] && printf '%s\t%s\t%s\n' "$url" "$via" "$date"
        fi
    done <<EOF
$(_aw_remote_lines "$1" "Private remote")
EOF
    return 0
}

# aw_is_opaque WS REL
# Opaque files are ones a policy keeps tools from reading, or that belong to another tool. The list is
# AW_OPAQUE_PATHS (space-separated, workspace-relative), defaulting to AGENTS.md and
# copilot-instructions.md; set and empty, nothing is opaque. A listed file is opaque when it exists and
# the ledger does not record the engine creating or updating it. Existence is judged without reading
# the file: -e, else the error ls gives (a denied stat is still a file there), else git's index.
aw_is_opaque() {
    local ws="$1" rel="$2" list p there=no lserr lock
    if [[ -n "${AW_OPAQUE_PATHS+set}" ]]; then list="$AW_OPAQUE_PATHS"; else list="AGENTS.md copilot-instructions.md"; fi
    for p in $list; do
        [[ "$p" == "$rel" ]] || continue
        if [[ -e "$ws/$rel" ]]; then there=yes
        else
            lserr="$(LC_ALL=C ls -d "$ws/$rel" 2>&1 >/dev/null)"
            if [[ -n "$lserr" && "$lserr" != *"No such file"* ]]; then there=yes
            elif git --no-optional-locks -C "$ws" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then there=yes
            fi
        fi
        [[ $there == yes ]] || return 1
        lock="$ws/.claude/kit-templates.lock"
        if [[ -f "$lock" ]] && awk -F '\t' -v d="$rel" '$1 == d && ($5 == "created" || $5 == "accepted") { f = 1 } END { exit !f }' "$lock" 2>/dev/null; then
            return 1
        fi
        return 0
    done
    return 1
}

# aw_word_list WS
# The private word list, resolved in one order everywhere: AW_BANNED_WORDS_FILE; the workspace's
# "Private word list" setting in .claude/workspace.md (relative to the workspace root); then
# ~/.config/agentic-workspace-kit/banned-words.txt. The first that is named decides. A named list that
# cannot be read, or that sits inside the kit checkout (which is public), exits 2 with the reason on
# stderr. With none named, it prints nothing and exits 0. In this copy the kit checkout is the
# workspace's (AW_KIT_ROOT is set below to WS/kit_path).
aw_word_list() {
    local ws="${1:-}" p="" src="" kit_real d
    if [[ -n "${AW_BANNED_WORDS_FILE:-}" ]]; then
        p="$AW_BANNED_WORDS_FILE" src="AW_BANNED_WORDS_FILE"
    elif [[ -n "$ws" && -f "$ws/.claude/workspace.md" ]]; then
        p="$(awk '
            /^[ \t]*```/ { fence = !fence; next }
            fence { next }
            /^[ \t]*[-*][ \t]+\*\*Private word list:\*\*/ {
                if (match($0, /`[^`]+`/)) print substr($0, RSTART + 1, RLENGTH - 2)
                exit }' "$ws/.claude/workspace.md" 2>/dev/null)"
        if [[ -n "$p" ]]; then
            src=".claude/workspace.md"
            case "$p" in \~/*) p="$HOME/${p:2}" ;; /*) ;; *) p="$ws/$p" ;; esac
        fi
    fi
    if [[ -z "$p" && -e "$HOME/.config/agentic-workspace-kit/banned-words.txt" ]]; then
        p="$HOME/.config/agentic-workspace-kit/banned-words.txt" src="the default location"
    fi
    [[ -n "$p" ]] || return 0
    if [[ ! -f "$p" || ! -r "$p" ]]; then
        printf 'aw: the private word list named by %s cannot be read\n' "$src" >&2
        return 2
    fi
    d="$(cd "$(dirname "$p")" && pwd -P)"
    for kit_real in "$AW_KIT_ROOT" ${ws:+"$ws/kit"}; do
        [[ -d "$kit_real" ]] || continue
        kit_real="$(cd "$kit_real" && pwd -P)"
        case "$d/" in
            "$kit_real"/*)
                printf 'aw: the private word list named by %s is inside the kit checkout, which is public\n' "$src" >&2
                return 2 ;;
        esac
    done
    printf '%s/%s\n' "$d" "$(basename "$p")"
}

# ---- Git hooks: the stub check (the rule the stubs themselves follow) -------------------------------

AW_STUB_MARKER="# agentic-workspace-kit hook stub 1"
AW_HOOK_NAMES="pre-commit pre-merge-commit commit-msg pre-push"
# hook_target <repo top> <name>: exit 0 when the stub in that repository would find an executable kit
# hook of that name — the repository is the kit itself, or an ancestor (the top included) holds kit/.
hook_target() {
    local top="$1" n="$2" d
    if grep -q '"agentic-workspace"' "$top/.claude-plugin/marketplace.json" 2>/dev/null && [[ -x "$top/githooks/$n" ]]; then
        return 0
    fi
    d="$top"
    while :; do
        if grep -q '"agentic-workspace"' "$d/kit/.claude-plugin/marketplace.json" 2>/dev/null && [[ -x "$d/kit/githooks/$n" ]]; then
            return 0
        fi
        [[ "$d" == / || -z "$d" ]] && return 1
        d="$(dirname "$d")"
    done
}
# hooks_of <repository top>: active | missing | other | none. Active is the local core.hooksPath set to
# this repository's own <git dir>/aw-hooks, each of the four stubs there executable and carrying the
# marker on its second line, and each stub's kit hook found and executable.
hooks_of() {
    local r="$1" gd lv ev n s
    [[ -e "$r/.git" ]] || { echo none; return 0; }
    gd="$(gx "$r" rev-parse --absolute-git-dir)"
    [[ -n "$gd" && -d "$gd" ]] || { echo none; return 0; }
    gd="$(cd "$gd" && pwd -P)"
    lv="$(gx "$r" config --local core.hooksPath)"
    if [[ -z "$lv" ]]; then
        ev="$(gx "$r" config core.hooksPath)"
        if [[ -n "$ev" ]]; then echo other; else echo missing; fi
        return 0
    fi
    case "$lv" in \~/*) lv="$HOME/${lv:2}" ;; /*) ;; *) lv="$r/$lv" ;; esac
    [[ -d "$lv" ]] && lv="$(cd "$lv" && pwd -P)"
    [[ "$lv" == "$gd/aw-hooks" ]] || { echo other; return 0; }
    r="$(cd "$r" && pwd -P)"
    for n in $AW_HOOK_NAMES; do
        s="$gd/aw-hooks/$n"
        if [[ ! -f "$s" || ! -x "$s" || "$(sed -n 2p "$s" 2>/dev/null)" != "$AW_STUB_MARKER" ]] || ! hook_target "$r" "$n"; then
            echo missing; return 0
        fi
    done
    echo active
}

# state_version: 2 in kit 3.0; the key set a reader can expect.
emit state_version 2
# target: the repository reported on (the top of the one DIR is in).
emit target "$T"

# ---- Git: history, working tree, who is here ---------------------------------------------------------
# in_git: yes | no | refused (a repository git will not read here, such as one owned by another user on
# a mounted folder: see git's safe.directory). Refused is not no: the history keys below then read 0.
if g rev-parse --git-dir >/dev/null; then in_git=yes
elif git --no-optional-locks -C "$T" rev-parse --git-dir 2>&1 | grep -qi 'dubious ownership\|safe.directory'; then
    in_git=refused; note "git refuses to read $T here (safe.directory)"
else in_git=no; note "$T is not a git repository"; fi
emit in_git "$in_git"
has_head=no
[[ $in_git == yes ]] && g rev-parse -q --verify HEAD >/dev/null && has_head=yes
if [[ $QUICK -eq 0 ]]; then
    commits=0
    [[ $has_head == yes ]] && commits="$(g rev-list --count HEAD || echo 0)"
    # commits: commits on HEAD; 0 means the metrics baseline waits for a first commit.
    emit commits "${commits:-0}"
    # uncommitted: lines of git status --porcelain (changed, staged and untracked paths).
    emit uncommitted "$( [[ $in_git == yes ]] && g status --porcelain | count || echo 0)"
    if [[ "${commits:-0}" -gt 0 ]]; then
        shortlog="$(g shortlog -sn HEAD)"
        # authors: distinct commit authors; one author means Default owner is worth offering.
        emit authors "$(printf '%s\n' "$shortlog" | sed '/^$/d' | count)"
        # author_names: their names, most commits first.
        emit author_names "$(printf '%s\n' "$shortlog" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' | join)"
    else
        emit authors 0; emit author_names ""
    fi
fi
# The person in front of the agent, from git config: a suggestion to confirm, never an assumption.
person="$(git --no-optional-locks -C "$T" config user.name 2>/dev/null)"
person_slug="$(lower "$person" | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')"
# person: git config user.name here.
emit person "$person"
# person_slug: that name as a file name, the profile's name in the people directory.
emit person_slug "$person_slug"

# ---- Settings: the plugin marketplace, and so where the kit is ---------------------------------------
settings="$T/.claude/settings.json"
plugins="" pmode=none ppath=""
have_jq=no; command -v jq >/dev/null 2>&1 && have_jq=yes
if [[ -f "$settings" && $have_jq == yes ]]; then
    plugins="$(jq -r '(.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key
                      | select(endswith("@agentic-workspace")) | sub("@agentic-workspace$"; "")' "$settings" 2>/dev/null | sort | join)"
    src="$(jq -r '.extraKnownMarketplaces["agentic-workspace"].source // {} | "\(.source // "")\t\(.path // "")"' "$settings" 2>/dev/null)"
    case "${src%%$'\t'*}" in
        directory) ppath="${src#*$'\t'}"; ppath="${ppath#./}"; ppath="${ppath%/}"
                   if [[ "$ppath" == ".claude/plugins" ]]; then pmode=vendor
                   elif [[ "$ppath" == "kit" ]]; then pmode=kit
                   else pmode=directory; fi ;;
        github) pmode=github ;;
    esac
elif [[ -f "$settings" ]]; then
    plugins=unknown pmode=unknown; note "jq is not on PATH; the settings file was not read"
fi

# kit_path: where the kit is: the directory-marketplace path, when its .claude-plugin/marketplace.json
# names agentic-workspace (a vendored .claude/plugins copy is not the kit); else kit, when
# kit/CLAUDE.kit.md is there or .gitmodules registers a submodule at kit (not initialised yet); else none.
kit_path=none
if [[ -n "$ppath" && $pmode != vendor && "$ppath" != /* ]] \
   && grep -q '"agentic-workspace"' "$T/$ppath/.claude-plugin/marketplace.json" 2>/dev/null; then
    kit_path="$ppath"
elif [[ -f "$T/kit/CLAUDE.kit.md" ]]; then
    kit_path=kit
fi
# The submodules, from .gitmodules, read once: name<TAB>path<TAB>branch<TAB>update per submodule.
subs=""
if [[ -f "$T/.gitmodules" ]]; then
    subs="$(git --no-optional-locks config -f "$T/.gitmodules" --get-regexp '^submodule\..*\.(path|branch|update)$' 2>/dev/null \
        | awk '{ k = $1; v = substr($0, length($1) + 2); sub(/^submodule\./, "", k)
                 f = k; sub(/.*\./, "", f); n = substr(k, 1, length(k) - length(f) - 1)
                 if (!(n in seen)) { seen[n] = 1; order[++c] = n }
                 val[n, f] = v }
               END { for (i = 1; i <= c; i++) { n = order[i]; if (val[n, "path"] != "") print n "\t" val[n, "path"] "\t" val[n, "branch"] "\t" val[n, "update"] } }')"
fi
kitname=""
while IFS=$'\t' read -r sn sp _sb _su; do
    [[ -n "$sn" ]] || continue
    [[ $kit_path == none && "$sp" == kit ]] && kit_path=kit
    [[ "$sp" == "$kit_path" ]] && kitname="$sn"
done <<EOF
$subs
EOF
emit kit_path "$kit_path"
KD=""; [[ $kit_path != none ]] && KD="$T/$kit_path"
AW_KIT_ROOT="$KD"
kit_repo=no; [[ -n "$KD" && -e "$KD/.git" ]] && kit_repo=yes

# ---- The index, read once: gitlinks, and the entries under each project folder -----------------------
# gitlinks: mode 160000 entries as path<TAB>sha. Every walk below reads this one listing, so the cost
# does not grow with the number of project folders.
gitlinks=""
[[ $in_git == yes ]] && gitlinks="$(g ls-files -s -z | tr '\0' '\n' | awk '$1 == "160000" { p = $0; sub(/^[^\t]*\t/, "", p); print p "\t" $2 }')"
# kit_submodule: yes (the kit is a gitlink in the index) | no (kit files tracked in place, or not
# tracked) | none (no kit found).
if [[ $kit_path == none ]]; then kit_submodule=none
elif printf '%s\n' "$gitlinks" | awk -F '\t' -v p="$kit_path" '$1 == p { f = 1 } END { exit !f }'; then kit_submodule=yes
else kit_submodule=no; fi
emit kit_submodule "$kit_submodule"

kit_commit="" kit_version="" kit_branch="" kit_behind=none
if [[ $kit_repo == yes ]]; then
    kit_commit="$(gx "$KD" rev-parse --short HEAD)"
    kit_branch="$(gx "$KD" symbolic-ref -q --short HEAD)"; kit_branch="${kit_branch:-detached}"
fi
[[ -n "$KD" ]] && kit_version="$(awk '/^## v/ { s = $2; sub(/^v/, "", s); print s; exit }' "$KD/CHANGELOG.md" 2>/dev/null)"
# behind_of <repo> <branch or detached> <.gitmodules branch>: commits the checkout is behind its
# remote, from refs already fetched: @{upstream} when on a branch that has one, else origin/<branch>
# (the .gitmodules branch, default main). unknown when there is no such ref.
behind_of() {
    local r="$1" b="$2" mb="${3:-main}" n=""
    [[ "$b" != detached ]] && n="$(gx "$r" rev-list --count 'HEAD..@{upstream}')"
    [[ -n "$n" ]] || n="$(gx "$r" rev-list --count "HEAD..origin/$mb")"
    printf '%s' "${n:-unknown}"
}
kit_mb="$(printf '%s\n' "$subs" | awk -F '\t' -v n="$kitname" 'n != "" && $1 == n { print $3; exit }')"
[[ $kit_repo == yes ]] && kit_behind="$(behind_of "$KD" "$kit_branch" "$kit_mb")"
# kit_commit: the kit checkout's HEAD, short.
emit kit_commit "$kit_commit"
# kit_version: the kit's version, from the first "## v" heading of its CHANGELOG.md.
emit kit_version "$kit_version"
# kit_branch: main (developer mode, or a fresh submodule add) | detached (the usual submodule
# checkout) | another branch name | empty when there is no kit checkout.
emit kit_branch "$kit_branch"
# kit_behind: commits the kit is behind its remote, from refs already fetched (no network) | unknown
# (no remote-tracking ref to compare with) | none (no kit checkout).
emit kit_behind "$kit_behind"

# kit_import: ok (the first non-empty line of CLAUDE.md is @kit/CLAUDE.kit.md, and that file is there) |
# broken (the line is there, the file is not: the kit is not initialised) | missing (no such line).
cl1=""; [[ -f "$T/CLAUDE.md" ]] && cl1="$(first_line "$T/CLAUDE.md")"
if [[ "$cl1" == "@kit/CLAUDE.kit.md" ]]; then
    if [[ -f "$T/kit/CLAUDE.kit.md" ]]; then kit_import=ok; else kit_import=broken; fi
else kit_import=missing; fi
emit kit_import "$kit_import"

# ---- Hooks ------------------------------------------------------------------------------------------
hooks=none; [[ $in_git == yes ]] && hooks="$(hooks_of "$T")"
# hooks: active (core.hooksPath is this repository's aw-hooks stub directory, and each stub reaches an
# executable kit hook) | missing (unset, or a stub or its kit hook absent) | other (hooks set to
# somewhere else, a global hooks path included) | none (not a repository).
emit hooks "$hooks"
kit_hooks=none; [[ $kit_repo == yes ]] && kit_hooks="$(hooks_of "$KD")"
# kit_hooks: the same, for the kit checkout's own repository.
emit kit_hooks "$kit_hooks"
if [[ $QUICK -eq 0 ]]; then
    # hooks_chain: aw.chainHooksPath, the hooks path that was in effect before the kit's, which the kit's
    # hooks run after their own checks; empty when there was none.
    emit hooks_chain "$( [[ $in_git == yes ]] && g config --local aw.chainHooksPath)"
fi

# ---- The origin and the list of confirmed private remotes --------------------------------------------
origin="" origin_visibility=unknown origin_confirmed=""
if [[ $in_git == yes ]]; then
    origin="$(aw_norm_url "$(g remote get-url origin)")"
    if [[ -z "$origin" ]]; then origin_visibility=none
    else
        entry="$(aw_private_remotes "$T" | awk -F '\t' -v u="$origin" '$1 == u { e = $2 ":" $3 } END { if (e != "") print e }')"
        if [[ -n "$entry" ]]; then origin_visibility=private origin_confirmed="$entry"
        else origin_visibility=unconfirmed; fi
    fi
fi
# origin: the origin remote's URL, normalised (host/owner/repo, or local:<path>); no credentials.
emit origin "$origin"
# origin_visibility: private (listed as a Private remote in .claude/workspace.md) | unconfirmed (an
# origin not listed) | none (no origin) | unknown (not a repository). A record, not a live check.
emit origin_visibility "$origin_visibility"
# origin_confirmed: how and when the listed entry was confirmed: gh:<date> | person:<date> | person:
# (a line with no date) | empty.
emit origin_confirmed "$origin_confirmed"

# ---- Submodules --------------------------------------------------------------------------------------
# Project patterns from .claude/projects.md (Active, Paused, Done), as projects_config reads them:
# <placeholder> segments stand for one folder name, and repeated patterns are read once.
active="$(conv Active)" register_path="$(conv Register)"
active="${active:-projects/<slug>/}" register_path="${register_path:-projects/INDEX.md}"
register_path="${register_path#./}"
paused_conv="$(conv Paused)" done_conv="$(conv Done)"
pattern_of() {
    local p="${1%/}"; p="${p#./}"
    case "$p" in *"<"*">"*) ;; *) p="$p/<slug>" ;; esac
    printf '%s' "$p"
}
patterns=""
for pp in "$active" "$paused_conv" "$done_conv"; do
    [[ -n "$pp" ]] || continue
    pp="$(pattern_of "$pp")"
    case $'\n'"$patterns"$'\n' in *$'\n'"$pp"$'\n'*) continue ;; esac
    patterns="${patterns:+$patterns$'\n'}$pp"
done
# match_pattern <pattern> <path>: exit 0 when the path is a project folder of that pattern exactly. A
# placeholder segment never matches a name starting with . or _ (reserved folders such as _done).
match_pattern() {
    local IFS=/ i=0 p r
    # shellcheck disable=SC2206
    local -a pp=($1) rr=($2)
    [[ ${#pp[@]} -gt 0 && ${#rr[@]} -eq ${#pp[@]} ]] || return 1
    while [[ $i -lt ${#pp[@]} ]]; do
        p="${pp[$i]}" r="${rr[$i]}"
        case "$p" in
            "<"*">") [[ -n "$r" && "$r" != .* && "$r" != _* ]] || return 1 ;;
            *) [[ "$p" == "$r" ]] || return 1 ;;
        esac
        i=$((i + 1))
    done
    return 0
}
is_project_path() {
    local pat
    while IFS= read -r pat; do
        [[ -n "$pat" ]] && match_pattern "$pat" "$1" && return 0
    done <<EOF
$patterns
EOF
    return 1
}

# The workspace's git configuration, read once (effective values: local over global).
cfg=""; [[ $in_git == yes ]] && cfg="$(g config -l)"
cfg_get() { printf '%s\n' "$cfg" | awk -v k="$1=" 'index($0, k) == 1 { v = substr($0, length(k) + 1) } END { print v }'; }
# HEAD's gitlinks, for the pointer comparison: one ls-tree over the submodule paths.
sub_paths="$(printf '%s\n' "$subs" | awk -F '\t' 'NF { print $2 }')"
head_links=""
if [[ $has_head == yes && -n "$sub_paths" ]]; then
    sp_args=()
    while IFS= read -r sp; do [[ -n "$sp" ]] && sp_args+=("$sp"); done <<EOF
$sub_paths
EOF
    head_links="$(g --literal-pathspecs ls-tree -r HEAD -- ${sp_args[@]+"${sp_args[@]}"} | awk '$1 == "160000" { p = $0; sub(/^[^\t]*\t/, "", p); print p "\t" $3 }')"
fi
link_of() { printf '%s\n' "$2" | awk -F '\t' -v p="$1" '$1 == p { print $2; exit }'; }

outside="" attention="" sub_list=""
while IFS=$'\t' read -r sn sp sb su; do
    [[ -n "$sn" ]] || continue
    sub_list="${sub_list:+$sub_list$'\n'}$sp"
    if [[ "$sp" == "$kit_path" ]]; then role=kit
    elif is_project_path "$sp"; then role=project
    else role=outside; outside+="$sp,"; fi
    upd="$(cfg_get "submodule.$sn.update")"; upd="${upd:-$su}"
    if [[ -e "$T/$sp/.git" ]]; then
        dirty="$(gx "$T/$sp" status --porcelain --ignore-submodules=all | count)"
        unpushed="$(gx "$T/$sp" rev-list --count HEAD --not --remotes)"; unpushed="${unpushed:-unknown}"
        if [[ -n "$(gx "$T/$sp" remote)" ]]; then remote=yes; else remote=none; fi
        sub_head="$(gx "$T/$sp" rev-parse HEAD)"
        branch="$(gx "$T/$sp" symbolic-ref -q --short HEAD)"; branch="${branch:-detached}"
        behind="$(behind_of "$T/$sp" "$branch" "$sb")"
        idx="$(link_of "$sp" "$gitlinks")" hd="$(link_of "$sp" "$head_links")"
        if [[ $has_head != yes ]]; then pointer=new
        elif [[ "$sub_head" != "$idx" ]]; then pointer=uncommitted
        elif [[ "$idx" != "$hd" ]]; then pointer=staged
        else pointer=ok; fi
        sh=n/a; [[ $role == project ]] && sh="$(hooks_of "$T/$sp")"
    else
        dirty=0 unpushed=unknown remote=none pointer=uninitialized behind=unknown branch=none
        sh=n/a; [[ $role == project ]] && sh=missing
    fi
    # submodule.<path>: role=kit|project|outside dirty=<changed files> unpushed=<commits not on any
    # remote>|unknown remote=yes|none pointer=ok|staged|uncommitted|new|uninitialized (staged: the index
    # holds a pointer HEAD does not; uncommitted: the submodule's HEAD is not the pointer in the index;
    # new: the workspace has no commit yet) behind=<commits behind its remote>|unknown
    # branch=<name>|detached|none (none: not initialised) hooks=active|missing|n/a (reported for
    # project submodules only).
    emit "submodule.$sp" "role=$role dirty=$dirty unpushed=$unpushed remote=$remote pointer=$pointer behind=$behind branch=$branch hooks=$sh"
    if [[ $role != outside ]]; then
        if [[ "$dirty" != 0 || ( "$unpushed" != unknown && "$unpushed" != 0 ) || $pointer == staged || $pointer == uncommitted \
              || ( "$behind" != unknown && "$behind" != 0 ) || ( $branch == detached && "$upd" == rebase ) ]]; then
            attention+="$sp,"
        fi
    fi
done <<EOF
$subs
EOF
# submodules: the submodule paths in .gitmodules.
emit submodules "$(printf '%s\n' "$sub_list" | join)"
# submodules_attention: kit and project submodules that are out of step: changed files, commits not
# pushed, a pointer staged or not committed, behind their remote, or detached where the workspace
# asks for update=rebase. Outside submodules are never listed.
emit submodules_attention "${attention%,}"

# submodule_recurse: on | off | held (unset because an outside submodule, one the kit does not manage,
# is committed in directly and a recursive checkout would detach it).
recurse="$(cfg_get submodule.recurse)"
if [[ "$recurse" == true ]]; then submodule_recurse=on
elif [[ -n "$outside" ]]; then submodule_recurse=held
else submodule_recurse=off; fi
emit submodule_recurse "$submodule_recurse"
if [[ $QUICK -eq 0 ]]; then
    miss=""
    [[ "$(cfg_get push.recursesubmodules)" == check ]] || miss+="push.recurseSubmodules,"
    [[ "$(cfg_get status.submodulesummary)" == true ]] || miss+="status.submoduleSummary,"
    [[ $submodule_recurse == off ]] && miss+="submodule.recurse,"
    while IFS=$'\t' read -r sn sp _sb _su; do
        [[ -n "$sn" && "$sp" != "$kit_path" ]] || continue
        is_project_path "$sp" || continue
        [[ "$(cfg_get "submodule.$sn.update")" == rebase ]] || miss+="submodule.$sn.update,"
    done <<EOF
$subs
EOF
    # submodule_config: ok | missing:<keys> — the workspace settings kit/setup.sh sets for submodules
    # (push.recurseSubmodules=check, status.submoduleSummary=true, submodule.recurse=true unless held,
    # update=rebase for each project submodule); missing names, comma-joined, those not as expected.
    if [[ -z "$miss" ]]; then emit submodule_config ok; else emit submodule_config "missing:${miss%,}"; fi
fi
# orphan_gitlinks: gitlinks in the index with no .gitmodules entry. Reported, not failed on; every
# submodule walk skips them.
emit orphan_gitlinks "$(printf '%s\n' "$gitlinks" | awk -F '\t' -v paths="$(printf '%s\n' "$sub_list" | tr '\n' '\034')" '
    BEGIN { n = split(paths, a, "\034"); for (i = 1; i <= n; i++) if (a[i] != "") known[a[i]] = 1 }
    NF && !($1 in known) { print $1 }' | join)"

# ---- Project folders, their README fields, and resources ---------------------------------------------
# Every folder under the active, paused and done patterns (reserved _ and . folders excepted), with its
# entry point. Globs, not ls, so any name reads as itself.
entry_conv="$(conv Entry\ point)"
proj_dirs="" proj_files=()
while IFS= read -r pat; do
    [[ -n "$pat" ]] || continue
    glob="$(printf '%s' "$pat" | sed 's/<[^>]*>/*/g')"
    for d in "$T"/$glob/; do
        [[ -d "$d" ]] || continue
        rel="${d#"$T"/}"; rel="${rel%/}"
        match_pattern "$pat" "$rel" || continue
        case $'\n'"$proj_dirs"$'\n' in *$'\n'"$rel"$'\n'*) continue ;; esac
        ep=""
        for f in $entry_conv README.md CLAUDE.md; do [[ -f "$T/$rel/$f" ]] && { ep="$T/$rel/$f"; break; }; done
        [[ -n "$ep" ]] || continue
        proj_dirs="${proj_dirs:+$proj_dirs$'\n'}$rel"
        proj_files+=("$ep")
    done
done <<EOF
$patterns
EOF
# readme.awk from the workspace's kit (so it matches the pinned kit), else the sibling plugin.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
rawk=""
if [[ -n "$KD" && -f "$KD/plugins/projects/hooks/lib/readme.awk" ]]; then rawk="$KD/plugins/projects/hooks/lib/readme.awk"
elif [[ -f "$here/../../projects/hooks/lib/readme.awk" ]]; then rawk="$here/../../projects/hooks/lib/readme.awk"; fi
# records: folder<US>versioned<US>sensitivity<US>resources<US>generated, one per project folder.
records=""
if [[ -n "$rawk" && ${#proj_files[@]} -gt 0 ]]; then
    records="$(awk -f "$rawk" "${proj_files[@]}" 2>/dev/null | awk -F '\037' -v root="$T/" '
        { d = $1; if (index(d, root) == 1) d = substr(d, length(root) + 1); sub(/\/[^\/]*$/, "", d)
          printf "%s\037%s\037%s\037%s\037%s\n", d, $16, $17, $18, $19 }')"
fi
slug_of() { printf '%s' "${1##*/}"; }

sens="" sens_tracked="" mismatch=""
if [[ -z "$rawk" && -n "$proj_dirs" ]]; then
    sens=unknown sens_tracked=unknown mismatch=unknown; note "lib/readme.awk was not found; project fields not read"
elif [[ -n "$records" ]]; then
    # The entries the index holds under each project folder, from one ls-files over those folders:
    # folder<TAB>entries<TAB>1 when the only entry is the folder's own gitlink.
    pd_args=()
    while IFS= read -r p; do [[ -n "$p" ]] && pd_args+=("$p"); done <<EOF
$proj_dirs
EOF
    tracked=""
    [[ $in_git == yes ]] && tracked="$(g --literal-pathspecs ls-files -s -z -- ${pd_args[@]+"${pd_args[@]}"} | tr '\0' '\n' \
        | awk -v dirs="$(printf '%s\n' "$proj_dirs" | tr '\n' '\034')" '
            BEGIN { n = split(dirs, a, "\034"); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1 }
            { p = $0; sub(/^[^\t]*\t/, "", p); q = p
              while (q != "") { if (q in want) break; if (index(q, "/") == 0) { q = ""; break } sub(/\/[^\/]*$/, "", q) }
              if (q == "") next
              c[q]++; if (p == q && $1 == "160000") gl[q] = 1 }
            END { for (d in c) print d "\t" c[d] "\t" ((c[d] == 1 && gl[d]) ? 1 : 0) }')"
    # Declared-versioned folders that are not gitlinks, asked of .gitignore in one call.
    ign_in=""
    while IFS=$'\037' read -r d v _s _r _g; do
        [[ -n "$d" && -n "$v" ]] || continue
        printf '%s\n' "$gitlinks" | awk -F '\t' -v p="$d" '$1 == p { f = 1 } END { exit !f }' && continue
        ign_in+="$d/"$'\n'
    done <<EOF
$records
EOF
    ignored=""
    [[ $in_git == yes && -n "$ign_in" ]] && ignored="$(printf '%s' "$ign_in" | g check-ignore --stdin)"
    while IFS=$'\037' read -r d v s _r _g; do
        [[ -n "$d" ]] || continue
        slug="$(slug_of "$d")"
        if [[ "$s" == sensitive ]]; then
            sens+="$slug,"
            printf '%s\n' "$tracked" | awk -F '\t' -v p="$d" '$1 == p && $2 > 0 && $3 == 0 { f = 1 } END { exit !f }' \
                && sens_tracked+="$slug,"
        fi
        [[ -n "$v" ]] || continue
        if printf '%s\n' "$gitlinks" | awk -F '\t' -v p="$d" '$1 == p { f = 1 } END { exit !f }'; then actual="own-repo"
        elif printf '%s\n' "$ignored" | grep -qxF "$d/"; then actual=untracked
        elif [[ -e "$T/$d/.git" ]]; then actual=nested
        else actual=workspace; fi
        [[ "$v" == "$actual" ]] || mismatch+="$slug:$v/$actual,"
    done <<EOF
$records
EOF
    sens="${sens%,}" sens_tracked="${sens_tracked%,}" mismatch="${mismatch%,}"
fi
# sensitive_projects: projects whose README says Sensitivity: sensitive, by folder name.
emit sensitive_projects "$sens"
# sensitive_tracked: sensitive projects with files tracked by the workspace (anything in the index under
# the folder other than a single gitlink): the workspace pre-commit refuses to stage more.
emit sensitive_tracked "$sens_tracked"
# versioned_mismatch: <slug>:<declared>/<actual> where the README's Versioned: disagrees with the
# folder: own-repo (a gitlink), untracked (ignored by .gitignore), nested (a .git of its own that is not
# a registered submodule), workspace (otherwise).
emit versioned_mismatch "$mismatch"

# Resources. Each machine maps <slug>/<name> to a path in .claude/resources.local.md (the last line for
# a name wins, ~/ expands); a grant is a path under additionalDirectories in either settings file.
maps=""
if [[ -f "$T/.claude/resources.local.md" ]]; then
    mapre='^([A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*)[ '$'\t'']+(.+)$'
    while IFS= read -r line; do
        if [[ "$line" =~ $mapre ]]; then
            mp="${BASH_REMATCH[2]}"; mp="${mp%"${mp##*[![:space:]]}"}"
            case "$mp" in \~/*) mp="$HOME/${mp:2}" ;; esac
            maps+="${BASH_REMATCH[1]}"$'\t'"$mp"$'\n'
        fi
    done < "$T/.claude/resources.local.md"
fi
grants=""
if [[ $have_jq == yes ]]; then
    for f in "$T/.claude/settings.local.json" "$settings"; do
        [[ -f "$f" ]] && grants+="$(jq -r '(.permissions.additionalDirectories // [])[] | strings' "$f" 2>/dev/null)"$'\n'
    done
fi
granted() {
    local p="$1" gdir
    while IFS= read -r gdir; do
        [[ -n "$gdir" ]] || continue
        case "$gdir" in \~/*) gdir="$HOME/${gdir:2}" ;; esac
        [[ "$gdir" == / ]] || gdir="${gdir%/}"
        [[ "$p" == "$gdir" || "$p" == "$gdir"/* || "$gdir" == / ]] && return 0
    done <<EOF
$grants
EOF
    return 1
}
ext="" ext_missing=""
while IFS=$'\037' read -r d _v _s res gen; do
    [[ -n "$d" && -n "$res" ]] || continue
    slug="$(slug_of "$d")"
    # Resource names are letters, digits, dot, dash and underscore (readme.awk field 18), so they split
    # on the commas safely.
    # shellcheck disable=SC2086
    for name in ${res//,/ }; do
        key="$slug/$name"
        ext+="$key,"
        mp="$(printf '%s' "$maps" | awk -F '\t' -v k="$key" '$1 == k { p = $2 } END { print p }')"
        if [[ -n "$mp" ]]; then
            if [[ -e "$mp" ]]; then
                if [[ $QUICK -eq 1 ]] || { [[ -r "$mp" ]] && { [[ ! -d "$mp" ]] || ls "$mp" >/dev/null 2>&1; }; }; then
                    if granted "$mp"; then val="resolves granted"; else val="resolves ungranted"; fi
                else val="no-permission unreadable"; fi
            elif [[ $QUICK -eq 1 ]]; then val="missing absent"
            else
                lserr="$(LC_ALL=C ls -d "$mp" 2>&1 >/dev/null)"
                if [[ -z "$lserr" || "$lserr" == *"No such file"* ]]; then val="missing absent"; else val="no-permission unreadable"; fi
            fi
        elif in_list "$name" "$gen"; then
            if [[ -d "$T/$d/$name" ]]; then val="resolves inside"; else val="missing absent"; fi
        else val="missing unmapped"; fi
        # resource.<slug>/<name>: resolves granted | resolves ungranted | resolves inside (generated
        # output kept in the project folder) | missing unmapped (no path on this machine) | missing absent
        # (the mapped path is not there now) | no-permission unreadable (there, but this shell cannot
        # read it). --quick tests -e and -d only, and never lists a folder.
        emit "resource.$key" "$val"
        case "$val" in "missing absent"|no-permission*) ext_missing+="$key," ;; esac
    done
done <<EOF
$records
EOF
# external_paths: every resource a project README names under ## Resources, as <slug>/<name>.
emit external_paths "${ext%,}"
# external_paths_missing: those that are absent or unreadable on this machine. Unmapped names are the
# projects hook's to offer, once, when a session opens the project.
emit external_paths_missing "${ext_missing%,}"

# ---- The skills bridge, and whether Claude Code would load the kit's plugins ----------------------------
manifest="$T/.claude/skills/.kit-generated"
# skills_bridge: present | missing — .claude/skills/.kit-generated, written by kit/scripts/skills-bridge.sh.
if [[ -f "$manifest" ]]; then emit skills_bridge present; else emit skills_bridge missing; fi
# A shell cannot ask a running Claude Code what it loaded, so this reads the same files Claude Code reads
# at startup: enabledPlugins in .claude/settings.local.json, then .claude/settings.json, then the user's
# settings.json (the first that names a plugin decides), and the installed-plugins registry, both under
# ${CLAUDE_CONFIG_DIR:-~/.claude}, read-only. A plugin whose hook runs this (CLAUDE_PLUGIN_ROOT) is loaded.
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
registry="$cfg/plugins/installed_plugins.json"
kit_plugins=""
if [[ $kit_path != none && $kit_path != /* ]]; then
    for pj in "$T/$kit_path"/plugins/*/.claude-plugin/plugin.json; do
        [[ -f "$pj" ]] && kit_plugins+="$(basename "$(dirname "$(dirname "$pj")")")"$'\n'
    done
fi
p_loaded=unknown p_not=""
if [[ -n "$kit_plugins" && $have_jq == yes ]]; then
    # name<TAB>true|false from each settings file, highest precedence first; awk keeps the first per name.
    enabled="$(for f in "$T/.claude/settings.local.json" "$settings" "$cfg/settings.json"; do
                   [[ -f "$f" ]] && jq -r '(.enabledPlugins // {}) | to_entries[] | select(.key | endswith("@agentic-workspace"))
                                           | "\(.key | sub("@agentic-workspace$"; ""))\t\(.value == true)"' "$f" 2>/dev/null
               done | awk -F '\t' '!($1 in seen) { seen[$1] = 1; print }')"
    installed="" have_registry=no
    if [[ -f "$registry" ]]; then
        # Installed for the user, or for this repository (project and local scope carry its path).
        installed="$(jq -r --arg t "$T" '(.plugins // {}) | to_entries[] | select(.key | endswith("@agentic-workspace"))
                         | select(any(.value | if type == "array" then .[] else . end; .scope == "user" or .projectPath == $t))
                         | .key | sub("@agentic-workspace$"; "")' "$registry" 2>/dev/null)" && have_registry=yes
        installed="$(printf '%s\n' "$installed" | join)"
    fi
    # The workspace's own settings registering the kit as a directory marketplace (the 3.0 layout:
    # extraKnownMarketplaces.agentic-workspace, source directory, path kit). Claude Code loads the plugins
    # those settings enable straight from that folder, without writing them to the registry, so the
    # registry is not consulted for them.
    dir_mkt=no
    for f in "$T/.claude/settings.local.json" "$settings"; do
        [[ -f "$f" ]] || continue
        mp="$(jq -r '.extraKnownMarketplaces["agentic-workspace"].source // empty | select(.source == "directory") | .path // empty' "$f" 2>/dev/null)"
        [[ -n "$mp" ]] || continue
        case "$mp" in /*) ;; *) mp="$T/$mp" ;; esac
        [[ -f "$mp/.claude-plugin/marketplace.json" ]] && dir_mkt=yes
        break
    done
    here_plugin=""
    [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && here_plugin="$(jq -r '.name // empty' "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)"
    while IFS= read -r p; do
        [[ -n "$p" && "$p" != "$here_plugin" ]] || continue
        case "$(printf '%s\n' "$enabled" | awk -F '\t' -v p="$p" '$1 == p { print $2; exit }')" in
            false) p_not+="$p:disabled," ;;
            true) [[ $dir_mkt == no && $have_registry == yes ]] && ! in_list "$p" "$installed" && p_not+="$p:not-installed," ;;
            *) p_not+="$p:not-enabled," ;;
        esac
    done <<EOF
$kit_plugins
EOF
    if [[ -n "$p_not" ]]; then p_loaded=no; elif [[ $have_registry == yes || $dir_mkt == yes ]]; then p_loaded=yes; fi
fi
# plugins_loaded: yes | no | unknown — whether Claude Code on this machine, opened here, would load every
# plugin in the kit checkout: each enabled by the settings above, and either served by the directory
# marketplace the workspace's own settings register (a kit/ that exists) or installed in the registry. It reads
# configuration, not the running session, so a plugin that is set up but fails to load still reads yes,
# and one loaded for a session only (claude --plugin-dir) reads no. Managed settings are not read.
# unknown: no jq, no kit checkout, or no registry to read (a machine where Claude Code has installed no
# plugins, or another surface's shell).
emit plugins_loaded "$p_loaded"
# plugins_not_loaded: each kit plugin not loaded, as <plugin>:<why> — not-enabled (no settings file enables
# it), disabled (the first settings file to name it sets it false: a choice, which the session-start
# summary leaves alone) or not-installed (enabled, but not in the registry for the user or this
# repository, and no directory marketplace in the workspace's settings serves it). The fix for the first and last is claude plugin install <plugin>@agentic-workspace, or
# /plugin.
emit plugins_not_loaded "${p_not%,}"

if [[ $QUICK -eq 1 ]]; then
    # quick: 1 when the report is the --quick subset.
    emit quick 1
    if [[ $JSON -eq 1 ]]; then
        printf '%s' "$out" | jq -Rn '[inputs | select(length > 0) | capture("^(?<key>[^=]+)=(?<value>.*)$")] | from_entries' 2>/dev/null \
            || { printf 'error=--json needs jq\n'; exit 2; }
    else
        printf '%s' "$out"
    fi
    exit 0
fi

# ---- The rest of the kit's state (the full check only) -----------------------------------------------
# kit_untracked_refused: untracked files in the kit checkout that its path rules would refuse
# (scripts/check-paths.sh --paths): a stray file a broad git add in kit/ would sweep in | unknown (the
# checker could not run).
kur=0
if [[ $kit_repo == yes ]]; then
    untracked="$(gx "$KD" ls-files -o --exclude-standard)"
    if [[ -n "$untracked" ]]; then
        cpo="$(printf '%s\n' "$untracked" | bash "$KD/scripts/check-paths.sh" --root "$KD" --workspace "$T" --paths 2>/dev/null)"
        cprc=$?
        if [[ $cprc -le 1 ]]; then kur="$(printf '%s\n' "$cpo" | grep -c '^refused')"; else kur=unknown; fi
    fi
fi
emit kit_untracked_refused "$kur"
# workspace_conventions: present | missing — .claude/workspace.md, read by the hooks, this check and the
# skills bridge.
if [[ -f "$T/.claude/workspace.md" ]]; then emit workspace_conventions present; else emit workspace_conventions missing; fi
# word_list: resolves | unreadable (named, but it cannot be read, or it sits inside the kit) | none. Only
# its state is reported, never its path or contents.
aw_word_list "$T" >/dev/null 2>&1; wl=$?
wlp="$(aw_word_list "$T" 2>/dev/null)"
if [[ $wl -eq 2 ]]; then emit word_list unreadable; elif [[ -n "$wlp" ]]; then emit word_list resolves; else emit word_list none; fi
# ledger: present | missing — .claude/kit-templates.lock, the engine's record of the files it made.
if [[ -f "$T/.claude/kit-templates.lock" ]]; then emit ledger present; else emit ledger missing; fi
# resources_file: present | missing — .claude/resources.local.md, this machine's resource paths.
if [[ -f "$T/.claude/resources.local.md" ]]; then emit resources_file present; else emit resources_file missing; fi
# The skills bridge's manifest (read above): origin<TAB>folder<TAB>source per folder it wrote.
bridged="" nb=0 nstale=0
if [[ -f "$manifest" ]]; then
    bridged="$(awk -F '\t' '!/^#/ && NF >= 2 && $2 != "" && $1 != "skip" { print $2 }' "$manifest" 2>/dev/null)"
    nb="$(awk -F '\t' '!/^#/ && NF >= 2 && $2 != "" { n++ } END { print n + 0 }' "$manifest" 2>/dev/null)"
    while IFS= read -r b; do [[ -n "$b" && ! -d "$T/.claude/skills/$b" ]] && nstale=$((nstale + 1)); done <<EOF
$bridged
EOF
fi
# skills_bridge_count: the manifest's lines (kit and user folders written, and skip lines).
emit skills_bridge_count "$nb"
# skills_bridge_stale: listed kit and user folders that are missing (kit/setup.sh skills writes them
# again).
emit skills_bridge_stale "$nstale"

# ---- The always-loaded file ---------------------------------------------------------------------------
# agents_md: opaque (a file the kit does not open: listed in AW_OPAQUE_PATHS, AGENTS.md by default, and
# not recorded as the engine's own in the ledger) | kit (its first line imports kit/CLAUDE.kit.md, or
# the 2.x "Team Manifest" heading) | own (any other AGENTS.md) | unreadable (present, but this shell
# may not read it) | missing
# A sandbox that denies reads can deny the stat as well, so the file looks absent to -e. It counts as
# present when -e sees it, or when ls fails for any reason other than there being no such file.
agents_there=no
if [[ -e "$T/AGENTS.md" ]]; then agents_there=yes
else
    lserr="$(LC_ALL=C ls -d "$T/AGENTS.md" 2>&1 >/dev/null)"
    [[ -n "$lserr" && "$lserr" != *"No such file"* ]] && agents_there=yes
fi
if aw_is_opaque "$T" AGENTS.md; then
    agents_md=opaque
elif [[ $agents_there == yes ]] && { [[ ! -e "$T/AGENTS.md" || ! -r "$T/AGENTS.md" ]] || ! head -c 1 "$T/AGENTS.md" >/dev/null 2>&1; }; then
    agents_md=unreadable; note "AGENTS.md is present but cannot be read here"
elif [[ -f "$T/AGENTS.md" ]]; then
    if [[ "$(first_line "$T/AGENTS.md")" == "@kit/CLAUDE.kit.md" ]] || grep -qE '^# .*Team Manifest[[:space:]]*$' "$T/AGENTS.md" 2>/dev/null; then
        agents_md=kit
    else agents_md=own; fi
else
    agents_md=missing
fi
# claude_md: kit (its first line imports kit/CLAUDE.kit.md) | shim (nothing but the 2.x @AGENTS.md
# import, comments and blank lines aside) | own | missing
if [[ -f "$T/CLAUDE.md" ]]; then
    body="$(awk '{ line = $0
                   while (1) { if (inc) { i = index(line, "-->"); if (!i) { line = ""; break } line = substr(line, i + 3); inc = 0 }
                               i = index(line, "<!--"); if (!i) break
                               rest = substr(line, i + 4); j = index(rest, "-->")
                               if (j) line = substr(line, 1, i - 1) substr(rest, j + 3); else { line = substr(line, 1, i - 1); inc = 1; break } }
                   gsub(/^[ \t\r]+|[ \t\r]+$/, "", line); if (line != "") print line }' "$T/CLAUDE.md" 2>/dev/null)"
    if [[ "$body" == "@AGENTS.md" ]]; then claude_md=shim
    elif [[ "$cl1" == "@kit/CLAUDE.kit.md" ]]; then claude_md=kit
    else claude_md=own; fi
else
    claude_md=missing
fi
[[ -f "$T/GEMINI.md" ]] && gemini_md=present || gemini_md=missing
# always_loaded: the file this surface actually loads, where the team part is judged and filled:
# CLAUDE.md when it is the kit's import or the repository's own; AGENTS.md when CLAUDE.md is the 2.x
# shim or absent (other tools read AGENTS.md directly); none.
if [[ $claude_md == own || $claude_md == kit ]]; then always_loaded=CLAUDE.md
elif [[ $agents_md != missing ]]; then always_loaded=AGENTS.md
else always_loaded=none; fi
emit always_loaded "$always_loaded"
emit agents_md "$agents_md"
emit claude_md "$claude_md"
# gemini_md: present | missing — a GEMINI.md of the repository's own (the kit never lays one down).
emit gemini_md "$gemini_md"
if [[ $always_loaded == none ]]; then standins=0 surf_standins=0
elif [[ $always_loaded == AGENTS.md && ( $agents_md == unreadable || $agents_md == opaque ) ]]; then standins=unknown surf_standins=unknown
else
    standins="$(standins "$T/$always_loaded" team)"; surf_standins="$(standins "$T/$always_loaded" surfaces)"
fi
# standins_remaining: stand-ins left in the always-loaded file's §1–§3. Above 0, the team part is open.
emit standins_remaining "${standins:-0}"
# surface_standins: a stand-in row in the §4 surface table: fill it with the other surface, or remove it.
emit surface_standins "${surf_standins:-0}"

# ---- Project conventions (.claude/projects.md) --------------------------------------------------------
# projects_conventions: kit (a "Project conventions" heading, projects in projects/<slug>/, the register
# at projects/INDEX.md) | foreign (another layout, or no such heading) | missing
if [[ ! -f "$T/.claude/projects.md" ]]; then pc=missing
elif grep -qiE '^#+[[:space:]]+Project conventions' "$T/.claude/projects.md" 2>/dev/null \
     && [[ "${active%/}" == "projects/<slug>" && "$register_path" == "projects/INDEX.md" ]]; then pc=kit
else pc=foreign; fi
emit projects_conventions "$pc"
# projects_dir: the Active pattern, where projects live. A value with prose after the path, as the
# kit's own lines have, is cut to the path.
emit projects_dir "$active"
# paused_dir: where paused projects are (the Active pattern unless the conventions say otherwise).
emit paused_dir "${paused_conv:-$active}"
# done_dir: where finished projects go (the Active pattern unless the conventions say otherwise).
emit done_dir "${done_conv:-$active}"
n="$(grep -E '^[[:space:]]*[-*] \*\*' "$T/.claude/projects.md" 2>/dev/null | grep -ci 'not set yet')"
# conventions_not_set: conventions still reading "not set yet"; each is a team-part question.
emit conventions_not_set "${n:-0}"
# in_flight_limit: the In-flight limit convention.
emit in_flight_limit "$(conv In-flight\ limit)"
# staleness: the Staleness convention (how old Updated: can be before the board flags it).
emit staleness "$(conv Staleness)"
default_owner="$(conv Default\ owner)"; [[ -n "$default_owner" ]] || default_owner="$(conv Owner)"
# default_owner: the one owner the conventions name for every project with no People section.
emit default_owner "$default_owner"

# ---- People -------------------------------------------------------------------------------------------
# The people directory is the one .claude/projects.md names; the profile is <full-name-slug>.md there.
people="$(conv People)"; people="${people:-memory/people/<name>.md}"
case "$people" in *'<'*) people="${people%%<*}" ;; esac
people="${people%/}"; people="${people#./}"
# people_dir: the folder person profiles live in.
emit people_dir "$people"
if [[ -z "$person_slug" ]]; then prof=unknown prof_path=""; note "git config user.name is not set"
elif [[ -f "$T/$people/$person_slug.md" ]]; then prof=present prof_path="$people/$person_slug.md"
else prof=missing prof_path=""; fi
# person_profile: present | missing | unknown (no user.name) — this person's profile.
emit person_profile "$prof"
# person_profile_path: that profile's path, when present.
emit person_profile_path "$prof_path"
# Profiles that might be this person's under another name (first name only, say): for the agent to confirm.
first="${person_slug%%-*}"
# Markdown files in the people folder, README aside, matched without regard to case; a glob, not ls, so
# any file name reads as itself.
cand="" n=0
if [[ -d "$T/$people" ]]; then
    for f in "$T/$people"/*; do
        f="${f##*/}" l="$(lower "${f##*/}")"
        [[ -f "$T/$people/$f" && "$l" == *.md && "$l" != readme.md ]] || continue
        n=$((n + 1))
        [[ -n "$first" && "$l" == *"$(lower "$first")"* && "$f" != "$person_slug.md" ]] && cand+="$people/$f"$'\n'
    done
fi
# person_profile_candidates: profiles that might be this person's under another name, to confirm.
emit person_profile_candidates "$(printf '%s' "$cand" | join)"
# people_profiles: profiles in the people folder.
emit people_profiles "$n"

# ---- The register and the projects in it --------------------------------------------------------------
# register: kit (Active, Paused and Done sections, as the installer writes it) | foreign | missing
if [[ ! -f "$T/$register_path" ]]; then reg=missing
elif [[ $(grep -cE '^## +(Active|Paused|Done)([^[:alnum:]]|$)' "$T/$register_path" 2>/dev/null) -ge 3 ]] \
     && grep -qE '^## +Active' "$T/$register_path" && grep -qE '^## +Paused' "$T/$register_path" && grep -qE '^## +Done' "$T/$register_path"; then reg=kit
else reg=foreign; fi
emit register "$reg"
# register_path: the register file the conventions name.
emit register_path "$register_path"
# register_rows: projects already listed in the register's tables.
emit register_rows "$( [[ -f "$T/$register_path" ]] && table_rows "$T/$register_path" || echo 0)"
# Project folders under the Active pattern, each with its entry point (README.md, else CLAUDE.md).
# Reserved folders (a name starting with _ or .) are not projects.
glob="$(printf '%s' "${active%/}" | sed 's/<[^>]*>/*/g')"
nproj=0 nostate=0 nprop=0
for d in "$T"/$glob/; do
    [[ -d "$d" ]] || continue
    rel="${d#"$T"/}"; rel="${rel%/}"
    match_pattern "$(pattern_of "$active")" "$rel" || continue
    ep=""; [[ -f "$d/README.md" ]] && ep="$d/README.md"; [[ -z "$ep" && -f "$d/CLAUDE.md" ]] && ep="$d/CLAUDE.md"
    [[ -n "$ep" ]] || continue
    nproj=$((nproj + 1))
    grep -qiE '^#+[[:space:]]+Current state' "$ep" 2>/dev/null || nostate=$((nostate + 1))
    grep -q 'proposed by /projects:adopt' "$ep" 2>/dev/null && nprop=$((nprop + 1))
done
# project_folders: project folders under the Active pattern with an entry point.
emit project_folders "$nproj"
# projects_without_current_state: those with no Current state block; with no adopt proposals either,
# offer /projects:adopt draft.
emit projects_without_current_state "$nostate"
# adopt_proposals: READMEs still carrying "proposed by /projects:adopt" blocks.
emit adopt_proposals "$nprop"

# ---- Other canonical files ----------------------------------------------------------------------------
# glossary: present | missing — memory/glossary.md.
if [[ -f "$T/memory/glossary.md" ]]; then emit glossary present
    # glossary_terms: rows in the glossary's tables.
    emit glossary_terms "$(table_rows "$T/memory/glossary.md")"
else emit glossary missing; emit glossary_terms 0; fi
# build_list: present | missing — pilot/build-list.md.
if [[ -f "$T/pilot/build-list.md" ]]; then emit build_list present; else emit build_list missing; fi
# verification: present | missing — docs/verification.md, what counts as checked.
if [[ -f "$T/docs/verification.md" ]]; then emit verification present; else emit verification missing; fi
# catalogue: present | missing — docs/catalogue.md.
if [[ -f "$T/docs/catalogue.md" ]]; then emit catalogue present; else emit catalogue missing; fi
readme=""; for f in README.md README readme.md README.rst; do [[ -f "$T/$f" ]] && { readme="$f"; break; }; done
# readme: the repository's README file, or empty.
emit readme "$readme"
co=""; for f in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS .gitlab/CODEOWNERS; do [[ -f "$T/$f" ]] && { co="$f"; break; }; done
# codeowners: the CODEOWNERS file, or empty.
emit codeowners "$co"

# ---- The decisions log --------------------------------------------------------------------------------
# decisions_log: kit (logs/decisions.md, every entry headed "## [YYYY-MM-DD] Title") | foreign (other
# headings, or a decisions log kept somewhere else) | missing. Per-project logs inside project folders
# are the kit's own shape and are not counted as elsewhere; the kit checkout and _delete/ are skipped.
prune=()
for p in "$active" "$paused_conv" "$done_conv" templates .claude/plugins _delete "${KD#"$T"/}"; do
    p="${p%%/*}"; [[ -n "$p" && "$p" != "<"* && "$p" != /* ]] && prune+=(-o -path "$T/$p")
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
# decisions_log_other: decision logs or ADR folders kept elsewhere.
emit decisions_log_other "$other"

# ---- Skills and commands of the team's own ------------------------------------------------------------
# own_skills: every skill (.claude/skills/, skills/) and command (.claude/commands/) the installer did
# not generate; the skills bridge's copies in .claude/skills/ (listed in its manifest) are not counted
# again. foreign_skills: those whose name says they do a kit command's job — closeout, the board,
# hygiene and the rest. The name match is a first pass; the agent reads own_skills for the rest.
own=""
for base in .claude/skills skills; do
    for s in "$T/$base"/*/; do
        [[ -d "$s" ]] || continue
        grep -qs 'Generated by install.sh from plugins/' "$s/SKILL.md" && continue
        [[ $base == .claude/skills ]] && printf '%s\n' "$bridged" | grep -qxF "$(basename "$s")" && continue
        own+="$base/$(basename "$s")"$'\n'
    done
done
if [[ -d "$T/.claude/commands" ]]; then
    own+="$(cd "$T" && find .claude/commands -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
        grep -qs 'Generated by install.sh from plugins/' "$f" || printf '%s\n' "$f"; done | sort)"$'\n'
fi
emit own_skills "$(printf '%s' "$own" | join)"
# foreign_skills: own skills whose name says they do a kit command's job; a first pass for the agent.
emit foreign_skills "$(printf '%s' "$own" | grep -iE 'close-?out|wrap-?up|board|hygiene|tidy|pick-?up|adopt|quick-?start|onboard|register-audit' | join)"

# ---- Kit versions written beside the team's own files, to merge by hand (2.x) -----------------------
kit_incoming="$(cd "$T" && find . -maxdepth 6 \( -path ./.git -o -name node_modules \) -prune -o -type f -name '*.kit-incoming' -print 2>/dev/null | sed 's#^\./##' | sort | join)"
# kit_incoming: 2.x .kit-incoming files, a kit version written beside a file of the team's own.
emit kit_incoming "$kit_incoming"

# ---- Plugins, surfaces, measurement -------------------------------------------------------------------
# settings: present | missing — .claude/settings.json.
if [[ -f "$settings" ]]; then emit settings present; else emit settings missing; fi
# plugins_registered: the kit's plugins enabled from the agentic-workspace marketplace.
emit plugins_registered "$plugins"
# plugins_mode: kit (the directory marketplace at kit/, the 3.0 layout) | vendor (a 2.x copy in
# .claude/plugins) | directory (a kit checkout elsewhere) | github (fetched by Claude Code) | none
emit plugins_mode "$pmode"
# plugins_path: the directory marketplace's path.
emit plugins_path "$ppath"
kit_checkout="" vcommit=""
if [[ -f "$T/.claude/plugins/VENDORED" ]]; then
    vcommit="$(sed -n 's/^kit commit: //p' "$T/.claude/plugins/VENDORED" | head -n 1)"
    kit_checkout="$(sed -n 's/^kit checkout: \(.*\) (on the machine.*/\1/p' "$T/.claude/plugins/VENDORED" | head -n 1)"
fi
# A directory marketplace that is a kit checkout (one with pilot/measure.sh) is the kit checkout.
[[ ( $pmode == directory || $pmode == kit ) && -f "$T/$ppath/pilot/measure.sh" ]] && kit_checkout="$ppath"
# vendored_commit: the kit commit a 2.x vendored copy came from.
emit vendored_commit "$vcommit"
# kit_checkout: the kit checkout the plugins come from (kit in a 3.0 workspace).
emit kit_checkout "$kit_checkout"
# closeout_conventions: present | missing — .claude/closeout.md.
if [[ -f "$T/.claude/closeout.md" ]]; then emit closeout_conventions present; else emit closeout_conventions missing; fi
surfaces=""
{ [[ -f "$settings" || $claude_md != missing ]]; } && surfaces="claude"
[[ -f "$T/.gemini/settings.json" ]] && surfaces="${surfaces:+$surfaces,}gemini"
# surfaces: the surfaces set up here (claude, gemini).
emit surfaces "$surfaces"
# gemini_commands: TOML command files under .gemini/commands.
emit gemini_commands "$( [[ -d "$T/.gemini/commands" ]] && find "$T/.gemini/commands" -type f -name '*.toml' 2>/dev/null | count || echo 0)"
ms=""
if [[ -f "$T/pilot/measure.sh" ]]; then ms="pilot/measure.sh"
elif [[ -n "$kit_checkout" ]]; then
    case "$kit_checkout" in /*) [[ -f "$kit_checkout/pilot/measure.sh" ]] && ms="$kit_checkout/pilot/measure.sh" ;;
                            *) [[ -f "$T/$kit_checkout/pilot/measure.sh" ]] && ms="$kit_checkout/pilot/measure.sh" ;; esac
fi
# measure_script: the metrics script to run, in the repository or in the kit checkout.
emit measure_script "$ms"
# metrics_csv: present | missing — pilot/metrics.csv; for joining, the baseline is taken.
if [[ -f "$T/pilot/metrics.csv" ]]; then emit metrics_csv present; else emit metrics_csv missing; fi
dd="${CLOSEOUT_DRAFT_ROOT:-$HOME/.claude/closeout-drafts}/$(basename "$T")"
n=0
for f in "$dd"/*.md; do [[ -f "$f" ]] && n=$((n + 1)); done
# closeout_drafts_pending: closeout drafts a prior session left for this repository.
emit closeout_drafts_pending "$n"

# ---- 2.x traces -----------------------------------------------------------------------------------------
lg=""
[[ -f "$T/.claude/plugins/VENDORED" ]] && lg+="vendored,"
[[ -n "$kit_incoming" ]] && lg+="kit_incoming,"
kna=no
[[ $kit_path != none && $kit_path != kit ]] && kna=yes
while IFS=$'\t' read -r sn sp _sb _su; do
    [[ -n "$sn" && "$sp" != kit ]] || continue
    grep -q '"agentic-workspace"' "$T/$sp/.claude-plugin/marketplace.json" 2>/dev/null && kna=yes
done <<EOF
$subs
EOF
[[ $kna == yes ]] && lg+="kit_not_at_kit,"
for s in "$T"/skills/*/; do
    [[ -d "$s" ]] && grep -qs 'Generated by install.sh from plugins/' "$s/SKILL.md" && { lg+="generated_skills_in_skills,"; break; }
done
[[ $claude_md == shim ]] && lg+="agents_shim,"
# legacy: 2.x traces kit/setup.sh migrate deals with: vendored (.claude/plugins/VENDORED),
# kit_incoming (.kit-incoming files), kit_not_at_kit (a kit checkout at a path other than kit/),
# generated_skills_in_skills (install.sh-generated skills in skills/), agents_shim (CLAUDE.md is the 2.x
# @AGENTS.md shim).
emit legacy "${lg%,}"

# ---- Mode ---------------------------------------------------------------------------------------------
signs=""
[[ $claude_md == own ]] && signs+="claude_md,"
[[ $agents_md == own && $claude_md != kit ]] && signs+="agents_md,"
[[ $gemini_md == present ]] && signs+="gemini_md,"
[[ $reg == foreign ]] && signs+="register,"
[[ $dl == foreign ]] && signs+="decisions_log,"
[[ $pc == foreign ]] && signs+="projects_conventions,"
printf '%s' "$out" | grep -q '^foreign_skills=.' && signs+="foreign_skills,"
signs="${signs%,}"
# signs: what says a system was here first — anything the installer did not lay down. The kit's own
# files, as installed or as filled in, are not signs, and neither is a .kit-incoming beside one; an
# AGENTS.md of its own is not one beside a CLAUDE.md that imports the kit.
emit signs "$signs"
# mode: the first that fits, in the quick-start's order:
#   joining         the team part is filled in (the kit's always-loaded file, no stand-ins left) and
#                   this person has no profile: the personal part only
#   existing-system any sign above: the kit adopts rather than installs
#   fresh           stand-ins still in the always-loaded file (or none to judge yet): team part, then personal
#   nothing-left    filled in, and they have a profile: the last section on its own
if [[ "$standins" == 0 && $prof != present ]] \
   && { [[ $agents_md == kit && $always_loaded == AGENTS.md ]] || [[ $claude_md == kit ]]; }; then mode=joining
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
