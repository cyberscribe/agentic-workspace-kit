#!/usr/bin/env bash
# The setup wizard: puts the kit into a team's shared repository, one stage per screen, including the
# steps no script can take for the team: merging the kit's versions of files the team already had,
# restarting Claude Code and trusting the folder so the plugins install. install.sh does the laying down; this runs it
# and walks the person through what comes around it. A pilot team is told one thing: run setup.sh.
#
#   ./setup.sh                    asks for what it needs
#   ./setup.sh --target ../team-workspace --team "Data Platform" --owner "Sam" --owner-handle "@sam" --pilot
#
# Options:
#   --target DIR          the team's shared repository
#   --team NAME           team name
#   --owner NAME          standards owner, who reviews changes to the always-loaded file
#   --owner-handle @h     their GitHub or GitLab handle, for CODEOWNERS
#   --pilot               add the pilot layer: protocol, build list and the metrics script
#   --init                create DIR and git init it when it is not a repository yet (asked otherwise)
#   --cowork              include stage 6, for teams that also work in Cowork (off by default)
#   --reinstall           run install.sh again even when the kit is laid down, to bring in a newer kit
#   -h, --help            this text
#
# Each stage reads the state check (plugins/workspace/bin/state.sh) before it acts, so a re-run skips
# what is done: Ctrl-C and run it again is the way back. Nothing is overwritten and nothing is deleted.
# AW_WIZARD_NONINTERACTIVE=1 runs it unattended, for the tests: every question takes its default, and
# the stages only a person can do (4, 5 and 6) are skipped. With no terminal on stdin it runs the same way.
# install.sh stays the scriptable path, with every option; this is the guided one.
#
# Stages, and the state check keys each one's outcome is read from:
#   1 Prerequisites                       git, jq and claude on PATH; the bash version
#   2 Target and identity                 in_git; team and owner from AGENTS.md, handle from CODEOWNERS
#   3 Lay down the kit                    agents_md, projects_conventions, closeout_conventions,
#                                         plugins_registered, build_list (with --pilot)
#   4 Merge the kit's versions            kit_incoming, mode
#   5 Restart Claude Code, trust folder   the person's word; plugins_registered is shown beside it
#   6 Cowork                              the skills folder: generated SKILL.md files, and no links
#   7 Verify                              the keys of stages 3 and 4, then mode
#   8 Finish                              mode, which decides what the quick-start does first
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/wizard.sh
. "$KIT/lib/wizard.sh"
# shellcheck disable=SC2034  # read by lib/wizard.sh
WZ_STATE_SH="$KIT/plugins/workspace/bin/state.sh"

TARGET="" TEAM="" OWNER="" HANDLE="" PILOT=0 INIT=0 COWORK=0 REINSTALL=0
usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="${2:-}"; shift 2 ;;
        --team) TEAM="${2:-}"; shift 2 ;;
        --owner) OWNER="${2:-}"; shift 2 ;;
        --owner-handle) HANDLE="${2:-}"; shift 2 ;;
        --pilot) PILOT=1; shift ;;
        --init) INIT=1; shift ;;
        --cowork) COWORK=1; shift ;;
        --reinstall) REINSTALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "setup.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
done

TOTAL=8
WRITTEN="nothing this run"
# stop <why>: the stage ends here and so does the run, with the summary so far.
stop() { outcome stopped "$1"; echo; finish; exit 1; }
# recorded <sed-expression> <file>: a value an earlier install wrote into the target, or nothing.
recorded() { [[ -f "$TARGET/$2" ]] && sed -n "$1" "$TARGET/$2" 2>/dev/null | head -n 1; }
# An angle-bracketed value is the installer's stand-in, not an answer.
known() { [[ -n "$1" && "$1" != *'<'* ]]; }

banner "Workspace context kit: setup" \
    "Eight short stages. Enter takes the [default]; Ctrl-C stops, and running this again picks up where it stopped."

# --- 1 · Prerequisites ------------------------------------------------------------------------------
stage 1 $TOTAL "Prerequisites"
missing=""
# The installer and the state check are written for bash 3.2, what macOS ships.
if ! check "bash $BASH_VERSION (3.2 or later)" test "${BASH_VERSINFO[0]}${BASH_VERSINFO[1]}" -ge 32; then
    step "Install a newer bash, or run this with the system's /bin/bash."; missing+=" bash"
fi
if ! check "git" command -v git; then
    step "Install git: https://git-scm.com/downloads"; missing+=" git"
fi
if ! check "jq, which the installer and the state check read the settings with" command -v jq; then
    step "Install jq: brew install jq (macOS), apt install jq (Debian, Ubuntu), or https://jqlang.org/download/"
    missing+=" jq"
fi
claude_note=""
if ! check "claude, the Claude Code command line" command -v claude; then
    step "Install Claude Code before stage 5: https://docs.claude.com/en/docs/claude-code/setup"
    claude_note="claude still to install, before stage 5"
fi
[[ -z "$missing" ]] || stop "install$missing, then run setup.sh again"
outcome "already done" "$claude_note"

# --- 2 · Target and identity ------------------------------------------------------------------------
stage 2 $TOTAL "Target and identity"
say "The kit goes into the team's shared repository: the one place everyone's standards, projects and"
say "decisions live. Not a code repository."
echo
if [[ -z "$TARGET" ]]; then
    # Run from inside the kit's own checkout, there is no sensible default: the kit is not the target.
    def="$PWD"
    case "$(cd "$PWD" && pwd -P)/" in "$(cd "$KIT" && pwd -P)/"*) def="" ;; esac
    TARGET="$(ask "Path to the team's shared repository" "$def")"
fi
[[ -n "$TARGET" ]] || stop "no repository named: pass --target DIR"
case "$TARGET" in /*) ;; *) TARGET="$PWD/$TARGET" ;; esac
[[ ! -d "$TARGET" ]] || TARGET="$(cd "$TARGET" && pwd -P)"
case "$TARGET/" in "$(cd "$KIT" && pwd -P)/"*) stop "$TARGET is inside the kit's own checkout; name the team's repository" ;; esac

state_check "$TARGET"
case "$(state_key in_git)" in
    yes) ;;
    refused) stop "git will not read $TARGET as this user (safe.directory); see git config --help, safe.directory" ;;
    *)
        if [[ $INIT -eq 0 ]]; then
            what="make $TARGET a git repository"; [[ -d "$TARGET" ]] || what="create $TARGET as a new git repository"
            # The one step that cannot be undone by running again, so it is asked, and n is the default.
            attended && confirm "There is no repository to install into yet. OK to $what?" n && INIT=1
            [[ $INIT -eq 1 ]] || stop "not a git repository yet: re-run with --init to $what"
        fi ;;
esac

# What an earlier run answered, from the files it wrote; where the team kept a file of its own, the
# kit's version beside it (.kit-incoming) carries the same answers.
team_now="" owner_now="" handle_now=""
for sfx in "" .kit-incoming; do
    known "$team_now" || team_now="$(recorded 's/^| \*\*Team\*\* | \(.*\) |$/\1/p' "AGENTS.md$sfx")"
    known "$owner_now" || owner_now="$(recorded 's/^| \*\*Standards owner\*\* | \(.*\) — reviews.*/\1/p' "AGENTS.md$sfx")"
    known "$handle_now" || handle_now="$(recorded 's#^/AGENTS\.md[[:space:]][[:space:]]*\([^[:space:]]*\).*#\1#p' ".github/CODEOWNERS$sfx")"
done
known "$team_now" || team_now=""
known "$owner_now" || owner_now=""
known "$handle_now" || handle_now=""
# A measured pilot already under way keeps its pilot layer on a re-run.
[[ "$(state_key build_list)" != present ]] || PILOT=1

if key_is in_git yes && [[ -n "$team_now" && -n "$owner_now" ]] \
    && [[ -z "$TEAM" || "$TEAM" == "$team_now" ]] && [[ -z "$OWNER" || "$OWNER" == "$owner_now" ]] \
    && [[ -z "$HANDLE" || "$HANDLE" == "$handle_now" ]]; then
    TEAM="$team_now" OWNER="$owner_now" HANDLE="${handle_now:-$HANDLE}"
    step "Repository   $TARGET"
    step "Team         $TEAM"
    step "Owner        $OWNER ${HANDLE}"
    outcome "already done" "read from AGENTS.md and CODEOWNERS"
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
    step "Repository   $TARGET$([[ $INIT -eq 1 ]] && printf '  (stage 3 creates it)')"
    step "Team         ${TEAM:-<to fill in>}"
    step "Owner        ${OWNER:-<to fill in>} ${HANDLE}"
    step "Pilot        $([[ $PILOT -eq 1 ]] && echo yes || echo no)"
    # Once the kit is laid down, stage 3 does not write again without --reinstall, and even then only
    # beside the team's file; a new answer here would never reach AGENTS.md.
    changed=""
    [[ -n "$team_now" && -n "$TEAM" && "$TEAM" != "$team_now" ]] && changed+="team $team_now, "
    [[ -n "$owner_now" && -n "$OWNER" && "$OWNER" != "$owner_now" ]] && changed+="owner $owner_now, "
    [[ -n "$handle_now" && -n "$HANDLE" && "$HANDLE" != "$handle_now" ]] && changed+="handle $handle_now, "
    if [[ -n "$changed" ]]; then
        outcome "left open" "AGENTS.md and CODEOWNERS already name ${changed%, }; edit them there, or re-run with --reinstall to get a .kit-incoming"
    else
        outcome "done"
    fi
fi

# --- 3 · Lay down the kit ---------------------------------------------------------------------------
stage 3 $TOTAL "Lay down the kit"
# laid_down: the state check sees the kit's files, its conventions and the three plugins registered.
laid_down() {
    key_not agents_md missing && key_not agents_md "" && key_not projects_conventions missing \
        && key_is closeout_conventions present && key_is plugins_registered closeout,projects,workspace \
        && { [[ $PILOT -eq 0 ]] || key_is build_list present; }
}
state_check "$TARGET"
if laid_down && [[ $REINSTALL -eq 0 ]]; then
    check "the kit's files (agents_md=$(state_key agents_md))" true
    check "plugins registered: $(state_key plugins_registered)" true
    [[ $PILOT -eq 0 ]] || check "the pilot layer (pilot/build-list.md)" true
    note "To bring in a newer kit, run setup.sh again with --reinstall; changed files arrive as .kit-incoming."
    outcome "already done"
else
    args=(--target "$TARGET" --team "$TEAM" --owner "$OWNER" --owner-handle "$HANDLE")
    [[ $PILOT -eq 0 ]] || args+=(--pilot)
    [[ $INIT -eq 0 ]] || args+=(--init)
    # Keep how the plugins arrive as it is: fetched from GitHub stays fetched, and a kit checkout the
    # repository already registers (a submodule, say) is left to itself.
    case "$(state_key plugins_mode)" in
        github) args+=(--plugin github) ;;
        directory) args+=(--plugin none); note "The plugins come from $(state_key plugins_path), which install.sh leaves as it is." ;;
    esac
    say "install.sh lays the kit down. It never overwrites: where a file of yours differs, the kit's"
    say "version is written beside it as <file>.kit-incoming, for stage 4."
    echo
    step "$(printf '%q ' bash "$KIT/install.sh" "${args[@]}")"
    echo
    attended && ! confirm "Run it now?" y && stop "nothing written"
    out="$(bash "$KIT/install.sh" "${args[@]}" </dev/null 2>&1)"; rc=$?
    if [[ $rc -ne 0 ]]; then printf '%s\n' "$out" | tail -n 8 | sed 's/^/    /'; stop "install.sh stopped with status $rc"; fi
    # section <heading>: the indented lines under one heading of install.sh's report.
    section() { printf '%s\n' "$out" | awk -v h="$1" 'index($0, h) == 1 { on = 1; next } on && /^  / { print; next } on { exit }'; }
    added="$(section "Added:" | grep -c .)" merged="$(section "Merged (JSON" | grep -c .)"
    same="$(section "Already up to date:" | grep -c .)" kept="$(section "Existing file kept" | grep -c .)"
    WRITTEN="by install.sh: added $added, settings merged $merged, beside a file of yours $kept, already up to date $same"
    step "Added          $added"
    step "Merged         $merged"
    step "Up to date     $same"
    if [[ "$kept" -gt 0 ]]; then
        step "Written beside a file of yours, as .kit-incoming:"
        section "Existing file kept" | sed 's/^/  /'
    fi
    section "Worth knowing:" | sed 's/^/  /'
    state_check "$TARGET"
    if laid_down; then outcome "done"; else outcome "left open" "stage 7 names what is missing"; fi
fi

# --- 4 · Merge the kit's versions -------------------------------------------------------------------
stage 4 $TOTAL "Merge the kit's versions"
state_check "$TARGET"
incoming="$(state_key kit_incoming)"
n_in=0; [[ -z "$incoming" ]] || n_in="$(printf '%s' "$incoming" | tr ',' '\n' | grep -c .)"
if ! attended; then
    if [[ $n_in -eq 0 ]]; then outcome skipped "unattended run; nothing to merge"
    else outcome skipped "unattended run; to merge by hand: $incoming"; fi
elif [[ $n_in -eq 0 ]]; then
    say "Nothing to merge: the kit wrote no file beside one of yours."
    outcome "already done"
elif key_is mode existing-system; then
    say "These kit versions sit beside a system that was here first:"
    printf '%s\n' "$incoming" | tr ',' '\n' | sed 's/^/    /'
    echo
    say "Leave them for now. /workspace:quick-start maps that system onto the kit with you, and takes"
    say "these into account as it does."
    outcome skipped "the quick-start maps the existing system"
else
    say "For each pair: take what you want from the kit's version into your file, then delete the"
    say ".kit-incoming file. This wizard deletes nothing."
    # The list arrives on descriptor 3, so the questions inside the loop still read the terminal.
    while IFS= read -r -u 3 f; do
        [[ -n "$f" ]] || continue
        base="${f%.kit-incoming}"
        echo; bold "$base"; echo
        diff -u "$TARGET/$base" "$TARGET/$f" 2>/dev/null | sed -n '3,24p' | sed 's/^/    /'
        confirm "Open both files?" n && { open_path "$TARGET/$base"; open_path "$TARGET/$f"; }
        pause "Press Enter when this one is merged, or to leave it for later."
    done 3< <(printf '%s\n' "$incoming" | tr ',' '\n')
    state_check "$TARGET"
    left="$(state_key kit_incoming)"
    if [[ -z "$left" ]]; then outcome "done"; else outcome "left open" "still to merge: $left"; fi
fi

# --- 5 · Restart Claude Code and trust the folder ---------------------------------------------------
stage 5 $TOTAL "Restart Claude Code and trust the folder"
say "Claude Code reads a repository's plugin settings only when a session starts in it, and only once"
say "the person has trusted that folder. It then offers to install the kit's marketplace and plugins,"
say "and their hooks come with them. Each person does this once, in their own first session; no script"
say "can do it for them. Once it is done, the hooks run when a session opens and when it ends."
echo
if ! attended; then
    outcome skipped "unattended run; each person does this once, in Claude Code"
else
    step "1. Close any Claude Code session already open in this repository."
    step "2. Start a new one there:  cd $(printf '%q' "$TARGET") && claude"
    step "3. Trust the folder when it asks: this folder itself, not only a folder above it."
    step "4. Accept the offer to install the agentic-workspace marketplace and its three plugins. Their"
    step "   hooks come with them. closeout has two: one keeps a draft when a session ends, one offers it"
    step "   when the next one starts. projects has one: the line that says where a project stands when a"
    step "   session opens in its folder. workspace has none."
    step "5. Type /plugin and check that closeout, projects and workspace are listed from agentic-workspace."
    echo
    [[ -n "$claude_note" ]] && warn "claude is not on PATH yet: install Claude Code first (stage 1 has the link)."
    note "The settings this repository gives Claude Code register: $(state_key plugins_registered)"
    echo
    if confirm "Were all three listed?" y; then
        outcome "done"
    else
        step "If none are listed: quit Claude Code and start it again in this folder itself, trust it, and"
        step "accept the install offer. If a plugin is listed but disabled, enable it from /plugin. Trust"
        step "and the offer come once per person, so each person who joins does this in their first session."
        outcome "left open" "the plugins were not all listed"
    fi
fi

# --- 6 · Cowork -------------------------------------------------------------------------------------
stage 6 $TOTAL "Cowork"
if [[ $COWORK -eq 0 ]]; then
    say "For teams that also work in Cowork, Claude's desktop app. Off by default: run setup.sh again with"
    say "--cowork to include it. The stages already done are skipped."
    outcome skipped "off by default; --cowork includes it"
elif ! attended; then
    outcome skipped "unattended run"
else
    cw=""
    say "Cowork does not read this repository's .claude/settings.json, so the kit's plugins and hooks do"
    say "not load there. It works in a folder you add and reads the kit's commands as skills. Three steps."
    echo
    bold "a. Add the folder"; echo
    step "In the Claude desktop app, open Cowork and add this repository with Add folder:"
    step "  $TARGET"
    pause "Press Enter once it is added."
    echo
    bold "b. The skills, as copies"; echo
    say "  One skill per command (closeout, projects-board, workspace-quick-start and the rest), written"
    say "  as real files. Cowork's scanner does not follow links, so a linked skill would not be seen."
    sdir="$(ask "Folder Cowork loads skills from" "$TARGET/.claude/skills")"
    if confirm "Write the skills there now?" y; then
        if bash "$KIT/install.sh" --skills-only --target "$TARGET" --skills-dir "$sdir" </dev/null >/dev/null 2>&1; then
            n_sk="$(grep -ls 'Generated by install.sh' "$sdir"/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
            check "$n_sk skills in $sdir" test "$n_sk" -gt 0 || cw+="skills not written; "
            check "every one a folder of its own, not a link" test -z "$(find "$sdir" -mindepth 1 -maxdepth 1 -type l 2>/dev/null)" \
                || cw+="links in the skills folder; "
            note "Cowork reads skills when a session starts: they appear in the next session, not this one."
        else
            warn "install.sh --skills-only stopped; run it by hand to see why."; cw+="skills not written; "
        fi
    else
        cw+="skills not written; "
    fi
    echo
    bold "c. Scheduled tasks"; echo
    step "In Cowork, a scheduled task runs a skill on a cadence. Two fit the kit, both in this folder:"
    step "  weekly    workspace-hygiene"
    step "  monthly   workspace-register-audit"
    step "Create them from Cowork's scheduled tasks, each with a prompt such as \"Run the workspace-hygiene"
    step "skill in this folder and write its report to audits/\"."
    confirm "Set up now, or left for later on purpose?" y || cw+="scheduled tasks not set up; "
    if [[ -z "$cw" ]]; then outcome "done"; else outcome "left open" "${cw%; }"; fi
fi

# --- 7 · Verify -------------------------------------------------------------------------------------
stage 7 $TOTAL "Verify"
state_check "$TARGET"
off=0
check "the always-loaded file: AGENTS.md is $(state_key agents_md), $(state_key always_loaded) is what Claude Code loads" key_not agents_md missing \
    || { step "  Run stage 3 again: setup.sh --reinstall"; off=$((off + 1)); }
check "project conventions in .claude/projects.md ($(state_key projects_conventions))" key_not projects_conventions missing \
    || { step "  Run stage 3 again: setup.sh --reinstall"; off=$((off + 1)); }
check "closeout conventions in .claude/closeout.md" key_is closeout_conventions present \
    || { step "  Run stage 3 again: setup.sh --reinstall"; off=$((off + 1)); }
check "plugins registered: closeout, projects, workspace" key_is plugins_registered closeout,projects,workspace \
    || { step "  .claude/settings.json registers: $(state_key plugins_registered). Run stage 3 again."; off=$((off + 1)); }
if ! check "no .kit-incoming file waiting" key_is kit_incoming ""; then
    if key_is mode existing-system; then step "  For /workspace:quick-start to map: $(state_key kit_incoming)"
    else step "  Still to merge (stage 4): $(state_key kit_incoming)"; fi
    off=$((off + 1))
fi
if [[ $PILOT -eq 1 ]]; then
    check "the pilot build list, pilot/build-list.md" key_is build_list present || { step "  Run stage 3 again with --pilot."; off=$((off + 1)); }
fi
echo
note "State check: mode=$(state_key mode)"
if [[ $off -eq 0 ]]; then outcome "done"; else outcome "left open" "$off to look at, named above"; fi

# --- 8 · Finish -------------------------------------------------------------------------------------
stage 8 $TOTAL "Finish"
WZ_SUMMARY+=("8. Finish: done")
finish
echo
say "Written: $WRITTEN."
echo
say "From here, open Claude Code in $TARGET and run /workspace:quick-start."
case "$(state_key mode)" in
    fresh) say "It interviews the team for what a script cannot ask; $(state_key standins_remaining) answers in $(state_key always_loaded) are still stand-ins." ;;
    joining) say "The team part is done, so it asks only the personal part: your profile and how you work." ;;
    existing-system) say "It maps the system that was here first onto the kit, and changes nothing without a yes." ;;
    nothing-left) say "Everything is set up, and it will say so. /projects:new starts a project." ;;
esac
if [[ $PILOT -eq 1 ]]; then
    say "Pilot: put the team's build list into pilot/build-list.md, commit, then run pilot/measure.sh."
    say "Context ablations run from the kit's own copy: $KIT/pilot/ablate.sh --target $TARGET"
fi
say "Nothing is committed. Review with: git -C $(printf '%q' "$TARGET") status"
exit 0
