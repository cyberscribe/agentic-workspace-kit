# shellcheck shell=bash
# The prelude in tests/run.sh defines st_bash, kitsrc_ok and the rest; checks are written "cond && ok || ko"
# as in run.sh, and the stubs written below are single-quoted on purpose.
# shellcheck disable=SC2154,SC2015,SC2016
# Section 15, part 2 of 3: the 2.x stop, update, and the attended runs. The helpers are in tests/sections/lib/15-setup.sh.
# shellcheck source=tests/sections/lib/15-setup.sh
. "$KIT/tests/sections/lib/15-setup.sh"
echo
echo "15 · Setup: the ten stages, new, adopt, the modes, update, developer mode and the template repository (2 of 3)"

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
        # --yes answers the offers only: attended, the migration is still asked, and Enter keeps its n.
        (cd "$SCRATCH" && printf '\n' | AW_KIT_URL="$KITSRC" AW_WIZARD_NONINTERACTIVE=0 "$st_bash" "$s15_setup" update --target "$s15_x" --yes \
            >"$SCRATCH/s15-2x-yes.log" 2>&1)
        st_tree "$s15_x" >"$SCRATCH/s15-2x-after-yes.txt"
        # A piped answer shows no prompt (read -p prints one only to a terminal), so the tree is the check.
        s15_diff="$(diff "$SCRATCH/s15-2x-before.txt" "$SCRATCH/s15-2x-after-yes.txt" 2>&1)"
        grep -q '^This workspace has the 2.x layout; the migration moves it to 3.0\.$' "$SCRATCH/s15-2x-yes.log" && [[ -z "$s15_diff" ]] \
            && ok "15 update --yes on a 2.x workspace, attended: the migration keeps its n default and the workspace is as it was" \
            || ko "15 update --yes on a 2.x workspace, attended: the migration keeps its n default and the workspace is as it was" "$s15_diff $(tail -n 4 "$SCRATCH/s15-2x-yes.log")"
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
    grep '^  git add ' "$SCRATCH/s15-update.log" | grep_all ' CLAUDE\.md' \
        || s15_bad+="the workspace has no commit yet, and the git add line leaves out CLAUDE.md (a partial first commit)"$'\n'
    [[ $s15_rc -eq 0 ]] || s15_bad+="status $s15_rc"$'\n'
    empty "15 update: the kit advances, the new kit's update.sh takes over, the CHANGELOG since the old version is printed, one commit named" "$s15_bad"
    if [[ $s15_engine -eq 1 ]]; then
        s15_bad=""
        grep '^  git add ' "$SCRATCH/s15-update.log" | grep_all ' \.claude/settings\.json' || s15_bad+="the git add line does not name .claude/settings.json, which the engine merged"$'\n'
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
    # The kit on a side branch, with a commit of its own that changes a template, while the tracked
    # branch moves on upstream: update leaves the branch where it is, runs the offers against the kit as
    # it stands from the commit the workspace records, and says so. --advance moves it as before.
    if [[ $s15_engine -eq 1 ]]; then
        s15_sb="$SCRATCH/s15-update-side"
        cp -R "$s15_u" "$s15_sb"
        s15_rec="$(git -C "$s15_sb" ls-files -s -- kit | awk '{ print $2 }')"
        git -C "$s15_sb/kit" checkout -q -b trial
        printf '\nA line the trial branch adds.\n' >> "$s15_sb/kit/templates/workspace/closeout.md"
        git -C "$s15_sb/kit" add -A && git -C "$s15_sb/kit" -c commit.gpgsign=false commit -q -m "Trial work"
        s15_trial="$(git -C "$s15_sb/kit" rev-parse HEAD)"
        printf 'upstream\n' > "$s15_k2/upstream.md"
        git -C "$s15_k2" add -A && git -C "$s15_k2" -c commit.gpgsign=false commit -q -m "Upstream moves on"
        s15_up="$(git -C "$s15_k2" rev-parse HEAD)"
        (cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_sb/kit/setup.sh" update </dev/null >"$s15_sb.log" 2>&1); s15_rc=$?
        s15_bad=""
        [[ $s15_rc -eq 0 ]] || s15_bad+="status $s15_rc"$'\n'
        [[ "$(git -C "$s15_sb/kit" rev-parse HEAD)" == "$s15_trial" ]] || s15_bad+="the kit moved off the trial branch's commit"$'\n'
        [[ "$(git -C "$s15_sb/kit" symbolic-ref -q --short HEAD)" == trial ]] || s15_bad+="the kit is no longer on the branch trial"$'\n'
        [[ "$(git -C "$s15_sb/kit" rev-list --count "$s15_rec..trial")" == 2 ]] || s15_bad+="the trial branch's history changed: $(git -C "$s15_sb/kit" log --oneline "$s15_rec..trial" | paste -sd'|' -)"$'\n'
        grep -q '^kit/ is on the branch trial, not main, the branch \.gitmodules tracks\. It is not advanced:' "$s15_sb.log" || s15_bad+="it does not say the kit is left on its branch"$'\n'
        grep -qF -- "--after-advance --old $s15_rec" "$s15_sb.log" || s15_bad+="it does not name the after-advance run and the --old it used ($s15_rec)"$'\n'
        grep -q 'changed   \.claude/closeout\.md' "$s15_sb.log" || s15_bad+="the template offers did not run"$'\n'
        grep -q 'kit/setup.sh update --advance' "$s15_sb.log" || s15_bad+="it does not name --advance"$'\n'
        empty "15 update with kit/ on a side branch: not advanced, the branch's commits untouched, the template offers run, and it names what it ran" "$s15_bad"
        (cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_sb/kit/setup.sh" update --advance </dev/null >"$s15_sb-advance.log" 2>&1)
        git -C "$s15_sb/kit" merge-base --is-ancestor "$s15_up" HEAD 2>/dev/null \
            && ok "15 update --advance with kit/ on a side branch: advanced as before" \
            || ko "15 update --advance with kit/ on a side branch: advanced as before" "$(head -n 12 "$s15_sb-advance.log")"
    else
        skp "15 update with kit/ on a side branch — needs ${s15_why:-a ledger in the fixture}"
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
                && grep '^  git add ' "$s15_c.log" | grep_all ' \.claude/closeout\.md' \
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
                && grep '^  git add ' "$s15_c.log" | grep_all ' \.gitignore' \
                && ok "15 update, attended: missing .gitignore lines offered as one diff; y adds them and names .gitignore in the commit" \
                || ko "15 update, attended: missing .gitignore lines offered as one diff; y adds them and names .gitignore in the commit" "$(tail -n 14 "$s15_c.log")"
        else
            ! grep -q -x '\.DS_Store' "$s15_c/.gitignore" \
                && [[ "$(awk -F '\t' '$1 == "!declined" && $2 == ".gitignore" { print $3 }' "$s15_c/.claude/kit-templates.lock" | LC_ALL=C sort | paste -sd' ' -)" == ".DS_Store _delete/" ]] \
                && ok "15 update, attended: n records each missing .gitignore line as declined, and adds none" \
                || ko "15 update, attended: n records each missing .gitignore line as declined, and adds none" "$(grep '^!declined' "$s15_c/.claude/kit-templates.lock")"
        fi
    done

    # Hunk by hunk. CLAUDE.md is recorded as made with the owner still a stand-in, as a workspace whose
    # owner was filled in later is, and the kit also rewords a line ten lines above the owner's row. The
    # diff then holds two hunks: the owner's row, which the file already has, and the wording, which fits.
    s15_c="$SCRATCH/s15-update-hunks"
    cp -R "$s15_u" "$s15_c"
    awk -F '\t' -v OFS='\t' '$1 == "CLAUDE.md" { print $0, "owner=<standards owner>"; next } { print }' \
        "$s15_c/.claude/kit-templates.lock" >"$SCRATCH/s15-lock" && cat "$SCRATCH/s15-lock" >"$s15_c/.claude/kit-templates.lock"
    sed 's/It is a bounded budget, not a folder/It is a bounded budget, never a folder/' \
        "$s15_c/kit/templates/workspace/CLAUDE.md" >"$SCRATCH/s15-tpl" && cat "$SCRATCH/s15-tpl" >"$s15_c/kit/templates/workspace/CLAUDE.md"
    (cd "$SCRATCH" && printf 'y\ny\nn\n' | AW_WIZARD_NONINTERACTIVE=0 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch >"$s15_c.log" 2>&1)
    s15_bad=""
    grep -q 'never a folder' "$s15_c/CLAUDE.md" || s15_bad+="the wording change did not land"$'\n'
    grep -q '^| \*\*Standards owner\*\* | Sam Example — ' "$s15_c/CLAUDE.md" || s15_bad+="the owner's row lost its value"$'\n'
    grep -q '<standards owner>' "$s15_c/CLAUDE.md" && s15_bad+="the stand-in came back"$'\n'
    [[ "$(awk -F '\t' '$1 == "CLAUDE.md" { print $5 }' "$s15_c/.claude/kit-templates.lock")" == accepted ]] || s15_bad+="CLAUDE.md is not recorded accepted"$'\n'
    grep -q '^  applied                CLAUDE\.md$' "$s15_c.log" || s15_bad+="the summary does not name CLAUDE.md as applied"$'\n'
    grep -q 'does not fit CLAUDE\.md' "$s15_c.log" && s15_bad+="a hunk of CLAUDE.md was left over"$'\n'
    empty "15 update, hunk by hunk: a filled placeholder counts as there, the kit's wording change elsewhere lands, the file is recorded accepted" "$s15_bad"

    # A hunk that fits nowhere: the line the second commit appends to closeout.md follows a last line the
    # team has reworded, so it neither applies nor is there. It is printed, and the file is not recorded.
    s15_c="$SCRATCH/s15-update-conflict"
    cp -R "$s15_u" "$s15_c"
    sed '$s/$/ (reworded by the team)/' "$s15_c/.claude/closeout.md" >"$SCRATCH/s15-co" && cat "$SCRATCH/s15-co" >"$s15_c/.claude/closeout.md"
    cp "$s15_c/.claude/closeout.md" "$SCRATCH/s15-co-before"
    # Nothing fits, so there is no question to apply: the first answer goes to "stop offering", and an n
    # there leaves the ledger as it was, where an apply question answered n would have recorded skipped.
    cp -R "$s15_c" "$s15_c-y"
    (cd "$SCRATCH" && printf 'n\nn\n' | AW_WIZARD_NONINTERACTIVE=0 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch >"$s15_c.log" 2>&1)
    s15_bad=""
    cmp -s "$s15_c/.claude/closeout.md" "$SCRATCH/s15-co-before" || s15_bad+=".claude/closeout.md changed"$'\n'
    [[ "$(awk -F '\t' '$1 == ".claude/closeout.md"' "$s15_c/.claude/kit-templates.lock")" == "$s15_lock_before" ]] \
        || s15_bad+="the ledger entry for .claude/closeout.md changed (an apply question was asked and answered?)"$'\n'
    grep -qxF '  .claude/closeout.md: none of the 1 changes fits as it is; 1 need merging by hand.' "$s15_c.log" || s15_bad+="the file and the count do not come first"$'\n'
    grep -q 'This change does not fit \.claude/closeout\.md as it is now; merge it by hand:' "$s15_c.log" || s15_bad+="the left-over hunk is not named"$'\n'
    grep -q '^    +A line the second kit commit adds\.$' "$s15_c.log" || s15_bad+="the lines it wanted are not printed"$'\n'
    grep -qF "    Merge the kit's latest change to .claude/closeout.md into my copy, keeping my own edits. kit/install.sh --template-diff .claude/closeout.md --target . prints the change." "$s15_c.log" \
        || s15_bad+="no ready-made prompt for the assistant"$'\n'
    grep -q '^  left for hand merging  \.claude/closeout\.md (1 of 1 changes)$' "$s15_c.log" || s15_bad+="the summary does not list it for hand merging"$'\n'
    empty "15 update, hunk by hunk: nothing fits, so no apply question; the hunk and a prompt for the assistant are printed, and n leaves the ledger" "$s15_bad"
    # The prompt's own command prints the change from the workspace's root.
    (cd "$s15_c" && "$st_bash" kit/install.sh --template-diff .claude/closeout.md --target . 2>&1) | grep_all '^+A line the second kit commit adds\.$' \
        && ok "15 update: the hand-merge prompt's command prints the change, run from the workspace's root" \
        || ko "15 update: the hand-merge prompt's command prints the change, run from the workspace's root"
    # y once merged by hand: recorded, and the next update does not offer it.
    s15_c="$s15_c-y"
    (cd "$SCRATCH" && printf 'y\nn\n' | AW_WIZARD_NONINTERACTIVE=0 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch >"$s15_c.log" 2>&1)
    (cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch </dev/null >"$s15_c-2.log" 2>&1)
    s15_bad=""
    cmp -s "$s15_c/.claude/closeout.md" "$SCRATCH/s15-co-before" || s15_bad+=".claude/closeout.md changed"$'\n'
    [[ "$(awk -F '\t' '$1 == ".claude/closeout.md" { print $5 }' "$s15_c/.claude/kit-templates.lock")" == accepted ]] || s15_bad+="not recorded accepted"$'\n'
    grep -q 'changed   \.claude/closeout\.md' "$s15_c-2.log" && s15_bad+="offered again on the next update"$'\n'
    empty "15 update, hunk by hunk: y to stop offering a hand merge records the file, and the next update does not offer it" "$s15_bad"

    # Some fit and some do not: the kit also rewords a line near the top of closeout.md, which fits,
    # while the appended line still follows a reworded last line. The question names the count, the
    # one that fits lands, the other is printed with the prompt, and the file stays offered.
    s15_sub() { # <file> <old> <new>: an exact replacement, which fails when <old> is not in the file
        python3 - "$@" <<'PYSUB'
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit("not found in " + p + ": " + old)
open(p, "w").write(s.replace(old, new, 1))
PYSUB
    }
    s15_c="$SCRATCH/s15-update-some"
    cp -R "$s15_u" "$s15_c"
    sed '$s/$/ (reworded by the team)/' "$s15_c/.claude/closeout.md" >"$SCRATCH/s15-co" && cat "$SCRATCH/s15-co" >"$s15_c/.claude/closeout.md"
    s15_sub "$s15_c/kit/templates/workspace/closeout.md" 'names the file rather than restating' 'names the file instead of restating'
    (cd "$SCRATCH" && printf 'y\nn\n' | AW_WIZARD_NONINTERACTIVE=0 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch >"$s15_c.log" 2>&1)
    s15_bad=""
    grep -q '^  1 of the 2 changes fit \.claude/closeout\.md as it is now\.$' "$s15_c.log" || s15_bad+="the count of changes that fit is not given"$'\n'
    grep -q 'names the file instead of restating' "$s15_c/.claude/closeout.md" || s15_bad+="the change that fits did not land"$'\n'
    grep -q '^A line the second kit commit adds\.$' "$s15_c/.claude/closeout.md" && s15_bad+="the change that does not fit was forced in"$'\n'
    grep -q "^    Merge the kit's latest change to \.claude/closeout\.md" "$s15_c.log" || s15_bad+="no ready-made prompt"$'\n'
    grep -q '^  applied                \.claude/closeout\.md (1 of 2 changes)$' "$s15_c.log" || s15_bad+="the summary does not list the one applied"$'\n'
    grep -q '^  left for hand merging  \.claude/closeout\.md (1 of 2 changes)$' "$s15_c.log" || s15_bad+="the summary does not list the one left"$'\n'
    [[ "$(awk -F '\t' '$1 == ".claude/closeout.md"' "$s15_c/.claude/kit-templates.lock")" == "$s15_lock_before" ]] \
        || s15_bad+="the ledger entry changed, so the file would not be offered again"$'\n'
    grep '^  git add ' "$s15_c.log" | grep_all ' \.claude/closeout\.md' || s15_bad+="the commit does not name .claude/closeout.md"$'\n'
    empty "15 update, hunk by hunk: some fit — the question gives the count, those land, the rest is printed with a prompt and stays offered" "$s15_bad"

    # The three shapes a customised workspace showed on a real update, none of which needs a merge:
    # closeout.md's edited passage rewritten by the team (gone), projects.md's rule restated in the
    # team's own sentence (gone), and workspace-map.md with the kit's new row already in place beside a
    # row of its own (merged) and a tree line rewritten (gone). No apply question; Enter stops the offer.
    s15_c="$SCRATCH/s15-update-own"
    cp -R "$s15_u" "$s15_c"
    s15_t="$s15_c/kit/templates/workspace" s15_bad=""
    printf '\nA line the second kit commit adds.\n' >> "$s15_c/.claude/closeout.md"
    s15_sub "$s15_t/closeout.md" 'names the file rather than restating' 'names the file instead of restating' || s15_bad+="fixture: closeout template"$'\n'
    s15_sub "$s15_c/.claude/closeout.md" 'This section names the file rather than restating the table. A second copy of a taxonomy is how two' \
        'We point at the taxonomy file and never copy its table, since a second copy of a taxonomy is how two' || s15_bad+="fixture: closeout"$'\n'
    s15_sub "$s15_t/projects.md" '- **Folder prefix:** none. The folder name is the slug.' '- **Folder prefix:** none; the folder is named by its slug.' || s15_bad+="fixture: projects template"$'\n'
    s15_sub "$s15_c/.claude/projects.md" '- **Folder prefix:** none. The folder name is the slug.' \
        '- **Folder prefix:** none, so a folder is named by its slug alone, and older folders keep theirs.' || s15_bad+="fixture: projects"$'\n'
    s15_sub "$s15_t/workspace-map.md" '| Organisations and topics |' '| Organisations, clients and topics |' || s15_bad+="fixture: map template row"$'\n'
    s15_sub "$s15_c/docs/workspace-map.md" '| Organisations and topics |' '| Organisations, clients and topics |' || s15_bad+="fixture: map row"$'\n'
    s15_sub "$s15_c/docs/workspace-map.md" '| People |' '| People, one file each |' || s15_bad+="fixture: map own row"$'\n'
    s15_sub "$s15_t/workspace-map.md" 'done when, the Current state block, open questions' 'done when, the Current state block, open questions and risks' || s15_bad+="fixture: map template tree"$'\n'
    s15_sub "$s15_c/docs/workspace-map.md" '← what, why, done when, the Current state block, open questions' '← the brief: outcome, done when, where it stands' || s15_bad+="fixture: map tree"$'\n'
    for s15_f in .claude/closeout.md .claude/projects.md docs/workspace-map.md; do cp "$s15_c/$s15_f" "$SCRATCH/s15-own-$(basename "$s15_f")"; done
    (cd "$SCRATCH" && printf '\n\n\nn\n' | AW_WIZARD_NONINTERACTIVE=0 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch >"$s15_c.log" 2>&1)
    (cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch </dev/null >"$s15_c-2.log" 2>&1)
    for s15_f in .claude/closeout.md .claude/projects.md docs/workspace-map.md; do
        cmp -s "$s15_c/$s15_f" "$SCRATCH/s15-own-$(basename "$s15_f")" || s15_bad+="$s15_f changed"$'\n'
        [[ "$(awk -F '\t' -v f="$s15_f" '$1 == f { print $5 }' "$s15_c/.claude/kit-templates.lock")" == accepted ]] || s15_bad+="$s15_f not recorded accepted (an apply question took the answer?)"$'\n'
        grep -q "^  in your own words      ${s15_f//./\\.}\$" "$s15_c.log" || s15_bad+="$s15_f not listed as in your own words"$'\n'
        grep -q "changed   ${s15_f//./\\.}" "$s15_c-2.log" && s15_bad+="$s15_f offered again on the next update"$'\n'
    done
    grep -q 'does not fit' "$s15_c.log" && s15_bad+="a hunk was put up for hand merging"$'\n'
    for s15_l in '  .claude/closeout.md: none of the 2 changes needs applying. 1 on lines you have rewritten; 1 already there.' \
        '  .claude/projects.md: none of the 1 changes needs applying. 1 on lines you have rewritten.' \
        '  docs/workspace-map.md: none of the 2 changes needs applying. 1 already in your own words; 1 on lines you have rewritten.'; do
        grep -qxF -- "$s15_l" "$s15_c.log" || s15_bad+="no line: $s15_l"$'\n'
    done
    empty "15 update: changes already made in the team's own words, or to passages it rewrote, get no apply question; Enter stops the offer" "$s15_bad"

    # --yes with no terminal: the template change and the .gitignore lines are applied without a prompt.
    s15_c="$SCRATCH/s15-update-yes"
    cp -R "$s15_u" "$s15_c"
    grep -v -x -e '\.DS_Store' "$s15_c/.gitignore" >"$SCRATCH/s15-gi" && cat "$SCRATCH/s15-gi" >"$s15_c/.gitignore"
    (cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch --yes </dev/null >"$s15_c.log" 2>&1)
    s15_bad=""
    grep -q '^A line the second kit commit adds\.$' "$s15_c/.claude/closeout.md" || s15_bad+="the template change was not applied"$'\n'
    [[ "$(awk -F '\t' '$1 == ".claude/closeout.md" { print $5 }' "$s15_c/.claude/kit-templates.lock")" == accepted ]] || s15_bad+="not recorded accepted"$'\n'
    grep -q -x '\.DS_Store' "$s15_c/.gitignore" || s15_bad+="the .gitignore line was not added"$'\n'
    grep -q '(y/n)' "$s15_c.log" && s15_bad+="a question was asked"$'\n'
    grep -q '^+A line the second kit commit adds\.$' "$s15_c.log" || s15_bad+="the diff was not printed"$'\n'
    grep -q '^  applied                \.claude/closeout\.md$' "$s15_c.log" && grep -q '^  applied                \.gitignore$' "$s15_c.log" \
        || s15_bad+="the summary does not list both as applied"$'\n'
    empty "15 update --yes: the template change and .gitignore lines are applied without a question, the diffs printed, both listed" "$s15_bad"

    # The macOS Icon line after an editor that drops carriage returns has saved .gitignore: the line is
    # all visible characters, so it comes through unchanged, still ignores Icon<CR>, and is not offered
    # again.
    s15_c="$SCRATCH/s15-update-icon"
    cp -R "$s15_u" "$s15_c"
    tr -d '\r' <"$s15_c/.gitignore" >"$SCRATCH/s15-gi" && cat "$SCRATCH/s15-gi" >"$s15_c/.gitignore"
    (cd "$SCRATCH" && AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s15_c/kit/setup.sh" update --no-fetch </dev/null >"$s15_c.log" 2>&1)
    s15_bad=""
    git -C "$s15_c" check-ignore -q --no-index -- "$(printf 'Icon\r')" || s15_bad+="Icon<CR> is not ignored"$'\n'
    git -C "$s15_c" check-ignore -q --no-index -- Icons && s15_bad+="Icons is ignored"$'\n'
    grep -q "Lines the kit's .gitignore template has" "$s15_c.log" && s15_bad+="the .gitignore lines are offered again: $(grep -n '^+' "$s15_c.log" | head -n 3)"$'\n'
    empty "15 update: the macOS Icon line survives an editor that drops carriage returns, and is not offered again" "$s15_bad"
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
    mkws_copy "$s15_ap" >/dev/null 2>&1
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
    mkws_copy "$s15_ap2" >/dev/null 2>&1
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
# update at a terminal, with a CHANGELOG change inside one version: the diff is printed straight to the
# terminal. A pager there would take the answers meant for the template questions after it.
if [[ ${s15_engine:-0} -eq 1 ]]; then
    s15_pg="$SCRATCH/s15-update-pager"
    cp -R "$s15_u" "$s15_pg"
    s15_rec="$(git -C "$s15_pg/kit" rev-parse HEAD)"
    printf '%s\n' '#!/bin/sh' ": >\"$SCRATCH/s15-pager-ran\"" 'cat' >"$SCRATCH/s15-pager"; chmod +x "$SCRATCH/s15-pager"
    sed 's/^A second commit, for the update test in section 15\.$/A second commit, reworded within 9.9.9./' \
        "$s15_pg/kit/CHANGELOG.md" >"$SCRATCH/s15-cl" && cat "$SCRATCH/s15-cl" >"$s15_pg/kit/CHANGELOG.md"
    git -C "$s15_pg/kit" -c commit.gpgsign=false commit -q -am "Reword within 9.9.9"
    rm -f "$SCRATCH/s15-pager-ran"
    (cd "$SCRATCH" && env -u AW_WIZARD_NONINTERACTIVE GIT_PAGER="$SCRATCH/s15-pager" PAGER="$SCRATCH/s15-pager" \
        python3 "$SCRATCH/s15-pty.py" "$s15_pg.log" '\(y/n\) \[[yn]\]: $=>' 'Press Enter[^\n]*$=>' -- \
        "$st_bash" "$s15_pg/kit/lib/setup/update.sh" --target "$s15_pg" --after-advance --old "$s15_rec" >/dev/null 2>&1); s15_rc=$?
    if [[ $s15_rc -eq 77 ]]; then
        skp "15 update at a terminal: the CHANGELOG diff is not paged — no pseudo-terminal can be opened here"
    else
        [[ ! -e "$SCRATCH/s15-pager-ran" ]] && grep -q '^+A second commit, reworded within 9\.9\.9\.$' "$s15_pg.log" \
            && ok "15 update at a terminal: the CHANGELOG diff within one version is printed, not paged" \
            || ko "15 update at a terminal: the CHANGELOG diff within one version is printed, not paged" "pager ran: $([[ -e "$SCRATCH/s15-pager-ran" ]] && echo yes || echo no); $(head -n 12 "$s15_pg.log")"
    fi
else
    skp "15 update at a terminal: the CHANGELOG diff is not paged — needs ${s15_why:-the update fixture above}"
fi

# update at a terminal, on a workspace whose glossary holds its terms (from before the vocabulary split):
# the move to memory/terms.md is offered, a no leaves the file as it is, and a yes moves it and adds the
# plain-words glossary.
if [[ ${s15_engine:-0} -eq 1 ]]; then
    s15_vt=""
    for s15_ans in n y; do
        s15_vw="$SCRATCH/s15-vocab-$s15_ans"
        cp -R "$s15_u" "$s15_vw"
        printf '# Glossary\n\n| Term | Meaning |\n|---|---|\n| QBR | quarterly business review |\n' > "$s15_vw/memory/glossary.md"
        rm -f "$s15_vw/memory/terms.md"
        s15_oh="$(git hash-object --no-filters --stdin < "$s15_vw/kit/templates/workspace/glossary.md")"
        awk -F '\t' -v h="$s15_oh" 'BEGIN { OFS = "\t" } $1 == "memory/terms.md" { next } $1 == "memory/glossary.md" { $2 = "templates/workspace/glossary.md"; $4 = h } { print }' \
            "$s15_vw/.claude/kit-templates.lock" > "$SCRATCH/s15-vocab.lock" && cat "$SCRATCH/s15-vocab.lock" > "$s15_vw/.claude/kit-templates.lock"
        s15_rec="$(git -C "$s15_vw/kit" rev-parse HEAD)"
        (cd "$SCRATCH" && env -u AW_WIZARD_NONINTERACTIVE GIT_PAGER=cat python3 "$SCRATCH/s15-pty.py" "$s15_vw.log" \
            "Move memory/glossary\\.md to memory/terms\\.md\\? \\(y/n\\) \\[n\\]: \$=>$s15_ans" \
            '\(y/n\) \[[yn]\]: $=>' 'Press Enter[^\n]*$=>' -- \
            "$st_bash" "$s15_vw/kit/lib/setup/update.sh" --target "$s15_vw" --after-advance --old "$s15_rec" >/dev/null 2>&1); s15_rc=$?
        [[ $s15_rc -eq 77 ]] && { s15_vt=skip; break; }
        grep -qF "memory/glossary.md holds this workspace's terms." "$s15_vw.log" || s15_vt+="$s15_ans: the move is not offered"$'\n'
        if [[ $s15_ans == n ]]; then
            grep -q 'QBR' "$s15_vw/memory/glossary.md" && [[ ! -e "$s15_vw/memory/terms.md" ]] || s15_vt+="n: the files changed"$'\n'
        else
            grep -q 'QBR' "$s15_vw/memory/terms.md" 2>/dev/null && grep -q 'Plain words' "$s15_vw/memory/glossary.md" 2>/dev/null \
                || s15_vt+="y: not moved, or no plain-words glossary: $(tail -n 20 "$s15_vw.log")"$'\n'
        fi
    done
    if [[ "$s15_vt" == skip ]]; then
        skp "15 update at a terminal: the vocabulary move is offered — no pseudo-terminal can be opened here"
    else
        empty "15 update at a terminal: a glossary holding the terms is offered the move to memory/terms.md; no leaves it, yes moves it and adds the plain-words glossary" "$s15_vt"
    fi
else
    skp "15 update at a terminal: the vocabulary move is offered — needs ${s15_why:-the update fixture above}"
fi
