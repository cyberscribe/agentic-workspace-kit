#!/usr/bin/env bash
# The folder name for a project or an ongoing area, from the name the person gives it. /projects:new and
# /ongoing:new both use this, so the same name always becomes the same folder.
#
#   kit/plugins/projects/scripts/slug.sh <name>...
#
# The words are joined with spaces, accented letters are written in plain ASCII where iconv can (Café
# is cafe), apostrophes and quotes are dropped (Sam's is sams), and the rest is lowercased; every run of
# anything other than a-z and 0-9 becomes one hyphen, and hyphens at either end are dropped. What is
# left is safe on every filesystem and in a URL: "Spring Workshop" is spring-workshop, "Rose garden
# (2027)" is rose-garden-2027. The commands show the slug, and the person can give another.
#
# Prints the slug; exits 1, printing nothing, when nothing usable is left, and 2 with no name.
# Written for bash 3.2.
set -u
[ $# -gt 0 ] || { echo "usage: slug.sh <name>" >&2; exit 2; }
# iconv's transliteration marks an accent with a separate character (e' on macOS), which the quote
# removal then drops; where iconv cannot convert, the name goes on as given.
t="$(printf '%s' "$*" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null)" || t="$*"
s="$(printf '%s' "$t" | LC_ALL=C tr -d "'\`\"^~" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//')"
[ -n "$s" ] || exit 1
printf '%s\n' "$s"
