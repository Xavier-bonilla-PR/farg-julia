#!/bin/bash
# Which top-level Scheme definitions have no counterpart in the Julia port?
#
# A mechanical name-diff over the 29 non-graphics files of the vendored Metacat.
# It is a SCREEN, not a verdict: run it after adding a layer, then check every
# name it prints by hand. As of the 2026-09-07 audit it reported ~80 names and
# ALL of them were false positives of four kinds -- see the audit note after
# step 8 in CONTINUE.md, which lists them:
#
#   (a) horizontal/vertical twins the port collapsed into one function that
#       takes the orientation as an argument
#   (b) constructors, accessors and globals that became structs, fields, CONSTs
#   (c) curried closures the port flattened into ordinary arguments
#   (d) five definitions that are DEAD in the Scheme itself
#
# So a name here means "look at this", never "port this".
#
# Usage:  bash metacat/bench/audit_coverage.sh [file ...]     (no args = all)

set -u
SS=metacat/scheme/metacat
[ -d "$SS" ] || { echo "run me from the repo root" >&2; exit 1; }

FILES=${*:-$(ls $SS | sed 's/\.ss$//' | grep -vE 'graphics|gui|fonts|sgl-interpreter|demos')}
JL=$(cat metacat/julia/src/*.jl metacat/bench/*.jl)

for f in $FILES; do
  [ -f "$SS/$f.ss" ] || continue
  while read -r name; do
    [ -z "$name" ] && continue
    # scheme-name -> the shapes the port might have used
    stem=$(printf '%s' "$name" | sed 's/[?!]*$//' | tr -d '*=')
    c1=$(printf '%s' "$stem" | sed 's|->|_to_|g' | tr '/-' '__')   # a->b  => a_to_b
    c2="is_$c1"                                                    # foo?  => is_foo
    c3=$(printf '%s' "$stem" | sed 's|->||g'    | tr '/-' '__')    # a->b  => ab
    printf '%s' "$JL" | grep -qiE "\b($c1|$c2|$c3)\b" || echo "  $f: $name"
  done < <(grep -oE '^\(define \(?([a-zA-Z0-9!?<>=/*+-]+)' "$SS/$f.ss" | sed -E 's/^\(define \(?//')
done
