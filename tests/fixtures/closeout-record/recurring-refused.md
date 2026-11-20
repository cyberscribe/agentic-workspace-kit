transcript: recurring.jsonl

### A command for renaming the screenshot folder
- plain: Renaming the screenshot folder could be a command.
- source: recurring
- kind: command
- existing: none
- cost: 90
- tier: Templates & agent roles
- destination: .claude/commands/rename-shots.md
- check: supported
- evidence: L8 "Renamed the old screenshot folder once, by hand."

### A skill for the docs release, cited once
- plain: Cutting a docs release could be a skill.
- source: recurring
- kind: skill
- recurs: repeated
- existing: none
- tier: Templates & agent roles
- destination: skills/docs-release/SKILL.md
- check: supported
- evidence: L2 "Release steps: bump the version, build, check the links, then tag."

### The dependency review, said by the agent
- plain: The dependency review is a role for a helper.
- source: recurring
- kind: agent
- recurs: said
- tier: Project reference
- destination: projects/deps/README.md
- check: supported
- evidence: L7 "Asked a subagent to read the lock files"

### A macro for the release
- plain: The release could be a macro.
- source: recurring
- kind: macro
- recurs: repeated
- existing: none
- tier: Templates & agent roles
- destination: skills/release-macro/SKILL.md
- check: supported
- evidence: L2 "Release steps: bump the version"
- evidence: L5 "Release steps again"

### The docs-release skill gains the second release's steps, filed as general reference
- plain: The docs-release skill could carry the steps both releases used; a skill is general reference too.
- source: recurring
- kind: skill
- recurs: repeated
- existing: skills/docs-release/SKILL.md
- cost: 0
- tier: General reference
- scope: shared
- destination: skills/docs-release/SKILL.md
- check: supported
- evidence: L2 "Release steps: bump the version, build, check the links, then tag."
- evidence: L5 "Release steps again"

An update to the skill already there.
