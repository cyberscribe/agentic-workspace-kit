#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# SessionEnd auto-capture for the closeout ritual.
#
# A good habit is to end a session by asking the agent to record what it learned
# and update the durable in-repo docs. Anyone who forgets that step loses those
# learnings. This hook is the safety net: on session end it spawns a separate,
# detached headless `claude -p` that reads the just-ended transcript and writes
# candidate doc-notes to a scratch file outside the repo. The next session in
# this project is pointed at that file by closeout-review.sh, to review and
# promote anything durable.
#
# It cannot make the *current* agent do the work: SessionEnd fires after the
# agent loop is over and its stdout is not injected into context. Hence the
# detached child, which is fully detached so the human's exit is never delayed.
#
# Wired from hooks/hooks.json -> hooks.SessionEnd. Receives the SessionEnd JSON
# on stdin.

set -euo pipefail

# Read the hook input before any early exit. A hook that exits with stdin unread
# can leave the writer holding a closed pipe (SIGPIPE, exit 141), which reads as a
# failed hook rather than a silent one.
input="$(cat)"

# (1) Recursion guard, checked first. The headless child below also triggers a
# SessionEnd when it finishes; without this it would spawn children forever.
if [[ -n "${CLOSEOUT_HOOK_CHILD:-}" ]]; then
    exit 0
fi

# (2) Global off switch, for projects that want /closeout without the backstop.
[[ "${CLOSEOUT_DISABLED:-}" == "1" ]] && exit 0

# Outside a kit workspace the plugin is installed but has nothing to do (hooks/lib/boundary.sh).
# shellcheck source=lib/boundary.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/boundary.sh"
[[ -n "$(aw_workspace_root "$input")" ]] || exit 0

# shellcheck source=lib/config.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

command -v jq >/dev/null 2>&1 || exit 0


reason="$(printf '%s' "$input" | jq -r '.reason // empty')"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"

# (3) Skip noise: /clear is not a real closeout, and a missing or unreadable
# transcript means there is nothing to capture.
[[ "$reason" == "clear" ]] && exit 0
[[ -z "$transcript_path" || ! -f "$transcript_path" ]] && exit 0

# (4) Skip trivial sessions — a handful of transcript lines is not worth a run.
min_lines="${CLOSEOUT_MIN_LINES:-6}"
lines="$(wc -l < "$transcript_path" 2>/dev/null || echo 0)"
[[ "$lines" -lt "$min_lines" ]] && exit 0

# (5) Resolve the claude binary in a PATH-independent way — hooks run with a
# minimal environment that often misses a user's shell PATH additions.
CLAUDE_BIN="${CLOSEOUT_CLAUDE_BIN:-$(command -v claude || true)}"
[[ -z "$CLAUDE_BIN" && -x "$HOME/.local/bin/claude" ]] && CLAUDE_BIN="$HOME/.local/bin/claude"
[[ -z "$CLAUDE_BIN" && -x "/usr/local/bin/claude" ]] && CLAUDE_BIN="/usr/local/bin/claude"
[[ -z "$CLAUDE_BIN" && -x "/opt/homebrew/bin/claude" ]] && CLAUDE_BIN="/opt/homebrew/bin/claude"
[[ -z "$CLAUDE_BIN" ]] && exit 0

project_dir="${cwd:-$PWD}"
closeout_config "$project_dir"
mkdir -p "$DRAFT_DIR" 2>/dev/null || exit 0
# Absolute, because the child runs from this directory (step 8): a relative
# CLOSEOUT_DRAFT_ROOT would otherwise resolve twice and misfile the draft.
DRAFT_DIR="$(CDPATH='' cd -- "$DRAFT_DIR" 2>/dev/null && pwd -P)" || exit 0

# (6) Suppression handshake with the /closeout command. When someone runs
# /closeout in-session, it already promotes durable learnings into the in-repo
# docs and drops a per-session sentinel here (.closeout-ran.<session_id>). Honor
# only the sentinel matching this ending session: skip the redundant auto-capture
# and remove it. A stale sentinel (older than 6h) is cleared but not honored, so
# an old closeout can never silence captures indefinitely.
#
# Keying by session id (not just project) means a /closeout in one session
# suppresses only that session's capture — concurrent or worktree sessions in the
# same project keep their own safety net, instead of the first session to end
# consuming a single shared sentinel and the rest writing spurious drafts.
if [[ -n "$session_id" ]]; then
    sentinel="$DRAFT_DIR/.closeout-ran.$session_id"
    if [[ -f "$sentinel" ]]; then
        fresh="$(find "$sentinel" -mmin -360 2>/dev/null)"
        rm -f "$sentinel"
        [[ -n "$fresh" ]] && exit 0
    fi
fi

# Sweep stale sentinels so they never accumulate.
find "$DRAFT_DIR" -maxdepth 1 -type f -name '.closeout-ran.*' -mmin +360 -delete 2>/dev/null || true

draft_file="$DRAFT_DIR/${session_id:-$(date +%s)}.md"

# (7) The promotion taxonomy. A project that defines its own tiers owns the
# section outright; failing that, the person's own conventions may; otherwise the
# plugin's default table is supplied.
if [[ "$CONVENTIONS_DEFINE_TIERS" == "project" ]]; then
    taxonomy="This project defines its own promotion tiers. Use exactly those — the
tier names, destinations and load rates below come from the project, and no other
taxonomy applies."
elif [[ "$CONVENTIONS_DEFINE_TIERS" == "user" ]]; then
    taxonomy="The person's own closeout conventions, below, define the promotion tiers.
Use exactly those — the tier names, destinations and load rates come from that
file, and no other taxonomy applies."
else
    taxonomy="TIER — where it belongs, which decides how often it is loaded back:

$TIER_TABLE

SCOPE — shared (committed, reaches teammates) or individual (this machine and
user only). A learning a teammate would need is worthless in an individual
destination."
fi

# Conventions, appended verbatim: the project's first, then the person's own.
# The project's win wherever the two disagree, which the prompt says in words
# because the child sees only text, not which file came from where.
conventions=""
if [[ -f "$CONVENTIONS_FILE" ]]; then
    conventions="

This project's own closeout conventions follow. They override everything above —
tier names, destinations, load rates, and any house rules:

$(cat "$CONVENTIONS_FILE")"
fi
if [[ -n "$USER_CONVENTIONS_FILE" ]]; then
    if [[ -f "$CONVENTIONS_FILE" ]]; then
        user_rank="They add to the project's conventions above; wherever the two
disagree, the project's win."
    else
        user_rank="They override the defaults above wherever they say something
different."
    fi
    conventions="$conventions

The person's own closeout conventions follow, from their personal file. They
apply in every repository this person works in.
$user_rank

$(cat "$USER_CONVENTIONS_FILE")"
fi

# (7b) Who needs to know — when two or more people are known for the repository
# and the step is not switched off. The hook cannot see which project the session
# worked in or what changed, so it lists everyone known and leaves the per-project
# condition (two or more for this project, or a scoped roster match) to the prompt. Under "ask" the draft still carries the section; the next session
# offers it in one line rather than presenting it (closeout-review.sh).
team_section=""
if [[ "${TEAM_COUNT:-0}" -ge 2 && "$WHO_NEEDS_TO_KNOW" != "off" ]]; then
    roster_note=""
    if [[ -n "$ROSTER_ROWS" ]]; then
        roster_note="

The team roster gives these default relationships and channels. A scoped one,
such as 'informed: anything touching measurement', applies only to a change of
that kind. A project's People section overrides the roster for that project; the
next session applies that.
$(printf '%s\n' "$ROSTER_ROWS" | awk -F'|' '{ r = ($2 == "" ? "no default" : $2); h = $3; if ($4 != "") h = h (h == "" ? "" : " ") $4
                                             print "  - " $1 " — " r (h == "" ? "" : " — " h) }')"
    fi
    team_section="

People known for this repository:
$(printf '%s\n' "$TEAM_MEMBERS" | sed 's/^/  - /')${roster_note}

If you write the file, end it with one more section, headed '## Who needs to
know'. Name a person from that list only where their work is affected by an item
above — they are accountable for the area it touches, a decision changes what
they are responsible for, it blocks or unblocks them, or they are to be consulted
before it is decided — one line each: who, what (in the item's plain words),
which item, and how they hear (their channel, where one is given). If nobody in particular needs to hear
about anything, write that in one line; if the session's work concerns only one
of them, leave the section out. You are suggesting; nothing is sent to anyone."
fi

read -r -d '' PROMPT <<EOF || true
You are reviewing a just-ended Claude Code session for this project to capture
durable learnings before they are lost. Read the session transcript (JSONL) at:
  $transcript_path

Memory is for the next session in this project. It starts without this
conversation and acts on what the files tell it. One test comes before anything
else: could that session find this by itself, in the code, the files, the docs,
git log or a tool's own help? If it could, it is not promoted. Write it as
already-written, with where it is found, and move on.

A second question goes with it: where would the obvious next move go wrong?
The command anyone would try first, the file anyone would edit, the assumption
anyone would make: where this session walked into a trap on that path, or the
person steered it round one, record the trap as the likely move, what goes
wrong and what to do instead. Its plain: line reads as a warning a colleague
would give, and its evidence is the moment it went wrong: the person's
correction, or the failed step and what fixed it. It usually goes to project or
general reference, beside what it is about.

Look for what passes that test in this order, and give the first the most care:

1. The person's interventions: what they redirected, corrected, refused or
   explained. Each one shows context the session did not have.
2. Your own mistakes in the session, read as missing context: where would more
   context have helped? If that context arrived later in the session, record the
   context itself. If it never arrived, propose asking the person for it.
3. Only then a general lesson, sparingly, favouring the specific and practical.

The order says where to look first; it is not a list of kinds to record. Judge
what would serve the next session from this session.

The person reads every item first as one plain sentence in their own words, not
in your idiom. A term that is not plain goes through the glossary
(memory/glossary.md, or the project's own glossary.md): use its plain words, or
propose a row for the term. A decision goes to the decisions file, a term of the
work to terms.md, a translation of AI-speak to the glossary, and the rest by the
tiers below.

Classify every item you keep on two axes before writing it down.

$taxonomy

Default to the cheapest tier that still works. Scope decides who it reaches:
shared reaches the team's sessions, individual only this person's. The always-loaded tier is a budget paid by every future session, not a
folder: put something there only if a session that never thought to ask for it
would still go wrong without it. Everything else is cheaper as reference that
loads on demand.

A note that is wrong costs more than a missing one, because the next session
acts on it. So check every item against the transcript before you write it
down. Find the line that supports it, then read on to the end of the transcript
for the same subject: a later turn can reverse an earlier one (a fix that was
reverted, a belief corrected after a test), and the latest word holds. Give each
item one result:

  supported     the record shows it and nothing later reverses it; cite the
                line or lines that show it
  contradicted  a later turn reverses it; cite the earlier line as "was" and
                the later one as "evidence", then either state what the record
                now shows as the correction, or drop it and say why
  unsupported   nothing in the record shows it; say what is missing. It is
                never written as fact: the person decides whether it is kept,
                marked unverified

  already-written  a later session would find it by itself; say where, and it
                   is not promoted
  observed      something you saw and could not explain; cite what you saw. It
                is never written as fact; the person sees it

The person's words and a tool's output show what happened; the agent's own
words show what it believed at the time. An item bound for the always-loaded
tier needs the strictest check: supported, with at least one cited line that is
the person's words or a tool's output. It comes from a correction or a gap in
context, with the incident behind it; a general lesson with no incident is not
promoted there. A correction bound there is written as an item of its own,
supported by the line that corrects it, and an item whose source is a
correction cites at least one line in the person's own words.

Write a concise markdown summary of candidate documentation updates to:
  $draft_file

Begin the file with this line, exactly, so the review can find the record:

  transcript: $transcript_path

Then one section per item, in this shape:

  ### <one-line claim>
  - plain: <the claim as one everyday sentence; the person reads this first>
  - source: correction | missing-context | general
  - tier: <tier name>
  - scope: shared | individual
  - destination: <the specific file or directory>
  - why this tier: <one sentence; say what would go wrong at a cheaper tier>
  - check: supported | contradicted | unsupported | already-written | observed
  - evidence: L<n> "<a span copied exactly from line n of the transcript>"
  - was: L<n> "<what the record said first>"            (contradicted only)
  - correction: <what the record shows>                 (contradicted, kept)
  - dropped: <why>                                      (contradicted, dropped)
  - missing: <what would support it>                    (unsupported only)
  - found: <where a later session would find it>        (already-written only)

  <the note itself, one to three sentences>

L<n> is the line number the Read tool shows for the transcript. The span is
copied exactly from that line and short enough to read at a glance, twenty words
at most. Give as many evidence lines as the item needs. Inside the quotes, write
a quotation mark as \\" and a line break as \\n; anything after the closing quote
is a note and is ignored. A scheduled run's prompt counts as a turn and can be
cited.

Leave in-repo documentation to the person; this run writes only the scratch summary
file. You are proposing; a human approves the tier before anything is promoted.

If nothing durable was learned and you saw nothing you could not explain, do
not create the file at all. If you saw something you could not explain, write
the file with that one item, as observed.${team_section}${conventions}
EOF

# (8) Spawn fully detached so the human's session exit is never blocked.
# Blast radius is bounded deliberately: Read, Grep and Write only (Grep reads nothing Read cannot), and the child runs
# from the draft directory, so writes to the repository fall outside the
# directories acceptEdits auto-approves. --add-dir adds to the working directory
# rather than restricting it, which is why the cd matters: spawned from the
# project, the whole repo would be auto-approved. The transcript's directory is
# the one grant beyond the draft directory (readable and, under acceptEdits,
# writable; the child is prompted to write only its draft — see DESIGN.md).
# The child is a session of its own, so it starts without the ending session's identity. A session
# inside a pairing carries PAIR_* (its role and mailbox), and every Claude Code session carries its own
# id and messaging variables; inherited, they made a child act as the pairing's engineer, which
# consumed the mailbox's nudge. They are dropped, as the leave-out test runner drops them, and
# AW_HEADLESS_RUN quiets the session-start lines nobody is there to read.
clean_env=(-u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION
           -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_BRIDGE_SESSION_ID
           -u CLAUDE_CODE_SESSION_ATTENDED)
while IFS= read -r v; do [[ -n "$v" ]] && clean_env+=(-u "$v"); done < <(compgen -e | grep '^PAIR_' || true)
child_args=(
    env "${clean_env[@]}" AW_HEADLESS_RUN=1 CLOSEOUT_HOOK_CHILD=1
    "$CLAUDE_BIN" -p "$PROMPT"
    --model "${CLOSEOUT_MODEL:-sonnet}"
    --permission-mode acceptEdits
    --allowedTools "Read,Grep,Write"
    --add-dir "$DRAFT_DIR"
    --add-dir "$(dirname "$transcript_path")"
)

cd -- "$DRAFT_DIR" 2>/dev/null || exit 0

# A resumed session can keep its id and so overwrite its earlier draft; clearing
# the marker restarts retention, so the new content is offered before any prune.
rm -f "$DRAFT_DIR/.seen.$(basename "$draft_file")"

# Prefer setsid for a clean full detach, but it is not on stock macOS (only via
# MacPorts/Homebrew) and is absent on a stripped hook PATH. Fall back to
# nohup + disown, which survives the parent session exit on any POSIX shell.
if command -v setsid >/dev/null 2>&1; then
    CLOSEOUT_HOOK_CHILD=1 setsid nohup "${child_args[@]}" >/dev/null 2>&1 < /dev/null &
else
    CLOSEOUT_HOOK_CHILD=1 nohup "${child_args[@]}" >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null || true
fi

exit 0
