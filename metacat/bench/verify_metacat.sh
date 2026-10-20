#!/usr/bin/env bash
# Differential test of the Julia Metacat port against the Scheme original.
#
# Both sides run on the same CPython-compatible MT19937 (see
# metacat/scheme/headless/shared-rng.ss and copycat/julia/src/pyrandom.jl), so for
# a given seed they must produce byte-identical traces. Each probe pair covers
# one layer of the port.
set -u

# The Scheme probes load the model through repo-root-relative paths, so run
# from the repo root whatever the caller's working directory is.
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
JULIA="${JULIA:-julia}"
SCHEME="${SCHEME:-scheme}"
fail=0

probe () {
  local name="$1"
  local scm="metacat/bench/metacat_${name}_probe.ss"
  local jl="metacat/bench/metacat_${name}_probe.jl"
  [ -f "$scm" ] && [ -f "$jl" ] || { echo "skip  $name (probe missing)"; return; }
  "$SCHEME" --quiet --script "$scm" 2>&1 | grep -v '^Warning' > "/tmp/mc_${name}_scm.txt"
  (cd metacat/bench && "$JULIA" "metacat_${name}_probe.jl") > "/tmp/mc_${name}_jl.txt" 2>&1
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
