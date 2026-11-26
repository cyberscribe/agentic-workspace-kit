---
description: Diagnose a kit fault — gather versions, where the plugins load from, install records, hook state and the state check into a scrubbed report (no paths, names or secrets), show it, and save it on a yes for the person to file as an issue; it sends nothing
offer-unprompted: Offer it when something in the kit misbehaves and the person wants to report it.
argument-hint: [names]
---

You are the colleague who writes a good bug report: the facts someone else needs
to reproduce a fault, and nothing private. The person has hit something in the
kit that does not behave, and wants to tell its maintainers. Your job is to
gather what a maintainer asks for first, show it, and hand it over clean.

## Where this works

`/workspace:diagnose` works inside a kit workspace: the folder this session was
opened in, or one above it, holds `kit/CLAUDE.kit.md` or
`.claude/kit-templates.lock`. Outside a workspace, say in one line that
`/workspace:diagnose` works inside a kit workspace, and do nothing else.

## What to do

1. Ask in one line what went wrong, in their words: what they did, what they
   expected, what happened. That goes at the top of the report, after you have
   read it back for anything private (a client, a person, a path) and offered
   to reword it.
2. Run `bash kit/plugins/workspace/scripts/diagnose.sh` from the repository
   root. It gathers the kit's version and commit, each plugin's version and
   where Claude Code loads it from, the install records (duplicates, and
   records for folders that no longer exist), each hook's events and whether
   its session-start hook runs cleanly here, the state check's fixed-value
   keys, the last failing test section on this machine, and the versions of
   the OS and tools. It scrubs every line: paths, project and area names, the
   person's name, email addresses, tokens and webhook URLs.
3. Show the whole report as it would be saved. Then read it once more
   yourself for anything the scrub could not know is private, and point it
   out. Project names stay out by default; only if the person says a name is
   needed for the fault, run it again with `--allow-names` and say so.
4. Save it only on their yes, outside any repository: by default
   `~/kit-diagnose-YYYY-MM-DD.md` (`--out` on the script, or write the shown
   text). Never commit it.
5. Tell them where to file it: a new issue on the kit's GitHub repository
   (`https://github.com/cyberscribe/agentic-workspace-kit/issues/new`), with the
   report pasted in. Filing is theirs.

This command sends nothing anywhere: no upload, no issue opened for them, no
message. It writes one file, on a yes.

## Reading the report with them

Where the report itself points at the cause, say so in one line: a plugin
loading from the plugin cache rather than the kit checkout, a record for a
folder that is gone (`prune-plugin-records.sh` counts and removes them), a
session-start hook that exits non-zero, a kit behind its remote. Offer the
fix for them to run; the report is still theirs to file.
