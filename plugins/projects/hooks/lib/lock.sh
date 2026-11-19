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
# without its holder's file, and an empty folder (a holder that has let go) is simply taken. Without
# perl or python3, which make the rename, the folder is made first and the file moved in.
#
# Why two writers cannot both hold it. A lock folder holding a file can only be replaced by nothing:
# the rename onto it fails. Its file is taken out by exactly one process: the holder letting go, or
# the one waiter that wins a takeover. Each holder's file has a name of its own, and taking a file out
# succeeds once, so a waiter that read a holder which has since let go cannot take the next holder's
# file. The lock folder itself is only ever removed with rmdir, which fails on a folder that holds a
# file, and never renamed away, so nothing can carry off a live holder's lock with it.
#
# Letting go needs no removal. A file is "taken out" by removing it where the shell can, and
# elsewhere by renaming it into .aw-gone/ beside it (aw_discard). Some mounts let a shell make and
# rename files but not remove them: Cowork's Linux shell on a connected folder, until the folder is
# given delete permission. There a holder lets go by renaming its file away, which leaves the lock
# folder empty, and the next writer's rename takes the empty folder. The next shell that can remove
# files there sweeps .aw-gone/. Only a shell that can neither remove nor rename beside the lock is
# turned away (status 2), before it takes anything, by a probe file it makes and takes out first.
#
# A lock is taken over only when its holder is not running. On the same host, that is no process with
# that id, or one that started at a different time (the id has been reused), and a holder that is
# alive keeps its lock however long it takes, so a clock that steps forward cannot cost it the lock. A
# host is the machine and, on Linux, its boot and process-id namespace (aw_host): Cowork's sessions
# share one host name, and each counts its process ids from its own namespace. A holder on another
# host cannot be checked, so its lock is taken over by age: once the later of the time it records and
# its file's own time is AW_LOCK_STALE seconds old (120 by default). The lock guards edits to small
# files that take milliseconds, so a holder that old has stopped; a lock that cannot be let go, such
# as one whose process was killed, is cleared that way without anyone's hands. A waiter that has
# waited AW_LOCK_WAIT seconds (10 by default) gives up and says who holds it, and when it may be taken.
#
# The holder lets go from an exit trap too, so a script that stops part way still lets go.
#
# The change itself is written to a temporary file, then renamed into place, so a reader sees the old
# file or the new one and never a part. The lock only orders the writers.
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

# aw_host: where a process id means one process: the host name and, on Linux, the boot and the
# process-id namespace, since containers and virtual machines share host names (Cowork's are all
# "claude") while each counts its own ids.
aw_host() {
    local b n
    if [ -z "${_aw_host:-}" ]; then
        _aw_host="$HOSTNAME"
        if [ -r /proc/sys/kernel/random/boot_id ]; then
            read -r b 2>/dev/null < /proc/sys/kernel/random/boot_id
            n="$(readlink /proc/self/ns/pid 2>/dev/null)"; n="${n#pid:[}"; n="${n%]}"
            _aw_host="$HOSTNAME/${b%%-*}${n:+/$n}"
        fi
    fi
    printf '%s' "$_aw_host"
}

# aw_lock_age <holder file> <since>: seconds since the later of the time the holder recorded and its
# file's last write.
aw_lock_age() {
    local m s="$2"
    m="$(stat -f %m "$1" 2>/dev/null)"
    case "$m" in ''|*[!0-9]*) m="$(stat -c %Y "$1" 2>/dev/null)" ;; esac
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    case "$s" in ''|*[!0-9]*) s=0 ;; esac
    [ "$s" -gt "$m" ] && m="$s"
    printf '%s\n' $(( $(date +%s) - m ))
}

# aw_lock_dead <pid> <host> <start> <since> <holder file>: 0 when that holder is certainly not running,
# or, on another host, its lock is older than AW_LOCK_STALE seconds.
aw_lock_dead() {
    local now rc
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$2" != "$(aw_host)" ]; then
        [ "$(aw_lock_age "$5" "$4")" -ge "${AW_LOCK_STALE:-120}" ]
        return
    fi
    now="$(aw_proc_start "$1")"; rc=$?
    case $rc in
        0) [ -n "$3" ] && [ "$now" != "$3" ] ;;
        1) return 0 ;;
        *) kill -0 "$1" 2>/dev/null && return 1
           case "$(kill -0 "$1" 2>&1)" in *ermitted*) return 1 ;; esac
           return 0 ;;
    esac
}

# aw_discard <path> [<dir>]: takes a file, or a folder and what it holds, out of its folder: removed
# where this shell can remove it, otherwise renamed into .aw-gone/ in <dir> (the path's own folder by
# default; a holder's file goes to the folder beside its lock, never into the lock). Status 0 only for
# the process that took it, so of two that try at once, one succeeds.
aw_discard() {
    local p="$1" g
    if [ -d "$p" ]; then
        rm -rf -- "$p" 2>/dev/null; [ -e "$p" ] || return 0
    else
        rm -- "$p" 2>/dev/null && return 0
        [ -e "$p" ] || return 1
    fi
    g="${2:-$(dirname "$p")}/.aw-gone"
    mkdir "$g" 2>/dev/null
    mv -- "$p" "$g/g.$$.$RANDOM$RANDOM.${p##*/}" 2>/dev/null
}

# aw_sweep <dir>: clears what aw_discard renamed away in <dir>, where this shell can remove files; quiet
# where it cannot. The folder itself stays, so a process renaming into it never finds it gone.
aw_sweep() { [ -d "$1/.aw-gone" ] && rm -rf "$1/.aw-gone"/g.* 2>/dev/null; return 0; }

# aw_lock_place <staged folder> <lock dir> <holder file>: 0 once the staged folder is the lock.
aw_lock_place() {
    if command -v perl >/dev/null 2>&1; then
        perl -e 'rename $ARGV[0], $ARGV[1] or exit 1' "$1" "$2" 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os, sys; os.rename(sys.argv[1], sys.argv[2])' "$1" "$2" 2>/dev/null
    else
        mkdir "$2" 2>/dev/null || return 1
        mv "$1/$3" "$2/$3" && aw_discard "$1"
    fi
}

# aw_can_let_go <dir>: 0 when this shell can make a file in <dir> and take it out again (remove it, or
# rename it away); 1 when it cannot make one, 2 when it cannot take it out. Asked once per folder per
# process. Each process probes with a file of its own, so two probing at once do not collide.
aw_can_let_go() {
    [ "${_aw_lets_go_in:-}" = "$1" ] && return 0
    { : > "$1/.aw-probe.$$"; } 2>/dev/null || return 1
    aw_discard "$1/.aw-probe.$$" || return 2
    _aw_lets_go_in="$1"
}

# aw_lock <lock dir>: 0 once the lock is held; 1, with the holder named on stderr, after AW_LOCK_WAIT
# seconds of a holder that is alive; 2, with the reason on stderr and nothing taken, where this shell
# cannot make files beside the lock and take them out again.
aw_lock() {
    local l="$1" n=0 tries id f pid host since start stage hstart d me age
    d="$(dirname "$l")"
    n=0; aw_can_let_go "$d" || n=$?
    if [ $n -ne 0 ]; then
        if [ $n -eq 2 ]; then
            printf 'lock: not taken: this shell can make files in %s but neither remove nor rename them, so a lock taken there could never be let go. Run this on the computer that holds the folder, or where files there can be removed.\n' "$d" >&2
        else
            printf 'lock: not taken: this shell cannot write in %s.\n' "$d" >&2
        fi
        return 2
    fi
    aw_sweep "$d"
    me="$(aw_host)"
    n=0
    tries=$(( ${AW_LOCK_WAIT:-10} * 10 ))
    id="$$.$RANDOM$RANDOM"
    stage="$l.$id"
    mkdir "$stage" 2>/dev/null || { printf 'lock: not taken: this shell cannot make a folder in %s.\n' "$d" >&2; return 2; }
    start="$(aw_proc_start "$$")"
    printf '%s\n%s\n%s\n%s\n' "$$" "$me" "$(date +%s)" "$start" > "$stage/h.$id"
    # shellcheck disable=SC2064
    trap "aw_discard '$stage'" EXIT
    until aw_lock_place "$stage" "$l" "h.$id"; do
        pid="" host="" since="" hstart=""
        for f in "$l"/h.*; do break; done
        if [ -f "$f" ]; then
            { read -r pid; read -r host; read -r since; read -r hstart; } 2>/dev/null < "$f"
            if aw_lock_dead "$pid" "$host" "$hstart" "$since" "$f"; then
                # Of two waiters, only the one that takes the file out goes on to clear the folder; rmdir
                # leaves alone a folder that a new holder has already taken.
                aw_discard "$f" "$d" && rmdir "$l" 2>/dev/null
                continue
            fi
        elif [ -f "$l/pid" ]; then
            # A lock left by the kit before 3.6.1: a pid file, and no start time to check.
            read -r pid 2>/dev/null < "$l/pid"; host="$me"
            if aw_lock_dead "$pid" "$host" "" "" "$l/pid"; then aw_discard "$l/pid" "$d" && rmdir "$l" 2>/dev/null; continue; fi
        elif [ -d "$l" ]; then
            # An empty folder, where nothing can rename onto it: cleared, then taken on the next pass.
            rmdir "$l" 2>/dev/null && continue
        fi
        n=$((n + 1))
        if [ "$n" -ge "$tries" ]; then
            if [ -n "$pid" ]; then
                case "$since" in ''|*[!0-9]*) since="" ;; *) since=", since $(( $(date +%s) - since )) seconds ago" ;; esac
                if [ -n "$host" ] && [ "$host" != "$me" ]; then
                    # Another host's process cannot be checked from here, so its lock goes by age.
                    age="$(aw_lock_age "$f" "")"
                    printf 'lock: gave up on %s: process %s on %s holds it%s. A process on another host cannot be checked from here, so the lock is taken over once it is %s seconds old, in %s seconds; run this again then.\n' \
                        "$l" "$pid" "$host" "$since" "${AW_LOCK_STALE:-120}" "$(( ${AW_LOCK_STALE:-120} - age ))" >&2
                else
                    printf 'lock: gave up on %s: process %s on %s holds it%s and is still running\n' \
                        "$l" "$pid" "${host:-this host}" "$since" >&2
                fi
            else
                printf 'lock: gave up on %s: it names no holder; if nothing is using it, remove it\n' "$l" >&2
            fi
            aw_discard "$stage"; trap - EXIT
            return 1
        fi
        sleep 0.1
    done
    # The time the lock was taken, for a waiter's message, rather than the time this one began to wait.
    since="$(date +%s)"
    printf '%s\n%s\n%s\n%s\n' "$$" "$me" "$since" "$start" > "$l/h.$id"
    _aw_lock_id="$id"
    # shellcheck disable=SC2064
    trap "aw_discard '$l/h.$id' '$d'; rmdir '$l' 2>/dev/null" EXIT
}

# aw_unlock <lock dir>: lets go. Where the holder's file cannot be taken out after all, it says so with
# status 1; the lock is then taken over once this process has ended, or by age from another host.
aw_unlock() {
    aw_discard "$1/h.${_aw_lock_id:-}" "$(dirname "$1")"; rmdir "$1" 2>/dev/null; trap - EXIT
    [ -e "$1/h.${_aw_lock_id:-}" ] || return 0
    printf 'lock: could not let go of %s; the next writer takes it over once this process has ended (from another host, once it is %s seconds old), or remove it by hand: rm -r %s\n' \
        "$1" "${AW_LOCK_STALE:-120}" "$(printf '%q' "$1")" >&2
    return 1
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
        aw_discard "$tmp"; aw_unlock "$f.lock"; return 1
    fi
    mv "$tmp" "$f" 2>/dev/null || { aw_discard "$tmp"; aw_unlock "$f.lock"; printf 'lock: could not replace %s; it is as it was\n' "$f" >&2; return 1; }
    aw_unlock "$f.lock"
}
