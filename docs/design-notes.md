# Design notes

*Decisions about how the kit works that a reader of the code would otherwise have to reconstruct: what
was chosen, what it was chosen over, and what it lets through. Each note is dated; a later decision is a
new note that names the one it replaces.*

## The copy check's direction — 2026-11-11

**The problem.** The copy check (R5 in `scripts/check-paths.sh`) refuses a kit line of 60 characters or
more that is new to the kit and that a workspace file holds word for word, and a kit file whose content a
workspace file has. It could not tell which way a copy ran. A kit developer's workspace always holds
copies of the kit: a handoff note quoting it, a snapshot of a plugin taken for a comparison, a rendered
transcript of a session that worked on it. At the push, those made the kit's own new lines read as
copies of the workspace: on 2026-11-10 one push was refused 696 lines, every one of them a workspace
file that had copied the kit after the commits were made.

**The rule.** At the pre-push, content a pushed commit shares with a workspace file counts as a copy of
that file only when the file is shown to have held it no later than the kit commit that brought it in:

- The kit's time is the committer time of the earliest pushed commit that adds the line or the blob,
  not the tip's.
- The workspace file's time is its mtime, which shows it held its present content then. For a file the
  workspace tracks, the first workspace commit holding the line (or blob) also shows it, and the earlier
  of the two counts.
- A minute is allowed for clock skew, and a tie counts as held before: both fall on the refusing side.
- When several workspace files hold the line, any one that held it first refuses it. A line in an old
  private note and in a fresh snapshot of the kit is refused, naming the note.
- A file written after the kit commit shows nothing either way, and is read as quoting the kit.

The pre-commit is unchanged. It sees the workspace as the change is made, so a line it lets through was
not in the workspace then; that is what makes the push-time rule safe.

**What it lets through.** A line that reached the kit in a commit that skipped the pre-commit (a machine
with no hooks set), from an untracked workspace file that has been written to since that commit. Both
have to hold at once, and the workspace guard already refuses `--no-verify` from an agent.

**What it refuses that it need not.** A file copied into the workspace with its old mtime kept (`cp -p`,
a move from another folder) dates from before the kit commit, so it is refused. That is the safe
direction: `AW_ALLOW_COPY` names the kit path for one command, or the file can be touched once it is
known to quote the kit.

**The options it beat.**

| Option | Why not |
|---|---|
| A workspace file newer than the line's first kit appearance quotes the kit, at both hooks | At the pre-commit the line has no kit commit yet, so the comparison falls to working-tree mtimes, and a private note edited after a leak passes. The rule above is this one, kept to the push and using the workspace's history where the file is tracked. |
| Skip workspace folders marked as kit drafts | Path-based: the 2026-11-10 copies were under a project's records folder, not a drafts folder. A list of folders needs upkeep, and each entry widens what is never checked. |
| Content the kit's own history already holds is a copy of the kit, whatever its path | At the push, every pushed line is in the kit's local history, so this turns the push-time line check off. For history before the push it is already the rule: lines and blobs the remote has are never candidates. |
