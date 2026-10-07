# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh, which sources this file (SC2154); backticks in
# single quotes are the Markdown being looked for (SC2016); a check ends in ok or ko, never both (SC2015).
# shellcheck disable=SC2154,SC2016,SC2015
# Section 21: closeout's commit plan and archive wording, the hygiene and register passes, the quick-start,
# and the pilot scripts in the 3.0 layout. Everything here is prefixed s21_, since the sections share one
# shell, and writes only under $SCRATCH.

echo
echo "21 · Closeout's commit order, the hygiene and register passes, and the pilot in a 3.0 workspace"

s21_dir="$SCRATCH/s21"
mkdir -p "$s21_dir"

# s21_flat <file>: the file on one line, runs of spaces folded, so a phrase can break across lines.
s21_flat() { tr '\n' ' ' < "$KIT/$1" | tr -s ' '; }
# s21_needs <file> <phrase>...: a line of detail per phrase the file lacks.
s21_needs() {
    local f="$1" flat w; shift
    flat="$(s21_flat "$f")"
    for w in "$@"; do grep -qF -- "$w" <<<"$flat" || printf '%s: no "%s"\n' "$f" "$w"; done
}

# --- Closeout: the commit is the person's, and submodules come first ---------------------------------
s21_bad=""
for s21_f in plugins/closeout/commands/closeout.md rituals/closeout.md; do
    s21_bad+="$(s21_needs "$s21_f" 'Leave the commit to the person' 'inside the submodule' 'add, commit and push' \
        'git add kit' 'push.recurseSubmodules=check' 'innermost' 'no command carries a comment' \
        'projects/_done/' 'kit/CLAUDE.kit.md' '.claude/skills/.kit-generated')"
    grep -qF 'stage what you touched' "$KIT/$s21_f" && s21_bad+="$s21_f: still asks the agent to stage"$'\n'
    grep -qF 'stage what it touched' "$KIT/$s21_f" && s21_bad+="$s21_f: still asks the agent to stage"$'\n'
    # The submodule's own commit comes before the workspace's pointer, in the text as in the commands.
    python3 - "$KIT/$s21_f" <<'PYORDER' || s21_bad+="$s21_f: the workspace commit is described before the submodule's"$'\n'
import sys
t = " ".join(open(sys.argv[1], encoding="utf-8").read().split())
a, b = t.find("inside the submodule, add, commit and push"), t.find("in the workspace, add the submodule's path")
sys.exit(0 if 0 <= a < b else 1)
PYORDER
done
empty "21 closeout: the command and the ritual leave the commit to the person, submodule first, with the 3.0 paths" "$s21_bad"

# The command's example: every line a git command with no comment, the project repository's lines
# before the workspace's add of its pointer.
s21_block="$(awk '/^```/ { if (f) exit; f = 1; next } f' <(sed -n '/^## Report/,/^## Finally/p' "$KIT/plugins/closeout/commands/closeout.md"))"
s21_bad=""
[[ -n "$s21_block" ]] || s21_bad+="no example block in the Report section"$'\n'
while IFS= read -r s21_l; do
    [[ -n "$s21_l" ]] || continue
    [[ "$s21_l" == git\ * ]] || s21_bad+="not a git command: $s21_l"$'\n'
    [[ "$s21_l" == *" #"* ]] && s21_bad+="carries a comment: $s21_l"$'\n'
done <<<"$s21_block"
s21_first_ws="$(grep -n '^git add ' <<<"$s21_block" | head -n 1 | cut -d: -f1)"
s21_last_sub="$(grep -n '^git -C ' <<<"$s21_block" | tail -n 1 | cut -d: -f1)"
[[ -n "$s21_first_ws" && -n "$s21_last_sub" && "$s21_last_sub" -lt "$s21_first_ws" ]] \
    || s21_bad+="the workspace's git add does not follow every submodule command"$'\n'
grep -q '^git -C [^ ]* push$' <<<"$s21_block" || s21_bad+="the submodule is not pushed before its pointer is committed"$'\n'
empty "21 closeout: the example commit plan is plain git commands, the submodule's first" "$s21_bad"

s21_bad="$(s21_needs plugins/closeout/README.md 'Committing is the person' 'innermost first' 'push.recurseSubmodules=check' \
    '.claude/skills/.kit-generated'; s21_needs plugins/closeout/docs/DESIGN.md 'innermost first' \
    'push.recurseSubmodules=check' '.claude/skills/.kit-generated')"
empty "21 closeout README and DESIGN: the commit order and the skills-bridge rule are explained" "$s21_bad"

# --- Closeout: .claude/skills/ is not a destination beside the skills bridge ------------------------
# s21_general <project dir> [VAR=value...]: the General reference row's shared destination.
s21_general() {
    local d="$1"; shift
    env "$@" CLOSEOUT_USER_CONVENTIONS= bash -c 'source "$1/lib/config.sh"; closeout_config "$2"; printf "%s\n" "$TIER_TABLE"' \
        _ "$KIT/plugins/closeout/hooks" "$d" | awk -F'|' '$2 ~ /General reference/ { gsub(/^ +| +$/, "", $4); print $4 }'
}
s21_pb="$s21_dir/bridge" s21_pn="$s21_dir/nobridge"
mkdir -p "$s21_pb/.claude/skills/kit-closeout" "$s21_pb/skills" "$s21_pn/.claude/skills"
printf '# Written by kit/scripts/skills-bridge.sh.\nkit\tkit-closeout\tplugins/closeout/commands/closeout.md\n' \
    > "$s21_pb/.claude/skills/.kit-generated"
s21_got="$(s21_general "$s21_pb")|$(s21_general "$s21_pn")|$(s21_general "$s21_pb" CLOSEOUT_TIER_GENERAL=docs/reference/)"
[[ "$s21_got" == "skills/|.claude/skills/|docs/reference/" ]] \
    && ok "21 closeout config: with the bridge's manifest, general reference goes to skills/; without it, .claude/skills/; the variable still wins" \
    || ko "21 closeout config: with the bridge's manifest, general reference goes to skills/; without it, .claude/skills/; the variable still wins" "$s21_got"

# --- Hygiene, register audit, the quick-start: the 3.0 wording --------------------------------------
s21_bad="$(s21_needs plugins/workspace/commands/hygiene.md 'kit/rituals/weekly-hygiene.md' \
    'bash kit/plugins/workspace/bin/state.sh --quick' '**Submodules.**' \
    'path · role · changed files · not pushed · pointer · behind · branch' \
    '`hooks` and `kit_hooks`' '`kit_import`' '`origin_visibility`, with `origin_confirmed`' '`orphan_gitlinks`' \
    '`external_paths_missing`' '`sensitive_tracked`' '`versioned_mismatch`' '`skills_bridge_stale`' \
    "the kit's bytes" "the workspace's bytes" 'hygiene-YYYY-MM-DD.md`, whatever comes before' \
    'bash kit/pilot/measure.sh' 'kit/pilot/ablate.sh' 'skills-bridge.sh --check' 'projects/_done/')"
s21_bad+="$(s21_needs rituals/weekly-hygiene.md 'Nine checks' '| **Submodules** |' 'state.sh --quick' \
    'hygiene-YYYY-MM-DD.md`, whatever comes before' "the kit's bytes and the workspace's bytes" \
    'kit/pilot/measure.sh' 'bash kit/pilot/ablate.sh' 'kit/docs/memory-layers.md')"
empty "21 hygiene: the command and the ritual list submodules, split the budget into kit and workspace, and compare with any *hygiene-date report" "$s21_bad"

s21_bad="$(s21_needs plugins/workspace/commands/register-audit.md 'kit/docs/documentation-register.md' \
    '`kit/` is left out' '.claude/skills/.kit-generated' 'Findings in the kit go upstream' 'team/people.md' '**Contact detail**'
    s21_needs docs/documentation-register.md '`kit/` (the kit, read in place' '.claude/skills/.kit-generated')"
empty "21 register audit: the rule is read from kit/, the kit and the bridge's copies are left out" "$s21_bad"

s21_qs="plugins/workspace/commands/quick-start.md"
s21_bad="$(s21_needs "$s21_qs" '`kit/plugins/workspace/bin/state.sh`' 'Fill `CLAUDE.md` §1–§3' 'kit/setup.sh link <slug>' \
    'kit/setup.sh skills' '.claude/skills/.kit-generated' 'bash kit/pilot/measure.sh --backfill 8' '`kit_import`')"
grep -qF '.kit-incoming' "$KIT/$s21_qs" && s21_bad+="$s21_qs: still names .kit-incoming"$'\n'
grep -qF 'Team Manifest' "$KIT/$s21_qs" && s21_bad+="$s21_qs: still names the Team Manifest"$'\n'
grep -qF 'Fill `AGENTS.md`' "$KIT/$s21_qs" && s21_bad+="$s21_qs: still fills AGENTS.md"$'\n'
# The resources offer comes once projects are listed: after item 9's /projects:new, before the roster.
awk '/^9\. \*Optional\* — \*\*Active projects/ { a = NR } /kit\/setup.sh link <slug>/ && !b { b = NR } /^10\. \*Optional\*/ { c = NR }
     END { exit !(a && b > a && c > b) }' "$KIT/$s21_qs" || s21_bad+="$s21_qs: the link offer is not with the project list"$'\n'
empty "21 quick-start: CLAUDE.md for AGENTS.md, the kit path, the bridge for Cowork, the link offer after projects, no .kit-incoming" "$s21_bad"

s21_bad="$(s21_needs pilot/README.md 'bash kit/pilot/measure.sh' 'bash kit/pilot/ablate.sh' 'kit/setup.sh new' \
    'CLAUDE.md AGENTS.md kit/CLAUDE.kit.md' 'A kit checkout is not a target')"
grep -q '__[A-Z_]*__' "$KIT/pilot/README.md" && s21_bad+="pilot/README.md: a render placeholder is left, but the page is read in place"$'\n'
empty "21 pilot README: the scripts run from kit/pilot/, and the page carries no render placeholders" "$s21_bad"

# --- measure.sh in a workspace whose kit is a submodule ----------------------------------------------
# A small kit (the marketplace name, CLAUDE.kit.md and the pilot scripts) and a workspace that starts in
# the 2.x shape (CLAUDE.md importing AGENTS.md) and moves to 3.0 (CLAUDE.md importing the kit).
s21_k="$s21_dir/kit-src" s21_w="$s21_dir/ws"
# s21_commit <repo> <days ago> <message>: everything, committed at noon that day.
s21_commit() {
    local when; when="$(days_ago "$2")T12:00:00"
    git -C "$1" add -A && GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git -C "$1" -c commit.gpgsign=false commit -q -m "$3"
}
mkdir -p "$s21_k/.claude-plugin" "$s21_k/pilot/lib"
git -C "$s21_k" init -q && git -C "$s21_k" symbolic-ref HEAD refs/heads/main
printf '{"name": "agentic-workspace", "plugins": []}\n' > "$s21_k/.claude-plugin/marketplace.json"
printf '# Agentic workspace kit — working standards\n\nOne.\n' > "$s21_k/CLAUDE.kit.md"
cp "$KIT/pilot/measure.sh" "$KIT/pilot/ablate.sh" "$s21_k/pilot/"
cp "$KIT/pilot/lib/"* "$s21_k/pilot/lib/"
s21_commit "$s21_k" 20 "Kit one"
s21_kit1="$(wc -c < "$s21_k/CLAUDE.kit.md")"

mkdir -p "$s21_w" && git -C "$s21_w" init -q && git -C "$s21_w" symbolic-ref HEAD refs/heads/main
printf '@AGENTS.md\n' > "$s21_w/CLAUDE.md"
printf '# Team Manifest\n\nThe 2.x standards, all in one file.\n' > "$s21_w/AGENTS.md"
s21_commit "$s21_w" 10 "The 2.x layout"
s21_b1=$(( $(wc -c < "$s21_w/CLAUDE.md") + $(wc -c < "$s21_w/AGENTS.md") ))

git -C "$s21_w" -c protocol.file.allow=always submodule add -q -b main "$s21_k" kit >/dev/null 2>&1
mkdir -p "$s21_w/docs" "$s21_w/.claude" "$s21_w/projects/alpha" "$s21_w/projects/_done/beta"
printf '%s\n' '@kit/CLAUDE.kit.md' 'Kit working standards: `kit/CLAUDE.kit.md`.' '' '# Test Team' '' \
    'More in @docs/extra.md, and ask sam@example.test.' 'Not an import: `@docs/not.md`, nor @~/.claude/notes.md or @docs/missing.md.' \
    > "$s21_w/CLAUDE.md"
printf '%s\n' '@kit/CLAUDE.kit.md' '' '# How this workspace is read' '' 'Also @docs/agents-only.md.' > "$s21_w/AGENTS.md"
printf '# Extra\n\nSee @nested.md.\n' > "$s21_w/docs/extra.md"
printf '# Nested\n\nBack to @extra.md, and @../CLAUDE.md.\n' > "$s21_w/docs/nested.md"
printf '# Not loaded\n' > "$s21_w/docs/not.md"
printf '# Only through AGENTS.md\n' > "$s21_w/docs/agents-only.md"
printf '%s\n' '# Project conventions' '' '- **Active:** `projects/<slug>/`' '- **Paused:** `projects/<slug>/`' \
    '- **Done:** `projects/_done/<slug>/`' > "$s21_w/.claude/projects.md"
printf '# Alpha\n\n## Current state\n\n- **State:** doing\n' > "$s21_w/projects/alpha/README.md"
printf '# Beta\n\n## Current state\n\n- **State:** done\n' > "$s21_w/projects/_done/beta/README.md"
printf '# Finished projects\n\n## Current state\n\n- **State:** doing\n' > "$s21_w/projects/_done/README.md"
s21_commit "$s21_w" 3 "The 3.0 layout"
s21_ws2=$(( $(wc -c < "$s21_w/CLAUDE.md") + $(wc -c < "$s21_w/AGENTS.md") + $(wc -c < "$s21_w/docs/extra.md") + $(wc -c < "$s21_w/docs/nested.md") ))
s21_b2=$(( s21_ws2 + s21_kit1 ))

# s21_col <csv text> <row 1..> <column>: a value looked up by header name.
s21_col() { awk -F, -v r="$2" -v name="$3" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == name) c = i; next }
                                             NR == r + 1 { print (c ? $c : "missing") }' <<<"$1"; }
s21_csv="$(cd "$s21_w" && bash kit/pilot/measure.sh --backfill 1 --out "$s21_dir/m.csv" 2>&1)"; s21_rc=$?
s21_got="$(s21_col "$s21_csv" 1 always_loaded_bytes) $(s21_col "$s21_csv" 2 always_loaded_bytes)"
[[ $s21_rc -eq 0 && "$s21_got" == "$s21_b1 $s21_b2" ]] \
    && ok "21 measure.sh from kit/pilot/: the 2.x row counts CLAUDE.md and AGENTS.md, the 3.0 row adds the kit's standards and every import once" \
    || ko "21 measure.sh from kit/pilot/: the 2.x row counts CLAUDE.md and AGENTS.md, the 3.0 row adds the kit's standards and every import once" \
        "rc=$s21_rc wanted '$s21_b1 $s21_b2', got '$s21_got'"$'\n'"$s21_csv"
s21_got="$(s21_col "$s21_csv" 2 projects_active),$(s21_col "$s21_csv" 2 projects_done)"
[[ "$s21_got" == "1,1" ]] && ok "21 measure.sh: projects/_done/<slug>/ counts as done, and projects/_done itself is reserved, not a project" \
    || ko "21 measure.sh: projects/_done/<slug>/ counts as done, and projects/_done itself is reserved, not a project" "active,done = $s21_got"

# The kit moves on, and the workspace has not committed the new pointer: the recorded commit counts.
printf '# Agentic workspace kit — working standards\n\nOne.\n\nTwo, a longer kit.\n' > "$s21_k/CLAUDE.kit.md"
s21_commit "$s21_k" 1 "Kit two"
s21_kit2="$(wc -c < "$s21_k/CLAUDE.kit.md")"
git -C "$s21_w/kit" -c protocol.file.allow=always fetch -q origin >/dev/null 2>&1 \
    && git -C "$s21_w/kit" checkout -q --detach origin/main >/dev/null 2>&1
s21_print() { (cd "$s21_w" && env "$@" bash kit/pilot/measure.sh --print 2>&1 | tail -n 1 | cut -d, -f2); }
s21_before="$(s21_print)"
s21_commit "$s21_w" 1 "Kit two"
s21_after="$(s21_print)"
[[ "$s21_before" == "$s21_b2" && "$s21_after" == "$(( s21_ws2 + s21_kit2 ))" ]] \
    && ok "21 measure.sh reads kit/CLAUDE.kit.md at the commit the workspace records, not the kit's working tree" \
    || ko "21 measure.sh reads kit/CLAUDE.kit.md at the commit the workspace records, not the kit's working tree" \
        "before commit: $s21_before (wanted $s21_b2); after: $s21_after (wanted $(( s21_ws2 + s21_kit2 )))"

# AGENTS.md is opaque by default: its size counts, its import is not followed. Once the kit's ledger
# records it as created by the engine, or with nothing opaque, it is read like any other file.
s21_ao="$(wc -c < "$s21_w/docs/agents-only.md")"
s21_opq="$(s21_print)" s21_none="$(s21_print AW_OPAQUE_PATHS=)"
printf '# Written by kit/install.sh.\nAGENTS.md\ttemplates/workspace/AGENTS.md\t%s\t%s\tcreated\n' "$(printf '0%.0s' {1..40})" "$(printf '1%.0s' {1..40})" \
    > "$s21_w/.claude/kit-templates.lock"
s21_led="$(s21_print)"
s21_want=$(( s21_ws2 + s21_kit2 ))
[[ "$s21_opq" == "$s21_want" && "$s21_none" == "$(( s21_want + s21_ao ))" && "$s21_led" == "$(( s21_want + s21_ao ))" ]] \
    && ok "21 measure.sh never reads an opaque AGENTS.md for imports, and does once the ledger says the engine created it" \
    || ko "21 measure.sh never reads an opaque AGENTS.md for imports, and does once the ledger says the engine created it" \
        "default $s21_opq (wanted $s21_want), AW_OPAQUE_PATHS= $s21_none, ledger $s21_led (both wanted $(( s21_want + s21_ao )))"

# The runner: beside measure.sh in kit/pilot/; for a copy of measure.sh elsewhere, the workspace's kit/.
mkdir -p "$s21_w/pilot/ablations" "$s21_dir/lone"
printf 'file: CLAUDE.md\nablate:\n  - "# Test Team"\n' > "$s21_w/pilot/ablations/x.md"
{ echo "date,ablation,arm,run,check,judge,input_tokens,output_tokens,cache_read_tokens,duration_ms,cost_usd,turns,status"
  for s21_i in 1 2 3; do printf '%s,x,with,%s,1,,100,50,0,1000,0.01,2,ok\n' "$(days_ago 0)" "$s21_i"; done
  for s21_i in 1 2 3; do printf '%s,x,without,%s,0,,100,50,0,1000,0.01,2,ok\n' "$(days_ago 0)" "$s21_i"; done
} > "$s21_w/pilot/ablation-results.csv"
cp "$KIT/pilot/measure.sh" "$s21_dir/lone/measure.sh"
s21_a="$(cd "$s21_w" && bash kit/pilot/measure.sh --print 2>/dev/null | tail -n 1 | cut -d, -f18-20)"
s21_l="$(bash "$s21_dir/lone/measure.sh" --target "$s21_w" --print 2>/dev/null | tail -n 1 | cut -d, -f18-20)"
[[ "$s21_a" == "1,1,0" && "$s21_l" == "1,1,0" ]] \
    && ok "21 measure.sh finds the runner beside it in kit/pilot/, and a copy elsewhere finds it in the workspace's kit/" \
    || ko "21 measure.sh finds the runner beside it in kit/pilot/, and a copy elsewhere finds it in the workspace's kit/" "kit/pilot: $s21_a, lone copy: $s21_l"

# --- ablate.sh: the workspace is the default target, a kit checkout is not a target ------------------
s21_rep="$(cd "$s21_dir" && bash "$s21_w/kit/pilot/ablate.sh" --report 2>&1)"; s21_rc=$?
[[ $s21_rc -eq 0 ]] && grep -qE '^\| x \|' <<<"$s21_rep" \
    && ok "21 ablate.sh run from kit/pilot/ with no --target reports on the workspace around the kit" \
    || ko "21 ablate.sh run from kit/pilot/ with no --target reports on the workspace around the kit" "rc=$s21_rc"$'\n'"$s21_rep"
s21_rep="$(bash "$s21_w/kit/pilot/ablate.sh" --target "$s21_w/kit" --report 2>&1)"; s21_rc=$?
[[ $s21_rc -eq 2 ]] && grep -qF 'is not a target' <<<"$s21_rep" \
    && ok "21 ablate.sh refuses a kit checkout named as the target" || ko "21 ablate.sh refuses a kit checkout named as the target" "rc=$s21_rc $s21_rep"
git clone -q "$s21_k" "$s21_dir/standalone" >/dev/null 2>&1
s21_rep="$(bash "$s21_dir/standalone/pilot/ablate.sh" --report 2>&1)"; s21_rc=$?
[[ $s21_rc -eq 2 ]] && grep -qF -- '--target' <<<"$s21_rep" \
    && ok "21 ablate.sh in a kit clone with no workspace around it stops and asks for --target" \
    || ko "21 ablate.sh in a kit clone with no workspace around it stops and asks for --target" "rc=$s21_rc $s21_rep"
s21_rep="$(bash "$s21_dir/standalone/pilot/ablate.sh" --outcomes "$s21_w/pilot/ablation-results.csv" 2>&1)"; s21_rc=$?
[[ $s21_rc -eq 0 && "$(cut -f1,3 <<<"$s21_rep")" == "x	discriminates" ]] \
    && ok "21 ablate.sh --outcomes reads only its file, so it runs from a kit clone too" \
    || ko "21 ablate.sh --outcomes reads only its file, so it runs from a kit clone too" "rc=$s21_rc $s21_rep"
# A copy kept inside a team's own repository (a 2.x install) still tests that repository by default.
s21_two="$s21_dir/two"
mkdir -p "$s21_two/pilot/lib" "$s21_two/pilot/ablations" && git -C "$s21_two" init -q
cp "$KIT/pilot/ablate.sh" "$s21_two/pilot/" && cp "$KIT/pilot/lib/"* "$s21_two/pilot/lib/"
cp "$s21_w/pilot/ablations/x.md" "$s21_two/pilot/ablations/" && cp "$s21_w/pilot/ablation-results.csv" "$s21_two/pilot/"
printf '# Test Team\n' > "$s21_two/CLAUDE.md"
s21_commit "$s21_two" 0 "A 2.x repository with its own runner"
s21_rep="$(bash "$s21_two/pilot/ablate.sh" --report 2>&1)"; s21_rc=$?
[[ $s21_rc -eq 0 ]] && grep -qE '^\| x \|' <<<"$s21_rep" \
    && ok "21 ablate.sh kept in a repository that is not a kit still defaults to that repository" \
    || ko "21 ablate.sh kept in a repository that is not a kit still defaults to that repository" "rc=$s21_rc $s21_rep"

# --- The files C9 owns: no machine paths, and the scripts lint clean ---------------------------------
s21_owned="rituals/closeout.md rituals/weekly-hygiene.md plugins/workspace/commands/hygiene.md
plugins/workspace/commands/register-audit.md plugins/closeout/hooks/lib/config.sh plugins/closeout/README.md
plugins/closeout/docs/DESIGN.md pilot/measure.sh pilot/ablate.sh pilot/README.md docs/documentation-register.md
plugins/closeout/commands/closeout.md plugins/workspace/commands/quick-start.md tests/sections/21-rituals.sh"
for s21_f in $s21_owned; do
    grep -nE '/(Users|home)/' "$KIT/$s21_f" | sed "s#^#$s21_f:#" || true
done > "$s21_dir/paths.txt"
empty "21 no home-folder machine path in the rituals, commands, closeout docs and pilot files" "$(cat "$s21_dir/paths.txt")"
if command -v shellcheck >/dev/null 2>&1; then
    check "21 shellcheck -x is clean on pilot/measure.sh, pilot/ablate.sh, the closeout config and this section" \
        bash -c 'cd "$1" && shellcheck -x pilot/measure.sh pilot/ablate.sh plugins/closeout/hooks/lib/config.sh && shellcheck -x -s bash tests/sections/21-rituals.sh' _ "$KIT"
else
    skp "21 shellcheck not on PATH; the pilot scripts, the closeout config and this section not linted"
fi

# Where the team is one person, quick-start offers to remove the review files. It names the two files and
# never the folder, because .github/workflows/stay-private.yml lives there too.
s21_bad="$(s21_needs "$s21_qs" '`.github/CODEOWNERS` and' '`.github/pull_request_template.md`, on their yes' \
    '`.github/workflows/stay-private.yml` lives there too' '(never `.github/workflows/`)')"
grep -qF 'remove `.github/`' "$KIT/$s21_qs" && s21_bad+="$s21_qs: offers to remove the whole .github/ folder"$'\n'
grep -qF '`.github/` for one person' "$KIT/$s21_qs" && s21_bad+="$s21_qs: lists .github/ as left over"$'\n'
empty "21 quick-start: the one-person offer names CODEOWNERS and the PR template, never .github/ or its workflow" "$s21_bad"

# A person who installed the standalone closeout for their user must not get it beside the kit's copy in a
# workspace: the workspace's settings, which outrank the user's, turn it off.
s21_v="$(jq -r '.enabledPlugins["closeout@closeout-marketplace"]' "$KIT/templates/workspace/settings.json" 2>/dev/null)"
[[ "$s21_v" == false ]] && ok "21 the workspace settings turn the standalone closeout off, so the kit's copy runs alone" \
    || ko "21 the workspace settings turn the standalone closeout off, so the kit's copy runs alone" "closeout@closeout-marketplace: ${s21_v:-absent}"
