#!/usr/bin/env bash
# SessionStart summary for the workspace plugin: one line for each thing about the workspace that is
# out of step — the git hooks, the kit import, a submodule, an orphan gitlink, a resource, a sensitive
# project, the origin, the kit's distance from its remote, a kit plugin not loaded while the skills
# bridge's kit-* skills stand in for it — each naming the command that fixes it. A workspace in step gets
# nothing.
#
# It finds the workspace from the session's folder: the nearest ancestor (the folder itself included)
# holding kit/CLAUDE.kit.md or .claude/kit-templates.lock. So a session opened inside kit/, or inside a
# project that is its own repository, reports on the workspace around it, and one opened anywhere else
# reports nothing. It reads the workspace through bin/state.sh --quick, which makes no network call,
# takes no lock and never lists a resource folder.
#
# The lines go out twice, as the projects hook's do: as systemMessage, which the person sees, and as
# additionalContext, which the agent reads.
#
# Hook-environment rules, shared with the other kit hooks: jq is required, there is no network, the
# timeout is 10 seconds (hooks/hooks.json), and any failure is silent — this summary is a convenience,
# never a gate, so every path out of the script exits 0 with nothing on stderr.
#
# Environment:
#   WORKSPACE_HOOK_DISABLED=1    turn the hook off
#   AW_HEADLESS_RUN=1            a headless run (an ablation arm): say nothing
#   CLOSEOUT_HOOK_CHILD          set by the closeout plugin's capture child, which has no one to tell
#
# Wired from hooks/hooks.json -> hooks.SessionStart (matcher startup).
# Written for bash 3.2, since macOS runs hooks with /bin/bash when it is first on PATH.

exec 2>/dev/null
trap 'exit 0' EXIT

# Read the hook input before any early exit, so the writer never meets a closed pipe.
input="$(cat)"

[[ "${WORKSPACE_HOOK_DISABLED:-}" == "1" ]] && exit 0
[[ "${AW_HEADLESS_RUN:-}" == "1" ]] && exit 0
[[ -n "${CLOSEOUT_HOOK_CHILD:-}" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
cwd="${cwd:-$PWD}"
cwd="${cwd%/}"
[[ -d "$cwd" ]] || exit 0
cwd="$(cd "$cwd" && pwd -P)" || exit 0

root="" d="$cwd"
while [[ -n "$d" ]]; do
    if [[ -f "$d/kit/CLAUDE.kit.md" || -f "$d/.claude/kit-templates.lock" ]]; then root="$d"; break; fi
    [[ "$d" == / ]] && break
    d="$(dirname "$d")"
done
[[ -n "$root" ]] || exit 0

rep="$(bash "$here/../bin/state.sh" --quick --target "$root" 2>/dev/null)" || exit 0
[[ -n "$rep" ]] || exit 0
# key <name>: one value from the report; per-item keys carry slashes and dots, so an index() match.
key() { printf '%s\n' "$rep" | awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }'; }
# field <value> <name>: one name=value part of a submodule.<path> value.
field() { printf '%s\n' "$1" | tr ' ' '\n' | awk -v k="$2=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }'; }
# names <comma list>: the first three, joined by ", ", with … when there are more.
names() {
    printf '%s\n' "$1" | tr ',' '\n' | sed '/^$/d' \
        | awk 'NR <= 3 { s = s (NR > 1 ? ", " : "") $0 } END { if (NR > 3) s = s ", …"; print s }'
}
ncount() { printf '%s\n' "$1" | tr ',' '\n' | sed '/^$/d' | awk 'END { print NR }'; }
# isnum <value>: exit 0 for a whole number.
isnum() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
# plural <n> <one> <many>
plural() { if [[ "$1" == 1 ]]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi; }

# The submodules whose update is rebase (the workspace's config, else .gitmodules): a detached HEAD is
# out of step only for those. name -> path comes from .gitmodules.
rebase_paths=""
if [[ -f "$root/.gitmodules" ]]; then
    rebase_paths="$( { git --no-optional-locks -C "$root" config -f .gitmodules --get-regexp '^submodule\..*\.(path|update)$' \
                         | sed 's/^/m /'
                       git --no-optional-locks -C "$root" config --get-regexp '^submodule\..*\.update$' | sed 's/^/c /'; } \
        | awk '{ src = $1; k = $2; v = $3; sub(/^submodule\./, "", k); f = k; sub(/.*\./, "", f); n = substr(k, 1, length(k) - length(f) - 1)
                 if (f == "path") path[n] = v
                 else if (src == "c") cu[n] = v
                 else mu[n] = v }
               END { for (n in path) { u = (n in cu) ? cu[n] : mu[n]; if (u == "rebase") print path[n] } }')"
fi

lines=()

# Git hooks: the workspace's, the kit's, and each project submodule's.
hooks_off=no
case "$(key hooks)" in missing|other) hooks_off=yes ;; esac
case "$(key kit_hooks)" in missing|other) hooks_off=yes ;; esac
subs="$(key submodules)"
all_subs="$(printf '%s\n' "$subs" | tr ',' '\n' | sed '/^$/d')"
while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    # A submodule that is not initialised has no git dir to hold hooks, and kit/setup.sh hooks passes
    # over it; it counts once it is initialised.
    [[ "$(field "$(key "submodule.$p")" pointer)" == uninitialized ]] && continue
    [[ "$(field "$(key "submodule.$p")" hooks)" == missing ]] && hooks_off=yes
done <<EOF
$all_subs
EOF
[[ $hooks_off == yes ]] && lines+=("Workspace: git hooks are not active — kit/setup.sh hooks turns them on.")

# The kit's standards in CLAUDE.md.
case "$(key kit_import)" in
    missing) lines+=("Workspace: CLAUDE.md does not import the kit's standards — its first line is @kit/CLAUDE.kit.md.") ;;
    broken) lines+=("Workspace: the kit is not initialised here — git submodule update --init kit.") ;;
esac

# The kit off main in developer mode (update=rebase with a detached HEAD).
kit_path="$(key kit_path)"
kit_dev_detached=no
if [[ -n "$kit_path" && "$kit_path" != none && "$(key kit_branch)" == detached ]] \
   && printf '%s\n' "$rebase_paths" | grep -qxF "$kit_path"; then
    kit_dev_detached=yes
    lines+=("Workspace: kit/ is detached from main (developer mode) — kit/setup.sh --developer puts it back.")
fi

# Submodules out of step, by the last part of their path (the whole path when two share it). The kit's
# distance from its remote has a line of its own, below.
items=()
attention="$(key submodules_attention)"
while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    v="$(key "submodule.$p")"
    role="$(field "$v" role)"
    [[ "$role" == outside ]] && continue
    parts=()
    n="$(field "$v" dirty)"; isnum "$n" && [[ "$n" -gt 0 ]] && parts+=("$(plural "$n" "changed file" "changed files")")
    n="$(field "$v" unpushed)"; isnum "$n" && [[ "$n" -gt 0 ]] && parts+=("$(plural "$n" "commit not pushed" "commits not pushed")")
    case "$(field "$v" pointer)" in staged|uncommitted) parts+=("pointer changed, not committed") ;; esac
    n="$(field "$v" behind)"
    [[ "$role" != kit ]] && isnum "$n" && [[ "$n" -gt 0 ]] && parts+=("$(plural "$n" "commit behind its remote" "commits behind its remote")")
    if [[ "$(field "$v" branch)" == detached ]] && printf '%s\n' "$rebase_paths" | grep -qxF "$p"; then
        [[ "$role" == kit && $kit_dev_detached == yes ]] || parts+=("detached")
    fi
    [[ ${#parts[@]} -gt 0 ]] || continue
    label="${p##*/}"
    same="$(printf '%s\n' "$all_subs" | awk -F/ -v l="$label" '$NF == l' | awk 'END { print NR }')"
    [[ "$same" -gt 1 ]] && label="$p"
    joined="${parts[0]}"
    i=1; while [[ $i -lt ${#parts[@]} ]]; do joined="$joined, ${parts[$i]}"; i=$((i + 1)); done
    items+=("$label: $joined")
done <<EOF
$(printf '%s\n' "$attention" | tr ',' '\n')
EOF
if [[ ${#items[@]} -gt 0 ]]; then
    s="${items[0]}"
    i=1; while [[ $i -lt ${#items[@]} ]]; do s="$s; ${items[$i]}"; i=$((i + 1)); done
    lines+=("Workspace: $s.")
fi

# Gitlinks with no .gitmodules entry.
v="$(key orphan_gitlinks)"
if [[ -n "$v" ]]; then
    n="$(ncount "$v")"
    if [[ "$n" == 1 ]]; then w="1 gitlink has"; else w="$n gitlinks have"; fi
    lines+=("Workspace: $w no .gitmodules entry ($(names "$v")) — kit/setup.sh migrate --dry-run names the two fixes.")
fi

# Resources absent or unreadable on this machine (unmapped names are the projects hook's to offer).
v="$(key external_paths_missing)"
if [[ -n "$v" ]]; then
    lines+=("Workspace: $(plural "$(ncount "$v")" "resource" "resources") not reachable on this machine ($(names "$v")) — kit/setup.sh link.")
fi

# Sensitive projects with files the workspace tracks.
v="$(key sensitive_tracked)"
if [[ -n "$v" ]]; then
    n="$(ncount "$v")"
    if [[ "$n" == 1 ]]; then
        lines+=("Workspace: 1 sensitive project has files tracked by the workspace ($v) — /projects:adopt $v untracked.")
    else
        lines+=("Workspace: $n sensitive projects have files tracked by the workspace ($(names "$v")) — /projects:adopt <slug> untracked, for each.")
    fi
fi

# An origin not recorded as confirmed private.
[[ "$(key origin_visibility)" == unconfirmed ]] \
    && lines+=("Workspace: origin is not confirmed private — kit/setup.sh records it once confirmed.")

# The kit behind its remote.
n="$(key kit_behind)"
if isnum "$n" && [[ "$n" -gt 0 ]]; then
    lines+=("Workspace: the kit is $(plural "$n" "commit" "commits") behind its remote — kit/setup.sh update.")
fi

# Kit plugins not loaded while the skills bridge's kit-* skills are there: the skills would stand in for
# the plugin's commands and hide that it is missing. A plugin set false in settings is a choice, not named.
if [[ "$(key skills_bridge)" == present && "$(key plugins_loaded)" == no ]]; then
    v="$(key plugins_not_loaded | tr ',' '\n' | awk -F: '$2 == "not-enabled" || $2 == "not-installed" { print $1 }' | paste -sd, -)"
    if [[ -n "$v" ]]; then
        n="$(ncount "$v")" nm="$(names "$v")"
        if [[ "$n" == 1 ]]; then
            lines+=("Workspace: the kit's $v plugin is not loaded, so its kit-* skills stand in for it — claude plugin install $v@agentic-workspace, or /plugin.")
        else
            lines+=("Workspace: the kit's plugins $nm are not loaded, so their kit-* skills stand in for them — claude plugin install <name>@agentic-workspace for each, or /plugin.")
        fi
    fi
fi

[[ ${#lines[@]} -gt 0 ]] || exit 0
msg="$(printf '%s\n' "${lines[@]}")"
context="What is out of step in this workspace, from the workspace plugin's session-start check (kit/plugins/workspace/bin/state.sh --quick, read from ${root}):
$msg
Mention these when the person's first request leaves room. Each line names its fix; setup and git commands are the person's to run, or yours on their yes."
jq -nc --arg m "$msg" --arg c "$context" \
    '{systemMessage:$m, hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$c}}'
exit 0
