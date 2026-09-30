# shellcheck shell=bash
# The checks quote Markdown with literal backticks and dollar signs (SC2016), follow the suite's
# "test && ok || ko" style, where ok always succeeds (SC2015), and use the prelude's st_bash (SC2154).
# shellcheck disable=SC2016,SC2015,SC2154
# Section 17: the projects lifecycle in 3.0. Sourced by tests/run.sh after section 11, so it uses the
# prelude's helpers (ok, ko, skp, check, empty, st_bash, mkws_min) and writes only under $SCRATCH.
# Every name here starts with s17_, since the sections share one shell.
#
# It covers readme.awk fields 16-20, the projects session-start hook (the old-format line beside the
# new fields, reserved folders, the resource line and its stamp, the Not adopted note), the ten
# commands, and the instructions each projects command carries for versioning, sensitivity, holding,
# archiving and resuming.

echo
echo "17 · Projects: versioning, sensitivity, hold, archive and resources"

s17_hook="$KIT/plugins/projects/hooks/session-start.sh"
s17_awk="$KIT/plugins/projects/hooks/lib/readme.awk"
s17_cmd="$KIT/plugins/projects/commands"
s17_stamps="$SCRATCH/s17-stamps"

# s17_start <cwd> [VAR=value...]: the hook's stdout, with the section's own stamp directory.
s17_start() {
    local cwd="$1"; shift
    jq -nc --arg c "$cwd" '{cwd: $c, source: "startup"}' \
        | env PROJECTS_HOOK_STATE_DIR="$s17_stamps" "$@" "$st_bash" "$s17_hook" 2>/dev/null
}
s17_msg() { jq -r '.systemMessage // empty' 2>/dev/null; }
s17_ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
# s17_fields <file> <n...>: the named fields of readme.awk's record for one file, joined by "|".
s17_fields() {
    local f="$1"; shift
    awk -f "$s17_awk" "$f" | awk -F '\037' -v want="$*" \
        '{ n = split(want, w, " "); o = ""; for (i = 1; i <= n; i++) o = o (i > 1 ? "|" : "") $(w[i]); print o }'
}
# s17_flat <file>: the file on one line, runs of spaces squeezed, for phrase checks across wrapped lines.
s17_flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
# s17_has <file> <phrase...>: every phrase is in the flattened file, or the missing ones are printed.
s17_has() {
    local f="$1" flat p; shift
    flat="$(s17_flat "$f")"
    for p in "$@"; do grep -qF -- "$p" <<<"$flat" || printf '%s: no "%s"\n' "${f##*/}" "$p"; done
}
# s17_before <file> <first> <second>: the first phrase appears before the second.
s17_before() {
    python3 - "$1" "$2" "$3" <<'PYBEFORE'
import sys
text = " ".join(open(sys.argv[1], encoding="utf-8").read().split())
a, b = text.find(sys.argv[2]), text.find(sys.argv[3])
if a < 0 or b < 0 or a > b:
    print(f"{sys.argv[1].rsplit('/', 1)[-1]}: \"{sys.argv[2]}\" is not before \"{sys.argv[3]}\" ({a}, {b})")
PYBEFORE
}

# ---- readme.awk fields 16-20 ---------------------------------------------------------------------

s17_r="$SCRATCH/s17-readmes"
mkdir -p "$s17_r"
cat > "$s17_r/full.md" <<'S17A'
# Field study

- **Versioned:** Own-repo, since the site went live
- Sensitivity: `sensitive` — interview consent forms

```
- **Versioned:** workspace
```

## Current state

- **State:** doing

## Resources *(optional)*

- `media` — raw interview recordings (large)
- exports — Generated renders, rebuilt by make
- survey-data: the survey extract, read-only
- field notes — has a space in its name
- <name> — <what it is>
<!-- - hidden — inside a comment -->
<!--
- also-hidden — inside a longer comment
-->

## Open questions
- not-a-resource — under another heading
S17A
s17_got="$(s17_fields "$s17_r/full.md" 16 17 18 19 20)"
[[ "$s17_got" == "own-repo|sensitive|media,exports,survey-data|exports|field notes" ]] \
    && ok "17 readme.awk fields 16-20: versioned, sensitivity, resources, generated, ignored" \
    || ko "17 readme.awk fields 16-20: versioned, sensitivity, resources, generated, ignored" "$s17_got"
printf '# Plain\n\n- **Versioned:** maybe\n- **Sensitivity:** <normal · sensitive>\n\n## Current state\n\n- **State:** ready\n' > "$s17_r/plain.md"
s17_got="$(s17_fields "$s17_r/plain.md" 16 17 18 19 20)"
[[ "$s17_got" == "||||" ]] \
    && ok "17 readme.awk: an unknown Versioned value and a stand-in Sensitivity are empty, with no resources" \
    || ko "17 readme.awk: an unknown Versioned value and a stand-in Sensitivity are empty, with no resources" "$s17_got"
s17_got="$(s17_fields "$KIT/templates/project-readme.md" 16 17 18 20)"
[[ "$s17_got" == "|||" ]] \
    && ok "17 readme.awk: the project template's two lines and its Resources item are stand-ins, read as empty" \
    || ko "17 readme.awk: the project template's two lines and its Resources item are stand-ins, read as empty" "$s17_got"

# ---- The project template and the conventions templates ------------------------------------------

s17_tpl="$KIT/templates/project-readme.md"
s17_bad=""
[[ "$(sed -n '3p' "$s17_tpl")" == '- **Versioned:** <workspace · own-repo · untracked>' ]] || s17_bad+="line 3 is not the Versioned line"$'\n'
[[ "$(sed -n '4p' "$s17_tpl")" == '- **Sensitivity:** <normal · sensitive>' ]] || s17_bad+="line 4 is not the Sensitivity line"$'\n'
s17_got="$(grep -n '^## ' "$s17_tpl" | sed 's/^[0-9]*://' | paste -sd'|' -)"
case "$s17_got" in
    *'## Where everything lives|## Resources *(optional)*|## Working conventions'*) ;;
    *) s17_bad+="Resources is not the optional section after Where everything lives: $s17_got"$'\n' ;;
esac
s17_bad+="$(s17_has "$s17_tpl" 'no machine path goes here' '.claude/resources.local.md' 'kit/setup.sh link <slug>')"
empty "17 the project template: Versioned and Sensitivity under the title, and an optional Resources section" "$s17_bad"

s17_pc="$KIT/templates/workspace/projects.md"
s17_bad=""
for s17_l in '- **Paused:** `projects/<slug>/`' '- **Done:** `projects/_done/<slug>/`' '- **Folder moves:** `the command`' \
             '- **Versioned default:** `workspace`' '- **Project template:** `kit/templates/project-readme.md`' \
             '- **People:** `memory/people/<name>.md`, from `kit/templates/person-profile.md`' \
             '- **Register:** `projects/INDEX.md`, with the sections `Active`, `Paused` and `Done`' \
             '- **Reserved folders:**' '- **Not adopted:** none'; do
    grep -qF -- "$s17_l" "$s17_pc" || s17_bad+="no line starting: $s17_l"$'\n'
done
s17_bad+="$(s17_has "$s17_pc" 'stays versioned' 'the person' '(`_done`, `_delete`)')"
# The kit's state check still reads the template as the kit's own conventions.
grep -qiE '^#+[[:space:]]+Project conventions' "$s17_pc" || s17_bad+="no Project conventions heading"$'\n'
grep -E '^[[:space:]]*[-*] \*\*' "$s17_pc" | grep -qi 'not set yet' && s17_bad+="a setting still reads not set yet"$'\n'
empty "17 .claude/projects.md template carries the 3.0 values (paused in place, _done, folder moves, versioned default, reserved, Not adopted)" "$s17_bad"
s17_got="$(grep -E '^## ' "$KIT/templates/workspace/INDEX.md" | paste -sd'|' -)"
[[ "$s17_got" == '## Active|## Paused|## Done' && "$(grep -c '^| Project | Folder |' "$KIT/templates/workspace/INDEX.md")" == 3 ]] \
    && ok "17 the register template has Active, Paused and Done, each with a table that links the folder" \
    || ko "17 the register template has Active, Paused and Done, each with a table that links the folder" "$s17_got"

# ---- The conventions reader: Not adopted -----------------------------------------------------------

s17_cf="$SCRATCH/s17-conf"
mkdir -p "$s17_cf/.claude"
cp "$s17_pc" "$s17_cf/.claude/projects.md"
s17_got="$(
    # shellcheck source=/dev/null
    . "$KIT/plugins/projects/hooks/lib/config.sh"
    projects_config "$s17_cf"
    printf '%s|%s|' "$NOT_ADOPTED" "$(printf '%s' "$PROJECT_PATTERNS" | paste -sd, -)"
    sed 's#^- \*\*Not adopted:\*\* none#- **Not adopted:** `site, projects/tool/`#' "$s17_pc" > "$s17_cf/.claude/projects.md"
    projects_config "$s17_cf"
    for s17_p in projects/site projects/tool projects/other; do
        if projects_not_adopted "$s17_p"; then printf 'y'; else printf 'n'; fi
    done
)"
[[ "$s17_got" == "|projects/<slug>,projects/_done/<slug>|yyn" ]] \
    && ok "17 conventions: Not adopted is none by default, a backticked list names folders by slug or path, and paused stays in place" \
    || ko "17 conventions: Not adopted is none by default, a backticked list names folders by slug or path, and paused stays in place" "$s17_got"

# ---- The session-start hook ----------------------------------------------------------------------

s17_ws="$SCRATCH/s17-ws"
if ! mkws_min "$s17_ws" >/dev/null 2>&1; then
    # Without KITSRC, a plain repository with the same conventions serves: the hook reads only files.
    s17_ws="$SCRATCH/s17-ws-plain"
    mkdir -p "$s17_ws/.claude" && git -C "$s17_ws" init -q
fi
mkdir -p "$s17_ws/.claude"
sed -e 's/__TEAM__/Test Team/' -e 's#^- \*\*Not adopted:\*\* none#- **Not adopted:** `site`#' "$s17_pc" > "$s17_ws/.claude/projects.md"
mkdir -p "$s17_ws/projects/field-study" "$s17_ws/projects/legacy" "$s17_ws/projects/_done/shipped" \
    "$s17_ws/projects/_delete/old" "$s17_ws/projects/stuck" "$s17_ws/projects/site" "$s17_ws/projects/loose"
cat > "$s17_ws/projects/field-study/README.md" <<'S17B'
# Field study

- **Versioned:** workspace
- **Sensitivity:** normal

## Desired outcome

The field study report is published.

## Done when

- [x] interviews done
- [ ] report published

## Current state

- **State:** doing
- **Updated:** 2026-09-24

2026-09-24 — Drafting.

## People

- Sam Example — owns

## Resources

- media — raw interview recordings
- survey-data — the survey extract
- exports — generated renders
S17B
printf '# Resources on this machine\n\nfield-study/survey-data\t/Volumes/Data/field-study/survey\nother/media  /Volumes/Data/other\n' \
    > "$s17_ws/.claude/resources.local.md"

s17_out="$(s17_start "$s17_ws/projects/field-study")"
s17_m="$(s17_msg <<<"$s17_out")"
if [[ "$(printf '%s\n' "$s17_m" | grep -c .)" == "4" ]] \
    && [[ "$(printf '%s\n' "$s17_m" | sed -n '4p')" == 'Resources not mapped on this machine: media — kit/setup.sh link field-study maps them.' ]]; then
    ok "17 hook: a fourth line names the resources not mapped here, leaving out mapped and generated ones"
else ko "17 hook: a fourth line names the resources not mapped here, leaving out mapped and generated ones" "$s17_m"; fi
s17_c="$(s17_ctx <<<"$s17_out")"
grep -qF 'never guess one' <<<"$s17_c" && grep -qF '.claude/resources.local.md' <<<"$s17_c" && grep -qF 'kit/setup.sh link field-study' <<<"$s17_c" \
    && ok "17 hook: the agent is asked to offer the mapping once, asking for each path and never guessing" \
    || ko "17 hook: the agent is asked to offer the mapping once, asking for each path and never guessing" "$s17_c"
s17_key="$(printf '%s' "$s17_ws" | sed 's#/#-#g; s#^-##')"
check "17 hook: the offer is stamped outside the repository with the sorted list it offered" \
    test "$(cat "$s17_stamps/$s17_key.field-study.resources" 2>/dev/null)" = "media"
s17_m="$(s17_start "$s17_ws/projects/field-study" | s17_msg)"
[[ "$(printf '%s\n' "$s17_m" | grep -c .)" == "3" ]] \
    && ok "17 hook: the same unmapped set is not offered twice on one machine" \
    || ko "17 hook: the same unmapped set is not offered twice on one machine" "$s17_m"
printf -- '- notes — the paper notebook scans\n' >> "$s17_ws/projects/field-study/README.md"
s17_m="$(s17_start "$s17_ws/projects/field-study" | s17_msg)"
grep -qxF 'Resources not mapped on this machine: media, notes — kit/setup.sh link field-study maps them.' <<<"$s17_m" \
    && ok "17 hook: a changed set of unmapped names is offered again" \
    || ko "17 hook: a changed set of unmapped names is offered again" "$s17_m"
s17_hs="$SCRATCH/s17-headless-stamps"
empty "17 hook: AW_HEADLESS_RUN=1 says nothing and writes no resource stamp" \
    "$(jq -nc --arg c "$s17_ws/projects/field-study" '{cwd: $c}' | env PROJECTS_HOOK_STATE_DIR="$s17_hs" AW_HEADLESS_RUN=1 "$st_bash" "$s17_hook" 2>&1; ls -A "$s17_hs" 2>/dev/null)"
printf 'field-study/media ~/recordings\nfield-study/notes /Volumes/Scans\n' >> "$s17_ws/.claude/resources.local.md"
s17_m="$(s17_start "$s17_ws/projects/field-study" | s17_msg)"
[[ "$(printf '%s\n' "$s17_m" | grep -c .)" == "3" ]] \
    && ok "17 hook: once every name is mapped, there is no resource line" \
    || ko "17 hook: once every name is mapped, there is no resource line" "$s17_m"

# The reader rule: the old-format flag is still read by position with the five new fields after it.
printf '# Legacy\n\n- **Versioned:** untracked\n- **Sensitivity:** sensitive\n\n## Now\n\n- **State:** doing\n\n## People\n\n- Ana — owns\n\n## Resources\n\n- archive — generated\n' \
    > "$s17_ws/projects/legacy/README.md"
s17_m="$(s17_start "$s17_ws/projects/legacy" | s17_msg)"
grep -qxF 'State: doing — owner Ana — from an older Now block; /projects:adopt converts it' <<<"$s17_m" \
    && [[ "$(printf '%s\n' "$s17_m" | grep -c .)" == "3" ]] \
    && ok "17 hook: a README in the old Now format still gets the old-format line with fields 16-20 present" \
    || ko "17 hook: a README in the old Now format still gets the old-format line with fields 16-20 present" "$s17_m"

# Reserved folders: _delete is never a project; _done is read through the Done location only.
printf '# Old\n\n## Current state\n\n- **State:** blocked\n- **Blocked by:** a quote — since 2025-01-01\n' > "$s17_ws/projects/_delete/old/README.md"
printf '# Shipped\n\n## Current state\n\n- **State:** done\n- **Blocked by:** a quote — since 2025-01-01\n- **Updated:** 2026-09-01\n' > "$s17_ws/projects/_done/shipped/README.md"
printf '# Stuck\n\n## Current state\n\n- **State:** blocked\n- **Blocked by:** legal sign-off — since 2025-01-01\n' > "$s17_ws/projects/stuck/README.md"
s17_m="$(s17_start "$s17_ws/projects/_delete/old" PROJECTS_HOOK_TODAY=2026-01-01 | s17_msg)"
grep -qE '^(Project|Done|State):' <<<"$s17_m" \
    && ko "17 hook: a session in projects/_delete/ is not in a project" "$s17_m" \
    || ok "17 hook: a session in projects/_delete/ is not in a project"
grep -qxF 'Done 2026-09-01; how it ended is recorded in README.md' <<<"$(s17_start "$s17_ws/projects/_done/shipped" | s17_msg)" \
    && ok "17 hook: a finished project in projects/_done/<slug>/ reads as done, through the Done location" \
    || ko "17 hook: a finished project in projects/_done/<slug>/ reads as done, through the Done location" "$(s17_start "$s17_ws/projects/_done/shipped")"
s17_m="$(s17_start "$s17_ws" PROJECTS_HOOK_TODAY=2026-01-02 | s17_msg)"
[[ "$s17_m" == 'Projects: 1 active project blocked for more than 14 days (Stuck). /projects:board shows it.' ]] \
    && ok "17 hook: the once-a-day scan skips _done and _delete" \
    || ko "17 hook: the once-a-day scan skips _done and _delete" "$s17_m"

# Not adopted: a listed folder with no Current state block tells the agent, and the person sees nothing;
# an unlisted one is silent, as before.
printf '# Our site\n\nWelcome to the site.\n' > "$s17_ws/projects/site/README.md"
printf '# Loose\n\nSome notes.\n' > "$s17_ws/projects/loose/README.md"
s17_out="$(s17_start "$s17_ws/projects/site")"
if [[ -z "$(s17_msg <<<"$s17_out")" ]] && grep -qF 'Not adopted' <<<"$(s17_ctx <<<"$s17_out")" \
    && grep -qF '/projects:adopt is not offered here' <<<"$(s17_ctx <<<"$s17_out")"; then
    ok "17 hook: a Not adopted folder gets a note for the agent only, so adopt is not offered unprompted"
else ko "17 hook: a Not adopted folder gets a note for the agent only, so adopt is not offered unprompted" "$s17_out"; fi
empty "17 hook: a folder with no Current state block that is not listed stays silent" "$(s17_start "$s17_ws/projects/loose")"
empty "17 hook: every run exits quietly (nothing on stderr)" \
    "$(jq -nc --arg c "$s17_ws/projects/field-study" '{cwd: $c}' | PROJECTS_HOOK_STATE_DIR="$s17_stamps" "$st_bash" "$s17_hook" 2>&1 >/dev/null)"

# ---- The ten commands ----------------------------------------------------------------------------

s17_want="closeout/closeout projects/adopt projects/board projects/close projects/hold projects/new projects/pickup workspace/hygiene workspace/quick-start workspace/register-audit"
s17_got="$(cd "$KIT/plugins" && for s17_f in ./*/commands/*.md; do s17_f="${s17_f#./}"; printf '%s\n' "${s17_f%.md}"; done \
    | sed 's#/commands/#/#' | sort | paste -sd' ' -)"
[[ "$s17_got" == "$s17_want" ]] && ok "17 the kit has exactly the ten commands, /projects:hold among them" \
    || ko "17 the kit has exactly the ten commands, /projects:hold among them" "has: $s17_got"

# ---- What each projects command says -------------------------------------------------------------

s17_h="$s17_cmd/hold.md"
s17_bad="$(s17_has "$s17_h" \
    'description: Put a project on hold — set it to paused with a one-line reason and, if wanted, a date to look at it again; its register row moves to the paused section, and the folder stays where it is, still versioned' \
    'offer-unprompted: Offer it when someone says a project is stopping for now, or is being set aside to come back to later.' \
    'argument-hint: [folder or slug] [reason]' \
    'State: paused' 'The reason' 'look again on YYYY-MM-DD' '<today> — Paused: <reason>.' 'was blocked by' \
    '"On hold"' '[<Name>](<slug>/)' 'the same columns as the active table' 'By default the folder does not move' \
    'stays versioned' 'this convention predates' 'Folder moves' '`/projects:close` owns' 'change only those two' \
    'frees' '/projects:pickup' 'Leave the commit to them')"
empty "17 hold: paused with a reason and a look-again date, the conventions' paused section, the folder link, the folder stays" "$s17_bad"

s17_c="$s17_cmd/close.md"
s17_bad="$(s17_has "$s17_c" 'projects/_done/<slug>/' 'mkdir -p projects/_done' 'git mv projects/<slug> projects/_done/<slug>' \
    '`.gitmodules`' 'git submodule absorbgitdirs' 'kit/setup.sh hooks' \
    'the `.gitignore` line `projects/<slug>/` rewritten to `projects/_done/<slug>/`' '!projects/<slug>/**/*.pptx' \
    'grep -rl' '--exclude-dir=kit' 'not rewritten' '`_done/<slug>/`' 'Folder moves' 'print the same commands' \
    'the commit is left to the person')"
empty "17 close: archives to projects/_done with git mv, rewrites the untracked .gitignore line and lists the others, runs hooks, follows Folder moves" "$s17_bad"

s17_n="$s17_cmd/new.md"
s17_bad="$(s17_has "$s17_n" '- **Versioned:** workspace' '- **Sensitivity:** normal' 'Versioned default' \
    'asked on the quick path too' 'for `sensitive` with `workspace`' '`untracked` (the default), or `own-repo` with a remote confirmed private' \
    'gh repo view' 'Public remote' 'Private remote' '# Projects kept out of the workspace repository (Versioned: untracked)' \
    'git submodule add <url> projects/<slug>' '## Resources' 'kit/setup.sh link <slug>')"
s17_bad+="$(s17_before "$s17_n" '1. `git init` in the project folder.' '2. `kit/setup.sh hooks --repo projects/<slug>`')"
s17_bad+="$(s17_before "$s17_n" 'kit/setup.sh hooks --repo projects/<slug>' '3. The remote they name.')"
s17_bad+="$(s17_before "$s17_n" '3. The remote they name.' 'git -C projects/<slug> remote add origin <url>')"
s17_bad+="$(s17_before "$s17_n" 'push -u origin HEAD' 'git submodule add <url> projects/<slug>')"
empty "17 new: asks Versioned and Sensitivity, refuses sensitive with workspace, and sets up own-repo with hooks before the remote" "$s17_bad"

s17_a="$s17_cmd/adopt.md"
s17_bad="$(s17_has "$s17_a" '**workspace → own-repo.**' '**workspace → untracked.**' '**untracked → workspace.**' \
    '**untracked → own-repo.**' '**own-repo → workspace.**' '**own-repo → untracked.**' \
    'git subtree -h' 'confirmed private' '`$(git rev-parse --git-common-dir)/modules/<name>`' '`_delete/modules-<name>`' \
    '`_delete/<slug>.git`' 'git config -f .gitmodules --remove-section submodule.<name>' 'earlier commits still hold the files' \
    'history to remove them is the person' 'Refused while the project is `sensitive`' 'kit/setup.sh hooks --repo projects/<slug>' \
    'kit/setup.sh link <slug>' 'Not adopted' 'ask before writing to its entry point' 'The versioning lines' \
    'workspace|own-repo|untracked')"
s17_bad+="$(s17_before "$s17_a" 'git log --diff-filter=D --name-only --format= -- projects/<slug>' 'git subtree split --prefix=projects/<slug>')"
s17_bad+="$(s17_before "$s17_a" 'git subtree -h' 'git subtree split --prefix=projects/<slug> -b split/<slug>')"
s17_bad+="$(s17_before "$s17_a" '3. `kit/setup.sh hooks --repo projects/<slug>`' '4. The remote the person names')"
s17_bad+="$(s17_before "$s17_a" 'git rm -r --cached projects/<slug>` — the workspace stops' '8. `git submodule add <url> projects/<slug>`')"
empty "17 adopt: the six transitions, history listed before subtree split, subtree -h, the modules folder, the link offer, Not adopted" "$s17_bad"

s17_b="$s17_cmd/board.md"
s17_bad="$(s17_has "$s17_b" 'kit/plugins/workspace/bin/state.sh --quick' '`sensitive_tracked`' '`versioned_mismatch`' \
    '`submodules_attention`' '`resource.<slug>/<name>`' 'not on this machine' 'look again on <date>' 'Not adopted')"
s17_bad+="$(s17_before "$s17_b" '8. **Ready to close**' '9. **Sensitive and tracked**')"
s17_bad+="$(s17_before "$s17_b" '9. **Sensitive and tracked**' '10. **Versioning disagrees**')"
s17_bad+="$(s17_before "$s17_b" '10. **Versioning disagrees**' '11. **Submodule out of step**')"
s17_bad+="$(s17_before "$s17_b" '11. **Submodule out of step**' '12. **Resource not reachable here**')"
s17_bad+="$(s17_before "$s17_b" '12. **Resource not reachable here**' '13. **Look-again date reached**')"
empty "17 board: flags 9-13 in order, from the state check where it is present" "$s17_bad"

s17_p="$s17_cmd/pickup.md"
s17_bad="$(s17_has "$s17_p" 'read-only while briefing; after the brief, one offered write: resuming a paused project, on a yes' \
    'Read-only while briefing; after the brief, one offered write: resuming a paused project, on a yes' \
    '`State: ready`' 'look again on YYYY-MM-DD' '`<today> — Resumed.`' 'Active section' 'in flight')"
grep -qF 'Read-only, always' "$s17_p" && s17_bad+="pickup.md: still says Read-only, always"$'\n'
empty "17 pickup: read-only while briefing, then one offered write that resumes a paused project" "$s17_bad"

# Every command that moves a register row takes the section's name from the conventions, so a register
# whose paused section is "On hold" keeps that name.
s17_bad="$(s17_has "$s17_h" "paused section, whatever it is called there")"
s17_bad+="$(s17_has "$s17_c" "Done section, whatever it is called there")"
s17_bad+="$(s17_has "$s17_p" "both as the conventions file names them")"
empty "17 hold, close and pickup move register rows to the sections the conventions name" "$s17_bad"

s17_bad="$(s17_has "$KIT/plugins/projects/README.md" 'Six commands' '/projects:hold' 'projects/_done/<slug>/' \
    '## How a project is kept' '## Resources' 'Folder moves' 'Not adopted')"
s17_bad+="$(s17_has "$KIT/plugins/projects/examples/projects-conventions.md" 'Folder moves' 'Versioned default' \
    'Not adopted' 'projects/_done/<slug>/' 'kit/templates/project-readme.md')"
empty "17 the plugin README and the example conventions describe the 3.0 lifecycle" "$s17_bad"
