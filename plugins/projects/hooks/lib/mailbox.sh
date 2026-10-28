# shellcheck shell=bash
# Where a project's pairing mailbox is. Sourced by hooks/pair.sh (its `where` and `default` commands)
# and scripts/pair.sh (the launcher), so both sides of a pairing find it the same way.
#
# A mailbox is any folder: inside the project, or anywhere else, including a folder that is copied
# between machines. It is found, in order:
#   1. the folder named for this one command (--mailbox);
#   2. an existing mailbox (one holding to-cc.md) at <default root>/<slug>, then at <project>/mailbox;
#   3. a new one at <default root>/<slug> when a default root is set, else at <project>/mailbox.
# An existing mailbox wins over a new location, so setting a default never loses a pairing in flight.
#
# The default root is set per machine, since the same folder has a different path on each:
# PAIR_MAILBOX_ROOT, else the first line of ~/.config/agentic-workspace-kit/mailbox-root (PAIR_CONFIG_DIR
# moves that folder). A leading ~/ expands.
#
# Written for bash 3.2 and POSIX tools.

aw_mb_config() { printf '%s' "${PAIR_CONFIG_DIR:-$HOME/.config/agentic-workspace-kit}/mailbox-root"; }

# aw_mb_root: the default root on this machine, or nothing.
aw_mb_root() {
    local r="${PAIR_MAILBOX_ROOT:-}"
    [ -n "$r" ] || r="$(sed -n '/^[[:space:]]*#/d; /^[[:space:]]*$/d; p' "$(aw_mb_config)" 2>/dev/null | head -n 1)"
    r="$(printf '%s' "$r" | sed 's/[[:space:]]*$//')"
    case "$r" in \~/*) r="$HOME/${r#\~/}" ;; esac
    printf '%s' "${r%/}"
}

# aw_mb_slug <project folder>: the project's name, without a priority prefix (00-, 01-).
aw_mb_slug() { basename "$1" | sed 's/^[0-9][0-9]*-//'; }

# aw_mb_resolve <project folder> [one-off folder]: prints the mailbox's path, then a tab, then "existing"
# or "new".
aw_mb_resolve() {
    local proj="$1" once="${2:-}" root cand
    if [ -n "$once" ]; then
        if [ -f "$once/to-cc.md" ]; then printf '%s\texisting\n' "$once"; else printf '%s\tnew\n' "$once"; fi
        return 0
    fi
    root="$(aw_mb_root)"
    for cand in ${root:+"$root/$(aw_mb_slug "$proj")"} "$proj/mailbox"; do
        [ -f "$cand/to-cc.md" ] && { printf '%s\texisting\n' "$cand"; return 0; }
    done
    if [ -n "$root" ]; then printf '%s/%s\tnew\n' "$root" "$(aw_mb_slug "$proj")"
    else printf '%s/mailbox\tnew\n' "$proj"
    fi
}
