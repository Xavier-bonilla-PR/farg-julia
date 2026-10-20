#!/bin/bash
# Where does Metacat narrate itself, and how much of it is there?
#
# Lists every `(tell *comment-window* 'add-comment ...)` in the non-graphics
# Scheme with the size of each send, brace-matched. This is the one genuine
# non-graphics gap in the port as of 2026-09-07 -- see the audit note after
# step 8 in CONTINUE.md.
#
# The sends are model output, not graphics: harness.ss stubs *comment-window*
# as (lambda msg (void)), but Chez still EVALUATES the arguments, so the Scheme
# already computes every one of these lines on every probe run and throws the
# result away. Replacing that stub with a printer is all a `narration` probe
# needs on the Scheme side.
#
# Usage:  bash metacat/bench/audit_narration.sh

set -u
[ -d metacat/scheme/metacat ] || { echo "run me from the repo root" >&2; exit 1; }

python3 - <<'PY'
import re, glob, os
total, sites = 0, []
for path in sorted(glob.glob('metacat/scheme/metacat/*.ss')):
    f = os.path.basename(path)
    if re.search(r'graphics|gui|fonts|sgl', f):
        continue
    lines = open(path).read().split('\n')
    for i, line in enumerate(lines):
        if "'add-comment" not in line:
            continue
        depth, j = 0, i
        while j < len(lines):
            depth += lines[j].count('(') - lines[j].count(')')
            if depth <= 0 and j > i:
                break
            j += 1
        n = j - i + 1
        total += n
        sites.append((f, i + 1, n))
for f, ln, n in sites:
    print(f"  {f}:{ln}\t{n} lines")
print(f"\n{len(sites)} sites, {total} lines of narration")
PY
