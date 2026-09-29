#!/usr/bin/env python3
"""Remove exact lines from a file: the `without` arm of an ablation.

    strip-lines.py FILE LINE [LINE...]

Each LINE is compared with every line of FILE after trimming whitespace at both ends, and must match
a whole line: a LINE that is only part of a longer line does not count. Every line that matches is
removed and the file is rewritten in place.

When any LINE matches nothing, the file is left untouched, each missing LINE is named on stderr and
the exit status is 2. The runner records that ablation as stale: the line moved, was reworded or is
gone, which is a finding in itself, so nothing here tries to match loosely.
"""
import sys


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: strip-lines.py FILE LINE [LINE...]\n")
        return 64
    path, wanted = argv[1], [w.strip() for w in argv[2:]]
    if any(not w for w in wanted):
        sys.stderr.write("strip-lines.py: an empty line cannot be ablated\n")
        return 64
    try:
        with open(path, encoding="utf-8", newline="") as f:
            lines = f.read().splitlines(keepends=True)
    except OSError as e:
        sys.stderr.write(f"strip-lines.py: cannot read {path}: {e.strerror}\n")
        return 66

    present = {line.strip() for line in lines}
    missing = [w for w in wanted if w not in present]
    if missing:
        for w in missing:
            sys.stderr.write(f"stale: not a whole line in {path}: {w}\n")
        return 2

    drop = set(wanted)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.writelines(line for line in lines if line.strip() not in drop)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
