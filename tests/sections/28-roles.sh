# shellcheck shell=bash
# KIT, SCRATCH, STATE and the check helpers come from tests/run.sh (SC2154); checks are "cond && ok || ko"
# (SC2015); single-quoted strings hold literal backticks (SC2016).
# shellcheck disable=SC2154,SC2015,SC2016
# Section 28: the person's roles (wave 2). The profile's Roles list and the quick-start question that
# fills it; the "as <role>" part of a People line in the project and area templates, beside the five
# roles and distinct from them; and a README with no role, which reads exactly as before: the owner,
# the state check and the session-start line are unchanged by it.
# Everything here is prefixed s28_, since the sections share one shell.

echo
echo "28 · Roles: the profile, the People line, and a README with none"

s28="$SCRATCH/s28"
mkdir -p "$s28"
s28_awk="$KIT/plugins/projects/hooks/lib/readme.awk"
# s28_flat <file>: the file on one line, runs of spaces squeezed, for phrases across wrapped lines.
s28_flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
# s28_has <file> <phrase...>: prints each phrase the flattened file lacks.
s28_has() {
    local f="$1" flat p; shift
    flat="$(s28_flat "$f")"
    for p in "$@"; do grep -qF -- "$p" <<<"$flat" || printf '%s: no "%s"\n' "${f#"$KIT"/}" "$p"; done
}

# ---- The stored part: the profile and the quick-start question ------------------------------------
s28_bad="$(s28_has "$KIT/templates/person-profile.md" '## Roles' 'in their own words, a handful at most' 'One is plenty.' \
        'Each project and area names the one they are in there' '| **Job** |'
    s28_has "$KIT/plugins/workspace/commands/quick-start.md" '**Their roles**' 'in their own words' 'A handful at most; one is plenty' \
        'under **Roles** in their profile' 'Ask nothing about the business itself (its size, revenue or market)'
    s28_has "$KIT/templates/team-roster.md" '| Name | Job | Default relationship |')"
grep -qF '| **Role** |' "$KIT/templates/person-profile.md" && s28_bad+="the profile still has a Role row beside Roles"$'\n'
# The personal part asks for the roles before anything optional, and no business questions anywhere in it.
s28_pp="$(awk '/^## The personal part/{f=1; next} f && /^## /{exit} f' "$KIT/plugins/workspace/commands/quick-start.md")"
[[ "$(grep -n '\*\*Their roles\*\*' <<<"$s28_pp" | cut -d: -f1)" -lt "$(grep -n 'Optional' <<<"$s28_pp" | head -n 1 | cut -d: -f1)" ]] \
    || s28_bad+="the roles question is not before the optional ones"$'\n'
grep -iE 'how many (people|employees)|annual|turnover|customers are' <<<"$s28_pp" >/dev/null && s28_bad+="a business question in the personal part"$'\n'
empty "28 the profile keeps a short Roles list in the person's own words, the quick-start asks for it, and no business questions" "$s28_bad"

# ---- The People line: "as <role>", beside the five roles ------------------------------------------
s28_bad=""
grep -qxF -- '- <name> — <accountable> — as <role> — `memory/people/<name>.md`' "$KIT/templates/project-readme.md" || s28_bad+="project template: no role in the People line"$'\n'
grep -qxF -- '- <name> — <accountable> — as <role> — `memory/people/<name>.md`' "$KIT/templates/area-readme.md" || s28_bad+="area template: no role in the People line"$'\n'
s28_bad+="$(s28_has "$KIT/templates/project-readme.md" 'name — what they answer for — who they are in this work — profile' \
        'one of the roles from their profile, written after "as"' 'It is optional'
    s28_has "$KIT/templates/area-readme.md" 'one of the roles from their profile, and optional')"
empty "28 the project and area templates carry the person's role in People, after the five roles and apart from them" "$s28_bad"

# The owner is read the same with a role and without one; the stand-in template line names no owner.
printf '# Holiday\n\n## Desired outcome\n\nA week away.\n\n## Current state\n\n- **State:** ready\n- **Updated:** 2026-11-20\n\n## People\n\n- Sam Lee — accountable — as parent — `memory/people/sam-lee.md`\n- Alex — consulted — as spouse\n' > "$s28/with.md"
printf '# Holiday\n\n## Desired outcome\n\nA week away.\n\n## Current state\n\n- **State:** ready\n- **Updated:** 2026-11-20\n\n## People\n\n- Sam Lee — accountable — `memory/people/sam-lee.md`\n- Alex — consulted\n' > "$s28/without.md"
s28_o1="$(awk -f "$s28_awk" "$s28/with.md" | awk -F '\037' '{print $8}')"
s28_o2="$(awk -f "$s28_awk" "$s28/without.md" | awk -F '\037' '{print $8}')"
s28_o3="$(awk -f "$s28_awk" "$KIT/templates/project-readme.md" | awk -F '\037' '{print $8}')"
[[ "$s28_o1" == "Sam Lee" && "$s28_o2" == "Sam Lee" && -z "$s28_o3" ]] \
    && ok "28 readme.awk: the owner is the name before the first dash, with a role or without; the template's stand-in names none" \
    || ko "28 readme.awk: the owner is the name before the first dash, with a role or without; the template's stand-in names none" "with=$s28_o1 without=$s28_o2 template=$s28_o3"

# ---- A README with no role: the state check reads it as it reads one with a role ------------------
if s28_ws="$s28/ws" && mkws_min "$s28_ws" 2>/dev/null; then
    mkdir -p "$s28_ws/projects/holiday"
    cp "$s28/without.md" "$s28_ws/projects/holiday/README.md"
    s28_a="$(cd "$s28_ws" && "$st_bash" "$STATE" 2>&1)"; s28_ra=$?
    cp "$s28/with.md" "$s28_ws/projects/holiday/README.md"
    s28_b="$(cd "$s28_ws" && "$st_bash" "$STATE" 2>&1)"; s28_rb=$?
    [[ $s28_ra -eq 0 && $s28_rb -eq 0 && "$s28_a" == "$s28_b" ]] && ! grep -qiE 'parent|spouse' <<<"$s28_b" \
        && ok "28 the state check gives the same output for a README with no role as for one with a role, and names no role" \
        || ko "28 the state check gives the same output for a README with no role as for one with a role, and names no role" "rc=$s28_ra/$s28_rb"$'\n'"$(diff <(printf '%s\n' "$s28_a") <(printf '%s\n' "$s28_b") | head -n 10)"
else
    skp "28 the state check with and without a role: no fixture workspace (the kit source could not be cloned)"
fi

# ---- The interview: one order, the role offered from the profile, and the questions about the plan ----
s28_new="$KIT/plugins/projects/commands/new.md"
s28_bad=""
# The order of "What to find out": outcome, role, finish line, the questions, people, versioning.
s28_order="$(awk '/^## What to find out/{f=1; next} f && /^## /{exit} f && /^[0-9]+\. /' "$s28_new" \
    | head -n 8 | grep -v '^2\. ' | sed -E 's/^([0-9]+)\. \*\*([^*]+)\*\*.*/\1 \2/' | paste -sd'|' -)"
[[ "$s28_order" == "1 Name|3 Desired outcome|4 Their role in it|5 Done when|6 Questions about the plan|7 People|8 How it is versioned, and whether anything in it is sensitive" ]] \
    || s28_bad+="the order is not outcome, role, finish line, questions, people, versioning: $s28_order"$'\n'
s28_bad+="$(s28_has "$s28_new" 'The order is the same on both paths: the outcome, their role in it, the finish line, the questions about the plan, the people, then how it is versioned.' \
        'offer those as the choices, with "another" always open' 'It goes on their own line in People as `as <role>`' \
        '## Questions about the plan' 'one branch at a time' 'what happens if this part fails or slips' 'who decides it' \
        'what done looks like for this part' 'is written into Open questions, in their words' \
        'as soon as they say enough: this is a sharpening pass, never a gate' 'and Open questions when the questions about the plan left any')"
s28_bad+="$(python3 - "$s28_new" <<'PY'
import sys
t = " ".join(open(sys.argv[1], encoding="utf-8").read().split())
a, b, c = t.find("## Questions about the plan"), t.find("## How it is versioned, and whether it is sensitive"), t.find("## Close with the finish line")
if not (0 <= a < b < c):
    print(f"new.md: the questions section is not between What to find out and the versioning section ({a}, {b}, {c})")
PY
)"
[[ -e "$KIT/plugins/projects/commands/grill.md" ]] && s28_bad+="a separate grill command exists; it lives in new and pickup"$'\n'
empty "28 /projects:new: outcome, role, finish line, questions about the plan, people, versioning; the questions go branch by branch, write what is open to Open questions and stop on the person's word" "$s28_bad"

s28_bad="$(s28_has "$KIT/plugins/ongoing/commands/new.md" '4. **Their role in it**' '**Roles** list' '"another" always open' 'as `as <role>`'
    s28_has "$KIT/plugins/projects/commands/adopt.md" "**The person's role in it**" '**Roles**' '"another" always open' '`- <name> — accountable — as <role> — <profile>`' \
        'A project without one is not missing anything' 'The one exception is the person'"'"'s role'
    s28_has "$KIT/plugins/ongoing/commands/adopt.md" "**People, with the person's role in it**" '**Roles** list' '"another" always open' 'its own part of their People line, `— as <role> —`'
    s28_has "$KIT/plugins/projects/commands/pickup.md" '**Your role in it:**' 'Omit the line when their line carries none' \
        '**Questioning the plan.**' 'Questions about the plan' 'stopping on the person'"'"'s word' 'With no open branch, there is no offer.')"
empty "28 /ongoing:new and both adopt commands ask the role from the profile's Roles; pickup names it and offers the questions for a plan with open branches" "$s28_bad"

# ---- Using the role: the session-start line names it; with none, the line is as it was ------------
s28_hook="$KIT/plugins/projects/hooks/session-start.sh"
# s28_line <hook> <cwd>: the line the person sees, from a hook run with its own stamp folder.
s28_line() { jq -nc --arg c "$2" '{cwd: $c, source: "startup"}' \
    | env PROJECTS_HOOK_STATE_DIR="$s28/stamps" "$st_bash" "$1" 2>/dev/null | jq -r '.systemMessage // empty'; }
s28_ctx() { jq -nc --arg c "$2" '{cwd: $c, source: "startup"}' \
    | env PROJECTS_HOOK_STATE_DIR="$s28/stamps" "$st_bash" "$1" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty'; }
if [[ -d "${s28_ws:-}/projects/holiday" ]]; then
    # The hook as origin/main has it, beside its own readme.awk, for the no-role comparison.
    s28_old="$s28/old-hook"; mkdir -p "$s28_old/lib"
    if git -C "$KIT" show origin/main:plugins/projects/hooks/session-start.sh > "$s28_old/session-start.sh" 2>/dev/null \
        && git -C "$KIT" show origin/main:plugins/projects/hooks/lib/readme.awk > "$s28_old/lib/readme.awk" 2>/dev/null; then
        for f in "$KIT"/plugins/projects/hooks/lib/*; do [[ "${f##*/}" == readme.awk ]] || cp "$f" "$s28_old/lib/"; done
        s28_have_old=1
    else s28_have_old=0; fi
    s28_p="$s28_ws/projects/holiday"
    git -C "$s28_ws" config user.name "Sam Lee"
    cp "$s28/with.md" "$s28_p/README.md"
    s28_bad=""
    s28_l="$(s28_line "$s28_hook" "$s28_p")"
    grep_all -F 'accountable Sam Lee (as parent)' <<<"$s28_l" || s28_bad+="owner's role not beside the owner: $s28_l"$'\n'
    grep_all -F ' — you: ' <<<"$s28_l" && s28_bad+="the owner is told their role twice: $s28_l"$'\n'
    grep_all -F 'is who that person is in this work' <<<"$(s28_ctx "$s28_hook" "$s28_p")" || s28_bad+="the agent is not told what the role means"$'\n'
    git -C "$s28_ws" config user.name "Alex Kim"
    s28_l="$(s28_line "$s28_hook" "$s28_p")"
    grep_all -F 'accountable Sam Lee (as parent) — you: as spouse' <<<"$s28_l" || s28_bad+="the person's own role not named: $s28_l"$'\n'
    empty "28 session-start: the owner's role beside their name, and the person's own when they are someone else on People" "$s28_bad"
    cp "$s28/without.md" "$s28_p/README.md"
    if [[ $s28_have_old -eq 1 ]]; then
        s28_n="$(s28_line "$s28_hook" "$s28_p"; s28_ctx "$s28_hook" "$s28_p")"
        s28_o="$(s28_line "$s28_old/session-start.sh" "$s28_p"; s28_ctx "$s28_old/session-start.sh" "$s28_p")"
        [[ -n "$s28_n" && "$s28_n" == "$s28_o" ]] \
            && ok "28 session-start: a README with no role gives exactly the line and context it gave before roles" \
            || ko "28 session-start: a README with no role gives exactly the line and context it gave before roles" "$(diff <(printf '%s\n' "$s28_o") <(printf '%s\n' "$s28_n"))"
    else
        skp "28 session-start with no role against origin/main: origin/main is not in this checkout"
    fi
    # An area: the same role, after the line.
    mkdir -p "$s28_ws/ongoing/garden"
    printf '# Garden\n\n## Desired state\n\nThe garden in good health.\n\n## Current state\n\n- **State:** active\n- **Updated:** 2026-11-01\n\n## People\n\n- Sam Lee — accountable — as gardener\n' > "$s28_ws/ongoing/garden/README.md"
    git -C "$s28_ws" config user.name "Sam Lee"
    s28_l="$(s28_line "$s28_hook" "$s28_ws/ongoing/garden")"
    grep_all -F 'Area: Garden' <<<"$s28_l" && grep_all -F ' — Sam Lee as gardener' <<<"$s28_l" \
        && ok "28 session-start in an area names the owner's role too" \
        || ko "28 session-start in an area names the owner's role too" "$s28_l"
fi

# ---- The board, the update and an older profile: the role offered, never flagged ---------------------
s28_bad="$(s28_has "$KIT/plugins/projects/commands/board.md" '**"by role"**' '**"role <word>"**' 'neither is ever a gap or a flag'
    s28_has "$KIT/plugins/workspace/commands/quick-start.md" 'A profile with no **Roles** list' 'an answer to a question is not a yes to the file'
    s28_has "$KIT/lib/setup/update.sh" 'New in 3.10.0: the roles you hold' 'Nothing needs it; without it, everything reads as before.')"
grep -qF '[write] [by role | role <role>]' "$KIT/plugins/projects/commands/board.md" || s28_bad+="board: no argument hint for the role"$'\n'
# update.sh says it once: only on the update that crosses into 3.10.0.
s28_older="$(sed -n '/^older() {/,/exit 1 }.; }$/p' "$KIT/lib/setup/update.sh")"
s28_got="$(eval "$s28_older"; for p in "3.9.0 3.10.0" "3.10.0 3.10.0" "3.10.1 3.10.0" "2.9.9 3.10.0"; do older $p && echo y || echo n; done | paste -sd' ' -)"
[[ "$s28_got" == "y n n y" ]] || s28_bad+="older(): $s28_got"$'\n'
empty "28 the board groups and filters by role without flagging its absence; setup update and quick-start offer the role to an older profile once" "$s28_bad"

# ---- Written on a yes: the gate runs showed an answer taken for consent --------------------------------
s28_bad="$(s28_has "$KIT/plugins/projects/commands/new.md" "write it only on the person's yes to it" 'is not that yes: show the draft and ask.'
    s28_has "$KIT/plugins/ongoing/commands/new.md" "write it only on the person's yes to it" 'is not that yes: show the draft and ask.')"
empty "28 /projects:new and /ongoing:new write the README only on a yes to it, not on the end of the questions" "$s28_bad"

# ---- The yes covers what was shown; a missing role is never a gap in pickup (PM-169) ----------------
s28_bad="$(s28_has "$KIT/plugins/projects/commands/new.md" 'The yes covers what was shown and nothing more' 'never written on that yes unseen. Quote only what the person said.' \
        'Fill in what the interview settled, shown with the README draft'
    s28_has "$KIT/plugins/ongoing/commands/new.md" 'The yes covers what was shown and nothing more' 'Fill in what the interview settled, shown with the README draft'
    s28_has "$KIT/plugins/projects/commands/pickup.md" 'A role is optional on every People line, theirs and everyone else' \
        'neither **Worth knowing** nor what comes after the brief mentions a missing role')"
empty "28 a yes to the draft writes only what was shown; pickup never lists a missing role as a gap" "$s28_bad"

# ---- Written on a yes, in every command that writes (PM-173) ------------------------------------------
s28_bad=""
for s28_f in projects/commands/adopt.md projects/commands/close.md projects/commands/hold.md projects/commands/rename.md \
             ongoing/commands/adopt.md ongoing/commands/review.md ongoing/commands/pause.md ongoing/commands/drop.md \
             workspace/commands/quick-start.md scheduler/commands/tasks.md closeout/commands/closeout.md; do
    s28_bad+="$(s28_has "$KIT/plugins/$s28_f" '## Written on a yes' "written only on the person's yes to it" \
        "the end of the questions, or \"that's all\" is not that yes" 'The yes covers what was shown and nothing more' 'Quote only what the person said.')"
done
s28_bad+="$(s28_has "$KIT/plugins/projects/commands/adopt.md" 'Draft mode is the one exception, by design'
    s28_has "$KIT/plugins/closeout/commands/closeout.md" 'Mechanical, uncontested promotions are the exception, by design')"
empty "28 every command that writes shows the change first and writes it only on a yes to it, with the two exceptions named" "$s28_bad"

# A role written inside the part for the five roles ("accountable, as marketing lead", as one live adopt
# run wrote it) is read too; "accountable, responsible" is not a role.
printf '# P\n\n## People\n\n- Jo Rivera — accountable, as marketing lead — `memory/people/jo.md`\n- Kim — accountable, responsible\n' > "$s28/comma.md"
s28_got="$(awk -f "$s28_awk" "$s28/comma.md" | awk -F '\037' '{ print $8 "|" $21 }')"
[[ "$s28_got" == "Jo Rivera|Jo Rivera=marketing lead" ]] \
    && ok "28 readme.awk reads a role written as ', as <role>' inside the five roles' part, and no role in 'accountable, responsible'" \
    || ko "28 readme.awk reads a role written as ', as <role>' inside the five roles' part, and no role in 'accountable, responsible'" "$s28_got"
