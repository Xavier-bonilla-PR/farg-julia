#!/usr/bin/env python3
"""Times the Python reference and the Julia port on the same Copycat problems.

Because the two implementations share a bit-exact RNG stream, a given
(problem, seed, iterations) triple makes both run the *identical* sequence of
codelets. The codelet counts are asserted equal, so the timings compare the
same work rather than two different random walks.

Writes results/benchmark.json and prints a summary table.
"""
import argparse
import json
import os
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PROBLEMS = [
    ("abc", "abd", "ijk"),
    ("abc", "abd", "iijjkk"),
    ("abc", "abd", "mrrjjj"),
    ("abc", "abd", "ppqqrr"),
    ("abc", "abd", "xyz"),
    ("abc", "abd", "kji"),
    ("abcd", "abcde", "ijkl"),
]


def run(cmd):
    t0 = time.perf_counter()
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    wall = time.perf_counter() - t0
    if out.returncode != 0:
        sys.exit("command failed: %s\n%s" % (' '.join(cmd), out.stderr[-2000:]))
    line = [l for l in out.stdout.splitlines() if l.startswith('{')][-1]
    return json.loads(line), wall


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--iterations', type=int, default=10)
    ap.add_argument('--seeds', type=int, nargs='+', default=[1, 2, 3])
    ap.add_argument('--julia', default=os.environ.get('JULIA', 'julia'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'results', 'benchmark.json'))
    opts = ap.parse_args()

    results = []
    for problem in PROBLEMS:
        for seed in opts.seeds:
            base = list(problem) + [str(opts.iterations), '--seed', str(seed), '--json']
            py, py_wall = run([sys.executable, 'bench/run_py.py'] + base + ['--warmup', '1'])
            pyl, pyl_wall = run([sys.executable, 'bench/run_py.py'] + base +
                                ['--warmup', '1', '--logging'])
            jl, jl_wall = run([opts.julia, '--project=julia', 'bench/run_jl.jl'] +
                              base + ['--warmup', '1'])
            jlcold, jlcold_wall = run([opts.julia, '--project=julia', 'bench/run_jl.jl'] + base)

            assert py['codelets'] == jl['codelets'], (
                "codelet counts differ for %s seed %d: python %d vs julia %d" %
                (problem, seed, py['codelets'], jl['codelets']))
            assert py['answers'] == jl['answers'], (
                "answers differ for %s seed %d" % (problem, seed))

            results.append({
                'problem': list(problem), 'seed': seed,
                'iterations': opts.iterations, 'codelets': py['codelets'],
                'python_s': py['elapsed_s'],
                'python_logging_s': pyl['elapsed_s'],
                'julia_s': jl['elapsed_s'],
                'python_process_wall_s': py_wall,
                'julia_process_wall_s': jl_wall,
                'julia_cold_process_wall_s': jlcold_wall,
                'speedup': py['elapsed_s'] / jl['elapsed_s'],
                'python_codelets_per_s': py['codelets'] / py['elapsed_s'],
                'julia_codelets_per_s': jl['codelets'] / jl['elapsed_s'],
            })
            print('.', end='', flush=True)
    print()

    os.makedirs(os.path.dirname(opts.out), exist_ok=True)
    with open(opts.out, 'w') as fh:
        json.dump({'iterations': opts.iterations, 'seeds': opts.seeds,
                   'results': results}, fh, indent=1)

    # aggregate per problem
    print('%-24s %9s %10s %10s %10s %8s' %
          ('problem', 'codelets', 'python s', 'julia s', 'py+log s', 'speedup'))
    print('-' * 76)
    for problem in PROBLEMS:
        rows = [r for r in results if r['problem'] == list(problem)]
        name = '%s:%s::%s:?' % problem
        print('%-24s %9d %10.3f %10.3f %10.3f %7.1fx' % (
            name, sum(r['codelets'] for r in rows) // len(rows),
            statistics.mean(r['python_s'] for r in rows),
            statistics.mean(r['julia_s'] for r in rows),
            statistics.mean(r['python_logging_s'] for r in rows),
            statistics.mean(r['speedup'] for r in rows)))
    print('-' * 76)
    tot_py = sum(r['python_s'] for r in results)
    tot_jl = sum(r['julia_s'] for r in results)
    tot_cod = sum(r['codelets'] for r in results)
    print('%-24s %9d %10.3f %10.3f %10.3f %7.1fx' % (
        'TOTAL', tot_cod, tot_py, tot_jl,
        sum(r['python_logging_s'] for r in results), tot_py / tot_jl))
    print()
    print('throughput: python %.0f codelets/s, julia %.0f codelets/s' %
          (tot_cod / tot_py, tot_cod / tot_jl))
    print('julia process wall (warm run incl. startup+JIT): %.2f s avg' %
          statistics.mean(r['julia_cold_process_wall_s'] for r in results))


if __name__ == '__main__':
    main()
