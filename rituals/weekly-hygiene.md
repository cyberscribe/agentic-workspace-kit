# Weekly Hygiene

*Is everything where it belongs, and what is the always-loaded tier costing this week?*

> Two stages: a deterministic scan, then a judgement pass. Scriptable in an afternoon; worth doing by
> hand first, so the script encodes checks you have actually found useful. `/workspace:hygiene` runs
> this ritual with an agent, writing its report to `audits/`.

---

## Stage 1 — the mechanical pass

Eight checks. Each is deterministic, and each answers a question a person would otherwise have to
remember to ask.

| Check | What it looks at |
|---|---|
| **Always-loaded budget** | Bytes in each always-loaded file, and the change since the last run |
| **Strays** | Durable-looking files outside the conventions — loose at the root, loose in `projects/`, or sitting in a scratch directory long enough to have stopped being scratch |
| **Registers** | Project folders against the rows in the index, in both directions |
| **Promised, absent** | Paths the canonical-fact table names that do not exist on disk |
| **Promotion candidates** | Project decisions carrying a *Generalises as* field that have not reached the cross-project log |
| **Staleness** | Guidance whose own "last updated" line has gone quiet |
| **Pending work** | Proposals the other rituals left unconfirmed |
| **Drafts sweep** | Closeout's drafts for this repository and each project folder, oldest first: drafts not yet promoted, and the files of other kinds and subdirectories that the drafts' retention never touches |

Add version-control state and any bridge or mirror your setup keeps in sync. If the repository keeps
metrics with `pilot/measure.sh`, its weekly run belongs to this pass, and its row goes in the report.
If it keeps ablations in `pilot/ablations/`, the pass offers to run them after `measure.sh`
(`pilot/ablate.sh --target <repository>`, from the kit checkout), with the number of runs and their
API-equivalent cost stated first; the person decides, and `measure.sh` runs again afterwards so the
week's row counts the new results. Run or not, the report carries each ablation's latest flag, and lists demotion
candidates and checks that need revision under pending work.
Write the report to a dated file, keep it, and **commit it** — the trail is what lets you tell a clean
week from a broken check, and a trail on one machine reaches nobody. Excluding audit output from
version control is a common reflex because it looks like noise; it is the record of whether the noise
means anything.

**The drafts sweep proposes; it never deletes.** Closeout prunes a draft only after it has been shown
in a session opened in the same folder, and only a top-level Markdown draft. A transcript left beside
the drafts, a research folder, or the drafts of a project nobody opens again stay until a person
clears them. The sweep lists each with its age and size and proposes promote, clear or leave; the
clearing is the person's.

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

**8. Demotion is a proposal; the person applies it.** A demotion candidate is a line whose ablation found no
difference three weeks running: bring it back with its flag history and the cheaper tier it could
move to, and let the person decide. A check that needs revision says nothing about its line; the
proposal is to rework the check, and the line stays where it is.

**9. Check the stores the scan cannot see.** Any per-surface or personal memory the script has no
access to gets read in the same pass. Project-scoped material held as content rather than as a pointer
is the drift the taxonomy exists to prevent.

**10. Leave version control alone.** List the files touched, new against modified, and let a human
commit.

## What this pass does not do

- **Rewrite prose for register drift.** That is a separate, slower check. The two are complementary:
  this one asks whether a file is in the right place, that one asks how it reads.
- **Touch project content.** A project's own files are its business. This pass looks at where things
  live and whether the registers agree with the disk.
- **Reorganise on taste.** A convention that keeps being broken is evidence about the convention.
  Bring that back as a proposal rather than enforcing it a fourth time.
