#!/usr/bin/env bash
# kit/setup.sh: the guided way into a workspace built on the agentic workspace kit, and the one entry
# point for the kit's modes. The workspace is a private repository with the kit as a submodule at kit/;
# this script sets it up, keeps it in step, and hands each mode to the script that does it.
#
#   kit/setup.sh [--target DIR] [--team NAME] [--owner NAME] [--owner-handle @h] [--pilot] [--cowork] [--init] [--reinstall]
#   kit/setup.sh new DIR [--team NAME] [--owner NAME] [--owner-handle @h] [--pilot] [--cowork] [--kit-url URL] [--kit-ref REF]
#   kit/setup.sh update [--target DIR] [--no-fetch]
#   kit/setup.sh --developer [--target DIR]
#   kit/setup.sh link [SLUG] [--target DIR] [--dry-run]
#   kit/setup.sh hooks [--target DIR] [--repo PATH] [--check]
#   kit/setup.sh skills [--target DIR] [--dry-run] [--check] [--no-user]
#   kit/setup.sh migrate [--target DIR] [--dry-run] [--map FILE] [--kit-from URL] [--kit-ref REF] [--allow-staged] [--developer]
#   kit/setup.sh -h | --help
#
# With no mode it runs the ten stages below on the workspace; new runs them on a folder it starts
# from nothing. The other modes run as child scripts, each given --target: update, --developer (also
# accepted as developer), link, hooks and migrate from lib/setup/, skills from scripts/skills-bridge.sh.
#
# The target is --target; else DIR for new; else the repository this kit checkout is a submodule of;
# else the current folder. A target inside the kit's own checkout stops.
#
# Each stage reads the state check (plugins/workspace/bin/state.sh) before it acts, so a re-run skips
# what is done: Ctrl-C and run it again is the way back. Nothing is overwritten, nothing is deleted and
# nothing is committed. AW_WIZARD_NONINTERACTIVE=1, or no terminal on stdin, runs it unattended: every
# question takes its default, and the stages only a person can do are skipped.
#
# Stages, and the state check keys each one's outcome is read from:
#    1 Prerequisites             bash, git and jq (required); claude and gh (optional)
#    2 Identity                  in_git, person; the ledger's @values; CLAUDE.md §1; .github/CODEOWNERS
#    3 The workspace             new, adopt or existing; then the engine (install.sh). ledger, claude_md,
#                                plugins_registered, plugins_mode, legacy
#    4 Remotes and privacy       hooks, kit_hooks, origin, origin_visibility, origin_confirmed
#    5 Submodule configuration   submodule_config
#    6 Outside folders           external_paths, external_paths_missing, resource.*
#    7 Restart Claude Code       the person's word; plugins_registered is shown beside it
#    8 Cowork (with --cowork)    skills_bridge
#    9 Verify                    every key above
#   10 Finish                    mode, which decides what the quick-start does first
#
# Exit status: 0 finished (stages may be left open), 1 stopped, 2 usage, 130 interrupted.
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/wizard.sh
. "$KIT/lib/wizard.sh"
# shellcheck source=lib/common.sh
. "$KIT/lib/common.sh"
# shellcheck disable=SC2034  # read by lib/wizard.sh
WZ_STATE_SH="$KIT/plugins/workspace/bin/state.sh"
DEFAULT_KIT_URL="https://github.com/cyberscribe/agentic-workspace-kit.git"

usage() { sed -n '6,14p' "$0" | sed 's/^# \{0,1\}//'; }

# abs_path <path>: an absolute path, resolved through links as far as it exists. A folder that does not
# exist yet keeps its last name under its resolved parent.
abs_path() {
    local p="$1"
    case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
    while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
    if [[ -d "$p" ]]; then (cd "$p" && pwd -P)
    elif [[ -d "$(dirname "$p")" ]]; then printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
    else printf '%s\n' "$p"; fi
}

# resolve_target <given>: --target or DIR when given; else the superproject of this kit checkout; else
# the current folder.
resolve_target() {
    local t="$1"
    [[ -n "$t" ]] || t="$(git --no-optional-locks -C "$KIT" rev-parse --show-superproject-working-tree 2>/dev/null)"
    [[ -n "$t" ]] || t="$PWD"
    abs_path "$t"
}

# inside_kit <path>: success when the path is the kit's own checkout or under it.
inside_kit() { case "$1/" in "$KIT"/*) return 0 ;; esac; return 1; }

# --- The modes that are scripts of their own -------------------------------------------------------
MODE=wizard
case "${1:-}" in
    new) MODE=new; shift ;;
    update|link|hooks|skills|migrate) MODE="$1"; shift ;;
    developer|--developer) MODE=developer; shift ;;
esac

if [[ $MODE != wizard && $MODE != new ]]; then
    given="" rest=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target) [[ $# -ge 2 ]] || { echo "setup.sh $MODE: --target needs a folder" >&2; exit 2; }
                given="$2"; shift 2 ;;
            *) rest+=("$1"); shift ;;
        esac
    done
    T="$(resolve_target "$given")"
    if inside_kit "$T"; then
        echo "setup.sh $MODE: $T is inside the kit's own checkout; name the workspace with --target DIR" >&2
        exit 1
    fi
    extra=()
    case "$MODE" in
        update) child="$KIT/lib/setup/update.sh" ;;
        developer) child="$KIT/lib/setup/developer.sh" ;;
        link) child="$KIT/lib/setup/link.sh" ;;
        hooks) child="$KIT/lib/setup/gitconfig.sh"; extra=(--hooks) ;;
        migrate) child="$KIT/lib/setup/migrate.sh" ;;
        skills) child="$KIT/scripts/skills-bridge.sh" ;;
    esac
    "${BASH:-bash}" "$child" --target "$T" ${extra[@]+"${extra[@]}"} ${rest[@]+"${rest[@]}"}
    exit $?
fi

# --- The wizard: the default run, and new ----------------------------------------------------------
given="" DIR="" TEAM="" OWNER="" HANDLE="" PILOT=0 INIT=0 COWORK=0 REINSTALL=0 KIT_URL="" KIT_REF=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target|--team|--owner|--owner-handle|--kit-url|--kit-ref)
            [[ $# -ge 2 ]] || { echo "setup.sh: $1 needs a value" >&2; exit 2; }
            case "$1" in
                --target) given="$2" ;; --team) TEAM="$2" ;; --owner) OWNER="$2" ;;
                --owner-handle) HANDLE="$2" ;; --kit-url) KIT_URL="$2" ;; --kit-ref) KIT_REF="$2" ;;
            esac
            shift 2 ;;
        --pilot) PILOT=1; shift ;;
        --init) INIT=1; shift ;;
        --cowork) COWORK=1; shift ;;
        --reinstall) REINSTALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "setup.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ $MODE == new && -z "$DIR" ]]; then DIR="$1"; shift
            else echo "setup.sh: unexpected argument $1" >&2; usage >&2; exit 2; fi ;;
    esac
done
if [[ $MODE == new && -z "$DIR" && -z "$given" ]]; then
    echo "setup.sh new: name the folder to start the workspace in (kit/setup.sh new DIR)" >&2; exit 2
fi
T="$(resolve_target "${given:-$DIR}")"

TOTAL=10
KIT_ADDED=0        # 1 when this run added the kit submodule
ENGINE_PATHS=()    # what the engine created or merged this run, for the commit list
TG=(git --no-optional-locks -C "$T")
# stop <why>: the stage ends here and so does the run, with the summary so far.
stop() { outcome stopped "$1"; echo; finish; exit 1; }
# An angle-bracketed value is a stand-in, not an answer.
known() { [[ -n "$1" && "$1" != *'<'* ]]; }
# lock_value <key>: a value from the @values line of the ledger (.claude/kit-templates.lock).
lock_value() {
    awk -F '\t' -v k="$1=" '$1 == "@values" { for (i = 2; i <= NF; i++) if (index($i, k) == 1) { print substr($i, length(k) + 1); exit } }' \
        "$T/.claude/kit-templates.lock" 2>/dev/null
}
# kit_gitlink: success when the workspace's index holds kit/ as a submodule (mode 160000).
kit_gitlink() { [[ "$("${TG[@]}" ls-files -s -- kit 2>/dev/null | awk '$1 == "160000" { print "y"; exit }')" == y ]]; }
# is_local_url <url>: a path or file:// URL rather than a network one; git clones those only with
# protocol.file.allow=always.
is_local_url() {
    case "$1" in file://*) return 0 ;; *://*) return 1 ;; esac
    local lhs="${1%%:*}"
    [[ "$1" == *:* && "$lhs" != */* && -n "$lhs" ]] && return 1
    return 0
}
# kit_url: where new and adopt add the kit from.
kit_url() {
    local u="$KIT_URL"
    [[ -n "$u" ]] || u="${AW_KIT_URL:-}"
    [[ -n "$u" ]] || u="$(git --no-optional-locks -C "$KIT" remote get-url origin 2>/dev/null)"
    [[ -n "$u" ]] || u="$DEFAULT_KIT_URL"
    # A relative path would be read against the workspace's own remote; it is made absolute here.
    if is_local_url "$u" && [[ "$u" != /* && "$u" != file://* && -d "$u" ]]; then u="$(cd "$u" && pwd -P)"; fi
    printf '%s\n' "$u"
}
# add_kit <url>: git submodule add, branch main, at kit/; then the pinned ref when --kit-ref names one.
add_kit() {
    local u="$1" pc=()
    is_local_url "$u" && pc=(-c protocol.file.allow=always)
    step "git submodule add -b main $u kit"
    "${TG[@]}" ${pc[@]+"${pc[@]}"} submodule add -q -b main "$u" kit >/dev/null 2>&1 \
        || stop "git submodule add did not finish; run it by hand to see why: git -C $T submodule add -b main $u kit"
    if [[ -n "$KIT_REF" ]]; then
        step "git -C kit checkout --detach $KIT_REF"
        git --no-optional-locks -C "$T/kit" checkout -q --detach "$KIT_REF" 2>/dev/null \
            || stop "the kit has no ref $KIT_REF"
        "${TG[@]}" add kit || stop "git add kit did not finish"
    fi
    KIT_ADDED=1
}
# section <report> <heading>: the indented items under one heading of the engine's report.
section() {
    printf '%s\n' "$1" | awk -v h="$2" 'index($0, h) == 1 { on = 1; next } on && /^  / { print; next } on { exit }'
}
# run_child <label> <script> <args...>: a kit script, its output indented; its status is returned.
run_child() {
    local label="$1" rc; shift
    step "$label"
    "${BASH:-bash}" "$@" 2>&1 | sed 's/^/    /'
    rc=${PIPESTATUS[0]}
    return "$rc"
}
# gh_visibility <owner/repo>: GitHub's answer (PRIVATE, INTERNAL, PUBLIC), or nothing when gh cannot
# say within 10 seconds. There is no timeout(1) on macOS, so a background sleep does the waiting.
gh_visibility() {
    local tmp pid w st
    command -v gh >/dev/null 2>&1 || return 0
    tmp="$(mktemp "${TMPDIR:-/tmp}/aw-gh.XXXXXX")" || return 0
    GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 gh repo view "$1" --json visibility --jq .visibility \
        >"$tmp" 2>/dev/null </dev/null &
    pid=$!
    ( sleep 10; kill "$pid" ) >/dev/null 2>&1 &
    w=$!
    wait "$pid" 2>/dev/null; st=$?
    { kill "$w"; wait "$w"; } >/dev/null 2>&1
    [[ $st -eq 0 ]] && tr -d '[:space:]' <"$tmp"
    rm -f "$tmp"
    return 0
}
# origin_github <normalised url>: owner/repo when the remote is on github.com, else nothing.
origin_github() {
    case "$1" in github.com/*/*) ;; *) return 0 ;; esac
    local r="${1#github.com/}"
    [[ "$r" == */* && "${r#*/}" != */* ]] && printf '%s\n' "$r"
    return 0
}
# listed_private <normalised url>: the via and date of a Private remote entry for it, or nothing.
listed_private() { aw_private_remotes "$T" | awk -F '\t' -v u="$1" '$1 == u { print $2 " " $3; exit }'; }
# record_private <normalised url> <gh|person>: a Private remote bullet in .claude/workspace.md, directly
# after the comment line under "## Private remotes" (at the end of that section when it has none).
record_private() {
    local f="$T/.claude/workspace.md" line tmp
    line="- **Private remote:** \`$1\` — confirmed $(date +%F) via $2"
    [[ -f "$f" ]] || { warn "no .claude/workspace.md to record it in; kit/setup.sh --reinstall creates it"; return 1; }
    tmp="$(mktemp "${TMPDIR:-/tmp}/aw-workspace-md.XXXXXX")" || return 1
    awk -v line="$line" '
        !done && /^## Private remotes[ \t]*$/ { print; sec = 1; next }
        sec && !done && /^<!--/ && /Private remote/ { print; print line; done = 1; next }
        sec && !done && /^## / { print line; print ""; print; done = 1; sec = 0; next }
        { print }
        END { if (!done) { if (!sec) { print ""; print "## Private remotes"; print "" } print line } }' "$f" >"$tmp" \
        && cat "$tmp" >"$f"
    rm -f "$tmp"
    [[ -n "$(listed_private "$1")" ]]
}

if [[ $MODE == new ]]; then
    banner "Agentic workspace kit: a new workspace" \
        "Ten short stages. Enter takes the [default]; Ctrl-C stops, and running kit/setup.sh again picks up where it stopped."
else
    banner "Agentic workspace kit: setup" \
        "Ten short stages. Enter takes the [default]; Ctrl-C stops, and running kit/setup.sh again picks up where it stopped."
fi

# --- 1 · Prerequisites ------------------------------------------------------------------------------
stage 1 $TOTAL "Prerequisites"
missing="" optional=""
# The kit's scripts are written for bash 3.2, what macOS ships.
if ! check "bash $BASH_VERSION (3.2 or later)" test "${BASH_VERSINFO[0]}${BASH_VERSINFO[1]}" -ge 32; then
    step "Install a newer bash, or run this with the system's /bin/bash."; missing+=" bash"
fi
if ! check "git" command -v git; then
    step "Install git: https://git-scm.com/downloads"; missing+=" git"
fi
if ! check "jq, which the engine and the state check read the settings with" command -v jq; then
    step "Install jq: brew install jq (macOS), apt install jq (Debian, Ubuntu), or https://jqlang.org/download/"
    missing+=" jq"
fi
if ! check "claude, the Claude Code command line (optional here)" command -v claude; then
    step "Install Claude Code before stage 7: https://docs.claude.com/en/docs/claude-code/setup"
    optional+="claude still to install, before stage 7; "
fi
if ! check "gh, the GitHub command line (optional: it confirms a GitHub origin is private)" command -v gh; then
    step "Without gh, stage 4 asks whether the origin is private, and the pre-push hook reads .claude/workspace.md."
    optional+="gh not installed; "
fi
[[ -z "$missing" ]] || stop "install$missing, then run kit/setup.sh again"
if [[ -z "$optional" ]]; then outcome "already done"; else outcome "done" "${optional%; }"; fi

# --- 2 · Identity -----------------------------------------------------------------------------------
stage 2 $TOTAL "Identity"
say "The workspace is the team's private repository: its standards, projects and decisions. The kit"
say "sits inside it at kit/, read in place."
echo
if inside_kit "$T"; then
    stop "$T is inside the kit's own checkout; name the workspace: kit/setup.sh --target DIR, or kit/setup.sh new DIR"
fi
state_check "$T"
# own_repo: the target is the top of a repository of its own, not a folder inside another one.
own_repo=0 top=""
if [[ -d "$T" ]]; then
    top="$(git --no-optional-locks -C "$T" rev-parse --show-toplevel 2>/dev/null)"
    [[ -n "$top" && "$(cd "$top" && pwd -P)" == "$T" ]] && own_repo=1
fi
if [[ $MODE == new ]]; then
    # new starts its own repository, even in an empty folder that sits inside another one.
    [[ ! -e "$T" || -z "$(ls -A "$T" 2>/dev/null)" ]] \
        || stop "$T is not empty: kit/setup.sh new starts a workspace in a new or empty folder; for a repository that exists, run kit/setup.sh --target $T"
    own_repo=0
fi
case "$(state_key in_git)" in
    yes)
        [[ $MODE == new || $own_repo -eq 1 ]] \
            || stop "$T is a folder inside the repository at $top; name the repository itself: kit/setup.sh --target $top" ;;
    refused) stop "git will not read $T as this user (safe.directory); see git config --help, safe.directory" ;;
    *)
        if [[ $MODE == new ]]; then
            :
        elif [[ $INIT -eq 0 ]]; then
            what="make $T a git repository"; [[ -d "$T" ]] || what="create $T as a new git repository"
            # The one step that cannot be undone by running again, so it is asked, and n is the default.
            attended && confirm "There is no repository here yet. OK to $what?" n && INIT=1
            [[ $INIT -eq 1 ]] || stop "not a git repository yet: kit/setup.sh new DIR starts one, or re-run with --init to $what"
        fi ;;
esac

# What an earlier run answered: the ledger's @values first, then CLAUDE.md §1 and CODEOWNERS. AGENTS.md
# is never read here; some workspaces keep it closed to tools.
team_now="$(lock_value team)" owner_now="$(lock_value owner)" handle_now="$(lock_value handle)"
known "$team_now" || team_now="$( [[ -f "$T/CLAUDE.md" ]] && sed -n 's/^| \*\*Team\*\* | \(.*\) |$/\1/p' "$T/CLAUDE.md" | head -n 1)"
known "$owner_now" || owner_now="$( [[ -f "$T/CLAUDE.md" ]] && sed -n 's/^| \*\*Standards owner\*\* | \(.*\) — reviews.*/\1/p' "$T/CLAUDE.md" | head -n 1)"
known "$handle_now" || handle_now="$(awk '$1 == "/CLAUDE.md" || $1 == "/AGENTS.md" { print $2; exit }' "$T/.github/CODEOWNERS" 2>/dev/null)"
known "$team_now" || team_now=""
known "$owner_now" || owner_now=""
known "$handle_now" || handle_now=""
# A measured pilot, or a Cowork team, keeps its layer on a re-run.
[[ "$(lock_value pilot)" != 1 && "$(state_key build_list)" != present ]] || PILOT=1
[[ "$(lock_value cowork)" != 1 ]] || COWORK=1

if [[ $own_repo -eq 1 && -n "$team_now" && -n "$owner_now" ]] \
    && [[ -z "$TEAM" || "$TEAM" == "$team_now" ]] && [[ -z "$OWNER" || "$OWNER" == "$owner_now" ]] \
    && [[ -z "$HANDLE" || "$HANDLE" == "$handle_now" ]]; then
    TEAM="$team_now" OWNER="$owner_now" HANDLE="${handle_now:-$HANDLE}"
    step "Workspace    $T"
    step "Team         $TEAM"
    step "Owner        $OWNER ${HANDLE}"
    outcome "already done" "read from the ledger and CLAUDE.md"
else
    [[ -n "$TEAM" ]] || TEAM="$(ask "Team name" "$team_now")"
    # The person running this is the likeliest standards owner; git knows their name.
    [[ -n "$OWNER" ]] || OWNER="$(ask "Standards owner, who reviews changes to the shared standards file" "${owner_now:-$(state_key person)}")"
    [[ -n "$HANDLE" ]] || HANDLE="$(ask "Their GitHub or GitLab handle, for CODEOWNERS" \
        "${handle_now:-${OWNER:+@}$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')}")"
    if [[ $PILOT -eq 0 ]] && attended; then
        confirm "Run it as a measured pilot, with a build list and weekly metrics?" n && PILOT=1
    fi
    echo
    step "Workspace    $T$([[ $MODE == new || $INIT -eq 1 ]] && printf '  (stage 3 starts it)')"
    step "Team         ${TEAM:-<to fill in>}"
    step "Owner        ${OWNER:-<to fill in>} ${HANDLE}"
    step "Pilot        $([[ $PILOT -eq 1 ]] && echo yes || echo no)"
    # The engine creates CLAUDE.md once and never writes it again, so a new answer here would not reach it.
    changed=""
    [[ -n "$team_now" && -n "$TEAM" && "$TEAM" != "$team_now" ]] && changed+="team $team_now, "
    [[ -n "$owner_now" && -n "$OWNER" && "$OWNER" != "$owner_now" ]] && changed+="owner $owner_now, "
    [[ -n "$handle_now" && -n "$HANDLE" && "$HANDLE" != "$handle_now" ]] && changed+="handle $handle_now, "
    if [[ -n "$changed" ]]; then
        outcome "left open" "CLAUDE.md and CODEOWNERS already name ${changed%, }; they are yours, so edit them there"
    else
        outcome "done"
    fi
fi

# --- 3 · The workspace: new, adopt or existing -----------------------------------------------------
stage 3 $TOTAL "The workspace"
state_check "$T"
if layout_2x "$T"; then
    say "The kit is installed here in the 2.x layout: its plugins copied into .claude/plugins, or the kit"
    say "checked out somewhere other than kit/. The migration moves it to the 3.0 layout, step by step,"
    say "and shows every step first."
    stop "this workspace has the 2.x layout: kit/setup.sh migrate --dry-run"
fi
legacy="$(state_key legacy)"
[[ -z "$legacy" ]] || note "Traces of an earlier kit, left as they are: $legacy (kit/setup.sh migrate --dry-run names them)"
# laid_down: the engine's ledger, the import line, the three plugins, registered from kit/.
laid_down() {
    key_is ledger present && key_is claude_md kit && key_is plugins_registered closeout,projects,workspace \
        && key_is plugins_mode kit
}
before_ok=0; laid_down && before_ok=1
merge_gitignore=0
if [[ $own_repo -eq 0 ]]; then
    step "git init -b main $T"
    mkdir -p "$T" || stop "could not create $T"
    if ! git --no-optional-locks init -q -b main "$T" >/dev/null 2>&1; then
        # git before 2.28 has no -b; the branch is named by hand.
        { git --no-optional-locks init -q "$T" >/dev/null 2>&1 && "${TG[@]}" symbolic-ref HEAD refs/heads/main; } \
            || stop "git init did not finish in $T"
    fi
    T="$(cd "$T" && pwd -P)"; TG=(git --no-optional-locks -C "$T")
    merge_gitignore=1
fi
if ! kit_gitlink; then
    url="$(git --no-optional-locks config -f "$T/.gitmodules" "submodule.$(aw_kitname "$T").url" 2>/dev/null)"
    if [[ -n "$(aw_kitname "$T")" && -n "$url" ]]; then
        # A copy of the template repository can arrive with .gitmodules and without the gitlink.
        say ".gitmodules names the kit at kit/, and the repository does not hold it: adding it again."
        add_kit "$url"
    else
        url="$(kit_url)"
        if [[ $merge_gitignore -eq 0 ]]; then
            say "This repository has no kit yet. The kit goes in as a submodule at kit/, from:"
            step "$url"
            attended && ! confirm "Add it now?" y && stop "nothing written"
        fi
        add_kit "$url"
    fi
    merge_gitignore=1
elif [[ ! -f "$T/kit/CLAUDE.kit.md" ]]; then
    # A clone made without --recurse-submodules holds the gitlink and an empty kit/.
    url="$(git --no-optional-locks config -f "$T/.gitmodules" "submodule.$(aw_kitname "$T").url" 2>/dev/null)"
    pc=(); is_local_url "$url" && pc=(-c protocol.file.allow=always)
    step "git submodule update --init kit"
    "${TG[@]}" ${pc[@]+"${pc[@]}"} submodule update -q --init -- kit >/dev/null 2>&1 \
        || stop "the kit submodule could not be initialised: git submodule update --init kit"
fi
if [[ $before_ok -eq 1 && $REINSTALL -eq 0 && $KIT_ADDED -eq 0 ]]; then
    check "the ledger, .claude/kit-templates.lock" true
    check "CLAUDE.md imports the kit's standards" true
    check "plugins registered from kit/: $(state_key plugins_registered)" true
    note "kit/setup.sh update brings in a newer kit; kit/setup.sh --reinstall creates any file of yours that is missing."
    outcome "already done"
else
    args=(--target "$T")
    [[ -z "$TEAM" ]] || args+=(--team "$TEAM")
    [[ -z "$OWNER" ]] || args+=(--owner "$OWNER")
    [[ -z "$HANDLE" ]] || args+=(--owner-handle "$HANDLE")
    [[ $PILOT -eq 0 ]] || args+=(--pilot)
    [[ $COWORK -eq 0 ]] || args+=(--cowork)
    [[ $merge_gitignore -eq 0 ]] || args+=(--gitignore merge)
    say "The engine, kit/install.sh, creates the files that are yours from here on, each only when it is"
    say "absent, and records them in .claude/kit-templates.lock. It never overwrites a file."
    echo
    step "$(printf '%q ' bash kit/install.sh "${args[@]}")"
    echo
    attended && ! confirm "Run it now?" y && stop "the kit is in place; the engine did not run"
    out="$("${BASH:-bash}" "$T/kit/install.sh" "${args[@]}" </dev/null 2>&1)"; rc=$?
    if [[ $rc -ne 0 ]]; then printf '%s\n' "$out" | tail -n 8 | sed 's/^/    /'; stop "kit/install.sh stopped with status $rc"; fi
    created="$(section "$out" "Created (")" merged="$(section "$out" "Merged (")"
    added="$(section "$out" "Added to .gitignore:")" kept="$(section "$out" "Kept as it was")"
    same="$(section "$out" "Already in place:")"
    while read -r p _; do [[ -z "$p" ]] || ENGINE_PATHS+=("$p"); done <<EOF
$created
$merged
EOF
    [[ -z "$added" ]] || ENGINE_PATHS+=(.gitignore)
    step "Created           $(printf '%s' "$created" | aw_count | sed 's/^0$/none/')"
    [[ -z "$created" ]] || printf '%s\n' "$created" | sed 's/^/  /'
    step "Settings merged   $(printf '%s' "$merged" | aw_count | sed 's/^0$/none/')"
    step "Added to .gitignore $(printf '%s' "$added" | aw_count | sed 's/^0$/none/')"
    step "Already in place  $(printf '%s' "$same" | aw_count | sed 's/^0$/none/')"
    if [[ -n "$kept" ]]; then
        step "Kept as it was (yours, from before the kit):"
        printf '%s\n' "$kept" | sed 's/^/  /'
    fi
    worth="$(section "$out" "Worth knowing:")"
    if [[ -n "$worth" ]]; then step "Worth knowing:"; printf '%s\n' "$worth" | sed 's/^/  /'; fi
    state_check "$T"
    if laid_down; then outcome "done"; else outcome "left open" "stage 9 names what is missing"; fi
fi

# --- 4 · Remotes and privacy ------------------------------------------------------------------------
stage 4 $TOTAL "Remotes and privacy"
say "A workspace is private. Git hooks from kit/githooks check what is committed and where it is pushed;"
say "a push goes only to a remote confirmed private."
echo
state_check "$T"
hooks_before=0; key_is hooks active && key_is kit_hooks active && hooks_before=1
if [[ $hooks_before -eq 0 ]]; then
    run_child "Setting the git hooks in the workspace and the kit:" "$T/kit/lib/setup/gitconfig.sh" --target "$T" --hooks \
        || warn "the hooks could not all be set; kit/setup.sh hooks shows why"
fi
origin_raw="$("${TG[@]}" remote get-url origin 2>/dev/null)"
origin="$(aw_norm_url "$origin_raw")"
recorded=0 open_why=""
if [[ -z "$origin" ]]; then
    note "No remote yet: nothing can be pushed, so nothing is exposed. Run kit/setup.sh again once origin is set."
elif [[ -n "$(listed_private "$origin")" ]]; then
    check "origin $origin is confirmed private ($(listed_private "$origin"))" true
else
    gh_repo="$(origin_github "$origin")" vis=""
    [[ -z "$gh_repo" ]] || vis="$(gh_visibility "$gh_repo")"
    case "$vis" in
        PRIVATE|INTERNAL)
            say "GitHub says $origin is $(printf '%s' "$vis" | tr '[:upper:]' '[:lower:]')."
            if ! attended || confirm "Record it in .claude/workspace.md as a confirmed private remote?" y; then
                record_private "$origin" gh && { recorded=1; check "recorded: $origin, confirmed via gh" true; }
            fi ;;
        PUBLIC)
            open_why="origin is public: make it private, or point origin at a private repository" ;;
        *)
            # With no answer from GitHub, only a person at a terminal can say.
            if attended && ( exec 3</dev/tty ) 2>/dev/null; then
                if confirm "Is $origin_raw a private repository?" n; then
                    record_private "$origin" person && { recorded=1; check "recorded: $origin, confirmed by you" true; }
                fi
            else
                note "origin $origin is not confirmed private; kit/setup.sh records it once it is confirmed (with gh, or at a terminal)."
            fi ;;
    esac
fi
state_check "$T"
if [[ -n "$origin" && -z "$open_why" && -z "$(listed_private "$origin")" ]]; then
    open_why="origin $origin is not confirmed private"
fi
if ! key_is hooks active || ! key_is kit_hooks active; then
    open_why="git hooks: workspace $(state_key hooks), kit $(state_key kit_hooks) — kit/setup.sh hooks${open_why:+; $open_why}"
fi
if [[ -n "$open_why" ]]; then outcome "left open" "$open_why"
elif [[ $hooks_before -eq 1 && $recorded -eq 0 ]]; then outcome "already done"
else outcome "done"; fi

# --- 5 · Submodule configuration --------------------------------------------------------------------
stage 5 $TOTAL "Submodule configuration"
say "The kit and any project that is its own repository are submodules. These settings make git show"
say "them in status, refuse a push that would leave one behind, and keep a project checked out on its branch."
echo
if key_is submodule_config ok; then
    check "submodule settings (submodule_config=ok, submodule.recurse $(state_key submodule_recurse))" true
    outcome "already done"
else
    run_child "Setting them:" "$T/kit/lib/setup/gitconfig.sh" --target "$T" --submodules \
        || warn "the submodule settings could not all be set"
    state_check "$T"
    if key_is submodule_config ok; then outcome "done"; else outcome "left open" "submodule_config=$(state_key submodule_config)"; fi
fi

# --- 6 · Outside folders ----------------------------------------------------------------------------
stage 6 $TOTAL "Outside folders"
ext="$(state_key external_paths)"
if [[ -z "$ext" ]]; then
    say "A project can name material kept outside the repository (a shared drive, a data folder) under"
    say "## Resources in its README; kit/setup.sh link maps each name to a path on this machine."
    outcome skipped "no project names an outside folder yet"
else
    run_child "Mapping the outside folders projects name ($(printf '%s' "$ext" | sed 's/,/, /g')):" "$T/kit/lib/setup/link.sh" --target "$T" \
        || warn "kit/setup.sh link stopped"
    state_check "$T"
    unreached=""
    for r in $(printf '%s' "$ext" | tr ',' ' '); do
        case "$(state_key "resource.$r")" in resolves*) ;; *) unreached+="$r, " ;; esac
    done
    if [[ -z "$unreached" ]]; then outcome "done"
    else outcome "left open" "not reachable on this machine: ${unreached%, } — kit/setup.sh link"; fi
fi

# --- 7 · Restart Claude Code and approve the plugins ------------------------------------------------
stage 7 $TOTAL "Restart Claude Code and approve the plugins"
say "Claude Code reads a repository's plugin settings only when a session starts in it, and only once"
say "the person has trusted that folder. It then offers to install the kit's marketplace, from kit/, and"
say "its three plugins, whose hooks come with them. Each person does this once, in their own first session."
echo
if ! attended; then
    outcome skipped "unattended run; each person does this once, in Claude Code"
else
    step "1. Close any Claude Code session already open in this workspace."
    step "2. Start a new one there:  cd $(printf '%q' "$T") && claude"
    step "3. Trust the folder when it asks: this folder itself, not only a folder above it."
    step "4. Accept the offer to install the agentic-workspace marketplace and its three plugins. Their"
    step "   hooks come with them. closeout has two: one keeps a draft when a session ends, one offers it"
    step "   when the next one starts. projects has one: the line that says where a project stands when a"
    step "   session opens in its folder. workspace has two: the line that names anything out of step when a"
    step "   session opens, and a guard that keeps an agent from bypassing the git hooks."
    step "5. Type /plugin and check that closeout, projects and workspace are listed from agentic-workspace,"
    step "   at $T/kit."
    step "6. If agentic-workspace is listed at another path, your user settings still name it there (a"
    step "   workspace moved from the 2.x layout does this). Re-point the user entry alone: a remove without"
    step "   --scope user also takes the marketplace and the three plugins out of this workspace's"
    step "   .claude/settings.json, and uninstalls them. Quit Claude Code, then run these one at a time:"
    step "     claude plugin marketplace remove --scope user agentic-workspace"
    step "     claude plugin marketplace add --scope user $(printf '%q' "$T/kit")"
    step "     claude plugin install closeout@agentic-workspace"
    step "     claude plugin install projects@agentic-workspace"
    step "     claude plugin install workspace@agentic-workspace"
    step "     git -C $(printf '%q' "$T") diff -- .claude/settings.json"
    step "   The last one prints nothing when the workspace's settings are as committed. If it prints a"
    step "   change, put the file back:"
    step "     git -C $(printf '%q' "$T") checkout -- .claude/settings.json"
    step "   Then start Claude Code again in this folder."
    echo
    [[ "$optional" != *claude* ]] || warn "claude is not on PATH yet: install Claude Code first (stage 1 has the link)."
    note "The settings this workspace gives Claude Code register: $(state_key plugins_registered)"
    echo
    if confirm "Were all three listed?" y; then
        outcome "done"
    else
        step "If none are listed: quit Claude Code and start it again in this folder itself, trust it, and"
        step "accept the install offer. If a plugin is listed but disabled, enable it from /plugin."
        outcome "left open" "the plugins were not all listed"
    fi
fi

# --- 8 · Cowork -------------------------------------------------------------------------------------
stage 8 $TOTAL "Cowork"
if [[ $COWORK -eq 0 ]]; then
    say "For teams that also work in Cowork, Claude's desktop app. Off by default: run kit/setup.sh again"
    say "with --cowork to include it. The stages already done are skipped."
    outcome skipped "off by default; --cowork includes it"
else
    cw=""
    say "Cowork does not read this workspace's .claude/settings.json, so the kit's plugins and hooks do"
    say "not load there. It works in a folder you add, and reads the kit's commands as skills."
    echo
    bold "a. Add the folder"; echo
    step "In the Claude desktop app, open Cowork and add this workspace with Add folder:"
    step "  $T"
    pause "Press Enter once it is added."
    echo
    bold "b. The skills bridge"; echo
    say "  One kit- skill per kit command, and a copy of each of your own skills in skills/, written into"
    say "  .claude/skills/ as real folders. Cowork's scanner does not follow links."
    bridge="$("${BASH:-bash}" "$T/kit/scripts/skills-bridge.sh" --target "$T" </dev/null 2>&1)"; rc=$?
    printf '%s\n' "$bridge" | sed 's/^/    /'
    state_check "$T"
    if [[ $rc -ne 0 ]] || ! key_is skills_bridge present; then cw+="the bridge did not finish (kit/setup.sh skills); "
    elif printf '%s\n' "$bridge" | grep -q '^ *clash '; then cw+="clashes in .claude/skills/, named above; "
    else note "Cowork reads skills when a session starts: they appear in the next session, not this one."; fi
    note "kit/setup.sh skills refreshes the bridge; run it from a terminal after an update."
    echo
    bold "c. Scheduled tasks"; echo
    step "In Cowork, a scheduled task runs a skill on a cadence. Two fit the kit, both in this folder:"
    step "  weekly    kit-workspace-hygiene"
    step "  monthly   kit-workspace-register-audit"
    step "Create them from Cowork's scheduled tasks, each with a prompt such as \"Run the kit-workspace-hygiene"
    step "skill in this folder and write its report to audits/\"."
    if attended; then
        confirm "Folder added and tasks set up, or left for later on purpose?" y || cw+="the folder or the scheduled tasks; "
    else
        cw+="adding the folder in Cowork is the person's step; "
    fi
    if [[ -z "$cw" ]]; then outcome "done"; else outcome "left open" "${cw%; }"; fi
fi

# --- 9 · Verify -------------------------------------------------------------------------------------
stage 9 $TOTAL "Verify"
state_check "$T"
off=0
# fix <command>: what puts a failing check right, under it.
fix() { step "  $*"; off=$((off + 1)); }
check "git hooks active in the workspace (hooks=$(state_key hooks))" key_is hooks active || fix "kit/setup.sh hooks"
check "git hooks active in the kit (kit_hooks=$(state_key kit_hooks))" key_is kit_hooks active || fix "kit/setup.sh hooks"
if ! check "CLAUDE.md imports the kit's standards (kit_import=$(state_key kit_import))" key_is kit_import ok; then
    if key_is kit_import broken; then fix "git submodule update --init kit"
    else fix "make the first line of CLAUDE.md @kit/CLAUDE.kit.md"; fi
fi
check "the ledger, .claude/kit-templates.lock" key_is ledger present || fix "kit/setup.sh --reinstall"
check "workspace settings, .claude/workspace.md" key_is workspace_conventions present || fix "kit/setup.sh --reinstall"
check "plugins registered: closeout, projects, workspace" key_is plugins_registered closeout,projects,workspace \
    || fix "compare .claude/settings.json with kit/templates/workspace/settings.json (it registers: $(state_key plugins_registered))"
check "the plugins come from kit/ (plugins_mode=$(state_key plugins_mode))" key_is plugins_mode kit || fix "kit/setup.sh migrate --dry-run"
check "submodule settings (submodule_config=$(state_key submodule_config))" key_is submodule_config ok || fix "kit/setup.sh"
vis="$(state_key origin_visibility)"
if check "origin is private or not set yet (origin_visibility=$vis)" test "$vis" = private -o "$vis" = none; then
    # A record is only a record; where gh can ask GitHub again, it does.
    gh_repo="$(origin_github "$(state_key origin)")"
    if [[ $vis == private && -n "$gh_repo" ]] && [[ "$(gh_visibility "$gh_repo")" == PUBLIC ]]; then
        warn "GitHub now says $(state_key origin) is public, though .claude/workspace.md records it as private."
        fix "make the repository private in its settings on GitHub"
    fi
else
    fix "kit/setup.sh records origin once it is confirmed private (stage 4)"
fi
check "every outside folder reachable here" key_is external_paths_missing "" || fix "kit/setup.sh link"
check "no sensitive project tracked by the workspace" key_is sensitive_tracked "" \
    || fix "/projects:adopt <slug> untracked, for each of: $(state_key sensitive_tracked)"
check "every gitlink registered in .gitmodules" key_is orphan_gitlinks "" || fix "kit/setup.sh migrate --dry-run names the two fixes"
check "no 2.x traces" key_is legacy "" || fix "kit/setup.sh migrate --dry-run"
if [[ $PILOT -eq 1 ]]; then
    check "the pilot build list, pilot/build-list.md" key_is build_list present || fix "kit/setup.sh --pilot --reinstall"
fi
echo
note "State check: mode=$(state_key mode)"
if [[ $off -eq 0 ]]; then outcome "done"; else outcome "left open" "$off to look at, named above"; fi

# --- 10 · Finish ------------------------------------------------------------------------------------
stage 10 $TOTAL "Finish"
WZ_SUMMARY+=("10. Finish: done")
finish
echo
say "From here, open Claude Code in $T and run /workspace:quick-start."
case "$(state_key mode)" in
    fresh) say "It interviews the team for what a script cannot ask; $(state_key standins_remaining) answers in CLAUDE.md are still stand-ins." ;;
    joining) say "The team part is done, so it asks only the personal part: your profile and how you work." ;;
    existing-system) say "It maps the system that was here first onto the kit, and changes nothing without a yes." ;;
    nothing-left) say "Everything is set up, and it will say so. /projects:new starts a project." ;;
esac
if [[ $PILOT -eq 1 ]]; then
    say "Pilot: put the team's build list into pilot/build-list.md, commit, then run bash kit/pilot/measure.sh."
    say "Pilot: each person raises cleanupPeriodDays in their own Claude Code settings to the pilot's length in days (30 is the default), so the agent-read counts keep their transcripts. The kit does not write there."
fi
echo
say "Nothing is committed."
add=()
[[ $KIT_ADDED -eq 0 ]] || add+=(.gitmodules kit)
[[ ${#ENGINE_PATHS[@]} -eq 0 ]] || add+=(.claude/kit-templates.lock)
for p in ${ENGINE_PATHS[@]+"${ENGINE_PATHS[@]}"}; do
    case " ${add[*]-} " in *" $p "*) ;; *) add+=("$p") ;; esac
done
if [[ ${#add[@]} -gt 0 ]]; then
    msg="Set up the workspace with the agentic workspace kit"
    [[ $KIT_ADDED -eq 1 ]] || msg="Add the files the agentic workspace kit creates"
    say "The commit to make, when you are ready:"
    step "cd $(printf '%q' "$T")"
    line=""
    for p in "${add[@]}"; do line+=" $(printf '%q' "$p")"; done
    step "git add${line}"
    step "git commit -m \"$msg\""
else
    say "Review with: git -C $(printf '%q' "$T") status"
fi
exit 0
