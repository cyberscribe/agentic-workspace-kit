# shellcheck shell=bash
# The prelude in tests/run.sh defines KITSRC, SCRATCH and the helpers (SC2154); the single-quoted
# bash -c scripts expand their own positional arguments (SC2016); "check && ok || ko" is the suite's
# idiom, where ok never fails (SC2015).
# shellcheck disable=SC2154,SC2016,SC2015
# tests/sections/13-privacy.sh: the privacy guards. scripts/check-paths.sh, the git hooks in
# githooks/ (the stub, the three contexts, chaining to the user's own hooks), lib/setup/gitconfig.sh and
# the Claude Code guard plugins/workspace/hooks/guard-git.sh.
#
# Sourced by tests/run.sh after section 11, in the runner's shell: every variable and function here
# starts with s13_, and everything is written under $SCRATCH/s13. Hooks are called the way git calls
# them, through "$st_bash", with the index, arguments and stdin a test sets. No test reaches the
# network: every pre-push that could ask GitHub is given a stub gh through AW_GH.

echo
echo "13 · Privacy: the path checker, the git hooks, chaining and the agent guard"

s13_S="$SCRATCH/s13"
mkdir -p "$s13_S"

if [[ $kitsrc_ok -ne 1 ]]; then
    skp "13 privacy — KITSRC could not be built (the kit is not a git checkout)"
else

s13_CP="$KITSRC/scripts/check-paths.sh"
s13_out="$s13_S/out"
s13_rc=0

# s13_run <command...>: runs it, output (stdout and stderr) to $s13_out, status to s13_rc.
s13_run() { "$@" > "$s13_out" 2>&1; s13_rc=$?; }
# s13_has <text>: 0 when the last output holds the text.
s13_has() { grep -qF -- "$1" "$s13_out"; }
# s13_expect <description> <want rc> [text that has to appear]: one check on the last run.
s13_expect() {
    local d="$1" want="$2" text="${3:-}"
    if [[ "$s13_rc" -eq "$want" ]] && { [[ -z "$text" ]] || s13_has "$text"; }; then ok "$d"
    else ko "$d" "exit $s13_rc (wanted $want)${text:+; wanted the text: $text}"$'\n'"$(head -n 12 "$s13_out")"; fi
}

# A word list of made-up words, so no test depends on (or prints) a real one.
s13_words="$s13_S/words.txt"
printf '# test list\n\nzorblax\nquindle-?corp\n' > "$s13_words"

# ---- 13.1 The kit's own tree ------------------------------------------------------------------------

s13_run "$st_bash" "$s13_CP" --root "$KITSRC" --content --all
s13_expect "13 check-paths.sh --all --content passes on the kit's working tree (KITSRC)" 0

s13_bad=""
while IFS= read -r s13_l; do
    s13_m="${s13_l%% *}"; s13_p="${s13_l#*$'\t'}"
    case "$s13_p" in
        githooks/pre-*|githooks/commit-msg|lib/setup/*.sh|scripts/*.sh)
            [[ "$s13_m" == 100755 ]] || s13_bad+="$s13_p is $s13_m"$'\n' ;;
    esac
done <<EOF
$(git -C "$KITSRC" ls-files -s)
EOF
empty "13 the hooks and the lib/setup and scripts entry points are mode 100755 in the kit's tree" "$s13_bad"

# No machine path in any kit file: the two home-folder roots, spelled in pieces so this file does not
# match itself.
s13_mp="$(git -C "$KITSRC" grep -n -I -F -e '/Use''rs/' -e '/ho''me/' HEAD -- 2>/dev/null | sed 's/^HEAD://')"
empty "13 no kit file names a machine path (a home folder under the two usual roots)" "$s13_mp"

s13_run "$st_bash" "$s13_CP" --list
s13_expect "13 --list prints the allow-list, .github/ and lib/ included" 0 "lib/ .claude-plugin/ .github/"

# ---- 13.2 Path rules, on paths alone ------------------------------------------------------------------

s13_paths() { printf '%s\n' "$@" | "$st_bash" "$s13_CP" --root "$KITSRC" --paths; }
s13_run s13_paths notes/plan.md
s13_expect "13 a path outside the allow-list is refused" 1 "outside the kit's allow-list"
s13_run s13_paths docs/.secrets/token.md
s13_expect "13 a private-by-name path is refused (.secrets)" 1 "private by name (.secrets)"
s13_run s13_paths docs/drafts/settings.local.json
s13_expect "13 a private-by-name path is refused (settings.local.json)" 1 "private by name (settings.local.json)"
s13_run s13_paths docs/private/brief.md
s13_expect "13 a folder named private is refused" 1 "private by name (private)"
s13_run s13_paths docs/data/responses.csv
s13_expect "13 a data-shaped file outside tests/fixtures/ is refused" 1 "private by name (*.csv)"
s13_run s13_paths tests/fixtures/sample/responses.csv docs/guide.md
s13_expect "13 a data-shaped file inside tests/fixtures/, and an ordinary docs page, are allowed" 0
s13_run s13_paths pilot/metrics.csv
s13_expect "13 the pilot's own results are refused by name" 1 "private by name"

# ---- 13.3 A workspace with the kit inside it ----------------------------------------------------------

s13_W="$s13_S/ws"
if ! mkws_min "$s13_W"; then
    ko "13 mkws_min builds the privacy fixture workspace"
else
s13_K="$s13_W/kit"
# s13_wsmd <Kit may name value>: the fixture's .claude/workspace.md, written whole, with the remotes the
# pre-push tests use.
s13_wsmd() {
    cat > "$s13_W/.claude/workspace.md" <<S13MD
# Workspace settings — Test Team

## Private remotes

<!-- - **Private remote:** \`github.com/<owner>/<repo>\` — confirmed YYYY-MM-DD via gh -->
- **Private remote:** \`github.com/example-owner/field-ws\` — confirmed 2026-09-30 via gh
- **Private remote:** \`github.com/example-owner/person-ws\` — confirmed 2026-09-30 via person

## Public remotes

- **Public remote:** \`github.com/example-owner/site\` — \`projects/site-build/\`, the published site

## Developing the kit

- **Private word list:** none
- **Kit may name:** $1
S13MD
}
s13_wsmd none
# The workspace's own .gitignore gains two lines, one for each way P4 reads a path.
printf '%s\n' 'kit/docs/held-back.md' '/templates/notes/' >> "$s13_W/.gitignore"
# The project slug is assembled, so the kit (this file included) never holds it whole and the
# derived-name rule has something to find.
s13_slug="orchard""-ledger"
mkdir -p "$s13_W/projects/$s13_slug" "$s13_W/projects/closeout" "$s13_W/memory"
printf '# Orchard ledger\n\n- **Versioned:** workspace\n- **Sensitivity:** normal\n' > "$s13_W/projects/$s13_slug/README.md"
printf '# Closeout\n' > "$s13_W/projects/closeout/README.md"
s13_long="The quarterly notes record how the team keeps its logbook between the two review rounds."
printf 'Notes\n\n%s\n' "$s13_long" > "$s13_W/memory/notes.md"
git -C "$s13_W" add -A >/dev/null 2>&1
s13_run git -C "$s13_W" commit -q -m "Workspace fixture"
s13_expect "13 a first commit in a fresh workspace goes through the real hooks and is allowed" 0
check "13 gitconfig.sh --hooks set core.hooksPath to the stub folder in the workspace's git directory" \
    test "$(git -C "$s13_W" config --get core.hooksPath)" = "$(git -C "$s13_W" rev-parse --absolute-git-dir)/aw-hooks"
check "13 ... and in the kit's, through its own git directory" \
    test "$(git -C "$s13_K" config --get core.hooksPath)" = "$(git -C "$s13_K" rev-parse --absolute-git-dir)/aw-hooks"
s13_bad=""
for s13_n in pre-commit pre-merge-commit commit-msg pre-push; do
    s13_f="$(git -C "$s13_W" rev-parse --absolute-git-dir)/aw-hooks/$s13_n"
    [[ -x "$s13_f" && "$(sed -n 2p "$s13_f")" == "# agentic-workspace-kit hook stub 1" ]] || s13_bad+="$s13_n "
done
empty "13 each stub is executable and carries the marker on line 2" "$s13_bad"

s13_run "$st_bash" "$s13_CP" --root "$s13_K" --workspace "$s13_W" --paths <<EOF
docs/held-back.md
templates/notes/draft.md
docs/guide.md
EOF
s13_expect "13 a path the workspace .gitignore lists as kit/<path> is refused" 1 "listed in the workspace .gitignore (.gitignore:"
s13_has "docs/held-back.md" && s13_has "templates/notes/draft.md" && ! s13_has "docs/guide.md" \
    && ok "13 ... and one it lists at the workspace root (an anchored pattern) is refused too, and nothing else" \
    || ko "13 ... and one it lists at the workspace root (an anchored pattern) is refused too, and nothing else" "$(cat "$s13_out")"

# s13_stage <repo> <mode> <path> <content file>: a fresh index from HEAD with one entry added or
# changed, so each case starts clean and nothing needs unstaging. Prints the index path.
s13_n_idx=0
s13_stage() {
    local r="$1" m="$2" p="$3" f="$4" sha ix
    s13_n_idx=$((s13_n_idx + 1)); ix="$s13_S/index.$s13_n_idx"
    if [[ "$m" == 160000 ]]; then sha="$f"; else sha="$(git -C "$r" hash-object -w "$f")" || return 1; fi
    GIT_INDEX_FILE="$ix" git -C "$r" read-tree HEAD && GIT_INDEX_FILE="$ix" git -C "$r" update-index --add --cacheinfo "$m,$sha,$p" || return 1
    printf '%s' "$ix"
}
# s13_kitpc <index> [VAR=value...]: the kit's pre-commit in the kit, with that index.
s13_kitpc() {
    local ix="$1"; shift
    s13_run env GIT_INDEX_FILE="$ix" AW_BANNED_WORDS_FILE="$s13_words" "$@" bash -c 'cd "$1" && exec "$2" githooks/pre-commit' _ "$s13_K" "$st_bash"
}
s13_file() { printf '%b' "$2" > "$s13_S/$1"; printf '%s' "$s13_S/$1"; }

# ---- 13.4 The kit's pre-commit: content rules ----------------------------------------------------------

s13_kitpc "$(s13_stage "$s13_K" 100644 docs/new-page.md "$(s13_file clean.md 'A new page.\n')")"
s13_expect "13 kit pre-commit: a plain docs page is allowed" 0
s13_kitpc "$(s13_stage "$s13_K" 100644 notes/new-page.md "$(s13_file clean2.md 'A new page.\n')")"
s13_expect "13 kit pre-commit: a path outside the allow-list is refused" 1 "outside the kit's allow-list"
s13_kitpc "$(s13_stage "$s13_K" 120000 docs/link.md "$(s13_file link.txt '../README.md')")"
s13_expect "13 kit pre-commit: a symlink is refused" 1 "a symlink"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/images/diagram.png "$(s13_file bin.png 'PNG\0\0\001\002binary')")"
s13_expect "13 kit pre-commit: a binary blob not listed in docs/images/SOURCES.md is refused" 1 "binary ("
s13_ix="$(s13_stage "$s13_K" 100644 docs/images/diagram.png "$s13_S/bin.png")"
printf '# Image sources\n\n| Image | How it was made |\n|---|---|\n| `diagram.png` | Drawn by hand for the tests |\n' > "$s13_S/sources.md"
s13_sha="$(git -C "$s13_K" hash-object -w "$s13_S/sources.md")"
GIT_INDEX_FILE="$s13_ix" git -C "$s13_K" update-index --add --cacheinfo "100644,$s13_sha,docs/images/SOURCES.md"
s13_kitpc "$s13_ix"
s13_expect "13 kit pre-commit: the same image, listed in SOURCES.md with how it was made, is allowed" 0
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/words.md "$(s13_file words.md 'Line one.\nThe Zorblax figures.\n')")"
s13_expect "13 kit pre-commit: a word from the private list is refused, naming the line" 1 "private word (line 2)"
grep -qi zorblax "$s13_out" && ko "13 ... and the word itself is never printed" "$(cat "$s13_out")" \
    || ok "13 ... and the word itself is never printed"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/zorblax-notes.md "$s13_S/clean.md")"
s13_expect "13 kit pre-commit: a private word in a path is refused" 1 "private word (path)"
grep -qi zorblax "$s13_out" && ko "13 ... and the path is printed with the word masked" "$(cat "$s13_out")" \
    || ok "13 ... and the path is printed with the word masked"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/derived.md "$(s13_file derived.md "See the $s13_slug folder.\n")")"
s13_expect "13 kit pre-commit: a project folder's name from the workspace is refused" 1 "names a project folder of the workspace (line 1)"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/derived2.md "$(s13_file derived2.md 'The closeout ritual.\n')")"
s13_expect "13 kit pre-commit: a derived name the kit already uses (closeout) is let through" 0
s13_wsmd "\`$s13_slug\`"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/derived.md "$s13_S/derived.md")"
s13_expect "13 kit pre-commit: a derived name listed under Kit may name is let through" 0
s13_wsmd none
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/copied.md "$s13_W/memory/notes.md")"
s13_expect "13 kit pre-commit: a verbatim copy of a workspace file (the same blob) is refused" 1 "a copy of memory/notes.md"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/partial.md "$(s13_file partial.md "Intro.\n$s13_long\n")")"
s13_expect "13 kit pre-commit: a long line copied from a workspace file is refused, naming the file and line" 1 "a copy of memory/notes.md (line 2)"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/partial.md "$s13_S/partial.md")" AW_ALLOW_COPY=docs/partial.md
s13_expect "13 kit pre-commit: AW_ALLOW_COPY names the path and lets that copy through" 0
# What the workspace keeps out of its own repository is compared too: an ignored private/ folder in
# a project holds the material the kit most needs to keep out.
s13_priv="The intake form records the goals the participant named in the first call, in their words."
mkdir -p "$s13_W/projects/$s13_slug/private"
printf 'Intake\n\n%s\n' "$s13_priv" > "$s13_W/projects/$s13_slug/private/intake.md"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/intake-copy.md "$(s13_file intake-copy.md "Notes.\n$s13_priv\n")")"
s13_expect "13 kit pre-commit: a long line copied from an ignored file in a project's private/ folder is refused" 1 \
    "a copy of projects/$s13_slug/private/intake.md (line 2)"
# The people folder is the one the conventions name, and a short own-repo project folder counts.
cp "$s13_W/.claude/projects.md" "$s13_S/projects.md.orig"; cp "$s13_W/.gitmodules" "$s13_S/gitmodules.orig"
sed 's#^- \*\*People:\*\* `memory/people/<name>.md`#- **People:** `memory/team-notes/<name>.md`#' "$s13_S/projects.md.orig" > "$s13_W/.claude/projects.md"
s13_person="dana""-okafor"
mkdir -p "$s13_W/memory/team-notes" && printf '# Dana\n' > "$s13_W/memory/team-notes/$s13_person.md"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/people.md "$(s13_file people.md "Ask $s13_person first.\n")")"
s13_expect "13 kit pre-commit: a name from the people folder the conventions name (People:) is refused" 1 "names a person's profile of the workspace (line 1)"
s13_short="q""7x"
git config -f "$s13_W/.gitmodules" "submodule.projects/$s13_short.path" "projects/$s13_short"
git config -f "$s13_W/.gitmodules" "submodule.projects/$s13_short.url" "https://example.invalid/tools.git"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/short.md "$(s13_file short.md "The $s13_short launch.\n")")"
s13_expect "13 kit pre-commit: an own-repo project's folder name is refused, under 4 characters too" 1 "names a project folder of the workspace (line 1)"
cp "$s13_S/projects.md.orig" "$s13_W/.claude/projects.md"; cp "$s13_S/gitmodules.orig" "$s13_W/.gitmodules"
# The workspace's own private terms (.claude/private-terms.local): made-up names here, as always.
printf '# terms\nvelmora\nNQX-?ops\n' > "$s13_W/.claude/private-terms.local"
s13_kitpc "$(s13_stage "$s13_K" 100644 docs/terms.md "$(s13_file terms.md 'Plain.\nThe Velmora pilot.\n')")"
s13_expect "13 kit pre-commit: a term from the workspace's .claude/private-terms.local is refused, naming the line" 1 "private term of the workspace (line 2)"
grep -qi velmora "$s13_out" && ko "13 ... and the term is never printed" "$(cat "$s13_out")" || ok "13 ... and the term is never printed"
printf 'Notes for NQXops\n' > "$s13_S/msg-term"
s13_run env AW_BANNED_WORDS_FILE="$s13_words" bash -c 'cd "$1" && exec "$2" githooks/commit-msg "$3"' _ "$s13_K" "$st_bash" "$s13_S/msg-term"
s13_expect "13 kit commit-msg: a private term in the message is refused" 1 "private term of the workspace (line 1)"
s13_run s13_paths .claude/private-terms.local docs/private-terms.local
s13_expect "13 private-terms.local is private by name wherever it sits" 1 "private by name (private-terms.local)"
printf '# terms\n' > "$s13_W/.claude/private-terms.local"
s13_kitpc "$(s13_stage "$s13_K" 100755 githooks/pre-commit "$(s13_file hook.sh '#!/usr/bin/env bash\nexit 0\n')")"
s13_expect "13 kit pre-commit: a change to a guard file is refused" 1 "a guard file"
s13_kitpc "$(s13_stage "$s13_K" 100755 githooks/pre-commit "$s13_S/hook.sh")" AW_GUARD_CHANGE=1
s13_expect "13 kit pre-commit: AW_GUARD_CHANGE=1 lets a deliberate guard change through" 0

# The same hooks through git itself: a commit inside kit/ goes stub -> kit hook, in the kit context.
printf 'An end-to-end page.\n' > "$s13_K/docs/e2e-page.md"
git -C "$s13_K" add docs/e2e-page.md
s13_run env AW_BANNED_WORDS_FILE="$s13_words" git -C "$s13_K" commit -q -m "Add an end-to-end page"
s13_expect "13 a real commit inside kit/ runs the kit's hooks and is allowed" 0
mkdir -p "$s13_K/notes" && printf 'x\n' > "$s13_K/notes/e2e.md"
git -C "$s13_K" add notes/e2e.md
s13_run env AW_BANNED_WORDS_FILE="$s13_words" git -C "$s13_K" commit -q -m "Add a note"
s13_expect "13 a real commit inside kit/ of a path outside the allow-list is refused" 1 "aw pre-commit: refused 1 item(s)"

# ---- 13.5 commit-msg and the push walk in the kit -------------------------------------------------------

s13_trailer="Co-Authored""-By: Claude <noreply@""anthropic.com>"
printf 'Add a page\n\n%s\n' "$s13_trailer" > "$s13_S/msg-attr"
s13_run env AW_BANNED_WORDS_FILE="$s13_words" bash -c 'cd "$1" && exec "$2" githooks/commit-msg "$3"' _ "$s13_K" "$st_bash" "$s13_S/msg-attr"
s13_expect "13 kit commit-msg: an attribution trailer is refused" 1 "attribution trailer"
printf 'Add a page about Zorblax\n' > "$s13_S/msg-word"
s13_run env AW_BANNED_WORDS_FILE="$s13_words" bash -c 'cd "$1" && exec "$2" githooks/commit-msg "$3"' _ "$s13_K" "$st_bash" "$s13_S/msg-word"
s13_expect "13 kit commit-msg: a private word in the message is refused" 1 "private word (line 1)"
printf 'Add a page\n\nPlain body.\n' > "$s13_S/msg-ok"
s13_run env AW_BANNED_WORDS_FILE="$s13_words" bash -c 'cd "$1" && exec "$2" githooks/commit-msg "$3"' _ "$s13_K" "$st_bash" "$s13_S/msg-ok"
s13_expect "13 kit commit-msg: a plain message is allowed" 0

# Commits to push are made in a clone with no hooks and fetched into the kit, so the fixture never
# has to step round the checks it is testing.
s13_C="$s13_S/kit-clone"
git clone -q "$KITSRC" "$s13_C" 2>/dev/null
s13_base="$(git -C "$s13_C" rev-parse HEAD)"
mkdir -p "$s13_C/notes" && printf 'secret\n' > "$s13_C/notes/plan.md"
git -C "$s13_C" add notes/plan.md && git -C "$s13_C" commit -q -m "Add a plan"
GIT_INDEX_FILE="$s13_S/index.back" git -C "$s13_C" read-tree "$s13_base"
GIT_INDEX_FILE="$s13_S/index.back" git -C "$s13_C" commit -q -m "Take the plan out again"
s13_addrm="$(git -C "$s13_C" rev-parse HEAD)"
git -C "$s13_C" read-tree HEAD
printf 'A page.\n' > "$s13_C/docs/pushed-page.md"
git -C "$s13_C" add docs/pushed-page.md && git -C "$s13_C" commit -q -m "Add a pushed page" -m "$s13_trailer"
s13_attr="$(git -C "$s13_C" rev-parse HEAD)"
git -C "$s13_C" branch -q clean "$s13_base"
git -C "$s13_C" checkout -q clean && printf 'A page.\n' > "$s13_C/docs/clean-page.md" \
    && git -C "$s13_C" add docs/clean-page.md && git -C "$s13_C" commit -q -m "Add a clean page"
s13_clean="$(git -C "$s13_C" rev-parse HEAD)"
git -C "$s13_K" fetch -q "$s13_C" main clean 2>/dev/null
s13_origin="$(git -C "$s13_K" rev-parse origin/main)"

# s13_kitpush <remote> <url> <local sha> <remote sha> [VAR=value...]: the kit's pre-push.
s13_kitpush() {
    local r="$1" u="$2" l="$3" rs="$4"; shift 4
    printf 'refs/heads/main %s refs/heads/main %s\n' "$l" "$rs" > "$s13_S/push-stdin"
    s13_run env AW_BANNED_WORDS_FILE="$s13_words" "$@" bash -c 'cd "$1" && exec "$2" githooks/pre-push "$3" "$4" < "$5"' \
        _ "$s13_K" "$st_bash" "$r" "$u" "$s13_S/push-stdin"
}
s13_kitpush origin "$KITSRC" "$s13_addrm" "$s13_origin"
s13_expect "13 kit pre-push: a file added in one commit and removed in the next is still refused" 1 "notes/plan.md"
s13_kitpush origin "$KITSRC" "$s13_addrm" 1234567890abcdef1234567890abcdef12345678
s13_expect "13 kit pre-push: a remote sha this repository lacks still walks every commit" 1 "notes/plan.md"
s13_kitpush origin "$KITSRC" "$s13_attr" "$s13_addrm"
s13_expect "13 kit pre-push: an attribution trailer in a pushed commit is refused" 1 "attribution trailer"

# The kit's own context has no visibility rule: a public GitHub remote is fine, and gh is never asked.
s13_gh="$s13_S/gh-stub"
mkdir -p "$s13_gh"
cat > "$s13_gh/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "${S13_GH_CALLS:-/dev/null}"
case "${S13_GH_MODE:-}" in
    PUBLIC|PRIVATE|INTERNAL) echo "$S13_GH_MODE" ;;
    hang) exec sleep 30 ;;
    *) exit 1 ;;
esac
EOF
chmod 755 "$s13_gh/gh"
: > "$s13_S/gh-calls"
s13_kitpush origin "git@github.com:example-owner/kit.git" "$s13_clean" "$s13_origin" \
    AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC S13_GH_CALLS="$s13_S/gh-calls"
s13_expect "13 kit pre-push: the kit's own repository never runs the workspace's public-remote check" 0
empty "13 ... and gh is not asked" "$(cat "$s13_S/gh-calls")"

# A subtree mirror (the closeout plugin's own repository): its tree is rooted at plugins/closeout.
s13_M="$s13_S/mirror"
mkdir -p "$s13_M" && cp -R "$s13_K/plugins/closeout/." "$s13_M/"
git -C "$s13_M" init -q && git -C "$s13_M" symbolic-ref HEAD refs/heads/main \
    && git -C "$s13_M" add -A && git -C "$s13_M" commit -q -m "Closeout mirror"
git -C "$s13_K" fetch -q "$s13_M" main 2>/dev/null
s13_mirror="$(git -C "$s13_K" rev-parse FETCH_HEAD)"
git -C "$s13_K" remote add closeout "$s13_S/closeout-mirror.git"
git -C "$s13_K" remote add closeout-bare "$s13_S/closeout-mirror.git"
git -C "$s13_K" config aw.mirror.closeout.prefix plugins/closeout
s13_kitpush closeout "$s13_S/closeout-mirror.git" "$s13_mirror" 0000000000000000000000000000000000000000
s13_expect "13 kit pre-push: a mirror push with aw.mirror.<remote>.prefix set is allowed" 0
s13_kitpush closeout-bare "$s13_S/closeout-mirror.git" "$s13_mirror" 0000000000000000000000000000000000000000
s13_expect "13 kit pre-push: the same push to a remote with no prefix is refused" 1 "outside the kit's allow-list"
printf 'refs/notes/commits %s refs/notes/commits %s\n' "$s13_clean" 0000000000000000000000000000000000000000 > "$s13_S/push-notes"
s13_run bash -c 'cd "$1" && exec "$2" githooks/pre-push origin "$3" < "$4"' _ "$s13_K" "$st_bash" "$KITSRC" "$s13_S/push-notes"
s13_expect "13 kit pre-push: a notes ref is refused" 1 "a notes ref is not pushed to the kit"

# A contributor's standalone clone of the kit, with no workspace around it: gitconfig.sh takes the kit
# itself as its target, and the kit's checks run without the workspace ones.
s13_run "$st_bash" "$s13_C/lib/setup/gitconfig.sh" --target "$s13_C" --hooks
s13_expect "13 gitconfig.sh sets the hooks in a standalone kit clone" 0 "set . core.hooksPath="
mkdir -p "$s13_C/notes" && printf 'x\n' > "$s13_C/notes/standalone.md"
git -C "$s13_C" add notes/standalone.md
s13_run git -C "$s13_C" commit -q -m "A note"
s13_expect "13 a standalone kit clone refuses a path outside the allow-list" 1 "outside the kit's allow-list"
s13_has "no workspace around this kit checkout" && ok "13 ... and says the workspace checks did not run" \
    || ko "13 ... and says the workspace checks did not run" "$(cat "$s13_out")"

# ---- 13.6 The workspace's pre-commit ---------------------------------------------------------------------

mkdir -p "$s13_W/projects/field-notes"
printf '# Field notes\n\n- **Versioned:** untracked\n- **Sensitivity:** sensitive\n' > "$s13_W/projects/field-notes/README.md"
# s13_wspc <index> [VAR=value...]: the workspace's pre-commit, with that index.
s13_wspc() {
    local ix="$1"; shift
    s13_run env GIT_INDEX_FILE="$ix" "$@" bash -c 'cd "$1" && exec "$2" kit/githooks/pre-commit' _ "$s13_W" "$st_bash"
}
s13_wspc "$(s13_stage "$s13_W" 100644 projects/field-notes/contacts.md "$(s13_file contacts.md 'Priya Shah, 555 0100\n')")"
s13_expect "13 workspace pre-commit: a file in a Sensitivity: sensitive project is refused" 1 "the project is Sensitivity: sensitive"
s13_has "/projects:adopt field-notes untracked" && ok "13 ... naming the command that keeps it out" \
    || ko "13 ... naming the command that keeps it out" "$(cat "$s13_out")"
s13_wspc "$(s13_stage "$s13_W" 160000 projects/field-notes/code "$s13_base")"
s13_expect "13 workspace pre-commit: a gitlink in a sensitive project is allowed (its own repository)" 0
s13_wspc "$(s13_stage "$s13_W" 100644 projects/$s13_slug/notes.md "$s13_S/clean.md")"
s13_expect "13 workspace pre-commit: a file in a normal project is allowed" 0
head -c 1200000 /dev/zero | tr '\0' 'a' > "$s13_S/big.txt"
s13_wspc "$(s13_stage "$s13_W" 100644 docs/big.txt "$s13_S/big.txt")" AW_MAX_FILE_MB=1
s13_expect "13 workspace pre-commit: a file over AW_MAX_FILE_MB is refused" 1 "over the 1 MB limit"
s13_wspc "$(s13_stage "$s13_W" 100644 docs/big.txt "$s13_S/big.txt")" AW_MAX_FILE_MB=0
s13_expect "13 workspace pre-commit: AW_MAX_FILE_MB=0 turns the size check off, and says so" 0 "the size check did not run"
s13_wspc "$(s13_stage "$s13_W" 100644 docs/old-notes.bak "$s13_S/clean.md")"
s13_expect "13 workspace pre-commit: a force-added ignored file is allowed, with a warning" 0 "added with git add -f"
mkdir -p "$s13_W/projects/loose-ends"
s13_wspc "$(s13_stage "$s13_W" 100644 projects/loose-ends/list.md "$s13_S/clean.md")"
s13_expect "13 workspace pre-commit: a file in a project folder with no README.md or CLAUDE.md is refused (fail closed)" 1 "no README.md or CLAUDE.md to say whether it is sensitive"
printf '# Loose ends\n\n- **Sensitivity:** normal\n' > "$s13_W/projects/loose-ends/CLAUDE.md"
s13_wspc "$(s13_stage "$s13_W" 100644 projects/loose-ends/list.md "$s13_S/clean.md")"
s13_expect "13 workspace pre-commit: ... and allowed once its CLAUDE.md says Sensitivity: normal" 0
# A sensitive project untracked and ignored, with the untrack not committed yet: a file still in the
# index, identical to HEAD, is refused whatever else is staged.
mkdir -p "$s13_W/projects/intake-study"
printf '# Intake study\n\n- **Sensitivity:** normal\n' > "$s13_W/projects/intake-study/README.md"
printf 'Answers.\n' > "$s13_W/projects/intake-study/answers.md"
git -C "$s13_W" add projects/intake-study && git -C "$s13_W" commit -q -m "Intake study"
cp "$s13_W/.gitignore" "$s13_S/gitignore.orig"
printf '/projects/intake-study\n' >> "$s13_W/.gitignore"
printf '# Intake study\n\n- **Versioned:** untracked\n- **Sensitivity:** sensitive\n' > "$s13_W/projects/intake-study/README.md"
s13_wspc "$(s13_stage "$s13_W" 100644 docs/other.md "$s13_S/clean.md")"
s13_expect "13 workspace pre-commit: a file left in the index under an ignored sensitive project is refused, though unchanged from HEAD" 1 \
    "projects/intake-study/answers.md — still in the index"
s13_ix="$(s13_stage "$s13_W" 100644 docs/other.md "$s13_S/clean.md")"
GIT_INDEX_FILE="$s13_ix" git -C "$s13_W" rm -r -q --cached projects/intake-study
s13_wspc "$s13_ix"
s13_expect "13 workspace pre-commit: ... and allowed once the untrack is staged" 0
cp "$s13_S/gitignore.orig" "$s13_W/.gitignore"
printf '# Intake study\n\n- **Sensitivity:** normal\n' > "$s13_W/projects/intake-study/README.md"

# A project whose README said sensitive in HEAD and now says normal: the downgrade has to land on its
# own first. The fixture's history is made before its hooks are set, so it has nothing to step round.
s13_W2="$s13_S/ws-head"
mkdir -p "$s13_W2" && git -C "$s13_W2" init -q && git -C "$s13_W2" symbolic-ref HEAD refs/heads/main
git -C "$s13_W2" -c protocol.file.allow=always submodule add -q -b main "$KITSRC" kit >/dev/null 2>&1
mkdir -p "$s13_W2/projects/vendor-review"
printf '# Vendor review\n\n- **Sensitivity:** sensitive\n' > "$s13_W2/projects/vendor-review/README.md"
git -C "$s13_W2" add -A && git -C "$s13_W2" commit -q -m "Before the hooks"
"$st_bash" "$s13_W2/kit/lib/setup/gitconfig.sh" --target "$s13_W2" --hooks >/dev/null 2>&1
printf '# Vendor review\n\n- **Sensitivity:** normal\n' > "$s13_W2/projects/vendor-review/README.md"
s13_run env GIT_INDEX_FILE="$(s13_stage "$s13_W2" 100644 projects/vendor-review/quotes.md "$s13_S/clean.md")" \
    bash -c 'cd "$1" && exec "$2" kit/githooks/pre-commit' _ "$s13_W2" "$st_bash"
s13_expect "13 workspace pre-commit: HEAD saying sensitive still refuses while the working tree says normal" 1 "Sensitivity: sensitive"

# The user's hook in the repository's own hooks folder runs after the kit's (no aw.chainHooksPath).
mkdir -p "$s13_W2/.git/hooks"
printf '#!/bin/sh\necho ran > "%s"\n' "$s13_S/default-chain.marker" > "$s13_W2/.git/hooks/pre-commit"
chmod 755 "$s13_W2/.git/hooks/pre-commit"
printf 'x\n' > "$s13_W2/root-note.md"
git -C "$s13_W2" add root-note.md
s13_run git -C "$s13_W2" commit -q -m "A root note"
s13_expect "13 chaining: a real commit runs the user's pre-commit from the repository's own hooks folder" 0
check "13 ... which left its marker" test -f "$s13_S/default-chain.marker"
printf '#!/bin/sh\necho "the user hook says no" >&2\nexit 1\n' > "$s13_W2/.git/hooks/pre-commit"
printf 'y\n' > "$s13_W2/root-note-2.md"
git -C "$s13_W2" add root-note-2.md
s13_run git -C "$s13_W2" commit -q -m "A second root note"
s13_expect "13 chaining: a real commit is refused when the user's pre-commit fails" 1 "the user hook says no"
printf '#!/bin/sh\nexit 0\n' > "$s13_W2/.git/hooks/pre-commit"

# pre-merge-commit runs the pre-commit checks under its own name.
s13_run env GIT_INDEX_FILE="$(s13_stage "$s13_W" 100644 projects/field-notes/merged.md "$s13_S/clean.md")" \
    bash -c 'cd "$1" && exec "$2" kit/githooks/pre-merge-commit' _ "$s13_W" "$st_bash"
s13_expect "13 workspace pre-merge-commit: the pre-commit checks run for a merge too" 1 "aw pre-merge-commit: refused 1 item(s)"

# ---- 13.7 The workspace's pre-push -------------------------------------------------------------------------

printf 'refs/heads/main %s refs/heads/main %s\n' "$s13_base" 0000000000000000000000000000000000000000 > "$s13_S/ws-stdin"
# s13_wspush <dir> <remote> <url> [VAR=value...]: the pre-push of the repository at dir, with stdin.
s13_wspush() {
    local d="$1" r="$2" u="$3"; shift 3
    s13_run env "$@" bash -c 'cd "$1" && exec "$2" "$3" "$4" "$5" < "$6"' _ "$d" "$st_bash" "$s13_K/githooks/pre-push" "$r" "$u" "$s13_S/ws-stdin"
}
s13_pub="git@github.com:example-owner/open-ws.git"
s13_wspush "$s13_W" origin "$s13_pub" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC
s13_expect "13 workspace pre-push: GitHub saying PUBLIC is refused" 1 "is public on GitHub"
s13_wspush "$s13_W" origin "$s13_pub" AW_GH="$s13_gh/gh" S13_GH_MODE=PRIVATE
s13_expect "13 workspace pre-push: GitHub saying PRIVATE is allowed" 0
s13_wspush "$s13_W" origin "$s13_pub" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC AW_ALLOW_PUBLIC=github.com/example-owner/open-ws
s13_expect "13 workspace pre-push: AW_ALLOW_PUBLIC=<normalised remote> pushes once, and says so" 0 "on purpose"
s13_wspush "$s13_W" origin "$s13_pub" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC AW_ALLOW_PUBLIC=1
s13_expect "13 workspace pre-push: AW_ALLOW_PUBLIC=1 is not a remote, and changes nothing" 1 "is public on GitHub"
s13_wspush "$s13_W" origin "https://github.com/example-owner/field-ws.git" AW_GH="$s13_S/no-such/gh"
s13_expect "13 workspace pre-push: with no gh, a remote listed as a Private remote (confirmed via gh) is allowed" 0
s13_wspush "$s13_W" origin "$s13_pub" AW_GH="$s13_S/no-such/gh"
s13_expect "13 workspace pre-push: with no gh, a remote not listed is refused" 1 "is not confirmed private"
s13_wspush "$s13_W" origin "https://github.com/example-owner/field-ws.git" AW_GH="$s13_gh/gh" S13_GH_MODE=fail
s13_expect "13 workspace pre-push: a gh that fails falls through to the list" 0
s13_t0=$SECONDS
s13_wspush "$s13_W" origin "https://github.com/example-owner/field-ws.git" AW_GH="$s13_gh/gh" S13_GH_MODE=hang AW_GH_TIMEOUT=1
s13_t=$((SECONDS - s13_t0))
s13_expect "13 workspace pre-push: a gh that hangs is stopped by the watchdog and the list decides" 0
[[ $s13_t -le 8 ]] && ok "13 ... within the watchdog's time (${s13_t}s)" || ko "13 ... within the watchdog's time" "${s13_t}s"

# A Private remote written by a person is trusted only with someone at a terminal.
s13_notty() { python3 -c 'import os, sys
pid = os.fork()
if pid == 0:
    os.setsid()
    os.execvp(sys.argv[1], sys.argv[1:])
_, st = os.waitpid(pid, 0)
sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 1)' "$@"; }
s13_run s13_notty env AW_GH="$s13_S/no-such/gh" bash -c 'cd "$1" && exec "$2" "$3" origin "$4" < "$5"' _ \
    "$s13_W" "$st_bash" "$s13_K/githooks/pre-push" "git@github.com:example-owner/person-ws.git" "$s13_S/ws-stdin"
s13_expect "13 workspace pre-push: a Private remote confirmed via person is not trusted with no terminal" 1 "no one is at a terminal"
s13_withtty() { S13_TTY_IN="$s13_S/ws-stdin" S13_TTY_OUT="$s13_out" python3 -c 'import os, pty, sys
try:
    pid, fd = pty.fork()
except OSError:
    sys.exit(97)
if pid == 0:
    i = os.open(os.environ["S13_TTY_IN"], os.O_RDONLY); os.dup2(i, 0)
    o = os.open(os.environ["S13_TTY_OUT"], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644); os.dup2(o, 1); os.dup2(o, 2)
    os.execvp(sys.argv[1], sys.argv[1:])
try:
    while os.read(fd, 1024):
        pass
except OSError:
    pass
_, st = os.waitpid(pid, 0)
sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 1)' "$@"; s13_rc=$?; }
s13_withtty env AW_GH="$s13_S/no-such/gh" bash -c 'cd "$1" && exec "$2" "$3" origin "$4"' _ \
    "$s13_W" "$st_bash" "$s13_K/githooks/pre-push" "git@github.com:example-owner/person-ws.git"
if [[ $s13_rc -eq 97 ]]; then
    skp "13 workspace pre-push: a Private remote confirmed via person is trusted at a terminal — no pseudo-terminal here"
else
    s13_expect "13 workspace pre-push: a Private remote confirmed via person is trusted at a terminal" 0
fi
s13_wspush "$s13_W" backup "$s13_S/backup.git" AW_GH="$s13_S/no-such/gh"
s13_expect "13 workspace pre-push: a local path under TMPDIR is allowed" 0
s13_wspush "$s13_W" backup "/nonexistent-aw-s13/backup.git" AW_GH="$s13_S/no-such/gh"
s13_expect "13 workspace pre-push: a local path outside TMPDIR is refused" 1 "a local path outside the temporary folder"

# ---- 13.8 Chaining ----------------------------------------------------------------------------------------

s13_uh="$s13_S/user-hooks"
mkdir -p "$s13_uh" "$s13_S/user-hooks-empty" "$s13_S/user-hooks-loop"
cat > "$s13_uh/pre-push" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$S13_UH_LOG.args"
cat > "$S13_UH_LOG.stdin"
exit "${S13_UH_RC:-0}"
EOF
chmod 755 "$s13_uh/pre-push"
git -C "$s13_W" config aw.chainHooksPath "$s13_uh"
s13_wspush "$s13_W" backup "$s13_S/backup.git" S13_UH_LOG="$s13_S/uh1" S13_UH_RC=1
s13_expect "13 chaining: the user's hook failing refuses the push" 1
s13_wspush "$s13_W" backup "$s13_S/backup.git" S13_UH_LOG="$s13_S/uh2" S13_UH_RC=0
s13_expect "13 chaining: the kit's checks and the user's hook both passing allows the push" 0
[[ "$(cat "$s13_S/uh2.args" 2>/dev/null)" == "backup"$'\n'"$s13_S/backup.git" ]] \
    && cmp -s "$s13_S/uh2.stdin" "$s13_S/ws-stdin" \
    && ok "13 chaining: the user's hook gets the same arguments and the same stdin" \
    || ko "13 chaining: the user's hook gets the same arguments and the same stdin" "$(cat "$s13_S/uh2.args" 2>&1)"
s13_wspush "$s13_W" backup "/nonexistent-aw-s13/backup.git" S13_UH_LOG="$s13_S/uh3" AW_GH="$s13_S/no-such/gh"
s13_expect "13 chaining: a kit refusal stops before the user's hook" 1
check "13 ... which did not run" test ! -e "$s13_S/uh3.args"
git -C "$s13_W" config aw.chainHooksPath "$s13_S/user-hooks-empty"
s13_wspush "$s13_W" backup "$s13_S/backup.git"
s13_expect "13 chaining: with no user hook, only the kit's checks run" 0
ln -s "$s13_K/githooks/pre-push" "$s13_S/user-hooks-loop/pre-push"
git -C "$s13_W" config aw.chainHooksPath "$s13_S/user-hooks-loop"
s13_wspush "$s13_W" backup "$s13_S/backup.git"
s13_expect "13 chaining: a user hook that is a symlink to the kit's own hook is not run again" 0
git -C "$s13_W" config aw.chainHooksPath "$s13_S/user-hooks-empty"

# ---- 13.9 Project repositories -----------------------------------------------------------------------------

s13_P="$s13_W/projects/site-build"
mkdir -p "$s13_P" && git -C "$s13_P" init -q && git -C "$s13_P" symbolic-ref HEAD refs/heads/main
printf '# Site build\n\n- **Versioned:** own-repo\n- **Sensitivity:** normal\n' > "$s13_P/README.md"
git -C "$s13_P" add README.md && git -C "$s13_P" commit -q -m "Start"
s13_run "$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --repo projects/site-build
s13_expect "13 gitconfig.sh --repo sets the hooks in one project repository" 0 "set projects/site-build core.hooksPath="
s13_wspush "$s13_P" origin "git@github.com:example-owner/field-ws.git" AW_GH="$s13_S/no-such/gh"
s13_expect "13 project pre-push: a remote confirmed private is allowed" 0
s13_wspush "$s13_P" origin "git@github.com:example-owner/site.git" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC
s13_expect "13 project pre-push: a listed Public remote is allowed for a normal project" 0
s13_wspush "$s13_P" origin "git@github.com:example-owner/other.git" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC
s13_expect "13 project pre-push: a remote neither confirmed private nor listed is refused" 1 "neither confirmed private nor listed as a Public remote"
printf '# Site build\n\n- **Versioned:** own-repo\n- **Sensitivity:** sensitive\n' > "$s13_P/README.md"
s13_wspush "$s13_P" origin "git@github.com:example-owner/site.git" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC \
    AW_ALLOW_PUBLIC=github.com/example-owner/site
s13_expect "13 project pre-push: a sensitive project is refused a listed Public remote, AW_ALLOW_PUBLIC or not" 1 "Sensitivity: sensitive"
printf '# Site build\n\n- **Versioned:** own-repo\n- **Sensitivity:** normal\n' > "$s13_P/README.md"
# A Public remote belongs to the project folder its line names: another project may not push to it.
s13_P2="$s13_W/projects/other-build"
mkdir -p "$s13_P2" && git -C "$s13_P2" init -q && git -C "$s13_P2" symbolic-ref HEAD refs/heads/main
printf '# Other build\n\n- **Versioned:** own-repo\n- **Sensitivity:** normal\n' > "$s13_P2/README.md"
git -C "$s13_P2" add README.md && git -C "$s13_P2" commit -q -m "Start"
"$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --repo projects/other-build >/dev/null 2>&1
s13_wspush "$s13_P2" origin "git@github.com:example-owner/site.git" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC
s13_expect "13 project pre-push: a Public remote listed for another project folder is refused" 1 "listed as a Public remote for projects/site-build, not for projects/other-build"
sed 's#`projects/site-build/`, the published site#the published site#' "$s13_W/.claude/workspace.md" > "$s13_S/ws-nofolder.md"
cp "$s13_W/.claude/workspace.md" "$s13_S/ws-folder.md"; cp "$s13_S/ws-nofolder.md" "$s13_W/.claude/workspace.md"
s13_wspush "$s13_P" origin "git@github.com:example-owner/site.git" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC
s13_expect "13 project pre-push: a Public remote line that names no project folder allows no project" 1 "names the one project folder"
cp "$s13_S/ws-folder.md" "$s13_W/.claude/workspace.md"
# Sensitivity is read from CLAUDE.md as well as README.md, and a project with neither is not published.
s13_P3="$s13_W/projects/site-build-2"
mkdir -p "$s13_P3" && git -C "$s13_P3" init -q && git -C "$s13_P3" symbolic-ref HEAD refs/heads/main
printf '# Build two\n\n- **Sensitivity:** sensitive\n' > "$s13_P3/CLAUDE.md"
git -C "$s13_P3" add CLAUDE.md && git -C "$s13_P3" commit -q -m "Start"
"$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --repo projects/site-build-2 >/dev/null 2>&1
sed 's#`projects/site-build/`, the published site#`projects/site-build-2/`, the published site#' "$s13_S/ws-folder.md" > "$s13_W/.claude/workspace.md"
s13_wspush "$s13_P3" origin "git@github.com:example-owner/site.git" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC
s13_expect "13 project pre-push: a project whose CLAUDE.md says Sensitivity: sensitive (no README) is refused its Public remote" 1 "Sensitivity: sensitive"
s13_P4="$s13_W/projects/site-build-3"
mkdir -p "$s13_P4" && git -C "$s13_P4" init -q && git -C "$s13_P4" symbolic-ref HEAD refs/heads/main
printf 'Notes.\n' > "$s13_P4/notes.md"
git -C "$s13_P4" add notes.md && git -C "$s13_P4" commit -q -m "Start"
"$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --repo projects/site-build-3 >/dev/null 2>&1
sed 's#`projects/site-build/`, the published site#`projects/site-build-3/`, the published site#' "$s13_S/ws-folder.md" > "$s13_W/.claude/workspace.md"
s13_wspush "$s13_P4" origin "git@github.com:example-owner/site.git" AW_GH="$s13_gh/gh" S13_GH_MODE=PUBLIC
s13_expect "13 project pre-push: a project with no README.md or CLAUDE.md is refused its Public remote" 1 "no README.md or CLAUDE.md"
cp "$s13_S/ws-folder.md" "$s13_W/.claude/workspace.md"

# ---- 13.10 Stubs --------------------------------------------------------------------------------------------

# A clone whose kit was never initialised: the stub cannot reach a kit, so the commit is refused.
s13_D="$s13_S/ws-no-kit"
git clone -q "$s13_W" "$s13_D" 2>/dev/null
s13_gd="$(git -C "$s13_D" rev-parse --absolute-git-dir)"
mkdir -p "$s13_gd/aw-hooks" && cp "$KITSRC/githooks/stub.sh" "$s13_gd/aw-hooks/pre-commit" && chmod 755 "$s13_gd/aw-hooks/pre-commit"
git -C "$s13_D" config core.hooksPath "$s13_gd/aw-hooks"
s13_run git -C "$s13_D" commit -q --allow-empty -m "No kit here"
s13_expect "13 stubs: with the kit not initialised, a commit is refused rather than let through" 1 "the kit's hooks are not reachable"

# A project whose folder moves into _done/ keeps its git directory (git mv leaves it where it is), so
# its stub, found by an absolute path, still runs, and still finds the kit by walking up.
s13_gdir="$s13_S/moved-project.git"
git init -q --separate-git-dir "$s13_gdir" "$s13_W/projects/lab-log"
printf '# Lab log\n' > "$s13_W/projects/lab-log/README.md"
"$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --repo projects/lab-log >/dev/null 2>&1
mkdir -p "$s13_S/moved-hooks"
printf '#!/bin/sh\necho "$PWD" >> "%s"\n' "$s13_S/moved.marker" > "$s13_S/moved-hooks/pre-commit"
chmod 755 "$s13_S/moved-hooks/pre-commit"
git --git-dir="$s13_gdir" config aw.chainHooksPath "$s13_S/moved-hooks"
git -C "$s13_W/projects/lab-log" add README.md && git -C "$s13_W/projects/lab-log" commit -q -m "Start"
mkdir -p "$s13_W/projects/_done/lab-log"
printf 'gitdir: %s\n' "$s13_gdir" > "$s13_W/projects/_done/lab-log/.git"
cp "$s13_W/projects/lab-log/README.md" "$s13_W/projects/_done/lab-log/README.md"
printf 'Closed.\n' >> "$s13_W/projects/_done/lab-log/README.md"
git -C "$s13_W/projects/_done/lab-log" add README.md
s13_run git -C "$s13_W/projects/_done/lab-log" commit -q -m "Closed"
s13_expect "13 stubs: after the project folder moves into _done/, a commit there still goes through the kit's hooks" 0
[[ "$(grep -c . "$s13_S/moved.marker" 2>/dev/null)" == 2 ]] && tail -n 1 "$s13_S/moved.marker" | grep -q '/_done/lab-log$' \
    && ok "13 ... both before and after the move (the chained hook ran each time)" \
    || ko "13 ... both before and after the move (the chained hook ran each time)" "$(cat "$s13_S/moved.marker" 2>&1)"

# ---- 13.11 Failing closed ------------------------------------------------------------------------------------

# A PATH holding git and dirname but no awk.
s13_bin="$s13_S/bin-no-awk"
mkdir -p "$s13_bin"
for s13_t in git dirname; do ln -s "$(command -v "$s13_t")" "$s13_bin/$s13_t"; done
if [[ -x /usr/local/bin/awk || -x /opt/homebrew/bin/awk ]]; then
    skp "13 fail closed: a missing awk — this machine has awk in a folder the hooks add to PATH"
else
    s13_run env PATH="$s13_bin" "$st_bash" -c 'cd "$1" && exec "$2" kit/githooks/pre-commit' _ "$s13_W" "$st_bash"
    s13_expect "13 fail closed: with awk missing from PATH, the hook refuses (could-not-run)" 1 "could-not-run: awk is not on PATH"
fi
mkdir -p "$s13_S/ro-tmp" && chmod 555 "$s13_S/ro-tmp"
s13_run env TMPDIR="$s13_S/ro-tmp" bash -c 'cd "$1" && exec "$2" kit/githooks/pre-commit' _ "$s13_W" "$st_bash"
s13_expect "13 fail closed: when TMPDIR cannot be written, the hook refuses (could-not-run)" 1 "could-not-run"
chmod 755 "$s13_S/ro-tmp"
# A workspace whose kit copy lacks readme.awk.
s13_W3="$s13_S/ws-no-awk"
mkdir -p "$s13_W3/kit" && git -C "$s13_W3" init -q
git -C "$KITSRC" archive HEAD | tar -x -f - --exclude 'plugins/projects/hooks/lib/readme.awk' -C "$s13_W3/kit"
mkdir -p "$s13_W3/projects/one" && printf '# One\n' > "$s13_W3/projects/one/README.md"
s13_run env GIT_INDEX_FILE="$s13_S/index.w3" bash -c 'cd "$1" && git add projects/one/README.md && exec "$2" kit/githooks/pre-commit' _ "$s13_W3" "$st_bash"
s13_expect "13 fail closed: with readme.awk missing from the kit, the workspace pre-commit refuses (could-not-run)" 1 "could-not-run"

# ---- 13.12 gitconfig.sh --------------------------------------------------------------------------------------

s13_run "$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --hooks
s13_expect "13 gitconfig.sh --hooks runs again cleanly" 0
grep -q '^set ' "$s13_out" && ko "13 ... and a second run sets nothing" "$(grep '^set ' "$s13_out")" || ok "13 ... and a second run sets nothing"
s13_run "$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --hooks --check
s13_expect "13 gitconfig.sh --check exits 0 when nothing would change" 0
git -C "$s13_W" config core.hooksPath .hooks-before
s13_run "$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --hooks --check
s13_expect "13 gitconfig.sh --check exits 1 when something would be set" 1 "set . core.hooksPath="
check "13 ... and writes nothing" test "$(git -C "$s13_W" config --get core.hooksPath)" = .hooks-before
s13_run "$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --hooks
check "13 gitconfig.sh keeps the hooks path it replaces as aw.chainHooksPath" \
    test "$(git -C "$s13_W" config --get aw.chainHooksPath)" = .hooks-before
check "13 ... and points core.hooksPath back at the stubs" \
    test "$(git -C "$s13_W" config --get core.hooksPath)" = "$(git -C "$s13_W" rev-parse --absolute-git-dir)/aw-hooks"
git -C "$s13_W" config aw.chainHooksPath "$s13_S/user-hooks-empty"

# Submodules: a project submodule gets update=rebase; an outside one holds submodule.recurse back.
s13_R="$s13_S/sub-src"
mkdir -p "$s13_R" && git -C "$s13_R" init -q && git -C "$s13_R" symbolic-ref HEAD refs/heads/main \
    && printf 'x\n' > "$s13_R/x.md" && git -C "$s13_R" add x.md && git -C "$s13_R" commit -q -m x
git -C "$s13_W" -c protocol.file.allow=always submodule add -q "$s13_R" projects/app >/dev/null 2>&1
git -C "$s13_W" -c protocol.file.allow=always submodule add -q "$s13_R" tasks/store >/dev/null 2>&1
s13_run "$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --submodules
s13_expect "13 gitconfig.sh --submodules sets push.recurseSubmodules=check" 0 "set . push.recurseSubmodules=check"
s13_has "set . submodule.projects/app.update=rebase" && ok "13 ... update=rebase for a project submodule" \
    || ko "13 ... update=rebase for a project submodule" "$(cat "$s13_out")"
s13_has "held submodule.recurse: tasks/store" && ok "13 ... and holds submodule.recurse back for one outside the kit's concern" \
    || ko "13 ... and holds submodule.recurse back for one outside the kit's concern" "$(cat "$s13_out")"
s13_run "$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --submodules --check
s13_expect "13 gitconfig.sh --submodules --check: nothing left to set on a second pass" 0
s13_run "$st_bash" "$s13_K/lib/setup/gitconfig.sh" --target "$s13_W" --hooks
s13_has "set projects/app core.hooksPath=" && ok "13 gitconfig.sh --hooks reaches a project submodule" \
    || ko "13 gitconfig.sh --hooks reaches a project submodule" "$(cat "$s13_out")"
s13_has "tasks/store" && ko "13 ... and leaves an outside submodule alone" "$(cat "$s13_out")" \
    || ok "13 ... and leaves an outside submodule alone"
fi

# ---- 13.13 The agent guard -----------------------------------------------------------------------------------

s13_G="$KITSRC/plugins/workspace/hooks/guard-git.sh"
# s13_guard <command>: deny or allow, as guard-git.sh answers a Bash tool call carrying that command.
s13_guard() {
    local c="$1" out
    c="${c//\\/\\\\}"; c="${c//\"/\\\"}"
    out="$(printf '{"session_id":"t","tool_name":"Bash","tool_input":{"command":"%s","description":"a test"}}' "$c" \
        | env "${@:2}" "$st_bash" "$s13_G")"
    case "$out" in *'"permissionDecision":"deny"'*) echo deny ;; '') echo allow ;; *) echo "odd: $out" ;; esac
}
s13_nv="--no""-verify"
s13_bad=""
for s13_c in "git commit $s13_nv -m x" "git push $s13_nv origin main" "git commit -n -m x" "git commit -nm x" \
    "git -c core.hooksPath=/dev/null commit -m x" \
    "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git push" \
    "git config core.hooksPath /dev/null" "cd kit && git commit $s13_nv -m x"; do
    [[ "$(s13_guard "$s13_c")" == deny ]] || s13_bad+="not denied: $s13_c"$'\n'
done
empty "13 guard-git.sh denies $s13_nv, commit -n, -c core.hooksPath, a GIT_CONFIG_ hooksPath and git config core.hooksPath" "$s13_bad"
s13_bad=""
for s13_c in "git commit -m \"a plain message\"" "git push origin main" "git status" "git log -n 3" \
    "git push -n origin main" "git config --get core.hooksPath" "ls -la"; do
    [[ "$(s13_guard "$s13_c")" == allow ]] || s13_bad+="not allowed: $s13_c"$'\n'
done
empty "13 guard-git.sh allows plain commands, and reading core.hooksPath" "$s13_bad"
[[ "$(s13_guard "git commit $s13_nv -m x" AW_GIT_GUARD_DISABLED=1)" == allow ]] \
    && ok "13 guard-git.sh is silent with AW_GIT_GUARD_DISABLED=1" || ko "13 guard-git.sh is silent with AW_GIT_GUARD_DISABLED=1"
s13_o="$(printf 'not json at all' | "$st_bash" "$s13_G"; echo "rc=$?")"
[[ "$s13_o" == "rc=0" ]] && ok "13 guard-git.sh is silent on input it cannot read" || ko "13 guard-git.sh is silent on input it cannot read" "$s13_o"

fi
