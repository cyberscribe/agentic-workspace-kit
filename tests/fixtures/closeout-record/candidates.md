transcript: transcript.jsonl

### The flake came from a stale lock file left by a killed worker
- tier: Project reference
- scope: shared
- destination: docs/DECISIONS.md
- why this tier: it explains this project's test harness, and nothing outside it
- check: supported
- evidence: L11 "leaves its lock file behind when it is killed"
- evidence: L13 "50 runs: 50 passed, removing the stale lock on start"

A killed worker leaves its lock file behind, and the next run waits on it.

### Raising the worker timeout to 30s fixes the flake
- tier: Project reference
- scope: shared
- destination: docs/DECISIONS.md
- why this tier: a future session would try the same fix first
- check: contradicted
- was: L6 "Raising the timeout to 30s fixes the flake"
- evidence: L8 "It flaked again on CI after the change"
- correction: Raising the timeout did not fix the flake; it came back on CI and the change was reverted.

Twenty passing runs after the timeout change were luck; the flake returned on CI.

### The CI runner has 4 cores
- tier: Project reference
- scope: shared
- destination: docs/ci.md
- why this tier: it bounds how many workers a test can start
- check: unsupported
- missing: nothing in the session measured the runner; the only mention is an attachment, not a turn

The CI runner has 4 cores.

### Every worker script removes a stale lock on start
- tier: Working standards
- scope: shared
- destination: CLAUDE.md
- why this tier: any session writing a worker script would otherwise reintroduce the flake
- check: supported
- evidence: L14 "Remove the stale lock on start from now on, in every worker script"
- evidence: L13 "50 runs: 50 passed, removing the stale lock on start"

A worker script removes its stale lock file on start.
