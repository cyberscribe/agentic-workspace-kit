# Workspace settings — Test Team

Read by the kit's git hooks, its state check and its skills bridge. Keep it prose; each setting is one
bullet with its value in backticks.

## Private remotes

A push goes only to a remote confirmed private. The pre-push hook asks GitHub where it can
(`gh repo view`); where it cannot, it reads this list. `kit/setup.sh` adds a line when it confirms one.

<!-- - **Private remote:** `github.com/<owner>/<repo>` — confirmed YYYY-MM-DD via gh -->

## Public remotes

A project that is its own repository and publishes on purpose (a site, an open-source tool) names its
remote here, then its folder, then the reason. Only that folder's repository may push to the remote,
and a sensitive project is never pushed to one.

<!-- - **Public remote:** `github.com/<owner>/<site>` — `projects/<site>/`, the published site -->

## Developing the kit

- **Private word list:** none — a file of words the kit's own commits leave out. A path here is relative
  to the workspace root, and never inside `kit/`.
- **Kit may name:** none — words the kit's derived-identifier check lets through (a project name that is
  also an ordinary word).

## Skills bridge

- **Kit skills not bridged:** none — kit commands whose `kit-` skill is left out of `.claude/skills/`,
  because a skill of the team's own already covers them.
