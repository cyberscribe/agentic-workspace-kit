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
    await $.ui.open({ id: PANE, title: TITLE })

    return { text: 'Scheduled tasks pane opened.' }
  })

  // The refresh timer runs only while the pane is placed: it starts when the pane opens and stops when it closes.
  let timer: Timer | undefined
  on('ui.open', { id: PANE }, async ($, e, next) => {
    if (!timer) timer = $.clock.every(REFRESH_MS, () => void refresh($))
    void refresh($)

    return next(e)
  })
  on('ui.close', { id: PANE }, ($, e, next) => {
    timer?.cancel()
    timer = undefined

    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    // Only the desktop and vscode trees draw buttons and the answer field: the terminal pane is a view, and mobile has no Input.
    const { Box, Text, Button, Input, Code } = $.ui.resolve(e) as Elements['terminal']
    const b = await read($, board)
    const now = await $.clock.now()
    const mobile = e.surface === 'mobile'
    // The terminal pane is a view: its sections run together and each task is one row of text. Acting is on the
    // desktop app, or by asking Claude. The desktop layout keeps its spacing.
    const terminal = e.surface === 'terminal'
    const gap = terminal ? 0 : 1

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
                {terminal ? (
                  <Text dimColor>Answer it by asking Claude here, or with /scheduler:tasks.</Text>
                ) : mobile ? (
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
                {!terminal && (
                  <Button
                    key={`session:${w.task}`}
                    onPress={() => patch($, { notice: `claude --resume ${w.sessionId}` })}
                  >
                    Open session
                  </Button>
                )}
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
                {!terminal && (
                  <Button key={`attention-log:${a.task}`} onPress={() => viewLog($, a.task)}>
                    View log
                  </Button>
                )}
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
            if (terminal) {
              return (
                <Text key={`task:${t.name}`}>
                  {t.name}  {t.status}  {t.schedule}  ·  {t.next ? `next ${t.next}` : 'not scheduled'}  ·  last{' '}
                  {t.lastStatus === 'waiting' ? 'awaiting your answer' : t.lastStatus || 'none yet'}
                </Text>
              )
            }
            return (
              <Box key={`task:${t.name}`} flexDirection="column">
                <Text>
                  {t.name}  {t.status}  {t.schedule}
                </Text>
                <Text dimColor>
                  {t.next ? `next ${t.next}` : 'not scheduled'} · last {t.lastStatus === 'waiting' ? 'awaiting your answer' : t.lastStatus || 'none yet'}
                </Text>
                {actions}
              </Box>
            )
          })}
        </Box>

        {b.log !== '' && !terminal && (
          <Box flexDirection="column" gap={gap}>
            <Text bold>Log: {b.logTask}</Text>
            <Code source={b.log} wrap="wrap" />
            <Button key="log-close" onPress={() => patch($, { log: '' })}>
              Close log
            </Button>
          </Box>
        )}

        {b.notice !== '' && <Code source={b.notice} wrap="wrap" />}

        {terminal && <Text dimColor>Ask Claude here, or use /scheduler:tasks, to run, pause, resume, answer or read a log.</Text>}
        <Text dimColor>
          {b.backend} · {b.tasksFolder} · refreshed {b.refreshedAt}
        </Text>
      </Box>
    )
  })
}
