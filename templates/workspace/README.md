# __TEAM__ — workspace

## Starting from the template

Choose Private in the Use this template form. Do not fork this repository: a fork of a public
repository cannot be made private. Then clone with --recurse-submodules and run kit/setup.sh:

```
git clone --recurse-submodules <your private repository URL> <folder>
cd <folder>
kit/setup.sh
```

A workspace made with `kit/setup.sh new` starts from the same files, so this section also records how it
began.

## What this is

The team's private workspace: its projects, reference, decisions and working standards. The agentic
workspace kit sits at `kit/` as a submodule, read in place and updated by pull.

## Layout

```
kit/                  the kit (a submodule): plugins, templates, rituals, git hooks; read in place
CLAUDE.md             the always-loaded file; its first line imports kit/CLAUDE.kit.md
AGENTS.md             points other tools at the same two files
.claude/              settings and the conventions the kit's commands read first
projects/INDEX.md     the register; one folder per project under projects/
memory/  docs/  logs/ reference, the workspace's own docs, and decisions
skills/               the team's own skills
```

The detailed map, and where new files go, is `docs/workspace-map.md`.

## Taking a kit update

```
kit/setup.sh update
```

It advances `kit/`, shows what changed, offers any template changes as diffs to apply or skip, and
prints the one commit to make.

## Keeping it private

A workspace holds project data, so it stays private. The git hooks the kit sets up refuse a push to a
remote that is not confirmed private, and `.claude/workspace.md` lists the confirmed ones.
`kit/setup.sh` confirms and records the origin.
