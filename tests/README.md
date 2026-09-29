# Tests

`bash tests/run.sh` from the kit root. Plain bash; it needs `git`, `jq` and `python3` (3.11 or later,
for `tomllib`). It builds every repository it uses under one `mktemp` directory in `$TMPDIR` and
removes it on exit; `AW_KEEP=1` keeps it for inspection.

Each check prints one line — `PASS`, `FAIL` or `SKIP` — with the detail indented under a failure, and
the run ends with a count. It exits non-zero when anything fails. Passing is the bar for every change
to the kit.

| Section | What it checks |
|---|---|
| 1 | A non-interactive install (with a skills folder), then a second run that changes no file in the repository or the skills folder (a checksum of every file, before and after) and reports everything already up to date; the stand-ins the quick-start looks for in `AGENTS.md` are found on a fresh install and gone once answered; the Next message; `.claude/projects.md` sets the staleness the board measures against; the installed project template has the Current state block with exactly four labels (State, Blocked by, Check-in, Updated, in that order) and a State line offering exactly the five states, Planned and People, and none of the older sections; a Claude-only install names no Gemini CLI surface in `AGENTS.md` or `.claude/projects.md`, and its surface table names the hooks and the skills row |
| 2 | An interactive install with its answers piped in, the skills folder among them; and one answering every question with Enter, which installs with the defaults |
| 2b | Installer modes: an unknown `--surfaces` value stops the run, `both` reads as Claude Code and Gemini CLI; `--plugin github` registers the marketplace and vendors nothing; `--plugin none` enables nothing, still places `.claude/closeout.md` for the closeout skill, and says so in `AGENTS.md`; `--dry-run` writes nothing anywhere; a second `--skills-only` run is up to date; a changed command regenerates its skill, which follows `procedure.md` while the vendored copy differs; a command the kit has dropped is named, as a skill, a Gemini wrapper and a vendored copy, as a file to delete, and nothing is deleted |
| 3 | Every JSON file parses; every generated Gemini TOML parses (from the interactive install, which asks for Gemini CLI); every plugin has a version; the root and vendored marketplaces list every plugin, and no marketplace carries `$schema`; no command uses a tool-specific argument placeholder; every script passes `bash -n` |
| 4 | The closeout hooks: team detection (none, one, three people, the `CLOSEOUT_TEAM` override, a Team section in the conventions); the capture prompt and how its child is launched, with a stub `claude` on `PATH`; the prompt's register; the recursion guard, sentinels and skips, each paired with a control call that does launch; the review pointer's drafts, `.seen` markers and retention, and on a fake clock what retention leaves for the drafts sweep in `/workspace:hygiene` (a non-`*.md` file, a subdirectory, a folder no session reopens); the personal conventions layer (`~/.claude/closeout.md`, `CLOSEOUT_USER_CONVENTIONS`) read after the project's, which win |
| 4b | The projects session-start hook: three lines inside a project folder — outcome, Done when progress, `State:` with its owner — the same as agent context; a blocked project named with what blocks it and since when, on the state line; a gap and a proposal named; a done project dated by its `Updated:` line; an older Now block read and labelled for conversion by `/projects:adopt`; outside a project one line at most once a day naming active projects blocked for more than 14 days (not paused or done ones, not a blocker 14 days old, not one dated only by a due date), nothing on a clean day, the stamp outside the repository; `.claude/projects.md` locations and section aliases; silent on bad input, when off, and inside the closeout child; under 100 ms with 20 projects; the register names the owner when there is no People section, and a bold State reads plainly |
| 5 | `pilot/measure.sh --backfill` over a fixture history with dated commits, including a project moving to done; the seven project columns week by week (`projects_blocked` and `blocked_over_14d` among them), and a second history for the data-model rules (locations, aliases, honest gaps, a dated Blocked by, in flight, a move to done, the median), `--out`, `MEASURE_ALWAYS_LOADED` and rebuilding an older CSV; every column is a known one; a third history for the reading rules the board and hook share (heading names, checklists only, a blocked State, `since`-only dates, gaps) |
| 6 | The words the kit does not use, from a private list outside the repository (below), as whole words in any case, everywhere except the licences, and in every commit message reachable from `HEAD`; a probe with made-up marker words from a temporary list proves the loader and the scan, and a list line that is not a valid regex fails the scan rather than passing it |
| 7 | No AI-vendor attribution lines in any file, or in any commit message reachable from `HEAD` except the one commit exempt by its full hash; a probe history proves the exemption covers that commit alone |
| 8 | No capitals-for-emphasis in command, example, template, ritual, team or manifest files, with an unterminated ignore block counted as a failure |
| 9 | Exactly the nine commands exist, each vendored for Claude Code and each with one skill: valid Agent Skills front matter (name matching its folder, a description of at most 1024 characters that says when to offer it), under 30 lines, pointing at the command file, with `procedure.md` equal to the command's body; `--skills-only` points at a kit inside the repository directly, falls back to `procedure.md` with none, and writes nothing else |

Checks iterate over what is there — every plugin, every command, every generated skill — so a new
command is covered the moment it exists. Section 9 also names the nine commands, so adding or
removing one is a deliberate change to that list as well.

## The word list

Section 6 reads its list from `$AW_BANNED_WORDS_FILE`, by default
`~/.config/agentic-workspace-kit/banned-words.txt`. The list is kept outside the repository, so no
word on it appears here, in the tests or anywhere else in the kit. One extended-regex alternative per
line; lines starting with `#` and blank lines are ignored. Each alternative is matched as a whole word,
case-insensitive, so a plural or a hyphenated form is caught when the line's own regex allows it
(`widgets?`, `hand-?offs?`). With no file at that path the scan prints one `SKIP` line and the run can
still pass; the probe runs either way. A line that is not a valid extended regex fails the run,
with grep's own message, rather than letting the scan pass unread.

## History

One commit, `d0a56ae` (v1.2), carries attribution trailers and is exempt from section 7 by its full
hash: history is not rewritten for it. Any trailer in any other commit fails the run. The attribution
patterns in `tests/run.sh` are assembled from pieces, so the file is scanned for attribution like any
other.
