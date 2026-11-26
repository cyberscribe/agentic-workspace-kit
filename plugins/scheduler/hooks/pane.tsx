import { atom, read, update } from 'claude-code'
import type { Elements, EngineInterface, Register, Timer } from 'claude-code'

import type { Attention, Board, Task, Waiting } from '../types'

const PANE = 'scheduled-tasks'
const TITLE = 'Scheduled tasks'
const REFRESH_MS = 60_000
// A reply or a run-now call can take minutes, so it gets the longest a process call may run: ten minutes.
const LONG_CALL_MS = 600_000
// The last-run statuses that put a task under Needs attention.
const FAILED = ['failed', 'timeout', 'denied', 'refused']

const EMPTY: Board = {
  isInWorkspace: true,
  refreshedAt: '',
  backend: '',
  tasksFolder: '',
  tasks: [],
  waiting: [],
  attention: [],
  notice: '',
  log: '',
  logTask: '',
  selected: '',
  opened: '',
  top: 0,
  busy: '',
  logTop: 0,
}

// The shape tag names this layout. A stored value from an earlier layout is declined, not drawn.
const board = atom({ plugin: 'scheduler', key: 'board' } as const, EMPTY, { shape: 'board-1' })

// The CLI's JSON, as schedule.sh prints it. Only the fields the pane draws are named.
type ListRow = {
  name: string
  status: string
  schedule: string
  next: string
  schedule_words: string
  next_words: string
  last_status: string
  waiting: string
}
type Shown = {
  backend: string
  fields: { paused_reason?: string }
  last_run: { end: string; session_id: string } | null
}

// Every read and write of the pane goes through here, so each one is a CLI call with its output kept.
// The CLI's own exit code and text come back as they are; a call that cannot start comes back as an error line.
async function cli(
  $: EngineInterface,
  args: readonly string[],
  options: { timeoutMs?: number; stdin?: string } = {},
) {
  try {
    const { exitCode, stdout, stderr } = await $.process.run(
      ['bash', `${$.plugin.root}/scripts/schedule.sh`, ...args],
      { timeoutMs: options.timeoutMs ?? 30_000, stdin: options.stdin },
    )
    return { ok: exitCode === 0, out: (exitCode === 0 ? stdout : stderr || stdout).trimEnd() }
  } catch (err) {
    return { ok: false, out: String(err) }
  }
}

// The pane acts only inside a kit workspace, by the same boundary the hooks use. The check runs in this
// process's folder, which is the session's.
async function inWorkspace($: EngineInterface) {
  const { exitCode, stdout } = await $.process.run(
    ['bash', '-c', 'source "$1" && aw_workspace_root ""', 'pane', `${$.plugin.root}/hooks/lib/boundary.sh`],
    { timeoutMs: 5_000 },
  )
  return exitCode === 0 && stdout.trim() !== ''
}

async function patch($: EngineInterface, fields: Partial<Board>) {
  await update($, board, value => ({ ...value, ...fields }))
}

// The question a waiting run ends on: the result text under the log's "Result:" heading, trimmed of its indent.
function question(log: string) {
  const at = log.indexOf('\nResult:\n')
  if (at < 0) return '(no question text)'
  // split always yields at least one piece; the fallback only satisfies the index type under noUncheckedIndexedAccess.
  const body = log.slice(at + '\nResult:\n'.length).split('\nStderr')[0] ?? ''
  return body.replace(/^ {2}/gm, '').trim()
}

function firstLine(text: string) {
  return text.split('\n')[0] ?? ''
}

// How long a run has waited, from its end time in the CLI's local "YYYY-MM-DD HH:MM:SS" form.
function waited(since: string, now: number) {
  const mins = Math.round((now - new Date(since.replace(' ', 'T')).getTime()) / 60_000)
  if (Number.isNaN(mins)) return `since ${since}`
  return mins < 60 ? `${Math.max(0, mins)} min` : `${Math.round(mins / 60)} h`
}

// Reads the board from the CLI and keeps the answers. Calls to `show` are made only where a task needs them.
// The number of the newest read of the scheduler, or of the newest action, which outdates any read before it.
let generation = 0

async function refresh($: EngineInterface) {
  // Each read takes a number; a newer read, or a key's action, makes an older one's answers stale, and they are
  // dropped rather than written over what is newer (a read begun before a resume ends after it, say).
  const mine = ++generation
  const put = async (fields: Partial<Board>) => {
    if (mine === generation) await patch($, fields)
  }
  try {
    if (!(await inWorkspace($))) {
      await put({ isInWorkspace: false })
      return
    }
    // On a first open the last list the CLI answered is drawn at once, marked as updating, while the full read
    // runs; a list of many tasks takes a second or two to read.
    const before = await read($, board)
    if (before.refreshedAt === '') {
      const cached = await cli($, ['list', '--json', '--cached'])
      if (cached.ok) {
        try {
          const old: ListRow[] = JSON.parse(cached.out)
          await put({
            tasks: old.map(row => ({ name: row.name, status: row.status, schedule: row.schedule_words, next: row.next_words, lastStatus: row.last_status })),
            waiting: old.filter(row => row.waiting !== '').map(row => ({ task: row.name, run: row.waiting, since: '', sessionId: '', question: '' })),
            attention: old.filter(row => FAILED.includes(row.last_status)).map(row => ({ task: row.name, reason: row.last_status })),
            refreshedAt: '…',
          })
          const name = before.selected || old[0]?.name
          if (name && ringOn === '') void focusOn($, PANE, `row:${name}`)
        } catch {
          // A cache that does not parse is skipped; the full read follows.
        }
      }
    }
    const listed = await cli($, ['list', '--json'])
    if (!listed.ok) {
      await put({ notice: listed.out })
      return
    }
    const rows: ListRow[] = JSON.parse(listed.out)
    // The rows go on screen as soon as the list lands; the questions and reasons, which need a call per task,
    // follow. On a first open with many tasks that is a second sooner.
    const first = await read($, board)
    if (first.refreshedAt === '' || first.refreshedAt === '…') {
      await put({
        tasks: rows.map(row => ({
          name: row.name,
          status: row.status,
          schedule: row.schedule_words,
          next: row.next_words,
          lastStatus: row.last_status,
        })),
        // What the list itself says, so the rows read right from the first draw; the question and the reason
        // follow from the per-task calls.
        waiting: rows.filter(row => row.waiting !== '').map(row => ({ task: row.name, run: row.waiting, since: '', sessionId: '', question: '' })),
        attention: rows.filter(row => FAILED.includes(row.last_status)).map(row => ({ task: row.name, reason: row.last_status })),
        refreshedAt: '…',
      })
      const name = first.selected || rows[0]?.name
      if (name && ringOn === '') void focusOn($, PANE, `row:${name}`)
    }
    const folder = await cli($, ['home'])
    const now = await $.clock.now()
    const tasks: Task[] = []
    const waiting: Waiting[] = []
    const attention: Attention[] = []
    let backend = ''

    for (const [i, row] of rows.entries()) {
      const needsShow = i === 0 || row.waiting !== '' || row.status === 'paused'
      const shown: Shown | undefined = needsShow
        ? JSON.parse((await cli($, ['show', row.name, '--json'])).out)
        : undefined
      if (shown && !backend) backend = shown.backend

      tasks.push({
        name: row.name,
        status: row.status,
        schedule: row.schedule_words,
        next: row.next_words,
        lastStatus: row.last_status,
      })

      if (row.waiting !== '' && shown?.last_run) {
        const log = await cli($, ['log', row.name, row.waiting])
        waiting.push({
          task: row.name,
          run: row.waiting,
          since: shown.last_run.end,
          sessionId: shown.last_run.session_id,
          question: question(log.out),
        })
      }

      const selfPaused =
        row.status === 'paused' && (shown?.fields.paused_reason ?? '').startsWith('paused itself')
      if (selfPaused || FAILED.includes(row.last_status)) {
        const reason = selfPaused
          ? (shown?.fields.paused_reason ?? '')
          : firstLine((await cli($, ['log', row.name])).out)
        attention.push({ task: row.name, reason })
      }
    }

    await put({
      isInWorkspace: true,
      refreshedAt: new Date(now).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }),
      backend,
      // The home folder shows as ~, so the footer stays short on a narrow pane.
      tasksFolder: firstLine(folder.out).replace('Tasks folder: ', '').replace(/^\/(Users|home)\/[^/]+/, '~'),
      tasks,
      waiting,
      attention,
    })
  } catch (err) {
    await put({ notice: `refresh failed: ${String(err)}` })
  }
}

// One action: its CLI call, the output shown as the notice, then a refresh so the lists match the CLI.
async function act(
  $: EngineInterface,
  args: readonly string[],
  options: { timeoutMs?: number; stdin?: string } = {},
) {
  // A call and the reread after it take a second or two with many tasks, so the key line says what is under
  // way the moment the key is pressed, rather than the screen sitting still.
  await patch($, { busy: args[0] === 'reply' ? `sending: ${options.stdin ?? ''}`.trim() : `${args[0]} ${args[1] ?? ''}`.trim() })
  try {
    const res = await cli($, args, options)
    // Once the CLI says it is done, the pane shows the new state straight away, so the row, the title and the
    // keys agree with the result line at once; the reread that follows confirms it.
    const after = await read($, board)
    const [verb, name] = args
    const settled =
      !res.ok || !name
        ? {}
        : verb === 'pause' || verb === 'resume'
          ? {
              tasks: after.tasks.map(t =>
                t.name === name
                  ? { ...t, status: verb === 'pause' ? 'paused' : 'active', next: verb === 'pause' ? '' : (firstFire(res.out) ?? t.next) }
                  : t,
              ),
            }
          : verb === 'reply'
            ? {
                waiting: after.waiting.filter(w => w.task !== name),
                tasks: after.tasks.map(t => (t.name === name ? { ...t, lastStatus: 'answered' } : t)),
              }
            : verb === 'run'
              ? { tasks: after.tasks.map(t => (t.name === name ? { ...t, lastStatus: 'running' } : t)) }
              : {}
    generation++
    await patch($, { notice: `/scheduler:tasks ${args.join(' ')}\n${res.out}`, busy: '', ...settled })
    await refresh($)
  } finally {
    await patch($, { busy: '' })
  }
}

async function viewLog($: EngineInterface, task: string) {
  const res = await cli($, ['log', task])
  await patch($, { log: res.out, logTask: task })
}

function lastWords(t: Task) {
  return t.lastStatus === 'waiting' ? 'awaiting your answer' : t.lastStatus || 'none yet'
}

// A run's log as the terminal shows it: what a person reads first. The CLI's own log is kept whole for the
// desktop pane and the CLI; here the timing line becomes when and how long, a zero cost and the auth source are
// left out, the open-it command resumes in the terminal (the CLI's says --desktop, for the app), home paths
// read as ~, and the run folder, an internal path, is dropped.
export function readableLog(log: string) {
  // A quoted path keeps working: a quoted home folder's 'site' becomes ~/'site', since a shell expands ~ only
  // outside quotes.
  const home = (text: string) =>
    text.replace(/'\/(Users|home)\/[^/\s']+\//g, "~/'").replace(/\/(Users|home)\/[^/\s']+/g, '~')
  const lines: string[] = []
  for (const raw of log.split('\n')) {
    const line = raw.replace(/^ {2}/, '')
    const timing = line.match(
      /^started (\S+) (\d\d:\d\d):\d\d, ended \S+ (\d\d:\d\d):\d\d, (\d+) attempt\(s\), exit (\d+), est\. \$([\d.]+)/,
    )
    if (timing) {
      const [, day, from, to, attempts, exit, usd] = timing
      const extras = [attempts !== '1' ? `${attempts} attempts` : '', Number(usd) > 0 ? `about $${usd}` : ''].filter(
        x => x !== '',
      )
      lines.push(`ran ${day} ${from}–${to}, exit ${exit}${extras.length > 0 ? `, ${extras.join(', ')}` : ''}`)
      continue
    }
    if (line.startsWith('folder: ')) continue
    lines.push(typeable(home(line.replace('claude --desktop --resume', 'claude --resume'))))
  }
  while (lines.length > 0 && lines[lines.length - 1] === '') lines.pop()
  return lines
}

// The last action's result as one line: the CLI's own last line ("Paused task-06; …", "Started task-07 in the
// background. …"), which is what happened, rather than the command that was run.
function lastResult(notice: string) {
  // The first line is the command that ran; the CLI's own first line after it says what happened. Its first
  // sentence is kept, so the result reads whole on one row ("Resumed task-06.", not the fire times after it).
  const lines = notice.split('\n').map(l => l.trim()).filter(l => l !== '')
  const said = lines.length > 1 ? (lines[1] ?? '') : (lines[0] ?? '')
  // A scheduler with no unit to install (the none backend) has nothing to say about one.
  const plain = said.replace(/;? ?(its )?none unit (is removed|installed)/, '').replace(/\s+\./, '.')
  const sentence = plain.match(/^.*?[.!?](?=\s|$)/)?.[0] ?? plain
  return typeable(notice.startsWith('/scheduler:tasks reply') ? `Answer sent. ${sentence}` : sentence)
}

// The CLI's own pointers name schedule.sh, which is not on a person's PATH; in the pane they name the command a
// person can type in Claude Code instead, which runs the same thing.
function typeable(text: string) {
  // The CLI's own name opens its error lines ("schedule.sh: no run yet"); the pane leaves it off.
  return text.replace(/^schedule\.sh: /gm, '').replace(/\bschedule\.sh ([a-z])/g, '/scheduler:tasks $1')
}

// wrapLines: text cut into lines of at most `width` characters at spaces, a word longer than that cut where it
// must, so a line is never wider than the pane and the count of lines is the count of rows it takes.
export function wrapLines(lines: readonly string[], width: number) {
  const out: string[] = []
  const room = Math.max(8, width)
  for (const line of lines) {
    if (line.length <= room) {
      out.push(line)
      continue
    }
    let rest = line
    while (rest.length > room) {
      let cut = rest.lastIndexOf(' ', room)
      if (cut <= 0) cut = room
      out.push(rest.slice(0, cut))
      rest = rest.slice(cut).replace(/^ /, '')
    }
    if (rest !== '') out.push(rest)
  }
  return out
}

// What a task's row says after its name: what needs the person first, then when it next runs.
function rowWords(b: Board, t: Task, narrow = false) {
  // A state word first, so whatever a narrow pane cuts is the schedule, never the state.
  const pending: Record<string, string> = { pause: 'pausing…', resume: 'resuming…', run: 'starting…' }
  const [verb, name] = b.busy.split(' ')
  const state =
    name === t.name && verb && pending[verb]
      ? pending[verb]
      : t.lastStatus === 'running'
        ? 'running'
        : b.waiting.some(w => w.task === t.name)
          ? 'needs your answer'
          : b.attention.some(a => a.task === t.name)
            ? 'failed'
            : t.status === 'paused'
              ? 'paused'
              : 'active'
  // "Thu 26 Nov 09:15" reads as "Thu 09:15" when narrow: the day and time, which is what a glance needs.
  const next = t.next ? `next ${narrow ? t.next.replace(/^(\S+) \d+ \S+ /, '$1 ') : t.next}` : 'not scheduled'
  if (state === 'paused' || state === 'pausing…') return `${state} · ${t.schedule}`
  return narrow ? `${state} · ${next}` : `${state} · ${t.schedule} · ${next}`
}

// Moves the focus ring onto an element of a site once it is drawn. A move asked for while the site is still
// settling (a view just changed, the pane just took the keyboard) can be refused, so it is asked again a few
// times, briefly; a ring the person moves meanwhile wins, since each try only lands where nothing else has.
async function focusOn($: EngineInterface, site: string, key: string) {
  try {
    for (let i = 0; i < 6; i++) {
      const moved = await $.ui.focus({ requestId: site, key }).catch(() => ({ deny: 'failed' }))
      if (!moved || !('deny' in moved) || !moved.deny) return
      await $.clock.sleep(150)
    }
  } catch {
    // The pane closed or the plugin reloaded meanwhile: there is nothing left to focus.
  }
}

// firstFire: the first of the "Next fire times" a resume prints ("  2026-11-26 10:28 Thu"), in the list's words
// ("Thu 26 Nov 10:28"), so a resumed row shows its next run at once rather than "not scheduled".
function firstFire(out: string) {
  const m = out.match(/^\s*(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2}) (\w{3})\s*$/m)
  if (!m) return undefined
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
  return `${m[5]} ${Number(m[3])} ${months[Number(m[2]) - 1]} ${m[4]}`
}

// A short pause around a change of view. Pressing the button that holds the ring and then removing it, as a change
// of view does, clears the ring after any move asked for in the same moment (seen on Claude Code 2.1.332), so the
// press is let finish before the view changes, and the view is let draw before the ring is moved.
async function settle($: EngineInterface) {
  await $.clock.sleep(60).catch(() => undefined)
}

// The terminal's layout, in the pane or in the band above the prompt, at two levels, as a terminal list reads.
//
// Everything is laid out to fit the rows the surface gives the body (`rows`), because a pane taller than its room
// scrolls, and in a scrolling pane the arrows scroll the text instead of moving the focus. So the list shows a
// window of rows that follows the selection: when there are more tasks than fit, a "↑ N more" or "↓ N more" row
// marks each end, and the focus landing on one moves the window by a row and the focus onto the next task (the
// `ui.focus` hook), so Up and Down reach every task. The focus ring is the selection; Enter or a row's digit (for
// the rows shown) opens the task. The actions are buttons drawn with their keys, so the keys are on screen
// rather than remembered.
//
// A task's own view lists its actions one under another, since Up and Down move between buttons and Left and
// Right do not (Left is Claude Code's own key, which opens its agents view). A waiting run's question and a log
// are cut to the rows left. A waiting run's view gives its answer field the focus, so answering is open, type,
// Enter; there the letters type, and Ctrl+D is the field's, until Escape steps back. Escape steps back from a
// task to the list, then closes the pane; in the band, where Escape belongs to the prompt, b and c do the same.
function terminalView(
  $: EngineInterface,
  el: Elements['terminal'],
  b: Board,
  now: number,
  cols: number,
  rows: number,
  site: string,
  close: (() => void) | undefined,
) {
  const { Box, Text, Button, Input } = el
  // Changing view inside a pane that holds the keyboard drops the ring with the element it was on, and autoFocus
  // applies only as the pane takes the keyboard, so each change of view puts the ring somewhere itself: a task
  // opens on its answer field when a run waits, else on its log (it changes nothing), and back lands on the row.
  const openTask = async (t: Task) => {
    await settle($)
    await patch($, { opened: t.name, selected: t.name, log: '', notice: '' })
    const waits = b.waiting.some(w => w.task === t.name)
    ringOn = waits ? `reply:${t.name}` : `task-log:${t.name}`
    await settle($)
    void focusOn($, site, ringOn)
  }
  const backToList = async (name: string) => {
    await settle($)
    await patch($, { opened: '', log: '', notice: '' })
    await settle($)
    void focusOn($, site, `row:${name}`)
  }
  // A row is cut to the body's width rather than wrapped, so each task stays one line.
  const fit = (text: string, room: number) => (text.length > room ? `${text.slice(0, Math.max(1, room - 1))}…` : text)
  const opened = b.tasks.find(t => t.name === b.opened)
  const footer = (
    <Text dimColor>
      {fit(
        b.refreshedAt === '…'
          ? 'updating the list…'
          : `${b.backend && b.backend !== 'none' ? `${b.backend} · ` : ''}refreshed ${b.refreshedAt}`,
        cols,
      )}
    </Text>
  )

  if (b.refreshedAt === '') return <Text dimColor>Loading the scheduled tasks…</Text>

  if (opened) {
    const waiting = b.waiting.find(w => w.task === opened.name)
    const attention = b.attention.find(a => a.task === opened.name)
    const logOpen = b.log !== '' && b.logTask === opened.name
    // The log comes first: the ring starts on it (it changes nothing), so the first action listed is the one the
    // ring is on, and the order on screen is the order Up and Down take.
    const actions = [
      {
        key: `task-log:${opened.name}`,
        hotkey: 'l',
        label: logOpen ? 'hide log' : 'log',
        press: async () => {
          // The press is let finish before the view changes and the view let draw before the ring moves, as for
          // every change of view (settle): the button pressed is not in the log view of a short pane.
          await settle($)
          if (logOpen) {
            await patch($, { log: '', logTop: 0 })
            ringOn = `task-log:${opened.name}`
            await settle($)
            return void focusOn($, site, ringOn)
          }
          await viewLog($, opened.name)
          await patch($, { logTop: 0 })
          ringOn = 'log-at'
          await settle($)
          void focusOn($, site, 'log-at')
        },
      },
      { key: `run:${opened.name}`, hotkey: 'r', label: 'run now', press: () => act($, ['run', opened.name], { timeoutMs: LONG_CALL_MS }) },
      {
        key: `toggle:${opened.name}`,
        hotkey: 'p',
        label: opened.status === 'paused' ? 'resume' : 'pause',
        press: () => act($, [opened.status === 'paused' ? 'resume' : 'pause', opened.name]),
      },
      ...(waiting
        ? [{ key: `session:${waiting.task}`, hotkey: 'o', label: 'open its session', press: () => patch($, { notice: `claude --resume ${waiting.sessionId}` }) }]
        : []),
      { key: 'back', hotkey: 'b', label: 'back', press: () => backToList(opened.name) },
    ]
    const buttons = (stack: boolean) => {
      const each = actions.map(a => (
        <Button key={a.key} plain hotkey={a.hotkey} autoFocus={!waiting && !logOpen && a.hotkey === 'l' ? true : undefined} onPress={a.press}>
          {`${mark(a.key)}${a.label}`}
        </Button>
      ))
      return stack ? <Box flexDirection="column">{each}</Box> : <Box flexDirection="row" gap={3}>{each}</Box>
    }
    const back = close ? 'b back' : 'Esc back'
    const title = (keys: string) => (
      // The title keeps the key of the task's row in the list, so a ring that was on the row stays on it here
      // rather than being dropped with it; pressing it goes back to the list.
      <Button key={`row:${opened.name}`} plain onPress={() => backToList(opened.name)}>
        <Text bold>
          {/* Keys folded into the title are never the part cut: the task's own words give way first. */}
          {fit(
            waiting
              ? `${opened.name} · needs your answer · waiting ${waited(waiting.since, now)}`
              : `${opened.name} · ${opened.next ? `next ${opened.next}` : 'not scheduled'} · ${opened.status} · ${opened.schedule} · last ${lastWords(opened)}`,
            Math.max(10, cols - 2 - (b.busy && keys ? ` · working: ${b.busy}…` : keys).length),
          ) + (b.busy && keys ? ` · working: ${b.busy}…` : keys)}
        </Text>
      </Button>
    )
    const keyLine = (text: string) => <Text dimColor>{fit(b.busy ? `working: ${b.busy}…` : text, cols)}</Text>
    const reason = attention ? 1 : 0
    const result = b.notice !== '' ? 1 : 0

    // A run awaiting an answer: the question comes first and is never cut, since nobody should answer a
    // question they cannot read whole. It is wrapped to the width; to make room, the actions line goes, then the
    // key line folds into the title. If even then it cannot all be shown, the answer field is not offered: the
    // view says where to answer instead.
    if (waiting && !logOpen && waiting.question === '') {
      // Opened in the moment between the list and the question being read: no answer field until it is shown.
      return (
        <Box flexDirection="column">
          {title(` · ${back}`)}
          <Text dimColor>Reading the question…</Text>
        </Box>
      )
    }
    if (waiting && !logOpen) {
      const question = wrapLines(waiting.question.split('\n').filter(l => l.trim() !== ''), cols)
      const keys = 'type the answer (digits too), Enter sends · ' + back
      const layouts = [
        { keyRow: true, actions: true },
        { keyRow: true, actions: false },
        { keyRow: false, actions: false },
      ]
      // The result row is the first thing to give way: the question has priority over it.
      const fits = layouts
        .flatMap(l => [{ ...l, result: result > 0 }, { ...l, result: false }])
        .find(l => 1 + (l.keyRow ? 1 : 0) + reason + question.length + 1 + (l.actions ? 1 : 0) + (l.result ? 1 : 0) <= rows)
      if (!fits) {
        return (
          <Box flexDirection="column">
            {title(` · ${back}`)}
            {question.slice(0, Math.max(1, rows - 3)).map((line, n) => (
              <Text key={`q:${n}`}>{line}</Text>
            ))}
            <Text bold>{fit(`The question is longer than this pane: widen the terminal, or answer with /scheduler:tasks.`, cols)}</Text>
          </Box>
        )
      }
      return (
        <Box flexDirection="column">
          {title(fits.keyRow ? '' : ` · type, Enter sends · ${back}`)}
          {fits.keyRow && keyLine(keys)}
          {attention && <Text>{fit(attention.reason, cols)}</Text>}
          {question.map((line, n) => (
            <Text key={`q:${n}`}>{line === '' ? ' ' : line}</Text>
          ))}
          <Input
            key={`reply:${waiting.task}`}
            label="Answer"
            autoFocus
            placeholder="type, then Enter"
            submitLabel="send"
            onSubmit={text => {
              if (text.trim() === '') return
              void act($, ['reply', waiting.task, '--run', waiting.run, '--file', '-'], { timeoutMs: LONG_CALL_MS, stdin: text })
            }}
          />
          {fits.actions && buttons(false)}
          {fits.result && <Text>{fit(lastResult(b.notice), cols)}</Text>}
        </Box>
      )
    }

    // An open log reads like a pager. The ring rests on one row that says where the window is ("lines 3–10 of
    // 20"); the log's lines are text around it, between "↑ N earlier" and "↓ N more" rows that are always drawn
    // while the log is longer than the window. Up and Down land on those rows, and the focus hook turns each landing
    // into a scroll of one line, with the ring kept on the position row, so every press moves the text. Enter on
    // either row moves a page. In a short pane the keys fold into the title and the actions line goes.
    if (logOpen) {
      const lines = wrapLines(readableLog(b.log), cols)
      const tight = rows < 9
      const longer = (size: number) => lines.length > size
      // In a short pane the log has the room to itself: the failure and the last result are the log's own first
      // lines, so they go, and the "↑"/"↓" rows share the position row's line.
      let size = Math.max(1, tight ? rows - 2 : rows - 3 - reason - result - 1)
      if (longer(size) && !tight) size = Math.max(1, size - 2)
      const logTop = Math.min(Math.max(0, b.logTop), Math.max(0, lines.length - size))
      logWindowSize = size
      logLength = lines.length
      const shown = lines.slice(logTop, logTop + size)
      const scrolls = longer(size)
      return (
        <Box flexDirection="column">
          {title('')}
          {!tight && keyLine(`↑↓ scroll the log · l hide it · ${back}`)}
          {!tight && attention && <Text>{fit(attention.reason, cols)}</Text>}
          {!tight && buttons(false)}
          {tight && (
            <Box flexDirection="row" gap={2}>
              {scrolls && (
                <Button key="log-up" plain onPress={() => patch($, { logTop: Math.max(0, logTop - size) })}>
                  <Text dimColor>{logTop > 0 ? `↑${logTop}` : '↑top'}</Text>
                </Button>
              )}
              <Button key="log-at" plain onPress={() => undefined}>
                <Text dimColor>
                  {fit(`${scrolls ? `lines ${logTop + 1}–${logTop + shown.length} of ${lines.length}` : `all ${lines.length} line${lines.length === 1 ? '' : 's'}`} · ↑↓ scroll · ${back}`, Math.max(10, cols - 16))}
                </Text>
              </Button>
              {scrolls && (
                <Button key="log-down" plain onPress={() => patch($, { logTop: Math.min(lines.length - size, logTop + size) })}>
                  <Text dimColor>{logTop + size < lines.length ? `↓${lines.length - logTop - size}` : '↓end'}</Text>
                </Button>
              )}
            </Box>
          )}
          {!tight && scrolls && (
            <Button key="log-up" plain onPress={() => patch($, { logTop: Math.max(0, logTop - size) })}>
              <Text dimColor>{logTop > 0 ? `↑ ${logTop} earlier` : '↑ top of the log'}</Text>
            </Button>
          )}
          {!tight && <Button key="log-at" plain onPress={() => undefined}>
            <Text dimColor>
              {fit(scrolls ? `lines ${logTop + 1}–${logTop + shown.length} of ${lines.length}` : `all ${lines.length} line${lines.length === 1 ? '' : 's'}`, cols - 2)}
            </Text>
          </Button>}
          {shown.map((line, n) => (
            <Text key={`logline:${logTop + n}`} bold={logTop + n === 0}>
              {line === '' ? ' ' : line}
            </Text>
          ))}
          {!tight && scrolls && (
            <Button key="log-down" plain onPress={() => patch($, { logTop: Math.min(lines.length - size, logTop + size) })}>
              <Text dimColor>{logTop + size < lines.length ? `↓ ${lines.length - logTop - size} more` : '↓ end of the log'}</Text>
            </Button>
          )}
          {!tight && result > 0 && <Text>{fit(lastResult(b.notice), cols)}</Text>}
        </Box>
      )
    }

    // The task itself: its actions one under another when they fit, else on one line.
    const stacked = rows - 2 - reason - result >= actions.length
    const spare = rows - 2 - reason - result - (stacked ? actions.length : 1)
    return (
      <Box flexDirection="column">
        {title('')}
        {keyLine(`↑↓ choose · Enter do it · ${back}`)}
        {attention && <Text>{fit(attention.reason, cols)}</Text>}
        {buttons(stacked)}
        {result > 0 && <Text>{fit(lastResult(b.notice), cols)}</Text>}
        {spare > 0 && footer}
      </Box>
    )
  }

  // The list. Its fixed rows: the actions line and the key line, then the footer when there is room. The rest is
  // the window of tasks, less a row for each "more" marker it needs.
  const total = b.tasks.length
  const selectedAt = Math.max(0, b.tasks.findIndex(t => t.name === b.selected))
  // The rows a list keeps: the actions line and the key line; a heading saying the order when there is room;
  // a line for the last action's result, while there is one. The rest is the window of tasks, less a row for each
  // "more" marker it needs.
  const heading = total > 1 && rows >= 7
  // A short pane (fullscreen at 24 lines gives six rows) draws the key line on the actions line, a task row more.
  const folded = rows < 7
  const result = b.notice !== '' ? 1 : 0
  let shown = Math.max(1, rows - (folded ? 1 : 2) - result - (heading ? 1 : 0))
  if (total > shown) shown = Math.max(1, shown - 2)
  // The window starts where the person left it, moved just enough to keep the selection in view.
  let top = Math.min(Math.max(0, b.top), Math.max(0, total - shown))
  if (selectedAt < top) top = selectedAt
  if (selectedAt >= top + shown) top = selectedAt - shown + 1
  windowSize = shown
  const window = b.tasks.slice(top, top + shown)
  const current = b.tasks[selectedAt]
  const width = Math.max(...window.map(t => t.name.length), 0)
  // A narrow pane (the dock, say) gives the status its room first: short words, and names capped at what is left.
  const narrow = cols < 70
  const nameRoom = narrow ? Math.max(10, Math.min(width, cols - 22)) : width
  const above = top
  const below = Math.max(0, total - top - shown)
  const keys = b.busy
    ? `working: ${b.busy}…`
    : total === 0
      ? `Make one with /scheduler:tasks · ${close ? 'c close' : 'Esc leaves'}`
      : folded
        ? `${total > shown ? `${top + 1}–${top + window.length}/${total} · ` : ''}↑↓ Enter open · ${close ? 'c close' : 'Esc leaves'}`
        : `${total > shown ? `${top + 1}–${top + window.length} of ${total} · ` : ''}↑↓ select · Enter${window.length > 1 ? ` or 1-${Math.min(9, window.length)}` : ''} open · ${close ? 'c close' : 'Esc leaves'}`
  const spare = rows - (folded ? 1 : 2) - result - (heading ? 1 : 0) - window.length - (above > 0 ? 1 : 0) - (below > 0 ? 1 : 0)

  return (
    <Box flexDirection="column">
      {total === 0 && <Text dimColor>No scheduled tasks yet.</Text>}
      {heading && <Text dimColor>{fit('Keys go to this pane. Waiting tasks first, then by name.', cols)}</Text>}
      {above > 0 && (
        <Button key="more-up" plain onPress={() => patch($, { top: Math.max(0, top - shown) })}>
          <Text dimColor>↑ {above} more</Text>
        </Button>
      )}
      {window.map((t, i) => (
        <Button
          key={`row:${t.name}`}
          plain
          hotkey={i < 9 ? String(i + 1) : undefined}
          autoFocus={t === current ? true : undefined}
          onPress={() => openTask(t)}
        >
          {/* Every row keeps the mark's column and, past the ninth, the digit's, so the columns line up. */}
          <Text bold={t === current}>
            {fit(`${i < 9 ? '' : '   '}${t === current ? '› ' : '  '}${fit(t.name, nameRoom).padEnd(nameRoom)}  ${rowWords(b, t, narrow)}`, cols - 3)}
          </Text>
        </Button>
      ))}
      {below > 0 && (
        <Button key="more-down" plain onPress={() => patch($, { top: top + shown })}>
          <Text dimColor>↓ {below} more</Text>
        </Button>
      )}
      {current && (
        <Box flexDirection="row" gap={3}>
          <Button key={`run:${current.name}`} plain hotkey="r" onPress={() => act($, ['run', current.name], { timeoutMs: LONG_CALL_MS })}>
            {`${mark(`run:${current.name}`)}run now`}
          </Button>
          <Button
            key={`toggle:${current.name}`}
            plain
            hotkey="p"
            onPress={() => act($, [current.status === 'paused' ? 'resume' : 'pause', current.name])}
          >
            {`${mark(`toggle:${current.name}`)}${current.status === 'paused' ? 'resume' : 'pause'}`}
          </Button>
          <Button
            key={`task-log:${current.name}`}
            plain
            hotkey="l"
            onPress={async () => {
              // Straight to the log view, with the ring on its position row: going by the task view first would
              // put the ring on an action the log view may not draw (a short pane folds them away), and a ring
              // left on nothing hands the keys to the prompt.
              await settle($)
              await viewLog($, current.name)
              await patch($, { opened: current.name, selected: current.name, logTop: 0, notice: '' })
              ringOn = 'log-at'
              await settle($)
              void focusOn($, site, 'log-at')
            }}
          >
            {`${mark(`task-log:${current.name}`)}log`}
          </Button>
          {close && (
            <Button key="band-close" plain hotkey="c" onPress={close}>
              close
            </Button>
          )}
          {folded && <Text dimColor>{fit(keys, Math.max(10, cols - (close ? 45 : 36)))}</Text>}
        </Box>
      )}
      {!(folded && current) && <Text dimColor>{fit(keys, cols)}</Text>}
      {result > 0 && <Text>{fit(lastResult(b.notice), cols)}</Text>}
      {spare > 0 && footer}
    </Box>
  )
}

// How many task rows the list drew last, read by the focus hook when a "more" marker takes the focus; and the same
// for an open log's window and its length.
let windowSize = 1
let logWindowSize = 1
let logLength = 0
// "›" marks, as text, what inverse video marks for the eye, since inverse is lost wherever a screen is read as
// plain text. In the list it marks the selected task, from the board, so mark and selection come from one state
// on one render (Claude Code can put the ring back on a row without a focus event, after Escape steps back). In a
// task's view it marks the action the ring is on, kept here from the focus hook, since only the arrows move it.
let ringOn = ''
const mark = (key: string) => (key === ringOn ? '› ' : '')

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'scheduler-pane', description: 'Open the Scheduled tasks pane' })

    return next(e)
  })

  on('command.run', { command: 'scheduler-pane' }, async $ => {
    if (!(await inWorkspace($))) {
      return {
        text: 'The Scheduled tasks pane works inside a kit workspace. The CLI works anywhere: schedule.sh list, or /scheduler:tasks.',
      }
    }
    // focus asks for the keyboard. The surface grants it while the prompt holds the keys over an empty composer,
    // as it does once this command has run; Escape hands the keys back and closes the pane.
    await patch($, { opened: '', log: '', notice: '' })
    // columns asks for a dock wide enough for a task row when the terminal seats the pane beside the transcript
    // (fullscreen, from 110 columns); the surface caps it at 45% of the terminal. Inline it takes the full width.
    // rows asks for as much height as the surface gives an inline pane: without it, an inline pane gets about a
    // quarter of the terminal (11 rows at 40), and with it all there is (27 at 40); the view fits what it gets.
    const opened = await $.ui.open({ id: PANE, title: TITLE, focus: true, closeOnEscape: true, columns: 60, rows: 200 })
    if (!opened.isPlaced) {
      // No seat for a pane: the same view is drawn in the band above the prompt, until its Close.
      inBand = true
      await refresh($)
      $.ui.invalidate('ui.render')
      return { text: 'Scheduled tasks are shown above the prompt: there is no room for a pane here.' }
    }

    return { text: 'Scheduled tasks pane opened.' }
  })

  // Set while the view is drawn in the band because the surface gave the pane no seat.
  let inBand = false
  // The refresh timer runs only while the pane is placed: it starts when the pane opens and stops when it closes.
  let timer: Timer | undefined
  on('ui.open', { id: PANE }, async ($, e, next) => {
    if (!timer) timer = $.clock.every(REFRESH_MS, () => void refresh($))
    // The first read can take a few seconds; while it runs the pane holds only its Loading line, so nothing takes
    // the ring as the pane takes the keyboard. Once the rows are drawn, the ring goes to the selected one.
    void refresh($).then(async () => {
      const b = await read($, board)
      const name = b.opened || b.selected || b.tasks[0]?.name
      if (name && ringOn === '') await focusOn($, PANE, `row:${name}`)
    })

    return next(e)
  })
  on('ui.close', { id: PANE }, async ($, e, next) => {
    if (e.origin.kind !== 'person' || (await read($, board)).opened === '') ringOn = ''
    // Escape, or the close mark, from a task's own view steps back to the list and keeps the pane open.
    const was = (await read($, board)).opened
    if (e.origin.kind === 'person' && was !== '') {
      await patch($, { opened: '', log: '', notice: '' })
      // Escape handed the keyboard back to the prompt before this close was refused; opening the same pane again
      // asks for it once more (the prompt is empty, so it is granted), then the ring goes back to the task's row.
      void $.ui
        .open({ id: PANE, title: TITLE, focus: true, closeOnEscape: true, columns: 60, rows: 200 })
        // Taking the keyboard back puts the ring on the first row a moment later; the move to the task's own row
        // waits for that, so it lands last.
        .then(() => $.clock.sleep(250))
        .then(() => focusOn($, PANE, `row:${was}`))
        .catch(() => undefined)
      return { value: undefined }
    }
    timer?.cancel()
    timer = undefined

    return next(e)
  })

  // The focus ring is the selection: arrowing onto a task's row selects it, so r, p and l act on that task. An arrow
  // that would put the ring on a "more" marker is kept from moving there: the window moves one row that way
  // instead, and the ring goes to the task that came into view, so each press of Up or Down moves one task.
  on('ui.focus', async ($, e, next) => {
    const element = e.element ?? ''
    // Tab or Shift+Tab onto one of Claude Code's own stops (the close mark) would leave the pane with no control
    // of its own under the ring, and the next letter typed would go to the prompt; the ring stays on the selected
    // task's row instead (in a task's view, its title, which shares that key). Escape still closes the pane.
    if (e.origin.kind === 'person' && element === '' && e.requestId === PANE) {
      const b = await read($, board)
      const name = b.opened || b.selected || b.tasks[0]?.name
      if (name) return next({ ...e, element: `row:${name}` })
    }
    if (element.startsWith('row:')) await patch($, { selected: element.slice('row:'.length) })
    if (e.requestId === PANE && element !== 'more-down' && element !== 'more-up') {
      ringOn = element
      $.ui.invalidate('ui.render')
    }
    if (e.origin.kind === 'person' && (element === 'log-down' || element === 'log-up')) {
      const b = await read($, board)
      const top = Math.max(0, Math.min(element === 'log-down' ? b.logTop + 1 : b.logTop - 1, Math.max(0, logLength - logWindowSize)))
      await patch($, { logTop: top })
      void focusOn($, e.requestId, 'log-at')
      return {}
    }
    if (e.origin.kind === 'person' && (element === 'more-down' || element === 'more-up')) {
      const b = await read($, board)
      const at = Math.max(0, b.tasks.findIndex(t => t.name === b.selected))
      const to = b.tasks[element === 'more-down' ? at + 1 : at - 1]
      if (to) {
        const top = Math.max(0, element === 'more-down' ? b.top + 1 : b.top - 1)
        await patch($, { selected: to.name, top: Math.min(top, Math.max(0, b.tasks.length - windowSize)) })
        void focusOn($, e.requestId, `row:${to.name}`)
        return {}
      }
    }

    return next(e)
  })

  // The band above the prompt draws the terminal view only while the pane had no seat; otherwise it passes.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (!inBand || e.surface !== 'terminal' || e.props.hasSurvey) return next(e)
    const b = await read($, board)
    const close = () => {
      inBand = false
      $.ui.invalidate('ui.render')
    }
    return terminalView($, $.ui.resolve(e), b, await $.clock.now(), e.props.bodyColumns, e.props.scroll.bodyRows, e.requestId, close)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const b = await read($, board)
    const now = await $.clock.now()
    if (e.surface === 'terminal' && b.isInWorkspace) {
      return terminalView($, $.ui.resolve(e), b, now, e.props.bodyColumns, e.props.scroll.bodyRows, PANE, undefined)
    }

    // The desktop, vscode and mobile trees: a block per task with its own buttons. Mobile has no Input.
    const { Box, Text, Button, Input, Code } = $.ui.resolve(e) as Elements['terminal']
    const mobile = e.surface === 'mobile'
    const gap = 1

    if (!b.isInWorkspace) {
      return (
        <Text>
          The Scheduled tasks pane works inside a kit workspace. The CLI works anywhere: schedule.sh list.
        </Text>
      )
    }

    return (
      <Box flexDirection="column" gap={gap}>
        {b.waiting.length > 0 && (
          <Box flexDirection="column" gap={gap}>
            <Text bold>Needs your answer</Text>
            {b.waiting.map(w => (
              <Box key={`waiting:${w.task}`} flexDirection="column">
                <Text bold>{w.task}</Text>
                <Text dimColor>waiting {waited(w.since, now)}</Text>
                <Text>{w.question}</Text>
                {mobile ? (
                  <Text dimColor>
                    Answer from a Mac with /scheduler:tasks reply {w.task}, or through the notify
                    command's phone path.
                  </Text>
                ) : (
                  <Input
                    key={`reply:${w.task}`}
                    label="Answer"
                    placeholder="Type an answer"
                    submitLabel="send"
                    onSubmit={text => {
                      if (text.trim() === '') return
                      void act($, ['reply', w.task, '--run', w.run, '--file', '-'], {
                        timeoutMs: LONG_CALL_MS,
                        stdin: text,
                      })
                    }}
                  />
                )}
                <Button key={`session:${w.task}`} onPress={() => patch($, { notice: `claude --resume ${w.sessionId}` })}>
                  Open session
                </Button>
              </Box>
            ))}
          </Box>
        )}

        {b.attention.length > 0 && (
          <Box flexDirection="column" gap={gap}>
            <Text bold>Needs attention</Text>
            {b.attention.map(a => (
              <Box key={`attention:${a.task}`} flexDirection="column">
                <Text>{a.task}</Text>
                <Text dimColor>{a.reason}</Text>
                <Button key={`attention-log:${a.task}`} onPress={() => viewLog($, a.task)}>
                  View log
                </Button>
              </Box>
            ))}
          </Box>
        )}

        <Box flexDirection="column" gap={gap}>
          <Text bold>All tasks</Text>
          {b.tasks.length === 0 && <Text dimColor>No scheduled tasks yet. Make one with /scheduler:tasks.</Text>}
          {b.tasks.map(t => {
            const actions = (
              <Box flexDirection="row" gap={2}>
                <Button key={`run:${t.name}`} onPress={() => act($, ['run', t.name], { timeoutMs: LONG_CALL_MS })}>
                  Run now
                </Button>
                <Button
                  key={`toggle:${t.name}`}
                  onPress={() => act($, [t.status === 'paused' ? 'resume' : 'pause', t.name])}
                >
                  {t.status === 'paused' ? 'Resume' : 'Pause'}
                </Button>
                <Button key={`task-log:${t.name}`} onPress={() => viewLog($, t.name)}>
                  View log
                </Button>
              </Box>
            )
            return (
              <Box key={`task:${t.name}`} flexDirection="column">
                <Text>
                  {t.name}  {t.status}  {t.schedule}
                </Text>
                <Text dimColor>
                  {t.next ? `next ${t.next}` : 'not scheduled'} · last {lastWords(t)}
                </Text>
                {actions}
              </Box>
            )
          })}
        </Box>

        {b.log !== '' && (
          <Box flexDirection="column" gap={gap}>
            <Text bold>Log: {b.logTask}</Text>
            <Code source={b.log} wrap="wrap" />
            <Button key="log-close" onPress={() => patch($, { log: '' })}>
              Close log
            </Button>
          </Box>
        )}

        {b.notice !== '' && <Code source={b.notice} wrap="wrap" />}

        <Text dimColor>
          {b.backend} · {b.tasksFolder} · refreshed {b.refreshedAt}
        </Text>
      </Box>
    )
  })
}
