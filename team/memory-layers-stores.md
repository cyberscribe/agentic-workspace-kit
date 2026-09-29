## 3. Where each type lives

> Pre-filled for a team working in Claude Code (and, where a team uses one, a skills folder or Gemini
> CLI) from one shared repository. Adjust it to the stores you actually use; every store appears in
> exactly one cell per row.

| Type | Shared — committed, reaches the team | Individual — one person, one machine |
|---|---|---|
| Working standards | `AGENTS.md` (Claude Code reads it through `CLAUDE.md`; with `--surfaces claude,gemini`, Gemini CLI through `.gemini/settings.json`) | `~/.claude/CLAUDE.md`, and each other surface's own file |
| General reference | `docs/` (including `docs/catalogue.md` and `docs/verification.md` once the team keeps them), `memory/glossary.md`, `memory/people/`, `memory/context/` | Claude Code auto-memory under `~/.claude/projects/`, holding a **pointer** at most |
| Project reference | `projects/<slug>/` — canonical — and the project's own `decisions.md` | Per-surface memory, holding a **pointer** to the project folder |
| Templates | `templates/`, `rituals/`, `.claude/agents/`, `.claude/commands/` (and `.gemini/commands/` where Gemini CLI is installed) | `~/.claude/agents/`, `~/.claude/commands/`, the skills folder `install.sh --skills-dir` writes for a desktop assistant |
| *Tracking (other axis)* | Each project README's **Current state** block, `projects/INDEX.md`, `pilot/build-list.md` | None; the kit keeps tracking shared |

Closeout drafts written by the plugin's end-of-session hook live in `~/.claude/closeout-drafts/` —
individual by design. They reach the team only when someone promotes them, by pull request, into a
shared cell above.

