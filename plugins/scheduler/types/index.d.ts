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
}

declare module 'claude-code' {
  interface PluginState {
    scheduler: { board: Shaped<Board> }
  }
}
