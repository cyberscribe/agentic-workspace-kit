# Team overlay

*The files `install.sh` adds when the kit is deployed as a team's shared workspace rather than one
person's. Each one is a source for the installer, not a file to copy by hand.*

| File | Lands at | What it does |
|---|---|---|
| `who-this-team-is.md` | §1 of `AGENTS.md` | Replaces the single-person profile with the team, its standards owner, and the rule that arbitrates team layer against personal layer |
| `memory-layers-stores.md` | §3 of `docs/memory-layers.md` | Fills in the stores table for a Claude Code + Gemini CLI team |
| `CLAUDE.md` | `CLAUDE.md` | A one-line import of `AGENTS.md`, so Claude Code reads the same file every other tool does |
| `closeout-conventions.md` | `.claude/closeout.md` | Points the closeout plugin (and the Cowork closeout skill) at `docs/memory-layers.md`, so there is one taxonomy rather than two |
| `claude-settings.json` | `.claude/settings.json` (merged) | Registers and enables the closeout plugin; lets the agent delete a promoted draft |
| `gemini-settings.json` | `.gemini/settings.json` (merged) | Makes Gemini CLI load `AGENTS.md` as its context file |
| `gemini-closeout.toml` | `.gemini/commands/closeout.toml` | `/closeout` for Gemini CLI — the live ritual, without the hook backstop |
| `CODEOWNERS` | `.github/CODEOWNERS` | Routes changes to the always-loaded tier through the standards owner |
| `pull_request_template.md` | `.github/pull_request_template.md` | Asks a documentation PR which tier it touches, and what it displaces |

The one file here that is genuinely the team's is §1 of `AGENTS.md`. Everything else is plumbing that
keeps several people and several agent surfaces reading the same thing.
