# shellcheck shell=bash
# The setup wizard's screen library. setup.sh sources it above its stages; on its own it defines
# functions and a few variables and does nothing else.
#
# The shape follows the wizard pattern in mattpocock/skills (MIT): a fixed library, then one stage per
# screen for each step a person has to take themselves. What a stage asks is offered with a default;
# what a stage checks is read from the state check (plugins/workspace/bin/state.sh), so a re-run skips
# what is already done, and Ctrl-C then running it again is the way back.
#
# Two ways to run:
#   attended    a person at a terminal. Each stage starts on a clear screen headed "Stage n of N", a
#               question shows its default in [brackets], and a stage ends with a pause for Enter.
#   unattended  AW_WIZARD_NONINTERACTIVE=1, or no terminal on stdin. Every question takes its default,
#               pause and confirm return at once, and a stage only a person can do is recorded as
#               skipped rather than waited on. The test suite drives the wizard this way.
#
# Written for bash 3.2 (macOS): no associative arrays, no ${x,,}, no read -i, and empty arrays are
# expanded with ${a[@]+"${a[@]}"} so set -u does not stop on them.

WZ_UNATTENDED=0
if [[ "${AW_WIZARD_NONINTERACTIVE:-0}" == 1 || ! -t 0 ]]; then WZ_UNATTENDED=1; fi
# Screen control only when a person is watching a terminal; a log or a test sees plain lines.
WZ_TTY=0
if [[ $WZ_UNATTENDED -eq 0 && -t 1 ]]; then WZ_TTY=1; fi
WZ_N=0 WZ_TOTAL=0 WZ_TITLE=""
WZ_SUMMARY=()        # one line per stage reached: "n. Title: outcome"
WZ_STATE=""          # the last state check's output, key=value lines
WZ_STATE_SH=""       # set by the stages file: the path to state.sh

attended() { [[ $WZ_UNATTENDED -eq 0 ]]; }
bold() { if [[ $WZ_TTY -eq 1 ]]; then printf '\033[1m%s\033[0m' "$1"; else printf '%s' "$1"; fi; }

say()  { printf '%s\n' "$*"; }
# step: something for the person to do. note: something worth knowing. warn: something that is off.
step() { printf '  %s\n' "$*"; }
note() { printf '  - %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }

banner() { echo; bold "$1"; echo; [[ -z "${2:-}" ]] || say "$2"; }

# stage <n> <total> <title>: a fresh screen for one stage.
stage() {
    WZ_N="$1" WZ_TOTAL="$2" WZ_TITLE="$3"
    [[ $WZ_TTY -eq 0 ]] || printf '\033[2J\033[H'
    echo; bold "Stage $1 of $2 · $3"; echo; echo
}

# outcome <word> [detail]: how the stage ended — done, already done, skipped, left open or stopped. It
# goes into the summary the last stage prints; an attended run then waits before clearing the screen.
outcome() {
    local o="$1${2:+ ($2)}"
    WZ_SUMMARY+=("$WZ_N. $WZ_TITLE: $o")
    echo; say "  -> $o"
    if attended && [[ "$1" != stopped && $WZ_N -lt $WZ_TOTAL ]]; then pause "Press Enter for stage $((WZ_N + 1))."; fi
    return 0
}

# ask <question> [default]: the answer on stdout. Enter takes the default; so does an unattended run,
# which also writes the question and the answer taken to stderr, so a log shows what was chosen.
ask() {
    local reply=""
    if attended; then
        read -r -p "  $1${2:+ [$2]}: " reply || true
    else
        printf '  %s: %s\n' "$1" "${2:-(none)}" >&2
    fi
    printf '%s' "${reply:-${2:-}}"
}

# confirm <question> [y|n]: success for yes. The default (n unless given) is what Enter and an
# unattended run take, so anything irreversible asks with n.
confirm() {
    case "$(ask "$1 (y/n)" "${2:-n}")" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

pause() {
    attended || return 0
    read -r -p "  ${1:-Press Enter to go on.} " _ || true
}

# open_path <file-or-url>: in the default app where the system has an opener; otherwise the path is
# printed for the person to open. Nothing is opened in an unattended run.
open_path() {
    attended || return 0
    if [[ "$(uname -s)" == Darwin ]] && command -v open >/dev/null 2>&1; then open "$1"
    elif command -v wslview >/dev/null 2>&1; then wslview "$1"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1 &
    else step "Open: $1"; fi
}

# state_check <dir>: run the state check on dir and keep its report for state_key. A folder that does
# not exist yet leaves the report empty, so every key reads empty.
state_check() {
    WZ_STATE=""
    [[ -d "$1" ]] || return 0
    WZ_STATE="$("${BASH:-bash}" "$WZ_STATE_SH" --target "$1" 2>/dev/null)"
}
state_key() { printf '%s\n' "$WZ_STATE" | sed -n "s/^$1=//p" | head -n 1; }
key_is()  { [[ "$(state_key "$1")" == "$2" ]]; }
key_not() { [[ "$(state_key "$1")" != "$2" ]]; }

# check <label> <command...>: a ✓ line when the command succeeds, a ✗ line when it does not, and the
# command's status returned, so a stage can follow a ✗ with what to do about it.
check() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then printf '  ✓ %s\n' "$label"; return 0; fi
    printf '  ✗ %s\n' "$label"; return 1
}

# finish: every stage reached and how it ended.
finish() {
    say "Stages"
    printf '  %s\n' ${WZ_SUMMARY[@]+"${WZ_SUMMARY[@]}"}
}

# Ctrl-C is the back button: say where the run stopped, and that a re-run picks up from there.
trap 'echo; echo; say "Stopped at stage $WZ_N. Run setup.sh again: stages already done are skipped."; exit 130' INT
