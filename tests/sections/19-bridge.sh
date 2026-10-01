# shellcheck shell=bash disable=SC2015,SC2016,SC2154
# SC2154: st_bash, kitsrc_ok and the rest come from the prelude in tests/run.sh. SC2016: the backticks in
# single quotes are literal markdown. SC2015: ok and ko always return 0, so A && ok || ko is safe.
# Section 19: the skills bridge, kit/scripts/skills-bridge.sh (contract §8). Sourced by tests/run.sh after
# section 11, into the runner's shell: every name here starts with s19_, and everything is written under
# $SCRATCH. The fixtures are mkws_min workspaces with a few skills of their own in skills/, one of them a
# submodule with an executable script, as a skill that ships its own command-line tool would be.
echo
echo "19 · The skills bridge: the kit's skills and the workspace's own, in .claude/skills/"

# s19_run <ws> [args...]: the bridge from the workspace's own kit checkout, under the kit's bash floor.
# Sets s19_rc and s19_out.
s19_run() {
    local ws="$1"; shift
    s19_out="$("$st_bash" "$ws/kit/scripts/skills-bridge.sh" --target "$ws" "$@" </dev/null 2>&1)"; s19_rc=$?
}
# s19_has <line pattern>: the bridge's last output has a line matching the extended regex.
s19_has() { printf '%s\n' "$s19_out" | grep -qE "$1"; }
# s19_skill <dir> <name> <text>: a minimal skill.
s19_skill() { mkdir -p "$1" && printf -- '---\nname: %s\ndescription: "%s"\n---\n\n%s\n' "$2" "$3" "$3" > "$1/SKILL.md"; }
# s19_mk <ws>: a mkws_min workspace with its own skills: daily-notes (an executable script, a link to a
# file elsewhere in the workspace, and a .claude folder of its own), field-tool (a submodule), a
# dot-folder, a folder with no SKILL.md, and kit-mine (a name in the kit's prefix).
s19_mk() {
    local ws="$1"
    mkws_min "$ws" || return 1
    s19_skill "$ws/skills/daily-notes" daily-notes "Keeps the daily notes. Offer it at the start of a day."
    mkdir -p "$ws/skills/daily-notes/bin" "$ws/skills/daily-notes/.claude" "$ws/docs"
    printf '#!/bin/sh\necho notes\n' > "$ws/skills/daily-notes/bin/run.sh" && chmod 755 "$ws/skills/daily-notes/bin/run.sh"
    printf '{}\n' > "$ws/skills/daily-notes/.claude/settings.local.json"
    printf 'The shared note format.\n' > "$ws/docs/note-format.md"
    ln -s ../../docs/note-format.md "$ws/skills/daily-notes/format.md"
    git -C "$ws" -c protocol.file.allow=always submodule add -q "$s19_tool" skills/field-tool >/dev/null 2>&1 || return 1
    s19_skill "$ws/skills/.drafts" drafts "Not a skill to bridge."
    mkdir -p "$ws/skills/notes-only" && printf 'Notes, not a skill.\n' > "$ws/skills/notes-only/README.md"
    s19_skill "$ws/skills/kit-mine" kit-mine "A skill in the kit's prefix."
}

s19_gen=1
grep -q -- '--skills-prefix' "$KIT/install.sh" 2>/dev/null || s19_gen=0
s19_ncmd=0
for s19_f in "$KIT"/plugins/*/commands/*.md; do [[ -f "$s19_f" ]] && s19_ncmd=$((s19_ncmd + 1)); done

# The field-tool skill's own repository, added to each fixture as a submodule.
s19_tool="$SCRATCH/s19-field-tool"
mkdir -p "$s19_tool/bin" && git -C "$s19_tool" init -q && git -C "$s19_tool" symbolic-ref HEAD refs/heads/main
s19_skill "$s19_tool" field-tool "Runs the field-study tool. Offer it when a field study needs its data pulled."
printf '#!/bin/sh\necho field\n' > "$s19_tool/bin/field-tool" && chmod 755 "$s19_tool/bin/field-tool"
git -C "$s19_tool" add -A && git -C "$s19_tool" -c commit.gpgsign=false commit -q -m "field-tool"

s19_w1="$SCRATCH/s19-ws1"
if [[ $kitsrc_ok -ne 1 ]]; then
    skp "19 the skills bridge — no KITSRC (the kit is not a git checkout)"
elif ! s19_mk "$s19_w1"; then
    ko "19 the fixture workspace builds (mkws_min and a submodule skill)"
else

# Refusals come before any generation, so they hold whatever the engine's state.
s19_run "$s19_w1" --bogus
[[ $s19_rc -eq 2 ]] && ok "19 an unknown option is a usage error (exit 2)" || ko "19 an unknown option is a usage error (exit 2)" "rc $s19_rc: $s19_out"
s19_bad=""
for s19_t in "$s19_w1/kit" "$s19_w1/kit/plugins"; do
    s19_o="$("$st_bash" "$s19_w1/kit/scripts/skills-bridge.sh" --target "$s19_t" 2>&1)"; s19_r=$?
    [[ $s19_r -eq 2 ]] || s19_bad+="${s19_t#"$SCRATCH"/}: rc $s19_r $s19_o"$'\n'
done
# The same refusal from a kit checkout outside the workspace: the target's repository is itself a kit.
s19_o="$("$st_bash" "$KIT/scripts/skills-bridge.sh" --target "$s19_w1/kit" 2>&1)"; s19_r=$?
[[ $s19_r -eq 2 ]] || s19_bad+="another checkout's bridge on kit/: rc $s19_r $s19_o"$'\n'
[[ -e "$s19_w1/kit/.claude" ]] && s19_bad+="kit/.claude was written"$'\n'
empty "19 a target inside the kit checkout is refused (exit 2), and nothing is written there" "$s19_bad"
mkdir -p "$SCRATCH/s19-plain" && git -C "$SCRATCH/s19-plain" init -q
s19_out="$("$st_bash" "$s19_w1/kit/scripts/skills-bridge.sh" --target "$SCRATCH/s19-plain" 2>&1)"; s19_rc=$?
[[ $s19_rc -eq 2 && ! -e "$SCRATCH/s19-plain/.claude" ]] && ok "19 a folder with no kit checkout is not a workspace (exit 2)" \
    || ko "19 a folder with no kit checkout is not a workspace (exit 2)" "rc $s19_rc: $s19_out"

if [[ $s19_gen -eq 0 ]]; then
    skp "19 the bridge's runs — kit/install.sh has no --skills-prefix yet (the engine, C2, not built in this tree)"
else

s19_sk="$s19_w1/.claude/skills"
# --check on a workspace the bridge has never run in: something to write, and nothing written.
s19_run "$s19_w1" --check
[[ $s19_rc -eq 1 && ! -e "$s19_sk" ]] && ok "19 --check before a first run exits 1 and writes nothing" \
    || ko "19 --check before a first run exits 1 and writes nothing" "rc $s19_rc: $s19_out"

s19_run "$s19_w1"
[[ $s19_rc -eq 0 ]] && ok "19 a first run exits 0" || ko "19 a first run exits 0" "$s19_out"

# The kit's skills: one kit-* folder per kit command, each with SKILL.md and procedure.md, in the manifest.
s19_bad="" s19_n=0
for s19_d in "$s19_sk"/kit-*; do
    [[ -d "$s19_d" ]] || continue
    s19_n=$((s19_n + 1))
    [[ -f "$s19_d/SKILL.md" && -f "$s19_d/procedure.md" ]] || s19_bad+="${s19_d##*/}: SKILL.md or procedure.md missing"$'\n'
done
[[ $s19_n -eq $s19_ncmd ]] || s19_bad+="$s19_n kit-* folders for $s19_ncmd commands"$'\n'
[[ $s19_n -gt 0 ]] || s19_bad+="no kit-* folder"$'\n'
empty "19 one kit-* skill per kit command ($s19_ncmd), each with SKILL.md and procedure.md" "$s19_bad"
if [[ $s19_ncmd -eq 10 && $s19_n -eq 10 ]]; then ok "19 ten kit-* skills are written"
else skp "19 ten kit-* skills are written — the kit has $s19_ncmd commands (/projects:hold arrives with the projects component)"; fi

s19_man="$s19_sk/.kit-generated"
s19_bad=""
[[ -f "$s19_man" ]] || s19_bad+="no .claude/skills/.kit-generated"$'\n'
head -n 1 "$s19_man" 2>/dev/null | grep -q '^# Written by kit/scripts/skills-bridge.sh' || s19_bad+="the manifest's first line is not the header"$'\n'
[[ "$(awk -F '\t' '$1 == "kit"' "$s19_man" 2>/dev/null | aw_count)" -eq $s19_n ]] || s19_bad+="kit lines differ from the kit-* folders"$'\n'
s19_bad+="$(awk -F '\t' '$1 == "kit" && $3 !~ /^plugins\/[^\/]+\/commands\/[^\/]+\.md$/ { print "source of " $2 ": " $3 }' "$s19_man" 2>/dev/null)"
[[ "$(awk -F '\t' '$1 == "user" { print $2 "=" $3 }' "$s19_man" 2>/dev/null | paste -sd' ' -)" == "daily-notes=skills/daily-notes field-tool=skills/field-tool" ]] \
    || s19_bad+="user lines: $(awk -F '\t' '$1 == "user"' "$s19_man" 2>/dev/null | paste -sd' ' -)"$'\n'
empty "19 the manifest lists every folder written: origin, folder and source, tab-separated" "$s19_bad"

# The workspace's own skills: real folders, links followed, .git and .claude taken out, modes kept, names
# as they are.
s19_bad=""
for s19_n in daily-notes field-tool; do
    [[ -d "$s19_sk/$s19_n" && ! -L "$s19_sk/$s19_n" ]] || s19_bad+="$s19_n: not a real folder"$'\n'
    [[ -e "$s19_sk/kit-$s19_n" ]] && s19_bad+="$s19_n: prefixed"$'\n'
done
[[ -x "$s19_sk/daily-notes/bin/run.sh" ]] || s19_bad+="daily-notes/bin/run.sh lost its executable bit"$'\n'
[[ -x "$s19_sk/field-tool/bin/field-tool" ]] || s19_bad+="field-tool/bin/field-tool lost its executable bit"$'\n'
[[ -f "$s19_sk/daily-notes/format.md" && ! -L "$s19_sk/daily-notes/format.md" ]] \
    && grep -q 'shared note format' "$s19_sk/daily-notes/format.md" || s19_bad+="daily-notes/format.md is not the linked file's content"$'\n'
s19_bad+="$(find "$s19_sk" \( -name .git -o -name .claude -o -type l \) 2>/dev/null)"
empty "19 user skills are copied as real folders without .git or .claude, a submodule skill included, executables kept, names unprefixed" "$s19_bad"

s19_bad=""
for s19_n in .drafts drafts notes-only; do [[ -e "$s19_sk/$s19_n" ]] && s19_bad+="$s19_n was copied"$'\n'; done
empty "19 a dot-folder and a folder with no SKILL.md are not copied" "$s19_bad"

[[ ! -e "$s19_sk/kit-mine" ]] && s19_has '^  clash   kit-mine  — ' \
    && ok "19 a user skill in the kit- prefix is reported as a clash and not copied" \
    || ko "19 a user skill in the kit- prefix is reported as a clash and not copied" "$s19_out"

# The generated skills themselves: section 9's format check, and the sibling sentence in kit- forms.
s19_bad=""
for s19_d in "$s19_sk"/kit-*; do
    [[ -f "$s19_d/SKILL.md" ]] || continue
    if declare -F skill_ok >/dev/null; then
        s19_e="$(skill_ok "$s19_d/SKILL.md" 2>&1)" || s19_bad+="${s19_d##*/}: $(printf '%s' "$s19_e" | tail -n 1)"$'\n'
    fi
    grep -qF '`kit-projects-new`' "$s19_d/SKILL.md" || s19_bad+="${s19_d##*/}: the sibling sentence has no kit-projects-new"$'\n'
    grep -qF '(`projects-new`' "$s19_d/SKILL.md" && s19_bad+="${s19_d##*/}: the sibling sentence names unprefixed skills"$'\n'
done
grep -qF '`kit/plugins/projects/commands/new.md`' "$s19_sk/kit-projects-new/SKILL.md" 2>/dev/null \
    || s19_bad+="kit-projects-new does not point at kit/plugins/projects/commands/new.md"$'\n'
if declare -F skill_ok >/dev/null; then
    empty "19 each kit-* skill passes section 9's skill_ok, points into kit/, and names its siblings in kit- forms" "$s19_bad"
else
    empty "19 each kit-* skill points into kit/ and names its siblings in kit- forms" "$s19_bad"
    skp "19 each kit-* skill passes section 9's skill_ok — skill_ok is defined in section 9 (run with AW_SECTIONS=\"9 19\")"
fi

# In Claude Code the plugin's command is the way in: each kit-* skill names its surface test, hands over
# to the plugin command when it is available, and otherwise names the plugin and the command that loads it.
s19_bad=""
while IFS=$'\t' read -r s19_o s19_n s19_src; do
    [[ "$s19_o" == kit && -f "$s19_sk/$s19_n/SKILL.md" ]] || continue
    s19_p="${s19_src#plugins/}"; s19_p="${s19_p%%/*}"; s19_c="$(basename "$s19_src" .md)"
    s19_t="/$s19_p:$s19_c"; [[ "$s19_p" == "$s19_c" ]] && s19_t="/$s19_c"
    s19_flat="$(tr '\n' ' ' < "$s19_sk/$s19_n/SKILL.md")"
    for s19_w in '`CLAUDECODE=1`' "\`$s19_p:$s19_c\` is among the commands or skills available to you" \
        "type \`$s19_t\`, and go no further here" "the $s19_p plugin is not loaded" \
        "\`claude plugin install $s19_p@agentic-workspace\`, or \`/plugin\`" 'then carry on here'; do
        [[ "$s19_flat" == *"$s19_w"* ]] || s19_bad+="$s19_n: no $s19_w"$'\n'
    done
done < "$s19_man"
empty "19 each kit-* skill hands over to its plugin command in Claude Code, and names the plugin and its fix when that is not loaded" "$s19_bad"

# With the bridge's skills there and a kit plugin Claude Code would not load, the state check says so and
# the workspace session-start summary names the plugin and the fix. A scratch config folder stands in for
# the person's own.
s19_cfg="$SCRATCH/s19-cc-config"
mkdir -p "$s19_cfg/plugins"
printf '{"version":2,"plugins":{"closeout@agentic-workspace":[{"scope":"user"}],"workspace@agentic-workspace":[{"scope":"user"}]}}\n' \
    > "$s19_cfg/plugins/installed_plugins.json"
s19_st="$(CLAUDE_CONFIG_DIR="$s19_cfg" "$st_bash" "$s19_w1/kit/plugins/workspace/bin/state.sh" --quick "$s19_w1" 2>&1)"
s19_hk="$(printf '{"cwd":"%s"}' "$s19_w1" | CLAUDE_CONFIG_DIR="$s19_cfg" "$st_bash" "$s19_w1/kit/plugins/workspace/hooks/session-start.sh" 2>&1 \
    | jq -r '.systemMessage // empty' 2>/dev/null)"
[[ "$s19_st" == *$'\nskills_bridge=present\n'* && "$s19_st" == *$'\nplugins_loaded=no\n'* \
   && "$s19_st" == *$'\nplugins_not_loaded=projects:not-installed\n'* \
   && "$s19_hk" == *"the kit's projects plugin is not loaded, so its kit-* skills stand in for it — claude plugin install projects@agentic-workspace, or /plugin."* ]] \
    && ok "19 a kit plugin not loaded beside the bridge: state.sh --quick names it, and the session-start summary gives the fix" \
    || ko "19 a kit plugin not loaded beside the bridge: state.sh --quick names it, and the session-start summary gives the fix" "$s19_st"$'\n'"$s19_hk"

# A second run changes nothing, and --check agrees.
s19_before="$(st_tree "$s19_w1")"
s19_run "$s19_w1"
s19_r1=$s19_rc s19_o1="$s19_out"
s19_run "$s19_w1" --check
if [[ $s19_r1 -eq 0 && $s19_rc -eq 0 && "$(st_tree "$s19_w1")" == "$s19_before" ]] \
    && ! printf '%s\n' "$s19_o1" | grep -qE '  (written|copied)'; then
    ok "19 a second run reports everything current and changes nothing, and --check exits 0"
else ko "19 a second run reports everything current and changes nothing, and --check exits 0" "rc $s19_r1/$s19_rc: $s19_o1"; fi

# A folder already in .claude/skills/ that the manifest does not list is a clash: never overwritten.
s19_skill "$s19_sk/team-own" team-own "Written by hand."
s19_skill "$s19_w1/skills/team-own" team-own "From skills/."
s19_run "$s19_w1"
[[ $s19_rc -eq 0 ]] && s19_has '^  clash   team-own  — ' && grep -q 'Written by hand' "$s19_sk/team-own/SKILL.md" \
    && ! awk -F '\t' '$2 == "team-own"' "$s19_man" | grep -q . \
    && ok "19 a folder there already and not listed is reported as a clash, left as it is and not listed" \
    || ko "19 a folder there already and not listed is reported as a clash, left as it is and not listed" "rc $s19_rc: $s19_out"

# A changed user skill: --check exits 1 and writes nothing; --dry-run says what it would copy; a run
# copies it.
printf 'A line added later.\n' >> "$s19_w1/skills/daily-notes/SKILL.md"
s19_before="$(st_tree "$s19_w1")"
s19_run "$s19_w1" --check
s19_r1=$s19_rc
s19_run "$s19_w1" --dry-run
if [[ $s19_r1 -eq 1 && $s19_rc -eq 0 && "$(st_tree "$s19_w1")" == "$s19_before" ]] && s19_has '^Dry run' \
    && s19_has '^  user    daily-notes  copied$'; then
    ok "19 --check exits 1 on a change and --dry-run names it, neither writing anything"
else ko "19 --check exits 1 on a change and --dry-run names it, neither writing anything" "check rc $s19_r1, dry-run rc $s19_rc: $s19_out"; fi
s19_run "$s19_w1"
grep -q 'A line added later' "$s19_sk/daily-notes/SKILL.md" && s19_has '^  user    daily-notes  copied$' \
    && ok "19 a changed user skill is copied again" || ko "19 a changed user skill is copied again" "$s19_out"

# --no-user leaves the workspace's own copies, and their manifest lines, as they are.
printf 'A second line added later.\n' >> "$s19_w1/skills/daily-notes/SKILL.md"
s19_run "$s19_w1" --no-user
[[ $s19_rc -eq 0 ]] && ! grep -q 'A second line' "$s19_sk/daily-notes/SKILL.md" \
    && awk -F '\t' '$1 == "user" && $2 == "daily-notes"' "$s19_man" | grep -q . && ! s19_has '^  (user|removed) ' \
    && ok "19 --no-user writes only the kit's skills and keeps the listed user copies" \
    || ko "19 --no-user writes only the kit's skills and keeps the listed user copies" "rc $s19_rc: $s19_out"

# The skip list: skip lines, no folder; the two folders written earlier are listed, so they are removed.
# The unlisted team-own folder stays.
s19_wm="$s19_w1/.claude/workspace.md"
sed 's/^- \*\*Kit skills not bridged:\*\* none/- **Kit skills not bridged:** `closeout, workspace-hygiene`/' "$s19_wm" > "$s19_wm.s19" \
    && cat "$s19_wm.s19" > "$s19_wm"
s19_run "$s19_w1"
s19_bad=""
[[ $s19_rc -eq 0 ]] || s19_bad+="rc $s19_rc"$'\n'
for s19_n in kit-closeout kit-workspace-hygiene; do
    [[ -e "$s19_sk/$s19_n" ]] && s19_bad+="$s19_n is still there"$'\n'
    s19_has "^  skip    $s19_n  \(Kit skills not bridged\)$" || s19_bad+="no skip line for $s19_n"$'\n'
    s19_has "^  removed $s19_n  " || s19_bad+="no removed line for $s19_n"$'\n'
    awk -F '\t' -v n="$s19_n" '$1 == "skip" && $2 == n' "$s19_man" | grep -q . || s19_bad+="no skip line in the manifest for $s19_n"$'\n'
done
[[ -f "$s19_sk/team-own/SKILL.md" ]] || s19_bad+="the unlisted team-own folder was removed"$'\n'
[[ -d "$s19_sk/kit-projects-new" ]] || s19_bad+="kit-projects-new was removed"$'\n'
empty "19 the skip list gives skip lines and no folder; only listed folders are removed" "$s19_bad${s19_bad:+$s19_out}"

# A workspace whose manifest lists folders that are missing (regenerated, as stale), and one the kit no
# longer produces (removed). An unlisted kit- folder of the team's own is left alone.
s19_w3="$SCRATCH/s19-ws3"
if mkws_min "$s19_w3"; then
    s19_sk3="$s19_w3/.claude/skills"
    s19_skill "$s19_w3/skills/daily-notes" daily-notes "Keeps the daily notes. Offer it at the start of a day."
    s19_skill "$s19_sk3/kit-retired" kit-retired "A command the kit has since dropped."
    s19_skill "$s19_sk3/kit-team-extra" kit-team-extra "The team's own, never listed."
    printf '# Written by kit/scripts/skills-bridge.sh.\nkit\tkit-projects-board\tplugins/projects/commands/board.md\nkit\tkit-retired\tplugins/retired/commands/cmd.md\nuser\tdaily-notes\tskills/daily-notes\n' \
        > "$s19_sk3/.kit-generated"
    s19_run "$s19_w3"
    s19_bad=""
    [[ $s19_rc -eq 0 ]] || s19_bad+="rc $s19_rc"$'\n'
    for s19_n in kit-projects-board daily-notes; do
        s19_has "^  stale   $s19_n  \(listed, missing; regenerated\)$" || s19_bad+="no stale line for $s19_n"$'\n'
        [[ -f "$s19_sk3/$s19_n/SKILL.md" ]] || s19_bad+="$s19_n was not regenerated"$'\n'
    done
    s19_has '^  removed kit-retired  ' || s19_bad+="no removed line for kit-retired"$'\n'
    [[ -e "$s19_sk3/kit-retired" ]] && s19_bad+="kit-retired is still there"$'\n'
    [[ -f "$s19_sk3/kit-team-extra/SKILL.md" ]] || s19_bad+="the unlisted kit-team-extra was removed"$'\n'
    awk -F '\t' '$2 == "kit-retired" || $2 == "kit-team-extra"' "$s19_sk3/.kit-generated" | grep -q . && s19_bad+="the manifest still lists kit-retired or lists kit-team-extra"$'\n'
    empty "19 a listed folder that is missing is reported stale and regenerated; a listed one no longer produced is removed; unlisted ones stay" "$s19_bad${s19_bad:+$s19_out}"
else ko "19 the stale-and-removed fixture builds"; fi

# A first run, with no manifest: an older sync script's mirror of a user skill is adopted and refreshed;
# the kit's older unprefixed skill is reported as legacy and left; anything else is named and left. A
# 2.x generated skill still in skills/ is not the workspace's own, and is not copied.
s19_w2="$SCRATCH/s19-ws2"
if mkws_min "$s19_w2"; then
    s19_sk2="$s19_w2/.claude/skills"
    s19_skill "$s19_w2/skills/daily-notes" daily-notes "Current text."
    s19_skill "$s19_sk2/daily-notes" daily-notes "An older mirror."
    s19_skill "$s19_sk2/projects-new" projects-new "The 2.x skill."
    printf '<!-- Generated by install.sh from plugins/projects/commands/new.md: edit that file, then re-run the installer. -->\n' >> "$s19_sk2/projects-new/SKILL.md"
    s19_skill "$s19_w2/skills/workspace-hygiene" workspace-hygiene "The 2.x skill."
    printf '<!-- Generated by install.sh from plugins/workspace/commands/hygiene.md: edit that file, then re-run the installer. -->\n' >> "$s19_w2/skills/workspace-hygiene/SKILL.md"
    mkdir -p "$s19_sk2/something-else" && printf 'Kept.\n' > "$s19_sk2/something-else/notes.md"
    s19_run "$s19_w2"
    s19_bad=""
    [[ $s19_rc -eq 0 ]] || s19_bad+="rc $s19_rc"$'\n'
    s19_has '^  user    daily-notes  copied \(adopted\)$' || s19_bad+="daily-notes was not adopted"$'\n'
    grep -q 'Current text' "$s19_sk2/daily-notes/SKILL.md" || s19_bad+="the adopted copy was not refreshed"$'\n'
    awk -F '\t' '$1 == "user" && $2 == "daily-notes"' "$s19_sk2/.kit-generated" | grep -q . || s19_bad+="the adopted copy is not in the manifest"$'\n'
    s19_has "^  legacy  projects-new  — the kit's older unprefixed skill; kit-projects-new replaces it" || s19_bad+="no legacy line for projects-new"$'\n'
    grep -q 'The 2.x skill' "$s19_sk2/projects-new/SKILL.md" || s19_bad+="the legacy folder was changed"$'\n'
    s19_has '^  legacy  workspace-hygiene  — skills/workspace-hygiene was generated' || s19_bad+="no legacy line for skills/workspace-hygiene"$'\n'
    [[ -e "$s19_sk2/workspace-hygiene" ]] && s19_bad+="the 2.x generated skill in skills/ was copied"$'\n'
    s19_has '^  left    something-else  ' || s19_bad+="something-else is not named"$'\n'
    [[ -f "$s19_sk2/something-else/notes.md" ]] || s19_bad+="something-else was changed"$'\n'
    empty "19 a first run adopts a mirrored copy, reports the kit's older skills as legacy, and leaves the rest" "$s19_bad${s19_bad:+$s19_out}"
else ko "19 the first-run fixture builds"; fi

fi
fi
