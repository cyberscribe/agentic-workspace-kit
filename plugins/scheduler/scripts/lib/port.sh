# shellcheck shell=bash
# Task fields are t_<field> and their defaults D_<field>, shared with schedule.sh (SC2034, SC2154); jq
# filters are single-quoted on purpose (SC2016); "a && b || c" lines are meant as written (SC2015).
# shellcheck disable=SC2034,SC2154,SC2016,SC2015
# schedule.sh port: moving tasks from a cloud scheduler to this machine, one deterministic step at a time.
# Sourced by schedule.sh for the port command only, so the runner's copy stays one file.
#
#   start <export.json> [--path-map FROM=TO]... [--cwd DIR]   import every task, paused, then check them
#   check [<name>]                      the audit: schedule, zone, folders, connectors, the prompt lint
#   ack <name> <finding> [--note TEXT]  record that a person read a warn finding
#   trial <name> --yes | --plan         one run now with the task's own settings; --plan only looks
#   activate <name>                     resume it here; the cloud twin still runs, so it is double-run
#   cloud-paused <name> --confirmed     the cloud task is paused (never deleted): this one runs alone
#   rollback <name>                     back to the cloud: pause this one, and re-enable the cloud twin
#   skip <name> --reason TEXT           leave a task out of the move
#   status [--json]                     one row a task: its stage and what comes next
#   done                                close the ledger once every task is cloud-paused or skipped
#
# The ledger, $SCHEDULER_DATA/port/current.json, holds each task's stage, findings, acknowledgements,
# path substitutions and trial, so a person can stop anywhere and pick up later. Each stage refuses to
# run before the one it follows, and running one again is safe. The judgement steps (rewording a prompt)
# happen in the task file, between stages; the stages themselves decide by code alone.
#
# The prompt lint reads plugins/scheduler/port-rules.tsv (SCHEDULER_PORT_RULES to point elsewhere).
# port needs jq, since the export and the ledger are JSON; scheduled runs do not.

PORT_RULES="${SCHEDULER_PORT_RULES:-$(cd "$SELF_DIR/.." && pwd)/port-rules.tsv}"
PORT_DIR="$S_DATA/port"
# Connectors a cloud scheduler attaches for its own use, compared lowercased with spaces, hyphens and
# underscores taken out.
CLOUD_OWN_CONNECTORS="claudecoderemote"
LEDGER="$PORT_DIR/current.json"

port_now() { date '+%Y-%m-%d %H:%M'; }
lj() { jq "$@" "$LEDGER"; }
lw() {   # jq args... : rewrite the ledger through a jq filter
    local tmp="$LEDGER.tmp.$$"
    jq "$@" "$LEDGER" >"$tmp" && mv "$tmp" "$LEDGER" || { rm -f "$tmp"; die "could not write the ledger"; }
}
need_ledger() { [[ -f "$LEDGER" ]] || die "no port in progress; 'schedule.sh port start <export.json>' begins one"; }
stage_of() { lj -r --arg n "$1" '.tasks[$n].stage // empty'; }
stage_rank() {
    case "$1" in imported) echo 1 ;; checked) echo 2 ;; trialled) echo 3 ;; double-run) echo 4 ;; cloud-paused) echo 5 ;; skipped) echo 9 ;; *) echo 0 ;; esac
}
set_stage() { lw --arg n "$1" --arg s "$2" --arg t "$(port_now)" '.tasks[$n].stage = $s | .tasks[$n].updated = $t'; }
in_ledger() {
    [[ -n "$(stage_of "$1")" ]] || die "$1 is not in this port; 'schedule.sh port status' lists what is"
}
slug() {
    local s; s="$(lower "$1" | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
    printf '%s' "${s:0:63}" | sed 's/-$//'
}

# --- start -----------------------------------------------------------------------------------------------
# A task in the export is read in either shape: plain (name, schedule, prompt, model, cwd, add_dirs,
# permission_mode, enabled) or a cloud scheduler's listing (cron_expression, derived_state.prompt,
# derived_state.folders, derived_state.permission_mode, model, enabled, mcp_connections[].name).
port_start() {
    local export="" cwd_default="" maps=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path-map) [[ "${2:-}" == *=* ]] || usage_die "--path-map takes FROM=TO"; maps+=("$2"); shift 2 ;;
            --cwd) cwd_default="${2:-}"; shift 2 ;;
            --*) usage_die "unknown option $1" ;;
            *) export="$1"; shift ;;
        esac
    done
    [[ -n "$export" && -f "$export" ]] || usage_die "port start needs the export file"
    export="$(cd "$(dirname "$export")" && pwd)/$(basename "$export")"
    local arr; arr="$(jq -c 'if type == "array" then . elif type == "object" then (.tasks // .scheduled_tasks // .items // [.]) else error("not an array") end' "$export" 2>/dev/null)" \
        || die "$export is not a JSON array of tasks, or an object holding one"
    [[ -n "$cwd_default" ]] || cwd_default="$(dirname "$export")"
    [[ -d "$cwd_default" ]] && cwd_default="$(cd "$cwd_default" && pwd)"
    mkdir -p "$PORT_DIR" "$S_TASKS"
    local mapjson; mapjson="$(for m in ${maps[@]+"${maps[@]}"}; do jq -nc --arg f "${m%%=*}" --arg t "${m#*=}" '{from: $f, to: $t}'; done | jq -sc .)"
    if [[ ! -f "$LEDGER" ]]; then
        jq -n --arg s "$export" --arg t "$(port_now)" --argjson m "$mapjson" '{source: $s, started: $t, path_map: $m, tasks: {}}' >"$LEDGER"
    else
        lw --arg s "$export" --argjson m "$mapjson" '.source = $s | .path_map = ((.path_map + $m) | unique_by(.from))'
    fi
    mapjson="$(lj -c '.path_map')"
    local n i; n="$(jq 'length' <<<"$arr")"
    echo "Importing $n task(s) from $export, each paused:"
    local names=()
    for ((i = 0; i < n; i++)); do
        local t; t="$(jq -c --argjson i "$i" '.[$i]' <<<"$arr")"
        local sid sname nm
        sid="$(jq -r '.id // empty | tostring' <<<"$t")"
        sname="$(jq -r '.name // .title // .description // empty' <<<"$t")"
        local have; have="$(lj -r --arg id "$sid" --arg sn "$sname" '.tasks | to_entries[] | select((($id != "") and (.value.source_id == $id)) or (($id == "") and (.value.source_name == $sn))) | .key' | head -n 1)"
        if [[ -n "$have" ]]; then
            echo "  $have: already in this port, at $(stage_of "$have"); left as it is"
            names+=("$have"); continue
        fi
        nm="$(slug "${sname:-task-$((i + 1))}")"; [[ -n "$nm" ]] || nm="task-$((i + 1))"
        local base="$nm" k=2
        while [[ -e "$(task_file "$nm")" ]]; do nm="${base:0:60}-$k"; k=$((k + 1)); done
        task_clear
        t_name="$nm"
        t_schedule="$(jq -r '.schedule // .cron_expression // empty' <<<"$t")"
        T_BODY="$(jq -r '.prompt // .derived_state.prompt // empty' <<<"$t")"
        t_model="$(jq -r '.model // empty' <<<"$t")"
        t_description="$(jq -r '.description // empty' <<<"$t" | tr '\n' ' ')"
        [[ "$t_description" == "$sname" || -z "$t_description" ]] && t_description="Moved from ${export##*/}: $sname"
        # A cloud listing attaches every connector the account has to every task, used or not. Only those
        # the prompt names (as written, with spaces or hyphens for underscores, or inside an mcp__ tool
        # name) go into requires; the rest are reported and left out, and the cloud scheduler's own
        # connector is never carried over, since a local run has no use for it.
        local conn cvar named=0 leftout="" ownout="" c2
        t_requires=""
        while IFS= read -r conn; do
            [[ -n "$conn" ]] || continue
            c2="$(lower "$conn" | tr -d ' _-')"
            if in_list "$c2" "$CLOUD_OWN_CONNECTORS"; then ownout+="${ownout:+, }$conn"; continue; fi
            named=0
            for cvar in "$conn" "${conn//_/ }" "${conn//_/-}"; do
                grep -qiF -- "$cvar" <<<"$T_BODY" && { named=1; break; }
            done
            if (( named )); then t_requires+="${t_requires:+, }$conn"; else leftout+="${leftout:+, }$conn"; fi
        done < <(jq -r '.mcp_connections[]? | (.name // .) | tostring' <<<"$t")
        local pm; pm="$(jq -r '.permission_mode // .derived_state.permission_mode // empty' <<<"$t")"
        local folders=() f
        while IFS= read -r f; do [[ -n "$f" ]] && folders+=("$f"); done < <(jq -r '(.derived_state.folders // ([.cwd // empty] + (.add_dirs // []))) | .[] | (.path? // .) | tostring' <<<"$t")
        # The path map: literal substitutions in the folders and the prompt, each counted and recorded.
        local subs="[]" j from to cnt
        for ((j = 0; j < $(jq 'length' <<<"$mapjson"); j++)); do
            from="$(jq -r --argjson j "$j" '.[$j].from' <<<"$mapjson")"; to="$(jq -r --argjson j "$j" '.[$j].to' <<<"$mapjson")"
            cnt="$(printf '%s' "$T_BODY" | grep -oF -- "$from" | wc -l | tr -d ' ')"
            if (( cnt > 0 )); then
                T_BODY="${T_BODY//"$from"/$to}"
                subs="$(jq -c --arg f "$from" --arg t "$to" --argjson c "$cnt" '. + [{from: $f, to: $t, count: $c, where: "prompt"}]' <<<"$subs")"
            fi
            local idx
            for idx in "${!folders[@]}"; do
                if [[ "${folders[idx]}" == *"$from"* ]]; then
                    folders[idx]="${folders[idx]//"$from"/$to}"
                    subs="$(jq -c --arg f "$from" --arg t "$to" '. + [{from: $f, to: $t, count: 1, where: "folder"}]' <<<"$subs")"
                fi
            done
        done
        for idx in "${!folders[@]}"; do [[ "${folders[idx]}" == \~/* ]] && folders[idx]="$HOME/${folders[idx]#\~/}"; done
        if [[ ${#folders[@]} -gt 0 ]]; then
            t_cwd="${folders[0]}"
            local rest=""; for f in "${folders[@]:1}"; do rest+="${rest:+, }$f"; done
            t_add_dirs="$rest"
        else
            t_cwd="$cwd_default"
        fi
        local notmapped=""
        if [[ -n "$pm" ]]; then
            if in_list "$pm" "default acceptEdits auto bypassPermissions manual dontAsk plan"; then t_permission_mode="$pm"
            else notmapped+="permission_mode $pm, "; fi
        fi
        [[ -n "$t_permission_mode" ]] || t_permission_mode=$D_permission_mode
        local unk; unk="$(jq -r '[keys[] | select(IN("id","name","title","description","schedule","cron_expression","prompt","model","cwd","add_dirs","permission_mode","enabled","mcp_connections","derived_state","created_at","updated_at","created","updated") | not)]
                                 + [(.derived_state // {}) | keys[] | select(IN("prompt","folders","permission_mode") | not) | "derived_state." + .] | join(", ")' <<<"$t")"
        [[ -n "$unk" ]] && notmapped+="$unk, "
        local enabled; enabled="$(jq -r 'if has("enabled") then (.enabled | tostring) else "" end' <<<"$t")"
        t_status=paused t_paused_reason="imported; review before resuming"
        t_timeout=$D_timeout t_retries=$D_retries t_retry_delay=$D_retry_delay t_pause_after_failures=$D_pause_after_failures
        t_notify_on=$D_notify_on t_keep_runs=$D_keep_runs t_created="$(port_now)"
        task_save "$(task_file "$nm")"
        jq -n --arg id "$sid" --arg sn "$sname" --arg t "$(port_now)" --arg en "$enabled" --argjson s "$subs" --arg lo "$leftout" --arg oo "$ownout" \
            '{source_id: $id, source_name: $sn, stage: "imported", imported: $t, updated: $t, enabled_in_source: $en, substitutions: $s, findings: [], acks: {}, set: [],
              connectors_left_out: ($lo | split(", ") | map(select(. != ""))), cloud_own_left_out: ($oo | split(", ") | map(select(. != "")))}' \
            >"$PORT_DIR/entry.$$"
        lw --arg n "$nm" --slurpfile e "$PORT_DIR/entry.$$" '.tasks[$n] = $e[0]'
        rm -f "$PORT_DIR/entry.$$"
        local lines; lines="$(printf '%s\n' "$T_BODY" | wc -l | tr -d ' ')"
        printf '  %s: schedule %s; prompt %s line(s); cwd %s; model %s%s%s%s%s\n' "$nm" "${t_schedule:-(none)}" "$lines" "$t_cwd" \
            "${t_model:-default}" "${t_requires:+; requires $t_requires}" \
            "$( [[ "$(jq 'length' <<<"$subs")" -gt 0 ]] && printf '; %s path substitution(s)' "$(jq '[.[].count] | add' <<<"$subs")")" \
            "$( [[ "$enabled" == false ]] && printf '; disabled in the source')" \
            "${notmapped:+; not mapped: ${notmapped%, }}"
        [[ -n "$leftout" ]] && printf '    attached in the cloud, not named in the prompt; left out: %s\n' "$leftout"
        [[ -n "$ownout" ]] && printf "    the cloud scheduler's own connector, left out: %s\n" "$ownout"
        names+=("$nm")
    done
    echo
    port_check
}

# --- check -----------------------------------------------------------------------------------------------
# findings_for <name>: the loaded task's findings as JSON lines, into FJ; set-rule fields are written.
findings_for() {
    local name="$1" file; file="$(task_file "$name")"
    FJ=""
    add() { FJ+="$(jq -nc --arg id "$1" --arg r "$2" --arg s "$3" --arg l "$4" --arg tx "$5" --arg m "$6" --arg f "$7" \
        '{id: $id, rule: $r, severity: $s, line: (if $l == "" then null else ($l | tonumber) end), text: $tx, message: $m, fix: $f}')"$'\n'; }
    if [[ -z "$t_schedule" ]]; then add schedule schedule block "" "" "The task has no schedule." "Set one with schedule.sh edit $name --schedule '<when>'."
    elif ! parse_schedule "$t_schedule"; then add schedule schedule block "" "$t_schedule" "$SERR" "Write it as cron, @daily, every <n>m or once YYYY-MM-DD HH:MM."
    elif [[ -n "$SZ" ]]; then
        need_backend
        if [[ "$BACKEND" == systemd ]]; then add zone zone warn "" "$SZ" "The schedule is in $SZ, and this machine in $(local_zone); systemd follows the zone." "Acknowledge it, or write the schedule in local time."
        else add zone zone block "" "$SZ" "The schedule is in $SZ, and this machine in $(local_zone); $BACKEND has no time zones." "Write the schedule in local time (next shows both)."; fi
    fi
    [[ -n "$T_BODY" ]] || add prompt prompt block "" "" "The prompt is empty." "Write the prompt in the task file's body."
    # Nobody watches a scheduled run, so it cannot be asked anything: bypassPermissions turns every check
    # off for it, and any mode but dontAsk or plan leans on approvals nobody gives.
    case "$(tv permission_mode)" in
        dontAsk|plan) ;;
        bypassPermissions) add permission-mode permission block "" "bypassPermissions" "The task would run unattended with every permission check off." "edit $name --permission-mode dontAsk, and name the tools it needs in allowed_tools." ;;
        *) add permission-mode permission warn "" "$(tv permission_mode)" "An unattended run cannot answer a permission prompt; a tool it would ask about is refused." "edit $name --permission-mode dontAsk, and name the tools in allowed_tools." ;;
    esac
    [[ -n "$t_allowed_tools" ]] || add allowed-tools permission warn "" "" "No tools are allowed, so under dontAsk the run can only read and answer." "edit $name --allowed-tools '<tools>': the trial shows which it reaches for."
    [[ -d "$t_cwd" ]] || add folder folder block "" "$t_cwd" "The folder the run starts in does not exist on this machine." "edit $name --cwd <folder>, or a --path-map at port start."
    if [[ -n "$t_add_dirs" ]]; then
        local ad ads=(); IFS=, read -r -a ads <<<"$t_add_dirs"
        for ad in "${ads[@]}"; do ad="$(trim "$ad")"; [[ -z "$ad" || -d "$ad" ]] || add "folder:$ad" folder block "" "$ad" "A folder in add_dirs does not exist on this machine." "edit $name --add-dirs '<folders>'."; done
    fi
    if [[ -n "$t_requires" ]]; then
        connector_states
        local r srv state
        while IFS='|' read -r r srv state; do
            [[ -n "$r" ]] || continue
            case "$state" in
                connected) ;;
                unchecked) add "connector:$r" connector warn "" "$r" "The connector could not be checked: no claude, or no folder to run it in." "Check it with schedule.sh doctor $name once the folder exists." ;;
                missing) add "connector:$r" connector block "" "$r" "$r is not in claude mcp list on this machine." "Connect it in Claude Code (claude.ai connectors, or claude mcp add), or take it out of the prompt and requires." ;;
                *) add "connector:$r" connector block "" "$r" "$r is listed as $srv, but $state." "Authenticate it with /mcp in Claude Code, then check again." ;;
            esac
        done <<<"$CS"
    fi
    # The prompt lint. A set rule writes its field (once) and is recorded; the others are findings.
    local id sev pat msg fix hit ln tx changed=0
    while IFS='	' read -r id sev pat msg fix; do
        [[ -z "$id" || "$id" == \#* || "$id" == id || "$sev" == trial || "$sev" == refusal ]] && continue
        while IFS= read -r hit; do
            [[ -n "$hit" ]] || continue
            ln="${hit%%:*}"; tx="$(trim "${hit#*:}")"; tx="${tx:0:120}"
            local hsev="$sev"
            if [[ "$sev" == block-path ]]; then
                # The words on the line that match the rule are paths; when each one exists here, the
                # line names a real folder on this machine, not a sandbox's mount, and is not a finding.
                local w wp matched=0 missing=0 words=()
                read -r -a words <<<"${hit#*:}"
                for w in ${words[@]+"${words[@]}"}; do
                    w="${w%[.,;:)\'\"\`]}"; w="${w#[(\'\"\`]}"
                    printf '%s\n' "$w" | grep -qiE -- "$pat" || continue
                    matched=1; wp="$w"
                    [[ "$wp" == \~/* ]] && wp="$HOME/${wp#\~/}"
                    [[ "$wp" == \$HOME/* ]] && wp="$HOME/${wp#\$HOME/}"
                    [[ -e "$wp" ]] || missing=1
                done
                (( matched && ! missing )) && continue
                hsev=block
            fi
            if [[ "$hsev" == set ]]; then
                # A set rule reports only when it changes the field: a task that already has the
                # value (from an earlier check, or set by the person) has nothing to fix.
                local key="${fix%%:*}" val; val="$(trim "${fix#*:}")"
                local cur="t_$key"
                [[ "${!cur}" == "$val" ]] && continue
                printf -v "t_$key" '%s' "$val"; changed=1
                lw --arg n "$name" --arg k "$key" --arg v "$val" --arg r "$id" --argjson l "$ln" \
                    '.tasks[$n].set = ((.tasks[$n].set // []) + [{field: $k, value: $v, rule: $r, line: $l}])'
                add "$id:$ln" "$id" set "$ln" "$tx" "$msg" "set $key: $val"
            else
                add "$id:$ln" "$id" "$hsev" "$ln" "$tx" "$msg" "$fix"
            fi
        done < <(printf '%s\n' "$T_BODY" | grep -n -i -E -- "$pat" 2>/dev/null)
    done <"$PORT_RULES"
    # A sandboxed folder: network calls go only to the allowed domains, and a refused one fails the
    # call without asking anyone.
    sandbox_state
    if [[ "$SB_ON" == yes ]]; then
        add sandbox sandbox warn "" "${SB_DOMAINS:-no domains}" "The run is sandboxed ($SB_FROM): network calls go only to the allowed domains; a refused one fails without asking." \
            "Check that every domain the task reaches is in sandbox.network.allowedDomains, or run it from a folder without the sandbox."
    fi
    # The credential rule reads the front matter as well (a notify command with a token in it, say).
    local cpat fmline fmn=0
    cpat="$(awk -F'\t' '$1 == "credential" { print $3 }' "$PORT_RULES")"
    if [[ -n "$cpat" ]]; then
        while IFS= read -r fmline; do
            fmn=$((fmn + 1))
            (( fmn == 1 )) && continue
            [[ "$fmline" == "---" ]] && break
            printf '%s\n' "$fmline" | grep -qiE -- "$cpat" && add "credential:front-matter-$fmn" credential warn "" "${fmline%%:*}: (value not shown)" \
                "Something shaped like a credential is written into the task file's settings." "Keep the credential in a file, and point to it."
        done <"$file"
    fi
    (( changed )) && task_save "$file"
    return 0
}

port_check() {
    need_ledger
    local names=() n
    if [[ $# -ge 1 ]]; then in_ledger "$1"; names=("$1")
    else while IFS= read -r n; do [[ -n "$n" ]] && names+=("$n"); done < <(lj -r '.tasks | keys[]'); fi
    for n in "${names[@]}"; do
        local st; st="$(stage_of "$n")"
        [[ "$st" == cloud-paused || "$st" == skipped ]] && { echo "$n: $st; not checked again"; continue; }
        if ! task_load "$(task_file "$n")"; then
            echo "$n: $TERR"; continue
        fi
        findings_for "$n"
        local fj; fj="$(printf '%s' "$FJ" | jq -sc .)"
        lw --arg n "$n" --argjson f "$fj" --arg t "$(port_now)" '.tasks[$n].findings = $f | .tasks[$n].checked = $t'
        local blocks warns acked
        blocks="$(jq '[.[] | select(.severity == "block")] | length' <<<"$fj")"
        warns="$(lj --arg n "$n" '[.tasks[$n] as $t | $t.findings[] | select(.severity == "warn") | select(($t.acks[.id] // null) == null)] | length')"
        acked="$(lj --arg n "$n" '[.tasks[$n] as $t | $t.findings[] | select(.severity == "warn") | select(($t.acks[.id] // null) != null)] | length')"
        # A block sends a task back to imported, unless it already runs here; none moves imported on.
        if (( blocks > 0 )); then
            case "$st" in checked|trialled) set_stage "$n" imported; st=imported ;; esac
        elif [[ "$st" == imported ]]; then
            set_stage "$n" checked; st=checked
        fi
        printf '%s: %s — %s block, %s warn to read%s\n' "$n" "$st" "$blocks" "$warns" "$( (( acked )) && printf ', %s acknowledged' "$acked")"
        jq -r '.[] | "  [\(.severity)] \(.id)\(if .line then " (prompt line \(.line))" else "" end): \(.message)\(if .text != "" then "\n      " + .text else "" end)\n      fix: \(.fix)"' <<<"$fj"
    done
}

port_ack() {
    need_ledger
    [[ $# -ge 2 ]] || usage_die "port ack needs a task and a finding id"
    local n="$1" id="$2" note=""; shift 2
    [[ "${1:-}" == --note ]] && note="${2:-}"
    in_ledger "$n"
    local sev; sev="$(lj -r --arg n "$n" --arg id "$id" '.tasks[$n].findings[] | select(.id == $id) | .severity' | head -n 1)"
    [[ -n "$sev" ]] || die "$n has no finding $id; 'schedule.sh port check $n' lists them"
    [[ "$sev" == warn ]] || die "$id is a $sev finding; a block is fixed in the task file, then checked again"
    lw --arg n "$n" --arg id "$id" --arg note "$note" --arg t "$(port_now)" '.tasks[$n].acks[$id] = {note: $note, at: $t}'
    echo "Acknowledged $id on $n${note:+: $note}."
}

# --- trial -----------------------------------------------------------------------------------------------
# One run now, with the task's own settings: its permission mode (dontAsk), its allowed tools, its
# folders. That is the test of whether its tool list is enough, so it acts as the task would, and asks
# for a yes first. result_to and the notify command are held back. It passes on a clean exit, no error in
# the result, no refusal the run stopped at, and no line in the result or stderr matching a trial rule
# (a tool that was not available). A refusal the run carried on from is a pass, and is named.
# --plan is a look instead: plan mode says what the model would do, ignores the task's allowed tools
# (and can still run read-only commands), so it tests nothing about permissions and never moves the
# task on.
port_trial() {
    need_ledger
    [[ $# -ge 1 ]] || usage_die "port trial needs a task"
    local n="$1" plan=0 yes=0; shift
    while [[ $# -gt 0 ]]; do
        case "$1" in --plan) plan=1 ;; --yes) yes=1 ;; --live) ;; *) usage_die "unknown option $1" ;; esac
        shift
    done
    in_ledger "$n"
    local st; st="$(stage_of "$n")"
    case "$st" in
        imported) die "port trial comes after port check: $n has block findings; fix them in its file, then 'schedule.sh port check $n'" ;;
        skipped|cloud-paused) die "$n is $st" ;;
    esac
    port_check "$n" >/dev/null
    [[ "$(stage_of "$n")" != imported ]] || die "port check now finds a block on $n; 'schedule.sh port check $n' shows it"
    if (( ! plan && ! yes )); then
        if [[ -t 0 && -t 1 ]]; then
            printf 'A trial is a real run with the task'"'"'s own tools: it can send mail, post or change files. Run it? (y/n) [n]: '
            local a; read -r a; [[ "$a" == y || "$a" == Y ]] || { echo "Not run."; return 1; }
        else
            die "a trial is a real run with the task's own tools and can send mail or post; give --yes once the person has said yes (or --plan for a look that changes nothing)"
        fi
    fi
    load_named "$n"
    refresh_runner
    local mode=live; (( plan )) && mode=plan
    env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-${USER:-}}" TMPDIR="${TMPDIR:-/tmp}" \
        SCHEDULER_HOME="$S_HOME" SCHEDULER_TASKS_DIR="$S_TASKS" SCHEDULER_DATA="$S_DATA" ${SCHEDULER_BACKEND:+SCHEDULER_BACKEND="$SCHEDULER_BACKEND"} \
        /bin/bash "$RUNNER" exec "$n" --trial "$mode"
    local d; d="$(last_run "$n")"
    [[ -n "$d" && "$(meta_get "$d" trigger)" == "trial-$mode" ]] || die "the trial left no run folder; 'schedule.sh doctor' says more"
    local rst bad="" id sev pat msg fix rf
    rst="$(meta_get "$d" status)"; rf="$(meta_get "$d" refusals)"
    [[ "$rst" == ok ]] || bad+="the run ended $rst (exit $(meta_get "$d" exit))$( r="$(meta_get "$d" reason)"; [[ -n "$r" ]] && printf ': %s' "$r")"$'\n'
    while IFS='	' read -r id sev pat msg fix; do
        [[ "$sev" == trial ]] || continue
        bad+="$(cat "$d/result.txt" "$d"/attempt-*.stderr 2>/dev/null | grep -i -E -- "$pat" | sed "s/^/$id: /")"
    done <"$PORT_RULES"
    bad="$(printf '%s' "$bad" | sed '/^$/d')"
    local passed=true; [[ -z "$bad" ]] || passed=false
    lw --arg n "$n" --arg r "$(basename "$d")" --arg m "$mode" --arg t "$(port_now)" --argjson p "$passed" --arg b "$bad" \
        '.tasks[$n].trial = {run: $r, mode: $m, at: $t, passed: $p, failed_lines: $b}'
    if (( plan )); then
        echo "Plan-mode look at $n: $( [[ "$passed" == true ]] && echo "it ran cleanly" || echo "it hit trouble")."
        echo "Plan mode does not use the task's allowed tools, so this tests nothing about them, and $n stays at $(stage_of "$n"). Run $(basename "$d"); 'schedule.sh log $n' shows what it said."
        [[ "$passed" == true ]] || printf '%s\n' "$bad" | sed 's/^/  /'
        return 0
    fi
    # A pass moves a checked task on; a failure undoes an earlier pass, so activate waits for a good one.
    if [[ "$passed" == true ]]; then
        [[ "$(stage_of "$n")" == checked ]] && set_stage "$n" trialled
    elif [[ "$(stage_of "$n")" == trialled ]]; then
        set_stage "$n" checked
    fi
    local how; how="with its own settings (permission_mode $(tv permission_mode), its allowed tools); result_to and notify held back"
    if [[ "$passed" == true ]]; then
        echo "Trial of $n $how: passed${rf:+, carrying on past $rf refused call(s): $(meta_get "$d" refused_calls)}."
        echo "Run $(basename "$d"); 'schedule.sh log $n' shows what it said. Next: schedule.sh port activate $n"
    else
        echo "Trial of $n $how: failed. Run $(basename "$d"):"
        printf '%s\n' "$bad" | sed 's/^/  /'
        echo "Fix the task file, then trial it again."
        return 1
    fi
}

# --- activate, cloud-paused, rollback, skip, status, done ----------------------------------------------------------------
port_activate() {
    need_ledger
    [[ $# -ge 1 ]] || usage_die "port activate needs a task"
    local n="$1"; in_ledger "$n"
    local st; st="$(stage_of "$n")"
    case "$st" in
        double-run|cloud-paused) echo "$n is already active here ($st)."; return 0 ;;
        trialled) ;;
        *) die "port activate comes after port trial: $n is at $st" ;;
    esac
    ( cmd_resume "$n" ) || die "$n could not be resumed; nothing changed in the port"
    set_stage "$n" double-run
    lw --arg n "$n" --arg t "$(port_now)" '.tasks[$n].activated = $t'
    echo "$n now runs here, and its cloud task is still enabled, so it runs twice until that one is disabled."
    echo "Pause the cloud task (pause it; deleting it is not part of this), then: schedule.sh port cloud-paused $n --confirmed"
}

# The cloud twin is paused, never deleted: it stays in the cloud scheduler, so the way back is one step.
port_cloud_paused() {
    need_ledger
    [[ $# -ge 1 ]] || usage_die "port cloud-paused needs a task"
    local n="$1"; in_ledger "$n"
    [[ "${2:-}" == --confirmed ]] || die "port cloud-paused records that the cloud task is paused; give --confirmed once it is"
    local st; st="$(stage_of "$n")"
    case "$st" in
        cloud-paused) echo "$n's cloud task is already recorded as paused."; return 0 ;;
        double-run) ;;
        *) die "port cloud-paused comes after port activate: $n is at $st" ;;
    esac
    set_stage "$n" cloud-paused
    lw --arg n "$n" --arg t "$(port_now)" '.tasks[$n].cloud_paused = $t'
    echo "$n: its cloud task is recorded as paused, and still there; this one runs here alone. 'schedule.sh port rollback $n' goes back."
}

# rollback: the local task is paused with a reason, the row goes back to trialled, and the cloud twin is
# to be re-enabled; it was paused, not deleted, so it is still there to turn back on.
port_rollback() {
    need_ledger
    [[ $# -ge 1 ]] || usage_die "port rollback needs a task"
    local n="$1"; in_ledger "$n"
    local st; st="$(stage_of "$n")"
    case "$st" in
        double-run|cloud-paused) ;;
        *) die "port rollback is for a task that runs here (double-run or cloud-paused); $n is at $st" ;;
    esac
    ( cmd_pause "$n" --reason "rolled back to its cloud task on $(port_now)" ) >/dev/null || die "$n could not be paused; nothing changed in the port"
    set_stage "$n" trialled
    lw --arg n "$n" --arg t "$(port_now)" '.tasks[$n].rolled_back = $t'
    echo "$n is paused here and back at trialled. Re-enable its cloud task, which was paused, not deleted."
}

port_skip() {
    need_ledger
    [[ $# -ge 1 ]] || usage_die "port skip needs a task"
    local n="$1" reason=""; shift
    [[ "${1:-}" == --reason ]] && reason="${2:-}"
    [[ -n "$reason" ]] || usage_die "port skip needs --reason"
    in_ledger "$n"
    [[ "$(stage_of "$n")" != cloud-paused ]] || die "$n runs here alone, its cloud task paused; 'port rollback $n' goes back first"
    set_stage "$n" skipped
    lw --arg n "$n" --arg r "$reason" '.tasks[$n].skip_reason = $r'
    echo "Skipped $n: $reason. Its task file stays, paused."
}

# What comes next for each stage, the line status prints.
port_next() {
    local n="$1" st="$2" blocks="$3"
    case "$st" in
        imported) printf 'fix %s block finding(s) in its file, then port check %s' "$blocks" "$n" ;;
        checked) printf 'port trial %s' "$n" ;;
        trialled) printf 'port activate %s' "$n" ;;
        double-run) printf 'pause the cloud task, then port cloud-paused %s --confirmed' "$n" ;;
        cloud-paused) printf 'runs here; the cloud task is paused (port rollback %s goes back)' "$n" ;;
        skipped) printf 'skipped: %s' "$(lj -r --arg n "$n" '.tasks[$n].skip_reason // ""')" ;;
    esac
}

port_status() {
    need_ledger
    local json=0; [[ "${1:-}" == --json ]] && json=1
    local rows n st b w
    # double-run first (a task running in two places), then by stage.
    rows="$(lj -r '.tasks | to_entries[] | .key as $n | .value as $t | [
              (if $t.stage == "double-run" then 0 else 1 end),
              ({"imported":1,"checked":2,"trialled":3,"double-run":4,"cloud-paused":5,"skipped":9}[$t.stage] // 0), $n, $t.stage,
              ([$t.findings[]? | select(.severity == "block")] | length),
              ([$t.findings[]? | select(.severity == "warn") | select(($t.acks[.id] // null) == null)] | length)
            ] | @tsv' | sort -t '	' -k1,1n -k2,2n -k3,3)"
    if (( json )); then
        local out=""
        while IFS='	' read -r _ _ n st b w; do
            [[ -n "$n" ]] || continue
            out+="$(jq -nc --arg n "$n" --arg s "$st" --argjson b "$b" --argjson w "$w" --arg x "$(port_next "$n" "$st" "$b")" \
                '{name: $n, stage: $s, blocks: $b, warns: $w, next: $x}'),"
        done <<<"$rows"
        printf '{"source":%s,"tasks":[%s]}\n' "$(lj '.source')" "${out%,}"
        return 0
    fi
    echo "Port from $(lj -r '.source'), started $(lj -r '.started')"
    # The name column is as wide as the longest name, so a long one does not push into STAGE.
    local wn=4
    while IFS='	' read -r _ _ n _; do (( ${#n} > wn )) && wn=${#n}; done <<<"$rows"
    printf "%-${wn}s  %-12s %-6s %-6s %s\n" TASK STAGE BLOCK WARN NEXT
    while IFS='	' read -r _ _ n st b w; do
        [[ -n "$n" ]] || continue
        printf "%-${wn}s  %-12s %-6s %-6s %s\n" "$n" "$st" "$b" "$w" "$(port_next "$n" "$st" "$b")"
    done <<<"$rows"
}

port_done() {
    need_ledger
    local left; left="$(lj -r '.tasks | to_entries[] | select(.value.stage != "cloud-paused" and .value.stage != "skipped") | "\(.key) (\(.value.stage))"')"
    [[ -z "$left" ]] || die "port done comes once every task is cloud-paused or skipped; still open: $(printf '%s' "$left" | paste -sd, - | sed 's/,/, /g')"
    local r s twins; r="$(lj '[.tasks[] | select(.stage == "cloud-paused")] | length')"; s="$(lj '[.tasks[] | select(.stage == "skipped")] | length')"
    twins="$(lj -r '.tasks | to_entries[] | select(.value.stage == "cloud-paused") | "  \(.key): \(.value.source_name)\(if .value.source_id != "" then " (" + .value.source_id + ")" else "" end)"')"
    local closed; closed="$PORT_DIR/done-$(date '+%Y%m%d-%H%M%S').json"
    mv "$LEDGER" "$closed"
    echo "Port closed: $r task(s) moved and running here alone, $s skipped. The ledger is kept at $closed."
    if [[ -n "$twins" ]]; then
        echo "These cloud tasks are paused in the cloud scheduler, not deleted; nothing here deletes them:"
        printf '%s\n' "$twins"
    fi
}

port_usage() {
    # The header comment, from its first line about port to the first line that is not a comment.
    awk '/^# schedule.sh port:/ { on = 1 } on && !/^#/ { exit } on { sub(/^# ?/, ""); print }' "$SELF_DIR/lib/port.sh"
}

cmd_port() {
    have jq || die "port needs jq, which reads the export and keeps the ledger; install jq, then start again"
    local sub="${1:-status}"; [[ $# -gt 0 ]] && shift
    case "$sub" in
        start) port_start "$@" ;;
        check) port_check "$@" ;;
        ack) port_ack "$@" ;;
        trial) port_trial "$@" ;;
        activate) port_activate "$@" ;;
        cloud-paused) port_cloud_paused "$@" ;;
        rollback) port_rollback "$@" ;;
        skip) port_skip "$@" ;;
        status) port_status "$@" ;;
        done) port_done "$@" ;;
        help|-h|--help) port_usage ;;
        *) usage_die "port has no step '$sub'; 'schedule.sh port help' lists them" ;;
    esac
}
