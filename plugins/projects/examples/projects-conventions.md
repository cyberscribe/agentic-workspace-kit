# Example `.claude/projects.md`

Copy this to `.claude/projects.md` in a consuming repository and rewrite it for your
team. Every projects command reads it first, before doing anything else, and follows
it over the plugin's own defaults — the same way the closeout plugin reads
`.claude/closeout.md`.

Keep it prose. There is no schema: the file is read as written. Two habits make it
work well:

- **One setting per line, value in backticks.** People read it at a glance, and a
  script (a session-start hook, a metrics run) can find a value without guessing.
- **Only what differs.** Anything you leave out falls back to the plugin default, so
  a three-line file is a perfectly good one.

The defaults, for comparison: active projects in `projects/<slug>/`; paused and
finished projects stay where they are and move sections in `projects/INDEX.md`
(Active / Paused / Done); lowercase hyphenated slugs with no prefix; an in-flight
limit of 3; a project flagged stale when its `Updated:` date is more than a week
old; the README from `templates/project-readme.md`.

Everything below the line is the example itself — a team that files work by status
folder, uses a priority prefix, and lets a project go two weeks between updates.
The quoted notes explain each choice; delete them in your copy.

---

# Project conventions

## Where projects live

- **Active:** `work/<slug>/`
- **Paused:** `work/_paused/<slug>/` — the folder moves, so a paused project is
  out of sight in everyday listings.
- **Done:** `archive/<year>/<slug>/` — moved when the project closes, by the
  person closing it.
- **Register:** `work/README.md`, with the sections `In flight`, `On hold` and
  `Shipped`.
- **Section names:** the Done when list is headed `Exit criteria` in older
  READMEs.

> Name your register's own sections here, and the commands use them rather than
> Active / Paused / Done. The same goes for a README section your team calls
> something else: the board, the session-start line and the metrics look for
> `Done when` and `People` by heading, and read the names given here too. Each
> sentence names the section it is about and backticks only heading names, since
> every backticked word in it is read as one. Moving folders between states is a
> choice; leaving them in place and moving only the register row keeps every
> link working.

## Names

- **Slug:** lowercase, hyphens, no dates — the date lives in the README.
- **Folder prefix:** a two-digit priority, `01-` to `09-`, set by the team lead.
  It is not part of the project's name: `work/03-vendor-review/` is the project
  `vendor-review`. Commands never add, change or strip a prefix on their own.

> A prefix that encodes something (priority, client, quarter) needs saying here,
> or a command will read it as part of the name.

## Pace

- **In-flight limit:** `2`
- **Staleness:** `every 2 weeks` — how old a project's `Updated:` date can be
  before the board flags it.

> The in-flight limit is a team default; a person's profile can carry their own.
> It is advice the commands raise, never a block. A person's count is the active
> projects in `doing` whose People section names them as **owns** or **does**
> (the register's Owner, where a README has no People section); say so here if
> your team counts differently.

## Where things go

- **Project template:** `.github/templates/project.md`
- **People:** `team/<name>.md`
- **Catalogue of reusable work:** `docs/catalogue.md`
- **What counts as checked:** `docs/verification.md`

## House rules

- Every project names one owner in its People section before it leaves `ready`.
- A project touching customer data links its data-handling note from Read before
  acting.

> Anything prose can say goes here. The commands follow it as they would a line
> from a teammate who knows how this team works.
