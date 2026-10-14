# Where the kit's plugins load

*Which sessions offer `/closeout`, `/projects:…` and `/workspace:…`, by the folder a session is opened on
and the surface it runs in, and where their hooks act. The state check reports it as `plugins_scope` and
`plugins_user_kit`; `kit/setup.sh` installs the plugins for the person at stage 7 and prints where they
load at stage 9.*

## The rule

Claude Code reads `.claude/settings.json` in the folder a session is opened on, and not in the folders
above it. The workspace's settings register the kit's marketplace and enable its three plugins, so on
their own they reach a session opened on the workspace's own folder and no other. Setup therefore also
installs the plugins for the person (user scope), and the plugins' hooks keep to kit workspaces.

| The session is opened on | Enabled by the workspace's settings alone (`plugins_scope=workspace`) | Installed for the person (`plugins_scope=user`, setup's default) |
|---|---|---|
| the workspace's own folder | loaded | loaded |
| a folder below it, such as `projects/<slug>/` | not loaded: no kit command is offered | loaded |
| any other folder | not loaded | loaded; the hooks pass silently, and each command says in one line that it works inside a kit workspace |

The desktop app's Code tab runs its own copy of Claude Code on the same settings, under
`~/.claude`, so the same table holds there: what it offers follows the folder the session was opened
on. A folder reached through a symbolic link is read by its real path, and trust is recorded against
that path in `~/.claude.json`, so either way in gives the same result. Cowork reads neither file; the
plugins reach it as uploaded `.plugin` files (`kit/setup.sh cowork`).

A workspace inside WSL opened from the Windows desktop app is untested. Installed for the person,
the plugins are in WSL's `~/.claude`, which the Windows app may not read; nothing here says either way.

Tried on 2026-10-13 with Claude Code 2.1.296 and the desktop app's own 2.1.295, each under an empty
`CLAUDE_CONFIG_DIR`: three plugins and eleven commands at the workspace's folder, none in a folder
below it, and all of them in both once installed for the person. Seen in the desktop app itself on
2026-10-14: a new Code-tab session on a workspace's own folder, opened by its real path or by a
symbolic link, offered the commands its settings alone enabled; one on `projects/demo/` below it
offered none. The first Code-tab session after trusting a new folder offered none, and the next one
offered them, as in the terminal. With the same plugins enabled for the person and by the workspace, as setup leaves
them, Claude Code loads each once and runs each hook once.

## The workspace boundary

A session is inside a kit workspace when its folder, or a folder above it, holds `kit/CLAUDE.kit.md`
(the kit, as the workspace's submodule) or `.claude/kit-templates.lock` (setup's ledger). The folder is
resolved to its real path first, so a workspace entered through a symbolic link counts. This is the same
walk the workspace plugin's session-start line has always used to find the workspace it reports on.

Every hook of the three plugins starts with it: closeout's SessionStart and SessionEnd, projects'
SessionStart and the pair hooks, workspace's SessionStart and the git guard. Outside a workspace each
exits 0 with nothing said, so the closeout capture starts no child session there and the git guard
leaves other repositories' commands alone. The rule lives in `hooks/lib/boundary.sh`; each plugin
carries an identical copy, since an installed plugin reaches only its own folder, and the test suite
checks that the three match. The commands cannot be hidden outside a workspace, so each one checks the
same two files first and, finding neither, says in one line where it works.

## Installing them for the person

Stage 7 of `kit/setup.sh` does it. Attended, it asks first (the default is yes); unattended, it takes the
default. It runs:

```
claude plugin marketplace add --scope user <workspace>/kit
claude plugin install <name>@agentic-workspace --scope user
```

the second once for each of `closeout`, `projects` and `workspace`. Its steps then ask for one new
session in the workspace: trust the folder, type `/`, and look for `/closeout`, `/projects:new` and
`/workspace:hygiene`, starting one more session if the first after trust has none. Claude Code's own
install offer, and re-pointing the marketplace, appear in the steps only where the install did not
happen here: declined, `claude` not on `PATH`, or the person's marketplace on another checkout. The workspace path is spelled the way
the person reached it, a symbolic link included: Claude Code records that path, and a folder later moved
to where its link was is still found by it. A re-run with the plugins already installed from this
workspace's kit runs nothing. Without `claude` on `PATH` the step is skipped and stage 9 prints the
commands. They change the person's own settings and leave the workspace's as committed. The plugins are
read from `kit/` in place, so `kit/setup.sh update` reaches them. The workspace's own `enabledPlugins`
stay as they are, so a person who never installs for themselves still has the plugins at the root.

## One kit checkout per machine

Claude Code keeps one path per marketplace name. Two kit workspaces on one machine, each with the plugins
installed for the person, share one: every session in either runs the plugins from whichever `kit/` the
person's settings name. `plugins_user_kit` says which: `this` (this workspace's kit), `elsewhere` (another
checkout) or `none`. Where it reads `elsewhere` and that checkout is still there, setup warns. Attended,
it asks whether to point the marketplace here instead (the default is no, since that moves the other
workspace onto this kit); unattended, it leaves it, and stage 9 prints the commands. A path that is no
longer there is replaced without asking. Two workspaces on the same kit version notice nothing.

## Common questions

**`/closeout` reads as unknown after setup.** Neither the person's settings nor the workspace's enable
the plugins. Where `.claude/settings.json` existed before the kit, the engine adds the marketplace to a
file that is the person's and leaves the rest; setup offers to add the three entries at stage 3 and to
install the plugins for the person at stage 7. Where both were declined, or a plugin is set to `false`,
stages 3, 7 and 9 print the commands. `git diff .claude/settings.json` shows the lines to commit.

**The commands are there in one session and missing in another.** Check which folder each session was
opened on, against the table. A session opened on a project folder offers the kit's commands only when
the plugins are installed for the person: `plugins_scope=user` in the state check.

**A kit command answers that it works inside a kit workspace.** The session was opened on a folder with
no `kit/CLAUDE.kit.md` or `.claude/kit-templates.lock` in it or above it. Open it on the workspace, or on
any folder inside it.

**The first session after trusting the folder lists no plugins.** That session can register the
marketplace without loading its plugins; the next one loads them. The desktop app does the same. The same holds after the workspace's
folder is moved or renamed, since the marketplace is recorded by its full path in
`~/.claude/plugins/known_marketplaces.json`: the first session there records the new path, and the one
after it loads them.

**A workspace on an older kit.** Before 3.2.0 setup did not install the plugins for the person, and their
hooks had no boundary. Installed for the person by hand on such a kit, the hooks run in every session on
the machine; `kit/setup.sh update` brings in the boundary.
