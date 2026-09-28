## 1. Who this team is

| Attribute | Detail |
|---|---|
| **Team** | __TEAM__ |
| **What the team does** | <the work, at the level that stays true for months> |
| **Standards owner** | __OWNER__ — reviews changes to this file and to `docs/memory-layers.md` |
| **Output preferences** | <markdown, tables, code blocks, file formats the team works in> |
| **Working conventions** | <anything that changes how outputs should be shaped> |

**Who to go to for what** is a directory, not a paragraph here: one file per person in
`memory/people/<name>.md`, from `templates/person-profile.md` — what they own, what they know, when to
ask them rather than the agent.

### 1.1 Team layer and personal layer

This file is the team's shared working standards. Each person also keeps a personal layer —
`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md` — for how they like to work. The two overlap, and the
overlap is arbitrated like this:

- **The team layer governs anything that touches someone else's work**: where files go, what "done"
  and "verified" mean, how decisions are recorded, which tools are sanctioned.
- **The personal layer governs your own sessions**: style, pace, depth, preferred formats.
- **A personal practice that proves useful to others is promoted here by pull request**, not by
  editing directly. The standards owner reviews it (`.github/CODEOWNERS`).
- **Updating beats appending.** A pull request that adds to this file names the line it replaces, or
  makes the case that the budget should grow. The weekly hygiene pass reports the byte count either
  way.

