#!/usr/bin/env bash
# Agent reads, counted from Claude Code's own transcripts: how often the agents working in a workspace
# opened its reference files. The transcripts are read and never written; only counts are printed.
#
#   pilot/reads.sh --print           the counts for the seven days to today; nothing written
#   pilot/reads.sh --report          the same, and the per-file detail in pilot/reads.local.md (a
#                                    local file git ignores: which files were read, which never were)
#   --target <dir>                   count for that workspace (default: the one the command is run in,
#                                    so bash kit/pilot/reads.sh from a workspace's root counts it)
#   --help                           this text
#   pilot/reads.sh --rows <date>...  measure.sh's call: one "date,<seven columns>" line per date
#   READS_AREAS="docs memory logs" pilot/reads.sh
#                                    the folders whose tracked Markdown counts as reference; project
#                                    READMEs, decisions files and the register are always added
#   READS_EXCLUDE="projects/tooling/" pilot/reads.sh
#                                    folders or files, by path from the root, left out: out of the
#                                    reference files, their reads and searches not counted. The way
#                                    to keep a project about the tooling itself out of the measure
#   READS_TRANSCRIPTS=<dir> pilot/reads.sh
#                                    read transcripts from that folder rather than Claude Code's own
#                                    (default: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects)
#
# A session is one Claude Code transcript and its subagents'. It belongs to the workspace when it was
# started inside it; one started inside the workspace's kit/ is kit development and is left out. A
# read is one tool call opening one reference file: the Read tool, or a Bash cat, head, tail, less,
# sed -n, awk, grep or rg naming the file. A search is a Grep or Glob call, or a Bash grep, rg, find
# or ls, aimed at a reference folder. An edit is not a read, and the always-loaded files are not
# reference: they load with no tool call. The window is the seven days ending on the row's date, in
# UTC, the one measure.sh uses. A window that does not start after the oldest transcript on this
# machine is reported empty, not zero: Claude Code prunes transcripts (cleanupPeriodDays, 30 by default).
#
# The count is a floor. A read through something this script does not parse is not seen: a script
# that opens the file itself, git show, a loop over a variable, a command handed to another shell.
# A search includes a plain ls or find of a reference folder, so it is not "the agent looked
# something up". Cowork and claude.ai sessions leave no transcript here: Claude Code only.
set -euo pipefail

usage() { sed -n '2,35p' "$0"; exit "${1:-1}"; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

mode=print target="" days=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --print) mode=print; shift ;;
        --report) mode=report; shift ;;
        --target) target="${2:-}"; [[ -n "$target" ]] || usage; shift 2 ;;
        --rows) mode=rows; shift
            while [[ $# -gt 0 && "$1" != --* ]]; do
                [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage
                days+=("$1"); shift
            done ;;
        --help|-h) usage 0 ;;
        *) usage ;;
    esac
done

# Claude Code's Bash sandbox denies /etc, and git stops outright on a system config it cannot read.
# Nothing counted here lives in the system config, so it is not read, as in measure.sh.
export GIT_CONFIG_NOSYSTEM=1
# The same for the system attributes file: unreadable, it costs a warning on every call that looks.
export GIT_ATTR_NOSYSTEM=1
# Every git call reads only: optional locks off, so a run beside a live session never leaves an
# index.lock behind.
git() { command git --no-optional-locks "$@"; }

root="$(git -C "${target:-.}" rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "reads.sh: ${target:-this folder} is not inside a git repository" >&2; exit 1; }
root="$(cd "$root" && pwd -P)"
cd "$root"

# The reference list is measure.sh's to compute, so the two scripts cannot disagree about it.
measure_sh="$here/measure.sh"
[[ -f "$measure_sh" ]] || measure_sh="$root/kit/pilot/measure.sh"
[[ -f "$measure_sh" ]] || { echo "reads.sh: no measure.sh beside this script or in kit/pilot/" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "reads.sh: needs jq to read the transcripts; nothing counted" >&2; exit 1; }

tdir="${READS_TRANSCRIPTS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}"
today="$(date -u +%F)"
[[ "$mode" == rows ]] || days=("$today")
[[ ${#days[@]} -gt 0 ]] || exit 0

# The scratch folder holds the workspace's reference paths while the script runs: made by mktemp under
# TMPDIR (macOS mktemp ignores TMPDIR unless given a template), readable by this user only, and removed
# however the run ends — finished, failed or interrupted.
old_umask="$(umask)"
umask 077
work="$(mktemp -d "${TMPDIR:-/tmp}/reads.XXXXXX")"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# window_start <day>: the first of the seven days ending on <day>. GNU and BSD date differ.
window_start() { date -u -d "$1 -6 days" +%F 2>/dev/null || date -u -j -v-6d -f %F "$1" +%F; }

# --- What counts as reference, per date -------------------------------------------------------------
# Each date has its own list, as the repository stood at the end of that day. The transcripts are
# matched once against every file on any of the lists; each date's counts then keep only its own.
: > "$work/ref.all"; : > "$work/always.all"; : > "$work/area.all"; : > "$work/exclude.all"
for d in "${days[@]}"; do
    bash "$measure_sh" --target "$root" --reads-lists "$d" > "$work/lists" 2>/dev/null || : > "$work/lists"
    awk -F'\t' '$1 == "ref" { print $2 }' "$work/lists" | LC_ALL=C sort -u > "$work/ref.$d"
    cat "$work/ref.$d" >> "$work/ref.all"
    awk -F'\t' '$1 == "always" { print $2 }' "$work/lists" >> "$work/always.all"
    awk -F'\t' '$1 == "area" { print $2 }' "$work/lists" >> "$work/area.all"
    awk -F'\t' '$1 == "exclude" { print $2 }' "$work/lists" >> "$work/exclude.all"
done

# --- Reading the transcripts ------------------------------------------------------------------------
# jq turns each transcript line into one tab-separated line for the dated entry and one for each
# Read, Bash, Grep or Glob call in it; awk does the rest. Each line is parsed on its own (fromjson?),
# so a line cut short by a live session is skipped rather than ending the file.
#
# The files reach jq as one stream, each behind a line break and a "==> file <==" line of its own.
# Handed the files directly, jq joins a file's unfinished last line to the first line of the next
# file and both are lost, so what was counted would depend on the order the files came in. The header
# line also says which file an entry is from, for the entry that names no session. cat does the
# copying: tail -n +1 writes the same headers and takes twice as long as everything else here. Nothing a transcript
# says reaches the disk: awk writes only session ids, dates and the workspace's own reference paths.
# shellcheck disable=SC2016  # a jq program: its $ names are jq's, not the shell's
jq_prog='
if startswith("==> ") and endswith(" <==") then "F\t" + .[4:-4] else
fromjson? | objects | select(.timestamp | type == "string")
| [(.sessionId // ""), .timestamp, (.cwd // ""), (if .isSidechain == true then 1 else 0 end), ""] as $h
| (["E"] + $h + [(if .type == "assistant" then 1 else 0 end)]),
  ( select(.type == "assistant") | .message.content? | arrays | .[] | objects | select(.type == "tool_use")
    | (.input | objects) as $i
    | if .name == "Read" then ["T"] + $h + [.id, "Read", ($i.file_path // ""), "", ""]
      elif .name == "Bash" then ["T"] + $h + [.id, "Bash", "", ($i.command // ""), ""]
      elif .name == "Grep" then ["T"] + $h + [.id, "Grep", ($i.path // ""), "", ($i.glob // "")]
      elif .name == "Glob" then ["T"] + $h + [.id, "Glob", ($i.path // ""), ($i.pattern // ""), ""]
      else empty end )
| map(if type == "string" or type == "number" then . else tostring end) | @tsv
end'

# The events, one per line:
#   G <day>                 how far back the transcripts reach: the last day of the one that
#                           went quiet longest ago
#   A <session> <day> <in|kit>   the agent answered in that session on that day
#   R <session> <day> <path>     a read of a reference file          (sessions in the workspace only)
#   K <session> <day> <path>     a read of a Markdown file under kit/, counted apart
#   Q <session> <day>            a search aimed at a reference folder
# shellcheck disable=SC2016  # an awk program: its $ fields are awk's, not the shell's
scan_awk='
BEGIN {
    FS = "\t"
    while ((getline line < reffile) > 0) ref[line] = 1
    while ((getline line < alwaysfile) > 0) always[line] = 1
    while ((getline line < excludefile) > 0) excl[line] = 1
    while ((getline line < areafile) > 0) { area[line] = 1; n = split(line, seg, "/"); areaword[seg[n]] = 1 }
    # A search is aimed at a folder, and a folder is known only by what git tracks in it: a reference
    # folder itself, or any folder under one that holds a reference file. A grep pattern or an option
    # value that happens to resolve inside a reference folder is not one.
    for (a in area) refdir[a] = 1
    for (line in ref) { d = line; while (sub(/\/[^\/]*$/, "", d)) if (in_area(d)) refdir[d] = 1 }
    rootlen = length(root)
    resolve_cmd = "cd -- \"$(cat \047" cwdfile "\047)\" 2>/dev/null && pwd -P"
    split("cat head tail less sed awk grep egrep fgrep rg", w, " "); for (i in w) readverb[w[i]] = 1
    split("grep egrep fgrep rg find ls", w, " "); for (i in w) searchverb[w[i]] = 1
    split("sudo command env time nohup nice do then else elif if while until ! {", w, " "); for (i in w) wrapper[w[i]] = 1
}

# @tsv writes a tab, a newline and a backslash inside a value as \t, \n and \\.
function unesc(s) {
    if (index(s, "\\") == 0) return s
    gsub(/\\\\/, "\001", s); gsub(/\\n/, "\n", s); gsub(/\\t/, "\t", s); gsub(/\\r/, "", s); gsub(/\001/, "\\", s)
    return s
}

# physical(dir): the folder as pwd -P gives it, when it still exists; else as the transcript wrote it.
# The folder goes to the shell in a file, never on a command line.
function physical(c,   r) {
    if (c in phys) return phys[c]
    r = ""
    if (resolve && substr(c, 1, 1) == "/") {
        printf "%s", c > cwdfile; close(cwdfile)
        if ((resolve_cmd | getline r) <= 0) r = ""
        close(resolve_cmd)
    }
    return phys[c] = (r == "" ? c : r)
}

# norm(path): an absolute path with ., .. and doubled slashes folded.
function norm(p,   n, i, k, seg, parts, out) {
    n = split(p, seg, "/"); k = 0
    for (i = 1; i <= n; i++) {
        if (seg[i] == "" || seg[i] == ".") continue
        if (seg[i] == "..") { if (k > 0) k--; continue }
        parts[++k] = seg[i]
    }
    out = ""
    for (i = 1; i <= k; i++) out = out "/" parts[i]
    return out == "" ? "/" : out
}

# absolute(path): a path argument made absolute against the folder the command runs in, or "" when it
# cannot be known (a variable in it, or a relative path after a cd that could not be followed).
function absolute(p) {
    if (p ~ /[$`]/) return ""
    if (p == "~") p = home; else if (substr(p, 1, 2) == "~/") p = home substr(p, 2)
    if (substr(p, 1, 1) != "/") { if (dir == "") return ""; p = dir "/" p }
    else if (rawcwd != physcwd && (p == rawcwd || substr(p, 1, length(rawcwd) + 1) == rawcwd "/")) p = physcwd substr(p, length(rawcwd) + 1)
    return norm(p)
}

# inside(absolute path): the path as the workspace names it ("" for its root), or "\001" outside it.
# A worktree Claude Code keeps under .claude/worktrees/ holds the same files, so its paths read as
# the workspace own.
function inside(p,   r) {
    if (p == "") return "\001"
    if (p == root) return ""
    if (substr(p, 1, rootlen + 1) != root "/") return "\001"
    r = substr(p, rootlen + 2)
    if (r ~ /^\.claude\/worktrees\/[^\/]+$/) return ""
    sub(/^\.claude\/worktrees\/[^\/]+\//, "", r)
    return r
}
function where(p) { return inside(absolute(p)) }

# excluded(path): 1 at or under a READS_EXCLUDE path. The reference files and folders already leave
# those out; this keeps the Markdown under kit/, which is matched by name, to the same rule.
function excluded(r,   x) {
    for (x in excl) if (r == x || substr(r, 1, length(x) + 1) == x "/") return 1
    return 0
}

function in_area(r,   a) {
    if (r == "\001" || r == "") return 0
    for (a in area) if (r == a || substr(r, 1, length(a) + 1) == a "/") return 1
    return 0
}

# read_event(path): 1 when the path is a reference file or a Markdown file of the kit. One read per
# tool call and file, however many times the call names it.
function read_event(r,   kind) {
    if (r == "\001" || r == "") return 0
    if (r in ref) kind = "R"
    else if (r ~ /^kit\/.*\.md$/ && !(r in always) && !excluded(r)) kind = "K"
    else return 0
    if (!((tid, r) in counted)) { counted[tid, r] = 1; ev[++nev] = kind "\t" sid "\t" day "\t" r }
    return 1
}
function search_event() { if (!(tid in searched)) { searched[tid] = 1; ev[++nev] = "Q\t" sid "\t" day } }

# lead(pattern): the folder a file name pattern is rooted in — the part before its first wildcard, cut
# back to a whole folder; a pattern with no wildcard is returned whole.
function lead(g,   k) {
    k = match(g, /[*?\[{]/)
    if (!k) return g
    g = substr(g, 1, k - 1)
    return match(g, /.*\//) ? substr(g, 1, RLENGTH - 1) : "."
}

# glob_reads(token): a read for every reference file a shell pattern such as docs/*.md names.
function glob_reads(t,   d, rest, re, f) {
    d = lead(t); rest = (d == "." && substr(t, 1, 2) != "./") ? t : substr(t, length(d) + 2)
    d = where(d)
    if (d == "\001") return
    re = rest; gsub(/[.+(){}|^$\\]/, "\\\\&", re); gsub(/\*\*\//, "\002", re); gsub(/\*/, "[^/]*", re); gsub(/\?/, "[^/]", re); gsub(/\002/, "(.*/)?", re)
    re = "^" re "$"
    for (f in ref) if (d == "" ? f ~ re : (substr(f, 1, length(d) + 1) == d "/" && substr(f, length(d) + 2) ~ re)) read_event(f)
}

function end_token() {
    if (tok == "" && !quoted) return
    if (want) { pending = tok; want = 0 }
    else if (redir) redir = 0
    else argv[++argc] = tok
    tok = ""; quoted = 0
}

# end_command(operator): one simple command, as its words. cd moves the folder the rest of the line
# runs in; a parenthesis keeps the move to itself.
function end_command(op,   i, a, v, t, r, sedn, sedi) {
    i = 1
    while (i <= argc && (argv[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || (argv[i] in wrapper))) i++
    if (i <= argc) {
        v = argv[i]; sub(/.*\//, "", v)
        if (v == "cd") dir = (i == argc) ? home : (i + 1 == argc && argv[argc] != "-") ? absolute(argv[argc]) : ""
        else if ((v in readverb) || (v in searchverb)) {
            sedn = sedi = 0
            if (v == "sed") for (a = i + 1; a <= argc; a++) {
                if (argv[a] ~ /^-[A-Za-z]*n[A-Za-z]*$/) sedn = 1
                if (argv[a] ~ /^-[A-Za-z]*i/ || argv[a] ~ /^--in-place/) sedi = 1
            }
            # sed reads when it prints (-n) and does not edit in place.
            if (v != "sed" || (sedn && !sedi)) for (a = i + 1; a <= argc; a++) {
                t = argv[a]
                if (substr(t, 1, 1) == "-") continue
                if (t ~ /[*?\[]/) {
                    if (v in searchverb) { if (where(lead(t)) in refdir) search_event() }
                    else glob_reads(t)
                    continue
                }
                r = where(t)
                if ((v in readverb) && read_event(r)) continue
                if ((v in searchverb) && (r in refdir)) search_event()
            }
        }
    }
    if (op == "(") stack[++depth] = dir
    else if (op == ")" && depth > 0) dir = stack[depth--]
    argc = 0; redir = 0
}

# bash_command(text): the words of a shell command, well enough to find the files it reads: quotes,
# escapes, comments, redirections (a file written to is not read) and here-documents (their text is
# data, not commands). A command inside a string handed to another shell is not followed.
function bash_command(cmd,   lines, nl, li, line, n, i, c, t, cont) {
    sq = dq = 0; tok = ""; quoted = 0; argc = 0; redir = 0; want = 0; heredoc = ""; inhere = 0; pending = ""; depth = 0
    dir = physcwd
    nl = split(cmd, lines, "\n")
    for (li = 1; li <= nl; li++) {
        line = lines[li]
        if (inhere) { t = line; sub(/^\t+/, "", t); if (t == heredoc) inhere = 0; continue }
        n = length(line); cont = 0
        for (i = 1; i <= n; i++) {
            c = substr(line, i, 1)
            if (sq) { if (c == "\047") sq = 0; else tok = tok c; continue }
            if (dq) {
                if (c == "\"") dq = 0
                else if (c == "\\" && i < n) { i++; tok = tok substr(line, i, 1) }
                else tok = tok c
                continue
            }
            if (c == " " || c == "\t") { end_token(); continue }
            if (c == "\047") { sq = 1; quoted = 1; continue }
            if (c == "\"") { dq = 1; quoted = 1; continue }
            if (c == "\\") { if (i == n) cont = 1; else { i++; tok = tok substr(line, i, 1) } continue }
            if (c == "#" && tok == "" && !quoted) break
            if (c == "<") {
                end_token()
                if (substr(line, i, 3) == "<<<") i += 2
                else if (substr(line, i, 2) == "<<") { i++; if (substr(line, i + 1, 1) == "-") i++; want = 1 }
                continue
            }
            if (c == ">") {
                end_token()
                if (substr(line, i + 1, 1) == ">") i++
                if (substr(line, i + 1, 1) == "&") i++
                redir = 1; continue
            }
            if (c == "|" || c == ";" || c == "&" || c == "(" || c == ")" || c == "`") { end_token(); end_command(c); continue }
            tok = tok c
        }
        if (sq || dq) { tok = tok "\n"; continue }
        end_token()
        if (!cont) end_command(";")
        if (pending != "") { heredoc = pending; pending = ""; inhere = 1 }
    }
    end_token(); end_command(";")
}

# session_of(file): the session a transcript file belongs to, from where it sits — <slug>/<id>.jsonl,
# or anywhere under <slug>/<id>/ for its subagents. Used only for an entry that names no session.
function session_of(f,   n, i, seg) {
    if (substr(f, 1, length(tdir)) != tdir) return ""
    n = split(substr(f, length(tdir) + 1), seg, "/")
    while (n > 0 && seg[1] == "") { for (i = 1; i < n; i++) seg[i] = seg[i + 1]; n-- }
    if (n < 2) return ""
    sub(/\.jsonl$/, "", seg[2])
    return seg[2]
}

# The file the entries that follow are from.
$1 == "F" { curfile = $2; next }

{
    day = substr($3, 1, 10)
    if (day !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) next
    sid = ($2 != "") ? $2 : session_of(curfile)
    if (sid == "") next
    if (!(sid in last_day) || day > last_day[sid]) last_day[sid] = day
}

# A session is placed by the folder it started in: the earliest entry of its own transcript, or of a
# subagent transcript when that is all there is.
$1 == "E" {
    if ($4 != "") {
        if ($5 == 0) { if (!(sid in first_ts) || $3 < first_ts[sid]) { first_ts[sid] = $3; first_cwd[sid] = $4 } }
        else if (!(sid in side_ts) || $3 < side_ts[sid]) { side_ts[sid] = $3; side_cwd[sid] = $4 }
    }
    if ($7 == 1 && !((sid, day) in active)) { active[sid, day] = 1; act[++nact] = sid "\t" day }
    next
}

$1 == "T" {
    tid = $7
    # A transcript can hold the same call twice (a resumed session carries its history); count it once.
    if (tid == "" || (tid in seen_call)) next
    seen_call[tid] = 1
    rawcwd = unesc($4); physcwd = physical(rawcwd); dir = physcwd
    if ($8 == "Read") read_event(where(unesc($9)))
    else if ($8 == "Bash") {
        cmd = $10
        # Most commands name no Markdown file and no reference folder; only the rest are worth the words.
        r = inside(physcwd)
        hit = (index(cmd, ".md") > 0 || (r != "" && r != "\001"))
        if (!hit) for (a in areaword) if (index(cmd, a) > 0) { hit = 1; break }
        if (hit) bash_command(unesc(cmd))
    }
    else if ($8 == "Grep") {
        r = where($9 == "" ? "." : unesc($9))
        if (!read_event(r)) {
            g = unesc($11)
            if (g != "" && lead(g) != ".") r = where(($9 == "" ? "." : unesc($9)) "/" lead(g))
            if (r in refdir) search_event()
        }
    }
    else if ($8 == "Glob") {
        g = lead(unesc($10))
        if (where(substr(g, 1, 1) == "/" ? g : ($9 == "" ? "." : unesc($9)) "/" g) in refdir) search_event()
    }
    next
}

END {
    for (sid in side_ts) if (!(sid in first_ts)) first_cwd[sid] = side_cwd[sid]
    for (sid in first_cwd) {
        r = inside(norm(physical(unesc(first_cwd[sid]))))
        class[sid] = (r == "\001") ? "out" : (r == "kit" || r ~ /^kit\//) ? "kit" : "in"
    }
    # Claude Code prunes a transcript by when it was last written, so what is still here reaches back
    # to the transcript that went quiet longest ago, not to the oldest entry in a long-lived one.
    for (sid in last_day) if (oldest == "" || last_day[sid] < oldest) oldest = last_day[sid]
    print "G\t" oldest
    for (i = 1; i <= nact; i++) { split(act[i], f, "\t"); if ((f[1] in class) && class[f[1]] != "out") print "A\t" act[i] "\t" class[f[1]] }
    for (i = 1; i <= nev; i++) { split(ev[i], f, "\t"); if (class[f[2]] == "in") print ev[i] }
}'

LC_ALL=C sort -u "$work/ref.all" > "$work/ref"
LC_ALL=C sort -u "$work/always.all" > "$work/always"
LC_ALL=C sort -u "$work/area.all" > "$work/area"
LC_ALL=C sort -u "$work/exclude.all" > "$work/exclude"
: > "$work/events"; : > "$work/errors"
# A folder path with a quote in it cannot be handed to the shell safely from awk; then a session's
# folder is compared as the transcript wrote it.
resolve=1; [[ "$work" != *"'"* ]] || resolve=0
if [[ -d "$tdir" ]]; then
    tdir_p="$(cd "$tdir" && pwd -P)"
    # The files in a fixed order, so two runs read alike. READS_TEST_ORDER is the tests' own: set, it
    # reverses the order, and the counts have to come out the same.
    # shellcheck disable=SC2016  # the sh program's $f is its own
    { find "$tdir_p" -type f -name '*.jsonl' -print0 | LC_ALL=C sort -z ${READS_TEST_ORDER:+-r} \
        | xargs -0 sh -c 'for f do printf "\n==> %s <==\n" "$f"; cat "$f"; done' sh 2> "$work/errors" \
        | jq -R -r "$jq_prog" 2>> "$work/errors" || true; } \
        | LC_ALL=C awk -v root="$root" -v home="${HOME:-}" -v tdir="$tdir_p" -v resolve="$resolve" -v cwdfile="$work/cwd" \
            -v reffile="$work/ref" -v alwaysfile="$work/always" -v areafile="$work/area" -v excludefile="$work/exclude" "$scan_awk" > "$work/events"
    # A transcript that could not be read is said, as a count; what jq said about it is not repeated.
    if [[ -s "$work/errors" ]]; then
        echo "reads.sh: $(grep -c . "$work/errors") transcript read errors; the counts leave those files out" >&2
    fi
fi

# --- Counting a window ------------------------------------------------------------------------------
# counts <day>: tab-separated — the seven columns, then kit development sessions left out, reads of
# the kit, and whether the window is a gap: there is no transcript, or the window does not start after
# the day the transcripts reach back to. That day itself may be part pruned, so it is not counted on.
# With no transcript at all the oldest date is written "-", so no field is ever empty.
# shellcheck disable=SC2016  # an awk program, as above
counts_awk='
BEGIN { FS = "\t"; while ((getline line < reffile) > 0) { ref[line] = 1; total++ } }
$1 == "G" { from = $2; next }
$3 < s || $3 > e { next }
$1 == "A" { if ($4 == "in") { if (!($2 in sess)) { sess[$2] = 1; ns++ } } else if (!($2 in ksess)) { ksess[$2] = 1; nk++ } next }
$1 == "R" && ($4 in ref) { reads++; if (!($2 in rs)) { rs[$2] = 1; nrs++ } if (!($4 in fr)) { fr[$4] = 1; nf++ } next }
$1 == "Q" { q++; next }
$1 == "K" { kr++; next }
END { printf "%d\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%d\n", ns, nrs, reads, q, nf, total, (from == "" ? "-" : from), nk, kr, (from == "" || s <= from) }'
counts() { awk -v s="$(window_start "$1")" -v e="$1" -v reffile="$work/ref.$1" "$counts_awk" "$work/events"; }

if [[ "$mode" == rows ]]; then
    for d in "${days[@]}"; do
        counts "$d" | awk -F'\t' -v d="$d" '{ if ($7 == "-") $7 = ""
            if ($10 == 1) print d ",,,,,," $6 "," $7; else print d "," $1 "," $2 "," $3 "," $4 "," $5 "," $6 "," $7 }'
    done
    exit 0
fi

# --- The printed counts, and the local report ---------------------------------------------------------
start="$(window_start "$today")"
IFS=$'\t' read -r n_sess n_reading n_reads n_search n_files n_total from n_kit n_kitreads gap < <(counts "$today")
[[ "$from" != "-" ]] || from=""
n_tfiles=0 n_tbytes=0
if [[ -d "$tdir" ]]; then
    read -r n_tfiles n_tbytes < <(find "$tdir_p" -type f -name '*.jsonl' -print0 | xargs -0 wc -c 2>/dev/null \
        | awk '!($2 == "total" && NF == 2) { n++; b += $1 } END { print n + 0, b + 0 }')
fi

summary() {
    echo "Agent reads: the 7 days to $today ($start to $today, UTC)"
    if [[ -z "$from" ]]; then
        echo "  no transcripts on this machine: nothing to count (0 files)"
        echo "  reference_files_total            $n_total"
        return
    fi
    echo "  transcripts read                 $n_tfiles files, $((n_tbytes / 1048576)) MB; reaching back to $from (transcripts_from)"
    if [[ "$gap" == 1 ]]; then
        echo "  the window starts on or before the day the transcripts reach back to ($from): no count for it, rather than a zero"
        echo "  reference_files_total            $n_total"
        return
    fi
    echo "  agent_sessions_7d                $n_sess   Claude Code sessions in the workspace (kit development, left out: $n_kit)"
    echo "  sessions_reading_reference_7d    $n_reading   of $n_sess sessions"
    echo "  reference_reads_7d               $n_reads   by $n_reading sessions"
    echo "  reference_searches_7d            $n_search"
    echo "  reference_files_read_7d          $n_files   of $n_total reference files (reference_files_total)"
    echo "  reference files never read       $((n_total - n_files))   of $n_total"
    echo "  reads of the kit's own Markdown  $n_kitreads   counted apart, in none of the figures above"
    # By area: the first folder of each file read.
    awk -F'\t' -v s="$start" -v e="$today" -v reffile="$work/ref.$today" '
        BEGIN { while ((getline line < reffile) > 0) ref[line] = 1 }
        $1 == "R" && $3 >= s && $3 <= e && ($4 in ref) { a = $4; sub(/\/.*/, "", a); n[a]++ }
        END { for (a in n) printf "%d\t%s\n", n[a], a }' "$work/events" | LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k2,2 \
        | awk -F'\t' '{ printf "%s%s/ %d", (NR == 1 ? "  reads by area                    " : ", "), $2, $1 } END { if (NR) print "" }'
}

summary
[[ "$mode" == report ]] || exit 0

report="pilot/reads.local.md"
# The report names files, so it is written only where git ignores it.
if ! git check-ignore -q "$report" 2>/dev/null; then
    echo "reads.sh: $report is not ignored by git here; add *.local.* to .gitignore first. No report written." >&2
    exit 1
fi
# The folder is made as any other of the workspace's; the report itself stays readable by this user only.
(umask "$old_umask"; mkdir -p pilot)
{
    echo "# Agent reads: the per-file detail"
    echo
    echo "*Written by \`kit/pilot/reads.sh --report\` on $today. Local to this machine and ignored by git:"
    echo "it names files. The counts alone go in \`pilot/metrics.csv\`.*"
    echo
    echo '```'
    summary
    echo '```'
    if [[ -n "$from" && "$gap" != 1 ]]; then
        echo
        echo "## Reference files read ($n_files of $n_total)"
        echo
        echo "| Reads | Sessions | File |"
        echo "|---:|---:|---|"
        awk -F'\t' -v s="$start" -v e="$today" -v reffile="$work/ref.$today" '
            BEGIN { while ((getline line < reffile) > 0) ref[line] = 1 }
            $1 == "R" && $3 >= s && $3 <= e && ($4 in ref) { n[$4]++; if (!(($4, $2) in seen)) { seen[$4, $2] = 1; m[$4]++ } }
            END { for (f in n) printf "%d\t%d\t%s\n", n[f], m[f], f }' "$work/events" | LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k3,3 \
            | awk -F'\t' '{ printf "| %d | %d | `%s` |\n", $1, $2, $3 }'
        echo
        echo "## Reference files never read in the window ($((n_total - n_files)) of $n_total)"
        echo
        awk -F'\t' -v s="$start" -v e="$today" '
            NR == FNR { if ($1 == "R" && $3 >= s && $3 <= e) seen[$4] = 1; next }
            !($0 in seen) { printf "- `%s`\n", $0 }' "$work/events" "$work/ref.$today"
        echo
        echo "## The kit's own Markdown, read ($n_kitreads reads)"
        echo
        awk -F'\t' -v s="$start" -v e="$today" '$1 == "K" && $3 >= s && $3 <= e { n[$4]++ } END { for (f in n) printf "%d\t%s\n", n[f], f }' "$work/events" \
            | LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k2,2 | awk -F'\t' '{ printf "- `%s` (%d)\n", $2, $1 }'
    fi
} > "$report"
chmod 600 "$report"
echo "The per-file detail is in $report (ignored by git)."
