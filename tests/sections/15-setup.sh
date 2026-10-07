# shellcheck shell=bash
# The prelude in tests/run.sh defines st_bash, kitsrc_ok and the rest; checks are written "cond && ok || ko"
# as in run.sh, and the stubs written below are single-quoted on purpose.
# shellcheck disable=SC2154,SC2015,SC2016
# Section 15: kit/setup.sh — the ten stages, new and adopt, the dispatch table, update, --developer,
# hooks, and scripts/build-template.sh. Sourced by tests/run.sh after section 11; every name here
# carries the s15_ prefix, and everything is written under $SCRATCH.
#
# Some checks need other components (the engine, the state keys, the git hooks). While one of those
# is still a placeholder, the check that needs it is a SKIP naming it; the rest run on their own.
echo
echo "15 · Setup: the ten stages, new, adopt, the modes, update, developer mode and the template repository"

s15_setup="$KIT/setup.sh"
s15_files=(setup.sh lib/wizard.sh lib/setup/update.sh lib/setup/developer.sh scripts/build-template.sh)
# s15_built <kit path>: the file is there and is not a wave-0 placeholder.
s15_built() { [[ -f "$KIT/$1" ]] && ! grep -q 'not built yet' "$KIT/$1" 2>/dev/null; }
# s15_need <component...>: 0 when every named component is built; otherwise s15_why names the missing.
s15_need() {
    local c; s15_why=""
    for c in "$@"; do
        case "$c" in
            engine) grep -q -- '--template-status' "$KIT/install.sh" 2>/dev/null || s15_why+="the 3.0 engine (install.sh, C2), " ;;
            state) grep -q 'kit_import' "$STATE" 2>/dev/null || s15_why+="the 3.0 state keys (state.sh, C4), " ;;
            hooks) { s15_built lib/setup/gitconfig.sh && s15_built githooks/pre-push; } || s15_why+="the git hooks (gitconfig.sh and githooks, C1), " ;;
            migrate) s15_built lib/setup/migrate.sh || s15_why+="the migration (migrate.sh, C8), " ;;
            session) s15_built plugins/workspace/hooks/session-start.sh || s15_why+="the session-start hook (C4), " ;;
            link) s15_built lib/setup/link.sh || s15_why+="the resource links (link.sh, C6), " ;;
            bridge) s15_built scripts/skills-bridge.sh || s15_why+="the skills bridge (skills-bridge.sh, C7), " ;;
            kitsrc) [[ $kitsrc_ok -eq 1 ]] || s15_why+="KITSRC (the kit is not a git checkout), " ;;
            mkws2x) git --no-optional-locks -C "$KIT" cat-file -e '915c528^{commit}' 2>/dev/null || s15_why+="915c528 (a shallow clone), " ;;
        esac
    done
    s15_why="${s15_why%, }"
    [[ -z "$s15_why" ]]
}
# s15_outcome <log> <n>: how stage n ended, from the summary the finish stage prints.
s15_outcome() { sed -n "s/^  $2\. [^:]*: //p" "$1" | tail -n 1; }
# s15_is <got> <want>: the outcome word matches, with or without its detail.
s15_is() { [[ "$1" == "$2" || "$1" == "$2 ("* ]]; }
# s15_wz <log> <args...>: setup.sh unattended from $SCRATCH (so the target comes from the arguments or
# the superproject, never the runner's folder), with the kit added from KITSRC unless AW_KIT_URL is set.
s15_wz() {
    local log="$1"; shift
    (cd "$SCRATCH" && AW_KIT_URL="${S15_KIT_URL:-$KITSRC}" AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$@" </dev/null >"$log" 2>&1)
}
s15_real() { (cd "$1" && pwd -P); }

# --- Static checks ----------------------------------------------------------------------------------
s15_bad=""
for s15_f in "${s15_files[@]}"; do
    "$st_bash" -n "$KIT/$s15_f" 2>/dev/null || s15_bad+="$s15_f does not parse under $st_bash"$'\n'
done
empty "15 setup.sh, lib/wizard.sh, update.sh, developer.sh and build-template.sh parse under $st_bash" "$s15_bad"
if command -v shellcheck >/dev/null 2>&1; then
    s15_out="$(cd "$KIT" && shellcheck -x "${s15_files[@]}" 2>&1)"
    empty "15 shellcheck -x is clean on setup.sh, lib/wizard.sh, update.sh, developer.sh and build-template.sh" "$s15_out"
else
    skp "15 shellcheck not on PATH; the setup scripts not linted"
fi
empty "15 every git call in the setup scripts carries --no-optional-locks" \
    "$(cd "$KIT" && grep -nE '(^|[;&|({]|\$\()[[:space:]]*git[[:space:]]' "${s15_files[@]}" | grep -vE ':[0-9]+:[[:space:]]*(#|(say|step|note|warn) ")' | grep -v -- '--no-optional-locks')"
s15_bad=""
for s15_f in setup.sh lib/setup/update.sh lib/setup/developer.sh scripts/build-template.sh; do
    [[ -x "$KIT/$s15_f" ]] || s15_bad+="$s15_f is not executable"$'\n'
done
empty "15 the setup entry points are executable" "$s15_bad"
empty "15 the setup scripts use no capitals for emphasis (MUST, NEVER, CRITICAL, IMPORTANT)" \
    "$(cd "$KIT" && grep -nwE 'MUST|NEVER|CRITICAL|IMPORTANT' "${s15_files[@]}")"
grep -q "awk -v k=\"\$1=\" 'index(\$0, k) == 1" "$KIT/lib/wizard.sh" \
    && ok "15 lib/wizard.sh state_key looks keys up with awk index(), so per-item keys with / and . read right" \
    || ko "15 lib/wizard.sh state_key looks keys up with awk index(), so per-item keys with / and . read right"
# state_key on a report holding per-item keys: the one asked for, and not a longer key sharing its start.
s15_out="$("$st_bash" -c '. "$1/lib/wizard.sh" 2>/dev/null; WZ_STATE=$(printf "%s\n" "resource.field-study/media=resolves granted" "resource.field-study/media.raw=missing absent" "submodule.projects/vendor-review=role=project dirty=0"); printf "%s|%s|%s" "$(state_key resource.field-study/media)" "$(state_key submodule.projects/vendor-review)" "$(state_key resource.field)"' _ "$KIT")"
[[ "$s15_out" == "resolves granted|role=project dirty=0|" ]] \
    && ok "15 state_key reads a per-item key containing / and . exactly" \
    || ko "15 state_key reads a per-item key containing / and . exactly" "$s15_out"

# --- The dispatch table -----------------------------------------------------------------------------
if s15_need kitsrc; then
    s15_d="$SCRATCH/s15-dispatch"
    mkws_min "$s15_d" >/dev/null 2>&1
    s15_dr="$(s15_real "$s15_d")"
    # Each child replaced by a recorder in the fixture's own kit checkout, which setup.sh finds beside it.
    for s15_f in lib/setup/update.sh lib/setup/developer.sh lib/setup/link.sh lib/setup/gitconfig.sh \
        lib/setup/migrate.sh scripts/skills-bridge.sh; do
        printf '%s\n' '#!/bin/sh' "echo \"${s15_f##*/} \$*\"" 'exit "${S15_RC:-0}"' >"$s15_d/kit/$s15_f"
    done
    s15_bad=""
    while IFS='|' read -r s15_args s15_want; do
        # The mode words are split on purpose; each case is one command line.
        # shellcheck disable=SC2086
        s15_got="$(cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_d/kit/setup.sh" $s15_args </dev/null 2>&1)"
        s15_want="${s15_want//@WS@/$s15_dr}"
        [[ "$s15_got" == "$s15_want" ]] || s15_bad+="setup.sh $s15_args: got '$s15_got', wanted '$s15_want'"$'\n'
    done <<'S15CASES'
update --no-fetch|update.sh --target @WS@ --no-fetch
--developer|developer.sh --target @WS@
developer|developer.sh --target @WS@
link field-study --dry-run|link.sh --target @WS@ field-study --dry-run
hooks --check|gitconfig.sh --target @WS@ --hooks --check
hooks --repo projects/vendor-review|gitconfig.sh --target @WS@ --hooks --repo projects/vendor-review
skills --dry-run --no-user|skills-bridge.sh --target @WS@ --dry-run --no-user
migrate --dry-run --map maps/ws.map|migrate.sh --target @WS@ --dry-run --map maps/ws.map
S15CASES
    empty "15 dispatch: update, --developer, developer, link, hooks, skills and migrate run their script with --target, the rest passed through" "$s15_bad"
    s15_got="$(cd "$SCRATCH" && "$st_bash" "$s15_d/kit/setup.sh" link --target "$s15_d" 2>&1)"
    [[ "$s15_got" == "link.sh --target $s15_dr" ]] && ok "15 dispatch: --target names the workspace, made absolute" \
        || ko "15 dispatch: --target names the workspace, made absolute" "$s15_got"
    (cd "$SCRATCH" && S15_RC=7 "$st_bash" "$s15_d/kit/setup.sh" update >/dev/null 2>&1); s15_rc=$?
    [[ $s15_rc -eq 7 ]] && ok "15 dispatch: the child's exit status is setup's" || ko "15 dispatch: the child's exit status is setup's" "status $s15_rc"
    s15_got="$(cd "$SCRATCH" && "$st_bash" "$s15_d/kit/setup.sh" hooks --target "$s15_d/kit/lib" 2>&1)"; s15_rc=$?
    [[ $s15_rc -eq 1 && "$s15_got" == *"inside the kit's own checkout"* ]] \
        && ok "15 dispatch: a target inside the kit's checkout stops (exit 1) before any child runs" \
        || ko "15 dispatch: a target inside the kit's checkout stops (exit 1) before any child runs" "status $s15_rc: $s15_got"
    (cd "$SCRATCH" && "$st_bash" "$s15_setup" --no-such-option </dev/null >/dev/null 2>&1); s15_rc=$?
    (cd "$SCRATCH" && "$st_bash" "$s15_setup" new </dev/null >/dev/null 2>&1); s15_rc2=$?
    [[ $s15_rc -eq 2 && $s15_rc2 -eq 2 ]] && ok "15 an unknown option, and new with no folder, are usage errors (exit 2)" \
        || ko "15 an unknown option, and new with no folder, are usage errors (exit 2)" "status $s15_rc, $s15_rc2"
    s15_got="$("$st_bash" "$s15_setup" --help 2>&1)"; s15_rc=$?
    s15_bad=""
    for s15_m in "kit/setup.sh new DIR" "kit/setup.sh update" "kit/setup.sh --developer" "kit/setup.sh link" \
        "kit/setup.sh hooks" "kit/setup.sh skills" "kit/setup.sh migrate" "--reinstall"; do
        [[ "$s15_got" == *"$s15_m"* ]] || s15_bad+="no '$s15_m' in --help"$'\n'
    done
    [[ $s15_rc -eq 0 ]] || s15_bad+="status $s15_rc"$'\n'
    empty "15 --help names every mode" "$s15_bad"
else
    skp "15 dispatch — needs $s15_why"
fi

# --- new: the workspace from nothing ----------------------------------------------------------------
if s15_need kitsrc; then
    s15_ne="$SCRATCH/s15-nonempty"; mkdir -p "$s15_ne"; printf 'notes\n' >"$s15_ne/notes.txt"
    s15_wz "$SCRATCH/s15-nonempty.log" "$s15_setup" new "$s15_ne" --team "Test Team"; s15_rc=$?
    [[ $s15_rc -eq 1 && ! -e "$s15_ne/.git" && "$(ls -A "$s15_ne")" == notes.txt ]] \
        && grep -q 'is not empty: kit/setup.sh new starts a workspace in a new or empty folder' "$SCRATCH/s15-nonempty.log" \
        && ok "15 new refuses a folder that is not empty, and writes nothing there" \
        || ko "15 new refuses a folder that is not empty, and writes nothing there" "status $s15_rc: $(tail -n 3 "$SCRATCH/s15-nonempty.log")"

    # The default run on a folder that is not a repository, without --init: it stops at stage 2 and
    # creates nothing. And on the kit's own checkout: it stops too.
    s15_wz "$SCRATCH/s15-no-init.log" "$s15_setup" --target "$SCRATCH/s15-no-init" --team "Test Team"; s15_rc=$?
    [[ $s15_rc -eq 1 && ! -e "$SCRATCH/s15-no-init" ]] && grep -q -- '--init' "$SCRATCH/s15-no-init.log" \
        && [[ "$(s15_outcome "$SCRATCH/s15-no-init.log" 2)" == stopped* ]] \
        && ok "15 the default run with no repository and no --init stops at stage 2, creates nothing, and names --init" \
        || ko "15 the default run with no repository and no --init stops at stage 2, creates nothing, and names --init" "status $s15_rc: $(tail -n 3 "$SCRATCH/s15-no-init.log")"
    s15_wz "$SCRATCH/s15-kit-target.log" "$s15_setup" --target "$KIT/pilot" --init; s15_rc=$?
    [[ $s15_rc -eq 1 ]] && grep -q "inside the kit's own checkout" "$SCRATCH/s15-kit-target.log" \
        && ok "15 the default run refuses the kit's own checkout as the workspace" \
        || ko "15 the default run refuses the kit's own checkout as the workspace" "status $s15_rc: $(tail -n 3 "$SCRATCH/s15-kit-target.log")"

    # new, with a stand-in claude on PATH that records any call: setup never starts Claude Code.
    s15_cl="$SCRATCH/s15-claude-stub"; mkdir -p "$s15_cl"
    printf '%s\n' '#!/bin/sh' "echo \"\$*\" >> \"$s15_cl/calls\"" 'exit 1' >"$s15_cl/claude"; chmod +x "$s15_cl/claude"
    s15_n="$SCRATCH/s15-new"
    PATH="$s15_cl:$PATH" mkws "$s15_n"; s15_nrc=$?
    [[ ! -s "$s15_cl/calls" ]] && ok "15 setup never calls claude" || ko "15 setup never calls claude" "$(cat "$s15_cl/calls")"
    s15_bad=""
    [[ "$(git -C "$s15_n" symbolic-ref HEAD 2>/dev/null)" == refs/heads/main ]] || s15_bad+="HEAD is not main"$'\n'
    [[ "$(git -C "$s15_n" ls-files -s -- kit | awk '{ print $1 }')" == 160000 ]] || s15_bad+="no kit gitlink"$'\n'
    [[ "$(git config -f "$s15_n/.gitmodules" submodule.kit.path)" == kit ]] || s15_bad+=".gitmodules has no kit path"$'\n'
    [[ "$(git config -f "$s15_n/.gitmodules" submodule.kit.branch)" == main ]] || s15_bad+=".gitmodules has no branch main"$'\n'
    [[ -f "$s15_n/kit/CLAUDE.kit.md" ]] || s15_bad+="kit/ is not checked out"$'\n'
    s15_is "$(s15_outcome "$s15_n.log" 1)" "already done" || s15_is "$(s15_outcome "$s15_n.log" 1)" "done" \
        || s15_bad+="stage 1: $(s15_outcome "$s15_n.log" 1)"$'\n'
    s15_is "$(s15_outcome "$s15_n.log" 2)" "done" || s15_bad+="stage 2: $(s15_outcome "$s15_n.log" 2)"$'\n'
    empty "15 new, unattended: git init on main, the kit added from AW_KIT_URL at kit/ with branch main, stages 1–2 as §2.3" "$s15_bad"

    if s15_need engine state hooks; then
        s15_bad=""
        [[ $s15_nrc -eq 0 ]] || s15_bad+="status $s15_nrc"$'\n'
        for s15_i in 1 2 3 4 5 6 7 8 9 10; do
            case $s15_i in 1) s15_w="already done|done" ;; 2|3|4|5|9|10) s15_w="done" ;; *) s15_w=skipped ;; esac
            s15_got="$(s15_outcome "$s15_n.log" $s15_i)"
            case "|$s15_w|" in *"|${s15_got%% (*}|"*) ;; *) s15_bad+="stage $s15_i: wanted $s15_w, got '$s15_got'"$'\n' ;; esac
        done
        [[ "$(s15_outcome "$s15_n.log" 8)" == "skipped (off by default; --cowork includes it)" ]] || s15_bad+="stage 8: $(s15_outcome "$s15_n.log" 8)"$'\n'
        empty "15 new, unattended, from nothing: stages 1 already done or done, 2–5 done, 6–8 skipped (Cowork off by default), 9–10 done" "$s15_bad"
        st_expect "15 new: the fresh-install green set (§11.4)" "$(st_run "$s15_n")" in_git=yes hooks=active kit_hooks=active \
            kit_path=kit kit_submodule=yes kit_import=ok ledger=present workspace_conventions=present claude_md=kit \
            agents_md=kit always_loaded=CLAUDE.md plugins_registered=closeout,projects,workspace plugins_mode=kit \
            submodule_config=ok submodules_attention= orphan_gitlinks= sensitive_tracked= versioned_mismatch= \
            external_paths_missing= legacy= kit_incoming= mode=fresh origin_visibility=none
        s15_bad=""
        grep -q '^Nothing is committed\.' "$s15_n.log" || s15_bad+="no 'Nothing is committed.'"$'\n'
        s15_line="$(grep '^  git add ' "$s15_n.log" | tail -n 1)"
        for s15_p in .gitmodules kit .claude/kit-templates.lock CLAUDE.md .gitignore .claude/workspace.md; do
            [[ " $s15_line " == *" $s15_p "* ]] || s15_bad+="the git add line has no $s15_p: $s15_line"$'\n'
        done
        grep -q '^  git add .*#' "$s15_n.log" && s15_bad+="an inline comment on the git add line"$'\n'
        empty "15 new: nothing committed, and the git add line names the kit, the ledger and the files created" "$s15_bad"
        git -C "$s15_n" rev-parse -q --verify HEAD >/dev/null 2>&1 \
            && ko "15 new makes no commit" || ok "15 new makes no commit"
        # A second run is the plain one, from the workspace's own kit/setup.sh: the target is its superproject.
        st_tree "$s15_n" >"$SCRATCH/s15-new-before.txt"
        s15_wz "$SCRATCH/s15-new-2.log" "$s15_n/kit/setup.sh"; s15_rc=$?
        st_tree "$s15_n" >"$SCRATCH/s15-new-after.txt"
        s15_bad=""
        [[ $s15_rc -eq 0 ]] || s15_bad+="status $s15_rc"$'\n'
        for s15_i in 1 2 3 4 5 6 7 8 9 10; do
            case $s15_i in 1) s15_w="already done|done" ;; 2|3|4|5) s15_w="already done" ;; 9|10) s15_w="done" ;; *) s15_w=skipped ;; esac
            s15_got="$(s15_outcome "$SCRATCH/s15-new-2.log" $s15_i)"
            case "|$s15_w|" in *"|${s15_got%% (*}|"*) ;; *) s15_bad+="stage $s15_i: wanted $s15_w, got '$s15_got'"$'\n' ;; esac
        done
        empty "15 a second run: 1–5 already done, 6–8 skipped, 9–10 done" "$s15_bad"
        empty "15 a second run changes nothing under the workspace, .git included" \
            "$(diff "$SCRATCH/s15-new-before.txt" "$SCRATCH/s15-new-after.txt" 2>&1)"
    else
        skp "15 new, unattended: stage outcomes, the green set, the commit list and a second run — needs $s15_why"
    fi
else
    skp "15 new — needs $s15_why"
fi

# --- Stage 6 (outside folders) and stage 8 (Cowork) ------------------------------------------------
if s15_need kitsrc engine state hooks link; then
    s15_r="$SCRATCH/s15-resources"
    mkws "$s15_r" >/dev/null 2>&1
    mkdir -p "$s15_r/projects/field-study" "$SCRATCH/s15-drive/recordings"
    printf '%s\n' '# Field study' '' '- **Versioned:** workspace' '- **Sensitivity:** normal' '' '## Resources' '' \
        '- media — raw interview recordings' '- survey-data — the survey responses extract' >"$s15_r/projects/field-study/README.md"
    printf '%s\n' '# Resources on this machine' '' "field-study/media  $SCRATCH/s15-drive/recordings" >"$s15_r/.claude/resources.local.md"
    s15_wz "$s15_r.6a.log" "$s15_r/kit/setup.sh"
    s15_got="$(s15_outcome "$s15_r.6a.log" 6)"
    [[ "$s15_got" == "left open (not reachable on this machine: field-study/survey-data — kit/setup.sh link)" && -L "$s15_r/projects/field-study/.resources/media" ]] \
        && ok "15 stage 6: link.sh maps what it can; a name with no path on this machine is left open, by name" \
        || ko "15 stage 6: link.sh maps what it can; a name with no path on this machine is left open, by name" "$s15_got"
    mkdir -p "$SCRATCH/s15-drive/survey"
    printf '%s\n' "field-study/survey-data  $SCRATCH/s15-drive/survey" >>"$s15_r/.claude/resources.local.md"
    s15_wz "$s15_r.6b.log" "$s15_r/kit/setup.sh"
    s15_is "$(s15_outcome "$s15_r.6b.log" 6)" "done" \
        && ok "15 stage 6: done once every outside folder a project names resolves here" \
        || ko "15 stage 6: done once every outside folder a project names resolves here" "$(s15_outcome "$s15_r.6b.log" 6)"
else
    skp "15 stage 6, outside folders — needs $s15_why"
fi
if s15_need kitsrc engine state hooks bridge; then
    s15_cw="$SCRATCH/s15-cowork"
    mkws "$s15_cw" --cowork; s15_rc=$?
    s15_n_kit="$(find "$s15_cw/.claude/skills" -mindepth 1 -maxdepth 1 -type d -name 'kit-*' 2>/dev/null | aw_count)"
    [[ $s15_rc -eq 0 && -f "$s15_cw/.claude/skills/.kit-generated" && $s15_n_kit -ge 1 ]] \
        && [[ "$(s15_outcome "$s15_cw.log" 8)" == "left open (adding the folder in Cowork is the person's step)" ]] \
        && ok "15 stage 8 with --cowork, unattended: the skills bridge is written ($s15_n_kit kit- skills); adding the folder is left to the person" \
        || ko "15 stage 8 with --cowork, unattended: the skills bridge is written; adding the folder is left to the person" "status $s15_rc, $s15_n_kit kit- skills: $(s15_outcome "$s15_cw.log" 8)"
else
    skp "15 stage 8, Cowork — needs $s15_why"
fi

# --- Adopt, and a template copy that lost its gitlink -----------------------------------------------
if s15_need kitsrc; then
    s15_a="$SCRATCH/s15-adopt"
    mkdir -p "$s15_a" && git -C "$s15_a" init -q && git -C "$s15_a" symbolic-ref HEAD refs/heads/main
    printf '# Field study\n\nThe team'"'"'s own README, from before the kit.\n' >"$s15_a/README.md"
    cp "$s15_a/README.md" "$SCRATCH/s15-adopt-readme.txt"
    s15_wz "$SCRATCH/s15-adopt.log" "$s15_setup" --target "$s15_a" --team "Test Team" --owner "Sam Example" --owner-handle "@sam"; s15_rc=$?
    [[ "$(git -C "$s15_a" ls-files -s -- kit | awk '{ print $1 }')" == 160000 && -f "$s15_a/kit/CLAUDE.kit.md" ]] \
        && ok "15 adopt: an existing repository with no kit gets it as a submodule at kit/ (unattended takes the default yes)" \
        || ko "15 adopt: an existing repository with no kit gets it as a submodule at kit/ (unattended takes the default yes)" "status $s15_rc: $(tail -n 5 "$SCRATCH/s15-adopt.log")"
    if s15_need engine state; then
        s15_bad=""
        cmp -s "$s15_a/README.md" "$SCRATCH/s15-adopt-readme.txt" || s15_bad+="README.md was changed"$'\n'
        awk -F '\t' '$1 == "README.md" && $5 == "kept" { f = 1 } END { exit !f }' "$s15_a/.claude/kit-templates.lock" 2>/dev/null \
            || s15_bad+="README.md is not recorded kept in the ledger"$'\n'
        st_expect "15 adopt: the workspace reads as set up" "$(st_run "$s15_a")" ledger=present claude_md=kit plugins_mode=kit
        empty "15 adopt: the team's own README is kept as it was, and recorded kept" "$s15_bad"
    else
        skp "15 adopt: the engine's files and the ledger — needs $s15_why"
    fi

    # A copy of the template repository whose gitlink was dropped: .gitmodules names kit, the index does not.
    s15_g="$SCRATCH/s15-lost-gitlink"
    mkdir -p "$s15_g" && git -C "$s15_g" init -q && git -C "$s15_g" symbolic-ref HEAD refs/heads/main
    printf '[submodule "kit"]\n\tpath = kit\n\turl = %s\n\tbranch = main\n' "$KITSRC" >"$s15_g/.gitmodules"
    S15_KIT_URL="$SCRATCH/s15-no-such-kit" s15_wz "$SCRATCH/s15-lost-gitlink.log" "$s15_setup" --target "$s15_g" --team "Test Team" --owner "Sam Example"
    [[ "$(git -C "$s15_g" ls-files -s -- kit | awk '{ print $1 }')" == 160000 ]] \
        && grep -q 'names the kit at kit/, and the repository does not hold it: adding it again' "$SCRATCH/s15-lost-gitlink.log" \
        && ok "15 a template copy that lost its kit gitlink gets it again, from the URL its .gitmodules names" \
        || ko "15 a template copy that lost its kit gitlink gets it again, from the URL its .gitmodules names" "$(tail -n 5 "$SCRATCH/s15-lost-gitlink.log")"
else
    skp "15 adopt — needs $s15_why"
fi

# --- A 2.x workspace: stage 3 stops, and update hands over to the migration -------------------------
if s15_need kitsrc mkws2x; then
    s15_x="$SCRATCH/s15-2x"
    if mkws2x "$s15_x"; then
        st_tree "$s15_x" >"$SCRATCH/s15-2x-before.txt"
        s15_wz "$SCRATCH/s15-2x.log" "$s15_setup" --target "$s15_x"; s15_rc=$?
        [[ $s15_rc -eq 1 && "$(s15_outcome "$SCRATCH/s15-2x.log" 3)" == "stopped (this workspace has the 2.x layout: kit/setup.sh migrate --dry-run)" ]] \
            && [[ -z "$(git -C "$s15_x" ls-files -s -- kit)" && ! -e "$s15_x/kit" ]] \
            && ok "15 a 2.x workspace stops at stage 3, pointing at kit/setup.sh migrate --dry-run, and gets no second kit" \
            || ko "15 a 2.x workspace stops at stage 3, pointing at kit/setup.sh migrate --dry-run, and gets no second kit" "status $s15_rc: $(s15_outcome "$SCRATCH/s15-2x.log" 3)"
        s15_wz "$SCRATCH/s15-2x-update.log" "$s15_setup" update --target "$s15_x"; s15_rc=$?
        st_tree "$s15_x" >"$SCRATCH/s15-2x-after.txt"
        s15_bad=""
        grep -q '^This workspace has the 2.x layout; the migration moves it to 3.0\.$' "$SCRATCH/s15-2x-update.log" \
            || s15_bad+="no handover line"$'\n'
        if s15_need migrate; then
            grep -q '^would ' "$SCRATCH/s15-2x-update.log" || s15_bad+="no dry-run action lines from migrate"$'\n'
            [[ $s15_rc -eq 0 ]] || s15_bad+="status $s15_rc"$'\n'
        else
            grep -q 'lib/setup/migrate.sh: not built yet' "$SCRATCH/s15-2x-update.log" || s15_bad+="migrate.sh was not run"$'\n'
            [[ $s15_rc -eq 2 ]] || s15_bad+="status $s15_rc, not migrate's"$'\n'
        fi
        s15_diff="$(diff "$SCRATCH/s15-2x-before.txt" "$SCRATCH/s15-2x-after.txt" 2>&1)"
        [[ -z "$s15_diff" ]] || s15_bad+="the workspace changed: $s15_diff"$'\n'
        empty "15 update on a 2.x workspace hands over to migrate --dry-run, exits with its status, and changes nothing unattended" "$s15_bad"
    else
        ko "15 the 2.x fixture (mkws2x) could not be built" "$(tail -n 5 "$s15_x.log" 2>/dev/null)"
    fi
else
    skp "15 a 2.x workspace at stage 3 and at update — needs $s15_why"
fi

# --- update against a second kit commit -------------------------------------------------------------
if s15_need kitsrc; then
    # The kit the workspace follows: a clone of KITSRC, so a second commit here leaves KITSRC as it is.
    s15_k2="$SCRATCH/s15-kit2"
    git clone -q "$KITSRC" "$s15_k2" && git -C "$s15_k2" checkout -q main
    s15_u="$SCRATCH/s15-update"
    S15_KIT_URL="$s15_k2" s15_wz "$s15_u.log" "$s15_setup" new "$s15_u" --team "Test Team" --owner "Sam Example" --owner-handle "@sam"
    s15_old_v="$(awk '/^## v[0-9]/ { v = $2; sub(/^v/, "", v); print v; exit }' "$s15_k2/CHANGELOG.md")"
    s15_engine=0; s15_need engine state && [[ -f "$s15_u/.claude/kit-templates.lock" ]] && s15_engine=1
    if [[ $s15_engine -eq 1 ]]; then
        # The engine re-adds the marketplace key when it is absent, so its report names settings.json.
        jq 'del(.extraKnownMarketplaces)' "$s15_u/.claude/settings.json" >"$SCRATCH/s15-settings.json" \
            && cat "$SCRATCH/s15-settings.json" >"$s15_u/.claude/settings.json"
        s15_lock_before="$(awk -F '\t' '$1 == ".claude/closeout.md"' "$s15_u/.claude/kit-templates.lock")"
        cp "$s15_u/.claude/closeout.md" "$SCRATCH/s15-closeout-before.md"
    fi
    # The second commit: a new version heading, a marker in the new update.sh, and a template change.
    python3 - "$s15_k2" <<'PYK2'
import sys, re
k = sys.argv[1]
p = k + "/CHANGELOG.md"; s = open(p).read()
i = s.index("\n## v") + 1
s = s[:i] + "## v9.9.9 — 2026-10-01\n\nA second commit, for the update test in section 15.\n\n" + s[i:]
open(p, "w").write(s)
p = k + "/lib/setup/update.sh"; s = open(p).read()
s = s.replace("set -uo pipefail\n", 'set -uo pipefail\n[[ " $* " == *" --after-advance "* ]] && echo "update.sh from the second commit"\n', 1)
open(p, "w").write(s)
p = k + "/templates/workspace/closeout.md"; open(p, "a").write("\nA line the second kit commit adds.\n")
PYK2
    git -C "$s15_k2" add -A && git -C "$s15_k2" -c commit.gpgsign=false commit -q -m "A second commit"
    s15_new_sha="$(git -C "$s15_k2" rev-parse HEAD)"
    (cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_u/kit/setup.sh" update </dev/null >"$SCRATCH/s15-update.log" 2>&1); s15_rc=$?
    s15_bad=""
    [[ "$(git -C "$s15_u/kit" rev-parse HEAD)" == "$s15_new_sha" ]] || s15_bad+="the kit did not advance to the second commit"$'\n'
    grep -q '^update.sh from the second commit$' "$SCRATCH/s15-update.log" || s15_bad+="the new kit's update.sh did not run (exec)"$'\n'
    grep -q '^A second commit, for the update test in section 15\.$' "$SCRATCH/s15-update.log" || s15_bad+="no CHANGELOG excerpt"$'\n'
    grep -q '^## v9\.9\.9' "$SCRATCH/s15-update.log" || s15_bad+="the excerpt lacks the new heading"$'\n'
    [[ -z "$s15_old_v" ]] || ! grep -q "^## v$s15_old_v" "$SCRATCH/s15-update.log" || s15_bad+="the excerpt runs past the old version's heading"$'\n'
    grep -q '^  git add kit \.claude/kit-templates\.lock' "$SCRATCH/s15-update.log" || s15_bad+="no git add line naming kit and the ledger"$'\n'
    grep -q "^  git commit -m \"Kit $s15_old_v -> 9\\.9\\.9\"\$" "$SCRATCH/s15-update.log" || s15_bad+="no commit line Kit $s15_old_v -> 9.9.9"$'\n'
    grep '^  git add ' "$SCRATCH/s15-update.log" | grep -q ' CLAUDE\.md' \
        || s15_bad+="the workspace has no commit yet, and the git add line leaves out CLAUDE.md (a partial first commit)"$'\n'
    [[ $s15_rc -eq 0 ]] || s15_bad+="status $s15_rc"$'\n'
    empty "15 update: the kit advances, the new kit's update.sh takes over, the CHANGELOG since the old version is printed, one commit named" "$s15_bad"
    if [[ $s15_engine -eq 1 ]]; then
        s15_bad=""
        grep '^  git add ' "$SCRATCH/s15-update.log" | grep -q ' \.claude/settings\.json' || s15_bad+="the git add line does not name .claude/settings.json, which the engine merged"$'\n'
        grep -q 'changed   \.claude/closeout\.md' "$SCRATCH/s15-update.log" || s15_bad+="the changed template is not listed"$'\n'
        [[ "$(awk -F '\t' '$1 == ".claude/closeout.md"' "$s15_u/.claude/kit-templates.lock")" == "$s15_lock_before" ]] \
            || s15_bad+="the ledger entry for .claude/closeout.md changed"$'\n'
        cmp -s "$s15_u/.claude/closeout.md" "$SCRATCH/s15-closeout-before.md" || s15_bad+=".claude/closeout.md changed"$'\n'
        empty "15 update, unattended: the changed template is listed and nothing is applied or recorded; the engine's paths are in the git add line" "$s15_bad"
    else
        skp "15 update: template offers, the ledger left alone unattended, the engine's paths — needs ${s15_why:-a ledger in the fixture}"
    fi
    # Run again. Before the 3.0 engine lands, the 2.2.0 one that step 8 runs vendors the plugins, which
    # reads as the 2.x layout, so this waits for it.
    if [[ $s15_engine -eq 1 ]]; then
        (cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_u/kit/setup.sh" update --no-fetch </dev/null >"$SCRATCH/s15-update-2.log" 2>&1)
        grep -q '^The kit is already at 9\.9\.9 (' "$SCRATCH/s15-update-2.log" \
            && ok "15 update again: the kit is already current, and says so" \
            || ko "15 update again: the kit is already current, and says so" "$(head -n 8 "$SCRATCH/s15-update-2.log")"
    else
        skp "15 update again: the kit is already current — needs ${s15_why:-a ledger in the fixture}"
    fi
else
    skp "15 update — needs $s15_why"
fi

# --- Attended runs -----------------------------------------------------------------------------------
# AW_WIZARD_NONINTERACTIVE=0 makes a run attended with its answers piped in, one per line.
if [[ -n "${s15_engine:-}" && ${s15_engine:-0} -eq 1 ]]; then
    for s15_ans in y n; do
        s15_c="$SCRATCH/s15-update-$s15_ans"
        cp -R "$s15_u" "$s15_c"
        (cd "$SCRATCH" && printf '%s\n' "$s15_ans" | AW_WIZARD_NONINTERACTIVE=0 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch >"$s15_c.log" 2>&1)
        s15_st="$(awk -F '\t' '$1 == ".claude/closeout.md" { print $5 }' "$s15_c/.claude/kit-templates.lock")"
        if [[ $s15_ans == y ]]; then
            grep -q '^A line the second kit commit adds\.$' "$s15_c/.claude/closeout.md" && [[ "$s15_st" == accepted ]] \
                && grep '^  git add ' "$s15_c.log" | grep -q ' \.claude/closeout\.md' \
                && ok "15 update, attended, y: the template's diff is applied to .claude/closeout.md, recorded accepted, and named in the commit" \
                || ko "15 update, attended, y: the template's diff is applied to .claude/closeout.md, recorded accepted, and named in the commit" "ledger: $s15_st; $(tail -n 12 "$s15_c.log")"
        else
            cmp -s "$s15_c/.claude/closeout.md" "$SCRATCH/s15-closeout-before.md" && [[ "$s15_st" == skipped ]] \
                && ok "15 update, attended, n: .claude/closeout.md is left as it was and the offer recorded skipped" \
                || ko "15 update, attended, n: .claude/closeout.md is left as it was and the offer recorded skipped" "ledger: $s15_st; $(tail -n 12 "$s15_c.log")"
        fi
    done
    # A .gitignore short of two template lines: offered as one diff; y adds them, n records them declined.
    for s15_ans in y n; do
        s15_c="$SCRATCH/s15-update-gi-$s15_ans"
        cp -R "$s15_u" "$s15_c"
        grep -v -x -e '\.DS_Store' -e '_delete/' "$s15_c/.gitignore" >"$SCRATCH/s15-gi" && cat "$SCRATCH/s15-gi" >"$s15_c/.gitignore"
        (cd "$SCRATCH" && printf 'n\n%s\n' "$s15_ans" | AW_WIZARD_NONINTERACTIVE=0 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch >"$s15_c.log" 2>&1)
        if [[ $s15_ans == y ]]; then
            grep -q -x '\.DS_Store' "$s15_c/.gitignore" && grep -q -x '_delete/' "$s15_c/.gitignore" \
                && grep '^  git add ' "$s15_c.log" | grep -q ' \.gitignore' \
                && ok "15 update, attended: missing .gitignore lines offered as one diff; y adds them and names .gitignore in the commit" \
                || ko "15 update, attended: missing .gitignore lines offered as one diff; y adds them and names .gitignore in the commit" "$(tail -n 14 "$s15_c.log")"
        else
            ! grep -q -x '\.DS_Store' "$s15_c/.gitignore" \
                && [[ "$(awk -F '\t' '$1 == "!declined" && $2 == ".gitignore" { print $3 }' "$s15_c/.claude/kit-templates.lock" | LC_ALL=C sort | paste -sd' ' -)" == ".DS_Store _delete/" ]] \
                && ok "15 update, attended: n records each missing .gitignore line as declined, and adds none" \
                || ko "15 update, attended: n records each missing .gitignore line as declined, and adds none" "$(grep '^!declined' "$s15_c/.claude/kit-templates.lock")"
        fi
    done
else
    skp "15 update, attended: a template diff and .gitignore lines applied or declined — needs ${s15_why:-the update fixture above}"
fi
# The one prompt that also needs a terminal: with no answer from GitHub, only a person at one can
# confirm the origin. It runs on a pseudo-terminal where one can be opened.
cat >"$SCRATCH/s15-pty.py" <<'PYPTY'
import os, pty, re, select, sys, time
log = sys.argv[1]; i = sys.argv.index("--"); rules = [r.split("=>", 1) for r in sys.argv[2:i]]; cmd = sys.argv[i + 1:]
try:
    pid, fd = pty.fork()
except OSError:
    sys.exit(77)
if pid == 0:
    os.execvp(cmd[0], cmd)
out = b""; pending = ""; deadline = time.time() + 180
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 1)
    if not r:
        continue
    try:
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    out += d; pending += d.decode("utf-8", "replace")
    for pat, ans in rules:
        if re.search(pat, pending):
            os.write(fd, (ans + "\n").encode()); pending = ""; break
else:
    os.kill(pid, 9)
_, st = os.waitpid(pid, 0)
open(log, "wb").write(out.replace(b"\r\n", b"\n").replace(b"\r", b""))
sys.exit(st >> 8 if os.WIFEXITED(st) else 1)
PYPTY
if s15_need kitsrc engine state hooks; then
    s15_ap="$SCRATCH/s15-origin-person"
    mkws "$s15_ap" >/dev/null 2>&1
    git -C "$s15_ap" remote add origin git@github.com:example-owner/vendor-review-ws.git
    s15_ghf="$SCRATCH/s15-gh-fails"; mkdir -p "$s15_ghf"; printf '%s\n' '#!/bin/sh' 'exit 1' >"$s15_ghf/gh"; chmod +x "$s15_ghf/gh"
    # s15-pty.py <log> <pattern=>answer>... -- <command...>: the first pattern matching the output since
    # the last answer is answered (an empty answer is Enter); exit 77 when no pseudo-terminal opens.
    (cd "$SCRATCH" && env -u AW_WIZARD_NONINTERACTIVE PATH="$s15_ghf:$PATH" python3 "$SCRATCH/s15-pty.py" "$s15_ap.log" \
        'Is git@github\.com:example-owner/vendor-review-ws\.git a private repository\? \(y/n\) \[n\]: $=>y' \
        '\(y/n\) \[[yn]\]: $=>' 'Press Enter[^\n]*$=>' -- "$st_bash" "$s15_ap/kit/setup.sh" >/dev/null 2>&1); s15_rc=$?
    if [[ $s15_rc -eq 77 ]]; then
        skp "15 stage 4, attended with no answer from gh: the person's yes — no pseudo-terminal can be opened here"
    else
        grep -q "^- \*\*Private remote:\*\* \`github.com/example-owner/vendor-review-ws\` — confirmed $(date +%F) via person\$" "$s15_ap/.claude/workspace.md" \
            && s15_is "$(s15_outcome "$s15_ap.log" 4)" "done" \
            && ok "15 stage 4, attended with no answer from gh: the person's yes records the origin, via person" \
            || ko "15 stage 4, attended with no answer from gh: the person's yes records the origin, via person" "$(s15_outcome "$s15_ap.log" 4); $(grep -n 'Private remote' "$s15_ap/.claude/workspace.md")"
    fi
    # Piped answers and no terminal: the question is not asked, and nothing is recorded.
    s15_ap2="$SCRATCH/s15-origin-piped"
    mkws "$s15_ap2" >/dev/null 2>&1
    git -C "$s15_ap2" remote add origin git@github.com:example-owner/vendor-review-ws.git
    (cd "$SCRATCH" && yes y 2>/dev/null | head -n 40 | PATH="$s15_ghf:$PATH" AW_WIZARD_NONINTERACTIVE=0 \
        "$st_bash" "$s15_ap2/kit/setup.sh" >"$s15_ap2.log" 2>&1)
    if ( exec 3</dev/tty ) 2>/dev/null; then
        skp "15 stage 4 with piped answers: this runner has a controlling terminal, so the no-terminal case cannot be shown"
    else
        ! grep -q '^- \*\*Private remote:\*\*' "$s15_ap2/.claude/workspace.md" && ! grep -q 'a private repository? (y/n)' "$s15_ap2.log" \
            && ok "15 stage 4 with answers piped in and no terminal: the private question is not asked, and nothing is recorded" \
            || ko "15 stage 4 with answers piped in and no terminal: the private question is not asked, and nothing is recorded" "$(s15_outcome "$s15_ap2.log" 4)"
    fi
else
    skp "15 stage 4, attended: the person's yes records the origin — needs $s15_why"
fi

# --- --developer ------------------------------------------------------------------------------------
if s15_need kitsrc; then
    # s15_devws <dir> <main commit or -> <HEAD: commit or branch:name>: a workspace whose kit/ is a clone
    # of KITSRC with two more commits: c2 on c1 (KITSRC's main), and c3 beside c2. No local main unless
    # asked for.
    s15_devws() {
        local d="$1" m="$2" h="$3" k="$1/kit"
        mkdir -p "$k" && git -C "$d" init -q && git -C "$d" symbolic-ref HEAD refs/heads/main
        git -C "$k" init -q && git -C "$k" remote add origin "$KITSRC" \
            && git -C "$k" -c protocol.file.allow=always fetch -q origin && git -C "$k" checkout -q --detach origin/main
        git -C "$k" -c commit.gpgsign=false commit -q --allow-empty -m c2 && git -C "$k" tag c2
        git -C "$k" checkout -q --detach origin/main
        git -C "$k" -c commit.gpgsign=false commit -q --allow-empty -m c3 && git -C "$k" tag c3
        git -C "$k" tag c1 origin/main
        [[ "$m" == - ]] || git -C "$k" branch -q main "$m"
        case "$h" in branch:*) git -C "$k" checkout -q -b "${h#branch:}" ;; *) git -C "$k" checkout -q --detach "$h" ;; esac
        git -C "$d" -c protocol.file.allow=always submodule add -q "$KITSRC" kit >/dev/null 2>&1
    }
    # s15_dev <dir>: developer.sh through setup.sh, unattended; the output in <dir>.dev.log.
    s15_dev() { (cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_setup" --developer --target "$1" </dev/null >"$1.dev.log" 2>&1); }
    s15_sha() { git -C "$1/kit" rev-parse -q --verify "$2" 2>/dev/null; }
    s15_bad=""
    s15_v="$SCRATCH/s15-dev-a"; s15_devws "$s15_v" - c2; s15_dev "$s15_v"; s15_rc=$?
    [[ $s15_rc -eq 0 && "$(git -C "$s15_v/kit" symbolic-ref -q --short HEAD)" == main && "$(s15_sha "$s15_v" main)" == "$(s15_sha "$s15_v" c2)" ]] \
        || s15_bad+="no main, HEAD at c2: status $s15_rc, HEAD $(git -C "$s15_v/kit" symbolic-ref -q --short HEAD), main $(s15_sha "$s15_v" main)"$'\n'
    s15_v="$SCRATCH/s15-dev-b"; s15_devws "$s15_v" c2 c1; s15_dev "$s15_v"; s15_rc=$?
    [[ $s15_rc -eq 0 && "$(git -C "$s15_v/kit" symbolic-ref -q --short HEAD)" == main && "$(s15_sha "$s15_v" main)" == "$(s15_sha "$s15_v" c2)" ]] \
        || s15_bad+="main at c2 holding HEAD c1: status $s15_rc, main $(s15_sha "$s15_v" main)"$'\n'
    s15_v="$SCRATCH/s15-dev-c"; s15_devws "$s15_v" c1 c2; s15_dev "$s15_v"; s15_rc=$?
    [[ $s15_rc -eq 0 && "$(git -C "$s15_v/kit" symbolic-ref -q --short HEAD)" == main && "$(s15_sha "$s15_v" main)" == "$(s15_sha "$s15_v" c2)" ]] \
        || s15_bad+="HEAD c2 ahead of main c1: status $s15_rc, main $(s15_sha "$s15_v" main)"$'\n'
    s15_v="$SCRATCH/s15-dev-d"; s15_devws "$s15_v" c2 c3; s15_dev "$s15_v"; s15_rc=$?
    [[ $s15_rc -eq 1 && "$(s15_sha "$s15_v" main)" == "$(s15_sha "$s15_v" c2)" && "$(s15_sha "$s15_v" HEAD)" == "$(s15_sha "$s15_v" c3)" ]] \
        && grep -q 'neither contains the other' "$s15_v.dev.log" \
        || s15_bad+="main c2 and HEAD c3 diverged: status $s15_rc, main $(s15_sha "$s15_v" main), HEAD $(s15_sha "$s15_v" HEAD)"$'\n'
    empty "15 --developer puts kit/ on main and never moves main backwards: no main, main ahead, HEAD ahead, diverged (refused)" "$s15_bad"
    s15_v="$SCRATCH/s15-dev-e"; s15_devws "$s15_v" c1 branch:feature; s15_dev "$s15_v"; s15_rc=$?
    [[ $s15_rc -eq 1 && "$(git -C "$s15_v/kit" symbolic-ref -q --short HEAD)" == feature ]] && grep -q 'developed on main only' "$s15_v.dev.log" \
        && ok "15 --developer refuses a kit/ on a branch other than main, and leaves it there" \
        || ko "15 --developer refuses a kit/ on a branch other than main, and leaves it there" "status $s15_rc: $(tail -n 3 "$s15_v.dev.log")"
    s15_v="$SCRATCH/s15-dev-a"
    s15_bad=""
    [[ "$(git -C "$s15_v" config --get submodule.kit.update)" == rebase ]] || s15_bad+="submodule.kit.update is not rebase"$'\n'
    [[ "$(git -C "$s15_v" config --get pull.rebase)" == true ]] || s15_bad+="pull.rebase is not true"$'\n'
    [[ "$(git -C "$s15_v/kit" rev-parse --abbrev-ref 'main@{upstream}' 2>/dev/null)" == origin/main ]] || s15_bad+="main does not track origin/main"$'\n'
    empty "15 --developer: submodule.<kit>.update=rebase and pull.rebase=true in the workspace, main tracking origin/main" "$s15_bad"
    git -C "$s15_v/kit" remote add closeout "$SCRATCH/s15-closeout-mirror"
    s15_dev "$s15_v"
    [[ "$(git -C "$s15_v/kit" config --get aw.mirror.closeout.prefix)" == plugins/closeout ]] \
        && ok "15 --developer: a closeout remote in the kit gets aw.mirror.closeout.prefix=plugins/closeout" \
        || ko "15 --developer: a closeout remote in the kit gets aw.mirror.closeout.prefix=plugins/closeout" "$(cat "$s15_v.dev.log")"
    s15_cfg="$(cat "$s15_v/.git/config" "$(git -C "$s15_v/kit" rev-parse --absolute-git-dir)/config" | git hash-object --stdin)"
    s15_refs="$(git -C "$s15_v/kit" for-each-ref --format='%(refname) %(objectname)' refs/heads)"
    s15_dev "$s15_v"; s15_rc=$?
    [[ $s15_rc -eq 0 ]] && ! grep -qE '^  (set |made |checked out )' "$s15_v.dev.log" \
        && [[ "$(cat "$s15_v/.git/config" "$(git -C "$s15_v/kit" rev-parse --absolute-git-dir)/config" | git hash-object --stdin)" == "$s15_cfg" ]] \
        && [[ "$(git -C "$s15_v/kit" for-each-ref --format='%(refname) %(objectname)' refs/heads)" == "$s15_refs" ]] \
        && ok "15 --developer run again sets nothing and moves nothing" \
        || ko "15 --developer run again sets nothing and moves nothing" "status $s15_rc: $(grep -E '^  (set |made |checked out )' "$s15_v.dev.log")"
    # No word list anywhere: an empty home, no AW_BANNED_WORDS_FILE, none named by the workspace.
    mkdir -p "$SCRATCH/s15-home-empty"
    (cd "$SCRATCH" && env -u AW_BANNED_WORDS_FILE HOME="$SCRATCH/s15-home-empty" AW_WIZARD_NONINTERACTIVE=1 \
        "$st_bash" "$s15_setup" --developer --target "$s15_v" </dev/null >"$s15_v.nowl.log" 2>&1); s15_rc=$?
    [[ $s15_rc -eq 0 ]] && grep -q 'left open (.*no private word list: set one in .claude/workspace.md or ~/.config/agentic-workspace-kit/banned-words.txt' "$s15_v.nowl.log" \
        && ok "15 --developer with no private word list says so, left open, and exits 0" \
        || ko "15 --developer with no private word list says so, left open, and exits 0" "status $s15_rc: $(tail -n 2 "$s15_v.nowl.log")"
else
    skp "15 --developer — needs $s15_why"
fi

# --- hooks ------------------------------------------------------------------------------------------
if s15_need kitsrc hooks; then
    s15_h="$SCRATCH/s15-hooks"
    mkws_min "$s15_h" >/dev/null 2>&1
    (cd "$SCRATCH" && "$st_bash" "$s15_setup" hooks --target "$s15_h" </dev/null >"$s15_h.1.log" 2>&1)
    (cd "$SCRATCH" && "$st_bash" "$s15_setup" hooks --target "$s15_h" </dev/null >"$s15_h.2.log" 2>&1); s15_rc=$?
    (cd "$SCRATCH" && "$st_bash" "$s15_setup" hooks --target "$s15_h" --check </dev/null >"$s15_h.3.log" 2>&1); s15_rc3=$?
    [[ $s15_rc -eq 0 && $s15_rc3 -eq 0 ]] && ! grep -q '^set ' "$s15_h.2.log" && grep -q '^ok ' "$s15_h.2.log" \
        && ok "15 hooks is idempotent: a second run sets nothing, and --check passes" \
        || ko "15 hooks is idempotent: a second run sets nothing, and --check passes" "status $s15_rc, $s15_rc3: $(grep '^set ' "$s15_h.2.log")"
else
    skp "15 hooks is idempotent — needs $s15_why"
fi

# --- Stage 4: the origin confirmed and recorded -----------------------------------------------------
if s15_need kitsrc engine state hooks; then
    s15_gh="$SCRATCH/s15-gh"; mkdir -p "$s15_gh"
    # A stand-in gh: "repo view" answers with S15_GH_ANSWER, or fails when it is empty.
    printf '%s\n' '#!/bin/sh' 'case "$*" in *"repo view"*) [ -n "$S15_GH_ANSWER" ] || exit 1; echo "$S15_GH_ANSWER"; exit 0 ;; esac' 'exit 1' >"$s15_gh/gh"
    chmod +x "$s15_gh/gh"
    s15_today="$(date +%F)"
    # s15_origin <dir> <answer>: a new workspace with a GitHub origin, then a plain run with gh answering.
    s15_origin() {
        mkws "$1" >/dev/null 2>&1
        git -C "$1" remote add origin git@github.com:example-owner/field-study-ws.git
        (cd "$SCRATCH" && PATH="$s15_gh:$PATH" S15_GH_ANSWER="$2" AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$1/kit/setup.sh" </dev/null >"$1.origin.log" 2>&1)
    }
    s15_o="$SCRATCH/s15-origin-private"; s15_origin "$s15_o" PRIVATE
    s15_line="- **Private remote:** \`github.com/example-owner/field-study-ws\` — confirmed $s15_today via gh"
    s15_bad=""
    [[ "$(grep -A1 '^<!-- - \*\*Private remote:\*\*' "$s15_o/.claude/workspace.md" | sed -n 2p)" == "$s15_line" ]] \
        || s15_bad+="no bullet directly after the comment line: $(grep -n 'Private remote' "$s15_o/.claude/workspace.md")"$'\n'
    s15_is "$(s15_outcome "$s15_o.origin.log" 4)" "done" || s15_bad+="stage 4: $(s15_outcome "$s15_o.origin.log" 4)"$'\n'
    empty "15 stage 4: gh answering PRIVATE records the origin in .claude/workspace.md, via gh, directly after the comment line" "$s15_bad"
    st_expect "15 stage 4: the state check reads the origin as confirmed private" "$(st_run "$s15_o")" \
        origin=github.com/example-owner/field-study-ws origin_visibility=private "origin_confirmed=gh:$s15_today"
    (cd "$SCRATCH" && PATH="$s15_gh:$PATH" S15_GH_ANSWER=PRIVATE AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_o/kit/setup.sh" </dev/null >"$s15_o.origin2.log" 2>&1)
    [[ "$(grep -c '^- \*\*Private remote:\*\*' "$s15_o/.claude/workspace.md")" -eq 1 ]] && s15_is "$(s15_outcome "$s15_o.origin2.log" 4)" "already done" \
        && ok "15 stage 4 run again: already done, and the remote is recorded once" \
        || ko "15 stage 4 run again: already done, and the remote is recorded once" "$(s15_outcome "$s15_o.origin2.log" 4)"
    s15_p="$SCRATCH/s15-origin-public"; s15_origin "$s15_p" PUBLIC
    [[ "$(s15_outcome "$s15_p.origin.log" 4)" == "left open (origin is public: make it private, or point origin at a private repository)" ]] \
        && ! grep -q '^- \*\*Private remote:\*\*' "$s15_p/.claude/workspace.md" \
        && ok "15 stage 4: a public origin is left open, and nothing is recorded" \
        || ko "15 stage 4: a public origin is left open, and nothing is recorded" "$(s15_outcome "$s15_p.origin.log" 4)"
    s15_q="$SCRATCH/s15-origin-nogh"; s15_origin "$s15_q" ""
    [[ "$(s15_outcome "$s15_q.origin.log" 4)" == "left open (origin github.com/example-owner/field-study-ws is not confirmed private)" ]] \
        && ! grep -q '^- \*\*Private remote:\*\*' "$s15_q/.claude/workspace.md" \
        && ok "15 stage 4: with no answer from gh, unattended, nothing is recorded and the stage is left open" \
        || ko "15 stage 4: with no answer from gh, unattended, nothing is recorded and the stage is left open" "$(s15_outcome "$s15_q.origin.log" 4)"
    # P3: gh absent, the remote listed as private: the workspace pre-push allows the push. An empty gh
    # config makes any gh on PATH fail at once, without a network call.
    mkdir -p "$SCRATCH/s15-gh-none"
    s15_sha="$(git -C "$s15_o/kit" rev-parse HEAD)"
    (cd "$s15_o" && printf 'refs/heads/main %s refs/heads/main %s\n' "$s15_sha" 0000000000000000000000000000000000000000 \
        | env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$SCRATCH/s15-gh-none" PATH="$SCRATCH/bin32:/usr/bin:/bin" \
            "$st_bash" "$s15_o/kit/githooks/pre-push" origin git@github.com:example-owner/field-study-ws.git >"$s15_o.push.log" 2>&1); s15_rc=$?
    [[ $s15_rc -eq 0 ]] && ok "15 with gh absent, a push to the origin stage 4 recorded as private is allowed" \
        || ko "15 with gh absent, a push to the origin stage 4 recorded as private is allowed" "status $s15_rc: $(cat "$s15_o.push.log")"
else
    skp "15 stage 4 records the confirmed origin, and the pre-push hook allows it without gh — needs $s15_why"
fi

# --- Identity never reads AGENTS.md -----------------------------------------------------------------
if s15_need kitsrc engine state hooks && [[ -d "$SCRATCH/s15-new/.git" ]]; then
    s15_o2="$SCRATCH/s15-opaque"
    cp -R "$SCRATCH/s15-new" "$s15_o2"
    # An AGENTS.md of the team's own (not in the ledger as created), closed to this user.
    awk -F '\t' '$1 != "AGENTS.md"' "$s15_o2/.claude/kit-templates.lock" >"$SCRATCH/s15-lock" && cat "$SCRATCH/s15-lock" >"$s15_o2/.claude/kit-templates.lock"
    printf 'The team keeps this file for another tool.\n' >"$s15_o2/AGENTS.md"
    chmod 000 "$s15_o2/AGENTS.md"
    s15_wz "$SCRATCH/s15-opaque.log" "$s15_o2/kit/setup.sh"; s15_rc=$?
    chmod 644 "$s15_o2/AGENTS.md"
    [[ $s15_rc -eq 0 && "$(cat "$s15_o2/AGENTS.md")" == "The team keeps this file for another tool." ]] \
        && s15_is "$(s15_outcome "$SCRATCH/s15-opaque.log" 2)" "already done" \
        && ok "15 identity reads the ledger and CLAUDE.md: an AGENTS.md closed to this user is neither needed nor touched" \
        || ko "15 identity reads the ledger and CLAUDE.md: an AGENTS.md closed to this user is neither needed nor touched" "status $s15_rc: $(s15_outcome "$SCRATCH/s15-opaque.log" 2)"
else
    skp "15 identity with an AGENTS.md closed to this user — needs ${s15_why:-the new workspace above}"
fi

# --- scripts/build-template.sh ----------------------------------------------------------------------
# The template repository is public and carries this workflow, so the workflow has to let a repository
# marked as a template through, and nothing else: without the guard every push to the template fails,
# and with a looser one a public workspace would pass.
s15_sp="$KIT/templates/workspace/stay-private.yml"
s15_if="$(grep -E '^[[:space:]]*if:' "$s15_sp")"
empty "15 stay-private.yml fails a public repository unless it is marked as a template" \
    "$([[ "$(printf '%s\n' "$s15_if" | grep -c .)" == 1 && "$s15_if" == *'github.event.repository.private == false && github.event.repository.is_template != true'* ]] \
        || printf 'the step condition: %s\n' "${s15_if:-none}")"
if s15_need kitsrc; then
    s15_ne="$SCRATCH/s15-template-nonempty"; mkdir -p "$s15_ne"; : >"$s15_ne/x"
    "$st_bash" "$KIT/scripts/build-template.sh" "$s15_ne" --kit-url "$KITSRC" >/dev/null 2>&1; s15_rc=$?
    [[ $s15_rc -eq 1 && ! -e "$s15_ne/.git" ]] && ok "15 build-template.sh refuses a folder that is not empty" \
        || ko "15 build-template.sh refuses a folder that is not empty" "status $s15_rc"
fi
if s15_need kitsrc engine; then
    s15_t="$SCRATCH/s15-template"
    # The runner's identity is in the environment (GIT_AUTHOR_NAME and the rest); none of it may reach the commit.
    (cd "$SCRATCH" && GIT_AUTHOR_NAME="Machine Person" GIT_COMMITTER_NAME="Machine Person" EMAIL="machine@example.test" \
        "$st_bash" "$KIT/scripts/build-template.sh" "$s15_t" --kit-url "$KITSRC" >"$s15_t.log" 2>&1); s15_rc=$?
    s15_bad=""
    [[ $s15_rc -eq 0 ]] || s15_bad+="status $s15_rc: $(tail -n 4 "$s15_t.log")"$'\n'
    s15_list="$(git -C "$s15_t" ls-files | LC_ALL=C sort | paste -sd' ' -)"
    s15_want=".claude/closeout.md .claude/projects.md .claude/settings.json .github/CODEOWNERS .github/pull_request_template.md .github/workflows/stay-private.yml .gitignore .gitmodules AGENTS.md CLAUDE.md README.md audits/README.md docs/.gitkeep docs/workspace-map.md kit logs/.gitkeep logs/decisions.md memory/.gitkeep memory/glossary.md memory/people/README.md projects/.gitkeep projects/INDEX.md skills/.gitkeep"
    [[ "$s15_list" == "$s15_want" ]] || s15_bad+="file list: $s15_list"$'\n'
    [[ "$(git -C "$s15_t" rev-list --count HEAD 2>/dev/null)" == 1 ]] || s15_bad+="not exactly one commit"$'\n'
    [[ "$(git -C "$s15_t" log -1 --format='%an <%ae>|%cn <%ce>' 2>/dev/null)" == "agentic workspace kit <kit@invalid>|agentic workspace kit <kit@invalid>" ]] \
        || s15_bad+="identity: $(git -C "$s15_t" log -1 --format='%an <%ae>|%cn <%ce>' 2>/dev/null)"$'\n'
    [[ "$(git -C "$s15_t" symbolic-ref HEAD 2>/dev/null)" == refs/heads/main ]] || s15_bad+="not on main"$'\n'
    [[ "$(git -C "$s15_t" ls-files -s -- kit | awk '{ print $1 }')" == 160000 ]] || s15_bad+="kit is not a gitlink"$'\n'
    [[ "$(git config -f "$s15_t/.gitmodules" submodule.kit.url)" == "$KITSRC" ]] || s15_bad+=".gitmodules url: $(git config -f "$s15_t/.gitmodules" submodule.kit.url)"$'\n'
    [[ "$(head -n 1 "$s15_t/CLAUDE.md" 2>/dev/null)" == "@kit/CLAUDE.kit.md" ]] || s15_bad+="CLAUDE.md does not start with the import"$'\n'
    grep -rqs 'Machine Person\|machine@example' "$s15_t/.git/config" "$s15_t/.git/logs" && s15_bad+="the machine identity reached .git"$'\n'
    # What the template ships is the workflow as the kit has it, guard included.
    cmp -s "$s15_t/.github/workflows/stay-private.yml" "$s15_sp" && grep -q 'is_template != true' "$s15_t/.github/workflows/stay-private.yml" \
        || s15_bad+="the built stay-private.yml is not the kit's, or lacks the is_template guard"$'\n'
    empty "15 build-template.sh: the exact file list, one commit on main as the kit, no identity from the machine" "$s15_bad"
    # macOS writes a folder's icon as a file named Icon and a carriage return. The template's line keeps
    # it out, and leaves files named Icon or Icons alone.
    git -C "$s15_t" check-ignore -q --no-index -- "$(printf 'Icon\r')" \
        && ! git -C "$s15_t" check-ignore -q --no-index -- Icons && ! git -C "$s15_t" check-ignore -q --no-index -- Icon \
        && ok "15 the template repository's .gitignore ignores a macOS Icon file, and not Icon or Icons" \
        || ko "15 the template repository's .gitignore ignores a macOS Icon file, and not Icon or Icons" "$(grep -n Icon "$s15_t/.gitignore" | od -c | head -n 3)"
    # A word from the private list stops the build before the commit, and the word is never printed.
    printf '%s\n' '# a comment line is not a word' '' 'standards' >"$SCRATCH/s15-words.txt"
    s15_t2="$SCRATCH/s15-template-words"
    (cd "$SCRATCH" && AW_BANNED_WORDS_FILE="$SCRATCH/s15-words.txt" "$st_bash" "$KIT/scripts/build-template.sh" "$s15_t2" --kit-url "$KITSRC" >"$s15_t2.log" 2>&1); s15_rc=$?
    [[ $s15_rc -eq 1 ]] && ! git -C "$s15_t2" rev-parse -q --verify HEAD >/dev/null 2>&1 \
        && grep -q $'^refused\tCLAUDE.md\tprivate word (line [0-9]*)$' "$s15_t2.log" && ! grep -qi 'standards' "$s15_t2.log" \
        && ok "15 build-template.sh stops on a private word, naming the file and line and never the word, and commits nothing" \
        || ko "15 build-template.sh stops on a private word, naming the file and line and never the word, and commits nothing" "status $s15_rc: $(head -n 4 "$s15_t2.log")"
    # A workspace's own path in the output (here, a kit cloned from inside it) is one of its names.
    s15_w="$SCRATCH/s15-template-ws"; mkdir -p "$s15_w" && git -C "$s15_w" init -q
    git clone -q "$KITSRC" "$s15_w/kit-copy"
    s15_t3="$SCRATCH/s15-template-names"
    (cd "$SCRATCH" && env -u AW_BANNED_WORDS_FILE HOME="$SCRATCH/s15-home-empty" "$st_bash" "$KIT/scripts/build-template.sh" "$s15_t3" \
        --kit-url "$s15_w/kit-copy" --workspace "$s15_w" >"$s15_t3.log" 2>&1); s15_rc=$?
    [[ $s15_rc -eq 1 ]] && grep -q $'^refused\t.gitmodules\tnames the workspace path of the workspace (line [0-9]*)$' "$s15_t3.log" \
        && ok "15 build-template.sh stops on a name of the workspace it is run from (its path, in .gitmodules)" \
        || ko "15 build-template.sh stops on a name of the workspace it is run from (its path, in .gitmodules)" "status $s15_rc: $(head -n 4 "$s15_t3.log")"
else
    skp "15 build-template.sh: the file list, the identity and the word checks — needs $s15_why"
fi

# --- Claude Code: the plugins listed from kit/ (opt-in) ---------------------------------------------
if [[ -d "$SCRATCH/s15-new/kit/.claude-plugin" ]] && s15_need engine; then
    if cc_gate "15 Claude Code lists the agentic-workspace marketplace from a new workspace's kit/"; then
        cc_run "15 marketplace add" plugin marketplace add "$SCRATCH/s15-new/kit" </dev/null >"$SCRATCH/s15-cc-add.log" 2>&1
        cc_run "15 marketplace list" plugin marketplace list </dev/null >"$SCRATCH/s15-cc-list.log" 2>&1; s15_rc=$?
        [[ $s15_rc -eq 0 ]] && grep -q 'agentic-workspace' "$SCRATCH/s15-cc-list.log" \
            && ok "15 Claude Code lists the agentic-workspace marketplace from a new workspace's kit/" \
            || ko "15 Claude Code lists the agentic-workspace marketplace from a new workspace's kit/" "$(cat "$SCRATCH/s15-cc-add.log" "$SCRATCH/s15-cc-list.log")"
    fi
else
    skp "15 Claude Code lists the agentic-workspace marketplace — needs ${s15_why:-a new workspace from above}"
fi
