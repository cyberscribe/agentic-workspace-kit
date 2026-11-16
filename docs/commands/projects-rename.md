# /projects:rename

*Renames a project: a new slug and title for its folder, README, register row and resource map, with
every path that named the old folder shown and updated on a yes. Source:
`plugins/projects/commands/rename.md`.*

## What it does

- Reads `.claude/projects.md` first: locations, the register, the entry point, a folder prefix, and the
  **Folder moves** line.
- Takes the project and the new name from the command (`/projects:rename pilot-study Field trial`), or asks.
  The slug comes from `scripts/slug.sh`; a priority prefix on the folder stays.
- Stops before any edit when the new folder exists, or a pairing is still open on the project.
- Moves the folder the way the project is versioned: `git mv` for a tracked folder or a submodule, the
  `.gitignore` line first and then `mv` for an untracked one.
- In the README: the title, `Updated:` today, a dated line `<today> — Renamed from <old> to <new>.`
  above the latest one, and its own old paths. The old name in its prose is listed, not changed.
- Updates the register row's name and link, and this machine's `.claude/resources.local.md`, then runs
  `kit/setup.sh link <new slug>`.
- Lists folders outside the repository named for the old slug (a Drive folder, say) and moves them on a
  separate yes where it can reach them.
- Rewrites path references in other current files on a yes; leaves logs, changelogs, retrospectives and
  dated lines as they were.

## When to reach for it

When a project's name has drifted from the work: the pilot study that became a field trial, the side
project that became the programme. For a change to how a project is versioned, use `/projects:adopt`.

## Common questions

**Why not just `git mv` the folder?** The register row, the resource map, the `.resources/` links and
any note pointing at the old path would all still name it. The command finds them and moves them
together.

**Does it rewrite the decisions log?** No. A log records what was true when it was written; a path
there to the old folder is history.

**What about other machines?** `.claude/resources.local.md` is per machine and not committed. The
command says so; on each other machine, the session-start line offers the mapping again until it is
done.

**Does it run in Cowork?** Yes, as the `kit-projects-rename` skill that `kit/setup.sh skills` writes. In
Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- `grep -rF '<old folder>/'` over the repository, leaving out `.git` and the history records, finds
  nothing.
- `/projects:board` shows the project under its new name, with its done-when progress unchanged.
- The session-start line in the new folder names the project and no unmapped resources.
