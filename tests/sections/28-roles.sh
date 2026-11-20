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
printf '# Holiday\n\n## Desired outcome\n\nA week away.\n\n## People\n\n- Sam Lee — accountable — as parent — `memory/people/sam-lee.md`\n- Alex — consulted — as spouse\n' > "$s28/with.md"
printf '# Holiday\n\n## Desired outcome\n\nA week away.\n\n## People\n\n- Sam Lee — accountable — `memory/people/sam-lee.md`\n- Alex — consulted\n' > "$s28/without.md"
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
    s28_has "$KIT/plugins/projects/commands/adopt.md" "**The person's role in it**" '**Roles**' '"another" always open' 'becomes `as <role>` on their own People line' \
        'A project without one is not missing anything' 'The one exception is the person'"'"'s role'
    s28_has "$KIT/plugins/ongoing/commands/adopt.md" "**People, with the person's role in it**" '**Roles** list' '"another" always open' 'becomes `as <role>`'
    s28_has "$KIT/plugins/projects/commands/pickup.md" '**Your role in it:**' 'Omit the line when their line carries none' \
        '**Questioning the plan.**' 'Questions about the plan' 'stopping on the person'"'"'s word' 'With no open branch, there is no offer.')"
empty "28 /ongoing:new and both adopt commands ask the role from the profile's Roles; pickup names it and offers the questions for a plan with open branches" "$s28_bad"
