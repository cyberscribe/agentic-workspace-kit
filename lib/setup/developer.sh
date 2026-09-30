#!/usr/bin/env bash
# lib/setup/developer.sh: kit/setup.sh --developer. Makes the workspace's kit/ a checkout the kit's
# developer works in: on main rather than a detached HEAD, tracking origin/main, with the settings that
# keep it there through pulls and updates. Running it again changes nothing.
#
#   developer.sh --target WS
#
# Steps:
#   1. git -C kit fetch origin (a note when offline).
#   2. kit/ onto main without moving any branch backwards: a new main at HEAD when there is none; main
#      checked out when it already contains HEAD; main fast-forwarded when HEAD is ahead of it. HEAD on
#      another branch, or main and HEAD diverged, stops. Then main tracks origin/main.
#   3. submodule.<kit name>.update=rebase and pull.rebase=true in the workspace; with a remote named
#      closeout in the kit, aw.mirror.closeout.prefix=plugins/closeout there, so the pre-push hook
#      checks the closeout mirror push against the right paths.
#   4. An https GitHub origin gets an ssh push URL (offered when attended; noted otherwise).
#   5. The git hooks (lib/setup/gitconfig.sh --hooks), so the kit's own pre-commit runs.
#   6. The private word list the kit's hooks check against, resolved as the hooks resolve it.
#
# Exit status: 0 done (left-open items are named), 1 stopped, 2 usage.
# shellcheck source-path=SCRIPTDIR/../..
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=lib/wizard.sh
. "$KIT/lib/wizard.sh"
# shellcheck source=lib/common.sh
. "$KIT/lib/common.sh"

WS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) [[ $# -ge 2 ]] || { echo "developer.sh: --target needs a folder" >&2; exit 2; }
            WS="$2"; shift 2 ;;
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "developer.sh: unknown option $1" >&2; exit 2 ;;
    esac
done
[[ "$WS" == /* ]] || { echo "developer.sh: --target takes the workspace's absolute path" >&2; exit 2; }

WG=(git --no-optional-locks -C "$WS")
KG=(git --no-optional-locks -C "$WS/kit")
if [[ "$("${WG[@]}" ls-files -s -- kit 2>/dev/null | awk '$1 == "160000" { print "y"; exit }')" != y ]] \
    || ! "${KG[@]}" rev-parse --git-dir >/dev/null 2>&1; then
    say "kit/ in $WS is not a checked-out submodule; developer mode works on the workspace's kit/."
    exit 1
fi
left=""
# setkey <where> <key> <value> <repository>: writes the key into that repository's local config only
# when its value differs, so a second run writes nothing.
setkey() {
    if [[ "$(git --no-optional-locks -C "$4" config --get "$2" 2>/dev/null)" == "$3" ]]; then
        step "ok   $1 $2=$3"
    else
        git --no-optional-locks -C "$4" config "$2" "$3" && step "set  $1 $2=$3"
    fi
}

# --- 1 · Fetch ---------------------------------------------------------------------------------------
url="$("${KG[@]}" remote get-url origin 2>/dev/null)"
pc=()
case "$url" in file://*) pc=(-c protocol.file.allow=always) ;; *://*) ;; *:*) [[ "${url%%:*}" == */* ]] && pc=(-c protocol.file.allow=always) ;; ?*) pc=(-c protocol.file.allow=always) ;; esac
if [[ -z "$url" ]]; then
    note "the kit has no origin remote; nothing fetched"
elif "${KG[@]}" ${pc[@]+"${pc[@]}"} fetch -q origin 2>/dev/null; then
    step "fetched origin"
else
    note "could not fetch origin (offline?); going on with what this clone already has"
fi

# --- 2 · kit/ on main --------------------------------------------------------------------------------
head="$("${KG[@]}" rev-parse HEAD)"
branch="$("${KG[@]}" symbolic-ref -q --short HEAD 2>/dev/null)"
main="$("${KG[@]}" rev-parse -q --verify refs/heads/main 2>/dev/null)"
if [[ -n "$branch" && "$branch" != main ]]; then
    say "kit/ is on the branch $branch. The kit is developed on main only: commit or move that work, then"
    say "check out main in kit/ and run this again."
    exit 1
elif [[ "$branch" == main ]]; then
    step "ok   kit/ is on main"
elif [[ -z "$main" ]]; then
    "${KG[@]}" checkout -q -b main "$head" && step "made main at $(printf '%.7s' "$head") and checked it out"
elif "${KG[@]}" merge-base --is-ancestor "$head" "$main" 2>/dev/null; then
    "${KG[@]}" checkout -q main && step "checked out main ($(printf '%.7s' "$main")), which already holds $(printf '%.7s' "$head")"
elif "${KG[@]}" merge-base --is-ancestor "$main" "$head" 2>/dev/null; then
    "${KG[@]}" checkout -q main && "${KG[@]}" merge -q --ff-only "$head" \
        && step "checked out main and moved it forward from $(printf '%.7s' "$main") to $(printf '%.7s' "$head")"
else
    say "kit/ is at $(printf '%.7s' "$head") and its main is at $(printf '%.7s' "$main"); neither contains the other."
    say "Moving either would lose commits. Decide which to keep, put main there by hand, and run this again."
    say "Both sides:  git -C kit log --oneline main...$head"
    exit 1
fi
[[ "$("${KG[@]}" symbolic-ref -q --short HEAD 2>/dev/null)" == main ]] || { say "kit/ could not be put on main."; exit 1; }
if "${KG[@]}" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1; then
    if [[ "$("${KG[@]}" rev-parse --abbrev-ref 'main@{upstream}' 2>/dev/null)" == origin/main ]]; then
        step "ok   main tracks origin/main"
    else
        "${KG[@]}" branch -q --set-upstream-to=origin/main main && step "set  main to track origin/main"
    fi
else
    note "the kit's origin has no main branch fetched here; main tracks nothing yet"
    left+="main tracks nothing (fetch origin, then run kit/setup.sh --developer again); "
fi

# --- 3 · Settings ------------------------------------------------------------------------------------
name="$(aw_kitname "$WS")"
[[ -n "$name" ]] || name=kit
setkey workspace "submodule.$name.update" rebase "$WS"
setkey workspace pull.rebase true "$WS"
if "${KG[@]}" remote get-url closeout >/dev/null 2>&1; then
    setkey kit aw.mirror.closeout.prefix plugins/closeout "$WS/kit"
fi

# --- 4 · Push over ssh ------------------------------------------------------------------------------
case "$url" in
    https://github.com/*/*)
        if [[ -z "$("${KG[@]}" config --get remote.origin.pushurl 2>/dev/null)" ]]; then
            r="${url#https://github.com/}"; r="${r%.git}"; r="${r%/}"
            if attended && confirm "Push to origin over ssh (git@github.com:$r.git), keeping fetches over https?" y; then
                "${KG[@]}" remote set-url --push origin "git@github.com:$r.git" && step "set  kit push URL git@github.com:$r.git"
            else
                note "pushes to origin go over https; to push over ssh: git -C kit remote set-url --push origin git@github.com:$r.git"
            fi
        fi ;;
esac

# --- 5 · Hooks ---------------------------------------------------------------------------------------
if ! "${BASH:-bash}" "$KIT/lib/setup/gitconfig.sh" --target "$WS" --hooks 2>&1 | sed 's/^/  /'; then
    left+="the git hooks were not all set (kit/setup.sh hooks); "
fi

# --- 6 · Private word list -------------------------------------------------------------------------
wl="$(aw_word_list "$WS" 2>/dev/null)"; wrc=$?
if [[ $wrc -eq 2 ]]; then
    left+="the private word list named for this workspace cannot be used (unreadable, or inside kit/); "
elif [[ -z "$wl" ]]; then
    left+="no private word list: set one in .claude/workspace.md or ~/.config/agentic-workspace-kit/banned-words.txt; "
else
    step "ok   a private word list resolves; the kit's hooks check commits against it"
fi

# --- 7 · Done ----------------------------------------------------------------------------------------
echo
say "kit/ is on main, tracking origin/main. Commit and push inside kit/, then commit the pointer here"
say "(git add kit). A reset --hard or checkout in the workspace also resets kit/; commit kit work first."
if [[ -n "$left" ]]; then
    echo
    say "  -> left open (${left%; })"
fi
exit 0
