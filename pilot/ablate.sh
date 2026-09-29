#!/usr/bin/env bash
# Context ablations: does one line of the always-loaded or reference context change what the agent
# does on the task it was promoted for? Each ablation in pilot/ablations/<id>.md names the line, a
# realistic prompt and a Check or a Judge. The runner cuts a fresh git worktree of the target's HEAD per
# run, runs the prompt headless in the `with` arm (HEAD as is) and the `without` arm (the line removed),
# grades each run with the Check, asks a blind comparator to pick between run i of each arm when there
# is a Judge, and appends counts to pilot/ablation-results.csv.
#
#   pilot/ablate.sh                    run every ablation in <target>/pilot/ablations/
#   pilot/ablate.sh <id> [<id>...]     run the named ablations
#   --target DIR                       the repository to test (default: the one this script sits in)
#   --runs K                           runs per arm for this invocation (default: the file's runs, else 3)
#   --max-budget-usd N                 usage guard per run, on its API-equivalent cost (default: the
#                                      file's max_budget_usd, else 1.00)
#   --bare                             add the bare arm: every always-loaded file emptied
#   --dry-run                          build the worktrees and print the commands; run and write nothing
#   --keep                             keep each run's stream, outputs, Check output, verdict and meta.json
#                                      under $TMPDIR, for inspection or --judge-kept (worktrees still go)
#   --report                           print the report for the latest results without running anything;
#                                      `--report > <target>/pilot/ablation-report.md` rewrites it from the CSV
#   --judge-kept DIR                   judge the with/without pairs kept by an earlier --keep run in DIR,
#                                      and write the verdicts into that run's rows; no arm runs
#   --no-judge                         run the arms and grade them by Check only: no comparator runs
#   --outcomes FILE                    print each ablation's latest result in a results CSV, one
#                                      "<ablation> TAB <date> TAB <result>" line each, and nothing else
#
# It writes only <target>/pilot/ablation-results.csv and <target>/pilot/ablation-report.md in the
# target. It never commits, pushes, or moves a branch: worktrees are detached at HEAD and removed on
# exit, and an ablation that pre-approves a commit or a push is refused. Run from a kit checkout, the
# default target is the kit itself; name a team's repository with --target.
#
# Two modes, chosen by the environment. With CLAUDE_CODE_OAUTH_TOKEN set (a token from
# `claude setup-token`), each run gets its own CLAUDE_CONFIG_DIR, a temporary copy of the minimum
# config (settings.json, CLAUDE.md, the plugin list and marketplace registry, nothing else), and its own
# temporary HOME; both go on exit. That allows ablations of `file: ~user/CLAUDE.md` (applied to the
# copy), and makes the bare arm true: the user-level file is emptied too. The plugin list and registry
# hold absolute paths into the person's own plugin cache, so plugin files are still read from there;
# the copy turns marketplace auto-update off, and each run gets DISABLE_AUTOUPDATER=1, so nothing is
# fetched into that cache. Without the token, arms use the person's own login, which cannot follow a
# copied config directory, so the user-level file loads in every arm as in a real session, `~user/`
# ablations are not run, and the bare arm is recorded as `bare-repo`: repository tier emptied,
# user-level tier present. The token is passed through the environment to each headless run (never to
# a Check) and is never written, printed or copied.
#
# What a run writes to the person's own files. --no-session-persistence keeps transcripts out,
# CLOSEOUT_DISABLED and the two state folders keep drafts and hook state out, and auto-update is off.
# Checked on the week-0 runs (45 real runs without the token, 2026-09-29): real runs write the CLI's
# global state file ~/.claude.json and its rotating backups under ~/.claude/backups, and nothing else.
# With the token those land in the run's own temporary config directory and HOME.
#
# Cost and billing. The cost_usd column is the CLI's total_cost_usd: an API-equivalent cost, what the
# run's tokens would cost at API prices. Runs on a subscription login (the person's own login, or the
# token above) are not charged it, so it reads as a usage figure, and --max-budget-usd caps it per run
# as a usage guard. Each run's init event names its apiKeySource, recorded in the api_key_source
# column; `none` means no API key is in use, which is the subscription login. The runner refuses to
# start, exit 4 with nothing run, when the environment would bill an API key or a cloud account:
# ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN or CLAUDE_CODE_USE_BEDROCK/VERTEX/FOUNDRY set in the
# environment or in the env block of the user, managed or HEAD project settings, or an apiKeyHelper
# in any of those settings. It stops,
# exit 3, at the first init event that names any source other than `none`. AW_ALLOW_API_BILLING=1
# allows both. Results written before the column existed have 13 fields and stay readable.
#
# What an arm loads. Repository files (CLAUDE.md, .claude/, docs) come from the worktree, so ablating
# them is faithful. Plugins do not: Claude Code resolves a directory marketplace through the person's
# own marketplace registry, which holds an absolute path to the target's checkout, so every arm loads
# the plugins from that checkout's working tree (uncommitted changes included), as a real session does,
# and not from the submodule initialised in the worktree. An ablation of a file inside a marketplace
# therefore stops with status error when the init event shows a plugin loading from outside the
# worktree, rather than run a `without` arm that changes nothing the session reads.
#
# The comparator. For each i, run i of `with` and run i of `without` go to `claude -p` unlabelled, in
# random order, with the Judge rubric and pilot/lib/judge.md as the prompt; it answers A, B or tie with
# one sentence, and the unblinded winner is written on the `with` row, with the comparator's own
# measurements on a row of arm `judge`. It runs from an empty temporary directory with no tools, so no
# repository CLAUDE.md loads. Without the token the person's user-level CLAUDE.md still loads there;
# with it, the comparator's config directory is empty.
set -uo pipefail

usage() { sed -n '2,30p' "$0" >&2; exit 64; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
target="" runs_override="" budget_override="" dry=0 keep=0 report_only=0 bare=0 judge_kept="" no_judge=0 outcomes=""
ids=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) target="${2:-}"; [[ -n "$target" ]] || usage; shift 2 ;;
        --runs) runs_override="${2:-}"; [[ "$runs_override" =~ ^[1-9][0-9]*$ ]] || usage; shift 2 ;;
        --max-budget-usd) budget_override="${2:-}"; [[ "$budget_override" =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage; shift 2 ;;
        --dry-run) dry=1; shift ;;
        --keep) keep=1; shift ;;
        --report) report_only=1; shift ;;
        --bare) bare=1; shift ;;
        --no-judge) no_judge=1; shift ;;
        --outcomes) outcomes="${2:-}"; [[ -f "$outcomes" ]] || usage; shift 2 ;;
        --judge-kept) judge_kept="${2:-}"; [[ -d "$judge_kept" ]] || usage; shift 2 ;;
        -h|--help) usage ;;
        -*) usage ;;
        *) ids+=("$1"); shift ;;
    esac
done

for tool in git jq python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ablate.sh needs $tool on PATH" >&2; exit 2; }
done

target="${target:-$here}"
target="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || { echo "ablate.sh: not a git repository: ${target}" >&2; exit 2; }
target="$(cd "$target" && pwd -P)"
abl_dir="$target/pilot/ablations"
csv="$target/pilot/ablation-results.csv"
report="$target/pilot/ablation-report.md"
header="date,ablation,arm,run,check,judge,input_tokens,output_tokens,cache_read_tokens,duration_ms,cost_usd,turns,status,api_key_source"

# --- The report ------------------------------------------------------------------------------------
# One row per ablation, from that ablation's own latest date, so an ablation not run on the newest date
# keeps its row and its flags. Every figure carries its n, and every row its date, so no number can be
# quoted without both. "Most" means more than half; the gap is `with` passes minus `without` passes,
# in runs. The flag column reads the whole history, and the first rule that applies wins:
#   stale                        the ablated line no longer matches a whole line of its file
#   error                        a run failed; for a line inside a plugin file, the report says why
#   without preferred            the line may hurt: the Check failed on most `with` runs and passed on
#                                most `without` runs
#   check fails both arms        the Check failed on most `with` runs (and `without` did no better),
#                                whatever the gap, so it says nothing about the line: check needs
#                                revision, no rerun at a larger k, never counted toward demotion
#   discriminates                the Check passed on most `with` runs, with a gap of 2 or more runs at
#                                any k (at k=3: 3/3 or 2/3 against 0/3, or 3/3 against 1/3)
#   leans with, rerun at k=5     the Check passed on most `with` runs, with a gap of exactly 1 (at k=3:
#                                3/3 against 2/3, 2/3 against 1/3); neither discriminating nor a
#                                demotion step. At k=1 this is the most a single pair can show
#   no difference (both pass)    the Check passed on most runs of both arms, with no gap or `without`
#                                ahead (at k=3: 2/3 against 3/3), and the comparator, if there is one,
#                                did not prefer `with` in most pairs
#   check blind, judge prefers with  as above, but the comparator preferred `with` in most pairs: the
#                                Check cannot see what the line does, so it needs revision
#   inconclusive                 anything else, such as `with` at exactly half its runs
# With no Check, the comparator's verdicts stand in for the runs, by the same gap: most pairs prefer
# `with` and `with` wins 2 or more pairs more than `without` is discriminates, a margin of 1 leans
# with; most pairs a tie is `no difference (judge ties)`; most prefer `without` is without preferred.
# Two flags read the history on top of that:
#   regressed                    `with` passed on most runs at the previous date and does not now
#   demotion candidate           `no difference (both pass)`, `no difference (judge ties)` or `without
#                                preferred` in each of three consecutive ISO weeks, the latest of them
#                                the ablation's latest week (the latest date in each week counts once, so a
#                                second look in the same week adds nothing); a failing check, a blind
#                                check, a lean and an inconclusive result never count toward it
render_report() {
    python3 - "$csv" "$abl_dir" "$market_paths" "${1:-report}" <<'PYREPORT'
import csv, datetime, os, statistics, sys
path, abl_dir, markets = sys.argv[1], sys.argv[2], [m for m in sys.argv[3].split("\n") if m]
mode = sys.argv[4]
allrows = list(csv.DictReader(open(path, encoding="utf-8")))
if not allrows and mode == "outcomes":
    sys.exit(0)
if not allrows:
    print("# Ablation report\n\nNo results yet."); sys.exit(0)
newest = max(r["date"] for r in allrows)
order, latest = [], {}
for r in allrows:
    if r["ablation"] not in order:
        order.append(r["ablation"])
    latest[r["ablation"]] = max(latest.get(r["ablation"], ""), r["date"])
# Newest first, then in the order the CSV first names them.
order.sort(key=lambda a: latest[a], reverse=True)
BARE = ("bare", "bare-repo")
DEMOTES = ("no difference (both pass)", "no difference (judge ties)", "without preferred")

def ablated_file(a):
    """The `file:` line of the ablation's definition, or empty."""
    try:
        for line in open(os.path.join(abl_dir, a + ".md"), encoding="utf-8"):
            if line.startswith("file:"):
                return line.split(":", 1)[1].strip().strip("\"'")
    except OSError:
        pass
    return ""

def spread(vals):
    vals = [float(v) for v in vals if v != ""]
    if not vals:
        return "—"
    sd = statistics.stdev(vals) if len(vals) > 1 else 0.0
    return f"{statistics.mean(vals):,.0f} ± {sd:,.0f} (n={len(vals)})"

def money(vals):
    vals = [float(v) for v in vals if v != ""]
    return f"${sum(vals):.2f} (n={len(vals)})" if vals else "—"

def rate(rs, arms):
    graded = [r for r in rs if r["arm"] in arms and r["check"] in ("0", "1")]
    return sum(r["check"] == "1" for r in graded), len(graded)

def verdicts(rs):
    return [r["judge"] for r in rs if r["arm"] == "with" and r["judge"] in ("with", "without", "tie")]

def outcome(rs):
    """The result of one ablation on one date: its rows for that date."""
    if any(r["status"] == "stale" for r in rs):
        return "stale"
    arms = [r for r in rs if r["arm"] in ("with", "without")]
    if any(r["status"] == "error" for r in arms):
        return "error"
    if any(r["status"] == "timeout" for r in arms):
        return "timeout"
    w, wo = rate(rs, ("with",)), rate(rs, ("without",))
    v = verdicts(rs)
    most = lambda n, of: n * 2 > of
    if w[1] and wo[1]:
        passes = lambda x: x[0] * 2 > x[1]
        fails = lambda x: x[0] * 2 < x[1]
        # The order is the rule. A Check `with` fails on most runs says nothing about the line, however
        # far `without` falls below it, unless `without` passes where `with` fails.
        if fails(w):
            return "without preferred" if passes(wo) else "check fails both arms"
        if passes(w):
            gap = w[0] - wo[0]
            if gap >= 2:
                return "discriminates"
            if gap == 1:
                return "leans with, rerun at k=5"
            # With no gap or `without` ahead, both arms pass: the line changes nothing the Check sees.
            if gap <= 0 and passes(wo):
                # A Check both arms pass cannot see the difference a comparator that prefers `with` did.
                if v and most(v.count("with"), len(v)):
                    return "check blind, judge prefers with"
                return "no difference (both pass)"
        return "inconclusive"
    if v:
        if most(v.count("with"), len(v)):
            return "discriminates" if v.count("with") - v.count("without") >= 2 else "leans with, rerun at k=5"
        if most(v.count("tie"), len(v)):
            return "no difference (judge ties)"
        if most(v.count("without"), len(v)):
            return "without preferred"
        return "inconclusive"
    return "not graded"

# measure.sh reads the results through this, so its counts and the report's flags are one rule.
if mode == "outcomes":
    for a in order:
        print(f"{a}\t{latest[a]}\t{outcome([r for r in allrows if r['ablation'] == a and r['date'] == latest[a]])}")
    sys.exit(0)

def history(a):
    """(date, rows) for every date the ablation has rows, oldest first."""
    dates = sorted({r["date"] for r in allrows if r["ablation"] == a})
    return [(d, [r for r in allrows if r["ablation"] == a and r["date"] == d]) for d in dates]

def week_start(d):
    y, w, _ = datetime.date.fromisoformat(d).isocalendar()
    return datetime.date.fromisocalendar(y, w, 1)

def flags(a, rs, day):
    base = outcome(rs)
    note = {"check fails both arms": " — check needs revision",
            "without preferred": " — the line may hurt",
            "check blind, judge prefers with": " — check needs revision"}.get(base, "")
    if base == "error" and any(ablated_file(a).startswith(m + "/") for m in markets):
        note = " — not run: the line is in a plugin file, and plugins load from the checkout, not the worktree"
    out = [base + note]
    past = [(d, x) for d, x in history(a) if d < day]
    # Regressed: the with arm passed on most runs at the previous graded date, and does not now.
    now = rate(rs, ("with",))
    prev = next((rate(x, ("with",)) for d, x in reversed(past) if rate(x, ("with",))[1]), None)
    if base not in ("stale", "error", "timeout") and now[1] and prev and prev[0] * 2 > prev[1] and not now[0] * 2 > now[1]:
        out.append("regressed")
    # Demotion: the last result in each ISO week, three consecutive weeks, each a no-difference result.
    weekly = {}
    for d, x in history(a):
        try:
            weekly[week_start(d)] = outcome(x)
        except ValueError:
            continue
    weeks = sorted(weekly)[-3:]
    if (len(weeks) == 3 and all(weekly[k] in DEMOTES for k in weeks)
            and (weeks[2] - weeks[0]).days == 14):
        out.append("demotion candidate")
    return ", ".join(out)

out = [f"# Ablation report", "",
       f"Latest results per ablation, the newest of {newest}, from `pilot/ablation-results.csv`; the Date "
       "column says when each row's figures are from. Each run is a fresh worktree of HEAD; "
       "`with` is HEAD as is, `without` has the ablation's lines removed. Pass rates are m/n runs graded "
       "by the ablation's Check. Tokens are output tokens per run, mean ± sd. The user-level tier "
       "(`~/.claude/CLAUDE.md`) is present in the `with` and `without` arms, as in a real session; it is "
       "ablated only when the runner has its own login token, and then in a temporary copy.",
       "",
       "| Ablation | Date | with: Check | without: Check | with: output tokens | without: output tokens | with: seconds | without: seconds | bare: Check | Judge with–without–tie | API-equivalent cost | Flag |",
       "|---|---|---|---|---|---|---|---|---|---|---|---|"]
kinds = set()
for a in order:
    day = latest[a]
    rs = [r for r in allrows if r["ablation"] == a and r["date"] == day]
    if any(r["status"] == "stale" for r in rs):
        out.append(f"| {a} | {day} | — | — | — | — | — | — | — | — | — | {flags(a, rs, day)} |"); continue
    cells = {}
    for arm in ("with", "without"):
        ar = [r for r in rs if r["arm"] == arm]
        p, n = rate(rs, (arm,))
        cells[arm] = (f"{p}/{n}" if n else "—",
                      spread(r["output_tokens"] for r in ar if r["status"] == "ok"),
                      spread([float(r["duration_ms"]) / 1000 for r in ar if r["status"] == "ok" and r["duration_ms"] != ""]))
    bare_cell = "—"
    for kind in BARE:
        p, n = rate(rs, (kind,))
        if any(r["arm"] == kind for r in rs):
            kinds.add(kind)
            bare_cell = (f"{p}/{n}" if n else "not graded") + (" (repository tier only)" if kind == "bare-repo" else "")
    v = verdicts(rs)
    judge_cell = f"{v.count('with')}–{v.count('without')}–{v.count('tie')} (n={len(v)})" if v else "—"
    out.append(f"| {a} | {day} | {cells['with'][0]} | {cells['without'][0]} | {cells['with'][1]} | {cells['without'][1]} "
               f"| {cells['with'][2]} | {cells['without'][2]} | {bare_cell} | {judge_cell} | {money(r['cost_usd'] for r in rs)} | {flags(a, rs, day)} |")

# The login each shown run used, from its init event. Rows written before the column existed have none.
shown = [r for a in order for r in allrows if r["ablation"] == a and r["date"] == latest[a] and r["status"] != "stale"]
sources = {}
for r in shown:
    k = (r.get("api_key_source") or "").strip()
    sources[k] = sources.get(k, 0) + 1
if sources:
    parts = []
    for k in sorted(sources, key=lambda k: (k == "", k)):
        n = sources[k]
        if k == "none":
            parts.append(f"`none` (no API key: the subscription login) on {n} run{'s' if n != 1 else ''}")
        elif k:
            parts.append(f"`{k}` (an API key, billed; allowed by AW_ALLOW_API_BILLING=1) on {n} run{'s' if n != 1 else ''}")
        else:
            parts.append(f"not recorded on {n} run{'s' if n != 1 else ''} (written before the runner recorded it)")
    out += ["", "Login, from each run's init event (`api_key_source`): " + "; ".join(parts) + "."]

skipped = []
if os.path.isdir(abl_dir):
    for name in sorted(os.listdir(abl_dir)):
        if not name.endswith(".md") or name == "README.md" or name[:-3] in order:
            continue
        for line in open(os.path.join(abl_dir, name), encoding="utf-8"):
            if line.startswith("file:") and line.split(":", 1)[1].strip().strip("\"'").startswith("~user/"):
                skipped.append(name[:-3])
                break
if skipped:
    out += ["", "Not run, because they ablate the user-level file, which needs the runner's own login token: "
            + ", ".join(f"`{s}`" for s in skipped) + "."]
if "bare" in kinds:
    out += ["", "The bare arm empties every always-loaded file in the repository and the user-level file in "
            "a temporary copy: the whole tier off, as in a plain with-and-without comparison."]
if "bare-repo" in kinds:
    out += ["", "The bare arm here is repository tier emptied; user-level tier present. The runner had no "
            "login token of its own, so the user-level file loaded as in any session."]
out += ["", "Flags, first rule that applies: `stale`; `error`; `without preferred` means the Check failed on "
        "most `with` runs and passed on most `without` runs, so the line may hurt; `check fails both arms` "
        "means it failed on most `with` runs and `without` did no better, whatever the gap, which says "
        "nothing about the line and asks for the check to be revised; `discriminates` means it passed on "
        "most `with` runs with a gap of 2 or more runs (`with` passes minus `without` passes, at any k); "
        "`leans with, rerun at k=5` means it passed on most `with` runs with a gap of exactly 1, which is "
        "neither discriminating nor a step toward demotion; `no difference (both pass)` means it passed on "
        "most runs of both arms with no gap or `without` ahead, and no comparator preferred `with`; `check blind, judge prefers "
        "with` means the same, but the comparator preferred `with`, so the Check needs revision; "
        "`inconclusive` is anything else. With no Check the comparator's pairs stand in for runs, by the "
        "same gap, and `no difference (judge ties)` means it called most pairs a tie. `regressed` means "
        "`with` passed on most runs at the previous date and does not now; `demotion candidate` means "
        "`no difference (both pass)`, `no difference (judge ties)` or `without preferred` in each of three "
        "consecutive weekly runs, and only ever proposes. The Judge column counts the blind comparisons of "
        "run i of each arm, after unblinding. API-equivalent cost is the CLI's total_cost_usd, the comparator's runs "
        "included: what the tokens would cost at API prices. A run on a subscription login is not charged "
        "it, and the per-run cap on it is a usage guard. A Check tests what its author thought the line was "
        "for, and a small n is a small n. Checks are tightened against outputs their authors or a model "
        "wrote, so a Check is a filter on which outputs count and not evidence about the line; the real "
        "runs are the evidence."]
if markets:
    out += ["", "Plugins load in every arm from the target's own checkout of each marketplace ("
            + ", ".join(f"`{m}`" for m in markets) + "), as in a real session, not from the worktree; an "
            "ablation of a line inside a plugin file is not run."]
print("\n".join(out))
PYREPORT
}

# The latest result per ablation for pilot/measure.sh: it runs nothing and writes nothing.
if [[ -n "$outcomes" ]]; then
    csv="$outcomes" abl_dir="" market_paths=""
    render_report outcomes
    exit $?
fi

# --- The target's plugin setup, from HEAD ---------------------------------------------------------
# The `with` arm has to load what a real session loads. The target's .claude/settings.json names its
# directory marketplaces (extraKnownMarketplaces, source "directory") and the plugins it enables from
# them; a marketplace that is a submodule is initialised in each worktree from the target's own
# checkout of it, with no network. Only those submodules: others may be stale or remote-only. The
# report reads the marketplace paths too, to say why an ablation of a plugin file did not run.
settings="$(git -C "$target" show HEAD:.claude/settings.json 2>/dev/null || echo '{}')"
markets="$(printf '%s' "$settings" | jq -r '(.extraKnownMarketplaces // {}) | to_entries[]
    | select(.value.source.source == "directory") | "\(.key)\t\(.value.source.path)"' 2>/dev/null)"
expected="$(printf '%s' "$settings" | jq -r --arg m "$(printf '%s\n' "$markets" | cut -f1 | paste -sd' ' -)" '
    ($m | split(" ")) as $names | (.enabledPlugins // {}) | to_entries[]
    | select(.value == true and ((.key | split("@")[1]) as $mk | $names | index($mk))) | .key' 2>/dev/null)"
market_paths="" submodules=""
while IFS=$'\t' read -r _name mpath; do
    [[ -n "$mpath" ]] || continue
    mpath="${mpath#./}"; mpath="${mpath%/}"
    [[ "$mpath" == /* ]] && continue
    market_paths+="$mpath"$'\n'
    [[ "$(git -C "$target" ls-tree HEAD -- "$mpath" 2>/dev/null | awk '{print $1}')" == 160000 ]] && submodules+="$mpath"$'\n'
done <<EOF
$markets
EOF

if [[ $report_only -eq 1 ]]; then
    [[ -f "$csv" ]] || { echo "ablate.sh: no results yet at ${csv#"$target"/}" >&2; exit 1; }
    render_report
    exit 0
fi

# --- Which ablations ------------------------------------------------------------------------------
files=()
if [[ ${#ids[@]} -gt 0 ]]; then
    for id in "${ids[@]}"; do
        [[ -f "$abl_dir/$id.md" ]] || { echo "ablate.sh: no ablation named $id in $abl_dir (the target is $target; name another with --target)" >&2; exit 64; }
        files+=("$abl_dir/$id.md")
    done
else
    shopt -s nullglob
    for f in "$abl_dir"/*.md; do [[ "$(basename "$f")" == README.md ]] || files+=("$f"); done
    shopt -u nullglob
fi
[[ ${#files[@]} -gt 0 ]] || { echo "ablate.sh: no ablations in $abl_dir (the target is $target; name another with --target)" >&2; exit 64; }
git -C "$target" rev-parse -q --verify HEAD >/dev/null || { echo "ablate.sh: no commits yet in $target" >&2; exit 2; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ablate.XXXXXX")" || exit 2
tmp="$(cd "$tmp" && pwd -P)"
: > "$tmp/worktrees"
: > "$tmp/scratch-dirs"
pid=""
cleanup() {
    # A headless run still going when the runner is stopped would carry on, billed, inside a worktree
    # about to be removed; it is stopped first.
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    fi
    # The per-run config directories and homes go even under --keep: they are copies of the person's
    # own settings, and nothing in them is needed to read a run.
    local d
    while IFS= read -r d; do
        [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
    done < "$tmp/scratch-dirs"
    # Worktrees go whatever --keep says: each run's outputs are already copied under runs/, which is all
    # an inspection or --judge-kept reads, and a kept worktree would stay registered in the target.
    local wt
    while IFS= read -r wt; do
        [[ -n "$wt" && -d "$wt" ]] && git -C "$target" worktree remove --force "$wt" >/dev/null 2>&1
    done < "$tmp/worktrees"
    git -C "$target" worktree prune >/dev/null 2>&1
    if [[ $keep -eq 1 ]]; then
        rm -rf "$tmp/wt"
        echo "ablate.sh: kept $tmp (runs/ holds each run's stream, outputs and meta.json; judge/ the verdicts)" >&2
        return
    fi
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# parse <file> <out.json>: the front matter and sections of one ablation file, as JSON. The front
# matter is a small YAML subset: `key: value`, and `key:` followed by `  - item` lines. Values may be
# plain, 'single-quoted' or "double-quoted" (with JSON escapes). Sections are the level-two headings
# Prompt, Fixture, Check and Judge; a Fixture is `path: |` blocks, indented two spaces.
parse() {
    python3 - "$1" > "$2" <<'PYPARSE'
import json, os, re, sys
path = sys.argv[1]
stem = os.path.basename(path)[:-3]
text = open(path, encoding="utf-8").read()
lines = text.split("\n")
def fail(msg):
    sys.stderr.write(f"ablate.sh: {os.path.basename(path)}: {msg}\n"); sys.exit(65)
if not lines or lines[0].strip() != "---":
    fail("no front matter")
try:
    end = lines.index("---", 1)
except ValueError:
    fail("front matter is not closed")
def scalar(v):
    v = v.strip()
    if v.startswith('"') and v.endswith('"') and len(v) > 1:
        return json.loads(v)
    if v.startswith("'") and v.endswith("'") and len(v) > 1:
        return v[1:-1].replace("''", "'")
    return v
fm, key = {}, None
for l in lines[1:end]:
    if not l.strip() or l.lstrip().startswith("#"):
        continue
    m = re.match(r"^\s+-\s+(.*)$", l)
    if m and key:
        fm.setdefault(key, [])
        if not isinstance(fm[key], list):
            fail(f"{key} mixes a value and a list")
        fm[key].append(scalar(m.group(1))); continue
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", l)
    if not m:
        fail(f"cannot read front matter line: {l}")
    key, val = m.group(1), m.group(2)
    fm[key] = scalar(val) if val.strip() else []
sections, cur = {}, None
for l in lines[end + 1:]:
    m = re.match(r"^##\s+(\w+)\s*$", l)
    if m:
        cur = m.group(1).lower(); sections[cur] = []; continue
    if cur:
        sections[cur].append(l)
def body(name):
    b = "\n".join(sections.get(name, [])).strip("\n")
    fence = re.match(r"^```[^\n]*\n(.*)\n```$", b.strip(), re.S)
    return (fence.group(1) if fence else b).strip()
fixtures, fx = [], None
for l in sections.get("fixture", []):
    m = re.match(r"^(\S[^:]*):\s*\|\s*$", l)
    if m:
        fx = {"path": m.group(1).strip(), "lines": []}; fixtures.append(fx); continue
    if fx is not None:
        if l.startswith("  "):
            fx["lines"].append(l[2:])
        elif not l.strip():
            fx["lines"].append("")
        else:
            fail(f"fixture line outside a path block: {l}")
def inside(p):
    return bool(p) and not p.startswith("/") and ".." not in p.split("/") and os.path.normpath(p).split("/")[0] != ".git"
for fx in fixtures:
    while fx["lines"] and fx["lines"][-1] == "":
        fx["lines"].pop()
    fx["content"] = "\n".join(fx.pop("lines")) + "\n"
    if not inside(fx["path"]):
        fail(f"fixture path must stay inside the repository, outside .git: {fx['path']}")
def aslist(v):
    if v in (None, ""):
        return []
    return v if isinstance(v, list) else [v]
def number(name, default, kind):
    v = fm.get(name, default)
    try:
        return kind(v)
    except (TypeError, ValueError):
        fail(f"{name} is not a number: {v}")
out = {
    "id": stem,
    "item": fm.get("item", ""),
    "file": fm.get("file", ""),
    "ablate": aslist(fm.get("ablate")),
    "runs": number("runs", 3, int),
    "timeout": number("timeout", 300, int),
    "max_turns": number("max_turns", 20, int),
    "max_budget_usd": str(fm.get("max_budget_usd", "") or ""),
    "allowed_tools": aslist(fm.get("allowed_tools")),
    "outputs": aslist(fm.get("outputs")),
    "prompt": body("prompt"),
    "check": body("check"),
    "judge": body("judge"),
    "fixtures": fixtures,
}
if fm.get("id") and fm["id"] != stem:
    fail(f"id {fm['id']} differs from the file name {stem}")
if not out["file"] or not isinstance(out["file"], str):
    fail("no file named")
if not out["ablate"]:
    fail("no ablate lines")
if not out["prompt"]:
    fail("no Prompt section")
if not out["check"] and not out["judge"]:
    fail("needs a Check or a Judge section")
if not out["file"].startswith("~user/"):
    if not inside(out["file"]):
        fail(f"file must be repository-relative: {out['file']}")
    for fx in fixtures:
        if os.path.normpath(fx["path"]) == os.path.normpath(out["file"]):
            fail(f"a fixture would overwrite the ablated file in both arms: {fx['path']}")
for o in out["outputs"]:
    if not isinstance(o, str) or not inside(o):
        fail(f"outputs must stay inside the repository, outside .git: {o}")
# A headless arm gets no approvals, so allowed_tools is the whole of what it may run. Nothing here may
# pre-approve a commit or a push: not Bash itself, not a wildcard or a shell that could run git, and no
# pattern that names either.
for t in out["allowed_tools"]:
    for name, inner in re.findall(r"([A-Za-z0-9_]+)(?:\(([^)]*)\))?", str(t)):
        if name != "Bash":
            continue
        prefix = re.sub(r"[:\s]*\*+$", "", inner).strip()
        if (not prefix or "git commit".startswith(prefix) or "git push".startswith(prefix)
                or re.search(r"\b(commit|push)\b", inner)
                or prefix.split()[0] in ("sh", "bash", "zsh", "env", "xargs", "eval", "exec", "command")):
            fail(f"allowed_tools may not open the way to a commit or a push: {t}")
print(json.dumps(out))
PYPARSE
}

mkdir -p "$tmp/abl"
for f in "${files[@]}"; do
    id="$(basename "$f" .md)"
    parse "$f" "$tmp/abl/$id.json" || exit 65
done

# --- Which login, and the per-run config ----------------------------------------------------------
# The token is only ever tested for presence here; each run inherits it from this environment.
token_mode=0
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && token_mode=1
src_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
bare_arm="bare-repo"
[[ $token_mode -eq 1 ]] && bare_arm=bare
always_loaded=()
read -r -a always_loaded <<< "${MEASURE_ALWAYS_LOADED:-AGENTS.md CLAUDE.md}"

# --- Billing ---------------------------------------------------------------------------------------
# Runs are meant to use a subscription login. Claude Code prefers an API key to a login when it finds
# one, so an environment that would supply one stops the runner before anything runs. Only presence is
# tested; no value is read or printed.
if [[ $dry -eq 0 && "${AW_ALLOW_API_BILLING:-}" != 1 ]]; then
    why=""
    [ -n "${ANTHROPIC_API_KEY:-}" ] && why+="ANTHROPIC_API_KEY is set"$'\n'
    [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] && why+="ANTHROPIC_AUTH_TOKEN is set"$'\n'
    for v in CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY; do
        [ -n "${!v:-}" ] && why+="$v is set (a cloud provider account is billed)"$'\n'
    done
    # A settings file can supply the same through its env block, which Claude Code applies at start.
    helper='type == "object" and has("apiKeyHelper")'
    envkey='.env | objects | has("ANTHROPIC_API_KEY") or has("ANTHROPIC_AUTH_TOKEN") or has("CLAUDE_CODE_USE_BEDROCK") or has("CLAUDE_CODE_USE_VERTEX") or has("CLAUDE_CODE_USE_FOUNDRY")'
    for s in "$src_cfg/settings.json" "/Library/Application Support/ClaudeCode/managed-settings.json" \
             "/etc/claude-code/managed-settings.json"; do
        [[ -f "$s" ]] || continue
        jq -e "$helper" "$s" >/dev/null 2>&1 && why+="$s configures an apiKeyHelper"$'\n'
        jq -e "$envkey" "$s" >/dev/null 2>&1 && why+="$s sets an API key or cloud provider in its env block"$'\n'
    done
    printf '%s' "$settings" | jq -e "$helper" >/dev/null 2>&1 \
        && why+=".claude/settings.json at HEAD configures an apiKeyHelper"$'\n'
    printf '%s' "$settings" | jq -e "$envkey" >/dev/null 2>&1 \
        && why+=".claude/settings.json at HEAD sets an API key or cloud provider in its env block"$'\n'
    if [[ -n "$why" ]]; then
        printf 'ablate.sh: refusing to start: these runs would be billed to an API key, not the subscription login:\n%sUnset it, or set AW_ALLOW_API_BILLING=1 to run on API billing.\n' \
            "$why" | sed '2,$s/^/  /' >&2
        exit 4
    fi
fi
# api_source <init event>: the run's apiKeySource, commas dropped so it fits a CSV field; empty when the
# event carries none. billed <source>: anything but `none` (no API key) or empty is an API key.
api_source() { printf '%s' "$1" | jq -r '.apiKeySource // "" | tostring' 2>/dev/null | tr -d ',\n'; }
billed() { [[ -n "$1" && "$1" != none && "${AW_ALLOW_API_BILLING:-}" != 1 ]]; }

# A results file from before the api_key_source column gains it in the header; its rows keep 13 fields,
# which the report and pilot/measure.sh read as an unrecorded login.
if [[ $dry -eq 0 && -s "$csv" && "$(head -n 1 "$csv")" == "${header%,api_key_source}" ]]; then
    { printf '%s\n' "$header"; tail -n +2 "$csv"; } > "$csv.tmp" && mv "$csv.tmp" "$csv"
fi

# scratch_dir <stem>: a fresh mktemp -d directory, removed by the EXIT trap whatever --keep says.
scratch_dir() {
    local d
    d="$(mktemp -d "${TMPDIR:-/tmp}/$1.XXXXXX")" || return 1
    d="$(cd "$d" && pwd -P)"
    printf '%s\n' "$d" >> "$tmp/scratch-dirs"
    printf '%s' "$d"
}

# make_config <full|empty>: sets cfg and home to fresh temporary directories. A full config is the
# minimum a session needs to load the same settings, user-level file and plugins: settings.json,
# CLAUDE.md, the installed-plugin list and the marketplace registry. Nothing else is copied: no
# transcripts, history, caches, drafts or credentials (the token arrives by environment). An empty one
# is for the comparator, which should read the outputs and not anybody's conventions. The two plugin
# files point at the person's own plugin cache by absolute path, so plugin files are read from there;
# the registry copy has every marketplace's autoUpdate turned off, so a run fetches nothing into it.
make_config() {
    cfg="$(scratch_dir ablate-cfg)" && home="$(scratch_dir ablate-home)" || return 1
    [[ "$1" == full ]] || return 0
    local f
    for f in settings.json CLAUDE.md plugins/installed_plugins.json plugins/known_marketplaces.json; do
        if [[ -f "$src_cfg/$f" ]]; then
            mkdir -p "$cfg/$(dirname "$f")" && cp "$src_cfg/$f" "$cfg/$f" || return 1
        fi
    done
    f="$cfg/plugins/known_marketplaces.json"
    if [[ -f "$f" ]]; then
        jq 'if type == "object" then map_values(if type == "object" then . + {autoUpdate: false} else . end) else . end' \
            "$f" > "$f.new" && mv "$f.new" "$f" || return 1
    fi
}

# run_env: the environment every headless session gets, as `env` arguments. AW_HEADLESS_RUN silences
# the projects session-start line; CLOSEOUT_DISABLED stops the closeout capture hook, which would
# otherwise start a second, billed session and write a draft under the real ~/.claude; the two state
# folders catch anything that still gets through. DISABLE_AUTOUPDATER stops background updates of
# Claude Code and its plugins. A runner started from inside a Claude Code session would pass that
# session's own identity and messaging variables down; they are removed, so each run starts as a
# session of its own. In token mode, the run's own config and home.
run_env() {
    renv=(-u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION
          -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_BRIDGE_SESSION_ID
          -u FORCE_AUTOUPDATE_PLUGINS DISABLE_AUTOUPDATER=1
          AW_HEADLESS_RUN=1 CLOSEOUT_DISABLED=1 CLOSEOUT_DRAFT_ROOT="$tmp/drafts"
          PROJECTS_HOOK_STATE_DIR="$tmp/projects-hook")
    [[ $token_mode -eq 1 ]] && renv+=(CLAUDE_CONFIG_DIR="$cfg" HOME="$home")
    mkdir -p "$tmp/drafts" "$tmp/projects-hook"
}

# watch <timeout>: waits for the child in $pid, stopping it at the timeout. Sets wstatus to timeout
# when it had to, and rc to the child's exit status.
watch() {
    local started; started=$(date +%s); wstatus=""
    while kill -0 "$pid" 2>/dev/null; do
        if [[ -z "$wstatus" && $(( $(date +%s) - started )) -ge $1 ]]; then
            kill "$pid" 2>/dev/null; wstatus=timeout
        fi
        sleep 0.2
    done
    wait "$pid" 2>/dev/null; rc=$?; pid=""
}

# measures <stream>: the CSV measurement fields of a run's result event, comma-joined and in order:
# input_tokens, output_tokens, cache_read_tokens, duration_ms, cost_usd, turns. input_tokens counts
# uncached input and cache writes together: with prompt caching on, the always-loaded context lands in
# the cache-write figure, and that is the load being measured.
measures() {
    local result
    result="$(grep '"type":"result"' "$1" 2>/dev/null | tail -n 1)"
    [[ -n "$result" ]] || { printf ',,,,,'; return; }
    printf '%s' "$result" | jq -r '[
        ((.usage.input_tokens // 0) + (.usage.cache_creation_input_tokens // 0)),
        (.usage.output_tokens // ""), (.usage.cache_read_input_tokens // ""),
        (.duration_ms // ""),
        (.total_cost_usd | if type == "number" then (. * 1000000 | round) / 1000000 else "" end),
        (.num_turns // "")] | map(tostring) | join(",")' 2>/dev/null || printf ',,,,,'
}

# judge_pair <ablation json> <i> <with run dir> <without run dir> <out dir> <timeout> <budget>: one
# blind comparison. Writes <out dir>/frag: the unblinded verdict (with, without, tie or empty), then
# the comparator's measurements, status and login, as one CSV fragment:
# judge,in,out,cache,ms,cost,turns,status,api_key_source. A comparator on an API key stops the invocation.
# It runs in this shell, not a subshell, so the EXIT trap can stop the comparator.
judge_pair() {
    local j="$1" i="$2" wrd="$3" word="$4" jd="$5" jt="$6" jb="$7" first second a b jcwd verdict m st src
    mkdir -p "$jd"
    printf ',,,,,,,error,' > "$jd/frag"
    # The coin: which arm is shown as A. Recorded as shown_as_a in the pair's verdict.json, which --keep
    # keeps under judge/, so a person can check the unblinding.
    if [[ $(( RANDOM % 2 )) -eq 0 ]]; then first=with second=without; else first=without second=with; fi
    if [[ "$first" == with ]]; then a="$wrd" b="$word"; else a="$word" b="$wrd"; fi
    python3 - "$here/lib/judge.md" "$j" "$a" "$b" > "$jd/prompt.txt" <<'PYJUDGE' || return 0
import json, os, re, sys
tpl, spec, a, b = open(sys.argv[1], encoding="utf-8").read(), json.load(open(sys.argv[2])), sys.argv[3], sys.argv[4]
CAP = 20000
def material(rd):
    # What the person would see: the final reply, and each output file the ablation names.
    reply = ""
    try:
        for line in open(os.path.join(rd, "stream.jsonl"), encoding="utf-8"):
            if '"type":"result"' in line:
                reply = json.loads(line).get("result", "") or ""
    except OSError:
        pass
    parts = [f"Final reply:\n{reply[:CAP] or '(none)'}"]
    for o in spec["outputs"]:
        p = os.path.join(rd, "outputs", o)
        body = open(p, encoding="utf-8", errors="replace").read()[:CAP] if os.path.isfile(p) else "(not written)"
        parts.append(f"File {o}:\n{body}")
    return "\n\n".join(parts)
# One pass, so text inside an output that looks like a placeholder is left as it is.
fill = {"RUBRIC": spec["judge"], "TASK": spec["prompt"], "OUTPUT_A": material(a), "OUTPUT_B": material(b)}
print(re.sub(r"\{\{(RUBRIC|TASK|OUTPUT_A|OUTPUT_B)\}\}", lambda m: fill[m.group(1)], tpl), end="")
PYJUDGE
    make_config empty || return 0
    jcwd="$(scratch_dir ablate-judge)" || return 0
    run_env
    (cd "$jcwd" && exec env "${renv[@]}" claude -p "$(cat "$jd/prompt.txt")" --output-format stream-json --verbose \
        --no-session-persistence --strict-mcp-config --tools "" --max-turns 1 --max-budget-usd "$jb" \
        < /dev/null > "$jd/stream.jsonl" 2> "$jd/stderr.txt") &
    pid=$!
    watch "$jt"
    verdict="$(python3 - "$jd/stream.jsonl" "$first" "$second" <<'PYVERDICT'
import json, re, sys
text = ""
try:
    for line in open(sys.argv[1], encoding="utf-8"):
        if '"type":"result"' in line:
            ev = json.loads(line)
            if ev.get("subtype") == "success" and not ev.get("is_error"):
                text = ev.get("result", "") or ""
except (OSError, ValueError):
    pass
found = None
for m in re.finditer(r"\{[^{}]*\}", text):
    try:
        obj = json.loads(m.group(0))
    except ValueError:
        continue
    if isinstance(obj, dict) and str(obj.get("winner", "")).strip().lower() in ("a", "b", "tie"):
        found = obj
if found:
    w = str(found["winner"]).strip().lower()
    print({"a": sys.argv[2], "b": sys.argv[3], "tie": "tie"}[w] + "\t" + str(found.get("reason", "")).replace("\n", " "))
PYVERDICT
)"
    m="$(measures "$jd/stream.jsonl")"
    src="$(api_source "$(grep -m1 '"subtype":"init"' "$jd/stream.jsonl" 2>/dev/null)")"
    if [[ -n "$wstatus" ]]; then st="$wstatus"; elif [[ -n "$verdict" ]]; then st=ok; else st=error; fi
    if billed "$src"; then
        echo "ablate.sh: the comparator's init event reports an API key ($src), which would be billed; stopping. Set AW_ALLOW_API_BILLING=1 to allow it." >&2
        st=error verdict="" halt=1
    fi
    jq -n --arg shown_as_a "$first" --arg verdict "${verdict%%$'\t'*}" --arg reason "${verdict#*$'\t'}" --arg status "$st" \
        --argjson run "$i" '{run: $run, shown_as_a: $shown_as_a, winner: $verdict, reason: $reason, status: $status}' > "$jd/verdict.json"
    printf '%s,%s,%s,%s' "${verdict%%$'\t'*}" "$m" "$st" "$src" > "$jd/frag"
}

# with_row <get|set> <first data line> <date> <ablation> <run> [verdict]: finds the last `with` row for
# that run at or after the given line of the CSV, on the given date when one is given. `get` prints its
# judge column; `set` writes the verdict there and prints the row's date. No such row: status 1.
with_row() {
    python3 - "$csv" "$@" <<'PYSET'
import os, sys
path, op, start, date, abl, run = sys.argv[1:7]
lines = open(path, encoding="utf-8").read().split("\n")
hit = None
for n in range(max(int(start), 1), len(lines)):
    f = lines[n].split(",")
    if len(f) in (13, 14) and f[1] == abl and f[2] == "with" and f[3] == run and (not date or f[0] == date):
        hit = n
if hit is None:
    sys.exit(1)
f = lines[hit].split(",")
if op == "get":
    print(f[5]); sys.exit(0)
f[5] = sys.argv[7]; lines[hit] = ",".join(f)
tmp = path + ".tmp"
open(tmp, "w", encoding="utf-8").write("\n".join(lines))
os.replace(tmp, path)
print(f[0])
PYSET
}

# judge_ablation <ablation json> <runs root> <runs> <first data line> <kept>: every pair whose two runs
# are ok, judged and recorded: the verdict on the `with` row, the comparator's own row as arm `judge`.
# For a kept run (<kept> is 1), the row is the one of the date in the run's meta.json, and a pair whose
# row already has a verdict, or has no row, is left alone, so judging the same folder twice changes nothing.
judge_ablation() {
    local j="$1" root="$2" k="$3" start="$4" kept="$5" id i wrd word frag v d date prior budget timeout st
    id="$(jq -r .id "$j")"
    [[ -n "$(jq -r .judge "$j")" ]] || return 0
    timeout="$(jq -r .timeout "$j")"
    budget="${budget_override:-$(jq -r .max_budget_usd "$j")}"; budget="${budget:-1.00}"
    for i in $(seq 1 "$k"); do
        [[ $halt -eq 0 ]] || break
        wrd="$root/$id/with/run-$i" word="$root/$id/without/run-$i"
        [[ "$(jq -r .status "$wrd/meta.json" 2>/dev/null)" == ok && "$(jq -r .status "$word/meta.json" 2>/dev/null)" == ok ]] || continue
        date="$today"
        if [[ "$kept" == 1 ]]; then
            date="$(jq -r '.date // ""' "$wrd/meta.json" 2>/dev/null)"
            if ! prior="$(with_row get "$start" "$date" "$id" "$i")"; then
                echo "ablate.sh: $id run $i: no with row${date:+ dated $date} in the results, so not judged" >&2; continue
            fi
            if [[ -n "$prior" ]]; then
                echo "ablate.sh: $id run $i: already judged ($prior), so not judged again" >&2; continue
            fi
        fi
        judge_pair "$j" "$i" "$wrd" "$word" "$tmp/judge/$id/run-$i" "$timeout" "$budget"
        frag="$(cat "$tmp/judge/$id/run-$i/frag")"
        v="${frag%%,*}"
        d="$(with_row set "$start" "$date" "$id" "$i" "$v")" || d="$today"
        row "$d,$id,judge,$i,,$frag"
        st="${frag%,*}"; st="${st##*,}"
        printf 'ablate.sh: %s judge run %s: %s%s\n' "$id" "$i" "$st" "${v:+, prefers $v}" >&2
    done
}

today="$(date +%Y-%m-%d)"
halt=0
row() { [[ $dry -eq 1 ]] || printf '%s\n' "$1" >> "$csv"; }

# --- Judging a kept run -------------------------------------------------------------------------
# An earlier --keep run left runs/<id>/<arm>/run-<i>/ under DIR. The pairs are judged as if the run
# had just finished, and the verdicts go into that run's own `with` rows: those of the date its meta.json
# records (a folder kept before the date was recorded matches the last such row in the CSV).
if [[ -n "$judge_kept" ]]; then
    [[ -f "$csv" ]] || { echo "ablate.sh: no results yet at ${csv#"$target"/}" >&2; exit 1; }
    judge_kept="$(cd "$judge_kept" && pwd -P)"
    for j in "$tmp"/abl/*.json; do
        id="$(basename "$j" .json)"
        [[ -d "$judge_kept/runs/$id" ]] || continue
        k=0
        for d in "$judge_kept/runs/$id/with"/run-*; do [[ -d "$d" ]] && k=$((k + 1)); done
        judge_ablation "$j" "$judge_kept/runs" "$k" 1 1
    done
    render_report > "$report"
    echo "ablate.sh: results in ${csv#"$target"/}, report in ${report#"$target"/}" >&2
    [[ $halt -eq 0 ]] || exit 3
    exit 0
fi

# in_submodule <path>: the submodule path containing <path>, if any.
in_submodule() {
    local s
    while IFS= read -r s; do
        [[ -n "$s" && "$1" == "$s/"* ]] && { printf '%s' "$s"; return 0; }
    done <<EOF
$submodules
EOF
    return 1
}
gitlink() { git -C "$target" ls-tree HEAD -- "$1" | awk '{print $3}'; }

# --- Refuse on a dirty tree -----------------------------------------------------------------------
# The arms are cut from HEAD. When a file an ablation names has uncommitted changes, the arms would
# silently disagree with what the person is looking at, so nothing runs until it is committed or
# restored. A file inside a submodule counts as changed when the submodule's checkout is not at the
# commit HEAD records, too.
dirty=""
for j in "$tmp"/abl/*.json; do
    id="$(basename "$j" .json)"
    file="$(jq -r .file "$j")"
    [[ "$file" == "~user/"* ]] && continue
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        if s="$(in_submodule "$p")"; then
            rel="${p#"$s"/}"
            if ! st="$(git -C "$target/$s" --no-optional-locks status --porcelain --untracked-files=no -- "$rel" 2>/dev/null)"; then
                dirty+="$id: git cannot read the status of $p"$'\n'
            elif [[ -n "$st" ]]; then
                dirty+="$id: $p has uncommitted changes"$'\n'
            fi
            [[ "$(git -C "$target/$s" rev-parse HEAD 2>/dev/null)" == "$(gitlink "$s")" ]] \
                || dirty+="$id: $s is checked out at a different commit from the one HEAD records"$'\n'
        elif ! st="$(git -C "$target" --no-optional-locks status --porcelain --untracked-files=no -- "$p" 2>/dev/null)"; then
            dirty+="$id: git cannot read the status of $p"$'\n'
        elif [[ -n "$st" ]]; then
            dirty+="$id: $p has uncommitted changes"$'\n'
        fi
    done <<EOF
$(jq -r '.file, .outputs[], .fixtures[].path' "$j")
EOF
done
if [[ -n "$dirty" ]]; then
    printf 'ablate.sh: refusing to start; commit or restore these first:\n%s' "$dirty" | sed '2,$s/^/  /' >&2
    exit 65
fi

# head_file <path>: the file as HEAD has it (inside a submodule, as the recorded commit has it).
head_file() {
    local s
    if s="$(in_submodule "$1")"; then
        git -C "$target/$s" show "$(gitlink "$s"):${1#"$s"/}" 2>/dev/null
    else
        git -C "$target" show "HEAD:$1" 2>/dev/null
    fi
}

# build_worktree <dir>: a detached worktree of HEAD with the marketplace submodules initialised.
build_worktree() {
    local wt="$1" s name
    mkdir -p "$(dirname "$wt")"
    git -C "$target" worktree add -q --detach "$wt" HEAD >/dev/null 2>&1 || return 1
    printf '%s\n' "$wt" >> "$tmp/worktrees"
    while IFS= read -r s; do
        [[ -n "$s" ]] || continue
        name="$(git config -f "$wt/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null \
            | awk -v p="$s" '$2 == p { sub(/^submodule\./, "", $1); sub(/\.path$/, "", $1); print $1; exit }')"
        name="${name:-$s}"
        git -C "$wt" -c protocol.file.allow=always -c "submodule.$name.url=$target/$s" \
            submodule update -q --init -- "$s" >/dev/null 2>&1 || return 1
    done <<EOF
$submodules
EOF
}

# plugin_problem <init event> <worktree> <needs-worktree-paths>: why the init event does not show the
# expected plugins, or nothing. When the ablated file lives in a marketplace, the plugins must also load
# from the worktree's copy, or the `without` arm would change nothing the session reads.
plugin_problem() {
    local init="$1" wt="$2" strict="$3" e p
    while IFS= read -r e; do
        [[ -n "$e" ]] || continue
        p="$(printf '%s' "$init" | jq -r --arg s "$e" 'first(.plugins[]? | select(.source == $s) | .path) // empty')"
        if [[ -z "$p" ]]; then
            printf 'plugin %s is not listed in the init event' "$e"; return
        fi
        if [[ "$strict" == 1 && "$p" != "$wt"/* ]]; then
            printf 'plugin %s loads from %s, outside the worktree' "$e" "$p"; return
        fi
    done <<EOF
$expected
EOF
}

no_json="{}"
if [[ $dry -eq 0 ]]; then
    mkdir -p "$(dirname "$csv")"
    [[ -s "$csv" ]] || printf '%s\n' "$header" > "$csv"
fi

arms=(with without)
[[ $bare -eq 1 ]] && arms+=("$bare_arm")
for j in "$tmp"/abl/*.json; do
    [[ $halt -eq 0 ]] || break
    id="$(basename "$j" .json)"
    file="$(jq -r .file "$j")"
    user_file=0
    if [[ "$file" == "~user/"* ]]; then
        if [[ $token_mode -eq 0 ]]; then
            echo "ablate.sh: $id ablates the user-level file, which needs the runner's own login token (CLAUDE_CODE_OAUTH_TOKEN), so it is not run" >&2
            continue
        fi
        user_file=1
    fi
    ablate=()
    while IFS= read -r l; do ablate+=("$l"); done < <(jq -r '.ablate[]' "$j")

    # A stale ablation is recorded once, with empty measurements, and not run. The user-level file is
    # read, never written: its lines are checked here and removed only from a run's copy.
    if [[ $user_file -eq 1 ]]; then
        cat "$src_cfg/${file#"~user/"}" > "$tmp/head-$id" 2>/dev/null || : > "$tmp/head-$id"
    else
        head_file "$file" > "$tmp/head-$id" || : > "$tmp/head-$id"
    fi
    if ! err="$(python3 "$here/lib/strip-lines.py" "$tmp/head-$id" "${ablate[@]}" 2>&1)"; then
        printf 'ablate.sh: %s is stale\n%s\n' "$id" "$err" >&2
        row "$today,$id,without,,,,,,,,,,stale,"
        continue
    fi

    runs="${runs_override:-$(jq -r .runs "$j")}"
    timeout="$(jq -r .timeout "$j")"
    budget="${budget_override:-$(jq -r .max_budget_usd "$j")}"
    budget="${budget:-1.00}"
    prompt="$(jq -r .prompt "$j")"
    check="$(jq -r .check "$j")"
    strict=0
    while IFS= read -r mp; do [[ -n "$mp" && "$file" == "$mp/"* ]] && strict=1; done <<EOF
$market_paths
EOF
    args=(-p "$prompt" --output-format stream-json --verbose --no-session-persistence --strict-mcp-config
          --max-turns "$(jq -r .max_turns "$j")" --max-budget-usd "$budget")
    tools=()
    while IFS= read -r t; do [[ -n "$t" ]] && tools+=("$t"); done < <(jq -r '.allowed_tools[]' "$j")
    [[ ${#tools[@]} -gt 0 ]] && args+=(--allowedTools "${tools[@]}")
    first_line="$( [[ -f "$csv" ]] && grep -c '' "$csv" || echo 0)"

    for arm in "${arms[@]}"; do
        [[ $halt -eq 0 ]] || break
        for i in $(seq 1 "$runs"); do
            wt="$tmp/wt/$id/$arm/run-$i"
            rd="$tmp/runs/$id/$arm/run-$i"
            mkdir -p "$rd"
            if ! build_worktree "$wt"; then
                echo "ablate.sh: could not build a worktree (or initialise its marketplace submodules) for $id $arm run $i" >&2
                row "$today,$id,$arm,$i,,,,,,,,,error,"; halt=1; break
            fi
            cfg="" home=""
            if [[ $token_mode -eq 1 ]] && ! make_config full; then
                echo "ablate.sh: could not make a config directory for $id $arm run $i" >&2
                row "$today,$id,$arm,$i,,,,,,,,,error,"; halt=1; break
            fi
            if [[ "$arm" == without ]]; then
                target_file="$wt/$file"
                [[ $user_file -eq 1 ]] && target_file="$cfg/${file#"~user/"}"
                if ! python3 "$here/lib/strip-lines.py" "$target_file" "${ablate[@]}" >/dev/null 2>&1; then
                    row "$today,$id,without,$i,,,,,,,,,stale,"; continue
                fi
            fi
            # The bare arm: every always-loaded file the repository has is emptied, and in token mode the
            # user-level file in this run's copy as well.
            if [[ "$arm" == bare || "$arm" == bare-repo ]]; then
                for f in "${always_loaded[@]}"; do
                    [[ -e "$wt/$f" ]] && : > "$wt/$f"
                done
                [[ $token_mode -eq 1 && -f "$cfg/CLAUDE.md" ]] && : > "$cfg/CLAUDE.md"
            fi
            # Fixtures are written from the parsed file, so no path or content passes through a shell. A
            # fixture that cannot be written makes the run an error, not a graded run without its input.
            if ! jq -c '.fixtures[]' "$j" | python3 -c '
import json, os, sys
root = sys.argv[1]
for line in sys.stdin:
    fx = json.loads(line)
    p = os.path.join(root, fx["path"])
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w", encoding="utf-8").write(fx["content"])' "$wt" 2> "$rd/fixture-error.txt"; then
                echo "ablate.sh: $id $arm run $i: could not write a fixture ($(tail -n 1 "$rd/fixture-error.txt"))" >&2
                row "$today,$id,$arm,$i,,,,,,,,,error,"
                git -C "$target" worktree remove --force "$wt" >/dev/null 2>&1
                continue
            fi

            run_env
            if [[ $dry -eq 1 ]]; then
                printf '%s %s run %s: cd %q && env' "$id" "$arm" "$i" "$wt"
                printf ' %q' "${renv[@]}"; printf ' claude'
                printf ' %q' "${args[@]}"; printf ' < /dev/null\n'
                continue
            fi

            # The run. --no-session-persistence keeps the transcript out of ~/.claude: the stream captured
            # here is the only record, and a Check reads tool calls from it.
            (cd "$wt" && exec env "${renv[@]}" claude "${args[@]}" \
                < /dev/null > "$rd/stream.jsonl" 2> "$rd/stderr.txt") &
            pid=$!
            started=$(date +%s) status="" problem="" init="" source=""
            # Watch the run: confirm the plugins and the login as soon as the init event appears, and stop
            # the run at the timeout. A run whose plugins are missing, or that is on an API key, is stopped
            # at once and the invocation halts.
            while kill -0 "$pid" 2>/dev/null; do
                if [[ -z "$init" ]]; then
                    init="$(grep -m1 '"subtype":"init"' "$rd/stream.jsonl" 2>/dev/null || true)"
                    if [[ -n "$init" ]]; then
                        problem="$(plugin_problem "$init" "$wt" "$strict")"
                        source="$(api_source "$init")"
                        billed "$source" && problem="api key: the init event reports $source, which would be billed; set AW_ALLOW_API_BILLING=1 to allow it"
                        [[ -n "$problem" ]] && { kill "$pid" 2>/dev/null; status=error; }
                    fi
                fi
                if [[ -z "$status" && $(( $(date +%s) - started )) -ge $timeout ]]; then
                    kill "$pid" 2>/dev/null; status=timeout
                fi
                sleep 0.2
            done
            wait "$pid" 2>/dev/null; rc=$?; pid=""
            if [[ -z "$init" ]]; then
                init="$(grep -m1 '"subtype":"init"' "$rd/stream.jsonl" 2>/dev/null || true)"
                if [[ -z "$init" ]]; then problem="no init event in the stream"; status="${status:-error}"
                else
                    problem="$(plugin_problem "$init" "$wt" "$strict")"
                    source="$(api_source "$init")"
                    billed "$source" && problem="api key: the init event reports $source, which would be billed; set AW_ALLOW_API_BILLING=1 to allow it"
                fi
                [[ -n "$problem" ]] && status=error
            fi
            [[ "$problem" == plugin* || "$problem" == "no init"* || "$problem" == "api key"* ]] && halt=1

            result="$(grep '"type":"result"' "$rd/stream.jsonl" 2>/dev/null | tail -n 1)"
            subtype="$(printf '%s' "${result:-$no_json}" | jq -r '.subtype // ""' 2>/dev/null)"
            is_error="$(printf '%s' "${result:-$no_json}" | jq -r 'if has("is_error") then (.is_error | tostring) else "" end' 2>/dev/null)"
            m="$(measures "$rd/stream.jsonl")"
            if [[ -z "$status" ]]; then
                [[ -n "$result" && "$subtype" == success && "$is_error" == false ]] && status=ok || status=error
            fi

            grade=""
            if [[ "$status" == ok && -n "$check" ]]; then
                # A Check is the ablation author's shell code, and its output is kept: it gets no login token.
                if (cd "$wt" && env -u CLAUDE_CODE_OAUTH_TOKEN AW_ABLATION_STREAM="$rd/stream.jsonl" AW_ABLATION_ARM="$arm" bash -c "$check") \
                    >"$rd/check.txt" 2>&1; then grade=1; else grade=0; fi
            fi
            while IFS= read -r o; do
                [[ -n "$o" && -e "$wt/$o" ]] && mkdir -p "$rd/outputs/$(dirname "$o")" && cp -R "$wt/$o" "$rd/outputs/$o"
            done < <(jq -r '.outputs[]' "$j")
            jq -n --arg date "$today" --arg id "$id" --arg arm "$arm" --argjson run "$i" --arg status "$status" --arg problem "$problem" \
                --arg subtype "$subtype" --argjson rc "$rc" --arg check "$grade" --argjson token_mode "$token_mode" --arg api_key_source "$source" \
                --argjson plugins "$(printf '%s' "${init:-$no_json}" | jq -c '[.plugins[]? | {source, path}]' 2>/dev/null || echo '[]')" \
                --argjson usage "$(printf '%s' "${result:-$no_json}" | jq -c '.usage // {}' 2>/dev/null || echo '{}')" \
                '{date: $date, ablation: $id, arm: $arm, run: $run, status: $status, problem: $problem, subtype: $subtype,
                  exit_code: $rc, check: $check, token_mode: ($token_mode == 1), api_key_source: $api_key_source,
                  plugins: $plugins, usage: $usage}' > "$rd/meta.json"
            row "$today,$id,$arm,$i,$grade,,$m,$status,$source"
            printf 'ablate.sh: %s %s run %s: %s%s%s\n' "$id" "$arm" "$i" "$status" "${grade:+, check $grade}" "${problem:+ — $problem}" >&2

            git -C "$target" worktree remove --force "$wt" >/dev/null 2>&1
            [[ $halt -eq 1 ]] && break
        done
    done
    # --no-judge leaves the with rows' judge column empty, so a later --keep folder can still be judged.
    [[ $dry -eq 0 && $halt -eq 0 && $no_judge -eq 0 ]] && judge_ablation "$j" "$tmp/runs" "$runs" "$first_line" 0
    [[ $dry -eq 1 && $no_judge -eq 0 && -n "$(jq -r .judge "$j")" ]] && printf '%s judge: run i of with and without, blind, from an empty directory, for i in 1..%s\n' "$id" "$runs"
done

if [[ $dry -eq 0 ]]; then
    render_report > "$report"
    echo "ablate.sh: results in ${csv#"$target"/}, report in ${report#"$target"/}" >&2
fi
[[ $halt -eq 0 ]] || exit 3
