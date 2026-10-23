#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Add a line to, or remove lines from, a small file that several agents share: a claims board, a
# locks file, a registry. Every change is made under a lock and renamed into place, and a file whose
# first line is a header (it starts with "#") keeps it; see hooks/lib/lock.sh for why.
#
#   kit/plugins/projects/scripts/registry.sh add <file> <line>
#                     appends the line (creating the file if it is not there)
#   kit/plugins/projects/scripts/registry.sh remove <file> <text>
#                     removes every line holding the text (a fixed string, not a pattern)
#   kit/plugins/projects/scripts/registry.sh replace <file> <text> <line>
#                     replaces every line holding the text with the line, or appends it
#
# Prints what it did; exits 1 when the lock could not be had or the change would have lost the
# header, and the file is then as it was. Written for bash 3.2.
set -u
here="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=../hooks/lib/lock.sh
. "$here/../hooks/lib/lock.sh"

usage() { sed -n '6,12p' "$0" | sed 's/^# \{0,1\}//'; }
op="${1:-}" f="${2:-}"
[ -n "$op" ] && [ -n "$f" ] || { usage >&2; exit 2; }
case "$op" in
    add)
        [ $# -eq 3 ] || { usage >&2; exit 2; }
        aw_rewrite "$f" awk -v l="$3" '{ print } END { print l }' || { echo "registry: $f left as it was" >&2; exit 1; }
        echo "registry: added to $f"
        ;;
    remove)
        [ $# -eq 3 ] || { usage >&2; exit 2; }
        # The awk program is single-quoted on purpose (aw_rewrite runs it).
        # shellcheck disable=SC2016
        aw_rewrite "$f" awk -v t="$3" 'NR == 1 && /^#/ { print; next } index($0, t) == 0' || { echo "registry: $f left as it was" >&2; exit 1; }
        echo "registry: removed lines holding that text from $f"
        ;;
    replace)
        [ $# -eq 4 ] || { usage >&2; exit 2; }
        # The awk program is single-quoted on purpose (aw_rewrite runs it).
        # shellcheck disable=SC2016
        aw_rewrite "$f" awk -v t="$3" -v l="$4" 'NR == 1 && /^#/ { print; next } index($0, t) { if (!d) print l; d = 1; next } { print } END { if (!d) print l }' \
            || { echo "registry: $f left as it was" >&2; exit 1; }
        echo "registry: replaced in $f"
        ;;
    -h|--help) usage ;;
    *) usage >&2; exit 2 ;;
esac
