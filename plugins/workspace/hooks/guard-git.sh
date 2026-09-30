#!/usr/bin/env bash
# plugins/workspace/hooks/guard-git.sh: a Claude Code PreToolUse hook on Bash. The workspace's git
# hooks decide what reaches a remote; this keeps an agent from stepping around them. It denies a git
# commit, push, merge, rebase, cherry-pick, am or pull that also carries a bypass (--no-verify, a
# standalone -n after commit, -c core.hooksPath, core.hooksPath=, or a GIT_CONFIG_ variable naming
# hooksPath), and a git config that changes core.hooksPath (kit/setup.sh hooks is the way to set it).
#
# It reads the tool input as raw text, so it needs no jq. On any other command, on input it cannot
# read, and when AW_GIT_GUARD_DISABLED=1 is set in the session's environment, it prints nothing and
# exits 0.

[[ "${AW_GIT_GUARD_DISABLED:-}" == 1 ]] && exit 0

input="$(cat 2>/dev/null)" || exit 0

# The command string: the first "command" value after "tool_input", with JSON escapes undone. Each
# shell separator (; & | and newline) then starts a new segment, and each segment is judged on its own.
cmd="$(printf '%s' "$input" | awk '
    BEGIN { RS = "\001" }
    {
        s = $0
        i = index(s, "\"tool_input\""); if (i > 0) s = substr(s, i)
        if (!match(s, /"command"[ \t\r\n]*:[ \t\r\n]*"/)) exit
        s = substr(s, RSTART + RLENGTH)
        out = ""; n = length(s)
        for (j = 1; j <= n; j++) {
            c = substr(s, j, 1)
            if (c == "\\") {
                j++; e = substr(s, j, 1)
                if (e == "n") out = out "\n"
                else if (e == "t") out = out "\t"
                else if (e == "r") out = out " "
                else out = out e
            } else if (c == "\"") { found = 1; break }
            else out = out c
        }
        if (found) printf "%s", out
    }' 2>/dev/null)" || exit 0
[[ -n "$cmd" ]] || exit 0

deny() {
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The workspace'"'"'s git hooks decide what reaches a remote. Report the hook'"'"'s refusal to the person rather than bypassing it."}}'
    exit 0
}

# A short-option cluster git commit accepts that holds n (-n, -an, -nm) skips the hooks as well.
cluster_re='^-[acCeFimnoqsStuvz]*n[acCeFimnoqsStuvz]*$'
# A GIT_CONFIG_ variable naming hooksPath can be set in one segment and read by git in the next.
env_hooks=0
case "$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')" in
    *git_config_*hookspath*|*hookspath*git_config_*) env_hooks=1 ;;
esac

# Each of ; & | becomes a newline, one for one.
# shellcheck disable=SC2020
segments="$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')"
while IFS= read -r seg; do
    [[ -n "$seg" ]] || continue
    lower="$(printf '%s' "$seg" | tr '[:upper:]' '[:lower:]')"
    # Word-split without globbing: a pattern in the command is text here, never a file list.
    set -f
    # shellcheck disable=SC2206
    words=($seg)
    set +f
    has_git=0 sub="" after_commit=0 bypass=0 is_config=0 reads=0
    for w in ${words[@]+"${words[@]}"}; do
        w="${w#[\"\'(]}"; w="${w%[\"\')]}"
        case "$w" in
            git|*/git) has_git=1; continue ;;
        esac
        [[ $has_git -eq 1 ]] || continue
        if [[ -z "$sub" ]]; then
            case "$w" in
                commit|push|merge|rebase|cherry-pick|am|pull) sub="$w"; [[ "$w" == commit ]] && after_commit=1 ;;
                config) sub=config; is_config=1 ;;
            esac
        fi
        case "$w" in
            --no-verify) bypass=1 ;;
            --get|--get-all|--get-regexp|--list|-l|get|--show-origin) reads=1 ;;
        esac
        [[ $after_commit -eq 1 && "$w" =~ $cluster_re ]] && bypass=1
    done
    [[ $has_git -eq 1 ]] || continue
    if [[ -n "$sub" && $is_config -eq 0 ]]; then
        [[ $bypass -eq 1 || $env_hooks -eq 1 ]] && deny
        case "$lower" in
            *"-c core.hookspath"*|*"core.hookspath="*) deny ;;
        esac
    fi
    if [[ $is_config -eq 1 && $reads -eq 0 ]]; then
        case "$lower" in *core.hookspath*) deny ;; esac
    fi
done <<EOF
$segments
EOF
exit 0
