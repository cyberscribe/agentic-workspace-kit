# shellcheck shell=bash
# The prelude in tests/run.sh defines st_bash, kitsrc_ok and the rest; checks are written "cond && ok || ko"
# as in run.sh, and the stubs written below are single-quoted on purpose.
# shellcheck disable=SC2154,SC2015,SC2016
# Section 15, part 1 of 3: the dispatch table, new, stages 6 and 8, adopt, identity. The helpers are in tests/sections/lib/15-setup.sh.
# shellcheck source=tests/sections/lib/15-setup.sh
. "$KIT/tests/sections/lib/15-setup.sh"
echo
echo "15 · Setup: the ten stages, new, adopt, the modes, update, developer mode and the template repository (1 of 3)"

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
            agents_md=kit always_loaded=CLAUDE.md plugins_registered=closeout,ongoing,projects,scheduler,workspace plugins_mode=kit \
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

    # --- A settings file that was there first --------------------------------------------------------
    # The engine adds the marketplace to it and nothing else, so stage 3 enables the kit's plugins in it
    # (the default), or names the commands that do. Each run names an empty CLAUDE_CONFIG_DIR, so the
    # runner's own Claude Code settings are never read.
    if s15_need engine state; then
        s15_cc="$SCRATCH/s15-cc-empty"; mkdir -p "$s15_cc"
        # s15_own <dir> <settings json>: a repository of the person's own, with a .claude/settings.json.
        s15_own() {
            mkdir -p "$1/.claude" && git -C "$1" init -q && git -C "$1" symbolic-ref HEAD refs/heads/main
            printf '%s\n' "$2" > "$1/.claude/settings.json"
        }
        s15_all='{"closeout@agentic-workspace":true,"ongoing@agentic-workspace":true,"projects@agentic-workspace":true,"scheduler@agentic-workspace":true,"workspace@agentic-workspace":true}'

        s15_e="$SCRATCH/s15-own-settings"
        s15_own "$s15_e" '{"permissions":{"allow":["Read(./**)"]}}'
        CLAUDE_CONFIG_DIR="$s15_cc" s15_wz "$s15_e.log" "$s15_setup" --target "$s15_e" --team "Test Team" --owner "Sam Example" --owner-handle "@sam"; s15_rc=$?
        s15_bad=""
        [[ $s15_rc -eq 0 ]] || s15_bad+="status $s15_rc"$'\n'
        [[ "$(jq -S -c '.enabledPlugins' "$s15_e/.claude/settings.json" 2>/dev/null)" == "$s15_all" ]] \
            || s15_bad+="enabledPlugins: $(jq -c '.enabledPlugins' "$s15_e/.claude/settings.json" 2>&1)"$'\n'
        [[ "$(jq -c '.permissions.allow' "$s15_e/.claude/settings.json" 2>/dev/null)" == '["Read(./**)"]' ]] || s15_bad+="its own permissions were changed"$'\n'
        s15_is "$(s15_outcome "$s15_e.log" 3)" done || s15_bad+="stage 3: $(s15_outcome "$s15_e.log" 3)"$'\n'
        s15_is "$(s15_outcome "$s15_e.log" 9)" done || s15_bad+="stage 9: $(s15_outcome "$s15_e.log" 9)"$'\n'
        grep -q 'claude plugin enable ' "$s15_e.log" && s15_bad+="enable commands printed with nothing left to enable"$'\n'
        grep '^  git add ' "$s15_e.log" | grep_all ' \.claude/settings\.json' || s15_bad+=".claude/settings.json is not in the git add line"$'\n'
        empty "15 a settings file of the person's own, unattended: the kit's plugins are enabled in it, its own keys kept, stages 3 and 9 done" "$s15_bad"
        st_expect "15 ... and the state check reads them enabled by the workspace's settings alone" \
            "$(CLAUDE_CONFIG_DIR="$s15_cc" st_run "$s15_e")" plugins_registered=closeout,ongoing,projects,scheduler,workspace plugins_not_loaded= plugins_scope=workspace
        s15_bad=""
        grep -q 'plugins_scope=workspace' "$s15_e.log" || s15_bad+="stage 9 does not say where the plugins load"$'\n'
        grep -qF "claude plugin marketplace add --scope user $(s15_real "$s15_e")/kit" "$s15_e.log" || s15_bad+="no marketplace add --scope user line"$'\n'
        for s15_p in closeout ongoing projects scheduler workspace; do
            grep -qF "claude plugin install $s15_p@agentic-workspace --scope user" "$s15_e.log" || s15_bad+="no user-scope install line for $s15_p"$'\n'
        done
        empty "15 stage 9 says the plugins load only in a session opened on the workspace's own folder, with the commands that install them for the person" "$s15_bad"

        # One switched off on purpose stays off, and is the only one the commands name.
        s15_e="$SCRATCH/s15-own-settings-off"
        s15_own "$s15_e" '{"enabledPlugins":{"projects@agentic-workspace":false}}'
        CLAUDE_CONFIG_DIR="$s15_cc" s15_wz "$s15_e.log" "$s15_setup" --target "$s15_e" --team "Test Team" --owner "Sam Example" --owner-handle "@sam"
        s15_bad=""
        [[ "$(jq -S -c '.enabledPlugins' "$s15_e/.claude/settings.json" 2>/dev/null)" == '{"closeout@agentic-workspace":true,"ongoing@agentic-workspace":true,"projects@agentic-workspace":false,"scheduler@agentic-workspace":true,"workspace@agentic-workspace":true}' ]] \
            || s15_bad+="enabledPlugins: $(jq -c '.enabledPlugins' "$s15_e/.claude/settings.json" 2>&1)"$'\n'
        grep -qF "claude plugin enable projects@agentic-workspace --scope project" "$s15_e.log" || s15_bad+="the enable command for projects is not printed"$'\n'
        grep -qE 'claude plugin enable (closeout|ongoing|scheduler|workspace)@' "$s15_e.log" && s15_bad+="an enable command for a plugin that is enabled"$'\n'
        s15_is "$(s15_outcome "$s15_e.log" 3)" "left open" || s15_bad+="stage 3: $(s15_outcome "$s15_e.log" 3)"$'\n'
        s15_is "$(s15_outcome "$s15_e.log" 9)" "left open" || s15_bad+="stage 9: $(s15_outcome "$s15_e.log" 9)"$'\n'
        grep -q '✗ plugins enabled in .claude/settings.json' "$s15_e.log" || s15_bad+="stage 9 has no failing line for the plugins"$'\n'
        empty "15 a plugin the settings file sets to false stays off; stages 3 and 9 are left open and name its enable command alone" "$s15_bad"

        # Attended, the offer declined: the five answers before it take their defaults (stage 1's pause,
        # the pilot question, stage 2's pause, adding the kit, running the engine).
        s15_e="$SCRATCH/s15-own-settings-no"
        s15_own "$s15_e" '{"permissions":{"allow":["Read(./**)"]}}'
        (cd "$SCRATCH" && printf '\n\n\n\n\nn\n' | CLAUDE_CONFIG_DIR="$s15_cc" AW_KIT_URL="$KITSRC" AW_WIZARD_NONINTERACTIVE=0 "$st_bash" "$s15_setup" \
            --target "$s15_e" --team "Test Team" --owner "Sam Example" --owner-handle "@sam" >"$s15_e.log" 2>&1)
        s15_bad=""
        [[ "$(jq -c '.enabledPlugins // "absent"' "$s15_e/.claude/settings.json" 2>/dev/null)" == '"absent"' ]] \
            || s15_bad+="enabledPlugins was written: $(jq -c '.enabledPlugins' "$s15_e/.claude/settings.json" 2>&1)"$'\n'
        [[ "$(jq -r '.extraKnownMarketplaces["agentic-workspace"].source.path' "$s15_e/.claude/settings.json" 2>/dev/null)" == kit ]] || s15_bad+="the marketplace was not added"$'\n'
        for s15_p in closeout ongoing projects scheduler workspace; do
            [[ "$(grep -cF "claude plugin enable $s15_p@agentic-workspace --scope project" "$s15_e.log")" -ge 3 ]] \
                || s15_bad+="the enable command for $s15_p is not in stages 3, 7 and 9"$'\n'
        done
        grep -qF "cd $(s15_real "$s15_e")" "$s15_e.log" || s15_bad+="the commands do not start in the workspace's folder"$'\n'
        grep -q "This workspace's settings do not enable: closeout, ongoing, projects, scheduler, workspace" "$s15_e.log" || s15_bad+="stage 7 does not say so before its steps"$'\n'
        s15_is "$(s15_outcome "$s15_e.log" 3)" "left open" || s15_bad+="stage 3: $(s15_outcome "$s15_e.log" 3)"$'\n'
        empty "15 attended, the offer declined: the settings file keeps no enabledPlugins, and stages 3, 7 and 9 print the four enable commands" "$s15_bad"
    else
        skp "15 a settings file of the person's own: the plugins enabled, or the commands named — needs $s15_why"
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
