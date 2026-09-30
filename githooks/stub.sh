#!/bin/sh
# agentic-workspace-kit hook stub 1
# The stub kit/setup.sh hooks copies into <git dir>/aw-hooks/<name> of each repository the kit looks
# after, with core.hooksPath pointing there. It finds the kit's hook of the same name and runs it: in
# the kit's own repository, the hook beside it; anywhere else, the one in the nearest kit/ folder above.
# A kit that cannot be reached (not initialised, checked out at an older release, or a folder moved)
# refuses rather than letting the commit or push through unchecked.
name=${0##*/}
case "$name" in pre-push) what=pushed ;; *) what=committed ;; esac
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$TOP" ]; then
    if grep -q '"agentic-workspace"' "$TOP/.claude-plugin/marketplace.json" 2>/dev/null && [ -x "$TOP/githooks/$name" ]; then
        exec "$TOP/githooks/$name" "$@"
    fi
    d=$TOP
    while :; do
        if grep -q '"agentic-workspace"' "$d/kit/.claude-plugin/marketplace.json" 2>/dev/null && [ -x "$d/kit/githooks/$name" ]; then
            exec "$d/kit/githooks/$name" "$@"
        fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
fi
echo "aw: the kit's hooks are not reachable from ${TOP:-this repository} (kit not initialised, or moved); kit/setup.sh hooks sets them up again. Nothing was $what." >&2
exit 1
