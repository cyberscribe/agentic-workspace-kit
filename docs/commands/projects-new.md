# /projects:new

*Starts a project: a short interview, then its README and a register row. Source:
`plugins/projects/commands/new.md`.*

## What it does

- Reads `.claude/projects.md` first, and follows it over the defaults: where projects live, the
  register's sections, folder naming, the in-flight limit, the template and the **Versioned default**.
- Offers two depths. **Quick** asks for the name, the desired outcome, three to five Done when
  criteria, how the project is versioned, and who owns it. **Full** adds what it is and is not,
  success criteria, people and their roles, precedents, approval gates, timing, planned steps, open
  questions and resources. Anything can be skipped; a skipped section is left out, not stubbed.
- Asks how the project's files are kept, `workspace`, `own-repo` or `untracked`, and whether anything
  in it is sensitive (`normal` or `sensitive`). Both answers are written as two lines under the title.
- For `own-repo`, shows each step and runs it on a yes: `git init`, `kit/setup.sh hooks --repo
  projects/<slug>`, a check of the remote's visibility with `gh` where it is available, and the remote.
  The commit, push and `git submodule add` are given as commands for the person.
- For `untracked`, adds `projects/<slug>/` to `.gitignore` before the README is written.
- Settles the starting state (`ready`, `blocked` or `doing`), counting the owner's projects in flight
  against their limit before starting one as `doing`. The limit is advice, never a block.
- Writes `projects/<slug>/README.md` from the project template, with the Current state block after
  Done when, and a row in `projects/INDEX.md`. It shows the README first and writes it on a yes.

## When to reach for it

When someone describes new work that has no project folder yet. If a folder already exists, the work
has started: it stops and suggests `/projects:adopt <folder>` instead.

## Common questions

**Can a sensitive project be tracked by the workspace?** No. The workspace's git hooks refuse a
sensitive project's files, so it is offered `untracked` (the default) or `own-repo` with a remote
confirmed private.

**My project publishes to a public repository.** For a normal project, a public remote is allowed when
it is named in `.claude/workspace.md` under Public remotes, with the project's folder. It offers that
line and adds it on your yes; without it, the pre-push hook refuses the push.

**Where do paths to outside material go?** Nowhere committed. Resources are named in the README by
short name only; `kit/setup.sh link <slug>` maps each name to a path on this machine.

**Does it run in Cowork?** Yes, as the `kit-projects-new` skill that `kit/setup.sh skills` writes. In
Claude Code that skill hands over to this command; in Cowork it runs the procedure in full.

## It's working if

- The README has `Versioned:` and `Sensitivity:` under its title, a checkable Done when list, and a
  Current state block reading the state it started in.
- The register has a row for it, and `/projects:board` shows it as a card.
- A session opened in the new folder shows the projects session-start line for it.
