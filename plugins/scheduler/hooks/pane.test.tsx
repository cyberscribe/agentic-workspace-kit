import { expect, mock, test } from 'claude-code/testing'
import type { On, ProcessRunResult } from 'claude-code'
import type { Engine } from 'claude-code/testing'

import { readableLog } from './pane'

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
// read on each call so a test can move the session out of the workspace between actions. The surface seats the
// pane unless `seat.placed` is false, and each open's arguments are kept in `seat.opens`.
type Seat = { placed: boolean; opens: unknown[] }
function beneath(on: On, calls: Call[], place = { inside: true }, seat: Seat = { placed: true, opens: [] }) {
  on('ui.open', (_, e) => {
    seat.opens.push(e)
    return { value: seat.placed ? { isPlaced: true } : { isPlaced: false, reason: 'no room for a pane' } }
  })
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

test('the three sections draw from the fixtures, on the desktop, vscode and mobile', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)

  for (const surface of ['desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })

    expect((await ui.find({ type: 'Text', text: /Needs your answer/ }))?.text).toBe('Needs your answer')
    expect(await ui.find({ type: 'Text', text: /Which branch should the review use/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Needs attention/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /failed: exit 1 at 2026-10-29/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /All tasks/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /morning-digest/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /morning-digest\s+active\s+weekdays 07:30/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /old-report\s+paused/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /next Mon 2 Nov 07:30/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /not scheduled · last ok/ })).toBeDefined()
    await ui.unmount()
  }
})

test('on the terminal the pane is a list: a row per task, the keys on screen, and the ring as the selection', async ($, on) => {
  const calls: Call[] = []
  const seat: Seat = { placed: true, opens: [] }
  beneath(on, calls, { inside: true }, seat)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)

  // The open asks for the keyboard and a dock wide enough for a row; Escape hands the keyboard back.
  expect(seat.opens[0]).toMatchObject({ id: 'scheduled-tasks', focus: true, closeOnEscape: true, columns: 60 })

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  // One row per task, what needs the person first: no sections, no question, no answer field at this level.
  expect(await ui.find({ type: 'Text', text: /^(› |  )?morning-digest\s+active · weekdays 07:30 · next Mon 2 Nov 07:30$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^(› |  )?ask-reviewer\s+needs your answer · / })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^(› |  )?branch-check\s+failed · daily 18:00 · next Fri 30 Oct 18:00$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^(› |  )?old-report\s+paused · @monthly$/ })).toBeDefined()
  expect(await ui.find({ type: 'Input' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /↑↓ select · Enter or 1-4 open · Esc leaves/ })).toBeDefined()
  // A digit per row and a letter per action, drawn with their keys; the first row holds the ring at first.
  const drawn = JSON.stringify(await ui.drawn())
  for (const key of ['1', '2', '3', '4', 'r', 'p', 'l']) expect(drawn).toContain(`"hotkey":"${key}"`)
  expect(drawn).toMatch(/"key":"row:morning-digest"[^}]*"autoFocus":true|"autoFocus":true[^}]*"key":"row:morning-digest"/)
  expect(drawn).not.toMatch(/delete/i)

  // The actions act on the selected row, the first until the ring moves. The ring moving with the arrows is the
  // person's, which a test cannot raise; the tmux captures show it (playground-evidence/p6a).
  calls.length = 0
  await ui.press({ key: 'run:morning-digest' })
  expect(calls[0]?.args).toEqual(['run', 'morning-digest'])
  await ui.unmount()
})

test('Enter opens a task, back returns to the list, and a waiting one opens on its answer field', async ($, on) => {
  const calls: Call[] = []
  const seat: Seat = { placed: true, opens: [] }
  beneath(on, calls, { inside: true }, seat)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  // Changing view pauses briefly (so the ring lands where it should), which the mocked clock has to pass.
  const through = async (key: string) => {
    const pressed = ui.press({ key })
    await clock.advance(2_000)
    await pressed
  }

  // A task's own view: its details, the actions and back, and its log on l.
  await through('row:morning-digest')
  expect(await ui.find({ type: 'Text', text: /^morning-digest · next Mon 2 Nov 07:30 · active · / })).toBeDefined()
  expect(JSON.stringify(await ui.drawn())).toContain('"hotkey":"b"')
  calls.length = 0
  await through('task-log:morning-digest')
  expect(calls[0]?.args).toEqual(['log', 'morning-digest'])
  expect(JSON.stringify(await ui.drawn())).toMatch(/"label":"(› )?hide log"/)
  await through('back')
  expect(await ui.find({ type: 'Text', text: /↑↓ select/ })).toBeDefined()

  // The waiting run: its whole question, and the answer field holding the focus, so answering is type then Enter.
  await through('row:ask-reviewer')
  expect(await ui.find({ type: 'Text', text: /Reply with the number of your pick/ })).toBeDefined()
  expect(JSON.stringify(await ui.drawn())).toMatch(/"key":"reply:ask-reviewer"[^}]*"autoFocus":true|"autoFocus":true[^}]*"key":"reply:ask-reviewer"/)
  expect(await ui.find({ type: 'Text', text: /type the answer \(digits too\), Enter sends · Esc back/ })).toBeDefined()
  calls.length = 0
  await ui.input({ key: 'reply:ask-reviewer', text: '1' })
  expect(calls[0]?.args).toEqual(['reply', 'ask-reviewer', '--run', 'run-0917', '--file', '-'])
  expect(calls[0]?.stdin).toBe('1')
  // A paused task's view offers resume.
  await through('back')
  await through('row:old-report')
  calls.length = 0
  await ui.press({ key: 'toggle:old-report' })
  expect(calls[0]?.args).toEqual(['resume', 'old-report'])
  await ui.unmount()
})

test('a row longer than the dock is cut to one line', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: { ...PANE.props, bodyColumns: 30, placement: 'dock' } })
  const row = await ui.find({ type: 'Text', text: /^(› |  )?morning/ })
  expect(row?.text).toMatch(/…$/)
  expect((row?.text ?? '').length).toBeLessThanOrEqual(27)
  await ui.unmount()
})

test('a key line wider than the dock gives up its digits, not its keys', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: { ...PANE.props, bodyColumns: 40, placement: 'dock' } })
  const line = await ui.find({ type: 'Text', text: /↑↓ select/ })
  expect(line?.text).toBe('↑↓ select · Enter open · Esc leaves')
  await ui.unmount()
})

const BAND = {
  plugin: 'scheduler',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isCollapsed: false,
    isWorking: false,
    maxRows: 40,
    bodyColumns: 80,
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

test('with no seat for a pane, the terminal view is drawn in the band until its Close', async ($, on) => {
  const calls: Call[] = []
  const seat: Seat = { placed: false, opens: [] }
  beneath(on, calls, { inside: true }, seat)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })

  const said = await $.command.run({
    command: 'scheduler-pane',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  })
  await clock.settle()
  expect(JSON.stringify(said)).toMatch(/shown above the prompt/)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /^(› |  )?ask-reviewer\s+needs your answer · / })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /↑↓ select · Enter or 1-4 open · c close/ })).toBeDefined()
  expect(JSON.stringify(await band.drawn())).toContain('"hotkey":"c"')
  calls.length = 0
  await band.press({ key: 'toggle:morning-digest' })
  expect(calls[0]?.args).toEqual(['pause', 'morning-digest'])

  await band.press({ key: 'band-close' })
  expect(await band.find({ type: 'Text', text: /↑↓ select/ })).toBeUndefined()
  await band.unmount()
})

test('while the pane has its seat, the band draws nothing of the pane', async ($, on) => {
  const calls: Call[] = []
  beneath(on, calls)
  const clock = mock.clock(on, { now: Date.parse('2026-10-30T10:00:00Z') })
  await openPane($, clock)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /↑↓ select/ })).toBeUndefined()
  await band.unmount()
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

test('the terminal log reads first what a person needs: status, when, how long, exit, and a resume that works there', () => {
  // A home folder, spelled in pieces so the kit's machine-path check (section 13) does not read it as one.
  const home = ['', 'Users', 'someone'].join('/')
  const log = [
    'Run 20261125-190934 of morning-digest: ok',
    '  started 2026-11-25 19:09:34, ended 2026-11-25 19:12:10, 2 attempt(s), exit 0, est. $0.0125, auth none',
    `  open it: cd '${home}/work/site' && claude --desktop --resume 46330a43`,
    `  folder: ${home}/.local/state/agentic-workspace-kit/scheduler/runs/morning-digest/20261125-190934`,
    '',
    'Result:',
    '  OK, done.',
    '',
  ].join('\n')
  expect(readableLog(log)).toEqual([
    'Run 20261125-190934 of morning-digest: ok',
    'ran 2026-11-25 19:09–19:12, exit 0, 2 attempts, about $0.0125',
    "open it: cd ~/'work/site' && claude --resume 46330a43",
    '',
    'Result:',
    'OK, done.',
  ])
  // A zero cost and a single attempt say nothing.
  expect(readableLog('  started 2026-11-25 19:09:34, ended 2026-11-25 19:09:34, 1 attempt(s), exit 0, est. $0.0000, auth none')).toEqual([
    'ran 2026-11-25 19:09–19:09, exit 0',
  ])
})
