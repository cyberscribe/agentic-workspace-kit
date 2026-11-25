import type { Register } from 'claude-code'

// Records how full the context window is after a session's first turn: one line per session, for the weekly
// hygiene report. The figure is the status line's, read at no cost from the engine's own measurement, so it
// counts everything the session carries before any work: the system prompt, tools, skills, memory files and
// the text session-start hooks print. Inside a kit workspace only; elsewhere it records nothing.
//
// The line goes to the kit's state folder, outside every repository:
//   ${XDG_STATE_HOME:-~/.local/state}/agentic-workspace-kit/workspace/context-readings.tsv
// as: time (with its UTC offset) · tokens · window · workspace folder · plugins with commands in the session ·
// the surfaces it drew on, or "headless" for a -p run such as a scheduled task, whose first turn is its task.
// scripts/context-readings.sh reads it back for one workspace.
const RECORD = `
source "$1" || exit 0
root="$(aw_workspace_root "")"
[ -n "$root" ] || exit 0
dir="\${XDG_STATE_HOME:-$HOME/.local/state}/agentic-workspace-kit/workspace"
mkdir -p "$dir" || exit 0
printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$(date '+%Y-%m-%d %H:%M %z')" "$2" "$3" "$root" "$4" "$5" >>"$dir/context-readings.tsv"
`

export const register: Register = on => {
  // session.measure fires after each main-thread turn; the first that carries a token count is the first turn.
  let isRecorded = false

  on('session.measure', async ($, e, next) => {
    const result = await next(e)
    if (isRecorded || e.context.tokens === undefined) return result
    isRecorded = true
    try {
      // The plugin set is read from the commands the session offers, so a plugin with no commands is not named.
      const plugins = [...new Set((await $.command.list()).map(c => c.plugin).filter(p => p !== undefined))].sort()
      const surfaces = await $.session.surfaces()
      await $.process.run(
        ['bash', '-c', RECORD, 'context-reading', `${$.plugin.root}/hooks/lib/boundary.sh`,
          String(e.context.tokens), String(e.context.window), plugins.join(','), surfaces.join(',') || 'headless'],
        { timeoutMs: 5_000 },
      )
    } catch {
      // A reading that cannot be written is skipped: the session goes on as if the module were absent.
    }
    return result
  })
}
