# ws-min: the smallest 3.0 workspace

`mkws_min` in `tests/run.sh` copies this tree into a new repository after adding the kit at `kit/`.
Names that start with a dot are stored with a `dot-` prefix instead (`dot-claude/` becomes `.claude/`,
`dot-gitignore` becomes `.gitignore`): a `.claude` folder is refused by the kit's own path check, and a
`.gitignore` here would apply to the kit's tree. This README is not copied.
