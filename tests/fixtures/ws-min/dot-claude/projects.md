# Project conventions — Test Team

The smallest set of project conventions the tests build on (tests/run.sh, mkws_min), with the 3.0
values. Each setting is one line with its value in backticks.

## Where projects live

- **Active:** `projects/<slug>/` — one folder per project, its `README.md` the entry point.
- **Paused:** `projects/<slug>/` — the folder stays where it is and stays versioned; its register row
  moves to the Paused section.
- **Done:** `projects/_done/<slug>/` — the folder moves here when the project closes, keeping history.
- **Entry point:** `README.md`
- **Register:** `projects/INDEX.md`, with the sections `Active`, `Paused` and `Done`.
- **Versioned default:** `workspace`
- **Folder moves:** `the command`
- **Reserved folders:** folders directly under `projects/` whose names start with `_` or `.` are not
  projects (`_done`, `_delete`).

## Pace

- **In-flight limit:** `3`
- **Staleness:** `1 week`

## Where things go

- **Project template:** `kit/templates/project-readme.md`
- **People:** `memory/people/<name>.md`, from `kit/templates/person-profile.md`
