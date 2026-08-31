#!/usr/bin/env bash
# Differential test of the Julia Metacat port against the Scheme original.
#
# Both sides run on the same CPython-compatible MT19937 (see
# scheme/headless/shared-rng.ss and julia/src/pyrandom.jl), so for a given seed
# they must produce byte-identical traces. Each probe pair covers one layer of
# the port.
set -u
JULIA="${JULIA:-julia}"
SCHEME="${SCHEME:-scheme}"
fail=0

probe () {
  local name="$1"
  local scm="bench/metacat_${name}_probe.ss"
  local jl="bench/metacat_${name}_probe.jl"
  [ -f "$scm" ] && [ -f "$jl" ] || { echo "skip  $name (probe missing)"; return; }
  "$SCHEME" --quiet --script "$scm" 2>&1 | grep -v '^Warning' > "/tmp/mc_${name}_scm.txt"
  (cd bench && "$JULIA" "metacat_${name}_probe.jl") > "/tmp/mc_${name}_jl.txt" 2>&1
  if diff -q "/tmp/mc_${name}_scm.txt" "/tmp/mc_${name}_jl.txt" > /dev/null; then
    echo "ok    $name ($(wc -l < "/tmp/mc_${name}_scm.txt") lines identical)"
  else
    fail=1
    echo "DIFF  $name"
    diff "/tmp/mc_${name}_scm.txt" "/tmp/mc_${name}_jl.txt" | head -20 | sed 's/^/        /'
  fi
}

for p in "$@"; do probe "$p"; done
[ "$fail" -eq 0 ] && echo "all probes matched" || echo "SOME PROBES DIFFER"
exit $fail
