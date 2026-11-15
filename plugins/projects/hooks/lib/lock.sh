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
# The lock is a directory holding one file, h.<id>, which gives the holder's process id, host, the time
# it took the lock and the process's own start time. The holder writes that file into a folder of its
# own beside the lock and renames the folder into place. A rename onto a path that is absent, or an
# empty folder, succeeds in one step, and onto a folder holding a file it fails, so a lock never exists
# without its holder's file, and an empty folder (a process stopped half way through letting go) is
# simply taken. Without perl, which makes the rename, the folder is made first and the file moved in.
#
# A lock is taken over only when its holder is not running: on the same host, no process with that id,
# or one that started at a different time (the id has been reused). A holder that is alive keeps its
# lock however long it takes, so a clock that steps forward cannot cost it the lock; a waiter that has
# waited AW_LOCK_WAIT seconds (10 by default) gives up and says who holds it. A holder on another
# host cannot be checked, so it counts as alive.
#
# Taking over is removing the dead holder's own file, then the directory. Removing a file succeeds
# for one process only, and fails once the file is gone, so of two waiters only one takes over, and a
# waiter that read a holder which has since let go cannot remove the next holder's lock: that lock
# holds a different file. The directory is removed only when empty, by the one waiter that removed
# the file. The holder lets go the same way, from an exit trap too, so a script that stops part way
# still lets go.
#
# The change itself is written as before: to a temporary file, then renamed into place, so a reader
# sees the old file or the new one and never a part. The lock only orders the writers.
#
# Written for bash 3.2 and POSIX tools.

# aw_proc_start <pid>: the process's start time, for telling it from a later process given the same
# id. Status 0 with the time when the process exists, 1 when it does not, 2 when this host cannot say.
# Linux reads /proc (ticks since boot); elsewhere ps, in UTC and the C locale so that every reader on
# the host gets the same text.
aw_proc_start() {
    local s
    if [ -d /proc/1 ]; then
        read -r s 2>/dev/null < "/proc/$1/stat" || return 1
        s="${s##*) }"
        # shellcheck disable=SC2086
        set -- $s
        printf '%s\n' "${20}"
        return 0
    fi
    command -v ps >/dev/null 2>&1 || return 2
    s="$(TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null)" || return 1
    [ -n "$s" ] || return 1
    # ps pads the field; one space between words, so the text survives being read back with read.
    # shellcheck disable=SC2086
    set -- $s
    printf '%s\n' "$*"
}

# aw_lock_dead <pid> <host> <start>: 0 when that holder is certainly not running.
aw_lock_dead() {
    local now rc
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$2" = "$HOSTNAME" ] || return 1
    now="$(aw_proc_start "$1")"; rc=$?
    case $rc in
        0) [ -n "$3" ] && [ "$now" != "$3" ] ;;
        1) return 0 ;;
        *) kill -0 "$1" 2>/dev/null && return 1
           case "$(kill -0 "$1" 2>&1)" in *ermitted*) return 1 ;; esac
           return 0 ;;
    esac
}

# aw_lock_place <staged folder> <lock dir> <holder file>: 0 once the staged folder is the lock.
aw_lock_place() {
    if command -v perl >/dev/null 2>&1; then
        perl -e 'rename $ARGV[0], $ARGV[1] or exit 1' "$1" "$2" 2>/dev/null
    else
        mkdir "$2" 2>/dev/null || return 1
        mv "$1/$3" "$2/$3" && rmdir "$1"
    fi
}

# aw_lock <lock dir>: 0 once the lock is held; 1, with the holder named on stderr, after AW_LOCK_WAIT
# seconds of a holder that is alive.
aw_lock() {
    local l="$1" n=0 tries id f pid host since start stage hstart
    tries=$(( ${AW_LOCK_WAIT:-10} * 10 ))
    id="$$.$RANDOM$RANDOM"
    stage="$l.$id"
    mkdir "$stage" || return 1
    start="$(aw_proc_start "$$")"
    printf '%s\n%s\n%s\n%s\n' "$$" "$HOSTNAME" "$(date +%s)" "$start" > "$stage/h.$id"
    # shellcheck disable=SC2064
    trap "rm -f '$stage/h.$id'; rmdir '$stage' 2>/dev/null" EXIT
    until aw_lock_place "$stage" "$l" "h.$id"; do
        pid="" host="" since="" hstart=""
        for f in "$l"/h.*; do break; done
        if [ -f "$f" ]; then
            { read -r pid; read -r host; read -r since; read -r hstart; } 2>/dev/null < "$f"
            if aw_lock_dead "$pid" "$host" "$hstart"; then
                rm "$f" 2>/dev/null && rmdir "$l" 2>/dev/null
                continue
            fi
        elif [ -f "$l/pid" ]; then
            # A lock left by the kit before 3.6.1: a pid file, and no start time to check.
            read -r pid 2>/dev/null < "$l/pid"; host="$HOSTNAME"
            if aw_lock_dead "$pid" "$host" ""; then rm -rf "$l"; continue; fi
        fi
        n=$((n + 1))
        if [ "$n" -ge "$tries" ]; then
            if [ -n "$pid" ]; then
                case "$since" in ''|*[!0-9]*) since="" ;; *) since=", since $(( $(date +%s) - since )) seconds ago" ;; esac
                printf 'lock: gave up on %s: process %s on %s holds it%s and is still running\n' \
                    "$l" "$pid" "${host:-this host}" "$since" >&2
            else
                printf 'lock: gave up on %s: it names no holder; if nothing is using it, remove it\n' "$l" >&2
            fi
            rm -f "$stage/h.$id"; rmdir "$stage" 2>/dev/null; trap - EXIT
            return 1
        fi
        sleep 0.1
    done
    # The time the lock was taken, for a waiter's message, rather than the time this one began to wait.
    since="$(date +%s)"
    printf '%s\n%s\n%s\n%s\n' "$$" "$HOSTNAME" "$since" "$start" > "$l/h.$id"
    _aw_lock_id="$id"
    # shellcheck disable=SC2064
    trap "rm -f '$l/h.$id'; rmdir '$l' 2>/dev/null" EXIT
}

# aw_unlock <lock dir>
aw_unlock() { rm -f "$1/h.${_aw_lock_id:-}"; rmdir "$1" 2>/dev/null; trap - EXIT; }

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
