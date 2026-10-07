# shellcheck shell=bash
# The prelude defines st_bash, kitsrc_ok and the rest; "check && ok || ko" is the suite's idiom, and ok
# always succeeds. Single-quoted $ and backticks below are literal text on purpose.
# shellcheck disable=SC2154,SC2015,SC2016
# Section 16: the 3.0 state check (plugins/workspace/bin/state.sh) and the workspace plugin's
# session-start summary (plugins/workspace/hooks/session-start.sh). Sourced by tests/run.sh after
# section 11; it uses the prelude's helpers (ok, ko, skp, check, empty, st_*, mkws_min, mkws_hooks,
# gitcount_run, aw_count) and writes only under $SCRATCH/s16. Every name here starts s16_.
echo
echo "16 · The state check's 3.0 keys, --quick and --explain, and the workspace session-start summary"

s16_S="$SCRATCH/s16"
s16_hook="$KIT/plugins/workspace/hooks/session-start.sh"
s16_hooks_json="$KIT/plugins/workspace/hooks/hooks.json"
mkdir -p "$s16_S"
st_err=""
# The default opaque list (§0.4), whatever the calling shell has set, for the checks that rely on it.
s16_opq="AGENTS.md copilot-instructions.md"

check "16 state.sh parses under $st_bash" "$st_bash" -n "$STATE"
check "16 session-start.sh parses under $st_bash" "$st_bash" -n "$s16_hook"
if command -v shellcheck >/dev/null 2>&1; then
    check "16 shellcheck -x is clean on state.sh and the workspace session-start hook" \
        bash -c 'cd "$1" && shellcheck -x plugins/workspace/bin/state.sh plugins/workspace/hooks/session-start.sh' _ "$KIT"
else
    skp "16 shellcheck not on PATH; state.sh and session-start.sh not linted"
fi
empty "16 every git call in state.sh and session-start.sh carries --no-optional-locks" \
    "$(grep -nE '(^|[;&|({]|\$\()[[:space:]]*git[[:space:]]' "$STATE" "$s16_hook" | grep -vE ':[0-9]+:[[:space:]]*#' | grep -v -- '--no-optional-locks')"
s16_bad=""
jq -e '.hooks.SessionStart[0].matcher == "startup"
       and .hooks.SessionStart[0].hooks[0].command == "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\""
       and .hooks.SessionStart[0].hooks[0].timeout == 10
       and .hooks.PreToolUse[0].matcher == "Bash"
       and .hooks.PreToolUse[0].hooks[0].command == "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/guard-git.sh\""
       and .hooks.PreToolUse[0].hooks[0].timeout == 5' "$s16_hooks_json" >/dev/null 2>&1 || s16_bad+="hooks.json does not register the two hooks as §5.3 says"$'\n'
[[ -x "$KIT/plugins/workspace/hooks/session-start.sh" && -x "$KIT/plugins/workspace/bin/state.sh" ]] || s16_bad+="state.sh or session-start.sh is not executable"$'\n'
empty "16 hooks.json registers SessionStart (startup, 10 s) and the PreToolUse Bash guard (5 s)" "$s16_bad"

# ---- The two copies of the shared functions ----------------------------------------------------------
# s16_fn <file> <function>: the function's text, from its "name() {" line to the first "}" line.
s16_fn() { awk -v f="$2() {" 'index($0, f) == 1 { p = 1 } p { print } p && /^}/ { exit }' "$1"; }
s16_bad=""
for s16_f in aw_norm_url _aw_norm_local _aw_remote_lines aw_private_remotes aw_is_opaque aw_word_list; do
    s16_a="$(s16_fn "$KIT/lib/common.sh" "$s16_f")" s16_b="$(s16_fn "$STATE" "$s16_f")"
    [[ -n "$s16_a" && "$s16_a" == "$s16_b" ]] || s16_bad+="$s16_f differs between lib/common.sh and state.sh"$'\n'
done
empty "16 state.sh's copies of aw_norm_url, aw_private_remotes, aw_is_opaque and aw_word_list match lib/common.sh" "$s16_bad"
mkdir -p "$s16_S/remote-dir"
# A literal tilde: the normaliser expands it.
# shellcheck disable=SC2088
s16_tilde='~/no-such-remote'
s16_urls=(
    "git@github.com:Example-Org/Field-Notes.git"
    "ssh://git@github.com:22/example-org/field-notes.git"
    "https://sam:token123@github.com/example-org/field-notes"
    "https://github.com/example-org/field-notes.git/"
    "HTTPS://GITHUB.COM/Example-Org/Field-Notes"
    "$s16_S/remote-dir"
    "file://$s16_S/remote-dir"
    "github-work:example-org/field-notes.git"
    "git://github.com/example-org/field-notes.git"
    "http://gitlab.example.com:8080/team/vendor-review.git"
    "ssh://git@github.com/example-org/field-notes/"
    "$s16_tilde"
)
# s16_norm <file>: the 12 URLs through that file's aw_norm_url, one per line.
s16_norm() {
    ( eval "$(s16_fn "$1" _aw_norm_local)"; eval "$(s16_fn "$1" aw_norm_url)"
      for u in "${s16_urls[@]}"; do aw_norm_url "$u"; done )
}
s16_na="$(s16_norm "$KIT/lib/common.sh")" s16_nb="$(s16_norm "$STATE")"
s16_want="github.com/example-org/field-notes"
[[ "$s16_na" == "$s16_nb" && "$(printf '%s\n' "$s16_na" | aw_count)" == 12 \
   && "$(printf '%s\n' "$s16_na" | sed -n '1,5p' | sort -u)" == "$s16_want" \
   && "$(printf '%s\n' "$s16_na" | sed -n 6p)" == "local:$s16_S/remote-dir" \
   && "$(printf '%s\n' "$s16_na" | sed -n 7p)" == "local:$s16_S/remote-dir" \
   && "$(printf '%s\n' "$s16_na" | sed -n 8p)" == "github-work/example-org/field-notes" ]] \
    && ok "16 the 12-URL table gives the same output from both copies of aw_norm_url" \
    || ko "16 the 12-URL table gives the same output from both copies of aw_norm_url" "$(diff <(printf '%s\n' "$s16_na") <(printf '%s\n' "$s16_nb"); printf '%s\n' "$s16_na")"
# s16_renorm <file>: each of the 12 outputs normalised again by that file's copy; it has to be unchanged,
# since the Private remotes list is written in the normalised form (github.com/owner/repo).
s16_renorm() {
    ( eval "$(s16_fn "$1" _aw_norm_local)"; eval "$(s16_fn "$1" aw_norm_url)"
      while IFS= read -r u; do aw_norm_url "$u"; done )
}
[[ "$(printf '%s\n' "$s16_na" | s16_renorm "$KIT/lib/common.sh")" == "$s16_na" \
   && "$(printf '%s\n' "$s16_nb" | s16_renorm "$STATE")" == "$s16_nb" ]] \
    && ok "16 aw_norm_url gives back a normalised URL unchanged (host/owner/repo and local:<path>), in both copies" \
    || ko "16 aw_norm_url gives back a normalised URL unchanged (host/owner/repo and local:<path>), in both copies" \
          "$(printf '%s\n' "$s16_na" | s16_renorm "$KIT/lib/common.sh")"

# ---- --explain ----------------------------------------------------------------------------------------
s16_ex="$("$st_bash" "$STATE" --explain 2>&1)"; s16_rc=$?
s16_hdr="$(awk '/^# Keys/ { k = 1; next } k && /^# Lists are/ { exit } k { sub(/^#[ \t]*/, ""); print }' "$STATE" | tr ' ' '\n' | sed '/^$/d' | sort -u)"
s16_bad=""
[[ $s16_rc -eq 0 ]] || s16_bad+="--explain exited $s16_rc"$'\n'
while IFS= read -r s16_k; do
    [[ -n "$s16_k" ]] || continue
    printf '%s\n' "$s16_ex" | awk -v k="$s16_k: " 'index($0, k) == 1 && length($0) > length(k) { f = 1 } END { exit !f }' \
        || s16_bad+="no meaning for $s16_k"$'\n'
done <<EOF
$s16_hdr
EOF
[[ "$("$st_bash" "$STATE" --explain submodule.projects/site 2>/dev/null)" == "submodule.<path>: role="* ]] || s16_bad+="--explain submodule.projects/site does not give the submodule.<path> entry"$'\n'
[[ "$("$st_bash" "$STATE" --explain hooks 2>/dev/null)" == "hooks: active "* ]] || s16_bad+="--explain hooks: $("$st_bash" "$STATE" --explain hooks 2>&1)"$'\n'
"$st_bash" "$STATE" --explain no_such_key >/dev/null 2>&1 && s16_bad+="--explain no_such_key exits 0"$'\n'
empty "16 --explain gives a meaning for every key the header lists, per-item keys by pattern, and exits 1 for an unknown key" "$s16_bad"

if [[ $kitsrc_ok -ne 1 ]]; then
    skp "16 the fixture checks need KITSRC (the kit is not a git checkout)"
else

# s16_commit <dir> <message>: everything in the folder, committed.
s16_commit() { git -C "$1" add -A && git -C "$1" -c commit.gpgsign=false commit -q -m "$2"; }
# s16_copy <from> <to>: a copy of a fixture workspace with its own hooks (a copy's hooks path would
# still point at the original's stubs).
s16_copy() {
    cp -R "$1" "$2" || return 1
    git -C "$2" config --unset core.hooksPath; git -C "$2/kit" config --unset core.hooksPath
    mkws_hooks "$2"
}
# s16_project_hooks <ws> <path>: the workspace's stubs, written into a project repository's own git dir.
s16_project_hooks() {
    local gd; gd="$(git -C "$1/$2" rev-parse --absolute-git-dir)" || return 1
    mkdir -p "$gd/aw-hooks" && cp -p "$(git -C "$1" rev-parse --absolute-git-dir)"/aw-hooks/* "$gd/aw-hooks/" \
        && git -C "$1/$2" config core.hooksPath "$gd/aw-hooks"
}
# s16_hookrun <cwd> [VAR=value...]: the session-start hook with {"cwd": <cwd>} on stdin; its stdout. Any
# stderr, or a status other than 0, is collected in s16_hook_err.
s16_hook_err=""
s16_hookrun() {
    local c="$1" o rc; shift
    o="$(printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$c" | env "$@" "$st_bash" "$s16_hook" 2>"$s16_S/hook.err")"; rc=$?
    [[ $rc -eq 0 && ! -s "$s16_S/hook.err" ]] || s16_hook_err+="$c: rc $rc $(cat "$s16_S/hook.err")"$'\n'
    printf '%s' "$o"
}
s16_msg() { jq -r '.systemMessage // empty' 2>/dev/null; }

# ---- W: the smallest workspace, then committed -------------------------------------------------------
s16_W="$s16_S/ws"
mkws_min "$s16_W"; s16_rc=$?
git -C "$s16_W" config user.name "Priya Shah"
if [[ $s16_rc -ne 0 ]]; then
    ko "16 mkws_min builds the fixture workspace" "status $s16_rc"
else
s16_kv="$(awk '/^## v/ { s = $2; sub(/^v/, "", s); print s; exit }' "$KIT/CHANGELOG.md")"
s16_kc="$(git -C "$KITSRC" rev-parse --short HEAD)"
r="$(st_run "$s16_W")"
st_expect "16 a new workspace: hooks, the kit at kit/ on main, the import, no origin" "$r" state_version=2 in_git=yes \
    hooks=active kit_hooks=active hooks_chain= kit_path=kit kit_submodule=yes "kit_commit=$s16_kc" "kit_version=$s16_kv" \
    kit_branch=main kit_behind=0 kit_import=ok kit_untracked_refused=0 origin= origin_visibility=none origin_confirmed= \
    workspace_conventions=present ledger=missing resources_file=missing skills_bridge=missing skills_bridge_count=0 \
    skills_bridge_stale=0 legacy=
st_expect "16 a new workspace: submodules, projects and resources" "$r" submodules=kit \
    "submodule.kit=role=kit dirty=0 unpushed=0 remote=yes pointer=new behind=0 branch=main hooks=n/a" \
    submodules_attention= orphan_gitlinks= submodule_recurse=off \
    submodule_config=missing:push.recurseSubmodules,status.submoduleSummary,submodule.recurse \
    sensitive_projects= sensitive_tracked= versioned_mismatch= external_paths= external_paths_missing=
st_expect "16 a new workspace: the changed 2.x keys read the 3.0 layout" "$r" claude_md=kit always_loaded=CLAUDE.md \
    agents_md=missing plugins_mode=kit plugins_path=kit kit_checkout=kit measure_script=kit/pilot/measure.sh \
    vendored_commit= kit_incoming= standins_remaining=0 mode=joining signs=
git -C "$s16_W" config push.recurseSubmodules check
git -C "$s16_W" config status.submoduleSummary true
git -C "$s16_W" config submodule.recurse true
printf '# Written by kit/install.sh.\n' > "$s16_W/.claude/kit-templates.lock"
s16_commit "$s16_W" "A workspace"
r="$(st_run "$s16_W")"
st_expect "16 committed, with the submodule settings: the pointer is ok and the settings are ok" "$r" \
    "submodule.kit=role=kit dirty=0 unpushed=0 remote=yes pointer=ok behind=0 branch=main hooks=n/a" \
    submodule_config=ok submodule_recurse=on ledger=present submodules_attention=

# ---- The §11.4 green set -----------------------------------------------------------------------------
# The keys a fresh install is held to, on a fixture shaped like one: the engine's AGENTS.md (recorded
# created in the ledger), a stand-in left in CLAUDE.md §2, the submodule settings.
s16_G="$s16_S/green"
s16_copy "$s16_W" "$s16_G"
printf '@kit/CLAUDE.kit.md\n\n# How this workspace is read\n' > "$s16_G/AGENTS.md"
printf 'AGENTS.md\ttemplates/workspace/AGENTS.md\t%s\t-\tcreated\n' "$(git -C "$KITSRC" rev-parse HEAD)" >> "$s16_G/.claude/kit-templates.lock"
sed 's/^Plain, short answers\.$/<how the agent should show up here>/' "$s16_W/CLAUDE.md" > "$s16_G/CLAUDE.md"
r="$(AW_OPAQUE_PATHS="$s16_opq" st_run "$s16_G")"
st_expect "16 the §11.4 green set, every key present" "$r" in_git=yes hooks=active kit_hooks=active kit_path=kit \
    kit_submodule=yes kit_import=ok ledger=present workspace_conventions=present claude_md=kit agents_md=kit \
    always_loaded=CLAUDE.md plugins_registered=closeout,projects,workspace plugins_mode=kit submodule_config=ok \
    submodules_attention= orphan_gitlinks= sensitive_tracked= versioned_mismatch= external_paths_missing= legacy= \
    kit_incoming= mode=fresh origin_visibility=none
s16_bad=""
for s16_k in in_git hooks kit_hooks kit_path kit_submodule kit_import ledger workspace_conventions claude_md agents_md \
    always_loaded plugins_registered plugins_mode submodule_config submodules_attention orphan_gitlinks sensitive_tracked \
    versioned_mismatch external_paths_missing legacy kit_incoming mode origin_visibility; do
    printf '%s\n' "$r" | grep -q "^$s16_k=" || s16_bad+="$s16_k is not emitted"$'\n'
done
empty "16 every §11.4 key is emitted by the full check" "$s16_bad"
s16_M="$s16_S/mkws-new"
mkws "$s16_M"; s16_rc=$?
if [[ $s16_rc -eq 0 ]]; then
    st_expect "16 setup.sh new reaches the §11.4 green set" "$(st_run "$s16_M")" in_git=yes hooks=active kit_hooks=active \
        kit_path=kit kit_submodule=yes kit_import=ok ledger=present workspace_conventions=present claude_md=kit \
        agents_md=kit always_loaded=CLAUDE.md plugins_registered=closeout,projects,workspace plugins_mode=kit \
        submodule_config=ok submodules_attention= orphan_gitlinks= sensitive_tracked= versioned_mismatch= \
        external_paths_missing= legacy= kit_incoming= mode=fresh origin_visibility=none
else
    skp "16 setup.sh new is not built in this tree (mkws returned $s16_rc); the green set is checked on the fixture above"
fi

# ---- hooks: active, missing, other, none -------------------------------------------------------------
s16_H="$s16_S/hooks-gone"
s16_copy "$s16_W" "$s16_H"
chmod -x "$s16_H/kit/githooks/pre-push"
st_expect "16 hooks missing when a stub's kit hook is gone (not executable)" "$(st_run "$s16_H")" hooks=missing kit_hooks=missing
chmod +x "$s16_H/kit/githooks/pre-push"
st_expect "16 control: with the kit hook back, active again" "$(st_run "$s16_H")" hooks=active kit_hooks=active
s16_gd="$(git -C "$s16_H" rev-parse --absolute-git-dir)"
sed '2s/.*/# a hook of another kind/' "$s16_gd/aw-hooks/commit-msg" > "$s16_S/commit-msg" && cat "$s16_S/commit-msg" > "$s16_gd/aw-hooks/commit-msg"
st_expect "16 hooks missing when a stub has lost its marker" "$(st_run "$s16_H")" hooks=missing kit_hooks=active
s16_O="$s16_S/hooks-other"
s16_copy "$s16_W" "$s16_O"
mkdir -p "$s16_S/elsewhere-hooks"
git -C "$s16_O" config core.hooksPath "$s16_S/elsewhere-hooks"
git -C "$s16_O/kit" config --unset core.hooksPath
printf '[core]\n\thooksPath = %s\n' "$s16_S/elsewhere-hooks" > "$s16_S/global.gitconfig"
st_expect "16 hooks other when set to another folder; the kit's missing when unset" "$(st_run "$s16_O")" hooks=other kit_hooks=missing hooks_chain=
st_expect "16 hooks other when only a global hooks path is in effect" "$(GIT_CONFIG_GLOBAL="$s16_S/global.gitconfig" st_run "$s16_O")" kit_hooks=other
git -C "$s16_O" config aw.chainHooksPath "$s16_S/elsewhere-hooks"
st_expect "16 hooks_chain reads aw.chainHooksPath" "$(st_run "$s16_O")" "hooks_chain=$s16_S/elsewhere-hooks"
mkdir -p "$s16_S/unreadable-system-config"
st_expect "16 a system git config git cannot read (a sandbox denying /etc) still reads the repository" \
    "$(GIT_CONFIG_SYSTEM="$s16_S/unreadable-system-config" st_run "$s16_O")" in_git=yes kit_path=kit
mkdir -p "$s16_S/plain"
st_expect "16 a plain folder: hooks none, kit none" "$(st_run "$s16_S/plain")" in_git=no hooks=none kit_hooks=none \
    kit_path=none kit_submodule=none kit_behind=none kit_import=missing origin_visibility=unknown submodules=

# ---- kit_import: missing and broken; the kit behind and detached --------------------------------------
s16_I="$s16_S/import-missing"
s16_copy "$s16_W" "$s16_I"
sed '1,2d' "$s16_W/CLAUDE.md" > "$s16_I/CLAUDE.md"
st_expect "16 kit_import missing when CLAUDE.md does not start with the import" "$(st_run "$s16_I")" kit_import=missing claude_md=own
s16_C="$s16_S/clone-no-kit"
git clone -q "$s16_W" "$s16_C" 2>/dev/null
r="$(st_run "$s16_C")"
st_expect "16 a clone with the kit not initialised: kit_import broken, the kit found from .gitmodules" "$r" \
    kit_import=broken kit_path=kit kit_submodule=yes kit_hooks=none hooks=missing \
    "submodule.kit=role=kit dirty=0 unpushed=unknown remote=none pointer=uninitialized behind=unknown branch=none hooks=n/a" \
    "origin=local:$s16_W" origin_visibility=unconfirmed
s16_KU="$s16_S/kit-upstream"
git clone -q "$KITSRC" "$s16_KU" 2>/dev/null && printf 'a later kit commit\n' > "$s16_KU/later.txt" && s16_commit "$s16_KU" "Later"
s16_B="$s16_S/kit-behind"
s16_copy "$s16_W" "$s16_B"
git -C "$s16_B/kit" -c protocol.file.allow=always fetch -q "$s16_KU" main:refs/remotes/origin/main 2>/dev/null
r="$(st_run "$s16_B")"
st_expect "16 kit_behind from a pre-fetched ref, with no network" "$r" kit_behind=1 kit_branch=main submodules_attention=kit
git -C "$s16_B/kit" checkout -q --detach
r="$(st_run "$s16_B")"
st_expect "16 kit_branch detached; behind still read against origin/<.gitmodules branch>" "$r" kit_branch=detached kit_behind=1 \
    "submodule.kit=role=kit dirty=0 unpushed=0 remote=yes pointer=ok behind=1 branch=detached hooks=n/a"

# ---- Submodules: roles, and each way out of step -------------------------------------------------------
s16_mkup() { # <dir> <readme text>: an upstream repository on main with one commit
    mkdir -p "$1" && git -C "$1" init -q && git -C "$1" symbolic-ref HEAD refs/heads/main \
        && printf '%b' "$2" > "$1/README.md" && s16_commit "$1" "First"
}
s16_mkup "$s16_S/up-site" '# Site\n\n- **Versioned:** own-repo\n- **Sensitivity:** normal\n'
s16_mkup "$s16_S/up-tool" '# A scheduler kept as its own repository\n'
s16_U="$s16_S/subs"
s16_copy "$s16_W" "$s16_U"
git -C "$s16_U" -c protocol.file.allow=always submodule add -q -b main "$s16_S/up-site" projects/site >/dev/null 2>&1
git -C "$s16_U" -c protocol.file.allow=always submodule add -q -b main "$s16_S/up-tool" tools/scheduler >/dev/null 2>&1
git -C "$s16_U" config --unset submodule.recurse
s16_commit "$s16_U" "Two submodules"
r="$(st_run "$s16_U")"
st_expect "16 submodules: roles kit, project and outside; recursion held for the outside one" "$r" \
    submodules=kit,projects/site,tools/scheduler submodules_attention= submodule_recurse=held \
    "submodule.projects/site=role=project dirty=0 unpushed=0 remote=yes pointer=ok behind=0 branch=main hooks=missing" \
    "submodule.tools/scheduler=role=outside dirty=0 unpushed=0 remote=yes pointer=ok behind=0 branch=main hooks=n/a" \
    submodule_config=missing:submodule.projects/site.update versioned_mismatch= sensitive_projects=
s16_project_hooks "$s16_U" projects/site
git -C "$s16_U" config submodule.projects/site.update rebase
st_expect "16 a project submodule's own hooks; update=rebase makes the settings ok with recursion held" "$(st_run "$s16_U")" \
    "submodule.projects/site=role=project dirty=0 unpushed=0 remote=yes pointer=ok behind=0 branch=main hooks=active" \
    submodule_config=ok
git -C "$s16_U/projects/site" checkout -q --detach
st_expect "16 a detached project with update=rebase needs attention" "$(st_run "$s16_U")" submodules_attention=projects/site \
    "submodule.projects/site=role=project dirty=0 unpushed=0 remote=yes pointer=ok behind=0 branch=detached hooks=active"
git -C "$s16_U" config submodule.projects/site.update checkout
st_expect "16 control: detached with update=checkout does not" "$(st_run "$s16_U")" submodules_attention=
git -C "$s16_U" config submodule.projects/site.update rebase
git -C "$s16_U/projects/site" checkout -q main
printf 'draft\n' > "$s16_U/projects/site/draft.md"
printf 'local change\n' > "$s16_U/tools/scheduler/local.txt"
st_expect "16 a dirty project needs attention; a dirty outside submodule never does" "$(st_run "$s16_U")" submodules_attention=projects/site \
    "submodule.projects/site=role=project dirty=1 unpushed=0 remote=yes pointer=ok behind=0 branch=main hooks=active" \
    "submodule.tools/scheduler=role=outside dirty=1 unpushed=0 remote=yes pointer=ok behind=0 branch=main hooks=n/a"
s16_commit "$s16_U/projects/site" "A draft"
st_expect "16 a commit in the project: unpushed, and the pointer not committed" "$(st_run "$s16_U")" \
    "submodule.projects/site=role=project dirty=0 unpushed=1 remote=yes pointer=uncommitted behind=0 branch=main hooks=active"
git -C "$s16_U" add projects/site
st_expect "16 the pointer staged" "$(st_run "$s16_U")" \
    "submodule.projects/site=role=project dirty=0 unpushed=1 remote=yes pointer=staged behind=0 branch=main hooks=active"
printf 'upstream\n' > "$s16_S/up-site/upstream.md" && s16_commit "$s16_S/up-site" "Upstream"
git -C "$s16_U/projects/site" -c protocol.file.allow=always fetch -q origin 2>/dev/null
r="$(st_run "$s16_U")"
st_expect "16 behind its remote, from the fetched ref" "$r" submodules_attention=projects/site \
    "submodule.projects/site=role=project dirty=0 unpushed=1 remote=yes pointer=staged behind=1 branch=main hooks=active"
s16_v="$(st_key "$r" submodule.projects/site)"
if grep -q 'sed -n "s/^\$1=//p"' "$KIT/lib/wizard.sh"; then
    [[ "$s16_v" == role=project* ]] && ok "16 st_key reads a per-item key with a slash" || ko "16 st_key reads a per-item key with a slash" "$r"
    skp "16 lib/wizard.sh state_key is still the 2.2.0 sed lookup; the awk lookup is C3's (§0.1)"
else
    s16_w="$( ( . "$KIT/lib/wizard.sh" >/dev/null 2>&1; WZ_STATE="$r"; state_key submodule.projects/site ) </dev/null 2>/dev/null)"
    [[ "$s16_v" == role=project* && "$s16_w" == "$s16_v" ]] \
        && ok "16 a per-item key with a slash is read the same by st_key and the wizard's state_key" \
        || ko "16 a per-item key with a slash is read the same by st_key and the wizard's state_key" "st_key: $s16_v"$'\n'"state_key: $s16_w"
fi
s16_j="$(st_run "$s16_U" --quick --json | jq -r '."submodule.projects/site"' 2>/dev/null)"
[[ "$s16_j" == "$s16_v" ]] && ok "16 --json keeps per-item keys as they are" || ko "16 --json keeps per-item keys as they are" "$s16_j"

# ---- orphan gitlinks and the origin ------------------------------------------------------------------
s16_R="$s16_S/orphan"
s16_copy "$s16_W" "$s16_R"
git -C "$s16_R" update-index --add --cacheinfo "160000,$(git -C "$s16_W" rev-parse HEAD),projects/archive-tool"
st_expect "16 a gitlink with no .gitmodules entry is an orphan, and the walks skip it" "$(st_run "$s16_R")" \
    orphan_gitlinks=projects/archive-tool submodules=kit submodules_attention=
s16_V="$s16_S/origin"
s16_copy "$s16_W" "$s16_V"
git -C "$s16_V" remote add origin "git@github.com:Example-Org/Field-Notes.git"
st_expect "16 origin unconfirmed when not listed" "$(st_run "$s16_V")" origin=github.com/example-org/field-notes \
    origin_visibility=unconfirmed origin_confirmed=
cp "$s16_V/.claude/workspace.md" "$s16_S/workspace.md.orig"
awk '{ print } /^<!-- - \*\*Private remote:/ { print "- **Private remote:** `https://github.com/example-org/field-notes` — confirmed 2026-09-30 via gh" }' \
    "$s16_S/workspace.md.orig" > "$s16_V/.claude/workspace.md"
st_expect "16 origin private when listed, with how and when it was confirmed" "$(st_run "$s16_V")" origin_visibility=private \
    origin_confirmed=gh:2026-09-30
awk '{ print } /^<!-- - \*\*Private remote:/ { print "- **Private remote:** `github.com/example-org/field-notes`" }' \
    "$s16_S/workspace.md.orig" > "$s16_V/.claude/workspace.md"
st_expect "16 a hand-written line with no date reads via person" "$(st_run "$s16_V")" origin_visibility=private origin_confirmed=person:
printf '%s\n' '<!-- - **Private remote:** `github.com/example-org/field-notes` — confirmed 2026-09-30 via gh -->' > "$s16_S/ws-comment.md"
cp "$s16_S/ws-comment.md" "$s16_V/.claude/workspace.md"
st_expect "16 a commented example is not a listing" "$(st_run "$s16_V")" origin_visibility=unconfirmed

# ---- The word list ------------------------------------------------------------------------------------
printf 'zzyzx\n' > "$s16_S/words.txt"
mkdir -p "$s16_S/home-empty"
r="$(AW_BANNED_WORDS_FILE="$s16_S/words.txt" st_run "$s16_W")"
[[ "$(st_key "$r" word_list)" == resolves && "$r" != *"$s16_S/words.txt"* ]] \
    && ok "16 word_list resolves, and its path is never printed" || ko "16 word_list resolves, and its path is never printed" "$r"
st_expect "16 word_list unreadable when named and missing" "$(AW_BANNED_WORDS_FILE="$s16_S/no-words.txt" st_run "$s16_W")" word_list=unreadable
st_expect "16 word_list none when nothing names one" "$(AW_BANNED_WORDS_FILE='' HOME="$s16_S/home-empty" st_run "$s16_W")" word_list=none

# ---- Projects: sensitivity, versioning, resources -------------------------------------------------------
s16_P="$s16_S/projects"
s16_copy "$s16_W" "$s16_P"
s16_readme() { mkdir -p "$s16_P/$1" && printf '%b' "$2" > "$s16_P/$1/README.md"; }
s16_readme projects/field-study '# Field study\n\n- **Versioned:** workspace\n- **Sensitivity:** sensitive\n\n## Resources\n\n- media — raw interview recordings\n- exports — generated renders\n- survey-data — the survey extract\n- bad name — a stray\n'
printf 'notes\n' > "$s16_P/projects/field-study/notes.md"
mkdir -p "$s16_P/projects/field-study/exports"
s16_readme projects/vendor-review '# Vendor review\n\n- **Versioned:** untracked\n- **Sensitivity:** normal\n\n## Resources\n\n- archive — the signed contracts\n- contracts — the drafts\n- scans — scanned pages\n'
s16_readme projects/notes-lab '# Notes lab\n\n- **Versioned:** workspace\n'
git -C "$s16_P/projects/notes-lab" init -q
s16_readme projects/private-log '# Private log\n\n- **Versioned:** untracked\n- **Sensitivity:** sensitive\n'
printf 'projects/private-log/\n' >> "$s16_P/.gitignore"
s16_readme projects/_done/old-study '# Old study\n\n- **Versioned:** own-repo\n- **Sensitivity:** normal\n'
s16_readme projects/_delete/gone '# Gone\n\n- **Sensitivity:** sensitive\n'
s16_readme projects/_done/_skip '# Not a project\n\n- **Sensitivity:** sensitive\n'
git -C "$s16_P" add projects/field-study projects/vendor-review
mkdir -p "$s16_S/drive/recordings" "$s16_S/locked" "$s16_S/homedir/cloud/scans"
chmod 000 "$s16_S/locked"
printf '# Resources on this machine\n\nfield-study/media  %s\nfield-study/media  %s\nfield-study/survey-data\t%s\nvendor-review/archive  %s\nvendor-review/scans  ~/cloud/scans   \nnot a mapping line\n' \
    "$s16_S/drive/elsewhere" "$s16_S/drive/recordings" "$s16_S/drive/no-such" "$s16_S/locked" > "$s16_P/.claude/resources.local.md"
printf '{"permissions":{"allow":["Bash(ls)"],"additionalDirectories":["%s"]}}\n' "$s16_S/drive" > "$s16_P/.claude/settings.local.json"
r="$(HOME="$s16_S/homedir" st_run "$s16_P")"
st_expect "16 sensitivity and versioning across the active and done patterns, reserved folders skipped" "$r" \
    sensitive_projects=field-study,private-log sensitive_tracked=field-study \
    versioned_mismatch=notes-lab:workspace/nested,vendor-review:untracked/workspace,old-study:own-repo/workspace
st_expect "16 resources, full check: each state of §7.4" "$r" \
    "external_paths=field-study/media,field-study/exports,field-study/survey-data,vendor-review/archive,vendor-review/contracts,vendor-review/scans" \
    "resource.field-study/media=resolves granted" "resource.field-study/exports=resolves inside" \
    "resource.field-study/survey-data=missing absent" "resource.vendor-review/archive=no-permission unreadable" \
    "resource.vendor-review/contracts=missing unmapped" "resource.vendor-review/scans=resolves ungranted" \
    external_paths_missing=field-study/survey-data,vendor-review/archive resources_file=present
# --quick tests -e and -d only: the unreadable folder resolves, and no ls runs at all.
mkdir -p "$s16_S/lsbin"
printf '%s\n' '#!/bin/sh' "printf '%s\\n' \"\$*\" >> \"$s16_S/ls.log\"" 'exec /bin/ls "$@"' > "$s16_S/lsbin/ls"
chmod +x "$s16_S/lsbin/ls"
: > "$s16_S/ls.log"
rq="$(HOME="$s16_S/homedir" PATH="$s16_S/lsbin:$PATH" st_run "$s16_P" --quick)"
st_expect "16 resources, --quick: -e and -d only" "$rq" "resource.vendor-review/archive=resolves ungranted" \
    "resource.field-study/media=resolves granted" "resource.field-study/exports=resolves inside" \
    "resource.field-study/survey-data=missing absent" external_paths_missing=field-study/survey-data \
    sensitive_tracked=field-study quick=1
empty "16 --quick makes no ls call" "$(cat "$s16_S/ls.log")"
HOME="$s16_S/homedir" PATH="$s16_S/lsbin:$PATH" st_run "$s16_P" >/dev/null
grep -qF "$s16_S/drive/recordings" "$s16_S/ls.log" && ok "16 control: the full check does list a mapped folder" \
    || ko "16 control: the full check does list a mapped folder" "$(cat "$s16_S/ls.log")"
chmod 755 "$s16_S/locked"
s16_keys() { printf '%s\n' "$1" | sed 's/=.*//' | sed -e 's/^submodule\..*/submodule.*/' -e 's/^resource\..*/resource.*/' | sort -u | paste -sd' ' -; }
s16_quick_want="$(printf '%s\n' state_version target in_git hooks kit_hooks kit_path kit_submodule kit_commit kit_version \
    kit_branch kit_behind kit_import origin origin_visibility origin_confirmed submodules submodule_recurse 'submodule.*' \
    submodules_attention orphan_gitlinks sensitive_projects sensitive_tracked versioned_mismatch external_paths \
    external_paths_missing 'resource.*' skills_bridge plugins_loaded plugins_not_loaded quick | sort -u | paste -sd' ' -)"
[[ "$(s16_keys "$rq")" == "$s16_quick_want" ]] && ok "16 --quick emits exactly its key set" \
    || ko "16 --quick emits exactly its key set" "got:  $(s16_keys "$rq")"$'\n'"want: $s16_quick_want"
s16_bad=""
for s16_k in $(s16_keys "$r") $(s16_keys "$(st_run "$s16_U")"); do
    s16_k="${s16_k/submodule.\*/submodule.<path>}"; s16_k="${s16_k/resource.\*/resource.<slug>/<name>}"
    printf '%s\n' "$s16_hdr" | grep -qxF -- "$s16_k" || s16_bad+="$s16_k is emitted but not in the header's key list"$'\n'
done
empty "16 every key the full check emits is in the header's key list, so --explain covers it" "$s16_bad"

# ---- agents_md: opaque ------------------------------------------------------------------------------------
s16_A="$s16_S/agents"
s16_copy "$s16_W" "$s16_A"
printf '@kit/CLAUDE.kit.md\n\n# How this workspace is read\n' > "$s16_A/AGENTS.md"
st_expect "16 an AGENTS.md the ledger does not record is opaque" "$(AW_OPAQUE_PATHS="$s16_opq" st_run "$s16_A")" agents_md=opaque claude_md=kit always_loaded=CLAUDE.md
st_expect "16 AW_OPAQUE_PATHS set empty: nothing is opaque" "$(AW_OPAQUE_PATHS='' st_run "$s16_A")" agents_md=kit
chmod 000 "$s16_A/AGENTS.md"
st_expect "16 an unreadable, unrecorded AGENTS.md is opaque, and never opened" "$(AW_OPAQUE_PATHS="$s16_opq" st_run "$s16_A")" agents_md=opaque
chmod 644 "$s16_A/AGENTS.md"
printf 'AGENTS.md\ttemplates/workspace/AGENTS.md\t%s\t-\tcreated\n' "$(git -C "$KITSRC" rev-parse HEAD)" >> "$s16_A/.claude/kit-templates.lock"
st_expect "16 one the ledger records as created is read: agents_md=kit" "$(AW_OPAQUE_PATHS="$s16_opq" st_run "$s16_A")" agents_md=kit
printf '@AGENTS.md\n' > "$s16_A/CLAUDE.md"
st_expect "16 the 2.x shim CLAUDE.md is a legacy trace" "$(st_run "$s16_A")" claude_md=shim always_loaded=AGENTS.md legacy=agents_shim

# ---- The skills bridge's manifest -----------------------------------------------------------------------
s16_K="$s16_S/bridge"
s16_copy "$s16_W" "$s16_K"
mkdir -p "$s16_K/.claude/skills/kit-projects-new" "$s16_K/skills/daily-notes"
printf -- '---\nname: daily-notes\n---\n' > "$s16_K/skills/daily-notes/SKILL.md"
printf -- '---\nname: kit-projects-new\n---\n' > "$s16_K/.claude/skills/kit-projects-new/SKILL.md"
printf '# Written by kit/scripts/skills-bridge.sh.\n# origin\tfolder\tsource\nkit\tkit-projects-new\tplugins/projects/commands/new.md\nuser\tdaily-notes\tskills/daily-notes\nskip\tkit-closeout\tplugins/closeout/commands/closeout.md\n' \
    > "$s16_K/.claude/skills/.kit-generated"
st_expect "16 the bridge manifest: lines counted, a missing listed folder stale, bridged copies not own skills" "$(st_run "$s16_K")" \
    skills_bridge=present skills_bridge_count=3 skills_bridge_stale=1 own_skills=skills/daily-notes

# ---- plugins_loaded: the settings' enabledPlugins and the installed-plugins registry --------------------
# Each run names its own CLAUDE_CONFIG_DIR, so the runner's own Claude Code setup is never read.
s16_PL="$s16_S/plugins-loaded"
s16_copy "$s16_W" "$s16_PL"
s16_PLt="$(cd "$s16_PL" && pwd -P)"
s16_cfg="$s16_S/cc-config"
mkdir -p "$s16_cfg/plugins"
# s16_reg <json for .plugins>: the registry in the scratch config folder.
s16_reg() { printf '{"version":2,"plugins":%s}\n' "$1" > "$s16_cfg/plugins/installed_plugins.json"; }
s16_pl() { CLAUDE_CONFIG_DIR="$s16_cfg" st_run "$s16_PL" "$@"; }
# The registry checks run on settings without the workspace's directory marketplace (a kit reached
# through a marketplace added for the user); the directory marketplace has its own checks below.
s16_nomkt="$s16_S/settings-nomkt.json"
jq 'del(.extraKnownMarketplaces)' "$s16_W/.claude/settings.json" > "$s16_nomkt"
cp "$s16_nomkt" "$s16_PL/.claude/settings.json"
st_expect "16 plugins_loaded unknown with no registry to read, and nothing named" "$(s16_pl)" plugins_loaded=unknown plugins_not_loaded=
s16_reg '{"closeout@agentic-workspace":[{"scope":"user"}],"projects@agentic-workspace":[{"scope":"user"}],"workspace@agentic-workspace":[{"scope":"user"}]}'
st_expect "16 plugins_loaded yes when every kit plugin is enabled and installed for the user" "$(s16_pl)" plugins_loaded=yes plugins_not_loaded=
s16_reg '{"closeout@agentic-workspace":[{"scope":"project","projectPath":"'"$s16_PLt"'"}],"projects@agentic-workspace":[{"scope":"project","projectPath":"/elsewhere"}],"workspace@agentic-workspace":[{"scope":"user"}],"projects@another-market":[{"scope":"user"}]}'
st_expect "16 a project-scope install counts for its own repository only; another marketplace's is not the kit's" "$(s16_pl --quick)" \
    plugins_loaded=no plugins_not_loaded=projects:not-installed
printf '{"enabledPlugins":{"projects@agentic-workspace":false}}\n' > "$s16_PL/.claude/settings.local.json"
jq 'del(.enabledPlugins["closeout@agentic-workspace"])' "$s16_nomkt" > "$s16_PL/.claude/settings.json"
st_expect "16 settings.local.json wins over settings.json, and a plugin no settings file names is not enabled" "$(s16_pl)" \
    plugins_loaded=no plugins_not_loaded=closeout:not-enabled,projects:disabled
printf '{"enabledPlugins":{"closeout@agentic-workspace":true}}\n' > "$s16_cfg/settings.json"
st_expect "16 the user's settings.json enables what the workspace's leaves out" "$(s16_pl)" plugins_loaded=no plugins_not_loaded=projects:disabled
printf '{"enabledPlugins":{"closeout@agentic-workspace":false}}\n' > "$s16_cfg/settings.json"
st_expect "16 the user's settings.json disables it" "$(s16_pl)" plugins_not_loaded=closeout:disabled,projects:disabled
st_expect "16 a plugin whose hook runs the check (CLAUDE_PLUGIN_ROOT) is loaded" \
    "$(CLAUDE_PLUGIN_ROOT="$s16_PL/kit/plugins/closeout" s16_pl)" plugins_not_loaded=projects:disabled
printf 'not json\n' > "$s16_cfg/plugins/installed_plugins.json"
cp "$s16_nomkt" "$s16_PL/.claude/settings.json"
printf '{}\n' > "$s16_PL/.claude/settings.local.json"; printf '{}\n' > "$s16_cfg/settings.json"
st_expect "16 a registry that does not parse reads unknown" "$(s16_pl)" plugins_loaded=unknown plugins_not_loaded=
# The 3.0 layout: the workspace's settings register kit/ as a directory marketplace, and Claude Code loads
# the enabled plugins from it without writing them to the registry (seen with a fresh CLAUDE_CONFIG_DIR).
cp "$s16_W/.claude/settings.json" "$s16_PL/.claude/settings.json"
s16_reg '{}'
st_expect "16 a directory marketplace at kit/ in the workspace's settings serves its enabled plugins, with an empty registry" \
    "$(s16_pl)" plugins_loaded=yes plugins_not_loaded=
st_expect "16 ... and --quick agrees" "$(s16_pl --quick)" plugins_loaded=yes plugins_not_loaded=
jq '.extraKnownMarketplaces["agentic-workspace"].source.path = "no-such-kit"' "$s16_W/.claude/settings.json" > "$s16_PL/.claude/settings.json"
st_expect "16 a directory marketplace whose folder does not exist serves nothing" "$(s16_pl)" \
    plugins_loaded=no plugins_not_loaded=closeout:not-installed,projects:not-installed,workspace:not-installed
cp "$s16_nomkt" "$s16_PL/.claude/settings.json"
st_expect "16 no kit checkout: unknown" "$(CLAUDE_CONFIG_DIR="$s16_cfg" st_run "$s16_S/plain")" plugins_loaded=unknown

# ---- A 2.2.0 workspace ------------------------------------------------------------------------------------
s16_X="$s16_S/two-x"
mkws2x "$s16_X"; s16_rc=$?
if [[ $s16_rc -eq 0 ]]; then
    st_expect "16 a 2.2.0 workspace: legacy traces, no kit at kit/" "$(AW_OPAQUE_PATHS="$s16_opq" st_run "$s16_X")" kit_path=none kit_submodule=none \
        plugins_mode=vendor agents_md=opaque claude_md=shim kit_import=missing \
        legacy=vendored,kit_not_at_kit,generated_skills_in_skills,agents_shim
else
    skp "16 a 2.2.0 workspace: mkws2x returned $s16_rc (915c528 not in this clone)"
fi

# ---- No lock and no write, full and --quick ---------------------------------------------------------------
s16_L="$s16_S/lock"
cp -R "$s16_U" "$s16_L"
printf 'more\n' >> "$s16_L/projects/site/draft.md"
printf '| Term | A meaning |\n' >> "$s16_L/CLAUDE.md"
git -C "$s16_L" add CLAUDE.md
for s16_f in CLAUDE.md .claude/projects.md projects/site/README.md kit/README.md; do age "$s16_L/$s16_f" 2; done
st_tree "$s16_L" > "$s16_S/lock-before.txt"
st_run "$s16_L" --quick >/dev/null; st_run "$s16_L" >/dev/null
st_tree "$s16_L" > "$s16_S/lock-after.txt"
empty "16 no lock and no write: nothing under the workspace, submodule git dirs included, changes" \
    "$(diff "$s16_S/lock-before.txt" "$s16_S/lock-after.txt" 2>&1)"
git -C "$s16_L" status --porcelain >/dev/null 2>&1
[[ "$(st_tree "$s16_L" | grep '^\.git/index ')" != "$(grep '^\.git/index ' "$s16_S/lock-before.txt")" ]] \
    && ok "16 control: a plain git status rewrites that index" || ko "16 control: a plain git status rewrites that index"

# ---- --quick's cost is structural ---------------------------------------------------------------------------
# s16_many <dir> <n>: the workspace with n project folders, half of them sensitive, each naming a resource.
s16_many() {
    local d="$1" i=1
    s16_copy "$s16_W" "$d"
    while [[ $i -le $2 ]]; do
        mkdir -p "$d/projects/study-$i"
        if [[ $((i % 2)) -eq 0 ]]; then s16_s=sensitive; else s16_s=normal; fi
        printf '# Study %s\n\n- **Versioned:** workspace\n- **Sensitivity:** %s\n\n## Resources\n\n- media — recordings\n' "$i" "$s16_s" \
            > "$d/projects/study-$i/README.md"
        i=$((i + 1))
    done
    git -C "$d" add projects
}
s16_many "$s16_S/cost-5" 5; s16_many "$s16_S/cost-50" 50
gitcount_run "$s16_S/git-5.log" "$st_bash" "$STATE" --quick "$s16_S/cost-5" >"$s16_S/cost-5.out" 2>/dev/null
gitcount_run "$s16_S/git-50.log" "$st_bash" "$STATE" --quick "$s16_S/cost-50" >"$s16_S/cost-50.out" 2>/dev/null
s16_c5="$(aw_count <"$s16_S/git-5.log")" s16_c50="$(aw_count <"$s16_S/git-50.log")"
[[ "$(st_key "$(cat "$s16_S/cost-50.out")" sensitive_tracked | tr ',' '\n' | aw_count)" == 25 && $s16_c5 -gt 0 && $s16_c50 -le $((s16_c5 + 2)) ]] \
    && ok "16 --quick's git calls do not grow with the projects ($s16_c5 on 5, $s16_c50 on 50)" \
    || ko "16 --quick's git calls do not grow with the projects ($s16_c5 on 5, $s16_c50 on 50)" "$(sort "$s16_S/git-50.log" | uniq -c | sort -rn | head)"
s16_t="$(python3 - "$st_bash" "$STATE" "$s16_S/cost-5" "$s16_S/cost-50" <<'PYT'
import subprocess, sys, time
out = []
for d in sys.argv[3:]:
    t = time.time()
    subprocess.run([sys.argv[1], sys.argv[2], "--quick", d], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out.append("%.2fs" % (time.time() - t))
print(" and ".join(out))
PYT
)"
echo "      (for information: --quick took $s16_t on 5 and 50 projects)"

# ---- The session-start summary ----------------------------------------------------------------------------
s16_hook_err=""
empty "16 hook: a workspace in step prints nothing" "$(s16_hookrun "$s16_W")"
# A project submodule that is not initialised (a clone made without --recurse-submodules) has no git
# dir to hold hooks, and kit/setup.sh hooks passes over it, so the hooks line does not count it.
s16_Q="$s16_S/hook-uninit"
s16_copy "$s16_W" "$s16_Q"
git -C "$s16_Q" update-index --add --cacheinfo "160000,$(git -C "$s16_W" rev-parse HEAD),projects/archive-tool"
git -C "$s16_Q" config -f .gitmodules submodule.projects/archive-tool.path projects/archive-tool
git -C "$s16_Q" config -f .gitmodules submodule.projects/archive-tool.url https://example.invalid/archive-tool.git
s16_commit "$s16_Q" "An uninitialised project submodule"
s16_v="$(st_key "$(st_run "$s16_Q")" submodule.projects/archive-tool)"
s16_o="$(s16_hookrun "$s16_Q" | s16_msg)"
[[ "$s16_v" == *"pointer=uninitialized"* && "$s16_v" == *"hooks=missing"* && "$s16_o" != *"git hooks are not active"* ]] \
    && ok "16 hook: an uninitialised project submodule (hooks=missing) does not make the hooks line appear" \
    || ko "16 hook: an uninitialised project submodule (hooks=missing) does not make the hooks line appear" "$s16_v"$'\n'"$s16_o"
s16_Z="$s16_S/hook-lines"
cp -R "$s16_U" "$s16_Z"
git -C "$s16_Z" config --unset core.hooksPath
sed '1,2d' "$s16_W/CLAUDE.md" > "$s16_Z/CLAUDE.md"
git -C "$s16_Z" config submodule.kit.update rebase
git -C "$s16_Z/kit" -c protocol.file.allow=always fetch -q "$s16_KU" main:refs/remotes/origin/main 2>/dev/null
git -C "$s16_Z/kit" checkout -q --detach
printf 'stray\n' > "$s16_Z/kit/stray-notes.md"
printf 'second\n' > "$s16_Z/projects/site/second.md" && s16_commit "$s16_Z/projects/site" "Second"
git -C "$s16_Z" update-index --add --cacheinfo "160000,$(git -C "$s16_W" rev-parse HEAD),projects/archive-tool"
mkdir -p "$s16_Z/projects/field-study"
printf '# Field study\n\n- **Versioned:** workspace\n- **Sensitivity:** sensitive\n\n## Resources\n\n- media — recordings\n- survey-data — the extract\n' \
    > "$s16_Z/projects/field-study/README.md"
printf 'field-study/media  %s\nfield-study/survey-data  %s\n' "$s16_S/drive/gone-1" "$s16_S/drive/gone-2" > "$s16_Z/.claude/resources.local.md"
git -C "$s16_Z" add projects/field-study
git -C "$s16_Z" remote add origin "https://github.com/example-org/field-notes.git"
s16_want="Workspace: git hooks are not active — kit/setup.sh hooks turns them on.
Workspace: CLAUDE.md does not import the kit's standards — its first line is @kit/CLAUDE.kit.md.
Workspace: kit/ is detached from main (developer mode) — kit/setup.sh --developer puts it back.
Workspace: kit: 1 changed file; site: 2 commits not pushed, pointer changed, not committed, 1 commit behind its remote.
Workspace: 1 gitlink has no .gitmodules entry (projects/archive-tool) — kit/setup.sh migrate --dry-run names the two fixes.
Workspace: 2 resources not reachable on this machine (field-study/media, field-study/survey-data) — kit/setup.sh link.
Workspace: 1 sensitive project has files tracked by the workspace (field-study) — /projects:adopt field-study untracked.
Workspace: origin is not confirmed private — kit/setup.sh records it once confirmed.
Workspace: the kit is 1 commit behind its remote — kit/setup.sh update."
s16_o="$(s16_hookrun "$s16_Z")"
[[ "$(printf '%s' "$s16_o" | s16_msg)" == "$s16_want" ]] && ok "16 hook: one line per thing out of step, in order, each naming its fix" \
    || ko "16 hook: one line per thing out of step, in order, each naming its fix" "$(printf '%s' "$s16_o" | s16_msg)"
printf '%s' "$s16_o" | jq -e --arg w "$s16_want" '.hookSpecificOutput.hookEventName == "SessionStart"
    and (.hookSpecificOutput.additionalContext | contains($w))' >/dev/null 2>&1 \
    && ok "16 hook: the same lines go to the agent as additionalContext" || ko "16 hook: the same lines go to the agent as additionalContext" "$s16_o"
s16_bad=""
[[ "$(s16_hookrun "$s16_Z/kit/plugins")" == "$s16_o" ]] || s16_bad+="from inside kit/ the output differs"$'\n'
[[ "$(s16_hookrun "$s16_Z/projects/site")" == "$s16_o" ]] || s16_bad+="from inside the own-repo project the output differs"$'\n'
empty "16 hook: from inside kit/ and inside an own-repo project it reports on the workspace around them" "$s16_bad"
mkdir -p "$s16_S/unrelated" && git -C "$s16_S/unrelated" init -q
s16_bad=""
[[ -z "$(s16_hookrun "$s16_S/unrelated")" ]] || s16_bad+="an unrelated repository got output"$'\n'
[[ -z "$(s16_hookrun "$s16_S/plain")" ]] || s16_bad+="a plain folder got output"$'\n'
[[ -z "$(s16_hookrun "$s16_Z" WORKSPACE_HOOK_DISABLED=1)" ]] || s16_bad+="WORKSPACE_HOOK_DISABLED=1 got output"$'\n'
[[ -z "$(s16_hookrun "$s16_Z" AW_HEADLESS_RUN=1)" ]] || s16_bad+="AW_HEADLESS_RUN=1 got output"$'\n'
[[ -z "$(s16_hookrun "$s16_Z" CLOSEOUT_HOOK_CHILD=1)" ]] || s16_bad+="CLOSEOUT_HOOK_CHILD got output"$'\n'
# Without jq: a PATH of the tools the hook and state.sh call, jq left out. The same folder with jq
# added does report, so it is jq's absence that silences the hook.
s16_tools=(bash cat dirname basename git awk grep sed tr ls find date sort head wc stat paste cut timeout)
mkpath "$s16_S/path-nojq" "${s16_tools[@]}"
mkpath "$s16_S/path-jq" "${s16_tools[@]}" jq
PATH="$s16_S/path-nojq" command -v jq >/dev/null 2>&1 && s16_bad+="jq is still found on the PATH meant to hide it"$'\n'
[[ -z "$(s16_hookrun "$s16_Z" PATH="$s16_S/path-nojq")" ]] || s16_bad+="with no jq on PATH it got output"$'\n'
[[ -n "$(s16_hookrun "$s16_Z" PATH="$s16_S/path-jq")" ]] || s16_bad+="with the same PATH and jq it got no output"$'\n'
[[ -z "$(s16_hookrun "$s16_S/no-such-folder")" ]] || s16_bad+="a missing folder got output"$'\n'
empty "16 hook: silent in an unrelated repository, a plain folder, when disabled, headless, as closeout's child, and without jq" "$s16_bad"
printf 'x\n' > "$s16_C/.claude/kit-templates.lock"
s16_o="$(s16_hookrun "$s16_C" | s16_msg)"
[[ "$s16_o" == *"Workspace: the kit is not initialised here — git submodule update --init kit."* \
   && "$s16_o" == *"origin is not confirmed private"* && "$s16_o" != *"does not import"* ]] \
    && ok "16 hook: a clone with the kit not initialised is found by its ledger and told to initialise it" \
    || ko "16 hook: a clone with the kit not initialised is found by its ledger and told to initialise it" "$s16_o"
s16_D="$s16_S/hook-two-sites"
cp -R "$s16_U" "$s16_D"
git -C "$s16_D" -c protocol.file.allow=always submodule add -q -b main "$s16_S/up-site" projects/_done/site >/dev/null 2>&1
printf 'x\n' > "$s16_D/projects/_done/site/x.md"
s16_o="$(s16_hookrun "$s16_D" | s16_msg)"
[[ "$s16_o" == *"Workspace: projects/site: "* && "$s16_o" == *"; projects/_done/site: 1 changed file"* ]] \
    && ok "16 hook: two submodules with the same last name are named by their paths" \
    || ko "16 hook: two submodules with the same last name are named by their paths" "$s16_o"
# A kit plugin not loaded beside the bridge's kit-* skills: one line naming it and the fix. A plugin set
# false is a choice, and the plugin whose hook is running (CLAUDE_PLUGIN_ROOT) is loaded.
s16_reg '{"workspace@agentic-workspace":[{"scope":"user"}],"closeout@agentic-workspace":[{"scope":"user"}]}'
s16_hb() { s16_hookrun "$s16_PL" CLAUDE_CONFIG_DIR="$s16_cfg" "$@" | s16_msg; }
s16_bad=""
[[ -z "$(s16_hb)" ]] || s16_bad+="with no bridge manifest: $(s16_hb)"$'\n'
mkdir -p "$s16_PL/.claude/skills"
printf '# Written by kit/scripts/skills-bridge.sh.\nkit\tkit-projects-board\tplugins/projects/commands/board.md\n' > "$s16_PL/.claude/skills/.kit-generated"
s16_o="$(s16_hb)"
[[ "$s16_o" == "Workspace: the kit's projects plugin is not loaded, so its kit-* skills stand in for it — claude plugin install projects@agentic-workspace, or /plugin." ]] \
    || s16_bad+="one plugin missing: $s16_o"$'\n'
s16_reg '{}'
s16_o="$(s16_hb CLAUDE_PLUGIN_ROOT="$s16_PL/kit/plugins/workspace")"
[[ "$s16_o" == "Workspace: the kit's plugins closeout, projects are not loaded, so their kit-* skills stand in for them — claude plugin install <name>@agentic-workspace for each, or /plugin." ]] \
    || s16_bad+="two missing, the hook's own plugin loaded: $s16_o"$'\n'
printf '{"enabledPlugins":{"closeout@agentic-workspace":false,"projects@agentic-workspace":false}}\n' > "$s16_PL/.claude/settings.local.json"
[[ -z "$(s16_hb CLAUDE_PLUGIN_ROOT="$s16_PL/kit/plugins/workspace")" ]] || s16_bad+="plugins set false got a line: $(s16_hb CLAUDE_PLUGIN_ROOT="$s16_PL/kit/plugins/workspace")"$'\n'
empty "16 hook: a kit plugin not loaded while bridge skills exist gets one line with the fix; none without the bridge, or for a plugin set false" "$s16_bad"
empty "16 hook: exit 0 and nothing on stderr in every run above" "$s16_hook_err"
empty "16 state.sh: silent on stderr in every run above" "$st_err"

fi
fi
