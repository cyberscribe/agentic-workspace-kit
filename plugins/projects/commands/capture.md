---
description: Capture something the team should see into the inbox in one line, with no questions asked — it is decided at the next review, not now
offer-unprompted: Offer it when something the team should see comes up in passing and nobody is acting on it now.
argument-hint: [what to capture]
---

You are the colleague with the notepad in a busy meeting. Someone says "we should
look at that" and you write it down, in their words, in the place everyone will
look later, and the conversation carries on without a pause. Capture is fast
because deciding is not its job: the inbox is where things wait, safely, until
the review decides what each one becomes. A capture that costs a question costs
the next one too, so you ask nothing you can find out for yourself.

The inbox is tracking. It is reconciled at the review and kept empty, never
promoted into reference. What the person captures is theirs to phrase; you record
it, you do not improve it.

## Project conventions come first

If `.claude/projects.md` exists in this repository, read it before anything else
and follow it over the defaults here — above all its **Captures** line, which says
where captures go, and where active projects live.

- A path (`work/inbox.md`) is the inbox; use it instead of the default.
- Something that is not a file in this repository — captures returned in a given
  format for a personal system, say — is followed as written: give the capture back
  in that form, write nothing to the repository, and stop there.
- No conventions file, or no Captures line: the inbox is `inbox.md` at the
  repository root.

## What to capture

What the user typed after the command (it follows this prompt) is the capture —
or, where this runs as a skill, what they asked to have captured.

- **Nothing typed** — ask once, in a few words: "What should I capture?" Their
  reply is the capture. If they give nothing again, leave the inbox as it is and
  say so in a line.
- **One thing** — one line in the inbox.
- **Several things** — a list, or one per line — one inbox line each, in the order
  given. A single sentence with an "and" in it is one thing.

Keep their words. Trim a leading dash or bullet and surrounding space, and join a
line broken only by wrapping; change nothing else — no rewording, no tags, no
guessed project name added in front.

## Writing the line

Each capture is one line, in this form, appended at the end of the inbox:

```
- [YYYY-MM-DD] <text> — <who captured>
```

- **The date** is today, absolute, in the person's local time.
- **Who captured** is the name in `git config user.name`. On a surface without git,
  use the name the person has given in this conversation or that the workspace
  knows them by; failing both, write `not recorded`. This is not worth a question.
  The name always follows the line's last ` — `, which is how the review reads it,
  so a dash inside the text is safe.
- **The file.** Append after the last line, leaving everything above it exactly as
  it was, and make sure the file ends with a newline. When the inbox holds no
  captures yet, leave one blank line between its header and the first. If the
  inbox does not exist yet, create it with this header, a blank line, and then the
  line:

  ```
  # Inbox

  Things the team should see, one line each — `- [YYYY-MM-DD] <text> — <who captured>` — added by `/projects:capture`, emptied line by line at `/projects:review`.
  ```

- **If you cannot write files here** — a chat surface with no access to the
  repository — give the exact line, ready to paste into the inbox, and say where
  it goes.

Then confirm in one line, with the count now waiting:
`Captured to inbox.md (4 waiting): Ask legal whether exports are covered by the new retention rule.`
For several captures, one line naming how many were added and the new count.

## When it plainly belongs to one project

After writing the capture, look at the active projects — the folders where the
conventions file keeps them (else `projects/`) and any the register lists as
active — skipping any whose Now block reads `State: done` or `parked`. If exactly
one of them is plainly what the capture is about — it names the project, its slug
or folder, or something only that project's README talks about — add one more
line offering to put it there instead:

`This looks like vendor-review — say "move it" and it goes to that project's Next up, out of the inbox.`

Plainly means you would be surprised to be wrong. The folder the session is
running in counts as a hint, never on its own as the answer. Two projects that
could fit, or a guess, means no offer: the review sorts it. The capture is already
safe in the inbox, so the offer costs nothing if it is ignored.

If they say yes:

- Add the text as the last item of that project's **Next up** list, numbered to
  follow the items there, in the README (or the entry point the conventions file
  names). A leading project name used only to address it ("vendor-review: check…")
  is dropped; the rest stays in their words. If there is no Next up section,
  insert one straight after the Now block and its dated line, at the heading level
  of the README's other sections, holding this one item.
- Remove that line — and only that line — from the inbox.
- Leave everything else in the README as it was. The Now block is not touched: a
  Next up line is not a change to where the project stands.
- Confirm in one line: `Moved to vendor-review → Next up (3 waiting in the inbox).`

## Practices

- **Write first, offer after.** The inbox line is written before any offer, so
  walking away at any point loses nothing.
- **No sorting now.** Whether it is a project, a next action, something waited
  on, parked, reference or nothing is the review's decision, made with the person.
  Capture does not guess at it, and does not judge whether it belongs here.
- **One line out.** The confirmation is one line; the offer, when there is one, is
  a second. No summary of the inbox, no suggestions.
- **Nothing beyond the working tree.** The line is written to the file and left
  there. Nothing is committed, pushed or sent; committing is theirs, with their
  own message.
