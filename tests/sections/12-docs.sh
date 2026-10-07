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
for s12_f in "$KIT"/plugins/*/hooks/*.sh; do
    s12_rel="${s12_f#"$KIT"/}"
    s12_p="${s12_rel#plugins/}"; s12_p="${s12_p%%/*}"
    s12_b="${s12_f##*/}"; s12_b="${s12_b%.sh}"
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
for s12_m in new update --developer link hooks skills migrate; do
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
