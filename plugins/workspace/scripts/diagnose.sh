#!/usr/bin/env bash
# diagnose.sh [--target <workspace>] [--allow-names] [--out <file>]: a fault report for the kit, scrubbed
# so it can be pasted into a public GitHub issue. Run from the workspace root (or --target). It prints the
# report; with --out it also writes it there. It sends nothing anywhere.
#
# What it gathers: the kit's version and commit; each kit plugin's version, and where Claude Code loads
# it from (the folder it is read from, else its cache copy); Claude Code's install records (how many, duplicates, records for folders that no longer
# exist); each kit hook's events and whether its session-start hook runs cleanly here (status and the
# length of what it prints, never the text); the state check in its quick form, keys whose values are
# fixed words or numbers only; the last failing test section, when this machine ran the suite; and the
# versions of the OS, bash, git, jq and Claude Code.
#
# The scrub, applied to every line: the home folder becomes ~, the workspace <workspace>, the kit <kit>,
# and any other absolute path <path>; tokens, keys, webhook URLs and long secrets become <secret>; email
# addresses <email>; the person's git name <person>; and every project and area name (folder names
# under the project and area locations, and register row names) <project>, unless --allow-names.
# No workspace file's contents are read into the report.
set -uo pipefail
# A sandbox can refuse git its system config (/etc/gitconfig), and git then fails on every command, which
# would read here as a kit that is not a git checkout; nothing this report reads needs that file.
export GIT_CONFIG_NOSYSTEM=1
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
kit="$(cd "$here/../../.." && pwd -P)"
target="$PWD" allow=0 out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) target="${2:?}"; shift 2 ;;
        --allow-names) allow=1; shift ;;
        --out) out="${2:?}"; shift 2 ;;
        *) echo "usage: diagnose.sh [--target <workspace>] [--allow-names] [--out <file>]" >&2; exit 2 ;;
    esac
done
ws="$(cd "$target" 2>/dev/null && pwd -P)" || { echo "diagnose.sh: no such folder: $target" >&2; exit 2; }
[[ -d "$ws/kit" ]] && kit="$(cd "$ws/kit" && pwd -P)"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
have() { command -v "$1" >/dev/null 2>&1; }

# ---- What the scrub hides ------------------------------------------------------------------------------
names="$(mktemp "${TMPDIR:-/tmp}/diag-names.XXXXXX")"; trap 'rm -f "$names"' EXIT
if [[ $allow -eq 0 ]]; then
    {   for d in "$ws"/projects/*/ "$ws"/projects/_done/*/ "$ws"/projects/_paused/*/ "$ws"/ongoing/*/; do
            [[ -d "$d" ]] && basename "$d"
        done
        # Register rows: the first cell of each table row that links to a folder (a header row links nowhere).
        for r in "$ws/projects/INDEX.md" "$ws/ongoing/INDEX.md"; do
            [[ -f "$r" ]] && awk -F'|' '/^\|/ && /\]\(|`[^`]*\/[^`]*`/ { c = $2; gsub(/\[|\]\([^)]*\)|\*|`/, "", c); gsub(/^[ \t]+|[ \t]+$/, "", c)
                if (c != "") print c }' "$r"
        done
    } | awk 'length($0) >= 3 && $0 !~ /^_/' \
      | grep -viwE '^(active|ready|doing|blocked|paused|done|dormant|archived|yes|no|ok|held|present|private|public|main|none|kit|workspace|projects|ongoing|closeout|scheduler|state|hooks|unknown)$' \
      | sort -u | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2- > "$names"
fi
person="$(git -C "$ws" config user.name 2>/dev/null)"
scrub() {
    PERSON="$person" HOMEP="$HOME" WSP="$ws" KITP="$kit" NAMES="$names" python3 -c '
import os, re, sys
home, ws, kit, person = os.environ["HOMEP"], os.environ["WSP"], os.environ["KITP"], os.environ["PERSON"]
names = [n for n in open(os.environ["NAMES"], encoding="utf-8").read().split("\n") if n]
secret = re.compile(r"(sk-ant-[A-Za-z0-9_-]+|sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
                    r"|xox[abposr]-[A-Za-z0-9-]+|AKIA[0-9A-Z]{16}|https?://hooks\.slack\.com/\S+|https?://discord(app)?\.com/api/webhooks/\S+"
                    r"|https?://[^/\s]*webhook[^\s]*|Bearer\s+\S+|(?<![A-Za-z0-9/.])(?=[A-Za-z0-9+_-]*[0-9])(?=[A-Za-z0-9+_-]*[A-Za-z])[A-Za-z0-9+_-]{32,}(?![A-Za-z0-9/]))")
email = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+")
path = re.compile(r"(?<![\w<~])/(?:Users|home|private|var|tmp|Volumes|opt|mnt|root|srv|etc)/[^\s:;,)\]\x27\"]*")
for line in sys.stdin:
    line = secret.sub("<secret>", line)
    line = email.sub("<email>", line)
    for p, tag in ((kit, "<kit>"), (ws, "<workspace>"), (home, "~")):
        if p and p != "/":
            line = line.replace(p, tag)
    line = path.sub("<path>", line)
    if person:
        line = re.sub(re.escape(person), "<person>", line, flags=re.I)
    # Names are looked for in what follows the first ": " of a list item (the values), never in the
    # headings and labels of the report, which are the words of the kit.
    head, sep, rest = line.partition(": ") if line.startswith("- ") else (line, "", "")
    for n in names:
        rest = re.sub(r"(?<![A-Za-z0-9])" + re.escape(n) + r"(?![A-Za-z0-9])", "<project>", rest, flags=re.I)
    sys.stdout.write(head + sep + rest)
'
}

# ---- The report ----------------------------------------------------------------------------------------
report() {
    echo "# Fault report for the agentic workspace kit"
    echo
    echo "Generated $(date '+%Y-%m-%d %H:%M %z') by kit/plugins/workspace/scripts/diagnose.sh. Scrubbed: paths, names, secrets."
    echo
    echo "## Versions"
    echo
    echo "- Kit: $(awk '/^## v[0-9]/ { print $2; exit }' "$kit/CHANGELOG.md" 2>/dev/null || echo unknown) ($(tail -n 1 "$kit/CLAUDE.kit.md" 2>/dev/null | tr -d '*'))"
    # Where git fails, its own first line of error is the report, rather than a guess at the cause.
    kc="$(git -C "$kit" rev-parse --short HEAD 2>&1)" || kc="no commit read (${kc%%$'\n'*})"
    echo "- Kit commit: $kc, branch $(git -C "$kit" symbolic-ref -q --short HEAD 2>/dev/null || echo detached), $(git -C "$kit" status --porcelain 2>/dev/null | grep -c . | tr -d ' ') changed files"
    gv="$(git --version 2>&1)"
    echo "- OS: $(uname -sr 2>/dev/null); bash ${BASH_VERSION%%(*}; ${gv%%$'\n'*}; jq $(jq --version 2>/dev/null | sed 's/^jq-//')"
    cv="not on this machine"; have claude && cv="$(claude --version 2>/dev/null)"; echo "- Claude Code: ${cv%%$'\n'*}"
    echo
    echo "## Kit plugins"
    echo
    list=""; have claude && list="$(cd "$ws" && claude plugin list --json 2>/dev/null)"
    for pj in "$kit"/plugins/*/.claude-plugin/plugin.json; do
        n="$(jq -r .name "$pj" 2>/dev/null)"; v="$(jq -r .version "$pj" 2>/dev/null)"
        loads="not read (no claude command here)"
        if [[ -n "$list" ]]; then
            loads="$(jq -r --arg n "$n" --arg kit "$kit" --arg cache "$cfg/plugins/cache/" '[.[] | select((.id | split("@")[0]) == $n)
                | (.readFromFolder // .installPath // .path // "") as $p
                | "\(.id) \(.scope // "?") \(if .enabled then "enabled" else "disabled" end), recorded \(.version // "?"), loads " +
                  (if $p == "" then "from the account" elif ($p | startswith($kit)) then "from this kit checkout (\(.folderVersion // "?"))"
                   elif ($p | startswith($cache)) then "from the plugin cache (\($p | split("/") | last))" else "from another folder" end)]
                | if length == 0 then "not installed" else join("; ") end' <<<"$list" 2>/dev/null)"
        fi
        echo "- $n $v: $loads"
    done
    echo
    echo "## Install records"
    echo
    rec="$cfg/plugins/installed_plugins.json"
    if [[ -f "$rec" ]] && have jq; then
        echo "- Records: $(jq '[.plugins[][]] | length' "$rec"), for $(jq '.plugins | length' "$rec") plugins"
        jq -r '.plugins | to_entries[] | select(.key | test("@agentic-workspace$")) | "- \(.key): \(.value | length) (\(.value | map(.scope) | group_by(.) | map("\(.[0]) \(length)") | join(", ")))"' "$rec"
        gone=0; while IFS= read -r p; do [[ -n "$p" && ! -e "$p" ]] && gone=$((gone + 1)); done < <(jq -r '.plugins[][] | .projectPath // empty' "$rec")
        echo "- Records for folders that no longer exist: $gone$([[ $gone -gt 0 ]] && echo " (bash kit/plugins/workspace/scripts/prune-plugin-records.sh counts and removes them)")"
    else
        echo "- No install records file here"
    fi
    echo
    echo "## Hooks"
    echo
    for hj in "$kit"/plugins/*/hooks/hooks.json; do
        p="$(basename "$(dirname "$(dirname "$hj")")")"
        echo "- $p: $(jq -r '.hooks | keys | join(", ")' "$hj" 2>/dev/null)"
    done
    for h in projects/hooks/session-start.sh workspace/hooks/session-start.sh closeout/hooks/closeout-review.sh; do
        [[ -f "$kit/plugins/$h" ]] || continue
        o="$(printf '{"session_id":"diagnose","source":"startup","cwd":"%s"}' "$ws" \
            | env -u PAIR_ROLE -u PAIR_MAILBOX PROJECTS_HOOK_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/diag-hook.XXXXXX")" \
                CLAUDE_PLUGIN_ROOT="$kit/plugins/${h%%/*}" CLAUDE_PROJECT_DIR="$ws" bash "$kit/plugins/$h" 2>/dev/null)"; rc=$?
        echo "- ${h%%/*} session start: exit $rc, $(printf '%s' "$o" | wc -c | tr -d ' ') characters printed"
    done
    echo
    echo "## State check (quick)"
    echo
    # Only keys whose values are fixed words or numbers; anything that names a path or a project stays out.
    # The quick form drops three keys a fault in quick-start turns on, so they come from the full check:
    # the mode, whether this person's profile was found, and the people folder (a folder the conventions
    # name, read by the scrub like any value). The profile's own path never comes.
    { bash "$kit/plugins/workspace/scripts/state.sh" --quick --target "$ws" 2>/dev/null
      bash "$kit/plugins/workspace/scripts/state.sh" --target "$ws" 2>/dev/null | grep -E '^(mode|person_profile|people_dir)='
    } | grep -vE '^(submodule\.|resource\.|external_paths=|origin=|kit_path=|target=)' \
        | awk -F= '{ k = $1; v = substr($0, length($1) + 2); ok = (k == "people_dir") ? "^[A-Za-z0-9 ._/-]*$" : "^[A-Za-z0-9 ._,:+-]*$"
                     if (v ~ ok && length(v) <= 60) print "- " k ": " v; else print "- " k ": (left out)" }'
    echo
    echo "## Last test run on this machine"
    echo
    t="${TMPDIR:-/tmp}/aw-test-times.tsv"
    if [[ -f "$t" ]]; then
        f="$(awk -F'\t' '$1 == "F" && n < 5 { print "- section " $2 ": " $4; n++ }' "$t")"
        echo "${f:-- no failures in the last run ($(date -r "$t" '+%Y-%m-%d %H:%M' 2>/dev/null || echo 'date unknown'))}"
    else
        echo "- the suite has not run here"
    fi
}

if [[ -n "$out" ]]; then
    report 2>/dev/null | scrub | tee "$out"
else
    report 2>/dev/null | scrub
fi
