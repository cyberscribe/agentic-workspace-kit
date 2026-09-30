# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# githooks/lib/common.sh: what the kit's git hooks share. Sourced by githooks/pre-commit,
# pre-merge-commit, commit-msg and pre-push, never run.
#
# A hook here decides three things in turn:
#   1. its context: the kit's own repository, the workspace around it, or a project repository
#      inside the workspace (an own-repo project, or a standalone repository in a project folder);
#   2. that context's checks, each ending allowed, refused or could-not-run (which refuses);
#   3. the user's own hook of the same name, run afterwards with the same arguments and stdin, since
#      a local core.hooksPath would otherwise retire it without a word.
#
# Written for bash 3.2. No jq: GUI git clients run hooks with a minimal PATH, which is also why the
# usual tool folders are put on PATH here when they are missing from it.

for awh_d in /usr/local/bin /opt/homebrew/bin; do
    case ":$PATH:" in *":$awh_d:"*) ;; *) [[ -d "$awh_d" ]] && PATH="$awh_d:$PATH" ;; esac
done
export PATH
unset awh_d

AWH_KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=../../lib/common.sh
. "$AWH_KIT_ROOT/lib/common.sh" || return 1

AWH_NAME="" AWH_CONTEXT="" AWH_TOP="" AWH_WS="" AWH_TMP=""
AWH_ARGS=()
AWH_ITEMS=()     # one line per refused item, printed under the refusal heading

# awh_start <hook name> "$@": buffers stdin, finds the context. Refuses (exit 1) when either fails.
awh_start() {
    AWH_NAME="$1"; shift
    AWH_ARGS=("$@")
    local t
    for t in git awk sed; do
        command -v "$t" >/dev/null 2>&1 || awh_die "could-not-run: $t is not on PATH"
    done
    AWH_TMP="$(mktemp -d "${TMPDIR:-/tmp}/aw-hook.XXXXXX" 2>/dev/null)" \
        || awh_die "could-not-run: cannot create a temporary folder under ${TMPDIR:-/tmp}"
    # shellcheck disable=SC2064
    trap "rm -rf '$AWH_TMP'" EXIT
    # stdin is read once, here, before any check: pre-push receives its ref list on it, and both the
    # kit's checks and the chained hook read this copy.
    if [[ -t 0 ]]; then : > "$AWH_TMP/stdin"; else cat > "$AWH_TMP/stdin"; fi
    awh_context || awh_die "could-not-run: this is not inside a git repository"
}

# awh_nothing: the closing word of a refusal.
awh_nothing() { if [[ "$AWH_NAME" == pre-push ]]; then printf 'Nothing was pushed.'; else printf 'Nothing was committed.'; fi; }

# awh_die <reason>: refuse at once with one reason.
awh_die() {
    printf 'aw %s: %s\n%s\n' "${AWH_NAME:-hook}" "$1" "$(awh_nothing)" >&2
    exit 1
}

# The hook scripts read AWH_CONTEXT.
# shellcheck disable=SC2034
# awh_context: sets AWH_TOP, AWH_CONTEXT (kit, workspace or project) and AWH_WS (the workspace root,
# possibly empty for a standalone kit clone).
awh_context() {
    local top d
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
    [[ -n "$top" && -d "$top" ]] || return 1
    AWH_TOP="$(cd "$top" && pwd -P)"
    if [[ "$AWH_TOP" == "$AWH_KIT_ROOT" ]]; then
        AWH_CONTEXT=kit
        AWH_WS="$(git rev-parse --show-superproject-working-tree 2>/dev/null)"
        [[ -n "$AWH_WS" && -d "$AWH_WS" ]] && AWH_WS="$(cd "$AWH_WS" && pwd -P)"
    elif [[ -d "$AWH_TOP/kit" && "$(cd "$AWH_TOP/kit" && pwd -P)" == "$AWH_KIT_ROOT" ]]; then
        AWH_CONTEXT=workspace
        AWH_WS="$AWH_TOP"
    else
        AWH_CONTEXT=project
        AWH_WS=""
        d="$(dirname "$AWH_TOP")"
        while :; do
            if [[ -d "$d/kit" && "$(cd "$d/kit" && pwd -P)" == "$AWH_KIT_ROOT" ]]; then AWH_WS="$d"; break; fi
            [[ "$d" == / ]] && break
            d="$(dirname "$d")"
        done
    fi
    return 0
}

# awh_item <text>: one refused item.
awh_item() { AWH_ITEMS+=("$1"); }

# awh_checkpaths <args...>: runs scripts/check-paths.sh and turns its findings into items. Its notes
# pass through on stderr.
awh_checkpaths() {
    local out st kind what why
    out="$("$BASH" "$AWH_KIT_ROOT/scripts/check-paths.sh" "$@" 2>"$AWH_TMP/cp.err")"; st=$?
    grep -v '^check-paths: ' "$AWH_TMP/cp.err" >&2
    if [[ $st -eq 0 ]]; then return 0; fi
    if [[ $st -ne 1 || -z "$out" ]]; then
        awh_item "could-not-run: scripts/check-paths.sh stopped (exit $st): $(grep -v '^note: ' "$AWH_TMP/cp.err" | head -n 1)"
        return 1
    fi
    while IFS=$'\t' read -r kind what why; do
        case "$kind" in
            refused) awh_item "$what — $why" ;;
            could-not-run) awh_item "could-not-run: $what — $why" ;;
        esac
    done <<EOF
$out
EOF
    return 1
}

# awh_verdict: when anything was refused, prints the refusal and exits 1; otherwise returns.
awh_verdict() {
    local n=${#AWH_ITEMS[@]} i
    [[ $n -gt 0 ]] || return 0
    printf 'aw %s: refused %s item(s)\n' "$AWH_NAME" "$n" >&2
    for i in "${AWH_ITEMS[@]}"; do printf '  %s\n' "$i" >&2; done
    printf '%s\n' "$(awh_nothing)" >&2
    exit 1
}

# awh_chain: runs the user's own hook of the same name, after the kit's checks have passed, and exits
# with its status (0 when there is none). The hook is the one in aw.chainHooksPath (the hooks path that
# was in effect before the kit set its own; relative to the repository's top), else the one in the
# repository's own hooks folder. It is skipped when it is missing, not executable, this hook itself, or
# one of the kit's stubs. AW_HOOK_CHAIN_DEPTH stops a chain that comes back round at 3.
awh_chain() {
    local depth="${AW_HOOK_CHAIN_DEPTH:-0}" dir cand real
    [[ "$depth" =~ ^[0-9]+$ ]] || depth=0
    if [[ $depth -ge 3 ]]; then
        printf 'aw %s: the hook chain has come round %s times; the rest of it did not run.\n' "$AWH_NAME" "$depth" >&2
        exit 0
    fi
    dir="$(git config --local --path --get aw.chainHooksPath 2>/dev/null)"
    if [[ -n "$dir" ]]; then
        [[ "$dir" == /* ]] || dir="$AWH_TOP/$dir"
    else
        dir="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
        [[ "$dir" == /* ]] || dir="$PWD/$dir"
        dir="$dir/hooks"
    fi
    cand="$dir/$AWH_NAME"
    [[ -f "$cand" && -x "$cand" ]] || exit 0
    [[ "$cand" -ef "$0" ]] && exit 0
    real="$(cd "$(dirname "$cand")" && pwd -P)"
    case "$real" in */aw-hooks) exit 0 ;; esac
    AW_HOOK_CHAIN_DEPTH=$((depth + 1)) "$cand" ${AWH_ARGS[@]+"${AWH_ARGS[@]}"} < "$AWH_TMP/stdin"
    exit $?
}

# ---- Workspace pre-commit ------------------------------------------------------------------------

# awh_sensitivity <readme file>: prints "sensitive" when readme.awk field 17 says so.
awh_sensitivity() {
    awk -v alias_outcome="" -v alias_done="" -v alias_people="" \
        -f "$AWH_KIT_ROOT/plugins/projects/hooks/lib/readme.awk" "$1" 2>/dev/null | awk -F '\037' '{ print $17; exit }'
}

# awh_project_sensitive <repo dir> <folder, relative to the repo> <entry point>: 0 when the project is
# Sensitivity: sensitive in the working tree or in HEAD, 1 when not, 2 when it cannot be told.
awh_project_sensitive() {
    local repo="$1" folder="$2" entry="$3" f
    [[ -f "$AWH_KIT_ROOT/plugins/projects/hooks/lib/readme.awk" ]] || return 2
    f="$repo/${folder:+$folder/}$entry"
    if [[ -f "$f" && "$(awh_sensitivity "$f")" == sensitive ]]; then return 0; fi
    if git -C "$repo" cat-file -e "HEAD:${folder:+$folder/}$entry" 2>/dev/null; then
        git -C "$repo" show "HEAD:${folder:+$folder/}$entry" > "$AWH_TMP/head-readme" 2>/dev/null || return 2
        [[ "$(awh_sensitivity "$AWH_TMP/head-readme")" == sensitive ]] && return 0
    fi
    return 1
}

# awh_folder_sensitive <repo dir> <folder> <entry point>: the project's sensitivity from any of its
# README.md, CLAUDE.md and configured entry point. 0 sensitive, 1 not, 2 cannot be read, 3 the folder
# has none of them in the working tree or HEAD, so nothing says it is not sensitive.
awh_folder_sensitive() {
    local repo="$1" folder="$2" e seen="|" found=0 rc
    for e in README.md CLAUDE.md "$3"; do
        case "$seen" in *"|$e|"*) continue ;; esac
        seen+="$e|"
        [[ -f "$repo/${folder:+$folder/}$e" ]] || git -C "$repo" cat-file -e "HEAD:${folder:+$folder/}$e" 2>/dev/null || continue
        found=1
        awh_project_sensitive "$repo" "$folder" "$e"; rc=$?
        [[ $rc -eq 1 ]] || return $rc
    done
    [[ $found -eq 1 ]] && return 1
    return 3
}

# awh_workspace_precommit: the sensitive-project refusal, the size guard and the force-add warning,
# over the staged changes (the index git is committing, GIT_INDEX_FILE included). A project folder with
# no entry point cannot say it is not sensitive, so its files are refused too (fail closed). And a
# sensitive project whose folder .gitignore keeps out has every file still in the index refused, staged
# change or not: that is the state an untrack leaves before it is committed, when a re-add equals HEAD.
awh_workspace_precommit() {
    local cfg="$AWH_KIT_ROOT/plugins/projects/hooks/lib/config.sh" base meta path om nm os ns st
    local folder pat sz limit known="" sens="" noentry="" glob d rel done_paths="|"
    if [[ ! -f "$cfg" || ! -f "$AWH_KIT_ROOT/plugins/projects/hooks/lib/readme.awk" ]]; then
        awh_item "could-not-run: the projects plugin's config.sh or readme.awk is missing from the kit"; return
    fi
    # shellcheck source=../../plugins/projects/hooks/lib/config.sh
    . "$cfg"
    projects_config "$AWH_WS"
    base="$(git hash-object -t tree /dev/null)"
    git rev-parse -q --verify 'HEAD^{commit}' >/dev/null && base=HEAD
    git diff-index --cached -z --no-renames "$base" > "$AWH_TMP/staged" 2>"$AWH_TMP/staged.err" || {
        awh_item "could-not-run: git diff-index failed: $(head -n 1 "$AWH_TMP/staged.err")"; return; }
    limit="${AW_MAX_FILE_MB:-25}"
    [[ "$limit" =~ ^[0-9]+$ ]] || { awh_item "could-not-run: AW_MAX_FILE_MB is not a whole number"; limit=25; }
    [[ "$limit" -eq 0 ]] && printf 'aw %s: AW_MAX_FILE_MB=0; the size check did not run.\n' "$AWH_NAME" >&2
    while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
        meta="${meta#:}"
        read -r om nm os ns st <<EOF
$meta
EOF
        case "$st" in D*) continue ;; esac
        [[ "$nm" == 160000 ]] && continue
        # The project folder this path sits in, if any.
        folder=""
        while IFS= read -r pat; do
            [[ -n "$pat" ]] || continue
            folder="$(projects_match "$pat" "$path")"
            [[ -n "$folder" && "$folder" != "$path" ]] && break
            folder=""
        done <<EOF
$PROJECT_PATTERNS
EOF
        if [[ -n "$folder" ]]; then
            case "$known" in *"|$folder|"*) ;; *)
                known+="|$folder|"
                awh_folder_sensitive "$AWH_TOP" "$folder" "${ENTRY_POINT:-README.md}"
                case $? in
                    0) sens+="|$folder|" ;;
                    2) awh_item "could-not-run: the sensitivity of $folder cannot be read" ;;
                    3) noentry+="|$folder|" ;;
                esac ;;
            esac
            case "$sens" in *"|$folder|"*)
                done_paths+="|$path|"
                awh_item "$path — the project is Sensitivity: sensitive; keep it untracked or its own private repository (/projects:adopt ${folder##*/} untracked)" ;;
            esac
            case "$noentry" in *"|$folder|"*)
                awh_item "$path — $folder has no README.md or CLAUDE.md to say whether it is sensitive; add one with its Sensitivity: line first" ;;
            esac
        fi
        if [[ "$limit" -gt 0 ]]; then
            sz="$(git cat-file -s "$ns" 2>/dev/null)"
            if [[ -z "$sz" ]]; then
                awh_item "could-not-run: the size of $path cannot be read"
            elif [[ "$sz" -gt $((limit * 1048576)) ]]; then
                awh_item "$path — $(( (sz + 1048575) / 1048576 )) MB, over the $limit MB limit; name large material under ## Resources in the project README instead"
            fi
        fi
        if [[ "$st" == A* ]] && git check-ignore --no-index -q -- "$path" 2>/dev/null; then
            printf 'aw %s: %s is listed in .gitignore and was added with git add -f; it is committed as asked.\n' "$AWH_NAME" "$path" >&2
        fi
        : "$om" "$os"
    done < "$AWH_TMP/staged"
    # Sensitive folders the workspace ignores, with files left in the index.
    while IFS= read -r pat; do
        [[ -n "$pat" ]] || continue
        glob="$(printf '%s' "$pat" | sed -e 's/<[^>]*>/*/g')"
        for d in "$AWH_TOP"/$glob; do
            [[ -d "$d" ]] || continue
            rel="${d#"$AWH_TOP"/}"
            case "${rel##*/}" in _*|.*) continue ;; esac
            git check-ignore --no-index -q -- "$rel/" 2>/dev/null || continue
            awh_folder_sensitive "$AWH_TOP" "$rel" "${ENTRY_POINT:-README.md}" || continue
            git ls-files -s -- "$rel" 2>/dev/null | awk '$1 != "160000" { sub(/^[^\t]*\t/, ""); print }' > "$AWH_TMP/held"
            while IFS= read -r path; do
                [[ -n "$path" ]] || continue
                case "$done_paths" in *"|$path|"*) continue ;; esac
                awh_item "$path — still in the index, under $rel, which is Sensitivity: sensitive and kept out by .gitignore; git rm --cached it"
            done < "$AWH_TMP/held"
        done
    done <<EOF
$PROJECT_PATTERNS
EOF
}

# ---- Kit pre-commit ------------------------------------------------------------------------------

# awh_guard_paths: a staged change to a file that holds the guards themselves needs AW_GUARD_CHANGE=1.
awh_guard_paths() {
    local p
    [[ "${AW_GUARD_CHANGE:-}" == 1 ]] && return 0
    git diff --cached --name-only -z --no-renames > "$AWH_TMP/guard" 2>/dev/null || {
        awh_item "could-not-run: git diff --cached failed"; return; }
    while IFS= read -r -d '' p; do
        case "$p" in
            scripts/check-paths.sh|githooks/*|.github/*|lib/common.sh)
                awh_item "$p — a guard file; a deliberate change goes through with AW_GUARD_CHANGE=1" ;;
        esac
    done < "$AWH_TMP/guard"
}

# ---- pre-push: remotes ---------------------------------------------------------------------------

# awh_safe_url <url>: the URL with any user or token before an @ removed, for printing.
awh_safe_url() {
    local u="$1"
    case "$u" in *://*@*) u="${u%%://*}://${u#*@}" ;; esac
    printf '%s' "$u"
}

# awh_gh_visibility <owner/repo>: PRIVATE, INTERNAL or PUBLIC as GitHub says, or nothing (no gh, a
# failure, or no answer within the watchdog's time: timeout(1) is not on macOS). AW_GH names the gh
# command (default gh); AW_GH_TIMEOUT shortens the 10-second wait.
awh_gh_visibility() {
    local gh="${AW_GH:-gh}" t="${AW_GH_TIMEOUT:-10}" pid w st
    command -v "$gh" >/dev/null 2>&1 || return 1
    [[ "$t" =~ ^[0-9]+$ && "$t" -ge 1 && "$t" -le 10 ]] || t=10
    : > "$AWH_TMP/gh.out"
    GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 "$gh" repo view "$1" --json visibility --jq .visibility \
        > "$AWH_TMP/gh.out" 2>/dev/null < /dev/null &
    pid=$!
    ( sleep "$t"; kill "$pid" 2>/dev/null ) > /dev/null 2>&1 < /dev/null &
    w=$!
    wait "$pid"; st=$?
    kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
    [[ $st -eq 0 ]] || return 1
    tr -d '[:space:]' < "$AWH_TMP/gh.out"
}

# awh_has_tty: 0 when a person is at a terminal (the process has a controlling terminal).
awh_has_tty() { ( exec 3</dev/tty ) 2>/dev/null; }

# awh_confirmed_private <normalised url>: 0 when the remote is confirmed private, 3 when GitHub says it
# is public, 1 otherwise. AWH_WHY says which, for the messages.
AWH_WHY=""
awh_confirmed_private() {
    local norm="$1" tmpd v line url via
    AWH_WHY=""
    case "$norm" in
        local:*)
            tmpd="$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)"
            if [[ -n "$tmpd" ]]; then
                case "${norm#local:}/" in "$tmpd"/*) AWH_WHY="a local path under the temporary folder"; return 0 ;; esac
            fi ;;
        github.com/*/*)
            v="$(awh_gh_visibility "${norm#github.com/}")"
            case "$v" in
                PRIVATE|INTERNAL) AWH_WHY="GitHub says $v"; return 0 ;;
                PUBLIC) AWH_WHY="GitHub says PUBLIC"; return 3 ;;
            esac ;;
    esac
    while IFS=$'\t' read -r url via line; do
        [[ "$url" == "$norm" ]] || continue
        if [[ "$via" == gh ]]; then AWH_WHY="listed as a Private remote (confirmed via gh)"; return 0; fi
        # A line a person wrote is trusted only with a person at a terminal, so an unattended push
        # without gh cannot rest on it.
        if awh_has_tty; then AWH_WHY="listed as a Private remote"; return 0; fi
        AWH_WHY="listed as a Private remote by a person, and no one is at a terminal to stand behind it"
        return 1
    done <<EOF
$(aw_private_remotes "$AWH_WS")
EOF
    : "$line"
    return 1
}

# awh_workspace_prepush <remote name> <url>
awh_workspace_prepush() {
    local name="$1" url="${2:-$1}" norm st show
    norm="$(aw_norm_url "$url")"
    show="$(awh_safe_url "$name")"
    [[ -n "$norm" ]] || awh_die "could-not-run: the remote $show has no URL to check"
    awh_confirmed_private "$norm"; st=$?
    [[ $st -eq 0 ]] && return 0
    if [[ -n "${AW_ALLOW_PUBLIC:-}" && "$AW_ALLOW_PUBLIC" == "$norm" ]]; then
        printf 'aw pre-push: AW_ALLOW_PUBLIC names this remote — pushing to a public remote on purpose.\n' >&2
        return 0
    fi
    if [[ $st -eq 3 ]]; then
        printf 'aw pre-push: %s (%s) is public on GitHub. A workspace is private; nothing was pushed. Make the repository private, or push to one that is; AW_ALLOW_PUBLIC=%s pushes once regardless.\n' "$show" "$norm" "$norm" >&2
        exit 1
    fi
    case "$norm" in
        local:*)
            printf 'aw pre-push: %s: a local path outside the temporary folder is not confirmed private (a synced folder can be shared); list it under Private remotes in .claude/workspace.md once confirmed.\nNothing was pushed.\n' "$show" >&2
            exit 1 ;;
    esac
    printf 'aw pre-push: %s (%s) is not confirmed private. A workspace is private; nothing was pushed. kit/setup.sh confirms and records a private remote; AW_ALLOW_PUBLIC=%s pushes once regardless.\n' "$show" "$norm" "$norm" >&2
    [[ -n "$AWH_WHY" ]] && printf '  (%s)\n' "$AWH_WHY" >&2
    exit 1
}

# awh_project_prepush <remote name> <url>: an own-repo project, or a standalone repository in a
# project folder. Private is always fine. A Public remote named in .claude/workspace.md is fine only for
# the project folder that bullet names, and only when the project is not sensitive: its README.md,
# CLAUDE.md or configured entry point, in the working tree or HEAD, says so, and a project with none of
# them cannot say, so it is not pushed to a public remote. A sensitive project goes to a confirmed
# private remote only.
awh_project_prepush() {
    local name="$1" url="${2:-$1}" norm show st cfg entry="README.md" found=1 sens=1 rel
    local u f listed=0 named=0 folders=""
    norm="$(aw_norm_url "$url")"
    show="$(awh_safe_url "$name")"
    [[ -n "$norm" ]] || awh_die "could-not-run: the remote $show has no URL to check"
    [[ -n "$AWH_WS" ]] || awh_die "could-not-run: no workspace found around this project"
    awh_confirmed_private "$norm"; st=$?
    [[ $st -eq 0 ]] && return 0
    cfg="$AWH_KIT_ROOT/plugins/projects/hooks/lib/config.sh"
    if [[ -f "$cfg" ]]; then
        # shellcheck source=../../plugins/projects/hooks/lib/config.sh
        . "$cfg"
        projects_config "$AWH_WS"
        entry="${ENTRY_POINT:-README.md}"
    fi
    awh_folder_sensitive "$AWH_TOP" "" "$entry"
    case $? in
        0) sens=0 ;;
        2) awh_die "could-not-run: this project's sensitivity cannot be read" ;;
        3) found=0 ;;
    esac
    if [[ $sens -eq 0 ]]; then
        printf 'aw pre-push: %s (%s) is not confirmed private, and this project is Sensitivity: sensitive. A sensitive project is pushed only to a confirmed private remote; AW_ALLOW_PUBLIC does not change that.\nNothing was pushed.\n' "$show" "$norm" >&2
        exit 1
    fi
    rel="${AWH_TOP#"$AWH_WS"/}"
    while IFS=$'\t' read -r u f _; do
        [[ "$u" == "$norm" ]] || continue
        listed=1
        folders="${folders:+$folders, }${f:-(none)}"
        [[ -n "$f" && "$f" == "$rel" ]] && named=1
    done <<EOF
$(aw_public_remotes "$AWH_WS")
EOF
    if [[ $listed -eq 1 && $named -eq 1 ]]; then
        if [[ $found -eq 0 ]]; then
            printf 'aw pre-push: %s is a Public remote for %s, and this project has no README.md or CLAUDE.md to say it is not sensitive. Add one with a Sensitivity: line, then push again.\nNothing was pushed.\n' "$show" "$rel" >&2
            exit 1
        fi
        return 0
    fi
    if [[ -n "${AW_ALLOW_PUBLIC:-}" && "$AW_ALLOW_PUBLIC" == "$norm" ]]; then
        printf 'aw pre-push: AW_ALLOW_PUBLIC names this remote — pushing to a public remote on purpose.\n' >&2
        return 0
    fi
    if [[ $listed -eq 1 ]]; then
        printf 'aw pre-push: %s is listed as a Public remote for %s, not for %s. A Public remote line names the one project folder that publishes to it, in backticks after the remote. Nothing was pushed.\n' "$show" "$folders" "$rel" >&2
        exit 1
    fi
    printf 'aw pre-push: %s is neither confirmed private nor listed as a Public remote in .claude/workspace.md. Nothing was pushed.\n' "$show" >&2
    exit 1
}
