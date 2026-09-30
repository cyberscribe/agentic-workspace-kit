#!/usr/bin/env bash
# lib/setup/update.sh: kit/setup.sh update. Brings a newer kit into the workspace and offers what came
# with it.
#
#   update.sh --target WS [--no-fetch]
#
# 1. A workspace still in the 2.x layout goes to the migration instead: its dry run is shown, and an
#    attended run is asked whether to run it for real.
# 2. The kit submodule is advanced (git submodule update --remote -- kit). The rest then runs from the
#    new kit's own copy of this script (--after-advance), so the steps below are the new kit's.
# 3. The CHANGELOG since the old version is printed.
# 4. Each template the kit changed since a file of yours was made from it is offered as a diff, one at
#    a time (an attended run asks; an unattended one lists them and records nothing). Lines the kit
#    added to its .gitignore template are offered as one diff.
# 5. The engine runs again, creating any file of yours a newer kit adds; the skills bridge is refreshed
#    when it is in use; the session-start summary is printed.
# 6. The one commit to make is printed. Nothing is committed here.
#
# Exit status: 0 finished, 1 stopped, 2 usage.
# shellcheck source-path=SCRIPTDIR/../..
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=lib/wizard.sh
. "$KIT/lib/wizard.sh"
# shellcheck source=lib/common.sh
. "$KIT/lib/common.sh"
# shellcheck disable=SC2034  # read by lib/wizard.sh
WZ_STATE_SH="$KIT/plugins/workspace/bin/state.sh"

WS="" NO_FETCH=0 AFTER=0 OLD=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target|--old)
            [[ $# -ge 2 ]] || { echo "update.sh: $1 needs a value" >&2; exit 2; }
            if [[ $1 == --target ]]; then WS="$2"; else OLD="$2"; fi
            shift 2 ;;
        --no-fetch) NO_FETCH=1; shift ;;
        --after-advance) AFTER=1; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "update.sh: unknown option $1" >&2; exit 2 ;;
    esac
done
[[ "$WS" == /* ]] || { echo "update.sh: --target takes the workspace's absolute path" >&2; exit 2; }
[[ -d "$WS" ]] || { echo "update.sh: no folder at $WS" >&2; exit 1; }
[[ $AFTER -eq 0 || -n "$OLD" ]] || { echo "update.sh: --after-advance needs --old" >&2; exit 2; }

WG=(git --no-optional-locks -C "$WS")
KG=(git --no-optional-locks -C "$WS/kit")
# version_of <changelog text on stdin>: the first "## v" heading's version, v dropped.
version_of() { awk '/^## v[0-9]/ { v = $2; sub(/^v/, "", v); print v; exit }'; }
# is_local_url <url>: a path or file:// URL, which git fetches only with protocol.file.allow=always.
is_local_url() {
    case "$1" in file://*) return 0 ;; *://*) return 1 ;; esac
    local lhs="${1%%:*}"
    [[ "$1" == *:* && "$lhs" != */* && -n "$lhs" ]] && return 1
    return 0
}

if [[ $AFTER -eq 0 ]]; then
    # --- Layout check -------------------------------------------------------------------------------
    state_check "$WS"
    if layout_2x "$WS"; then
        say "This workspace has the 2.x layout; the migration moves it to 3.0."
        echo
        "${BASH:-bash}" "$KIT/lib/setup/migrate.sh" --target "$WS" --dry-run; rc=$?
        if [[ $rc -eq 0 ]] && attended; then
            echo
            if confirm "Run the migration now?" n; then
                "${BASH:-bash}" "$KIT/lib/setup/migrate.sh" --target "$WS"; rc=$?
            fi
        fi
        exit $rc
    fi
    if [[ "$("${WG[@]}" ls-files -s -- kit 2>/dev/null | awk '$1 == "160000" { print "y"; exit }')" != y ]]; then
        say "kit/ is not a submodule of $WS, so there is nothing to advance."
        say "kit/setup.sh new starts a workspace with it; kit/setup.sh --target DIR adds it to a repository."
        exit 1
    fi
    old="$("${KG[@]}" rev-parse HEAD 2>/dev/null)" || { say "The kit at $WS/kit is not checked out: git submodule update --init kit"; exit 1; }
    old_version="$(version_of <"$WS/kit/CHANGELOG.md" 2>/dev/null)"

    # --- Advance ------------------------------------------------------------------------------------
    name="$(aw_kitname "$WS")"
    url="$("${WG[@]}" config "submodule.$name.url" 2>/dev/null)"
    [[ -n "$url" ]] || url="$("${WG[@]}" config -f .gitmodules "submodule.$name.url" 2>/dev/null)"
    pc=(); is_local_url "$url" && pc=(-c protocol.file.allow=always)
    nf=(); [[ $NO_FETCH -eq 0 ]] || nf=(--no-fetch)
    say "The kit is at ${old_version:-an unknown version} ($(printf '%.7s' "$old")). Advancing it:"
    step "git submodule update --remote${nf[*]+ ${nf[*]}} -- kit"
    # pipefail is on, so the pipeline fails when git does.
    if ! "${WG[@]}" ${pc[@]+"${pc[@]}"} submodule update --remote ${nf[@]+"${nf[@]}"} -- kit 2>&1 | sed 's/^/    /'; then
        say "The kit could not be advanced; nothing else was done."
        exit 1
    fi
    if [[ ! -f "$WS/kit/lib/setup/update.sh" ]]; then
        say "The new kit has no lib/setup/update.sh; nothing more to do here."
        exit 1
    fi
    # The rest runs from the kit just checked out, so a newer kit's steps are the ones taken.
    exec "${BASH:-bash}" "$WS/kit/lib/setup/update.sh" --target "$WS" --after-advance --old "$old" ${nf[@]+"${nf[@]}"}
fi

# --- After the advance, from the new kit ------------------------------------------------------------
new="$("${KG[@]}" rev-parse HEAD 2>/dev/null)"
new_version="$(version_of <"$WS/kit/CHANGELOG.md" 2>/dev/null)"
old_version="$("${KG[@]}" show "$OLD:CHANGELOG.md" 2>/dev/null | version_of)"
offer=1
if [[ "$new" == "$OLD" ]]; then
    say "The kit is already at ${new_version:-an unknown version} ($(printf '%.7s' "$new"))."
else
    echo
    say "Kit ${old_version:-?} ($(printf '%.7s' "$OLD")) -> ${new_version:-?} ($(printf '%.7s' "$new")). What changed:"
    echo
    # From the top down to the old version's heading; the same version, the diff; else the first 60 lines.
    if [[ -n "$old_version" && "$old_version" == "$new_version" ]]; then
        "${KG[@]}" diff --no-color "$OLD..HEAD" -- CHANGELOG.md
    elif [[ -n "$old_version" ]] && excerpt="$(awk -v v="## v$old_version" '
            index($0, v) == 1 && substr($0, length(v) + 1, 1) !~ /[0-9.]/ { found = 1; exit }
            { print }
            END { exit !found }' "$WS/kit/CHANGELOG.md" 2>/dev/null)"; then
        printf '%s\n' "$excerpt"
    else
        sed -n '1,60p' "$WS/kit/CHANGELOG.md" 2>/dev/null
    fi
    if [[ -n "$old_version" && -n "$new_version" && "${old_version%%.*}" != "${new_version%%.*}" ]]; then
        state_check "$WS"
        if layout_2x "$WS"; then
            echo
            say "This is a major release: kit/setup.sh migrate --dry-run shows what moves."
            offer=0
        fi
    fi
fi

# --- Template diffs ---------------------------------------------------------------------------------
ACCEPTED=() GITIGNORE_ADDED=0 RECORDED=0
if [[ $offer -eq 1 ]]; then
    status_out="$("${BASH:-bash}" "$WS/kit/install.sh" --template-status --target "$WS" 2>/dev/null)"; rc=$?
    if [[ $rc -ne 0 ]]; then
        warn "the engine could not report on your files' templates (kit/install.sh --template-status, status $rc)"
        status_out=""
    fi
    listed=0
    diff_file="$(mktemp "${TMPDIR:-/tmp}/aw-update.XXXXXX")" || exit 1
    echo
    while IFS=$'\t' read -r -u 3 st dest src; do
        case "$st" in
            changed)
                "${BASH:-bash}" "$WS/kit/install.sh" --template-diff "$dest" --target "$WS" >"$diff_file" 2>/dev/null; drc=$?
                if [[ $drc -eq 3 ]]; then
                    # The template changed in a way that renders the same for this workspace.
                    if attended; then
                        "${BASH:-bash}" "$WS/kit/install.sh" --template-record "$dest" --status accepted --target "$WS" >/dev/null 2>&1 \
                            && RECORDED=1
                    fi
                    continue
                fi
                if [[ $drc -ne 0 ]]; then
                    say "Template changed: $dest (from kit/$src). No earlier version to compare with; compare the two by hand."
                    continue
                fi
                listed=$((listed + 1))
                if ! attended; then
                    step "changed   $dest  (from kit/$src; kit/setup.sh update, run at a terminal, offers the diff)"
                    continue
                fi
                bold "The kit's template for $dest has changed:"; echo
                cat "$diff_file"
                echo
                if confirm "Apply this change to $dest?" n; then
                    if "${WG[@]}" apply --check "$diff_file" >/dev/null 2>&1 && "${WG[@]}" apply "$diff_file"; then
                        "${BASH:-bash}" "$WS/kit/install.sh" --template-record "$dest" --status accepted --target "$WS" >/dev/null 2>&1
                        ACCEPTED+=("$dest"); RECORDED=1
                        check "applied to $dest" true
                    else
                        say "  The diff does not apply to $dest as it is now: left for hand merging."
                    fi
                else
                    "${BASH:-bash}" "$WS/kit/install.sh" --template-record "$dest" --status skipped --target "$WS" >/dev/null 2>&1
                    RECORDED=1
                    note "skipped; offered again only if the template changes again"
                fi ;;
            changed-no-base)
                listed=$((listed + 1))
                say "Template changed: $dest (from kit/$src). The kit's earlier version is not in this clone; compare $dest with kit/$src by hand." ;;
        esac
    done 3<<EOF
$status_out
EOF
    rm -f "$diff_file"

    # .gitignore: the template's lines the file does not have yet, as one diff (the engine exits 3 when
    # none is missing).
    if [[ -f "$WS/.gitignore" ]]; then
        gi_diff="$(mktemp "${TMPDIR:-/tmp}/aw-update-gitignore.XXXXXX")" || exit 1
        "${BASH:-bash}" "$WS/kit/install.sh" --target "$WS" --gitignore offer >"$gi_diff" 2>/dev/null; grc=$?
        missing="$(sed -n 's/^+\([^+].*\)$/\1/p' "$gi_diff" | grep -v '^#')"
        if [[ $grc -eq 0 && -n "$missing" ]]; then
            listed=$((listed + 1))
            bold "Lines the kit's .gitignore template has and yours does not:"; echo
            cat "$gi_diff"
            echo
            if ! attended; then
                note "unattended: nothing added; kit/setup.sh update, run at a terminal, offers them"
            elif confirm "Add them to .gitignore?" y; then
                if "${WG[@]}" apply --check "$gi_diff" >/dev/null 2>&1 && "${WG[@]}" apply "$gi_diff"; then
                    GITIGNORE_ADDED=1; check "added to .gitignore" true
                elif "${BASH:-bash}" "$WS/kit/install.sh" --target "$WS" --gitignore merge >/dev/null 2>&1; then
                    GITIGNORE_ADDED=1; check "added to .gitignore" true
                else
                    warn "the lines could not be added; .gitignore is as it was"
                fi
            else
                while IFS= read -r l; do
                    [[ -z "$l" ]] || "${BASH:-bash}" "$WS/kit/install.sh" --gitignore-decline "$l" --target "$WS" >/dev/null 2>&1
                done <<EOF
$missing
EOF
                RECORDED=1
                note "declined; these lines are not offered again"
            fi
        fi
        rm -f "$gi_diff"
    fi
    [[ $listed -gt 0 ]] || say "No template changes to offer."
fi

# --- The engine, the bridge, and the summary --------------------------------------------------------
echo
ENGINE_PATHS=()
out="$("${BASH:-bash}" "$WS/kit/install.sh" --target "$WS" </dev/null 2>&1)"; rc=$?
if [[ $rc -ne 0 ]]; then
    warn "kit/install.sh stopped with status $rc:"
    printf '%s\n' "$out" | tail -n 6 | sed 's/^/    /'
else
    # section <heading>: the indented items under one heading of the engine's report.
    section() { printf '%s\n' "$out" | awk -v h="$1" 'index($0, h) == 1 { on = 1; next } on && /^  / { print; next } on { exit }'; }
    created="$(section "Created (")" merged="$(section "Merged (")"
    while read -r p _; do [[ -z "$p" ]] || ENGINE_PATHS+=("$p"); done <<EOF
$created
$merged
EOF
    [[ -z "$(section "Added to .gitignore:")" ]] || ENGINE_PATHS+=(.gitignore)
    [[ -z "$created" ]] || { say "Created for you, new with this kit:"; printf '%s\n' "$created"; }
    [[ -z "$merged" ]] || { say "Settings: the kit's marketplace path added:"; printf '%s\n' "$merged"; }
    worth="$(section "Worth knowing:")"
    [[ -z "$worth" ]] || { say "Worth knowing:"; printf '%s\n' "$worth"; }
fi
if [[ -f "$WS/.claude/skills/.kit-generated" ]]; then
    say "The skills bridge:"
    "${BASH:-bash}" "$WS/kit/scripts/skills-bridge.sh" --target "$WS" </dev/null 2>&1 | sed 's/^/  /'
fi
# The same lines a session opens with, from the workspace plugin's own hook.
hook="$WS/kit/plugins/workspace/hooks/session-start.sh"
if command -v jq >/dev/null 2>&1 && [[ -f "$hook" ]]; then
    summary="$(jq -n --arg c "$WS" '{cwd: $c, hook_event_name: "SessionStart", source: "startup"}' \
        | env -u AW_HEADLESS_RUN -u CLOSEOUT_HOOK_CHILD -u WORKSPACE_HOOK_DISABLED "${BASH:-bash}" "$hook" 2>/dev/null)"; rc=$?
    if [[ $rc -ne 0 ]]; then
        note "the session-start summary could not run here (kit/plugins/workspace/hooks/session-start.sh, status $rc)"
    else
        summary="$(printf '%s' "$summary" | jq -r '.systemMessage // empty' 2>/dev/null)"
        echo
        if [[ -n "$summary" ]]; then printf '%s\n' "$summary"; else say "Workspace: nothing out of step."; fi
    fi
fi

# --- The commit -------------------------------------------------------------------------------------
add=(kit .claude/kit-templates.lock)
for p in ${ACCEPTED[@]+"${ACCEPTED[@]}"} ${ENGINE_PATHS[@]+"${ENGINE_PATHS[@]}"}; do
    case " ${add[*]} " in *" $p "*) ;; *) add+=("$p") ;; esac
done
[[ $GITIGNORE_ADDED -eq 0 ]] || case " ${add[*]} " in *" .gitignore "*) ;; *) add+=(.gitignore) ;; esac
# A workspace with no commit yet has its first commit still to make: the plan names everything that
# commit takes, not only what this update touched, so following it leaves nothing out.
first_commit=0
if ! "${WG[@]}" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    first_commit=1
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        case " ${add[*]} " in *" $p "*) ;; *) add+=("$p") ;; esac
    done < <("${WG[@]}" ls-files -co --exclude-standard 2>/dev/null)
fi
pointer_moved=1
if "${WG[@]}" rev-parse -q --verify HEAD >/dev/null 2>&1 && "${WG[@]}" diff --quiet --ignore-submodules=dirty HEAD -- kit 2>/dev/null; then pointer_moved=0; fi
echo
if [[ $pointer_moved -eq 0 && $RECORDED -eq 0 && ${#ACCEPTED[@]} -eq 0 && ${#ENGINE_PATHS[@]} -eq 0 && $GITIGNORE_ADDED -eq 0 ]]; then
    say "Nothing to commit: the kit and your files are as the last commit has them."
    exit 0
fi
if [[ -n "$old_version" && "$old_version" != "$new_version" ]]; then msg="Kit $old_version -> ${new_version:-?}"
elif [[ "$new" != "$OLD" ]]; then msg="Kit ${new_version:-?} ($(printf '%.7s' "$OLD") -> $(printf '%.7s' "$new"))"
else msg="Kit ${new_version:-?}"; fi
if [[ $first_commit -eq 1 ]]; then say "Nothing is committed here yet, so this is the first commit, with everything setup created:"
else say "Commit to make, when you are ready:"; fi
step "git add ${add[*]}"
step "git commit -m \"$msg\""
exit 0
