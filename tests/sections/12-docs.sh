# shellcheck shell=bash
# KIT and the check helpers come from tests/run.sh, which sources this file (SC2154); a check ends in ok
# or ko, never both (SC2015); backticks in single quotes are the Markdown being looked for (SC2016).
# shellcheck disable=SC2154,SC2015,SC2016
# Section 12: the docs. Every command has a page in docs/commands/, every hook script a page in
# docs/hooks/, and each page, docs/setup.md included, has the same four sections in the same order.
# Every command also has a row in the README that links its page. It reads the kit's own files only,
# so it needs no fixture. Everything here is prefixed s12_, since the sections share one shell.
#
# Page names follow the skills' rule for commands: <plugin>-<command>, or the bare name when the two are
# the same (closeout). A plugin's hook script is <plugin>-<script>, or the bare script name when it
# already starts with its plugin's name (closeout-capture); a git hook is its own name (pre-push).

echo
echo "12 · The docs: a page per command and hook, the four sections, and a README row per command"

# The four sections every page has, exactly and in this order.
s12_shape="What it does|When to reach for it|Common questions|It's working if"

# s12_h2 <file>: the file's H2 headings joined with |, leaving out fenced code blocks.
s12_h2() {
    awk '/^```/ { fence = !fence; next } !fence && /^## / { sub(/^## /, ""); sub(/[ \t]+$/, ""); print }' "$1" \
        | paste -sd'|' -
}
# s12_page <page> <source>: a line of detail for each way the page falls short. It runs in a command
# substitution, so the loops, not this function, keep the list of expected pages (s12_expected).
s12_expected=""
s12_page() {
    local page="$1" src="$2" n h
    if [[ ! -f "$page" ]]; then printf '%s: no page for %s\n' "${page#"$KIT"/}" "$src"; return; fi
    h="$(s12_h2 "$page")"
    [[ "$h" == "$s12_shape" ]] || printf '%s: sections are "%s"\n' "${page#"$KIT"/}" "$h"
    n="$(awk 'END { print NR }' "$page")"
    [[ $n -ge 25 && $n -le 70 ]] || printf '%s: %s lines, outside 25 to 70\n' "${page#"$KIT"/}" "$n"
    grep -qF -- "$src" "$page" || printf '%s: does not name its source, %s\n' "${page#"$KIT"/}" "$src"
}

# --- Commands --------------------------------------------------------------------------------------
s12_bad="" s12_rows="" s12_count=0
shopt -s nullglob
for s12_f in "$KIT"/plugins/*/commands/*.md; do
    s12_rel="${s12_f#"$KIT"/}"
    s12_p="${s12_rel#plugins/}"; s12_p="${s12_p%%/*}"
    s12_c="${s12_f##*/}"; s12_c="${s12_c%.md}"
    s12_name="$s12_p-$s12_c"; [[ "$s12_p" == "$s12_c" ]] && s12_name="$s12_c"
    s12_expected+=" docs/commands/$s12_name.md "
    s12_bad+="$(s12_page "$KIT/docs/commands/$s12_name.md" "$s12_rel")"$'\n'
    grep -qE "^\|.*docs/commands/$s12_name\.md" "$KIT/README.md" \
        || s12_rows+="no README row links docs/commands/$s12_name.md"$'\n'
    s12_count=$((s12_count + 1))
done
[[ $s12_count -gt 0 ]] && ok "12 the kit has commands to document ($s12_count)" || ko "12 the kit has commands to document" "none under plugins/*/commands/"
empty "12 every command has docs/commands/<name>.md, with the four sections in order, 25 to 70 lines, naming its source" \
    "$(printf '%s' "$s12_bad" | sed '/^$/d')"
empty "12 every command has a row in the README that links its page" "$s12_rows"

# --- Hooks -----------------------------------------------------------------------------------------
s12_bad="" s12_count=0
for s12_f in "$KIT"/plugins/*/hooks/*.sh "$KIT"/plugins/*/hooks/*.tsx; do
    [[ "$s12_f" == *.test.tsx ]] && continue
    s12_rel="${s12_f#"$KIT"/}"
    s12_p="${s12_rel#plugins/}"; s12_p="${s12_p%%/*}"
    s12_b="${s12_f##*/}"; s12_b="${s12_b%.sh}"; s12_b="${s12_b%.tsx}"
    case "$s12_b" in "$s12_p"-*) s12_name="$s12_b" ;; *) s12_name="$s12_p-$s12_b" ;; esac
    s12_expected+=" docs/hooks/$s12_name.md "
    s12_bad+="$(s12_page "$KIT/docs/hooks/$s12_name.md" "$s12_rel")"$'\n'
    s12_count=$((s12_count + 1))
done
for s12_f in "$KIT"/githooks/pre-* "$KIT"/githooks/commit-msg; do
    [[ -f "$s12_f" ]] || continue
    s12_rel="${s12_f#"$KIT"/}"
    s12_expected+=" docs/hooks/${s12_f##*/}.md "
    s12_bad+="$(s12_page "$KIT/docs/hooks/${s12_f##*/}.md" "$s12_rel")"$'\n'
    s12_count=$((s12_count + 1))
done
[[ $s12_count -gt 0 ]] && ok "12 the kit has hooks to document ($s12_count)" || ko "12 the kit has hooks to document" "no hook scripts found"
empty "12 every hook script has docs/hooks/<name>.md, with the four sections in order, 25 to 70 lines, naming its source" \
    "$(printf '%s' "$s12_bad" | sed '/^$/d')"

# --- setup.sh --------------------------------------------------------------------------------------
empty "12 docs/setup.md has the four sections in order, 25 to 70 lines, and names setup.sh" \
    "$(s12_page "$KIT/docs/setup.md" "setup.sh")"
s12_bad=""
for s12_m in new update --developer link hooks skills cowork migrate; do
    grep -qF -- "kit/setup.sh $s12_m" "$KIT/docs/setup.md" || s12_bad+="docs/setup.md does not name kit/setup.sh $s12_m"$'\n'
done
empty "12 docs/setup.md names every mode setup.sh dispatches" "$s12_bad"

# --- No page without a subject ---------------------------------------------------------------------
s12_bad=""
for s12_f in "$KIT"/docs/commands/*.md "$KIT"/docs/hooks/*.md; do
    case "$s12_expected" in *" ${s12_f#"$KIT"/} "*) ;; *) s12_bad+="${s12_f#"$KIT"/}: no command or hook of that name"$'\n' ;; esac
done
shopt -u nullglob
empty "12 every page in docs/commands/ and docs/hooks/ belongs to a command or hook that exists" "$s12_bad"

# --- The check itself ------------------------------------------------------------------------------
# A probe page with the sections out of order, and one with a heading inside a code block, prove the
# shape check reads headings as a person would.
s12_probe="$SCRATCH/s12-probe.md"
printf '# p\n\n## What it does\n\n```\n## Not a heading\n```\n\n## Common questions\n\n## When to reach for it\n\n## It'"'"'s working if\n' > "$s12_probe"
[[ "$(s12_h2 "$s12_probe")" == "What it does|Common questions|When to reach for it|It's working if" ]] \
    && ok "12 the shape check skips fenced code and sees sections out of order" \
    || ko "12 the shape check skips fenced code and sees sections out of order" "$(s12_h2 "$s12_probe")"

# The footer of CLAUDE.kit.md is the version an agent reads in every session, so it has to move with
# the CHANGELOG; a release that forgets it shows the old version to every workspace.
s12_v="$(awk '/^## v[0-9]/ { v = $2; sub(/^v/, "", v); print v; exit }' "$KIT/CHANGELOG.md")"
s12_f="$(awk '/^\*Kit [0-9]/ { f = $2; sub(/\*$/, "", f) } END { print f }' "$KIT/CLAUDE.kit.md")"
empty "12 CLAUDE.kit.md ends naming the CHANGELOG's latest version" \
    "$([[ "$s12_f" == "$s12_v" ]] || printf 'footer %s, CHANGELOG %s\n' "${s12_f:-none}" "$s12_v")"

# --- Start here: the README's Quick start, its Part 2 tree and its welcome -------------------------
# The Quick start reaches an area, the weekly hygiene and Cowork as well as a project and closeout, and
# the Part 2 tree is drawn from the workspace map: the kit as kit/, areas in ongoing/, no templates/ at
# the workspace root.
s12_qs="$(awk '/^## Quick start$/ { f = 1; next } f && /^## / { exit } f' "$KIT/README.md")"
s12_tree="$(awk '/^## Part 2 /{ p = 1 } p && /^```$/ { if (f) exit; f = 1; next } f' "$KIT/README.md")"
s12_bad=""
for s12_w in '/workspace:quick-start' '/projects:new' '/ongoing:new' '/closeout' '/workspace:hygiene' 'kit/setup.sh cowork'; do
    grep -qF -- "$s12_w" <<<"$s12_qs" || s12_bad+="the Quick start does not reach $s12_w"$'\n'
done
for s12_w in '  kit/ ' '  ongoing/' '  projects/' '  skills/ ' '  audits/ ' '    templates/ '; do
    grep -qF -- "$s12_w" <<<"$s12_tree" || s12_bad+="the Part 2 tree has no '$s12_w'"$'\n'
done
grep -qE '^  templates/' <<<"$s12_tree" && s12_bad+="the Part 2 tree puts templates/ at the workspace root"$'\n'
grep -qF 'read, check and correct' "$KIT/README.md" || s12_bad+="the welcome does not say the files are there to read, check and correct"$'\n'
empty "12 README: the Quick start reaches an area, hygiene and Cowork; Part 2 is drawn from the workspace map" "$s12_bad"

# --- What the kit is for: the README's two purposes, the principles and the audit ------------------
s12_bad=""
s12_wf="$(awk '/^## What the kit is for$/ { f = 1; next } f && /^## / { exit } f' "$KIT/README.md")"
for s12_w in '**Common ground between you and the assistant.**' '**What the assistant cannot find for itself.**' \
    'docs/principles.md' 'docs/purpose-audit.md' 'cannot learn what only your team knows'; do
    grep -qF -- "$s12_w" <<<"$s12_wf" || s12_bad+="What the kit is for: no '$s12_w'"$'\n'
done
# Every principle names the file that carries it, and every path it names is in the kit.
s12_np="$(grep -cE '^\*\*[0-9]+\. ' "$KIT/docs/principles.md")"
[[ "$s12_np" -ge 8 && "$(grep -c '^\*In the kit:\*' "$KIT/docs/principles.md")" == "$s12_np" ]] \
    || s12_bad+="principles.md: $s12_np principles, not each with an 'In the kit:' line"$'\n'
while IFS= read -r s12_p; do
    [[ -e "$KIT/$s12_p" ]] || s12_bad+="principles.md names $s12_p, which is not in the kit"$'\n'
done < <(grep -oE '`(plugins|templates|docs|rituals|pilot|scripts)/[A-Za-z0-9_./-]+`' "$KIT/docs/principles.md" | tr -d '`' | sort -u)
# The audit has a row for every command, hook script and template, and each verdict is one of the five.
s12_au="$KIT/docs/purpose-audit.md"
for s12_c in "$KIT"/plugins/*/commands/*.md; do
    s12_n="$(basename "$(dirname "$(dirname "$s12_c")")"):$(basename "$s12_c" .md)"
    s12_n="${s12_n/closeout:closeout/closeout}"
    grep -qF "/$s12_n" "$s12_au" || s12_bad+="purpose-audit.md: no row for /$s12_n"$'\n'
done
for s12_t in "$KIT"/templates/*.md; do
    grep -qF "templates/$(basename "$s12_t")" "$s12_au" || s12_bad+="purpose-audit.md: no row for templates/$(basename "$s12_t")"$'\n'
done
s12_v="$(awk -F '|' '/^\| / && $3 !~ /Serves|---/ { v = $3; gsub(/^ +| +$/, "", v); print v }' "$s12_au" | sort -u | grep -vxE 'Both|1|2|Rail|Neither, (fold in|retire)')"
[[ -z "$s12_v" ]] || s12_bad+="purpose-audit.md: verdicts outside the five: $s12_v"$'\n'
empty "12 what the kit is for: the README's two purposes, principles that each name a kit file, and an audit row for every command and template" "$s12_bad"
