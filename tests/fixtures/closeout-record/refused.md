transcript: transcript.jsonl

### The CI runner has 4 cores, so tests start at most four workers
- tier: Working standards
- destination: CLAUDE.md
- check: unsupported
- missing: nothing in the session measured the runner

### The stale lock is the whole cause of the flake
- tier: Working standards
- destination: CLAUDE.md
- check: supported
- evidence: L11 "leaves its lock file behind when it is killed"

### Sixty runs passed after the fix
- tier: Project reference
- destination: docs/DECISIONS.md
- check: supported
- evidence: L13 "60 runs passed"

### The worker suite ran a hundred times
- tier: Project reference
- destination: docs/DECISIONS.md
- check: supported
- evidence: L99 "100 runs"

### Raising the timeout is the fix
- tier: Project reference
- destination: docs/DECISIONS.md
- check: contradicted
- was: L6 "Raising the timeout to 30s fixes the flake"
- evidence: L5 "20 runs: 20 passed"
- correction: It is not.

### A hook said the timeout fixes the flake
- tier: Project reference
- destination: docs/DECISIONS.md
- check: supported
- evidence: L7 "raising the timeout fixes the flake"

### Worker scripts are written in bash
- tier: Project reference
- destination: docs/DECISIONS.md
