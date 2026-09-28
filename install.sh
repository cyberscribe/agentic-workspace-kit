#!/usr/bin/env bash
# Deploys the workspace context kit into a team's shared repository.
#
#   ./install.sh --target ../team-workspace --team "Data Platform" --owner "Sam" --owner-handle "@sam" --pilot
#
# What it lays down:
#   - the kit (docs/, rituals/, templates/, logs/, projects/INDEX.md, memory/) with AGENTS.md as the
#     one always-loaded file, and §1 rewritten for a team rather than a person
#   - Claude Code: CLAUDE.md as a one-line import of AGENTS.md, and the closeout plugin registered in
#     .claude/settings.json with .claude/closeout.md pointing it at the kit's taxonomy
#   - Gemini CLI: .gemini/settings.json loading AGENTS.md, and a /closeout command
#   - .github/CODEOWNERS and a pull request template for the always-loaded tier
#   - with --pilot: pilot/ (protocol, build list, metrics script) and a first metrics row
#
# It never overwrites. An existing file with different content is left alone and the kit's version is
# written beside it as <file>.kit-incoming, so the merge is a human decision. JSON settings are the
# exception: they are merged additively with jq, which only ever adds keys and list entries.
# Running it twice is safe.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="" TEAM="" OWNER="" OWNER_HANDLE="" PLUGIN="vendor" PLUGIN_SRC="" SURFACES="claude,gemini" PILOT=0 DRY=0
PLUGIN_REPO="cyberscribe/agentic-workspace-kit"

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; cat <<'USAGE'

Options:
  --target DIR          the team repository (a git repository; created if --init is also given)
  --team NAME           team name, written into AGENTS.md and the closeout conventions
  --owner NAME          standards owner, who reviews changes to the always-loaded tier
  --owner-handle @h     their GitHub/GitLab handle for CODEOWNERS (defaults to a placeholder)
  --plugin MODE         vendor (default) | github | none
                          vendor: copy plugins/closeout from this kit into .claude/plugins/closeout —
                                  pinned, reviewable, no network or GitHub access needed
                          github: register this kit's repository as the marketplace and let Claude
                                  Code fetch the plugin from it
  --plugin-src DIR      vendor the plugin from somewhere other than this kit's plugins/closeout
  --surfaces LIST       claude,gemini (default) | claude | gemini
  --pilot               add pilot/ and record the first metrics row
  --init                git init the target if it is not already a repository
  --dry-run             say what would happen, write nothing
USAGE
}

INIT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --team) TEAM="$2"; shift 2 ;;
        --owner) OWNER="$2"; shift 2 ;;
        --owner-handle) OWNER_HANDLE="$2"; shift 2 ;;
        --plugin) PLUGIN="$2"; shift 2 ;;
        --plugin-src) PLUGIN_SRC="$2"; shift 2 ;;
        --surfaces) SURFACES="$2"; shift 2 ;;
        --pilot) PILOT=1; shift ;;
        --init) INIT=1; shift ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

die() { echo "install.sh: $*" >&2; exit 1; }
[[ -n "$TARGET" ]] || { usage; exit 1; }
[[ "$PLUGIN" =~ ^(vendor|github|none)$ ]] || die "--plugin must be vendor, github or none"
TEAM="${TEAM:-<team name>}"
OWNER="${OWNER:-<standards owner>}"
OWNER_HANDLE="${OWNER_HANDLE:-@<standards-owner-handle>}"
TODAY="$(date +%F)"
has_surface() { [[ ",$SURFACES," == *",$1,"* ]]; }

if [[ ! -d "$TARGET" ]]; then
    [[ $INIT -eq 1 ]] || die "$TARGET does not exist (add --init to create it)"
    [[ $DRY -eq 1 ]] || mkdir -p "$TARGET"
fi
if [[ $DRY -eq 0 ]] && ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    [[ $INIT -eq 1 ]] || die "$TARGET is not a git repository (add --init to create one)"
    git -C "$TARGET" init -q
fi
TARGET="$(cd "$TARGET" 2>/dev/null && pwd || echo "$TARGET")"

# Report buckets, printed at the end.
added=() same=() incoming=() merged=()

# Substitutes the install-time values into a template on its way to the target.
sed_escape() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }
render() {
    local team owner handle
    team="$(sed_escape "$TEAM")"; owner="$(sed_escape "$OWNER")"; handle="$(sed_escape "$OWNER_HANDLE")"
    sed -e "s|__TEAM__|$team|g" -e "s|__OWNER__|$owner|g" -e "s|__OWNER_HANDLE__|$handle|g" \
        -e "s|__DATE__|$TODAY|g" -e 's|MANIFEST\.md|AGENTS.md|g' "$1"
}

# place <content-file> <relative-dest>: the one place a file reaches the target.
place() {
    local src="$1" rel="$2" dest="$TARGET/$2"
    if [[ -e "$dest" ]]; then
        if cmp -s "$src" "$dest"; then same+=("$rel"); return; fi
        incoming+=("$rel")
        [[ $DRY -eq 1 ]] || cp "$src" "$dest.kit-incoming"
        return
    fi
    added+=("$rel")
    [[ $DRY -eq 1 ]] || { mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"; }
}

# place_rendered <kit-file> <relative-dest>
place_rendered() { local t; t="$(mktemp)"; render "$1" > "$t"; place "$t" "$2"; rm -f "$t"; }

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
    t="$(mktemp)"
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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 1 · The always-loaded file. MANIFEST.md becomes AGENTS.md, with the single-person header note and
#     §1 swapped for the team versions, and the surface table filled in.
{
    echo "# $TEAM — Team Manifest"
    echo
    echo "> The team's always-loaded file, read in full by every agent surface at the start of every"
    echo "> session. Claude Code reads it through \`CLAUDE.md\`; Gemini CLI through \`.gemini/settings.json\`."
    echo "> It is a budget, not a folder: an addition names the line it replaces. Changes go by pull"
    echo "> request to the standards owner. Angle-bracket placeholders are the team's to fill in."
    echo
    replace_section "$KIT/MANIFEST.md" '^## 1[.] Who this is for' '^---$' "$KIT/team/who-this-team-is.md" \
        | awk 'f; /^---$/ && !f { f = 1; print }' \
        | sed -e 's#^| <primary surface> | This file | <permission model, quirks> |$#| Claude Code | `CLAUDE.md`, which imports this file | Closeout plugin: `/closeout`, plus an end-of-session capture hook |#' \
              -e 's#^| <second surface> | This file + <config> | <what differs> |$#| Gemini CLI | This file, via `.gemini/settings.json` | `/closeout` command only; no end-of-session capture |#' \
              -e "s#^\*Last updated: <YYYY-MM-DD>\*#*Last updated: $TODAY*#"
} > "$work/AGENTS.md"
place_rendered "$work/AGENTS.md" AGENTS.md

# 2 · General reference and rituals. memory-layers §3 is pre-filled for this setup.
replace_section "$KIT/docs/memory-layers.md" '^## 3[.] Where each type lives' '^Two rules make the table usable' \
    "$KIT/team/memory-layers-stores.md" > "$work/memory-layers.md"
place_rendered "$work/memory-layers.md" docs/memory-layers.md
for f in docs/workspace-map.md docs/documentation-register.md rituals/closeout.md rituals/weekly-hygiene.md \
         templates/project-decisions.md templates/project-readme.md templates/person-profile.md; do
    place_rendered "$KIT/$f" "$f"
done
place "$KIT/docs/images/context-taxonomy.svg" docs/images/context-taxonomy.svg

# 3 · Empty homes for the canonical files the manifest points at, so every promised path exists.
printf '# Projects\n\nThe register: one line per project, linking its folder.\n\n## Active\n\n| Project | Folder | One-liner |\n|---|---|---|\n\n## Paused\n\n## Done\n' > "$work/INDEX.md"
place "$work/INDEX.md" projects/INDEX.md
printf '# Decisions\n\nCross-project decisions only. The filter and the entry format are in `templates/project-decisions.md`.\n' > "$work/decisions.md"
place "$work/decisions.md" logs/decisions.md
printf '# Glossary\n\nThe team'"'"'s vocabulary, acronyms and internal names. One line each.\n\n| Term | Meaning |\n|---|---|\n' > "$work/glossary.md"
place "$work/glossary.md" memory/glossary.md
printf '# People\n\nOne file per person, from `templates/person-profile.md`: who owns what, and who to go to for what.\n' > "$work/people.md"
place "$work/people.md" memory/people/README.md
printf '# Audits\n\nDated reports from the weekly hygiene pass and the monthly register audit. Committed, so the trail reaches everyone.\n' > "$work/audits.md"
place "$work/audits.md" audits/README.md

# 4 · Governance for a shared always-loaded tier.
place_rendered "$KIT/team/CODEOWNERS" .github/CODEOWNERS
place_rendered "$KIT/team/pull_request_template.md" .github/pull_request_template.md

# 5 · Claude Code.
if has_surface claude; then
    place_rendered "$KIT/team/CLAUDE.md" CLAUDE.md
    if [[ "$PLUGIN" != "none" ]]; then
        place_rendered "$KIT/team/closeout-conventions.md" .claude/closeout.md
        if [[ "$PLUGIN" == "vendor" ]]; then
            # The plugin ships inside this kit, so vendoring is a local copy with no network needed.
            PLUGIN_SRC="${PLUGIN_SRC:-$KIT/plugins/closeout}"
            [[ -f "$PLUGIN_SRC/.claude-plugin/plugin.json" ]] || die "no closeout plugin at $PLUGIN_SRC — pass --plugin-src"
            ver="$(jq -r .version "$PLUGIN_SRC/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)"
            rev="$(git -C "$KIT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
            while IFS= read -r f; do
                place "$PLUGIN_SRC/$f" ".claude/plugins/closeout/$f"
            done < <(cd "$PLUGIN_SRC" && find . -type f ! -path './.git/*' ! -name .DS_Store | sed 's#^\./##' | sort)
            printf 'Vendored from github.com/%s (plugins/closeout)\nversion: %s\nkit commit: %s\n\nTo update, re-run install.sh from a newer checkout of the kit;\nchanged files arrive as .kit-incoming for review.\n' \
                "$PLUGIN_REPO" "$ver" "$rev" > "$work/VENDORED"
            place "$work/VENDORED" .claude/plugins/closeout/VENDORED
            source_json='{ "source": "directory", "path": ".claude/plugins/closeout" }'
        else
            source_json="{ \"source\": \"github\", \"repo\": \"$PLUGIN_REPO\" }"
        fi
        sed "s|__MARKETPLACE_SOURCE__|$source_json|" "$KIT/team/claude-settings.json" > "$work/claude-settings.json"
        merge_json "$work/claude-settings.json" .claude/settings.json
    fi
fi

# 6 · Gemini CLI.
if has_surface gemini; then
    merge_json "$KIT/team/gemini-settings.json" .gemini/settings.json
    place "$KIT/team/gemini-closeout.toml" .gemini/commands/closeout.toml
fi

# 7 · Pilot layer.
if [[ $PILOT -eq 1 ]]; then
    place_rendered "$KIT/pilot/README.md" pilot/README.md
    place "$KIT/pilot/build-list.md" pilot/build-list.md
    place "$KIT/pilot/measure.sh" pilot/measure.sh
    [[ $DRY -eq 1 ]] || chmod +x "$TARGET/pilot/measure.sh"
fi

# Report.
say() { local label="$1"; shift; [[ $# -gt 0 ]] || return 0; echo "$label"; printf '  %s\n' "$@"; }
echo
[[ $DRY -eq 1 ]] && echo "Dry run — nothing written." && echo
echo "Kit deployed to $TARGET"
echo
say "Added:" ${added[@]+"${added[@]}"}
say "Merged (JSON, additive):" ${merged[@]+"${merged[@]}"}
say "Already up to date:" ${same[@]+"${same[@]}"}
say "Existing file kept; kit version written beside it as .kit-incoming — merge by hand:" ${incoming[@]+"${incoming[@]}"}
echo
if [[ $DRY -eq 0 ]]; then
    n="$(grep -c '<[a-zA-Z][^>]*>' "$TARGET/AGENTS.md" || true)"
    echo "Next:"
    echo "  1. Fill the angle-bracket placeholders in AGENTS.md ($n lines), starting with §1."
    [[ -e "$TARGET/CLAUDE.md.kit-incoming" ]] && \
        echo "     An existing CLAUDE.md was kept: move what the team shares into AGENTS.md, then replace CLAUDE.md with the one-line import in CLAUDE.md.kit-incoming."
    has_surface claude && [[ "$PLUGIN" != "none" ]] && \
        echo "  2. Each person, in Claude Code: trust the folder, then approve the closeout plugin's hooks when asked."
    [[ $PILOT -eq 1 ]] && echo "  3. Put the team's own build list into pilot/build-list.md, commit, then run pilot/measure.sh."
    echo "  Review with: git -C \"$TARGET\" status"
fi
