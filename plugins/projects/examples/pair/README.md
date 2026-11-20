# Mailbox: <project name>

The product manager (PM, a Cowork or chat session) and the engineer (CC, a Claude Code session) talk
here, so the person directing them does not relay messages. The person reads both files whenever they
like; nothing here needs them unless a message says **For <person>**. Set up by `/projects:pair`.

## Files

Every file has one writer, so this folder can sit anywhere, including a folder that is copied between
machines: a file two machines change between copies would come back as two versions.

| File | Written by | Holds |
|---|---|---|
| `to-cc.md` | the PM | messages to the engineer, ids `PM-001`, `PM-002`, … |
| `to-pm.md` | the engineer | messages to the PM, ids `CC-001`, `CC-002`, … |
| `status-cc.md` | the engineer | the status it has set on each PM message |
| `status-pm.md` | the PM | the status it has set on each CC message |
| `gates.json` | the PM | the phase's gates: what done means, each with its check (below) |
| `KICKOFF.md` | the PM | the engineer's opening prompt; the launcher puts this machine's path for `{mailbox}` |
| `.cc-*` | the engineer's session | its id, its state (`working`, `waiting` with a watch running, or `stopped`, since when), its lock |
| `.pm-*`, `.closed` | the PM | its session and lock, the sealed copy of the gates and its seal record (`.pm-gates`), its check-in (`.pm-checkin`); `.closed` once the pairing is closed |
| `.aw-gone/` | either side's lock | what a shell that cannot remove files set aside on letting go; the next shell that can remove files here clears it |

Anything else here is a stray, such as a copy left by two machines writing one file: `pair.sh check`
names it.

## A message

Append only, newest last. Each side writes only its own files, and takes the next id with
`kit/plugins/projects/hooks/pair.sh post`, which reads the last id and appends under a lock, so two
writers never share one. Anyone else who writes to a file (a second session, the person) takes the
next free id the same way. Two messages under one id are two messages: `pair.sh check` and the
engineer's start hook name the id, and the later is read in full, not as an amendment.

```
## PM-007 · 2026-10-06 17:40 +0100 · Short title
The message.
Status: open
```

`Status: open` goes on a line of its own, last in the message, and is never edited afterwards. A reply is a new message in the other file that names the id it answers on its
first line (`Re: PM-007`).

**From another pairing.** A PM from another pairing writes here with `pair.sh post --from pm`, so it
takes the next free id like anyone else. Its title starts `Not from this pairing's PM:`, and it asks
for replies headed `Re: PM-NNN (other)`, so the engineer reads it apart from its own PM's brief and its
answer does not read as a reply to this pairing's PM. `post` warns that another PM holds this mailbox;
for such a message that is expected.

## Time

Every time written here comes from the system clock, never from an estimate: read it with `date`
each time. A header is written by `kit/plugins/projects/hooks/pair.sh post`, which stamps it itself, or
headed with the output of `date`; a header typed by hand, or dated later than the file it sits in, is named
by `pair.sh check`. Keep the clock synced with network time where the machine allows it. Write the UTC offset
with every time (`2026-10-06 17:40 +0100`, from `date '+%Y-%m-%d %H:%M %z'`), so times written on
machines in different zones still sort into the order things happened.

## Status

The reader of a message sets its status by appending one line to its own status file, never by
editing the message:

```
PM-007 · 2026-10-06 18:05 +0100 · done 4f2a91c
```

`kit/plugins/projects/hooks/pair.sh status --mailbox <this folder> --from cc --id PM-007 done 4f2a91c`
writes that line (`--from pm` for the PM). Without a shell, append it by hand. The last line for an
id holds. A status:

- `open` — not yet dealt with (the writer sets this). A message with no status anywhere counts as open.
- `done <time> <commit or note>` — finished.
- `declined <why>` — not doing it.
- `waiting <on what>` — blocked; the PM or the person has the next move.

## Gates

What done means for a phase is a list of gates in `gates.json`, written by the PM with the brief, so
"done" is a set of checks rather than a sentence in a report:

```json
{ "gates": [
  { "id": "G1", "what": "CI is green on the pull request", "check": "gh pr checks <n>",
    "by": "pm", "passes": false, "evidence": "" } ] }
```

`id`, `what`, `check` and `by` are fixed once the brief is posted: the PM's first post with the file in
place seals them, and `pair.sh gates` refuses a list whose fixed part has changed since, naming what
changed. A gate is not made easier or dropped along the way; when the PM changes the list on purpose, it
seals it again with `pair.sh gates --mailbox <this folder> --from pm --seal`. `by` says who sets
`passes`: `pm` (the default), `cc`, or `person`, which the PM records on the person's word.

- `pair.sh gates --mailbox <this folder>` prints each gate and how many pass. The engineer's opening
  context and the PM's `pair.sh check` carry the count (`Gates: 4 of 6 pass`).
- **The engineer** never edits `gates.json`. It records evidence, which proposes a pass, as a line in
  its own status file: `pair.sh gates --mailbox <this folder> --from cc --id G1 <evidence>` writes
  `gate G1 · <time> · <evidence>` to `status-cc.md`. For a `cc` gate that line is the pass.
- **The PM** checks the evidence against its primary source (the CI run itself, the page, the file),
  not against the report, and sets the gate: `pair.sh gates --mailbox <this folder> --from pm --id G1
  pass <what it saw>`, or `fail`.

## How each side keeps up

- **The engineer** checks `to-cc.md` at the start of each piece of work, at each gate and before it
  reports done. Between turns a background command it starts watches the file and wakes it when a
  message arrives. The watch holds nothing: the session stays free for the person to type into.
  The first time the watch or a hook points it at a message, `status-cc.md` gains a `received <time>` line
  for that id, so the PM sees how long the message waited. A `received` line is a pickup record, not a
  settlement: the message stays open until a status line says otherwise.
- **The PM** is a Cowork session by default, which checks back by a scheduled message into its own
  conversation. A Claude Code PM, the fallback, is started with `pair.sh <folder> --pm` and runs
  `pair.sh watch --role pm` as a background command, which wakes it when a CC message arrives. Either way
  it reads `pair.sh check` before saying anything about the engineer, and tests what the engineer reports
  before accepting it.
- **Scheduled tasks are recorded here.** Each one the PM creates for the pairing (a check-in, a
  follow-up) has its id in `.pm-checkin` and a line in the PM's next message saying what it is and when
  it fires. The engineer's write-ups take what is scheduled from there, so the two accounts agree.
- A message that cannot wait for a check goes to the person directly.

## Closing out

A closeout keeps what a session learned; it does not end the pairing (that is the PM's last message
and `.closed`). When the person runs closeout in the PM's session, the engineer closes out first and
the PM last, so no file is written by both:

- The PM posts a message titled `Close out` before it writes anything durable.
- The engineer closes out its own session straight away. It writes what is its own: the code
  repository it works in and its notes in the project's handoff folder. The shared files are the PM's:
  the project's decisions log, its README's Current state, the workspace's memory and logs. An entry
  the engineer has for one of those goes in its reply, for the PM to write.
- It replies with a `CC-NNN` titled `Closed out`, listing every file it wrote and every entry it
  proposes, and sets the `Close out` message done.
- The PM then writes the shared files, and leaves alone every file the engineer listed. An engineer
  whose session has stopped does not hold the PM up: the PM closes out and tells the person which
  engineer still needs it, with the command that resumes it.

A closeout run in the engineer's own session closes out that session only, and says so in one line.
Closing out the PM is the person's call.

## Commands handed to the person

A command the person pastes into a terminal is written to survive the paste: each line about 70
characters at most, a long command broken with a trailing `\`, variables set on lines of their own,
anything longer in a script they run with one short line, and the output to expect shown beside it.
A terminal returns a wrapped line as several, and each runs as a command of its own.

## From Cowork

A manager in Cowork runs the mailbox commands itself, in Cowork's Linux shell, with this folder's path
as that shell sees it (under `~/mnt/`): `post`, `status`, `gates` (passes, fails and seals) and `check`.
It passes its token from `.pm-session` as `--pm` on each write, so a seal records the session that made it:

```
bash <kit>/plugins/projects/hooks/pair.sh post \
  --mailbox <mailbox> --from pm --pm <token> \
  --title "<title>" <<'EOF'
<the message>
EOF
```

That shell may make and rename files in a connected folder but not remove them. The lock lets go there
by renaming its file into `.aw-gone/` in this folder, and the next shell that can remove files clears
it; a shell that can do neither is turned away before it takes anything. A lock whose holder stopped on
another machine (a Cowork session that ended mid-write, say) is taken over once it is two minutes old,
since that machine's processes cannot be checked from here. No lock waits on anyone's hands.

`check` in Cowork reads the engineer's state from the activity beat and the end mark: the engineer's
process is on the person's computer, which Cowork cannot see, and the line says so.

**Re-sealing the gate list.** When the PM changes `gates.json` on purpose, it seals it again itself
(`pair.sh gates --mailbox <mailbox> --from pm --pm <token> --seal`). Nothing waits on the person, and
nothing is silent: `.pm-gates` records each re-seal with when, by which PM session and what changed;
`pair.sh check`, `pair.sh gates` and the engineer's session-start line list every one; and the PM names
it, with what changed, in its next message to the engineer and its next report to the person.

**What still goes to the person.** Commands that act on their computer rather than on this folder:
launching or resuming the engineer (`kit/plugins/projects/scripts/pair.sh <project folder>`), `watch`,
`join`, `leave`, `where` and `default`, and anything else that runs there, such as the project's tests.
`pair.sh` run in Cowork's shell for one of these stops at once and says to hand it over. The manager
writes each out in full, with the computer's absolute paths, kept to the paste rule above.

## Shared files

A file several sessions edit (a claims board, a locks file) is changed with
`kit/plugins/projects/scripts/registry.sh add|remove|replace`, which locks it, keeps its header and
renames the result into place, rather than with a hand-written `sed` or rewrite.

## Standing rules

<quoted from the workspace's and the project's own guidance by /projects:pair>
