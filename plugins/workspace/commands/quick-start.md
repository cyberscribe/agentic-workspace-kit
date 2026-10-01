---
description: First-time setup — interview the team (once) and each person (on their first session) to fill in the workspace's standards, people, conventions and first projects, or map a system already in place onto the kit, then check it is reachable on every surface and running
offer-unprompted: Offer it when the always-loaded file still has angle-bracketed stand-ins, or when a person working here has no profile yet.
---

You are helping people make this workspace theirs. Think of yourself as the new
colleague who has read the handbook template and now wants to hear, in their own
words, how this team actually works — so that every agent session after this one
starts already knowing. Sometimes the team is new to all of it; sometimes one
person is joining a team that has already set up; sometimes someone arrives with
a system of their own that has been working for them, and your job is to fit the
kit around it rather than the other way round. You are curious, you listen more
than you write, and you keep it short: twenty minutes that people enjoy is worth
more than an hour that fills every box.

A setup nobody can reach is not used, so you end every run the same way: by
checking that the commands answer on every surface the person works in, and
that the first session in a project shows where it stands.

Everything here is optional except the few answers that shape every session. Ask
for those with real interest; let the rest be skipped with a word, and come back
another day. Show each change before making it, and change nothing without a yes.

## Find out where things stand

Before asking anything, run the state check from the repository root. It prints
one `key=value` per line, writes nothing, and leaves no git lock behind:

```
bash "${CLAUDE_PLUGIN_ROOT}/bin/state.sh"
```

Where that path has not been filled in, as when this file is read as a skill,
the script is `bin/state.sh` beside the `commands/` folder this file sits in:
`kit/plugins/workspace/bin/state.sh` in a workspace built on the kit. With no
shell at all, read `state.sh` as a file instead: the comment beside each check
names what it reads, so the same keys come from reading those files yourself.

| Key | What it means for the conversation |
|---|---|
| `mode` | Which mode this is: see the next section |
| `always_loaded` | The file every session here loads: `CLAUDE.md`, whose first line imports the kit's standards, `kit/CLAUDE.kit.md`. Judge stand-ins and fill the team part there, below the import; `kit/CLAUDE.kit.md` is the kit's and changes only by pull request to the kit, and `AGENTS.md`, a router for other tools, stays as it is. If the file cannot be read from this shell, what this surface actually loaded decides |
| `standins_remaining`, `surface_standins` | Angle-bracketed stand-ins left in §1–§3, and rows to fill or remove in the §4 surface table. Above 0, the team part is open |
| `person`, `person_profile`, `person_profile_candidates` | The person in front of you, from `git config user.name`, to confirm rather than assume; whether their profile is in `people_dir`; and profiles that may be theirs under another name |
| `authors`, `author_names`, `readme`, `codeowners` | What the repository already says about the team: offer it as suggested answers, so people confirm rather than compose. One author is the cue for a Default owner line |
| `conventions_not_set`, `in_flight_limit`, `staleness`, `default_owner` | The settings in `.claude/projects.md`. Each one still reading "not set yet" is a question for the team part |
| `register_rows`, `glossary_terms`, `build_list`, `verification`, `catalogue` | What an earlier run already answered: offer only the questions still open |
| `signs` | What says a system was here first, by key. The files the kit created, as created or as filled in, are never signs |
| `legacy` | Traces of a 2.x install. They are the migration's, not this interview's: `kit/setup.sh migrate --dry-run` shows what moves, and the person runs it |
| `kit_import`, `hooks`, `origin_visibility` | Whether the workspace is wired: the kit's standards imported, the git hooks active, the origin confirmed private. Anything else is `kit/setup.sh`'s to set: name the command, and leave running it to the person |
| `own_skills`, `foreign_skills`, `decisions_log_other` | The team's own skills and commands, the ones whose names say they do a kit command's job, and decisions logs kept elsewhere. The name match is a first pass: read `own_skills` for the rest |
| `adopt_proposals`, `projects_without_current_state` | Step 3 of fitting the kit to a system already in place |
| `external_paths`, `external_paths_missing` | Material projects name outside the repository, and what is not reachable on this machine: the offer after projects are listed |
| `plugins_registered`, `plugins_loaded`, `plugins_not_loaded`, `surfaces`, `gemini_commands`, `skills_bridge` | Step 1 of reachable and running |
| `commits`, `measure_script`, `metrics_csv` | Step 3 of reachable and running |

## Which mode this is

Decide from `mode=` rather than asking, then say in two lines what you found and
which parts you will offer. The script takes the first that fits, in this order:

- **`joining`** — the always-loaded file, `CLAUDE.md`, has no stand-ins left in
  its own §1–§3, and this person has no profile: the personal part only. This is what most people after the first will see; whatever the
  first person mapped or left beside the kit's files is already settled, and so
  is the metrics baseline (see the last section).
- **`existing-system`** — `signs` names at least one. The kit adopts rather than
  installs: go to "Fitting the kit to a system already in place". If the team
  part is also unfinished, offer only the questions the mapping leaves open.
- **`fresh`** — stand-ins still in the always-loaded file, whatever the register
  holds: the team part, then the personal part. Where an earlier run already
  answered some of it (projects in the register, a staleness setting in place), offer only
  the questions still open.
- **`nothing-left`** — filled in, and they have a profile: say so, and offer the
  last section on its own.

Every mode ends with "Reachable and running".

## The team part — once, ideally with the standards owner

Fill `CLAUDE.md` §1–§3 from the answers, below its import line, and check the
surface table in §4 against what is actually installed. A stand-in row there
(`<second surface>`) is filled with the other surface the team uses — a desktop
assistant with the kit's skills, say — or removed when there is none, on their
yes. It is the always-loaded file, so every line is paid for by every future
session: keep answers to a line each, and move anything longer to a `docs/`
file with a one-line pointer.

1. **What the team does**, at the level that stays true for months.
2. **The standards owner** — confirm the name setup recorded in §1.
3. **Output preferences** — formats, length, tone, spelling.
4. **Working conventions** that change how work should be shaped.
5. **How the agent should show up** (§2) — keep the defaults unless something
   rings false; ask what good looks like when the work is writing, building,
   deciding. The angle-bracketed paragraph above that list is the stand-in:
   on their yes it is replaced by their answer, or deleted when they keep the
   defaults. Left in place, every later person is taken for a fresh team.
6. **Approval gates** (§3) — the irreversible edge: spending money, contacting
   someone outside the team, writing to a system of record, publishing. Name
   theirs precisely; everything short of that line can proceed.

The rest of the team part lives in its own files rather than in `CLAUDE.md`, so
none of it costs the always-loaded budget.

7. *Optional* — **Five glossary terms** a newcomer or an agent would stumble on,
   into `memory/glossary.md`.
8. *Optional* — **How projects run here**, into `.claude/projects.md`: the
   default **in-flight limit** (how many projects one person has in the `doing`
   state at once — three, if the team has no view yet) and the **staleness**
   setting, written `` - **Staleness:** `1 week` `` (how long a project's
   `Updated:` line may go before the board flags it as stale; a project's own
   `Check-in:` line does not change it). Where one
   person works here, offer a `` - **Default owner:** `<name>` `` line too, so
   projects with no People section are theirs on the board. The
   projects commands read this file first and follow it, so a changed line here
   changes their behaviour. If the file already describes the team's own layout,
   it wins: change only the lines the team confirms.
9. *Optional* — **Active projects.** List the projects worth starting now, each
   with its name and owner. Once this interview closes, they run `/projects:new`
   for each one; the close names the first of them as the first thing to do. A register row goes
   in together with its README, when that command writes both, not before it.
   Once projects are listed, ask whether any uses material kept outside the
   repository — large media, a data extract, a shared-drive folder. Each goes
   into the project's README under `## Resources` by name only, and
   `kit/setup.sh link <slug>`, run from a terminal, maps each name to its path on
   this machine in `.claude/resources.local.md`, which is never committed. Ask
   for each path; never guess one.
10. *Optional* — **The team roster.** Offer to start `team/people.md` from
    `templates/team-roster.md` in the kit (`kit/templates/team-roster.md`), so
    closeout knows who to tell.
11. *Optional* — **What counts as checked.** Offer to adopt a verification
    standard into `docs/verification.md`: a short table, one row per kind of work
    the team does — code, analysis, client-facing writing, figures — with what
    is checked, by whom or what, and what evidence is kept. Start from
    `kit/templates/verification-standard.md`. Closeout's
    "verify before you record" step and the close of a project point at it once
    it exists.
12. *Optional* — **The catalogue.** Seed `docs/catalogue.md` with what the team
    has already built and would reuse — one line each: name — what it does —
    where it lives — owner — starting from `kit/templates/catalogue.md`. Three honest lines beat a complete list; finished
    projects add to it from then on.
13. *Optional, pilot only* — **The build list.** Transfer the team's own list of
    what it means to build into `pilot/build-list.md`, one owner and one date per
    row.

`CLAUDE.md` is shown first, since it is the one everyone pays for. Suggest
committing on a branch and opening a pull request, so the standards owner's
review is the first use of the process rather than an exception to it. Where
the team is one person, the author and the reviewer are the same: skip the pull
request, and offer to remove `.github/` (its `CODEOWNERS` and template), on
their yes.

## The personal part — each person, on their first session

1. **Their profile**, from `kit/templates/person-profile.md` (or the template
   `.claude/projects.md` names) into the people directory, named as `.claude/projects.md` says (by default their full name,
   lowercase, joined by hyphens: `memory/people/priya-shah.md`): role, what they own, what to come to them for, what
   not to, how they like requests. Written with them, in their words; it is the
   "who to go to" directory for the team and for every agent.
2. *Optional* — **Their in-flight limit** — how many projects they can be doing
   at once and still finish them. Offer the team default from
   `.claude/projects.md` as the suggested answer, and add it to their profile as
   an **In-flight limit** row (add the row if the template does not carry it).
   A number below the team default is as useful as one above it; it is theirs
   to set.
3. *Optional* — **Their personal layer.** Ask how they like an agent to work with
   them — depth, format, pace — and draft a few lines for their own
   `~/.claude/CLAUDE.md` or their other tool's equivalent. Those files are theirs and
   outside this repository: show the lines and let them add them. Anything that
   would matter to someone else's work belongs in the team layer instead, by pull
   request.

## Fitting the kit to a system already in place

Someone who built their own system has already made most of the kit's choices,
often under other names. The aim is one system, theirs, that the kit's commands
can read — not a second one beside it. Nothing existing is moved or renamed.

1. **The mapping.** Show a short table of what exists against the kit's
   taxonomy (`kit/docs/memory-layers.md`), one line per thing found:

   | Yours | In the kit's terms | What happens |
   |---|---|---|
   | `projects/INDEX.md`, sections Live / Done | The project register | Kept; its section names recorded in `.claude/projects.md` |
   | `logs/decisions.md` | The cross-project decisions log | Kept as is |
   | A closeout skill | `/closeout` | Two doing one job: see step 4 |
   | `CLAUDE.md`, theirs | The always-loaded file | Kept; `.claude/closeout.md` says so, and names how a change to it is reviewed |

   Ask them to confirm or correct each line. Where their convention differs
   from the kit's, theirs wins, and the difference is written down where the
   commands will read it: project layout, register sections, folder prefixes and
   section names in `.claude/projects.md`; where learnings go and in what tiers
   in `.claude/closeout.md`. The always-loaded line is always in the table:
   `.claude/closeout.md` names the file promotions go to and how a change to
   it is reviewed, and it has to name theirs. Where one person works here (one
   author in `git shortlog -sn`, or their file says so), offer a
   `` - **Default owner:** `<name>` `` line in `.claude/projects.md`. Each of those
   edits is shown before it is made.
2. **Their always-loaded file** stays theirs; the kit keeps a `CLAUDE.md` it
   found as it was. The kit's working standards reach it by one line: offer to
   add `@kit/CLAUDE.kit.md` as its first line, with the fallback line the
   kit's starter carries under it (`kit/templates/workspace/CLAUDE.md` shows
   both), shown first and made on a yes. Point out any heading of theirs that
   repeats one in `kit/CLAUDE.kit.md`, since both would then load in every
   session, and offer to fold theirs down to what the kit's lacks. An
   `AGENTS.md` of their own, such as a router for other tools, stays as it is.
3. **Proposals left in their projects.** Find the blocks `/projects:adopt`
   left marked `proposed by /projects:adopt` in project READMEs, and walk them
   project by project: for each Done when, Current state block and owner's
   line, confirm (delete the marker), edit, or skip for another day. The quick
   path is "confirm all that look right, skip the rest". A project still
   carrying a Now block in the older format is reported by `/projects:adopt`,
   which offers the conversion when run on that folder. If active projects
   have no Current state block and no proposals, offer to run
   `/projects:adopt draft` over them now —
   after the `.claude/projects.md` edits from step 1, which it reads — and walk
   what it proposed in this same sitting; or they run `/projects:adopt
   <folder>` one at a time later. Where a project's finish line or outcome is
   there only as prose (a "Finish line" paragraph, a `Goal:` bullet), the
   commands will not see it: offer a `Done when` checklist or a `Desired
   outcome` heading drawn from that text, inserted after it, the prose left as
   it is.
4. **Rituals that do the same job.** Name each pair plainly — an existing
   closeout skill and `/closeout`, an existing tidy-up and `/workspace:hygiene`,
   an existing status page and `/projects:board` — and propose folding each into one:
   split by kind of work, one producing a dated artefact and the other reading
   it, or one calling the other as a named step.
   Running both is the outcome to avoid, since then neither gets run. Change a
   ritual or skill only on their yes. Where the retired one kept a prose status
   section current, name it: offer to retire it into the Current state block's
   dated line, or record in `.claude/closeout.md` that closeout refreshes it too.
5. **What is left over.** List every file the kit created that a confirmed
   line made redundant — the starter `AGENTS.md` when a router of their own
   stays, a `kit-` skill whose job a skill of theirs does (the `Kit skills not
   bridged` line in `.claude/workspace.md` leaves it out of the bridge),
   `.github/` for one person. Say what each is, and give the list as commands
   they can run; deleting is theirs.

## Reachable and running — the end of every mode

Each step is optional, and each is shown before it is done. Offer them in this
order, and take a "not now" as an answer.

1. **Surface parity.** Confirm the commands are reachable on every surface this
   person actually works in: the plugins in Claude Code, from `kit/`; the
   generated wrappers under `.gemini/commands/` where the team installed for
   Gemini CLI; and for a desktop assistant that loads skills from a folder, such
   as Cowork, the skills bridge. `kit/setup.sh skills`, run from a terminal,
   writes one `kit-` skill per command (`kit-projects-board`, `kit-closeout`,
   `kit-workspace-quick-start` and the rest) into `.claude/skills/`, copies the
   team's own skills from `skills/` beside them, and records what it wrote in
   `.claude/skills/.kit-generated`; it refreshes only what that manifest lists,
   and reports a name clash rather than overwriting. `skills_bridge` says
   whether it has run here. In Claude Code the `kit-` skills hand over to the
   plugin commands, so check the plugins there too: `plugins_loaded=no` names
   each missing one in `plugins_not_loaded`, and `claude plugin install
   <plugin>@agentic-workspace` (or `/plugin`) is the fix.

   For the desktop assistant, check where it actually scans, not only where the
   skills were written. Find the folder it loads skills from — the surface
   table in the always-loaded file, the repository's own notes on its skills,
   or the person's answer — and check that each folder the manifest lists is
   there as a real folder, not a link, since some scanners do not follow links.
   Where the assistant scans a folder other than `.claude/skills/`, list what is
   missing and say where it would need to come from. The bridge writes
   `.claude/skills/`, which an agent's sandbox may refuse to write: give
   `kit/setup.sh skills` as the command for the person to run, and
   `kit/setup.sh skills --check` to see whether a refresh is due. Then say
   plainly that the assistant reads its skills when a session starts, so skills
   added or refreshed now appear only in the next session, this one included.
   For any other missing surface, say so and give the command that adds it.
2. **Session start.** Ask them to open a new session in one project folder and
   check that the projects plugin's session-start line appears: the outcome,
   done-when progress, and the project's state and owner, with what it is
   blocked by when that is set. The workspace plugin adds its own lines only
   when something is out of step — hooks, the kit import, a submodule, a
   resource, the origin — so a clean workspace shows none. On a surface without session hooks, the skills' descriptions
   carry the same prompt. With no project yet, leave this for the first session
   after `/projects:new`, and say so in the close.
3. **Measure yourself.** The script reads committed history, so the baseline
   comes after the first commit: with `commits=0`, say "commit first, then run
   it" and leave it. Run the script `measure_script` names with `--backfill 8`,
   from the repository root: in a workspace built on the kit that is
   `bash kit/pilot/measure.sh --backfill 8`, which writes `pilot/metrics.csv`
   here and counts `CLAUDE.md`, `AGENTS.md`, `kit/CLAUDE.kit.md` and what they
   import as the always-loaded tier. Add `MEASURE_ALWAYS_LOADED` only where the
   team's agents load something else at every session. Leave the CSV for them to commit, and add the
   weekly run to the hygiene pass. Say the honesty check
   plainly: a month with no closeout artefacts and no Current state updates
   means the system is a plan, not a practice. The baseline is team-level: when
   joining with `metrics_csv=present`, skip it.
4. **First real use.** End on the first thing to do in one real project, with
   who does it, and suggest ending today's session with `/closeout`.

## Close

Summarise in a few lines what was set up, what was wired in, and what was
skipped, so it can be picked up later. Name the first thing to do, from the
last step. Leave the commit to them: they write the message, and writing it is their
check that they understand what changed.
