# Team overlay

*The files `install.sh` adds when the kit is deployed as a team's shared workspace rather than one
person's. Each one is a source for the installer, not a file to copy by hand.*

| File | Lands at | What it does |
|---|---|---|
| `who-this-team-is.md` | §1 of `AGENTS.md` | Replaces the single-person profile with the team, its standards owner, and the rule that arbitrates team layer against personal layer |
| `memory-layers-stores.md` | §3 of `docs/memory-layers.md` | Fills in the stores table for a team sharing one repository, with each README's Current state block under Tracking |
| `CLAUDE.md` | `CLAUDE.md` | A one-line import of `AGENTS.md`, so Claude Code reads the same file every other tool does |
| `closeout-conventions.md` | `.claude/closeout.md` | Points the closeout plugin (and the generated `closeout` skill) at `docs/memory-layers.md`, so there is one taxonomy rather than two |
| `projects-conventions.md` | `.claude/projects.md` | The team's project conventions — where projects live, register sections, naming, in-flight limit, staleness — read first by every projects command |
| `claude-settings.json` | `.claude/settings.json` (merged) | Registers the kit's marketplace and enables its closeout, projects and workspace plugins; lets the agent delete a promoted draft |
| `gemini-settings.json` | `.gemini/settings.json` (merged) | With `--surfaces claude,gemini` only: makes Gemini CLI load `AGENTS.md` as its context file |
| `CODEOWNERS` | `.github/CODEOWNERS` | Routes changes to the always-loaded tier through the standards owner |
| `pull_request_template.md` | `.github/pull_request_template.md` | Asks a documentation PR which tier it touches, and what it displaces |

Commands for other surfaces are generated, not kept here: `install.sh` writes a thin form of each
`plugins/<plugin>/commands/<command>.md` for every surface asked for — a skill per command with
`--skills-dir <path>`, a Gemini CLI wrapper with `--surfaces claude,gemini` — so each procedure has
one source.

The one file here that is genuinely the team's is §1 of `AGENTS.md`. Everything else is plumbing that
keeps several people and several agent surfaces reading the same thing.
