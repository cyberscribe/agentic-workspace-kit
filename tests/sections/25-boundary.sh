# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh (SC2154); checks are "cond && ok || ko"
# (SC2015); single-quoted JSON and Markdown hold literal $ and backticks (SC2016).
# shellcheck disable=SC2154,SC2015,SC2016
# Section 25: the workspace boundary. The kit's plugins are installed for the person, so they load in
# every session; their hooks act only inside a kit workspace (hooks/lib/boundary.sh), and each command
# says where it works. Setup's user-scope step, run against a stub claude: it installs once and a re-run
# leaves it alone, it keeps the spelling the person reached the workspace by, and it does not re-point
# the person's marketplace away from another kit checkout unattended. Stage 7's attended steps, by path,
# through a pseudo-terminal. And the plugins_user_kit key.
# Everything here is prefixed s25_, since the sections share one shell.

echo
echo "25 · The workspace boundary: hooks inside a kit workspace only, and setup's user-scope install"

s25="$SCRATCH/s25"
mkdir -p "$s25"
s25_real() { (cd "$1" && pwd -P); }

# --- The helper -------------------------------------------------------------------------------------
s25_bad=""
for s25_p in closeout projects scheduler; do
    cmp -s "$KIT/plugins/workspace/hooks/lib/boundary.sh" "$KIT/plugins/$s25_p/hooks/lib/boundary.sh" \
        || s25_bad+="plugins/$s25_p/hooks/lib/boundary.sh differs from the workspace plugin's"$'\n'
done
empty "25 each plugin carries the same hooks/lib/boundary.sh" "$s25_bad"

# Fixtures: a workspace marked by its kit, one marked by the ledger alone, a symlink to the first, and a
# folder with neither (a git repository with the projects conventions, which the hooks once accepted).
s25_ws="$s25/ws"; s25_led="$s25/ledger-only"; s25_out="$s25/outside"; s25_link="$s25/ws-link"
mkdir -p "$s25_ws/kit" "$s25_ws/projects/alpha/notes" "$s25_led/.claude" "$s25_out/projects/alpha/notes" "$s25_out/.claude"
: > "$s25_ws/kit/CLAUDE.kit.md"; : > "$s25_led/.claude/kit-templates.lock"
git -C "$s25_out" init -q
ln -s "$s25_ws" "$s25_link"
# s25_root <input JSON> [VAR=value...]: what aw_workspace_root prints for it, from the folder $s25.
s25_root() {
    local in="$1"; shift
    (cd "$s25" && env "$@" "$st_bash" -c '. "$1"; aw_workspace_root "$2"' _ "$KIT/plugins/workspace/hooks/lib/boundary.sh" "$in")
}
s25_wsr="$(s25_real "$s25_ws")"
s25_bad=""
[[ -z "$(s25_root "{\"cwd\":\"$s25_out/projects/alpha\"}" CLAUDE_PROJECT_DIR=)" ]] || s25_bad+="a folder with no marker above it has a root"$'\n'
[[ "$(s25_root "{\"cwd\":\"$s25_ws\"}")" == "$s25_wsr" ]] || s25_bad+="the workspace's own folder"$'\n'
[[ "$(s25_root "{\"cwd\":\"$s25_ws/projects/alpha/notes\"}")" == "$s25_wsr" ]] || s25_bad+="two levels down"$'\n'
[[ "$(s25_root "{\"cwd\":\"$s25_link/projects/alpha\"}")" == "$s25_wsr" ]] || s25_bad+="through a symlink: $(s25_root "{\"cwd\":\"$s25_link/projects/alpha\"}")"$'\n'
[[ "$(s25_root "{\"cwd\":\"$s25_led\"}")" == "$(s25_real "$s25_led")" ]] || s25_bad+="the ledger alone"$'\n'
[[ -z "$(s25_root "{\"session_id\":\"x\",\"cwd\":\"$s25_out\",\"tool_input\":{\"cwd\":\"$s25_ws\"}}")" ]] \
    || s25_bad+="a cwd inside the tool input was read in place of the session's"$'\n'
[[ "$(s25_root '{"session_id":"x"}' CLAUDE_PROJECT_DIR="$s25_ws/projects")" == "$s25_wsr" ]] || s25_bad+="no cwd: CLAUDE_PROJECT_DIR not used"$'\n'
[[ -z "$(s25_root '{"cwd":"/no/such/folder"}')" ]] || s25_bad+="a folder that is not there has a root"$'\n'
empty "25 aw_workspace_root: none outside, the root from itself, two levels down and through a symlink, the ledger alone, the session's cwd and not a tool's" "$s25_bad"

# --- Every hook: silent outside, active inside -------------------------------------------------------
# guard-git: the bypass is denied inside and passes through outside.
s25_guard() {
    printf '{"session_id":"t","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git commit --no''-verify -m x"}}' "$1" \
        | "$st_bash" "$KIT/plugins/workspace/hooks/guard-git.sh" 2>/dev/null
}
s25_bad=""
for s25_c in "$s25_ws" "$s25_ws/projects/alpha/notes" "$s25_link/projects/alpha"; do
    [[ "$(s25_guard "$s25_c")" == *'"deny"'* ]] || s25_bad+="not denied in ${s25_c#"$s25"/}"$'\n'
done
[[ -z "$(s25_guard "$s25_out/projects/alpha")" ]] || s25_bad+="answered outside: $(s25_guard "$s25_out/projects/alpha")"$'\n'
empty "25 workspace PreToolUse guard: denies inside (root, two down, by a symlink), silent outside" "$s25_bad"

# projects SessionStart: a project folder with a Current state block speaks, inside; the same folder
# outside, in a repository with .claude/projects.md, says nothing.
s25_readme='# Alpha

**Outcome:** A thing, done.

## Done when

- [ ] It is done.

## Current state

<!-- current-state -->
**Status:** doing · **Updated:** 2026-10-01 · **Owner:** Sam
**Now:** building it.
<!-- /current-state -->
'
for s25_d in "$s25_ws" "$s25_out"; do
    printf '%s' "$s25_readme" > "$s25_d/projects/alpha/README.md"
    mkdir -p "$s25_d/.claude"; printf '# Projects\n' > "$s25_d/.claude/projects.md"
done
s25_proj() {
    jq -nc --arg c "$1" '{cwd: $c, source: "startup"}' \
        | env PROJECTS_HOOK_STATE_DIR="$s25/stamps" "$st_bash" "$KIT/plugins/projects/hooks/session-start.sh" 2>/dev/null
}
s25_bad=""
[[ -n "$(s25_proj "$s25_ws/projects/alpha")" ]] || s25_bad+="nothing inside"$'\n'
[[ -n "$(s25_proj "$s25_link/projects/alpha")" ]] || s25_bad+="nothing by the symlink"$'\n'
[[ -z "$(s25_proj "$s25_out/projects/alpha")" ]] || s25_bad+="spoke outside: $(s25_proj "$s25_out/projects/alpha")"$'\n'
empty "25 projects SessionStart: the project's line inside (and by a symlink), nothing outside" "$s25_bad"

# projects pair hooks: with the launcher's variables, start records the session inside and not outside.
s25_bad=""
for s25_d in "$s25_ws" "$s25_out"; do
    s25_mb="$s25_d/projects/alpha/mailbox"; mkdir -p "$s25_mb"; rm -f "$s25_mb"/.cc-*
    printf '# To CC\n' > "$s25_mb/to-cc.md"; printf '# To the PM\n' > "$s25_mb/to-pm.md"
    printf '{"session_id":"s25","cwd":"%s"}' "$s25_d/projects/alpha" \
        | PAIR_ROLE=cc PAIR_MAILBOX="$s25_mb" "$st_bash" "$KIT/plugins/projects/hooks/pair.sh" start >/dev/null 2>&1
done
[[ -f "$s25_ws/projects/alpha/mailbox/.cc-session" ]] || s25_bad+="start did not record the session inside"$'\n'
[[ ! -e "$s25_out/projects/alpha/mailbox/.cc-session" ]] || s25_bad+="start recorded the session outside"$'\n'
s25_rc="$(printf '{"session_id":"s25","cwd":"%s"}' "$s25_out/projects/alpha" \
    | PAIR_ROLE=cc PAIR_MAILBOX="$s25_out/projects/alpha/mailbox" "$st_bash" "$KIT/plugins/projects/hooks/pair.sh" stop >/dev/null 2>&1; echo $?)"
[[ "$s25_rc" == 0 && ! -e "$s25_out/projects/alpha/mailbox/.cc-state" ]] || s25_bad+="stop acted outside (exit $s25_rc)"$'\n'
empty "25 projects pair hooks: start and stop act inside, pass through outside" "$s25_bad"

# closeout SessionStart: a waiting draft is offered inside, not outside (each folder has one).
s25_drafts="$s25/drafts"
for s25_d in "$s25_ws" "$s25_out"; do
    mkdir -p "$s25_drafts/$(basename "$s25_d")"
    printf '# A draft\n' > "$s25_drafts/$(basename "$s25_d")/2026-10-01-a-draft.md"
done
s25_review() {
    jq -nc --arg c "$1" '{cwd: $c, source: "startup"}' \
        | env CLOSEOUT_DRAFT_ROOT="$s25_drafts" CLOSEOUT_USER_CONVENTIONS= "$st_bash" "$KIT/plugins/closeout/hooks/closeout-review.sh" 2>/dev/null
}
s25_bad=""
[[ "$(s25_review "$s25_ws")" == *a-draft* ]] || s25_bad+="the draft is not offered inside"$'\n'
[[ -z "$(s25_review "$s25_out")" ]] || s25_bad+="offered outside: $(s25_review "$s25_out" | head -c 200)"$'\n'
empty "25 closeout SessionStart: a waiting draft offered inside, nothing outside" "$s25_bad"

# closeout SessionEnd: outside, no capture child is started (a stub claude records any start).
s25_stub="$s25/stub-bin"; mkdir -p "$s25_stub"
printf '#!/bin/bash\necho "started $*" >> "%s"\n' "$s25/capture.log" > "$s25_stub/claude"; chmod +x "$s25_stub/claude"
printf '{"type":"user","message":{"role":"user","content":"hello"}}\n' > "$s25/transcript.jsonl"
: > "$s25/capture.log"
jq -nc --arg c "$s25_out" --arg t "$s25/transcript.jsonl" '{cwd: $c, reason: "exit", session_id: "s25", transcript_path: $t}' \
    | env PATH="$s25_stub:$PATH" CLOSEOUT_DRAFT_ROOT="$s25_drafts" "$st_bash" "$KIT/plugins/closeout/hooks/closeout-capture.sh" >/dev/null 2>&1
s25_rc=$?
sleep 1
[[ $s25_rc -eq 0 && ! -s "$s25/capture.log" ]] && ok "25 closeout SessionEnd: outside, exits 0 and starts no capture" \
    || ko "25 closeout SessionEnd: outside, exits 0 and starts no capture" "exit $s25_rc; $(cat "$s25/capture.log")"

# workspace SessionStart: the out-of-step summary for a workspace marked by its ledger, nothing outside.
s25_wss() {
    jq -nc --arg c "$1" '{cwd: $c, source: "startup"}' | "$st_bash" "$KIT/plugins/workspace/hooks/session-start.sh" 2>/dev/null
}
s25_bad=""
[[ -n "$(s25_wss "$s25_led")" ]] || s25_bad+="nothing for a workspace with only its ledger, which is out of step"$'\n'
[[ -z "$(s25_wss "$s25_out/projects/alpha")" ]] || s25_bad+="spoke outside"$'\n'
empty "25 workspace SessionStart: a summary inside, nothing outside" "$s25_bad"

# --- The commands -----------------------------------------------------------------------------------
s25_bad=""
# The scheduler is the one exception: a task names the folder it runs in, so /scheduler:tasks works
# in any folder, and its Where this works section says so.
for s25_f in "$KIT"/plugins/*/commands/*.md; do
    s25_pl="$(basename "$(dirname "$(dirname "$s25_f")")")"; s25_n="$(basename "$s25_f" .md)"
    s25_c="/$s25_pl:$s25_n"; [[ $s25_pl == closeout ]] && s25_c=/closeout
    s25_w="$(awk '/^## Where this works$/ { on = 1; next } on && /^## / { exit } on' "$s25_f" | tr '\n' ' ')"
    if [[ $s25_c == /scheduler:tasks ]]; then
        grep -qF "\`$s25_c\` works in any folder" <<<"$s25_w" || s25_bad+="${s25_f#"$KIT"/}: no line saying $s25_c works in any folder"$'\n'
        continue
    fi
    grep -qF "say in one line that \`$s25_c\` works inside a kit workspace, and do nothing" <<<"$s25_w" \
        || s25_bad+="${s25_f#"$KIT"/}: no outside-a-workspace line naming $s25_c"$'\n'
done
empty "25 every command says, outside a kit workspace, in one line that it works inside one, and stops; /scheduler:tasks says it works in any folder" "$s25_bad"

# --- plugins_user_kit --------------------------------------------------------------------------------
if [[ $kitsrc_ok -eq 1 ]]; then
    s25_w="$s25/st-ws"; mkws_min "$s25_w" >/dev/null 2>&1
    s25_cc="$s25/cc-state"; mkdir -p "$s25_cc"
    s25_mk() { jq -n --arg p "$1" '{extraKnownMarketplaces: {"agentic-workspace": {source: {source: "directory", path: $p}}}}' > "$s25_cc/settings.json"; }
    rm -f "$s25_cc/settings.json"
    st_expect "25 plugins_user_kit=none with no user-scope marketplace" "$(CLAUDE_CONFIG_DIR="$s25_cc" st_run "$s25_w")" plugins_user_kit=none
    ln -s "$s25_w" "$s25/st-ws-link"
    s25_mk "$s25/st-ws-link/kit"
    st_expect "25 plugins_user_kit=this when it names this workspace's kit, by a symlink" "$(CLAUDE_CONFIG_DIR="$s25_cc" st_run "$s25_w")" plugins_user_kit=this
    s25_mk "$KITSRC"
    st_expect "25 plugins_user_kit=elsewhere when it names another checkout" "$(CLAUDE_CONFIG_DIR="$s25_cc" st_run "$s25_w")" plugins_user_kit=elsewhere
else
    skp "25 plugins_user_kit — needs the kit source repository"
fi

# --- Setup's user-scope step, against a stub claude ----------------------------------------------------
# The stub logs each call and writes what the real one writes to the person's settings.json:
# marketplace add puts the directory source under extraKnownMarketplaces, install sets enabledPlugins.
s25_cl="$s25/claude-stub"
cat > "$s25_cl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$S25_LOG"
f="$CLAUDE_CONFIG_DIR/settings.json"; [ -f "$f" ] || echo '{}' > "$f"
case "$1 $2" in
    "plugin marketplace") for a in "$@"; do p="$a"; done
        jq --arg p "$p" '.extraKnownMarketplaces["agentic-workspace"] = {source: {source: "directory", path: $p}}' "$f" > "$f.t" && mv "$f.t" "$f" ;;
    "plugin install") jq --arg k "$3" '.enabledPlugins[$k] = true' "$f" > "$f.t" && mv "$f.t" "$f" ;;
esac
STUB
chmod +x "$s25_cl"
# s25_setup <log> <calls log> <config dir> <folder to run from>: setup unattended, from that folder, no --target.
s25_setup() {
    (cd "$4" && env AW_CLAUDE="$s25_cl" S25_LOG="$2" CLAUDE_CONFIG_DIR="$3" AW_WIZARD_NONINTERACTIVE=1 \
        "$st_bash" kit/setup.sh </dev/null >"$1" 2>&1)
}
if mkws "$s25/setup-ws" >/dev/null 2>&1; then
    ln -s "$s25/setup-ws" "$s25/setup-link"
    s25_cc="$s25/cc-setup"; mkdir -p "$s25_cc"; : > "$s25/calls.log"
    s25_setup "$s25/setup1.log" "$s25/calls.log" "$s25_cc" "$s25/setup-link"
    s25_bad=""
    [[ "$(head -n 1 "$s25/calls.log")" == "plugin marketplace add --scope user $s25/setup-link/kit" ]] \
        || s25_bad+="marketplace add, by the symlink: $(head -n 1 "$s25/calls.log")"$'\n'
    for s25_p in closeout projects scheduler workspace; do
        grep -qxF "plugin install $s25_p@agentic-workspace --scope user" "$s25/calls.log" || s25_bad+="no user-scope install of $s25_p"$'\n'
    done
    grep -q 'plugins_scope=user' "$s25/setup1.log" || s25_bad+="stage 9 does not report plugins_scope=user"$'\n'
    grep -q '^  7\. [^:]*: done' "$s25/setup1.log" || s25_bad+="stage 7: $(grep '^  7\. ' "$s25/setup1.log" | tail -n 1)"$'\n'
    empty "25 setup, unattended: the marketplace added for the person by the spelling they came in by, the kit's plugins installed for them, stage 9 says so" "$s25_bad"

    : > "$s25/calls2.log"
    s25_setup "$s25/setup2.log" "$s25/calls2.log" "$s25_cc" "$s25/setup-link"
    [[ ! -s "$s25/calls2.log" ]] && grep -q "installed for you, from this workspace's kit/" "$s25/setup2.log" \
        && ok "25 setup again: already installed for the person, so claude is not run" \
        || ko "25 setup again: already installed for the person, so claude is not run" "$(cat "$s25/calls2.log")"

    # Another kit checkout already registered for the person: unattended, it is left where it is.
    s25_cc="$s25/cc-other"; mkdir -p "$s25_cc"; : > "$s25/calls3.log"
    jq -n --arg p "$KITSRC" '{extraKnownMarketplaces: {"agentic-workspace": {source: {source: "directory", path: $p}}}}' > "$s25_cc/settings.json"
    s25_setup "$s25/setup3.log" "$s25/calls3.log" "$s25_cc" "$s25/setup-ws"
    s25_bad=""
    [[ ! -s "$s25/calls3.log" ]] || s25_bad+="claude was run: $(cat "$s25/calls3.log")"$'\n'
    grep -qF "already take the kit's plugins from another checkout: $KITSRC" "$s25/setup3.log" || s25_bad+="no warning naming the other checkout"$'\n'
    grep -q 'plugins_user_kit=elsewhere' "$s25/setup3.log" || s25_bad+="stage 9 does not report plugins_user_kit=elsewhere"$'\n'
    [[ "$(jq -r '.extraKnownMarketplaces["agentic-workspace"].source.path' "$s25_cc/settings.json")" == "$KITSRC" ]] || s25_bad+="the person's marketplace was re-pointed"$'\n'
    empty "25 setup, unattended, with the person's marketplace on another kit checkout: warns, leaves it, stage 9 names the commands" "$s25_bad"

    # Stage 7 attended. A pseudo-terminal makes the run attended; whenever the output stops on an
    # unfinished line (a question or a pause), the driver answers it: the first rule whose text is in
    # that line gives the answer, otherwise Enter takes the default.
    cat > "$s25/pty.py" <<'S25PY'
import json, os, pty, re, select, sys, time
rules = json.loads(sys.argv[1])
try:
    pid, fd = pty.fork()
except OSError as e:
    print("S25-NO-PTY", e); sys.exit(0)
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
out = b""; answered = 0; deadline = time.time() + 300
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if fd in r:
        try: data = os.read(fd, 65536)
        except OSError: break
        if not data: break
        out += data; continue
    text = out.decode("utf-8", "replace").replace("\r", "")
    if len(text) > answered and not text.endswith("\n"):
        line = text.rsplit("\n", 1)[-1]
        os.write(fd, (next((a for t, a in rules if t in line), "") + "\n").encode()); answered = len(text)
_, st = os.waitpid(pid, 0)
sys.stdout.write(re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out.decode("utf-8", "replace")).replace("\r", ""))
print("S25-RC", os.WEXITSTATUS(st) if os.WIFEXITED(st) else 128)
S25PY
    # s25_att <name> <claude> <config dir> <rules>: setup attended from the workspace, entered by its
    # symlink; stage 7's screen
    # goes to <name>.7, the claude calls to <name>.calls.
    s25_att() {
        : > "$s25/$1.calls"; mkdir -p "$3"
        (cd "$s25/setup-link" && env -u AW_WIZARD_NONINTERACTIVE AW_CLAUDE="$2" S25_LOG="$s25/$1.calls" CLAUDE_CONFIG_DIR="$3" \
            python3 -I "$s25/pty.py" "$4" "$st_bash" kit/setup.sh >"$s25/$1.log" 2>&1)
        sed -n '/Stage 7 of/,/Stage 8 of/p' "$s25/$1.log" > "$s25/$1.7"
    }
    s25_offer() {
        grep -qF "4. Accept the offer to install the agentic-workspace marketplace" "$s25/$1.7" || s25_bad+="$1: no install offer"$'\n'
        grep -qF "6. If agentic-workspace is listed at another path" "$s25/$1.7" || s25_bad+="$1: no re-pointing step"$'\n'
        ! grep -qF "Type / and check" "$s25/$1.7" || s25_bad+="$1: the installed-for-you steps"$'\n'
    }
    s25_att att-user "$s25_cl" "$s25/cc-att-user" '[["Were they all listed?", "n"]]'
    if grep -q '^S25-NO-PTY' "$s25/att-user.log"; then
        skp "25 setup attended, stage 7 by path — no pseudo-terminal here ($(sed -n 's/^S25-NO-PTY //p' "$s25/att-user.log"))"
    else
        s25_bad=""
        grep -q '^S25-RC 0$' "$s25/att-user.log" || s25_bad+="exit: $(grep '^S25-RC' "$s25/att-user.log")"$'\n'
        [[ "$(wc -l < "$s25/att-user.calls" | tr -d ' ')" -eq 5 ]] || s25_bad+="claude calls: $(cat "$s25/att-user.calls")"$'\n'
        grep -qF "2. Start a new one there:  cd $(printf '%q' "$s25/setup-link") && claude" "$s25/att-user.7" || s25_bad+="step 2 does not name the folder by the symlink"$'\n'
        grep -qF "4. Type / and check that /closeout, /projects:new, /scheduler:tasks and /workspace:hygiene are listed." "$s25/att-user.7" || s25_bad+="no step 4 to look for the commands"$'\n'
        grep -qF "start one more new one there" "$s25/att-user.7" || s25_bad+="no second-session step"$'\n'
        grep -qF "  claude plugin list" "$s25/att-user.7" || s25_bad+="the fallback does not name claude plugin list"$'\n'
        ! grep -qiF "offer" "$s25/att-user.7" || s25_bad+="names an install offer: $(grep -iF offer "$s25/att-user.7")"$'\n'
        ! grep -qF "Type /plugin" "$s25/att-user.7" || s25_bad+="names the /plugin check"$'\n'
        ! grep -qF "marketplace remove" "$s25/att-user.7" || s25_bad+="names the re-pointing steps"$'\n'
        [[ -z "$s25_bad" ]] || s25_bad+="stage 7:"$'\n'"$(cat "$s25/att-user.7")"
        empty "25 setup attended, installed for the person: stage 7 asks for a new session there, by the path the person came in by, and a look at /, with no install offer or re-pointing, and its fallback names claude plugin list" "$s25_bad"

        s25_bad=""
        s25_att att-no "$s25_cl" "$s25/cc-att-no" '[["Install them for you now?", "n"]]'
        [[ ! -s "$s25/att-no.calls" ]] || s25_bad+="att-no: claude was run"$'\n'
        s25_offer att-no
        s25_att att-none "$SCRATCH/no-claude" "$s25/cc-att-none" '[]'
        grep -qF "claude is not on PATH, so the plugins are not installed for you yet" "$s25/att-none.7" || s25_bad+="att-none: no note"$'\n'
        s25_offer att-none
        mkdir -p "$s25/cc-att-else"
        jq -n --arg p "$KITSRC" '{extraKnownMarketplaces: {"agentic-workspace": {source: {source: "directory", path: $p}}}}' > "$s25/cc-att-else/settings.json"
        s25_att att-else "$s25_cl" "$s25/cc-att-else" '[]'
        grep -qF "Point it at this workspace's kit instead? (y/n) [n]" "$s25/att-else.7" || s25_bad+="att-else: not asked to re-point"$'\n'
        [[ ! -s "$s25/att-else.calls" ]] || s25_bad+="att-else: claude was run"$'\n'
        s25_offer att-else
        empty "25 setup attended, install declined, no claude, or the person's marketplace on another checkout: stage 7 keeps the install offer and the re-pointing steps" "$s25_bad"
    fi
else
    skp "25 setup's user-scope step — needs a workspace built by setup new"
fi

# --- Live: one plugin id at both scopes loads once --------------------------------------------------
# After setup the workspace's settings and the person's both enable the same three ids. Claude Code
# loads each once, so each SessionStart hook runs once, not twice. Starts Claude Code (no model call:
# the hook events and the init message come before one), under a config directory of its own.
if cc_gate "25 the same plugins enabled for the person and by the workspace load once, each SessionStart hook run once"; then
    s25_lw="$s25/live-ws"; s25_ccc="$s25/cc-live"; mkdir -p "$s25_ccc"
    if mkws "$s25_lw" >/dev/null 2>&1; then
        (cd "$s25_lw" && env -u PAIR_ROLE -u PAIR_MAILBOX AW_CLAUDE=claude CLAUDE_CONFIG_DIR="$s25_ccc" AW_WIZARD_NONINTERACTIVE=1 \
            "$st_bash" kit/setup.sh </dev/null >"$s25/live-setup.log" 2>&1)
        jq --arg p "$(s25_real "$s25_lw")" '.projects[$p].hasTrustDialogAccepted = true' "$s25_ccc/.claude.json" > "$s25_ccc/.claude.json.t" 2>/dev/null \
            || jq -n --arg p "$(s25_real "$s25_lw")" '{projects: {($p): {hasTrustDialogAccepted: true}}}' > "$s25_ccc/.claude.json.t"
        mv "$s25_ccc/.claude.json.t" "$s25_ccc/.claude.json"
        # Two sessions, since the first after trust may register the marketplace without loading it.
        for s25_i in 1 2; do
            (cd "$s25_lw" && env -u PAIR_ROLE -u PAIR_MAILBOX CLOSEOUT_DRAFT_ROOT="$s25/drafts-live" CLAUDE_CONFIG_DIR="$s25_ccc" \
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 \
                claude -p ok --include-hook-events --output-format stream-json --verbose </dev/null 2>/dev/null \
                | awk '{ print } /"subtype":"init"/ { exit }' > "$s25/live-$s25_i.jsonl")
            printf -- '- %s tests/run.sh: 25 hooks once, session %s (claude -p, ended at init)\n' "$(date '+%F %H:%M')" "$s25_i" >> "$AW_CC_LOG" 2>/dev/null
        done
        s25_want="$(cat "$KIT"/plugins/*/hooks/hooks.json | jq -s '[.[].hooks.SessionStart[]? | select((.matcher // "") | test("startup")) | .hooks[]] | length')"
        s25_bad=""
        for s25_f in "$s25_lw/.claude/settings.json" "$s25_ccc/settings.json"; do
            [[ "$(jq -c '[.enabledPlugins // {} | to_entries[] | select(.key | endswith("@agentic-workspace")) | select(.value)] | length' "$s25_f")" == 4 ]] \
                || s25_bad+="${s25_f##*/} in $(basename "$(dirname "$s25_f")") does not enable all four"$'\n'
        done
        s25_names="$(jq -r 'select(.subtype == "init") | .plugins[] | select(.path != "builtin") | .name' "$s25/live-2.jsonl" | sort | paste -sd, -)"
        [[ "$s25_names" == closeout,projects,scheduler,workspace ]] || s25_bad+="the second session loads: ${s25_names:-nothing}"$'\n'
        s25_got="$(jq -c 'select(.subtype == "hook_started" and .hook_event == "SessionStart")' "$s25/live-2.jsonl" | wc -l | tr -d ' ')"
        [[ "$s25_got" == "$s25_want" ]] || s25_bad+="$s25_got SessionStart hooks started, against $s25_want in the kit's hooks.json files"$'\n'
        empty "25 the same plugins enabled for the person and by the workspace load once, each SessionStart hook run once" "$s25_bad"
    else
        ko "25 the same plugins enabled for the person and by the workspace load once — the workspace could not be built"
    fi
fi
