# Project conventions — __TEAM__

Read first by every projects command (`/projects:new` and the rest of the projects plugin, on Claude
Code and as skills alike) and followed over the plugin's own defaults. It holds the kit's defaults
until the team changes them; `/workspace:quick-start` asks about the lines marked "not set yet".

Keep it prose. There is no schema: the commands read it as written, so a line changed here changes
what they do. Each setting is one line with its value in backticks, which keeps it easy to read for a
person and easy to find for a script.

## Where projects live

- **Active:** `projects/<slug>/` — one folder per project, its `README.md` the entry point.
- **Paused:** `projects/<slug>/` — the folder stays where it is and stays versioned; its register row
  moves to the Paused section (`/projects:hold`).
- **Done:** `projects/_done/<slug>/` — `/projects:close` moves the folder here, keeping history:
  `git mv` for a project tracked by the workspace or its own repository, and a plain move plus a
  `.gitignore` line for an untracked one.
- **Entry point:** `README.md` in the project folder; a folder with no README but a `CLAUDE.md` of its
  own uses that. The commands, the session-start line and the metrics all read them in this order.
- **Register:** `projects/INDEX.md`, with the sections `Active`, `Paused` and `Done`. The READMEs are
  canonical; where the register disagrees with one, the README wins and the register is corrected.
- **Folder moves:** `the command` — `/projects:close` and `/projects:hold` make the move they show, on
  a yes. The other value, `the person`, prints the commands for a person to run instead.
- **Reserved folders:** folders directly under `projects/` whose names start with `_` or `.` are not
  projects (`_done`, `_delete`).
- **Not adopted:** none — project folders whose README is not a project README, such as a published
  site's home page. Name them here in backticks, joined by commas; the adopt command is not offered
  there unprompted, and asks before it writes there.

## How projects are kept

- **Versioned default:** `workspace` — what `/projects:new` offers first. The other ways are
  `own-repo` (the folder is its own repository, added as a submodule) and `untracked` (the folder is
  listed in `.gitignore`). Each README says which, on its `Versioned:` line.
- **Sensitive projects:** a project whose README says `Sensitivity: sensitive` is `untracked` or its
  own private repository. The workspace's git hooks refuse to stage its files, and the board flags one
  the workspace still tracks.

## Names

- **Slug:** lowercase words joined by hyphens, short enough to type — `vendor-review`, not
  `2026-q3-vendor-review-project`.
- **Folder prefix:** none. The folder name is the slug.

## Pace

- **In-flight limit:** `3` — how many projects one person has in the `doing` state at once. A
  person's own profile can set a different number. Going over it is advice to talk about, not a
  block.
- **Counting in flight:** a person's count is the active projects whose Current state block reads
  `State: doing` and whose People section names them as **owns** or **does** — or, where a README
  has no People section, whose register Owner is them. Their profile is the file in the people
  directory matching their name. The projects commands, the board and the metrics all count this
  way.
- **Default owner:** none — a name here in backticks owns every project that has no People section
  and no register Owner, as a one-person repository might want.
- **Staleness:** `1 week` — how old a project's `Updated:` date can get before the board flags it
  as stale. A project's own `Check-in:` is its own rhythm for looking at it, and the board does not
  measure against it.

## Where things go

- **Project template:** `kit/templates/project-readme.md`
- **People:** `memory/people/<name>.md`, from `kit/templates/person-profile.md`; the name is the
  person's full name, lowercase, joined by hyphens — `memory/people/priya-shah.md`
- **Catalogue of reusable work:** `docs/catalogue.md`, if the team keeps one, started from
  `kit/templates/catalogue.md`
- **What counts as checked:** `docs/verification.md`, if the team has adopted one, started from
  `kit/templates/verification-standard.md`
