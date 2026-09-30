#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# lib/setup/gitconfig.sh: the git settings the kit keeps in a workspace, in two parts.
#
#   --hooks       writes the hook stub (githooks/stub.sh) into <git dir>/aw-hooks/ of the workspace, the
#                 kit, and each project repository (gitlinks and standalone repositories in project
#                 folders), and points core.hooksPath there. A hooks path already in effect is kept as
#                 aw.chainHooksPath, and the kit's hooks run it after their own checks. With --repo
#                 PATH, only that repository.
#   --submodules  push.recurseSubmodules=check, status.submoduleSummary=true, submodule.recurse=true
#                 (held when the workspace has a submodule outside the kit's concern, unless --recurse),
#                 and submodule.<name>.update=rebase for each project submodule.
#
# With neither, --hooks. Every key is written only when its value differs, and every stub only when
# its content differs, so a second run changes nothing. Output: "set <repo> <key>=<value>" or
# "ok <repo> <key>". --check prints the same and exits 1 when anything would be set, writing nothing.
#
# Run from setup.sh (stages 4 and 5, kit/setup.sh hooks), from the migration and from developer mode.
# --target is the workspace root; a kit checkout of its own (a contributor's clone) is also accepted,
# and then only the kit's hooks are set. --kit-at PATH names the kit checkout when it is not at kit/ yet
# (the migration's dry run, before the kit moves): it is looked after, and named, as kit.
#
# Exit codes: 0 ok, 1 stopped (not a repository), 2 usage.

set -uo pipefail

usage() {
    cat <<'EOF'
Usage: lib/setup/gitconfig.sh --target WS [--hooks] [--submodules] [--repo PATH] [--check] [--recurse]
                              [--kit-at PATH]
EOF
}

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=../common.sh
. "$KIT/lib/common.sh"

target="" do_hooks=0 do_subs=0 repo_only="" check=0 recurse=0 kit_at="kit"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; target="$2"; shift 2 ;;
        --hooks) do_hooks=1; shift ;;
        --submodules) do_subs=1; shift ;;
        --repo) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; repo_only="$2"; do_hooks=1; shift 2 ;;
        --check) check=1; shift ;;
        --recurse) recurse=1; shift ;;
        --kit-at) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; kit_at="${2%/}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ -n "$target" ]] || { usage >&2; exit 2; }
[[ $do_hooks -eq 0 && $do_subs -eq 0 ]] && do_hooks=1
[[ -d "$target" ]] || { echo "gitconfig.sh: no folder at $target" >&2; exit 1; }
WS="$(cd "$target" && pwd -P)"
aw_git_elsewhere "$WS" rev-parse --git-dir >/dev/null 2>&1 || { echo "gitconfig.sh: $WS is not a git repository" >&2; exit 1; }

changed=0
case "$kit_at" in ''|/*|*..*) usage >&2; exit 2 ;; esac
KITDIR="$WS/$kit_at"

# label <repo dir>: the repository as the output names it, relative to the workspace.
label() {
    if [[ "$1" == "$WS" ]]; then printf '.'
    elif [[ "$1" == "$KITDIR" || "$1" == "$(cd "$KITDIR" 2>/dev/null && pwd -P)" ]]; then printf 'kit'
    else printf '%s' "${1#"$WS"/}"; fi
}

# setkey <repo dir> <key> <value>: sets a local key when its effective value differs.
setkey() {
    local r="$1" k="$2" v="$3" cur
    cur="$(aw_git_elsewhere "$r" config --get "$k" 2>/dev/null)"
    if [[ "$cur" == "$v" ]]; then printf 'ok %s %s\n' "$(label "$r")" "$k"; return 0; fi
    printf 'set %s %s=%s\n' "$(label "$r")" "$k" "$v"
    changed=1
    [[ $check -eq 1 ]] && return 0
    aw_git_elsewhere "$r" config --local "$k" "$v"
}

# A kit checkout of its own: only the kit is looked after.
standalone_kit=0
if grep -q '"agentic-workspace"' "$WS/.claude-plugin/marketplace.json" 2>/dev/null && [[ -f "$WS/githooks/stub.sh" ]]; then
    standalone_kit=1
fi

PATTERNS=""
if [[ $standalone_kit -eq 0 ]]; then
    cfg="$KIT/plugins/projects/hooks/lib/config.sh"
    if [[ -f "$cfg" ]]; then
        # shellcheck source=../../plugins/projects/hooks/lib/config.sh
        . "$cfg"
        projects_config "$WS"
        PATTERNS="$PROJECT_PATTERNS"
    fi
fi

# is_project_path <path>: 0 when the workspace-relative path is itself a project folder.
is_project_path() {
    local pat m
    while IFS= read -r pat; do
        [[ -n "$pat" ]] || continue
        m="$(projects_match "$pat" "$1")"
        [[ -n "$m" && "$m" == "$1" ]] && return 0
    done <<EOF
$PATTERNS
EOF
    return 1
}

# The submodules: name<TAB>path, from .gitmodules.
submodules() {
    [[ -f "$WS/.gitmodules" ]] || return 0
    aw_git_elsewhere "$WS" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | while read -r k p; do
        k="${k#submodule.}"
        printf '%s\t%s\n' "${k%.path}" "$p"
    done
}

# ---- Hooks ---------------------------------------------------------------------------------------

# hooks_for <repo dir>: the stubs and core.hooksPath in one repository.
hooks_for() {
    local r="$1" gd dir n cur chain want
    gd="$(aw_git_elsewhere "$r" rev-parse --absolute-git-dir 2>/dev/null)" || { printf 'skip %s (not a git repository)\n' "$(label "$r")"; return 0; }
    dir="$gd/aw-hooks"
    want=0
    for n in pre-commit pre-merge-commit commit-msg pre-push; do
        cmp -s "$KIT/githooks/stub.sh" "$dir/$n" 2>/dev/null && [[ -x "$dir/$n" ]] && continue
        want=1
    done
    if [[ $want -eq 0 ]]; then
        printf 'ok %s aw-hooks\n' "$(label "$r")"
    else
        printf 'set %s aw-hooks=%s\n' "$(label "$r")" "$dir"
        changed=1
        if [[ $check -eq 0 ]]; then
            mkdir -p "$dir" || { echo "gitconfig.sh: cannot write $dir" >&2; exit 1; }
            for n in pre-commit pre-merge-commit commit-msg pre-push; do
                cmp -s "$KIT/githooks/stub.sh" "$dir/$n" 2>/dev/null || cat "$KIT/githooks/stub.sh" > "$dir/$n"
                chmod 755 "$dir/$n"
            done
        fi
    fi
    # A hooks path already in effect (a repository's own, or a global one such as a push guard) is kept
    # so the kit's hooks can run it after their own checks. An older stub folder is not kept: it is ours.
    cur="$(aw_git_elsewhere "$r" config --get core.hooksPath 2>/dev/null)"
    if [[ -n "$cur" && "$cur" != "$dir" && "${cur%/}" != */aw-hooks ]]; then
        chain="$(aw_git_elsewhere "$r" config --local --get aw.chainHooksPath 2>/dev/null)"
        if [[ "$chain" == "$cur" ]]; then
            printf 'ok %s aw.chainHooksPath\n' "$(label "$r")"
        else
            printf 'set %s aw.chainHooksPath=%s\n' "$(label "$r")" "$cur"
            changed=1
            [[ $check -eq 1 ]] || aw_git_elsewhere "$r" config --local aw.chainHooksPath "$cur"
        fi
    fi
    setkey "$r" core.hooksPath "$dir"
}

if [[ $do_hooks -eq 1 ]]; then
    if [[ -n "$repo_only" ]]; then
        [[ "$repo_only" == /* ]] || repo_only="$WS/$repo_only"
        [[ -d "$repo_only" ]] || { echo "gitconfig.sh: no folder at $repo_only" >&2; exit 1; }
        hooks_for "$(cd "$repo_only" && pwd -P)"
    elif [[ $standalone_kit -eq 1 ]]; then
        hooks_for "$WS"
    else
        hooks_for "$WS"
        if [[ -e "$KITDIR/.git" ]]; then hooks_for "$KITDIR"
        elif [[ -d "$KITDIR" ]]; then printf 'skip kit (not initialised: git submodule update --init kit)\n'
        fi
        # Project repositories: gitlinks in project folders, then standalone repositories there.
        seen="|"
        while IFS=$'\t' read -r name path; do
            [[ -n "$path" ]] || continue
            is_project_path "$path" || continue
            seen+="$path|"
            if [[ -e "$WS/$path/.git" ]]; then hooks_for "$WS/$path"
            else printf 'skip %s (not initialised)\n' "$path"; fi
            : "$name"
        done <<EOF
$(submodules)
EOF
        while IFS= read -r pat; do
            [[ -n "$pat" ]] || continue
            glob="$(printf '%s' "$pat" | sed -e 's/<[^>]*>/*/g')"
            for d in "$WS"/$glob; do
                [[ -d "$d" && -e "$d/.git" ]] || continue
                rel="${d#"$WS"/}"
                case "$seen" in *"|$rel|"*) continue ;; esac
                is_project_path "$rel" || continue
                seen+="$rel|"
                hooks_for "$(cd "$d" && pwd -P)"
            done
        done <<EOF
$PATTERNS
EOF
    fi
fi

# ---- Submodules ----------------------------------------------------------------------------------

if [[ $do_subs -eq 1 && $standalone_kit -eq 0 ]]; then
    setkey "$WS" push.recurseSubmodules check
    setkey "$WS" status.submoduleSummary true
    kitname="$(aw_kitname "$WS")"
    outside=""
    while IFS=$'\t' read -r name path; do
        [[ -n "$path" ]] || continue
        if [[ "$path" == kit || "$path" == "$kit_at" || ( -n "$kitname" && "$name" == "$kitname" ) ]]; then continue; fi
        if is_project_path "$path"; then
            setkey "$WS" "submodule.$name.update" rebase
        else
            outside="${outside:+$outside, }$path"
        fi
    done <<EOF
$(submodules)
EOF
    if [[ -n "$outside" && $recurse -eq 0 ]]; then
        if [[ "$(aw_git_elsewhere "$WS" config --get submodule.recurse 2>/dev/null)" == true ]]; then
            printf 'ok . submodule.recurse\n'
        else
            printf 'held submodule.recurse: %s are outside the kit'"'"'s concern and are committed in directly; setting it is the person'"'"'s call (git config submodule.recurse true)\n' "$outside"
        fi
    else
        setkey "$WS" submodule.recurse true
    fi
fi

if [[ $check -eq 1 && $changed -eq 1 ]]; then exit 1; fi
exit 0
