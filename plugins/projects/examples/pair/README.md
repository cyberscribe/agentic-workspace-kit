# Mailbox: <project name>

The product manager (PM, a Cowork or chat session) and the engineer (CC, a Claude Code session) talk
here, so the person directing them does not relay messages. The person reads both files whenever they
like; nothing here needs them unless a message says **For <person>**. Set up by `/projects:pair`.

## Files

- `to-cc.md` — messages from the PM to the engineer, ids `PM-001`, `PM-002`, …
- `to-pm.md` — messages from the engineer to the PM, ids `CC-001`, `CC-002`, …
- `KICKOFF.md` — the engineer's opening prompt, sent by the launcher.
- `.cc-session`, `.cc-state` — written by the engineer's session: its id, and whether it is
  `working`, `waiting` (a watch on this mailbox is running) or `stopped`, since when.
- `.closed` — present once the PM has closed the pairing.

## A message

Append only, newest last. Each side writes only the other's file, and takes the next id with
`kit/plugins/projects/hooks/pair.sh post`, which reads the last id and appends under a lock, so two
writers never share one. Anyone else who writes to a file (a second session, the person) takes the
next free id the same way. Two messages under one id are two messages: `pair.sh check` and the
engineer's start hook name the id, and the later is read in full, not as an amendment.

```
## PM-007 · 2026-10-06 17:40 · Short title
The message.
Status: open
```

`Status:` goes on a line of its own, last in the message. Times are local. A reply is a new message in the other file that names the id it answers on its
first line (`Re: PM-007`).

## Status

The reader of a message sets its `Status:` line — the only edit made to an existing message:

- `open` — not yet dealt with (the writer sets this). A message with no `Status:` line counts as open.
- `done <time> <commit or note>` — finished.
- `declined <why>` — not doing it.
- `waiting <on what>` — blocked; the PM or the person has the next move.

## How each side keeps up

- **The engineer** checks `to-cc.md` at the start of each piece of work, at each gate and before it
  reports done. Between turns a background command it starts watches the file and wakes it when a
  message arrives. The watch holds nothing: the session stays free for the person to type into.
- **The PM** checks `to-pm.md` every 30 minutes while anything is open, and tests what the engineer
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
