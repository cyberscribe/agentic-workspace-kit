#!/usr/bin/env bash
# scripts/build-template.sh: builds the template repository, the starting point a new workspace is
# made from with GitHub's "Use this template". It is produced from templates/workspace/ by this script
# rather than kept by hand, so it cannot drift from what kit/setup.sh new creates.
#
#   scripts/build-template.sh OUT [--kit-url URL] [--kit-from URL] [--workspace WS]
#
#   OUT             a new or empty folder (or one holding only a .git with no commit, where an
#                   earlier build stopped); it becomes a repository with one commit on main
#   --kit-url URL   the kit URL written into .gitmodules, in its https form (default: AW_KIT_URL, else
#                   this checkout's origin, else the kit's GitHub URL)
#   --kit-from URL  where the kit is cloned from while building (default: the kit URL); the gitlink
#                   records that clone's main, so the commit it names has to be on the kit's remote
#                   before the template is pushed
#   --workspace WS  the workspace whose names the output is checked against (default: the repository
#                   this kit checkout is a submodule of, when there is one)
#
# What it does:
#   - runs git with HOME, the global git config and the template folder pointed at empty temporary
#     folders, so no name, email, setting or sample hook from this machine reaches the output;
#   - git init -b main OUT, then git submodule add -b main <kit url> kit;
#   - kit/install.sh --stand-ins renders the starter files with their angle-bracketed stand-ins, which
#     the engine replaces with the team's answers when kit/setup.sh runs in a workspace made from it;
#   - a .gitkeep in projects/, memory/, docs/, logs/ and skills/;
#   - checks the exact file list (no ledger, no .claude/workspace.md, no settings.local.json);
#   - checks every file and path against the private word list (resolved as the kit's hooks resolve
#     it) and, with a workspace, against that workspace's own names: project folders, people, repository
#     names, its path, the home folder and the git email, each skipped when the kit already carries it;
#     a word is never printed, only its kind, file and line;
#   - makes one commit on main as "agentic workspace kit <kit@invalid>".
#
# Exit status: 0 built, 1 stopped (nothing committed), 2 usage.
# shellcheck source-path=SCRIPTDIR/..
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=lib/common.sh
. "$KIT/lib/common.sh"
DEFAULT_KIT_URL="https://github.com/cyberscribe/agentic-workspace-kit.git"

OUT="" URL="" FROM="" WSX="" WSX_SET=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kit-url|--kit-from|--workspace)
            [[ $# -ge 2 ]] || { echo "build-template.sh: $1 needs a value" >&2; exit 2; }
            case "$1" in --kit-url) URL="$2" ;; --kit-from) FROM="$2" ;; --workspace) WSX="$2"; WSX_SET=1 ;; esac
            shift 2 ;;
        -h|--help) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "build-template.sh: unknown option $1" >&2; exit 2 ;;
        *) [[ -z "$OUT" ]] || { echo "build-template.sh: one output folder only" >&2; exit 2; }
            OUT="$1"; shift ;;
    esac
done
[[ -n "$OUT" ]] || { echo "usage: scripts/build-template.sh OUT [--kit-url URL] [--kit-from URL] [--workspace WS]" >&2; exit 2; }
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
# A folder holding only a .git with no commit (a build that stopped before its commit) is taken as empty:
# git init picks it up again.
if [[ -e "$OUT" && -n "$(ls -A "$OUT" 2>/dev/null)" ]]; then
    # The git directory is compared first: an unfinished .git is not a repository to git, which then
    # finds the one around OUT instead.
    if [[ "$(ls -A "$OUT")" != .git ]] \
        || { [[ "$(git --no-optional-locks -C "$OUT" rev-parse --absolute-git-dir 2>/dev/null)" == "$(cd "$OUT" && pwd -P)/.git" ]] \
            && git --no-optional-locks -C "$OUT" rev-parse -q --verify HEAD >/dev/null 2>&1; }; then
        echo "build-template.sh: $OUT is not empty; name a new or empty folder" >&2; exit 1
    fi
fi

# is_local_url <url>: a path or file:// URL.
is_local_url() {
    case "$1" in file://*) return 0 ;; *://*) return 1 ;; esac
    local lhs="${1%%:*}"
    [[ "$1" == *:* && "$lhs" != */* && -n "$lhs" ]] && return 1
    return 0
}
[[ -n "$URL" ]] || URL="${AW_KIT_URL:-}"
[[ -n "$URL" ]] || URL="$(git --no-optional-locks -C "$KIT" remote get-url origin 2>/dev/null)"
[[ -n "$URL" ]] || URL="$DEFAULT_KIT_URL"
if is_local_url "$URL"; then
    [[ "$URL" == /* || "$URL" == file://* || ! -d "$URL" ]] || URL="$(cd "$URL" && pwd -P)"
else
    # Whoever clones the template may have no ssh key for GitHub, so the https form goes in .gitmodules.
    URL="https://$(aw_norm_url "$URL").git"
fi
[[ -n "$FROM" ]] || FROM="$URL"
if is_local_url "$FROM" && [[ "$FROM" != /* && "$FROM" != file://* && -d "$FROM" ]]; then FROM="$(cd "$FROM" && pwd -P)"; fi
if [[ $WSX_SET -eq 0 ]]; then
    WSX="$(git --no-optional-locks -C "$KIT" rev-parse --show-superproject-working-tree 2>/dev/null)"
fi
[[ -z "$WSX" ]] || WSX="$(cd "$WSX" && pwd -P)" || { echo "build-template.sh: no folder at $WSX" >&2; exit 2; }

# --- What the output is checked against, worked out before git loses this machine's settings ---------
work="$(mktemp -d "${TMPDIR:-/tmp}/aw-template.XXXXXX")" || { echo "build-template.sh: no temporary folder" >&2; exit 1; }
words=""
wl="$(aw_word_list "$WSX")" || { echo "build-template.sh: the private word list cannot be used; nothing built" >&2; exit 1; }
if [[ -n "$wl" ]]; then
    words="$work/words"
    # Blank and comment lines are left out: an empty pattern would match every line.
    grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$wl" >"$words" 2>/dev/null
    [[ -s "$words" ]] || words=""
else
    echo "note: no private word list; the word check did not run"
fi
ids="$work/ids"
: >"$ids"
if [[ -n "$WSX" ]]; then
    # id <kind> <value>: one identifier of the workspace, kept unless the kit already names it.
    may_name="$(awk '/^[ \t]*[-*][ \t]+\*\*Kit may name:\*\*/ { if (match($0, /`[^`]+`/)) print substr($0, RSTART + 1, RLENGTH - 2); exit }' \
        "$WSX/.claude/workspace.md" 2>/dev/null | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    id() {
        [[ -n "$2" ]] || return 0
        printf '%s\n' "$may_name" | grep -q -i -x -F -e "$2" && return 0
        git --no-optional-locks -C "$KIT" grep -q -i -w -F -e "$2" HEAD -- 2>/dev/null && return 0
        printf '%s\t%s\n' "$1" "$2" >>"$ids"
    }
    # Project folders, by the conventions' patterns; names of four characters or more.
    if [[ -f "$KIT/plugins/projects/hooks/lib/config.sh" ]]; then
        # shellcheck source=plugins/projects/hooks/lib/config.sh
        . "$KIT/plugins/projects/hooks/lib/config.sh"
        projects_config "$WSX"
        while IFS= read -r pat; do
            [[ -n "$pat" ]] || continue
            glob="$(printf '%s' "$pat" | sed 's/<[^>]*>/*/g')"
            for d in "$WSX"/$glob; do
                [[ -d "$d" ]] || continue
                n="${d##*/}"
                case "$n" in _*|.*) continue ;; esac
                [[ ${#n} -ge 4 ]] && id "a project name" "$n"
            done
        done <<EOF
$PROJECT_PATTERNS
EOF
    fi
    for f in "$WSX"/memory/people/*.md; do
        [[ -f "$f" ]] || continue
        n="${f##*/}"; n="${n%.md}"
        [[ "$n" == README ]] || id "a person's name" "$n"
    done
    o="$(aw_norm_url "$(git --no-optional-locks -C "$WSX" remote get-url origin 2>/dev/null)")"
    case "$o" in ""|local:*) ;; *) id "a repository name" "${o#*/}" ;; esac
    kitname="$(aw_kitname "$WSX")"
    while read -r key value; do
        [[ "$key" == "submodule.$kitname.url" ]] && continue
        o="$(aw_norm_url "$value")"
        case "$o" in ""|local:*) ;; *) id "a repository name" "${o#*/}" ;; esac
    done <<EOF
$(git --no-optional-locks config -f "$WSX/.gitmodules" --get-regexp '^submodule\..*\.url$' 2>/dev/null)
EOF
    id "the home folder" "$HOME"
    id "the workspace path" "$WSX"
    id "the git email" "$(git --no-optional-locks -C "$WSX" config user.email 2>/dev/null)"
fi

# --- Build, with no identity from this machine ------------------------------------------------------
# An empty template folder too, so no sample hooks or other files from this machine's git reach .git.
export HOME="$work/empty-home" GIT_CONFIG_GLOBAL="$work/empty-home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    GIT_TEMPLATE_DIR="$work/empty-template"
mkdir -p "$HOME" "$GIT_TEMPLATE_DIR"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL \
    GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX
OG=(git --no-optional-locks -C "$OUT")
mkdir -p "$OUT" || exit 1
if ! git --no-optional-locks init -q -b main "$OUT" >/dev/null 2>&1; then
    { git --no-optional-locks init -q "$OUT" && "${OG[@]}" symbolic-ref HEAD refs/heads/main; } || exit 1
fi
pc=(); is_local_url "$FROM" && pc=(-c protocol.file.allow=always)
"${OG[@]}" ${pc[@]+"${pc[@]}"} submodule add -q -b main "$FROM" kit >/dev/null 2>&1 \
    || { echo "build-template.sh: git submodule add -b main $FROM kit did not finish" >&2; exit 1; }
if [[ "$FROM" != "$URL" ]]; then
    "${OG[@]}" config -f .gitmodules submodule.kit.url "$URL" && "${OG[@]}" submodule sync -q -- kit >/dev/null \
        && "${OG[@]}" add .gitmodules || exit 1
fi
if ! out="$("${BASH:-bash}" "$OUT/kit/install.sh" --stand-ins --target "$OUT" 2>&1)"; then
    printf '%s\n' "$out" | tail -n 6 >&2
    echo "build-template.sh: kit/install.sh --stand-ins did not finish; nothing committed" >&2
    exit 1
fi
for d in projects memory docs logs skills; do
    mkdir -p "$OUT/$d" && : >"$OUT/$d/.gitkeep"
done
"${OG[@]}" add -A || exit 1

# --- Checks -----------------------------------------------------------------------------------------
refused=0
expected=".claude/closeout.md
.claude/projects.md
.claude/settings.json
.github/CODEOWNERS
.github/pull_request_template.md
.github/workflows/stay-private.yml
.gitignore
.gitmodules
AGENTS.md
CLAUDE.md
README.md
audits/README.md
docs/.gitkeep
docs/workspace-map.md
kit
logs/.gitkeep
logs/decisions.md
memory/.gitkeep
memory/glossary.md
memory/people/README.md
projects/.gitkeep
projects/INDEX.md
skills/.gitkeep"
actual="$("${OG[@]}" ls-files | LC_ALL=C sort)"
expected="$(printf '%s\n' "$expected" | LC_ALL=C sort)"
if [[ "$actual" != "$expected" ]]; then
    echo "build-template.sh: the file list is not the template's:" >&2
    printf '%s\n' "$expected" >"$work/expected"; printf '%s\n' "$actual" >"$work/actual"
    diff "$work/expected" "$work/actual" | sed -n 's/^</  missing /p; s/^>/  extra   /p' >&2
    refused=1
fi
while IFS= read -r f; do
    [[ "$f" == kit ]] && continue
    if [[ -n "$words" ]]; then
        printf '%s\n' "$f" | grep -q -i -w -F -f "$words" && { printf 'refused\t%s\tprivate word (path)\n' "$f"; refused=1; }
        while IFS=: read -r n _; do
            [[ -n "$n" ]] && { printf 'refused\t%s\tprivate word (line %s)\n' "$f" "$n"; refused=1; }
        done <<EOF
$(grep -n -i -w -F -f "$words" "$OUT/$f" 2>/dev/null)
EOF
    fi
    while IFS=$'\t' read -r kind value; do
        [[ -n "$value" ]] || continue
        printf '%s\n' "$f" | grep -q -i -w -F -e "$value" && { printf 'refused\t%s\tnames %s of the workspace (path)\n' "$f" "$kind"; refused=1; }
        while IFS=: read -r n _; do
            [[ -n "$n" ]] && { printf 'refused\t%s\tnames %s of the workspace (line %s)\n' "$f" "$kind" "$n"; refused=1; }
        done <<EOF
$(grep -n -i -w -F -e "$value" "$OUT/$f" 2>/dev/null)
EOF
    done <"$ids"
done <<EOF
$actual
EOF
[[ -n "$WSX" ]] || echo "note: no workspace around this kit checkout; the workspace-name check did not run"
if [[ $refused -ne 0 ]]; then
    echo "build-template.sh: stopped; nothing committed in $OUT" >&2
    exit 1
fi

# --- The one commit ---------------------------------------------------------------------------------
"${OG[@]}" -c user.name="agentic workspace kit" -c user.email="kit@invalid" -c commit.gpgsign=false \
    commit -q -m "The agentic workspace template" || { echo "build-template.sh: the commit did not finish" >&2; exit 1; }
echo "Built $OUT: one commit on main ($("${OG[@]}" rev-parse --short HEAD)), the kit at $("${OG[@]}" rev-parse --short HEAD:kit) from $URL."
echo "The kit commit it names has to be on the kit's remote before this is pushed."
exit 0
