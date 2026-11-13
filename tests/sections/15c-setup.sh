# shellcheck shell=bash
# The prelude in tests/run.sh defines st_bash, kitsrc_ok and the rest; checks are written "cond && ok || ko"
# as in run.sh, and the stubs written below are single-quoted on purpose.
# shellcheck disable=SC2154,SC2015,SC2016
# Section 15, part 3 of 3: --developer, hooks, stage 4's origin, and build-template.sh. The helpers are in tests/sections/lib/15-setup.sh.
# shellcheck source=tests/sections/lib/15-setup.sh
. "$KIT/tests/sections/lib/15-setup.sh"
echo
echo "15 · Setup: the ten stages, new, adopt, the modes, update, developer mode and the template repository (3 of 3)"

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
        mkws_copy "$1" >/dev/null 2>&1
        git -C "$1" remote add origin git@github.com:example-owner/field-study-ws.git
        (cd "$SCRATCH" && PATH="$s15_gh:$PATH" S15_GH_ANSWER="$2" AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$1/kit/setup.sh" </dev/null >"$1.origin.log" 2>&1)
    }
    s15_o="$SCRATCH/s15-origin-private"; s15_origin "$s15_o" PRIVATE
    # The copy itself (mkws_copy, in tests/run.sh): a copied workspace's hooks resolve inside the copy,
    # for the workspace and its kit, where a plain cp -a of the same build still points at the original.
    s15_bad="" s15_raw="$SCRATCH/s15-copy-raw"
    s15_c0="$(git -C "$s15_o" rev-parse --git-path hooks)"; s15_c1="$(git -C "$s15_o/kit" rev-parse --git-path hooks)"
    [[ "$s15_c0" == "$s15_o"/* && "$s15_c1" == "$s15_o"/* ]] || s15_bad+="the copy's hooks are elsewhere: $s15_c0, $s15_c1"$'\n'
    cp -a "$s15_o" "$s15_raw" 2>/dev/null
    s15_c2="$(git -C "$s15_raw" rev-parse --git-path hooks 2>/dev/null)"
    [[ -n "$s15_c2" && "$s15_c2" != "$s15_raw"/* ]] || s15_bad+="a plain copy's hooks resolve inside it, so the step proves nothing: $s15_c2"$'\n'
    empty "15 a copied fixture workspace runs its own hooks, the workspace's and its kit's, where a plain copy would run the original's" "$s15_bad"
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
    s15_want=".claude/closeout.md .claude/projects.md .claude/settings.json .github/CODEOWNERS .github/pull_request_template.md .github/workflows/stay-private.yml .gitignore .gitmodules AGENTS.md CLAUDE.md README.md audits/README.md docs/.gitkeep docs/workspace-map.md kit logs/.gitkeep logs/decisions.md memory/.gitkeep memory/glossary.md memory/people/README.md memory/terms.md projects/.gitkeep projects/INDEX.md skills/.gitkeep"
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
