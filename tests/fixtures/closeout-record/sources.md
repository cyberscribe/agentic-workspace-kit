transcript: sources.jsonl

### Build summaries for the support team name the broken feature and who to ask, without stack traces
- plain: Write build summaries for the support team as which feature broke and who to ask, not stack traces.
- source: correction
- tier: Project reference
- scope: shared
- destination: projects/builds/README.md
- why this tier: it is how this project's summaries are written, and nowhere else
- check: supported
- evidence: L6 "The support team will not read stack traces. Say which feature broke and who to ask"
- was: L5 "group the failures by stack trace and quote each trace in full"

The summaries are for the support team: the feature and the person to ask, in plain words.

### The person to ask about each feature is in notes/owners.jsonl, not CODEOWNERS
- plain: Who to ask about each feature is listed in notes/owners.jsonl; CODEOWNERS only names reviewers.
- source: missing-context
- tier: Project reference
- scope: shared
- destination: projects/builds/README.md
- why this tier: the session looked in CODEOWNERS first and would again
- check: supported
- evidence: L9 "CODEOWNERS only names reviewers" (the agent, after reading the file)
- evidence: L8 "{\"feature\": \"checkout\", \"owner\": \"Priya\"}\n{\"feature\": \"search\""

Feature owners are in notes/owners.jsonl.

### The daily task summarises overnight build failures and checks for flaky tests
- plain: Each weekday morning the task writes up the night's failed builds and looks for flaky tests.
- source: missing-context
- tier: Project reference
- scope: shared
- destination: projects/builds/README.md
- why this tier: it says what the scheduled run is for
- check: supported
- evidence: L1 "summarise the overnight build failures into notes/builds.md"
- evidence: L2 "check the build log for tests marked flaky"

The scheduled task's job, from its prompt.

### Summaries are kept short
- plain: Keep summaries short.
- source: general
- tier: General reference
- scope: shared
- destination: docs/writing.md
- why this tier: it applies beyond this project
- check: supported
- evidence: L11 "Keep summaries short in general."

A general preference for short summaries.

### CODEOWNERS names reviewers
- plain: The CODEOWNERS file lists who reviews changes.
- source: missing-context
- tier: Project reference
- destination: projects/builds/README.md
- check: already-written
- found: .github/CODEOWNERS, whose first line says what it is for
- evidence: L9 "CODEOWNERS only names reviewers"

### The search tests failed twice with no change to the search code
- plain: The search tests failed twice last night, and nothing in the search code had changed; the cause is not known.
- source: missing-context
- tier: Project reference
- destination: projects/builds/README.md
- check: observed
- evidence: L12 "failed twice with no change to the search code, and the log does not say why"

### git status from the VM leaves a lock behind
- plain: Running `git status` from the VM leaves a lock on the repository, and the next git command fails; use `git --no-optional-locks status` there.
- source: correction
- tier: Project reference
- scope: shared
- destination: projects/builds/README.md
- why this tier: the first git command anyone runs from the VM walks into it, and nothing in the repository says so
- check: supported
- evidence: L15 "Unable to create '/repo/.git/index.lock': File exists."
- evidence: L16 "That lock is left by git status from the VM. Use git --no-optional-locks status there"

The trap on the obvious next move: the likely command, what goes wrong, what to do instead.
