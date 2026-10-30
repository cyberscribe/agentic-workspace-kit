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
| `KICKOFF.md` | the PM | the engineer's opening prompt; the launcher puts this machine's path for `{mailbox}` |
| `.cc-*` | the engineer's session | its id, its state (`working`, `waiting` with a watch running, or `stopped`, since when), its lock |
| `.pm-*`, `.closed` | the PM | its session and lock; `.closed` once the pairing is closed |

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

## How each side keeps up

- **The engineer** checks `to-cc.md` at the start of each piece of work, at each gate and before it
  reports done. Between turns a background command it starts watches the file and wakes it when a
  message arrives. The watch holds nothing: the session stays free for the person to type into.
  The first time the watch or a hook points it at a message, `status-cc.md` gains a `received <time>` line
  for that id, so the PM sees how long the message waited. A `received` line is a pickup record, not a
  settlement: the message stays open until a status line says otherwise.
- **The PM** runs `pair.sh watch --role pm` as a background command, which wakes it when a CC message arrives, and
  reads `pair.sh check` before saying anything about the engineer. A Claude Code PM is started with
  `pair.sh <folder> --pm`; a Cowork PM checks on a schedule instead. Either way it tests what the engineer
  reports before accepting it.
- A message that cannot wait for a check goes to the person directly.

## Commands handed to the person

A command the person pastes into a terminal is written to survive the paste: each line about 70
characters at most, a long command broken with a trailing `\`, variables set on lines of their own,
anything longer in a script they run with one short line, and the output to expect shown beside it.
A terminal returns a wrapped line as several, and each runs as a command of its own.

## Shared files

A file several sessions edit (a claims board, a locks file) is changed with
`kit/plugins/projects/scripts/registry.sh add|remove|replace`, which locks it, keeps its header and
renames the result into place, rather than with a hand-written `sed` or rewrite.

## Standing rules

<quoted from the workspace's and the project's own guidance by /projects:pair>
