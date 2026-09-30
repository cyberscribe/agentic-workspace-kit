# Reads project entry points (README.md or the conventions' entry point) and
# prints one record per file, fields separated by the unit separator (\037):
#
#   file  has_block  state  outcome  done_found  done_total  done_ticked  owner
#   proposed  title  people_found  blocked_by  blocked_since  updated  old_format
#   versioned  sensitivity  resources  resources_generated  resources_ignored
#
# Fields 16-20 were added in kit 3.0, after the first fifteen, so a reader takes
# fields by position (awk -F '\037' '{ print $17 }') or ends a read with a spare
# variable; a reader of the first fifteen keeps working.
#
# The parser contract the projects commands and pilot/measure.sh share (see "How
# the files are read" in the plugin README):
# - Current state lines are "- **Label:** value"; a plain "Label:" is read the
#   same way. Values come from the Current state section when there is one, else
#   from anywhere.
# - has_block is 1 when the file has a Current state heading or a State: line.
# - A value that is empty, "-", "—", "none" or "n/a", or begins "none found",
#   "not yet named" or "<" (a template stand-in), is an honest gap: printed as
#   empty.
# - blocked_since is the date after "since" in the Blocked by value; another date
#   on the line (a due date, say) leaves it undated.
# - A heading's name is its text up to the first " — ", " – ", "(" or ":", without
#   markup, lowercased; it is compared exactly with "done when", "desired outcome",
#   "people", "current state", or an alias passed in as alias_done /
#   alias_outcome / alias_people (lowercase, "|"-joined).
# - A heading named "now" is the block's earlier format: it is read as the block,
#   and old_format is 1, so a reader can say the file wants converting rather
#   than misreading it.
# - Done when counts checklist lines only ("- [ ]", "- [x]").
# - A block inserted by /projects:adopt --draft carries a "proposed by
#   /projects:adopt" comment; its presence sets proposed=1.
# - versioned is the first "Versioned:" label outside fences and HTML comments,
#   bold or plain: its first word, lowercased, kept only when it is workspace,
#   own-repo or untracked. sensitivity is the same for "Sensitivity:" with normal
#   and sensitive. Anything else, a stand-in included, is empty; an empty
#   sensitivity reads as normal.
# - resources are the list items under a heading named "resources": the name is
#   the item's text before the first " — ", " – ", " - " or ":", without
#   backticks, kept when it is letters, digits, dot, dash and underscore (starting
#   with a letter or digit). resources_generated are those whose description says
#   "generated", in any case. resources_ignored are the item names that did not fit
#   the pattern, so a reader can name them. Stand-ins ("<name>") are skipped. Each
#   list is comma-joined.
#
# Portable across BSD awk and gawk: no gensub, no IGNORECASE, no arrays of arrays.

function flush(   st, bb, up) {
    if (file == "") return
    if (block_section) { st = blk_state; bb = blk_blocked; up = blk_updated }
    else { st = any_state; bb = any_blocked; up = any_updated }
    printf "%s\037%d\037%s\037%s\037%d\037%d\037%d\037%s\037%d\037%s\037%d\037%s\037%s\037%s\037%d\037%s\037%s\037%s\037%s\037%s\n", \
        file, (block_section || any_state != ""), st, outcome, done_found, done_total, done_ticked, \
        owner, proposed, title, people_found, bb, since_date(bb), up, old_format, \
        versioned, sensitivity, res_names, res_generated, res_ignored
}

function reset() {
    block_section = 0; blk_state = ""; blk_blocked = ""; blk_updated = ""
    any_state = ""; any_blocked = ""; any_updated = ""
    outcome = ""; done_found = 0; done_total = 0; done_ticked = 0; owner = ""
    proposed = 0; title = ""; section = ""; fence = 0
    people_found = 0; old_format = 0
    cont_blk = 0; cont_any = 0; outcome_done = 0
    versioned = ""; sensitivity = ""; versioned_seen = 0; sensitivity_seen = 0
    res_names = ""; res_generated = ""; res_ignored = ""; in_cmt = 0; vis = ""
}

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

# The line with any HTML comment removed, carrying an open comment across lines
# in in_cmt. Used by fields 16-20, which ignore anything inside a comment.
function visible(line,   out, p) {
    out = ""
    while (line != "") {
        if (in_cmt) {
            p = index(line, "-->"); if (!p) return out
            line = substr(line, p + 3); in_cmt = 0
        } else {
            p = index(line, "<!--"); if (!p) return out line
            out = out substr(line, 1, p - 1); line = substr(line, p + 4); in_cmt = 1
        }
    }
    return out
}

# The first word of a label's value, markup stripped and lowercased; "" when the
# value is not one of the allowed words (a space-separated list).
function first_word(v, allowed,   w, n, a, i) {
    gsub(/\*|`|_/, "", v)
    v = trim(v)
    split(v, w, /[ \t,;.(]/)
    v = tolower(w[1])
    n = split(allowed, a, " ")
    for (i = 1; i <= n; i++) if (v == a[i]) return v
    return ""
}

function add_to(list, item) { return list == "" ? item : list "," item }

function since_date(s,   low) {
    low = tolower(s)
    if (match(low, /since[ \t]+[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return substr(s, RSTART + RLENGTH - 10, 10)
    return ""
}

function first_date(s) {
    if (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return substr(s, RSTART, RLENGTH)
    return ""
}

# The heading's name: up to the first " — ", " – ", "(" or ":", without markup,
# lowercased. "Done when — checklist" and "People *(optional)*" read as
# "done when" and "people".
function heading_name(s,   n) {
    sub(/^#+[ \t]*/, "", s)
    gsub(/\*|`/, "", s)
    n = index(s, " — "); if (n) s = substr(s, 1, n - 1)
    n = index(s, " – "); if (n) s = substr(s, 1, n - 1)
    n = index(s, "("); if (n) s = substr(s, 1, n - 1)
    n = index(s, ":"); if (n) s = substr(s, 1, n - 1)
    return tolower(trim(s))
}

function is_named(name, canonical, aliases,   n, a, i) {
    if (name == canonical) return 1
    if (aliases == "") return 0
    n = split(aliases, a, "|")
    for (i = 1; i <= n; i++) if (a[i] != "" && name == a[i]) return 1
    return 0
}

function is_gap(v,   low) {
    low = tolower(trim(v))
    return (low == "" || low == "-" || low == "—" || low == "none" || low == "n/a" || \
            index(low, "none found") == 1 || index(low, "not yet named") == 1 || index(low, "<") == 1)
}

# The value after "Label:" on a labelled line, or "\001" when the line is not that label.
function label_value(line, label,   low, pat) {
    low = tolower(line)
    pat = "^[ \t]*([-*][ \t]+)?(\\*\\*)?" label "(\\*\\*)?:(\\*\\*)?[ \t]*"
    if (match(low, pat)) {
        line = substr(line, RLENGTH + 1)
        gsub(/`/, "", line)
        return trim(line)
    }
    return "\001"
}

FNR == 1 { flush(); reset(); file = FILENAME }

/^[ \t]*```/ { fence = !fence; next }
fence { next }

# Fields 16-20 read the visible text only; this rule consumes nothing.
{ vis = visible($0) }

!versioned_seen && vis != "" {
    v = label_value(vis, "versioned")
    if (v != "\001") { versioned_seen = 1; versioned = first_word(v, "workspace own-repo untracked") }
}
!sensitivity_seen && vis != "" {
    v = label_value(vis, "sensitivity")
    if (v != "\001") { sensitivity_seen = 1; sensitivity = first_word(v, "normal sensitive") }
}
section == "resources" && vis ~ /^[ \t]*[-*][ \t]+/ {
    item = vis; sub(/^[ \t]*[-*][ \t]+/, "", item); gsub(/`/, "", item)
    rname = item; rdesc = ""
    n = 0
    split(" — | – | - |:", seps, "|")
    for (i = 1; i <= 4; i++) {
        p = index(item, seps[i])
        if (p && (n == 0 || p < n)) { n = p; nl = length(seps[i]) }
    }
    if (n) { rname = substr(item, 1, n - 1); rdesc = substr(item, n + nl) }
    rname = trim(rname)
    if (rname != "" && index(rname, "<") != 1) {
        if (rname ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) {
            res_names = add_to(res_names, rname)
            if (tolower(rdesc) ~ /generated/) res_generated = add_to(res_generated, rname)
        } else res_ignored = add_to(res_ignored, rname)
    }
}

/proposed by \/projects:adopt/ { proposed = 1 }

# A hard-wrapped Blocked by carries on in indented lines that are not new items.
(cont_blk || cont_any) && /^[ \t]+[^ \t]/ && !/^[ \t]*[-*][ \t]/ {
    line = trim($0); gsub(/`/, "", line)
    if (cont_blk) blk_blocked = blk_blocked " " line
    if (cont_any) any_blocked = any_blocked " " line
    next
}
{ cont_blk = 0; cont_any = 0 }

/^[ \t]*<!--/ { next }

/^#[ \t]/ && title == "" {
    title = trim(substr($0, 2)); gsub(/\*|`/, "", title)
    # A CLAUDE.md's title often describes the file ("Thesis rewrite — agent entry
    # point"); the project's name is the part before the dash.
    if (FILENAME ~ /(^|\/)CLAUDE\.md$/) {
        n = index(title, " — "); if (n == 0) n = index(title, " – ")
        if (n > 1) title = trim(substr(title, 1, n - 1))
    }
}

/^#+[ \t]/ {
    name = heading_name($0)
    if (name == "current state") { section = "block"; block_section = 1 }
    else if (name == "now") { section = "block"; block_section = 1; old_format = 1 }
    else if (is_named(name, "done when", alias_done)) { section = "done"; done_found = 1 }
    else if (is_named(name, "desired outcome", alias_outcome)) section = "outcome"
    else if (is_named(name, "people", alias_people)) { section = "people"; people_found = 1 }
    else if (name == "resources") section = "resources"
    else section = ""
    next
}

{
    v = label_value($0, "state")
    if (v != "\001") {
        gsub(/\*/, "", v)
        split(v, w, /[ \t,;.(]/); v = tolower(w[1])
        if (index(v, "<") == 1) v = ""
        if (section == "block" && blk_state == "") blk_state = v
        if (any_state == "") any_state = v
        next
    }
    v = label_value($0, "blocked by")
    if (v != "\001") {
        if (is_gap(v)) v = ""
        if (section == "block" && blk_blocked == "") { blk_blocked = v; cont_blk = (v != "") }
        if (any_blocked == "") { any_blocked = v; cont_any = (v != "") }
        next
    }
    v = label_value($0, "updated")
    if (v != "\001") {
        v = first_date(v)
        if (section == "block" && blk_updated == "") blk_updated = v
        if (any_updated == "") any_updated = v
        next
    }
}

# The outcome is the section's first paragraph, joined across its wrapped lines.
section == "outcome" && !outcome_done {
    line = trim($0)
    if (line == "") { if (outcome != "") outcome_done = 1; next }
    if (outcome == "") {
        sub(/^[-*][ \t]+/, "", line)
        if (index(line, "<") != 1) outcome = line
    } else if (line ~ /^[-*][ \t]/) outcome_done = 1
    else outcome = outcome " " line
    next
}

section == "done" && /^[ \t]*[-*][ \t]+\[[ xX]\]/ {
    done_total++
    if ($0 ~ /\[[xX]\]/) done_ticked++
    next
}

section == "people" && owner == "" && /^[ \t]*[-*][ \t]+/ {
    line = $0
    sub(/^[ \t]*[-*][ \t]+/, "", line)
    low = tolower(line)
    if (low ~ /(^|[^a-z])owns([^a-z]|$)/) {
        # The name is what comes before the first dash separator.
        n = index(line, " — "); if (n == 0) n = index(line, " – "); if (n == 0) n = index(line, " - ")
        if (n > 0) line = substr(line, 1, n - 1)
        gsub(/\*|`/, "", line)
        line = trim(line)
        owner = is_gap(line) ? "" : line
    }
    next
}

END { flush() }
