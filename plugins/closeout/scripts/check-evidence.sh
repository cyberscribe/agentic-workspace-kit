#!/usr/bin/env bash
# Check closeout candidates against the session's own record before anything is promoted.
#
#   plugins/closeout/scripts/check-evidence.sh <candidates.md> [--transcript PATH] [--session ID]
#
# The candidates are a closeout draft, or the list /closeout writes before it promotes, in the item
# shape the capture prompt and the command describe:
#
#   transcript: /path/to/<session-id>.jsonl          (optional, once, before the first item)
#
#   ### <one-line claim>
#   - plain: <the claim in one everyday sentence, as the person reads it first>
#   - source: correction | missing-context | general                 (general when left out)
#   - tier: <tier name>
#   - destination: <file or directory>
#   - check: supported | contradicted | unsupported | already-written | observed
#   - evidence: L212 "a short span quoted verbatim from line 212"   (one or more)
#   - was: L48 "what the record said first"                         (contradicted)
#   - correction: <what the record shows>  or  - dropped: <why>      (contradicted)
#   - missing: <what would support it>                               (unsupported)
#   - found: <where a session would already find it>                 (already-written)
#
# already-written is a learning a later session would find by itself (in the code, the files, the docs,
# git log or a tool's help); it is not promoted, and found: says where. observed is something the session
# saw and could not explain: cited, never promoted as fact, and reported to the person.
#
# L<n> is a line of the transcript JSONL. The file is append-only, so a line number stays put. An anchor
# resolves when the line exists, is a turn of the conversation, and its text holds the quoted span once
# whitespace is collapsed. A turn is the person, a tool's output, the agent's text and tool calls, or the
# prompt a run was given: a queue record that enqueues it, or a queued_command attachment that is not a
# task notification. Hook injections, other attachments and request records are not turns.
#
# The quote runs from the first " after L<n> to the next " that is not escaped with a backslash; text
# after it is a note and is ignored. Inside it, \" is a quote, \\ a backslash, and \n or \t a line break
# or a tab, so a span copied from JSON output or across lines reads as the line does.
#
# Three rules about where a learning came from, as the item says: every item has a plain: line; a
# working-standards item is never a general lesson (it needs a correction or a gap in context, with the
# incident behind it); and a correction cites at least one line that is the person's own words.
#
# The record is found in this order: --transcript, the draft's transcript: line, --session, and the
# draft's own name (<session-id>.md), each id looked up as <config>/projects/*/<id>.jsonl under
# CLAUDE_CONFIG_DIR or ~/.claude. With none, nothing can be resolved and the output says so.
#
# What this proves is narrow and deliberate: the evidence exists, sits where it is said to, says what is
# quoted, and for the always-loaded tier comes from someone other than the agent. Whether the quote
# supports the claim, and whether a later turn reverses it, is the reader's judgement.
#
# One line per item, each anchor beneath it, then a count. Exit 0 when nothing is refused, 1 when
# something is (each refusal is named), 2 on bad usage.

set -euo pipefail

usage() { sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

draft="" transcript="" session=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --transcript) [[ $# -ge 2 ]] || usage; transcript="$2"; shift 2 ;;
        --session) [[ $# -ge 2 ]] || usage; session="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*) usage ;;
        *) [[ -z "$draft" ]] || usage; draft="$1"; shift ;;
    esac
done
[[ -n "$draft" && -f "$draft" ]] || usage
command -v jq >/dev/null 2>&1 || { echo "check-evidence: jq is needed" >&2; exit 2; }

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
by_id() { # by_id <session id>: the first transcript with that id, or nothing
    local f
    for f in "$config_dir"/projects/*/"$1".jsonl; do [[ -f "$f" ]] && { printf '%s' "$f"; return; }; done
    return 0
}

# The record: the first source that names a file that exists.
header="$(awk '/^### /{exit} /^transcript:[[:space:]]*/{sub(/^transcript:[[:space:]]*/, ""); print; exit}' "$draft")"
header="${header/#\~/$HOME}"
record=""
# A relative transcript: line is read from the draft's own folder.
[[ -n "$header" && "$header" != /* ]] && header="$(dirname "$draft")/$header"
for candidate in "$transcript" "$header"; do
    [[ -n "$candidate" && -f "$candidate" ]] && { record="$candidate"; break; }
done
[[ -z "$record" && -n "$session" ]] && record="$(by_id "$session")"
[[ -z "$record" ]] && record="$(by_id "$(basename "$draft" .md)")"

if [[ -n "$record" ]]; then
    record_lines="$(wc -l < "$record" | tr -d ' ')"
    echo "record: $record ($record_lines lines)"
else
    record_lines=0
    named="${transcript:-${header:-}}"
    echo "record: none found${named:+ ($named is gone)}; anchors cannot be resolved, so this checks the draft's own quotes only"
fi

# The always-loaded file, by name: CLAUDE.md, AGENTS.md, or wherever CLOSEOUT_TIER_ALWAYS points.
always_names=" CLAUDE.md AGENTS.md "
[[ -n "${CLOSEOUT_TIER_ALWAYS:-}" ]] && always_names+="$(basename "$CLOSEOUT_TIER_ALWAYS") "

# speaker_and_text <n>: "<speaker>\t<text>" for line n, where speaker is person, tool, agent or none.
speaker_and_text() {
    sed -n "${1}p" "$record" | jq -r '
        def txt(c): if (c | type) == "string" then c
                    else [c[]? | if .type == "text" then .text
                                 elif .type == "tool_result" then txt(.content)
                                 elif .type == "tool_use" then ([.input | .. | strings] | join(" "))
                                 else empty end] | join(" ") end;
        if .type == "queue-operation" and .operation == "enqueue" and ((.content | type) == "string") then
            "prompt\t" + .content
        elif .type == "attachment" and .attachment.type == "queued_command" and ((.attachment.prompt | type) == "string")
             and (.attachment.prompt | startswith("<task-notification>") | not) then
            "prompt\t" + .attachment.prompt
        elif .type == "user" and (.isMeta | not) then
            (if ((.message.content | type) == "array") and any(.message.content[]; .type == "tool_result")
             then "tool" else "person" end) + "\t" + txt(.message.content)
        elif .type == "assistant" then "agent\t" + txt(.message.content)
        else "none\t" end' 2>/dev/null || printf 'none\t'
}

squash() { tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }

# parse_anchor <value>: sets a_n and a_quote from 'L<n> "<quote>"[ note]', by the rule in the header.
# Returns 1 when the value is not an anchor.
parse_anchor() {
    local v="$1" rest c i out="" esc=0
    [[ "$v" =~ ^L([0-9]+)[[:space:]]+\"(.*)$ ]] || return 1
    a_n="${BASH_REMATCH[1]}" rest="${BASH_REMATCH[2]}"
    for (( i = 0; i < ${#rest}; i++ )); do
        c="${rest:i:1}"
        if [[ $esc -eq 1 ]]; then
            case "$c" in n) out+=$'\n' ;; t) out+=$'\t' ;; *) out+="$c" ;; esac
            esc=0
        elif [[ "$c" == "\\" ]]; then esc=1
        elif [[ "$c" == '"' ]]; then a_quote="$(printf '%s' "$out" | squash)"; return 0
        else out+="$c"; fi
    done
    return 1
}

# Items as tab-separated records: index, key, value. The claim is key "claim".
items="$(awk '
    /^### / { n++; sub(/^### +/, ""); print n "\tclaim\t" $0; next }
    n && /^- [a-z ]+:/ { line = $0; sub(/^- /, "", line); k = line; sub(/:.*/, "", k); v = line; sub(/^[^:]*:[[:space:]]*/, "", v); print n "\t" k "\t" v }
' "$draft")"

count=0 supported=0 contradicted=0 unsupported=0 already=0 observed=0 refused=0
refusals=""
refuse() { refusals+="refused: $1"$'\n'; refused=$((refused + 1)); }

total="$(printf '%s\n' "$items" | awk -F'\t' 'NF { n = $1 } END { print n + 0 }')"
i=0
while [[ $i -lt $total ]]; do
    i=$((i + 1))
    rows="$(printf '%s\n' "$items" | awk -F'\t' -v i="$i" '$1 == i')"
    get() { printf '%s\n' "$rows" | awk -F'\t' -v k="$1" '$2 == k { sub(/^[^\t]*\t[^\t]*\t/, ""); print }'; }
    claim="$(get claim)" check="$(get check | head -n 1 | tr -d '`' | tr '[:upper:]' '[:lower:]' | squash)"
    tier="$(get tier | head -n 1)" dest="$(get destination | head -n 1 | tr -d '`')"
    count=$((count + 1))

    strict=""
    dest_file="$(basename "${dest%% *}" 2>/dev/null || true)"
    case "$always_names" in *" $dest_file "*) [[ -n "$dest_file" ]] && strict=1 ;; esac
    grep -qi 'working standards' <<<"$tier" && strict=1

    printf '%-13s %s%s\n' "${check:-no check}" "$claim" "${strict:+  [always-loaded]}"

    # Each anchor: resolve it, note who spoke, and keep the line numbers for the order check.
    others=0 persons=0 bad_anchor=0 ev_max=0 was_max=0 n_ev=0
    while IFS=$'\t' read -r kind value; do
        [[ -n "$kind" ]] || continue
        if ! parse_anchor "$value"; then
            echo "    $kind: not an anchor (L<n> \"quote\"): $value"; bad_anchor=1; continue
        fi
        n="$a_n" quote="$a_quote"
        [[ "$kind" == evidence ]] && { n_ev=$((n_ev + 1)); [[ $n -gt $ev_max ]] && ev_max=$n; }
        [[ "$kind" == was && $n -gt $was_max ]] && was_max=$n
        if [[ -z "$record" ]]; then
            echo "    $kind L$n: not resolved (no record)"; continue
        fi
        if [[ $n -lt 1 || $n -gt $record_lines ]]; then
            echo "    $kind L$n: past the end of the record ($record_lines lines)"; bad_anchor=1; continue
        fi
        st="$(speaker_and_text "$n")" speaker="${st%%$'\t'*}" text="$(printf '%s' "${st#*$'\t'}" | squash)"
        if [[ "$speaker" == none ]]; then
            echo "    $kind L$n: not a turn of the conversation"; bad_anchor=1
        elif [[ -z "$quote" || "$text" != *"$quote"* ]]; then
            echo "    $kind L$n ($speaker): the quote is not on this line"; bad_anchor=1
        else
            echo "    $kind L$n ($speaker): ok"
            [[ "$kind" == evidence && "$speaker" != agent ]] && others=$((others + 1))
            [[ "$kind" == evidence && "$speaker" == person ]] && persons=$((persons + 1))
        fi
    done < <(printf '%s\n' "$rows" | awk -F'\t' '$2 == "evidence" || $2 == "was" { print $2 "\t" $3 }')

    [[ $bad_anchor -eq 1 ]] && refuse "$claim: an anchor does not resolve"
    plain="$(get plain | head -n 1)" source="$(get source | head -n 1 | tr -d '`' | tr '[:upper:]' '[:lower:]' | squash)"
    [[ -n "$plain" ]] || refuse "$claim: no plain: line (the claim in one everyday sentence, as the person reads it)"
    case "${source:-general}" in
        correction)
            [[ $persons -gt 0 || -z "$record" ]] || refuse "$claim: a correction, with no evidence line in the person's own words" ;;
        missing-context|general) ;;
        *) refuse "$claim: source: is '$source', not correction, missing-context or general" ;;
    esac
    [[ -n "$strict" && "${source:-general}" == general ]] \
        && refuse "$claim: for the always-loaded tier, from a general lesson; it needs the person's correction or a gap in context, with the incident"
    case "$check" in
        supported)
            supported=$((supported + 1))
            [[ $n_ev -gt 0 ]] || refuse "$claim: supported, with no evidence line"
            if [[ -n "$strict" ]]; then
                if [[ -z "$record" ]]; then
                    refuse "$claim: for the always-loaded tier, and the record is not here to resolve it; propose it with its quotes, checked against the draft only"
                elif [[ $others -eq 0 ]]; then
                    refuse "$claim: for the always-loaded tier, cited only by the agent's own words; it needs the person's words or a tool's output"
                fi
            fi ;;
        contradicted)
            contradicted=$((contradicted + 1))
            if [[ -n "$(get correction)" ]]; then echo "    → corrected: $(get correction | head -n 1)"
            elif [[ -n "$(get dropped)" ]]; then echo "    → dropped: $(get dropped | head -n 1)"
            else refuse "$claim: contradicted, with neither correction: nor dropped:"; fi
            [[ $n_ev -gt 0 ]] || refuse "$claim: contradicted, with no evidence line"
            [[ $was_max -gt 0 && $ev_max -le $was_max ]] && refuse "$claim: the contradicting evidence (L$ev_max) is not later than what it reverses (L$was_max)"
            [[ -n "$strict" && -n "$(get correction)" ]] && refuse "$claim: a correction bound for the always-loaded tier is restated as its own supported candidate"
            ;;
        unsupported)
            unsupported=$((unsupported + 1))
            if [[ -n "$(get missing)" ]]; then echo "    → unverified: missing $(get missing | head -n 1)"
            else refuse "$claim: unsupported, with no missing: line"; fi
            [[ -n "$strict" ]] && refuse "$claim: unsupported, and bound for the always-loaded tier"
            ;;
        already-written)
            already=$((already + 1))
            if [[ -n "$(get found)" ]]; then echo "    → already written: $(get found | head -n 1)"
            else refuse "$claim: already-written, with no found: line saying where"; fi ;;
        observed)
            observed=$((observed + 1))
            echo "    → observed, cause unknown"
            [[ $n_ev -gt 0 ]] || refuse "$claim: observed, with no evidence line"
            [[ -n "$strict" ]] && refuse "$claim: observed, and bound for the always-loaded tier"
            ;;
        *) refuse "$claim: no check: line (supported, contradicted, unsupported, already-written or observed)" ;;
    esac
done

echo
extra=""
[[ $already -gt 0 ]] && extra+=", $already already written"
[[ $observed -gt 0 ]] && extra+=", $observed observed"
echo "$count items: $supported supported, $contradicted contradicted, $unsupported unsupported (unverified)$extra; $refused refused"
if [[ $refused -gt 0 ]]; then printf '%s' "$refusals"; exit 1; fi
exit 0
