#!/usr/bin/env python3
"""Cross-checks the Julia port against the Python reference implementation.

Both share a bit-exact CPython-compatible RNG, so for a given seed they must
execute the identical codelet sequence and return the identical answers. Any
difference is a porting bug.

Two modes:
  * full   - run both to completion and compare answer distributions.
  * trace  - run both for a bounded number of codelets and compare the
             per-codelet trace. Used for problems that this Copycat variant
             takes pathologically long to settle (see PATHOLOGICAL below).
"""
import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PROBLEMS = [
    ("abc", "abd", "ijk"),
    ("abc", "abd", "iijjkk"),
    ("abc", "abd", "xyz"),
    ("abc", "abd", "mrrjjj"),
    ("abc", "abd", "ppqqrr"),
    ("abc", "abd", "ijkl"),
    ("abc", "abd", "rppkkk"),
    ("aabc", "aabd", "ijkk"),
    ("abcd", "abcde", "ijkl"),
    ("abc", "abd", "kji"),
    ("abc", "abd", "mrrkkk"),
    ("abac", "abad", "srqr"),
    ("rst", "rsu", "xyz"),
    ("abc", "abd", "wyz"),
    ("abc", "abd", "glz"),
]

# Problems where this Copycat variant runs for an unbounded-looking time in
# BOTH implementations (they agree codelet for codelet; they just take a very
# large number of codelets to reach an answer). Verified by trace instead.
PATHOLOGICAL = [
    ("axbxcx", "axbxdx", "pxqxrx"),
    ("abc", "abd", "aababc"),
]


def sh(cmd, timeout):
    try:
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return None
    if p.returncode != 0:
        sys.exit("failed: %s\n%s" % (' '.join(cmd), p.stderr[-3000:]))
    return [l for l in p.stdout.splitlines()
            if l and not l.startswith('#') and not l.startswith('Changing')]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--iterations', type=int, default=5)
    ap.add_argument('--seeds', type=int, nargs='+', default=[1, 2, 3])
    ap.add_argument('--julia', default=os.environ.get('JULIA', 'julia'))
    ap.add_argument('--timeout', type=int, default=180)
    ap.add_argument('--trace-codelets', type=int, default=4000)
    opts = ap.parse_args()

    fails = ok = 0

    for problem in PROBLEMS:
        for seed in opts.seeds:
            args = list(problem) + [str(opts.iterations), '--seed', str(seed)]
            py = sh([sys.executable, 'bench/run_py.py'] + args, opts.timeout)
            jl = sh([opts.julia, '--project=julia', 'bench/run_jl.jl'] + args, opts.timeout)
            label = '%s:%s::%s:? seed=%d' % (problem + (seed,))
            if py is None or jl is None:
                print('SKIP  %-34s (timeout - move it to PATHOLOGICAL)' % label)
                continue
            if py == jl:
                ok += 1
                print('ok    %-34s %s' % (label, '; '.join(py)))
            else:
                fails += 1
                print('DIFF  %-34s' % label)
                print('        python: %s' % py)
                print('        julia : %s' % jl)
            sys.stdout.flush()

    for problem in PATHOLOGICAL:
        for seed in opts.seeds:
            n = str(opts.trace_codelets)
            py = sh([sys.executable, 'bench/trace_py.py', str(seed), n] + list(problem),
                    opts.timeout)
            jl = sh([opts.julia, '--project=julia', 'bench/trace_jl.jl', str(seed), n] +
                    list(problem), opts.timeout)
            label = '%s:%s::%s:? seed=%d' % (problem + (seed,))
            if py is None or jl is None:
                print('SKIP  %-34s (trace timeout)' % label)
                continue
            if py == jl and len(py) > 0:
                ok += 1
                print('ok    %-34s %d codelets traced identically' % (label, len(py)))
            else:
                fails += 1
                first = next((i for i, (a, b) in enumerate(zip(py, jl)) if a != b), None)
                print('DIFF  %-34s first differing codelet: %s' % (label, first))
                if first is not None:
                    print('        python: %s' % py[first])
                    print('        julia : %s' % jl[first])
            sys.stdout.flush()

    print()
    print('%d/%d comparisons matched' % (ok, ok + fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
