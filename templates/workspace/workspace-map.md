# Workspace Map

*The file-by-file layout, the canonical source for each kind of fact, and where new files go.*

> This workspace's own map, started from the kit's template and kept by the team. The always-loaded
> file keeps a high-level surface table; this file holds the detail, so it can grow without costing
> every session.

---

## Canonical fact locations

These files are the source of truth. Everything else points at them rather than restating them.
**Duplication is the mechanism by which drift happens** — two copies look equally authoritative and
age at different rates.

| Domain | Canonical file |
|---|---|
| The team, its standards owner and its conventions | `CLAUDE.md` §1–§4 |
| The kit's working standards | `kit/CLAUDE.kit.md` (the kit's; imported by `CLAUDE.md`) |
| Glossary, acronyms, internal vocabulary | `memory/glossary.md` |
| People | `memory/people/<name>.md` |
| Organisations and topics | `memory/context/<topic>.md` |
| Which store a durable fact belongs in | `kit/docs/memory-layers.md` |
| How guidance prose should read | `kit/docs/documentation-register.md` |
| Cross-project decisions | `logs/decisions.md` |
| Active projects | `projects/INDEX.md` |
| Project conventions | `.claude/projects.md` |
| End-of-session promotion conventions | `.claude/closeout.md`, with the ritual in `kit/rituals/closeout.md` |
| Remotes confirmed private, and other workspace settings | `.claude/workspace.md` |
| Per-tool conventions | `docs/<tool>-conventions.md` |
| Reusable document skeletons | `kit/templates/` |

## Filesystem

```
workspace/
  CLAUDE.md                ← the always-loaded file; line 1 imports kit/CLAUDE.kit.md
  AGENTS.md                ← points other tools at the same two files
  README.md                ← navigational entry point for humans
  kit/                     ← the kit, a submodule: read in place, updated with kit/setup.sh update

  .claude/
    settings.json          ← registers kit/ as the plugin marketplace
    projects.md            ← project conventions, read first by every projects command
    closeout.md            ← closeout conventions
    workspace.md           ← private remotes and other settings the git hooks read
    kit-templates.lock     ← which template each file above started from (written by the kit)

  docs/                    ← general reference, loaded on demand
    workspace-map.md       ← this file
    catalogue.md           ← what the team has built and can reuse (optional)
    verification.md        ← what counts as checked, per kind of work (optional)
    <topic>.md             ← one file per subsystem or convention

  projects/
    INDEX.md               ← the register: Active / Paused / Done
    <slug>/                ← one folder per project
      README.md            ← what, why, done when, the Current state block, open questions
      decisions.md         ← when the project earns one
    _done/<slug>/          ← finished projects

  skills/                  ← the team's own skills
  logs/
    decisions.md           ← cross-project decisions
  memory/
    glossary.md
    people/<name>.md
    context/<topic>.md     ← canonical cross-surface facts
  audits/                  ← dated reports from the periodic checks
```

## Conventions for new files

| Kind of content | Location |
|---|---|
| Per-project working files | `projects/<slug>/` — and a row in `projects/INDEX.md` |
| Something reusable the team has built | One line in `docs/catalogue.md` |
| Per-person notes | `memory/people/<name>.md` |
| Per-organisation or per-topic notes | `memory/context/<topic>.md` |
| Long-form drafts | `drafts/<slug>/` |
| Cross-project decisions | `logs/decisions.md`, after the strip filter |
| Project-specific decisions | `projects/<slug>/decisions.md`, from `kit/templates/project-decisions.md` |
| A skeleton of the team's own | `templates/<name>.md`, named in `.claude/projects.md` where a command reads it |
| Detail referenced from the always-loaded file | `docs/<topic>.md` |
| Material outside the repository | Named under `## Resources` in the project README, mapped per machine in `.claude/resources.local.md` |
| One-shot deliverables | Wherever your surface surfaces files; not in the durable tree |

If a referenced file does not exist yet, create it at first use. A documented-but-absent path is a
promise rather than a fault.

New guidance prose follows `kit/docs/documentation-register.md`.

## How file references are written

Prose names files in several ways that look alike and resolve differently. Write this section for your
own workspace early — a link checker run naively over a mature tree reports most references as broken,
and it will be wrong about nearly all of them.

| Form | Example | Resolves against |
|---|---|---|
| Relative path | `../sibling.md` | The directory of the referring file. The default. |
| Bare name, anaphoric | "…per `spec.md` §3" | A file named in full nearby. House style: give the path once, then the short name. |
| External codebase | `src/handler.php` | A repository outside this tree. Correct, and will never resolve here. |
| Documented, not yet created | `logs/experiments.md` | A file the conventions promise, awaiting a first use. |

Two consequences worth holding on to: a dangling reference is not automatically a defect, and any
automated check over references resolves the short-name form before calling anything absent.

## Surface ownership

Where more than one agent surface reads this tree, name which files each surface owns and which it
leaves alone. An unstated boundary becomes a quiet convention, and then a stale reference someone
debugs months later.
