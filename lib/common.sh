# shellcheck shell=bash
# Shared functions for the kit's scripts: setup, the engine, the git hooks and the scripts in scripts/.
#
# Sourced, never run, so it sets no shell options of its own. Written for bash 3.2 (macOS /bin/bash):
# no associative arrays, no ${x,,}, no mapfile. Only git is needed; no function here uses jq, because
# the git hooks source this file and GUI git clients run hooks with a minimal PATH.
#
# Functions:
#   aw_kitname WS              the kit submodule's name in WS/.gitmodules (its path is kit), or nothing
#   aw_norm_url URL            a remote URL as host/owner/repo, lowercased; a local path as local:<abs>
#   aw_private_remotes WS      one line per Private remote in WS/.claude/workspace.md: url<TAB>via<TAB>date
#   aw_public_remotes WS       one line per Public remote bullet: url<TAB>folder<TAB>, the folder being
#                              the project the bullet names in its second backticked span, or nothing
#   aw_git_elsewhere DIR ARGS  git -C DIR ARGS with the calling repository's git environment cleared
#   aw_count                   a line count of stdin, with no padding
#   aw_is_opaque WS REL        exit 0 when REL is a file the kit does not open
#   aw_word_list WS            the private word list path that resolves, or nothing; exit 2 when one is
#                              configured but cannot be used

# The kit checkout this file belongs to, for the checks that keep private material out of it.
AW_KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# aw_kitname WS
# The kit submodule is found by its path, kit, not by its name: a migrated workspace keeps the name it
# had at its old path.
aw_kitname() {
    local ws="$1" key value
    [[ -f "$ws/.gitmodules" ]] || return 0
    while read -r key value; do
        if [[ "$value" == "kit" ]]; then
            key="${key#submodule.}"
            printf '%s\n' "${key%.path}"
            return 0
        fi
    done <<EOF
$(git --no-optional-locks config -f "$ws/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null)
EOF
    return 0
}

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

# aw_public_remotes WS
# url<TAB>folder<TAB> per Public remote. A Public remote is bound to one project: the bullet names the
# remote in its first backticked span and the project folder in its second, as
# - **Public remote:** `github.com/owner/site` — `projects/site/`, the published site
# The folder comes back workspace-relative, with no ./ and no trailing /; empty when the bullet names
# none, which the project pre-push refuses.
aw_public_remotes() {
    local line url dir re
    # shellcheck disable=SC2016
    re='^[ '$'\t'']*[-*] \*\*Public remote:\*\*[^`]*`([^`]+)`[^`]*(`([^` ]+)`)?'
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$line" =~ $re ]]; then
            url="$(aw_norm_url "${BASH_REMATCH[1]}")"
            dir="${BASH_REMATCH[3]}"; dir="${dir#./}"
            while [[ "$dir" == */ ]]; do dir="${dir%/}"; done
            [[ -n "$url" ]] && printf '%s\t%s\t\n' "$url" "$dir"
        fi
    done <<EOF
$(_aw_remote_lines "$1" "Public remote")
EOF
    return 0
}

# aw_git_elsewhere DIR ARGS...
# A git hook inherits GIT_DIR, GIT_INDEX_FILE and the rest from the git that ran it; a git command
# aimed at another repository would read them and act on the wrong one. Optional locks are off, so a
# read never rewrites an index.
aw_git_elsewhere() {
    local dir="$1"; shift
    (
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX \
            GIT_ALTERNATE_OBJECT_DIRECTORIES
        git --no-optional-locks -C "$dir" "$@"
    )
}

# aw_count
# Lines on stdin, as a bare number (BSD wc pads its count with spaces). A last line with no newline
# still counts.
aw_count() { awk 'END { print NR }'; }

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
# stderr. With none named, it prints nothing and exits 0.
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
