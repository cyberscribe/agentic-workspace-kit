# Tests

`bash tests/run.sh` from the kit root. Plain bash; it needs `git`, `jq` and `python3` (3.11 or later,
for `tomllib`). It builds every repository it uses under one `mktemp` directory in `$TMPDIR` and
removes it on exit; `AW_KEEP=1` keeps it for inspection.

Each check prints one line — `PASS`, `FAIL` or `SKIP` — with the detail indented under a failure, and
the run ends with a count. It exits non-zero when anything fails. Passing is the bar for every change
to the kit.

| Section | What it checks |
|---|---|
| 1 | A non-interactive install (with a skills folder), then a second run that changes no file in the repository or the skills folder (a checksum of every file, before and after) and reports everything already up to date; the stand-ins the quick-start looks for in `AGENTS.md` are found on a fresh install and gone once answered; the inbox and the Next message; a Claude-only install names no Gemini CLI surface in `AGENTS.md` or `.claude/projects.md`, and its surface table names the hooks and the skills row |
| 2 | An interactive install with its answers piped in, the skills folder among them; and one answering every question with Enter, which installs with the defaults |
| 2b | Installer modes: an unknown `--surfaces` value stops the run, `both` reads as Claude Code and Gemini CLI; `--plugin github` registers the marketplace and vendors nothing; `--plugin none` enables nothing, still places `.claude/closeout.md` for the closeout skill, and says so in `AGENTS.md`; `--dry-run` writes nothing anywhere; a second `--skills-only` run is up to date; a changed command regenerates its skill, which follows `procedure.md` while the vendored copy differs |
| 3 | Every JSON file parses; every generated Gemini TOML parses (from the interactive install, which asks for Gemini CLI); every plugin has a version; the root and vendored marketplaces list every plugin, and no marketplace carries `$schema`; no command uses a tool-specific argument placeholder; every script passes `bash -n` |
| 4 | The closeout hooks: team detection (none, one, three people, the `CLOSEOUT_TEAM` override, a Team section in the conventions); the capture prompt and how its child is launched, with a stub `claude` on `PATH`; the prompt's register; the recursion guard, sentinels and skips, each paired with a control call that does launch; the review pointer's drafts, `.seen` markers and retention; the personal conventions layer (`~/.claude/closeout.md`, `CLOSEOUT_USER_CONVENTIONS`) read after the project's, which win |
| 4b | The projects session-start hook: three lines inside a project folder, the same as agent context; a gap and a proposal named; outside a project one line at most once a day, nothing on a clean day, the stamp outside the repository; `.claude/projects.md` locations and section aliases; silent on bad input, when off, and inside the closeout child; under 100 ms with 20 projects; the shared reading rules (a waiting project with a Waiting on line has what it needs, the register names the owner when there is no People section, a bold State) |
| 5 | `pilot/measure.sh --backfill` over a fixture history with dated commits, including a project moving to done; the seven project columns week by week, and a second history for the data-model rules (locations, aliases, honest gaps, waiting dates, in flight, a move to done, the median), `--out`, `MEASURE_ALWAYS_LOADED` and rebuilding an older CSV; every column is a known one; a third history for the reading rules the board and hook share (heading names, checklists only, waiting, `since`-only dates, gaps) |
| 6 | The method words the kit does not use, as whole words in any case, plurals and hyphenated forms included, everywhere except the licences; a probe file proves the pattern catches them |
| 7 | No AI-vendor attribution lines in any file, or in any commit message reachable from `HEAD` |
| 8 | No capitals-for-emphasis in command, example, template, ritual, team or manifest files, with an unterminated ignore block counted as a failure |
| 9 | Exactly the twelve commands exist, each vendored for Claude Code and each with one skill: valid Agent Skills front matter (name matching its folder, a description of at most 1024 characters that says when to offer it), under 30 lines, pointing at the command file, with `procedure.md` equal to the command's body; `--skills-only` points at a kit inside the repository directly, falls back to `procedure.md` with none, and writes nothing else |

Checks iterate over what is there — every plugin, every command, every generated skill — so a new
command is covered the moment it exists. Section 9 also names the twelve commands, so adding or
removing one is a deliberate change to that list as well.

`AW_SKIP_HISTORY=1` skips the history half of section 7 and reports it as `SKIP`, never as a pass. It
exists for the window between finding attribution in published history and the rewrite that removes
it; the default run tells the truth about the history.

`tests/run.sh` has to spell out the word list, so the lines that do end in a `# wordlist` marker, and
only those lines are left out of the word scan. Its attribution patterns are assembled from pieces,
so it is scanned for attribution like any other file.
