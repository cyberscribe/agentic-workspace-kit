#!/usr/bin/env bash
# Backticks in the single-quoted printf, awk and jq text below are literal markdown, not expansions.
# shellcheck disable=SC2016
#
# install.sh: the engine behind kit/setup.sh. It creates the files a workspace owns, once each, from
# the templates in the kit checkout the workspace pins (kit/), and records each one in
# .claude/kit-templates.lock with the kit commit and a hash of what it rendered. From then on the file
# is the person's: the engine never writes beside it or over it. It maintains two things afterwards,
# the marketplace path in .claude/settings.json and the .gitignore lines, and it answers the questions
# kit/setup.sh update asks: has a template changed since a file was made, and what is the change as a
# diff the person can apply.
#
# The guided path is kit/setup.sh; this script is what it runs. The forms:
#
#   install.sh --target WS [--kit REL] [--team NAME] [--owner NAME] [--owner-handle @h] [--pilot]
#              [--cowork] [--surfaces claude|claude,gemini] [--gitignore merge|offer|report]
#              [--dry-run] [--init]
#   install.sh --stand-ins --target OUT [--kit REL]
#   install.sh --skills-only --skills-dir DIR [--skills-prefix PFX] [--skills-skip LIST] [--target WS]
#              [--plugin-src DIR] [--dry-run]
#   install.sh --template-status --target WS
#   install.sh --template-diff DEST --target WS
#   install.sh --template-record DEST --status accepted|skipped --target WS
#   install.sh --gitignore-decline LINE --target WS
#
# Exit codes: 0 ok; 1 a precondition or a write failed; 2 a usage error. --template-diff exits 1 when
# the old template cannot be recovered and 3 when the diff is empty; --gitignore offer exits 3 when no
# line is missing.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
. "$SELF_DIR/lib/common.sh"
# shellcheck source=lib/templates.sh
. "$SELF_DIR/lib/templates.sh"

# The engine always names its repository explicitly; a GIT_DIR inherited from a hook or a wrapper
# would point every git call at the wrong one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX

usage() {
    cat <<'USAGE'
install.sh — the engine behind kit/setup.sh. It creates the files a workspace owns, once each, from
the templates in its kit checkout, and records them in .claude/kit-templates.lock.

  install.sh --target WS [--kit REL] [--team NAME] [--owner NAME] [--owner-handle @h] [--pilot]
             [--cowork] [--surfaces claude|claude,gemini] [--gitignore merge|offer|report]
             [--dry-run] [--init]
      Create the workspace's own files that are missing, keep the ones already there, and report.
      --kit REL        where the kit sits inside WS (default kit); every template is read from there
      --gitignore      merge: add the template's missing lines; offer: print them as a diff and
                       write nothing; report: list them (the default, except with --init or when
                       CLAUDE.md is created in this run, which merge)
      --init           git init WS when it is not a repository yet
      --dry-run        say what would happen, write nothing

  install.sh --stand-ins --target OUT [--kit REL]
      Render every file with the stand-in values into OUT, with no ledger (the template repository).

  install.sh --skills-only --skills-dir DIR [--skills-prefix PFX] [--skills-skip LIST] [--target WS]
             [--plugin-src DIR] [--dry-run]
      One skill per kit command, for a surface that loads skills from a folder.

  install.sh --template-status --target WS
  install.sh --template-diff DEST --target WS
  install.sh --template-record DEST --status accepted|skipped --target WS
  install.sh --gitignore-decline LINE --target WS
      The questions kit/setup.sh update asks, one per form.

The guided path is kit/setup.sh.
USAGE
}

usage_error() {
    printf 'install.sh: %s\n' "$1" >&2
    printf 'install.sh --help lists the forms it takes. The guided path is kit/setup.sh.\n' >&2
    exit 2
}
die() { printf 'install.sh: %s\n' "$1" >&2; exit 1; }

if [[ $# -eq 0 ]]; then usage >&2; exit 2; fi

MODE=install
TARGET="" REL="kit" TEAM="" OWNER="" HANDLE="" PILOT=0 COWORK=0 SURFACES="" GI_MODE="" DRY=0 INIT=0
SKILLS_DIR="" SKILLS_PREFIX="" SKILLS_SKIP="" PLUGIN_SRC="" ARG_DEST="" REC_STATUS="" DECLINE=""
# An option's value may be empty (setup passes an unanswered question through as ""); an empty path is
# caught where the path is used.
need() { [[ $# -ge 2 ]] || usage_error "$1 needs a value"; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) need "$@"; TARGET="$2"; shift 2 ;;
        --kit) need "$@"; REL="$2"; shift 2 ;;
        --team) need "$@"; TEAM="$2"; shift 2 ;;
        --owner) need "$@"; OWNER="$2"; shift 2 ;;
        --owner-handle) need "$@"; HANDLE="$2"; shift 2 ;;
        --pilot) PILOT=1; shift ;;
        --cowork) COWORK=1; shift ;;
        --surfaces) need "$@"; SURFACES="$2"; shift 2 ;;
        --gitignore) need "$@"; GI_MODE="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        --init) INIT=1; shift ;;
        --stand-ins) MODE=standins; shift ;;
        --skills-only) MODE=skills; shift ;;
        --skills-dir) need "$@"; SKILLS_DIR="$2"; shift 2 ;;
        --skills-prefix) need "$@"; SKILLS_PREFIX="$2"; shift 2 ;;
        --skills-skip) [[ $# -ge 2 ]] || usage_error "--skills-skip needs a value"; SKILLS_SKIP="$2"; shift 2 ;;
        --plugin-src) need "$@"; PLUGIN_SRC="$2"; shift 2 ;;
        --template-status) MODE=status; shift ;;
        --template-diff) need "$@"; MODE="diff"; ARG_DEST="$2"; shift 2 ;;
        --template-record) need "$@"; MODE=record; ARG_DEST="$2"; shift 2 ;;
        --status) need "$@"; REC_STATUS="$2"; shift 2 ;;
        --gitignore-decline) [[ $# -ge 2 ]] || usage_error "--gitignore-decline needs a line"; MODE=decline; DECLINE="$2"; shift 2 ;;
        --plugin) usage_error "--plugin was retired in 3.0: the plugins are read in place from kit/" ;;
        --interactive) usage_error "--interactive was retired in 3.0" ;;
        -h|--help) usage; exit 0 ;;
        *) usage_error "unknown option: $1" ;;
    esac
done

# Options that belong to one form only.
[[ -z "$SKILLS_DIR" || $MODE == skills ]] || usage_error "--skills-dir goes with --skills-only; a workspace's skills bridge is kit/setup.sh skills"
[[ -z "$PLUGIN_SRC" || $MODE == skills ]] || usage_error "--plugin-src goes with --skills-only; an install reads the plugins in place from kit/"
[[ -z "$SKILLS_PREFIX$SKILLS_SKIP" || $MODE == skills ]] || usage_error "--skills-prefix and --skills-skip go with --skills-only"
[[ -z "$REC_STATUS" || $MODE == record ]] || usage_error "--status goes with --template-record"
case "$GI_MODE" in ''|merge|offer|report) ;; *) usage_error "--gitignore takes merge, offer or report" ;; esac
REL="${REL%/}"; REL="${REL:-kit}"
case "$REL" in /*|*..*) usage_error "--kit takes a path inside the workspace, such as kit" ;; esac

# A value goes into a tab-separated ledger line and into markdown, so tabs and newlines become spaces.
clean() { printf '%s' "$1" | tr '\t\r\n' '   '; }
TEAM="$(clean "$TEAM")" OWNER="$(clean "$OWNER")" HANDLE="$(clean "$HANDLE")"

# Surfaces: claude, or claude with gemini (parked, still generated on request). "both" reads as the two.
if [[ -n "$SURFACES" ]]; then
    SURFACES="$(printf '%s' "$SURFACES" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
    [[ "$SURFACES" != both ]] || SURFACES="claude,gemini"
    for s in ${SURFACES//,/ }; do
        [[ "$s" == claude || "$s" == gemini ]] || usage_error "--surfaces takes claude or claude,gemini (got '$s')"
    done
    [[ ",$SURFACES," == *",claude,"* ]] || usage_error "--surfaces takes claude or claude,gemini: a workspace is always set up for Claude Code"
fi

TODAY="$(date +%F)"
work="$(mktemp -d "${TMPDIR:-/tmp}/aw-install.XXXXXX")" || die "cannot make a temporary folder under ${TMPDIR:-/tmp}"
trap 'rm -rf "$work"' EXIT

# Report buckets. Items are paths, except under "Worth knowing" and "Added to .gitignore".
r_created=() r_merged=() r_gitignore=() r_regen=() r_same=() r_kept=() r_changed=() r_notes=()

# ---- The skills generator (--skills-only; and the Gemini CLI wrappers of a gemini install) ----------
#
# Each plugins/<plugin>/commands/<command>.md is the one source of its procedure; every other surface
# gets a thin generated form of it, never a copy to edit. A command named after its own plugin is not
# namespaced (closeout's is /closeout everywhere); the rest are <plugin> then <command>.
#   gemini   .gemini/commands/<plugin>/<command>.toml: the description, and the body as the prompt.
#   skills   <skills dir>/<prefix><name>/SKILL.md, a thin pointer at the command file with a
#            description that says when to offer it, and procedure.md beside it, the body as it stands.
# A generated file carries a marker naming its source, so a changed command replaces it; a file at
# that path without the marker is someone's own and is left alone.

GEN_MARK='Generated by install.sh from plugins/'

fm_body() { awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } !fm' "$1"; }
fm_field() { awk -v k="$2" 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { exit } fm && index($0, k ":") == 1 { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' "$1"; }

# place_generated <content file> <dest, absolute> <label for the report>
place_generated() {
    local src="$1" dest="$2" label="$3" mark
    mark="$dest"; [[ "$(basename "$dest")" != procedure.md ]] || mark="$(dirname "$dest")/SKILL.md"
    if [[ ! -e "$dest" ]]; then
        r_created+=("$label")
        [[ $DRY -eq 1 ]] || { mkdir -p "$(dirname "$dest")" && cat "$src" > "$dest"; } || die "cannot write $dest"
    elif cmp -s "$src" "$dest"; then
        r_same+=("$label")
    elif grep -qs "$GEN_MARK" "$mark"; then
        r_regen+=("$label")
        [[ $DRY -eq 1 ]] || cat "$src" > "$dest" || die "cannot write $dest"
    else
        r_kept+=("$label")
    fi
}

skip_listed() { # <name without prefix>: 0 when --skills-skip names it, with or without the prefix
    local item
    for item in $(printf '%s' "$SKILLS_SKIP" | tr ',' ' '); do
        [[ "$item" == "$1" || "$item" == "$SKILLS_PREFIX$1" ]] && return 0
    done
    return 1
}

generate_commands() { # <format> <plugins dir> <repository root, resolved>
    local fmt="$1" psrc="$2" root="$3" src plugin cmd ns desc offer t tp dest name base ptr p lab
    for src in "$psrc"/*/commands/*.md; do
        [[ -f "$src" ]] || continue
        plugin="$(basename "$(dirname "$(dirname "$src")")")" cmd="$(basename "$src" .md)"
        ns="$plugin"; [[ "$plugin" == "$cmd" ]] && ns=""
        desc="$(fm_field "$src" description)"
        [[ -n "$desc" ]] || die "no description in the front matter of $src"
        offer="$(fm_field "$src" offer-unprompted)"
        t="$work/gen"
        case "$fmt" in
            gemini)
                dest="$root/.gemini/commands/${ns:+$ns/}$cmd.toml" lab=".gemini/commands/${ns:+$ns/}$cmd.toml"
                # A TOML literal string cannot hold three single quotes, and Gemini CLI would run !{...}
                # and expand @{...} rather than pass them through as text.
                if fm_body "$src" | grep -qE "'''|[!@][{]"; then
                    die "$src contains ''', !{ or @{, which a Gemini CLI command cannot carry as written"
                fi
                {
                    printf '# %s%s/commands/%s.md: edit that file, then re-run the installer.\n' "$GEN_MARK" "$plugin" "$cmd"
                    printf 'description = "%s"\n' "$(printf '%s' "$desc" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
                    printf "prompt = '''\n"
                    fm_body "$src"
                    printf "'''\n"
                } > "$t"
                place_generated "$t" "$dest" "$lab" ;;
            skills)
                base="${ns:+$ns-}$cmd" name="$SKILLS_PREFIX${ns:+$ns-}$cmd"
                if skip_listed "$base"; then r_notes+=("not generated: $name (--skills-skip)"); continue; fi
                # Where the skill points, as a path from the repository root: the command file itself when
                # the kit is inside the repository; otherwise procedure.md beside the skill is the whole of it.
                ptr="" p="$(cd "$(dirname "$src")" 2>/dev/null && pwd -P)/$cmd.md"
                case "$p" in "$root"/*) ptr="${p#"$root"/}" ;; esac
                desc="${desc%.}. The kit's /${ns:+$ns:}$cmd command, as a skill.${offer:+ $offer}"
                {
                    printf -- '---\nname: %s\n' "$name"
                    printf 'description: "%s"\n---\n\n' "$(printf '%s' "$desc" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
                    printf '<!-- %s%s/commands/%s.md: edit that file, then re-run the installer. -->\n\n' "$GEN_MARK" "$plugin" "$cmd"
                    printf '# %s\n\n' "$name"
                    printf "This is the kit's \`/%s\` command as a skill, for an assistant that loads skills from a folder\n" "${ns:+$ns:}$cmd"
                    printf 'rather than plugins. Its procedure has one source, and this skill points at it.\n\n'
                    if [[ -n "$ptr" ]]; then
                        printf 'Follow the procedure in `%s` in this repository, reading it in full\n' "$ptr"
                        printf 'before acting. When that file cannot be reached from here, follow `procedure.md` beside\n'
                        printf 'this file instead: the same procedure, copied from it when this skill was generated.\n\n'
                    else
                        printf 'Follow the procedure in `procedure.md` beside this file, reading it in full before acting:\n'
                        printf "it is the kit's \`plugins/%s/commands/%s.md\`, copied when this skill was generated.\n\n" "$plugin" "$cmd"
                    fi
                    printf 'Where the procedure speaks of what the user typed after the command, read it as what the\n'
                    printf 'person asked for in their message. Where it names another kit command (`/projects:new`,\n'
                    if [[ -n "$SKILLS_PREFIX" ]]; then
                        printf '`/workspace:hygiene`, `/closeout`), that is the skill of that name joined by hyphens, with the\n'
                        printf '`%s` prefix (`%sprojects-new`, `%sworkspace-hygiene`, `%scloseout`): name it that way.\n' \
                            "$SKILLS_PREFIX" "$SKILLS_PREFIX" "$SKILLS_PREFIX" "$SKILLS_PREFIX"
                    else
                        printf '`/workspace:hygiene`, `/closeout`), that is the skill of the same name joined by a hyphen\n'
                        printf 'here (`projects-new`, `workspace-hygiene`, `closeout`): name it that way to the person.\n'
                    fi
                    printf 'This surface runs no session hooks, so anything the procedure leaves to a hook is offered\n'
                    printf 'in words instead. If it cannot read the repository'"'"'s files, say so first and ask the person\n'
                    printf 'to share the ones the procedure reads; if it cannot write them, give each change as the\n'
                    printf 'exact text to paste and the path it goes to, and make nothing else up.\n'
                } > "$t"
                tp="$work/gen-procedure"
                fm_body "$src" > "$tp"
                place_generated "$tp" "$SKILLS_DIR/$name/procedure.md" "$SKILLS_DIR/$name/procedure.md"
                place_generated "$t" "$SKILLS_DIR/$name/SKILL.md" "$SKILLS_DIR/$name/SKILL.md" ;;
            *) die "generate_commands: no output format called $fmt" ;;
        esac
    done
}

# stale_generated <plugins dir> <root>: a generated file whose source command the kit no longer has is
# named under "Worth knowing" as one to delete. Nothing is deleted here.
stale_generated() {
    local psrc="$1" root="$2" f rel
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        rel="$(sed -n 's/.*Generated by install\.sh from plugins\/\([^:]*\.md\):.*/\1/p' "$f" | head -n 1)"
        [[ -n "$rel" && ! -f "$psrc/$rel" ]] || continue
        case "$f" in
            */SKILL.md) r_notes+=("$(dirname "$f")/ was generated from plugins/$rel, which the kit no longer has: delete the folder") ;;
            *) r_notes+=("${f#"$root"/} was generated from plugins/$rel, which the kit no longer has: delete it") ;;
        esac
    done < <({ [[ -n "$SKILLS_DIR" && -d "$SKILLS_DIR" ]] && find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md
               [[ $MODE == install && -d "$root/.gemini/commands" ]] && find "$root/.gemini/commands" -name '*.toml'; } 2>/dev/null | sort)
}

# ---- The report -----------------------------------------------------------------------------------
say_list() { local label="$1"; shift; [[ $# -gt 0 ]] || return 0; echo "$label"; printf '  %s\n' "$@"; }
report_lists() {
    say_list "Created (yours from here on):" ${r_created[@]+"${r_created[@]}"}
    say_list "Merged (settings marketplace path):" ${r_merged[@]+"${r_merged[@]}"}
    say_list "Added to .gitignore:" ${r_gitignore[@]+"${r_gitignore[@]}"}
    say_list "Regenerated from the kit's command files:" ${r_regen[@]+"${r_regen[@]}"}
    say_list "Already in place:" ${r_same[@]+"${r_same[@]}"}
    say_list "Kept as it was (yours, from before the kit):" ${r_kept[@]+"${r_kept[@]}"}
    say_list "Template changed since your copy was made (kit/setup.sh update offers the diff):" ${r_changed[@]+"${r_changed[@]}"}
    say_list "Worth knowing:" ${r_notes[@]+"${r_notes[@]}"}
}

# ---- --skills-only --------------------------------------------------------------------------------
if [[ $MODE == skills ]]; then
    [[ -n "$SKILLS_DIR" ]] || usage_error "--skills-only needs --skills-dir"
    TARGET="${TARGET:-.}"
    [[ -d "$TARGET" ]] || die "no folder at $TARGET"
    root="$(cd "$TARGET" && pwd -P)"
    psrc="${PLUGIN_SRC:-$SELF_DIR/plugins}"
    [[ -d "$psrc" ]] || die "no plugins folder at $psrc"
    psrc="$(cd "$psrc" && pwd -P)"
    # The skills folder, resolved through its nearest existing ancestor, so a folder not made yet is
    # still judged by where it would land.
    sd="$SKILLS_DIR"; [[ "$sd" == /* ]] || sd="$PWD/$sd"
    sd_rest=""
    while [[ ! -d "$sd" ]]; do sd_rest="/$(basename "$sd")$sd_rest"; sd="$(dirname "$sd")"; done
    sd="$(cd "$sd" && pwd -P)$sd_rest"
    # The kit checkout is public: skills generated inside it would be committed to it.
    for kr in "$SELF_DIR" "$root/kit"; do
        [[ -d "$kr" ]] || continue
        kr="$(cd "$kr" && pwd -P)"
        case "$sd/" in "$kr"/*) die "the skills folder $SKILLS_DIR is inside the kit checkout ($kr), which is public; choose a folder outside it" ;; esac
    done
    SKILLS_DIR="$sd"
    [[ $DRY -eq 1 ]] || mkdir -p "$SKILLS_DIR" || die "cannot make $SKILLS_DIR"
    generate_commands skills "$psrc" "$root"
    stale_generated "$psrc" "$root"
    echo
    [[ $DRY -eq 1 ]] && echo "Dry run — nothing written." && echo
    echo "Skills written to $SKILLS_DIR, pointing into $root"
    echo
    report_lists
    exit 0
fi

# ---- Every other form works on a workspace with the kit inside it ------------------------------------
[[ -n "$TARGET" ]] || usage_error "--target is needed"
[[ -d "$TARGET" ]] || die "no folder at $TARGET"
WS="$(cd "$TARGET" && pwd -P)"
KIT="$WS/$REL"
if ! grep -qs '"agentic-workspace"' "$KIT/.claude-plugin/marketplace.json" || [[ ! -f "$KIT/CLAUDE.kit.md" ]]; then
    printf 'install.sh: no kit at %s/%s — add it with kit/setup.sh new, or git submodule add <url> kit\n' "$WS" "$REL" >&2
    exit 1
fi
KIT_COMMIT="$(aw_git_elsewhere "$KIT" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)" || KIT_COMMIT=""
[[ -n "$KIT_COMMIT" ]] || KIT_COMMIT="-"
KIT_VERSION="$(awk '/^## v[0-9]/ { v = $2; sub(/^v/, "", v); print v; exit }' "$KIT/CHANGELOG.md" 2>/dev/null)"
LEDGER="$WS/$AW_LEDGER_REL"

# The files a workspace owns, in the contract's order: <dest>|<template in the kit>. .gitignore is
# handled on its own, since its lines are merged rather than its file compared.
owned_files() {
    printf '%s\n' \
        'CLAUDE.md|templates/workspace/CLAUDE.md' \
        'AGENTS.md|templates/workspace/AGENTS.md' \
        'README.md|templates/workspace/README.md' \
        '.claude/settings.json|templates/workspace/settings.json' \
        '.claude/closeout.md|templates/workspace/closeout.md' \
        '.claude/projects.md|templates/workspace/projects.md'
    [[ "${1:-}" == standins ]] || printf '%s\n' '.claude/workspace.md|templates/workspace/workspace.md'
    printf '%s\n' \
        'projects/INDEX.md|templates/workspace/INDEX.md' \
        'logs/decisions.md|templates/workspace/decisions.md' \
        'memory/glossary.md|templates/workspace/glossary.md' \
        'memory/people/README.md|templates/workspace/people-README.md' \
        'audits/README.md|templates/workspace/audits-README.md' \
        'docs/workspace-map.md|templates/workspace/workspace-map.md' \
        '.github/CODEOWNERS|templates/workspace/CODEOWNERS' \
        '.github/pull_request_template.md|templates/workspace/pull_request_template.md' \
        '.github/workflows/stay-private.yml|templates/workspace/stay-private.yml'
    [[ "${1:-}" == standins || "$AW_V_pilot" != 1 ]] || printf '%s\n' 'pilot/build-list.md|pilot/build-list.md'
}

GI_TPL="templates/workspace.gitignore"
GI_HEADER='# Added by the agentic workspace kit (kit/templates/workspace.gitignore)'

# gi_missing <.gitignore or /dev/null> <declined list or /dev/null>: the template's lines (not blank,
# not a # line) that the file does not have and the person has not declined, in template order. Lines
# compare after trailing spaces are trimmed.
gi_missing() {
    awk '
        { l = $0; sub(/[ \t\r]+$/, "", l) }
        FILENAME == ARGV[1] { if (l == "" || l ~ /^#/) next; if (!(l in seen)) { seen[l] = 1; order[++n] = l }; next }
        { have[l] = 1 }
        END { for (i = 1; i <= n; i++) if (!(order[i] in have)) print order[i] }' "$KIT/$GI_TPL" "$1" "$2"
}
# gi_new_content <.gitignore> <missing lines file>: the file as it is, then the header (once) and the lines.
gi_new_content() {
    cat "$1"
    [[ ! -s "$1" || "$(tail -c 1 "$1" | od -An -c | tr -d ' ')" == '\n' ]] || printf '\n'
    if ! grep -qxF "$GI_HEADER" "$1"; then
        [[ ! -s "$1" ]] || printf '\n'
        printf '%s\n' "$GI_HEADER"
    fi
    cat "$2"
}

# The values the files are rendered with: the ledger's @values when it has them, else this run's answers
# over the stand-ins.
load_values() {
    local v=""
    aw_tpl_standins
    [[ -f "$1" ]] && v="$(awk -F '\t' '$1 == "@values" { print; exit }' "$1")"
    if [[ -n "$v" ]]; then aw_tpl_values_parse "$v"; return 0; fi
    return 1
}

# render_to <kit commit or empty> <template path> <out>: with the current AW_V_* values.
render_to() { aw_tpl_read "$KIT" "$1" "$2" 2>/dev/null | aw_tpl_render "$KIT" "$1" > "$3"; }

# ---- --template-status, --template-diff, --template-record, --gitignore-decline ----------------------
if [[ $MODE == status || $MODE == diff || $MODE == record || $MODE == decline ]]; then
    [[ -f "$LEDGER" ]] || die "no ledger at $AW_LEDGER_REL in $WS (kit/setup.sh creates it)"
    load_values "$LEDGER"
fi

if [[ $MODE == status ]]; then
    while IFS= read -r line; do
        case "$line" in ''|'#'*|'@'*|'!'*) continue ;; esac
        IFS="$AW_TAB" read -r dest src c h st _rest <<<"$line"
        if [[ "$st" == lines ]]; then st_out=lines
        elif aw_tpl_opaque "$WS" "$dest"; then st_out=opaque
        elif [[ ! -e "$WS/$dest" && ! -L "$WS/$dest" ]]; then st_out=removed
        elif [[ ! -f "$KIT/$src" ]]; then st_out=dropped
        else
            render_to "" "$src" "$work/new"
            if [[ "$(aw_tpl_hash < "$work/new")" == "$h" ]]; then st_out=current
            elif [[ "$c" != "-" ]] && aw_git_elsewhere "$KIT" cat-file -e "$c:$src" 2>/dev/null; then st_out=changed
            else st_out=changed-no-base; fi
        fi
        printf '%s\t%s\t%s\n' "$st_out" "$dest" "$src"
    done < "$LEDGER"
    exit 0
fi

if [[ $MODE == diff ]]; then
    line="$(aw_ledger_line "$LEDGER" "$ARG_DEST")"
    [[ -n "$line" ]] || die "$ARG_DEST has no entry in $AW_LEDGER_REL"
    IFS="$AW_TAB" read -r dest src c h st rest <<<"$line"
    [[ "$st" != lines ]] || die ".gitignore is offered line by line: install.sh --gitignore offer"
    ! aw_tpl_opaque "$WS" "$dest" || die "$dest is opaque here (AW_OPAQUE_PATHS); no diff is offered for it"
    [[ -f "$KIT/$src" ]] || die "the kit no longer has $src"
    if [[ "$c" == "-" ]] || ! aw_git_elsewhere "$KIT" cat-file -e "$c:$src" 2>/dev/null; then
        printf 'install.sh: the template %s as it was at %s is not in this kit checkout (a shallow clone?); compare %s with kit/%s by hand\n' \
            "$src" "${c:0:7}" "$dest" "$src" >&2
        exit 1
    fi
    render_to "" "$src" "$work/new"
    # The old side is rendered with the values the file was made with: @values, with any value that
    # changed since (a later --cowork, say) taken back to what it was then.
    for k in $AW_VALUE_KEYS; do n="AW_V_$k"; printf -v "AW_O_$k" '%s' "${!n}"; done
    [[ -z "${rest:-}" ]] || aw_tpl_values_parse "$rest"
    render_to "$c" "$src" "$work/old"
    aw_tpl_swap
    if cmp -s "$work/old" "$work/new"; then exit 3; fi
    tdir="$work/diff"
    if ! { mkdir -p "$tdir/$(dirname "$dest")" && aw_git_elsewhere "$tdir" init -q >/dev/null 2>&1; }; then
        die "cannot make a scratch repository under ${TMPDIR:-/tmp}"
    fi
    cat "$work/old" > "$tdir/$dest"
    aw_git_elsewhere "$tdir" -c core.autocrlf=false -c core.safecrlf=false add -f -- "$dest" || die "cannot stage the old template in the scratch repository"
    cat "$work/new" > "$tdir/$dest"
    aw_git_elsewhere "$tdir" -c diff.noprefix=false -c diff.mnemonicPrefix=false -c color.ui=false \
        -c diff.srcPrefix=a/ -c diff.dstPrefix=b/ -c core.autocrlf=false -c core.quotePath=false \
        diff --no-color --no-ext-diff --no-textconv -- "$dest"
    exit 0
fi

if [[ $MODE == record ]]; then
    case "$REC_STATUS" in accepted|skipped) ;; *) usage_error "--template-record takes --status accepted or --status skipped" ;; esac
    line="$(aw_ledger_line "$LEDGER" "$ARG_DEST")"
    [[ -n "$line" ]] || die "$ARG_DEST has no entry in $AW_LEDGER_REL"
    IFS="$AW_TAB" read -r dest src _c _h st _rest <<<"$line"
    [[ "$st" != lines ]] || die ".gitignore lines are declined one at a time: install.sh --gitignore-decline LINE"
    ! aw_tpl_opaque "$WS" "$dest" || die "$dest is opaque here (AW_OPAQUE_PATHS); its entry stays kept"
    [[ -f "$KIT/$src" ]] || die "the kit no longer has $src"
    render_to "" "$src" "$work/new"
    aw_ledger_put "$LEDGER" "$dest" "$dest$AW_TAB$src$AW_TAB$KIT_COMMIT$AW_TAB$(aw_tpl_hash < "$work/new")$AW_TAB$REC_STATUS" \
        || die "cannot write $AW_LEDGER_REL"
    exit 0
fi

if [[ $MODE == decline ]]; then
    DECLINE="$(printf '%s' "$DECLINE" | sed 's/[[:space:]]*$//')"
    [[ -n "$DECLINE" ]] || usage_error "--gitignore-decline needs a line"
    if ! aw_ledger_declined "$LEDGER" | grep -qxF -- "$DECLINE"; then
        printf '!declined\t.gitignore\t%s\n' "$DECLINE" >> "$LEDGER" || die "cannot write $AW_LEDGER_REL"
    fi
    exit 0
fi

# ---- --gitignore offer: the missing lines as one diff, for kit/setup.sh update to present ------------
if [[ $MODE == install && "$GI_MODE" == offer ]]; then
    gi="$WS/.gitignore"
    [[ -f "$gi" ]] || { printf 'install.sh: no .gitignore to offer lines to; the engine creates one when it has no record of it\n' >&2; exit 3; }
    aw_ledger_declined "$LEDGER" > "$work/declined"
    gi_missing "$gi" "$work/declined" > "$work/missing"
    [[ -s "$work/missing" ]] || exit 3
    tdir="$work/offer"
    if ! { mkdir -p "$tdir" && aw_git_elsewhere "$tdir" init -q >/dev/null 2>&1; }; then
        die "cannot make a scratch repository under ${TMPDIR:-/tmp}"
    fi
    cat "$gi" > "$tdir/.gitignore"
    aw_git_elsewhere "$tdir" -c core.autocrlf=false add -f -- .gitignore || die "cannot stage .gitignore in the scratch repository"
    gi_new_content "$gi" "$work/missing" > "$tdir/.gitignore"
    aw_git_elsewhere "$tdir" -c diff.noprefix=false -c diff.mnemonicPrefix=false -c color.ui=false \
        -c diff.srcPrefix=a/ -c diff.dstPrefix=b/ -c core.autocrlf=false \
        diff --no-color --no-ext-diff --no-textconv -- .gitignore
    exit 0
fi

# ---- The repository ---------------------------------------------------------------------------------
if ! aw_git_elsewhere "$WS" rev-parse --git-dir >/dev/null 2>&1; then
    if [[ $INIT -eq 1 && $DRY -eq 0 ]]; then
        aw_git_elsewhere "$WS" init -q -b main >/dev/null 2>&1 \
            || { aw_git_elsewhere "$WS" init -q && aw_git_elsewhere "$WS" symbolic-ref HEAD refs/heads/main; } \
            || die "cannot git init $WS"
    elif [[ $INIT -eq 1 ]]; then
        r_notes+=("$WS is not a git repository yet; --init would make one")
    elif [[ $MODE == install ]]; then
        die "$WS is not a git repository (kit/setup.sh new makes one, or add --init)"
    fi
fi

# ---- --stand-ins: the template repository's files ---------------------------------------------------
if [[ $MODE == standins ]]; then
    aw_tpl_standins
    while IFS='|' read -r dest src; do
        [[ -f "$KIT/$src" ]] || die "the kit at $REL/ has no $src"
        if aw_tpl_opaque "$WS" "$dest"; then r_notes+=("$dest is opaque here and was left unread"); continue; fi
        render_to "" "$src" "$work/new"
        if cmp -s "$work/new" "$WS/$dest"; then r_same+=("$dest"); continue; fi
        r_created+=("$dest")
        [[ $DRY -eq 1 ]] || { mkdir -p "$(dirname "$WS/$dest")" && cat "$work/new" > "$WS/$dest"; } || die "cannot write $dest"
    done < <(owned_files standins)
    if cmp -s "$KIT/$GI_TPL" "$WS/.gitignore"; then r_same+=(".gitignore")
    else
        r_created+=(".gitignore")
        [[ $DRY -eq 1 ]] || cat "$KIT/$GI_TPL" > "$WS/.gitignore" || die "cannot write .gitignore"
    fi
    echo
    [[ $DRY -eq 1 ]] && echo "Dry run — nothing written." && echo
    echo "Stand-in files in $WS  (kit at $REL/, ${KIT_VERSION:-unknown version}, commit ${KIT_COMMIT:0:7})"
    echo
    report_lists
    exit 0
fi

# ---- The install proper -----------------------------------------------------------------------------
LW="$work/ledger"
if [[ -f "$LEDGER" ]]; then cat "$LEDGER" > "$LW" || die "cannot read $AW_LEDGER_REL"; else aw_ledger_header > "$LW"; fi

# Values. The first run records them; later runs render with what was recorded, so neither the date
# nor a repeated flag makes a template look changed. A later run can still fill a stand-in (a team name
# given at last) and switch on cowork, gemini or the pilot; the files that change with it are handled
# per file below, from the old values kept in AW_O_*.
changed_keys=""
if load_values "$LW"; then
    for k in $AW_VALUE_KEYS; do n="AW_V_$k"; printf -v "AW_O_$k" '%s' "${!n}"; done
    set_value() { # <key> <value>
        local n="AW_V_$1"
        [[ "${!n}" != "$2" ]] || return 0
        printf -v "$n" '%s' "$2"; changed_keys+=" $1"
    }
    for pair in "team|$TEAM|<team name>" "owner|$OWNER|<standards owner>" "handle|$HANDLE|@<standards-owner-handle>"; do
        IFS='|' read -r k given standin <<<"$pair"
        n="AW_V_$k"
        [[ -n "$given" && "$given" != "${!n}" ]] || continue
        if [[ "${!n}" == "$standin" ]]; then set_value "$k" "$given"
        else r_notes+=("$k is recorded as '${!n}' in $AW_LEDGER_REL, so '$given' was not applied; the files are yours to edit"); fi
    done
    [[ $COWORK -eq 0 ]] || set_value cowork 1
    [[ $PILOT -eq 0 ]] || set_value pilot 1
    if [[ -n "$SURFACES" ]]; then
        sv="$AW_V_surfaces"
        for s in ${SURFACES//,/ }; do [[ ",$sv," == *",$s,"* ]] || sv="$sv,$s"; done
        set_value surfaces "$sv"
    fi
else
    aw_tpl_standins
    [[ -z "$TEAM" ]] || AW_V_team="$TEAM"
    [[ -z "$OWNER" ]] || AW_V_owner="$OWNER"
    [[ -z "$HANDLE" ]] || AW_V_handle="$HANDLE"
    [[ -z "$SURFACES" ]] || AW_V_surfaces="$SURFACES"
    AW_V_date="$TODAY" AW_V_cowork="$COWORK" AW_V_pilot="$PILOT"
fi
# The @values line goes after the leading comments, replacing any earlier one.
vline="$(aw_tpl_values_line)"
AW_L_V="$vline" awk -F '\t' '
    $1 == "@values" { next }
    !done && $0 !~ /^#/ { print ENVIRON["AW_L_V"]; done = 1 }
    { print }
    END { if (!done) print ENVIRON["AW_L_V"] }' "$LW" > "$work/ledger.v" && cat "$work/ledger.v" > "$LW"

ledger_set() { # <dest> <source> <commit> <hash> <status> [<base value>...]
    local dest="$1" out="$1"; shift
    while [[ $# -gt 0 ]]; do out+="$AW_TAB$1"; shift; done
    aw_ledger_put "$LW" "$dest" "$out" || die "cannot update the ledger copy"
}
write_dest() { # <dest> <content file>
    [[ $DRY -eq 1 ]] && return 0
    { mkdir -p "$(dirname "$WS/$1")" && cat "$2" > "$WS/$1"; } || die "cannot write $1"
}
exists() { [[ -e "$WS/$1" || -L "$WS/$1" ]]; }

created_claude=0 settings_created=0 opaque_kept=()
process_file() {
    local dest="$1" src="$2" line c h st rest nh k n base=""
    if [[ ! -f "$KIT/$src" ]]; then r_notes+=("the kit at $REL/ has no $src, so $dest was not created"); return; fi
    render_to "" "$src" "$work/new"
    nh="$(aw_tpl_hash < "$work/new")"
    line="$(aw_ledger_line "$LW" "$dest")"
    if aw_tpl_opaque "$WS" "$dest"; then
        # Opaque: recorded, never opened. Its base is recorded all the same.
        [[ -n "$line" ]] || ledger_set "$dest" "$src" "$KIT_COMMIT" "$nh" kept
        opaque_kept+=("$dest")
        return
    fi
    if [[ -n "$line" ]]; then
        IFS="$AW_TAB" read -r _d _s c h st rest <<<"$line"
        if ! exists "$dest"; then
            r_notes+=("$dest is recorded in $AW_LEDGER_REL but is not here; the kit does not recreate a file you removed")
            return
        fi
        if [[ -n "$changed_keys" ]]; then
            aw_tpl_swap; render_to "" "$src" "$work/old"; aw_tpl_swap
            if ! cmp -s "$work/old" "$work/new"; then
                if cmp -s "$WS/$dest" "$work/old"; then
                    # Untouched since the engine wrote it: the new values' render replaces it.
                    write_dest "$dest" "$work/new"; ledger_set "$dest" "$src" "$KIT_COMMIT" "$nh" created
                    r_created+=("$dest")
                else
                    # Edited since: the change is offered as a diff, rendered from the values it was made with.
                    if [[ -z "${rest:-}" ]]; then
                        for k in $changed_keys; do n="AW_O_$k"; base+="$AW_TAB$k=${!n}"; done
                        rest="${base#"$AW_TAB"}"
                    fi
                    aw_ledger_put "$LW" "$dest" "$dest$AW_TAB$src$AW_TAB$c$AW_TAB$h$AW_TAB$st$AW_TAB$rest" \
                        || die "cannot update the ledger copy"
                    r_changed+=("$dest")
                fi
                return
            fi
        fi
        if cmp -s "$WS/$dest" "$work/new"; then
            if [[ "$h" != "$nh" || -n "${rest:-}" ]]; then
                [[ "$st" == accepted ]] || st=created
                ledger_set "$dest" "$src" "$KIT_COMMIT" "$nh" "$st"
            fi
            r_same+=("$dest")
        elif [[ "$h" == "$nh" && -z "${rest:-}" ]]; then
            r_same+=("$dest")
        else
            r_changed+=("$dest")
        fi
        return
    fi
    if ! exists "$dest"; then
        write_dest "$dest" "$work/new"; ledger_set "$dest" "$src" "$KIT_COMMIT" "$nh" created
        r_created+=("$dest")
        [[ "$dest" != CLAUDE.md ]] || created_claude=1
        [[ "$dest" != .claude/settings.json ]] || settings_created=1
    elif cmp -s "$WS/$dest" "$work/new"; then
        ledger_set "$dest" "$src" "$KIT_COMMIT" "$nh" created
        r_same+=("$dest")
    else
        # The stand-in rule: a file byte-identical to the stand-in render (the template repository's
        # copy, never edited) is the kit's still, and takes the real render.
        vline="$(aw_tpl_values_line)"
        aw_tpl_standins; render_to "" "$src" "$work/standin"
        aw_tpl_standins; aw_tpl_values_parse "$vline"
        if cmp -s "$WS/$dest" "$work/standin"; then
            write_dest "$dest" "$work/new"; ledger_set "$dest" "$src" "$KIT_COMMIT" "$nh" created
            r_created+=("$dest")
            [[ "$dest" != CLAUDE.md ]] || created_claude=1
        else
            ledger_set "$dest" "$src" "$KIT_COMMIT" "$nh" kept
            r_kept+=("$dest")
        fi
    fi
}

while IFS='|' read -r dest src; do process_file "$dest" "$src"; done < <(owned_files)
for f in ${opaque_kept[@]+"${opaque_kept[@]}"}; do
    r_notes+=("$f is opaque here (AW_OPAQUE_PATHS): recorded as kept without being opened")
done

# ---- .claude/settings.json: the one key the engine maintains ----------------------------------------
settings="$WS/.claude/settings.json"
want_src='{"source":"directory","path":"kit"}'
if [[ $settings_created -eq 0 && -f "$settings" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
        r_notes+=(".claude/settings.json was not checked: jq is not on PATH")
    elif ! jq -e . "$settings" >/dev/null 2>&1; then
        r_notes+=(".claude/settings.json does not parse as JSON, so its marketplace path was not checked")
    else
        cur="$(jq -c '.extraKnownMarketplaces["agentic-workspace"].source // empty' "$settings")"
        cp "$settings" "$work/settings"
        if [[ -z "$cur" ]]; then
            jq --argjson s "$want_src" '.extraKnownMarketplaces["agentic-workspace"].source = $s' "$settings" > "$work/settings" \
                || die "cannot update .claude/settings.json"
            jq -S . "$settings" > "$work/cmp-a" 2>/dev/null; jq -S . "$work/settings" > "$work/cmp-b" 2>/dev/null
            if ! cmp -s "$work/cmp-a" "$work/cmp-b"; then
                write_dest .claude/settings.json "$work/settings"
                r_merged+=(".claude/settings.json")
            fi
        elif [[ "$(printf '%s' "$cur" | jq -S -c .)" != "$(printf '%s' "$want_src" | jq -S -c .)" ]]; then
            r_notes+=("legacy: the agentic-workspace marketplace in .claude/settings.json is $cur, not kit/ — kit/setup.sh migrate --dry-run shows the change")
        fi
        # Kit keys the person's file lacks are listed, each with the command that adds it; the person's own
        # values, a plugin switched off included, are never changed.
        # The jq program is literal text for jq, not for the shell.
        while IFS= read -r expr; do
            [[ -n "$expr" ]] || continue
            q="${expr//\'/\'\\\'\'}"
            r_notes+=("settings key the kit's template has and yours lacks: jq '$q' .claude/settings.json > .claude/settings.json.new && mv .claude/settings.json.new .claude/settings.json")
        done < <(jq -r --slurpfile t "$KIT/templates/workspace/settings.json" '
            def pexpr: (reduce .[] as $k (""; . + (if ($k | type) == "string" and ($k | test("^[A-Za-z_][A-Za-z0-9_]*$"))
                then "." + $k else "[" + ($k | tojson) + "]" end))) | if startswith("[") then "." + . else . end;
            def miss($u; $t; $p):
                if ($t | type) == "object" then
                    $t | to_entries[] | .key as $k | .value as $v
                    | if ($u | type) == "object" and ($u | has($k)) then miss($u[$k]; $v; $p + [$k])
                      elif ($u | type) == "object" or $u == null then {p: ($p + [$k]), op: "=", v: $v}
                      else empty end
                elif ($t | type) == "array" and ($u | type) == "array" then
                    $t[] as $e | if any($u[]; . == $e) then empty else {p: $p, op: "+=", v: [$e]} end
                else empty end;
            miss(.; $t[0]; []) | "\(.p | pexpr) \(.op) \(.v | tojson)"' "$work/settings" 2>/dev/null)
    fi
fi

# ---- .gitignore -------------------------------------------------------------------------------------
[[ -n "$GI_MODE" ]] || { if [[ $INIT -eq 1 || $created_claude -eq 1 ]]; then GI_MODE=merge; else GI_MODE=report; fi; }
gi="$WS/.gitignore"
gi_line="$(aw_ledger_line "$LW" .gitignore)"
if ! exists .gitignore; then
    if [[ -n "$gi_line" ]]; then
        r_notes+=(".gitignore is recorded in $AW_LEDGER_REL but is not here; the kit does not recreate a file you removed")
    else
        write_dest .gitignore "$KIT/$GI_TPL"
        ledger_set .gitignore "$GI_TPL" "$KIT_COMMIT" - lines
        r_created+=(".gitignore")
    fi
else
    [[ -n "$gi_line" ]] || ledger_set .gitignore "$GI_TPL" "$KIT_COMMIT" - lines
    aw_ledger_declined "$LW" > "$work/declined"
    gi_missing "$gi" "$work/declined" > "$work/missing"
    if [[ -s "$work/missing" ]]; then
        case "$GI_MODE" in
            merge)
                gi_new_content "$gi" "$work/missing" > "$work/gitignore"
                write_dest .gitignore "$work/gitignore"
                ledger_set .gitignore "$GI_TPL" "$KIT_COMMIT" - lines
                while IFS= read -r l; do r_gitignore+=("$l"); done < "$work/missing" ;;
            *)
                n_missing=$(( $(aw_count < "$work/missing") ))
                r_notes+=(".gitignore lacks $n_missing line(s) the kit's template has ($(paste -sd' ' - < "$work/missing")); kit/setup.sh update offers them") ;;
        esac
    fi
fi

# ---- Gemini CLI (parked: still set up on request) ---------------------------------------------------
if [[ ",$AW_V_surfaces," == *",gemini,"* ]]; then
    gs="$WS/.gemini/settings.json" gtpl="$KIT/templates/workspace/gemini-settings.json"
    if [[ ! -e "$gs" ]]; then
        write_dest .gemini/settings.json "$gtpl"; r_created+=(".gemini/settings.json")
    elif command -v jq >/dev/null 2>&1 && jq -e . "$gs" >/dev/null 2>&1; then
        # An additive merge: the context file list is unioned, and nothing of the person's is removed.
        jq -s '.[0] as $old | .[1] as $new | ($new * $old)
            | .context.fileName = (([$old.context.fileName] | flatten | map(select(. != null))) + ($new.context.fileName // []) | unique)' \
            "$gs" "$gtpl" > "$work/gemini" || die "cannot merge .gemini/settings.json"
        jq -S . "$gs" > "$work/cmp-a" 2>/dev/null; jq -S . "$work/gemini" > "$work/cmp-b" 2>/dev/null
        if cmp -s "$work/cmp-a" "$work/cmp-b"; then r_same+=(".gemini/settings.json")
        else write_dest .gemini/settings.json "$work/gemini"; r_merged+=(".gemini/settings.json"); fi
    else
        r_notes+=(".gemini/settings.json was not merged: jq is missing or the file does not parse")
    fi
    generate_commands gemini "$KIT/plugins" "$WS"
    stale_generated "$KIT/plugins" "$WS"
fi

# ---- Traces of the 2.x layout: reported, never touched ----------------------------------------------
[[ ! -e "$WS/.claude/plugins/VENDORED" ]] \
    || r_notes+=("legacy: .claude/plugins/ holds the 2.x vendored plugins — kit/setup.sh migrate --dry-run shows the move")
incoming="$(aw_git_elsewhere "$WS" ls-files -co --exclude-standard -- '*.kit-incoming' ":(exclude)$REL" 2>/dev/null | head -n 5 | paste -sd' ' -)"
[[ -z "$incoming" ]] || r_notes+=("legacy: 2.x .kit-incoming files ($incoming) — kit/setup.sh migrate --dry-run lists them")
for f in "$WS"/skills/*/SKILL.md; do
    if [[ ! -f "$f" ]] || ! grep -qs "$GEN_MARK" "$f"; then continue; fi
    r_notes+=("legacy: skills/$(basename "$(dirname "$f")") was generated by the 2.x installer — kit/setup.sh migrate --dry-run moves it out")
done
if [[ -f "$WS/CLAUDE.md" ]] && ! aw_tpl_opaque "$WS" CLAUDE.md \
    && [[ "$(awk '/^[[:space:]]*$/ { next } /^<!--/ { c = 1 } c { if (/-->/) c = 0; next } { print }' "$WS/CLAUDE.md" 2>/dev/null)" == "@AGENTS.md" ]]; then
    r_notes+=("legacy: CLAUDE.md is the 2.x one-line import of AGENTS.md — kit/setup.sh migrate --dry-run shows the 3.0 step")
fi
if exists .github/CODEOWNERS && [[ " ${r_created[*]-} " == *" .github/CODEOWNERS "* ]]; then
    lc_team="$(printf '%s' "$AW_V_team" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lc_team" == solo || "$AW_V_team" == "$AW_V_owner" ]]; then
        r_notes+=(".github/ routes changes to the always-loaded file to the standards owner for review; with one person it is optional, and the quick-start offers to remove it")
    fi
fi

# ---- The ledger -------------------------------------------------------------------------------------
if ! cmp -s "$LW" "$LEDGER"; then
    [[ -f "$LEDGER" ]] || r_created+=("$AW_LEDGER_REL")
    write_dest "$AW_LEDGER_REL" "$LW"
fi

# ---- Report -----------------------------------------------------------------------------------------
echo
[[ $DRY -eq 1 ]] && echo "Dry run — nothing written." && echo
echo "Workspace: $WS  (kit at $REL/, ${KIT_VERSION:-unknown version}, commit ${KIT_COMMIT:0:7})"
echo
report_lists
if [[ $DRY -eq 0 ]]; then
    echo
    echo "Next:"
    i=1
    if [[ -f "$WS/CLAUDE.md" && "$(awk 'NF { print; exit }' "$WS/CLAUDE.md" 2>/dev/null)" == '@kit/CLAUDE.kit.md' ]] \
        && [[ " ${r_kept[*]-} " != *" CLAUDE.md "* ]]; then
        # A stand-in is an angle-bracketed phrase with a space in it; path patterns like <name> are not.
        n="$(tr '\n' ' ' < "$WS/CLAUDE.md" | grep -o '<[A-Za-z][^<>]* [^<>]*>' | aw_count)"
        echo "  $i. Open the workspace in Claude Code and run /workspace:quick-start. It interviews you for the rest"
        echo "     — CLAUDE.md has $n answers still to fill in — then offers /projects:new for the first projects."
    else
        echo "  $i. Your own CLAUDE.md was kept. The kit's working standards load through a first line of"
        echo "     @kit/CLAUDE.kit.md; /workspace:quick-start maps your system onto the kit and changes nothing without your yes."
    fi
    i=$((i + 1))
    echo "  $i. Each person, in Claude Code: trust the folder, then approve the closeout, projects and workspace plugins when asked."
    i=$((i + 1))
    if [[ "$AW_V_pilot" == 1 ]]; then
        echo "  $i. Put the team's own build list into pilot/build-list.md, commit, then run bash $REL/pilot/measure.sh."
    fi
    echo "  Nothing is committed. Review with: git -C \"$WS\" status"
fi
exit 0
