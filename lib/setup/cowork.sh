#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/../..
# lib/setup/cowork.sh: kit/setup.sh cowork, which packages the kit's plugins for Cowork.
#
#   kit/setup.sh cowork [PLUGIN...] [--target DIR] [--out DIR] [--from DIR] [--check]
#   bash kit/lib/setup/cowork.sh --target WS [PLUGIN...] [--out DIR] [--from DIR] [--check]
#
# Cowork does not read the marketplace in kit/. It installs a plugin from a .plugin file, a zip of the
# plugin's folder, uploaded in Claude's plugin settings; the commands then appear in Cowork as skills
# (/projects:pair and the rest). This writes one file per plugin, <plugin>-<version>.plugin, into
# .claude/cowork-plugins/ in the workspace (git ignores it), or --out. With no names it packages every
# plugin in the kit; --from points at another plugins folder.
#
# Before packaging, each plugin is checked for what Cowork refuses to install: no name in
# .claude-plugin/plugin.json, a description over 500 characters, or a top-level bin/ folder. A plugin
# that fails is reported and not packaged. --check runs the checks and writes nothing.
#
# The upload is the person's step, and it is repeated after each kit update: the version in the file
# name says which one Cowork has. A plugin whose name matches a skill already on the account (closeout,
# where the Cowork closeout skill is installed) is refused by Cowork, which would replace that skill
# with it; such a plugin is left out, and the account skill stays the way in.
#
# Output is one line per plugin:   built <path>   checked <plugin> <version>   refused <plugin>: <why>
# Exit codes: 0 every plugin built (or checked), 1 one was refused or a file could not be written,
# 2 usage or not a workspace.
#
# Written for bash 3.2 (macOS /bin/bash); needs jq, and zip or python3.
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

usage() { sed -n '5,6p' "$0" | sed 's/^# \{0,1\}//'; }

T="" OUT="" FROM="$KIT/plugins" CHECK=0 names=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target|--out|--from)
            [[ $# -ge 2 && -n "$2" ]] || { echo "setup.sh cowork: $1 needs a folder" >&2; exit 2; }
            case "$1" in --target) T="$2" ;; --out) OUT="$2" ;; --from) FROM="$2" ;; esac
            shift 2 ;;
        --check) CHECK=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "setup.sh cowork: unknown option $1" >&2; usage >&2; exit 2 ;;
        *) names+=("$1"); shift ;;
    esac
done
[[ -n "$T" && -d "$T" ]] || { echo "setup.sh cowork: name the workspace with --target DIR" >&2; exit 2; }
[[ -d "$FROM" ]] || { echo "setup.sh cowork: no plugins folder at $FROM" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "setup.sh cowork: needs jq" >&2; exit 2; }
T="$(cd "$T" && pwd -P)"
[[ -n "$OUT" ]] || OUT="$T/.claude/cowork-plugins"

if [[ ${#names[@]} -eq 0 ]]; then
    for d in "$FROM"/*/; do [[ -f "$d.claude-plugin/plugin.json" ]] && names+=("$(basename "$d")"); done
fi
[[ ${#names[@]} -gt 0 ]] || { echo "setup.sh cowork: no plugins in $FROM" >&2; exit 2; }

# pack <folder> <file>: the folder's contents as a zip, without macOS clutter or git metadata.
pack() {
    if command -v zip >/dev/null 2>&1; then
        (cd "$1" && zip -qrX "$2" . -x '*.DS_Store' -x '.git/*' -x '*/.git/*')
    else
        python3 - "$1" "$2" <<'PYZIP'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d != ".git")
        for f in sorted(files):
            if f == ".DS_Store":
                continue
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, src))
PYZIP
    fi
}

rc=0
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aw-cowork.XXXXXX")" || { echo "setup.sh cowork: no scratch folder" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT
[[ $CHECK -eq 1 ]] || mkdir -p "$OUT" || { echo "setup.sh cowork: cannot write $OUT" >&2; exit 1; }
OUT="$(cd "$OUT" 2>/dev/null && pwd -P || printf '%s' "$OUT")"
for n in "${names[@]}"; do
    d="$FROM/$n"
    m="$d/.claude-plugin/plugin.json"
    if [[ ! -f "$m" ]]; then echo "refused $n: no .claude-plugin/plugin.json"; rc=1; continue; fi
    name="$(jq -r '.name // empty' "$m" 2>/dev/null)"
    ver="$(jq -r '.version // "0.0.0"' "$m" 2>/dev/null)"
    len="$(jq -r '(.description // "") | length' "$m" 2>/dev/null)"
    why=""
    [[ -n "$name" ]] || why="plugin.json has no name; "
    [[ "${len:-0}" -le 500 ]] || why+="description is $len characters, over 500; "
    [[ ! -e "$d/bin" ]] || why+="has a top-level bin/ folder; "
    if [[ -n "$why" ]]; then echo "refused $n: ${why%; }"; rc=1; continue; fi
    if [[ $CHECK -eq 1 ]]; then echo "checked $name $ver"; continue; fi
    f="$OUT/$name-$ver.plugin"
    # Built in a scratch folder and copied over, so nothing in the workspace is renamed or deleted
    # (an agent's shell may be refused both there).
    z="$tmp/$name-$ver.plugin"
    if pack "$d" "$z" && [[ -s "$z" ]] && cp "$z" "$f"; then echo "built $f"; else echo "refused $n: could not write $f"; rc=1; fi
done
exit $rc
