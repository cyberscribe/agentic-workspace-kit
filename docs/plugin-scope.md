# Where the kit's plugins load

*Which sessions offer `/closeout`, `/projects:…` and `/workspace:…`, by the folder a session is opened on
and the surface it runs in. The state check reports it as `plugins_scope`; `kit/setup.sh` prints it at
stage 9.*

## The rule

Claude Code reads `.claude/settings.json` in the folder a session is opened on, and not in the folders
above it. The workspace's settings register the kit's marketplace and enable its three plugins, so they
reach a session opened on the workspace's own folder and no other.

| The session is opened on | Enabled by the workspace's settings (`plugins_scope=workspace`) | Also installed for the person (`plugins_scope=user`) |
|---|---|---|
| the workspace's own folder | loaded | loaded |
| a folder below it, such as `projects/<slug>/` | not loaded: no kit command is offered | loaded |
| any other folder | not loaded | loaded |

The desktop app's Code tab runs its own copy of Claude Code on the same settings, under
`~/.claude`, so the same table holds there: what it offers follows the folder the session was opened
on. A folder reached through a symbolic link is read by its real path, and trust is recorded against
that path in `~/.claude.json`, so either way in gives the same result. Cowork reads neither file; the
plugins reach it as uploaded `.plugin` files (`kit/setup.sh cowork`).

Tried on 2026-10-13 with Claude Code 2.1.296 and the desktop app's own 2.1.295, each under an empty
`CLAUDE_CONFIG_DIR`: three plugins and eleven commands at the workspace's folder, none in a folder
below it, and all of them in both once installed for the person.

## Installing them for the person

```
claude plugin marketplace add --scope user <workspace>/kit
claude plugin install <name>@agentic-workspace --scope user
```

The second line is run once for each of `closeout`, `projects` and `workspace`; stage 9 prints all four
commands with the workspace's path filled in. They change the person's own settings and leave the workspace's as committed. The plugins are still
read from `kit/` in place, so `kit/setup.sh update` reaches them. A person with two workspaces has one
marketplace of that name, pointing at one of the two `kit/` folders. Installed this way, the plugins'
hooks run in every session on the machine, in a workspace or not.

## Common questions

**`/closeout` reads as unknown after setup.** The workspace's settings do not enable the plugins. This
happens where `.claude/settings.json` existed before the kit: the engine adds the marketplace to a file
that is the person's and leaves the rest. Setup offers to add the three entries at stage 3; where that
was declined, or a plugin is set to `false`, stages 3, 7 and 9 print the commands, run in the
workspace's folder: `claude plugin enable closeout@agentic-workspace --scope project`, and the same for
`projects` and `workspace`. `git diff .claude/settings.json` then shows the three lines to commit.

**The commands are there in one session and missing in another.** Check which folder each session was
opened on, against the table. A session opened on a project folder offers the kit's commands only when
the plugins are installed for the person.

**The first session after trusting the folder lists no plugins.** That session can register the
marketplace without loading its plugins; the next one loads them. The same holds after the workspace's
folder is moved or renamed, since the marketplace is recorded by its full path in
`~/.claude/plugins/known_marketplaces.json`: the first session there records the new path, and the one
after it loads them.
