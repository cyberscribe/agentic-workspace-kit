#!/usr/bin/env bash
# Start, or resume, a /projects:pair pairing's Claude Code session: the engineer's (the default), or with
# --pm the product manager's.
#
#   kit/plugins/projects/scripts/pair.sh <project folder> [--mailbox DIR] [--new] [--session ID]
#                                    [--ultracode] [--mode MODE] [--pm] [--print]
#
#   --mailbox DIR   the mailbox for this launch, wherever it is (otherwise hooks/lib/mailbox.sh finds
#                   it: this machine's default root, else <project folder>/mailbox)
#   --new           start a new session even when the last one could be resumed
#   --session ID    resume that session rather than the one the mailbox recorded
#   --ultracode     start at ultracode effort, for a phase that fans out across many pieces
#   --mode MODE     the permission mode (default auto; PAIR_PERMISSION_MODE sets it too)
#   --pm            start, or resume, the PM's own Claude Code session, named <slug>-pm, with the PM's
#                   prompt (examples/pair/PM-KICKOFF.md). A PM's session is for a build pairing; a Cowork
#                   PM is started from Cowork instead
#   --print         print the command it would run, and run nothing
#
# The PM writes the mailbox and its KICKOFF.md first (/projects:pair). This script runs on the person's
# machine, because only there can it see Claude Code's transcripts: when the session id the last
# engineer recorded in the mailbox (.cc-session) still has a transcript, it resumes that session with a
# short prompt; otherwise it starts a new one, named <slug>-cc, with KICKOFF.md as the prompt.
#
# A PM session (--pm) works the same way on .pm-session. A new one gets a fresh token, which the prompt
# gives it and it posts with; the file records the token, and the session id once the PM's watch records
# it. A resume keeps the token the file holds. A PM launch writes .pm-session only when it starts a session.
#
# A resume starts in the folder the transcript records as the session's first working folder, since
# Claude Code finds a session to resume from the folder it is started in, and the session may have been
# started somewhere other than the project folder. A new session starts in the project folder. Either
# way Claude Code starts with this plugin loaded for that session (--plugin-dir, so the pairing hooks are
# there whatever the folder's own settings load). An engineer is started with PAIR_ROLE=cc and
# PAIR_MAILBOX set, which is what wakes hooks/pair.sh; a PM is started the same way with PAIR_ROLE=pm, so its
# Stop hook can hold its turn for the PM watch, which its prompt also gives. Every other session ignores them. A mailbox outside the session's folder is added to it
# (--add-dir), so the session can write there. KICKOFF.md names the mailbox as {mailbox}, and this script
# puts in the path this machine sees, so the same file reads right on every machine that opens the mailbox.
# Written for bash 3.2.
set -u

die() { printf 'pair: %s\n' "$*" >&2; exit 2; }
usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" | sed 's/^# \{0,1\}//'; }

plugin="$(cd "$(dirname "$0")/.." && pwd -P)"
proj="" mb="" new=0 ultra=0 print=0 pm=0 want="" mode="${PAIR_PERMISSION_MODE:-auto}"
while [ $# -gt 0 ]; do
    case "$1" in
        --mailbox) [ $# -ge 2 ] || die "--mailbox needs a folder"; mb="$2"; shift 2 ;;
        --new) new=1; shift ;;
        --session) [ $# -ge 2 ] || die "--session needs an id"; want="$2"; shift 2 ;;
        --ultracode) ultra=1; shift ;;
        --mode) [ $# -ge 2 ] || die "--mode needs a value"; mode="$2"; shift 2 ;;
        --pm) pm=1; shift ;;
        --print) print=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) usage >&2; die "unknown option $1" ;;
        *) [ -z "$proj" ] || die "one project folder only"; proj="$1"; shift ;;
    esac
done
[ -n "$proj" ] || { usage >&2; die "name the project folder"; }
[ -d "$proj" ] || die "$proj is not a folder"
proj="$(cd "$proj" && pwd -P)"
# shellcheck source=SCRIPTDIR/../hooks/lib/mailbox.sh
. "$plugin/hooks/lib/mailbox.sh"
found="$(aw_mb_resolve "$proj" "$mb")"
mb="${found%%"$(printf '\t')"*}"
[ -d "$mb" ] || die "no mailbox at $mb: the PM sets it up with /projects:pair"
mb="$(cd "$mb" && pwd -P)"
[ -f "$mb/to-cc.md" ] || die "$mb has no to-cc.md: the PM sets it up with /projects:pair"
command -v claude >/dev/null 2>&1 || [ $print -eq 1 ] || die "claude is not on PATH"

# A priority prefix (00-, 01-) is not part of the project's name.
slug="$(aw_mb_slug "$proj")"
pairsh="$plugin/hooks/pair.sh"

# Resume when the recorded session's transcript is still on this machine. The engineer's record is its
# bare session id; the PM's is a "session:" line in .pm-session, beside its token.
if [ $pm -eq 1 ]; then
    rec="$mb/.pm-session"
    sid="$want"
    [ -z "$sid" ] && sid="$(sed -n 's/^session: //p' "$rec" 2>/dev/null | head -n 1 | tr -d '[:space:]')"
else
    rec="$mb/.cc-session"
    sid="$want"
    [ -z "$sid" ] && [ -f "$rec" ] && sid="$(head -n 1 "$rec" | tr -d '[:space:]')"
fi
resume=0 where="$proj"
if [ $new -eq 0 ] && [ -n "$sid" ]; then
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$sid".jsonl; do
        [ -f "$f" ] || break
        resume=1
        # The first "cwd" in the transcript is the folder the session started in.
        d="$(grep -o -m 1 '"cwd":"[^"]*"' "$f" | head -n 1 | sed -e 's/^"cwd":"//' -e 's/"$//' -e 's/\\\\/\\/g')"
        [ -n "$d" ] && [ -d "$d" ] && where="$d"
        break
    done
fi
[ -n "$want" ] && [ $resume -eq 0 ] && die "no transcript for session $want on this machine"

# The PM's token: a resumed PM keeps the one its mailbox holds; a new PM gets a fresh one. A print shows a
# placeholder, since nothing is written by a print.
fresh=0 tok=""
if [ $pm -eq 1 ]; then
    tok="$(sed -n 's/^token: //p' "$rec" 2>/dev/null | head -n 1 | tr -d '[:space:]')"
    if [ $resume -eq 0 ] || [ -z "$tok" ]; then
        fresh=1
        if [ $print -eq 1 ]; then tok="<token made at launch>"
        else tok="$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 12)"
        fi
    fi
fi

args=(--plugin-dir "$plugin" --permission-mode "$mode")
[ $ultra -eq 1 ] && args+=(--effort ultracode)
case "$mb/" in "$where"/*) ;; *) args+=(--add-dir "$mb") ;; esac
# The PM's watch, as its prompt gives it: a background command that ends when a CC message arrives.
watch_cmd="bash $(printf '%q' "$pairsh") watch --role pm --mailbox $(printf '%q' "$mb")"
if [ $resume -eq 1 ]; then
    args+=(--resume "$sid")
    if [ $pm -eq 1 ]; then
        prompt="Resuming the pairing as its PM. Your token is $tok: post every PM message with --pm $tok. Read $mb/to-pm.md for CC messages with Status: open, then start the PM watch if none is running: $watch_cmd"
        how="Resuming PM session $sid"
    else
        prompt="Resuming the pairing. Read $mb/to-cc.md for anything with Status: open, and carry on from your last message in $mb/to-pm.md. Start the mailbox watch from your opening context as a background command if none is running."
        how="Resuming session $sid"
    fi
else
    if [ $pm -eq 1 ]; then
        args+=(--name "$slug-pm")
        # awk, not sed, so no character in a path or token can act as a sed command.
        # Paths go in quoted for the shell (%q), and through the environment, since awk -v would read their backslashes.
        prompt="$(PM_M="$(printf '%q' "$mb")" PM_P="$(printf '%q' "$pairsh")" PM_W="$watch_cmd" awk -v t="$tok" -v s="$slug" '
            function rep(str, key, val,   out, i) { out = ""; while ((i = index(str, key)) > 0) { out = out substr(str, 1, i - 1) val; str = substr(str, i + length(key)) } return out str }
            { $0 = rep($0, "{mailbox}", ENVIRON["PM_M"]); $0 = rep($0, "{token}", t); $0 = rep($0, "{pair}", ENVIRON["PM_P"]); $0 = rep($0, "{slug}", s); $0 = rep($0, "{watch}", ENVIRON["PM_W"]); print }' \
            "$plugin/examples/pair/PM-KICKOFF.md")"
        how="Starting a new PM session, $slug-pm"
    else
        args+=(--name "$slug-cc")
        # awk, not sed, so no character in the path can act as a sed command.
        if [ -f "$mb/KICKOFF.md" ]; then prompt="$(awk -v m="$mb" '{ while ((i = index($0, "{mailbox}")) > 0) $0 = substr($0, 1, i - 1) m substr($0, i + 9); print }' "$mb/KICKOFF.md")"
        else prompt="You are the engineer on $slug. Read $mb/README.md, then $mb/to-cc.md, and start with the first message whose Status is open."
        fi
        how="Starting a new session, $slug-cc"
    fi
fi
if [ $pm -eq 0 ]; then
    [ -f "$mb/.closed" ] && printf 'pair: note: %s/.closed is there, so the session will not watch the mailbox; the PM removes it to reopen the pairing.\n' "$mb" >&2
fi

if [ $print -eq 1 ]; then
    if [ $pm -eq 1 ]; then printf '%s\ncd %q && PAIR_ROLE=pm PAIR_MAILBOX=%q claude' "$how" "$where" "$mb"
    else printf '%s\ncd %q && PAIR_ROLE=cc PAIR_MAILBOX=%q claude' "$how" "$where" "$mb"
    fi
    printf ' %q' "${args[@]}" "$prompt"
    printf '\n'
    exit 0
fi
# The PM's record is written when its session is started: the token its posts carry, and when.
if [ $pm -eq 1 ] && [ $fresh -eq 1 ]; then
    printf 'token: %s\nsince: %s\n' "$tok" "$(date '+%Y-%m-%d %H:%M %z')" > "$rec" || die "cannot write $rec"
fi
printf 'pair: %s in %s\n' "$how" "$where" >&2
cd "$where" || die "cannot enter $where"
if [ $pm -eq 1 ]; then PAIR_ROLE=pm PAIR_MAILBOX="$mb" exec claude "${args[@]}" "$prompt"; fi
PAIR_ROLE=cc PAIR_MAILBOX="$mb" exec claude "${args[@]}" "$prompt"
