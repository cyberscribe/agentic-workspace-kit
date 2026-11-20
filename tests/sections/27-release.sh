# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh (SC2154); checks are "cond && ok || ko"
# (SC2015); single-quoted strings hold literal dollar signs for the stub (SC2016).
# shellcheck disable=SC2154,SC2015,SC2016
# Section 27: the release script (scripts/release.sh). It takes the version and reads the rest from
# <notes>/<version>/; the tag's subject is notes.md's first line; a dry run changes nothing; and it keeps
# its refusals: a red check, and a merge commit that does not hold exactly the release tree. Run against
# a fixture repository with a local origin and a stub gh, so nothing reaches GitHub.
# Everything here is prefixed s27_, since the sections share one shell.

echo
echo "27 · The release script: the version in, the rest from the notes folder"

s27="$SCRATCH/s27"
s27_r="$s27/kit" s27_o="$s27/origin.git" s27_bin="$s27/bin" s27_n="$s27/handoff"
mkdir -p "$s27_r/scripts" "$s27_bin" "$s27_n/9.9.9"
git init -q --bare "$s27_o"
git -C "$s27_r" init -q -b main
printf '#!/usr/bin/env bash\nexit 0\n' > "$s27_r/scripts/check-paths.sh"
printf '# Changelog\n' > "$s27_r/CHANGELOG.md"
git -C "$s27_r" add -A && git -C "$s27_r" commit -qm "base"
git -C "$s27_r" remote add origin "$s27_o" && git -C "$s27_r" push -q origin main 2>/dev/null
git -C "$s27_r" branch -q kit-trial
git -C "$s27_r" switch -q -c release/v9.9.9
printf '# Changelog\n\n## v9.9.9 — 2026-11-20\n\nA change.\n' > "$s27_r/CHANGELOG.md"
git -C "$s27_r" commit -qam "v9.9.9"
git -C "$s27_r" switch -q main
# A merge commit whose tree is not the release's: main with a change of its own merged in.
git -C "$s27_r" switch -q -c other main && printf 'x\n' > "$s27_r/x" && git -C "$s27_r" add x && git -C "$s27_r" commit -qm x
git -C "$s27_r" switch -q main
s27_bad_merge="$(git -C "$s27_r" commit-tree "$(git -C "$s27_r" rev-parse 'other^{tree}')" -p main -p release/v9.9.9 -m "merge")"
printf '# Roles in every project, and a sharper first interview\n\n**What is new**\n\nThings.\n' > "$s27_n/9.9.9/notes.md"

# The stub gh: the pull request's state, merge commit and checks come from S27_STATE, S27_MERGE and
# S27_CHECKS; every call is logged.
cat > "$s27_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${S27_LOG:?}"
case "$1 $2" in
    "pr list") exit 0 ;;
    "pr view")
        case "$*" in
            *mergeCommit*) echo "${S27_MERGE:-}" ;;
            *headRefName*) echo "kit-trial main OPEN" ;;
            *) echo "${S27_STATE:-OPEN}" ;;
        esac ;;
    "pr checks") [[ "$*" == *--json* ]] && echo "${S27_CHECKS:-[]}" || echo "ci	pass" ;;
    "release view") exit 1 ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$s27_bin/gh"
s27_log="$s27/gh.log"
s27_refs() { git -C "$s27_r" for-each-ref --format='%(refname) %(objectname)' | sort; }
s27_run() { s27_out="$(env KIT="$s27_r" S27_LOG="$s27_log" PATH="$s27_bin:$PATH" "$@" 2>&1)"; s27_rc=$?; }
s27_refs0="$(s27_refs)"

s27_run env S27_CHECKS='[{"name":"ubuntu","bucket":"pass"},{"name":"macos","bucket":"pass"}]' \
    bash "$KIT/scripts/release.sh" 9.9.9 ship --notes "$s27_n" --pr 7 --dry-run
s27_bad=""
[[ $s27_rc -eq 0 ]] || s27_bad+="rc=$s27_rc"$'\n'
grep_all -xF "ok: the tag's subject, from notes.md's first line: v9.9.9: Roles in every project, and a sharper first interview" <<<"$s27_out" \
    || s27_bad+="no subject line"$'\n'
grep_all -F 'git tag -a v9.9.9 ' <<<"$s27_out" && grep_all -F -- '-m v9.9.9:\ Roles\ in\ every\ project\,\ and\ a\ sharper\ first\ interview' <<<"$s27_out" \
    || s27_bad+="the tag step does not carry the subject"$'\n'
grep_all -F -- "--notes-file $(cd "$s27_n/9.9.9" && pwd -P)/notes.md" <<<"$s27_out" \
    || s27_bad+="the release does not read notes.md from the version's folder"$'\n'
[[ "$(s27_refs)" == "$s27_refs0" ]] || s27_bad+="the dry run changed a ref"$'\n'
empty "27 ship --dry-run: the version in, notes.md from <notes>/<version>/, the tag's subject v<version>: and its first line, and nothing changed" "$s27_bad${s27_bad:+$s27_out}"

s27_run bash "$KIT/scripts/release.sh" 9.9.9 pr --notes "$s27_n" --dry-run
[[ $s27_rc -eq 0 && "$s27_out" == *"move kit-trial to release/v9.9.9 as a fast-forward, without a checkout"* \
    && "$s27_out" == *"(dry run: not run)"* && "$(s27_refs)" == "$s27_refs0" ]] \
    && ok "27 pr --dry-run: the trial branch would move as a fast-forward without a checkout, and nothing changed" \
    || ko "27 pr --dry-run: the trial branch would move as a fast-forward without a checkout, and nothing changed" "rc=$s27_rc $s27_out"

s27_run env S27_CHECKS='[{"name":"ubuntu","bucket":"fail"},{"name":"macos","bucket":"pass"}]' \
    bash "$KIT/scripts/release.sh" 9.9.9 ship --notes "$s27_n" --pr 7 --dry-run
[[ $s27_rc -eq 1 && "$s27_out" == *"STOPPED: not every check on #7 passed (ubuntu: fail)"* && "$s27_out" != *"git tag"* ]] \
    && ok "27 ship stops on a check that did not pass, before any tag" \
    || ko "27 ship stops on a check that did not pass, before any tag" "rc=$s27_rc $s27_out"

s27_run env S27_STATE=MERGED S27_MERGE="$s27_bad_merge" S27_CHECKS='[{"name":"ubuntu","bucket":"pass"}]' \
    bash "$KIT/scripts/release.sh" 9.9.9 ship --notes "$s27_n" --pr 7
[[ $s27_rc -eq 1 && "$s27_out" == *"does not hold the release tree"* && "$s27_out" != *"git tag"* ]] \
    && ok "27 ship stops on a merge commit that does not hold exactly the release tree" \
    || ko "27 ship stops on a merge commit that does not hold exactly the release tree" "rc=$s27_rc $s27_out"

s27_bad=""
s27_run bash "$KIT/scripts/release.sh" 9.9.9 ship --notes "$s27/nowhere" --dry-run
[[ $s27_rc -eq 1 && "$s27_out" == *"no folder $s27/nowhere/9.9.9"* ]] || s27_bad+="missing notes folder: rc=$s27_rc $s27_out"$'\n'
s27_run bash "$KIT/scripts/release.sh" 9.9 ship --notes "$s27_n" --dry-run
[[ $s27_rc -eq 2 ]] || s27_bad+="a version that is not x.y.z: rc=$s27_rc $s27_out"$'\n'
empty "27 the script refuses a version that is not x.y.z and a notes folder with no folder for the version" "$s27_bad"
