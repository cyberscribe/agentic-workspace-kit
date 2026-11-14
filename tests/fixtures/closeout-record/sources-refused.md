transcript: sources.jsonl

### Owners are in notes/owners.jsonl
- source: missing-context
- tier: Project reference
- destination: projects/builds/README.md
- check: supported
- evidence: L9 "the person to ask about each feature is in notes/owners.jsonl"

### Always keep summaries short
- plain: Keep summaries short, everywhere.
- source: general
- tier: Working standards
- destination: CLAUDE.md
- check: supported
- evidence: L11 "Keep summaries short in general."

### Summaries name the feature and the person to ask
- plain: Summaries say which feature broke and who to ask.
- source: correction
- tier: Project reference
- destination: projects/builds/README.md
- check: supported
- evidence: L10 "Checkout broke last night: ask Priya."

### The task was notified when the watch ended
- plain: The run was told a background task had finished.
- source: missing-context
- tier: Project reference
- destination: projects/builds/README.md
- check: supported
- evidence: L3 "task-notification"

### Build summaries are a hunch
- plain: Summaries might help.
- source: hunch
- tier: Project reference
- destination: projects/builds/README.md
- check: supported
- evidence: L10 "Checkout broke last night"

### The build log path is already in the README
- plain: The build log's location is already written down.
- source: missing-context
- tier: Project reference
- destination: projects/builds/README.md
- check: already-written

### Search fails for reasons unknown
- plain: Search tests fail and nobody knows why.
- source: missing-context
- tier: Working standards
- destination: CLAUDE.md
- check: observed
- evidence: L12 "the log does not say why"
