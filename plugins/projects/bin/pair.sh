#!/usr/bin/env bash
# Start, or resume, the engineer's Claude Code session for a /projects:pair pairing.
#
#   kit/plugins/projects/bin/pair.sh <project folder> [--mailbox DIR] [--new] [--ultracode]
#                                    [--mode MODE] [--print]
#
#   --mailbox DIR   the mailbox, when it is not <project folder>/mailbox
#   --new           start a new session even when the last one could be resumed
#   --ultracode     start at ultracode effort, for a phase that fans out across many pieces
#   --mode MODE     the permission mode (default auto; PAIR_PERMISSION_MODE sets it too)
#   --print         print the command it would run, and run nothing
#
# The PM writes the mailbox and its KICKOFF.md first (/projects:pair). This script runs on the person's
# machine, because only there can it see Claude Code's transcripts: when the session id the last
# engineer recorded in the mailbox (.cc-session) still has a transcript, it resumes that session with a
# short prompt; otherwise it starts a new one, named <slug>-cc, with KICKOFF.md as the prompt.
#
# Either way it starts Claude Code in the project folder with this plugin loaded for that session
# (--plugin-dir, so the pairing hooks are there whatever the folder's own settings load) and with
# PAIR_ROLE=cc and PAIR_MAILBOX set, which is what wakes hooks/pair.sh. Every other session ignores them.
# Written for bash 3.2.
set -u

die() { printf 'pair: %s\n' "$*" >&2; exit 2; }
usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

plugin="$(cd "$(dirname "$0")/.." && pwd -P)"
proj="" mb="" new=0 ultra=0 print=0 mode="${PAIR_PERMISSION_MODE:-auto}"
while [ $# -gt 0 ]; do
    case "$1" in
        --mailbox) [ $# -ge 2 ] || die "--mailbox needs a folder"; mb="$2"; shift 2 ;;
        --new) new=1; shift ;;
        --ultracode) ultra=1; shift ;;
        --mode) [ $# -ge 2 ] || die "--mode needs a value"; mode="$2"; shift 2 ;;
        --print) print=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) usage >&2; die "unknown option $1" ;;
        *) [ -z "$proj" ] || die "one project folder only"; proj="$1"; shift ;;
    esac
done
[ -n "$proj" ] || { usage >&2; die "name the project folder"; }
[ -d "$proj" ] || die "$proj is not a folder"
proj="$(cd "$proj" && pwd -P)"
[ -n "$mb" ] || mb="$proj/mailbox"
[ -d "$mb" ] || die "no mailbox at $mb: the PM sets it up with /projects:pair"
mb="$(cd "$mb" && pwd -P)"
[ -f "$mb/to-cc.md" ] || die "$mb has no to-cc.md: the PM sets it up with /projects:pair"
command -v claude >/dev/null 2>&1 || [ $print -eq 1 ] || die "claude is not on PATH"

# A priority prefix (00-, 01-) is not part of the project's name.
slug="$(basename "$proj" | sed 's/^[0-9][0-9]*-//')"

# Resume when the recorded session's transcript is still on this machine.
sid=""
[ -f "$mb/.cc-session" ] && sid="$(head -n 1 "$mb/.cc-session" | tr -d '[:space:]')"
resume=0
if [ $new -eq 0 ] && [ -n "$sid" ]; then
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$sid".jsonl; do
        [ -f "$f" ] && resume=1
        break
    done
fi

args=(--plugin-dir "$plugin" --permission-mode "$mode")
[ $ultra -eq 1 ] && args+=(--effort ultracode)
if [ $resume -eq 1 ]; then
    args+=(--resume "$sid")
    prompt="Resuming the pairing. Read $mb/to-cc.md for anything with Status: open, and carry on from your last message in $mb/to-pm.md."
    how="Resuming session $sid"
else
    args+=(--name "$slug-cc")
    if [ -f "$mb/KICKOFF.md" ]; then prompt="$(cat "$mb/KICKOFF.md")"
    else prompt="You are the engineer on $slug. Read $mb/README.md, then $mb/to-cc.md, and start with the first message whose Status is open."
    fi
    how="Starting a new session, $slug-cc"
fi
[ -f "$mb/.closed" ] && printf 'pair: note: %s/.closed is there, so the session will not wait on the mailbox; the PM removes it to reopen the pairing.\n' "$mb" >&2

if [ $print -eq 1 ]; then
    printf '%s\ncd %q && PAIR_ROLE=cc PAIR_MAILBOX=%q claude' "$how" "$proj" "$mb"
    printf ' %q' "${args[@]}" "$prompt"
    printf '\n'
    exit 0
fi
printf 'pair: %s in %s\n' "$how" "$proj" >&2
cd "$proj" || die "cannot enter $proj"
PAIR_ROLE=cc PAIR_MAILBOX="$mb" exec claude "${args[@]}" "$prompt"
