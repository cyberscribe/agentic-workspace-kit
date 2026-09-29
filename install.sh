#!/usr/bin/env bash
# Deploys the workspace context kit into a team's shared repository.
#
#   ./install.sh                  asks the handful of questions it needs, then installs
#   ./install.sh --target ../team-workspace --team "Data Platform" --owner "Sam" --owner-handle "@sam" --pilot
#
# What it lays down:
#   - the kit (docs/, rituals/, templates/, logs/, projects/INDEX.md, memory/) with AGENTS.md as the
#     one always-loaded file, and §1 rewritten for a team rather than a person
#   - Claude Code: CLAUDE.md as a one-line import of AGENTS.md; the closeout, projects and workspace
#     plugins registered in .claude/settings.json, with .claude/closeout.md pointing closeout at the
#     kit's taxonomy; /workspace:quick-start is the first-time interview that fills in the rest
#   - .claude/projects.md, the team's project conventions, read first by every projects command
#   - with --surfaces claude,gemini: .gemini/settings.json loading AGENTS.md, and a wrapper for every
#     plugin command, generated from the same markdown Claude Code runs
#   - with --skills-dir DIR: one thin skill per command, for assistants that load skills from a folder
#   - .github/CODEOWNERS and a pull request template for the always-loaded tier
#   - with --pilot: pilot/ (protocol, build list, metrics script); the script reads committed
#     history, so the first metrics row is taken after the first commit
#
# It never overwrites. An existing file with different content is left alone and the kit's version is
# written beside it as <file>.kit-incoming, so the merge is a human decision. JSON settings are the
# exception: they are merged additively with jq, which only ever adds keys and list entries. So are the
# files it generates from the command files (skills, Gemini wrappers), which are refreshed in place.
# Running it twice is safe.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="" TEAM="" OWNER="" OWNER_HANDLE="" PLUGIN="vendor" PLUGIN_SRC="" SURFACES="claude" PILOT=0 DRY=0
INTERACTIVE=0 PILOT_SET=0 SURFACES_SET=0 SKILLS_DIR="" SKILLS_SET=0 SKILLS_ONLY=0
PLUGIN_REPO="cyberscribe/agentic-workspace-kit"

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; cat <<'USAGE'

Options:
  --target DIR          the team repository (a git repository; created if --init is also given)
  --team NAME           team name, written into AGENTS.md and the closeout conventions
  --owner NAME          standards owner, who reviews changes to the always-loaded tier
  --owner-handle @h     their GitHub/GitLab handle for CODEOWNERS (defaults to a placeholder)
  --plugin MODE         vendor (default) | github | none
                          vendor: copy this kit's plugins/ (closeout, projects, workspace) into
                                  .claude/plugins/ — pinned, reviewable, no network or GitHub
                                  access needed
                          github: register this kit's repository as the marketplace and let Claude
                                  Code fetch the plugins from it
  --plugin-src DIR      vendor from a plugins directory other than this kit's plugins/
  --surfaces LIST       claude (default) | claude,gemini | gemini
  --skills-dir DIR      also write one skill per command into DIR (projects-new, closeout,
                        workspace-quick-start, …), for a desktop assistant that loads skills from a
                        folder rather than plugins; each points at the command file, so the
                        procedure keeps one source
  --skills-only         write the skills and nothing else (with --skills-dir; --target, default the
                        current folder, is the repository the skills point into)
  --pilot               add pilot/: protocol, build list, and the metrics script to run after the
                        first commit
  --init                git init the target if it is not already a repository
  --interactive         ask for anything not given as an option (the default when run with no options
                        from a terminal)
  --dry-run             say what would happen, write nothing

After installing, run /workspace:quick-start in Claude Code (or the workspace-quick-start skill): it
interviews the team for what a script cannot usefully ask — what the team does, its conventions, its
approval gates, its people.
USAGE
}

INIT=0
[[ $# -eq 0 && -t 0 ]] && INTERACTIVE=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --team) TEAM="$2"; shift 2 ;;
        --owner) OWNER="$2"; shift 2 ;;
        --owner-handle) OWNER_HANDLE="$2"; shift 2 ;;
        --plugin) PLUGIN="$2"; shift 2 ;;
        --plugin-src) PLUGIN_SRC="$2"; shift 2 ;;
        --surfaces) SURFACES="$2"; SURFACES_SET=1; shift 2 ;;
        --skills-dir) SKILLS_DIR="$2"; SKILLS_SET=1; shift 2 ;;
        --skills-only) SKILLS_ONLY=1; shift ;;
        --pilot) PILOT=1; PILOT_SET=1; shift ;;
        --interactive) INTERACTIVE=1; shift ;;
        --init) INIT=1; shift ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

die() { echo "install.sh: $*" >&2; exit 1; }

# The quick-start's first half: only what the files need to be laid down. Everything that takes
# judgement — what the team does, how it works, who owns what — is asked by /workspace:quick-start in the
# agent, where the answers can be discussed rather than typed into a prompt.
if [[ $INTERACTIVE -eq 1 ]]; then
    # A question with no default takes an empty answer as "none": ${2:-} keeps set -u from stopping here.
    ask() { local reply; read -r -p "$1${2:+ [$2]}: " reply || true; printf '%s' "${reply:-${2:-}}"; }
    echo "Workspace context kit — a few questions, then it installs. Press Enter to accept a [default]."
    echo
    [[ -n "$TARGET" ]] || TARGET="$(ask "Path to the team's shared repository (created if it does not exist)" ".")"
    [[ -d "$TARGET" ]] && git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || INIT=1
    [[ -n "$TEAM" ]] || TEAM="$(ask "Team name")"
    [[ -n "$OWNER" ]] || OWNER="$(ask "Standards owner — who reviews changes to the shared standards file")"
    [[ -n "$OWNER_HANDLE" ]] || OWNER_HANDLE="$(ask "Their GitHub or GitLab handle, for CODEOWNERS" "${OWNER:+@}$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')")"
    [[ $SURFACES_SET -eq 1 ]] || SURFACES="$(ask "Agent tools the team uses (claude, or claude,gemini)" "claude" | tr -d ' ')"
    [[ $SKILLS_SET -eq 1 ]] || SKILLS_DIR="$(ask "Folder a desktop assistant loads skills from, if anyone uses one (Enter for none)")"
    if [[ $PILOT_SET -eq 0 ]]; then
        case "$(ask "Run it as a measured pilot, with a build list and weekly metrics? (y/n)" "n")" in
            [Yy]*) PILOT=1 ;;
        esac
    fi
    echo
    echo "  repository   $TARGET$([[ $INIT -eq 1 ]] && echo '  (will be created)')"
    echo "  team         ${TEAM:-<to fill in>}"
    echo "  owner        ${OWNER:-<to fill in>} ${OWNER_HANDLE}"
    echo "  tools        $SURFACES"
    echo "  skills       ${SKILLS_DIR:-none}"
    echo "  pilot        $([[ $PILOT -eq 1 ]] && echo yes || echo no)"
    echo
    case "$(ask "Install? (y/n)" "y")" in [Yy]*) ;; *) echo "Nothing written."; exit 0 ;; esac
fi

[[ $SKILLS_ONLY -eq 0 || -n "$SKILLS_DIR" ]] || die "--skills-only needs --skills-dir"
[[ $SKILLS_ONLY -eq 0 || -n "$TARGET" ]] || TARGET="."
[[ -n "$TARGET" ]] || { usage; exit 1; }
[[ "$PLUGIN" =~ ^(vendor|github|none)$ ]] || die "--plugin must be vendor, github or none"
# Surfaces are a comma-separated list of claude and gemini; "both" is read as the two of them. Anything
# else stops the run here, rather than installing for no surface and saying it had.
SURFACES="$(printf '%s' "$SURFACES" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
[[ "$SURFACES" != "both" ]] || SURFACES="claude,gemini"
for surf in ${SURFACES//,/ }; do [[ "$surf" == claude || "$surf" == gemini ]] || die "--surfaces takes claude, gemini or claude,gemini (got '$surf')"; done
[[ -n "${SURFACES//,/}" ]] || die "--surfaces needs at least one of claude, gemini"
TEAM="${TEAM:-<team name>}"
OWNER="${OWNER:-<standards owner>}"
OWNER_HANDLE="${OWNER_HANDLE:-@<standards-owner-handle>}"
TODAY="$(date +%F)"
has_surface() { [[ ",$SURFACES," == *",$1,"* ]]; }

if [[ ! -d "$TARGET" ]]; then
    [[ $INIT -eq 1 ]] || die "$TARGET does not exist (add --init to create it)"
    [[ $DRY -eq 1 ]] || mkdir -p "$TARGET"
fi
if [[ $DRY -eq 0 && $SKILLS_ONLY -eq 0 ]] && ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    [[ $INIT -eq 1 ]] || die "$TARGET is not a git repository (add --init to create one)"
    git -C "$TARGET" init -q
fi
TARGET="$(cd "$TARGET" 2>/dev/null && pwd || echo "$TARGET")"
# The skills folder is usually outside the repository (an assistant's own folder), so it is resolved
# against where the installer was run, and created if need be.
if [[ -n "$SKILLS_DIR" ]]; then
    [[ $DRY -eq 1 ]] || mkdir -p "$SKILLS_DIR"
    SKILLS_DIR="$(cd "$SKILLS_DIR" 2>/dev/null && pwd || echo "$SKILLS_DIR")"
fi

# Report buckets, printed at the end.
added=() same=() incoming=() merged=() regenerated=() notes=()

# Substitutes the install-time values into a template on its way to the target.
sed_escape() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }
render() {
    local team owner handle
    team="$(sed_escape "$TEAM")"; owner="$(sed_escape "$OWNER")"; handle="$(sed_escape "$OWNER_HANDLE")"
    sed -e "s|__TEAM__|$team|g" -e "s|__OWNER__|$owner|g" -e "s|__OWNER_HANDLE__|$handle|g" \
        -e "s|__DATE__|$TODAY|g" -e 's|MANIFEST\.md|AGENTS.md|g' "$1"
}

# place <content-file> <relative-dest> [root]: the one place a file reaches the target. The root is
# the repository unless a caller writes somewhere else the person named, such as a skills folder.
place() {
    local src="$1" rel="$2" dest="${3:-$TARGET}/$2"
    # Files placed outside the repository are reported by full path, so the report says where.
    [[ "${3:-$TARGET}" == "$TARGET" ]] || rel="$dest"
    if [[ -e "$dest" ]]; then
        if cmp -s "$src" "$dest"; then same+=("$rel"); return; fi
        incoming+=("$rel")
        [[ $DRY -eq 1 ]] || cp "$src" "$dest.kit-incoming"
        return
    fi
    added+=("$rel")
    [[ $DRY -eq 1 ]] || { mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"; }
}

# place_generated <content-file> <relative-dest> [root]: as place, for a file generate_commands derives
# from a command. Such a file is never edited by hand — its first comment says to edit the command and
# re-run — so a changed command replaces it here rather than arriving as .kit-incoming, which keeps
# the command the one source. A file at that path without the generated comment is someone's own, and
# goes through place like any other. procedure.md carries no comment of its own; the SKILL.md beside
# it, written in the same run, vouches for it.
place_generated() {
    local src="$1" rel="$2" dest="${3:-$TARGET}/$2" mark
    mark="$dest"; [[ "$(basename "$dest")" != procedure.md ]] || mark="$(dirname "$dest")/SKILL.md"
    if [[ -e "$dest" ]] && ! cmp -s "$src" "$dest" && grep -qs 'Generated by install.sh from plugins/' "$mark"; then
        [[ "${3:-$TARGET}" == "$TARGET" ]] || rel="$dest"
        regenerated+=("$rel")
        [[ $DRY -eq 1 ]] || cp "$src" "$dest"
        return
    fi
    place "$@"
}

# place_rendered <kit-file> <relative-dest>. mktemp makes its file 0600; the rendered file is a
# shared document, so it is opened up to the usual 0644 before it is copied into place.
place_rendered() { local t; t="$(mktemp "${TMPDIR:-/tmp}/aw.XXXXXX")"; render "$1" > "$t"; chmod 644 "$t"; place "$t" "$2"; rm -f "$t"; }

# replace_section <file> <start-regex> <end-regex> <replacement-file>
# Swaps the lines from the start heading up to (not including) the end marker for the replacement.
# Used to specialise one section of a kit file without keeping a second copy of the rest of it.
replace_section() {
    awk -v start="$2" -v end="$3" -v repl="$4" '
        $0 ~ start && !done { while ((getline l < repl) > 0) print l; skip = 1; done = 1; next }
        skip && $0 ~ end { skip = 0 }
        !skip { print }' "$1"
}

# merge_json <kit-json> <relative-dest>: additive merge; list values are unioned rather than replaced.
merge_json() {
    local src="$1" rel="$2" dest="$TARGET/$2" t
    if [[ ! -e "$dest" ]]; then place "$src" "$rel"; return; fi
    if ! command -v jq >/dev/null; then
        incoming+=("$rel (jq not found — merge by hand)")
        [[ $DRY -eq 1 ]] || cp "$src" "$dest.kit-incoming"
        return
    fi
    t="$(mktemp "${TMPDIR:-/tmp}/aw.XXXXXX")"
    jq -s '
        def union(a; b): ((a // []) + (b // [])) | unique;
        .[0] as $old | .[1] as $new
        | ($old * $new)
        | if ($old.permissions.allow or $new.permissions.allow) then .permissions.allow = union($old.permissions.allow; $new.permissions.allow) else . end
        | if ($old.sandbox.filesystem.allowWrite or $new.sandbox.filesystem.allowWrite) then .sandbox.filesystem.allowWrite = union($old.sandbox.filesystem.allowWrite; $new.sandbox.filesystem.allowWrite) else . end
        | if ($old.context.fileName or $new.context.fileName) then .context.fileName = union([$old.context.fileName] | flatten | map(select(. != null)); $new.context.fileName) else . end
    ' "$dest" "$src" > "$t"
    if cmp -s <(jq -S . "$dest") <(jq -S . "$t"); then same+=("$rel"); else
        merged+=("$rel")
        [[ $DRY -eq 1 ]] || cp "$t" "$dest"
    fi
    rm -f "$t"
}

# Commands on the surfaces that do not load Claude Code plugins. Each plugins/<plugin>/commands/
#     <command>.md is the one source of its procedure; every other surface gets a thin generated form
#     of it, never a copy to edit. generate_commands is the only place that knows where the commands
#     are, how they are named and how their front matter is read, and each surface is one case in it:
#       gemini   .gemini/commands/<plugin>/<command>.toml: the description, and the markdown body as
#                the prompt. Gemini CLI appends what the user typed after the command, which is why the
#                commands speak of it in prose rather than through a placeholder.
#       skills   <skills dir>/<name>/SKILL.md, for assistants that load skills from a folder: a thin
#                pointer at the command file, a description that says when to offer it unprompted
#                (the command's offer-unprompted line, since such surfaces run no session hooks), and
#                procedure.md beside it, the body as it stands in the kit. Both are refreshed on every
#                run (place_generated), so a changed command reaches the skills with no merge step.
#     A command named after its own plugin is not namespaced (closeout's is /closeout on every
#     surface); the rest are <plugin> then <command>, joined however the surface joins names.
#     A new surface is a new case: it sets dest (and root, when it writes outside the repository)
#     and writes the file to $t; the loop, the naming and the placing are shared.
# fm_body <markdown>: everything after the front matter.
fm_body() { awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } !fm' "$1"; }
generate_commands() { # <format>
    local fmt="$1" src plugin cmd ns desc offer t dest root name ptr p tgt
    for src in "${PLUGIN_SRC:-$KIT/plugins}"/*/commands/*.md; do
        [[ -f "$src" ]] || continue
        plugin="$(basename "$(dirname "$(dirname "$src")")")" cmd="$(basename "$src" .md)"
        ns="$plugin"; [[ "$plugin" == "$cmd" ]] && ns=""
        # The description comes from the command's own front matter, so no surface can drift from it.
        desc="$(awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { exit } fm && sub(/^description:[[:space:]]*/, "") { print; exit }' "$src")"
        [[ -n "$desc" ]] || die "no description in the front matter of $src"
        offer="$(awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { exit } fm && sub(/^offer-unprompted:[[:space:]]*/, "") { print; exit }' "$src")"
        t="$(mktemp "${TMPDIR:-/tmp}/aw.XXXXXX")" root="$TARGET"
        case "$fmt" in
            gemini)
                dest=".gemini/commands/${ns:+$ns/}$cmd.toml"
                # The body becomes a TOML literal string, which cannot hold three single quotes, and
                # Gemini CLI would run !{...} and expand @{...} rather than pass them through as text.
                if fm_body "$src" | grep -qE "'''|[!@][{]"; then
                    rm -f "$t"; die "$src contains ''', !{ or @{, which a Gemini CLI command cannot carry as written"
                fi
                {
                    printf '# Generated by install.sh from plugins/%s/commands/%s.md: edit that file, then re-run the installer.\n' "$plugin" "$cmd"
                    printf 'description = "%s"\n' "$(printf '%s' "$desc" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
                    printf "prompt = '''\n"
                    fm_body "$src"
                    printf "'''\n"
                } > "$t" ;;
            skills)
                root="$SKILLS_DIR" name="${ns:+$ns-}$cmd" dest="$name/SKILL.md"
                # Where the skill points, as a path from the repository root. The kit inside the
                # repository (a submodule, or the kit's own checkout) is pointed at directly; a vendored
                # install at its copy under .claude/plugins/; with neither, there is no path in the
                # repository to give, and procedure.md is the whole of it.
                ptr="" p="$(cd "$(dirname "$src")" 2>/dev/null && pwd -P)/$cmd.md"
                tgt="$(cd "$TARGET" 2>/dev/null && pwd -P || echo "$TARGET")"
                case "$p" in "$tgt"/*) ptr="${p#"$tgt"/}" ;; esac
                # The vendored copy is named only while it says what procedure.md says. A team that kept
                # an older copy (the newer one waiting as .kit-incoming) would otherwise be told the two
                # are one procedure when they are not; until they merge, procedure.md is the whole of it.
                local vend="$TARGET/.claude/plugins/$plugin/commands/$cmd.md"
                if [[ -z "$ptr" && -f "$vend" ]]; then
                    fm_body "$vend" > "$t.a"; fm_body "$src" > "$t.b"
                    if cmp -s "$t.a" "$t.b"; then ptr=".claude/plugins/$plugin/commands/$cmd.md"
                    else notes+=("skill $name follows procedure.md: the vendored .claude/plugins/$plugin/commands/$cmd.md differs from the kit's (merge its .kit-incoming, then re-run)"); fi
                    rm -f "$t.a" "$t.b"
                elif [[ -z "$ptr" && $DRY -eq 1 && $SKILLS_ONLY -eq 0 && "$PLUGIN" == "vendor" ]] && has_surface claude; then
                    ptr=".claude/plugins/$plugin/commands/$cmd.md"
                fi
                # The description is a double-quoted YAML string: backslashes and quotes escaped.
                desc="${desc%.}. The kit's /${ns:+$ns:}$cmd command, as a skill.${offer:+ $offer}"
                {
                    printf -- '---\nname: %s\n' "$name"
                    printf 'description: "%s"\n---\n\n' "$(printf '%s' "$desc" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
                    printf '<!-- Generated by install.sh from plugins/%s/commands/%s.md: edit that file, then re-run the installer. -->\n\n' "$plugin" "$cmd"
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
                    printf '`/workspace:hygiene`, `/closeout`), that is the skill of the same name joined by a hyphen\n'
                    printf 'here (`projects-new`, `workspace-hygiene`, `closeout`): name it that way to the person.\n'
                    printf 'This surface runs no session hooks, so anything the procedure leaves to a hook is offered\n'
                    printf 'in words instead. If it cannot read the repository'"'"'s files, say so first and ask the person\n'
                    printf 'to share the ones the procedure reads; if it cannot write them, give each change as the\n'
                    printf 'exact text to paste and the path it goes to, and make nothing else up.\n'
                } > "$t"
                local tp; tp="$(mktemp "${TMPDIR:-/tmp}/aw.XXXXXX")"
                fm_body "$src" > "$tp"; place_generated "$tp" "$name/procedure.md" "$root"; rm -f "$tp" ;;
            *) rm -f "$t"; die "generate_commands: no output format called $fmt" ;;
        esac
        place_generated "$t" "$dest" "$root"; rm -f "$t"
    done
}
# The report, printed at the end of every run.
report() {
    say() { local label="$1"; shift; [[ $# -gt 0 ]] || return 0; echo "$label"; printf '  %s\n' "$@"; }
    echo
    [[ $DRY -eq 1 ]] && echo "Dry run — nothing written." && echo
    if [[ $SKILLS_ONLY -eq 1 ]]; then echo "Skills written to $SKILLS_DIR, pointing into $TARGET"; else echo "Kit deployed to $TARGET"; fi
    echo
    say "Added:" ${added[@]+"${added[@]}"}
    say "Merged (JSON, additive):" ${merged[@]+"${merged[@]}"}
    say "Regenerated from the kit's command files:" ${regenerated[@]+"${regenerated[@]}"}
    say "Already up to date:" ${same[@]+"${same[@]}"}
    say "Existing file kept; kit version written beside it as .kit-incoming — merge by hand:" ${incoming[@]+"${incoming[@]}"}
    say "Worth knowing:" ${notes[@]+"${notes[@]}"}
    echo
    if [[ $DRY -eq 0 && $SKILLS_ONLY -eq 1 ]]; then
        echo "Next: load the skills into the assistant (a skills folder it reads, or one upload per skill folder)."
        echo "  Re-run this after updating the kit: the skills are regenerated from the command files."
    elif [[ $DRY -eq 0 ]]; then
        # A stand-in is an angle-bracketed phrase with a space in it; path patterns like <name> are not.
        n="$(tr '\n' ' ' < "$TARGET/AGENTS.md" | grep -o '<[A-Za-z][^<>]* [^<>]*>' | wc -l | tr -d ' ')"
        echo "Next:"
        if [[ $claude_kept -eq 1 ]]; then
            # A CLAUDE.md of the repository's own means a system was here first: the quick-start maps it
            # onto the kit rather than filling in AGENTS.md, so the stand-in count would mislead.
            kept=(CLAUDE.md)
            for f in projects/INDEX.md logs/decisions.md; do [[ ! -e "$TARGET/$f.kit-incoming" ]] || kept+=("$f"); done
            case ${#kept[@]} in
                1) kept="CLAUDE.md was" ;;
                2) kept="${kept[0]} and ${kept[1]} were" ;;
                *) kept="${kept[0]}, ${kept[1]} and ${kept[2]} were" ;;
            esac
            echo "  1. Your own $kept kept. Run /workspace:quick-start in Claude Code (or the"
            echo "     workspace-quick-start skill): it maps your system onto the kit and changes nothing without your yes."
        else
            echo "  1. Open the repository in Claude Code and run /workspace:quick-start (or the workspace-quick-start"
            echo "     skill). It interviews you for the rest — AGENTS.md has $n answers still to fill in — then offers"
            echo "     /projects:new for the first projects."
        fi
        [[ "$PLUGIN" == "none" ]] && has_surface claude && ! has_surface gemini && \
            echo "     With --plugin none the workspace plugin is not installed: add it, or follow the kit's plugins/workspace/commands/quick-start.md by hand."
        has_surface claude && [[ "$PLUGIN" != "none" ]] && \
            echo "  2. Each person, in Claude Code: trust the folder, then approve the closeout and projects plugins' hooks when asked."
        [[ -n "$SKILLS_DIR" ]] && \
            echo "     Skills for a desktop assistant are in $SKILLS_DIR, one folder per command. Where the assistant" && \
            echo "     reads a skills folder, point it at this one; where it takes uploads, zip each folder and upload it."
        [[ $PILOT -eq 1 ]] && echo "  3. Put the team's own build list into pilot/build-list.md, commit, then run pilot/measure.sh."
        echo "  Review with: git -C \"$TARGET\" status"
    fi
}

work="$(mktemp -d "${TMPDIR:-/tmp}/aw.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# A CLAUDE.md that is not the kit's one-line import belongs to a system that was here first.
claude_kept=0
if [[ $SKILLS_ONLY -eq 0 ]] && has_surface claude && [[ -e "$TARGET/CLAUDE.md" ]] \
    && ! cmp -s <(render "$KIT/team/CLAUDE.md") "$TARGET/CLAUDE.md"; then
    claude_kept=1
fi

# With --skills-only, the skills are the whole job: nothing else reaches the repository.
if [[ $SKILLS_ONLY -eq 1 ]]; then
    generate_commands skills
    report
    exit 0
fi

# The surface table in AGENTS.md §4 says what this install actually set up, because every session
# reads it. The Claude Code row names the plugins and their hooks only when they were installed. Each
# other surface installed gets its own row; with none, the row stays a stand-in for the quick-start to
# fill with the team's other surface, or to remove.
if [[ "$PLUGIN" == "none" ]]; then
    claude_row='| Claude Code | `CLAUDE.md`, which imports this file | The kit'"'"'s plugins are not installed here (`install.sh --plugin none`); add them to get `/closeout`, `/projects:*`, `/workspace:*` and their hooks |'
else
    claude_row='| Claude Code | `CLAUDE.md`, which imports this file | Plugins closeout, projects, workspace: `/closeout`, `/projects:*`, `/workspace:*`; the closeout end-of-session capture and next-session review, and the projects session-start line |'
fi
other_rows=""
if has_surface gemini; then
    other_rows+='| Gemini CLI | This file, via `.gemini/settings.json` | The same commands, as wrappers in `.gemini/commands/` generated from the plugin files; no end-of-session capture |'$'\n'
fi
if [[ -n "$SKILLS_DIR" ]]; then
    # A skill can name a command file in this repository only when one is there: the vendored plugins,
    # or the kit itself inside the repository. Otherwise it carries its procedure beside it.
    kit_real="$(cd "$KIT" && pwd -P)" target_real="$(cd "$TARGET" 2>/dev/null && pwd -P || echo "$TARGET")"
    if { [[ "$PLUGIN" == "vendor" ]] && has_surface claude; } || [[ "$kit_real" == "$target_real"/* ]]; then
        skills_how='pointing at the command files in this repository'
    else
        skills_how='each carrying its procedure beside it as `procedure.md`'
    fi
    other_rows+='| Desktop assistant | This file, read by the `workspace-quick-start` and other kit skills when they run | One skill per command, generated by `install.sh --skills-dir` and '"$skills_how"'; no session hooks, so the skills say when to offer the board and closeout |'$'\n'
fi
[[ -n "$other_rows" ]] || other_rows='| <second surface> | This file + <config> | <what differs> |'$'\n'

# 1 · The always-loaded file. MANIFEST.md becomes AGENTS.md, with the single-person header note and
#     §1 swapped for the team versions, and the surface table filled in.
how_read='Claude Code reads it through `CLAUDE.md`'
has_surface claude || how_read=''
has_surface gemini && how_read="${how_read:+$how_read; }Gemini CLI through \`.gemini/settings.json\`"
[[ -n "$SKILLS_DIR" ]] && how_read="${how_read:+$how_read; }the kit's skills when they run"
{
    echo "# $TEAM — Team Manifest"
    echo
    echo "> The team's always-loaded file, read in full by every agent surface at the start of every"
    echo "> session. ${how_read:+${how_read}.}"
    echo "> It is a budget, not a folder: an addition names the line it replaces. Changes go by pull"
    echo "> request to the standards owner. Angle-bracket placeholders are the team's to fill in."
    echo
    replace_section "$KIT/MANIFEST.md" '^## 1[.] Who this is for' '^---$' "$KIT/team/who-this-team-is.md" \
        | awk 'f; /^---$/ && !f { f = 1; print }' \
        | CLAUDE_ROW="$claude_row" OTHER_ROWS="$other_rows" awk '
            # ENVIRON rather than -v, so backslashes and backticks in the rows reach the file as written.
            $0 == "| <primary surface> | This file | <permission model, quirks> |" { print ENVIRON["CLAUDE_ROW"]; next }
            $0 == "| <second surface> | This file + <config> | <what differs> |" { printf "%s", ENVIRON["OTHER_ROWS"]; next }
            { print }' \
        | sed -e "s#^\*Last updated: <YYYY-MM-DD>\*#*Last updated: $TODAY*#"
} > "$work/AGENTS.md"
place_rendered "$work/AGENTS.md" AGENTS.md

# 2 · General reference and rituals. memory-layers §3 is pre-filled for this setup.
replace_section "$KIT/docs/memory-layers.md" '^## 3[.] Where each type lives' '^Two rules make the table usable' \
    "$KIT/team/memory-layers-stores.md" > "$work/memory-layers.md"
place_rendered "$work/memory-layers.md" docs/memory-layers.md
for f in docs/workspace-map.md docs/documentation-register.md rituals/closeout.md rituals/weekly-hygiene.md \
         templates/project-decisions.md templates/project-readme.md templates/person-profile.md \
         templates/verification-standard.md templates/catalogue.md; do
    place_rendered "$KIT/$f" "$f"
done
place "$KIT/docs/images/context-taxonomy.svg" docs/images/context-taxonomy.svg

# 3 · Empty homes for the canonical files the manifest points at, so every promised path exists.
printf '# Projects\n\nThe register: one line per project, linking its folder.\n\n## Active\n\n| Project | Folder | State | Owner | One-liner |\n|---|---|---|---|---|\n\n## Paused\n\n## Done\n' > "$work/INDEX.md"
place "$work/INDEX.md" projects/INDEX.md
printf '# Decisions\n\nCross-project decisions only. The filter and the entry format are in `templates/project-decisions.md`.\n' > "$work/decisions.md"
place "$work/decisions.md" logs/decisions.md
printf '# Glossary\n\nThe team'"'"'s vocabulary, acronyms and internal names. One line each.\n\n| Term | Meaning |\n|---|---|\n' > "$work/glossary.md"
place "$work/glossary.md" memory/glossary.md
printf '# People\n\nOne file per person, from `templates/person-profile.md`: who owns what, and who to go to for what.\n' > "$work/people.md"
place "$work/people.md" memory/people/README.md
# The projects plugin's extension point: prose conventions every projects command reads first.
place_rendered "$KIT/team/projects-conventions.md" .claude/projects.md
# Closeout's extension point, the team's tiers and house rules: wherever /closeout can run — the
# Claude Code plugin, the generated Gemini CLI command, or the closeout skill. All read this one file.
# Where the repository keeps a CLAUDE.md of its own, that file stays the always-loaded one, and the
# house rule says so rather than sending promotions to an AGENTS.md nothing here loads.
if { has_surface claude && [[ "$PLUGIN" != "none" ]]; } || has_surface gemini || [[ -n "$SKILLS_DIR" ]]; then
    if [[ $claude_kept -eq 1 ]]; then
        awk '/^- \*\*The always-loaded file is `AGENTS.md`/ {
                 print "- **The always-loaded file is `CLAUDE.md`**, this repository'"'"'s own, kept when the kit was installed;"
                 print "  `/workspace:quick-start` confirms it with the person. Promotions into working standards go there."
                 skip = 1; next }
             skip && /^  / { next }
             { skip = 0; print }' "$KIT/team/closeout-conventions.md" > "$work/closeout-conventions.md"
        place_rendered "$work/closeout-conventions.md" .claude/closeout.md
    else
        place_rendered "$KIT/team/closeout-conventions.md" .claude/closeout.md
    fi
fi
printf '# Audits\n\nDated reports from the weekly hygiene pass and the monthly register audit. Committed, so the trail reaches everyone.\n' > "$work/audits.md"
place "$work/audits.md" audits/README.md
# The team inbox: /projects:capture adds a line, /projects:review empties it.
place "$KIT/team/inbox.md" inbox.md

# 4 · Governance for a shared always-loaded tier.
place_rendered "$KIT/team/CODEOWNERS" .github/CODEOWNERS
place_rendered "$KIT/team/pull_request_template.md" .github/pull_request_template.md
lc_team="$(printf '%s' "$TEAM" | tr '[:upper:]' '[:lower:]')"
if [[ "$lc_team" == solo || "$TEAM" == "$OWNER" ]]; then
    notes+=(".github/ routes changes to the always-loaded file to the standards owner for review; with one person it is optional, and the quick-start offers to remove it")
fi

# 5 · Claude Code.
if has_surface claude; then
    place_rendered "$KIT/team/CLAUDE.md" CLAUDE.md
    if [[ "$PLUGIN" != "none" ]]; then
        if [[ "$PLUGIN" == "vendor" ]]; then
            # The plugins ship inside this kit, so vendoring is a local copy with no network needed.
            # They are laid down as one small marketplace, so a single settings entry registers them all.
            PLUGIN_SRC="${PLUGIN_SRC:-$KIT/plugins}"
            rev="$(git -C "$KIT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
            # Built from a working tree with changes, the commit alone would not say what was copied.
            [[ -z "$(git -C "$KIT" status --porcelain 2>/dev/null)" ]] || rev="$rev + uncommitted changes"
            vendored=""
            for name in closeout projects workspace; do
                src="$PLUGIN_SRC/$name"
                [[ -f "$src/.claude-plugin/plugin.json" ]] || die "no $name plugin at $src — pass --plugin-src"
                while IFS= read -r f; do
                    place "$src/$f" ".claude/plugins/$name/$f"
                done < <(cd "$src" && find . -type f ! -path './.git/*' ! -name .DS_Store | sed 's#^\./##' | sort)
                vendored+="$name $(jq -r .version "$src/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)"$'\n'
            done
            cat > "$work/marketplace.json" <<JSON
{
  "name": "agentic-workspace",
  "description": "Vendored from github.com/$PLUGIN_REPO by install.sh.",
  "owner": { "name": "Robert Peake", "url": "https://github.com/cyberscribe" },
  "plugins": [
    { "name": "closeout", "source": "./closeout" },
    { "name": "projects", "source": "./projects" },
    { "name": "workspace", "source": "./workspace" }
  ]
}
JSON
            place "$work/marketplace.json" .claude/plugins/.claude-plugin/marketplace.json
            # The local checkout is named too, so pilot/measure.sh and the installer can be found
            # again from here without asking.
            printf 'Vendored from github.com/%s (plugins/)\nkit commit: %s\nkit checkout: %s (on the machine that ran the installer)\n\n%s\nTo update, re-run install.sh from a newer checkout of the kit;\nchanged files arrive as .kit-incoming for review.\n' \
                "$PLUGIN_REPO" "$rev" "$KIT" "$vendored" > "$work/VENDORED"
            place "$work/VENDORED" .claude/plugins/VENDORED
            source_json='{ "source": "directory", "path": ".claude/plugins" }'
        else
            source_json="{ \"source\": \"github\", \"repo\": \"$PLUGIN_REPO\" }"
        fi
        sed "s|__MARKETPLACE_SOURCE__|$source_json|" "$KIT/team/claude-settings.json" > "$work/claude-settings.json"
        merge_json "$work/claude-settings.json" .claude/settings.json
    fi
fi

# 6 · Commands on the surfaces that do not load Claude Code plugins (generate_commands, above).
if has_surface gemini; then
    merge_json "$KIT/team/gemini-settings.json" .gemini/settings.json
    generate_commands gemini
fi
if [[ -n "$SKILLS_DIR" ]]; then
    # Skills of the person's own that do a kit skill's job would both answer the same request until
    # the quick-start folds them; say so now rather than leave it to be found.
    for d in "$SKILLS_DIR"/*/; do
        [[ -f "$d/SKILL.md" ]] && ! grep -qs 'Generated by install.sh from plugins/' "$d/SKILL.md" || continue
        own="$(basename "$d")"
        for kw in closeout review board hygiene; do
            case "$(printf '%s' "$own" | tr '[:upper:]' '[:lower:]')" in
                *"$kw"*) notes+=("skill $own overlaps the kit's $kw skill; /workspace:quick-start folds the two into one"); break ;;
            esac
        done
    done
    generate_commands skills
fi

# 7 · Pilot layer.
if [[ $PILOT -eq 1 ]]; then
    place_rendered "$KIT/pilot/README.md" pilot/README.md
    place "$KIT/pilot/build-list.md" pilot/build-list.md
    place "$KIT/pilot/measure.sh" pilot/measure.sh
    [[ $DRY -eq 1 ]] || chmod 755 "$TARGET/pilot/measure.sh"
fi

report
