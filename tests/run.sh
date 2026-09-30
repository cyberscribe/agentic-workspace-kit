#!/usr/bin/env bash
# The kit's test suite. Plain bash; needs only git, jq and python3. A claude binary is optional: the
# checks that call the real one are reported as SKIP without it.
#
#   bash tests/run.sh               run everything
#   AW_KEEP=1 bash tests/run.sh     keep the scratch directory afterwards, for inspection
#   AW_BANNED_WORDS_FILE=<path> bash tests/run.sh
#                                   read section 6's word list from <path> rather than
#                                   ~/.config/agentic-workspace-kit/banned-words.txt; with no list
#                                   there, the scan is reported as SKIP
#   AW_REQUIRE_CLAUDE=1 bash tests/run.sh
#                                   fail, rather than skip, section 3's plugin validation when no
#                                   claude binary with `plugin validate` is on PATH (for a release);
#                                   implies AW_TEST_CLAUDE=1
#   AW_SECTIONS="13 16" bash tests/run.sh
#                                   run only the named sections ("4b", "11", or a file's number in
#                                   tests/sections/); a section that reads another's fixtures brings it
#   AW_TEST_CLAUDE=1 bash tests/run.sh
#                                   run the checks in tests/sections/ that start Claude Code, with a
#                                   scratch CLAUDE_CONFIG_DIR; each run appends a line to $AW_CC_LOG
#                                   (default: claude-runs.md in the scratch directory)
#   AW_BASH32=0 bash tests/run.sh   leave PATH alone; by default a bash that is /bin/bash (3.2 on
#                                   macOS) comes first, so child scripts run under the kit's floor
#
# One line per check: PASS, FAIL or SKIP, then a count. Exits non-zero when anything fails.
# Every repository it builds lives under one mktemp directory in $TMPDIR, removed on exit.
#
# The prelude, below the check helpers, builds what the 3.0 sections share: KITSRC (a one-commit
# repository of the kit's working tree), mkws_min, mkws and mkws2x (fixture workspaces), the st_*
# state-check helpers, the bash 3.2 PATH entry, a git that counts its calls, and cc_gate and cc_run
# for Claude Code. Sections 12 and on live in tests/sections/NN-name.sh and are sourced after
# section 11.
#
# The sections follow the numbered list in the spec's tests section:
#   1 the engine (kit/install.sh), twice     5 measure.sh --backfill on a dated fixture history
#   2 the retired interactive installer      6 words the kit does not use, from a private list
#   2b installer modes and flags
#   3 JSON, TOML, versions, marketplaces     7 no AI-vendor attribution, in files and in history
#   4 closeout hooks                         8 the register: no capitals-for-emphasis in prompts
#   4b the projects session-start hook       9 the ten commands, on Claude Code and as skills; the
#                                               closeout command and ritual carry the same core rules
#                                            10 ablations: pilot/ablate.sh against a stub claude; the
#                                               blind comparator, the bare arm, the login-token switch,
#                                               the billing guard, and the flags and demotion rule from a
#                                               prepared CSV
#                                            11 the state check: modes, keys, no lock left; the setup
#                                               scripts parse and lint clean
# and then, from tests/sections/: 13 privacy guards, 14 ownership and the engine, 15 setup, 16 the state
# check's 3.0 keys, 17 projects, 18 resources, 19 the skills bridge, 20 the migration, 21 closeout,
# hygiene and the pilot in a 3.0 workspace (12, the docs, arrives with them).
#
# Two shellcheck notes are off for the whole file, as in the section files: SC2015, since every check is
# written "cond && ok … || ko …" and ok never fails; SC2016, since many patterns and messages hold a
# literal backtick or $ in single quotes on purpose.
# shellcheck disable=SC2015,SC2016
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

# ---- The 3.0 prelude: fixtures and helpers every section can use --------------------------------
#
# The section filter. AW_SECTIONS="13 16" runs only those sections; the existing sections are named by
# their number as printed ("4b", "11"), the files in tests/sections/ by their leading number. A section
# that reads another's fixtures brings that one along (3 and 9 read 1's). Unset or empty, every
# section runs.
aw_sections_run=""
if [[ -n "${AW_SECTIONS:-}" ]]; then
    for aw_s in $AW_SECTIONS; do
        case "$aw_s" in 3|9) aw_sections_run+=" 1" ;; esac
        aw_sections_run+=" $aw_s"
    done
    echo "Sections: $AW_SECTIONS (AW_SECTIONS); running$aw_sections_run"
fi
aw_sections_seen=""
# aw_want <section id>: 0 when the section runs.
aw_want() {
    [[ -n "${AW_SECTIONS:-}" ]] || return 0
    case " $aw_sections_run " in *" $1 "*) aw_sections_seen+=" $1"; return 0 ;; esac
    return 1
}

# The state check and its helpers, shared by section 11 and the sections in tests/sections/. They run
# under /bin/bash where there is one (bash 3.2 on macOS), since that is the floor the kit is written for.
STATE="$KIT/plugins/workspace/bin/state.sh"
st_bash=bash; [[ -x /bin/bash ]] && st_bash=/bin/bash
st_err=""
# st_run <dir> [option...]: the report on stdout; anything on stderr is collected for the silence check.
st_run() { local d="$1" e; shift; "$st_bash" "$STATE" "$@" "$d" 2>"$SCRATCH/state.err"
    e="$(cat "$SCRATCH/state.err")"; [[ -z "$e" ]] || st_err+="$d: $e"$'\n'; }
# st_key <report> <key>: the value of one key. An index() match rather than a regex, since per-item keys
# (submodule.<path>, resource.<slug>/<name>) carry slashes and dots.
st_key() { printf '%s\n' "$1" | awk -v k="$2=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }'; }
# st_expect <description> <report> key=value...: every pair matches, or the mismatches are the detail.
st_expect() {
    local d="$1" rep="$2" bad="" kv k; shift 2
    for kv in "$@"; do
        k="${kv%%=*}"
        [[ "$(st_key "$rep" "$k")" == "${kv#*=}" ]] || bad+="$k: wanted '${kv#*=}', got '$(st_key "$rep" "$k")'"$'\n'
    done
    empty "$d" "$bad"
}
# st_tree <dir>: every path under it, .git included, with size and mtime, directories too — a lock
# file created and removed still changes its directory's mtime, so a clean run leaves this unchanged.
st_tree() { python3 - "$1" <<'PYTREE'
import os, sys
root = sys.argv[1]
for dp, dn, fn in os.walk(root):
    dn.sort()
    for n in sorted(dn + fn):
        p = os.path.join(dp, n); s = os.lstat(p)
        print(os.path.relpath(p, root), s.st_size, s.st_mtime_ns)
print(".", os.lstat(root).st_mtime_ns)
PYTREE
}

# The bash 3.2 pass. bin32/bash points at /bin/bash and comes first on PATH, so a hook, a child script
# started as "bash x.sh" or through #!/usr/bin/env bash, and session-start.sh all run under the floor
# the kit is written for. AW_BASH32=0 leaves PATH alone, for a pass under the runner's own bash.
if [[ "${AW_BASH32:-1}" != "0" && -x /bin/bash ]]; then
    mkdir -p "$SCRATCH/bin32" && ln -s /bin/bash "$SCRATCH/bin32/bash"
    export PATH="$SCRATCH/bin32:$PATH"
fi

# A git that counts: $SCRATCH/gitcount/git logs one line per call to $AW_GITCOUNT_LOG, then runs the
# real git. For structural cost tests: gitcount_run <log> <command...> runs the command with it first
# on PATH, and aw_count <"$log" gives the number of git calls.
aw_real_git="$(command -v git)"
mkdir -p "$SCRATCH/gitcount"
# The $* and $@ are the shim's own, written literally.
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "${AW_GITCOUNT_LOG:-/dev/null}"' "exec \"$aw_real_git\" \"\$@\"" \
    > "$SCRATCH/gitcount/git"
chmod +x "$SCRATCH/gitcount/git"
gitcount_run() { local log="$1"; shift; : > "$log"; AW_GITCOUNT_LOG="$log" PATH="$SCRATCH/gitcount:$PATH" "$@"; }
aw_count() { awk 'END { print NR }'; }

# No fixture's pre-push can reach a real gh (and the network): the hooks ask the command named by AW_GH,
# which is a path that does not exist unless a check points it at a stub of its own.
export AW_GH="$SCRATCH/no-gh"

# KITSRC: a repository on branch main with one commit, whose tree is the kit's working tree (tracked
# and untracked files, ignored ones left out, modes kept). Every workspace fixture adds the kit from it,
# so the scripts under test are the working tree's, committed or not.
KITSRC="$SCRATCH/kit-src"
kitsrc_ok=0
if git --no-optional-locks -C "$KIT" rev-parse --git-dir >/dev/null 2>&1; then
    mkdir -p "$KITSRC" && git -C "$KITSRC" init -q && git -C "$KITSRC" symbolic-ref HEAD refs/heads/main
    while IFS= read -r -d '' aw_f; do
        [[ -f "$KIT/$aw_f" ]] || continue
        mkdir -p "$KITSRC/$(dirname "$aw_f")" && cp -p "$KIT/$aw_f" "$KITSRC/$aw_f"
    done < <(git --no-optional-locks -C "$KIT" ls-files -z -co --exclude-standard)
    git -C "$KITSRC" add -A \
        && git -C "$KITSRC" -c commit.gpgsign=false commit -q -m "The kit's working tree, for the tests" \
        && kitsrc_ok=1
fi
[[ $kitsrc_ok -eq 1 ]] || echo "note: the kit is not a git checkout; the fixtures built from KITSRC are not available"

# mkws_min <dir>: the smallest 3.0 workspace, with no setup code. A new repository on main, the kit
# added from KITSRC at kit/, the static tree in tests/fixtures/ws-min/ copied in (dot- names become
# dot names: dot-claude/ is .claude/), and the hooks set. Nothing is committed. Returns non-zero when
# the workspace could not be built (3: no KITSRC).
mkws_min() {
    local d="$1" f rel
    [[ $kitsrc_ok -eq 1 ]] || return 3
    mkdir -p "$d" && git -C "$d" init -q && git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
    git -C "$d" -c protocol.file.allow=always submodule add -q -b main "$KITSRC" kit >/dev/null 2>&1 || return 1
    while IFS= read -r f; do
        rel="${f#"$KIT/tests/fixtures/ws-min/"}"
        [[ "$rel" == README.md ]] && continue
        rel="$(printf '%s' "$rel" | sed -e 's#^dot-#.#' -e 's#/dot-#/.#g')"
        mkdir -p "$d/$(dirname "$rel")" && cp -p "$f" "$d/$rel"
    done < <(find "$KIT/tests/fixtures/ws-min" -type f | sort)
    mkws_hooks "$d"
}

# mkws_kit <dir>: a new repository on main with the kit added from KITSRC at kit/, and nothing else:
# the starting point for running the engine (kit/install.sh) directly. Returns 3 without KITSRC.
mkws_kit() {
    local d="$1"
    [[ $kitsrc_ok -eq 1 ]] || return 3
    mkdir -p "$d" && git -C "$d" init -q && git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
    git -C "$d" -c protocol.file.allow=always submodule add -q -b main "$KITSRC" kit >/dev/null 2>&1
}

# mkws_hooks <dir>: the git hooks for a fixture workspace and its kit. Once lib/setup/gitconfig.sh is
# built, it does this. While it is a placeholder, the stub below is written in its place: the
# contract's stub (the marker on line 2, the kit's hook of the same name found from the repository's
# top), which passes over a kit hook that is itself still a placeholder, so a fixture can still commit.
mkws_hooks() {
    local d="$1" repo gd n
    if ! grep -q 'not built yet' "$d/kit/lib/setup/gitconfig.sh" 2>/dev/null; then
        "$st_bash" "$d/kit/lib/setup/gitconfig.sh" --target "$d" --hooks >/dev/null 2>&1
        return
    fi
    for repo in "$d" "$d/kit"; do
        gd="$(git -C "$repo" rev-parse --absolute-git-dir)" || return 1
        mkdir -p "$gd/aw-hooks"
        for n in pre-commit pre-merge-commit commit-msg pre-push; do
            cat > "$gd/aw-hooks/$n" <<'W0STUB'
#!/bin/sh
# agentic-workspace-kit hook stub 1
# Written by tests/run.sh (mkws_hooks) while lib/setup/gitconfig.sh is a placeholder.
name=${0##*/}
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
target=""
if grep -q '"agentic-workspace"' "$TOP/.claude-plugin/marketplace.json" 2>/dev/null && [ -x "$TOP/githooks/$name" ]; then
    target="$TOP/githooks/$name"
else
    d=$TOP
    while :; do
        if grep -q '"agentic-workspace"' "$d/kit/.claude-plugin/marketplace.json" 2>/dev/null && [ -x "$d/kit/githooks/$name" ]; then
            target="$d/kit/githooks/$name"; break
        fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
fi
if [ -z "$target" ]; then
    echo "aw: the kit's hooks are not reachable from $TOP (kit not initialised, or moved); kit/setup.sh hooks sets them up again." >&2
    exit 1
fi
grep -q 'not built yet' "$target" 2>/dev/null && exit 0
exec "$target" "$@"
W0STUB
            chmod 755 "$gd/aw-hooks/$n"
        done
        git -C "$repo" config core.hooksPath "$gd/aw-hooks"
    done
}

# mkws <dir> [setup args...]: a workspace made the way a person makes one, with setup.sh new, unattended,
# the kit added from KITSRC. Setup's output goes to <dir>.log; its status is returned.
mkws() {
    local d="$1" rc; shift
    [[ $kitsrc_ok -eq 1 ]] || return 3
    AW_KIT_URL="$KITSRC" AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$KIT/setup.sh" new "$d" --team "Test Team" \
        --owner "Sam Example" --owner-handle "@sam" "$@" </dev/null >"$d.log" 2>&1
    rc=$?
    git -C "$d" rev-parse --git-dir >/dev/null 2>&1 && git -C "$d" config user.name "Priya Shah"
    return $rc
}

# mkws2x <dir>: a workspace in the 2.2.0 layout, for the migration: the kit at 915c528 (its own
# repository, built once) as a submodule at templates/agentic-workspace, its 2.2.0 install.sh run with
# vendored plugins and skills in <dir>/skills, and everything committed. Returns 3 when 915c528 is not
# in the object store (a shallow clone); the sections that need it print one SKIP.
mkws2x() {
    local d="$1" k2="$SCRATCH/kit-2.2.0"
    git --no-optional-locks -C "$KIT" cat-file -e '915c528^{commit}' 2>/dev/null || return 3
    if [[ ! -d "$k2/.git" ]]; then
        mkdir -p "$k2" && git --no-optional-locks -C "$KIT" archive 915c528 | tar -x -C "$k2" || return 1
        git -C "$k2" init -q && git -C "$k2" symbolic-ref HEAD refs/heads/main && git -C "$k2" add -A \
            && git -C "$k2" -c commit.gpgsign=false commit -q -m "Kit 2.2.0" || return 1
    fi
    mkdir -p "$d" && git -C "$d" init -q && git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
    git -C "$d" config user.name "Priya Shah"
    git -C "$d" -c protocol.file.allow=always submodule add -q -b main "$k2" templates/agentic-workspace >/dev/null 2>&1 || return 1
    bash "$d/templates/agentic-workspace/install.sh" --target "$d" "${install_args[@]}" --skills-dir "$d/skills" \
        </dev/null >"$d.log" 2>&1 || return 1
    git -C "$d" add -A && git -C "$d" -c commit.gpgsign=false commit -q -m "The 2.2.0 layout" || return 1
}

# Claude Code in tests is opt-in: AW_TEST_CLAUDE=1, which AW_REQUIRE_CLAUDE=1 implies (and which turns a
# SKIP into a FAIL). Every run uses a scratch config directory, so nothing is written to ~/.claude, and
# appends one line to AW_CC_LOG (default: a file in the scratch directory).
[[ "${AW_REQUIRE_CLAUDE:-}" == "1" ]] && AW_TEST_CLAUDE=1
AW_CC_LOG="${AW_CC_LOG:-$SCRATCH/claude-runs.md}"
CC_CONFIG="$SCRATCH/cc-config"
# cc_gate <description> [prompt]: 0 when Claude Code checks run here. Otherwise it records a SKIP (a
# FAIL under AW_REQUIRE_CLAUDE=1) saying why and returns 1. With "prompt", the check calls the model
# (claude -p), which needs CLAUDE_CODE_OAUTH_TOKEN: a keychain login does not follow CLAUDE_CONFIG_DIR.
cc_gate() {
    local why=""
    if [[ "${AW_TEST_CLAUDE:-}" != "1" ]]; then skp "$1 — Claude Code checks are opt-in (AW_TEST_CLAUDE=1)"; return 1; fi
    command -v claude >/dev/null 2>&1 || why="no claude binary on PATH"
    [[ -z "$why" && "${2:-}" == prompt && -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] && why="no CLAUDE_CODE_OAUTH_TOKEN for claude -p"
    [[ -z "$why" ]] && return 0
    if [[ "${AW_REQUIRE_CLAUDE:-}" == "1" ]]; then ko "$1 — AW_REQUIRE_CLAUDE=1 and $why"; else skp "$1 — $why"; fi
    return 1
}
# cc_run <label> <claude arguments...>: claude with the scratch config directory and non-essential
# traffic off; one line per run goes to AW_CC_LOG. Its status is returned.
cc_run() {
    local label="$1" rc; shift
    mkdir -p "$CC_CONFIG"
    env CLAUDE_CONFIG_DIR="$CC_CONFIG" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 claude "$@"
    rc=$?
    printf -- '- %s tests/run.sh: %s (claude %s) exit %s\n' "$(date '+%F %H:%M')" "$label" "${1:-}" "$rc" >> "$AW_CC_LOG" 2>/dev/null
    return $rc
}

# ---------------------------------------------------------------------------------------------------
if aw_want 1; then
echo "1 · The engine: a first run, then a second"

# Each fixture is a repository with the kit added from KITSRC at kit/ (mkws_kit), and the engine run on
# it directly, so what is checked is the engine's own report. Section 15 drives the same engine through
# kit/setup.sh new; section 14 covers the ledger, template changes and the .gitignore modes.
T1="$SCRATCH/install-1"
S1="$SCRATCH/skills-1"   # the commands as skills, outside the repository; section 9 reads them
T1G="$SCRATCH/install-1-gemini"
if ! mkws_kit "$T1" || ! mkws_kit "$T1G"; then
    skp "1 the engine's fixtures need KITSRC (the kit is not a git checkout here)"
else
out1="$(bash "$KIT/install.sh" --target "$T1" "${install_args[@]}" --pilot </dev/null 2>&1)"; rc1=$?
if [[ $rc1 -eq 0 ]]; then ok "1 first run exits 0"; else ko "1 first run exits 0" "$out1"; fi
missing=""
for f in CLAUDE.md AGENTS.md README.md .claude/settings.json .gitignore .claude/closeout.md .claude/projects.md \
         .claude/workspace.md projects/INDEX.md logs/decisions.md memory/glossary.md memory/people/README.md \
         audits/README.md docs/workspace-map.md .github/CODEOWNERS .github/pull_request_template.md \
         .github/workflows/stay-private.yml pilot/build-list.md .claude/kit-templates.lock; do
    [[ -e "$T1/$f" ]] || missing+="$f"$'\n'
done
empty "1 first run creates the user-owned files, the ledger and the pilot's build list" "$missing"
# Kit-owned files are read in place from kit/; none is copied into the workspace.
extra=""
for f in docs/memory-layers.md docs/documentation-register.md rituals templates pilot/measure.sh pilot/README.md \
         .claude/plugins; do
    [[ ! -e "$T1/$f" ]] || extra+="$f"$'\n'
done
empty "1 nothing kit-owned is copied: docs, rituals, templates, the pilot's scripts and the plugins stay in kit/" "$extra"
check "1 the team name reaches CLAUDE.md" grep -q 'Test Team' "$T1/CLAUDE.md"
check "1 CLAUDE.md starts with the import of the kit's standards" test "$(head -n 1 "$T1/CLAUDE.md")" = '@kit/CLAUDE.kit.md'
check "1 .claude/closeout.md sets who needs to know, as auto" grep -qxF -- '- **Who needs to know:** auto' "$T1/.claude/closeout.md"
# The conventions every projects command reads first carry the staleness the board measures against,
# and the project template carries the Current state block the hook, board and metrics read.
check "1 .claude/projects.md sets the staleness a project's Updated date is measured against" \
    grep -qE '^- \*\*Staleness:\*\* `[^`]+`' "$T1/.claude/projects.md"
check "1 .claude/projects.md points at the project template in kit/" grep -qF '`kit/templates/project-readme.md`' "$T1/.claude/projects.md"
tpl="$T1/kit/templates/project-readme.md"
bad=""
for h in '## Done when' '## Current state' '## Planned *(optional)*' '## People *(optional)*'; do
    grep -qxF "$h" "$tpl" || bad+="no heading: $h"$'\n'
done
# The block's labels are exactly these four, in this order, so a label added back is caught as
# surely as one taken away; and State offers exactly the five states.
labels="$(awk '/^## / { f = ($0 == "## Current state") ; next } f && /^- \*\*[^*]+:\*\*/ { l = $0; sub(/^- \*\*/, "", l); sub(/:\*\*.*/, "", l); print l }' "$tpl" | paste -sd'|' -)"
[[ "$labels" == 'State|Blocked by|Check-in|Updated' ]] || bad+="the block's labels are \"$labels\", not State|Blocked by|Check-in|Updated"$'\n'
grep -qxF -- '- **State:** <ready · doing · blocked · paused · done>' "$tpl" || bad+="the State line does not offer exactly the five states"$'\n'
[[ "$(sed -n 3p "$tpl")" == '- **Versioned:** <workspace · own-repo · untracked>' ]] || bad+="line 3 is not the Versioned line"$'\n'
[[ "$(sed -n 4p "$tpl")" == '- **Sensitivity:** <normal · sensitive>' ]] || bad+="line 4 is not the Sensitivity line"$'\n'
bad+="$(grep -nE '^## (Now|Next up|Parked)([[:space:]]|$)' "$tpl")"
empty "1 the kit's project template has Versioned and Sensitivity under the title, a Current state block (State, Blocked by, Check-in, Updated), Planned, and no older sections" "$bad"
grep -q '/workspace:quick-start' <<<"$out1" && ok "1 the Next message says to run /workspace:quick-start" \
    || ko "1 the Next message says to run /workspace:quick-start" "$(grep -A3 '^Next' <<<"$out1")"
check "1 no .claude/commands directory (quick-start lives in the workspace plugin)" test ! -e "$T1/.claude/commands"

# The quick-start decides the team part is unfinished while CLAUDE.md §1–§3 hold an angle-bracketed
# stand-in, which always has a space in it; path patterns such as memory/people/<name>.md never do.
# This is the rule its prompt states, checked against the file the engine actually writes.
standins() { tr '\n' ' ' < "$1" | grep -o '<[A-Za-z][^<>]* [^<>]*>' | wc -l | tr -d ' '; }
n="$(standins "$T1/CLAUDE.md")"
[[ "$n" -gt 0 ]] && ok "1 a fresh CLAUDE.md has stand-ins for the quick-start to find ($n)" || ko "1 a fresh CLAUDE.md has stand-ins for the quick-start to find"
filled="$SCRATCH/claude-filled.md"
tr '\n' '\v' < "$T1/CLAUDE.md" | sed -E 's/<[A-Za-z][^<>]* [^<>]*>/filled in/g' | tr '\v' '\n' > "$filled"
if [[ "$(standins "$filled")" == "0" ]] && grep -q '<name>' "$filled"; then
    ok "1 once every stand-in is answered none remain, though path patterns such as <name> do"
else ko "1 once every stand-in is answered none remain, though path patterns such as <name> do" "$(grep -n '<' "$filled")"; fi
grep -q "has $n answers still to fill in" <<<"$out1" && ok "1 the Next message counts stand-ins, not path patterns" \
    || ko "1 the Next message counts stand-ins, not path patterns" "$(grep 'still to fill' <<<"$out1")"

# The second run: every path under the workspace, .git included, keeps its size and mtime.
st_tree "$T1" > "$SCRATCH/install-1-before.txt"
out2="$(bash "$KIT/install.sh" --target "$T1" "${install_args[@]}" --pilot </dev/null 2>&1)"; rc2=$?
if [[ $rc2 -eq 0 ]]; then ok "1 second run exits 0"; else ko "1 second run exits 0" "$out2"; fi
st_tree "$T1" > "$SCRATCH/install-1-after.txt"
empty "1 second run changes no file, .git included" "$(diff "$SCRATCH/install-1-before.txt" "$SCRATCH/install-1-after.txt" 2>&1)"
if grep -q '^Already in place:' <<<"$out2" && ! grep -qE '^(Created|Merged|Added to \.gitignore|Regenerated|Kept as it was)' <<<"$out2"; then
    ok "1 second run reports everything already in place, and nothing created, merged or kept aside"
else
    ko "1 second run reports everything already in place, and nothing created, merged or kept aside" \
        "$(grep -A8 -E '^(Created|Merged|Added to \.gitignore|Regenerated|Kept as it was)' <<<"$out2")"
fi
check "1 the default install is Claude Code only (no .gemini/)" test ! -e "$T1/.gemini"
# Every session reads CLAUDE.md, and every projects command reads .claude/projects.md first, so
# neither may name a surface this install did not set up.
empty "1 a Claude-only install names no Gemini CLI surface in the files read first" \
    "$(grep -n -i -E 'gemini cli|\.gemini/settings' "$T1/CLAUDE.md" "$T1/AGENTS.md" "$T1/.claude/projects.md")"
check "1 the surface table carries the Claude Code row, naming the plugins and the git hooks in kit/" \
    grep -qxF "$(head -n 1 "$KIT/templates/workspace/surface-rows/claude.md")" "$T1/CLAUDE.md"
grep -qF "approve the closeout, projects and workspace plugins when asked" <<<"$out1" \
    && ok "1 the Next message asks each person to approve the three plugins" \
    || ko "1 the Next message asks each person to approve the three plugins" "$(grep -A6 '^Next' <<<"$out1")"
grep -qF "bash kit/pilot/measure.sh" <<<"$out1" && ok "1 the pilot's Next line runs the measurement from kit/" \
    || ko "1 the pilot's Next line runs the measurement from kit/" "$(grep -A6 '^Next' <<<"$out1")"
empty "1 no .kit-incoming files after two runs" "$(find "$T1" -name '*.kit-incoming' -not -path '*/.git/*' -not -path "$T1/kit/*")"
check "1 pilot/measure.sh is mode 100755 in the kit" test "$(git -C "$T1/kit" ls-files -s pilot/measure.sh | cut -c1-6)" = 100755

# The Gemini CLI surface (frozen) still installs on request, beside Claude Code; section 3 parses it.
bash "$KIT/install.sh" --target "$T1G" "${install_args[@]}" --surfaces claude,gemini </dev/null >/dev/null 2>&1
check "1 --surfaces claude,gemini installs Claude Code and Gemini CLI" test -f "$T1G/CLAUDE.md" -a -f "$T1G/.gemini/settings.json"

# The commands as skills, for surfaces with no plugins (section 9 checks each one). They are generated by
# the workspace's own kit, as the skills bridge does it, so each points at its command file in kit/.
bash "$T1/kit/install.sh" --skills-only --target "$T1" --skills-dir "$S1" </dev/null >/dev/null 2>&1
check "1 --skills-only writes the skills into a folder outside the repository" test -f "$S1/closeout/SKILL.md"

# A repository with a CLAUDE.md of its own keeps it as the always-loaded file: the engine records it
# kept, the Next message points at the quick-start's mapping, and .claude/closeout.md names CLAUDE.md.
TK="$SCRATCH/install-kept"
if mkws_kit "$TK"; then
    printf '# My rules\n\nHouse rules of my own.\n' > "$TK/CLAUDE.md"
    outk="$(bash "$KIT/install.sh" --target "$TK" --team Solo --owner Alex </dev/null 2>&1)"
    if grep -qF 'Your own CLAUDE.md was kept' <<<"$outk" && ! grep -q 'answers still to fill in' <<<"$outk" \
        && [[ "$(head -n 1 "$TK/CLAUDE.md")" == '# My rules' ]] \
        && grep -q "^CLAUDE.md	templates/workspace/CLAUDE.md	.*	kept\$" "$TK/.claude/kit-templates.lock" \
        && grep -qF 'The always-loaded file is `CLAUDE.md`' "$TK/.claude/closeout.md" \
        && grep -q 'with one person it is optional' <<<"$outk"; then
        ok "1 a CLAUDE.md of its own is kept, recorded kept, and the engine reports it"
    else ko "1 a CLAUDE.md of its own is kept, recorded kept, and the engine reports it" "$outk"; fi
else
    skp "1 the kept-CLAUDE.md fixture needs KITSRC"
fi
fi

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 2; then
echo
echo "2 · The interactive installer is retired; the guided path is kit/setup.sh"

# Section 15 runs kit/setup.sh new unattended, which takes the defaults the old interactive path offered.
out="$(bash "$KIT/install.sh" --interactive </dev/null 2>&1)"; rc=$?
[[ $rc -eq 2 ]] && grep -qF 'The guided path is kit/setup.sh.' <<<"$out" \
    && ok "2 install.sh --interactive exits 2, naming kit/setup.sh" \
    || ko "2 install.sh --interactive exits 2, naming kit/setup.sh" "rc $rc: $out"
out="$(bash "$KIT/install.sh" </dev/null 2>&1)"; rc=$?
[[ $rc -eq 2 ]] && grep -qF 'The guided path is kit/setup.sh.' <<<"$out" \
    && ok "2 install.sh with no options prints its usage and exits 2" \
    || ko "2 install.sh with no options prints its usage and exits 2" "rc $rc: $out"

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 2b; then
echo
echo "2b · Installer modes and flags"

M="$SCRATCH/modes"
mkdir -p "$M"
if ! mkws_kit "$M/bogus"; then
    skp "2b the installer's fixtures need KITSRC"
else
out="$(bash "$KIT/install.sh" --target "$M/bogus" --init --surfaces bogus 2>&1)"; rc=$?
[[ $rc -ne 0 && ! -e "$M/bogus/CLAUDE.md" ]] && ok "2b an unknown surface stops the run before anything is written" \
    || ko "2b an unknown surface stops the run before anything is written" "rc=$rc $out"
mkws_kit "$M/both" && bash "$KIT/install.sh" --target "$M/both" --init --surfaces Both >/dev/null 2>&1
check "2b --surfaces both installs Claude Code and Gemini CLI" test -f "$M/both/CLAUDE.md" -a -f "$M/both/.gemini/settings.json"

# The plugins are read in place from kit/, so the 2.x ways of registering them are retired.
out="$(bash "$KIT/install.sh" --target "$M/bogus" --plugin github 2>&1)"; rc=$?
[[ $rc -eq 2 && ! -e "$M/bogus/CLAUDE.md" ]] && ok "2b --plugin github is retired (exit 2), and nothing is written" \
    || ko "2b --plugin github is retired (exit 2), and nothing is written" "rc=$rc $out"
out="$(bash "$KIT/install.sh" --target "$M/bogus" --plugin none 2>&1)"; rc=$?
[[ $rc -eq 2 && ! -e "$M/bogus/CLAUDE.md" ]] && ok "2b --plugin none is retired (exit 2), and nothing is written" \
    || ko "2b --plugin none is retired (exit 2), and nothing is written" "rc=$rc $out"
# The engine needs the kit inside the workspace: a repository with no kit/ is refused.
mkdir -p "$M/no-kit" && git -C "$M/no-kit" init -q
out="$(bash "$KIT/install.sh" --target "$M/no-kit" 2>&1)"; rc=$?
[[ $rc -eq 1 && "$(ls -A "$M/no-kit")" == ".git" ]] && grep -q 'no kit at' <<<"$out" \
    && ok "2b a repository with no kit/ is refused (exit 1), naming kit/setup.sh new, and nothing is written" \
    || ko "2b a repository with no kit/ is refused (exit 1), naming kit/setup.sh new, and nothing is written" "rc=$rc $out"

mkws_kit "$M/dry"
st_tree "$M/dry" > "$M/dry-before.txt"
bash "$KIT/install.sh" --target "$M/dry" --dry-run --pilot >/dev/null 2>&1
st_tree "$M/dry" > "$M/dry-after.txt"
empty "2b --dry-run writes nothing" "$(diff "$M/dry-before.txt" "$M/dry-after.txt" 2>&1)"

mkdir -p "$M/only"
bash "$KIT/install.sh" --skills-only --target "$M/only" --skills-dir "$M/only-skills" >/dev/null 2>&1
out="$(bash "$KIT/install.sh" --skills-only --target "$M/only" --skills-dir "$M/only-skills" 2>&1)"
if grep -q '^Already in place:' <<<"$out" && ! grep -qE '^(Created|Merged|Regenerated|Kept as it was)' <<<"$out"; then
    ok "2b a second --skills-only run reports only files already in place"
else ko "2b a second --skills-only run reports only files already in place" "$out"; fi

# The bridge's form: --skills-prefix names each skill kit-<name>, and its sibling sentence uses the
# prefixed names; --skills-skip leaves the named commands out.
bash "$KIT/install.sh" --skills-only --target "$M/only" --skills-dir "$M/prefixed" --skills-prefix kit- \
    --skills-skip closeout,workspace-hygiene >/dev/null 2>&1
bad=""
[[ -f "$M/prefixed/kit-projects-new/SKILL.md" ]] || bad+="no kit-projects-new"$'\n'
grep -q '^name: kit-projects-new$' "$M/prefixed/kit-projects-new/SKILL.md" 2>/dev/null || bad+="the name is not prefixed"$'\n'
grep -qF '(`kit-projects-new`' "$M/prefixed/kit-projects-new/SKILL.md" 2>/dev/null \
    && ! grep -qF '(`projects-new`' "$M/prefixed/kit-projects-new/SKILL.md" 2>/dev/null || bad+="the sibling sentence does not name kit- skills"$'\n'
[[ ! -e "$M/prefixed/kit-closeout" && ! -e "$M/prefixed/kit-workspace-hygiene" ]] || bad+="a skipped command was written"$'\n'
[[ -z "$(find "$M/prefixed" -maxdepth 1 -mindepth 1 ! -name 'kit-*')" ]] || bad+="a folder without the prefix"$'\n'
empty "2b --skills-prefix kit- names the skills and their sibling sentence; --skills-skip leaves commands out" "$bad"
out="$(bash "$KIT/install.sh" --skills-only --target "$M/bogus" --skills-dir "$M/bogus/kit/skills-inside" 2>&1)"; rc=$?
[[ $rc -eq 1 && ! -e "$M/bogus/kit/skills-inside" ]] && ok "2b a skills folder inside the kit checkout is refused (exit 1)" \
    || ko "2b a skills folder inside the kit checkout is refused (exit 1)" "rc=$rc $out"

# A changed command reaches its skill on the next run, with no merge step: generated files are
# refreshed, and nothing is written beside them.
MP="$M/plugins-copy"
cp -R "$KIT/plugins" "$MP"
mkdir -p "$M/regen"
bash "$KIT/install.sh" --skills-only --target "$M/regen" --plugin-src "$MP" --skills-dir "$M/regen-skills" >/dev/null 2>&1
printf '\nOne more line, added upstream.\n' >> "$MP/projects/commands/board.md"
out="$(bash "$KIT/install.sh" --skills-only --target "$M/regen" --plugin-src "$MP" --skills-dir "$M/regen-skills" 2>&1)"
if grep -q 'One more line, added upstream' "$M/regen-skills/projects-board/procedure.md" \
    && [[ -z "$(find "$M/regen-skills" -name '*.kit-incoming')" ]] \
    && grep -q 'projects-board' <<<"$(sed -n '/^Regenerated/,/^$/p' <<<"$out")"; then
    ok "2b a changed command regenerates its skill on the next run, and nothing is written beside it"
else ko "2b a changed command regenerates its skill on the next run, and nothing is written beside it" "$out"; fi

# A command the kit later drops leaves its generated skill and its Gemini wrapper behind, since the
# engine never deletes; the next run names each as a file to delete. The first runs read a clone of the
# kit (kit-a) that still has the command; the next runs read kit/, which never had it.
mkws_kit "$M/retire"
git clone -q "$KITSRC" "$M/retire/kit-a" 2>/dev/null
printf -- '---\ndescription: A command that a later version drops\n---\n\nBody.\n' > "$M/retire/kit-a/plugins/projects/commands/retired.md"
bash "$KIT/install.sh" --skills-only --target "$M/retire" --plugin-src "$M/retire/kit-a/plugins" --skills-dir "$M/retire-skills" >/dev/null 2>&1
bash "$KIT/install.sh" --target "$M/retire" --kit kit-a --init --surfaces claude,gemini >/dev/null 2>&1
out="$( { bash "$KIT/install.sh" --skills-only --target "$M/retire" --skills-dir "$M/retire-skills" 2>&1
          bash "$KIT/install.sh" --target "$M/retire" --surfaces claude,gemini 2>&1; } )"
if grep -q "retire-skills/projects-retired/ was generated from plugins/projects/commands/retired.md" <<<"$out" \
    && grep -q "^  .gemini/commands/projects/retired.toml was generated from" <<<"$out" \
    && [[ "$(grep -c 'no longer has' <<<"$out")" == 2 && -f "$M/retire-skills/projects-retired/SKILL.md" \
          && -f "$M/retire/.gemini/commands/projects/retired.toml" ]]; then
    ok "2b a command the kit has dropped is named as a file to delete, as a skill and as a Gemini wrapper, and nothing is deleted"
else ko "2b a command the kit has dropped is named as a file to delete, as a skill and as a Gemini wrapper, and nothing is deleted" "$out"; fi
fi

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 3; then
echo
echo "3 · JSON, TOML, plugin versions, marketplaces"

# templates/workspace/settings.json has no placeholder in 3.0, so every JSON file parses as it stands.
bad=""
while IFS= read -r f; do jq empty "$f" >/dev/null 2>&1 || bad+="${f#"$KIT"/}"$'\n'; done \
    < <(find "$KIT" -name '*.json' -not -path '*/.git/*' | sort)
empty "3 every JSON file in the kit parses, templates included" "$bad"
bad=""
while IFS= read -r f; do jq empty "$f" >/dev/null 2>&1 || bad+="${f#"$SCRATCH"/}"$'\n'; done \
    < <(find "$T1" "$T1G" -name '*.json' -not -path '*/.git/*' -not -path '*/kit/*' 2>/dev/null | sort)
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
    done < <(find "$T1G/.gemini" -name '*.toml' 2>/dev/null | sort)
    [[ $n -gt 0 ]] || bad="no TOML files were generated"
    empty "3 every generated TOML ($n) parses, with a description and a prompt" "$bad"
fi

check "3 the kit ships no hand-written Gemini wrapper" test -z "$(find "$KIT/templates/workspace" -name '*.toml')"

bad=""
for pj in "$KIT"/plugins/*/.claude-plugin/plugin.json; do
    jq -e '(.version | type == "string") and (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+"))' "$pj" >/dev/null 2>&1 \
        || bad+="${pj#"$KIT"/}"$'\n'
done
empty "3 every plugin.json carries a semantic version" "$bad"

# lists_plugins <marketplace.json> <source prefix> <plugins root> [<directory set>]: the marketplace's
# plugin set equals the directories in <directory set> (default: the kit's plugins/) in both
# directions, each source resolves to that plugin under <plugins root>, and the three the kit ships
# are there by name. A directory the marketplace omits never installs; an entry with no directory
# fails at install time on someone else's machine, which is why both directions are checked.
lists_plugins() {
    local mp="$1" prefix="$2" root="$3" dirs="${4:-$KIT/plugins}" d name src shown problems=""
    for name in closeout projects workspace; do
        jq -e --arg n "$name" '.plugins | map(.name) | index($n) != null' "$mp" >/dev/null || problems+="$name not listed"$'\n'
    done
    for d in "$dirs"/*/; do
        name="$(basename "$d")"
        src="$(jq -r --arg n "$name" '.plugins[] | select(.name == $n) | .source' "$mp")"
        if [[ -z "$src" ]]; then problems+="$name not listed"$'\n'; continue; fi
        [[ "$src" == "$prefix$name" ]] || problems+="$name source is $src"$'\n'
        [[ -f "$root/$name/.claude-plugin/plugin.json" ]] || problems+="$name source does not resolve under $root"$'\n'
    done
    shown="${dirs#"$KIT"/}"; shown="${shown#"$SCRATCH"/}"
    while IFS= read -r name; do
        [[ -d "$dirs/$name" ]] || problems+="$name is listed but has no directory in $shown"$'\n'
    done < <(jq -r '.plugins[].name' "$mp")
    printf '%s' "$problems" | sort -u
}
empty "3 the root marketplace lists all three plugins, and every plugin in plugins/" \
    "$(lists_plugins "$KIT/.claude-plugin/marketplace.json" "./plugins/" "$KIT/plugins")"
# §9.2: the optional "$schema" key is ignored at load time and names a vendor URL, so no marketplace carries it.
empty "3 no marketplace file carries a \$schema key" \
    "$(for f in "$KIT"/.claude-plugin/marketplace.json "$KIT"/plugins/*/.claude-plugin/marketplace.json; do
        [[ -f "$f" ]] && jq -e 'has("$schema")' "$f" >/dev/null && echo "$f"; done)"

# The marketplace check has to bite: two copies of the kit's manifests, one with a plugin directory
# the marketplace omits and one with a marketplace entry that has no directory, must each be reported.
GF="$SCRATCH/gate-fixtures"
for g in extra ghost; do
    mkdir -p "$GF/$g" && cp -R "$KIT/.claude-plugin" "$KIT/plugins" "$GF/$g/"
done
cp -R "$GF/extra/plugins/workspace" "$GF/extra/plugins/extra"
jq '.name = "extra"' "$KIT/plugins/workspace/.claude-plugin/plugin.json" > "$GF/extra/plugins/extra/.claude-plugin/plugin.json"
jq '.plugins += [{"name": "ghost", "description": "A listed plugin with no directory.", "source": "./plugins/ghost"}]' \
    "$KIT/.claude-plugin/marketplace.json" > "$GF/ghost/.claude-plugin/marketplace.json"
r="$(lists_plugins "$GF/extra/.claude-plugin/marketplace.json" "./plugins/" "$GF/extra/plugins" "$GF/extra/plugins")"
grep -q '^extra not listed$' <<<"$r" && ok "3 fixture: a plugin directory the marketplace omits is reported" \
    || ko "3 fixture: a plugin directory the marketplace omits is reported" "got: ${r:-nothing}"
r="$(lists_plugins "$GF/ghost/.claude-plugin/marketplace.json" "./plugins/" "$GF/ghost/plugins" "$GF/ghost/plugins")"
grep -q '^ghost is listed but has no directory' <<<"$r" && ok "3 fixture: a marketplace entry with no plugin directory is reported" \
    || ko "3 fixture: a marketplace entry with no plugin directory is reported" "got: ${r:-nothing}"

# claude plugin validate --strict reads manifests and hooks.json and makes no model call. Pointed at
# a directory it picks marketplace.json over plugin.json, so closeout (which carries both, for its
# standalone mirror) is validated file by file: the root marketplace, then every plugin.json and
# plugin-level marketplace.json by path. It writes a .claude.json into its config directory, so that
# directory is a scratch one, and non-essential traffic is off so it sends no telemetry.
validate_kit() {
    local root="$1" f out bad=""
    for f in "$root" "$root"/plugins/*/.claude-plugin/plugin.json "$root"/plugins/*/.claude-plugin/marketplace.json; do
        [[ -e "$f" ]] || continue
        out="$(env CLAUDE_CONFIG_DIR="$SCRATCH/claude-config" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 \
            claude plugin validate --strict "$f" < /dev/null 2>&1)" \
            || bad+="${f#"$root"/}:"$'\n'"$(grep -E '❯|✘|rror' <<<"$out")"$'\n'
    done
    printf '%s' "$bad"
}
# Without claude the gate is a SKIP, so a green run does not show it ran; AW_REQUIRE_CLAUDE=1 (for a
# release) makes that a FAIL instead.
if ! command -v claude >/dev/null 2>&1; then
    [[ "${AW_REQUIRE_CLAUDE:-}" == 1 ]] && ko "3 claude plugin validate --strict — AW_REQUIRE_CLAUDE=1 and no claude binary on PATH" \
        || skp "3 claude plugin validate --strict not run — no claude binary on PATH"
elif ! claude plugin validate --help < /dev/null >/dev/null 2>&1; then
    [[ "${AW_REQUIRE_CLAUDE:-}" == 1 ]] && ko "3 claude plugin validate --strict — AW_REQUIRE_CLAUDE=1 and this claude has no plugin validate command" \
        || skp "3 claude plugin validate --strict not run — this claude has no plugin validate command"
else
    mkdir -p "$SCRATCH/claude-config"
    empty "3 claude plugin validate --strict passes the root marketplace and every plugin manifest and hooks file" \
        "$(validate_kit "$KIT")"
    # The strict gate has to bite too: an unknown field in a plugin.json is a warning, and --strict fails it.
    mkdir -p "$GF/strict" && cp -R "$KIT/.claude-plugin" "$KIT/plugins" "$GF/strict/"
    jq '.unknownField = true' "$KIT/plugins/projects/.claude-plugin/plugin.json" > "$GF/strict/plugins/projects/.claude-plugin/plugin.json"
    grep -q unknownField <<<"$(validate_kit "$GF/strict")" && ok "3 fixture: claude plugin validate --strict fails a plugin.json with an unknown field" \
        || ko "3 fixture: claude plugin validate --strict fails a plugin.json with an unknown field"
fi

bad="$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$T1/.claude/settings.json" 2>/dev/null)"
missing=""
for name in closeout projects workspace; do grep -qx "$name@agentic-workspace" <<<"$bad" || missing+="$name@agentic-workspace"$'\n'; done
jq -e '.extraKnownMarketplaces["agentic-workspace"].source == {"source": "directory", "path": "kit"}' "$T1/.claude/settings.json" >/dev/null 2>&1 \
    || missing+="the marketplace is not the directory kit"$'\n'
empty "3 .claude/settings.json enables all three plugins from the directory marketplace at kit" "$missing"

# One source per procedure works on both surfaces only if commands speak of arguments in prose.
empty "3 no command uses a tool-specific argument placeholder" \
    "$(cd "$KIT" && grep -nE '\$ARGUMENTS|\{\{args\}\}' plugins/*/commands/*.md 2>/dev/null)"

# Every shell script: the .sh files, and the git hooks, which have no extension.
bad=""
while IFS= read -r f; do bash -n "$f" 2>/dev/null || bad+="${f#"$KIT"/}"$'\n'; done \
    < <({ find "$KIT" -name '*.sh' -not -path '*/.git/*'
          for f in "$KIT"/githooks/*; do [[ -f "$f" && "$(head -n 1 "$f")" == *bash* ]] && echo "$f"; done; } | sort)
empty "3 every shell script passes bash -n, the git hooks included" "$bad"

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 4; then
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
    if grep -qF 'People known for this repository' <<<"$prompt" && grep -qF 'Who needs to' <<<"$prompt" \
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
    grep -qF 'People known for this repository' "$REC.prompt" && ko "4 capture prompt leaves out who-needs-to-know for one person" \
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
empty "4 review: silent inside the capture child, and marks nothing" "$(review "$PR" CLOSEOUT_HOOK_CHILD=1)$(find "$DR" -mindepth 1 -maxdepth 1 -name '.seen*' | sed 's#.*/##')"
outr="$(review "$PR")"
if jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' <<<"$outr" >/dev/null 2>&1 \
    && jq -r '.hookSpecificOutput.additionalContext' <<<"$outr" | grep -qF "$DR/s1.md"; then
    ok "4 review: a pending draft is surfaced as SessionStart additionalContext"
else ko "4 review: a pending draft is surfaced as SessionStart additionalContext" "$outr"; fi
jq -r '.hookSpecificOutput.additionalContext' <<<"$outr" | grep -qF 'Take the step only when two or more are known for this project' \
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

# Who needs to know (closeout 1.3.0): the auto | ask | off setting, the team roster, handles only,
# and the How and Offer columns. The roster's people are folded to the people directory's file names,
# so a person with a profile and a roster row is counted once.
ROSTER_ROWS_FIXTURE='| Name | Role | Default relationship | Channel | Handle |
|---|---|---|---|---|
| <full name> | <what they do> | <relationship> | <channel> | <@handle> |
| Priya Shah | Measurement lead | keep told: anything touching measurement | Slack | @priya |
| Tom Ode | Engineer | helps | email | tom.ode@example.org |
| Lee Ray | Operations | ask first | phone | +44 7700 900123 |
| Kim Day | Analyst since 2026-09-01 | does | team meeting | kim |
| ann@example.org | Designer | helps | Slack | ann |
| Sam Fox | Finance | keep told: budget over 1000000 | email | sam |'
mkroster() { # <name> [setting]: a project with one profile (priya-shah), the roster above, and the setting
    local p; p="$(mkproject "$1" priya-shah)"
    mkdir -p "$p/team"; printf '# Team roster\n\n%s\n' "$ROSTER_ROWS_FIXTURE" > "$p/team/people.md"
    [[ -n "${2:-}" ]] && printf '# Conventions\n\n- **Who needs to know:** `%s`\n' "$2" > "$p/.claude/closeout.md"
    printf '%s' "$p"
}
# setting_of <project> [VAR=value...]: WHO_NEEDS_TO_KNOW|ROSTER_REJECTED, as the hooks compute them.
setting_of() {
    local project="$1"; shift
    env "$@" CLOSEOUT_DRAFT_ROOT="$DRAFTS" bash -c '
        source "$1/lib/config.sh"; closeout_config "$2"
        printf "%s|%s" "$WHO_NEEDS_TO_KNOW" "$ROSTER_REJECTED"' _ "$HOOKS" "$project"
}
RA="$(mkroster roster-auto)" RK="$(mkroster roster-ask ask)" RO="$(mkroster roster-off off)"
r="$(team_of "$RA")"; [[ "$r" == "5|kim-day,lee-ray,priya-shah,sam-fox,tom-ode" ]] \
    && ok "4 team: the roster adds its people, a profile and a roster row for one person count once, the template row is skipped" \
    || ko "4 team: the roster adds its people, a profile and a roster row for one person count once, the template row is skipped" "got $r"
r="$(team_of "$RA" CLOSEOUT_TEAM="dana,eli")"; [[ "$r" == "2|dana,eli" ]] && ok "4 team: CLOSEOUT_TEAM still stands alone with a roster present" || ko "4 team: CLOSEOUT_TEAM still stands alone with a roster present" "got $r"
r="$(team_of "$RA" CLOSEOUT_ROSTER=)"; [[ "$r" == "1|priya-shah" ]] && ok "4 team: an empty CLOSEOUT_ROSTER leaves the roster out" || ko "4 team: an empty CLOSEOUT_ROSTER leaves the roster out" "got $r"
r="$(setting_of "$RA")|$(setting_of "$RK")|$(setting_of "$RO")"
[[ "$r" == "auto|tom-ode,lee-ray,line 10|ask|tom-ode,lee-ray,line 10|off|tom-ode,lee-ray,line 10" ]] \
    && ok "4 setting: auto by default, ask and off read from the conventions; the email and phone rows are named, a name-cell email by its line, the dated row and a figure in a relationship are not" \
    || ko "4 setting: auto by default, ask and off read from the conventions; the email and phone rows are named, a name-cell email by its line, the dated row and a figure in a relationship are not" "got $r"
UW="$SCRATCH/user/who-off.md"; printf -- '- Who needs to know: off\n' > "$UW"
r="$(setting_of "$RA" CLOSEOUT_USER_CONVENTIONS="$UW")|$(setting_of "$RK" CLOSEOUT_USER_CONVENTIONS="$UW")"
[[ "$r" == off\|*\|ask\|* ]] && ok "4 setting: the personal file sets it where the project is silent, and the project's wins" \
    || ko "4 setting: the personal file sets it where the project is silent, and the project's wins" "got $r"
# The template itself parses to no rows and no rejected contact detail.
PTR="$(mkproject roster-template)"; mkdir -p "$PTR/team"; cp "$KIT/templates/team-roster.md" "$PTR/team/people.md"
r="$(team_of "$PTR")|$(setting_of "$PTR")"; [[ "$r" == "0||auto|" ]] && ok "4 roster: the template's own row is a placeholder, with no contact detail" || ko "4 roster: the template's own row is a placeholder, with no contact detail" "got $r"

if capture "$RA" s-roster-auto; then
    p="$(cat "$REC.prompt")"; bad=""
    grep -qF 'priya-shah — keep told: anything touching measurement — Slack @priya' <<<"$p" || bad+="the scoped roster row is not in the prompt as written"$'\n'
    grep -qF 'applies only to a change of' <<<"$p" || bad+="the prompt does not say a scoped relationship applies only to its kind of change"$'\n'
    grep -qF "A project's People section overrides the roster" <<<"$p" || bad+="the prompt does not say the project's People section wins"$'\n'
    grep -qF 'how they' <<<"$p" || bad+="the prompt does not ask how each person hears"$'\n'
    grep -qiE 'example\.org|7700|900123' <<<"$p" && bad+="a contact detail reached the prompt"$'\n'
    grep -qF 'kim-day — does — team meeting kim' <<<"$p" || bad+="the dated row lost its handle"$'\n'
    grep -qF 'sam-fox — keep told: budget over 1000000 — email sam' <<<"$p" || bad+="a figure in a relationship was taken for a phone number"$'\n'
    grep -qF 'ann@' <<<"$p" && bad+="a name-cell email reached the prompt"$'\n'
    empty "4 capture: roster rows reach the prompt with their scope and channel, the project wins, and no email or phone does" "$bad"
    empty "4 capture: the roster prompt has no capitals-for-emphasis" "$(grep -nwE "$shouted" <<<"$p" || true)"
else ko "4 capture: roster rows reach the prompt with their scope and channel, the project wins, and no email or phone does" "the stub never ran"; fi
if capture "$RO" s-roster-off; then
    grep -qF 'People known for this repository' "$REC.prompt" && ko "4 capture: off leaves who-needs-to-know out, with five people known" \
        || ok "4 capture: off leaves who-needs-to-know out, with five people known"
else ko "4 capture: off leaves who-needs-to-know out, with five people known" "the stub never ran"; fi

# review_ctx <project> <draft dir name>: the review hook's injected context for a project with one draft.
review_ctx() { mkdir -p "$DRAFTS/$2"; printf '### a claim\n' > "$DRAFTS/$2/s1.md"; review "$1" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }
ca="$(review_ctx "$RA" roster-auto)" ck="$(review_ctx "$RK" roster-ask)" co="$(review_ctx "$RO" roster-off)"
if grep -qF 'present it to the user as the short who / what / why table' <<<"$ca" && grep -qF 'How (' <<<"$ca" && grep -qF 'Offer (draft, note or none)' <<<"$ca"; then
    ok "4 review: auto presents the table, with How and Offer"
else ko "4 review: auto presents the table, with How and Offer" "$ca"; fi
offer="$(grep -F 'offer the step in one line' <<<"$ck" || true)"
if [[ -n "$offer" ]] && ! grep -qF 'present it to the user as the short' <<<"$ck"; then
    ok "4 review: ask produces a one-line offer, and the table only on a yes"
else ko "4 review: ask produces a one-line offer, and the table only on a yes" "$ck"; fi
if [[ -n "$co" ]] && ! grep -qF 'Who needs to know' <<<"$co"; then ok "4 review: off skips the step"; else ko "4 review: off skips the step" "$co"; fi
if grep -qF 'email address or phone number in the row for: tom-ode, lee-ray' <<<"$ca" && ! grep -qiE 'example\.org|7700' <<<"$ca"; then
    ok "4 review: a roster row with an email address or phone number is flagged by name, without repeating the detail"
else ko "4 review: a roster row with an email address or phone number is flagged by name, without repeating the detail" "$ca"; fi
empty "4 review: the roster context has no capitals-for-emphasis" "$( { printf '%s\n%s\n' "$ca" "$ck"; } | grep -nwE "$shouted" || true)"

# The command and the ritual: the setting, the precedence, the scoped match, and the How and Offer
# columns; the register audit flags a contact detail in the roster; /projects:new offers the roster.
bad=""
for f in plugins/closeout/commands/closeout.md rituals/closeout.md; do
    grep -qE '^\| Who \| What they need to know \| Why them \| How \| Offer \| Where it is recorded \|$' "$KIT/$f" || bad+="$f: no Who | … | How | Offer | … table header"$'\n'
    grep -qF '`draft`' "$KIT/$f" && grep -qF '`note`' "$KIT/$f" && grep -qF '`none`' "$KIT/$f" || bad+="$f: the three offers are not all named"$'\n'
    grep -qF 'Who needs to know:' "$KIT/$f" && grep -qF '`ask`' "$KIT/$f" && grep -qF '`off`' "$KIT/$f" || bad+="$f: no auto | ask | off setting"$'\n'
    tr '\n' ' ' < "$KIT/$f" | grep -qE '`off`[^.;]* (skips this step|leaves it out)' || bad+="$f: off does not skip the step"$'\n'
    tr '\n' ' ' < "$KIT/$f" | grep -qE '`ask`[^.;]* offers it in one line' || bad+="$f: ask is not a one-line offer"$'\n'
    grep -qF 'team/people.md' "$KIT/$f" || bad+="$f: does not name the roster"$'\n'
done
grep -qF "The project's roles win over the roster's" "$KIT/plugins/closeout/commands/closeout.md" || bad+="closeout.md: no precedence sentence"$'\n'
grep -qF 'wins over the roster' "$KIT/rituals/closeout.md" || bad+="rituals/closeout.md: no precedence sentence"$'\n'
grep -qF 'only for a change of that kind' "$KIT/rituals/closeout.md" || bad+="rituals/closeout.md: a scoped relationship is not limited to its kind of change"$'\n'
grep -qF '**Contact detail**' "$KIT/plugins/workspace/commands/register-audit.md" && grep -qF 'team/people.md' "$KIT/plugins/workspace/commands/register-audit.md" \
    || bad+="register-audit.md: does not flag a contact detail in the roster"$'\n'
grep -qF 'team/people.md' "$KIT/plugins/projects/commands/new.md" || bad+="projects new.md: no offer to seed People from the roster"$'\n'
grep -qxF -- '- **Who needs to know:** auto' "$KIT/templates/workspace/closeout.md" || bad+="templates/workspace/closeout.md: no setting line"$'\n'
grep -qE '^\| Name \| Role \| Default relationship \| Channel \| Handle \|$' "$KIT/templates/workspace/closeout.md" || bad+="templates/workspace/closeout.md: no roster example"$'\n'
empty "4 who needs to know: the setting, the roster, precedence and How / Offer in the command, ritual, conventions, audit and /projects:new" "$bad"

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 4b; then
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
cp "$KIT/templates/workspace/projects.md" "$PF/.claude/projects.md"
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
# A headless run (an ablation arm sets AW_HEADLESS_RUN=1) has no one to tell: it says nothing, in a
# project folder or outside one, and records no stamp, so the day's first real session still gets its line.
empty "4b session-start: AW_HEADLESS_RUN=1 is silent in a project folder" "$(pstart "$PF/projects/p07" AW_HEADLESS_RUN=1)"
empty "4b session-start: AW_HEADLESS_RUN=1 is silent outside one, on a day with a line to give, and records no stamp" \
    "$(pstart "$PF" PROJECTS_HOOK_TODAY=2026-01-02 AW_HEADLESS_RUN=1; find "$PSTAMPS" -name '*.last' 2>/dev/null)"
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

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 5; then
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
fx_readme alpha "done"
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
empty "5 metrics.csv holds counts only — a date, fifteen integers, the median days (empty until a project is done), and the three ablation counts" \
    "$(tail -n +2 "$CSV" | grep -vE '^[0-9]{4}-[0-9]{2}-[0-9]{2}(,[0-9]+){15},[0-9]*,[0-9]+,[0-9]*,[0-9]*$' || true)"

# --- F12: the project columns ---------------------------------------------------------------------
# In the fixture above, alpha is created 18 days ago in state doing and set to done 4 days ago (14
# days to done); beta is created 11 days ago in state ready. Neither has a People section and the
# register has no Owner column, so nobody is counted in flight. median_days_to_done is empty until a
# project reaches done.
known="$(printf '%s\n' ${base//,/ } projects_active projects_blocked projects_with_done_when \
    projects_done blocked_over_14d max_in_flight_per_person median_days_to_done \
    ablations_named ablations_discriminating ablations_no_difference)"
[[ "$(head -n 1 "$CSV")" == "$base,projects_active,projects_blocked,projects_with_done_when,projects_done,blocked_over_14d,max_in_flight_per_person,median_days_to_done,ablations_named,ablations_discriminating,ablations_no_difference" ]] \
    && ok "5 F12 the header carries the seven project columns, then the three ablation columns, in order" \
    || ko "5 F12 the header carries the seven project columns, then the three ablation columns, in order" "$(head -n 1 "$CSV")"
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
# line; and a median over two finished projects (6 and 20 days, so 13). CLAUDE.md imports AGENTS.md, so
# naming only CLAUDE.md in MEASURE_ALWAYS_LOADED still counts both: imports are followed.
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
    for pair in always_loaded_bytes=$(( $(wc -c < "$G/CLAUDE.md") + $(wc -c < "$G/AGENTS.md") )) projects_active=3 projects_blocked=1 \
        projects_with_done_when=2 projects_done=2 blocked_over_14d=1 max_in_flight_per_person=2 median_days_to_done=13; do
        got="$(gcol "${pair%%=*}")"; [[ "$got" == "${pair#*=}" ]] || printf '%s: expected %s, got %s\n' "${pair%%=*}" "${pair#*=}" "$got"
    done
)"
empty "5 F12 the data-model rules hold (locations, aliases, gaps, blocked, in flight, moved to done, median)" "$bad"

# --target measures another repository from anywhere; a relative --out stays relative to where it was typed.
tcsv="$SCRATCH/measure-out/t.csv"
tout="$(cd "$SCRATCH" && MEASURE_ALWAYS_LOADED="CLAUDE.md" bash "$KIT/pilot/measure.sh" --target "$G/work" --backfill 0 --out measure-out/t.csv 2>&1)"; trc=$?
[[ $trc -eq 0 && "$(cat "$tcsv" 2>/dev/null)" == "$(cat "$gcsv")" && ! -e "$G/pilot/metrics.csv" ]] \
    && ok "5 --target measures that repository from another directory, the same rows as from inside it" \
    || ko "5 --target measures that repository from another directory, the same rows as from inside it" "rc=$trc $tout"

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

# --- The ablation columns -------------------------------------------------------------------------
# A history that commits ablation files and a results CSV. 15 days ago: x discriminates, y passes
# both arms, z fails both, and a retired ablation with no file left still has rows; x also carries a
# judge row and a bare-repo arm that passes, neither of which may move a count. 8 days ago: y's newer
# run discriminates, and z gains rows misdated two days ago that make it discriminate — on the row for
# 7 days ago they are not yet known. Today an uncommitted ablation file joins, and today's row reads
# the working tree, where z's rows now count.
A="$SCRATCH/measure-abl"
mkdir -p "$A/pilot/ablations" && git -C "$A" init -q
cp "$KIT/pilot/measure.sh" "$KIT/pilot/ablate.sh" "$A/pilot/"
ax_commit() { # <days ago> <message>
    local when; when="$(days_ago "$1")T12:00:00"
    git -C "$A" add -A
    GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git -C "$A" -c commit.gpgsign=false commit -q -m "$2"
}
ax_rows() { # <days ago> <ablation> <with checks> <without checks>: one ok row per run, arms in turn
    local d i c; d="$(days_ago "$1")"
    i=0; for c in $3; do i=$((i + 1)); printf '%s,%s,with,%s,%s,,100,50,0,1000,0.01,2,ok\n' "$d" "$2" "$i" "$c"; done
    i=0; for c in $4; do i=$((i + 1)); printf '%s,%s,without,%s,%s,,100,50,0,1000,0.01,2,ok\n' "$d" "$2" "$i" "$c"; done
}
printf '# Manifest\n' > "$A/CLAUDE.md"
for x in x y z; do printf 'file: CLAUDE.md\nablate:\n  - "# Manifest"\n' > "$A/pilot/ablations/$x.md"; done
printf '# About these ablations\n' > "$A/pilot/ablations/README.md"
{ echo "date,ablation,arm,run,check,judge,input_tokens,output_tokens,cache_read_tokens,duration_ms,cost_usd,turns,status"
  ax_rows 15 x "1 1 1" "0 0 0"; ax_rows 15 y "1 1 1" "1 1 1"; ax_rows 15 z "0 0 0" "0 0 0"; ax_rows 15 retired "1 1 1" "0 0 0"
  printf '%s,x,judge,1,,,100,50,0,1000,0.01,1,ok\n' "$(days_ago 15)"
  for i in 1 2 3; do printf '%s,x,bare-repo,%s,1,,100,50,0,1000,0.01,2,ok\n' "$(days_ago 15)" "$i"; done
} > "$A/pilot/ablation-results.csv"
ax_commit 15 "Three ablations"
{ ax_rows 8 y "1 1 1" "0 0 0"; ax_rows 2 z "1 1 1" "0 0 0"; } >> "$A/pilot/ablation-results.csv"
ax_commit 8 "A second run"
printf 'file: CLAUDE.md\nablate:\n  - "# Manifest"\n' > "$A/pilot/ablations/w.md"
aout="$(cd "$A" && bash pilot/measure.sh --backfill 2 2>&1)"; arc=$?
acol() { awk -F, -v r="$1" -v name="$2" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == name) c = i; next }
                                         NR == r + 1 { print (c ? $c : "missing") }' "$A/pilot/metrics.csv"; }
bad="$(
    for spec in 1:3,1,1 2:3,2,0 3:4,3,0; do
        r="${spec%%:*}" want="${spec#*:}"
        got="$(acol "$r" ablations_named),$(acol "$r" ablations_discriminating),$(acol "$r" ablations_no_difference)"
        [[ "$got" == "$want" ]] || printf 'row %s: expected %s, got %s\n' "$r" "$want" "$got"
    done
)"
[[ $arc -eq 0 ]] || bad+="measure.sh exited $arc: $aout"
empty "5 ablation columns week by week: files at the revision, latest result on or before the day, judge and bare rows ignored, a failing check counted in neither, today from the working tree" "$bad"
# The counts are read by the runner's own rule. As first committed: x discriminates, y passes both arms
# and z fails both.
git -C "$A" show HEAD~1:pilot/ablation-results.csv > "$SCRATCH/measure-abl-first.csv"
arep="$(bash "$A/pilot/ablate.sh" --target "$A" --outcomes "$SCRATCH/measure-abl-first.csv" 2>&1 | sort | cut -f1,3 | paste -sd'|' -)"
[[ "$arep" == "retired	discriminates|x	discriminates|y	no difference (both pass)|z	check fails both arms" ]] \
    && ok "5 ablate.sh --outcomes gives each ablation's latest result, one tab-separated line each" \
    || ko "5 ablate.sh --outcomes gives each ablation's latest result, one tab-separated line each" "$arep"
aflags="$(cd "$A" && bash pilot/ablate.sh --target "$A" --report 2>&1 | awk -F'|' '$2 ~ /^ (x|y|z) $/ { gsub(/ /, "", $2); sub(/^ /, "", $13); split($13, f, ","); sub(/ +$/, "", f[1]); print $2 ":" f[1] }' | sort | paste -sd'|' -)"
[[ "$aflags" == "x:discriminates|y:discriminates|z:discriminates" ]] \
    && ok "5 the ablation columns and the report's flags agree" || ko "5 the ablation columns and the report's flags agree" "$aflags"
# Without the runner beside it, measure.sh counts the files and leaves the two result counts empty; a
# kit checkout named in .claude/plugins/VENDORED supplies the runner.
mkdir -p "$SCRATCH/measure-lone"; cp "$KIT/pilot/measure.sh" "$SCRATCH/measure-lone/measure.sh"
lrow="$(bash "$SCRATCH/measure-lone/measure.sh" --target "$A" --print 2>/dev/null | tail -n 1 | cut -d, -f18-)"
[[ "$lrow" == "4,," ]] && ok "5 without the runner, ablations_named is counted and the other two are empty" \
    || ko "5 without the runner, ablations_named is counted and the other two are empty" "got $lrow"
mkdir -p "$A/.claude/plugins"
printf 'Vendored from github.com/example/kit (plugins/)\nkit commit: 0000000\nkit checkout: %s (on the machine that ran the installer)\n' "$KIT" > "$A/.claude/plugins/VENDORED"
lrow="$(bash "$SCRATCH/measure-lone/measure.sh" --target "$A" --print 2>/dev/null | tail -n 1 | cut -d, -f18-)"
[[ "$lrow" == "4,3,0" ]] && ok "5 the runner is found through the kit checkout .claude/plugins/VENDORED names" \
    || ko "5 the runner is found through the kit checkout .claude/plugins/VENDORED names" "got $lrow"

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 6; then
echo
echo "6 · Words the kit does not use"

# The words the kit does not use live in a private list outside the repository, so the repository
# never spells them out. It is resolved as the hooks resolve it (lib/common.sh aw_word_list): first
# $AW_BANNED_WORDS_FILE, then the "Private word list" of the workspace around this kit checkout, then
# ~/.config/agentic-workspace-kit/banned-words.txt.
# One extended-regex alternative per line; lines starting with # and blank lines are ignored. The scan
# is whole-word and case-insensitive across every text file except the licences, so plurals and
# hyphenated forms are caught exactly as far as the list's own regexes allow. With no list, the scan
# is reported as SKIP, never as PASS.
words_ws="$(git --no-optional-locks -C "$KIT" rev-parse --show-superproject-working-tree 2>/dev/null)"
# shellcheck source=/dev/null
words_file="$( . "$KIT/lib/common.sh" && aw_word_list "$words_ws" 2>/dev/null )"; words_rc=$?
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
[[ "$(wordscan "$ppat" "$probe/tree" | grep -oiwE "($ppat)" | tr '[:upper:]' '[:lower:]' | sort | paste -sd' ' -)" == "blip-blop blipblops zorbl" ]] \
    && ok "6 the word scan catches whole words in any case, with the plurals and hyphens the list allows" \
    || ko "6 the word scan catches whole words in any case, with the plurals and hyphens the list allows" "$(wordscan "$ppat" "$probe/tree")"
# A list line that is not a valid regex fails the scan rather than letting it pass unread.
printf 'zorbl\nblip(\n' > "$probe/broken.txt"
r="$(scanned "probe" wordscan "$(listpattern "$probe/broken.txt")" "$probe/tree")"
[[ "$r" == FAIL* ]] && ok "6 a list line that is not a valid regex fails the scan instead of passing it" \
    || ko "6 a list line that is not a valid regex fails the scan instead of passing it" "$r"

if [[ $words_rc -ne 0 ]]; then
    ko "6 word scan not run — a word list is named but cannot be read, or sits inside the kit checkout"
elif [[ -z "$words_file" || ! -f "$words_file" ]]; then
    skp "6 word scan not run — no word list resolves (AW_BANNED_WORDS_FILE, the workspace's Private word list, or ~/.config/agentic-workspace-kit/banned-words.txt)"
else
    banned="$(listpattern "$words_file")"
    if [[ -z "$banned" ]]; then
        ko "6 the word list at $words_file has no entries"
    else
        entries="$(sed -e 's/[[:space:]]*$//' "$words_file" | grep -cvE '^[[:space:]]*(#|$)')"
        scanned "6 no listed word anywhere in the kit ($entries entries from $words_file)" \
            wordscan "$banned" "$KIT"
        scanned "6 no listed word in the team roster template" wordscan "$banned" "$KIT/templates/team-roster.md"
        if git -C "$KIT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
            scanned "6 no listed word in any commit message reachable from HEAD" \
                bash -c 'git -C "$1" log HEAD --format="%h %s%n%B" | grep -niwE "($2)"' _ "$KIT" "$banned"
        fi
    fi
fi

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 7; then
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

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 8; then
echo
echo "8 · The register: no capitals-for-emphasis in prompts, templates and rituals"

# Command prompts, templates, rituals and the team overlay are read by agents as guidance. Norms are
# stated as facts about how the work is done, so shouted imperatives have no place in them. Lines
# between register-audit ignore markers (used where the words are quoted as examples) are skipped.
# The set covers every file an agent reads as a prompt or as guidance: commands, their examples, the
# templates and rituals, the workspace templates (templates/workspace/), the kit's working standards
# (CLAUDE.kit.md), the git hooks, the docs pages for commands and hooks, and the pilot's prompts (pilot/lib/judge.md, handed to the blind comparator). The closeout hooks' prompts are checked in section 4. Line numbers are
# the file's own, and an ignore-start with no ignore-end fails rather than exempting the rest.
regscan() { # <file>: offending lines as "line: text", plus a note for an unterminated ignore block
    awk '/register-audit: ignore-start/ { s = 1; next } /register-audit: ignore-end/ { s = 0; next }
         !s { print FNR ": " $0 } END { if (s) print "0: unterminated register-audit: ignore-start" }' "$1" \
        | grep -E ': (.*[^[:alnum:]_])?(MUST|NEVER|CRITICAL|IMPORTANT)([^[:alnum:]_].*)?$|^0: unterminated' || true
}
hits=""
shopt -s nullglob
for f in "$KIT"/plugins/*/commands/*.md "$KIT"/plugins/*/examples/* "$KIT"/templates/* "$KIT"/rituals/* \
         "$KIT"/templates/workspace/* "$KIT"/templates/workspace/surface-rows/* "$KIT"/CLAUDE.kit.md \
         "$KIT"/githooks/* "$KIT"/docs/commands/*.md "$KIT"/docs/hooks/*.md "$KIT"/docs/setup.md \
         "$KIT"/docs/migration.md "$KIT"/pilot/lib/*.md; do
    [[ -f "$f" ]] || continue
    h="$(regscan "$f")"
    [[ -n "$h" ]] && hits+="$(printf '%s\n' "$h" | sed "s#^#${f#"$KIT"/}:#")"$'\n'
done
shopt -u nullglob
empty "8 no MUST, NEVER, CRITICAL or IMPORTANT in command, example, template, ritual, workspace template, kit standards, hook, docs or pilot prompt files" "$hits"
empty "8 the team roster template passes the register scan" "$(regscan "$KIT/templates/team-roster.md")"
probe="$SCRATCH/register-probe.md"
printf 'Fine.\n<!-- register-audit: ignore-start -->\nQuoted: MUST.\n<!-- register-audit: ignore-end -->\nYou NEVER skip.\n<!-- register-audit: ignore-start -->\nALWAYS.\n' > "$probe"
[[ "$(regscan "$probe" | paste -sd'|' -)" == "5: You NEVER skip.|0: unterminated register-audit: ignore-start" ]] \
    && ok "8 the register scan reports real line numbers and fails an unterminated ignore block" \
    || ko "8 the register scan reports real line numbers and fails an unterminated ignore block" "$(regscan "$probe")"

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 9; then
echo
echo "9 · The ten commands, on Claude Code and as skills, from one source each"

# The command set is fixed by the contract's command list; an eleventh, or a missing one, fails here
# so the plugins, the skills and this list move together.
commands="closeout/closeout projects/adopt projects/board projects/close projects/hold projects/new projects/pickup
workspace/hygiene workspace/quick-start workspace/register-audit"
have="$(cd "$KIT/plugins" && printf '%s\n' ./*/commands/*.md | sed 's#^\./##' | sed 's#/commands/#/#; s#\.md$##' | sort | paste -sd' ' -)"
[[ "$have" == "$(printf '%s' "$commands" | tr '\n' ' ')" ]] && ok "9 the kit has exactly the ten commands" \
    || ko "9 the kit has exactly the ten commands" "has: $have"
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
# Claude Code reads each command in place from kit/ (the workspace's kit is KITSRC, the working tree);
# the skills section 1 generated point at that same file and carry its body as procedure.md.
bad=""
for pc in $commands; do
    p="${pc%/*}" c="${pc#*/}"
    src="$KIT/plugins/$p/commands/$c.md" sk="$S1/$(skill_of "$pc")"
    cmp -s "$src" "$T1/kit/plugins/$p/commands/$c.md" || bad+="$pc: kit/ in the workspace does not hold the command as it stands in the kit"$'\n'
    if [[ ! -f "$sk/SKILL.md" ]]; then bad+="$pc: no skill $(skill_of "$pc")"$'\n'; continue; fi
    err="$(skill_ok "$sk/SKILL.md" 2>&1)" || bad+="$pc: $(printf '%s' "$err" | tail -n 1)"$'\n'
    grep -qF "\`kit/plugins/$p/commands/$c.md\` in this repository" "$sk/SKILL.md" \
        || bad+="$pc: the skill does not point at the command file in kit/"$'\n'
    body_of "$src" > "$SCRATCH/body.md"
    cmp -s "$SCRATCH/body.md" "$sk/procedure.md" || bad+="$pc: procedure.md is not the command's body"$'\n'
done
extra="$(cd "$S1" 2>/dev/null && find . -mindepth 1 -maxdepth 1 | sed 's#^\./##' | sort | paste -sd' ' -)"
[[ "$extra" == "$(for pc in $commands; do skill_of "$pc"; done | sort | paste -sd' ' -)" ]] || bad+="skills folder holds: $extra"$'\n'
empty "9 every command is read from kit/ by Claude Code and has one valid skill under 30 lines, pointing at it" "$bad"

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

# The ritual restates the command's procedure for surfaces that cannot reach the plugin; these are
# the rules the two copies must not drift apart on.
bad=""
for f in plugins/closeout/commands/closeout.md rituals/closeout.md; do
    for w in 'zero-sum' 'Promote learnings first' '`doing`' '`blocked`' '`paused`' '`done`' 'inside the submodule'; do
        grep -qF -- "$w" "$KIT/$f" || bad+="$f: no $w"$'\n'
    done
done
[[ -z "$bad" ]] && ok "9 closeout parity: the command and the ritual carry the same core rules" \
    || ko "9 closeout parity: the command and the ritual carry the same core rules" "$bad"
# The ablation offer at promotion: only for the two tiers loaded most often, offered and not required,
# made on a proposal as well as a promotion, asked as "what task would go worse", and reported.
bad=""
for f in plugins/closeout/commands/closeout.md rituals/closeout.md; do
    flat="$(tr '\n' ' ' < "$KIT/$f" | tr -s ' ')"
    grep -qE 'two tiers loaded most often|always-loaded tier or general reference' <<<"$flat" || bad+="$f: the offer is not limited to the top two tiers"$'\n'
    grep -qF 'offer an ablation' <<<"$flat" || bad+="$f: no offer of an ablation"$'\n'
    grep -qE 'a no ends it|offered, not required' <<<"$flat" || bad+="$f: the offer is not optional"$'\n'
    grep -qF 'proposed for promotion' <<<"$flat" || bad+="$f: the offer does not ride with a proposal"$'\n'
    grep -qF 'what task would go worse' <<<"$flat" || bad+="$f: no question about what task would go worse"$'\n'
    grep -qF -- '- Any ablation offered' "$KIT/$f" || bad+="$f: no report line for the ablation offer"$'\n'
done
empty "9 closeout parity: the command and the ritual both offer an ablation on the top two tiers, optionally, and report it" "$bad"

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 10; then
echo
echo "10 · Ablations: pilot/ablate.sh end to end against a stub claude"

ABL="$KIT/pilot/ablate.sh"
STRIP="$KIT/pilot/lib/strip-lines.py"

# strip-lines.py: whole lines after trimming, and a line that matches nothing leaves the file alone.
SL="$SCRATCH/strip-lines.txt"
printf 'Keep this.\n  Write every date as YYYY-MM-DD.  \nWrite every date as YYYY-MM-DD, please.\n' > "$SL"
python3 "$STRIP" "$SL" "Write every date as YYYY-MM-DD." >/dev/null 2>&1
[[ "$(cat "$SL")" == $'Keep this.\nWrite every date as YYYY-MM-DD, please.' ]] \
    && ok "10 strip-lines: removes a whole line after trimming, and leaves a longer line that contains it" \
    || ko "10 strip-lines: removes a whole line after trimming, and leaves a longer line that contains it" "$(cat "$SL")"
before="$(cat "$SL")"
err="$(python3 "$STRIP" "$SL" "Keep this." "Write every date" 2>&1)"; rc=$?
[[ $rc -eq 2 && "$err" == *"Write every date"* && "$(cat "$SL")" == "$before" ]] \
    && ok "10 strip-lines: a part-line is not a match — exit 2, the missing line named, the file untouched" \
    || ko "10 strip-lines: a part-line is not a match — exit 2, the missing line named, the file untouched" "rc=$rc $err"

# The fixture: a repository whose plugins come from a directory marketplace that is a submodule, as in a
# workspace that carries the kit. Its always-loaded file has one line the ablation removes.
AK="$SCRATCH/abl-kit" AR="$SCRATCH/abl-repo"
mkdir -p "$AK/plugins/notes" "$AR/.claude" "$AR/pilot/ablations"
printf '{"name": "notes"}\n' > "$AK/plugins/notes/plugin.json"
git -C "$AK" init -q && git -C "$AK" add -A && git -C "$AK" commit -qm "kit"
git -C "$AR" init -q
git -C "$AR" -c protocol.file.allow=always submodule add -q "$AK" kitsub >/dev/null 2>&1
printf '# Team notes\n\nKeep summaries short.\nWrite every date as YYYY-MM-DD.\n' > "$AR/CLAUDE.md"
printf '%s\n' '{"extraKnownMarketplaces": {"local-kit": {"source": {"source": "directory", "path": "kitsub"}}},' \
    ' "enabledPlugins": {"notes@local-kit": true, "other@elsewhere": true}}' > "$AR/.claude/settings.json"
cat > "$AR/pilot/ablations/dates.md" <<'ABLFILE'
---
id: dates
item: "Write every date as YYYY-MM-DD."
tier: always
promoted: 2026-09-29
file: CLAUDE.md
ablate:
  - "Write every date as YYYY-MM-DD."
runs: 3
allowed_tools:
  - Read
  - Write
outputs:
  - notes/meeting.md
---

## Prompt

Write up raw/meeting-notes.txt as notes/meeting.md, in under 100 words. Today is Monday 29 September 2026.

## Fixture

raw/meeting-notes.txt: |
  met on monday about the garden rota.
  next meeting in a fortnight.

## Check

grep -q '2026-' notes/meeting.md
ABLFILE
cat > "$AR/pilot/ablations/moved.md" <<'ABLFILE'
---
file: CLAUDE.md
ablate:
  - "A line that was reworded long ago."
---

## Prompt

Summarise CLAUDE.md.

## Check

true
ABLFILE
cat > "$AR/pilot/ablations/personal.md" <<'ABLFILE'
---
file: ~user/CLAUDE.md
ablate:
  - "A line from the user-level file."
---

## Prompt

Summarise the notes.

## Check

true
ABLFILE
git -C "$AR" add -A && git -C "$AR" commit -qm "fixture"
ARHEAD="$(git -C "$AR" rev-parse HEAD)"
ARCONF="$(cksum < "$AR/.git/config")"

# The stub stands in for the model: it follows the always-loaded line when the file carries it. It
# lists the plugins it finds in the worktree's marketplace submodule, so an uninitialised submodule
# shows up as a missing plugin, and records what it saw for the checks below.
ASTUB="$SCRATCH/abl-bin" ALOG="$SCRATCH/abl-log"
mkdir -p "$ASTUB" "$ALOG"
cat > "$ASTUB/claude" <<'STUBSCRIPT'
#!/usr/bin/env bash
# The comparator is the call with --tools: it prefers whichever output keeps the dated line, and says
# which letter that was, so the runner's unblinding can be checked against it.
if [[ " $* " == *" --tools "* ]]; then
    rec="$(mktemp "${AJLOG:-$ALOG}/judge.XXXXXX")"
    { printf 'cwd_entries=%s\nconfig=%s\n' "$(ls -A | grep -c .)" "${CLAUDE_CONFIG_DIR:-}"
      d="$PWD"; while [[ "$d" != / ]]; do [[ -e "$d/CLAUDE.md" ]] && echo "claude_md_at=$d"; d="$(dirname "$d")"; done
      printf 'arg=%s\n' "$@"; } > "$rec"
    a="${2#*"## Output A"}"; a="${a%%"## Output B"*}"
    grep -q '2026-10-13' <<<"$a" && w=A || w=B
    echo "winner=$w" >> "$rec"; printf '%s' "$2" > "$rec.prompt"
    jq -nc --arg s "${STUB_API_KEY_SOURCE:-none}" '{type: "system", subtype: "init", apiKeySource: $s, plugins: []}'
    jq -nc --arg w "$w" '{type: "result", subtype: "success", is_error: false, duration_ms: 800, num_turns: 1,
        total_cost_usd: 0.01, result: ("Read both.\n{\"winner\": \"" + $w + "\", \"reason\": \"It keeps the dates.\"}"),
        usage: {input_tokens: 100, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 40}}'
    exit 0
fi
rec="$(mktemp "${ALOG:?}/call.XXXXXX")"
{ printf 'headless=%s\ncloseout=%s\n' "${AW_HEADLESS_RUN:-}" "${CLOSEOUT_DISABLED:-}"
  printf 'config=%s\nhome=%s\n' "${CLAUDE_CONFIG_DIR:-}" "$HOME"
  printf 'session=%s\nautoupdater=%s\n' "${CLAUDE_CODE_SESSION_ID:-}" "${DISABLE_AUTOUPDATER:-}"
  [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && printf 'token_sum=%s\n' "$(printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN" | cksum | awk '{print $1}')"
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
      (cd "$CLAUDE_CONFIG_DIR" && find . -type f | sort | sed 's|^\./|cfgfile=|')
      grep -qxF 'A line from the user-level file.' "$CLAUDE_CONFIG_DIR/CLAUDE.md" && echo 'userline=present' || echo 'userline=absent'
      [[ -s "$CLAUDE_CONFIG_DIR/CLAUDE.md" ]] && echo 'usermd=full' || echo 'usermd=empty'
      printf 'market_autoupdate=%s\n' "$(jq -c '[.[] | .autoUpdate]' "$CLAUDE_CONFIG_DIR/plugins/known_marketplaces.json" 2>/dev/null)"
  fi
  [[ -s CLAUDE.md ]] && echo 'claude_md=full' || echo 'claude_md=empty'
  grep -qxF 'Write every date as YYYY-MM-DD.' CLAUDE.md && echo 'line=present' || echo 'line=absent'
  [[ -f raw/meeting-notes.txt ]] && echo 'fixture=placed' || echo 'fixture=missing'
  printf 'arg=%s\n' "$@"; } > "$rec"
plugins="[]"
if [[ -z "${STUB_NO_PLUGINS:-}" ]]; then
    for d in kitsub/plugins/*/; do
        [[ -d "$d" ]] || continue
        n="$(basename "$d")"
        plugins="$(jq -c --arg n "$n" --arg p "${STUB_PLUGIN_ROOT:-$PWD}/${d%/}" '. + [{name: $n, source: ($n + "@local-kit"), path: $p}]' <<<"$plugins")"
    done
fi
# The login the real CLI reports: `none` for a subscription login, the variable's name for an API key.
src="${STUB_API_KEY_SOURCE:-none}"; [ -n "${ANTHROPIC_API_KEY:-}" ] && src=ANTHROPIC_API_KEY
jq -nc --argjson p "$plugins" --arg c "$PWD" --arg s "$src" '{type: "system", subtype: "init", cwd: $c, apiKeySource: $s, plugins: $p}'
[[ -n "${STUB_NO_PLUGINS:-}" ]] && sleep 3
if [[ -n "${STUB_SLEEP:-}" ]]; then
    echo "$$" > "${STUB_MARK:?}/stub.pid"; sleep "$STUB_SLEEP"; echo late > "$STUB_MARK/late"
fi
mkdir -p notes
if grep -qxF 'Write every date as YYYY-MM-DD.' CLAUDE.md; then
    printf 'Garden rota, 2026-09-29. Next meeting 2026-10-13.\n' > notes/meeting.md; out=120
    [[ -n "${STUB_TOOL_USE:-}" ]] && jq -nc '{type: "assistant", message: {content: [{type: "tool_use", name: "Bash",
        input: {command: "git add notes/meeting.md"}}]}}'
else
    printf 'Garden rota, Monday. Next meeting in a fortnight.\n' > notes/meeting.md; out=90
fi
jq -nc --argjson o "$out" --arg nc "${STUB_NO_CACHE_READ:-}" '{type: "result", subtype: "success", is_error: false,
    duration_ms: 1500, num_turns: 2, total_cost_usd: 0.33624339999999997,
    usage: ({input_tokens: 10, cache_creation_input_tokens: 2000, cache_read_input_tokens: 500, output_tokens: $o}
            | if $nc != "" then del(.cache_read_input_tokens) else . end)}'
STUBSCRIPT
chmod +x "$ASTUB/claude"
# ablate <args...>: the runner against the fixture, with the stub first on PATH and no API key from the
# calling shell; output in $aout, status in $arc.
ablate() { aout="$(env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u AW_ALLOW_API_BILLING PATH="$ASTUB:$PATH" ALOG="$ALOG" "$@" 2>&1)"; arc=$?; }
calls() { find "$ALOG" -mindepth 1 -maxdepth 1 ! -name '.*' | grep -c . ; }
# judges: the comparator's logs, judge.<id>, in the stub's log folder.
judges() { find "$AJLOG" -mindepth 1 -maxdepth 1 -name 'judge.*' | sed 's#.*/##' | grep -c '^judge\.[A-Za-z0-9]*$'; }
ACSV="$AR/pilot/ablation-results.csv" AREP="$AR/pilot/ablation-report.md"
wtcount() { git -C "$AR" worktree list | grep -c . ; }

ablate bash "$ABL" --target "$AR" --dry-run --runs 1
if [[ $arc -eq 0 && "$(grep -c 'claude ' <<<"$aout")" == 2 && ! -e "$ACSV" && ! -e "$AREP" && "$(calls)" == 0 && "$(wtcount)" == 1 ]]; then
    ok "10 --dry-run prints one command per arm and runs, writes and leaves nothing"
else ko "10 --dry-run prints one command per arm and runs, writes and leaves nothing" "rc=$arc calls=$(calls)"$'\n'"$aout"; fi

ablate bash "$ABL" --target "$AR" --runs 2
[[ $arc -eq 0 ]] && ok "10 a run with a stale ablation and a user-level one still exits 0" || ko "10 a run with a stale ablation and a user-level one still exits 0" "$aout"
[[ "$(head -n 1 "$ACSV" 2>/dev/null)" == "date,ablation,arm,run,check,judge,input_tokens,output_tokens,cache_read_tokens,duration_ms,cost_usd,turns,status,api_key_source" ]] \
    && ok "10 the CSV header is the spec's thirteen columns plus api_key_source" || ko "10 the CSV header is the spec's thirteen columns plus api_key_source" "$(head -n 1 "$ACSV" 2>&1)"
bad="$(awk -F, 'NR > 1 && NF != 14' "$ACSV" 2>/dev/null)"
empty "10 every CSV row has fourteen fields" "$bad"
today="$(date +%Y-%m-%d)"
want="$today,dates,with,1,1,,2010,120,500,1500,0.336243,2,ok,none
$today,dates,with,2,1,,2010,120,500,1500,0.336243,2,ok,none
$today,dates,without,1,0,,2010,90,500,1500,0.336243,2,ok,none
$today,dates,without,2,0,,2010,90,500,1500,0.336243,2,ok,none
$today,moved,without,,,,,,,,,,stale,"
[[ "$(tail -n +2 "$ACSV" 2>/dev/null)" == "$want" ]] \
    && ok "10 rows per arm and run, the Check graded 1 with the line and 0 without, cost to six places, the subscription login recorded as none, the stale one recorded once, the user-level one not run" \
    || ko "10 rows per arm and run, the Check graded 1 with the line and 0 without, cost to six places, the subscription login recorded as none, the stale one recorded once, the user-level one not run" "$(cat "$ACSV" 2>&1)"
bad=""
for r in "$ALOG"/call.*; do
    grep -qx 'headless=1' "$r" && grep -qx 'closeout=1' "$r" || bad+="$(basename "$r"): environment"$'\n'
    grep -qx 'fixture=placed' "$r" || bad+="$(basename "$r"): fixture missing"$'\n'
    for a in --no-session-persistence --strict-mcp-config --max-budget-usd --allowedTools Read Write; do
        grep -qx "arg=$a" "$r" || bad+="$(basename "$r"): no $a"$'\n'
    done
done
[[ "$(calls)" == 4 ]] || bad+="$(calls) calls, not 4"$'\n'
empty "10 each run sets AW_HEADLESS_RUN and CLOSEOUT_DISABLED, places the fixture and passes the flags and allowed tools" "$bad"
[[ "$(grep -lx 'line=present' "$ALOG"/call.* | grep -c .)" == 2 && "$(grep -lx 'line=absent' "$ALOG"/call.* | grep -c .)" == 2 ]] \
    && ok "10 the line is present in the with arm and absent in the without arm" \
    || ko "10 the line is present in the with arm and absent in the without arm" "$(cat "$ALOG"/call.*)"
[[ "$(git -C "$AR" rev-parse HEAD)" == "$ARHEAD" && "$(git -C "$AR" for-each-ref refs/heads | grep -c .)" == 1 \
    && "$(wtcount)" == 1 && "$(cksum < "$AR/.git/config")" == "$ARCONF" \
    && "$(git -C "$AR" status --porcelain | sort | paste -sd' ' -)" == "?? pilot/ablation-report.md ?? pilot/ablation-results.csv" ]] \
    && ok "10 the target keeps its HEAD, branches and config, no worktree is left, and only the CSV and report are new" \
    || ko "10 the target keeps its HEAD, branches and config, no worktree is left, and only the CSV and report are new" "$(git -C "$AR" status --porcelain; git -C "$AR" worktree list)"
rep="$(cat "$AREP" 2>/dev/null)"
if grep -qF "| dates | $today | 2/2 | 0/2 | 120 ± 0 (n=2) | 90 ± 0 (n=2) |" <<<"$rep" && grep -qF '| discriminates |' <<<"$rep" \
    && grep -qF "| moved | $today |" <<<"$rep" && grep -qF '| stale |' <<<"$rep" && grep -qF '`personal`' <<<"$rep"; then
    ok "10 the report carries n and the date on every figure, the stale ablation, and the user-level one as not run"
else ko "10 the report carries n and the date on every figure, the stale ablation, and the user-level one as not run" "$rep"; fi
n0="$(calls)"
ablate bash "$ABL" --target "$AR" --report
[[ $arc -eq 0 && "$aout" == "$rep" && "$(calls)" == "$n0" ]] \
    && ok "10 --report prints the latest report and runs nothing" || ko "10 --report prints the latest report and runs nothing" "$aout"

# A dirty tree: the arms are cut from HEAD, so an uncommitted change to a named file stops the run.
rows0="$(grep -c . "$ACSV")"
printf 'An uncommitted line.\n' >> "$AR/CLAUDE.md"
ablate bash "$ABL" --target "$AR" dates
[[ $arc -eq 65 && "$aout" == *"dates: CLAUDE.md has uncommitted changes"* && "$(calls)" == "$n0" && "$(grep -c . "$ACSV")" == "$rows0" ]] \
    && ok "10 an uncommitted change to the ablated file refuses the run, naming it, and writes nothing" \
    || ko "10 an uncommitted change to the ablated file refuses the run, naming it, and writes nothing" "rc=$arc"$'\n'"$aout"
git -C "$AR" checkout -q -- CLAUDE.md

# Plugins missing from the init event: the run is stopped, recorded as error, and nothing else runs.
ablate env STUB_NO_PLUGINS=1 bash "$ABL" --target "$AR" --runs 2 dates
last="$(tail -n 1 "$ACSV")"
[[ $arc -eq 3 && "$aout" == *"notes@local-kit is not listed"* && "$(calls)" == "$((n0 + 1))" \
    && "$(grep -c . "$ACSV")" == "$((rows0 + 1))" && "$last" == "$today,dates,with,1,,,,,,,,,error,none" && "$(wtcount)" == 1 ]] \
    && ok "10 an expected plugin missing from the init event stops the run with status error, before any other run" \
    || ko "10 an expected plugin missing from the init event stops the run with status error, before any other run" "rc=$arc last=$last"$'\n'"$aout"

# A result event with a field missing keeps every other value in its own column.
ablate env STUB_NO_CACHE_READ=1 bash "$ABL" --target "$AR" --runs 1 dates
got="$(tail -n 2 "$ACSV")"
[[ $arc -eq 0 && "$got" == "$today,dates,with,1,1,,2010,120,,1500,0.336243,2,ok,none
$today,dates,without,1,0,,2010,90,,1500,0.336243,2,ok,none" ]] \
    && ok "10 a result with no cache_read_input_tokens leaves that column empty and the rest in place, status ok" \
    || ko "10 a result with no cache_read_input_tokens leaves that column empty and the rest in place, status ok" "rc=$arc"$'\n'"$got"

# Billing. Runs are meant to use the subscription login. An API key in the environment, or an
# apiKeyHelper in the settings, refuses the run before anything runs; AW_ALLOW_API_BILLING=1 lets it go
# ahead and records the source; an init event that reports an API key the environment did not show
# stops the run at once.
n6="$(calls)" r6b="$(grep -c . "$ACSV")" AKEY="sk-ant-api03-k22stub-$RANDOM$RANDOM-key"
ablate env ANTHROPIC_API_KEY="$AKEY" bash "$ABL" --target "$AR" --runs 1 dates
[[ $arc -eq 4 && "$aout" == *"ANTHROPIC_API_KEY is set"* && "$aout" == *"AW_ALLOW_API_BILLING=1"* && "$aout" != *"$AKEY"* \
    && "$(calls)" == "$n6" && "$(grep -c . "$ACSV")" == "$r6b" && "$(wtcount)" == 1 ]] \
    && ok "10 an API key in the environment refuses the run: exit 4, nothing run or written, the key not printed" \
    || ko "10 an API key in the environment refuses the run: exit 4, nothing run or written, the key not printed" "rc=$arc"$'\n'"$aout"
AHELP="$SCRATCH/abl-helper-config"; mkdir -p "$AHELP"
printf '{"apiKeyHelper": "/bin/echo not-a-key"}\n' > "$AHELP/settings.json"
ablate env CLAUDE_CONFIG_DIR="$AHELP" bash "$ABL" --target "$AR" --runs 1 dates
[[ $arc -eq 4 && "$aout" == *"configures an apiKeyHelper"* && "$(calls)" == "$n6" && "$(grep -c . "$ACSV")" == "$r6b" ]] \
    && ok "10 an apiKeyHelper in the user settings refuses the run the same way" \
    || ko "10 an apiKeyHelper in the user settings refuses the run the same way" "rc=$arc"$'\n'"$aout"
printf '{"env": {"ANTHROPIC_API_KEY": "%s"}}\n' "$AKEY" > "$AHELP/settings.json"
ablate env CLAUDE_CONFIG_DIR="$AHELP" bash "$ABL" --target "$AR" --runs 1 dates
[[ $arc -eq 4 && "$aout" == *"in its env block"* && "$aout" != *"$AKEY"* && "$(calls)" == "$n6" && "$(grep -c . "$ACSV")" == "$r6b" ]] \
    && ok "10 an API key in the user settings' env block refuses the run the same way, the key not printed" \
    || ko "10 an API key in the user settings' env block refuses the run the same way, the key not printed" "rc=$arc"$'\n'"$aout"
ablate env CLAUDE_CODE_USE_BEDROCK=1 bash "$ABL" --target "$AR" --runs 1 dates
[[ $arc -eq 4 && "$aout" == *"CLAUDE_CODE_USE_BEDROCK is set"* && "$(calls)" == "$n6" && "$(grep -c . "$ACSV")" == "$r6b" ]] \
    && ok "10 a cloud provider switch in the environment refuses the run the same way" \
    || ko "10 a cloud provider switch in the environment refuses the run the same way" "rc=$arc"$'\n'"$aout"
ablate env ANTHROPIC_API_KEY="$AKEY" AW_ALLOW_API_BILLING=1 bash "$ABL" --target "$AR" --runs 1 dates
got="$(tail -n 2 "$ACSV" | cut -d, -f3,13,14 | paste -sd' ' -)"
if [[ $arc -eq 0 && "$got" == "with,ok,ANTHROPIC_API_KEY without,ok,ANTHROPIC_API_KEY" && "$(calls)" == "$((n6 + 2))" ]] \
    && grep -qF '`ANTHROPIC_API_KEY` (an API key, billed' "$AREP" && ! grep -qF "$AKEY" "$ACSV" "$AREP"; then
    ok "10 with AW_ALLOW_API_BILLING=1 the runs go ahead and the API-key source is recorded in the CSV and the report"
else ko "10 with AW_ALLOW_API_BILLING=1 the runs go ahead and the API-key source is recorded in the CSV and the report" "rc=$arc $got"$'\n'"$aout"; fi
grep -qF '`none` (no API key: the subscription login) on ' "$AREP" \
    && ok "10 the report names a subscription login, apiKeySource none, as such" \
    || ko "10 the report names a subscription login, apiKeySource none, as such" "$(grep '^Login' "$AREP")"
ablate env STUB_API_KEY_SOURCE=apiKeyHelper bash "$ABL" --target "$AR" --runs 2 dates
got="$(tail -n 1 "$ACSV" | cut -d, -f2,3,4,5,13,14)"
[[ $arc -eq 3 && "$aout" == *"would be billed"* && "$(calls)" == "$((n6 + 3))" && "$got" == "dates,with,1,,error,apiKeyHelper" && "$(wtcount)" == 1 ]] \
    && ok "10 an init event that reports an API key stops the run with status error, before any other run" \
    || ko "10 an init event that reports an API key stops the run with status error, before any other run" "rc=$arc $got"$'\n'"$aout"

# A results file from before the api_key_source column: the next run adds the column to the header, the
# older 13-field rows stay as they are, and the report reads them, their login as not recorded.
python3 - "$ACSV" <<'PYOLD'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
lines[0] = lines[0].rsplit(",", 1)[0]
lines[1:1] = ["2026-09-01,legacy,with,1,1,,10,20,0,1000,0.2,2,ok", "2026-09-01,legacy,without,1,0,,10,20,0,1000,0.2,2,ok"]
open(p, "w", encoding="utf-8").write("\n".join(lines))
PYOLD
r7="$(grep -c . "$ACSV")"
ablate bash "$ABL" --target "$AR" --runs 1 dates
if [[ $arc -eq 0 && "$(head -n 1 "$ACSV")" == *",status,api_key_source" && "$(grep -c . "$ACSV")" == "$((r7 + 2))" \
    && "$(grep -c '^2026-09-01,legacy,.*,ok$' "$ACSV")" == 2 ]] && grep -qF '| legacy | 2026-09-01 | 1/1 | 0/1 |' "$AREP" \
    && grep -qF 'not recorded on 2 runs' "$AREP"; then
    ok "10 an older results file gains the api_key_source header, keeps its 13-field rows, and the report still reads them"
else ko "10 an older results file gains the api_key_source header, keeps its 13-field rows, and the report still reads them" "rc=$arc $(head -n 1 "$ACSV")"$'\n'"$(grep legacy "$AREP")"; fi

# More ablations, each run by name: a Check that reads tool calls from the captured stream; a fixture that
# cannot be written; a kit-file ablation whose plugins load from outside the worktree; and files the
# parser refuses before anything runs.
abl_file() { # abl_file <id> <file> <ablate line> <front-matter extra> <fixture block> <check>
    printf -- '---\nfile: %s\nablate:\n  - %s\n%s---\n\n## Prompt\n\nWrite up the meeting.\n\n%s## Check\n\n%s\n' \
        "$2" "$3" "$4" "$5" "$6" > "$AR/pilot/ablations/$1.md"
}
abl_file staged CLAUDE.md '"Write every date as YYYY-MM-DD."' $'allowed_tools:\n  - "Bash(git add:*)"\n' "" \
    'grep -q '"'"'"command":"git add notes/meeting.md"'"'"' "$AW_ABLATION_STREAM"'
abl_file unwritable CLAUDE.md '"Write every date as YYYY-MM-DD."' "" $'## Fixture\n\nCLAUDE.md/inside.txt: |\n  cannot be written\n\n' 'true'
abl_file kitfile kitsub/plugins/notes/plugin.json "'{\"name\": \"notes\"}'" "" "" 'true'
abl_file commits CLAUDE.md '"Write every date as YYYY-MM-DD."' $'allowed_tools:\n  - Read\n  - "Bash(git commit:*)"\n' "" 'true'
abl_file barebash CLAUDE.md '"Write every date as YYYY-MM-DD."' $'allowed_tools:\n  - Bash\n' "" 'true'
abl_file gitwild CLAUDE.md '"Write every date as YYYY-MM-DD."' $'allowed_tools:\n  - "Bash(git:*)"\n' "" 'true'
abl_file overwrite CLAUDE.md '"Write every date as YYYY-MM-DD."' "" $'## Fixture\n\nCLAUDE.md: |\n  replaced\n\n' 'true'
abl_file escape CLAUDE.md '"Write every date as YYYY-MM-DD."' $'outputs:\n  - ../../outside.txt\n' "" 'true'
git -C "$AR" add -A && git -C "$AR" commit -qm "more ablations"

ablate env STUB_TOOL_USE=1 bash "$ABL" --target "$AR" --runs 1 staged
got="$(tail -n 2 "$ACSV" | cut -d, -f3,5,13 | paste -sd' ' -)"
[[ $arc -eq 0 && "$got" == "with,1,ok without,0,ok" ]] \
    && ok "10 a Check can read the run's tool calls from AW_ABLATION_STREAM" \
    || ko "10 a Check can read the run's tool calls from AW_ABLATION_STREAM" "rc=$arc $got"$'\n'"$aout"

ablate bash "$ABL" --target "$AR" --runs 1 unwritable
got="$(tail -n 2 "$ACSV" | cut -d, -f3,5,13 | paste -sd' ' -)"
[[ "$got" == "with,,error without,,error" && "$aout" == *"could not write a fixture"* && "$(wtcount)" == 1 ]] \
    && ok "10 a fixture that cannot be written makes the run an error, not a graded run" \
    || ko "10 a fixture that cannot be written makes the run an error, not a graded run" "rc=$arc $got"$'\n'"$aout"

n1="$(calls)"
ablate env STUB_PLUGIN_ROOT="$AK/.." bash "$ABL" --target "$AR" --runs 2 kitfile
last="$(tail -n 1 "$ACSV")"
[[ $arc -eq 3 && "$aout" == *"outside the worktree"* && "$(calls)" == "$((n1 + 1))" \
    && "$(cut -d, -f2,3,4,5,13 <<<"$last")" == "kitfile,with,1,,error" && "$(wtcount)" == 1 ]] \
    && ok "10 ablating a kit file halts with error when the plugins load from outside the worktree" \
    || ko "10 ablating a kit file halts with error when the plugins load from outside the worktree" "rc=$arc last=$last"$'\n'"$aout"
ablate bash "$ABL" --target "$AR" --runs 1 kitfile
got="$(tail -n 2 "$ACSV" | cut -d, -f2,3,13 | paste -sd' ' -)"
[[ $arc -eq 0 && "$got" == "kitfile,with,ok kitfile,without,ok" ]] \
    && ok "10 the same kit-file ablation runs when the plugins load from the worktree" \
    || ko "10 the same kit-file ablation runs when the plugins load from the worktree" "rc=$arc $got"$'\n'"$aout"

bad=""
for pair in "commits:Bash(git commit:*)" "barebash:Bash" "gitwild:Bash(git:*)" \
            "overwrite:would overwrite the ablated file" "escape:outputs must stay inside"; do
    id="${pair%%:*}" want="${pair#*:}" n2="$(calls)" r2="$(grep -c . "$ACSV")"
    ablate bash "$ABL" --target "$AR" --runs 1 "$id"
    [[ $arc -eq 65 && "$aout" == *"$want"* && "$(calls)" == "$n2" && "$(grep -c . "$ACSV")" == "$r2" ]] \
        || bad+="$id: rc=$arc $aout"$'\n'
done
empty "10 the parser refuses allowed tools that could commit, a fixture over the ablated file, and outputs outside the repository" "$bad"

# Stopped from outside mid-run, the runner stops the headless child before it removes the worktrees.
AMARK="$SCRATCH/abl-mark"; mkdir -p "$AMARK"
env PATH="$ASTUB:$PATH" ALOG="$ALOG" STUB_SLEEP=6 STUB_MARK="$AMARK" bash "$ABL" --target "$AR" --runs 1 dates >/dev/null 2>&1 &
arun=$!
for _ in $(seq 1 50); do [[ -s "$AMARK/stub.pid" ]] && break; sleep 0.1; done
kill -TERM "$arun" 2>/dev/null; wait "$arun" 2>/dev/null
spid="$(cat "$AMARK/stub.pid" 2>/dev/null)"
if [[ -n "$spid" ]] && ! kill -0 "$spid" 2>/dev/null && [[ ! -e "$AMARK/late" && "$(wtcount)" == 1 ]]; then
    ok "10 a runner stopped mid-run stops its headless child and leaves no worktree"
else ko "10 a runner stopped mid-run stops its headless child and leaves no worktree" "stub=$spid late=$(ls "$AMARK")"; fi

# The comparator. An ablation with a Judge: run i of each arm goes to the comparator unlabelled; the
# stub comparator prefers the dated output by content, so every verdict unblinds to `with` whichever
# letter it was shown as.
AJLOG="$SCRATCH/abl-judge-log"; mkdir -p "$AJLOG"
{ sed '/^## Check$/,$d' "$AR/pilot/ablations/dates.md" | sed 's/^id: dates$/id: judged/'
  printf '## Judge\n\nPrefer the notes whose dates a reader could resolve in six months.\n'; } > "$AR/pilot/ablations/judged.md"
git -C "$AR" add -A && git -C "$AR" commit -qm "judged"
n3="$(calls)"
ablate env AJLOG="$AJLOG" bash "$ABL" --target "$AR" --runs 2 judged
got="$(grep ",judged," "$ACSV" | cut -d, -f3,4,5,6,13 | paste -sd' ' -)"
[[ $arc -eq 0 && "$got" == "with,1,,with,ok with,2,,with,ok without,1,,,ok without,2,,,ok judge,1,,with,ok judge,2,,with,ok" \
    && "$(calls)" == "$((n3 + 4))" && "$(judges)" == 2 ]] \
    && ok "10 a Judge sends each pair to the comparator and writes the unblinded winner on the with row, with a judge row per pair" \
    || ko "10 a Judge sends each pair to the comparator and writes the unblinded winner on the with row, with a judge row per pair" "rc=$arc $got"$'\n'"$aout"
[[ "$(grep ',judged,judge,1,' "$ACSV")" == "$today,judged,judge,1,,with,100,40,0,800,0.01,1,ok,none" ]] \
    && ok "10 the judge row carries the comparator's own tokens, time, cost, turns and login" \
    || ko "10 the judge row carries the comparator's own tokens, time, cost, turns and login" "$(grep ',judged,judge,' "$ACSV")"
bad=""
for r in "$AJLOG"/judge.*; do
    [[ "$r" == *.prompt ]] && continue
    grep -qx 'cwd_entries=0' "$r" || bad+="$(basename "$r"): the comparator's directory is not empty"$'\n'
    grep -q '^claude_md_at=' "$r" && bad+="$(basename "$r"): a CLAUDE.md above the comparator: $(grep '^claude_md_at=' "$r")"$'\n'
    for a in --no-session-persistence --strict-mcp-config --tools --max-turns 1 --max-budget-usd; do
        grep -qx "arg=$a" "$r" || bad+="$(basename "$r"): no $a"$'\n'
    done
    grep -qx 'arg=' "$r" || bad+="$(basename "$r"): --tools is not given the empty list"$'\n'
    p="$r.prompt"
    grep -q '^## Output A$' "$p" && grep -q '^## Output B$' "$p" && grep -q 'Prefer the notes whose dates' "$p" \
        && grep -q 'Write up raw/meeting-notes.txt' "$p" || bad+="$(basename "$r"): the prompt lacks the rubric, the task or the two outputs"$'\n'
    grep -qiE 'run-[0-9]|/with/|/without/|\{\{' "$p" && bad+="$(basename "$r"): the prompt names an arm or leaves a placeholder"$'\n'
done
empty "10 the comparator runs from an empty directory with no CLAUDE.md above it, no tools, one turn, and a blind prompt" "$bad"
grep -qF '| 2–0–0 (n=2) |' "$AREP" && ok "10 the report counts the verdicts with their n" || ko "10 the report counts the verdicts with their n" "$(grep '| judged |' "$AREP")"

# --judge-kept: pairs kept by an earlier run are judged without running any arm, and the verdict lands on
# that run's with row.
AKEPT="$SCRATCH/abl-kept"
for arm in with without; do
    mkdir -p "$AKEPT/runs/judged/$arm/run-1/outputs/notes"
    printf '{"status": "ok"}\n' > "$AKEPT/runs/judged/$arm/run-1/meta.json"
    : > "$AKEPT/runs/judged/$arm/run-1/stream.jsonl"
done
printf 'Garden rota, 2026-09-29. Next meeting 2026-10-13.\n' > "$AKEPT/runs/judged/with/run-1/outputs/notes/meeting.md"
printf 'Garden rota, Monday. Next meeting in a fortnight.\n' > "$AKEPT/runs/judged/without/run-1/outputs/notes/meeting.md"
printf '%s\n' "2026-09-01,judged,with,1,,,10,20,0,1000,0.2,2,ok" "2026-09-01,judged,without,1,,,10,20,0,1000,0.2,2,ok" >> "$ACSV"
n4="$(calls)" wt0="$(wtcount)"
ablate env AJLOG="$AJLOG" bash "$ABL" --target "$AR" --judge-kept "$AKEPT" judged
got="$(tail -n 3 "$ACSV" | cut -d, -f1,3,6,13 | paste -sd' ' -)"
[[ $arc -eq 0 && "$got" == "2026-09-01,with,with,ok 2026-09-01,without,,ok 2026-09-01,judge,with,ok" && "$(calls)" == "$n4" && "$(wtcount)" == "$wt0" ]] \
    && ok "10 --judge-kept judges a kept pair, runs no arm, and writes the verdict on that run's with row" \
    || ko "10 --judge-kept judges a kept pair, runs no arm, and writes the verdict on that run's with row" "rc=$arc $got"$'\n'"$aout"

# A kept run records its date, and --judge-kept writes onto that date's row even when a later run of the
# same ablation exists; judging the same folder again judges nothing twice.
AKEPT2="$SCRATCH/abl-kept-dated"
for arm in with without; do
    mkdir -p "$AKEPT2/runs/judged/$arm/run-1/outputs/notes"
    printf '{"status": "ok", "date": "2026-09-02"}\n' > "$AKEPT2/runs/judged/$arm/run-1/meta.json"
    : > "$AKEPT2/runs/judged/$arm/run-1/stream.jsonl"
    cp "$AKEPT/runs/judged/$arm/run-1/outputs/notes/meeting.md" "$AKEPT2/runs/judged/$arm/run-1/outputs/notes/"
done
printf '%s\n' "2026-09-02,judged,with,1,,,10,20,0,1000,0.2,2,ok" "2026-09-02,judged,without,1,,,10,20,0,1000,0.2,2,ok" \
    "2026-10-06,judged,with,1,,,10,20,0,1000,0.2,2,ok" "2026-10-06,judged,without,1,,,10,20,0,1000,0.2,2,ok" >> "$ACSV"
j0="$(judges)"
ablate env AJLOG="$AJLOG" bash "$ABL" --target "$AR" --judge-kept "$AKEPT2" judged
got="$(grep -E '^2026-(09-02|10-06),judged,' "$ACSV" | cut -d, -f1,3,6 | paste -sd' ' -)"
[[ $arc -eq 0 && "$got" == "2026-09-02,with,with 2026-09-02,without, 2026-10-06,with, 2026-10-06,without, 2026-09-02,judge,with" ]] \
    && ok "10 --judge-kept writes the verdict on the row of the kept run's own date, not a later run's" \
    || ko "10 --judge-kept writes the verdict on the row of the kept run's own date, not a later run's" "rc=$arc $got"$'\n'"$aout"
r6="$(grep -c . "$ACSV")"
ablate env AJLOG="$AJLOG" bash "$ABL" --target "$AR" --judge-kept "$AKEPT2" judged
[[ $arc -eq 0 && "$(grep -c . "$ACSV")" == "$r6" && "$aout" == *"already judged"* \
    && "$(judges)" == "$((j0 + 1))" ]] \
    && ok "10 --judge-kept twice on one folder adds no row and calls no comparator the second time" \
    || ko "10 --judge-kept twice on one folder adds no row and calls no comparator the second time" "rc=$arc"$'\n'"$aout"

# The coin is fair and recorded: over twelve pairs, verdict.json shows each arm as A at least once (the
# chance of a fair coin failing this is 1 in 2048), every verdict still unblinds to with, and --keep
# keeps runs/ and judge/ but no worktree.
ablate env AJLOG="$AJLOG" bash "$ABL" --target "$AR" --runs 12 --keep judged
kept="$(sed -n 's/^ablate.sh: kept \([^ ]*\) .*/\1/p' <<<"$aout")"
shown="$(cat "$kept"/judge/judged/run-*/verdict.json 2>/dev/null | jq -r .shown_as_a | sort -u | paste -sd' ' -)"
winners="$(cat "$kept"/judge/judged/run-*/verdict.json 2>/dev/null | jq -r .winner | sort -u | paste -sd' ' -)"
[[ $arc -eq 0 && "$shown" == "with without" && "$winners" == "with" && -d "$kept/runs/judged/with/run-12/outputs" \
    && ! -e "$kept/wt" && "$(wtcount)" == 1 ]] \
    && ok "10 the comparator's coin shows each arm as A, verdict.json records it, and --keep leaves no worktree" \
    || ko "10 the comparator's coin shows each arm as A, verdict.json records it, and --keep leaves no worktree" "rc=$arc shown=$shown winners=$winners kept=$kept wt=$(wtcount)"

# --no-judge: the arms run and are graded as usual, but no comparator runs, no judge row is written and
# the with rows' judge column stays empty; --help and --dry-run say so.
n5="$(calls)" j5="$(judges)" r5="$(grep -c . "$ACSV")"
ablate env AJLOG="$AJLOG" bash "$ABL" --target "$AR" --runs 1 --no-judge judged
got="$(tail -n +"$((r5 + 1))" "$ACSV" | cut -d, -f2,3,4,6,13 | paste -sd' ' -)"
[[ $arc -eq 0 && "$got" == "judged,with,1,,ok judged,without,1,,ok" && "$(calls)" == "$((n5 + 2))" \
    && "$(judges)" == "$j5" && "$(wtcount)" == 1 ]] \
    && ok "10 --no-judge runs both arms and calls no comparator: no judge row, the with row's judge column empty" \
    || ko "10 --no-judge runs both arms and calls no comparator: no judge row, the with row's judge column empty" "rc=$arc $got"$'\n'"$aout"
ablate bash "$ABL" --target "$AR" --runs 1 --dry-run --no-judge judged
dry_nj="$aout"
ablate bash "$ABL" --target "$AR" --runs 1 --dry-run judged
help="$(bash "$ABL" --help 2>&1)"
[[ "$dry_nj" != *"judged judge:"* && "$aout" == *"judged judge:"* && "$help" == *"--no-judge"* ]] \
    && ok "10 --dry-run lists the comparator only without --no-judge, and --help names the flag" \
    || ko "10 --dry-run lists the comparator only without --no-judge, and --help names the flag" "$dry_nj"

# The bare arm without a token: the repository's always-loaded files are emptied, the arm is recorded as
# bare-repo, and the report says the user-level tier was present.
ablate bash "$ABL" --target "$AR" --runs 1 --bare dates
got="$(tail -n 3 "$ACSV" | cut -d, -f3,5,13 | paste -sd' ' -)"
last="$(grep -lx 'claude_md=empty' "$ALOG"/call.*)"
[[ $arc -eq 0 && "$got" == "with,1,ok without,0,ok bare-repo,0,ok" && "$(grep -c . <<<"$last")" == 1 ]] && grep -qx 'config=' "$last" \
    && grep -qF '(repository tier only)' "$AREP" && grep -qF 'repository tier emptied; user-level tier present' "$AREP" \
    && ok "10 --bare with no token empties the repository tier, records bare-repo and says the user-level tier was present" \
    || ko "10 --bare with no token empties the repository tier, records bare-repo and says the user-level tier was present" "rc=$arc $got"$'\n'"$(cat "$last")"

# The token switch, stub only. With CLAUDE_CODE_OAUTH_TOKEN set, each run gets a temporary config
# directory holding the minimum set and a temporary HOME, both gone afterwards; a user-level ablation runs
# against the copy; the true bare arm empties the copy's CLAUDE.md too; and the token is passed through
# without appearing in anything the runner writes or prints.
AHOME="$SCRATCH/abl-home" ATMP="$SCRATCH/abl-tmp"
mkdir -p "$AHOME/.claude/plugins/cache/x" "$AHOME/.claude/projects/p" "$AHOME/.claude/todos" "$ATMP"
printf '# Me\n\nA line from the user-level file.\nAnother line.\n' > "$AHOME/.claude/CLAUDE.md"
printf '{}\n' > "$AHOME/.claude/settings.json"
printf '{}\n' > "$AHOME/.claude/plugins/installed_plugins.json"
printf '%s\n' '{"team": {"source": {"source": "directory", "path": "/x"}, "installLocation": "/x", "autoUpdate": true}}' \
    > "$AHOME/.claude/plugins/known_marketplaces.json"
printf 'cached\n' > "$AHOME/.claude/plugins/cache/x/f"
printf 'transcript\n' > "$AHOME/.claude/projects/p/t.jsonl"
printf 'todo\n' > "$AHOME/.claude/todos/t.json"
printf 'auth\n' > "$AHOME/.claude.json"
homesum() { (cd "$AHOME" && find . -type f -exec cksum {} + | sort); }
home0="$(homesum)"
ATOKEN="sk-ant-oat01-k22stub-$RANDOM$RANDOM-token"
tsum="$(printf '%s' "$ATOKEN" | cksum | awk '{print $1}')"
ALOG="$SCRATCH/abl-log-token"; mkdir -p "$ALOG"
tokrun() { ablate env -u CLAUDE_CONFIG_DIR HOME="$AHOME" TMPDIR="$ATMP" CLAUDE_CODE_OAUTH_TOKEN="$ATOKEN" "$@"; }
tokrun bash "$ABL" --target "$AR" --runs 1 --bare --dry-run personal dates
dry_out="$aout"
tokrun bash "$ABL" --target "$AR" --runs 1 --bare --keep personal dates
kept="$(sed -n 's/^ablate.sh: kept \([^ ]*\) .*/\1/p' <<<"$aout")"
got="$(tail -n 6 "$ACSV" | cut -d, -f2,3,5,13 | paste -sd' ' -)"
[[ $arc -eq 0 && "$got" == "dates,with,1,ok dates,without,0,ok dates,bare,0,ok personal,with,1,ok personal,without,1,ok personal,bare,1,ok" ]] \
    && ok "10 with a token, the user-level ablation runs and the bare arm is recorded as bare" \
    || ko "10 with a token, the user-level ablation runs and the bare arm is recorded as bare" "rc=$arc $got"$'\n'"$aout"
bad="" seen=""
for r in "$ALOG"/call.*; do
    c="$(sed -n 's/^config=//p' "$r")" h="$(sed -n 's/^home=//p' "$r")"
    [[ "$c" == "$ATMP"/ablate-cfg.* && "$h" == "$ATMP"/ablate-home.* ]] || bad+="$(basename "$r"): config=$c home=$h"$'\n'
    [[ " $seen " == *" $c "* ]] && bad+="$(basename "$r"): config directory shared with another run"$'\n'; seen+=" $c"
    [[ -e "$c" || -e "$h" ]] && bad+="$(basename "$r"): $c or $h is still there"$'\n'
    grep -qx "token_sum=$tsum" "$r" || bad+="$(basename "$r"): the token did not reach the run unchanged"$'\n'
    [[ "$(grep '^cfgfile=' "$r" | paste -sd' ' -)" == "cfgfile=CLAUDE.md cfgfile=plugins/installed_plugins.json cfgfile=plugins/known_marketplaces.json cfgfile=settings.json" ]] \
        || bad+="$(basename "$r"): copied $(grep '^cfgfile=' "$r" | paste -sd' ' -)"$'\n'
    grep -qx 'market_autoupdate=\[false\]' "$r" && grep -qx 'autoupdater=1' "$r" \
        || bad+="$(basename "$r"): auto-update not off: $(grep 'autoupdate' "$r" | paste -sd' ' -)"$'\n'
done
[[ "$(find "$ALOG" -mindepth 1 -maxdepth 1 -name 'call.*' | grep -c .)" == 6 ]] || bad+="$(find "$ALOG" -mindepth 1 -maxdepth 1 -name 'call.*' | grep -c .) calls, not 6"$'\n'
if find "$ATMP" -mindepth 1 -maxdepth 1 | sed 's#.*/##' | grep -qE '^ablate-(cfg|home|judge)\.'; then bad+="left in TMPDIR: $(ls "$ATMP")"$'\n'; fi
[[ "$(homesum)" == "$home0" ]] || bad+="the person's own config changed"$'\n'
empty "10 each run gets its own temporary config (the minimum set only) and HOME, removed after, the token passed through, and the person's config untouched" "$bad"
pick() { grep -l -x "$1" "$ALOG"/call.* | xargs grep -l -x "$2" | grep -c .; }
[[ "$(pick 'userline=present' 'usermd=full')" == 3 && "$(pick 'userline=absent' 'usermd=full')" == 1 && "$(pick 'userline=absent' 'usermd=empty')" == 2 \
    && "$(grep -lx 'claude_md=empty' "$ALOG"/call.* | grep -c .)" == 2 ]] \
    && ok "10 the user-level line is removed from the copy in the without arm, and the true bare arm empties both tiers" \
    || ko "10 the user-level line is removed from the copy in the without arm, and the true bare arm empties both tiers" "$(grep -h 'user\|claude_md' "$ALOG"/call.*)"
leak=""
grep -qF "$ATOKEN" <<<"$dry_out$aout" && leak+="printed"$'\n'
grep -rqF "$ATOKEN" "$ACSV" "$AREP" "$AR/pilot" && leak+="written under pilot/"$'\n'
[[ -n "$kept" && -d "$kept" ]] && grep -rqF "$ATOKEN" "$kept" && leak+="written in the run directory"$'\n'
[[ -n "$kept" && -d "$kept" ]] || leak+="no kept run directory to search"$'\n'
grep -qF 'CLAUDE_CONFIG_DIR=' <<<"$dry_out" || leak+="--dry-run does not show the config directory"$'\n'
empty "10 the token appears in no output, CSV, report or run directory, --dry-run included" "$leak"
grep -qF '`personal`' "$AREP" && ko "10 a user-level ablation that ran is not listed as not run" "$(cat "$AREP")" \
    || ok "10 a user-level ablation that ran is not listed as not run"

# A Check that prints its whole environment: the token is not in it, so it cannot reach check.txt. The
# runner is started as if from inside a Claude Code session; the run does not inherit that session's id.
abl_file envcheck CLAUDE.md '"Write every date as YYYY-MM-DD."' "" "" 'env; test -n "$AW_ABLATION_ARM"'
git -C "$AR" add -A && git -C "$AR" commit -qm "envcheck"
ALOG="$SCRATCH/abl-log-envcheck"; mkdir -p "$ALOG"
tokrun env CLAUDE_CODE_SESSION_ID=outer-session-k22 bash "$ABL" --target "$AR" --runs 1 --keep envcheck
kept="$(sed -n 's/^ablate.sh: kept \([^ ]*\) .*/\1/p' <<<"$aout")"
leak=""
[[ $arc -eq 0 && -n "$kept" ]] || leak+="rc=$arc, kept=$kept"$'\n'
grep -q '^AW_ABLATION_ARM=' "$kept"/runs/envcheck/with/run-1/check.txt 2>/dev/null || leak+="the Check's environment was not captured"$'\n'
grep -rqF "$ATOKEN" "$kept" 2>/dev/null && leak+="token in the kept run directory"$'\n'
grep -q 'CLAUDE_CODE_OAUTH_TOKEN' "$kept"/runs/envcheck/*/run-1/check.txt 2>/dev/null && leak+="the Check saw the token variable"$'\n'
for r in "$ALOG"/call.*; do
    grep -qx 'session=' "$r" || leak+="$(basename "$r"): inherited $(grep '^session=' "$r")"$'\n'
    grep -qx "token_sum=$tsum" "$r" || leak+="$(basename "$r"): the run itself lost the token"$'\n'
done
empty "10 a Check runs without the login token, and a run does not inherit the outer session's id" "$leak"

# Flags, from a prepared history: discriminates, no difference (both pass), check fails both arms,
# inconclusive, regressed, stale, and demotion candidate on the third weekly both-pass run (two runs in
# one ISO week count once; three weeks of a check failing both arms never count).
AF="$SCRATCH/abl-flags"
mkdir -p "$AF/pilot/ablations" "$AF/.claude"
printf '%s\n' '{"extraKnownMarketplaces": {"local-kit": {"source": {"source": "directory", "path": "kitsub"}}}}' > "$AF/.claude/settings.json"
printf -- '---\nfile: kitsub/plugins/notes/commands/notes.md\nablate:\n  - "A line."\n---\n' > "$AF/pilot/ablations/plugfile.md"
printf -- '---\nfile: CLAUDE.md\nablate:\n  - "A line."\n---\n' > "$AF/pilot/ablations/crashed.md"
git -C "$AF" init -q && printf 'x\n' > "$AF/x" && git -C "$AF" add -A && git -C "$AF" commit -qm "x"
fr() { printf '%s,%s,%s,%s,%s,%s,100,50,0,1000,0.01,2,ok\n' "$@"; }
fr3() { # fr3 <date> <ablation> <with checks> <without checks>: one row per run, arms in turn
    local i=0 c; for c in $3; do i=$((i + 1)); fr "$1" "$2" with $i "$c" ""; done
    i=0; for c in $4; do i=$((i + 1)); fr "$1" "$2" without $i "$c" ""; done
}
{ echo "date,ablation,arm,run,check,judge,input_tokens,output_tokens,cache_read_tokens,duration_ms,cost_usd,turns,status"
  for d in 2026-09-14 2026-09-21 2026-09-28; do fr $d idle with 1 1 ""; fr $d idle without 1 1 ""; done
  fr 2026-09-14 twice with 1 1 ""; fr 2026-09-14 twice without 1 0 ""
  for d in 2026-09-21 2026-09-28; do fr $d fresh with 1 1 ""; fr $d fresh without 1 1 ""; done
  for d in 2026-09-14 2026-09-21 2026-09-28; do fr $d failing with 1 0 ""; fr $d failing without 1 0 ""; done
  fr 2026-09-28 mixed with 1 1 ""; fr 2026-09-28 mixed with 2 0 ""; fr 2026-09-28 mixed without 1 0 ""; fr 2026-09-28 mixed without 2 0 ""
  for d in 2026-09-21 2026-09-23 2026-09-28; do fr $d twice with 1 1 ""; fr $d twice without 1 1 ""; done
  fr 2026-09-21 broken with 1 1 ""; fr 2026-09-21 broken with 2 1 ""; fr 2026-09-21 broken without 1 0 ""; fr 2026-09-21 broken without 2 0 ""
  fr 2026-09-28 broken with 1 0 ""; fr 2026-09-28 broken with 2 0 ""; fr 2026-09-28 broken without 1 0 ""; fr 2026-09-28 broken without 2 0 ""
  fr 2026-09-28 steady with 1 1 ""; fr 2026-09-28 steady without 1 0 ""; fr 2026-09-28 steady bare-repo 1 0 ""
  echo "2026-09-28,moved,without,,,,,,,,,,stale"
  fr 2026-09-28 judged with 1 "" with; fr 2026-09-28 judged with 2 "" with; fr 2026-09-28 judged with 3 "" tie
  fr 2026-09-28 judged without 1 "" ""; fr 2026-09-28 judged without 2 "" ""; fr 2026-09-28 judged without 3 "" ""
  for d in 2026-09-14 2026-09-21 2026-09-28; do
      for i in 1 2 3; do fr $d blind with $i 1 with; fr $d blind without $i 1 ""; done
      for i in 1 2 3; do fr $d ties with $i "" tie; fr $d ties without $i "" ""; done
      for i in 1 2 3; do fr $d worse with $i "" without; fr $d worse without $i "" ""; done
  done
  for d in 2026-06-01 2026-08-03 2026-09-28; do fr $d gappy with 1 1 ""; fr $d gappy without 1 1 ""; done
  for d in 2026-09-07 2026-09-14 2026-09-21; do fr $d early with 1 1 ""; fr $d early without 1 1 ""; done
  fr 2026-09-28 hurts with 1 0 ""; fr 2026-09-28 hurts without 1 1 ""
  echo "2026-09-28,plugfile,with,1,,,,,,,,,error"
  echo "2026-09-28,crashed,with,1,,,,,,,,,error"
  fr3 2026-09-28 gap3 "1 1 1" "0 0 0"; fr3 2026-09-28 gap2 "1 1 1" "1 0 0"; fr3 2026-09-28 gap2low "1 1 0" "0 0 0"
  fr3 2026-09-28 gap1 "1 1 1" "1 1 0"; fr3 2026-09-28 gap1low "1 1 0" "1 0 0"; fr3 2026-09-28 weak "1 0 0" "0 0 0"
  fr3 2026-09-28 same "1 1 1" "1 1 1"
  for d in 2026-09-14 2026-09-21 2026-09-28; do fr3 $d leaning "1 1 1" "1 1 0"; done
  fr 2026-09-28 jlean with 1 "" with; fr 2026-09-28 jlean with 2 "" with; fr 2026-09-28 jlean with 3 "" without
  fr3 2026-09-28 behind "1 1 0" "1 1 1"
  for d in 2026-09-14 2026-09-21 2026-09-28; do fr3 $d behindwk "1 1 0" "1 1 1"; fr3 $d hurtswk "1 0 0" "1 1 0"; done
  for i in 1 2 3; do fr 2026-09-28 jlean without $i "" ""; done
} > "$AF/pilot/ablation-results.csv"
fsum="$(cksum < "$AF/pilot/ablation-results.csv")" n5="$(calls)"
ablate bash "$ABL" --target "$AF" --report
flag() { grep -F "| $1 | 2026-09-28 |" <<<"$aout" | awk -F'|' '{gsub(/^ +| +$/, "", $(NF-1)); print $(NF-1)}'; }
got="idle=$(flag idle); fresh=$(flag fresh); failing=$(flag failing); mixed=$(flag mixed); twice=$(flag twice); broken=$(flag broken); steady=$(flag steady); moved=$(flag moved); judged=$(flag judged)"
[[ $arc -eq 0 && "$got" == "idle=no difference (both pass), demotion candidate; fresh=no difference (both pass); failing=check fails both arms — check needs revision; mixed=inconclusive; twice=no difference (both pass); broken=check fails both arms — check needs revision, regressed; steady=leans with, rerun at k=5; moved=stale; judged=discriminates" ]] \
    && ok "10 flags from a prepared CSV: each outcome, regressed, stale; three both-pass weeks make a demotion candidate, three both-fail weeks do not" \
    || ko "10 flags from a prepared CSV: each outcome, regressed, stale; three both-pass weeks make a demotion candidate, three both-fail weeks do not" "$got"$'\n'"$aout"
got="blind=$(flag blind); ties=$(flag ties); worse=$(flag worse); gappy=$(flag gappy); hurts=$(flag hurts); crashed=$(flag crashed)"
[[ "$got" == "blind=check blind, judge prefers with — check needs revision; ties=no difference (judge ties), demotion candidate; worse=without preferred — the line may hurt, demotion candidate; gappy=no difference (both pass); hurts=without preferred — the line may hurt; crashed=error" ]] \
    && ok "10 flags: a Check both arms pass is blind when the comparator prefers with, a judge-only ablation can reach demotion, and the weeks must be consecutive" \
    || ko "10 flags: a Check both arms pass is blind when the comparator prefers with, a judge-only ablation can reach demotion, and the weeks must be consecutive" "$got"$'\n'"$aout"
got="gap3=$(flag gap3); gap2=$(flag gap2); gap2low=$(flag gap2low); gap1=$(flag gap1); gap1low=$(flag gap1low); weak=$(flag weak); same=$(flag same)"
[[ "$got" == "gap3=discriminates; gap2=discriminates; gap2low=discriminates; gap1=leans with, rerun at k=5; gap1low=leans with, rerun at k=5; weak=check fails both arms — check needs revision; same=no difference (both pass)" ]] \
    && ok "10 flags by gap: 2 or more runs discriminates, 1 leans with, 0 with both passing is no difference; with 1/3 against 0/3 is a check failing both arms, not a lean" \
    || ko "10 flags by gap: 2 or more runs discriminates, 1 leans with, 0 with both passing is no difference; with 1/3 against 0/3 is a check failing both arms, not a lean" "$got"
got="leaning=$(flag leaning); jlean=$(flag jlean)"
[[ "$got" == "leaning=leans with, rerun at k=5; jlean=leans with, rerun at k=5" ]] \
    && ok "10 three weeks of leaning with make no demotion candidate, and a comparator ahead by one pair leans with too" \
    || ko "10 three weeks of leaning with make no demotion candidate, and a comparator ahead by one pair leans with too" "$got"
got="behind=$(flag behind); behindwk=$(flag behindwk); hurtswk=$(flag hurtswk)"
[[ "$got" == "behind=no difference (both pass); behindwk=no difference (both pass), demotion candidate; hurtswk=without preferred — the line may hurt, demotion candidate" ]] \
    && ok "10 flags: with 2/3 against 3/3 is no difference and three weeks of it a demotion candidate; with 1/3 against 2/3 is without preferred, not a check failing both arms" \
    || ko "10 flags: with 2/3 against 3/3 is no difference and three weeks of it a demotion candidate; with 1/3 against 2/3 is without preferred, not a check failing both arms" "$got"
[[ "$(flag plugfile)" == "error — not run: the line is in a plugin file, and plugins load from the checkout, not the worktree" ]] \
    && ok "10 an error on an ablation of a plugin file says why in the report" \
    || ko "10 an error on an ablation of a plugin file says why in the report" "$(flag plugfile)"
early="$(grep -F '| early | 2026-09-21 |' <<<"$aout")"
[[ "$early" == *"| no difference (both pass), demotion candidate |" ]] \
    && ok "10 an ablation not run on the newest date keeps its row, from its own latest date, and its demotion flag" \
    || ko "10 an ablation not run on the newest date keeps its row, from its own latest date, and its demotion flag" "$aout"
[[ "$aout" == *"| 2–0–1 (n=3) |"* && "$(grep -F '| steady |' <<<"$aout")" == *"| 0/1 (repository tier only) |"* ]] \
    && ok "10 the report shows the judge tally and the bare arm with their n" \
    || ko "10 the report shows the judge tally and the bare arm with their n" "$aout"
[[ "$(cksum < "$AF/pilot/ablation-results.csv")" == "$fsum" && ! -e "$AF/pilot/ablation-report.md" && "$(calls)" == "$n5" ]] \
    && ok "10 --report reads the CSV, runs nothing and writes nothing" \
    || ko "10 --report reads the CSV, runs nothing and writes nothing" "$(ls "$AF/pilot")"
# measure.sh counts by the same rule: only `discriminates` as discriminating, only `no difference (both
# pass)` as no difference; a lean and a check failing both arms count in neither.
for x in gap3 gap2 gap2low gap1 gap1low weak same; do printf -- '---\nfile: CLAUDE.md\nablate:\n  - "A line."\n---\n' > "$AF/pilot/ablations/$x.md"; done
mrow="$(bash "$KIT/pilot/measure.sh" --target "$AF" --print 2>/dev/null | tail -n 1 | awk -F, '{ print $(NF-2) "," $(NF-1) "," $NF }')"
[[ "$mrow" == "9,3,1" ]] \
    && ok "10 measure.sh counts three discriminating (gaps 3, 2, 2) and one no difference, and neither a lean nor a failing check" \
    || ko "10 measure.sh counts three discriminating (gaps 3, 2, 2) and one no difference, and neither a lean nor a failing check" "got $mrow"

fi
# ---------------------------------------------------------------------------------------------------
if aw_want 11; then
echo
echo "11 · The state check: one scratch repository per mode, the other keys, and no lock left behind"

# plugins/workspace/bin/state.sh reads a repository and prints key=value lines; the quick-start and the
# setup wizard branch on its mode= line. Each mode is built in scratch from a real install, so the
# facts it reads are the installer's own. It runs under /bin/bash where there is one (bash 3.2 on
# macOS), since that is the floor it is written for.
# STATE and the st_* helpers (st_bash, st_run, st_key, st_expect, st_tree) are in the prelude.
st_err=""

check "11 state.sh parses under $st_bash" "$st_bash" -n "$STATE"
# Every git call goes through --no-optional-locks; a git command in command position without it fails.
empty "11 every git call in state.sh carries --no-optional-locks" \
    "$(grep -nE '(^|[;&|({]|\$\()[[:space:]]*git[[:space:]]' "$STATE" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v -- '--no-optional-locks')"

# Fresh: a workspace as kit/setup.sh new leaves it (mkws), with the pilot, stand-ins still in CLAUDE.md,
# nothing committed.
SF="$SCRATCH/state-fresh"
mkws "$SF" --pilot || ko "11 the fresh fixture: kit/setup.sh new finishes" "$(tail -n 12 "$SF.log" 2>/dev/null)"
r="$(st_run "$SF")"
st_expect "11 fresh: mode and the always-loaded file" "$r" mode=fresh always_loaded=CLAUDE.md agents_md=kit \
    claude_md=kit gemini_md=missing signs= target="$SF" in_git=yes commits=0 authors=0
# The §4 surface table is rendered from the kit's surface rows, so its stand-ins are gone at creation.
[[ "$(st_key "$r" standins_remaining)" -gt 0 && "$(st_key "$r" surface_standins)" == 0 ]] \
    && ok "11 fresh: stand-ins counted in §1–§3 of CLAUDE.md, none in the rendered §4 surface table" \
    || ko "11 fresh: stand-ins counted in §1–§3 of CLAUDE.md, none in the rendered §4 surface table" "$r"
st_expect "11 fresh: the person, their profile and the project conventions" "$r" "person=Priya Shah" \
    person_slug=priya-shah person_profile=missing person_profile_path= people_dir=memory/people people_profiles=0 \
    projects_conventions=kit "projects_dir=projects/<slug>/" "paused_dir=projects/<slug>/" "done_dir=projects/_done/<slug>/" \
    conventions_not_set=0 in_flight_limit=3 "staleness=1 week" default_owner=
st_expect "11 fresh: register, decisions log and the other canonical files" "$r" register=kit \
    register_path=projects/INDEX.md register_rows=0 project_folders=0 decisions_log=kit decisions_log_other= \
    glossary=present glossary_terms=0 build_list=present verification=missing catalogue=missing \
    codeowners=.github/CODEOWNERS kit_incoming= own_skills= foreign_skills=
st_expect "11 fresh: plugins, surfaces and measurement, all read in place from kit/" "$r" settings=present \
    plugins_registered=closeout,projects,workspace plugins_mode=kit plugins_path=kit \
    kit_checkout=kit closeout_conventions=present surfaces=claude gemini_commands=0 \
    measure_script=kit/pilot/measure.sh metrics_csv=missing vendored_commit= state_version=2

# Joining: the team part filled in and committed, this person with no profile yet.
SJ="$SCRATCH/state-joining"
cp -R "$SF" "$SJ"
python3 - "$SJ/CLAUDE.md" <<'PYFILL'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"<[A-Za-z][^<>]* [^<>]*>", "filled in", s))
PYFILL
git -C "$SJ" add -A && git -C "$SJ" -c commit.gpgsign=false commit -q -m "Set up the kit"
r="$(st_run "$SJ")"
st_expect "11 joining: no stand-ins left and no profile for this person" "$r" mode=joining standins_remaining=0 \
    surface_standins=0 person_profile=missing signs= commits=1 authors=1 "author_names=Test Runner" uncommitted=0

# Nothing left: the same, with this person's profile, generated skills and a project folder with its
# own decisions log — none of which is a sign of another system.
SN="$SCRATCH/state-nothing-left"
cp -R "$SJ" "$SN"
printf '# Priya Shah\n' > "$SN/memory/people/priya-shah.md"
printf '# Priya\n' > "$SN/memory/people/priya.md"
mkdir -p "$SN/projects/alpha"
printf '# Alpha\n\n## Current state\n\nState: doing\n' > "$SN/projects/alpha/README.md"
printf '# Decisions\n' > "$SN/projects/alpha/decisions.md"
bash "$KIT/install.sh" --skills-only --target "$SN" --skills-dir "$SN/.claude/skills" >/dev/null 2>&1
git -C "$SN" add -A && git -C "$SN" -c commit.gpgsign=false commit -q -m "First profile"
r="$(st_run "$SN")"
st_expect "11 nothing left: filled in, with a profile; generated skills and project logs are the kit's" "$r" \
    mode=nothing-left person_profile=present person_profile_path=memory/people/priya-shah.md \
    person_profile_candidates=memory/people/priya.md people_profiles=2 project_folders=1 \
    projects_without_current_state=0 adopt_proposals=0 decisions_log=kit own_skills= signs=
r="$(st_run "$SN/memory" --json)"
[[ "$(printf '%s' "$r" | jq -r '.mode + " " + .target' 2>/dev/null)" == "nothing-left $SN" ]] \
    && ok "11 --json gives the same facts, and a folder inside a repository reports on the repository" \
    || ko "11 --json gives the same facts, and a folder inside a repository reports on the repository" "$r"

# Joining comes before existing system: once the team's file is filled in, what the first person left
# beside it is settled, so a newcomer is offered the personal part.
SJ2="$SCRATCH/state-joining-own-skill"
cp -R "$SJ" "$SJ2"
mkdir -p "$SJ2/.claude/skills/our-closeout" && printf -- '---\nname: our-closeout\n---\n' > "$SJ2/.claude/skills/our-closeout/SKILL.md"
st_expect "11 joining takes precedence over the signs of another system" "$(st_run "$SJ2")" mode=joining signs=foreign_skills

# Existing system, first shape: the repository's own CLAUDE.md and register were there before the kit,
# which the engine keeps and records as kept.
SE="$SCRATCH/state-existing"
if mkws_kit "$SE"; then
    git -C "$SE" config user.name "Priya Shah"
    mkdir -p "$SE/projects"
    printf '# How we work\n\nWe keep decisions in plain files beside the code.\n' > "$SE/CLAUDE.md"
    printf '# Work\n\n## Live\n\n## Done\n' > "$SE/projects/INDEX.md"
    git -C "$SE" add -A && git -C "$SE" -c commit.gpgsign=false commit -q -m "Our own system"
    bash "$KIT/install.sh" --target "$SE" "${install_args[@]}" </dev/null >/dev/null 2>&1
fi
r="$(st_run "$SE")"
st_expect "11 existing system: its own CLAUDE.md and register, kept by the engine, nothing written beside them" "$r" \
    mode=existing-system always_loaded=CLAUDE.md claude_md=own agents_md=kit standins_remaining=0 register=foreign \
    kit_incoming= signs=claude_md,register

# Existing system, second shape: a filled-in kit whose person has a profile, plus skills and commands
# of the team's own. Only the ones doing a kit command's job are signs; all of them are listed.
SX="$SCRATCH/state-existing-skills"
cp -R "$SN" "$SX"
mkdir -p "$SX/.claude/skills/our-closeout" "$SX/skills/report-builder" "$SX/.claude/commands"
printf -- '---\nname: our-closeout\n---\n' > "$SX/.claude/skills/our-closeout/SKILL.md"
printf -- '---\nname: report-builder\n---\n' > "$SX/skills/report-builder/SKILL.md"
printf 'Tidy the repository.\n' > "$SX/.claude/commands/tidy-repo.md"
st_expect "11 existing system: own skills listed, the overlapping ones taken as signs" "$(st_run "$SX")" \
    mode=existing-system own_skills=.claude/skills/our-closeout,skills/report-builder,.claude/commands/tidy-repo.md \
    foreign_skills=.claude/skills/our-closeout,.claude/commands/tidy-repo.md signs=foreign_skills

# Existing system, third shape: a GEMINI.md of its own, a decisions log elsewhere, and project
# conventions describing another layout.
SO="$SCRATCH/state-existing-other"
cp -R "$SN" "$SO"
printf '# Ours\n' > "$SO/GEMINI.md"
mkdir -p "$SO/docs/adr" && printf '# 1. Record decisions\n' > "$SO/docs/adr/0001-record.md"
sed 's#^- \*\*Register:\*\* `projects/INDEX.md`#- **Register:** `work/INDEX.md`#' "$SN/.claude/projects.md" > "$SO/.claude/projects.md"
st_expect "11 existing system: GEMINI.md, a decisions log elsewhere, another project layout" "$(st_run "$SO")" \
    mode=existing-system gemini_md=present decisions_log=foreign decisions_log_other=docs/adr \
    projects_conventions=foreign register_path=work/INDEX.md register=missing \
    signs=gemini_md,decisions_log,projects_conventions

# A folder that is not a repository, and one that does not exist.
SP="$SCRATCH/state-plain"; mkdir -p "$SP"
st_expect "11 a plain folder: fresh, with nothing to read" "$(st_run "$SP")" mode=fresh in_git=no always_loaded=none \
    commits=0 settings=missing plugins_mode=none surfaces=
r="$("$st_bash" "$STATE" "$SCRATCH/no-such-folder" 2>"$SCRATCH/state.err")"; rc=$?
[[ $rc -eq 2 && "$r" == error=* && ! -s "$SCRATCH/state.err" ]] \
    && ok "11 a missing target exits 2 with an error= line on stdout" \
    || ko "11 a missing target exits 2 with an error= line on stdout" "rc $rc: $r $(cat "$SCRATCH/state.err")"

# AGENTS.md where a sandbox denies the stat as well as the read: -e sees nothing, and only ls's error
# says the file is there. A stub ls stands in for the sandbox; the control, with the real ls, is missing.
# The copy leaves AGENTS.md out. The ledger records the engine created it, so it is not opaque (§0.4):
# the state check tries it and reports it unreadable.
SB="$SCRATCH/state-denied" SBL="$SCRATCH/ls-deny"
python3 -c 'import shutil, sys; shutil.copytree(sys.argv[1], sys.argv[2], symlinks=True, ignore=lambda d, n: ["AGENTS.md"] if d == sys.argv[1] else [])' "$SF" "$SB"
mkdir -p "$SBL"
printf '%s\n' '#!/bin/sh' 'for a; do case "$a" in */AGENTS.md) echo "ls: $a: Operation not permitted" >&2; exit 1 ;; esac; done' \
    'exec /bin/ls "$@"' > "$SBL/ls"
chmod +x "$SBL/ls"
st_expect "11 an AGENTS.md whose stat is denied reads unreadable; CLAUDE.md stays the always-loaded file" "$(PATH="$SBL:$PATH" st_run "$SB")" \
    agents_md=unreadable always_loaded=CLAUDE.md claude_md=kit mode=fresh
st_expect "11 control: with no AGENTS.md at all it reads missing" "$(st_run "$SB")" agents_md=missing always_loaded=CLAUDE.md
# A repository git will not read here (another owner, as on a mounted folder) says so, not in_git=no.
st_expect "11 a repository git refuses (safe.directory) reads in_git=refused" \
    "$(GIT_TEST_ASSUME_DIFFERENT_OWNER=1 st_run "$SJ")" in_git=refused commits=0
empty "11 silent on stderr in every run above" "$st_err"

# No lock and no write. The repository has a staged change and tracked files whose mtimes no longer
# match the index, so a plain `git status` would refresh the index and write it back through
# index.lock. The state check runs status too, and leaves every path, .git included, as it found it.
SL="$SCRATCH/state-lock"
cp -R "$SN" "$SL"
printf '| Term | A meaning |\n' >> "$SL/memory/glossary.md"
git -C "$SL" add memory/glossary.md
for f in AGENTS.md CLAUDE.md projects/INDEX.md; do age "$SL/$f" 2; done
st_tree "$SL" > "$SCRATCH/state-before.txt"
r="$(st_run "$SL")"
st_tree "$SL" > "$SCRATCH/state-after.txt"
[[ "$(st_key "$r" uncommitted)" == 1 ]] && ok "11 the staged change is seen" || ko "11 the staged change is seen" "$r"
[[ ! -e "$SL/.git/index.lock" ]] && ok "11 no index.lock after a run on a repository with a staged change" \
    || ko "11 no index.lock after a run on a repository with a staged change"
empty "11 nothing under the repository, .git and its index included, changes size or mtime" \
    "$(diff "$SCRATCH/state-before.txt" "$SCRATCH/state-after.txt" 2>&1)"
# The control: a plain status on the same repository does rewrite the index, so the check above can fail.
git -C "$SL" status --porcelain >/dev/null 2>&1
[[ "$(st_tree "$SL" | grep '^\.git/index ')" != "$(grep '^\.git/index ' "$SCRATCH/state-before.txt")" ]] \
    && ok "11 control: a plain git status rewrites that index, so the no-write check can fail" \
    || ko "11 control: a plain git status rewrites that index, so the no-write check can fail"

# The quick-start branches on the state check. Its fenced command, with the placeholder Claude Code
# fills in (${CLAUDE_PLUGIN_ROOT}) standing for the plugin in kit/, is run in each mode's repository;
# the mode it reports must be one the command has a branch for. The command names only keys the script
# emits, names the kit path for a surface that does not fill the placeholder in, keeps a fallback
# for a surface with no shell, and offers the team roster in the team part.
QS="$KIT/plugins/workspace/commands/quick-start.md"
qs_cmd="$(awk '/^```/ { f = !f; next } f && /bin\/state\.sh/ { print; exit }' "$QS")"
bad=""
[[ "$qs_cmd" == *'${CLAUDE_PLUGIN_ROOT}/bin/state.sh'* ]] || bad+="no state-check command in a fence: $qs_cmd"$'\n'
for pair in "$SF:fresh" "$SJ:joining" "$SE:existing-system" "$SN:nothing-left"; do
    d="${pair%:*}" want="${pair##*:}"
    got="$(cd "$d" && CLAUDE_PLUGIN_ROOT="$d/kit/plugins/workspace" "$st_bash" -c "$qs_cmd" 2>&1 | sed -n 's/^mode=//p')"
    [[ "$got" == "$want" ]] || bad+="$d: the quick-start's command reported mode '$got', wanted '$want'"$'\n'
    grep -qF -- "- **\`$want\`** — " "$QS" || bad+="no branch in the quick-start for mode $want"$'\n'
done
[[ -f "$SF/kit/plugins/workspace/bin/state.sh" ]] || bad+="the fallback kit/plugins/workspace/bin/state.sh is not in the workspace"$'\n'
grep -qF '`kit/plugins/workspace/bin/state.sh`' "$QS" || bad+="the quick-start does not name the path in kit/"$'\n'
grep -q 'With no$' "$QS" && grep -q '^shell at all, read `state.sh` as a file' "$QS" || bad+="no fallback for a surface with no shell"$'\n'
awk '/^## The team part/ { s = 1; next } /^## / { s = 0 } s' "$QS" | tr '\n' ' ' \
    | grep -q 'start `team/people.md` from *`templates/team-roster.md`' || bad+="the team part does not offer the team roster"$'\n'
emitted="$(st_run "$SF" | sed 's/=.*//' | sort -u)"
# Keys are the first column of the discovery table, and any key written with an underscore or as
# key=value anywhere in the command (the format's own `key=value` aside).
qs_keys="$( { awk -F'|' '/^## Find out where things stand/ { s = 1 } /^## Which mode/ { s = 0 } s && /^\| `/ { print $2 }' "$QS" \
                | grep -o '`[a-z_]*`'
              grep -oE '`[a-z]+(_[a-z]+)*=[a-z0-9-]*`|`[a-z]+(_[a-z]+)+`' "$QS"; } | tr -d '`' | sed 's/=.*//' | grep -vx key | sort -u)"
[[ -n "$qs_keys" ]] || bad+="no keys read from the quick-start's table"$'\n'
for k in $qs_keys; do
    grep -qx "$k" <<<"$emitted" || bad+="the quick-start names $k, which state.sh does not emit"$'\n'
done
modes="$(sed -n 's/.*then mode=\([a-z-]*\).*/\1/p; s/.*else mode=\([a-z-]*\).*/\1/p' "$STATE" | sort -u | paste -sd' ' -)"
[[ "$modes" == "existing-system fresh joining nothing-left" ]] || bad+="state.sh modes read as: $modes"$'\n'
empty "11 the quick-start's state-check command decides each mode, names only keys state.sh emits, keeps the no-shell fallback and offers the roster" "$bad"

# The scripts setup.sh runs: they parse, lint clean and read git without taking its lock. Section 15
# runs the wizard itself (the ten stages, new, adopt, update, --developer, hooks).
SETUP="$KIT/setup.sh" WZLIB="$KIT/lib/wizard.sh"
check "11 setup.sh parses under $st_bash" "$st_bash" -n "$SETUP"
check "11 lib/wizard.sh parses under $st_bash" "$st_bash" -n "$WZLIB"
sc_list=(setup.sh install.sh lib/wizard.sh lib/common.sh lib/templates.sh plugins/workspace/bin/state.sh
    pilot/ablate.sh pilot/measure.sh plugins/closeout/hooks/lib/config.sh
    githooks/pre-commit githooks/pre-merge-commit githooks/commit-msg githooks/pre-push githooks/stub.sh
    githooks/lib/common.sh)
for f in "$KIT"/scripts/*.sh "$KIT"/lib/setup/*.sh "$KIT"/plugins/workspace/hooks/*.sh; do sc_list+=("${f#"$KIT"/}"); done
if command -v shellcheck >/dev/null 2>&1; then
    check "11 shellcheck -x is clean on setup.sh, install.sh, the libraries, state.sh, the pilot, the git hooks, scripts/, lib/setup/ and the workspace hooks" \
        bash -c 'cd "$1" && shift && shellcheck -x "$@"' _ "$KIT" "${sc_list[@]}"
else
    skp "11 shellcheck not on PATH; the kit's scripts not linted"
fi
empty "11 every git call in the wizard carries --no-optional-locks" \
    "$(grep -nE '(^|[;&|({]|\$\()[[:space:]]*git[[:space:]]' "$SETUP" "$WZLIB" | grep -vE ':[0-9]+:[[:space:]]*#' | grep -v -- '--no-optional-locks')"

fi
# ---------------------------------------------------------------------------------------------------
# The sections in tests/sections/, in order, each sourced into this shell. Each file prints its own
# heading and prefixes its variables and functions with its number (s13_...), since they share one
# shell; each writes only under $SCRATCH.
shopt -s nullglob
aw_section_files=("$KIT"/tests/sections/[0-9]*.sh)
shopt -u nullglob
for aw_section_file in ${aw_section_files[@]+"${aw_section_files[@]}"}; do
    aw_id="${aw_section_file##*/}"; aw_id="${aw_id%%-*}"; aw_id="${aw_id%.sh}"
    aw_want "$aw_id" || continue
    # shellcheck source=/dev/null
    . "$aw_section_file"
done
if [[ -n "${AW_SECTIONS:-}" ]]; then
    for aw_s in $AW_SECTIONS; do
        case " $aw_sections_seen " in *" $aw_s "*) ;; *) echo "note: AW_SECTIONS names $aw_s, and no section has that number" ;; esac
    done
fi

echo
echo "$pass passed, $fail failed, $skip skipped"
[[ $fail -eq 0 ]]
