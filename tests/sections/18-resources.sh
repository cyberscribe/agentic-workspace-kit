# shellcheck shell=bash
# The prelude in tests/run.sh defines kitsrc_ok, st_bash, STATE and the check helpers; "cond && ok ||
# ko" is the suite's idiom, and ok always succeeds.
# shellcheck disable=SC2154,SC2015
# Section 18: resources outside the workspace, and kit/setup.sh link (lib/setup/link.sh).
#
# Sourced by tests/run.sh after section 11; every name here carries the s18_ prefix, and everything is
# written under $SCRATCH. The fixtures are mkws_min workspaces with three projects (one of them a
# gitlink, one under projects/_done/), resource folders under $SCRATCH/s18-ext, and a HOME of their
# own so a mapping written with ~/ has somewhere to point. The state.sh checks run once state.sh
# reports state_version=2 (C4), and are skipped by name until then.

echo "18 · Resources outside the workspace: kit/setup.sh link"

if [[ $kitsrc_ok -ne 1 ]]; then
    skp "18 resources — no KITSRC (the kit is not a git checkout), so no fixture workspace can be built"
else

s18_ext="$SCRATCH/s18-ext"
s18_home="$SCRATCH/s18-home"
mkdir -p "$s18_ext/media" "$s18_ext/other-media" "$s18_ext/contracts" "$s18_ext/notes-dir" \
    "$s18_ext/locked" "$s18_ext/shut/inner" "$s18_ext/already" "$s18_home/drive/media"
printf 'an interview\n' > "$s18_ext/media/one.txt"
chmod 000 "$s18_ext/locked" "$s18_ext/shut"

# A repository for the gitlink project, added to each fixture as projects/vendor-review.
s18_vsrc="$SCRATCH/s18-vendor-src"
mkdir -p "$s18_vsrc" && git -C "$s18_vsrc" init -q && git -C "$s18_vsrc" symbolic-ref HEAD refs/heads/main
printf '# Vendor review\n\n## Resources\n\n- contracts — the signed contracts\n' > "$s18_vsrc/README.md"
git -C "$s18_vsrc" add -A && git -C "$s18_vsrc" -c commit.gpgsign=false commit -q -m "Vendor review"

# s18_readme <file> <resource line...>: a project README with the two 3.0 lines and a Resources list.
s18_readme() {
    local f="$1" t; shift
    mkdir -p "$(dirname "$f")"
    t="$(basename "$(dirname "$f")")"
    {
        printf '# %s\n\n- **Versioned:** workspace\n- **Sensitivity:** normal\n\n## Resources\n\n' "$t"
        printf -- '- %s\n' "$@"
        printf '\n## Where everything lives\n\nHere.\n'
    } > "$f"
}

# s18_fixture <dir> [nomap]: a workspace with the three projects; without nomap, the mappings and a
# settings.local.json seeded with an allow list and other keys.
s18_fixture() {
    local d="$1"
    mkws_min "$d" || return 1
    s18_readme "$d/projects/field-study/README.md" \
        "media — raw interview recordings (large; kept outside git)" \
        "exports — generated renders; rebuilt by \`make render\`" \
        "survey-data — the survey responses extract, read-only" \
        "locked — a folder this shell cannot read" \
        "deep — a folder under one this shell cannot enter" \
        "notes — field notes" \
        "bad name — a name with a space in it"
    s18_readme "$d/projects/_done/old-study/README.md" "archive — the earlier recordings"
    git -C "$d" -c protocol.file.allow=always submodule add -q -b main "$s18_vsrc" projects/vendor-review >/dev/null 2>&1 || return 1
    [[ "${2:-}" == nomap ]] && return 0
    printf '%s\n' '# Resources on this machine' '' 'One line per project and name.' '' \
        "field-study/media        $s18_ext/other-media" \
        "field-study/media        $s18_ext/media   " \
        "field-study/survey-data  $s18_ext/not-here" \
        "field-study/locked$(printf '\t')$s18_ext/locked" \
        "field-study/deep         $s18_ext/shut/inner" \
        "vendor-review/contracts  $s18_ext/contracts/" \
        "old-study/archive        ~/drive/media" \
        "a line that is not a mapping" > "$d/.claude/resources.local.md"
    cat > "$d/.claude/settings.local.json" <<EOF
{
  "permissions": {
    "allow": ["Bash(ls:*)", "Bash(git status)", "Read(./docs/**)", "WebSearch", "Bash(jq:*)"],
    "additionalDirectories": ["$s18_ext/already"],
    "deny": ["Read(./.env)"]
  },
  "env": { "EXAMPLE": "1" },
  "enableAllProjectMcpServers": false
}
EOF
}

# s18_run <ws> [args...]: link.sh unattended, from the fixture's own kit. Output (stdout and stderr)
# in s18_out, status in s18_rc.
s18_run() {
    local ws="$1"; shift
    s18_out="$(AW_WIZARD_NONINTERACTIVE=1 HOME="$s18_home" "$st_bash" "$ws/kit/lib/setup/link.sh" --target "$ws" "$@" </dev/null 2>&1)"
    s18_rc=$?
}
# s18_has <line...>: every line appears in s18_out exactly; the missing ones are returned in s18_bad.
s18_has() {
    local l; s18_bad=""
    for l in "$@"; do
        printf '%s\n' "$s18_out" | awk -v l="$l" '$0 == l { f = 1 } END { exit !f }' || s18_bad+="no line: $l"$'\n'
    done
    [[ -z "$s18_bad" ]] || s18_bad+="output:"$'\n'"$s18_out"
}
s18_target() { [[ -L "$1" ]] && readlink "$1"; }

s18_ws="$SCRATCH/s18-ws"
if ! s18_fixture "$s18_ws"; then
    ko "18 fixture workspace builds (mkws_min, three projects, a gitlink)"
else

s18_ld="$s18_ws/kit/lib/setup/link.sh"
if grep -q 'not built yet' "$s18_ld" 2>/dev/null; then
    ko "18 lib/setup/link.sh is built" "still the wave-0 placeholder"
fi

# ---- The first run: every kind of line ----------------------------------------------------------------
s18_map_before="$(cat "$s18_ws/.claude/resources.local.md")"
s18_settings_before="$(cat "$s18_ws/.claude/settings.local.json")"
s18_run "$s18_ws"
[[ $s18_rc -eq 0 ]] && ok "18 link exits 0 with resources missing, unreadable and unmapped" \
    || ko "18 link exits 0 with resources missing, unreadable and unmapped" "rc $s18_rc"$'\n'"$s18_out"

s18_bad=""
[[ "$(s18_target "$s18_ws/projects/field-study/.resources/media")" == "$s18_ext/media" ]] \
    || s18_bad+="field-study/media: $(s18_target "$s18_ws/projects/field-study/.resources/media") (the last mapping wins)"$'\n'
[[ "$(s18_target "$s18_ws/projects/vendor-review/.resources/contracts")" == "$s18_ext/contracts" ]] \
    || s18_bad+="vendor-review/contracts: $(s18_target "$s18_ws/projects/vendor-review/.resources/contracts") (trailing slash dropped)"$'\n'
[[ "$(s18_target "$s18_ws/projects/_done/old-study/.resources/archive")" == "$s18_home/drive/media" ]] \
    || s18_bad+="old-study/archive: $(s18_target "$s18_ws/projects/_done/old-study/.resources/archive") (~/ expanded)"$'\n'
for s18_n in survey-data locked deep notes exports; do
    [[ -e "$s18_ws/projects/field-study/.resources/$s18_n" || -L "$s18_ws/projects/field-study/.resources/$s18_n" ]] \
        && s18_bad+="a link for $s18_n, which is not readable or not mapped"$'\n'
done
empty "18 setup.sh link makes the symlinks: the last mapping wins, ~/ expands, a done project is linked, nothing else is" "$s18_bad"

s18_has "linked   field-study/media -> $s18_ext/media" \
    "granted  $s18_ext/media" \
    "For Cowork: Add folder $s18_ext/media (once per machine)" \
    "missing  field-study/survey-data (mapped to $s18_ext/not-here; not on this machine now)" \
    "no-permission field-study/locked ($s18_ext/locked)" \
    "no-permission field-study/deep ($s18_ext/shut/inner)" \
    "unmapped field-study/notes" \
    "inside   field-study/exports (generated; kept out of git)" \
    "ignored  field-study/bad name (a resource name is letters, digits, dot, dash, underscore)" \
    "linked   vendor-review/contracts -> $s18_ext/contracts" \
    "linked   old-study/archive -> $s18_home/drive/media"
empty "18 link prints the linked, granted, missing, no-permission, unmapped, inside and ignored lines" "$s18_bad"

s18_sl="$s18_ws/.claude/settings.local.json"
s18_bad=""
[[ "$(jq -c '.permissions.allow' "$s18_sl")" == "$(printf '%s' "$s18_settings_before" | jq -c '.permissions.allow')" ]] \
    || s18_bad+="allow list changed: $(jq -c '.permissions.allow' "$s18_sl")"$'\n'
[[ "$(jq -c 'keys_unsorted' "$s18_sl")" == '["permissions","env","enableAllProjectMcpServers"]' ]] \
    || s18_bad+="top-level keys: $(jq -c 'keys_unsorted' "$s18_sl")"$'\n'
[[ "$(jq -c '.permissions | keys_unsorted' "$s18_sl")" == '["allow","additionalDirectories","deny"]' ]] \
    || s18_bad+="permissions keys: $(jq -c '.permissions | keys_unsorted' "$s18_sl")"$'\n'
[[ "$(jq -c '[.permissions.deny, .env, .enableAllProjectMcpServers]' "$s18_sl")" == '[["Read(./.env)"],{"EXAMPLE":"1"},false]' ]] \
    || s18_bad+="other keys: $(jq -c '[.permissions.deny, .env, .enableAllProjectMcpServers]' "$s18_sl")"$'\n'
s18_want="$(jq -nc --arg a "$s18_ext/already" --arg b "$s18_ext/media" --arg c "$s18_ext/contracts" --arg d "$s18_home/drive/media" '[$a, $b, $c, $d]')"
[[ "$(jq -c '.permissions.additionalDirectories' "$s18_sl")" == "$s18_want" ]] \
    || s18_bad+="additionalDirectories: $(jq -c '.permissions.additionalDirectories' "$s18_sl"), wanted $s18_want"$'\n'
empty "18 link adds to additionalDirectories in a settings.local.json seeded with an allow list, which survives, order included, with every other key" "$s18_bad"

s18_ex="$(cd "$s18_ws/projects/vendor-review" && git rev-parse --git-path info/exclude)"
[[ "$s18_ex" == /* ]] || s18_ex="$s18_ws/projects/vendor-review/$s18_ex"
s18_bad=""
grep -qx '/.resources/' "$s18_ex" 2>/dev/null || s18_bad+="no /.resources/ line in $s18_ex"$'\n'
[[ -z "$(git -C "$s18_ws/projects/vendor-review" status --porcelain)" ]] \
    || s18_bad+="the project repository sees: $(git -C "$s18_ws/projects/vendor-review" status --porcelain)"$'\n'
[[ ! -e "$s18_ws/projects/vendor-review/.gitignore" ]] || s18_bad+="a .gitignore was written in the gitlink project"$'\n'
empty "18 link writes info/exclude for a gitlink project, and the project's repository stays clean" "$s18_bad"

s18_bad=""
grep -qx '/exports/' "$s18_ws/projects/field-study/.gitignore" 2>/dev/null || s18_bad+="no /exports/ in projects/field-study/.gitignore"$'\n'
git -C "$s18_ws" check-ignore -q projects/field-study/.resources/media || s18_bad+="the workspace does not ignore .resources/media"$'\n'
git -C "$s18_ws" check-ignore -q projects/_done/old-study/.resources/archive || s18_bad+="the workspace does not ignore _done/old-study/.resources/archive"$'\n'
empty "18 an inside resource is listed in the project's .gitignore, and the links are ignored by the workspace" "$s18_bad"

[[ "$(cat "$s18_ws/.claude/resources.local.md")" == "$s18_map_before" ]] \
    && ok "18 unattended, link leaves resources.local.md as it was" \
    || ko "18 unattended, link leaves resources.local.md as it was"

# ---- A second run changes nothing -------------------------------------------------------------------
s18_t0="$(st_tree "$s18_ws")"
s18_run "$s18_ws"
s18_t1="$(st_tree "$s18_ws")"
s18_bad=""
[[ "$s18_t0" == "$s18_t1" ]] || s18_bad+="$(diff <(printf '%s\n' "$s18_t0") <(printf '%s\n' "$s18_t1") | head -n 10)"$'\n'
printf '%s\n' "$s18_out" | grep -q '^granted' && s18_bad+="a second granted line"$'\n'
empty "18 a second run writes nothing (.git included) and grants nothing again" "$s18_bad"

# ---- A real folder where a link would go, and a re-pointed mapping ------------------------------------
s18_readme "$s18_ws/projects/site-notes/README.md" "assets — design files"
mkdir -p "$s18_ws/projects/site-notes/.resources/assets" && printf 'mine\n' > "$s18_ws/projects/site-notes/.resources/assets/keep.txt"
printf 'site-notes/assets  %s\nfield-study/media  %s\n' "$s18_ext/contracts" "$s18_ext/other-media" >> "$s18_ws/.claude/resources.local.md"
s18_run "$s18_ws"
s18_bad=""
[[ -d "$s18_ws/projects/site-notes/.resources/assets" && ! -L "$s18_ws/projects/site-notes/.resources/assets" \
    && "$(cat "$s18_ws/projects/site-notes/.resources/assets/keep.txt")" == mine ]] || s18_bad+="the real folder was changed"$'\n'
s18_has "kept     site-notes/assets (projects/site-notes/.resources/assets is a real file or folder, left as it is)" \
    "linked   field-study/media -> $s18_ext/other-media" "granted  $s18_ext/other-media"
[[ "$(s18_target "$s18_ws/projects/field-study/.resources/media")" == "$s18_ext/other-media" ]] \
    || s18_bad+="field-study/media not re-pointed: $(s18_target "$s18_ws/projects/field-study/.resources/media")"$'\n'
[[ "$(jq -r '.permissions.additionalDirectories[-1]' "$s18_sl")" == "$s18_ext/other-media" \
    && "$(jq -c '.permissions.allow' "$s18_sl")" == "$(printf '%s' "$s18_settings_before" | jq -c '.permissions.allow')" ]] \
    || s18_bad+="settings after the re-point: $(jq -c '.permissions' "$s18_sl")"$'\n'
empty "18 a real folder at .resources/<name> is left alone and reported; a changed mapping re-points the link and is granted" "$s18_bad"

# ---- --dry-run writes nothing, and says what the real run then does -----------------------------------
s18_wd="$SCRATCH/s18-dry"
if s18_fixture "$s18_wd"; then
    s18_t0="$(st_tree "$s18_wd")"
    s18_run "$s18_wd" --dry-run; s18_dry="$s18_out"; s18_drc=$s18_rc
    s18_t1="$(st_tree "$s18_wd")"
    s18_bad=""
    [[ $s18_drc -eq 0 ]] || s18_bad+="rc $s18_drc"$'\n'
    [[ "$s18_t0" == "$s18_t1" ]] || s18_bad+="$(diff <(printf '%s\n' "$s18_t0") <(printf '%s\n' "$s18_t1") | head -n 10)"$'\n'
    [[ "$(printf '%s\n' "$s18_dry" | head -n 1)" == "Dry run — nothing written." ]] || s18_bad+="no dry-run heading"$'\n'
    empty "18 --dry-run writes nothing (.git included)" "$s18_bad"
    s18_run "$s18_wd"
    [[ "$(printf '%s\n' "$s18_dry" | sed '1d')" == "$(printf '%s\n' "$s18_out" | sed 's/^/would /')" ]] \
        && ok "18 the dry run's lines are the real run's, with would in front" \
        || ko "18 the dry run's lines are the real run's, with would in front" "$(diff <(printf '%s\n' "$s18_dry" | sed '1d') <(printf '%s\n' "$s18_out" | sed 's/^/would /'))"
else
    ko "18 dry-run fixture builds"
fi

# ---- One project by name, and the exit codes --------------------------------------------------------
s18_wo="$SCRATCH/s18-one"
if s18_fixture "$s18_wo"; then
    s18_run "$s18_wo" vendor-review
    s18_bad=""
    [[ $s18_rc -eq 0 ]] || s18_bad+="rc $s18_rc"$'\n'
    [[ "$(s18_target "$s18_wo/projects/vendor-review/.resources/contracts")" == "$s18_ext/contracts" ]] || s18_bad+="vendor-review not linked"$'\n'
    [[ ! -e "$s18_wo/projects/field-study/.resources" ]] || s18_bad+="field-study touched"$'\n'
    printf '%s\n' "$s18_out" | grep -q 'field-study\|old-study' && s18_bad+="other projects reported: $s18_out"$'\n'
    empty "18 link SLUG maps that project only" "$s18_bad"

    s18_bad=""
    s18_run "$s18_wo" no-such-project; [[ $s18_rc -eq 2 ]] || s18_bad+="unknown project: rc $s18_rc"$'\n'
    s18_run "$s18_wo" --bogus; [[ $s18_rc -eq 2 ]] || s18_bad+="unknown option: rc $s18_rc"$'\n'
    s18_out="$(AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s18_wo/kit/lib/setup/link.sh" </dev/null 2>&1)"; s18_rc=$?
    [[ $s18_rc -eq 2 ]] || s18_bad+="no --target: rc $s18_rc"$'\n'
    mkdir -p "$SCRATCH/s18-not-a-workspace"
    s18_out="$(AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$s18_wo/kit/lib/setup/link.sh" --target "$SCRATCH/s18-not-a-workspace" </dev/null 2>&1)"; s18_rc=$?
    [[ $s18_rc -eq 1 ]] || s18_bad+="not a workspace: rc $s18_rc"$'\n'
    empty "18 exit codes: 2 for usage (an unknown project or option, no --target), 1 for a folder that is not a workspace" "$s18_bad"

    printf '{ "permissions": { "allow": [ "Bash(ls:*)" ' > "$s18_wo/.claude/settings.local.json"
    s18_broken="$(cat "$s18_wo/.claude/settings.local.json")"
    s18_run "$s18_wo" field-study
    [[ $s18_rc -eq 1 && "$(cat "$s18_wo/.claude/settings.local.json")" == "$s18_broken" ]] \
        && printf '%s\n' "$s18_out" | grep -q 'by hand' \
        && ok "18 a settings.local.json that is not valid JSON is left as it is; link says so and exits 1" \
        || ko "18 a settings.local.json that is not valid JSON is left as it is; link says so and exits 1" "rc $s18_rc"$'\n'"$s18_out"
else
    ko "18 single-project fixture builds"
fi

# ---- No mappings at all: unattended writes no file; attended asks, records and links ---------------
s18_wn="$SCRATCH/s18-nomap"
if s18_fixture "$s18_wn" nomap; then
    s18_run "$s18_wn"
    s18_bad=""
    [[ ! -e "$s18_wn/.claude/resources.local.md" ]] || s18_bad+="resources.local.md was created"$'\n'
    [[ ! -e "$s18_wn/.claude/settings.local.json" ]] || s18_bad+="settings.local.json was created with nothing to grant"$'\n'
    s18_has "unmapped field-study/media" "unmapped field-study/notes" "unmapped vendor-review/contracts" \
        "inside   field-study/exports (generated; kept out of git)"
    empty "18 unattended, with no mappings, link never writes resources.local.md and names each unmapped resource" "$s18_bad"

    # A pseudo-terminal makes the run attended. The answer goes to the notes question only; the
    # others take Enter and stay unmapped.
    s18_pty="$(cd "$s18_wn" && env -u AW_WIZARD_NONINTERACTIVE HOME="$s18_home" S18_ANSWER="$s18_ext/notes-dir" \
        python3 - "$st_bash" "$s18_wn/kit/lib/setup/link.sh" --target "$s18_wn" 2>&1 <<'S18PY'
import os, pty, select, sys, time
answer = os.environ["S18_ANSWER"]
try:
    pid, fd = pty.fork()
except OSError as e:
    print("S18-NO-PTY", e)
    sys.exit(0)
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
out = b""
seen = 0
deadline = time.time() + 60
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 1)
    if fd not in r:
        continue
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
    while out.count(b"Enter to leave it unmapped") > seen:
        q = out.split(b"Enter to leave it unmapped")[seen]
        seen += 1
        os.write(fd, ((answer if b"field-study/notes" in q.splitlines()[-1] else "") + "\n").encode())
_, st = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
print("S18-RC", os.WEXITSTATUS(st) if os.WIFEXITED(st) else 128)
S18PY
)"
    if printf '%s\n' "$s18_pty" | grep -q '^S18-NO-PTY'; then
        skp "18 attended: an answer is recorded in resources.local.md, with its header, and linked — no pseudo-terminal here ($(printf '%s\n' "$s18_pty" | sed -n 's/^S18-NO-PTY //p' | head -n 1))"
    else
        s18_bad=""
        printf '%s\n' "$s18_pty" | grep -q '^S18-RC 0$' || s18_bad+="exit: $(printf '%s\n' "$s18_pty" | grep '^S18-RC')"$'\n'
        [[ "$(head -n 1 "$s18_wn/.claude/resources.local.md" 2>/dev/null)" == "# Resources on this machine" ]] || s18_bad+="no header"$'\n'
        grep -qxF "field-study/notes  $s18_ext/notes-dir" "$s18_wn/.claude/resources.local.md" 2>/dev/null || s18_bad+="no mapping line"$'\n'
        [[ "$(grep -c '/' "$s18_wn/.claude/resources.local.md" 2>/dev/null)" -eq 2 ]] || s18_bad+="lines other than the header and the answer: $(cat "$s18_wn/.claude/resources.local.md")"$'\n'
        [[ "$(s18_target "$s18_wn/projects/field-study/.resources/notes")" == "$s18_ext/notes-dir" ]] || s18_bad+="not linked"$'\n'
        printf '%s\n' "$s18_pty" | grep -qx "linked   field-study/notes -> $s18_ext/notes-dir" || s18_bad+="no linked line"$'\n'
        printf '%s\n' "$s18_pty" | grep -qx "unmapped field-study/media" || s18_bad+="Enter did not leave media unmapped"$'\n'
        [[ -z "$s18_bad" ]] || s18_bad+="transcript:"$'\n'"$s18_pty"
        empty "18 attended: an answer is recorded in resources.local.md, with its header, and linked; Enter leaves a name unmapped" "$s18_bad"
    fi
else
    ko "18 no-mapping fixture builds"
fi

# ---- setup.sh link: the dispatcher (C3) --------------------------------------------------------------
if grep -q 'lib/setup/' "$KIT/setup.sh" 2>/dev/null && grep -qw 'link' "$KIT/setup.sh"; then
    s18_ws2="$SCRATCH/s18-setup"
    if s18_fixture "$s18_ws2"; then
        s18_out="$(AW_WIZARD_NONINTERACTIVE=1 HOME="$s18_home" "$st_bash" "$s18_ws2/kit/setup.sh" link vendor-review --target "$s18_ws2" </dev/null 2>&1)"; s18_rc=$?
        [[ $s18_rc -eq 0 && "$(s18_target "$s18_ws2/projects/vendor-review/.resources/contracts")" == "$s18_ext/contracts" ]] \
            && ok "18 kit/setup.sh link SLUG runs link.sh" || ko "18 kit/setup.sh link SLUG runs link.sh" "rc $s18_rc"$'\n'"$s18_out"
    else
        ko "18 setup-dispatch fixture builds"
    fi
else
    skp "18 kit/setup.sh link SLUG runs link.sh — setup.sh does not dispatch link yet (C3)"
fi

# ---- state.sh: resource.* full and quick (C4) -------------------------------------------------------
s18_sv="$(HOME="$s18_home" "$st_bash" "$STATE" "$s18_ws" 2>/dev/null | awk -F= '$1 == "state_version" { print $2; exit }')"
if [[ "$s18_sv" != 2 ]]; then
    skp "18 state.sh resource.* states, full and quick — state.sh reports state_version=${s18_sv:-none}, not 2 (C4)"
else
    # The fixture as the re-point left it: media (other-media), contracts and archive linked and
    # granted; exports inside with no folder yet; survey-data absent; locked and deep unreadable; notes
    # unmapped; site-notes/assets readable but not granted by a link (its folder was kept).
    s18_full="$(HOME="$s18_home" "$st_bash" "$STATE" "$s18_ws" 2>/dev/null)"
    st_expect "18 state.sh resource.* states, full check" "$s18_full" \
        "resource.field-study/media=resolves granted" \
        "resource.vendor-review/contracts=resolves granted" \
        "resource.old-study/archive=resolves granted" \
        "resource.field-study/survey-data=missing absent" \
        "resource.field-study/locked=no-permission unreadable" \
        "resource.field-study/deep=no-permission unreadable" \
        "resource.field-study/notes=missing unmapped" \
        "resource.field-study/exports=missing absent" \
        "resources_file=present"
    s18_bad=""
    case ",$(st_key "$s18_full" external_paths_missing)," in
        *,field-study/survey-data,*) ;; *) s18_bad+="survey-data not in external_paths_missing"$'\n' ;; esac
    case ",$(st_key "$s18_full" external_paths_missing)," in
        *,field-study/locked,*) ;; *) s18_bad+="locked not in external_paths_missing"$'\n' ;; esac
    case ",$(st_key "$s18_full" external_paths_missing)," in
        *,field-study/notes,*|*,field-study/media,*) s18_bad+="an unmapped or resolving name in external_paths_missing"$'\n' ;; esac
    empty "18 state.sh external_paths_missing holds absent and no-permission resources only" "$s18_bad"
    mkdir -p "$s18_ws/projects/field-study/exports"
    s18_quick="$(HOME="$s18_home" "$st_bash" "$STATE" --quick "$s18_ws" 2>/dev/null)"
    s18_bad=""
    [[ "$(st_key "$s18_quick" resource.field-study/exports)" == "resolves inside" ]] || s18_bad+="exports: $(st_key "$s18_quick" resource.field-study/exports)"$'\n'
    [[ "$(st_key "$s18_quick" resource.field-study/media)" == "resolves granted" ]] || s18_bad+="media: $(st_key "$s18_quick" resource.field-study/media)"$'\n'
    [[ "$(st_key "$s18_quick" resource.field-study/survey-data)" == "missing absent" ]] || s18_bad+="survey-data: $(st_key "$s18_quick" resource.field-study/survey-data)"$'\n'
    [[ "$(st_key "$s18_quick" resource.field-study/notes)" == "missing unmapped" ]] || s18_bad+="notes: $(st_key "$s18_quick" resource.field-study/notes)"$'\n'
    [[ "$(st_key "$s18_quick" resource.field-study/deep)" == "missing absent" ]] || s18_bad+="deep (-e only): $(st_key "$s18_quick" resource.field-study/deep)"$'\n'
    case "$(st_key "$s18_quick" resource.field-study/locked)" in resolves*) ;; *) s18_bad+="locked (-e and -d only): $(st_key "$s18_quick" resource.field-study/locked)"$'\n' ;; esac
    [[ "$(st_key "$s18_quick" quick)" == 1 ]] || s18_bad+="no quick=1"$'\n'
    empty "18 state.sh --quick resource.* states, from -e and -d alone" "$s18_bad"
fi

fi
chmod 755 "$s18_ext/locked" "$s18_ext/shut" 2>/dev/null
fi
