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
async function refresh($: EngineInterface) {
  try {
    if (!(await inWorkspace($))) {
      await patch($, { isInWorkspace: false })
      return
    }
    const listed = await cli($, ['list', '--json'])
    if (!listed.ok) {
      await patch($, { notice: listed.out })
      return
    }
    const rows: ListRow[] = JSON.parse(listed.out)
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

    await patch($, {
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
    await patch($, { notice: `refresh failed: ${String(err)}` })
  }
}

// One action: its CLI call, the output shown as the notice, then a refresh so the lists match the CLI.
async function act(
  $: EngineInterface,
  args: readonly string[],
  options: { timeoutMs?: number; stdin?: string } = {},
) {
  const res = await cli($, args, options)
  await patch($, { notice: `schedule.sh ${args.join(' ')}\n${res.out}` })
  await refresh($)
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
    lines.push(home(line.replace('claude --desktop --resume', 'claude --resume')))
  }
  while (lines.length > 0 && lines[lines.length - 1] === '') lines.pop()
  return lines
}

// What a task's row says after its name: what needs the person first, then when it next runs.
function rowWords(b: Board, t: Task) {
  if (b.waiting.some(w => w.task === t.name)) return 'needs your answer'
  const attention = b.attention.find(a => a.task === t.name)
  if (attention) return `needs attention: ${firstLine(attention.reason)}`
  if (t.status === 'paused') return `paused · ${t.schedule}`
  return `${t.schedule} · ${t.next ? `next ${t.next}` : 'not scheduled'}`
}

// The terminal's layout, in the pane or in the band above the prompt, at two levels, as a terminal list reads.
// The list: one row per task, which the arrows move between (the focus ring is the selection), Enter opens, and a
// digit jumps to. A task's own view: its details, a waiting run's question and answer field, and its log. The
// actions are buttons drawn with their keys (r, p, l), so the keys are on screen rather than remembered, and they
// act on the selected task in the list and on the open one in its view. Escape steps back from a task's view to
// the list, then closes the pane; in the band, where Escape belongs to the prompt, b and c do the same. A waiting
// run's view gives its answer field the focus, so answering is open, type, Enter; there the letters type, and
// Ctrl+D is the field's, until Escape steps back.
function terminalView(
  $: EngineInterface,
  el: Elements['terminal'],
  b: Board,
  now: number,
  cols: number,
  close: (() => void) | undefined,
) {
  const { Box, Text, Button, Input, Code } = el
  // A row is cut to the body's width rather than wrapped, so a narrow dock still shows one row per task.
  const fit = (text: string, room: number) => (text.length > room ? `${text.slice(0, Math.max(1, room - 1))}…` : text)
  const rows = b.tasks.slice(0, 9)
  const opened = b.tasks.find(t => t.name === b.opened)
  const current = opened ?? rows.find(t => t.name === b.selected) ?? rows[0]
  const width = Math.max(...rows.map(t => t.name.length), 0)

  const actions = current && (
    <Box flexDirection="row" gap={3}>
      <Button key={`run:${current.name}`} plain hotkey="r" onPress={() => act($, ['run', current.name], { timeoutMs: LONG_CALL_MS })}>
        run now
      </Button>
      <Button
        key={`toggle:${current.name}`}
        plain
        hotkey="p"
        onPress={() => act($, [current.status === 'paused' ? 'resume' : 'pause', current.name])}
      >
        {current.status === 'paused' ? 'resume' : 'pause'}
      </Button>
      <Button
        key={`task-log:${current.name}`}
        plain
        hotkey="l"
        onPress={async () => {
          if (opened && b.log !== '' && b.logTask === current.name) return patch($, { log: '' })
          await patch($, { opened: current.name, selected: current.name })
          await viewLog($, current.name)
        }}
      >
        {opened && b.log !== '' ? 'hide log' : 'log'}
      </Button>
      {opened && (
        <Button key="back" plain hotkey="b" autoFocus onPress={() => patch($, { opened: '', log: '' })}>
          back
        </Button>
      )}
      {!opened && close && (
        <Button key="band-close" plain hotkey="c" onPress={close}>
          close
        </Button>
      )}
    </Box>
  )

  const footer = (
    <Text dimColor>
      {b.backend} · refreshed {b.refreshedAt}
    </Text>
  )

  if (opened) {
    const waiting = b.waiting.find(w => w.task === opened.name)
    const attention = b.attention.find(a => a.task === opened.name)
    return (
      <Box flexDirection="column">
        <Text bold wrap="truncate-end">
          {opened.name} · {opened.status}
        </Text>
        <Text dimColor wrap="truncate-end">
          {opened.schedule} · {opened.next ? `next ${opened.next}` : 'not scheduled'} · last {lastWords(opened)}
        </Text>
        {attention && <Text>{attention.reason}</Text>}
        {waiting && (
          <Box flexDirection="column" marginTop={1}>
            <Text bold>Needs your answer · waiting {waited(waiting.since, now)}</Text>
            <Text>{waiting.question}</Text>
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
            <Button key={`session:${waiting.task}`} plain hotkey="o" onPress={() => patch($, { notice: `claude --resume ${waiting.sessionId}` })}>
              open its session
            </Button>
          </Box>
        )}
        <Box marginTop={1}>{actions}</Box>
        {/* The keys sit under the actions, above anything long, so a log never pushes them out of view. */}
        <Text dimColor wrap="truncate-end">
          {waiting ? 'type the answer, Enter sends · ' : ''}{close ? 'b back' : 'Esc back'} · Tab next
        </Text>
        {b.log !== '' && b.logTask === opened.name && (
          <Box flexDirection="column" marginTop={1}>
            {readableLog(b.log).map((line, i) => (
              <Text key={`log:${i}`} bold={i === 0}>
                {line === '' ? ' ' : line}
              </Text>
            ))}
          </Box>
        )}
        {b.notice !== '' && <Code source={b.notice} wrap="wrap" />}
        {footer}
      </Box>
    )
  }

  return (
    <Box flexDirection="column">
      {b.tasks.length === 0 && <Text dimColor>No scheduled tasks yet. Make one with /scheduler:tasks.</Text>}
      {rows.map((t, i) => (
        <Button
          key={`row:${t.name}`}
          plain
          hotkey={String(i + 1)}
          autoFocus={t === current ? true : undefined}
          onPress={() => patch($, { opened: t.name, selected: t.name, log: '', notice: '' })}
        >
          <Text bold={t === current}>{fit(`${t.name.padEnd(width)}  ${rowWords(b, t)}`, cols - 3)}</Text>
        </Button>
      ))}
      {b.tasks.length > rows.length && (
        <Text dimColor>{b.tasks.length - rows.length} more: /scheduler:tasks lists them all.</Text>
      )}
      {actions && <Box marginTop={1}>{actions}</Box>}
      <Text dimColor wrap="truncate-end">
        ↑↓ select · Enter or 1-{rows.length} open · {close ? 'c close' : 'Esc close'}
      </Text>
      {b.notice !== '' && <Code source={b.notice} wrap="wrap" />}
      {footer}
    </Box>
  )
}

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
    const opened = await $.ui.open({ id: PANE, title: TITLE, focus: true, closeOnEscape: true, columns: 60 })
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
    void refresh($)

    return next(e)
  })
  on('ui.close', { id: PANE }, async ($, e, next) => {
    // Escape, or the close mark, from a task's own view steps back to the list and keeps the pane open.
    if (e.origin.kind === 'person' && (await read($, board)).opened !== '') {
      await patch($, { opened: '', log: '' })
      return { value: undefined }
    }
    timer?.cancel()
    timer = undefined

    return next(e)
  })

  // The focus ring is the selection: arrowing onto a task's row selects it, so r, p and l act on that task.
  on('ui.focus', async ($, e, next) => {
    if (e.element?.startsWith('row:')) await patch($, { selected: e.element.slice('row:'.length) })

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
    return terminalView($, $.ui.resolve(e), b, await $.clock.now(), e.props.bodyColumns, close)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const b = await read($, board)
    const now = await $.clock.now()
    if (e.surface === 'terminal' && b.isInWorkspace) {
      return terminalView($, $.ui.resolve(e), b, now, e.props.bodyColumns, undefined)
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
                    Answer from a Mac with schedule.sh reply {w.task} --run {w.run} --file -, or through the notify
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
