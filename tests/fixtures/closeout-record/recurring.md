transcript: recurring.jsonl

### A skill for cutting a docs release: bump, build, check links, tag
- plain: Cutting a docs release is the same four steps each time; a skill could carry them.
- source: recurring
- kind: skill
- recurs: repeated
- existing: none
- cost: 118
- tier: Templates & agent roles
- scope: shared
- destination: skills/docs-release/SKILL.md
- check: supported
- evidence: L2 "Release steps: bump the version, build, check the links, then tag."
- evidence: L5 "Release steps again: bump the version, build, check the links, then tag."

Name, when it applies (a docs release), and the four steps.

### An agent definition for the Monday dependency review
- plain: The Monday dependency review is a role for a helper that reads the lock files and changes nothing.
- source: recurring
- kind: agent
- recurs: said
- existing: none
- tier: Templates & agent roles
- scope: shared
- destination: .claude/agents/dependency-review.md
- check: supported
- evidence: L6 "I hand the dependency review to a helper every Monday"
- evidence: L7 "it changed no files"

It may read the lock files; it reports each changed package.

### The release checklist gains the link check
- plain: The existing release checklist should list the link check before the tag.
- source: recurring
- kind: checklist
- recurs: earlier-round rituals/release.md
- existing: rituals/release.md
- tier: Templates & agent roles
- scope: shared
- destination: rituals/release.md
- check: supported
- evidence: L3 "links: 0 broken; tagged docs-v4.1"

An update to the checklist already there, not a new one.
