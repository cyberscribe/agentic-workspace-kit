import { expect, test } from 'claude-code/testing'
import type { On, ProcessRunResult } from 'claude-code'

function result(stdout = '', exitCode = 0): ProcessRunResult {
  return { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
}

// The engine's measurement echoes what moved, and the session offers commands from two plugins and one built
// in. Each process call the module makes is kept, and answered as if the reading were written.
function beneath(on: On, runs: (readonly string[])[]) {
  on('session.measure', (_, e) => ({ changed: e.changed }))
  on('session.surfaces', () => ({ value: ['terminal' as const] }))
  on('command.list', () => ({
    value: [
      { name: 'workspace:hygiene', description: 'd', source: 'plugin' as const, plugin: 'workspace' },
      { name: 'clear', description: 'd', source: 'builtin' as const },
      { name: 'projects:new', description: 'd', source: 'plugin' as const, plugin: 'projects' },
      { name: 'projects:board', description: 'd', source: 'plugin' as const, plugin: 'projects' },
    ],
  }))
  on('process.run', (_, e) => {
    runs.push(e.argv)
    return { value: result() }
  })
}

const measured = (tokens: number | undefined) => ({
  context: tokens === undefined ? { window: 200_000 } : { tokens, window: 200_000, percent: Math.round(tokens / 2_000) },
  rateLimits: [],
  changed: ['context' as const],
})

test('the first measurement with a token count is recorded once, with the tokens and the window', async ($, on) => {
  const runs: (readonly string[])[] = []
  beneath(on, runs)

  // Before the first response the window has no count: nothing is recorded yet.
  await $.session.measure(measured(undefined))
  expect(runs.length).toBe(0)

  await $.session.measure(measured(26_702))
  expect(runs.length).toBe(1)
  const argv = runs[0] ?? []
  expect(argv[0]).toBe('bash')
  // bash -c <script> <$0> <boundary.sh> <tokens> <window> <plugins>
  expect(argv[4]).toMatch(/\/hooks\/lib\/boundary\.sh$/)
  expect(argv[5]).toBe('26702')
  expect(argv[6]).toBe('200000')
  // The plugins with commands in the session, each once, sorted; a built-in command names none.
  expect(argv[7]).toBe('projects,workspace')
  expect(argv[8]).toBe('terminal')
  // The script records only inside a kit workspace, with the time from date and its UTC offset.
  expect(argv[2]).toContain('aw_workspace_root')
  expect(argv[2]).toContain("date '+%Y-%m-%d %H:%M %z'")
  expect(argv[2]).toContain('agentic-workspace-kit/workspace')

  // Later turns record nothing more.
  await $.session.measure(measured(31_000))
  expect(runs.length).toBe(1)
})

test('a reading that cannot be written leaves the session as it was', async ($, on) => {
  on('session.measure', (_, e) => ({ changed: e.changed }))
  on('process.run', () => {
    throw new Error('no shell here')
  })
  const answer = await $.session.measure(measured(18_804))
  expect(answer).toEqual({ changed: ['context'] })
})
