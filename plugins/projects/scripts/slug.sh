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
# The accented Latin letters are written plainly from a fixed table first: iconv's transliteration
# depends on the locale, and in the C locale a CI runner has it writes "?" for each (Café became caf).
# iconv then takes what the table does not cover, marking an accent with a separate character (e' on
# macOS) that the quote removal drops; where iconv cannot convert, the name goes on as given.
name="$*"
# Each letter is its own substitution of its UTF-8 bytes: a bracket expression would be read byte by
# byte in the C locale.
plain='à a á a â a ã a ä a å a æ ae ç c è e é e ê e ë e ì i í i î i ï i ñ n ò o ó o ô o õ o ö o ø o œ oe ù u ú u û u ü u ý y ÿ y ß ss
À A Á A Â A Ã A Ä A Å A Æ AE Ç C È E É E Ê E Ë E Ì I Í I Î I Ï I Ñ N Ò O Ó O Ô O Õ O Ö O Ø O Œ OE Ù U Ú U Û U Ü U Ý Y'
prog=""
# The table splits into its pairs on purpose, and holds no pattern characters.
# shellcheck disable=SC2086
set -- $plain
while [ $# -gt 1 ]; do prog="${prog}s/$1/$2/g;"; shift 2; done
t="$(printf '%s' "$name" | LC_ALL=C sed "$prog")"
t2="$(printf '%s' "$t" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null)" && t="$t2"
s="$(printf '%s' "$t" | LC_ALL=C tr -d "'\`\"^~" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//')"
[ -n "$s" ] || exit 1
printf '%s\n' "$s"
