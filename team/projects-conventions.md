# Project conventions — __TEAM__

Read first by every projects command (`/projects:new` and the rest of the projects plugin, on Claude
Code and as skills alike) and followed over the plugin's own defaults. It holds the kit's defaults
until the team changes them; `/workspace:quick-start` asks about the lines marked "not set yet".

Keep it prose. There is no schema: the commands read it as written, so a line changed here changes
what they do. Each setting is one line with its value in backticks, which keeps it easy to read for a
person and easy to find for a script.

## Where projects live

- **Active:** `projects/<slug>/` — one folder per project, its `README.md` the entry point.
- **Paused:** stays in `projects/<slug>/`; its register row moves to Paused.
- **Done:** stays in `projects/<slug>/` with `State: done` in its README; its register row moves to
  Done. Nothing is moved or deleted, so links keep working.
- **Entry point:** `README.md` in the project folder; a folder with no README but a `CLAUDE.md` of its
  own uses that. The commands, the session-start line and the metrics all read them in this order.
- **Register:** `projects/INDEX.md`, with the sections `Active`, `Paused` and `Done`. The READMEs are
  canonical; where the register disagrees with one, the README wins and the register is corrected.

## Names

- **Slug:** lowercase words joined by hyphens, short enough to type — `vendor-review`, not
  `2026-q3-vendor-review-project`.
- **Folder prefix:** none. The folder name is the slug.

## Pace

- **In-flight limit:** `3` — how many projects one person has in the `doing` state at once. A
  person's own profile can set a different number. Going over it is advice to talk about, not a
  block.
- **Counting in flight:** a person's count is the active projects whose Now block reads
  `State: doing` and whose People section names them as **owns** or **does** — or, where a README
  has no People section, whose register Owner is them. Their profile is the file in the people
  directory matching their name. The projects commands, the board and the metrics all count this
  way.
- **Default owner:** none — a name here in backticks owns every project that has no People section
  and no register Owner, as a one-person repository might want.
- **Review cadence:** `weekly` — what the board's stale flag measures against; a project's own
  `Check-in:` is looked at by the review, not the board.
- **Review day:** `not set yet`

## Where things go

- **Captures:** `inbox.md` at the repository root — one line each, processed at the review.
- **Project template:** `templates/project-readme.md`
- **People:** `memory/people/<name>.md`, from `templates/person-profile.md`; the name is the person's
  full name, lowercase, joined by hyphens — `memory/people/priya-shah.md`
- **Catalogue of reusable work:** `docs/catalogue.md`, if the team keeps one
- **What counts as checked:** `docs/verification.md`, if the team has adopted one
