# shellcheck shell=bash
# The parts use what is defined here (SC2034); the prelude defines KIT and the rest (SC2154).
# shellcheck disable=SC2154,SC2034
# Section 15's shared helpers, sourced by each of its parts (tests/sections/15a-setup.sh, 15b and 15c).
# Section 15: kit/setup.sh — the ten stages, new and adopt, the dispatch table, update, --developer,
# hooks, and scripts/build-template.sh. It runs as three parts, each its own parallel job; every name
# carries the s15_ prefix, and everything is written under $SCRATCH.
#
# Some checks need other components (the engine, the state keys, the git hooks). While one of those
# is still a placeholder, the check that needs it is a SKIP naming it; the rest run on their own.

s15_setup="$KIT/setup.sh"
s15_files=(setup.sh lib/wizard.sh lib/setup/update.sh lib/setup/developer.sh scripts/build-template.sh)
# s15_built <kit path>: the file is there and is not a wave-0 placeholder.
s15_built() { [[ -f "$KIT/$1" ]] && ! grep -q 'not built yet' "$KIT/$1" 2>/dev/null; }
# s15_need <component...>: 0 when every named component is built; otherwise s15_why names the missing.
s15_need() {
    local c; s15_why=""
    for c in "$@"; do
        case "$c" in
            engine) grep -q -- '--template-status' "$KIT/install.sh" 2>/dev/null || s15_why+="the 3.0 engine (install.sh, C2), " ;;
            state) grep -q 'kit_import' "$STATE" 2>/dev/null || s15_why+="the 3.0 state keys (state.sh, C4), " ;;
            hooks) { s15_built lib/setup/gitconfig.sh && s15_built githooks/pre-push; } || s15_why+="the git hooks (gitconfig.sh and githooks, C1), " ;;
            migrate) s15_built lib/setup/migrate.sh || s15_why+="the migration (migrate.sh, C8), " ;;
            session) s15_built plugins/workspace/hooks/session-start.sh || s15_why+="the session-start hook (C4), " ;;
            link) s15_built lib/setup/link.sh || s15_why+="the resource links (link.sh, C6), " ;;
            bridge) s15_built scripts/skills-bridge.sh || s15_why+="the skills bridge (skills-bridge.sh, C7), " ;;
            kitsrc) [[ $kitsrc_ok -eq 1 ]] || s15_why+="KITSRC (the kit is not a git checkout), " ;;
            mkws2x) git --no-optional-locks -C "$KIT" cat-file -e '915c528^{commit}' 2>/dev/null || s15_why+="915c528 (a shallow clone), " ;;
        esac
    done
    s15_why="${s15_why%, }"
    [[ -z "$s15_why" ]]
}
# s15_outcome <log> <n>: how stage n ended, from the summary the finish stage prints.
s15_outcome() { sed -n "s/^  $2\. [^:]*: //p" "$1" | tail -n 1; }
# s15_is <got> <want>: the outcome word matches, with or without its detail.
s15_is() { [[ "$1" == "$2" || "$1" == "$2 ("* ]]; }
# s15_wz <log> <args...>: setup.sh unattended from $SCRATCH (so the target comes from the arguments or
# the superproject, never the runner's folder), with the kit added from KITSRC unless AW_KIT_URL is set.
s15_wz() {
    local log="$1"; shift
    (cd "$SCRATCH" && AW_KIT_URL="${S15_KIT_URL:-$KITSRC}" AW_WIZARD_NONINTERACTIVE=1 "$st_bash" "$@" </dev/null >"$log" 2>&1)
}
s15_real() { (cd "$1" && pwd -P); }
