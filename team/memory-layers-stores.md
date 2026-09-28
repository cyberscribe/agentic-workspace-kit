## 3. Where each type lives

> Pre-filled for a team working in Claude Code and Gemini CLI from one shared repository. Adjust it to
> the stores you actually use; every store appears in exactly one cell per row.

| Type | Shared — committed, reaches the team | Individual — one person, one machine |
|---|---|---|
| Working standards | `AGENTS.md` (Claude Code reads it through `CLAUDE.md`; Gemini CLI through `.gemini/settings.json`) | `~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md` |
| General reference | `docs/`, `memory/glossary.md`, `memory/people/`, `memory/context/` | Claude Code auto-memory under `~/.claude/projects/`, holding a **pointer** at most |
| Project reference | `projects/<slug>/` — canonical — and the project's own `decisions.md` | Per-surface memory, holding a **pointer** to the project folder |
| Templates | `templates/`, `rituals/`, `.claude/agents/`, `.claude/commands/`, `.gemini/commands/` | `~/.claude/agents/`, `~/.claude/commands/`, `~/.gemini/commands/` |
| *Tracking (other axis)* | `projects/INDEX.md`, `pilot/build-list.md` | Your own task system |

Closeout drafts written by the plugin's end-of-session hook live in `~/.claude/closeout-drafts/` —
individual by design. They reach the team only when someone promotes them, by pull request, into a
shared cell above.

