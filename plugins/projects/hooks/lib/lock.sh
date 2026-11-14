# shellcheck shell=bash
# Locked, atomic edits to a small shared file: a registry, a claims board, a mailbox. Sourced by
# hooks/pair.sh and scripts/registry.sh.
#
# Several agents edit such files at once. Hand-written edits (sed -i, a python rewrite) can each read
# the file, change it and write it back over another's change, and a rewrite that fails half way
# leaves the file truncated, header and all, with nothing said. Here every change happens under a
# lock, is written to a temporary file beside the original, is checked, and only then renamed into
# place: a rename is all or nothing, so a reader sees the old file or the new one, never a part.
#
# The lock is a directory, which mkdir creates or refuses in one step, holding the holder's process
# id and the time it took the lock. A lock whose holder has died is taken over at once. One held for
# more than a minute is taken over too, since every change here takes milliseconds, and that is said
# on stderr, naming the holder and how long it held the lock: a live holder losing its lock is the
# failure this file exists to prevent, so it is never silent. A minute by the clock is not enough on
# its own: the clock can step forward (a machine waking, a new virtual machine setting its time), and
# every lock then looks a minute old at once, a working writer's included. So the waiter must also
# have seen the same holder, unchanged, for about three seconds of its own waiting. The holder releases the lock from an
# exit trap, so a script that stops part way still lets go.
#
# Written for bash 3.2 and POSIX tools.

# aw_take <lock dir> <holder>: removes a lock its holder has left behind, and only that lock. The
# holder was read a moment earlier, and in that moment the lock can change hands: the holder lets go
# and exits, another writer takes the lock, and removing the directory then would pull a live writer's
# lock from under it, so two writers would be in at once and one change lost. So a takeover holds a
# second lock, <lock dir>.take, which lets one writer at a time take over, and reads the holder again
# under it: while the lock still names a holder that is gone, nothing else can change it. A .take left
# by a writer that died part way is cleared after a minute.
aw_take() {
    if ! mkdir "$1.take" 2>/dev/null; then
        [ -z "$(find "$1.take" -prune -mmin +1 2>/dev/null)" ] || rm -rf "$1.take"
        return 0
    fi
    [ "$(cat "$1/pid" 2>/dev/null)" != "$2" ] || rm -rf "$1"
    rmdir "$1.take" 2>/dev/null
    return 0
}

# aw_lock <lock dir>: 0 once the lock is held; 1 after about ten seconds of a live holder.
aw_lock() {
    local l="$1" n=0 holder since key seen="" same=0
    until mkdir "$l" 2>/dev/null; do
        holder="$(cat "$l/pid" 2>/dev/null)"
        if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
            aw_take "$l" "$holder"
            continue
        fi
        # How long this waiter has watched one holder, by its own passes: a holder and the time it
        # took the lock, unchanged since the last pass.
        key="$holder/$(cat "$l/since" 2>/dev/null)"
        if [ "$key" = "$seen" ]; then same=$((same + 1)); else seen="$key" same=0; fi
        if [ "$same" -ge 30 ] && [ -n "$(find "$l" -prune -mmin +1 2>/dev/null)" ]; then
            since="$(cat "$l/since" 2>/dev/null)"
            case "$since" in ''|*[!0-9]*) since="over a minute" ;; *) since="$(( $(date +%s) - since )) seconds" ;; esac
            printf 'lock: taking over %s from process %s, which has held it for %s; its change may be lost\n' \
                "$l" "${holder:-unknown}" "$since" >&2
            aw_take "$l" "$holder"
            continue
        fi
        n=$((n + 1))
        [ "$n" -lt 100 ] || return 1
        sleep 0.1
    done
    printf '%s\n' "$$" > "$l/pid"
    date +%s > "$l/since"
    # shellcheck disable=SC2064
    trap "aw_unlock '$l'" EXIT
}

# aw_unlock <lock dir>: lets go of the lock, if it is still this process's: one taken over after a
# minute belongs to its new holder, which removing it would leave unguarded.
aw_unlock() {
    [ "$(cat "$1/pid" 2>/dev/null)" != "$$" ] || rm -rf "$1"
    trap - EXIT
}

# aw_rewrite <file> <command...>: runs the command with the file's current lines on stdin (none when
# it does not exist yet) and makes its stdout the new file, under the lock <file>.lock. The result
# must keep the file's first line when that line is a header (it starts with "#"); otherwise the file
# is left as it was and the status is 1. The command sees the file as it is under the lock, so two
# writers cannot lose each other's change.
aw_rewrite() {
    local f="$1" tmp head rc; shift
    aw_lock "$f.lock" || return 1
    tmp="$f.tmp.$$"
    if [ -f "$f" ]; then "$@" < "$f" > "$tmp"; else "$@" < /dev/null > "$tmp"; fi
    rc=$?
    head="$(head -n 1 "$f" 2>/dev/null)"
    if [ $rc -ne 0 ] || { case "$head" in '#'*) true ;; *) false ;; esac && [ "$(head -n 1 "$tmp")" != "$head" ]; }; then
        rm -f "$tmp"; aw_unlock "$f.lock"; return 1
    fi
    mv "$tmp" "$f"
    aw_unlock "$f.lock"
}
