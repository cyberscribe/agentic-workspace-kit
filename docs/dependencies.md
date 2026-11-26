# Dependencies and their licences

The kit vendors no third-party code: it holds no package manifest and no copied library. It calls other
programs by name, each installed separately by whoever uses it, so their licences govern those programs and
do not pass to the kit. This page lists them, so a team can see what a machine needs and what it is agreeing
to. The kit's own licence is in `LICENSE`.

Section 12 of the suite checks that every tool a kit script looks for with `command -v` has a row here. The
licences are as each project publishes them; check the project's own page before relying on one.

## Needed

| Tool | Used for | Licence |
|---|---|---|
| `bash` (3.2 or later) | Every script, the hooks and the installer | GPL (3.2, as macOS ships it: GPL-2.0; later: GPL-3.0) |
| `git` | The workspace, the submodule, the hooks | GPL-2.0 |
| `claude` (Claude Code) | The plugins, the scheduler's runs, `plugin-cost.sh`, the tests' `claude plugin test` | Anthropic's commercial terms; not open source |
| `jq` | Reading JSON in setup, the scheduler, the pairing and the tests | MIT |

The plugins' hooks modules (`*.tsx`) run inside Claude Code on its early-access plugin API; they import
nothing else.

## Optional

| Tool | Used for, when present | Licence |
|---|---|---|
| `gh` | Setup's check that a GitHub origin is private | MIT |
| `shellcheck` | The suite's lint checks | GPL-3.0 |
| `python3` | The pairing's file lock where `perl` is missing; `pilot/lib/strip-lines.py` | PSF License |
| `zip` | Packaging plugins for Cowork (`setup.sh cowork`) | Info-ZIP License |
| `plutil` | Checking launchd property lists (macOS) | Part of macOS |
| `systemd-analyze` | Checking systemd timer lines (tests) | LGPL-2.1-or-later |
| `xdg-open`, `wslview` | Opening a file for the person on Linux and WSL | MIT (xdg-utils); GPL-3.0 (wslu) |
| `osascript`, `pmset` | Notifications and the wake check on macOS | Part of macOS |
| `notify-send` | Desktop notifications on Linux | LGPL-2.1 (libnotify) |
| `docker` | The opt-in container tests (`AW_TEST_DOCKER=1`) | Apache-2.0 (Docker Engine) |
| `tmux` | The pane harness and its cold-user agent (`tests/pane/`, section 30 with `AW_TEST_PANE=1`) | ISC |
| Ubuntu, Fedora and Debian base images | `tests/docker/*.Dockerfile` | Each distribution's own terms |

## Not counted here

Everyday system tools that every supported machine already has: `awk`, `sed`, `grep`, `date`, `mv`, `ps`,
`perl`, `open` (macOS) and `setsid` (Linux).
