# /workspace:diagnose

*A fault report for the kit's maintainers, scrubbed of anything private, saved on a yes and never sent.
Source: `plugins/workspace/commands/diagnose.md`, with `plugins/workspace/scripts/diagnose.sh`.*

## What it does

- Asks what went wrong, in your words, and reads it back for anything private before it goes in.
- Runs `kit/plugins/workspace/scripts/diagnose.sh`, which gathers the kit's version and commit, each
  plugin's version and where Claude Code loads it from (the kit checkout, the plugin cache, the account),
  the install records (duplicates, and records for folders that no longer exist), each hook's events and
  whether its session-start hook runs cleanly (its exit status and how much it prints, never the text),
  the state check's fixed-value keys, the last failing test section on this machine, and the versions of
  the OS, bash, git, jq and Claude Code.
- Scrubs every line: the home folder becomes `~`, the workspace `<workspace>`, the kit `<kit>`, any other
  path `<path>`; tokens, keys and webhook URLs `<secret>`; email addresses `<email>`; your git name
  `<person>`; project and area names `<project>`. No workspace file's contents are read into it.
- Shows the whole report, points out anything the scrub could not know is private, and saves it outside
  any repository on your yes (`~/kit-diagnose-YYYY-MM-DD.md` by default).
- Tells you where to file it. Filing the issue is yours; the command sends nothing.

## When to reach for it

When something in the kit misbehaves and you want to tell its maintainers: a command that is not offered,
a session-start line that never appears, a hook that errors, setup or update stopping.

## Common questions

**Can a project name go in?** Only when the fault needs it and you say so: it runs again with
`--allow-names`.

**Does it fix anything?** No. Where the report points at the cause (a stale install record, a plugin
loading from the cache instead of the kit), it names the fix for you to run.

**Does it run in Cowork?** Yes, as the `kit-workspace-diagnose` skill that `kit/setup.sh skills` writes.
Without the `claude` command, the plugin lines say they were not read.

## It's working if

- The report names the kit version, each plugin and where it loads from.
- Searching it for your home folder, your name or a project name finds nothing.
- Nothing was sent: the only new file is the one you agreed to save.
