# Weekly Hygiene

*Is everything where it belongs, and what is the always-loaded tier costing this week?*

> Two stages: a deterministic scan, then a judgement pass. Scriptable in an afternoon; worth doing by
> hand first, so the script encodes checks you have actually found useful.

---

## Stage 1 — the mechanical pass

Seven checks. Each is deterministic, and each answers a question a person would otherwise have to
remember to ask.

| Check | What it looks at |
|---|---|
| **Always-loaded budget** | Bytes in each always-loaded file, and the change since the last run |
| **Strays** | Durable-looking files outside the conventions — loose at the root, loose in `projects/`, or sitting in a scratch directory long enough to have stopped being scratch |
| **Registers** | Project folders against the rows in the index, in both directions |
| **Promised, absent** | Paths the canonical-fact table names that do not exist on disk |
| **Promotion candidates** | Project decisions carrying a *Generalises as* field that have not reached the cross-project log |
| **Staleness** | Guidance whose own "last updated" line has gone quiet |
| **Waiting work** | Drafts or captures the other rituals left unpromoted |

Add version-control state and any bridge or mirror your setup keeps in sync. Write the report to a
dated file, keep it, and **commit it** — the trail is what lets you tell a clean week from a broken
check, and a trail on one machine reaches nobody. Excluding audit output from version control is a
common reflex because it looks like noise; it is the record of whether the noise means anything.

**Leave link checking out**, or implement all the reference forms in `docs/workspace-map.md` first. A
checker that assumes every reference is a relative path reports most of a mature tree as broken.

**Watch what the check itself touches.** A scan that calls a version-control command from an
environment that cannot clean up after itself will report the lock file it just created. A monitor
that mutates the system it observes reports itself, and the first run is where you find out.

## Stage 2 — the judgement pass

Work the report top to bottom.

**1. Classify every stray by content type before moving it.** The four types and their destinations
are in `docs/memory-layers.md`. A file that resists classification is usually tracking or scratch, and
belongs in neither store.

**2. Apply the uncontested moves; propose the rest.** Moving a stray draft into the drafts folder is
mechanical. Deciding that a note is working standards rather than general reference changes what loads
every session — that one comes back as a proposal.

**3. Nothing is deleted.** Strays move to their home; superseded material is marked superseded with a
pointer and keeps its name. Where something genuinely needs removing, stage it somewhere obvious and
say so.

**4. Read the budget line even when it has not moved.** If it grew, name what grew and whether the
addition named what it replaced. If it is flat, say so in one line — the trend is the finding.

**5. Treat a promised-but-absent file as a question, not a fault.** If this week supplied a first use,
create it. Otherwise note that it is still waiting.

**6. Refresh a stale date only when the content actually moved.** A "last updated" line that disagrees
with the file's edit history *is* the finding; rewriting the date without checking what changed
converts a real signal into a clean-looking lie.

**7. Promotion is proposed, never silent.** For each promotion candidate, apply the strip filter —
remove the project, the stack and the stakeholder, and see whether anything survives — and bring the
proposed general-form rewrite back to a human. The cross-project log is consulted by every future
session; entries arriving in it are a person's call.

**8. Check the stores the scan cannot see.** Any per-surface or personal memory the script has no
access to gets read in the same pass. Project-scoped material held as content rather than as a pointer
is the drift the taxonomy exists to prevent.

**9. Leave version control alone.** List the files touched, new against modified, and let a human
commit.

## What this pass does not do

- **Rewrite prose for register drift.** That is a separate, slower check. The two are complementary:
  this one asks whether a file is in the right place, that one asks how it reads.
- **Touch project content.** A project's own files are its business. This pass looks at where things
  live and whether the registers agree with the disk.
- **Reorganise on taste.** A convention that keeps being broken is evidence about the convention.
  Bring that back as a proposal rather than enforcing it a fourth time.
