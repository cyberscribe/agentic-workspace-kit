# shellcheck shell=bash
# A pairing's gate list: what done means for the phase, as checks, in gates.json in the mailbox. Sourced
# by hooks/pair.sh.
#
# The PM writes gates.json with the brief:
#
#   { "gates": [ { "id": "G1", "what": "the suite is green on CI", "check": "gh pr checks <n>",
#                  "by": "pm", "passes": false, "evidence": "" } ] }
#
# id, what and check are fixed once the brief is posted; by (who may set passes: pm, the default; cc;
# or person, which the PM records on the person's word) is fixed too. Only passes and evidence change
# afterwards. The fixed part is sealed when the PM posts its next message with gates.json in place, or
# by `pair.sh gates --from pm --seal` after a deliberate change: a copy goes to .pm-gates, and from then
# on a list whose fixed part differs from the copy is refused, with what changed. That keeps "done" from
# drifting: a check cannot be made easier, or a gate dropped, without the PM sealing it again.
#
# A re-seal never waits on anyone, and it is never silent. .pm-gates keeps a line for each seal after its
# first two lines (the time of the latest seal, then the sealed fixed part):
#   first seal: 2026-11-15 11:00 +0000 · PM token 3f9a
#   re-seal: 2026-11-16 09:12 +0000 · PM token 3f9a · G2's check changed; G4 was added
# and pair.sh check, pair.sh gates and the engineer's session-start line each list every re-seal, with
# when, by which PM session, and what changed.
#
# Each file keeps one writer. gates.json and .pm-gates are the PM's; the engineer never edits them. Its
# evidence, which proposes a pass, is a line in its own status file, status-cc.md:
#   gate G1 · 2026-11-15 11:40 +0000 · <evidence>
# For a gate whose by is cc that line is the pass; for the rest the PM checks the evidence against its
# primary source and sets passes in gates.json.
#
# jq does the reading (the kit needs it; the pair hooks otherwise do without). Without jq, the hooks
# leave the gate line out and the gates command says jq is missing.

# gates_fixed <file>: the fixed part of the list, canonical (sorted keys, one line).
gates_fixed() { jq -S -c 'del(.gates[].passes, .gates[].evidence)' "$1" 2>/dev/null; }

# gates_invalid <file>: one line per problem with the list's shape; nothing when it is sound.
gates_invalid() {
    jq -r '
        if type != "object" or (.gates | type) != "array" then "it is not an object with a list called gates"
        elif (.gates | length) == 0 then "its gates list is empty"
        else
            (.gates | to_entries[] | .key as $i | .value as $g |
                if ($g | type) != "object" then "gate \($i + 1) is not an object"
                elif ($g.id | type) != "string" or $g.id == "" then "gate \($i + 1) has no id"
                elif ($g.what | type) != "string" or $g.what == "" then "\($g.id) has no what"
                elif ($g.check | type) != "string" or $g.check == "" then "\($g.id) has no check"
                elif (["pm", "cc", "person"] | index($g.by // "pm")) == null then "\($g.id): by is pm, cc or person"
                elif ($g.passes | type) != "boolean" then "\($g.id): passes is true or false"
                elif (($g.evidence // "") | type) != "string" then "\($g.id): evidence is text"
                else empty end),
            ([.gates[] | objects | .id] | group_by(.) | map(select(length > 1) | .[0]) | .[] | "\(.) is used by two gates")
        end' "$1" 2>/dev/null || printf 'it is not valid JSON\n'
}

# gates_changes <sealed fixed part> <current fixed part>: what changed, one line each.
gates_changes() {
    jq -rn --argjson a "$1" --argjson b "$2" '
        ($a.gates | map({key: .id, value: .}) | from_entries) as $x
        | ($b.gates | map({key: .id, value: .}) | from_entries) as $y
        | [ ($x | keys[] | select($y[.] == null) | "\(.) was removed"),
            ($y | keys[] | select($x[.] == null) | "\(.) was added"),
            ($x | keys[] as $k | select($y[$k] != null and $y[$k] != $x[$k])
                | (($x[$k] + $y[$k]) | keys[]) as $f | select($x[$k][$f] != $y[$k][$f]) | "\($k)'"'"'s \($f) changed") ]
        | if length == 0 and $a != $b then ["the order of the gates, or something outside them, changed"] else . end
        | .[]' 2>/dev/null
}

# gates_state <mailbox>: sets g_state (none, nojq, invalid, changed, unsealed or ok) and g_why.
gates_state() {
    local f="$1/gates.json" seal="$1/.pm-gates" sealed now
    g_why=""
    [ -f "$f" ] || { g_state=none; return; }
    command -v jq >/dev/null 2>&1 || { g_state=nojq; return; }
    g_why="$(gates_invalid "$f")"
    [ -z "$g_why" ] || { g_state=invalid; return; }
    [ -f "$seal" ] || { g_state=unsealed; return; }
    sealed="$(sed -n '2p' "$seal")"; now="$(gates_fixed "$f")"
    if [ "$sealed" = "$now" ]; then g_state=ok; return; fi
    g_why="$(gates_changes "$sealed" "$now")"
    g_state=changed
}

# gates_seal <mailbox> <who> [<what changed>]: the PM's copy of the fixed part and when it was taken,
# with the seal history carried over and one line added: a first seal, or a re-seal naming what changed.
# Written beside the file and renamed into place, so a reader sees the old copy or the new one.
gates_seal() {
    local s="$1/.pm-gates" t="$1/.pm-gates.tmp.$$" now
    now="$(date '+%Y-%m-%d %H:%M %z')"
    {
        printf 'sealed: %s\n' "$now"
        gates_fixed "$1/gates.json"
        [ -f "$s" ] && sed -n '3,$p' "$s"
        if [ ! -f "$s" ]; then printf 'first seal: %s · %s\n' "$now" "$2"
        else printf 're-seal: %s · %s · %s\n' "$now" "$2" "$3"; fi
    } > "$t" && mv "$t" "$s"
}

# gates_reseals <mailbox>: one line per re-seal, oldest first, or nothing.
gates_reseals() {
    [ -f "$1/.pm-gates" ] || return 0
    awk -F' · ' '/^re-seal: / { sub(/^re-seal: /, "", $1); printf "Re-sealed %s by %s: %s.\n", $1, $2, $3 }' "$1/.pm-gates"
}

# gates_rows <mailbox>: one tab-separated row per gate: id, by, passes (true, false; a cc gate passes on
# the engineer's evidence), the time of the engineer's latest evidence (or empty), what, check, the PM's
# evidence, the engineer's, and the time of evidence left out as older than the gate (or empty).
#
# The engineer's evidence counts only from when the gate it names took its present form: the seal that
# first fixed it, or the latest re-seal that added it or changed its what, check or by. .pm-gates holds
# that history (the "first seal:" and "re-seal:" lines; a list sealed before the history was kept has
# only its "sealed:" line, which stands for every gate). So a new list that reuses an id starts with no
# evidence, and a re-seal that changes G2 leaves G1's evidence counted. Times are compared as minutes
# since 1970 in UTC, worked out from the "%Y-%m-%d %H:%M %z" text both files use, so a seal made in one
# time zone and evidence written in another compare correctly. Evidence in the same minute counts.
gates_rows() {
    local cc="$1/status-cc.md" seal="$1/.pm-gates"
    [ -f "$cc" ] || cc=/dev/null
    [ -f "$seal" ] || seal=/dev/null
    jq -r '.gates[] | [.id, (.by // "pm"), (.passes | tostring), .what, .check, (.evidence // "")] | @tsv' "$1/gates.json" \
        | awk -F'\t' -v OFS='\t' '
            # "2026-11-20 13:52 +0000" as minutes since 1970 in UTC; -1 for text that is not a time.
            function mins(t,    a, y, m, d, era, yoe, doy, doe, off) {
                if (t !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9] [+-][0-9][0-9][0-9][0-9]$/) return -1
                y = substr(t, 1, 4) + 0; m = substr(t, 6, 2) + 0; d = substr(t, 9, 2) + 0
                if (m <= 2) y--
                era = int(y / 400); yoe = y - era * 400
                doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
                doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
                off = substr(t, 19, 2) * 60 + substr(t, 21, 2); if (substr(t, 18, 1) == "-") off = -off
                return (era * 146097 + doe - 719468) * 1440 + substr(t, 12, 2) * 60 + substr(t, 15, 2) - off
            }
            # The seal history: when the list was first fixed, and when each gate was last added or changed.
            FILENAME == seal {
                if ($0 ~ /^sealed: /) { if (base == "") base = mins(substr($0, 9)) }
                else if ($0 ~ /^first seal: /) { split(substr($0, 13), a, sep); base = mins(a[1]) }
                else if ($0 ~ /^re-seal: /) {
                    n = split(substr($0, 10), a, sep); t0 = mins(a[1]); k = split(a[3], c, "; ")
                    for (j = 1; j <= k; j++) {
                        if (c[j] ~ /^[^ ]+ was added$/) { g = c[j]; sub(/ was added$/, "", g); since[g] = t0 }
                        else if (c[j] ~ /^[^ ]+'"'"'s [a-z]+ changed$/) { g = c[j]; sub(/'"'"'s [a-z]+ changed$/, "", g); since[g] = t0 }
                    }
                }
                next
            }
            # "gate <id> · <time> · <evidence>", cut with index so a dot in the evidence stays in it.
            FILENAME == cc { if ($0 ~ /^gate [^ ]+ · /) { s = substr($0, 6); i = index(s, sep); id = substr(s, 1, i - 1)
                             s = substr(s, i + length(sep)); i = index(s, sep); if (i == 0) next
                             tt = substr(s, 1, i - 1); from = (id in since) ? since[id] : (base == "" ? -1 : base)
                             if (from >= 0 && mins(tt) < from) { old[id] = tt; next }
                             t[id] = tt; e[id] = substr(s, i + length(sep)) }; next }
            { pass = $3; if ($2 == "cc" && ($1 in t)) pass = "true"
              print $1, $2, pass, (($1 in t) ? t[$1] : ""), $4, $5, $6, (($1 in e) ? e[$1] : ""), \
                    ((!($1 in t) && ($1 in old)) ? old[$1] : "") }
        ' sep=' · ' seal="$seal" cc="$cc" "$seal" "$cc" -
}

# gates_line <mailbox>: the one-line summary the session-start line and the PM's check carry, or nothing
# when the mailbox has no gate list.
gates_line() {
    local rows n p q
    gates_state "$1"
    case "$g_state" in
        none) return 0 ;;
        nojq) printf 'Gates: gates.json is here, and jq, which reads it, is not installed.\n'; return 0 ;;
        invalid) printf 'Gates: gates.json is not a gate list (%s); pair.sh gates says more.\n' "${g_why%%$'\n'*}"; return 0 ;;
        changed) printf 'Gates: gates.json has changed since the PM sealed it (%s); pair.sh gates refuses it until the PM seals it again.\n' \
            "$(printf '%s' "$g_why" | paste -sd ';' - | sed 's/;/; /g')"; return 0 ;;
    esac
    rows="$(gates_rows "$1")"
    n="$(printf '%s\n' "$rows" | grep -c .)"
    p="$(printf '%s\n' "$rows" | awk -F'\t' '$3 == "true"' | grep -c .)"
    q="$(printf '%s\n' "$rows" | awk -F'\t' '$3 != "true" && $4 != ""' | grep -c .)"
    printf 'Gates: %s of %s pass' "$p" "$n"
    [ "$q" -eq 0 ] || printf ', %s with evidence for the PM to check' "$q"
    [ "$g_state" = unsealed ] && printf ' (not sealed yet: the PM'"'"'s next post seals it)'
    printf ' (pair.sh gates).\n'
}
