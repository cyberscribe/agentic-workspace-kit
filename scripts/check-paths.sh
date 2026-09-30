#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# scripts/check-paths.sh: the kit's one checker of paths and content. The kit's git hooks, the test
# suite and CI all run this file, so the rules exist once.
#
# The kit is public and the workspace around it is private. This checker is what keeps the second
# out of the first: a path outside the kit's own folders, a file that is private by its name, a
# symlink, a file the workspace's .gitignore keeps out, a binary or oversized blob, a word from the
# private word list, a name derived from the workspace (a project, a person, a remote, a machine
# path), a verbatim copy of a workspace file, or an attribution trailer.
#
# Every check ends allowed, refused or could-not-run, and could-not-run refuses: a check that cannot
# look is not a check that passed.
#
# Written for bash 3.2 (macOS /bin/bash). Only git and POSIX tools: the hooks run it, and GUI git
# clients run hooks with a minimal PATH, so there is no jq here.

set -uo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/check-paths.sh [--root DIR] [--prefix P] [--workspace WS] [--content] SOURCE
       scripts/check-paths.sh --list

SOURCE is one of:
  --staged                              the index (honours GIT_INDEX_FILE)
  --push REMOTE LOCAL_SHA REMOTE_SHA    the commits a push sends (add --ref REF for the pushed ref)
  --commits A..B                        each commit in the range
  --all                                 every file in HEAD's tree
  --paths                               paths on stdin, one per line (path rules only)
  --message FILE                        a commit message file (the word list and attribution rules)

--root DIR       the kit checkout to check (default: the repository around the current folder)
--prefix P       judge each path as P/<path> (a subtree mirror push: aw.mirror.<remote>.prefix)
--workspace WS   the workspace around the kit, for its .gitignore, derived names and copies;
                 empty or absent, those checks print a note and do not run
--content        add the content rules (binary, size, words, derived names, copies, attribution)

One line per finding on stdout: refused<TAB><item><TAB><reason>, or could-not-run<TAB><rule><TAB><reason>.
Exit 0 when everything is allowed, 1 when anything is refused or could not run, 2 for a usage error.
EOF
}

CP_DIRS="plugins docs templates rituals scripts githooks pilot tests lib .claude-plugin .github"
CP_DATA_EXT="csv xlsx xls pptx docx pdf sqlite db jsonl"
CP_FILES=".gitignore .gitattributes LICENSE README.md CHANGELOG.md CONTRIBUTING.md CLAUDE.kit.md install.sh setup.sh"

cp_list() {
    local d out=""
    for d in $CP_DIRS; do out+="$d/ "; done
    printf 'directories: %s\n' "${out% }"
    printf 'root files:  %s\n' "$CP_FILES"
}

root="" prefix="" ws="" ws_given=0 content=0 source="" ref=""
push_remote="" push_local="" push_rsha="" range="" msgfile=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; root="$2"; shift 2 ;;
        --prefix) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; prefix="${2%/}"; shift 2 ;;
        --workspace) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; ws="$2"; ws_given=1; shift 2 ;;
        --content) content=1; shift ;;
        --ref) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; ref="$2"; shift 2 ;;
        --list) cp_list; exit 0 ;;
        --staged|--all|--paths) [[ -z "$source" ]] || { usage >&2; exit 2; }; source="${1#--}"; shift ;;
        --push)
            [[ -z "$source" && $# -ge 4 ]] || { usage >&2; exit 2; }
            source=push push_remote="$2" push_local="$3" push_rsha="$4"; shift 4 ;;
        --commits)
            [[ -z "$source" && $# -ge 2 && "$2" == *..* ]] || { usage >&2; exit 2; }
            source=commits range="$2"; shift 2 ;;
        --message)
            [[ -z "$source" && $# -ge 2 ]] || { usage >&2; exit 2; }
            source=message msgfile="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ -n "$source" ]] || { usage >&2; exit 2; }

CP_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CP_KIT="$(cd "$CP_SELF/.." && pwd -P)"
if [[ ! -f "$CP_KIT/lib/common.sh" ]]; then
    printf 'could-not-run\tsetup\tlib/common.sh is missing beside this checker\n'
    exit 1
fi
# shellcheck source=../lib/common.sh
. "$CP_KIT/lib/common.sh"

if [[ -z "$root" ]]; then
    root="$(git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)" || { echo "check-paths: not inside a git repository" >&2; exit 2; }
fi
[[ -d "$root" ]] || { echo "check-paths: no folder at $root" >&2; exit 2; }
root="$(cd "$root" && pwd -P)"
cd "$root" || exit 2
git --no-optional-locks rev-parse --git-dir >/dev/null 2>&1 || { echo "check-paths: $root is not a git repository" >&2; exit 2; }

# The findings file collects every line before anything is printed, so duplicates (a merge compared
# with each parent, say) print once.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aw-check.XXXXXX" 2>/dev/null)" || {
    printf 'could-not-run\ttemporary folder\tcannot create one under %s\n' "${TMPDIR:-/tmp}"
    echo "check-paths: could not run" >&2
    exit 1
}
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/findings"

g() { git --no-optional-locks "$@"; }
refused() { printf 'refused\t%s\t%s\n' "$1" "$2" >> "$tmp/findings"; }
cnr() { printf 'could-not-run\t%s\t%s\n' "$1" "$2" >> "$tmp/findings"; }
note() { printf 'note: %s\n' "$*" >&2; }

for t in awk sed grep sort; do
    command -v "$t" >/dev/null 2>&1 || cnr "$t" "$t is not on PATH"
done

if [[ $ws_given -eq 1 && -n "$ws" ]]; then
    if [[ -d "$ws" ]]; then ws="$(cd "$ws" && pwd -P)"; else cnr workspace "no folder at the workspace path given"; ws=""; fi
else
    ws=""
fi

ZERO_RE='^0+$'
EMPTY_TREE="$(g hash-object -t tree /dev/null)"

# ---- Collecting what to check -----------------------------------------------------------------
# entries: key<TAB>newmode<TAB>oldsha<TAB>newsha<TAB>path, one line per file added or changed.
# The key is "-" for the index and for --all, and the commit's sha in a commit walk.
: > "$tmp/entries"; : > "$tmp/binary"; : > "$tmp/messages"

# add_raw <key> <git raw -z args...>: appends entries from git's raw -z output.
add_raw() {
    local key="$1" meta path om nm os ns st; shift
    g "$@" > "$tmp/raw" 2>"$tmp/raw.err" || { cnr "git" "git ${1:-} failed: $(head -n 1 "$tmp/raw.err")"; return 1; }
    while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
        meta="${meta#:}"
        read -r om nm os ns st <<EOF
$meta
EOF
        case "$st" in D*) continue ;; esac
        case "$path" in *$'\t'*|*$'\n'*) refused "$(printf '%q' "$path")" "a tab or newline in the path"; continue ;; esac
        printf '%s\t%s\t%s\t%s\t%s\n' "$key" "$nm" "$os" "$ns" "$path" >> "$tmp/entries"
        : "$om"
    done < "$tmp/raw"
}

# add_numstat <key> <git numstat -z args...>: records binary paths (numstat prints - and -).
add_numstat() {
    local key="$1" rec a; shift
    g "$@" > "$tmp/num" 2>"$tmp/num.err" || { cnr "git" "git ${1:-} --numstat failed: $(head -n 1 "$tmp/num.err")"; return 1; }
    while IFS= read -r -d '' rec; do
        a="${rec%%$'\t'*}"
        [[ "$a" == "-" ]] || continue
        rec="${rec#*$'\t'}"; rec="${rec#*$'\t'}"
        printf '%s\t%s\n' "$key" "$rec" >> "$tmp/binary"
    done < "$tmp/num"
}

# add_message <item> <text on stdin>: one message to check, stored as item<TAB>line-number<TAB>text.
# Comment lines are dropped, and everything from git's scissors line down (the diff "git commit -v"
# shows) is not part of the message.
add_message() {
    awk -v item="$1" '
        /^# -+ >8 -+$/ { exit }
        /^#/ { next }
        { print item "\t" NR "\t" $0 }' >> "$tmp/messages"
}

# The history a copy is judged against (R5), and the tree a long line is compared with.
CP_HIST_ARGS=()
CP_LINE_BASE=""
walked=()

case "$source" in
    all)
        if g rev-parse -q --verify 'HEAD^{commit}' >/dev/null; then
            add_raw - diff-tree -r -z --no-renames --diff-filter=ACMRT "$EMPTY_TREE" HEAD
            add_numstat - diff-tree -r -z --numstat --no-renames "$EMPTY_TREE" HEAD
        fi
        CP_HIST_ARGS=(HEAD) ;;
    staged)
        base="$EMPTY_TREE"
        g rev-parse -q --verify 'HEAD^{commit}' >/dev/null && base=HEAD
        add_raw - diff-index --cached -z --no-renames --diff-filter=ACMRT "$base"
        add_numstat - diff-index --cached -z --numstat --no-renames "$base"
        CP_HIST_ARGS=(--all)
        [[ "$base" == HEAD ]] && CP_LINE_BASE=HEAD ;;
    push|commits)
        if [[ "$source" == push ]]; then
            case "$ref" in
                refs/notes/*) refused "$ref" "a notes ref is not pushed to the kit" ;;
            esac
            if [[ "$push_local" =~ $ZERO_RE ]]; then
                :   # A deletion sends no content.
            else
                rev_args=("$push_local" --not)
                if g config --get "remote.$push_remote.url" >/dev/null 2>&1; then
                    rev_args+=("--remotes=$push_remote")
                    CP_HIST_ARGS+=("--remotes=$push_remote")
                fi
                # A remote sha this repository does not have is left out: the walk then covers more,
                # never less.
                if [[ ! "$push_rsha" =~ $ZERO_RE ]] && g cat-file -e "$push_rsha^{commit}" 2>/dev/null; then
                    rev_args+=("$push_rsha")
                    CP_HIST_ARGS+=("$push_rsha")
                    CP_LINE_BASE="$push_rsha"
                fi
                if list="$(g rev-list --reverse "${rev_args[@]}" 2>"$tmp/rl.err")"; then
                    [[ -n "$list" ]] && while IFS= read -r c; do walked+=("$c"); done <<EOF
$list
EOF
                else
                    cnr "commit walk" "git rev-list could not read the commits this push sends: $(head -n 1 "$tmp/rl.err")"
                fi
                # An annotated tag carries a message of its own.
                if [[ "$(g cat-file -t "$push_local" 2>/dev/null)" == tag ]]; then
                    g cat-file tag "$push_local" | awk 'body { print; next } /^$/ { body = 1 }' \
                        | add_message "tag $(g rev-parse --short "$push_local")"
                fi
            fi
        else
            if list="$(g rev-list --reverse "$range" 2>"$tmp/rl.err")"; then
                [[ -n "$list" ]] && while IFS= read -r c; do walked+=("$c"); done <<EOF
$list
EOF
                CP_HIST_ARGS=("${range%%..*}")
                CP_LINE_BASE="${range%%..*}"
            else
                cnr "commit walk" "the range $range cannot be read: $(head -n 1 "$tmp/rl.err")"
            fi
        fi
        # With nothing already published to compare against, the history before the first commit
        # sent is the baseline.
        if [[ ${#walked[@]} -gt 0 ]]; then
            if [[ ${#CP_HIST_ARGS[@]} -eq 0 ]] && first_parent="$(g rev-parse -q --verify "${walked[0]}^" 2>/dev/null)"; then
                CP_HIST_ARGS=("$first_parent")
            fi
            if [[ -z "$CP_LINE_BASE" ]]; then
                CP_LINE_BASE="$(g rev-parse -q --verify "${walked[0]}^" 2>/dev/null)"
            fi
        fi
        for c in ${walked[@]+"${walked[@]}"}; do
            add_raw "$c" diff-tree -r -z --root --no-commit-id --no-renames -m --diff-filter=ACMRT "$c"
            add_numstat "$c" diff-tree -r -z --root --no-commit-id --no-renames -m --numstat "$c"
            g cat-file commit "$c" | awk 'body { print; next } /^$/ { body = 1 }' \
                | add_message "commit $(g rev-parse --short "$c")"
        done ;;
    paths)
        while IFS= read -r p; do
            [[ -n "$p" ]] && printf -- '-\t-\t-\t-\t%s\n' "$p" >> "$tmp/entries"
        done ;;
    message)
        if [[ -r "$msgfile" ]]; then add_message "message" < "$msgfile"
        else cnr message "the message file cannot be read"; fi ;;
esac

# item <key> <path>: how a finding names the file, with the commit in a walk.
item() { if [[ "$1" == - ]]; then printf '%s' "$2"; else printf '%s (%s)' "$2" "$(g rev-parse --short "$1")"; fi; }
# pp <path>: the path as the rules judge it, under the mirror prefix when there is one.
pp() { if [[ -n "$prefix" ]]; then printf '%s/%s' "$prefix" "$1"; else printf '%s' "$1"; fi; }

# ---- Path rules (P1-P4) -----------------------------------------------------------------------
# P2's names, each paired with where it applies: any component, or a folder only.
p2_reason() {
    local path="$1" comp last n i
    local -a parts
    IFS=/ read -r -a parts <<< "$path"
    n=${#parts[@]}
    i=0
    while [[ $i -lt $n ]]; do
        comp="${parts[$i]}"; last=0; [[ $i -eq $((n - 1)) ]] && last=1
        case "$comp" in
            .secrets) printf '.secrets'; return ;;
            settings.local.json) printf 'settings.local.json'; return ;;
            resources.local.md) printf 'resources.local.md'; return ;;
            private-terms.local) printf 'private-terms.local'; return ;;
            CLAUDE.local.md) printf 'CLAUDE.local.md'; return ;;
            *.local.*) printf '*.local.*'; return ;;
            .resources) printf '.resources'; return ;;
            *.pem) printf '*.pem'; return ;;
            *.key) printf '*.key'; return ;;
            .env) printf '.env'; return ;;
            .env.*) printf '.env.*'; return ;;
            _delete) printf '_delete'; return ;;
        esac
        if [[ $last -eq 0 ]]; then
            case "$comp" in
                *.local) printf '*.local'; return ;;
                private) printf 'private'; return ;;
                .claude) printf '.claude'; return ;;
            esac
        fi
        i=$((i + 1))
    done
    case "$path" in
        pilot/ablation-results.csv|pilot/ablation-report.md|pilot/metrics.csv) printf '%s' "$path"; return ;;
        pilot/ablations/*) printf 'pilot/ablations/'; return ;;
    esac
    case "$path" in tests/fixtures/*) return ;; esac
    local ext="${path##*/}"
    [[ "$ext" == *.* ]] || return
    ext="$(printf '%s' "${ext##*.}" | tr '[:upper:]' '[:lower:]')"
    in_list "$ext" "$CP_DATA_EXT" && printf '*.%s' "$ext"
}

in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

: > "$tmp/pp"
while IFS=$'\t' read -r key nm os ns path; do
    j="$(pp "$path")"
    it="$(item "$key" "$path")"
    if [[ "$j" == */* ]]; then
        in_list "${j%%/*}" "$CP_DIRS" || refused "$it" "outside the kit's allow-list"
    else
        in_list "$j" "$CP_FILES" || refused "$it" "outside the kit's allow-list"
    fi
    r="$(p2_reason "$j")"
    [[ -z "$r" ]] || refused "$it" "private by name ($r)"
    [[ "$nm" == 120000 ]] && refused "$it" "a symlink"
    printf '%s\t%s\n' "$j" "$it" >> "$tmp/pp"
    : "$os" "$ns"
done < "$tmp/entries"

# P4: the workspace's .gitignore, read by git itself in a throwaway repository, for the path as it
# sits under kit/ and as it would sit at the workspace root.
if [[ -z "$ws" ]]; then
    note "no workspace around this kit checkout; the workspace checks did not run"
elif [[ -s "$tmp/pp" ]]; then
    tw="$tmp/ignore-repo"
    if mkdir -p "$tw" && aw_git_elsewhere "$tw" init -q >/dev/null 2>&1; then
        [[ -f "$ws/.gitignore" ]] && cat "$ws/.gitignore" > "$tw/.gitignore"
        ex="$(aw_git_elsewhere "$ws" rev-parse --git-path info/exclude 2>/dev/null)"
        [[ -n "$ex" && "$ex" != /* ]] && ex="$ws/$ex"
        if [[ -n "$ex" && -f "$ex" ]]; then mkdir -p "$tw/.git/info" && cat "$ex" > "$tw/.git/info/exclude"; fi
        cut -f1 "$tmp/pp" | sort -u | awk '{ printf "kit/%s%c%s%c", $0, 0, $0, 0 }' > "$tmp/ign.in"
        aw_git_elsewhere "$tw" check-ignore --no-index -v -z --stdin < "$tmp/ign.in" > "$tmp/ign.out" 2>"$tmp/ign.err"
        st=$?
        if [[ $st -gt 1 ]]; then
            cnr P4 "git check-ignore failed: $(head -n 1 "$tmp/ign.err")"
        else
            while IFS= read -r -d '' src && IFS= read -r -d '' ln && IFS= read -r -d '' pat && IFS= read -r -d '' pth; do
                [[ "$pat" == '!'* ]] && continue
                pth="${pth#kit/}"
                awk -F '\t' -v p="$pth" '$1 == p { print $2 }' "$tmp/pp" | while IFS= read -r it; do
                    refused "$it" "listed in the workspace .gitignore ($src:$ln:$pat)"
                done
            done < "$tmp/ign.out"
        fi
    else
        cnr P4 "the throwaway repository for the .gitignore check cannot be created"
    fi
fi

# ---- Content rules (R1-R6) ----------------------------------------------------------------------
if [[ $content -eq 1 ]]; then
    # R1 and R2 need each blob's size; one batch call gives them all.
    awk -F '\t' '$2 != "160000" && $4 != "-" { print $4 }' "$tmp/entries" | sort -u > "$tmp/shas"
    : > "$tmp/sizes"
    if [[ -s "$tmp/shas" ]]; then
        g cat-file --batch-check='%(objectname) %(objectsize)' < "$tmp/shas" > "$tmp/sizes" 2>/dev/null \
            || cnr R2 "git cat-file could not read the blob sizes"
    fi
    size_of() { awk -v s="$1" '$1 == s { print $2; exit }' "$tmp/sizes"; }

    # R1: binary blobs, bar images with a line in docs/images/SOURCES.md.
    sources_listed() {
        local key="$1" name="$2" src
        if [[ "$key" == - && "$source" == staged ]]; then src="$(g show ":$(pp_inv docs/images/SOURCES.md)" 2>/dev/null)"
        elif [[ "$key" == - ]]; then src="$(g show "HEAD:$(pp_inv docs/images/SOURCES.md)" 2>/dev/null)"
        else src="$(g show "$key:$(pp_inv docs/images/SOURCES.md)" 2>/dev/null)"; fi
        printf '%s\n' "$src" | awk -F '|' -v n="$name" '
            NF >= 3 { a = $2; b = $3; gsub(/[ `]/, "", a); gsub(/^[ ]+|[ ]+$/, "", b); if (a == n && b != "") f = 1 }
            END { exit !f }'
    }
    # pp_inv <kit path>: the same file as the tree being checked names it (without the mirror prefix).
    pp_inv() { if [[ -n "$prefix" ]]; then printf '%s' "${1#"$prefix"/}"; else printf '%s' "$1"; fi; }
    while IFS=$'\t' read -r key path; do
        j="$(pp "$path")"
        if [[ "$j" == docs/images/*.png && "$j" != docs/images/*/* ]] && sources_listed "$key" "${j##*/}"; then continue; fi
        ns="$(awk -F '\t' -v k="$key" -v p="$path" '$1 == k && $5 == p { print $4; exit }' "$tmp/entries")"
        refused "$(item "$key" "$path")" "binary ($(size_of "$ns") bytes; images need a line in docs/images/SOURCES.md)"
    done < "$tmp/binary"

    # R2: size.
    limit="${AW_MAX_FILE_MB:-25}"
    [[ "$limit" =~ ^[0-9]+$ ]] || { cnr R2 "AW_MAX_FILE_MB is not a whole number"; limit=25; }
    if [[ "$limit" -eq 0 ]]; then
        note "AW_MAX_FILE_MB=0: the size check did not run"
    else
        while IFS=$'\t' read -r key nm os ns path; do
            [[ "$nm" == 160000 || "$ns" == - ]] && continue
            sz="$(size_of "$ns")"
            [[ -n "$sz" ]] || continue
            if [[ "$sz" -gt $((limit * 1048576)) ]]; then
                refused "$(item "$key" "$path")" "$(( (sz + 1048575) / 1048576 )) MB, over the $limit MB limit"
            fi
            : "$os"
        done < "$tmp/entries"
    fi

    # The added lines, for R3-R5: key<TAB>path<TAB>line number<TAB>text. A new file is all added
    # lines; a changed one is its diff with no context. Binary files, symlinks and gitlinks have none.
    : > "$tmp/lines"
    while IFS=$'\t' read -r key nm os ns path; do
        [[ "$nm" == 160000 || "$nm" == 120000 || "$ns" == - ]] && continue
        grep -qxF -- "$key"$'\t'"$path" "$tmp/binary" && continue
        if [[ "$os" =~ $ZERO_RE ]]; then
            g cat-file blob "$ns" 2>/dev/null | awk -v k="$key" -v p="$path" '{ sub(/\r$/, ""); print k "\t" p "\t" NR "\t" $0 }' >> "$tmp/lines"
        else
            g diff -U0 --no-color --no-ext-diff --no-textconv "$os" "$ns" 2>/dev/null | awk -v k="$key" -v p="$path" '
                /^@@ / { if (match($0, /\+[0-9]+/)) n = substr($0, RSTART + 1, RLENGTH - 1) + 0; h = 1; next }
                h && /^\+/ { t = substr($0, 2); sub(/\r$/, "", t); print k "\t" p "\t" n "\t" t; n++ }' >> "$tmp/lines"
        fi
    done < "$tmp/entries"
    cut -f4- "$tmp/lines" > "$tmp/text"
    cut -f5 "$tmp/entries" > "$tmp/paths"
    # For the path half of R3 and R4: key<TAB>path of each entry, in the same order as paths.
    cut -f1,5 "$tmp/entries" > "$tmp/pathkeys"
    cut -f3- "$tmp/messages" > "$tmp/msgtext"

    # hits <pattern file> <grep flags> <reason text> [line-reason]: runs one scan over the added lines,
    # the paths and the messages; each hit becomes a finding naming the file and the line, never the
    # word itself. Returns 2 when grep could not run (a list line that is not a valid pattern).
    hits() {
        local pats="$1" flags="$2" what="$3" n rc=0
        if [[ -s "$tmp/text" ]]; then
            grep -n "$flags" -f "$pats" "$tmp/text" > "$tmp/h" 2>/dev/null; [[ $? -gt 1 ]] && rc=2
            cut -d: -f1 "$tmp/h" | while IFS= read -r n; do
                awk -F '\t' -v n="$n" 'NR == n { print $1 "\t" $2 "\t" $3; exit }' "$tmp/lines"
            done | while IFS=$'\t' read -r k p l; do refused "$(item "$k" "$p")" "$what (line $l)"; done
        fi
        if [[ -s "$tmp/paths" && "$source" != message ]]; then
            grep -n "$flags" -f "$pats" "$tmp/paths" > "$tmp/h" 2>/dev/null; [[ $? -gt 1 ]] && rc=2
            cut -d: -f1 "$tmp/h" | while IFS= read -r n; do
                awk -F '\t' -v n="$n" 'NR == n { print $1 "\t" $2; exit }' "$tmp/pathkeys"
            done | while IFS=$'\t' read -r k p; do refused "$(item "$k" "$(mask "$pats" "$flags" "$p")")" "$what (path)"; done
        fi
        if [[ -s "$tmp/msgtext" && "${4:-}" == messages ]]; then
            grep -n "$flags" -f "$pats" "$tmp/msgtext" > "$tmp/h" 2>/dev/null; [[ $? -gt 1 ]] && rc=2
            cut -d: -f1 "$tmp/h" | while IFS= read -r n; do
                awk -F '\t' -v n="$n" 'NR == n { print $1 "\t" $2; exit }' "$tmp/messages"
            done | while IFS=$'\t' read -r m l; do refused "$m" "$what (line $l)"; done
        fi
        return $rc
    }
    # mask <pattern file> <grep flags> <path>: the path with each component that matches replaced by
    # "…", so a finding about a path never spells the word out.
    mask() {
        local out="" c
        local -a cs
        IFS=/ read -r -a cs <<< "$3"
        for c in ${cs[@]+"${cs[@]}"}; do
            if printf '%s\n' "$c" | grep -q "$2" -f "$1" 2>/dev/null; then c="…"; fi
            out="${out:+$out/}$c"
        done
        printf '%s' "$out"
    }

    # R3: the private word list. One extended regex per line, matched as a whole word in any case,
    # the same reading the test suite gives it. LICENSE files are left out, as the test suite leaves
    # them out: they carry the author's name by design.
    wl="$(aw_word_list "$ws")"; wl_rc=$?
    if [[ $wl_rc -ne 0 ]]; then
        cnr R3 "the private word list is configured but cannot be used"
    elif [[ -z "$wl" ]]; then
        note "no private word list; the word check did not run"
    else
        sed -e 's/[[:space:]]*$//' "$wl" | grep -vE '^[[:space:]]*(#|$)' > "$tmp/words"
        if [[ -s "$tmp/words" ]]; then
            cp "$tmp/text" "$tmp/text.all"; cp "$tmp/lines" "$tmp/lines.all"
            awk -F '\t' '{ n = $2; sub(/.*\//, "", n); print ((n ~ /^LICENSE/) ? "" : $0) }' "$tmp/lines.all" > "$tmp/lines"
            cut -f4- "$tmp/lines" > "$tmp/text"
            hits "$tmp/words" -iwE "private word" messages || cnr R3 "a line in the private word list is not a valid extended regex"
            cp "$tmp/text.all" "$tmp/text"; cp "$tmp/lines.all" "$tmp/lines"
        fi
    fi

    # R3, second list: the workspace's own private terms (.claude/private-terms.local, gitignored, never
    # in the kit): client, product and people names the person keeps out of anything public. Same
    # reading as the word list: one extended regex per line, whole word, any case; # starts a comment.
    if [[ -n "$ws" && -e "$ws/.claude/private-terms.local" ]]; then
        if [[ ! -f "$ws/.claude/private-terms.local" || ! -r "$ws/.claude/private-terms.local" ]]; then
            cnr R3 "the workspace's .claude/private-terms.local cannot be read"
        else
            sed -e 's/[[:space:]]*$//' "$ws/.claude/private-terms.local" | grep -vE '^[[:space:]]*(#|$)' > "$tmp/terms"
            if [[ -s "$tmp/terms" ]]; then
                hits "$tmp/terms" -iwE "private term of the workspace" messages \
                    || cnr R3 "a line in .claude/private-terms.local is not a valid extended regex"
            fi
        fi
    fi

    # R6: attribution trailers in commit and tag messages. The patterns are assembled from pieces so
    # this file does not carry the trailer itself.
    attr1='^co-authored''-by:.*(claude|anthropic|noreply@anthropic\.com)'
    attr2='generated'' with .*claude'
    if [[ -s "$tmp/msgtext" ]]; then
        grep -inE -e "$attr1" -e "$attr2" "$tmp/msgtext" | cut -d: -f1 | while IFS= read -r n; do
            awk -F '\t' -v n="$n" 'NR == n { print $1; exit }' "$tmp/messages"
        done | sort -u | while IFS= read -r m; do refused "$m" "attribution trailer"; done
    fi

    if [[ -n "$ws" && "$source" != message ]]; then
        # R4: names derived from the workspace, computed now and never stored. Each is skipped when the
        # kit already says it (HEAD), or when .claude/workspace.md lists it under Kit may name.
        : > "$tmp/ids"
        cfg="$CP_KIT/plugins/projects/hooks/lib/config.sh"
        if [[ -f "$cfg" ]]; then
            # shellcheck source=../plugins/projects/hooks/lib/config.sh
            . "$cfg"
            projects_config "$ws"
            while IFS= read -r pat; do
                [[ -n "$pat" ]] || continue
                glob="$(printf '%s' "$pat" | sed -e 's/<[^>]*>/*/g')"
                for d in "$ws"/$glob; do
                    [[ -d "$d" ]] || continue
                    s="${d##*/}"
                    case "$s" in _*|.*) continue ;; esac
                    [[ ${#s} -ge 4 ]] && printf 'a project folder\t%s\n' "$s" >> "$tmp/ids"
                done
            done <<EOF
$PROJECT_PATTERNS
EOF
        else
            cnr R4 "the projects plugin's config.sh is missing"
        fi
        # The people folder is the one the conventions name (People:), as the state check reads it.
        people="$(awk '/^[ \t]*[-*] \*\*People:\*\*/ { if (match($0, /`[^`]*`/)) print substr($0, RSTART + 1, RLENGTH - 2); exit }' \
            "$ws/.claude/projects.md" 2>/dev/null)"
        people="${people:-memory/people/<name>.md}"
        case "$people" in *'<'*) people="${people%%<*}" ;; esac
        people="${people%/}"; people="${people#./}"
        for f in "$ws/$people"/*.md; do
            [[ -f "$f" ]] || continue
            s="${f##*/}"; s="${s%.md}"
            [[ "$s" == README || ${#s} -lt 4 ]] && continue
            printf "a person's profile\t%s\n" "$s" >> "$tmp/ids"
        done
        u="$(aw_git_elsewhere "$ws" config --get remote.origin.url 2>/dev/null)"
        u="$(aw_norm_url "$u")"
        [[ -n "$u" && "$u" != local:* && "$u" == */*/* ]] && printf "the workspace's remote\t%s\n" "${u#*/}" >> "$tmp/ids"
        if [[ -f "$ws/.gitmodules" ]]; then
            kn="$(aw_kitname "$ws")"
            aw_git_elsewhere "$ws" config -f .gitmodules --get-regexp '^submodule\..*\.url$' 2>/dev/null | while read -r k v; do
                k="${k#submodule.}"; k="${k%.url}"
                [[ -n "$kn" && "$k" == "$kn" ]] && continue
                u="$(aw_norm_url "$v")"
                [[ -n "$u" && "$u" != local:* && "$u" == */*/* ]] && printf "a submodule's remote\t%s\n" "${u#*/}"
            done >> "$tmp/ids"
            # A project that is its own repository is named by its folder whatever the folder's
            # length: the 4-character floor above is for ordinary words, and a short own-repo name is
            # usually a product's.
            aw_git_elsewhere "$ws" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | while read -r k v; do
                [[ "$v" == kit ]] && continue
                while IFS= read -r pat; do
                    [[ -n "$pat" ]] || continue
                    if [[ "$(projects_match "$pat" "$v" 2>/dev/null)" == "$v" ]]; then
                        s="${v##*/}"
                        case "$s" in _*|.*) ;; *) printf 'a project folder\t%s\n' "$s" ;; esac
                        break
                    fi
                done <<EOF
${PROJECT_PATTERNS:-}
EOF
                : "$k"
            done >> "$tmp/ids"
        fi
        if [[ -n "${HOME:-}" && "$HOME" != / ]]; then
            printf 'the home folder\t%s\n' "$HOME" >> "$tmp/ids"
            h="$(cd "$HOME" 2>/dev/null && pwd -P)"; [[ -n "$h" && "$h" != "$HOME" ]] && printf 'the home folder\t%s\n' "$h" >> "$tmp/ids"
        fi
        printf 'the workspace path\t%s\n' "$ws" >> "$tmp/ids"
        e="$(aw_git_elsewhere "$ws" config --get user.email 2>/dev/null)"
        [[ -n "$e" ]] && printf 'the git email\t%s\n' "$e" >> "$tmp/ids"
        may="$(awk '
            /^[ \t]*```/ { fence = !fence; next }
            fence { next }
            /^[ \t]*[-*][ \t]+\*\*Kit may name:\*\*/ { if (match($0, /`[^`]+`/)) print substr($0, RSTART + 1, RLENGTH - 2); exit }' \
            "$ws/.claude/workspace.md" 2>/dev/null | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
        sort -u "$tmp/ids" | while IFS=$'\t' read -r kind id; do
            [[ -n "$id" ]] || continue
            lid="$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"
            if [[ -n "$may" ]] && printf '%s\n' "$may" | grep -qxF -- "$lid"; then continue; fi
            if g rev-parse -q --verify 'HEAD^{commit}' >/dev/null && g grep -q -i -w -F -e "$id" HEAD -- 2>/dev/null; then continue; fi
            printf '%s\n' "$id" > "$tmp/id1"
            hits "$tmp/id1" -iwF "names $kind of the workspace" || cnr R4 "the derived-name scan could not run"
        done

        # R5: provenance. A blob the workspace has and the kit's history never had is a copy of a
        # workspace file; so is an added line of 60 characters or more that the kit did not already
        # have and a workspace file holds word for word.
        allow_copy=",${AW_ALLOW_COPY:-},"
        while IFS=$'\t' read -r key nm os ns path; do
            [[ "$nm" == 160000 || "$ns" == - ]] && continue
            case "$allow_copy" in *",$(pp "$path"),"*) continue ;; esac
            aw_git_elsewhere "$ws" cat-file -e "$ns" 2>/dev/null || continue
            if [[ ${#CP_HIST_ARGS[@]} -gt 0 ]] && [[ -n "$(g log --format=%H -1 --find-object="$ns" "${CP_HIST_ARGS[@]}" 2>/dev/null)" ]]; then
                continue
            fi
            wf="$(aw_git_elsewhere "$ws" ls-files -s 2>/dev/null | awk -v s="$ns" '$2 == s { sub(/^[^\t]*\t/, ""); print; exit }')"
            refused "$(item "$key" "$path")" "a copy of ${wf:-a workspace file}"
            : "$os"
        done < "$tmp/entries"

        awk -F '\t' 'length($0) - length($1) - length($2) - length($3) - 3 >= 60' "$tmp/lines" > "$tmp/long"
        if [[ -s "$tmp/long" ]]; then
            cut -f4- "$tmp/long" | sort -u > "$tmp/cand"
            if [[ -n "$CP_LINE_BASE" ]]; then
                # git grep has no whole-line switch: substring matches are narrowed to exact lines here.
                g grep -h -F -f "$tmp/cand" "$CP_LINE_BASE" -- 2>/dev/null \
                    | awk 'FNR == NR { c[$0] = 1; next } ($0 in c)' "$tmp/cand" - | sort -u > "$tmp/known"
                if [[ -s "$tmp/known" ]]; then
                    grep -vxF -f "$tmp/known" "$tmp/cand" > "$tmp/cand2"; cat "$tmp/cand2" > "$tmp/cand"
                fi
            fi
            if [[ -s "$tmp/cand" ]]; then
                excl=(":(exclude)kit")
                if [[ -n "${AW_OPAQUE_PATHS+set}" ]]; then op="$AW_OPAQUE_PATHS"; else op="AGENTS.md copilot-instructions.md"; fi
                for o in $op; do excl+=(":(exclude)$o"); done
                aw_git_elsewhere "$ws" grep -F -f "$tmp/cand" -- . "${excl[@]}" > "$tmp/wsg" 2>/dev/null
                # What the workspace keeps out of its own repository on purpose is read too: a
                # sensitive project, a private/ folder, an own-repo project's checkout, .secrets/. So
                # every file of 1 MB or less under the project folders and .secrets/, tracked or not,
                # is compared line for line; .git folders and symlinks are not followed.
                : > "$tmp/roots"
                while IFS= read -r pat; do
                    [[ -n "$pat" ]] || continue
                    glob="$(printf '%s' "$pat" | sed -e 's/<[^>]*>/*/g')"
                    for d in "$ws"/$glob; do [[ -d "$d" && ! -L "$d" ]] && printf '%s\n' "${d#"$ws"/}" >> "$tmp/roots"; done
                done <<EOF
${PROJECT_PATTERNS:-}
EOF
                [[ -d "$ws/.secrets" && ! -L "$ws/.secrets" ]] && printf '.secrets\n' >> "$tmp/roots"
                if [[ -s "$tmp/roots" ]]; then
                    ( cd "$ws" && sort -u "$tmp/roots" | awk '{ for (r in R) if (index($0, r "/") == 1) next; R[$0] = 1; print }' | while IFS= read -r r; do
                          find "$r" -name .git -prune -o -type f -size -1025k -print0 2>/dev/null
                      done | xargs -0 grep -I -H -F -x -f "$tmp/cand" -- /dev/null 2>/dev/null ) >> "$tmp/wsg"
                fi
                if [[ -s "$tmp/wsg" ]]; then
                    # file:line, with a file name that may itself hold a colon: the split is the one whose
                    # right-hand side is a candidate line, word for word (which also drops substring hits).
                    awk 'FNR == NR { c[$0] = 1; next }
                        { s = $0; i = 0
                          while ((k = index(substr(s, i + 1), ":")) > 0) {
                              i += k
                              if (substr(s, i + 1) in c) { if (!(substr(s, i + 1) in seen)) { seen[substr(s, i + 1)] = 1; print substr(s, i + 1) "\t" substr(s, 1, i - 1) }; break }
                          } }' "$tmp/cand" "$tmp/wsg" > "$tmp/lmap"
                    while IFS=$'\t' read -r key path ln text; do
                        case "$allow_copy" in *",$(pp "$path"),"*) continue ;; esac
                        wf="$(awk -F '\t' -v t="$text" '$1 == t { print $2; exit }' "$tmp/lmap")"
                        [[ -n "$wf" ]] && refused "$(item "$key" "$path")" "a copy of $wf (line $ln)"
                    done < "$tmp/long"
                fi
            fi
        fi
    fi
fi

# ---- Report ----------------------------------------------------------------------------------------
awk '!seen[$0]++' "$tmp/findings" > "$tmp/out"
cat "$tmp/out"
nr=$(( $(grep -c '^refused' "$tmp/out") ))
nc=$(( $(grep -c '^could-not-run' "$tmp/out") ))
if [[ $((nr + nc)) -gt 0 ]]; then
    printf 'check-paths: %s refused, %s could not run\n' "$nr" "$nc" >&2
    exit 1
fi
printf 'check-paths: %s paths allowed\n' "$(( $(aw_count < "$tmp/entries") ))" >&2
exit 0
