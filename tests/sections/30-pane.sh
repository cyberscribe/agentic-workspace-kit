# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh (SC2154); checks are "cond && ok || ko"
# (SC2015); single-quoted strings hold literal escape sequences (SC2016).
# shellcheck disable=SC2154,SC2015,SC2016
# Section 30: the scheduler pane driven as a person drives it. Always: the frame reader the harness judges
# with (tests/pane/frame.pl), on hand-written frames, so a change to how it reads a screen is caught here.
# With AW_TEST_PANE=1 (and tmux and a signed-in claude): tests/pane/harness.sh on a grid of fixtures, sizes
# and modes, every rule it checks reported as a line here. It drives real Claude Code sessions in detached
# tmux, so it is opt-in, and it reaches only scratch schedulers (the harness's wrapper sees to that).
# Everything here is prefixed s30_, since the sections share one shell.
echo
echo "30 · The scheduler pane, as a person drives it"

s30="$SCRATCH/s30"
mkdir -p "$s30"
s30_read() { perl "$KIT/tests/pane/frame.pl" "$1" <"$2" | sed -n "s/^$3=//p"; }

# An inline pane at 40 columns: its top frame from column 0 to the last, the ring (inverse) on a row, that
# row in bold, and the key line.
printf '%s\n' \
    'some conversation' \
    '╭────────────────────────────────────✕─╮' \
    $'│ \e[1;7m1: task-01   weekdays 07:30\e[0m         │' \
    '│ 2: task-02   weekdays 08:00          │' \
    '│ ↑↓ select · Enter open · Esc close   │' \
    '╰──────────────────────────────────────╯' >"$s30/inline.ansi"
s30_bad=""
[[ "$(s30_read 40 "$s30/inline.ansi" open)" == 1 ]] || s30_bad+="inline: not read as open"$'\n'
[[ "$(s30_read 40 "$s30/inline.ansi" ring)" == "1: task-01   weekdays 07:30" ]] || s30_bad+="inline: ring '$(s30_read 40 "$s30/inline.ansi" ring)'"$'\n'
[[ "$(s30_read 40 "$s30/inline.ansi" bold)" == *"task-01"* ]] || s30_bad+="inline: bold '$(s30_read 40 "$s30/inline.ansi" bold)'"$'\n'
[[ "$(s30_read 40 "$s30/inline.ansi" hint)" == "↑↓ select · Enter open · Esc close" ]] || s30_bad+="inline: hint '$(s30_read 40 "$s30/inline.ansi" hint)'"$'\n'
[[ "$(s30_read 40 "$s30/inline.ansi" top)" == 0 && "$(s30_read 40 "$s30/inline.ansi" topend)" == 39 && "$(s30_read 40 "$s30/inline.ansi" dock)" == 0 ]] \
    || s30_bad+="inline: top $(s30_read 40 "$s30/inline.ansi" top) to $(s30_read 40 "$s30/inline.ansi" topend), dock $(s30_read 40 "$s30/inline.ansi" dock)"$'\n'
empty "30 frame reader: an inline pane is open, full width, with its ring, bold row and key line" "$s30_bad"

# A docked pane beside the conversation: no rounded top, the close mark on its first row, and a key line
# read from the pane's side of the rule, not the conversation's.
printf '%s\n' \
    'the conversation says Esc close here   │                    ✕' \
    'more of the conversation               │1: task-01' \
    'and more                               │↑↓ select · Esc close' >"$s30/dock.ansi"
s30_bad=""
[[ "$(s30_read 62 "$s30/dock.ansi" dock)" == 1 ]] || s30_bad+="dock: not read as docked"$'\n'
[[ "$(s30_read 62 "$s30/dock.ansi" hint)" == "↑↓ select · Esc close" ]] || s30_bad+="dock: hint '$(s30_read 62 "$s30/dock.ansi" hint)'"$'\n'
empty "30 frame reader: a docked pane is read as docked, its key line from its own side" "$s30_bad"

# No pane: nothing open, no ring.
printf '%s\n' '❯ ' '  ⏵⏵ auto mode on' >"$s30/none.ansi"
[[ "$(s30_read 80 "$s30/none.ansi" open)" == 0 && -z "$(s30_read 80 "$s30/none.ansi" ring)" ]] \
    && ok "30 frame reader: with no pane, nothing is open and there is no ring" \
    || ko "30 frame reader: with no pane, nothing is open and there is no ring"

check "30 shellcheck: the harness" shellcheck -x "$KIT/tests/pane/harness.sh"

# The live grid, opt-in. AW_PANE_GRID narrows it: "fixtures|sizes|modes|seeds|keys".
if [[ "${AW_TEST_PANE:-}" != 1 ]]; then
    skp "30 the pane driven live in tmux (AW_TEST_PANE=1, needs tmux and a signed-in claude)"
elif ! command -v tmux >/dev/null 2>&1 || ! command -v claude >/dev/null 2>&1; then
    ko "30 the pane driven live in tmux" "AW_TEST_PANE=1, and tmux or claude is not on PATH"
else
    IFS='|' read -r s30_fx s30_sz s30_md s30_sd s30_ky <<<"${AW_PANE_GRID:-3 20|80x24 170x40|classic fullscreen|1|100}"
    bash "$KIT/tests/pane/harness.sh" --out "$s30/live" --fixtures "$s30_fx" --sizes "$s30_sz" --modes "$s30_md" \
        --seeds "$s30_sd" --keys "$s30_ky" --no-turn --jobs "${AW_PANE_JOBS:-4}" >"$s30/live.out" 2>&1
    while IFS=$'\t' read -r s30_cell s30_rule s30_res s30_detail; do
        case "$s30_res" in
            pass) ok "30 $s30_cell $s30_rule" ;;
            fail) ko "30 $s30_cell $s30_rule" "$s30_detail" ;;
        esac
    done <"$s30/live/results.tsv"
fi
