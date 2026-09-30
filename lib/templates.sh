# shellcheck shell=bash
# lib/templates.sh: the template render, the ledger, the stand-in values and opaque handling, for the
# engine (install.sh). Sourced, never run, after lib/common.sh. Written for bash 3.2; only git is used.
#
# The render is a pure function of two things: the template files at one kit commit, and the values
# recorded in the ledger's @values line. So a template as it stood at an older commit can be rendered
# again, byte for byte, and set beside today's render as a diff the person applies or skips.
#
# Values live in globals, one per key: AW_V_team AW_V_owner AW_V_handle AW_V_date AW_V_surfaces
# AW_V_cowork AW_V_pilot. A second set, AW_O_<key>, holds another set of values; aw_tpl_swap exchanges
# the two, so a render with older values is a swap, a render, and a swap back.
#
# Functions:
#   aw_tpl_standins              set AW_V_* to the stand-in values
#   aw_tpl_values_parse LINE     set AW_V_* from an @values line (keys it does not name are left alone)
#   aw_tpl_values_line           the @values line for AW_V_*
#   aw_tpl_swap                  exchange AW_V_* and AW_O_*
#   aw_tpl_read KIT COMMIT PATH  a kit file's bytes: the working tree when COMMIT is empty
#   aw_tpl_render KIT COMMIT     render the template on stdin with AW_V_*, rows read at COMMIT
#   aw_tpl_hash                  git's blob hash of stdin
#   aw_ledger_line FILE DEST     the ledger line for DEST, or nothing
#   aw_ledger_field LINE N       field N of a ledger line
#   aw_ledger_put FILE DEST LINE replace DEST's line in FILE, or append it
#   aw_ledger_declined FILE      the .gitignore lines the person declined, one per line
#   aw_tpl_opaque WS DEST        exit 0 when DEST is a file the kit does not open (aw_is_opaque)

# These globals are read by the script that sources this file, and the AW_V_* values also through
# indirect expansion (${!n}), which shellcheck cannot follow.
# shellcheck disable=SC2034
AW_LEDGER_REL=".claude/kit-templates.lock"
AW_VALUE_KEYS="team owner handle date surfaces cowork pilot"
AW_TAB=$'\t'

# The header of a new ledger. The first three lines are the contract's; the fourth names the fields.
aw_ledger_header() {
    printf '%s\n' \
        '# Written by kit/install.sh. One line per file the kit created from a template; the file itself is' \
        "# yours. This records which template version it came from, so kit/setup.sh update can offer the" \
        "# template's later changes as a diff to apply or skip." \
        '# Fields: file, template, kit commit, template hash, status (created, kept, accepted, skipped, lines).'
}

# shellcheck disable=SC2034
aw_tpl_standins() {
    AW_V_team="<team name>"
    AW_V_owner="<standards owner>"
    AW_V_handle="@<standards-owner-handle>"
    AW_V_date="YYYY-MM-DD"
    AW_V_surfaces="claude"
    AW_V_cowork=0
    AW_V_pilot=0
}

# aw_tpl_values_parse LINE: an @values line, or any tab-separated key=value fields. A tab or newline
# inside a value cannot occur: the engine turns them into spaces before it records anything.
aw_tpl_values_parse() {
    local f k v rest="$1"
    while [[ -n "$rest" ]]; do
        f="${rest%%"$AW_TAB"*}"
        if [[ "$rest" == *"$AW_TAB"* ]]; then rest="${rest#*"$AW_TAB"}"; else rest=""; fi
        [[ "$f" == *=* ]] || continue
        k="${f%%=*}" v="${f#*=}"
        case " $AW_VALUE_KEYS " in *" $k "*) printf -v "AW_V_$k" '%s' "$v" ;; esac
    done
}

aw_tpl_values_line() {
    local k n out="@values"
    for k in $AW_VALUE_KEYS; do n="AW_V_$k"; out+="$AW_TAB$k=${!n}"; done
    printf '%s\n' "$out"
}

aw_tpl_swap() {
    local k a b t
    for k in $AW_VALUE_KEYS; do
        a="AW_V_$k" b="AW_O_$k"
        t="${!a}"
        printf -v "$a" '%s' "${!b-}"
        printf -v "$b" '%s' "$t"
    done
}

# aw_tpl_read KIT COMMIT PATH: cat-file rather than show, so the bytes are the blob's exactly.
aw_tpl_read() {
    if [[ -z "$2" ]]; then
        cat "$1/$3"
    else
        aw_git_elsewhere "$1" cat-file blob "$2:$3"
    fi
}

# aw_tpl_render KIT COMMIT < template > render
# The placeholders are __TEAM__, __OWNER__, __OWNER_HANDLE__, __DATE__ and __SURFACE_ROWS__. The rows
# are template files too (templates/workspace/surface-rows/), read at the same commit as the template,
# so an old render uses the old rows. Values reach awk through the environment, which passes
# backslashes, ampersands and backticks through as written; the substitution is index and substr, so
# no character in a value is special.
aw_tpl_render() {
    local kit="$1" commit="${2:-}" rows="" r f
    for f in claude cowork gemini; do
        case "$f" in
            cowork) [[ "$AW_V_cowork" == 1 ]] || continue ;;
            gemini) [[ ",$AW_V_surfaces," == *",gemini,"* ]] || continue ;;
        esac
        r="$(aw_tpl_read "$kit" "$commit" "templates/workspace/surface-rows/$f.md" 2>/dev/null | awk 'NF { print; exit }')"
        [[ -n "$r" ]] || continue
        if [[ -n "$rows" ]]; then rows="$rows"$'\n'"$r"; else rows="$r"; fi
    done
    AW_R_TEAM="$AW_V_team" AW_R_OWNER="$AW_V_owner" AW_R_HANDLE="$AW_V_handle" AW_R_DATE="$AW_V_date" \
    AW_R_ROWS="$rows" awk '
        function swap(s, tok, val,    out, i) {
            out = ""
            while ((i = index(s, tok)) > 0) { out = out substr(s, 1, i - 1) val; s = substr(s, i + length(tok)) }
            return out s
        }
        {
            line = $0
            line = swap(line, "__OWNER_HANDLE__", ENVIRON["AW_R_HANDLE"])
            line = swap(line, "__OWNER__", ENVIRON["AW_R_OWNER"])
            line = swap(line, "__TEAM__", ENVIRON["AW_R_TEAM"])
            line = swap(line, "__DATE__", ENVIRON["AW_R_DATE"])
            line = swap(line, "__SURFACE_ROWS__", ENVIRON["AW_R_ROWS"])
            print line
        }'
}

# aw_tpl_hash: the blob hash git would give these bytes, with no filters, so it depends on the bytes
# alone and not on where it runs.
aw_tpl_hash() { git hash-object --no-filters --stdin; }

# aw_ledger_line FILE DEST: the first line whose first field is DEST. Comments, the @values line and
# !declined lines never match, since no dest starts with # @ or !.
aw_ledger_line() {
    [[ -f "$1" ]] || return 0
    awk -F '\t' -v d="$2" '$1 == d && $1 !~ /^[#@!]/ { print; exit }' "$1"
}

aw_ledger_field() { printf '%s\n' "$1" | awk -F '\t' -v n="$2" '{ print $n }'; }

# aw_ledger_put FILE DEST LINE: DEST's line replaced in place, or LINE appended; the order of the
# other lines is kept.
aw_ledger_put() {
    local file="$1" dest="$2" line="$3" t
    t="$(mktemp "${TMPDIR:-/tmp}/aw-ledger.XXXXXX")" || return 1
    AW_L_LINE="$line" awk -F '\t' -v d="$dest" '
        $1 == d && $1 !~ /^[#@!]/ && !done { print ENVIRON["AW_L_LINE"]; done = 1; next }
        { print }
        END { if (!done) print ENVIRON["AW_L_LINE"] }' "$file" > "$t" && cat "$t" > "$file"
    local rc=$?
    rm -f "$t"
    return $rc
}

aw_ledger_declined() {
    [[ -f "$1" ]] || return 0
    awk -F '\t' '$1 == "!declined" && $2 == ".gitignore" { print $3 }' "$1"
}

# aw_tpl_opaque WS DEST: the engine never opens an opaque file (contract §0.4); it records the file as
# kept without reading it.
aw_tpl_opaque() { aw_is_opaque "$1" "$2"; }
