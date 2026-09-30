#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/../..
# lib/setup/link.sh: kit/setup.sh link, which maps each project's named resources on this machine.
#
#   kit/setup.sh link [SLUG] [--target DIR] [--dry-run]
#   bash kit/lib/setup/link.sh --target WS [SLUG] [--dry-run]
#
# A project names the material it uses from outside the repository under "## Resources" in its README,
# by name only. Each machine maps <slug>/<name> to a real path in .claude/resources.local.md, which is
# gitignored. For every mapped path this machine can read, link makes the symlink
# <project folder>/.resources/<name> and grants the path to Claude Code in .claude/settings.local.json
# (permissions.additionalDirectories). A resource the README calls generated, with no mapping, lives
# inside the project folder and is listed in the project's .gitignore instead.
#
# Output is one line per resource, which setup's stage 6 shows as it is:
#   linked   <slug>/<name> -> <path>    granted  <path>    missing  <slug>/<name> (...)
#   no-permission <slug>/<name> (...)   inside   <slug>/<name> (...)   unmapped <slug>/<name>
#   ignored  <slug>/<text> (...)        kept     <slug>/<name> (...)
# --dry-run prints the same lines with "would " in front and writes nothing.
#
# Attended (a person at a terminal), an unmapped name is asked for; the answer is appended to
# .claude/resources.local.md and then linked. A path is never guessed. Unattended
# (AW_WIZARD_NONINTERACTIVE=1, or no terminal on stdin) nothing is asked and that file is not written.
#
# Exit codes: 0 finished (a resource that is not on this machine is not an error), 1 not a workspace,
# or .claude/settings.local.json could not be updated, 2 usage.
#
# Written for bash 3.2 (macOS /bin/bash); needs git and jq.
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=lib/common.sh
. "$KIT/lib/common.sh"
# shellcheck source=lib/wizard.sh
. "$KIT/lib/wizard.sh"
# shellcheck source=plugins/projects/hooks/lib/config.sh
. "$KIT/plugins/projects/hooks/lib/config.sh"
README_AWK="$KIT/plugins/projects/hooks/lib/readme.awk"
trap 'echo; echo "Stopped. Run kit/setup.sh link again: links already made are kept."; exit 130' INT

usage() {
    cat <<'EOF'
Usage: kit/setup.sh link [SLUG] [--target DIR] [--dry-run]
       bash kit/lib/setup/link.sh --target WS [SLUG] [--dry-run]

Maps the resources each project names under "## Resources" to paths on this machine, from
.claude/resources.local.md: a symlink at <project>/.resources/<name>, and the path granted to Claude
Code in .claude/settings.local.json. With SLUG, only that project. --dry-run writes nothing.
EOF
}

WS="" SLUG="" DRY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) [[ $# -ge 2 && -n "$2" ]] || { echo "link: --target needs a folder" >&2; usage >&2; exit 2; }
                  WS="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "link: unknown option $1" >&2; usage >&2; exit 2 ;;
        *) [[ -z "$SLUG" ]] || { echo "link: one project at a time ($SLUG, then $1)" >&2; exit 2; }
           SLUG="$1"; shift ;;
    esac
done
[[ -n "$WS" ]] || { echo "link: --target is required" >&2; usage >&2; exit 2; }
slug_re='^[A-Za-z0-9][A-Za-z0-9._-]*$'
if [[ -n "$SLUG" && ! "$SLUG" =~ $slug_re ]]; then
    echo "link: $SLUG is not a project folder name" >&2; exit 2
fi
if [[ ! -d "$WS" ]] || ! WS="$(cd "$WS" && pwd -P)" || [[ ! -e "$WS/.git" && ! -f "$WS/.claude/projects.md" ]]; then
    echo "link: $WS is not a workspace (no .git and no .claude/projects.md there)" >&2
    exit 1
fi

LOCAL_MAP="$WS/.claude/resources.local.md"
SETTINGS_LOCAL="$WS/.claude/settings.local.json"
SETTINGS_SHARED="$WS/.claude/settings.json"
FAILED=0

# say_line <word> <rest>: one output line, the word padded to line the names up.
say_line() {
    if [[ $DRY -eq 1 ]]; then printf 'would %-8s %s\n' "$1" "$2"; else printf '%-8s %s\n' "$1" "$2"; fi
}
say_plain() {
    if [[ $DRY -eq 1 ]]; then printf 'would %s\n' "$1"; else printf '%s\n' "$1"; fi
}

# ---- The mappings on this machine ------------------------------------------------------------------
# MAP_KEYS and MAP_PATHS are parallel; the last line for a key wins, so lookups walk from the end.
MAP_KEYS=() MAP_PATHS=()
map_re='^([A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*)[ '$'\t'']+(.+)$'
if [[ -f "$LOCAL_MAP" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ $map_re ]]; then
            p="${BASH_REMATCH[2]}"
            p="${p%"${p##*[![:space:]]}"}"
            [[ -n "$p" ]] || continue
            MAP_KEYS+=("${BASH_REMATCH[1]}")
            MAP_PATHS+=("$p")
        fi
    done < "$LOCAL_MAP"
fi

# map_lookup <slug/name>: the mapped path, expanded (~/ to $HOME/, a relative path against the
# workspace root, a trailing slash dropped); status 1 when unmapped.
map_lookup() {
    local i=${#MAP_KEYS[@]} p
    while [[ $i -gt 0 ]]; do
        i=$((i - 1))
        if [[ "${MAP_KEYS[$i]}" == "$1" ]]; then
            p="${MAP_PATHS[$i]}"
            case "$p" in
                "~") p="$HOME" ;;
                \~/*) p="$HOME/${p:2}" ;;
                /*) ;;
                *) p="$WS/$p" ;;
            esac
            while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

# path_state <path>: absent, unreadable or readable. Existence follows the state check: -e, else the
# error ls gives (a path under a folder this shell may not enter is still there). A folder counts as
# readable only when it can be listed.
path_state() {
    local p="$1" err
    if [[ ! -e "$p" ]]; then
        err="$(LC_ALL=C ls -d "$p" 2>&1 >/dev/null)"
        if [[ -z "$err" || "$err" == *"No such file"* ]]; then printf 'absent'; return; fi
        printf 'unreadable'; return
    fi
    if [[ ! -r "$p" ]]; then printf 'unreadable'; return; fi
    if [[ -d "$p" ]] && ! ls "$p" >/dev/null 2>&1; then printf 'unreadable'; return; fi
    printf 'readable'
}

# ---- Grants in .claude/settings.local.json ----------------------------------------------------------
# is_granted <path>: the path is, or lies under, an additionalDirectories entry in either settings file.
is_granted() {
    local p="$1" f e
    for f in "$SETTINGS_LOCAL" "$SETTINGS_SHARED"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r e; do
            [[ -n "$e" ]] || continue
            case "$e" in \~/*) e="$HOME/${e:2}" ;; esac
            while [[ "$e" == */ && "$e" != / ]]; do e="${e%/}"; done
            [[ "$p" == "$e" || "$p" == "$e"/* ]] && return 0
        done <<EOF
$(jq -r '(.permissions.additionalDirectories // []) | if type == "array" then .[] else empty end | strings' "$f" 2>/dev/null)
EOF
    done
    return 1
}

# grant <path>: appends the path to permissions.additionalDirectories. jq keeps the order of every
# existing key and list, so an allow list the person built up stays exactly as it was. The file is
# written only when the path is new, through a temporary file beside it.
grant() {
    local p="$1" src tmp
    if [[ -f "$SETTINGS_LOCAL" ]]; then src="$(cat "$SETTINGS_LOCAL")"; else src='{}'; fi
    if ! printf '%s' "$src" | jq -e 'type == "object" and ((.permissions // {}) | type == "object")
            and (((.permissions // {}).additionalDirectories // []) | type == "array")' >/dev/null 2>&1; then
        warn "cannot add $p: .claude/settings.local.json is not settings JSON this can merge into; add it to permissions.additionalDirectories by hand"
        FAILED=1
        return 1
    fi
    [[ $DRY -eq 1 ]] && return 0
    mkdir -p "$WS/.claude" || { FAILED=1; return 1; }
    tmp="$SETTINGS_LOCAL.link.$$"
    if printf '%s' "$src" | jq --arg p "$p" '.permissions.additionalDirectories += [$p]' > "$tmp" 2>/dev/null; then
        mv "$tmp" "$SETTINGS_LOCAL" || { FAILED=1; return 1; }
    else
        rm -f "$tmp"
        warn "cannot write .claude/settings.local.json; add $p to permissions.additionalDirectories by hand"
        FAILED=1
        return 1
    fi
}

# ---- Small writes, each made only when needed ------------------------------------------------------
# has_line <file> <line>: the file holds that exact line.
has_line() { [[ -f "$1" ]] && awk -v l="$2" '$0 == l { f = 1 } END { exit !f }' "$1"; }

# append_line <file> <line>: adds the line, first ending the file's last line when it has no newline.
append_line() {
    local f="$1"
    mkdir -p "$(dirname "$f")" || return 1
    if [[ -s "$f" && -n "$(tail -c 1 "$f")" ]]; then printf '\n' >> "$f" || return 1; fi
    printf '%s\n' "$2" >> "$f"
}

# exclude_in_nested <folder>: a project with a repository of its own keeps .resources/ out of that
# repository through its local info/exclude, which is never committed.
exclude_in_nested() {
    local dir="$1" ex
    # A gitlink's folder, or a standalone repository, has a .git of its own once it is checked out.
    [[ -e "$dir/.git" ]] || return 0
    ex="$(aw_git_elsewhere "$dir" rev-parse --git-path info/exclude 2>/dev/null)" || return 0
    [[ -n "$ex" ]] || return 0
    [[ "$ex" == /* ]] || ex="$dir/$ex"
    has_line "$ex" "/.resources/" && return 0
    [[ $DRY -eq 1 ]] && return 0
    append_line "$ex" "/.resources/"
}

# ---- The project folders ---------------------------------------------------------------------------
projects_config "$WS"

# expand_pattern <pattern>: the folders the pattern names, one per line. A <placeholder> segment is any
# one folder whose name does not start with "." or "_" (those are reserved).
expand_pattern() {
    local pattern="$1" seg d c nl=$'\n' cur="$WS" next
    local IFS=/
    # shellcheck disable=SC2206
    local -a segs=($pattern)
    IFS=$' \t\n'
    for seg in ${segs[@]+"${segs[@]}"}; do
        [[ -n "$seg" ]] || continue
        next=""
        while IFS= read -r d; do
            [[ -n "$d" ]] || continue
            case "$seg" in
                "<"*">")
                    for c in "$d"/*/; do
                        [[ -d "$c" ]] || continue
                        c="${c%/}"
                        case "${c##*/}" in .*|_*) continue ;; esac
                        next="${next:+$next$nl}$c"
                    done ;;
                *) [[ -d "$d/$seg" ]] && next="${next:+$next$nl}$d/$seg" ;;
            esac
        done <<EOF
$cur
EOF
        cur="$next"
        [[ -n "$cur" ]] || return 0
    done
    printf '%s\n' "$cur"
}

FOLDERS=()
while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    while IFS= read -r folder; do
        [[ -n "$folder" ]] || continue
        [[ -z "$SLUG" || "${folder##*/}" == "$SLUG" ]] || continue
        dup=0
        for f in ${FOLDERS[@]+"${FOLDERS[@]}"}; do [[ "$f" == "$folder" ]] && dup=1; done
        [[ $dup -eq 1 ]] || FOLDERS+=("$folder")
    done <<EOF
$(expand_pattern "$pattern")
EOF
done <<EOF
$PROJECT_PATTERNS
EOF

if [[ -n "$SLUG" && ${#FOLDERS[@]} -eq 0 ]]; then
    echo "link: no project folder named $SLUG" >&2
    exit 2
fi

# One record per resource, collected before anything is asked, so a question reads the terminal and
# not the list being walked: folder<US>slug<US>kind<US>name, kind being name, generated or ignored.
RECORDS=()
US=$'\037'
for folder in ${FOLDERS[@]+"${FOLDERS[@]}"}; do
    rec=""
    for f in "$ENTRY_POINT" README.md; do
        [[ -f "$folder/$f" ]] || continue
        rec="$(awk -v alias_outcome="$ALIAS_OUTCOME" -v alias_done="$ALIAS_DONE" -v alias_people="$ALIAS_PEOPLE" \
            -f "$README_AWK" "$folder/$f" 2>/dev/null | awk -F '\037' '{ print $18 "\037" $19 "\037" $20; exit }')"
        [[ "$rec" == "$US$US" ]] && rec=""
        [[ -n "$rec" ]] && break
    done
    [[ -n "$rec" ]] || continue
    IFS="$US" read -r names generated ignored _rest <<EOF
$rec
EOF
    slug="${folder##*/}"
    # An ignored name can hold any character, so the split is made with globbing off.
    old_ifs="$IFS"; IFS=,; set -f
    for n in $names; do
        kind=name
        case ",$generated," in *",$n,"*) kind=generated ;; esac
        RECORDS+=("$folder$US$slug$US$kind$US$n")
    done
    for n in $ignored; do RECORDS+=("$folder$US$slug${US}ignored$US$n"); done
    IFS="$old_ifs"; set +f
done

if [[ ${#RECORDS[@]} -eq 0 ]]; then
    if [[ -n "$SLUG" ]]; then echo "No resources named in $SLUG's README."; else echo "No project names a resource under ## Resources."; fi
    exit $FAILED
fi
[[ $DRY -eq 1 ]] && echo "Dry run — nothing written."

# link_one <folder> <slug> <name> <path>: the symlink, the grant and the nested exclude for one
# readable, mapped resource.
link_one() {
    local folder="$1" slug="$2" name="$3" p="$4" rel ln cur
    rel="${folder#"$WS"/}"
    ln="$folder/.resources/$name"
    if [[ -L "$ln" ]]; then
        cur="$(readlink "$ln")"
        if [[ "$cur" != "$p" && $DRY -eq 0 ]]; then ln -sfn "$p" "$ln" || { FAILED=1; return; }; fi
    elif [[ -e "$ln" ]]; then
        say_line kept "$slug/$name ($rel/.resources/$name is a real file or folder, left as it is)"
        return
    elif [[ $DRY -eq 0 ]]; then
        if ! mkdir -p "$folder/.resources" || ! ln -s "$p" "$ln"; then FAILED=1; return; fi
    fi
    exclude_in_nested "$folder"
    say_line linked "$slug/$name -> $p"
    if ! is_granted "$p" && grant "$p"; then
        say_line granted "$p"
        say_plain "For Cowork: Add folder $p (once per machine)"
    fi
}

# map_append <slug/name> <path>: a new line in .claude/resources.local.md, created with its header.
map_append() {
    if [[ ! -f "$LOCAL_MAP" ]]; then
        mkdir -p "$WS/.claude" || return 1
        # shellcheck disable=SC2016
        printf '%s\n' '# Resources on this machine' '' \
            'One line per project and name: `<slug>/<name>`, then the path. Never committed.' '' > "$LOCAL_MAP" || return 1
    fi
    append_line "$LOCAL_MAP" "$1  $2" || return 1
    MAP_KEYS+=("$1") MAP_PATHS+=("$2")
}

for r in "${RECORDS[@]}"; do
    IFS="$US" read -r folder slug kind name <<EOF
$r
EOF
    key="$slug/$name"
    if [[ "$kind" == ignored ]]; then
        say_line ignored "$key (a resource name is letters, digits, dot, dash, underscore)"
        continue
    fi
    if p="$(map_lookup "$key")"; then
        case "$(path_state "$p")" in
            absent) say_line missing "$key (mapped to $p; not on this machine now)" ;;
            unreadable) say_line no-permission "$key ($p)" ;;
            readable) link_one "$folder" "$slug" "$name" "$p" ;;
        esac
        continue
    fi
    if [[ "$kind" == generated ]]; then
        if ! has_line "$folder/.gitignore" "/$name/" && [[ $DRY -eq 0 ]]; then
            append_line "$folder/.gitignore" "/$name/" || FAILED=1
        fi
        say_line inside "$key (generated; kept out of git)"
        continue
    fi
    if attended && [[ $DRY -eq 0 ]]; then
        answer="$(ask "Path for $key on this machine (Enter to leave it unmapped)")"
        answer="${answer#"${answer%%[![:space:]]*}"}"
        answer="${answer%"${answer##*[![:space:]]}"}"
        if [[ -n "$answer" ]]; then
            if map_append "$key" "$answer" && p="$(map_lookup "$key")"; then
                case "$(path_state "$p")" in
                    absent) say_line missing "$key (mapped to $p; not on this machine now)" ;;
                    unreadable) say_line no-permission "$key ($p)" ;;
                    readable) link_one "$folder" "$slug" "$name" "$p" ;;
                esac
            else
                warn "cannot write .claude/resources.local.md"
                FAILED=1
            fi
            continue
        fi
    fi
    say_line unmapped "$key"
done

exit $FAILED
