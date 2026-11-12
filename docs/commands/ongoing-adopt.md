# /ongoing:adopt

*Gives an existing folder, or a long-running project with no real finish line, the shape of an ongoing
area, as small proposed insertions. Source: `plugins/ongoing/commands/adopt.md`.*

## What it does

- Reads `.claude/projects.md` first, then the folder named.
- For a project, reads its Done when: a real, near finish line stays a project. A list scoped to a
  milestone inside a longer practice is the common case: the practice becomes the area, and the
  milestone is kept word for word under the area's Projects section.
- Drafts what is missing in the area template's shape, each block marked
  `proposed by /ongoing:adopt <date>: confirm or edit`: the `Versioned:` and `Sensitivity:` lines,
  What this is, Desired state, Standards to keep (or `- not yet named`), the Current state block in area
  states, Projects and Recurring. A project's dated log stays below, as history.
- When the folder sits with the projects, shows the move to the areas location and splits the files
  that name the old path into live ones (scheduled tasks, settings, scripts, guidance) and history,
  which stays as written.
- Moves the register row to the area register, creating it if needed.

## When to reach for it

When a "project" has run for months with a finish line nobody believes in, or a folder of notes has
grown around a practice. `/projects:adopt` hands over to it when the person says a project is an area.

## Common questions

**Does it rewrite the README?** No. It inserts what is missing and marks it proposed; everything already
there stays as its authors wrote it.

**Who moves the folder?** The person, or the command on a yes. Where tools run from absolute paths into
the folder, it offers a link at the old path, kept out of git, until those are rebuilt.

**Does it run in Cowork?** Yes, as the `kit-ongoing-adopt` skill that `kit/setup.sh skills` writes.

## It's working if

- The README has a Desired state, Standards to keep and an area Current state block.
- The proposed markers are there for the owner to confirm.
- The area register lists it, and the project register no longer does.
