# shellcheck shell=bash
# The prelude in tests/run.sh defines KIT, KITSRC, STATE, st_bash and the helpers. ok and ko always
# return 0, so the suite's "test && ok || ko" form reads as if-then-else.
# shellcheck disable=SC2015,SC2154
# Section 20: the migration from the 2.x layout (lib/setup/migrate.sh, contract §9). Sourced by
# tests/run.sh after section 11; every name here starts s20_.
#
# The migration hands work to other scripts from M8 on: lib/setup/gitconfig.sh (hooks, submodule
# settings), install.sh (the engine, M15) and scripts/skills-bridge.sh (M17). Until those are built, a
# real run stops at M8 with exit 3, so the checks that need a run to finish are reported as SKIP,
# naming what they wait for, and the checks on the steps before M8 still run.
echo
echo "20 · The migration from the 2.x layout: dry run, real run, the map, and what it never touches"

s20_scr="$SCRATCH/s20"
mkdir -p "$s20_scr"

# s20_built <kit path>: 0 when that script is past its placeholder.
s20_built() { [[ -f "$KIT/$1" ]] && ! grep -q 'not built yet' "$KIT/$1"; }
s20_wait=""
s20_built lib/setup/gitconfig.sh || s20_wait+="${s20_wait:+, }lib/setup/gitconfig.sh (C1)"
grep -q 'kit-templates.lock' "$KIT/install.sh" 2>/dev/null || s20_wait+="${s20_wait:+, }the 3.0 install.sh engine (C2)"
s20_built scripts/skills-bridge.sh || s20_wait+="${s20_wait:+, }scripts/skills-bridge.sh (C7)"
s20_wait_state=""
grep -q 'state_version 2' "$STATE" 2>/dev/null || s20_wait_state="plugins/workspace/bin/state.sh 3.0 keys (C4)"

# s20_run <kit checkout> <workspace> [args...]: the migration from that kit checkout, the way a person
# runs it: kit/setup.sh migrate once setup.sh dispatches it, else the script itself. Output goes to
# $s20_out and $s20_err; the status is returned.
s20_out="$s20_scr/out" s20_err="$s20_scr/err"
s20_run() {
    local k="$1" w="$2"; shift 2
    if grep -q 'lib/setup/migrate.sh' "$k/setup.sh" 2>/dev/null; then
        "$st_bash" "$k/setup.sh" migrate --target "$w" "$@" </dev/null >"$s20_out" 2>"$s20_err"
    else
        "$st_bash" "$k/lib/setup/migrate.sh" --target "$w" "$@" </dev/null >"$s20_out" 2>"$s20_err"
    fi
}
# s20_actions <file>: the action lines, in order.
s20_actions() { grep -E '^(would )?(move|retire|edit|config|run|note|skip) ' "$1"; }
# s20_commit <dir>: a commit in a fixture, with no hooks, since what is under test is the migration.
s20_commit() { git -C "$1" add -A && git -C "$1" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -q -m "$2"; }
s20_advance() {  # the kit checkout at <path> brought to KITSRC by hand, as a developer's checkout is
    git -C "$1" -c protocol.file.allow=always fetch -q "$KITSRC" main && git -C "$1" checkout -q --detach FETCH_HEAD
}

check "20 migrate.sh parses under $st_bash" "$st_bash" -n "$KIT/lib/setup/migrate.sh"
empty "20 every git read in migrate.sh carries --no-optional-locks, or goes through mg_g or aw_git_elsewhere" \
    "$(grep -nE '(^|[;&|({]|\$\()[[:space:]]*git[[:space:]]+(ls-files|log|rev-parse|diff|status|show|cat-file|grep)' "$KIT/lib/setup/migrate.sh" \
        | grep -vE '^[0-9]+:[[:space:]]*(#|echo |printf )' | grep -v -- '--no-optional-locks')"
check "20 migrate.sh --help exits 0" "$st_bash" "$KIT/lib/setup/migrate.sh" --help
"$st_bash" "$KIT/lib/setup/migrate.sh" --dry-run >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "20 no --target is a usage error (exit 2)" || ko "20 no --target is a usage error (exit 2)"

s20_ws="$s20_scr/ws"
mkws2x "$s20_ws"
s20_rc=$?
if [[ $s20_rc -eq 3 ]]; then
    skp "20 the 2.x fixture needs 915c528 in the object store (a shallow clone): the mkws2x checks do not run"
elif [[ $s20_rc -ne 0 ]]; then
    ko "20 the 2.x fixture (mkws2x) builds" "$(tail -n 5 "$s20_ws.log" 2>/dev/null)"
else
    # What a workspace of some age holds besides the kit's files: a doc naming the old kit path, a
    # dated record naming it too, a skill of the team's own, finished projects in a folder of their own
    # (one tracked, one ignored), paused ones likewise, and a register link to a finished project.
    s20_k="$s20_ws/templates/agentic-workspace"
    mkdir -p "$s20_ws/docs" "$s20_ws/skills/field-notes" "$s20_ws/archive/old-survey" \
        "$s20_ws/archive/vendor-notes" "$s20_ws/on-hold/field-study"
    printf 'The closeout ritual is templates/agentic-workspace/rituals/closeout.md.\n' > "$s20_ws/docs/notes.md"
    printf '\n## 2026-01-05 Kit checkout path\n\nThe kit sat at templates/agentic-workspace/ then.\n' >> "$s20_ws/logs/decisions.md"
    printf -- '---\nname: field-notes\ndescription: "A skill of the team'"'"'s own."\n---\n\nNotes.\n' > "$s20_ws/skills/field-notes/SKILL.md"
    printf '# Old survey\n' > "$s20_ws/archive/old-survey/README.md"
    printf '# Vendor notes\n' > "$s20_ws/archive/vendor-notes/README.md"
    printf '# Field study\n' > "$s20_ws/on-hold/field-study/README.md"
    printf '/archive/vendor-notes/\n' > "$s20_ws/.gitignore"
    python3 - "$s20_ws/.claude/projects.md" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"- \*\*Paused:\*\*.*?(?=\n- \*\*Done)", "- **Paused:** `on-hold/<slug>/` — moved there while paused.", s, flags=re.S)
s = re.sub(r"- \*\*Done:\*\*.*?(?=\n- \*\*Entry point)", "- **Done:** `archive/<slug>/` — moved there when finished.", s, flags=re.S)
open(p, "w").write(s)
PY
    printf '| [Old survey](../archive/old-survey/) | done |\n' >> "$s20_ws/projects/INDEX.md"
    s20_commit "$s20_ws" "A workspace of some age"
    s20_advance "$s20_k"
    s20_agents_sum="$(git hash-object "$s20_ws/AGENTS.md")"

    # A malformed map stops the run before anything moves (exit 2).
    printf 'git-mv\tdocs/notes.md\tdocs/moved.md\nfrobnicate docs\n' > "$s20_scr/bad.map"
    st_tree "$s20_ws" > "$s20_scr/tree-bad-before"
    s20_run "$s20_k" "$s20_ws" --map "$s20_scr/bad.map"; s20_rc=$?
    st_tree "$s20_ws" > "$s20_scr/tree-bad-after"
    [[ $s20_rc -eq 2 ]] && cmp -s "$s20_scr/tree-bad-before" "$s20_scr/tree-bad-after" && grep -q 'line 2' "$s20_err" \
        && ok "20 a malformed map exits 2, naming the line, before anything moves" \
        || ko "20 a malformed map exits 2, naming the line, before anything moves" "rc $s20_rc; $(cat "$s20_err")"
    printf 'git-mv docs/notes.md ../outside.md\n' > "$s20_scr/bad2.map"
    s20_run "$s20_k" "$s20_ws" --map "$s20_scr/bad2.map"; s20_rc=$?
    [[ $s20_rc -eq 2 ]] && ok "20 a map path with .. is malformed (exit 2)" || ko "20 a map path with .. is malformed (exit 2)" "rc $s20_rc"
    printf 'retire AGENTS.md\n' > "$s20_scr/bad3.map"
    s20_run "$s20_k" "$s20_ws" --map "$s20_scr/bad3.map"; s20_rc=$?
    [[ $s20_rc -eq 2 ]] && grep -q 'opaque' "$s20_err" && ok "20 a map line naming an opaque file is malformed (exit 2)" \
        || ko "20 a map line naming an opaque file is malformed (exit 2)" "rc $s20_rc; $(cat "$s20_err")"

    # The opaque AGENTS.md is made unreadable for the runs below: any attempt to open it shows.
    chmod 000 "$s20_ws/AGENTS.md"

    st_tree "$s20_ws" > "$s20_scr/tree-dry-before"
    s20_run "$s20_k" "$s20_ws" --dry-run; s20_rc=$?
    st_tree "$s20_ws" > "$s20_scr/tree-dry-after"
    cp "$s20_out" "$s20_scr/dry.out"; cp "$s20_err" "$s20_scr/dry.err"
    [[ $s20_rc -eq 0 ]] && ok "20 the dry run finishes (exit 0)" || ko "20 the dry run finishes (exit 0)" "rc $s20_rc; $(cat "$s20_err")"
    s20_d="$(diff "$s20_scr/tree-dry-before" "$s20_scr/tree-dry-after" 2>&1)"
    empty "20 the dry run changes nothing in the workspace (st_tree, .git included)" "$s20_d"
    s20_d="$(s20_actions "$s20_scr/dry.out" | grep -v '^would ')"
    empty "20 every action line of the dry run starts with would" "$s20_d"
    # The steps handed to other scripts show, under their would-run line, what they would set and
    # create, and the engine's files are in the dry run's commit plan.
    s20_d=""
    grep -q '^    would set \. core\.hooksPath=' "$s20_scr/dry.out" || s20_d+="no core.hooksPath line under M8"$'\n'
    grep -q '^    would set \. push\.recurseSubmodules=check' "$s20_scr/dry.out" || s20_d+="no push.recurseSubmodules line under M9"$'\n'
    grep -q '^    would create \.github/workflows/stay-private\.yml' "$s20_scr/dry.out" || s20_d+="no stay-private.yml line under M15"$'\n'
    grep -q '^  git add .*\.github/workflows/stay-private\.yml' "$s20_scr/dry.out" || s20_d+="the dry run's commit plan leaves out the engine's files"$'\n'
    empty "20 the dry run shows what gitconfig.sh and the engine would set and create, and plans the engine's files" "$s20_d"

    s20_run "$s20_k" "$s20_ws"; s20_rc=$?
    cp "$s20_out" "$s20_scr/real.out"; cp "$s20_err" "$s20_scr/real.err"
    s20_actions "$s20_scr/dry.out" | sed 's/^would //' > "$s20_scr/dry.act"
    s20_actions "$s20_scr/real.out" > "$s20_scr/real.act"
    if [[ -z "$s20_wait" ]]; then
        [[ $s20_rc -eq 0 ]] && ok "20 the real run finishes (exit 0)" || ko "20 the real run finishes (exit 0)" "rc $s20_rc; $(cat "$s20_scr/real.err")"
        grep -q '^  git add .*\.github/workflows/stay-private\.yml' "$s20_scr/real.out" \
            && ok "20 the real run's commit plan names the files the engine created" \
            || ko "20 the real run's commit plan names the files the engine created" "$(grep -A3 '^Then:' "$s20_scr/real.out")"
        s20_d="$(diff "$s20_scr/dry.act" "$s20_scr/real.act" 2>&1)"
        empty "20 the dry run's action lines are the real run's, with would in front" "$s20_d"
    else
        [[ $s20_rc -eq 3 ]] && grep -q 'stopped at M8' "$s20_scr/real.err" \
            && ok "20 the real run stops at M8 while the scripts it hands over to are placeholders (exit 3)" \
            || ko "20 the real run stops at M8 while the scripts it hands over to are placeholders (exit 3)" "rc $s20_rc; $(cat "$s20_scr/real.err")"
        s20_n="$(awk 'END { print NR }' "$s20_scr/real.act")"
        head -n "$s20_n" "$s20_scr/dry.act" > "$s20_scr/dry-head.act"
        s20_d="$(diff "$s20_scr/dry-head.act" "$s20_scr/real.act" 2>&1)"
        empty "20 the real run's action lines up to where it stopped are the dry run's, with would in front" "$s20_d"
        skp "20 the dry run's action lines equal the whole real run's — waits for $s20_wait"
    fi

    # Nothing is deleted: every retired path is under _delete/, and _delete/ is ignored.
    s20_d=""
    while IFS= read -r s20_l; do
        s20_p="${s20_l#retire }"; s20_p="${s20_p%% -> *}"
        [[ -e "$s20_ws/_delete/$s20_p" && ! -e "$s20_ws/$s20_p" ]] || s20_d+="$s20_p"$'\n'
    done < <(grep '^retire ' "$s20_scr/real.act")
    grep -q '^retire \.claude/plugins ' "$s20_scr/real.act" || s20_d+="(.claude/plugins was not retired)"$'\n'
    grep -q '^retire skills/projects-new ' "$s20_scr/real.act" || s20_d+="(skills/projects-new was not retired)"$'\n'
    empty "20 nothing is deleted: the vendored plugins, the generated skills and the unchanged copies are under _delete/" "$s20_d"
    git -C "$s20_ws" check-ignore -q _delete/x && ok "20 _delete/ is ignored before anything moves into it" \
        || ko "20 _delete/ is ignored before anything moves into it"
    [[ -f "$s20_ws/skills/field-notes/SKILL.md" ]] && ! grep -q 'skills/field-notes' "$s20_scr/real.act" \
        && ok "20 a skill without the generator's marker stays in skills/" || ko "20 a skill without the generator's marker stays in skills/"
    [[ -f "$s20_ws/kit/CLAUDE.kit.md" && ! -e "$s20_ws/templates/agentic-workspace" ]] \
        && [[ "$(git -C "$s20_ws" config -f .gitmodules --get submodule.templates/agentic-workspace.path)" == kit ]] \
        && ok "20 M1: the kit is at kit/, its submodule keeping its old name" || ko "20 M1: the kit is at kit/, its submodule keeping its old name"
    [[ "$(jq -c '.extraKnownMarketplaces["agentic-workspace"].source' "$s20_ws/.claude/settings.json")" == '{"source":"directory","path":"kit"}' ]] \
        && [[ "$(jq -c '.enabledPlugins' "$s20_ws/.claude/settings.json")" == "$(git -C "$s20_ws" show HEAD:.claude/settings.json | jq -c '.enabledPlugins')" ]] \
        && ok "20 M3: the marketplace path is kit, and nothing else in the settings changed" \
        || ko "20 M3: the marketplace path is kit, and nothing else in the settings changed"

    # M7: a reference is rewritten, and one in a dated record is only noted.
    grep -q '^edit docs/notes.md:1 ' "$s20_scr/real.act" && grep -q 'kit/rituals/closeout.md' "$s20_ws/docs/notes.md" \
        && ok "20 M7 rewrites a reference to the old kit path" || ko "20 M7 rewrites a reference to the old kit path" "$(cat "$s20_ws/docs/notes.md")"
    grep -q '^note logs/decisions.md:[0-9]* names templates/agentic-workspace/' "$s20_scr/real.act" \
        && grep -q 'at templates/agentic-workspace/ then' "$s20_ws/logs/decisions.md" \
        && ok "20 M7 only notes a reference in a decisions log" || ko "20 M7 only notes a reference in a decisions log"

    # The opaque file: never opened, never changed.
    s20_d="$(grep -h 'AGENTS.md' "$s20_scr/dry.err" "$s20_scr/real.err"; grep -hi 'permission denied' "$s20_scr/dry.err" "$s20_scr/real.err")"
    chmod 644 "$s20_ws/AGENTS.md"
    [[ -z "$s20_d" && "$(git hash-object "$s20_ws/AGENTS.md")" == "$s20_agents_sum" ]] \
        && ok "20 an opaque AGENTS.md (unreadable here) is untouched and unread" \
        || ko "20 an opaque AGENTS.md (unreadable here) is untouched and unread" "$s20_d"

    if [[ -n "$s20_wait" ]]; then
        skp "20 M11 moves finished projects to projects/_done/ (git mv, and mv under a new ignore line) — waits for $s20_wait"
        skp "20 the real run reaches the 3.0 state keys — waits for $s20_wait"
        skp "20 a second run prints only skip lines — waits for $s20_wait"
    else
        s20_d=""
        [[ -f "$s20_ws/projects/_done/old-survey/README.md" ]] && git -C "$s20_ws" ls-files --error-unmatch projects/_done/old-survey/README.md >/dev/null 2>&1 \
            || s20_d+="old-survey was not moved with git mv"$'\n'
        [[ -f "$s20_ws/projects/_done/vendor-notes/README.md" ]] && git -C "$s20_ws" check-ignore -q projects/_done/vendor-notes/README.md \
            || s20_d+="vendor-notes was not moved and kept ignored"$'\n'
        grep -q '](_done/old-survey/)' "$s20_ws/projects/INDEX.md" || s20_d+="the register link was not rewritten"$'\n'
        grep -qF -- "- **Done:** \`projects/_done/<slug>/\`" "$s20_ws/.claude/projects.md" || s20_d+="the Done bullet was not rewritten"$'\n'
        grep -q '^note 1 paused projects in on-hold/' "$s20_scr/real.act" || s20_d+="no note for the paused folder"$'\n'
        [[ -f "$s20_ws/on-hold/field-study/README.md" ]] || s20_d+="the paused project moved"$'\n'
        empty "20 M11 moves finished projects to projects/_done/ (git mv, and mv under a new ignore line); M12 moves nothing" "$s20_d"
        if [[ -n "$s20_wait_state" ]]; then
            skp "20 the real run reaches the 3.0 state keys — waits for $s20_wait_state"
        else
            st_expect "20 the real run reaches the 3.0 state keys" "$(st_run "$s20_ws")" \
                claude_md=kit plugins_mode=kit kit_path=kit hooks=active legacy=
        fi
        s20_run "$s20_ws/kit" "$s20_ws"; s20_rc=$?
        s20_d="$(s20_actions "$s20_out" | grep -v '^skip ')"
        [[ $s20_rc -eq 0 && -z "$s20_d" ]] && ok "20 a second run prints only skip lines" \
            || ko "20 a second run prints only skip lines" "rc $s20_rc; $s20_d$(cat "$s20_err")"
    fi

    # A throwaway clone: the kit submodule not populated, brought in with --kit-from from another
    # 3.0 checkout (KITSRC), the way the proof on a real workspace is run.
    s20_cl="$s20_scr/clone"
    git clone -q --no-hardlinks "$s20_ws" "$s20_cl" 2>/dev/null
    git -C "$s20_cl" config remote.origin.pushurl no-push://throwaway
    s20_run "$KITSRC" "$s20_cl" --kit-from "$KITSRC" --dry-run
    s20_actions "$s20_out" | sed 's/^would //' > "$s20_scr/clone-dry.act"
    s20_run "$KITSRC" "$s20_cl" --kit-from "$KITSRC"; s20_rc=$?
    cp "$s20_out" "$s20_scr/clone.out"; cp "$s20_err" "$s20_scr/clone.err"
    s20_actions "$s20_scr/clone.out" > "$s20_scr/clone-real.act"
    s20_d="$(diff "$s20_scr/clone-dry.act" "$s20_scr/clone-real.act" 2>&1)"
    empty "20 on a clone with an unpopulated kit, the dry run names the real run's kit steps (init, url, update) and every other action" "$s20_d"
    s20_st="$(git -C "$s20_cl" submodule status 2>&1)"
    if [[ -n "$s20_wait" ]]; then
        [[ $s20_rc -eq 3 && -f "$s20_cl/kit/CLAUDE.kit.md" ]] && ! printf '%s\n' "$s20_st" | grep -q '^-' \
            && ok "20 a clone with an unpopulated kit, run with --kit-from, gets the kit at kit/ and an active submodule (runs to M8 while $s20_wait wait)" \
            || ko "20 a clone with an unpopulated kit, run with --kit-from, gets the kit at kit/ and an active submodule" "rc $s20_rc; $s20_st; $(cat "$s20_scr/clone.err")"
    else
        [[ $s20_rc -eq 0 && -f "$s20_cl/kit/CLAUDE.kit.md" ]] && ! printf '%s\n' "$s20_st" | grep -q '^-' \
            && ok "20 a clone with an unpopulated kit, run with --kit-from, migrates, and its submodule is active" \
            || ko "20 a clone with an unpopulated kit, run with --kit-from, migrates, and its submodule is active" "rc $s20_rc; $s20_st; $(cat "$s20_scr/clone.err")"
    fi
fi

# M0b, M1 and a map's submodule-mv in one uncommitted run. git refuses to move a submodule while
# .gitmodules has unstaged changes, so each write to it is staged at once.
s20_o="$s20_scr/orphan-2x"
if [[ -n "$s20_wait" ]]; then
    skp "20 an orphan gitlink, M1 and a map's submodule-mv in one run — waits for $s20_wait"
elif mkws2x "$s20_o"; then
    git init -q "$s20_scr/site-src2" && git -C "$s20_scr/site-src2" commit -q --allow-empty -m site
    git -C "$s20_o" -c protocol.file.allow=always submodule add -q "$s20_scr/site-src2" public >/dev/null 2>&1
    git -C "$s20_o" update-index --add --cacheinfo "160000,$(git -C "$KITSRC" rev-parse HEAD),projects/archive-tool"
    mkdir -p "$s20_o/projects/archive-tool"
    s20_commit "$s20_o" "An orphan gitlink and a site submodule"
    s20_advance "$s20_o/templates/agentic-workspace"
    printf 'submodule-register\tprojects/archive-tool\thttps://example.invalid/archive-tool.git\tmain\nsubmodule-mv\tpublic\tprojects/site\n' > "$s20_scr/orphan.map"
    s20_run "$s20_o/templates/agentic-workspace" "$s20_o" --dry-run --map "$s20_scr/orphan.map"; s20_rc=$?
    s20_actions "$s20_out" | sed 's/^would //' > "$s20_scr/orphan-dry.act"
    s20_run "$s20_o/templates/agentic-workspace" "$s20_o" --map "$s20_scr/orphan.map"; s20_rc2=$?
    s20_actions "$s20_out" > "$s20_scr/orphan-real.act"; cp "$s20_err" "$s20_scr/orphan-real.err"
    s20_d="$(diff "$s20_scr/orphan-dry.act" "$s20_scr/orphan-real.act" 2>&1)"
    if [[ $s20_rc -eq 0 && $s20_rc2 -eq 0 && -f "$s20_o/kit/CLAUDE.kit.md" ]] && git -C "$s20_o" diff --quiet -- .gitmodules \
        && [[ "$(git -C "$s20_o" ls-files -s -- projects/site | awk '{ print $1 }')" == 160000 ]] \
        && [[ "$(git -C "$s20_o" config -f .gitmodules --get submodule.projects/archive-tool.url)" == https://example.invalid/archive-tool.git ]]; then
        empty "20 an orphan gitlink, M1 and a map's submodule-mv go through in one uncommitted run, .gitmodules staged, and the dry run's action lines match" "$s20_d"
    else
        ko "20 an orphan gitlink, M1 and a map's submodule-mv go through in one uncommitted run, .gitmodules staged, and the dry run's action lines match" \
            "rc $s20_rc/$s20_rc2; $(git -C "$s20_o" status --short -- .gitmodules); $(cat "$s20_scr/orphan-real.err")"
    fi
else
    ko "20 the 2.x fixture for the orphan gitlink builds" "$(tail -n 5 "$s20_o.log" 2>/dev/null)"
fi

# A run that stops and is resumed: the commit plan and the staged list the resumed run prints cover
# the whole migration, not only the part the resumed run did.
s20_r="$s20_scr/resume-2x"
if [[ -n "$s20_wait" ]]; then
    skp "20 a stopped and resumed run plans the whole migration — waits for $s20_wait"
elif mkws2x "$s20_r"; then
    mkdir -p "$s20_r/docs" && printf 'Move me.\n' > "$s20_r/docs/moveme.md" && printf 'a file, not a folder\n' > "$s20_r/blocker"
    printf 'The kit checkout is templates/agentic-workspace for now.\n' > "$s20_r/docs/kitref.md"
    s20_commit "$s20_r" "Material for a stopped run"
    s20_advance "$s20_r/templates/agentic-workspace"
    printf 'git-mv\tdocs/moveme.md\tblocker/moveme.md\n' > "$s20_scr/stop.map"
    printf 'git-mv\tdocs/moveme.md\tdocs/moved/moveme.md\n' > "$s20_scr/resume.map"
    s20_run "$s20_r/templates/agentic-workspace" "$s20_r" --map "$s20_scr/stop.map"; s20_rc=$?
    cp "$s20_err" "$s20_scr/stop.err"
    s20_run "$s20_r/kit" "$s20_r" --map "$s20_scr/resume.map"; s20_rc2=$?
    cp "$s20_out" "$s20_scr/resume.out"
    s20_add="$(grep '^  git add ' "$s20_scr/resume.out")"
    s20_d=""
    [[ $s20_rc -eq 3 ]] && grep -q 'stopped at M16' "$s20_scr/stop.err" || s20_d+="the first run did not stop at M16 (rc $s20_rc)"$'\n'
    [[ $s20_rc2 -eq 0 ]] || s20_d+="the resumed run exited $s20_rc2: $(cat "$s20_err")"$'\n'
    grep -q 'It covers the earlier run that stopped at M16' "$s20_scr/resume.out" || s20_d+="no line naming the earlier run"$'\n'
    for s20_p in kit .claude/settings.json docs/moved/moveme.md; do
        [[ " ${s20_add#  git add } " == *" $s20_p "* ]] || s20_d+="the git add line leaves out $s20_p"$'\n'
    done
    grep -qx '  templates/agentic-workspace' "$s20_scr/resume.out" || s20_d+="the staged list leaves out the kit's move"$'\n'
    grep -q '^note docs/kitref.md:1 still names templates/agentic-workspace' "$s20_scr/resume.out" \
        || s20_d+="the resumed run's M18 leaves out the first run's move of the kit"$'\n'
    [[ ! -e "$(git -C "$s20_r" rev-parse --absolute-git-dir)/aw-migrate-state" ]] || s20_d+="aw-migrate-state is left after the run finished"$'\n'
    s20_run "$s20_r/kit" "$s20_r" --map "$s20_scr/resume.map"
    grep -q '^Nothing changed in this run' "$s20_out" || s20_d+="a third run did not say nothing changed"$'\n'
    empty "20 a run that stops and is resumed prints a commit plan, staged list and leftover references for the whole migration" "$s20_d"
else
    ko "20 the 2.x fixture for the stopped run builds" "$(tail -n 5 "$s20_r.log" 2>/dev/null)"
fi

# M0: a kit checkout with a .git folder of its own, on a cp -R copy (a clone always absorbs).
if [[ $kitsrc_ok -eq 1 ]]; then
    s20_e="$s20_scr/embedded"
    mkdir -p "$s20_e/.claude" && git -C "$s20_e" init -q && git -C "$s20_e" symbolic-ref HEAD refs/heads/main
    git -c protocol.file.allow=always clone -q "$KITSRC" "$s20_e/templates/agentic-workspace" 2>/dev/null
    git -C "$s20_e" -c protocol.file.allow=always submodule add -q -b main "$KITSRC" templates/agentic-workspace >/dev/null 2>&1
    printf '{ "extraKnownMarketplaces": { "agentic-workspace": { "source": { "source": "directory", "path": "templates/agentic-workspace" } } } }\n' \
        > "$s20_e/.claude/settings.json"
    printf '# Field study team\n\nOur own standards.\n' > "$s20_e/CLAUDE.md"
    s20_commit "$s20_e" "An embedded kit checkout"
    cp -R "$s20_e" "$s20_scr/embedded-copy"
    s20_run "$s20_scr/embedded-copy/templates/agentic-workspace" "$s20_scr/embedded-copy"; s20_rc=$?
    s20_st="$(git -C "$s20_scr/embedded-copy" submodule status 2>&1)"
    grep -q '^run git submodule absorbgitdirs -- templates/agentic-workspace' "$s20_out" \
        && [[ -f "$s20_scr/embedded-copy/kit/.git" ]] && ! printf '%s\n' "$s20_st" | grep -q '^-' \
        && ok "20 M0 absorbs an embedded kit .git, then M1 moves the kit to kit/" \
        || ko "20 M0 absorbs an embedded kit .git, then M1 moves the kit to kit/" "rc $s20_rc; $s20_st; $(cat "$s20_err")"
fi

# Preconditions and the orphan gitlink, on a 3.0 workspace (mkws_min), where every step before M8 is
# already done.
s20_m="$s20_scr/min"
if mkws_min "$s20_m"; then
    git -C "$s20_m" update-index --add --cacheinfo "160000,$(git -C "$KITSRC" rev-parse HEAD),projects/archive-tool"
    mkdir -p "$s20_m/projects/archive-tool" "$s20_m/kit/maps"
    printf 'note inside the kit\n' > "$s20_m/kit/maps/ws.map"
    s20_run "$s20_m/kit" "$s20_m" --allow-staged --map "$s20_m/kit/maps/ws.map"; s20_rc=$?
    [[ $s20_rc -eq 2 ]] && grep -q 'keep it outside kit/' "$s20_err" \
        && ok "20 a map inside kit/ is refused (exit 2)" || ko "20 a map inside kit/ is refused (exit 2)" "rc $s20_rc; $(cat "$s20_err")"
    s20_run "$s20_m/kit" "$s20_m"; s20_rc=$?
    [[ $s20_rc -eq 1 ]] && grep -q 'staged changes' "$s20_err" \
        && ok "20 staged changes stop the run (exit 1) without --allow-staged" || ko "20 staged changes stop the run (exit 1) without --allow-staged" "rc $s20_rc"
    s20_run "$s20_m/kit" "$s20_m" --allow-staged; s20_rc=$?
    [[ $s20_rc -eq 3 ]] && grep -q 'submodule-register projects/archive-tool' "$s20_err" && grep -q 'untrack projects/archive-tool' "$s20_err" \
        && ! grep -q '^run kit/lib/setup/gitconfig.sh' "$s20_out" \
        && ok "20 an orphan gitlink stops the run before M8 and M9 (exit 3), naming the two fixes" \
        || ko "20 an orphan gitlink stops the run before M8 and M9 (exit 3), naming the two fixes" "rc $s20_rc; $(cat "$s20_err")"
    printf 'submodule-register\tprojects/archive-tool\thttps://example.invalid/archive-tool.git\tmain\n' > "$s20_scr/register.map"
    s20_run "$s20_m/kit" "$s20_m" --allow-staged --map "$s20_scr/register.map"; s20_rc=$?
    [[ "$(git -C "$s20_m" config -f .gitmodules --get submodule.projects/archive-tool.url)" == https://example.invalid/archive-tool.git ]] \
        && ! grep -q 'no .gitmodules entry' "$s20_err" \
        && ok "20 with submodule-register in the map, the orphan gitlink is registered and the run goes on" \
        || ko "20 with submodule-register in the map, the orphan gitlink is registered and the run goes on" "rc $s20_rc; $(cat "$s20_err")"
else
    ko "20 the 3.0 fixture (mkws_min) builds"
fi

# The map, every verb, on a migrated workspace: a dry run and a real run, compared, then checked.
if [[ -n "$s20_wait" ]]; then
    skp "20 a map with every verb (keep protecting a lookalike, an absent source skipped) — waits for $s20_wait"
    skp "20 --confirm-private-origin records origin under Private remotes, via person — waits for $s20_wait"
elif [[ -d "$s20_ws/kit" ]]; then
    s20_w="$s20_ws"
    s20_commit "$s20_w" "The 3.0 layout"
    mkdir -p "$s20_w/ai" "$s20_w/docs/shared/ai" "$s20_w/projects/field-study" "$s20_w/scratch-notes"
    printf 'Profile.\n' > "$s20_w/ai/profile.md"
    printf 'Old guide.\n' > "$s20_w/docs/old-guide.md"
    printf 'Obsolete.\n' > "$s20_w/docs/obsolete.md"
    printf 'Read ai/profile.md, (ai/tools.md) and shared/ai/COLLABORATION.md.\n' > "$s20_w/docs/links.md"
    printf 'Contact list.\n' > "$s20_w/projects/field-study/intake.md"
    printf '# Field study\n' > "$s20_w/projects/field-study/README.md"
    printf 'draft\n' > "$s20_w/scratch-notes/one.md"
    printf 'scratch-notes/\n' >> "$s20_w/.gitignore"
    git init -q "$s20_scr/site-src" && git -C "$s20_scr/site-src" commit -q --allow-empty -m site
    git -C "$s20_w" -c protocol.file.allow=always submodule add -q "$s20_scr/site-src" vendor/site >/dev/null 2>&1
    s20_commit "$s20_w" "Material for the map"
    cat > "$s20_scr/every.map" <<'MAP'
# Every verb once.
git-mv	ai	memory/ai
git-mv	docs/old-guide.md	docs/guides/guide.md
git-mv	docs/absent.md	docs/gone.md
submodule-mv	vendor/site	projects/site
mv	scratch-notes	projects/field-study/scratch-notes
retire	docs/obsolete.md
untrack	projects/field-study/intake.md
gitignore-add	*.tmp
gitignore-rewrite	scratch-notes/	projects/field-study/scratch-notes/
keep	shared/ai/COLLABORATION.md
rewrite	ai/	memory/ai/
note check the field-study owner with Priya Shah
MAP
    s20_run "$s20_w/kit" "$s20_w" --dry-run --map "$s20_scr/every.map"; s20_rc=$?
    s20_actions "$s20_out" | sed 's/^would //' > "$s20_scr/map-dry.act"
    s20_run "$s20_w/kit" "$s20_w" --map "$s20_scr/every.map"; s20_rc2=$?
    s20_actions "$s20_out" > "$s20_scr/map-real.act"
    s20_d="$(diff "$s20_scr/map-dry.act" "$s20_scr/map-real.act" 2>&1)"
    [[ $s20_rc -eq 0 && $s20_rc2 -eq 0 ]] && empty "20 a map's dry run and real run print the same action lines" "$s20_d" \
        || ko "20 a map's dry run and real run print the same action lines" "rc $s20_rc/$s20_rc2; $(cat "$s20_err")"
    s20_d=""
    [[ -f "$s20_w/memory/ai/profile.md" && ! -e "$s20_w/ai" ]] || s20_d+="git-mv of a folder"$'\n'
    [[ -f "$s20_w/docs/guides/guide.md" ]] || s20_d+="git-mv with a new parent folder"$'\n'
    grep -q '^skip git-mv docs/absent.md -> docs/gone.md (not present here)' "$s20_scr/map-real.act" || s20_d+="the absent source was not skipped"$'\n'
    [[ "$(git -C "$s20_w" ls-files -s -- projects/site | awk '{ print $1 }')" == 160000 ]] || s20_d+="submodule-mv"$'\n'
    [[ -f "$s20_w/projects/field-study/scratch-notes/one.md" && ! -e "$s20_w/scratch-notes" ]] || s20_d+="mv"$'\n'
    [[ -f "$s20_w/_delete/docs/obsolete.md" ]] || s20_d+="retire"$'\n'
    [[ -f "$s20_w/projects/field-study/intake.md" ]] && ! git -C "$s20_w" ls-files --error-unmatch projects/field-study/intake.md >/dev/null 2>&1 \
        && grep -qx '/projects/field-study/intake.md' "$s20_w/.gitignore" || s20_d+="untrack"$'\n'
    grep -qx '\*.tmp' "$s20_w/.gitignore" || s20_d+="gitignore-add"$'\n'
    grep -qx 'projects/field-study/scratch-notes/' "$s20_w/.gitignore" || s20_d+="gitignore-rewrite"$'\n'
    [[ "$(cat "$s20_w/docs/links.md")" == 'Read memory/ai/profile.md, (memory/ai/tools.md) and shared/ai/COLLABORATION.md.' ]] \
        || s20_d+="rewrite with keep: $(cat "$s20_w/docs/links.md")"$'\n'
    grep -q '^note check the field-study owner with Priya Shah' "$s20_scr/map-real.act" || s20_d+="note"$'\n'
    empty "20 a map with every verb: moves, retire, untrack, the .gitignore verbs, rewrite with keep protecting a lookalike, note" "$s20_d"
    s20_run "$s20_w/kit" "$s20_w" --map "$s20_scr/every.map"; s20_rc=$?
    s20_d="$(s20_actions "$s20_out" | grep -vE '^(skip|note) ')"
    [[ $s20_rc -eq 0 && -z "$s20_d" ]] && ok "20 the same map run again changes nothing" \
        || ko "20 the same map run again changes nothing" "rc $s20_rc; $s20_d"

    git -C "$s20_w" remote add origin https://github.com/example-org/field-workspace.git
    s20_run "$s20_w/kit" "$s20_w" --allow-staged --confirm-private-origin; s20_rc=$?
    (
        # shellcheck source=/dev/null
        . "$KIT/lib/common.sh"
        aw_private_remotes "$s20_w"
    ) > "$s20_scr/remotes"
    [[ $s20_rc -eq 0 ]] && grep -q "^github.com/example-org/field-workspace	person	$(date +%F)\$" "$s20_scr/remotes" \
        && ok "20 --confirm-private-origin records origin under Private remotes, via person" \
        || ko "20 --confirm-private-origin records origin under Private remotes, via person" "rc $s20_rc; $(cat "$s20_scr/remotes" "$s20_err")"
fi
