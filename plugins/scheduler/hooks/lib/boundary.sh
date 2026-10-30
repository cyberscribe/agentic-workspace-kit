# shellcheck shell=bash
# The workspace boundary, sourced by every hook of the kit's plugins.
#
# Setup installs the plugins for the person (user scope), so Claude Code loads them in every session on
# the machine, wherever it is opened. Their hooks act only inside a kit workspace and pass silently
# everywhere else. A folder is inside one when it, or a folder above it, holds kit/CLAUDE.kit.md (the
# kit, as the workspace's submodule) or .claude/kit-templates.lock (the ledger setup writes). The folder
# is resolved with pwd -P first, so a workspace entered through a symlink counts.
#
# Each plugin carries a byte-identical copy at hooks/lib/boundary.sh, because an installed plugin can
# reach only its own folder. tests/sections/25-boundary.sh checks that the copies match.
#
# Written for bash 3.2, with no jq: the guard and the pair hooks run without it.

# aw_input_cwd <hook input JSON>: the session's folder as the input gives it, its first "cwd" (a later
# one could sit inside a tool's input), JSON escapes undone; nothing when there is none.
aw_input_cwd() {
    printf '%s' "${1:-}" | awk 'BEGIN { RS = "\001" }
        { i = index($0, "\"cwd\""); if (i == 0) exit
          s = substr($0, i + 5); if (!sub(/^[ \t\r\n]*:[ \t\r\n]*"/, "", s)) exit
          out = ""
          while (length(s) > 0) {
              c = substr(s, 1, 1)
              if (c == "\\") { out = out substr(s, 2, 1); s = substr(s, 3); continue }
              if (c == "\"") break
              out = out c; s = substr(s, 2)
          }
          print out; exit }'
}

# aw_workspace_root <hook input JSON>: the workspace the session is in, or nothing. The folder is the
# input's cwd, else CLAUDE_PROJECT_DIR, else the hook's own working folder.
aw_workspace_root() {
    local d
    d="$(aw_input_cwd "${1:-}")"
    [[ -n "$d" ]] || d="${CLAUDE_PROJECT_DIR:-$PWD}"
    d="$(cd "$d" 2>/dev/null && pwd -P)" || return 0
    while [[ -n "$d" ]]; do
        if [[ -f "$d/kit/CLAUDE.kit.md" || -f "$d/.claude/kit-templates.lock" ]]; then
            printf '%s\n' "$d"
            return 0
        fi
        [[ "$d" == / ]] && return 0
        d="$(dirname "$d")"
    done
    return 0
}
