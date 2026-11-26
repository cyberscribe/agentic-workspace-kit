// What the Scheduled tasks pane keeps: one atom, holding the last refresh's reads of the scheduler CLI and the
// output of the last action. The pane draws from this value and nothing else.

export type Task = {
  name: string
  status: string
  schedule: string
  next: string
  lastStatus: string
}

export type Waiting = {
  task: string
  run: string
  since: string
  sessionId: string
  question: string
}

export type Attention = {
  task: string
  reason: string
}

export type Board = {
  isInWorkspace: boolean
  refreshedAt: string
  backend: string
  tasksFolder: string
  tasks: Task[]
  waiting: Waiting[]
  attention: Attention[]
  notice: string
  log: string
  logTask: string
  // The task the terminal's action keys act on, by name; empty means the first task.
  selected: string
  // The task whose own view the terminal shows, by name; empty shows the list.
  opened: string
  // The first task the terminal list shows, when there are more tasks than rows.
  top: number
  // What a key started, shown in the key line until it finishes; empty when nothing is under way.
  busy: string
  // The first line an open log shows, when it is longer than the pane.
  logTop: number
}

declare module 'claude-code' {
  interface PluginState {
    scheduler: { board: Shaped<Board> }
  }
}
