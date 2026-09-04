# Changelog

Versions of the workspace context kit. Newest first. Entries are corrected by appending, not by
rewriting — the record of what a version claimed is part of what the version is.

---

## v1.1 — 2026-09-04

Revised after auditing the workspace this kit was extracted from against the kit's own claims. Every
change below is something the audit demonstrated rather than something that seemed sensible.

**`README.md` §2.1 — the manifest split is a habit, not an event.** v1.0 reported that splitting an
overgrown always-loaded file cut it roughly in half, and stopped there. Four months after that split
the same file had regained about ten per cent and had reacquired a section of pure runtime detail.
The section now says what maintains the split: the weekly budget line, reported whether or not it
moved.

**`README.md` §2.2 — a canonical-fact table is a claim, not a mechanism.** Nothing enforces it until
something reads two files and compares them. Adds the consolidation rule that follows from it: merge
the uniques first and point second, and where two copies disagree, keep the losing reading in the
winning file. A deleted disagreement looks like agreement.

**`README.md` §4.4 (new) — read the rituals you already have before adding one.** The audited
workspace acquired a duplicate weekly pass in a single morning. When two overlap, split them by kind
of work — one produces a dated artefact mechanically, the other reads it and exercises judgement —
rather than by subject.

**`README.md` §4.2, `rituals/weekly-hygiene.md`, `docs/documentation-register.md` — commit the audit
trail.** v1.0 said to keep the dated reports while the workspace it came from kept them out of version
control. A trail on one machine reaches nobody, which is the visibility rule applied to your own
instruments.

**`README.md` Part 7 — a ritual on paper is a claim, not a practice.** The check is artefacts. A
defined-but-unpractised ritual reads exactly like a working one in a document. Also added as an
honesty check in `rituals/closeout.md`, which is the ritual most likely to exist only on paper.

**`docs/memory-layers.md` §7** — fifth house rule: merge before you point.

## v1.0 — 2026-09-04

First extraction. Eight files: the guide, a manifest skeleton, the taxonomy, the placement map, the
documentation register, two ritual procedures, and two document templates.

Drawn from a working folder shared by several agent surfaces over roughly a year of daily use, then
stripped of everything specific to that setting — clients, projects, people, tools, paths.
