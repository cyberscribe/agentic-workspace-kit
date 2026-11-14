transcript: transcript.jsonl

### The CI runner has 4 cores, so tests start at most four workers
- plain: Tests start no more than four workers, because the build machine has four cores.
- source: missing-context
- tier: Working standards
- destination: CLAUDE.md
- check: unsupported
- missing: nothing in the session measured the runner

### The stale lock is the whole cause of the flake
- plain: The old lock file is the only reason the test was flaky.
- source: missing-context
- tier: Working standards
- destination: CLAUDE.md
- check: supported
- evidence: L11 "leaves its lock file behind when it is killed"

### Sixty runs passed after the fix
- plain: The test passed sixty times after the fix.
- source: missing-context
- tier: Project reference
- destination: docs/DECISIONS.md
- check: supported
- evidence: L13 "60 runs passed"

### The worker suite ran a hundred times
- plain: The worker tests were run a hundred times.
- source: missing-context
- tier: Project reference
- destination: docs/DECISIONS.md
- check: supported
- evidence: L99 "100 runs"

### Raising the timeout is the fix
- plain: Giving the worker more time fixes the test.
- source: missing-context
- tier: Project reference
- destination: docs/DECISIONS.md
- check: contradicted
- was: L6 "Raising the timeout to 30s fixes the flake"
- evidence: L5 "20 runs: 20 passed"
- correction: It is not.

### A hook said the timeout fixes the flake
- plain: A reminder said more time fixes the test.
- source: missing-context
- tier: Project reference
- destination: docs/DECISIONS.md
- check: supported
- evidence: L7 "raising the timeout fixes the flake"

### Worker scripts are written in bash
- plain: The worker scripts are shell scripts.
- source: general
- tier: Project reference
- destination: docs/DECISIONS.md
