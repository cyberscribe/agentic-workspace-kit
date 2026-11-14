import { expect, mock, test } from 'claude-code/testing'
import type { On, ProcessRunResult } from 'claude-code'
import type { Engine } from 'claude-code/testing'

// The pane is drawn from the CLI's answers, so each test answers `$.process.run` from these fixtures. A waiting
// run, a failed task and a healthy task cover the three sections; the paused task covers the Resume button.
const LIST = [
  // The pane draws the *_words fields, which the CLI writes in words; the raw cron text is kept beside them.
  { name: 'morning-digest', status: 'active', schedule: '30 7 * * 1-5', next: '2026-11-02 07:30', schedule_words: 'weekdays 07:30', next_words: 'Mon 2 Nov 07:30', last_status: 'ok', waiting: '' },
  { name: 'ask-reviewer', status: 'active', schedule: '15 9 * * 1-5', next: '2026-11-02 09:15', schedule_words: 'weekdays 09:15', next_words: 'Mon 2 Nov 09:15', last_status: 'waiting', waiting: 'run-0917' },
  { name: 'branch-check', status: 'active', schedule: '0 18 * * *', next: '2026-10-30 18:00', schedule_words: 'daily 18:00', next_words: 'Fri 30 Oct 18:00', last_status: 'failed', waiting: '' },
  { name: 'old-report', status: 'paused', schedule: '@monthly', next: '', schedule_words: '@monthly', next_words: '', last_status: 'ok', waiting: '' },
]

const SHOW: Record<string, object> = {
  'morning-digest': { backend: 'launchd', fields: {}, last_run: { end: '2026-10-30 07:30:02', session_id: 'sess-digest' } },
  'ask-reviewer': { backend: 'launchd', fields: {}, last_run: { end: '2026-10-30 09:17:00', session_id: 'sess-review' } },
  'branch-check': { backend: 'launchd', fields: {}, last_run: { end: '2026-10-29 18:00:04', session_id: 'sess-branch' } },
  'old-report': { backend: 'launchd', fields: { paused_reason: 'paused by hand' }, last_run: null },
}

// Keyed by the argument vector after schedule.sh, joined by spaces.
const CLI: Record<string, string> = {
  home: 'Tasks folder: /srv/example/tasks',
  'log ask-reviewer run-0917': 'Run run-0917\nResult:\n  Which branch should the review use?\n  1. main\n  2. the feature branch\n  3. both\n\n  Reply with the number of your pick (1, 2 or 3). I will act on just that choice.\n\nStderr:\n',
  'log branch-check': 'failed: exit 1 at 2026-10-29 18:00\nmore detail below',
  'log morning-digest': 'ok at 2026-10-30 07:30',
  'log old-report': 'paused by hand',
}

type Call = { args: readonly string[]; stdin?: string }

function result(stdout: string, exitCode = 0): ProcessRunResult {
  return { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
}

// The world beneath the pane: the CLI, answered from the fixtures and recorded in `calls`. The boundary check
// is the one process call that is not schedule.sh; it answers as a kit workspace unless `place.inside` is false,
// read on each call so a test can move the session out of the workspace between actions.
function beneath(on: On, calls: Call[], place = { inside: true }) {
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('process.run', (_, e) => {
    if (e.argv[1] === '-c') return { value: place.inside ? result('/srv/example/workspace') : result('', 1) }
    const args = e.argv.slice(2)
    calls.push({ args, stdin: e.init?.stdin })
    if (args[0] === 'list') return { value: result(JSON.stringify(LIST)) }
    if (args[0] === 'show') return { value: result(JSON.stringify(SHOW[args[1] ?? ''] ?? {})) }
    const key = args.join(' ')
    return { value: result(CLI[key] ?? 'ok') }
  })
}

// Runs the /scheduler-pane command, which opens the pane and so starts its first refresh; waits for that refresh to land.
async function openPane($: Engine, clock: ReturnType<typeof mock.clock>) {
  await $.command.run({
    command: 'scheduler-pane',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  })
  await clock.settle()
}

const PANE = {
  plugin: 'scheduler',
  component: 'Pane',
  requestId: 'scheduled-tasks',
  props: {
    title: 'Scheduled tasks',
    isFocused: false,
    bodyColumns: 80,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

test('the three sections draw from the fixtures, on every surface', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)

  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })

    expect((await ui.find({ type: 'Text', text: /Needs your answer/ }))?.text).toBe('Needs your answer')
    expect(await ui.find({ type: 'Text', text: /Which branch should the review use/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Needs attention/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /failed: exit 1 at 2026-10-29/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /All tasks/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /morning-digest/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /morning-digest\s+active\s+weekdays 07:30/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /old-report\s+paused/ })).toBeDefined()
    // The terminal row carries next and last on one line with its own spacing, so the desktop wording is checked elsewhere.
    if (surface !== 'terminal') {
      expect(await ui.find({ type: 'Text', text: /next Mon 2 Nov 07:30/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /not scheduled · last ok/ })).toBeDefined()
    }
    await ui.unmount()
  }
})

test('on the terminal the pane is a view: the waiting question whole, every task a row, and no button or answer field', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  // The question is the run's whole result, its last line included, not one list item.
  expect(await ui.find({ type: 'Text', text: /1\. main/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Reply with the number of your pick/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Answer it by asking Claude here/ })).toBeDefined()
  for (const name of ['morning-digest', 'ask-reviewer', 'branch-check', 'old-report']) {
    expect(await ui.find({ type: 'Text', text: new RegExp(name) })).toBeDefined()
  }
  // The terminal tree draws no button and no answer field: the pane shows, and acting is elsewhere.
  expect(await ui.find({ type: 'Button' })).toBeUndefined()
  expect(await ui.find({ type: 'Input' })).toBeUndefined()
  // The hint says how to act instead, so no line promises a key.
  expect(await ui.find({ type: 'Text', text: /Ask Claude here, or use \/scheduler:tasks, to run, pause, resume, answer or read a log/ })).toBeDefined()
  await ui.unmount()
})

test('each button calls the CLI with its argument vector', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  calls.length = 0

  await ui.press({ key: 'run:morning-digest' })
  expect(calls[0]?.args).toEqual(['run', 'morning-digest'])

  calls.length = 0
  await ui.press({ key: 'toggle:morning-digest' })
  expect(calls[0]?.args).toEqual(['pause', 'morning-digest'])

  calls.length = 0
  await ui.press({ key: 'toggle:old-report' })
  expect(calls[0]?.args).toEqual(['resume', 'old-report'])

  calls.length = 0
  await ui.press({ key: 'task-log:morning-digest' })
  expect(calls[0]?.args).toEqual(['log', 'morning-digest'])

  calls.length = 0
  await ui.press({ key: 'attention-log:branch-check' })
  expect(calls[0]?.args).toEqual(['log', 'branch-check'])

  calls.length = 0
  await ui.input({ key: 'reply:ask-reviewer', text: 'use main' })
  expect(calls[0]?.args).toEqual(['reply', 'ask-reviewer', '--run', 'run-0917', '--file', '-'])
  expect(calls[0]?.stdin).toBe('use main')

  await ui.unmount()
})

test('no delete action is drawn, and no button reaches the CLI as a delete', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(JSON.stringify(await ui.drawn())).not.toMatch(/delete/i)

  for (const key of ['run:morning-digest', 'toggle:morning-digest', 'task-log:morning-digest', 'attention-log:branch-check', 'log-close']) {
    await ui.press({ key })
  }
  expect(calls.some(call => call.args.includes('delete'))).toBe(false)

  await ui.unmount()
})

test('mobile draws no input fields, though desktop draws the reply field', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)

  const desktop = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await desktop.find({ type: 'Input' })).toBeDefined()
  await desktop.unmount()

  const mobile = await $.ui.mount({ ...PANE, surface: 'mobile' })
  expect(await mobile.find({ type: 'Input' })).toBeUndefined()
  await mobile.unmount()
})

test('outside a kit workspace the command and the pane both say so, and name the CLI as working anywhere', async ($, on) => {
  const calls: Call[] = []
  const place = { inside: false }
  beneath(on, calls, place)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })

  const asked = await $.command.run({
    command: 'scheduler-pane',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  })
  expect(JSON.stringify(asked)).toMatch(/works inside a kit workspace.*CLI works anywhere/)

  // Inside first, so the pane opens and draws its tasks; then the session moves out and an action refreshes it.
  place.inside = true
  await openPane($, clock)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /All tasks/ })).toBeDefined()

  place.inside = false
  await ui.press({ key: 'toggle:old-report' })
  expect(await ui.find({ type: 'Text', text: /works inside a kit workspace/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /The CLI works anywhere/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /All tasks/ })).toBeUndefined()
  await ui.unmount()
})

test('the footer names the backend, the tasks folder and the refresh time', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(
    await ui.find({ type: 'Text', text: /launchd · \/srv\/example\/tasks · refreshed \d{1,2}:\d{2}$/ }),
  ).toBeDefined()
  await ui.unmount()
})
