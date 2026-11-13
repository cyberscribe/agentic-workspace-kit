# ongoing — keep up what has no finish line

A Claude Code plugin for **ongoing areas**: a practice, a responsibility, a collection,
anything kept up rather than finished. Forcing such work into a project gives it a finish
line that is never crossed and a card that is always stale. An area is the other kind of
thing, kept in its own README with the same machinery as a project and a different
measure. Five commands:

| Command | What it is for |
|---|---|
| **`/ongoing:new`** | Start an area: a short interview for its desired state, the standards to keep, people, cadence and versioning, then its README and register row, and an offer to put the check-in on a schedule at the area's cadence. |
| **`/ongoing:review [slug]`** | The check-in: walk each standard with the owner, note what is met and what slipped, and turn a slipped standard whose fix has an end into a project. |
| **`/ongoing:adopt <folder>`** | Give an existing folder, or a long-running project with no real finish line, the area's shape as small insertions. |
| **`/ongoing:pause [slug]`** | Set an area dormant — seasonal or set aside — with a reason and a date to look again. |
| **`/ongoing:drop [slug]`** | Archive an area that is no longer relevant, with its reason, its child projects settled. |

## Project and area

| | Project | Ongoing area |
|---|---|---|
| Lives in | `projects/<slug>/` | `ongoing/<slug>/` |
| Register | `projects/INDEX.md` | `ongoing/INDEX.md` (Active / Dormant / Archived) |
| Template | `templates/project-readme.md` | `templates/area-readme.md` |
| What you want | **Desired outcome** — a finish line | **Desired state** — a direction, kept true |
| Measured against | **Done when** — finished when every box is ticked | **Standards to keep** — healthy while they are met |
| `State:` | ready · doing · blocked · paused · done | active · dormant · archived |
| Stale when | `Updated:` is older than the team's staleness setting | its own `Check-in:` cadence has passed; never while dormant |
| In-flight limit | counts | does not count |
| Commands | `/projects:*` | `/ongoing:*` |

The title's `Versioned:` and `Sensitivity:` lines, the Current state labels, People and
its five roles, Resources and Working conventions are the same, so the same readers find
them. The two kinds meet in the area's **Projects** section: when a piece of an area has a
finish line — a season's repot, an exam — that piece is a project, started with
`/projects:new`, whose What this is names the area. A small one may sit inline under the
area until it earns a folder. `/projects:board` lists areas in a section of their own.

## Your conventions

The commands read `.claude/projects.md` first, as the projects commands do. Its **Areas**,
**Area register** and **Area template** lines move areas anywhere; the example conventions
in the projects plugin show them.

## Install

From a kit workspace, setup installs it with the other plugins. On its own:

```
/plugin marketplace add cyberscribe/agentic-workspace-kit
/plugin install ongoing@agentic-workspace
```
