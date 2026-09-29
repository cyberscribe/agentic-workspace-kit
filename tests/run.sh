#!/usr/bin/env bash
# The kit's test suite. Plain bash; needs only git, jq and python3.
#
#   bash tests/run.sh               run everything
#   AW_KEEP=1 bash tests/run.sh     keep the scratch directory afterwards, for inspection
#   AW_BANNED_WORDS_FILE=<path> bash tests/run.sh
#                                   read section 6's word list from <path> rather than
#                                   ~/.config/agentic-workspace-kit/banned-words.txt; with no list
#                                   there, the scan is reported as SKIP
#
# One line per check: PASS, FAIL or SKIP, then a count. Exits non-zero when anything fails.
# Every repository it builds lives under one mktemp directory in $TMPDIR, removed on exit.
#
# The sections follow the numbered list in the spec's tests section:
#   1 non-interactive install, twice    5 measure.sh --backfill on a dated fixture history
#   2 interactive install, piped        6 words the kit does not use, from a private list
#   2b installer modes and flags
#   3 JSON, TOML, versions, marketplaces 7 no AI-vendor attribution, in files and in history
#   4 closeout hooks                    8 the register: no capitals-for-emphasis in prompts
#   4b the projects session-start hook  9 the nine commands, on Claude Code and as skills
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for tool in git jq python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "tests/run.sh needs $tool on PATH" >&2; exit 2; }
done

# A clean environment: the runner's own git identity, hooks and signing, and any closeout settings
# exported in the calling shell, would otherwise leak into the fixtures.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Test Runner" GIT_AUTHOR_EMAIL="runner@example.test"
export GIT_COMMITTER_NAME="Test Runner" GIT_COMMITTER_EMAIL="runner@example.test"
for v in $(compgen -v | grep '^CLOSEOUT_' || true); do unset "$v"; done

# macOS mktemp ignores TMPDIR unless given a template, so a template is always passed.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/aw-tests.XXXXXX")"
SCRATCH="$(cd "$SCRATCH" && pwd -P)"
if [[ "${AW_KEEP:-}" == "1" ]]; then
    trap 'echo "Scratch kept at $SCRATCH"' EXIT
else
    trap 'rm -rf "$SCRATCH"' EXIT
fi

pass=0 fail=0 skip=0
ok()   { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
# ko <description> [detail]: the detail, if any, is indented under the FAIL line.
ko()   { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed '/^$/d' | head -n 20 | sed 's/^/        /'; return 0; }
skp()  { skip=$((skip + 1)); printf 'SKIP  %s\n' "$1"; }
# check <description> <command...>: passes when the command succeeds.
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi; }
# empty <description> <text>: passes when the text is empty; otherwise the text is the detail.
empty() { if [[ -z "$2" ]]; then ok "$1"; else ko "$1" "$2"; fi; }

# Dates relative to today, in local time, portable across BSD and GNU date.
days_ago() { python3 -c 'import datetime,sys; print(datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])))' "$1"; }
# age <path> <days>: backdates a file's mtime, as if it were written that many days ago.
age() { python3 -c 'import os,sys,time; t = time.time() - float(sys.argv[2]) * 86400; os.utime(sys.argv[1], (t, t))' "$1" "$2"; }

install_args=(--team "Test Team" --owner "Sam Example" --owner-handle "@sam")

# ---------------------------------------------------------------------------------------------------
echo "1 · Non-interactive install, then a second run"

T1="$SCRATCH/install-1"
mkdir -p "$T1" && git -C "$T1" init -q
S1="$SCRATCH/skills-1"   # the skills folder a desktop assistant would load, outside the repository
out1="$(bash "$KIT/install.sh" --target "$T1" "${install_args[@]}" --pilot --skills-dir "$S1" </dev/null 2>&1)"; rc1=$?
if [[ $rc1 -eq 0 ]]; then ok "1 first run exits 0"; else ko "1 first run exits 0" "$out1"; fi
missing=""
for f in AGENTS.md CLAUDE.md .claude/settings.json .claude/closeout.md .claude/projects.md \
         templates/verification-standard.md templates/catalogue.md \
         .claude/plugins/VENDORED .claude/plugins/.claude-plugin/marketplace.json \
         projects/INDEX.md logs/decisions.md memory/glossary.md \
         memory/people/README.md docs/memory-layers.md audits/README.md .github/CODEOWNERS \
         pilot/measure.sh; do
    [[ -e "$T1/$f" ]] || missing+="$f"$'\n'
done
empty "1 first run lays down the promised files" "$missing"
check "1 the team name reaches AGENTS.md" grep -q 'Test Team' "$T1/AGENTS.md"
# The conventions every projects command reads first carry the staleness the board measures against,
# and the project template carries the Current state block the hook, board and metrics read.
check "1 .claude/projects.md sets the staleness a project's Updated date is measured against" \
    grep -qE '^- \*\*Staleness:\*\* `[^`]+`' "$T1/.claude/projects.md"
tpl="$T1/templates/project-readme.md"
bad=""
for h in '## Done when' '## Current state' '## Planned *(optional)*' '## People *(optional)*'; do
    grep -qxF "$h" "$tpl" || bad+="no heading: $h"$'\n'
done
# The block's labels are exactly these four, in this order, so a label added back is caught as
# surely as one taken away; and State offers exactly the five states.
labels="$(awk '/^## / { f = ($0 == "## Current state") ; next } f && /^- \*\*[^*]+:\*\*/ { l = $0; sub(/^- \*\*/, "", l); sub(/:\*\*.*/, "", l); print l }' "$tpl" | paste -sd'|' -)"
[[ "$labels" == 'State|Blocked by|Check-in|Updated' ]] || bad+="the block's labels are \"$labels\", not State|Blocked by|Check-in|Updated"$'\n'
grep -qxF -- '- **State:** <ready · doing · blocked · paused · done>' "$tpl" || bad+="the State line does not offer exactly the five states"$'\n'
bad+="$(grep -nE '^## (Now|Next up|Parked)([[:space:]]|$)' "$tpl")"
empty "1 the installed project template has a Current state block (State, Blocked by, Check-in, Updated), Planned, and no older sections" "$bad"
grep -q '/workspace:quick-start' <<<"$out1" && ok "1 the Next message says to run /workspace:quick-start" \
    || ko "1 the Next message says to run /workspace:quick-start" "$(grep -A3 '^Next' <<<"$out1")"
check "1 no .claude/commands directory (quick-start lives in the workspace plugin)" test ! -e "$T1/.claude/commands"

# The quick-start decides the team part is unfinished while AGENTS.md §1–§3 hold an angle-bracketed
# stand-in, which always has a space in it; path patterns such as memory/people/<name>.md never do.
# This is the rule its prompt states, checked against the file the installer actually writes.
standins() { tr '\n' ' ' < "$1" | grep -o '<[A-Za-z][^<>]* [^<>]*>' | wc -l | tr -d ' '; }
n="$(standins "$T1/AGENTS.md")"
[[ "$n" -gt 0 ]] && ok "1 a fresh AGENTS.md has stand-ins for the quick-start to find ($n)" || ko "1 a fresh AGENTS.md has stand-ins for the quick-start to find"
filled="$SCRATCH/agents-filled.md"
tr '\n' '\v' < "$T1/AGENTS.md" | sed -E 's/<[A-Za-z][^<>]* [^<>]*>/filled in/g' | tr '\v' '\n' > "$filled"
if [[ "$(standins "$filled")" == "0" ]] && grep -q '<name>' "$filled"; then
    ok "1 once every stand-in is answered none remain, though path patterns such as <name> do"
else ko "1 once every stand-in is answered none remain, though path patterns such as <name> do" "$(grep -n '<' "$filled")"; fi
grep -q "has $n answers still to fill in" <<<"$out1" && ok "1 the Next message counts stand-ins, not path patterns" \
    || ko "1 the Next message counts stand-ins, not path patterns" "$(grep 'still to fill' <<<"$out1")"

# snap <dir>: a checksum per file, so any write the second run makes shows up, whatever its route.
snap() { (cd "$1" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 shasum); }
# The skills folder is written on the same runs, outside the repository, so it is checked too.
s1="$(snap "$T1"; snap "$S1")"
out2="$(bash "$KIT/install.sh" --target "$T1" "${install_args[@]}" --pilot --skills-dir "$S1" </dev/null 2>&1)"; rc2=$?
if [[ $rc2 -eq 0 ]]; then ok "1 second run exits 0"; else ko "1 second run exits 0" "$out2"; fi
printf '%s\n' "$s1" > "$SCRATCH/snap-1"; { snap "$T1"; snap "$S1"; } > "$SCRATCH/snap-2"
empty "1 second run changes no file, in the repository or the skills folder" "$(diff "$SCRATCH/snap-1" "$SCRATCH/snap-2")"
if grep -q '^Already up to date:' <<<"$out2" && ! grep -qE '^(Added|Merged|Regenerated|Existing file kept)' <<<"$out2"; then
    ok "1 second run reports everything already up to date, and nothing added, merged or set aside"
else
    ko "1 second run reports everything already up to date, and nothing added, merged or set aside" \
        "$(grep -A8 -E '^(Added|Merged|Regenerated|Existing file kept)' <<<"$out2")"
fi
check "1 the default install is Claude Code only (no .gemini/)" test ! -e "$T1/.gemini"
# Every session reads AGENTS.md, and every projects command reads .claude/projects.md first, so
# neither may name a surface this install did not set up.
empty "1 a Claude-only install names no Gemini CLI surface in the files read first" \
    "$(grep -n -i -E 'gemini cli|\.gemini/settings' "$T1/AGENTS.md" "$T1/.claude/projects.md")"
check "1 the surface table names the plugins' hooks, including the session-start line" \
    grep -qF 'the closeout end-of-session capture and next-session review, and the projects session-start line' "$T1/AGENTS.md"
check "1 the surface table gains a desktop-assistant row when skills are written" grep -q '^| Desktop assistant |' "$T1/AGENTS.md"
grep -qF "approve the closeout and projects plugins' hooks" <<<"$out1" && ok "1 the Next message asks each person to approve both plugins' hooks" \
    || ko "1 the Next message asks each person to approve both plugins' hooks" "$(grep -A6 '^Next' <<<"$out1")"
empty "1 no .kit-incoming files after two runs" "$(find "$T1" "$S1" -name '*.kit-incoming' -not -path '*/.git/*')"
perm="$(python3 -c 'import os,sys; print(" ".join(oct(os.stat(f).st_mode & 0o777)[2:] for f in sys.argv[1:]))' \
    "$T1/AGENTS.md" "$T1/CLAUDE.md" "$T1/pilot/README.md" "$T1/pilot/measure.sh")"
[[ "$perm" == "644 644 644 755" ]] && ok "1 rendered files are 0644 and pilot/measure.sh is 0755" \
    || ko "1 rendered files are 0644 and pilot/measure.sh is 0755" "$perm"
check "1 VENDORED names the kit checkout it was built from" grep -qF "kit checkout: $KIT" "$T1/.claude/plugins/VENDORED"

# A repository with a CLAUDE.md of its own keeps it as the always-loaded file: the Next message
# points at the quick-start's mapping, and .claude/closeout.md promotes to that file, not AGENTS.md.
TK="$SCRATCH/install-kept"
mkdir -p "$TK" && git -C "$TK" init -q && printf '# My rules\n\nHouse rules of my own.\n' > "$TK/CLAUDE.md"
outk="$(bash "$KIT/install.sh" --target "$TK" --team Solo --owner Alex </dev/null 2>&1)"
if grep -qF 'Your own CLAUDE.md was kept' <<<"$outk" && ! grep -q 'answers still to fill in' <<<"$outk" \
    && grep -qF 'The always-loaded file is `CLAUDE.md`' "$TK/.claude/closeout.md" \
    && ! grep -qF 'The always-loaded file is `AGENTS.md`' "$TK/.claude/closeout.md" \
    && grep -q 'with one person it is optional' <<<"$outk"; then
    ok "1 an existing CLAUDE.md stays the always-loaded file, in the Next message and .claude/closeout.md"
else ko "1 an existing CLAUDE.md stays the always-loaded file, in the Next message and .claude/closeout.md" "$outk"; fi

# ---------------------------------------------------------------------------------------------------
echo
echo "2 · Interactive install with answers piped in"

T2="$SCRATCH/install-2"   # deliberately absent: the interactive path offers to create it
# Answers, in the order install.sh asks: target, team, owner, handle, tools, skills folder, pilot,
# confirm.
S2="$SCRATCH/skills-2"
out="$(printf '%s\n' "$T2" "Piped Team" "Pat Example" "@pat" "claude,gemini" "$S2" "y" "y" \
    | bash "$KIT/install.sh" --interactive 2>&1)"; rc=$?
if [[ $rc -eq 0 ]]; then ok "2 interactive install exits 0"; else ko "2 interactive install exits 0" "$out"; fi
check "2 the target was created as a git repository" git -C "$T2" rev-parse --git-dir
check "2 the piped team name reaches AGENTS.md" grep -q 'Piped Team' "$T2/AGENTS.md"
check "2 the piped handle reaches CODEOWNERS" grep -q '@pat' "$T2/.github/CODEOWNERS"
check "2 the pilot answer installs pilot/" test -f "$T2/pilot/measure.sh"
check "2 both surfaces installed" test -f "$T2/CLAUDE.md" -a -f "$T2/.gemini/settings.json"
check "2 the piped skills folder gets the skills" test -f "$S2/workspace-quick-start/SKILL.md"

# Enter on every question: the questions with no default are left as stand-ins, and nothing stops.
T2E="$SCRATCH/install-2-enter"
out="$(printf '%s\n' "$T2E" "" "" "" "" "" "" "" | bash "$KIT/install.sh" --interactive 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && grep -q '<team name>' "$T2E/AGENTS.md" 2>/dev/null && [[ ! -e "$T2E/.gemini" && ! -e "$T2E/pilot" ]] \
    && grep -qE '^  skills +none$' <<<"$out" && [[ ! -e "$T2E/.claude/closeout.md.kit-incoming" ]]; then
    ok "2 Enter on every question installs with the defaults: stand-ins kept, Claude Code only, no skills, no pilot"
else ko "2 Enter on every question installs with the defaults: stand-ins kept, Claude Code only, no skills, no pilot" "$out"; fi

# ---------------------------------------------------------------------------------------------------
echo
echo "2b · Installer modes and flags"

M="$SCRATCH/modes"
mkdir -p "$M"
out="$(bash "$KIT/install.sh" --target "$M/bogus" --init --surfaces bogus 2>&1)"; rc=$?
[[ $rc -ne 0 && ! -e "$M/bogus/AGENTS.md" ]] && ok "2b an unknown surface stops the run before anything is written" \
    || ko "2b an unknown surface stops the run before anything is written" "rc=$rc $out"
bash "$KIT/install.sh" --target "$M/both" --init --surfaces Both >/dev/null 2>&1
check "2b --surfaces both installs Claude Code and Gemini CLI" test -f "$M/both/CLAUDE.md" -a -f "$M/both/.gemini/settings.json"

bash "$KIT/install.sh" --target "$M/github" --init --plugin github >/dev/null 2>&1
check "2b --plugin github registers the kit's repository as the marketplace, and vendors nothing" \
    jq -e '.extraKnownMarketplaces["agentic-workspace"].source == {"source": "github", "repo": "cyberscribe/agentic-workspace-kit"}' "$M/github/.claude/settings.json"
check "2b --plugin github: no .claude/plugins" test ! -e "$M/github/.claude/plugins"

bash "$KIT/install.sh" --target "$M/none" --init --plugin none --skills-dir "$M/none-skills" >/dev/null 2>&1
if [[ ! -e "$M/none/.claude/plugins" ]] && ! jq -e '.enabledPlugins' "$M/none/.claude/settings.json" >/dev/null 2>&1 \
    && [[ -f "$M/none/.claude/closeout.md" && -f "$M/none-skills/closeout/SKILL.md" ]] \
    && grep -q "plugins are not installed here" "$M/none/AGENTS.md"; then
    ok "2b --plugin none: no plugins enabled, the closeout skill still gets .claude/closeout.md, and AGENTS.md says so"
else ko "2b --plugin none: no plugins enabled, the closeout skill still gets .claude/closeout.md, and AGENTS.md says so" \
    "$(ls -A "$M/none/.claude"; grep -n '^| Claude Code' "$M/none/AGENTS.md")"; fi

mkdir -p "$M/dry" && git -C "$M/dry" init -q
bash "$KIT/install.sh" --target "$M/dry" --dry-run --skills-dir "$M/dry-skills" --pilot >/dev/null 2>&1
[[ "$(ls -A "$M/dry")" == ".git" && ! -e "$M/dry-skills" ]] && ok "2b --dry-run writes nothing, in the repository or the skills folder" \
    || ko "2b --dry-run writes nothing, in the repository or the skills folder" "$(ls -A "$M/dry" "$M/dry-skills" 2>&1)"

mkdir -p "$M/only"
bash "$KIT/install.sh" --skills-only --target "$M/only" --skills-dir "$M/only-skills" >/dev/null 2>&1
out="$(bash "$KIT/install.sh" --skills-only --target "$M/only" --skills-dir "$M/only-skills" 2>&1)"
if grep -q '^Already up to date:' <<<"$out" && ! grep -qE '^(Added|Merged|Regenerated|Existing file kept)' <<<"$out"; then
    ok "2b a second --skills-only run reports only files already up to date"
else ko "2b a second --skills-only run reports only files already up to date" "$out"; fi

# A changed command reaches its skill on the next run, with no merge step: generated files are
# refreshed. The vendored copy is a team file and keeps the never-overwrite rule, so while it differs
# the skill stops naming it and follows procedure.md, and the report says why.
MP="$M/plugins-copy"
cp -R "$KIT/plugins" "$MP"
bash "$KIT/install.sh" --target "$M/regen" --init --plugin-src "$MP" --skills-dir "$M/regen-skills" >/dev/null 2>&1
printf '\nOne more line, added upstream.\n' >> "$MP/projects/commands/board.md"
out="$(bash "$KIT/install.sh" --target "$M/regen" --plugin-src "$MP" --skills-dir "$M/regen-skills" 2>&1)"
if [[ -f "$M/regen/.claude/plugins/projects/commands/board.md.kit-incoming" ]] \
    && grep -q 'One more line, added upstream' "$M/regen-skills/projects-board/procedure.md" \
    && [[ -z "$(find "$M/regen-skills" -name '*.kit-incoming')" ]] \
    && ! grep -q 'in this repository' "$M/regen-skills/projects-board/SKILL.md" \
    && grep -q 'in this repository' "$M/regen-skills/projects-new/SKILL.md" \
    && grep -q 'skill projects-board follows procedure.md' <<<"$out"; then
    ok "2b a changed command regenerates its skill; while the vendored copy differs, the skill follows procedure.md and says so"
else ko "2b a changed command regenerates its skill; while the vendored copy differs, the skill follows procedure.md and says so" \
    "$out"; fi

# A command the kit later drops leaves its generated skill, its Gemini wrapper and its vendored copy
# behind, since the installer never deletes; the next run names each one as a file to delete.
MR="$M/plugins-retired"
cp -R "$KIT/plugins" "$MR"
printf -- '---\ndescription: A command that a later version drops\n---\n\nBody.\n' > "$MR/projects/commands/retired.md"
bash "$KIT/install.sh" --target "$M/retire" --init --surfaces claude,gemini --plugin-src "$MR" --skills-dir "$M/retire-skills" >/dev/null 2>&1
rm "$MR/projects/commands/retired.md"
out="$(bash "$KIT/install.sh" --target "$M/retire" --surfaces claude,gemini --plugin-src "$MR" --skills-dir "$M/retire-skills" 2>&1)"
if grep -q "retire-skills/projects-retired/ was generated from plugins/projects/commands/retired.md" <<<"$out" \
    && grep -q "^  .gemini/commands/projects/retired.toml was generated from" <<<"$out" \
    && grep -q "^  .claude/plugins/projects/commands/retired.md has no counterpart in the kit" <<<"$out" \
    && [[ "$(grep -c 'no longer has\|no counterpart' <<<"$out")" == 3 && -f "$M/retire-skills/projects-retired/SKILL.md" ]]; then
    ok "2b a command the kit has dropped is named on every surface as a file to delete, and nothing is deleted"
else ko "2b a command the kit has dropped is named on every surface as a file to delete, and nothing is deleted" "$out"; fi

# ---------------------------------------------------------------------------------------------------
echo
echo "3 · JSON, TOML, plugin versions, marketplaces"

# team/claude-settings.json is a template: the installer fills __MARKETPLACE_SOURCE__ with a JSON
# object, so it is parsed with a representative one in place.
bad=""
while IFS= read -r f; do
    sed 's|__MARKETPLACE_SOURCE__|{ "source": "directory", "path": ".claude/plugins" }|' "$f" | jq empty >/dev/null 2>&1 \
        || bad+="${f#"$KIT"/}"$'\n'
done < <(find "$KIT" -name '*.json' -not -path '*/.git/*' | sort)
empty "3 every JSON file in the kit parses (templates with their placeholder filled)" "$bad"
bad=""
while IFS= read -r f; do jq empty "$f" >/dev/null 2>&1 || bad+="${f#"$SCRATCH"/}"$'\n'; done \
    < <(find "$T1" "$T2" -name '*.json' -not -path '*/.git/*' | sort)
empty "3 every JSON file an install writes parses" "$bad"

# Gemini CLI is frozen: its wrappers are still generated on request, but parsing them needs
# python3 3.11+ (tomllib), which a stock macOS python3 is not. The check runs on request only.
if [[ -z "${AW_TEST_GEMINI:-}" ]]; then
    skp "3 Gemini TOML wrappers not parsed — Gemini CLI is frozen; set AW_TEST_GEMINI=1 to check them"
elif ! python3 -c 'import tomllib' 2>/dev/null; then
    skp "3 Gemini TOML wrappers not parsed — $(python3 --version 2>&1) has no tomllib (3.11+)"
else
    toml_ok() { python3 -c 'import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert isinstance(d.get("prompt"), str) and d["prompt"].strip(), "no prompt"
assert isinstance(d.get("description"), str) and d["description"].strip(), "no description"' "$1"; }
    bad="" n=0
    while IFS= read -r f; do
        n=$((n + 1)); toml_ok "$f" >/dev/null 2>&1 || bad+="${f#"$SCRATCH"/}"$'\n'
    done < <(find "$T1/.gemini" "$T2/.gemini" -name '*.toml' 2>/dev/null | sort)
    [[ $n -gt 0 ]] || bad="no TOML files were generated"
    empty "3 every generated TOML ($n) parses, with a description and a prompt" "$bad"
fi

check "3 the kit ships no hand-written Gemini wrapper" test -z "$(find "$KIT/team" -name '*.toml')"

bad=""
for pj in "$KIT"/plugins/*/.claude-plugin/plugin.json; do
    jq -e '(.version | type == "string") and (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+"))' "$pj" >/dev/null 2>&1 \
        || bad+="${pj#"$KIT"/}"$'\n'
done
empty "3 every plugin.json carries a semantic version" "$bad"

# lists_plugins <marketplace.json> <source prefix> <plugins root>: every plugin directory in the kit
# is listed, its source resolves to that plugin, and the three the kit ships are there by name.
lists_plugins() {
    local mp="$1" prefix="$2" root="$3" d name src problems=""
    for name in closeout projects workspace; do
        jq -e --arg n "$name" '.plugins | map(.name) | index($n) != null' "$mp" >/dev/null || problems+="$name not listed"$'\n'
    done
    for d in "$KIT"/plugins/*/; do
        name="$(basename "$d")"
        src="$(jq -r --arg n "$name" '.plugins[] | select(.name == $n) | .source' "$mp")"
        if [[ -z "$src" ]]; then problems+="$name not listed"$'\n'; continue; fi
        [[ "$src" == "$prefix$name" ]] || problems+="$name source is $src"$'\n'
        [[ -f "$root/$name/.claude-plugin/plugin.json" ]] || problems+="$name source does not resolve under $root"$'\n'
    done
    printf '%s' "$problems" | sort -u
}
empty "3 the root marketplace lists all three plugins, and every plugin in plugins/" \
    "$(lists_plugins "$KIT/.claude-plugin/marketplace.json" "./plugins/" "$KIT/plugins")"
empty "3 the vendored marketplace lists all three plugins, and every plugin in plugins/" \
    "$(lists_plugins "$T1/.claude/plugins/.claude-plugin/marketplace.json" "./" "$T1/.claude/plugins")"
# §9.2: the optional "$schema" key is ignored at load time and names a vendor URL, so no marketplace carries it.
empty "3 no marketplace file carries a \$schema key" \
    "$(for f in "$KIT"/.claude-plugin/marketplace.json "$KIT"/plugins/*/.claude-plugin/marketplace.json \
            "$T1/.claude/plugins/.claude-plugin/marketplace.json"; do
        [[ -f "$f" ]] && jq -e 'has("$schema")' "$f" >/dev/null && echo "$f"; done)"

bad=""
for d in "$KIT"/plugins/*/; do
    name="$(basename "$d")" ver="$(jq -r .version "$d/.claude-plugin/plugin.json")"
    grep -qx "$name $ver" "$T1/.claude/plugins/VENDORED" || bad+="VENDORED lacks '$name $ver'"$'\n'
    diff -rq -x .DS_Store -x .git "$d" "$T1/.claude/plugins/$name" >/dev/null 2>&1 || bad+="vendored $name differs from the kit"$'\n'
done
empty "3 VENDORED names each plugin's version, and each vendored copy matches the kit" "$bad"

bad="$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$T1/.claude/settings.json")"
missing=""
for name in closeout projects workspace; do grep -qx "$name@agentic-workspace" <<<"$bad" || missing+="$name@agentic-workspace"$'\n'; done
empty "3 .claude/settings.json enables all three plugins" "$missing"

# One source per procedure works on both surfaces only if commands speak of arguments in prose.
empty "3 no command uses a tool-specific argument placeholder" \
    "$(cd "$KIT" && grep -nE '\$ARGUMENTS|\{\{args\}\}' plugins/*/commands/*.md 2>/dev/null)"

bad=""
while IFS= read -r f; do bash -n "$f" 2>/dev/null || bad+="${f#"$KIT"/}"$'\n'; done \
    < <(find "$KIT" -name '*.sh' -not -path '*/.git/*' | sort)
empty "3 every shell script passes bash -n" "$bad"

# ---------------------------------------------------------------------------------------------------
echo
echo "4 · Closeout hooks: team detection, capture prompt, review pointer"

HOOKS="$KIT/plugins/closeout/hooks"
# Capitals-for-emphasis in the prompts the hooks hand an agent: section 8's four words plus the shouted
# negatives and qualifiers the hooks once used. Whole words only, so acronyms and names pass; the tier
# table's ALWAYS is a load-rate label, not emphasis, and is left out. Three capitalised words in a row
# ("CAN BE STALE") count too, whatever they are.
shouted='MUST|NEVER|CRITICAL|IMPORTANT|NOT|DO NOT|ONLY|ALSO|CANNOT|([A-Z]{2,}[[:space:]]+){2}[A-Z]{2,}'
# The personal conventions layer (closeout 1.2.0) is off for every check in this section unless a
# check turns it on, so the runner's own ~/.claude/closeout.md never reaches a fixture.
export CLOSEOUT_USER_CONVENTIONS=""
DRAFTS="$SCRATCH/drafts"

# team_of <project> [VAR=value...]: TEAM_COUNT|comma-separated members, as the hooks compute them.
team_of() {
    local project="$1"; shift
    env "$@" CLOSEOUT_DRAFT_ROOT="$DRAFTS" bash -c '
        source "$1/lib/config.sh"; closeout_config "$2"
        printf "%s|%s" "$TEAM_COUNT" "$(printf "%s" "$TEAM_MEMBERS" | paste -sd, -)"' _ "$HOOKS" "$project"
}
mkproject() { # <name> <person>...: a project with one profile per person, plus a README to ignore
    local p="$SCRATCH/projects/$1"; shift
    mkdir -p "$p/.claude"
    if [[ $# -gt 0 ]]; then
        mkdir -p "$p/memory/people"
        printf '# People\n' > "$p/memory/people/README.md"
        local who; for who in "$@"; do printf '# %s\n' "$who" > "$p/memory/people/$who.md"; done
    fi
    printf '%s' "$p"
}

P0="$(mkproject zero)"
P1="$(mkproject one alex)"
P3="$(mkproject three alex blair casey)"
PC="$(mkproject conventions alex)"
printf '# Closeout conventions\n\nMARKER-CONVENTIONS-VERBATIM\n\n## Team\n\n- alex\n- dana\n\n## Other\n\n- not-a-person\n' > "$PC/.claude/closeout.md"

r="$(team_of "$P0")"; [[ "$r" == "0|" ]] && ok "4 team: no people directory → 0" || ko "4 team: no people directory → 0" "got $r"
r="$(team_of "$P1")"; [[ "$r" == "1|alex" ]] && ok "4 team: one profile → 1" || ko "4 team: one profile → 1" "got $r"
r="$(team_of "$P3")"; [[ "$r" == "3|alex,blair,casey" ]] && ok "4 team: three profiles, README ignored → 3" || ko "4 team: three profiles, README ignored → 3" "got $r"
r="$(team_of "$P3" CLOSEOUT_TEAM=" dana , eli,")"; [[ "$r" == "2|dana,eli" ]] && ok "4 team: CLOSEOUT_TEAM overrides the profiles" || ko "4 team: CLOSEOUT_TEAM overrides the profiles" "got $r"
r="$(team_of "$PC")"; [[ "$r" == "2|alex,dana" ]] && ok "4 team: a Team section in the conventions adds to the profiles, deduplicated" || ko "4 team: a Team section in the conventions adds to the profiles, deduplicated" "got $r"

# A stub claude on PATH records how the capture hook would have launched the headless child.
STUB="$SCRATCH/bin"
mkdir -p "$STUB"
cat > "$STUB/claude" <<'STUBSCRIPT'
#!/usr/bin/env bash
out="${STUB_OUT:?}"
pwd -P > "$out.pwd"
printf '%s' "${CLOSEOUT_HOOK_CHILD:-}" > "$out.child"
printf '%s\n' "$@" > "$out.args"
printf '%s' "$2" > "$out.prompt"
: > "$out.done"
STUBSCRIPT
chmod +x "$STUB/claude"

TRANSCRIPT="$SCRATCH/transcripts/session.jsonl"
mkdir -p "$(dirname "$TRANSCRIPT")"
for i in 1 2 3 4 5 6 7 8; do printf '{"line":%d}\n' "$i" >> "$TRANSCRIPT"; done
printf '{"line":1}\n' > "$SCRATCH/transcripts/short.jsonl"

# capture <project> <session> [reason] [transcript] [VAR=value...]
# Runs the SessionEnd hook, then waits for the detached stub to report. Returns 0 if the stub ran.
# Each session gets its own record prefix ($SCRATCH/rec-<session>), so a slow stub from one call can
# never be read as the result of another; the hook's own exit status is left in $crc. A positive
# case waits up to five seconds; a negative one (CAPTURE_WAIT=10, a second) only needs to show
# that nothing was launched, and is always paired with a control that does launch.
capture() {
    local project="$1" sid="$2" reason="${3:-prompt_input_exit}" tr="${4:-$TRANSCRIPT}" i
    shift 4 2>/dev/null || shift $#
    REC="$SCRATCH/rec-$sid"
    rm -f "$REC".*
    jq -nc --arg r "$reason" --arg t "$tr" --arg s "$sid" --arg c "$project" \
        '{reason: $r, transcript_path: $t, session_id: $s, cwd: $c}' \
        | env PATH="$STUB:$PATH" STUB_OUT="$REC" CLOSEOUT_DRAFT_ROOT="$DRAFTS" "$@" bash "$HOOKS/closeout-capture.sh" >/dev/null 2>&1
    crc=$?
    for i in $(seq 1 "${CAPTURE_WAIT:-50}"); do [[ -f "$REC.done" ]] && return 0; sleep 0.1; done
    return 1
}
# suppressed <description> <control session> <session> <capture args...>: the control call (same
# project, nothing suppressing) must launch the stub; the suppressed call must exit 0 and launch nothing.
suppressed() {
    local d="$1" ctl="$2"; shift 2
    if ! capture "$P1" "$ctl"; then ko "$d" "the control call never launched the stub, so the check proves nothing"; return; fi
    if CAPTURE_WAIT=10 capture "$@"; then ko "$d" "the stub ran"
    elif [[ $crc -ne 0 ]]; then ko "$d" "the hook exited $crc rather than stopping on purpose"
    else ok "$d"; fi
}

if capture "$P3" s-three; then
    ok "4 capture: spawns the claude found on PATH"
    prompt="$(cat "$REC.prompt")"
    grep -qF "$TRANSCRIPT" <<<"$prompt" && ok "4 capture prompt names the transcript" || ko "4 capture prompt names the transcript"
    grep -qF "$DRAFTS/three/s-three.md" <<<"$prompt" && ok "4 capture prompt names the per-session draft file" || ko "4 capture prompt names the per-session draft file"
    grep -qF '| Working standards |' <<<"$prompt" && ok "4 capture prompt carries the default tier table" || ko "4 capture prompt carries the default tier table"
    if grep -qF 'more than one person' <<<"$prompt" && grep -qF 'Who needs to' <<<"$prompt" \
        && grep -qE '^  - casey$' <<<"$prompt"; then
        ok "4 capture prompt adds who-needs-to-know for three people, naming them"
    else ko "4 capture prompt adds who-needs-to-know for three people, naming them"; fi
    # The capture prompt is guidance an agent reads, so it is held to the same register as section 8,
    # with the wider set of shouted words ($shouted) that hook prompts are also checked for.
    empty "4 capture prompt has no capitals-for-emphasis" "$(grep -nwE "$shouted" <<<"$prompt" || true)"
    [[ "$(cat "$REC.pwd")" == "$(cd "$DRAFTS/three" && pwd -P)" ]] \
        && ok "4 capture child runs from the draft directory" || ko "4 capture child runs from the draft directory" "pwd was $(cat "$REC.pwd")"
    [[ "$(cat "$REC.child")" == "1" ]] && ok "4 capture child carries the recursion guard" || ko "4 capture child carries the recursion guard"
    if grep -qx -- '--allowedTools' "$REC.args" && grep -qx 'Read,Write' "$REC.args" \
        && grep -qx -- '-p' "$REC.args" && grep -qxF "$DRAFTS/three" "$REC.args"; then
        ok "4 capture child is limited to Read,Write with the draft directory added"
    else ko "4 capture child is limited to Read,Write with the draft directory added" "$(cat "$REC.args" | grep -E '^--' )"; fi
else
    ko "4 capture: spawns the claude found on PATH" "the stub never ran"
fi

if capture "$P1" s-one; then
    grep -qF 'more than one person' "$REC.prompt" && ko "4 capture prompt leaves out who-needs-to-know for one person" \
        || ok "4 capture prompt leaves out who-needs-to-know for one person"
else ko "4 capture prompt leaves out who-needs-to-know for one person" "the stub never ran"; fi

if capture "$PC" s-conv; then
    if grep -qF 'MARKER-CONVENTIONS-VERBATIM' "$REC.prompt" && grep -qE '^  - dana$' "$REC.prompt"; then
        ok "4 capture prompt appends the conventions verbatim and names the Team section's people"
    else ko "4 capture prompt appends the conventions verbatim and names the Team section's people"; fi
else ko "4 capture prompt appends the conventions verbatim and names the Team section's people" "the stub never ran"; fi

PT="$(mkproject tiers)"
printf '# Conventions\n\n## Promotion tiers\n\n| Tier | Where |\n|---|---|\n| Handbook | docs/ |\n' > "$PT/.claude/closeout.md"
if capture "$PT" s-tiers; then
    if grep -qF 'defines its own promotion tiers' "$REC.prompt" && ! grep -qF '| Working standards |' "$REC.prompt"; then
        ok "4 capture prompt yields to a project's own promotion tiers"
    else ko "4 capture prompt yields to a project's own promotion tiers"; fi
else ko "4 capture prompt yields to a project's own promotion tiers" "the stub never ran"; fi

suppressed "4 capture: the recursion guard stops a child from spawning another" \
    s-guard-ctl "$P1" s-guard prompt_input_exit "$TRANSCRIPT" CLOSEOUT_HOOK_CHILD=1
suppressed "4 capture: /clear is not captured" s-clear-ctl "$P1" s-clear clear
suppressed "4 capture: a trivial transcript is not captured" \
    s-short-ctl "$P1" s-short prompt_input_exit "$SCRATCH/transcripts/short.jsonl"

mkdir -p "$DRAFTS/one"
: > "$DRAFTS/one/.closeout-ran.s-fresh"
suppressed "4 capture: a fresh /closeout sentinel for this session suppresses capture" s-fresh-ctl "$P1" s-fresh
check "4 capture: the fresh sentinel is consumed" test ! -e "$DRAFTS/one/.closeout-ran.s-fresh"
: > "$DRAFTS/one/.closeout-ran.s-stale"; age "$DRAFTS/one/.closeout-ran.s-stale" 0.3   # about seven hours
capture "$P1" s-stale && ok "4 capture: a stale sentinel is not honoured" || ko "4 capture: a stale sentinel is not honoured"
check "4 capture: the stale sentinel is removed" test ! -e "$DRAFTS/one/.closeout-ran.s-stale"
: > "$DRAFTS/one/.closeout-ran.s-other"
capture "$P1" s-mine && ok "4 capture: another session's sentinel does not suppress this one" || ko "4 capture: another session's sentinel does not suppress this one"

# review <project> [VAR=value...]: the SessionStart hook's stdout.
review() {
    local project="$1"; shift
    jq -nc --arg c "$project" '{cwd: $c, source: "startup"}' \
        | env CLOSEOUT_DRAFT_ROOT="$DRAFTS" "$@" bash "$HOOKS/closeout-review.sh" 2>/dev/null
}
PR="$(mkproject reviewed alex blair casey)"
DR="$DRAFTS/reviewed"
empty "4 review: silent when there are no drafts" "$(review "$PR")"
mkdir -p "$DR"
printf '### a claim\n' > "$DR/s1.md"
empty "4 review: silent inside the capture child, and marks nothing" "$(review "$PR" CLOSEOUT_HOOK_CHILD=1)$(ls -A "$DR" | grep '^\.seen' || true)"
outr="$(review "$PR")"
if jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' <<<"$outr" >/dev/null 2>&1 \
    && jq -r '.hookSpecificOutput.additionalContext' <<<"$outr" | grep -qF "$DR/s1.md"; then
    ok "4 review: a pending draft is surfaced as SessionStart additionalContext"
else ko "4 review: a pending draft is surfaced as SessionStart additionalContext" "$outr"; fi
jq -r '.hookSpecificOutput.additionalContext' <<<"$outr" | grep -qF 'more than one person' \
    && ok "4 review: names the who-needs-to-know step when the project has a team" || ko "4 review: names the who-needs-to-know step when the project has a team"
empty "4 review: the injected context has no capitals-for-emphasis" \
    "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$outr" | grep -nwE "$shouted" || true)"
check "4 review: the first surfacing leaves a .seen marker" test -f "$DR/.seen.s1.md"
age "$DR/.seen.s1.md" 1
before="$(python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$DR/.seen.s1.md")"
review "$PR" >/dev/null
after="$(python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$DR/.seen.s1.md")"
[[ "$before" == "$after" ]] && ok "4 review: a later surfacing leaves the marker's date alone" || ko "4 review: a later surfacing leaves the marker's date alone"
printf '### old capture\n' > "$DR/s2.md"; age "$DR/s2.md" 10
age "$DR/.seen.s1.md" 5
: > "$DR/.seen.gone.md"
outr="$(review "$PR")"
check "4 review: a draft first surfaced beyond the retention window is pruned with its marker" test ! -e "$DR/s1.md" -a ! -e "$DR/.seen.s1.md"
if [[ -f "$DR/s2.md" && -f "$DR/.seen.s2.md" ]] && jq -r '.hookSpecificOutput.additionalContext' <<<"$outr" | grep -qF "$DR/s2.md"; then
    ok "4 review: an old draft never yet surfaced is kept and surfaced (retention counts from first surfacing)"
else ko "4 review: an old draft never yet surfaced is kept and surfaced (retention counts from first surfacing)"; fi
check "4 review: a marker whose draft is gone is removed" test ! -e "$DR/.seen.gone.md"

# Retention prunes only top-level *.md drafts, and only in a folder a session opens again: a file of
# another kind, a subdirectory, and the drafts of a folder nobody reopens outlive any window. Those
# are what the drafts sweep in /workspace:hygiene lists.
PS="$(mkproject swept)"
DS="$DRAFTS/swept"
mkdir -p "$DS/research" "$DRAFTS/not-reopened"
printf '### a claim\n' > "$DS/t1.md"; printf 'transcript\n' > "$DS/_sess.txt"
printf '### notes\n' > "$DS/research/n.md"; printf '### a claim\n' > "$DRAFTS/not-reopened/t2.md"
for f in "$DS/_sess.txt" "$DS/research/n.md" "$DS/research" "$DRAFTS/not-reopened/t2.md"; do age "$f" 30; done
review "$PS" >/dev/null; age "$DS/.seen.t1.md" 30; review "$PS" >/dev/null
check "4 review: a surfaced draft past the window is pruned (the control for the three below)" test ! -e "$DS/t1.md"
check "4 review: retention leaves a file that is not a *.md draft, 30 days on" test -f "$DS/_sess.txt"
check "4 review: retention leaves a subdirectory and its contents, 30 days on" test -f "$DS/research/n.md"
check "4 review: retention leaves the drafts of a folder no session reopens" test -f "$DRAFTS/not-reopened/t2.md"
for f in plugins/workspace/commands/hygiene.md rituals/weekly-hygiene.md; do
    grep -qi 'drafts sweep' "$KIT/$f" && ok "4 the drafts sweep is named in $f" || ko "4 the drafts sweep is named in $f"
done

# Personal conventions (closeout 1.2.0): read after the project's, which win where they disagree.
UC="$SCRATCH/user/closeout.md" UT="$SCRATCH/user/tiers.md" FH="$SCRATCH/user-home"
mkdir -p "$SCRATCH/user" "$FH/.claude"
printf '# Mine\n\nMARKER-USER-CONVENTIONS\n\n## Team\n\n- zed\n' > "$UC"
printf '# Mine\n\n## Promotion tiers\n\n| Tier | Where |\n|---|---|\n| Personal | notes/ |\n' > "$UT"
printf '# Mine\n\nMARKER-USER-HOME\n' > "$FH/.claude/closeout.md"
r="$(team_of "$P1" CLOSEOUT_USER_CONVENTIONS="$UC")"; [[ "$r" == "1|alex" ]] && ok "4 user conventions: a Team section there adds nobody to the project" || ko "4 user conventions: a Team section there adds nobody to the project" "got $r"
if capture "$PC" s-user-both prompt_input_exit "$TRANSCRIPT" CLOSEOUT_USER_CONVENTIONS="$UC"; then
    a="$(grep -nF MARKER-CONVENTIONS-VERBATIM "$REC.prompt" | head -n 1 | cut -d: -f1)"
    b="$(grep -nF MARKER-USER-CONVENTIONS "$REC.prompt" | head -n 1 | cut -d: -f1)"
    if [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]] && grep -qF "the project's win" "$REC.prompt"; then
        ok "4 capture prompt appends the personal conventions after the project's, and says the project's win"
    else ko "4 capture prompt appends the personal conventions after the project's, and says the project's win" "project marker line ${a:-none}, personal marker line ${b:-none}"; fi
else ko "4 capture prompt appends the personal conventions after the project's, and says the project's win" "the stub never ran"; fi
# The default path is ~/.claude/closeout.md: a subshell unsets the override and moves HOME for one call.
if ( unset CLOSEOUT_USER_CONVENTIONS; HOME="$FH" capture "$P1" s-user-home ) \
    && grep -qF MARKER-USER-HOME "$SCRATCH/rec-s-user-home.prompt"; then
    ok "4 capture prompt reads ~/.claude/closeout.md by default"
else ko "4 capture prompt reads ~/.claude/closeout.md by default"; fi
if ( HOME="$FH" capture "$P1" s-user-off prompt_input_exit "$TRANSCRIPT" CLOSEOUT_USER_CONVENTIONS= ) \
    && ! grep -qF MARKER-USER-HOME "$SCRATCH/rec-s-user-off.prompt"; then
    ok "4 capture: an empty CLOSEOUT_USER_CONVENTIONS leaves the personal layer out"
else ko "4 capture: an empty CLOSEOUT_USER_CONVENTIONS leaves the personal layer out"; fi
if capture "$P1" s-user-tiers prompt_input_exit "$TRANSCRIPT" CLOSEOUT_USER_CONVENTIONS="$UT"; then
    if grep -qF 'conventions, below, define the promotion tiers' "$REC.prompt" && ! grep -qF '| Working standards |' "$REC.prompt"; then
        ok "4 capture: personal promotion tiers replace the default table where the project defines none"
    else ko "4 capture: personal promotion tiers replace the default table where the project defines none"; fi
else ko "4 capture: personal promotion tiers replace the default table where the project defines none" "the stub never ran"; fi
if capture "$PT" s-user-ptiers prompt_input_exit "$TRANSCRIPT" CLOSEOUT_USER_CONVENTIONS="$UT"; then
    if grep -qF 'This project defines its own promotion tiers' "$REC.prompt" && ! grep -qF 'conventions, below, define the promotion tiers' "$REC.prompt"; then
        ok "4 capture: the project's promotion tiers win over personal ones"
    else ko "4 capture: the project's promotion tiers win over personal ones"; fi
else ko "4 capture: the project's promotion tiers win over personal ones" "the stub never ran"; fi
PU="$(mkproject personal)"
printf '# Conventions\n\nMARKER-PROJECT\n' > "$PU/.claude/closeout.md"
mkdir -p "$DRAFTS/personal"; printf '### a claim\n' > "$DRAFTS/personal/s1.md"
outr="$(review "$PU" CLOSEOUT_USER_CONVENTIONS="$UC" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
if grep -qF "$UC" <<<"$outr" && grep -qF "the project's win" <<<"$outr"; then
    ok "4 review: names the personal conventions file, read after the project's"
else ko "4 review: names the personal conventions file, read after the project's" "$outr"; fi

# ---------------------------------------------------------------------------------------------------
echo
echo "4b · Projects session-start line (F13)"

PHOOK="$KIT/plugins/projects/hooks/session-start.sh"
PSTAMPS="$SCRATCH/projects-stamps"

# pstart <cwd> [VAR=value...]: the projects SessionStart hook's stdout; its exit code and stderr
# are checked separately below.
pstart() {
    local cwd="$1"; shift
    jq -nc --arg c "$cwd" '{cwd: $c, source: "startup"}' \
        | env PROJECTS_HOOK_STATE_DIR="$PSTAMPS" "$@" bash "$PHOOK" 2>/dev/null
}
pmsg() { jq -r '.systemMessage // empty' 2>/dev/null; }

PF="$SCRATCH/projects-f13"
mkdir -p "$PF/.claude" "$PF/projects"
git -C "$PF" init -q
cp "$KIT/team/projects-conventions.md" "$PF/.claude/projects.md"
for i in $(seq -w 1 19); do
    mkdir -p "$PF/projects/p$i"
    printf '# Project p%s\n\n## Desired outcome\n\nThe p%s rollout is live\nfor every team.\n\n## Done when\n\n- [x] one\n- [ ] two\n- [x] three\n- [ ] four\n\n## Current state\n\n- **State:** doing\n- **Updated:** 2026-09-24\n\n2026-09-24 — Priya has the p%s draft with the sponsor.\n\n## People\n\n- Sam — owns — `memory/people/sam.md`\n- Priya — does\n' \
        "$i" "$i" "$i" > "$PF/projects/p$i/README.md"
done
mkdir -p "$PF/projects/gap/notes"
printf '# Gap\n\n<!-- proposed by /projects:adopt 2026-09-28: confirm or edit -->\n## Current state\n\nState: ready\nBlocked by: not yet named\n' > "$PF/projects/gap/README.md"

out="$(pstart "$PF/projects/p07")"
msg="$(pmsg <<<"$out")"
if [[ "$(printf '%s\n' "$msg" | grep -c .)" == "3" ]] \
    && grep -qxF 'Project: Project p07 — outcome: The p07 rollout is live for every team.' <<<"$msg" \
    && grep -qxF 'Done when: 2 of 4 ticked' <<<"$msg" \
    && grep -qxF 'State: doing — owner Sam' <<<"$msg"; then
    ok "4b session-start: three lines in a project folder — outcome, done-when progress, state and owner"
else ko "4b session-start: three lines in a project folder — outcome, done-when progress, state and owner" "$msg"; fi
jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | contains("projects/p07/README.md"))' <<<"$out" >/dev/null 2>&1 \
    && ok "4b session-start: the agent gets the same lines as additionalContext, naming the file" \
    || ko "4b session-start: the agent gets the same lines as additionalContext, naming the file" "$out"
msg="$(pstart "$PF/projects/gap/notes" | pmsg)"
grep -qF 'Project: Gap (proposed)' <<<"$msg" && grep -qxF 'State: ready — no owner named' <<<"$msg" \
    && ok "4b session-start: a 'not yet named' blocker is a gap, and a proposed block says so, from a subfolder" \
    || ko "4b session-start: a 'not yet named' blocker is a gap, and a proposed block says so, from a subfolder" "$msg"

# What blocks a project is on the state line, with its date: after "blocked" when that is the state,
# after the state otherwise.
mkdir -p "$PF/projects/held" "$PF/projects/snag"
printf '# Held\n\n## Current state\n\n- **State:** blocked\n- **Blocked by:** the signed budget from finance — since 2026-09-01\n\n## People\n\n- Dana — owns\n' > "$PF/projects/held/README.md"
printf '# Snag\n\n## Current state\n\n- **State:** doing\n- **Blocked by:** the test rig\n  being rebuilt\n\n## People\n\n- Dana — owns\n' > "$PF/projects/snag/README.md"
msg="$(pstart "$PF/projects/held" | pmsg)"
grep -qxF 'State: blocked by the signed budget from finance — since 2026-09-01 — owner Dana' <<<"$msg" \
    && ok "4b session-start: a blocked project names what blocks it and since when" \
    || ko "4b session-start: a blocked project names what blocks it and since when" "$msg"
msg="$(pstart "$PF/projects/snag" | pmsg)"
grep -qxF 'State: doing — blocked by the test rig being rebuilt — owner Dana' <<<"$msg" \
    && ok "4b session-start: a Blocked by line on another state is named after it, joined across a wrapped line" \
    || ko "4b session-start: a Blocked by line on another state is named after it, joined across a wrapped line" "$msg"
rm -rf "$PF/projects/held" "$PF/projects/snag"

# Outside a project: one line on the first session of a day when an active project has been blocked
# for more than 14 days, then nothing that day. Paused and done projects, a blocker 14 days old, and
# one dated only by a due date are not named.
mkdir -p "$PF/projects/stuck" "$PF/projects/fresh" "$PF/projects/due" "$PF/projects/resting" "$PF/projects/over"
printf '# Stuck one\n\n## Current state\n\n- **State:** blocked\n- **Blocked by:** legal sign-off — since 2025-12-01\n' > "$PF/projects/stuck/README.md"
printf '# Fresh\n\n## Current state\n\n- **State:** blocked\n- **Blocked by:** a quote — since 2025-12-19\n' > "$PF/projects/fresh/README.md"
printf '# Due\n\n## Current state\n\n- **State:** blocked\n- **Blocked by:** a quote, due 2025-11-01\n' > "$PF/projects/due/README.md"
printf '# Resting\n\n## Current state\n\n- **State:** paused\n- **Blocked by:** a hire — since 2025-10-01\n' > "$PF/projects/resting/README.md"
printf '# Over\n\n## Current state\n\n- **State:** done\n- **Blocked by:** a hire — since 2025-10-01\n' > "$PF/projects/over/README.md"
msg="$(pstart "$PF" PROJECTS_HOOK_TODAY=2026-01-02 | pmsg)"
[[ "$msg" == 'Projects: 1 active project blocked for more than 14 days (Stuck one). /projects:board shows it.' ]] \
    && ok "4b session-start: outside a project, one line naming projects blocked for more than 14 days, by title" \
    || ko "4b session-start: outside a project, one line naming projects blocked for more than 14 days, by title" "$msg"
empty "4b session-start: at most once a day per repository" "$(pstart "$PF" PROJECTS_HOOK_TODAY=2026-01-02)"
empty "4b session-start: the once-a-day stamp lives outside the repository" "$(find "$PF" -name '*.last')"
# Both dated blockers are cleared, so the next day, when Fresh's would have passed 14 days, is clean.
printf '# Stuck one\n\n## Current state\n\n- **State:** doing\n' > "$PF/projects/stuck/README.md"
printf '# Fresh\n\n## Current state\n\n- **State:** doing\n' > "$PF/projects/fresh/README.md"
empty "4b session-start: prints nothing outside a project folder on a clean day" "$(pstart "$PF" PROJECTS_HOOK_TODAY=2026-01-03)"
check "4b session-start: a clean day records no stamp, so a later blocker still surfaces that day" \
    test "$(cat "$PSTAMPS"/*.last 2>/dev/null)" = "2026-01-02"
rm -rf "$PF/projects/stuck" "$PF/projects/fresh" "$PF/projects/due" "$PF/projects/resting" "$PF/projects/over"

# The shared reading rules: with no People section the register names the owner; a bold State reads
# as its word.
mkdir -p "$PF/projects/03-reg"
printf '# Reg

## Current state

- **State:** **doing**
- **Updated:** 2026-09-20
' > "$PF/projects/03-reg/README.md"
printf '# Projects

## Active

| Project | Folder | State | Owner | One-liner |
|---|---|---|---|---|
| Reg | `projects/03-reg/` | doing | Kim Lee | x |
' > "$PF/projects/INDEX.md"
msg="$(pstart "$PF/projects/03-reg" | pmsg)"
grep -qF 'Project: Reg — ' <<<"$msg" && grep -qxF 'State: doing — owner Kim Lee' <<<"$msg" \
    && ok "4b session-start: with no People section the register row names the owner, and a bold State reads plainly" \
    || ko "4b session-start: with no People section the register row names the owner, and a bold State reads plainly" "$msg"

# A done project says how it ended, dated by its Updated line, rather than giving a state; a CLAUDE.md
# entry point's title is the project's name, not the file's description.
mkdir -p "$PF/projects/shipped" "$PF/projects/thesis"
printf '# Shipped\n\n## Done when\n\n- [x] it ships\n\n## Current state\n\n- **State:** done\n- **Updated:** 2026-10-13\n\n## People\n\n- Tom — owns\n' > "$PF/projects/shipped/README.md"
printf '# Thesis rewrite — agent entry point\n\n## Current state\n\n- **State:** doing\n- **Updated:** 2026-09-20\n' > "$PF/projects/thesis/CLAUDE.md"
msg="$(pstart "$PF/projects/shipped" | pmsg)"
grep -qxF 'Done 2026-10-13; how it ended is recorded in README.md' <<<"$msg" && ! grep -q '^State:' <<<"$msg" \
    && ok "4b session-start: a done project reads as done, with its Updated date" \
    || ko "4b session-start: a done project reads as done, with its Updated date" "$msg"
grep -qF 'Project: Thesis rewrite — ' <<<"$(pstart "$PF/projects/thesis" | pmsg)" \
    && ok "4b session-start: a CLAUDE.md entry point is named by its title before the dash" \
    || ko "4b session-start: a CLAUDE.md entry point is named by its title before the dash" "$(pstart "$PF/projects/thesis" | pmsg)"

# A block in its earlier format (a Now heading) is still read, and the line says adopt converts it.
mkdir -p "$PF/projects/legacy"
printf '# Legacy\n\n## Now\n\n- **State:** doing\n\n## People\n\n- Ana — owns\n' > "$PF/projects/legacy/README.md"
msg="$(pstart "$PF/projects/legacy" | pmsg)"
grep -qxF 'State: doing — owner Ana — from an older Now block; /projects:adopt converts it' <<<"$msg" \
    && ok "4b session-start: an older Now block is read and labelled for conversion by /projects:adopt" \
    || ko "4b session-start: an older Now block is read and labelled for conversion by /projects:adopt" "$msg"
rm -rf "$PF/projects/legacy"

# Conventions: a status-folder layout with its own Done when heading.
PX="$SCRATCH/projects-f13-example"
mkdir -p "$PX/.claude" "$PX/work/03-vendor-review" "$PX/work/_paused/old"
git -C "$PX" init -q
cp "$KIT/plugins/projects/examples/projects-conventions.md" "$PX/.claude/projects.md"
printf '# Vendor review\n\n## Exit criteria\n\n- [X] longlist\n- [ ] shortlist\n\n## Current state\n\nState: blocked\nBlocked by: the vendors quotes — since 2026-09-10\n' > "$PX/work/03-vendor-review/README.md"
printf '# Old\n\n## Current state\n\n- **State:** paused\n' > "$PX/work/_paused/old/README.md"
msg="$(pstart "$PX/work/03-vendor-review")"
grep -qF 'Done when: 1 of 2 ticked' <<<"$(pmsg <<<"$msg")" \
    && ok "4b session-start: follows .claude/projects.md — project folder and a Section names alias" \
    || ko "4b session-start: follows .claude/projects.md — project folder and a Section names alias" "$msg"
msg="$(pstart "$PX/work/_paused/old" | pmsg)"
grep -qF 'Project: Old — ' <<<"$msg" && grep -qF 'State: paused' <<<"$msg" \
    && ok "4b session-start: the most specific location wins (paused inside active)" \
    || ko "4b session-start: the most specific location wins (paused inside active)" "$msg"

# Silent on failure, and fast.
errs=""
for input in 'not json' '{"cwd":"/nonexistent/place"}' ''; do
    # Run from the scratch folder: with no cwd in the input the hook falls back to its own working
    # directory, and the kit's checkout may sit inside a repository with projects of its own.
    (cd "$SCRATCH" && printf '%s' "$input" | PROJECTS_HOOK_STATE_DIR="$PSTAMPS" bash "$PHOOK") >"$SCRATCH/f13.out" 2>"$SCRATCH/f13.err" \
        || errs="$errs exit $? for '$input';"
    [[ -s "$SCRATCH/f13.out" || -s "$SCRATCH/f13.err" ]] && errs="$errs output for '$input';"
done
empty "4b session-start: bad input exits 0 with no output" "$errs"
empty "4b session-start: silent when turned off, or inside the closeout capture child" \
    "$(pstart "$PF/projects/p01" PROJECTS_HOOK_DISABLED=1)$(pstart "$PF/projects/p01" CLOSEOUT_HOOK_CHILD=1)"
ms="$(python3 - "$PHOOK" "$PF" <<'PY'
import json, os, subprocess, sys, time
hook, repo = sys.argv[1], sys.argv[2]
env = dict(os.environ, PROJECTS_HOOK_STATE_DIR="/dev/null/unwritable")  # every run does the full scan
worst = 0
for cwd in (repo, repo + "/projects/p07"):
    data = json.dumps({"cwd": cwd}).encode()
    runs = []
    for _ in range(5):
        t = time.perf_counter()
        subprocess.run(["bash", hook], input=data, env=env, capture_output=True)
        runs.append(time.perf_counter() - t)
    worst = max(worst, sorted(runs)[2])
print(int(worst * 1000))
PY
)"
[[ "$ms" -lt 100 ]] && ok "4b session-start: under 100 ms with 20 projects (median ${ms} ms)" \
    || ko "4b session-start: under 100 ms with 20 projects (median ${ms} ms)"

# ---------------------------------------------------------------------------------------------------
echo
echo "5 · measure.sh --backfill on a dated fixture history"

F="$SCRATCH/measure"
mkdir -p "$F/pilot" && git -C "$F" init -q
cp "$KIT/pilot/measure.sh" "$F/pilot/measure.sh"
# fx_commit <days ago> <name> <email> <message>: commits everything at noon, local time, that day.
fx_commit() {
    local when; when="$(days_ago "$1")T12:00:00"
    git -C "$F" add -A
    GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" GIT_AUTHOR_NAME="$2" GIT_AUTHOR_EMAIL="$3" \
        GIT_COMMITTER_NAME="$2" GIT_COMMITTER_EMAIL="$3" git -C "$F" -c commit.gpgsign=false commit -q -m "$4"
}
fx_readme() { # <slug> <state>
    mkdir -p "$F/projects/$1"
    printf '# %s\n\n## Desired outcome\n\nA thing exists.\n\n## Done when\n\n- [ ] it exists\n\n## Current state\n\n- **State:** %s\n- **Updated:** %s\n' \
        "$1" "$2" "$(days_ago 0)" > "$F/projects/$1/README.md"
}
decision() { printf '\n## [%s] Decision %s\n\n**Decision**: something.\n' "$(days_ago "$1")" "$2" >> "$F/logs/decisions.md"; }

# Commit days sit mid-week so each lands in one backfill window even a day either side of midnight UTC.
mkdir -p "$F/logs" "$F/memory/people"
printf '# Manifest\n\nShared standards.\n' > "$F/AGENTS.md"
printf '@AGENTS.md\n' > "$F/CLAUDE.md"
printf '# Decisions\n' > "$F/logs/decisions.md"; decision 18 1
printf '# People\n' > "$F/memory/people/README.md"
printf '# Alex\n' > "$F/memory/people/alex.md"
mkdir -p "$F/projects"; printf '# Projects\n' > "$F/projects/INDEX.md"
fx_readme alpha doing
fx_commit 18 Alex alex@example.test "Start alpha"

decision 11 2
printf '# Blair\n' > "$F/memory/people/blair.md"
fx_readme beta ready
mkdir -p "$F/audits"; printf '# Audits\n' > "$F/audits/README.md"; printf 'report\n' > "$F/audits/hygiene-1.md"
printf '# Build list\n\n| # | Item | Owner | Due | Status |\n|---|---|---|---|---|\n| 1 | Thing one | Alex | soon | exists |\n| 2 | Thing two | Blair | later | planned |\n' > "$F/pilot/build-list.md"
fx_commit 11 Blair blair@example.test "Start beta"

decision 4 3
fx_readme alpha done
fx_commit 4 Alex alex@example.test "Alpha is done"
mkdir -p "$F/docs"; printf '# Reference\n' > "$F/docs/reference.md"
fx_commit 3 Blair blair@example.test "Reference doc"

mout="$(cd "$F" && bash pilot/measure.sh --backfill 3 2>&1)"; mrc=$?
if [[ $mrc -eq 0 && -f "$F/pilot/metrics.csv" ]]; then ok "5 --backfill 3 exits 0 and writes pilot/metrics.csv"; else ko "5 --backfill 3 exits 0 and writes pilot/metrics.csv" "$mout"; fi
CSV="$F/pilot/metrics.csv"
base="date,always_loaded_bytes,decisions_logged,doc_files,people_profiles,audit_reports,build_items_named,build_items_exist,doc_commits_7d,doc_contributors_7d"
# A prefix match, so columns appended later keep this check true.
[[ "$(head -n 1 "$CSV")" == "$base"* ]] && ok "5 the header starts with the established columns, in order" || ko "5 the header starts with the established columns, in order" "$(head -n 1 "$CSV")"
# The first commit is 18 days ago, so the week 21 days ago is left out rather than written as zeros.
[[ "$(wc -l < "$CSV" | tr -d ' ')" == "4" ]] && ok "5 one row per week from the first commit, plus today (3 rows)" || ko "5 one row per week from the first commit, plus today (3 rows)" "$(cat "$CSV")"
# Rows oldest first, one per backfill week, dated exactly seven days apart. measure.sh dates in UTC.
dates="$(tail -n +2 "$CSV" | cut -d, -f1 | paste -sd' ' -)"
[[ "$(tail -n 1 "$CSV" | cut -d, -f1)" == "$(date -u +%F)" ]] && ok "5 the last row is today (UTC)" || ko "5 the last row is today (UTC)" "$dates"

# col <row 1..3> <column name>: a value looked up by header name, not position.
col() { awk -F, -v r="$1" -v name="$2" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == name) c = i; next }
                                        NR == r + 1 { print (c ? $c : "missing") }' "$CSV"; }
bytes=$(( $(wc -c < "$F/AGENTS.md") + $(wc -c < "$F/CLAUDE.md") ))
# Expected values per row: after alpha; after beta; after alpha is done and the doc.
expect() { # <row> <column> <value>
    local got; got="$(col "$1" "$2")"
    [[ "$got" == "$3" ]] || printf 'row %s %s: expected %s, got %s\n' "$1" "$2" "$3" "$got"
}
bad="$(
    expect 1 always_loaded_bytes "$bytes"; expect 1 decisions_logged 1; expect 1 doc_files 5; expect 1 people_profiles 1
    expect 1 audit_reports 0; expect 1 build_items_named 0; expect 1 build_items_exist 0
    expect 1 doc_commits_7d 1; expect 1 doc_contributors_7d 1
    expect 2 decisions_logged 2; expect 2 doc_files 7; expect 2 people_profiles 2; expect 2 audit_reports 1
    expect 2 build_items_named 2; expect 2 build_items_exist 1; expect 2 doc_commits_7d 1; expect 2 doc_contributors_7d 1
    expect 3 always_loaded_bytes "$bytes"; expect 3 decisions_logged 3; expect 3 doc_files 8; expect 3 people_profiles 2
    expect 3 audit_reports 1; expect 3 doc_commits_7d 2; expect 3 doc_contributors_7d 2
)"
empty "5 every established column counts the fixture history correctly, week by week" "$bad"
empty "5 metrics.csv holds counts only — a date, fifteen integers, and the median days (empty until a project is done)" \
    "$(tail -n +2 "$CSV" | grep -vE '^[0-9]{4}-[0-9]{2}-[0-9]{2}(,[0-9]+){15},[0-9]*$' || true)"

# --- F12: the project columns ---------------------------------------------------------------------
# In the fixture above, alpha is created 18 days ago in state doing and set to done 4 days ago (14
# days to done); beta is created 11 days ago in state ready. Neither has a People section and the
# register has no Owner column, so nobody is counted in flight. median_days_to_done is empty until a
# project reaches done.
known="$(printf '%s\n' ${base//,/ } projects_active projects_blocked projects_with_done_when \
    projects_done blocked_over_14d max_in_flight_per_person median_days_to_done)"
[[ "$(head -n 1 "$CSV")" == "$base,projects_active,projects_blocked,projects_with_done_when,projects_done,blocked_over_14d,max_in_flight_per_person,median_days_to_done" ]] \
    && ok "5 F12 the header ends with the seven project columns, in order" || ko "5 F12 the header ends with the seven project columns, in order" "$(head -n 1 "$CSV")"
bad=""
for c in $(head -n 1 "$CSV" | tr , ' '); do grep -qxF "$c" <<<"$known" || bad+="unknown column $c"$'\n'; done
empty "5 every metrics.csv column is a known one" "$bad"
bad="$(
    expect 1 projects_active 1; expect 1 projects_blocked 0; expect 1 projects_with_done_when 1; expect 1 projects_done 0
    expect 1 median_days_to_done ""
    expect 2 projects_active 2; expect 2 projects_blocked 0; expect 2 projects_with_done_when 2; expect 2 projects_done 0
    expect 2 blocked_over_14d 0; expect 2 max_in_flight_per_person 0; expect 2 median_days_to_done ""
    expect 3 projects_active 1; expect 3 projects_blocked 0; expect 3 projects_with_done_when 1; expect 3 projects_done 1
    expect 3 blocked_over_14d 0; expect 3 max_in_flight_per_person 0; expect 3 median_days_to_done 14
)"
empty "5 F12 the project columns count the fixture history correctly, week by week" "$bad"

# A second history exercises the data-model rules: a conventions file with its own locations,
# register and a Done when alias; plain and bold labels; honest gaps; a Blocked by line by date; the
# in-flight rule from People and from the register; a project moved into a done folder with no State
# line; and a median over two finished projects (6 and 20 days, so 13).
G="$SCRATCH/measure-f12"
mkdir -p "$G/pilot" "$G/.claude" "$G/work" && git -C "$G" init -q
cp "$KIT/pilot/measure.sh" "$G/pilot/measure.sh"
gx_commit() { # <days ago> <message>
    local when; when="$(days_ago "$1")T12:00:00"
    git -C "$G" add -A
    GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git -C "$G" -c commit.gpgsign=false commit -q -m "$2"
}
printf '# Manifest\n' > "$G/AGENTS.md"; printf '@AGENTS.md\n' > "$G/CLAUDE.md"
printf '# Project conventions\n\n## Where projects live\n\n- **Active:** `work/<slug>/`\n- **Done:** `archive/<slug>/` — moved there when it closes.\n- **Register:** `work/README.md`, with the sections `In flight` and `Shipped`.\n- **Section names:** the Done when list is headed `Exit criteria` in older READMEs.\n  Older READMEs carry a prose `Status` section; that is narrative.\n' > "$G/.claude/projects.md"
printf '# Work\n\n## In flight\n\n| Project | Folder | State | Owner |\n|---|---|---|---|\n| Two | `work/two/` | doing | Sam |\n| Three | `work/three/` | doing | Lee |\n' > "$G/work/README.md"
# gp <folder> <sections>: a project README; the sections are printf %b text after a common head.
gp() { mkdir -p "$G/$1"; { printf '# %s\n\nWhat this is. A project written to be counted, shaped like a real one.\n\n## Desired outcome\n\nIt is finished.\n\n' "${1##*/}"; printf '%b' "$2"; } > "$G/$1/README.md"; }
gp work/one "## Done when\n\n- [ ] it ships\n\n## Current state\n\n- **State:** doing\n\n## People\n\n- Sam — owns\n"
gp work/five "## Done when\n\n- [ ] it ships\n\n## Current state\n\n- **State:** doing\n\n## People\n\n- Kim — owns\n"
gp work/two "## Done when\n\n- [ ] none found yet\n\n## Current state\n\n- **State:** doing\n- **Blocked by:** not yet named\n"
gp work/three "## Done when\n\n- [x] it ships\n\n## Current state\n\nState: doing\nBlocked by: the budget from Lee — since $(days_ago 30)\n\n## People\n\n- **Sam** — owns — \`team/sam.md\`\n- Kim — does\n- Sam — does\n- Lee — keep told\n"
gp work/four "## Exit criteria\n\n- [x] it ships\n\n## Status\n\nA prose paragraph, no Current state block.\n"
gp work/six "## Done when\n\n- [ ] it ships\n\n## Current state\n\n- **State:** paused\n\n## People\n\n- Sam — owns\n"
gx_commit 30 "Six projects"
gp work/five "## Done when\n\n- [x] it ships\n\n## Current state\n\n- **State:** done\n\n## People\n\n- Kim — owns\n"
gx_commit 24 "Five is done"
# One moves to the done folder, and its Current state block goes with the move: the folder says it is done.
mkdir -p "$G/archive" && git -C "$G" mv work/one archive/one
gp archive/one "## Done when\n\n- [x] it ships\n\n## People\n\n- Sam — owns\n"
gx_commit 10 "One moves to the archive"

gcsv="$SCRATCH/measure-out/m.csv"
gout="$(cd "$G/work" && MEASURE_ALWAYS_LOADED="CLAUDE.md" bash ../pilot/measure.sh --backfill 0 --out ../../measure-out/m.csv 2>&1)"; grc=$?
if [[ $grc -eq 0 && -f "$gcsv" && ! -e "$G/pilot/metrics.csv" ]]; then ok "5 F12 --out writes where it is told, relative to the working directory"
else ko "5 F12 --out writes where it is told, relative to the working directory" "$gout"; fi
gcol() { awk -F, -v name="$1" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == name) c = i; next } NR == 2 { print (c ? $c : "missing") }' "$gcsv"; }
bad="$(
    for pair in always_loaded_bytes=$(wc -c < "$G/CLAUDE.md" | tr -d ' ') projects_active=3 projects_blocked=1 \
        projects_with_done_when=2 projects_done=2 blocked_over_14d=1 max_in_flight_per_person=2 median_days_to_done=13; do
        got="$(gcol "${pair%%=*}")"; [[ "$got" == "${pair#*=}" ]] || printf '%s: expected %s, got %s\n' "${pair%%=*}" "${pair#*=}" "$got"
    done
)"
empty "5 F12 the data-model rules hold (locations, aliases, gaps, blocked, in flight, moved to done, median)" "$bad"

# An older CSV with fewer columns is rebuilt for the same dates when today's row is appended.
printf '%s\n%s,1,1,1,1,1,1,1,1,1\n' "$base" "$(days_ago 7)" > "$gcsv"
(cd "$G" && bash pilot/measure.sh --out "$gcsv" >/dev/null 2>&1)
[[ "$(head -n 1 "$gcsv")" == "$(head -n 1 "$CSV")" && "$(wc -l < "$gcsv" | tr -d ' ')" == 3 ]] \
    && ok "5 F12 an older CSV is recomputed in the new columns, keeping its dates" || ko "5 F12 an older CSV is recomputed in the new columns, keeping its dates" "$(cat "$gcsv")"

# The reading rules the board, the hook and these columns share: a heading's name ends at a dash or
# bracket; Done when counts checklist lines only; a blocked State counts as blocked without a Blocked
# by line; only "since" dates a block; "none" is a gap.
Hx="$SCRATCH/measure-rules"
mkdir -p "$Hx/pilot" && git -C "$Hx" init -q && cp "$KIT/pilot/measure.sh" "$Hx/pilot/measure.sh"
mkdir -p "$Hx/projects/a" "$Hx/projects/b" "$Hx/projects/c"
printf '# A

## Done when — checklist

- [ ] it ships

## Current state

- **State:** blocked
- **Blocked by:** a quote from Lee, due %s
' "$(days_ago 40)" > "$Hx/projects/a/README.md"
printf '# B

## Done when

- it ships

## Current state

- **State:** doing
- **Blocked by:** none

## People *(optional)*

- Kim — owns
' > "$Hx/projects/b/README.md"
printf '# C

## Done when (for now)

- [x] it ships

## Current state

- **State:** doing

## People (optional)

- Kim — owns, does
' > "$Hx/projects/c/README.md"
git -C "$Hx" add -A && git -C "$Hx" -c commit.gpgsign=false commit -q -m rules
hrow="$(cd "$Hx" && bash pilot/measure.sh --print 2>/dev/null | tail -n 1)"
hcol() { awk -F, -v name="$1" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == name) c = i; next } NR == 2 { print $c }' <<<"$(printf '%s\n%s\n' "$(head -n 1 "$CSV")" "$hrow")"; }
bad="$(for pair in projects_active=3 projects_blocked=1 projects_with_done_when=2 blocked_over_14d=0 max_in_flight_per_person=2; do
    got="$(hcol "${pair%%=*}")"; [[ "$got" == "${pair#*=}" ]] || printf '%s: expected %s, got %s\n' "${pair%%=*}" "${pair#*=}" "$got"; done)"
empty "5 F12 reads READMEs by the shared rules (headings, checklists, blocked, since-only dates, gaps)" "$bad"
# A repository with nothing committed has no history to read: a note, and no file.
Hn="$SCRATCH/measure-empty"
mkdir -p "$Hn/pilot" && git -C "$Hn" init -q && cp "$KIT/pilot/measure.sh" "$Hn/pilot/measure.sh"
hnout="$(cd "$Hn" && bash pilot/measure.sh --backfill 8 2>&1)"; hnrc=$?
[[ $hnrc -eq 0 && ! -e "$Hn/pilot/metrics.csv" ]] && grep -q 'no commits yet' <<<"$hnout" \
    && ok "5 no commits yet: says so and writes nothing" || ko "5 no commits yet: says so and writes nothing" "$hnout"
# Decision headings are counted with or without the brackets around the date.
printf '# Decisions\n\n## 2026-03-02 — Plain form\n\n## [2026-03-03] Kit form\n\n## Not a decision\n' > "$Hx/decisions-probe.md"
mkdir -p "$Hx/logs" && cp "$Hx/decisions-probe.md" "$Hx/logs/decisions.md"
git -C "$Hx" add -A && git -C "$Hx" -c commit.gpgsign=false commit -q -m decisions
[[ "$(cd "$Hx" && bash pilot/measure.sh --print 2>/dev/null | tail -n 1 | cut -d, -f3)" == 2 ]] \
    && ok "5 decisions_logged counts '## YYYY-MM-DD — Title' as well as '## [YYYY-MM-DD] Title'" \
    || ko "5 decisions_logged counts '## YYYY-MM-DD — Title' as well as '## [YYYY-MM-DD] Title'" "$(cd "$Hx" && bash pilot/measure.sh --print 2>&1)"
# --- end of the F12 block -------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------
echo
echo "6 · Words the kit does not use"

# The words the kit does not use live in a private list outside the repository, so the repository
# never spells them out: $AW_BANNED_WORDS_FILE, by default ~/.config/agentic-workspace-kit/banned-words.txt.
# One extended-regex alternative per line; lines starting with # and blank lines are ignored. The scan
# is whole-word and case-insensitive across every text file except the licences, so plurals and
# hyphenated forms are caught exactly as far as the list's own regexes allow. With no list, the scan
# is reported as SKIP, never as PASS.
words_file="${AW_BANNED_WORDS_FILE:-$HOME/.config/agentic-workspace-kit/banned-words.txt}"
# listpattern <file>: the list as one alternation, comments, blank lines and trailing space dropped.
listpattern() { sed -e 's/[[:space:]]*$//' "$1" | grep -vE '^[[:space:]]*(#|$)' | paste -sd'|' -; }
# wordscan <pattern> <path>...
wordscan() { local pat="$1"; shift; grep -rnIiwE "($pat)" --exclude=LICENSE --exclude-dir=.git "$@"; }
# scanned <description> <command...>: runs a scan and reads its exit status as grep sets it — 1 is
# clean (PASS), 0 is a hit (FAIL, with the hits), and anything higher means the pattern did not
# compile or the scan could not run (FAIL, with grep's own message), so a typo in the list can never
# pass as a clean kit.
scanned() {
    local d="$1" out rc; shift
    out="$("$@" 2>&1)"; rc=$?
    case $rc in
        1) ok "$d" ;;
        0) ko "$d" "$out" ;;
        *) ko "$d" "the scan did not run (exit $rc) — a line in the list may not be a valid extended regex"$'\n'"$out" ;;
    esac
}

# The probe proves the mechanism with made-up marker words from a temporary list, so it needs no real
# one: comments and blank lines drop out, a plural and a hyphenated form the regex allows are caught
# in any case, and a longer word that merely starts with a marker is left alone.
probe="$SCRATCH/words-probe"; mkdir -p "$probe/tree"
printf '# a comment line\n\nzorbl   \nblip-?blops?\n' > "$probe/list.txt"
printf 'One Zorbl, and a zorblet.\nTwo BLIPBLOPS and the blip-blop.\nNothing to see.\n' > "$probe/tree/prose.md"
ppat="$(listpattern "$probe/list.txt")"
[[ "$ppat" == 'zorbl|blip-?blops?' ]] && ok "6 the list loader keeps one alternative per line and drops comments, blanks and trailing space" \
    || ko "6 the list loader keeps one alternative per line and drops comments, blanks and trailing space" "$ppat"
[[ "$(wordscan "$ppat" "$probe/tree" | grep -oiwE "($ppat)" | tr 'A-Z' 'a-z' | sort | paste -sd' ' -)" == "blip-blop blipblops zorbl" ]] \
    && ok "6 the word scan catches whole words in any case, with the plurals and hyphens the list allows" \
    || ko "6 the word scan catches whole words in any case, with the plurals and hyphens the list allows" "$(wordscan "$ppat" "$probe/tree")"
# A list line that is not a valid regex fails the scan rather than letting it pass unread.
printf 'zorbl\nblip(\n' > "$probe/broken.txt"
r="$(scanned "probe" wordscan "$(listpattern "$probe/broken.txt")" "$probe/tree")"
[[ "$r" == FAIL* ]] && ok "6 a list line that is not a valid regex fails the scan instead of passing it" \
    || ko "6 a list line that is not a valid regex fails the scan instead of passing it" "$r"

if [[ ! -f "$words_file" ]]; then
    skp "6 word scan not run — no word list at $words_file (set AW_BANNED_WORDS_FILE to use another path)"
else
    banned="$(listpattern "$words_file")"
    if [[ -z "$banned" ]]; then
        ko "6 the word list at $words_file has no entries"
    else
        entries="$(sed -e 's/[[:space:]]*$//' "$words_file" | grep -cvE '^[[:space:]]*(#|$)')"
        scanned "6 no listed word anywhere in the kit ($entries entries from $words_file)" \
            wordscan "$banned" "$KIT"
        if git -C "$KIT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
            scanned "6 no listed word in any commit message reachable from HEAD" \
                bash -c 'git -C "$1" log HEAD --format="%h %s%n%B" | grep -niwE "($2)"' _ "$KIT" "$banned"
        fi
    fi
fi

# ---------------------------------------------------------------------------------------------------
echo
echo "7 · No AI-vendor attribution"

# The patterns are assembled from pieces so this file does not match itself, which lets it be scanned
# like any other. The two trailer tokens count anywhere on a line — in a table cell or a quoted commit
# message as much as at the start. "Generated with" counts only at the start of a line (after any
# symbols), which is the shape of a tool's footer, not of prose that uses the phrase.
attrib="co-authored""-by:|claude""-session:|^[^[:alnum:]]*generated"" with "
hits="$(cd "$KIT" && grep -rnIiE "$attrib" --exclude-dir=.git . || true)"
empty "7 no attribution lines in any kit file" "$hits"

# One commit is exempt by its full hash: Robert decided on 2026-09-29 not to rewrite history for it (v1.2).
history_exempt="d0a56ae2d7163d310008b47302258ec8ca46a56d"
# histscan <repo> <exempt full hash>: "<hash> <subject>: <line>" for each attribution line in a commit
# message reachable from HEAD, other than the exempt commit's.
# Each message is read on its own, so nothing a message says can pass for the start of another commit.
histscan() {
    local h
    git -C "$1" rev-list HEAD | while IFS= read -r h; do
        [[ "$h" == "$2" ]] && continue
        git -C "$1" log -1 --format=%B "$h" | awk -v pat="$attrib" -v c="$h $(git -C "$1" log -1 --format=%s "$h")" \
            'tolower($0) ~ pat { print c ": " $0 }'
    done
}
# The probe: two commits with trailers, one exempted; the other is still reported.
AH="$SCRATCH/attrib-history"
mkdir -p "$AH" && git -C "$AH" init -q
git -C "$AH" -c commit.gpgsign=false commit -q --allow-empty -m "first" -m "Co-Authored""-By: a tool <t@example.test>"
ah_first="$(git -C "$AH" rev-parse HEAD)"
git -C "$AH" -c commit.gpgsign=false commit -q --allow-empty -m "second" -m "Claude""-Session: https://example.test/s"
ah_second="$(git -C "$AH" rev-parse HEAD)"
r="$(histscan "$AH" "$ah_first")"
[[ "$(grep -c . <<<"$r")" == 1 ]] && grep -q "^$ah_second second: " <<<"$r" \
    && ok "7 the history scan exempts one commit by full hash and still reports a trailer in any other" \
    || ko "7 the history scan exempts one commit by full hash and still reports a trailer in any other" "$r"
if ! git -C "$KIT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    skp "7 attribution in git history not checked — the kit is not a git checkout"
else
    empty "7 no attribution lines in any commit message reachable from HEAD, bar the one exempt commit" \
        "$(histscan "$KIT" "$history_exempt")"
fi

# ---------------------------------------------------------------------------------------------------
echo
echo "8 · The register: no capitals-for-emphasis in prompts, templates and rituals"

# Command prompts, templates, rituals and the team overlay are read by agents as guidance. Norms are
# stated as facts about how the work is done, so shouted imperatives have no place in them. Lines
# between register-audit ignore markers (used where the words are quoted as examples) are skipped.
# The set covers every file an agent reads as a prompt or as guidance: commands, their examples, the
# templates and rituals, the team overlay (the Gemini closeout prompt included) and MANIFEST.md, the
# mould for AGENTS.md. The closeout hooks' prompts are checked in section 4. Line numbers are
# the file's own, and an ignore-start with no ignore-end fails rather than exempting the rest.
regscan() { # <file>: offending lines as "line: text", plus a note for an unterminated ignore block
    awk '/register-audit: ignore-start/ { s = 1; next } /register-audit: ignore-end/ { s = 0; next }
         !s { print FNR ": " $0 } END { if (s) print "0: unterminated register-audit: ignore-start" }' "$1" \
        | grep -E ': (.*[^[:alnum:]_])?(MUST|NEVER|CRITICAL|IMPORTANT)([^[:alnum:]_].*)?$|^0: unterminated' || true
}
hits=""
shopt -s nullglob
for f in "$KIT"/plugins/*/commands/*.md "$KIT"/plugins/*/examples/* "$KIT"/templates/* "$KIT"/rituals/* \
         "$KIT"/team/*.md "$KIT"/team/*.toml "$KIT"/MANIFEST.md; do
    [[ -f "$f" ]] || continue
    h="$(regscan "$f")"
    [[ -n "$h" ]] && hits+="$(printf '%s\n' "$h" | sed "s#^#${f#"$KIT"/}:#")"$'\n'
done
shopt -u nullglob
empty "8 no MUST, NEVER, CRITICAL or IMPORTANT in command, example, template, ritual, team or manifest files" "$hits"
probe="$SCRATCH/register-probe.md"
printf 'Fine.\n<!-- register-audit: ignore-start -->\nQuoted: MUST.\n<!-- register-audit: ignore-end -->\nYou NEVER skip.\n<!-- register-audit: ignore-start -->\nALWAYS.\n' > "$probe"
[[ "$(regscan "$probe" | paste -sd'|' -)" == "5: You NEVER skip.|0: unterminated register-audit: ignore-start" ]] \
    && ok "8 the register scan reports real line numbers and fails an unterminated ignore block" \
    || ko "8 the register scan reports real line numbers and fails an unterminated ignore block" "$(regscan "$probe")"

# ---------------------------------------------------------------------------------------------------
echo
echo "9 · The nine commands, on Claude Code and as skills, from one source each"

# The command set is fixed by the spec's architecture table; a tenth, or a missing one, fails here
# so the plugins, the skills and this list move together.
commands="closeout/closeout projects/adopt projects/board projects/close projects/new projects/pickup
workspace/hygiene workspace/quick-start workspace/register-audit"
have="$(cd "$KIT/plugins" && ls */commands/*.md | sed 's#/commands/#/#; s#\.md$##' | sort | paste -sd' ' -)"
[[ "$have" == "$(printf '%s' "$commands" | tr '\n' ' ')" ]] && ok "9 the kit has exactly the nine commands" \
    || ko "9 the kit has exactly the nine commands" "has: $have"
# skill_of <plugin/command>: a command named after its plugin keeps its bare name.
skill_of() { local p="${1%/*}" c="${1#*/}"; if [[ "$p" == "$c" ]]; then echo "$c"; else echo "$p-$c"; fi; }
body_of() { awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } !fm' "$1"; }
# skill_ok <SKILL.md>: the Agent Skills format — front matter with a name (lowercase words joined by
# single hyphens, at most 64 characters, the same as its folder) and a description (1 to 1024
# characters, no angle brackets, saying when to offer it) — and under 30 lines.
skill_ok() { python3 - "$1" <<'PYSKILL'
import json, re, sys, os
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
lines = text.split("\n")
assert lines[0] == "---", "no front matter"
end = lines.index("---", 1)
fm = {}
for l in lines[1:end]:
    k, _, v = l.partition(": ")
    fm[k] = v
assert set(fm) == {"name", "description"}, f"front matter keys {sorted(fm)}"
name = fm["name"]
assert re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) and len(name) <= 64, f"name {name!r}"
assert name == os.path.basename(os.path.dirname(path)), "name differs from its folder"
d = fm["description"]
assert d.startswith('"') and d.endswith('"'), "description is not a quoted string"
d = json.loads(d)  # the installer escapes only backslashes and quotes, so JSON reads it as YAML would
assert 1 <= len(d) <= 1024, f"description is {len(d)} characters"
assert "<" not in d and ">" not in d, "angle brackets in the description"
assert "Offer it" in d, "the description does not say when to offer it"
n = text.count("\n") + (0 if text.endswith("\n") else 1)  # lines as wc -l counts them, blank ones too
assert n < 30, f"{n} lines"
PYSKILL
}
bad=""
for pc in $commands; do
    p="${pc%/*}" c="${pc#*/}"
    src="$KIT/plugins/$p/commands/$c.md" sk="$S1/$(skill_of "$pc")"
    cmp -s "$src" "$T1/.claude/plugins/$p/commands/$c.md" || bad+="$pc: not vendored for Claude Code as it stands in the kit"$'\n'
    if [[ ! -f "$sk/SKILL.md" ]]; then bad+="$pc: no skill $(skill_of "$pc")"$'\n'; continue; fi
    err="$(skill_ok "$sk/SKILL.md" 2>&1)" || bad+="$pc: $(printf '%s' "$err" | tail -n 1)"$'\n'
    grep -qF "\`.claude/plugins/$p/commands/$c.md\` in this repository" "$sk/SKILL.md" \
        || bad+="$pc: the skill does not point at the vendored command file"$'\n'
    body_of "$src" > "$SCRATCH/body.md"
    cmp -s "$SCRATCH/body.md" "$sk/procedure.md" || bad+="$pc: procedure.md is not the command's body"$'\n'
done
extra="$(cd "$S1" && ls -A | sort | paste -sd' ' -)"
[[ "$extra" == "$(for pc in $commands; do skill_of "$pc"; done | sort | paste -sd' ' -)" ]] || bad+="skills folder holds: $extra"$'\n'
empty "9 every command is vendored for Claude Code and has one valid skill under 30 lines, pointing at it" "$bad"

# Where a skill points depends on where the kit sits. Inside the repository (a submodule), the skill
# names the command file itself; with no copy in the repository, procedure.md is the whole of it.
# --skills-only writes the skills and nothing else.
R="$SCRATCH/skills-sub" RS="$SCRATCH/skills-sub-out"
mkdir -p "$R/kit" && cp -R "$KIT/plugins" "$R/kit/plugins"
bash "$KIT/install.sh" --skills-only --target "$R" --skills-dir "$RS" --plugin-src "$R/kit/plugins" >/dev/null 2>&1
if grep -qF '`kit/plugins/projects/commands/board.md` in this repository' "$RS/projects-board/SKILL.md" 2>/dev/null \
    && [[ "$(ls -A "$R")" == "kit" ]]; then
    ok "9 skills-only: a kit inside the repository is pointed at directly, and nothing else is written"
else ko "9 skills-only: a kit inside the repository is pointed at directly, and nothing else is written" "$(ls -A "$R"; cat "$RS/projects-board/SKILL.md" 2>&1)"; fi
RN="$SCRATCH/skills-none" RNS="$SCRATCH/skills-none-out"
mkdir -p "$RN"
bash "$KIT/install.sh" --skills-only --target "$RN" --skills-dir "$RNS" >/dev/null 2>&1
if [[ -f "$RNS/closeout/procedure.md" ]] && ! grep -q 'in this repository' "$RNS/closeout/SKILL.md" \
    && skill_ok "$RNS/closeout/SKILL.md" >/dev/null 2>&1; then
    ok "9 skills-only: with no copy of the kit in the repository, a skill follows procedure.md beside it"
else ko "9 skills-only: with no copy of the kit in the repository, a skill follows procedure.md beside it" "$(cat "$RNS/closeout/SKILL.md" 2>&1)"; fi

# ---------------------------------------------------------------------------------------------------
echo
echo "$pass passed, $fail failed, $skip skipped"
[[ $fail -eq 0 ]]
