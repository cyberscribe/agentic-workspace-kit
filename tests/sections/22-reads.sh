# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh, which sources this file (SC2154); backticks in
# single quotes are the Markdown being looked for (SC2016); a check ends in ok or ko, never both (SC2015).
# shellcheck disable=SC2154,SC2016,SC2015
# Section 22: the agent-reads measure. pilot/reads.sh counts, from Claude Code's transcripts, how often
# agents working in a workspace read its reference files, and measure.sh carries the counts as columns.
# Every transcript here is written by this file into a scratch config folder: fixtures only, no clones,
# and nothing read from the real ~/.claude. Everything is prefixed s22_ and written under $SCRATCH.

echo
echo "22 · Agent reads: reads.sh on written transcripts, and its columns in metrics.csv"

s22_dir="$SCRATCH/s22"
s22_w="$s22_dir/ws" s22_other="$s22_dir/elsewhere" s22_cfg="$s22_dir/config" s22_home="$s22_dir/home"
mkdir -p "$s22_w" "$s22_other" "$s22_cfg" "$s22_home"
READS="$KIT/pilot/reads.sh"
s22_bash="${st_bash:-bash}"

# --- The workspace: reference files, an always-loaded import, a project, a kit folder ---------------
# s22_commit <days ago> <message>: everything, committed at noon UTC that day.
s22_commit() {
    local when; when="$(python3 -c 'import datetime,sys; print((datetime.datetime.now(datetime.timezone.utc).date() - datetime.timedelta(days=int(sys.argv[1]))).isoformat())' "$1")T12:00:00+0000"
    git -C "$s22_w" add -A && GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git -C "$s22_w" -c commit.gpgsign=false commit -q -m "$2"
}
git -C "$s22_w" init -q && git -C "$s22_w" symbolic-ref HEAD refs/heads/main
mkdir -p "$s22_w/docs/sub" "$s22_w/memory/people" "$s22_w/logs" "$s22_w/projects/one" "$s22_w/projects/_done/two" \
    "$s22_w/kit/docs" "$s22_w/src"
cp "$KIT/templates/workspace.gitignore" "$s22_w/.gitignore"
printf '@kit/CLAUDE.kit.md\n\n# Team\n\nThe standards are in @docs/always.md.\n' > "$s22_w/CLAUDE.md"
printf '# Kit standards\n' > "$s22_w/kit/CLAUDE.kit.md"
printf '# Kit guide\n' > "$s22_w/kit/docs/guide.md"
for s22_f in docs/always.md docs/alpha.md docs/beta.md docs/gamma.md docs/sub/delta.md memory/people/sam.md \
    logs/decisions.md projects/INDEX.md projects/one/README.md projects/one/decisions.md projects/one/notes.md \
    projects/_done/two/README.md src/code.md; do
    printf '# %s\n\nfoo\n' "$s22_f" > "$s22_w/$s22_f"
done
s22_commit 25 "The workspace"
printf '# Late\n' > "$s22_w/docs/late.md"
s22_commit 3 "A reference file added later"
# The ten reference files of the first commit, and the eleventh of the second. Not reference: the
# always-loaded CLAUDE.md and its import, a project's other notes, src/, and everything under kit/.
s22_ref="docs/alpha.md docs/beta.md docs/gamma.md docs/sub/delta.md memory/people/sam.md logs/decisions.md
projects/INDEX.md projects/one/README.md projects/one/decisions.md projects/_done/two/README.md docs/late.md"

# --- The transcripts ---------------------------------------------------------------------------------
# Written in Claude Code's layout: <config>/projects/<slug>/<session>.jsonl, a session's subagents under
# <slug>/<session>/subagents/. Dates are UTC days before today; s22_d <n> is that day.
python3 - "$s22_cfg" "$s22_w" "$s22_other" "$s22_home" <<'PYFIX'
import datetime, json, os, sys
cfg, W, other, home = sys.argv[1:5]
today = datetime.datetime.now(datetime.timezone.utc).date()
seq = [0]
def stamp(n):
    seq[0] += 1
    return "%sT12:%02d:%02d.000Z" % ((today - datetime.timedelta(days=n)).isoformat(), seq[0] // 60 % 60, seq[0] % 60)
def entry(sid, n, cwd, typ="assistant", content=None, side=False, named=True):
    e = {"type": typ, "isSidechain": side, "cwd": cwd, "timestamp": stamp(n), "uuid": "u%d" % seq[0]}
    if named: e["sessionId"] = sid
    if typ == "assistant": e["message"] = {"role": "assistant", "content": content or [{"type": "text", "text": "Done."}]}
    else: e["message"] = {"role": "user", "content": "Carry on."}
    return e
def tool(name, **inp):
    seq[0] += 1
    return {"type": "tool_use", "id": "toolu_%04d" % seq[0], "name": name, "input": inp}
def bash(cmd): return tool("Bash", command=cmd, description="a step")
def write(base, rel, entries, tail=""):
    p = os.path.join(base, "projects", rel); os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        for e in entries: f.write(json.dumps(e) + "\n")
        f.write(tail)

S1, S2, S3, S4 = ("%d%d%d%d%d%d%d%d-1111-4111-8111-111111111111" % ((i,) * 8) for i in (1, 2, 3, 4))
SK, SO, SOLD, SU = ("%s-2222-4222-8222-222222222222" % (c * 8) for c in "abcd")

# S1: started in the workspace root, yesterday. Thirteen reads, five searches, one read of the kit.
twice = entry(S1, 1, W, content=[tool("Read", file_path=W + "/docs/alpha.md")])                    # read 1
s1 = [entry(S1, 1, W, "user"), twice, twice,                                                       # the same call recorded twice
    entry(S1, 1, W, content=[
        tool("Read", file_path=W + "/docs/always.md"),          # always loaded through an import: not a read
        tool("Read", file_path=W + "/CLAUDE.md"),               # always loaded
        tool("Edit", file_path=W + "/docs/beta.md", old_string="foo", new_string="bar"),   # an edit is not a read
        tool("Write", file_path=W + "/docs/gamma.md", content="# new"),
        tool("Read", file_path=W + "/src/code.md"),             # outside the reference folders
        tool("Read", file_path=W + "/projects/one/notes.md"),   # a project's working file
        tool("Read", file_path=W + "/projects/one/README.md", limit=20),                    # read 2
        tool("Read", file_path=W + "/kit/docs/guide.md"),       # the kit, counted apart
        tool("Read", file_path=W + "/kit/CLAUDE.kit.md"),       # always loaded
    ]),
    entry(S1, 1, W, content=[bash("cat docs/beta.md docs/beta.md")]),                               # read 3, once
    entry(S1, 1, W, content=[bash("head -n 5 docs/gamma.md && tail -3 \"docs/sub/delta.md\"")]),     # reads 4, 5
    entry(S1, 1, W, content=[bash("sed -n '1,5p' memory/people/sam.md"),                           # read 6
                             bash("sed -i '' 's/foo/bar/' docs/alpha.md"),                          # an edit
                             bash("sed 's/foo/bar/' docs/alpha.md")]),                              # no -n
    entry(S1, 1, W, content=[bash("less logs/decisions.md | cat")]),                                # read 7
    entry(S1, 1, W, content=[bash("FOO=1 awk '/foo/ { print $1 }' projects/INDEX.md")]),            # read 8
    entry(S1, 1, W, content=[bash("grep -n foo docs/alpha.md > /dev/null 2>&1")]),                  # read 9
    entry(S1, 1, W, content=[bash("rg foo " + W + "/projects/one/decisions.md")]),                  # read 10, absolute
    entry(S1, 1, W, content=[bash("cd docs && cat alpha.md")]),                                     # read 11, after a cd
    entry(S1, 1, W, content=[bash("head -1 memory/people/*.md")]),                                  # read 12, a pattern
    entry(S1, 1, W, content=[tool("Grep", pattern="foo", path=W + "/docs/alpha.md")]),              # read 13: one file
    # Not reads: a redirect target, a here-document's text, a quoted command, a command for another shell.
    entry(S1, 1, W, content=[bash("cat > docs/gamma.md <<'EOF'\ncat docs/beta.md\nless logs/decisions.md\nEOF")]),
    entry(S1, 1, W, content=[bash("echo \"cat docs/beta.md\"; bash -c 'cat docs/beta.md' # cat docs/beta.md")]),
    entry(S1, 1, W, content=[bash("for f in $FILES; do cat \"$f\"; done; cat docs/missing.md; ls docs/alpha.md")]),
    # Not searches: inside a reference folder, a pattern and an option's value are not folders.
    entry(S1, 1, W, content=[bash("cd docs && grep -n 'foo bar' missing.md -A 3; ls -t | head -3")]),
    # Searches: the two tools, and the Bash forms aimed at a reference folder.
    entry(S1, 1, W, content=[tool("Grep", pattern="foo", path=W + "/docs"),                         # search 1
                             tool("Glob", pattern="memory/**/*.md"),                                # search 2
                             tool("Grep", pattern="foo"),                                           # the whole workspace: not one
                             tool("Glob", pattern="src/**/*.md"),
                             tool("Glob", pattern="**/*.md", path=W + "/projects/one")]),
    entry(S1, 1, W, content=[bash("grep -rn foo docs/"), bash("ls memory/people"),                  # searches 3, 4
                             bash("find logs -name '*.md'"),                                        # search 5
                             bash("ls projects/one; grep -r foo .; find . -name '*.md'")]),
]
cut = '{"type":"assistant","sessionId":"%s","isSidechain":false,"cwd":"%s","timestamp":"%s","message":{"content":[{"type":"tool_use","id":"toolu_cut","name":"Read","input":{"file_path":"%s/docs/beta.md' % (S1, W, stamp(1), W)
write(cfg, "-ws/%s.jsonl" % S1, s1, cut)
# Its subagents, three days ago: one names its session, one (a workflow's agent) is placed by its folder.
# S1's transcript above ends mid-line, as a live session's does. Whichever file is read next must not
# lose its first line to it, so the files that sort next to it, either way round, open with a read.
write(cfg, "-ws/%s/subagents/agent-a1.jsonl" % S1,
    [entry(S1, 3, W, side=True, content=[tool("Read", file_path=W + "/docs/gamma.md")])])           # read 14
write(cfg, "-ws/%s/subagents/workflows/wf_1/agent-b2.jsonl" % S1,
    [entry(S1, 3, W, side=True, named=False, content=[bash("cat docs/sub/delta.md")])])            # read 15
with open(os.path.join(cfg, "projects", "-ws", S1, "subagents", "agent-a1.meta.json"), "w") as f: f.write("{}\n")

# S2: started in a project folder, six days ago — the first day of today's window. Two reads.
P = W + "/projects/one"
write(cfg, "-ws-projects-one/%s.jsonl" % S2,
    [entry(S2, 6, P, content=[bash("cat README.md"), bash("cat ../../docs/beta.md")]),              # reads 16, 17
     entry(S2, 6, P, "user")])
# S3: seven days ago — the day before today's window, the last day of the window a week earlier.
write(cfg, "-ws/%s.jsonl" % S3, [entry(S3, 7, W, "user"), entry(S3, 7, W, content=[tool("Read", file_path=W + "/docs/alpha.md")])])
# S4: in the workspace and reading nothing of the reference; later in another folder, where a relative
# path is that folder's, not the workspace's.
write(cfg, "-ws/%s.jsonl" % S4, [entry(S4, 1, W, "user"), entry(S4, 1, W, content=[bash("git status")]),
    entry(S4, 1, other, content=[bash("cat docs/alpha.md")])])
# SK: started in the workspace's kit/ — kit development, left out. SO: started somewhere else.
write(cfg, "-ws-kit/%s.jsonl" % SK, [entry(SK, 1, W + "/kit", "user"), entry(SK, 1, W + "/kit", content=[tool("Read", file_path=W + "/docs/alpha.md")])])
write(cfg, "-elsewhere/%s.jsonl" % SO, [entry(SO, 1, other, "user"), entry(SO, 1, other, content=[tool("Read", file_path=W + "/docs/alpha.md")])])
# SOLD: the transcript that went quiet longest ago, twenty days back; an entry older still inside S3
# would not move that date, and none does here.
write(cfg, "-ws/%s.jsonl" % SOLD, [entry(SOLD, 20, W, "user"), entry(SOLD, 20, W, content=[tool("Read", file_path=W + "/docs/beta.md")])])
# SU: opened and never answered — not a session of the agent's.
write(cfg, "-ws/%s.jsonl" % SU, [entry(SU, 1, W, "user")])

# A second, smaller set under a home folder's .claude: one session with one read, two days ago, and
# one elsewhere fifteen days ago, so the transcripts reach back past the window.
write(os.path.join(home, ".claude"), "-ws/%s.jsonl" % S3, [entry(S3, 2, W, "user"),
    entry(S3, 2, W, content=[tool("Read", file_path=W + "/logs/decisions.md")])])
write(os.path.join(home, ".claude"), "-elsewhere/%s.jsonl" % SO, [entry(SO, 15, other, "user"), entry(SO, 15, other)])
PYFIX
s22_d() { python3 -c 'import datetime,sys; print((datetime.datetime.now(datetime.timezone.utc).date() - datetime.timedelta(days=int(sys.argv[1]))).isoformat())' "$1"; }
s22_today="$(s22_d 0)" s22_from="$(s22_d 20)"
# s22_stamp <dir>: every file under it with its size and modification time, to show nothing was touched.
s22_stamp() { python3 -c 'import os,sys
for d, _, fs in sorted(os.walk(sys.argv[1])):
    for f in sorted(fs):
        s = os.stat(os.path.join(d, f)); print(os.path.join(d, f), s.st_size, s.st_mtime_ns)' "$1"; }
s22_before="$(s22_stamp "$s22_cfg"; s22_stamp "$s22_home")"
s22_tree_before="$(cd "$s22_w" && find . -path ./.git -prune -o -print | sort; git -C "$s22_w" status --porcelain)"

# s22_rows <date>...: the rows reads.sh gives measure.sh, from the scratch config folder.
s22_rows() { env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_cfg" bash "$READS" --target "$s22_w" --rows "$@" 2>&1; }

# --- The counts -------------------------------------------------------------------------------------
s22_got="$(s22_rows "$s22_today")"
s22_want="$s22_today,3,2,17,5,9,11,$s22_from"
[[ "$s22_got" == "$s22_want" ]] \
    && ok "22 today's row: 3 sessions (one in kit/, one elsewhere and one never answered left out), 2 reading, 17 reads, 5 searches, 9 of 11 files" \
    || ko "22 today's row: 3 sessions (one in kit/, one elsewhere and one never answered left out), 2 reading, 17 reads, 5 searches, 9 of 11 files" "want $s22_want"$'\n'"got  $s22_got"

# The same row whatever order the transcript files are read in: here, the list reversed.
s22_got="$(READS_TEST_ORDER=reverse s22_rows "$s22_today")"
[[ "$s22_got" == "$s22_want" ]] \
    && ok "22 the same row with the transcript files read in reverse order: an unfinished last line costs the next file nothing" \
    || ko "22 the same row with the transcript files read in reverse order: an unfinished last line costs the next file nothing" "want $s22_want"$'\n'"got  $s22_got"

# Each kind of read on its own, so a miscount names its cause: reads.sh --report lists reads per file.
s22_rep_out="$(env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_cfg" bash "$READS" --target "$s22_w" --report 2>&1)"; s22_rc=$?
s22_rep="$s22_w/pilot/reads.local.md"
s22_bad=""
[[ $s22_rc -eq 0 && -f "$s22_rep" ]] || s22_bad+="--report exited $s22_rc: $s22_rep_out"$'\n'
# file | reads | sessions: alpha is read by the Read tool, grep, cat after a cd, and the Grep tool on the file.
while IFS='|' read -r s22_f s22_n s22_s; do
    grep -qF "| $s22_n | $s22_s | \`$s22_f\` |" "$s22_rep" 2>/dev/null || s22_bad+="$s22_f: wanted $s22_n reads by $s22_s sessions, report has: $(grep -F "\`$s22_f\`" "$s22_rep" 2>/dev/null | head -n 1)"$'\n'
done <<'S22_FILES'
docs/alpha.md|4|1
docs/beta.md|2|2
docs/gamma.md|2|1
docs/sub/delta.md|2|1
memory/people/sam.md|2|1
logs/decisions.md|1|1
projects/INDEX.md|1|1
projects/one/README.md|2|2
projects/one/decisions.md|1|1
S22_FILES
empty "22 each form counts once: Read, cat, head, tail, sed -n, less, awk, grep, rg, a cd, a pattern, the Grep tool on one file, relative and absolute, a subagent's" "$s22_bad"

s22_bad=""
for s22_f in docs/always.md CLAUDE.md src/code.md projects/one/notes.md docs/missing.md; do
    grep -qF "\`$s22_f\`" "$s22_rep" 2>/dev/null && s22_bad+="$s22_f is in the report"$'\n'
done
s22_never="$(sed -n '/^## Reference files never read/,/^## The kit/p' "$s22_rep" 2>/dev/null | grep -c '^- ')"
[[ "$s22_never" == 2 ]] || s22_bad+="never read lists $s22_never files, not 2"$'\n'
for s22_f in docs/late.md projects/_done/two/README.md; do
    sed -n '/^## Reference files never read/,/^## The kit/p' "$s22_rep" 2>/dev/null | grep -qxF -- "- \`$s22_f\`" || s22_bad+="$s22_f is not listed as never read"$'\n'
done
grep -qxF -- '- `kit/docs/guide.md` (1)' "$s22_rep" 2>/dev/null || s22_bad+="the kit's guide is not counted apart"$'\n'
grep -qF 'kit/CLAUDE.kit.md' "$s22_rep" 2>/dev/null && s22_bad+="the always-loaded kit file is counted"$'\n'
empty "22 not counted: an always-loaded file, an edit, a write, a path outside the reference, a redirect, a here-document; the kit's Markdown apart; 2 never read" "$s22_bad"

# --- Windows, and empty rather than zero ------------------------------------------------------------
# The window is the seven days ending on the row's date. S2 worked six days ago and S3 seven: today's
# row has S2 and not S3, the row a week back has S3 and not S2, with the ten files of its own commit.
s22_got="$(s22_rows "$(s22_d 7)" "$(s22_d 8)" "$(s22_d 13)" "$(s22_d 14)" "$(s22_d 30)")"
s22_want="$(s22_d 7),1,1,1,0,1,10,$s22_from
$(s22_d 8),0,0,0,0,0,10,$s22_from
$(s22_d 13),0,0,0,0,0,10,$s22_from
$(s22_d 14),,,,,,10,$s22_from
$(s22_d 30),,,,,,0,$s22_from"
[[ "$s22_got" == "$s22_want" ]] \
    && ok "22 the window ends on the row's date and starts six days before; a window reaching back to the oldest transcript is empty, a later quiet one is zero" \
    || ko "22 the window ends on the row's date and starts six days before; a window reaching back to the oldest transcript is empty, a later quiet one is zero" "want:"$'\n'"$s22_want"$'\n'"got:"$'\n'"$s22_got"

# --- Where the transcripts are read from --------------------------------------------------------------
s22_got="$(env -u READS_TRANSCRIPTS -u CLAUDE_CONFIG_DIR HOME="$s22_home" bash "$READS" --target "$s22_w" --rows "$s22_today" 2>&1)"
s22_got+="|$(env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_dir/no-such-config" HOME="$s22_home" bash "$READS" --target "$s22_w" --rows "$s22_today" 2>&1)"
s22_got+="|$(READS_TRANSCRIPTS="$s22_home/.claude/projects" CLAUDE_CONFIG_DIR="$s22_cfg" bash "$READS" --target "$s22_w" --rows "$s22_today" 2>&1)"
s22_want="$s22_today,1,1,1,0,1,11,$(s22_d 15)|$s22_today,,,,,,11,|$s22_today,1,1,1,0,1,11,$(s22_d 15)"
[[ "$s22_got" == "$s22_want" ]] \
    && ok "22 CLAUDE_CONFIG_DIR is honoured, \$HOME/.claude is read without it, READS_TRANSCRIPTS overrides both, and no transcripts is empty columns" \
    || ko "22 CLAUDE_CONFIG_DIR is honoured, \$HOME/.claude is read without it, READS_TRANSCRIPTS overrides both, and no transcripts is empty columns" "want $s22_want"$'\n'"got  $s22_got"

# READS_AREAS: only memory/ as a reference folder leaves the project files, the register and memory.
s22_got="$(READS_AREAS="memory" s22_rows "$s22_today")"
[[ "$s22_got" == "$s22_today,3,2,6,2,4,5,$s22_from" ]] \
    && ok "22 READS_AREAS names the reference folders: with memory alone, 6 reads of 4 of 5 files and the 2 searches aimed at it" \
    || ko "22 READS_AREAS names the reference folders: with memory alone, 6 reads of 4 of 5 files and the 2 searches aimed at it" "got $s22_got"

# READS_EXCLUDE: a project folder and a folder under docs/ leave the measure — three files out of the
# eleven, and the five reads of them out of the seventeen. A search of a folder left out is not one.
s22_got="$(READS_EXCLUDE="projects/one/ docs/sub" s22_rows "$s22_today")"
s22_got+="|$(READS_EXCLUDE="memory kit/docs/" s22_rows "$s22_today")"
s22_got+="|$(READS_EXCLUDE="memory kit/docs/" env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_cfg" bash "$READS" --target "$s22_w" --print 2>&1 | grep -c "kit's own Markdown  0 ")"
[[ "$s22_got" == "$s22_today,3,2,12,5,6,8,$s22_from|$s22_today,3,2,15,3,8,10,$s22_from|1" ]] \
    && ok "22 READS_EXCLUDE leaves folders and files out: out of the reference files, their reads and searches not counted, the kit's Markdown included" \
    || ko "22 READS_EXCLUDE leaves folders and files out: out of the reference files, their reads and searches not counted, the kit's Markdown included" "got $s22_got"

# --- --print, --help, and nothing written -------------------------------------------------------------
s22_out="$(env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_cfg" bash "$READS" --target "$s22_w" --print 2>&1)"; s22_rc=$?
s22_bad=""
[[ $s22_rc -eq 0 ]] || s22_bad+="--print exited $s22_rc"$'\n'
for s22_l in "the 7 days to $s22_today ($(s22_d 6) to $s22_today, UTC)" "reaching back to $s22_from" \
    'agent_sessions_7d                3 ' 'left out: 1)' 'sessions_reading_reference_7d    2   of 3 sessions' \
    'reference_reads_7d               17 ' 'reference_searches_7d            5' \
    'reference_files_read_7d          9   of 11 reference files' 'never read       2   of 11' "kit's own Markdown  1 " \
    'docs/ 10, projects/ 4, memory/ 2, logs/ 1'; do
    grep -qF -- "$s22_l" <<<"$s22_out" || s22_bad+="--print lacks: $s22_l"$'\n'
done
empty "22 --print states each count with its window and what it is out of" "$s22_bad${s22_bad:+$s22_out}"

s22_bad=""
for s22_f in $s22_ref docs/always.md kit/docs/guide.md; do
    grep -qF -- "$s22_f" <<<"$s22_out$s22_rep_out" && s22_bad+="a printed line names $s22_f"$'\n'
done
grep -qF 'pilot/reads.local.md' <<<"$s22_rep_out" || s22_bad+="--report does not say where the detail went"$'\n'
empty "22 --print and --report print counts and no file of the workspace; --report names only its own report" "$s22_bad"

s22_out="$(bash "$READS" --help 2>&1)"; s22_rc=$?
bash "$READS" --no-such-mode >/dev/null 2>&1; s22_rc2=$?
[[ $s22_rc -eq 0 && $s22_rc2 -eq 1 ]] && grep -qF -- '--print' <<<"$s22_out" && grep -qF -- '--report' <<<"$s22_out" \
    && grep -qF 'READS_AREAS' <<<"$s22_out" && grep -qF -- '--target' <<<"$s22_out" && grep -qF 'READS_EXCLUDE' <<<"$s22_out" \
    && grep -qF 'The count is a floor' <<<"$s22_out" && grep -qF 'plain ls or find' <<<"$s22_out" && grep -qF 'Claude Code only' <<<"$s22_out" \
    && ok "22 --help prints the modes, --target, READS_AREAS and the limits (a floor, what a search includes, Claude Code only) and exits 0; an unknown option exits 1" \
    || ko "22 --help prints the modes, --target, READS_AREAS and the limits (a floor, what a search includes, Claude Code only) and exits 0; an unknown option exits 1" "rc=$s22_rc,$s22_rc2 $s22_out"

# The report is the one file a run may write, and only where git ignores it.
s22_tree_after="$(cd "$s22_w" && find . -path ./.git -prune -o -print | grep -vxF -e ./pilot -e ./pilot/reads.local.md | sort; git -C "$s22_w" status --porcelain)"
[[ "$s22_tree_before" == "$s22_tree_after" ]] && git -C "$s22_w" check-ignore -q pilot/reads.local.md \
    && ok "22 pilot/reads.local.md is ignored by a workspace built from templates/workspace.gitignore, and nothing else was written there" \
    || ko "22 pilot/reads.local.md is ignored by a workspace built from templates/workspace.gitignore, and nothing else was written there" \
        "$(diff <(printf '%s\n' "$s22_tree_before") <(printf '%s\n' "$s22_tree_after"))"

# Where the ignore line is missing the report is refused, and --print still works.
s22_bare="$s22_dir/bare"
mkdir -p "$s22_bare/docs" && git -C "$s22_bare" init -q && printf '# A\n' > "$s22_bare/docs/a.md"
git -C "$s22_bare" add -A && git -C "$s22_bare" -c commit.gpgsign=false commit -q -m "One"
s22_out="$(env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_cfg" bash "$READS" --target "$s22_bare" --report 2>&1)"; s22_rc=$?
[[ $s22_rc -eq 1 && ! -e "$s22_bare/pilot" ]] && grep -qF 'not ignored by git' <<<"$s22_out" \
    && grep -qF 'reference_files_read_7d          0   of 1 reference files' <<<"$s22_out" \
    && ok "22 --report writes nothing where git would not ignore the report, says so and exits 1" \
    || ko "22 --report writes nothing where git would not ignore the report, says so and exits 1" "rc=$s22_rc $s22_out"

# --- The columns in metrics.csv -----------------------------------------------------------------------
s22_csv="$s22_dir/metrics.csv"
s22_out="$(env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_cfg" bash "$KIT/pilot/measure.sh" --target "$s22_w" --backfill 2 --out "$s22_csv" 2>&1)"; s22_rc=$?
s22_cols="agent_sessions_7d,sessions_reading_reference_7d,reference_reads_7d,reference_searches_7d,reference_files_read_7d,reference_files_total,transcripts_from"
s22_bad=""
[[ $s22_rc -eq 0 ]] || s22_bad+="measure.sh --backfill exited $s22_rc: $s22_out"$'\n'
[[ "$(head -n 1 "$s22_csv" | cut -d, -f21-)" == "$s22_cols" ]] || s22_bad+="the header's last columns are: $(head -n 1 "$s22_csv" | cut -d, -f21-)"$'\n'
s22_got="$(tail -n +2 "$s22_csv" | cut -d, -f1,21- | paste -sd' ' -)"
s22_want="$(s22_d 14),,,,,,10,$s22_from $(s22_d 7),1,1,1,0,1,10,$s22_from $s22_today,3,2,17,5,9,11,$s22_from"
[[ "$s22_got" == "$s22_want" ]] || s22_bad+="rows: want $s22_want"$'\n'"      got  $s22_got"$'\n'
[[ "$(awk -F, '{ print NF }' "$s22_csv" | sort -u)" == 27 ]] || s22_bad+="not every row has 27 fields"$'\n'
empty "22 measure.sh --backfill: the seven columns after the ablation columns, a row per week, a pruned week empty" "$s22_bad"

# Counts only: no path or file name of the fixture, no session id, no folder of the machine.
s22_bad=""
for s22_f in $s22_ref docs/always.md kit/docs/guide.md src/code.md projects/one/notes.md; do
    grep -qF -- "$s22_f" "$s22_csv" && s22_bad+="the CSV names $s22_f"$'\n'
    grep -qF -- "${s22_f##*/}" "$s22_csv" && s22_bad+="the CSV names ${s22_f##*/}"$'\n'
done
grep -qE '[0-9a-f]{8}-[0-9a-f]{4}-|toolu_|/' "$s22_csv" && s22_bad+="the CSV carries an id or a path"$'\n'
grep -vE '^(date,[a-z0-9_,]+|[0-9]{4}-[0-9]{2}-[0-9]{2}(,[0-9]*)*,([0-9]{4}-[0-9]{2}-[0-9]{2})?)$' "$s22_csv" | grep -q . && s22_bad+="a line of the CSV is not a header or dates and counts"$'\n'
empty "22 metrics.csv holds dates and counts only: no file name, path or session id from the transcripts" "$s22_bad"

# The daily row, a CSV with the older columns recomputed for its dates, and a copy of measure.sh with
# no reads.sh to call.
printf 'date,always_loaded_bytes\n%s,1\n' "$(s22_d 7)" > "$s22_dir/old.csv"
s22_out="$(env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_cfg" bash "$KIT/pilot/measure.sh" --target "$s22_w" --out "$s22_dir/old.csv" 2>&1)"
s22_got="$(tail -n +2 "$s22_dir/old.csv" | cut -d, -f1,21- | paste -sd' ' -)"
mkdir -p "$s22_dir/lone" && cp "$KIT/pilot/measure.sh" "$s22_dir/lone/measure.sh"
s22_lone="$(env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_cfg" bash "$s22_dir/lone/measure.sh" --target "$s22_w" --print 2>/dev/null | tail -n 1 | cut -d, -f21-)"
[[ "$s22_got" == "$(s22_d 7),1,1,1,0,1,10,$s22_from $s22_today,3,2,17,5,9,11,$s22_from" && "$s22_lone" == ",,,,,," ]] \
    && ok "22 measure.sh: the daily row and a recomputed older CSV carry the columns; without reads.sh they are empty, not zero" \
    || ko "22 measure.sh: the daily row and a recomputed older CSV carry the columns; without reads.sh they are empty, not zero" "rows: $s22_got"$'\n'"lone: $s22_lone"$'\n'"$s22_out"

# Nothing under either config folder was written, moved or touched by any run above.
[[ "$s22_before" == "$(s22_stamp "$s22_cfg"; s22_stamp "$s22_home")" ]] \
    && ok "22 the transcripts are as they were: same files, sizes and modification times" \
    || ko "22 the transcripts are as they were: same files, sizes and modification times" \
        "$(diff <(printf '%s\n' "$s22_before") <(s22_stamp "$s22_cfg"; s22_stamp "$s22_home"))"

# --- A system git config git cannot read (Claude Code's sandbox denies /etc) --------------------------
# The suite runs with the system config off; these runs turn it back on and point it at a folder, which
# git cannot read as a config. Plain git stops there, so the fixture bites; the pilot scripts do not.
mkdir -p "$s22_dir/unreadable-system-config"
s22_sys() { env -u GIT_CONFIG_NOSYSTEM -u GIT_ATTR_NOSYSTEM -u READS_TRANSCRIPTS GIT_CONFIG_SYSTEM="$s22_dir/unreadable-system-config" CLAUDE_CONFIG_DIR="$s22_cfg" "$@"; }
s22_bad=""
s22_sys git -C "$s22_w" rev-parse HEAD >/dev/null 2>&1 && s22_bad+="plain git still reads the repository, so this check proves nothing"$'\n'
s22_got="$(s22_sys bash "$KIT/pilot/measure.sh" --target "$s22_w" --print 2>&1 | tail -n 1 | cut -d, -f1,2,21-)"
[[ "$s22_got" == "$s22_today,$(( $(wc -c < "$s22_w/CLAUDE.md") + $(wc -c < "$s22_w/kit/CLAUDE.kit.md") + $(wc -c < "$s22_w/docs/always.md") )),3,2,17,5,9,11,$s22_from" ]] \
    || s22_bad+="measure.sh --print: $s22_got"$'\n'
s22_got="$(s22_sys bash "$READS" --target "$s22_w" --rows "$s22_today" 2>&1)"
[[ "$s22_got" == "$s22_today,3,2,17,5,9,11,$s22_from" ]] || s22_bad+="reads.sh --rows: $s22_got"$'\n'
s22_got="$(s22_sys bash "$KIT/pilot/ablate.sh" --target "$s22_w" --report 2>&1)"
[[ "$s22_got" == *"no results yet at pilot/ablation-results.csv"* && "$s22_got" != *"not a git repository"* ]] || s22_bad+="ablate.sh --report: $s22_got"$'\n'
empty "22 with a system git config git cannot read, measure.sh, reads.sh and ablate.sh still read the repository" "$s22_bad"
s22_got="$(grep -cE '^export GIT_CONFIG_NOSYSTEM=1$' "$KIT/pilot/ablate.sh")"
[[ "$s22_got" == 0 ]] && grep -qF 'git() { GIT_CONFIG_NOSYSTEM=1 GIT_ATTR_NOSYSTEM=1 command git "$@"; }' "$KIT/pilot/ablate.sh" \
    && ok "22 ablate.sh leaves the system config out of its own git calls only, not out of the runs it grades" \
    || ko "22 ablate.sh leaves the system config out of its own git calls only, not out of the runs it grades"

# The system attributes file goes the same way, so a run in the sandbox prints no git warning.
s22_bad=""
for s22_f in pilot/measure.sh pilot/reads.sh plugins/workspace/bin/state.sh; do
    grep -qxF 'export GIT_ATTR_NOSYSTEM=1' "$KIT/$s22_f" || s22_bad+="$s22_f does not set GIT_ATTR_NOSYSTEM"$'\n'
done
empty "22 measure.sh, reads.sh and state.sh leave the system attributes file out as well" "$s22_bad"

# --- The scripts themselves ---------------------------------------------------------------------------
check "22 pilot/reads.sh and pilot/measure.sh parse under /bin/bash" bash -c '/bin/bash -n "$1/pilot/reads.sh" && /bin/bash -n "$1/pilot/measure.sh"' _ "$KIT"
s22_got="$(env -u READS_TRANSCRIPTS CLAUDE_CONFIG_DIR="$s22_cfg" "$s22_bash" "$READS" --target "$s22_w" --rows "$s22_today" 2>&1)"
[[ "$s22_got" == "$s22_today,3,2,17,5,9,11,$s22_from" ]] && ok "22 reads.sh gives the same row under $s22_bash" \
    || ko "22 reads.sh gives the same row under $s22_bash" "$s22_got"
check "22 pilot/reads.sh is mode 100755 in the kit" test "$(git -C "$KITSRC" ls-files -s pilot/reads.sh | cut -c1-6)" = 100755
empty "22 reads.sh never writes under the config folder: no redirect, move or removal names it" \
    "$(grep -nE '(>|rm|mv|cp|touch|mkdir)[^#]*\$(tdir|tdir_p|\{?CLAUDE_CONFIG_DIR|HOME)' "$READS")"
empty "22 no home-folder machine path in reads.sh or this section" "$(grep -nE '/(Users|home)/' "$READS" "$KIT/tests/sections/22-reads.sh")"
if command -v shellcheck >/dev/null 2>&1; then
    check "22 shellcheck -x is clean on pilot/reads.sh, pilot/measure.sh and this section" \
        bash -c 'cd "$1" && shellcheck -x pilot/reads.sh pilot/measure.sh && shellcheck -x -s bash tests/sections/22-reads.sh' _ "$KIT"
else
    skp "22 shellcheck not on PATH; pilot/reads.sh and this section not linted"
fi

# --- The docs ---------------------------------------------------------------------------------------
s22_flat="$(tr '\n' ' ' < "$KIT/pilot/README.md" | tr -s ' ')"
s22_bad=""
for s22_l in '## Agent reads' 'bash kit/pilot/reads.sh --print' 'pilot/reads.local.md' 'cleanupPeriodDays' 'READS_AREAS' 'READS_EXCLUDE' \
    'looked, not that it acted' 'Cowork and claude.ai' 'never writes' 'The count is a floor' \
    'includes a plain listing (`ls`, `find`)' 'not that it looked something up' $(tr ',' ' ' <<<"$s22_cols"); do
    grep -qF -- "$s22_l" <<<"$s22_flat" || s22_bad+="pilot/README.md: no \"$s22_l\""$'\n'
done
grep -qF 'cleanupPeriodDays' "$KIT/setup.sh" || s22_bad+="setup.sh: the pilot's Next lines do not carry the retention note"$'\n'
[[ "$(grep -c 'cleanupPeriodDays' "$KIT/setup.sh")" -le 1 ]] || s22_bad+="setup.sh: the retention note is there more than once"$'\n'
empty "22 the pilot README has the Agent reads section, its limits (a floor; a search includes ls and find), every column and the retention note; setup.sh --pilot prints the note once" "$s22_bad"

# --- Speed --------------------------------------------------------------------------------------------
# 200 transcripts of 2,000 lines, read with the tools macOS ships (/usr/bin first on PATH, so its awk,
# sed, find and jq where they exist). One line in four is a tool call, half of those worth parsing.
s22_big="$s22_dir/big"
python3 - "$s22_big" "$s22_w" <<'PYBIG'
import datetime, json, os, sys
big, W = sys.argv[1:3]
day = (datetime.datetime.now(datetime.timezone.utc).date() - datetime.timedelta(days=1)).isoformat()
filler = "x" * 300
for s in range(200):
    sid = "%08d-3333-4333-8333-333333333333" % s
    d = os.path.join(big, "projects", "-ws"); os.makedirs(d, exist_ok=True)
    lines = []
    for n in range(2000):
        ts = "%sT%02d:%02d:%02d.000Z" % (day, n // 3600, n // 60 % 60, n % 60)
        e = {"type": "user", "sessionId": sid, "isSidechain": False, "cwd": W, "timestamp": ts, "message": {"role": "user", "content": filler}}
        if n % 4 == 0:
            k = n // 4 % 4
            t = ({"name": "Read", "input": {"file_path": W + "/docs/alpha.md"}} if k == 0 else
                 {"name": "Bash", "input": {"command": "cd docs && grep -n 'foo bar' beta.md | head -5; cat <<'EOF'\n" + filler + "\nEOF"}} if k == 1 else
                 {"name": "Bash", "input": {"command": "git status --short && git log --oneline -5 # " + filler[:80]}} if k == 2 else
                 {"name": "Edit", "input": {"file_path": W + "/src/code.md", "old_string": filler, "new_string": "y"}})
            t.update(type="tool_use", id="toolu_%d_%d" % (s, n))
            e = {"type": "assistant", "sessionId": sid, "isSidechain": False, "cwd": W, "timestamp": ts, "message": {"role": "assistant", "content": [t]}}
        lines.append(json.dumps(e))
    with open(os.path.join(d, sid + ".jsonl"), "w") as f: f.write("\n".join(lines) + "\n")
# One more, quiet for twenty days, so the transcripts reach back past the window.
old = (datetime.datetime.now(datetime.timezone.utc).date() - datetime.timedelta(days=20)).isoformat()
with open(os.path.join(big, "projects", "-ws", "old.jsonl"), "w") as f:
    f.write(json.dumps({"type": "assistant", "sessionId": "old", "isSidechain": False, "cwd": "/nowhere", "timestamp": old + "T12:00:00.000Z", "message": {"content": []}}) + "\n")
PYBIG
s22_t0="$(python3 -c 'import time; print(time.time())')"
s22_got="$(PATH="/usr/bin:/bin:$PATH" READS_TRANSCRIPTS="$s22_big/projects" bash "$READS" --target "$s22_w" --rows "$s22_today" 2>&1)"
s22_secs="$(python3 -c 'import sys,time; print("%.1f" % (time.time() - float(sys.argv[1])))' "$s22_t0")"
[[ "$s22_got" == "$s22_today,200,200,50000,0,2,11,$s22_from" ]] && python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 10 else 1)' "$s22_secs" \
    && ok "22 200 transcripts of 2,000 lines are read in under 10 seconds ($s22_secs s): 200 sessions, 50,000 reads of 2 files" \
    || ko "22 200 transcripts of 2,000 lines are read in under 10 seconds ($s22_secs s): 200 sessions, 50,000 reads of 2 files" "took $s22_secs s; got $s22_got"

# --- The scratch folder -------------------------------------------------------------------------------
# While it runs, reads.sh keeps the workspace's reference paths in a scratch folder: under TMPDIR, this
# user's only, and gone however the run ends. The long run above is interrupted mid-read, as Ctrl-C
# and a kill would do it (the signal goes to the script and the tools it started).
s22_tmp="$s22_dir/tmp"
mkdir -p "$s22_tmp/done" "$s22_tmp/fail" "$s22_tmp/int" "$s22_tmp/term" "$s22_dir/stub"
cat > "$s22_dir/interrupt.py" <<'PYINT'
import glob, os, signal, stat, subprocess, sys, time
script, target, tdir, tmp, day, name = sys.argv[1:7]
env = dict(os.environ, TMPDIR=tmp, READS_TRANSCRIPTS=tdir)
p = subprocess.Popen(["/bin/bash", script, "--target", target, "--rows", day], env=env, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True,
                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
seen, open_modes, t0 = 0, [], time.time()
while time.time() - t0 < 30 and p.poll() is None:
    work = glob.glob(os.path.join(tmp, "reads.*"))
    if work and os.path.exists(os.path.join(work[0], "events")):
        seen = 1
        for d, _, fs in os.walk(work[0]):
            for f in [d] + [os.path.join(d, f) for f in fs]:
                try:
                    if stat.S_IMODE(os.stat(f).st_mode) & 0o077: open_modes.append(os.path.basename(f))
                except OSError: pass
        break
    time.sleep(0.05)
if p.poll() is None: os.killpg(p.pid, getattr(signal, name))
try: rc = p.wait(timeout=30)
except subprocess.TimeoutExpired: rc = "still running"
print("seen=%d open=%s left=%d rc=%s" % (seen, ",".join(open_modes) or "none", len(glob.glob(os.path.join(tmp, "*"))), rc))
PYINT
s22_got="int: $(python3 "$s22_dir/interrupt.py" "$READS" "$s22_w" "$s22_big/projects" "$s22_tmp/int" "$s22_today" SIGINT)
term: $(python3 "$s22_dir/interrupt.py" "$READS" "$s22_w" "$s22_big/projects" "$s22_tmp/term" "$s22_today" SIGTERM)"
[[ "$s22_got" == "int: seen=1 open=none left=0 rc=130
term: seen=1 open=none left=0 rc=143" ]] \
    && ok "22 interrupted mid-read (INT, TERM), reads.sh removes its scratch folder; while it ran, the folder and its files were this user's only" \
    || ko "22 interrupted mid-read (INT, TERM), reads.sh removes its scratch folder; while it ran, the folder and its files were this user's only" "$s22_got"

# A run that finishes and a run that fails part-way (an awk that exits 7) leave nothing either.
printf '#!/bin/sh\nexit 7\n' > "$s22_dir/stub/awk" && chmod +x "$s22_dir/stub/awk"
env -u READS_TRANSCRIPTS TMPDIR="$s22_tmp/done" CLAUDE_CONFIG_DIR="$s22_cfg" bash "$READS" --target "$s22_w" --print >/dev/null 2>&1; s22_rc=$?
env -u READS_TRANSCRIPTS TMPDIR="$s22_tmp/fail" CLAUDE_CONFIG_DIR="$s22_cfg" PATH="$s22_dir/stub:$PATH" bash "$READS" --target "$s22_w" --print >/dev/null 2>&1; s22_rc2=$?
s22_left="$(find "$s22_tmp/done" "$s22_tmp/fail" -mindepth 1 | head -n 5)"
[[ $s22_rc -eq 0 && $s22_rc2 -ne 0 && -z "$s22_left" ]] \
    && ok "22 a finished run and a failed one leave nothing under TMPDIR" \
    || ko "22 a finished run and a failed one leave nothing under TMPDIR" "rc=$s22_rc,$s22_rc2 left: $s22_left"
[[ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$s22_rep")" == 0o600 ]] \
    && ok "22 pilot/reads.local.md, which names files, is readable by its owner only" \
    || ko "22 pilot/reads.local.md, which names files, is readable by its owner only" "$(ls -l "$s22_rep")"
