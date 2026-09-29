#!/usr/bin/env bash
# Shared configuration resolution for the projects plugin's hooks.
#
# Sourced by session-start.sh. The projects commands read .claude/projects.md as
# prose; a hook cannot, so it reads the few settings it needs from the one habit
# that file keeps: one setting per bullet, "- **Label:** ... `value` ...", the
# first backticked value being the setting. Anything absent falls back to the kit
# defaults, which are also what team/projects-conventions.md says.
#
# Written for bash 3.2 (macOS /bin/bash): no ${x,,}, no mapfile, no associative
# arrays.

# projects_root <dir>
# Echoes the repository the session belongs to: the nearest ancestor holding
# .claude/projects.md, else the nearest holding .git (directory or file, so a
# submodule or worktree counts), else nothing. $HOME itself is never a root —
# ~/.claude is the user's own configuration, not a repository's.
projects_root() {
    local d="$1" git_root=""
    while [[ -n "$d" && "$d" != "/" ]]; do
        if [[ "$d" != "$HOME" ]]; then
            [[ -f "$d/.claude/projects.md" ]] && { printf '%s' "$d"; return; }
            [[ -z "$git_root" && -e "$d/.git" ]] && git_root="$d"
        fi
        d="${d%/*}"
    done
    printf '%s' "$git_root"
}

# projects_config <root>
#
# Sets: CONVENTIONS_FILE, ACTIVE_PATTERN, PAUSED_PATTERN, DONE_PATTERN,
#       ENTRY_POINT, REGISTER_FILE, DEFAULT_OWNER (a backticked **Owner:** or
#       **Default owner:** — one owner for every project with no People section),
#       ALIAS_OUTCOME, ALIAS_DONE, ALIAS_PEOPLE
# Patterns are root-relative paths whose <placeholder> segments stand for any one
# folder name, e.g. "projects/<slug>" or "archive/<year>/<slug>". Aliases are
# lowercase heading names joined by "|", from the conventions file's
# **Section names** line, read sentence by sentence: a backticked name in a
# sentence that mentions "Done when" is an alias for Done when, and so on — so a
# Section names sentence backticks heading names and nothing else.
projects_config() {
    local root="$1" label value
    CONVENTIONS_FILE="$root/.claude/projects.md"
    ACTIVE_PATTERN="projects/<slug>"
    PAUSED_PATTERN=""
    DONE_PATTERN=""
    ENTRY_POINT="README.md"
    REGISTER_FILE="projects/INDEX.md"
    DEFAULT_OWNER=""
    ALIAS_OUTCOME=""
    ALIAS_DONE=""
    ALIAS_PEOPLE=""
    [[ -f "$CONVENTIONS_FILE" ]] || return 0

    # Collected first and read from a here-document rather than by process
    # substitution: /dev/fd is not available in every sandbox a hook or test runs in.
    local records
    records="$(projects_conventions_records "$CONVENTIONS_FILE")"
    while IFS=$'\x1f' read -r label value; do
        case "$label" in
            active)      [[ -n "$value" ]] && ACTIVE_PATTERN="$(projects_pattern "$value")" ;;
            paused)      [[ -n "$value" ]] && PAUSED_PATTERN="$(projects_pattern "$value")" ;;
            done)        [[ -n "$value" ]] && DONE_PATTERN="$(projects_pattern "$value")" ;;
            entry\ point) [[ -n "$value" ]] && ENTRY_POINT="$value" ;;
            register)    [[ -n "$value" ]] && REGISTER_FILE="${value#./}" ;;
            owner|default\ owner) [[ -n "$value" ]] && DEFAULT_OWNER="$value" ;;
            alias_outcome) ALIAS_OUTCOME="${ALIAS_OUTCOME:+$ALIAS_OUTCOME|}$value" ;;
            alias_done)    ALIAS_DONE="${ALIAS_DONE:+$ALIAS_DONE|}$value" ;;
            alias_people)  ALIAS_PEOPLE="${ALIAS_PEOPLE:+$ALIAS_PEOPLE|}$value" ;;
        esac
    done <<EOF
$records
EOF
}

# projects_conventions_records <file>
# One "label<US>value" line per setting bullet, plus alias_* lines for Section names.
projects_conventions_records() {
    awk '
        # Emit one record per "- **Label:** text" bullet, with its continuation lines.
        function flush(   lab, rest, v, n, i, s, low, t) {
            if (buf == "") return
            if (match(buf, /^\*\*[^*]+\*\*/)) {
                lab = substr(buf, 3, RLENGTH - 4); sub(/:$/, "", lab)
                lab = tolower(lab); rest = substr(buf, RLENGTH + 1)
                if (lab == "section names") {
                    n = split(rest, s, /[.;] /)
                    for (i = 1; i <= n; i++) {
                        low = tolower(s[i]); t = s[i]
                        while (match(t, /`[^`]+`/)) {
                            v = tolower(substr(t, RSTART + 1, RLENGTH - 2)); t = substr(t, RSTART + RLENGTH)
                            if (low ~ /done when/)        print "alias_done\037" v
                            if (low ~ /desired outcome/)  print "alias_outcome\037" v
                            if (low ~ /people/)           print "alias_people\037" v
                        }
                    }
                } else {
                    v = ""
                    if (match(rest, /`[^`]+`/)) v = substr(rest, RSTART + 1, RLENGTH - 2)
                    print lab "\037" v
                }
            }
            buf = ""
        }
        /^[ \t]*```/ { flush(); fence = !fence; next }
        fence { next }
        /^[ \t]*[-*][ \t]+/ { flush(); line = $0; sub(/^[ \t]*[-*][ \t]+/, "", line); buf = line; next }
        /^[ \t]+[^ \t]/ && buf != "" { line = $0; sub(/^[ \t]+/, "", line); buf = buf " " line; next }
        { flush() }
        END { flush() }
    ' "$1" 2>/dev/null
}

# projects_pattern <value>
# "projects/<slug>/" -> "projects/<slug>"; a bare folder ("work/") gains "/<slug>".
projects_pattern() {
    local p="${1%/}"
    p="${p#./}"
    case "$p" in *"<"*">"*) ;; *) p="$p/<slug>" ;; esac
    printf '%s' "$p"
}

# projects_match <pattern> <relative path>
# Echoes the leading part of the path that the pattern names — the project folder —
# or nothing when the path is not inside one.
projects_match() {
    local pattern="$1" rel="$2" out="" p r
    local IFS=/
    # shellcheck disable=SC2206
    local -a pp=($pattern) rr=($rel)
    [[ ${#rr[@]} -ge ${#pp[@]} && ${#pp[@]} -gt 0 ]] || return 0
    local i=0
    while [[ $i -lt ${#pp[@]} ]]; do
        p="${pp[$i]}"; r="${rr[$i]}"
        case "$p" in
            "<"*">") [[ -n "$r" && "$r" != .* ]] || return 0 ;;
            *) [[ "$p" == "$r" ]] || return 0 ;;
        esac
        out="${out:+$out/}$r"
        i=$((i + 1))
    done
    printf '%s' "$out"
}
