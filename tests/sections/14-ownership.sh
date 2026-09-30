# shellcheck shell=bash
# ok and ko always return 0, so "check && ok || ko" is the suite's if-then-else; backticks in the
# single-quoted patterns are literal markdown; st_bash and kitsrc_ok come from the prelude in tests/run.sh.
# shellcheck disable=SC2015,SC2016,SC2154
# Section 14 · Ownership: the engine (install.sh) and the files a workspace owns.
#
# Sourced by tests/run.sh after section 11, in the runner's shell: every variable and function here
# starts with s14_, and everything is written under $SCRATCH/s14/. The fixtures are built without
# setup.sh: a new repository with the kit added at kit/ from KITSRC, and the engine run from that kit
# checkout, under the bash 3.2 floor ($st_bash). A template change is made in a clone of KITSRC, never
# in KITSRC itself, since the other sections build from it.

echo
echo "14 · Ownership: the engine creates the workspace's files once and records them"

if [[ ${kitsrc_ok:-0} -ne 1 ]]; then
    skp "14 ownership — KITSRC was not built (the kit is not a git checkout)"
else

s14_root="$SCRATCH/s14"
mkdir -p "$s14_root"
s14_today="$(date +%F)"

# s14_ws <dir> [kit repository]: a new repository on main, the kit added at kit/ (from KITSRC unless
# another repository is named). Nothing else.
s14_ws() {
    local d="$1" src="${2:-$KITSRC}"
    mkdir -p "$d" && git -C "$d" init -q && git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
    git -C "$d" -c protocol.file.allow=always submodule add -q -b main "$src" kit >/dev/null 2>&1
}
# s14_eng <dir> [engine args...]: the workspace's own kit/install.sh, aimed at the workspace.
s14_eng() { local d="$1"; shift; "$st_bash" "$d/kit/install.sh" --target "$d" "$@"; }
s14_run() { local d="$1"; shift; s14_eng "$d" --team "Test Team" --owner "Sam Example" --owner-handle "@sam" "$@"; }
# s14_files <dir>: every file the workspace holds outside .git and kit/, one per line, sorted.
s14_files() { (cd "$1" && find . -path ./.git -prune -o -path ./kit -prune -o \( -type f -o -type l \) -print | sed 's#^\./##' | grep -vx '.gitmodules' | LC_ALL=C sort); }
s14_field() { awk -F '\t' -v d="$2" -v n="$3" '$1 == d { print $n; exit }' "$1/.claude/kit-templates.lock"; }
s14_status() { "$st_bash" "$1/kit/install.sh" --template-status --target "$1" 2>/dev/null | awk -F '\t' -v d="$2" '$2 == d { print $1; exit }'; }
# s14_diff_lists <a> <b>: diff of two texts, through files (a sandbox may refuse diff a /dev/fd path).
s14_diff_lists() { printf '%s\n' "$1" > "$s14_root/diff-a"; printf '%s\n' "$2" > "$s14_root/diff-b"; diff "$s14_root/diff-a" "$s14_root/diff-b"; }
# s14_applies <repo> <diff text>: git apply --check on the diff, through a file.
s14_applies() { printf '%s\n' "$2" > "$s14_root/check.diff"; git -C "$1" apply --check "$s14_root/check.diff" 2>/dev/null; }
s14_mode() { python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"; }

s14_set=".claude/closeout.md
.claude/kit-templates.lock
.claude/projects.md
.claude/settings.json
.claude/workspace.md
.github/CODEOWNERS
.github/pull_request_template.md
.github/workflows/stay-private.yml
.gitignore
AGENTS.md
CLAUDE.md
README.md
audits/README.md
docs/workspace-map.md
logs/decisions.md
memory/glossary.md
memory/people/README.md
projects/INDEX.md"
s14_set="$(printf '%s\n' "$s14_set" | LC_ALL=C sort)"

# ---- A fresh workspace ------------------------------------------------------------------------------
s14_F="$s14_root/fresh"
s14_ws "$s14_F"
s14_out="$(s14_run "$s14_F" 2>&1)"; s14_rc=$?
if [[ $s14_rc -eq 0 ]]; then ok "14 the engine exits 0 on a new workspace"; else ko "14 the engine exits 0 on a new workspace" "$s14_out"; fi
empty "14 the engine creates exactly the contract's set of files, the ledger included" \
    "$(s14_diff_lists "$s14_set" "$(s14_files "$s14_F")")"
s14_bad=""
for s14_p in docs/memory-layers.md docs/documentation-register.md rituals templates .claude/plugins pilot/measure.sh pilot/README.md; do
    [[ ! -e "$s14_F/$s14_p" ]] || s14_bad+="$s14_p"$'\n'
done
s14_bad+="$(find "$s14_F" -name '*.kit-incoming' -not -path '*/.git/*')"
empty "14 nothing kit-owned is copied: no docs/memory-layers.md, rituals/, templates/, .claude/plugins/ or .kit-incoming" "$s14_bad"
if grep -qF 'Workspace: '"$s14_F"'  (kit at kit/, ' <<<"$s14_out" && grep -qxF 'Created (yours from here on):' <<<"$s14_out" \
    && grep -qxF '  .claude/kit-templates.lock' <<<"$s14_out" && grep -qxF 'Next:' <<<"$s14_out"; then
    ok "14 the report names the workspace and the kit, lists what it created (the ledger too), and ends with Next"
else ko "14 the report names the workspace and the kit, lists what it created (the ledger too), and ends with Next" "$s14_out"; fi

s14_l1="$(sed -n 1p "$s14_F/CLAUDE.md")" s14_l2="$(sed -n 2p "$s14_F/CLAUDE.md")"
[[ "$s14_l1" == '@kit/CLAUDE.kit.md' \
   && "$s14_l2" == 'Kit working standards: `kit/CLAUDE.kit.md` (read it at session start if the line above was not expanded).' ]] \
    && ok "14 CLAUDE.md starts with the import line and the fallback line" \
    || ko "14 CLAUDE.md starts with the import line and the fallback line" "$s14_l1"$'\n'"$s14_l2"
s14_bad=""
grep -qxF '# Test Team — working standards' "$s14_F/CLAUDE.md" || s14_bad+="no team heading"$'\n'
grep -qF '| **Team** | Test Team |' "$s14_F/CLAUDE.md" || s14_bad+="no Team row"$'\n'
grep -qF '| **Standards owner** | Sam Example — reviews' "$s14_F/CLAUDE.md" || s14_bad+="no Standards owner row"$'\n'
grep -qF '| Claude Code | `CLAUDE.md`, which imports `kit/CLAUDE.kit.md` |' "$s14_F/CLAUDE.md" || s14_bad+="no Claude Code row"$'\n'
grep -q '^| Cowork |\|^| Gemini CLI |' "$s14_F/CLAUDE.md" && s14_bad+="a Cowork or Gemini row without the flag"$'\n'
grep -qxF "*Last updated: $s14_today*" "$s14_F/CLAUDE.md" || s14_bad+="no dated last line"$'\n'
grep -q '__[A-Z_]*__' "$s14_F/CLAUDE.md" "$s14_F/AGENTS.md" "$s14_F/.claude/workspace.md" "$s14_F/.github/CODEOWNERS" && s14_bad+="a placeholder left unrendered"$'\n'
grep -qF '@sam' "$s14_F/.github/CODEOWNERS" || s14_bad+="CODEOWNERS lacks the handle"$'\n'
[[ "$(sed -n 1p "$s14_F/AGENTS.md")" == '@kit/CLAUDE.kit.md' ]] || s14_bad+="AGENTS.md does not start with the import"$'\n'
grep -qxF '# Workspace settings — Test Team' "$s14_F/.claude/workspace.md" || s14_bad+=".claude/workspace.md has no team heading"$'\n'
empty "14 the rendered files carry the answers: team, owner, handle, date, the Claude Code row only" "$s14_bad"

# The ledger: the contract's header, the @values line, and one five-field line per file.
s14_L="$s14_F/.claude/kit-templates.lock"
s14_head="$(head -n 3 "$s14_L")"
s14_want_head='# Written by kit/install.sh. One line per file the kit created from a template; the file itself is
# yours. This records which template version it came from, so kit/setup.sh update can offer the
# template'"'"'s later changes as a diff to apply or skip.'
[[ "$s14_head" == "$s14_want_head" ]] && ok "14 the ledger opens with the contract's three comment lines" \
    || ko "14 the ledger opens with the contract's three comment lines" "$s14_head"
s14_values="$(awk -F '\t' '$1 == "@values"' "$s14_L")"
s14_want_values="$(printf '@values\tteam=Test Team\towner=Sam Example\thandle=@sam\tdate=%s\tsurfaces=claude\tcowork=0\tpilot=0' "$s14_today")"
[[ "$s14_values" == "$s14_want_values" ]] && ok "14 the @values line records the answers and flags, in the contract's order" \
    || ko "14 the @values line records the answers and flags, in the contract's order" "$s14_values"
s14_kithead="$(git -C "$s14_F/kit" rev-parse HEAD)"
s14_bad="$(awk -F '\t' -v k="$s14_kithead" '
    /^#/ || $1 == "@values" { next }
    NF != 5 { print "fields " NF ": " $1; next }
    $3 != k { print "kit commit " $3 ": " $1 }
    $1 == ".gitignore" { if ($4 != "-" || $5 != "lines" || $2 != "templates/workspace.gitignore") print "gitignore entry: " $0; next }
    $4 !~ /^[0-9a-f]{40}$/ { print "hash: " $1 }
    $5 != "created" { print "status " $5 ": " $1 }' "$s14_L")"
s14_bad+="$(s14_diff_lists "$(printf '%s\n' "$s14_set" | grep -vxF .claude/kit-templates.lock)" \
    "$(awk -F '\t' '!/^#/ && $1 != "@values" { print $1 }' "$s14_L" | LC_ALL=C sort)")"
empty "14 every file has one ledger line: the kit's full commit, a 40-hex render hash, status created; .gitignore as lines" "$s14_bad"
# Field 4 is the hash of the render, so a file the engine wrote hashes to it.
s14_bad=""
for s14_p in CLAUDE.md .claude/closeout.md docs/workspace-map.md; do
    [[ "$(git hash-object --no-filters "$s14_F/$s14_p")" == "$(s14_field "$s14_F" "$s14_p" 4)" ]] || s14_bad+="$s14_p"$'\n'
done
empty "14 each ledger hash is the blob hash of the file the engine wrote" "$s14_bad"

s14_bad=""
jq -e '.extraKnownMarketplaces["agentic-workspace"].source == {"source": "directory", "path": "kit"}' "$s14_F/.claude/settings.json" >/dev/null || s14_bad+="marketplace path"$'\n'
jq -e '.attribution == {"commit": "", "pr": ""}' "$s14_F/.claude/settings.json" >/dev/null || s14_bad+="attribution"$'\n'
jq -e '[.enabledPlugins[]] == [true, true, true]' "$s14_F/.claude/settings.json" >/dev/null || s14_bad+="plugins"$'\n'
jq -e '.permissions.ask | index("Edit(./kit/**)") != null' "$s14_F/.claude/settings.json" >/dev/null || s14_bad+="ask rule for kit/"$'\n'
empty "14 .claude/settings.json: the marketplace at kit, the three plugins, empty attribution, and ask on kit/" "$s14_bad"

s14_tree="$(st_tree "$s14_F")"
s14_out="$(s14_run "$s14_F" 2>&1)"; s14_rc=$?
if [[ $s14_rc -eq 0 && "$s14_tree" == "$(st_tree "$s14_F")" ]]; then
    ok "14 a second run changes nothing, .git included (st_tree)"
else ko "14 a second run changes nothing, .git included (st_tree)" "rc=$s14_rc"$'\n'"$(s14_diff_lists "$s14_tree" "$(st_tree "$s14_F")" | head -n 10)"; fi
if grep -qxF 'Already in place:' <<<"$s14_out" && ! grep -qE '^(Created|Merged|Added to|Kept as it was|Template changed)' <<<"$s14_out"; then
    ok "14 the second run reports everything already in place, and nothing created, merged, kept or changed"
else ko "14 the second run reports everything already in place, and nothing created, merged, kept or changed" "$s14_out"; fi
s14_st="$(s14_eng "$s14_F" --template-status 2>&1)"
[[ -n "$s14_st" && -z "$(awk -F '\t' '$1 != "current" && !($1 == "lines" && $2 == ".gitignore")' <<<"$s14_st")" ]] \
    && ok "14 --template-status reads current for every file, and lines for .gitignore" \
    || ko "14 --template-status reads current for every file, and lines for .gitignore" "$s14_st"

s14_D="$s14_root/dry"
s14_ws "$s14_D"
s14_tree="$(st_tree "$s14_D")"
s14_out="$(s14_run "$s14_D" --dry-run --pilot 2>&1)"
if [[ "$s14_tree" == "$(st_tree "$s14_D")" ]] && grep -qxF 'Dry run — nothing written.' <<<"$s14_out" && grep -qxF '  CLAUDE.md' <<<"$s14_out"; then
    ok "14 --dry-run says what it would create and writes nothing"
else ko "14 --dry-run says what it would create and writes nothing" "$s14_out"; fi

s14_P="$s14_root/pilot"
s14_ws "$s14_P"
s14_out="$(s14_run "$s14_P" --pilot 2>&1)"
if [[ -f "$s14_P/pilot/build-list.md" && ! -e "$s14_P/pilot/measure.sh" && ! -e "$s14_P/pilot/README.md" ]] \
    && grep -qF 'bash kit/pilot/measure.sh' <<<"$s14_out" && [[ "$(s14_field "$s14_P" pilot/build-list.md 5)" == created ]]; then
    ok "14 --pilot creates pilot/build-list.md only; the metrics script is run in place from kit/pilot/"
else ko "14 --pilot creates pilot/build-list.md only; the metrics script is run in place from kit/pilot/" "$(ls -A "$s14_P/pilot" 2>&1)"$'\n'"$s14_out"; fi

# ---- The kit's own standards file -------------------------------------------------------------------
s14_kb="$(wc -c < "$KIT/CLAUDE.kit.md" | tr -d ' ')"
[[ "$s14_kb" -le 9000 ]] && ok "14 CLAUDE.kit.md is at most 9,000 bytes ($s14_kb)" || ko "14 CLAUDE.kit.md is at most 9,000 bytes ($s14_kb)"
empty "14 CLAUDE.kit.md's headings are unnumbered, so the workspace's §1–§4 stay its own" "$(grep -nE '^#+ +§?[0-9]' "$KIT/CLAUDE.kit.md")"
awk 'NF { l = $0 } END { print l }' "$KIT/CLAUDE.kit.md" | grep -qE '^\*Kit [0-9]+\.[0-9]+\.[0-9]+\*$' \
    && ok "14 CLAUDE.kit.md ends with the kit version it shipped with" \
    || ko "14 CLAUDE.kit.md ends with the kit version it shipped with" "$(tail -n 1 "$KIT/CLAUDE.kit.md")"
s14_bad=""
for s14_h in '## Operating stance' '### Documentation register' '## Where everything lives' '## Active work' '## Session startup' '## Decisions log' '## Rituals' '## Privacy'; do
    grep -qxF "$s14_h" "$KIT/CLAUDE.kit.md" || s14_bad+="no heading: $s14_h"$'\n'
done
[[ "$(awk '/^## Privacy$/ { f = 1; next } f && /^(## |\*Kit )/ { exit } f && NF' "$KIT/CLAUDE.kit.md" | aw_count)" -le 10 ]] || s14_bad+="the Privacy section is over 10 lines"$'\n'
grep -qF 'kit/docs/documentation-register.md' "$KIT/CLAUDE.kit.md" || s14_bad+="no kit/ pointer to the register"$'\n'
empty "14 CLAUDE.kit.md has the contract's sections in order, a Privacy section of at most 10 lines, and kit/ pointers" "$s14_bad"

# ---- Files already there ----------------------------------------------------------------------------
s14_K="$s14_root/kept"
s14_ws "$s14_K"
printf '# Our own readme\n' > "$s14_K/README.md"
printf '# Our rules\n\nHouse rules of our own.\n' > "$s14_K/CLAUDE.md"
s14_out="$(s14_run "$s14_K" 2>&1)"
if [[ "$(cat "$s14_K/README.md")" == '# Our own readme' && "$(s14_field "$s14_K" README.md 5)" == kept \
      && "$(s14_field "$s14_K" CLAUDE.md 5)" == kept && "$(head -n 1 "$s14_K/CLAUDE.md")" == '# Our rules' ]] \
    && grep -A3 -xF 'Kept as it was (yours, from before the kit):' <<<"$s14_out" | grep -qxF '  README.md' \
    && grep -qF 'Your own CLAUDE.md was kept' <<<"$s14_out"; then
    ok "14 a differing file already there is kept as it was, recorded kept, and reported"
else ko "14 a differing file already there is kept as it was, recorded kept, and reported" "$s14_out"; fi
[[ "$(s14_status "$s14_K" README.md)" == current ]] && ok "14 a kept file's base is recorded, so it reads current until the template changes" \
    || ko "14 a kept file's base is recorded, so it reads current until the template changes" "$(s14_eng "$s14_K" --template-status 2>&1)"

# The template repository's files are stand-in renders; the first real run replaces the untouched ones.
s14_S="$s14_root/standins"
s14_ws "$s14_S"
s14_out="$(s14_eng "$s14_S" --stand-ins 2>&1)"; s14_rc=$?
s14_want="$(printf '%s\n' "$s14_set" | grep -vxF -e .claude/kit-templates.lock -e .claude/workspace.md)"
if [[ $s14_rc -eq 0 ]] && [[ "$(s14_files "$s14_S")" == "$s14_want" ]] && grep -qF '<team name>' "$s14_S/CLAUDE.md" \
    && grep -qxF '*Last updated: YYYY-MM-DD*' "$s14_S/CLAUDE.md"; then
    ok "14 --stand-ins writes the template set with the stand-in values, and no ledger or .claude/workspace.md"
else ko "14 --stand-ins writes the template set with the stand-in values, and no ledger or .claude/workspace.md" \
    "rc=$s14_rc"$'\n'"$(s14_diff_lists "$s14_want" "$(s14_files "$s14_S")")"; fi
printf '\nOur own line.\n' >> "$s14_S/README.md"
s14_out="$(s14_run "$s14_S" 2>&1)"
if grep -qxF '# Test Team — working standards' "$s14_S/CLAUDE.md" && [[ "$(s14_field "$s14_S" CLAUDE.md 5)" == created ]] \
    && [[ "$(s14_field "$s14_S" README.md 5)" == kept ]] && grep -qF 'Our own line.' "$s14_S/README.md" \
    && grep -A20 -xF 'Created (yours from here on):' <<<"$s14_out" | grep -qxF '  CLAUDE.md'; then
    ok "14 a stand-in render is replaced with the real one and recorded created; an edited one is kept"
else ko "14 a stand-in render is replaced with the real one and recorded created; an edited one is kept" "$s14_out"; fi

# ---- An opaque AGENTS.md ----------------------------------------------------------------------------
s14_O="$s14_root/opaque"
s14_ws "$s14_O"
printf 'A router this workspace keeps for another tool.\n' > "$s14_O/AGENTS.md"
chmod 000 "$s14_O/AGENTS.md"
if [[ -r "$s14_O/AGENTS.md" ]]; then
    skp "14 opaque AGENTS.md — this user can read a mode-000 file, so unread cannot be shown"
else
    s14_err="$(s14_run "$s14_O" 2>&1 >/dev/null)"
    s14_st="$(s14_status "$s14_O" AGENTS.md)"
    if [[ "$(s14_field "$s14_O" AGENTS.md 5)" == kept && "$s14_st" == opaque && "$(s14_mode "$s14_O/AGENTS.md")" == 0 ]] \
        && ! grep -qi 'permission denied' <<<"$s14_err"; then
        ok "14 an opaque AGENTS.md is recorded kept without being opened, and --template-status says opaque"
    else ko "14 an opaque AGENTS.md is recorded kept without being opened, and --template-status says opaque" \
        "ledger: $(s14_field "$s14_O" AGENTS.md 5) status: $s14_st"$'\n'"$s14_err"; fi
    chmod 644 "$s14_O/AGENTS.md"
    [[ "$(cat "$s14_O/AGENTS.md")" == 'A router this workspace keeps for another tool.' ]] \
        && ok "14 the opaque file's content is unchanged" || ko "14 the opaque file's content is unchanged"
fi

# ---- --cowork, and values that change after the first run --------------------------------------------
s14_C="$s14_root/cowork"
s14_ws "$s14_C"
s14_run "$s14_C" --cowork >/dev/null 2>&1
s14_tree="$(st_tree "$s14_C")"
s14_st="$(s14_eng "$s14_C" --template-status 2>&1)"
s14_run "$s14_C" >/dev/null 2>&1
if grep -q '^| Cowork |' "$s14_C/CLAUDE.md" && [[ -z "$(awk -F '\t' '$1 != "current" && $1 != "lines"' <<<"$s14_st")" ]] \
    && [[ "$s14_tree" == "$(st_tree "$s14_C")" ]] && grep -q 'cowork=1' "$s14_C/.claude/kit-templates.lock"; then
    ok "14 a workspace made with --cowork has the Cowork row, reads current, and a later plain run changes nothing"
else ko "14 a workspace made with --cowork has the Cowork row, reads current, and a later plain run changes nothing" "$s14_st"; fi

s14_C2="$s14_root/cowork-later"
s14_ws "$s14_C2"
s14_run "$s14_C2" >/dev/null 2>&1
s14_out="$(s14_run "$s14_C2" --cowork 2>&1)"
if grep -q '^| Cowork |' "$s14_C2/CLAUDE.md" && [[ "$(s14_status "$s14_C2" CLAUDE.md)" == current ]] \
    && grep -A3 -xF 'Created (yours from here on):' <<<"$s14_out" | grep -qxF '  CLAUDE.md'; then
    ok "14 a later --cowork rewrites an untouched CLAUDE.md with the Cowork row, which then reads current"
else ko "14 a later --cowork rewrites an untouched CLAUDE.md with the Cowork row, which then reads current" "$s14_out"; fi

s14_C3="$s14_root/cowork-edited"
s14_ws "$s14_C3"
s14_run "$s14_C3" >/dev/null 2>&1
printf '\nA convention of our own.\n' >> "$s14_C3/CLAUDE.md"
cp "$s14_C3/CLAUDE.md" "$s14_root/cowork-edited.before"
s14_out="$(s14_run "$s14_C3" --cowork 2>&1)"
s14_diff="$(s14_eng "$s14_C3" --template-diff CLAUDE.md 2>&1)"; s14_rc=$?
if cmp -s "$s14_C3/CLAUDE.md" "$s14_root/cowork-edited.before" && [[ "$(s14_status "$s14_C3" CLAUDE.md)" == changed ]] \
    && [[ $s14_rc -eq 0 ]] && grep -q '^+| Cowork |' <<<"$s14_diff" \
    && s14_applies "$s14_C3" "$s14_diff"; then
    ok "14 a later --cowork leaves an edited CLAUDE.md alone and offers the Cowork row as a diff that applies"
else ko "14 a later --cowork leaves an edited CLAUDE.md alone and offers the Cowork row as a diff that applies" \
    "rc=$s14_rc"$'\n'"$s14_diff"$'\n'"$s14_out"; fi

# ---- A template change in the kit -------------------------------------------------------------------
s14_KR="$s14_root/kit-repo"
git clone -q "$KITSRC" "$s14_KR" 2>/dev/null
s14_T="$s14_root/template-change"
s14_ws "$s14_T" "$s14_KR"
s14_run "$s14_T" >/dev/null 2>&1
printf '\nOne more house rule, added upstream.\n' >> "$s14_KR/templates/workspace/closeout.md"
printf '| Example | An entry the template now carries |\n' >> "$s14_KR/templates/workspace/glossary.md"
git -C "$s14_KR" -c commit.gpgsign=false commit -qam "A template change" 2>/dev/null
git -C "$s14_T/kit" fetch -q origin 2>/dev/null && git -C "$s14_T/kit" checkout -q --detach origin/main 2>/dev/null
s14_newkit="$(git -C "$s14_T/kit" rev-parse HEAD)"
s14_out="$(s14_run "$s14_T" 2>&1)"
if [[ "$(s14_status "$s14_T" .claude/closeout.md)" == changed && "$(s14_status "$s14_T" memory/glossary.md)" == changed \
      && "$(s14_status "$s14_T" CLAUDE.md)" == current ]] \
    && grep -A3 -F 'Template changed since your copy was made' <<<"$s14_out" | grep -qxF '  .claude/closeout.md' \
    && ! grep -qF 'One more house rule' "$s14_T/.claude/closeout.md"; then
    ok "14 after a template change in the kit, --template-status says changed and a plain run reports it and writes nothing"
else ko "14 after a template change in the kit, --template-status says changed and a plain run reports it and writes nothing" \
    "$(s14_eng "$s14_T" --template-status 2>&1)"$'\n'"$s14_out"; fi

# The diff has a/ and b/ headers whatever the person's git config says, so git apply takes it as it is.
printf '[diff]\n\tnoprefix = true\n\tmnemonicPrefix = true\n' > "$s14_root/gitconfig-noprefix"
s14_diff="$(GIT_CONFIG_GLOBAL="$s14_root/gitconfig-noprefix" s14_eng "$s14_T" --template-diff .claude/closeout.md 2>&1)"; s14_rc=$?
if [[ $s14_rc -eq 0 ]] && grep -qxF -- '--- a/.claude/closeout.md' <<<"$s14_diff" && grep -qxF '+++ b/.claude/closeout.md' <<<"$s14_diff" \
    && grep -qxF '+One more house rule, added upstream.' <<<"$s14_diff" \
    && GIT_CONFIG_GLOBAL="$s14_root/gitconfig-noprefix" s14_applies "$s14_T" "$s14_diff"; then
    ok "14 --template-diff exits 0 with a/ b/ headers under diff.noprefix=true, and git apply --check takes it"
else ko "14 --template-diff exits 0 with a/ b/ headers under diff.noprefix=true, and git apply --check takes it" "rc=$s14_rc"$'\n'"$s14_diff"; fi
printf '%s\n' "$s14_diff" > "$s14_root/closeout.diff"
git -C "$s14_T" apply "$s14_root/closeout.diff" 2>/dev/null
s14_eng "$s14_T" --template-record .claude/closeout.md --status accepted >/dev/null 2>&1; s14_rc=$?
if [[ $s14_rc -eq 0 && "$(s14_status "$s14_T" .claude/closeout.md)" == current \
      && "$(s14_field "$s14_T" .claude/closeout.md 5)" == accepted && "$(s14_field "$s14_T" .claude/closeout.md 3)" == "$s14_newkit" ]]; then
    ok "14 --template-record accepted moves the entry to the new kit commit and hash, and it reads current"
else ko "14 --template-record accepted moves the entry to the new kit commit and hash, and it reads current" \
    "$(grep closeout "$s14_T/.claude/kit-templates.lock")"; fi
s14_eng "$s14_T" --template-record memory/glossary.md --status skipped >/dev/null 2>&1
if [[ "$(s14_status "$s14_T" memory/glossary.md)" == current && "$(s14_field "$s14_T" memory/glossary.md 5)" == skipped ]] \
    && ! grep -q 'An entry the template now carries' "$s14_T/memory/glossary.md"; then
    ok "14 --template-record skipped leaves the file alone and stops offering that change"
else ko "14 --template-record skipped leaves the file alone and stops offering that change" "$(grep glossary "$s14_T/.claude/kit-templates.lock")"; fi
s14_eng "$s14_T" --template-record no/such.md --status accepted >/dev/null 2>&1; s14_rc=$?
s14_eng "$s14_T" --template-record README.md --status bogus >/dev/null 2>&1; s14_rc2=$?
[[ $s14_rc -eq 1 && $s14_rc2 -eq 2 ]] && ok "14 --template-record exits 1 for a file with no entry, and 2 for an unknown status" \
    || ko "14 --template-record exits 1 for a file with no entry, and 2 for an unknown status" "rc=$s14_rc rc2=$s14_rc2"

# A changed entry whose old and new renders agree gives an empty diff (exit 3); one whose kit commit is
# not in the object store has no base (changed-no-base, exit 1).
python3 - "$s14_T/.claude/kit-templates.lock" <<'PYLEDGER'
import sys
p = sys.argv[1]
out = []
for line in open(p, encoding="utf-8").read().split("\n"):
    f = line.split("\t")
    if f[0] == "README.md" and len(f) >= 5:
        f[3] = "0" * 40
    if f[0] == "docs/workspace-map.md" and len(f) >= 5:
        f[2] = "e" * 40
        f[3] = "0" * 40
    out.append("\t".join(f))
open(p, "w", encoding="utf-8").write("\n".join(out))
PYLEDGER
s14_eng "$s14_T" --template-diff README.md >/dev/null 2>&1; s14_rc=$?
if [[ "$(s14_status "$s14_T" README.md)" == changed && $s14_rc -eq 3 ]]; then
    ok "14 an empty template diff exits 3"
else ko "14 an empty template diff exits 3" "status $(s14_status "$s14_T" README.md) rc=$s14_rc"; fi
s14_eng "$s14_T" --template-diff docs/workspace-map.md >/dev/null 2>&1; s14_rc=$?
[[ "$(s14_status "$s14_T" docs/workspace-map.md)" == changed-no-base && $s14_rc -eq 1 ]] \
    && ok "14 a kit commit missing from the object store reads changed-no-base, and --template-diff exits 1" \
    || ko "14 a kit commit missing from the object store reads changed-no-base, and --template-diff exits 1" "rc=$s14_rc"

# The engine reads its templates from the workspace's kit/, whichever engine runs.
s14_RK="$s14_root/reads-kit"
s14_ws "$s14_RK" "$s14_KR"
"$st_bash" "$KIT/install.sh" --target "$s14_RK" --team "Test Team" >/dev/null 2>&1
grep -qF 'One more house rule, added upstream.' "$s14_RK/.claude/closeout.md" \
    && ok "14 the templates come from the workspace's kit/, not from the engine's own folder" \
    || ko "14 the templates come from the workspace's kit/, not from the engine's own folder"

# A file recorded in the ledger and then removed is not recreated; a template the kit dropped says so.
s14_R="$s14_root/removed"
s14_ws "$s14_R"
mkdir -p "$s14_R/.claude"
cp "$s14_F/.claude/kit-templates.lock" "$s14_R/.claude/kit-templates.lock"
printf 'notes.md\ttemplates/workspace/no-such-template.md\t%s\t%s\tcreated\n' "$s14_kithead" "$(printf x | git hash-object --stdin)" >> "$s14_R/.claude/kit-templates.lock"
printf 'Notes.\n' > "$s14_R/notes.md"
s14_out="$(s14_run "$s14_R" 2>&1)"
if [[ ! -e "$s14_R/CLAUDE.md" && ! -e "$s14_R/.gitignore" && "$(s14_status "$s14_R" CLAUDE.md)" == removed \
      && "$(s14_status "$s14_R" notes.md)" == dropped ]] \
    && grep -qF 'CLAUDE.md is recorded in .claude/kit-templates.lock but is not here' <<<"$s14_out"; then
    ok "14 a recorded file that is gone is not recreated (removed), and a template the kit no longer has reads dropped"
else ko "14 a recorded file that is gone is not recreated (removed), and a template the kit no longer has reads dropped" "$s14_out"; fi

# ---- .gitignore in its three modes ------------------------------------------------------------------
s14_tpl_lines="$(grep -vE '^(#|[[:space:]]*$)' "$KIT/templates/workspace.gitignore")"
s14_G="$s14_root/gi-merge"
s14_ws "$s14_G"
printf 'node_modules/\n.DS_Store\n' > "$s14_G/.gitignore"
s14_out="$(s14_run "$s14_G" --gitignore merge 2>&1)"
s14_bad=""
[[ "$(head -n 1 "$s14_G/.gitignore")" == node_modules/ ]] || s14_bad+="the person's first line moved"$'\n'
[[ "$(grep -cxF '# Added by the agentic workspace kit (kit/templates/workspace.gitignore)' "$s14_G/.gitignore")" == 1 ]] || s14_bad+="header not written exactly once"$'\n'
[[ "$(grep -cxF '.DS_Store' "$s14_G/.gitignore")" == 1 ]] || s14_bad+=".DS_Store duplicated"$'\n'
while IFS= read -r s14_p; do grep -qxF -- "$s14_p" "$s14_G/.gitignore" || s14_bad+="missing: $s14_p"$'\n'; done <<<"$s14_tpl_lines"
grep -qxF '*.pptx' "$s14_G/.gitignore" && s14_bad+="the optional *.pptx line was added"$'\n'
grep -A3 -xF 'Added to .gitignore:' <<<"$s14_out" | grep -qxF '  .secrets/' || s14_bad+="the report does not list the added lines"$'\n'
empty "14 --gitignore merge appends the missing template lines once, under one header, keeping the person's lines" "$s14_bad"
s14_tree="$(st_tree "$s14_G")"
s14_run "$s14_G" --gitignore merge >/dev/null 2>&1
[[ "$s14_tree" == "$(st_tree "$s14_G")" ]] && ok "14 a second merge adds nothing" || ko "14 a second merge adds nothing"

s14_GD="$s14_root/gi-default"
s14_ws "$s14_GD"
printf 'node_modules/\n' > "$s14_GD/.gitignore"
s14_run "$s14_GD" >/dev/null 2>&1
grep -qxF '.secrets/' "$s14_GD/.gitignore" && ok "14 merge is the default when the engine creates CLAUDE.md in this run" \
    || ko "14 merge is the default when the engine creates CLAUDE.md in this run" "$(cat "$s14_GD/.gitignore")"

s14_GR="$s14_root/gi-report"
s14_ws "$s14_GR"
printf 'node_modules/\n' > "$s14_GR/.gitignore"
printf '# Our rules\n' > "$s14_GR/CLAUDE.md"
s14_out="$(s14_run "$s14_GR" 2>&1)"
if [[ "$(cat "$s14_GR/.gitignore")" == node_modules/ ]] && grep -qF '.gitignore lacks' <<<"$s14_out" \
    && grep -F '.gitignore lacks' <<<"$s14_out" | grep -qF 'kit/setup.sh update offers them'; then
    ok "14 report (the default on a workspace that has its CLAUDE.md) lists the missing lines and writes nothing"
else ko "14 report (the default on a workspace that has its CLAUDE.md) lists the missing lines and writes nothing" "$s14_out"; fi
s14_tree="$(st_tree "$s14_GR")"
s14_diff="$(s14_eng "$s14_GR" --gitignore offer 2>&1)"; s14_rc=$?
if [[ $s14_rc -eq 0 && "$s14_tree" == "$(st_tree "$s14_GR")" ]] && grep -qxF '+.secrets/' <<<"$s14_diff" \
    && s14_applies "$s14_GR" "$s14_diff"; then
    ok "14 --gitignore offer prints the missing lines as a diff git apply takes, and writes nothing"
else ko "14 --gitignore offer prints the missing lines as a diff git apply takes, and writes nothing" "rc=$s14_rc"$'\n'"$s14_diff"; fi
s14_eng "$s14_GR" --gitignore-decline '*.bak' >/dev/null 2>&1
s14_eng "$s14_GR" --gitignore-decline '*.bak' >/dev/null 2>&1
s14_diff="$(s14_eng "$s14_GR" --gitignore offer 2>&1)"
if [[ "$(grep -cxF "$(printf '!declined\t.gitignore\t*.bak')" "$s14_GR/.claude/kit-templates.lock")" == 1 ]] \
    && ! grep -qxF '+*.bak' <<<"$s14_diff" && grep -qxF '+*.bak-*' <<<"$s14_diff"; then
    ok "14 --gitignore-decline records the line once, and the offer leaves it out"
else ko "14 --gitignore-decline records the line once, and the offer leaves it out" "$s14_diff"; fi
printf '%s\n' "$s14_diff" > "$s14_root/gitignore.diff"
git -C "$s14_GR" apply "$s14_root/gitignore.diff" 2>/dev/null
s14_eng "$s14_GR" --gitignore offer >/dev/null 2>&1; s14_rc=$?
s14_run "$s14_GR" --gitignore merge >/dev/null 2>&1
[[ $s14_rc -eq 3 ]] && ! grep -qxF '*.bak' "$s14_GR/.gitignore" \
    && ok "14 once the offer is applied it exits 3, and a merge still leaves the declined line out" \
    || ko "14 once the offer is applied it exits 3, and a merge still leaves the declined line out" "rc=$s14_rc"

# ---- .claude/settings.json: one key maintained, the person's values kept ------------------------------
s14_J="$s14_root/settings"
s14_ws "$s14_J"
mkdir -p "$s14_J/.claude"
printf '%s\n' '{"permissions": {"allow": ["Zed(x)", "Alpha(y)"]}, "enabledPlugins": {"workspace@agentic-workspace": false}}' > "$s14_J/.claude/settings.json"
s14_out="$(s14_run "$s14_J" 2>&1)"
s14_bad=""
jq -e '.extraKnownMarketplaces["agentic-workspace"].source == {"source": "directory", "path": "kit"}' "$s14_J/.claude/settings.json" >/dev/null || s14_bad+="marketplace path not set"$'\n'
jq -e '.permissions.allow == ["Zed(x)", "Alpha(y)"]' "$s14_J/.claude/settings.json" >/dev/null || s14_bad+="allow list changed"$'\n'
jq -e '.enabledPlugins["workspace@agentic-workspace"] == false' "$s14_J/.claude/settings.json" >/dev/null || s14_bad+="the person's false was changed"$'\n'
grep -A2 -xF 'Merged (settings marketplace path):' <<<"$s14_out" | grep -qxF '  .claude/settings.json' || s14_bad+="not reported as merged"$'\n'
empty "14 an existing settings.json gets the marketplace path at kit; its list order and a plugin switched off are kept" "$s14_bad"
s14_cmd="$(grep -F "settings key the kit's template has and yours lacks" <<<"$s14_out" | grep -F 'Edit(./kit/**)' | head -n 1 | sed 's/^.*yours lacks: //')"
if [[ -n "$s14_cmd" ]] && (cd "$s14_J" && bash -c "$s14_cmd") 2>/dev/null \
    && jq -e '.permissions.ask | index("Edit(./kit/**)") != null' "$s14_J/.claude/settings.json" >/dev/null \
    && jq -e '.permissions.allow == ["Zed(x)", "Alpha(y)"]' "$s14_J/.claude/settings.json" >/dev/null; then
    ok "14 each kit key the file lacks is listed with a jq command that adds it, and the command works"
else ko "14 each kit key the file lacks is listed with a jq command that adds it, and the command works" "$s14_cmd"$'\n'"$s14_out"; fi
s14_tree="$(st_tree "$s14_J")"
s14_run "$s14_J" >/dev/null 2>&1
[[ "$s14_tree" == "$(st_tree "$s14_J")" ]] && jq -e '.enabledPlugins["workspace@agentic-workspace"] == false' "$s14_J/.claude/settings.json" >/dev/null \
    && ok "14 a rerun leaves settings.json alone, the switched-off plugin included" \
    || ko "14 a rerun leaves settings.json alone, the switched-off plugin included"

# ---- Traces of 2.x, reported and left alone ----------------------------------------------------------
s14_X="$s14_root/legacy"
s14_ws "$s14_X"
mkdir -p "$s14_X/.claude/plugins" "$s14_X/skills/projects-new" "$s14_X/.claude"
printf 'Vendored.\n' > "$s14_X/.claude/plugins/VENDORED"
printf 'Incoming.\n' > "$s14_X/README.md.kit-incoming"
printf -- '---\nname: projects-new\n---\n<!-- Generated by install.sh from plugins/projects/commands/new.md: edit that file. -->\n' > "$s14_X/skills/projects-new/SKILL.md"
printf '%s\n' '{"extraKnownMarketplaces": {"agentic-workspace": {"source": {"source": "directory", "path": ".claude/plugins"}}}}' > "$s14_X/.claude/settings.json"
cp "$s14_X/.claude/settings.json" "$s14_root/legacy-settings.before"
s14_out="$(s14_run "$s14_X" 2>&1)"
s14_n="$(grep -c 'legacy: .*kit/setup.sh migrate --dry-run' <<<"$s14_out")"
if [[ "$s14_n" == 4 && -f "$s14_X/.claude/plugins/VENDORED" && -f "$s14_X/README.md.kit-incoming" && -f "$s14_X/skills/projects-new/SKILL.md" ]] \
    && cmp -s "$s14_X/.claude/settings.json" "$s14_root/legacy-settings.before"; then
    ok "14 2.x traces (vendored plugins, .kit-incoming, generated skills, a legacy marketplace path) are named with migrate --dry-run and left alone"
else ko "14 2.x traces (vendored plugins, .kit-incoming, generated skills, a legacy marketplace path) are named with migrate --dry-run and left alone" "$s14_out"; fi

# ---- Usage and preconditions ------------------------------------------------------------------------
s14_err="$("$st_bash" "$KIT/install.sh" 2>&1 </dev/null)"; s14_rc=$?
[[ $s14_rc -eq 2 && "$(printf '%s\n' "$s14_err" | awk 'NF { l = $0 } END { print l }')" == 'The guided path is kit/setup.sh.' ]] \
    && ok "14 with no options the engine prints its usage, ending with the guided path, and exits 2" \
    || ko "14 with no options the engine prints its usage, ending with the guided path, and exits 2" "rc=$s14_rc"
mkdir -p "$s14_root/no-kit" && git -C "$s14_root/no-kit" init -q
s14_err="$("$st_bash" "$KIT/install.sh" --target "$s14_root/no-kit" 2>&1)"; s14_rc=$?
[[ $s14_rc -eq 1 ]] && grep -qF "install.sh: no kit at $(cd "$s14_root/no-kit" && pwd -P)/kit — add it with kit/setup.sh new, or git submodule add <url> kit" <<<"$s14_err" \
    && [[ "$(ls -A "$s14_root/no-kit")" == .git ]] \
    && ok "14 a target with no kit/ stops with exit 1 and the contract's message, writing nothing" \
    || ko "14 a target with no kit/ stops with exit 1 and the contract's message, writing nothing" "rc=$s14_rc $s14_err"
s14_bad=""
for s14_a in "--plugin vendor" "--interactive" "--skills-dir $s14_root/x" "--plugin-src $s14_root/x" "--gitignore sometimes" "--surfaces gemini"; do
    # shellcheck disable=SC2086
    "$st_bash" "$KIT/install.sh" --target "$s14_F" $s14_a >/dev/null 2>&1
    [[ $? -eq 2 ]] || s14_bad+="$s14_a"$'\n'
done
empty "14 retired and misplaced options are usage errors (exit 2): --plugin, --interactive, --skills-dir or --plugin-src without --skills-only" "$s14_bad"

# ---- --skills-only, with the prefix and the skip list -------------------------------------------------
s14_SK="$s14_root/skills"
s14_out="$(s14_eng "$s14_F" --skills-only --skills-dir "$s14_SK" --skills-prefix kit- --skills-skip "closeout, workspace-hygiene" 2>&1)"; s14_rc=$?
s14_ncmd=0; for s14_p in "$s14_F"/kit/plugins/*/commands/*.md; do [[ -f "$s14_p" ]] && s14_ncmd=$((s14_ncmd + 1)); done
s14_have=0 s14_unprefixed=""
for s14_p in "$s14_SK"/*/; do
    [[ -d "$s14_p" ]] || continue
    s14_have=$((s14_have + 1)); s14_p="${s14_p%/}"
    case "${s14_p##*/}" in kit-*) ;; *) s14_unprefixed+="${s14_p##*/} " ;; esac
done
s14_bad=""
[[ $s14_rc -eq 0 ]] || s14_bad+="rc=$s14_rc"$'\n'
[[ "$s14_have" == "$(( s14_ncmd - 2 ))" ]] || s14_bad+="$s14_have folders for $s14_ncmd commands less two skipped"$'\n'
[[ ! -e "$s14_SK/kit-closeout" && ! -e "$s14_SK/kit-workspace-hygiene" ]] || s14_bad+="a skipped command was generated"$'\n'
[[ -z "$s14_unprefixed" ]] || s14_bad+="folders without the prefix: $s14_unprefixed"$'\n'
grep -qxF 'name: kit-projects-new' "$s14_SK/kit-projects-new/SKILL.md" || s14_bad+="front-matter name"$'\n'
grep -qF '`kit-projects-new`, `kit-workspace-hygiene`, `kit-closeout`' "$s14_SK/kit-projects-new/SKILL.md" || s14_bad+="sibling sentence without kit- names"$'\n'
grep -qF '`kit/plugins/projects/commands/new.md` in this repository' "$s14_SK/kit-projects-new/SKILL.md" || s14_bad+="pointer"$'\n'
grep -qF 'Generated by install.sh from plugins/projects/commands/new.md' "$s14_SK/kit-projects-new/SKILL.md" || s14_bad+="marker"$'\n'
[[ "$(aw_count < "$s14_SK/kit-projects-new/SKILL.md")" -lt 30 ]] || s14_bad+="SKILL.md is 30 lines or more"$'\n'
empty "14 --skills-only --skills-prefix kit- --skills-skip: prefixed folders and names, the sibling sentence in kit- form, skipped ones absent" "$s14_bad"
s14_eng "$s14_F" --skills-only --skills-dir "$s14_root/skills-plain" >/dev/null 2>&1
[[ -f "$s14_root/skills-plain/projects-new/SKILL.md" ]] && grep -qF '(`projects-new`, `workspace-hygiene`, `closeout`)' "$s14_root/skills-plain/projects-new/SKILL.md" \
    && ok "14 --skills-only without a prefix keeps the 2.2.0 names" || ko "14 --skills-only without a prefix keeps the 2.2.0 names"
s14_eng "$s14_F" --skills-only --skills-dir "$s14_F/kit/generated-skills" >/dev/null 2>&1; s14_rc=$?
[[ $s14_rc -eq 1 && ! -e "$s14_F/kit/generated-skills" ]] && ok "14 a skills folder inside the kit checkout is refused (exit 1) and not made" \
    || ko "14 a skills folder inside the kit checkout is refused (exit 1) and not made" "rc=$s14_rc"

fi
