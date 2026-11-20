#!/usr/bin/env bash
# release.sh <version> pr|ship --notes <dir> [--pr N] [--mailbox DIR] [--dry-run]: the kit's release,
# through a pull request from the trial branch into main. The maintainer runs it in their own terminal
# (the kit's pre-push hook wants one). Every step that changes something here or on GitHub prints what it
# will do and waits for a yes; --dry-run runs every check and changes nothing.
#
# Everything per release comes from <dir>/<version>/, kept outside the kit: notes.md is the pull
# request's body and the GitHub release's text, and its first line is the tag's subject, after "v<version>: ". The release
# commits are on the branch release/v<version>, dated in its CHANGELOG ("## v<version> "), so nothing in
# this script changes from one release to the next.
#
#   pr     move the trial branch to release/v<version> as a fast-forward and push it, which runs CI; open
#          the pull request from it into main titled "v<version>" with notes.md as its body, or retitle
#          the open one
#   ship   once that pull request is merged with a merge commit: stop unless every check on it passed,
#          and, where the release was paired, every gate in the mailbox's gates.json; check the merge
#          commit holds exactly release/v<version>'s tree, tag v<version> on it, publish the GitHub
#          release with notes.md, and bring the closeout mirror up to the release (a no-op when closeout
#          is unchanged)
#   --pr N       the pull request; without it, the open one from the trial branch into main, else the
#                newest merged
#   --mailbox    the pairing's mailbox, whose gates.json ship waits on; by default <dir>/../mailbox when
#                it exists. With no gates.json there, ship says so and goes on.
#
# The repository is the checkout this script sits in (KIT overrides it); the GitHub repository and the
# trial branch are AW_RELEASE_REPO and AW_RELEASE_TRIAL, cyberscribe/agentic-workspace-kit and
# kit-trial by default.
set -euo pipefail
export GIT_CONFIG_NOSYSTEM=1
here="$(cd "$(dirname "$0")" && pwd -P)"

say() { printf '%s\n' "$*"; }
stop() { say "STOPPED: $*"; exit 1; }
usage() { say "usage: release.sh <version> pr|ship --notes <dir> [--pr N] [--mailbox DIR] [--dry-run]" >&2; exit 2; }

V="${1:-}"; [[ $# -gt 0 ]] && shift
mode="${1:-}"; [[ $# -gt 0 ]] && shift
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[[ "$mode" == pr || "$mode" == ship ]] || usage
dry=0 PR="" NOTES_DIR="" MAILBOX=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry=1; shift ;;
        --pr) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || stop "--pr needs a pull request number"; PR="$2"; shift 2 ;;
        --notes) [[ $# -ge 2 ]] || stop "--notes needs a folder"; NOTES_DIR="$2"; shift 2 ;;
        --mailbox) [[ $# -ge 2 ]] || stop "--mailbox needs a folder"; MAILBOX="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[[ -n "$NOTES_DIR" ]] || stop "--notes names the folder that holds <version>/notes.md"
[[ -d "$NOTES_DIR/$V" ]] || stop "there is no folder $NOTES_DIR/$V"
rel="$(cd "$NOTES_DIR/$V" && pwd -P)"
notes="$rel/notes.md"
[[ -n "$MAILBOX" ]] || { [[ -d "$NOTES_DIR/../mailbox" ]] && MAILBOX="$(cd "$NOTES_DIR/../mailbox" && pwd -P)"; } || true
BR="release/v$V"
TRIAL="${AW_RELEASE_TRIAL:-kit-trial}"
REPO="${AW_RELEASE_REPO:-cyberscribe/agentic-workspace-kit}"
TITLE="v$V"

cd "${KIT:-$(git -C "$here" rev-parse --show-toplevel)}"
# The release tree is whatever is committed on the release branch; ship checks the merge commit holds
# exactly it.
git rev-parse -q --verify "$BR^{commit}" >/dev/null || stop "there is no branch $BR in $(pwd)"
TREE="$(git rev-parse "$BR^{tree}")"
grep -q "^## v$V " <(git show "$BR:CHANGELOG.md") || stop "$BR's CHANGELOG has no dated '## v$V ' heading yet"
[[ -s "$notes" ]] || stop "$notes is missing or empty"
# The tag's subject is "v<version>: " and notes.md's first line, without a heading's #s, as every
# earlier tag has it, so git tag -n reads as one list.
first="$(sed -n '1{s/^#* *//;p;q;}' "$notes")"
[[ -n "$first" ]] || stop "notes.md's first line is empty; it is the tag's subject"
subject="v$V: $first"
say "ok: $BR is at $(git log -1 --format='%h %s' "$BR")"
say "ok: the tag's subject, from notes.md's first line: $subject"

# open_pr: the number of the open pull request from the trial branch into main, or nothing.
open_pr() { gh pr list -R "$REPO" --head "$TRIAL" --base main --state open --json number -q '.[0].number // empty' 2>/dev/null || true; }
# step <what> <command...>: shows the step, then runs it on a yes; a dry run only shows it.
step() {
    local what="$1"; shift
    say ""; say "Next: $what"; say "  $(printf '%q ' "$@")"
    [[ $dry -eq 0 ]] || { say "  (dry run: not run)"; return 0; }
    local a=""; read -r -p "  Run it? (y/n) " a || true
    [[ "$a" == [Yy]* ]] || stop "not run, at your answer; run the command again to carry on from here"
    "$@"
}

git fetch -q origin || stop "git fetch origin failed"
# The notes go out as the pull request's body and the release's text: the word list and attribution
# rules, as for a commit message. No --workspace here: its copy rule, without the push's timing, would
# count the workspace's own copies of kit files; the pre-push hook runs the copy check as it should.
bash scripts/check-paths.sh --message "$notes" --content >/dev/null 2>&1 \
    || stop "notes.md: $(bash scripts/check-paths.sh --message "$notes" --content 2>/dev/null | cut -f3 | sed -n 1,3p)"
say "ok: notes.md passes the private-word and attribution checks"

case "$mode" in
pr)
    # What matters is that main has no change of its own that the release lacks, so the pull request
    # merges cleanly.
    extra="$(git rev-list --no-merges origin/main --not "$BR")"
    [[ -z "$extra" ]] || stop "origin/main has $(printf '%s\n' "$extra" | wc -l | tr -d ' ') commit(s) $BR lacks; the pull request would not merge cleanly"
    say "ok: origin/main has nothing $BR lacks; $BR adds $(git rev-list --count --no-merges "$BR" --not origin/main) commit(s)"
    bash scripts/check-paths.sh --commits "origin/main..$BR" --content >/dev/null 2>&1 \
        || stop "the commits since origin/main fail the content checks: $(bash scripts/check-paths.sh --commits "origin/main..$BR" --content 2>/dev/null | cut -f2,3 | sed -n 1,3p)"
    say "ok: every commit since origin/main passes the content checks, messages included"
    [[ -n "$PR" ]] || PR="$(open_pr)"
    if [[ -n "$PR" ]]; then
        [[ "$(gh pr view "$PR" -R "$REPO" --json headRefName,baseRefName,state -q '.headRefName + " " + .baseRefName + " " + .state')" == "$TRIAL main OPEN" ]] \
            || stop "#$PR is not an open pull request from $TRIAL into main"
        say "ok: #$PR is the open pull request from $TRIAL into main"
    else
        say "ok: no pull request from $TRIAL into main is open; one is opened after the push"
    fi
    if [[ "$(git rev-parse -q --verify "$TRIAL" 2>/dev/null)" == "$(git rev-parse "$BR")" ]]; then
        say "ok: $TRIAL is already at $BR"
    elif [[ "$(git symbolic-ref -q --short HEAD)" == "$TRIAL" ]]; then
        git merge-base --is-ancestor "$TRIAL" "$BR" || stop "$TRIAL has commits $BR does not; it cannot move to it as a fast-forward"
        { git diff --quiet && git diff --cached --quiet; } || stop "this checkout has uncommitted changes; the fast-forward would carry them"
        step "fast-forward $TRIAL to $BR ($(git rev-list --count "$TRIAL..$BR") commits), here in $(pwd)" git merge -q --ff-only "$BR"
    else
        # Not checked out here: the branch moves without a checkout, and git refuses anything but a
        # fast-forward, or a branch checked out in another worktree.
        if git rev-parse -q --verify "$TRIAL" >/dev/null; then
            git merge-base --is-ancestor "$TRIAL" "$BR" || stop "$TRIAL has commits $BR does not; it cannot move to it as a fast-forward"
        fi
        step "move $TRIAL to $BR as a fast-forward, without a checkout" git fetch -q . "$BR:$TRIAL"
    fi
    if [[ "$(git rev-parse -q --verify "refs/remotes/origin/$TRIAL" 2>/dev/null)" == "$(git rev-parse "$BR")" ]]; then
        say "ok: $TRIAL is already pushed at the release"
    else
        step "push $TRIAL to GitHub, which runs CI" git push origin "$TRIAL"
    fi
    if [[ -n "$PR" ]]; then
        step "retitle #$PR \"$TITLE\", with notes.md as its body" gh pr edit "$PR" -R "$REPO" --title "$TITLE" --body-file "$notes"
    else
        step "open a pull request from $TRIAL into main, \"$TITLE\", with notes.md as its body" \
            gh pr create -R "$REPO" --base main --head "$TRIAL" --title "$TITLE" --body-file "$notes"
        [[ $dry -eq 1 ]] || PR="$(open_pr)"
    fi
    me="bash $here/release.sh $V ship --notes $NOTES_DIR${MAILBOX:+ --mailbox $MAILBOX}"
    say ""
    if [[ -n "$PR" ]]; then
        say "#$PR's checks (CI takes a few minutes after a push; gh pr checks $PR -R $REPO --watch follows them):"
        gh pr checks "$PR" -R "$REPO" 2>&1 | sed 's/^/  /' || true
        say ""
        say "Next: $me --pr $PR --dry-run, which stops unless every check on #$PR has passed (and every"
        say "gate, where the release is paired). Once it gets past the checks, merge #$PR on GitHub with a"
        say "merge commit (not squash or rebase)."
        say "Then: $me --pr $PR"
    else
        say "Next: the pull request's number is known once it is opened; this run is a dry run."
    fi
    ;;
ship)
    if [[ -z "$PR" ]]; then
        PR="$(open_pr)"
        [[ -n "$PR" ]] || PR="$(gh pr list -R "$REPO" --head "$TRIAL" --base main --state merged --limit 1 --json number -q '.[0].number // empty' 2>/dev/null || true)"
        [[ -n "$PR" ]] || stop "no pull request from $TRIAL into main, open or merged; name one with --pr"
        say "note: #$PR is the pull request this run tags from (--pr names another)"
    fi
    state="$(gh pr view "$PR" -R "$REPO" --json state -q .state 2>/dev/null || true)"
    if [[ "$state" == MERGED ]]; then
        M="$(gh pr view "$PR" -R "$REPO" --json mergeCommit -q .mergeCommit.oid)"
        git cat-file -e "$M^{commit}" 2>/dev/null || stop "the merge commit $M is not here after the fetch"
        [[ "$(git rev-parse "$M^{tree}")" == "$TREE" ]] \
            || stop "#$PR's merge commit $(printf '%.7s' "$M") does not hold the release tree $TREE; it is not the release"
        git merge-base --is-ancestor "$BR" "$M" 2>/dev/null \
            || stop "the merge commit $M does not hold $BR (merged by squash or rebase?); the tag would not mark the release's commits"
        [[ "$(git show "$M:CHANGELOG.md" | grep -c "^## v$V ")" == 1 ]] || stop "the merge commit's CHANGELOG has no v$V heading"
        say "ok: #$PR merged as $(git log -1 --format='%h' "$M"), which holds $BR, exactly the release tree and the v$V CHANGELOG entry"
    elif [[ $dry -eq 1 ]]; then
        M="$(git rev-parse "$BR")"
        say "note: #$PR is ${state:-not found}, not merged, so this dry run stands $BR's tip ($(printf '%.7s' "$M")) in for the merge commit"
    else
        stop "#$PR is ${state:-not found}, not merged"
    fi
    # Every check on the pull request passed: 3.6.2 was tagged with its Ubuntu job red. gh's JSON gives
    # each check a bucket (pass, fail, pending, skipping or cancel); anything but pass stops the release.
    cj="$(gh pr checks "$PR" -R "$REPO" --json name,bucket 2>/dev/null || true)"
    [[ -n "$cj" && "$cj" != "[]" ]] || stop "gh reports no checks on #$PR, or could not read them (gh pr checks $PR -R $REPO), so nothing says CI passed"
    notpass="$(jq -r '.[] | select(.bucket != "pass") | "\(.name): \(.bucket)"' <<<"$cj" | paste -sd ';' - | sed 's/;/; /g')"
    [[ -z "$notpass" ]] || stop "not every check on #$PR passed ($notpass); a release ships on green checks only"
    say "ok: all $(jq length <<<"$cj") checks on #$PR passed ($(jq -r '[.[].name] | join(", ")' <<<"$cj"))"
    # A paired release also waits on its gate list: every gate passed, the list as the PM sealed it.
    if [[ -n "$MAILBOX" && -f "$MAILBOX/gates.json" ]]; then
        [[ -f plugins/projects/hooks/lib/gates.sh ]] || stop "the kit here has no plugins/projects/hooks/lib/gates.sh to read $MAILBOX/gates.json with"
        g_state="" g_why=""
        # shellcheck source=/dev/null
        . plugins/projects/hooks/lib/gates.sh
        gates_state "$MAILBOX"
        case "$g_state" in
            nojq) stop "jq is needed to read $MAILBOX/gates.json" ;;
            invalid) stop "$MAILBOX/gates.json is not a gate list: ${g_why%%$'\n'*}" ;;
            changed) stop "$MAILBOX/gates.json has changed since the PM sealed it: $(paste -sd ';' - <<<"$g_why" | sed 's/;/; /g')" ;;
            unsealed) stop "$MAILBOX/gates.json is not sealed, so its gates may have changed; the PM seals it (pair.sh gates --from pm --seal)" ;;
        esac
        open_gates="$(gates_rows "$MAILBOX" | awk -F'\t' '$3 != "true" { print $1 }' | paste -sd ',' - | sed 's/,/, /g')"
        [[ -z "$open_gates" ]] || stop "the pairing's gates have not all passed: $open_gates (pair.sh gates --mailbox $MAILBOX lists them)"
        say "ok: every gate in $MAILBOX/gates.json has passed"
    else
        say "note: no gates.json${MAILBOX:+ in $MAILBOX}, so there are no gates to wait on"
    fi
    if git rev-parse -q --verify "refs/tags/v$V" >/dev/null; then
        [[ "$(git rev-parse "v$V^{commit}")" == "$M" ]] || stop "a tag v$V already exists, on another commit"
        say "ok: the tag v$V is already on the merge commit"
    else
        step "tag v$V on the merge commit" git tag -a "v$V" "$M" -m "$subject"
    fi
    if [[ -n "$(git ls-remote origin "refs/tags/v$V")" ]]; then say "ok: the tag is already on GitHub"
    else step "push the tag to GitHub" git push origin "v$V"; fi
    if gh release view "v$V" -R "$REPO" >/dev/null 2>&1; then say "ok: the GitHub release v$V already exists"
    else step "publish the GitHub release v$V with notes.md" gh release create "v$V" -R "$REPO" --verify-tag --title "v$V" --notes-file "$notes"; fi
    # The closeout mirror is the subtree split of plugins/closeout, pushed only as a fast-forward of what
    # the mirror holds.
    if ! git remote get-url closeout >/dev/null 2>&1; then
        [[ $dry -eq 1 ]] || stop "there is no 'closeout' remote here for the mirror"
        say ""; say "note: no 'closeout' remote here, so this dry run does not check the mirror"
    else
        say ""; say "Splitting plugins/closeout for the mirror (this takes a minute)…"
        S="$(git subtree split --prefix=plugins/closeout "$M" 2>/dev/null)" || stop "git subtree split failed"
        mh="$(git ls-remote closeout refs/heads/main | cut -f1)"
        [[ -n "$mh" ]] || stop "could not read the mirror's main (git ls-remote closeout)"
        if [[ "$mh" == "$S" ]]; then
            say "ok: the closeout mirror is already at the release ($(printf '%.7s' "$S"))"
        else
            git cat-file -e "$mh^{commit}" 2>/dev/null || git fetch -q closeout || stop "could not fetch the mirror"
            git merge-base --is-ancestor "$mh" "$S" || stop "the mirror's main ($(printf '%.7s' "$mh")) is not behind the split ($(printf '%.7s' "$S")): it has moved on its own; pull it back first"
            say "ok: the mirror moves $(git rev-list --count "$mh..$S") commits, $(printf '%.7s' "$mh") to $(printf '%.7s' "$S"), as a fast-forward"
            step "push the closeout mirror" git push closeout "$S:refs/heads/main"
        fi
    fi
    say ""
    say "Next: put the workspace's kit checkout back on main at the release, then record it in the"
    say "workspace (git switch main && git pull --ff-only in the kit, then commit the kit pointer)."
    ;;
esac
