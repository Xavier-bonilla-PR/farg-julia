#!/usr/bin/env python3
"""Times the Scheme reference implementation of Metacat against the Julia port.

Both sides run on the same CPython-compatible MT19937 (see
metacat/scheme/headless/shared-rng.ss and copycat/julia/src/pyrandom.jl), so a
given seed makes them execute the identical codelet sequence. Every workload
therefore carries a checksum, and this driver refuses to report a timing until
the two checksums agree -- a port that got faster by doing different work fails
here instead of showing up as a speedup.

Three benchmarks are run:

  metacat_bench.{ss,jl}     five single-layer micro-benchmarks plus the model
                            in aggregate, ordinarily and in justify mode
  metacat_problems.{ss,jl}  the model one problem at a time, which is where the
                            spread between cheap and expensive runs shows up
  time to first answer      one cold process, one small problem, wall clock --
                            the measurement the two above cannot make, because
                            they both discard start-up on purpose

That last one is the honest counterweight to the speedups. Chez loads Metacat's
source and interprets it; Julia compiles the port before it can run a codelet,
and the compile costs far more than a small problem does. So the port loses
outright on a single run and only pays for itself across a sweep -- which is
what it is for. The crossover is reported alongside.

Writes results/benchmark.json and results/benchmark.txt and prints a summary.
"""
import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BENCH = os.path.join('metacat', 'bench')


def run(cmd, cwd):
    t0 = time.perf_counter()
    out = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    wall = time.perf_counter() - t0
    if out.returncode != 0:
        sys.exit("command failed: %s\n%s" % (' '.join(cmd), out.stderr[-3000:]))
    return out.stdout, wall


def parse(stdout, tag):
    """BENCH/PROB lines -> {name: (iterations, seconds, checksum_fields)}."""
    rows = {}
    for line in stdout.splitlines():
        parts = line.rstrip('\n').split('\t')
        if not parts or parts[0] != tag:
            continue
        name, iterations, seconds = parts[1], int(parts[2]), float(parts[3])
        rows[name] = (iterations, seconds, tuple(parts[4:]))
    return rows


def compare(scm, jl, what):
    """Both sides must have run the same workloads and reached the same state."""
    if list(scm) != list(jl):
        sys.exit("%s: workload names differ\n  scheme: %s\n  julia:  %s"
                 % (what, list(scm), list(jl)))
    for name in scm:
        s_iters, _, s_sum = scm[name]
        j_iters, _, j_sum = jl[name]
        if s_iters != j_iters:
            sys.exit("%s: %s ran %d iterations in Scheme, %d in Julia"
                     % (what, name, s_iters, j_iters))
        if s_sum != j_sum:
            sys.exit("%s: %s did DIFFERENT WORK\n  scheme: %s\n  julia:  %s"
                     % (what, name, s_sum, j_sum))


def table(rows_scm, rows_jl, head, checksum_head):
    width = max(len(n) for n in rows_scm)
    out = ['%-*s %6s %10s %10s %8s  %s'
           % (width, head, 'iters', 'chez s', 'julia s', 'speedup', checksum_head),
           '-' * (width + 60)]
    for name in rows_scm:
        iters, s_secs, s_sum = rows_scm[name]
        _, j_secs, _ = rows_jl[name]
        out.append('%-*s %6d %10.3f %10.3f %7.1fx  %s'
                   % (width, name, iters, s_secs, j_secs, s_secs / j_secs,
                      ' '.join(s_sum)))
    tot_s = sum(r[1] for r in rows_scm.values())
    tot_j = sum(r[1] for r in rows_jl.values())
    out.append('-' * (width + 60))
    out.append('%-*s %6s %10.3f %10.3f %7.1fx'
               % (width, 'TOTAL', '', tot_s, tot_j, tot_s / tot_j))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--julia', default=os.environ.get('JULIA', 'julia'))
    ap.add_argument('--scheme', default=os.environ.get('SCHEME', 'scheme'))
    ap.add_argument('--cold-repeats', type=int, default=3,
                    help='cold-process runs to time for time-to-first-answer')
    ap.add_argument('--out', default=os.path.join(ROOT, 'metacat', 'results'))
    opts = ap.parse_args()

    report = []
    payload = {}

    for bench, tag, head, checksum_head in [
            ('metacat_bench', 'BENCH', 'workload', 'checksum'),
            ('metacat_problems', 'PROB', 'problem', 'outcome  codelets  temp')]:
        # The Scheme loads the model through repo-root-relative paths; the Julia
        # includes its sources relative to metacat/bench. Each runs where it can.
        scm_out, scm_wall = run([opts.scheme, '--quiet', '--script',
                                 os.path.join(BENCH, bench + '.ss')], ROOT)
        jl_out, jl_wall = run([opts.julia, bench + '.jl'],
                              os.path.join(ROOT, BENCH))
        scm, jl = parse(scm_out, tag), parse(jl_out, tag)
        if not scm:
            sys.exit("%s.ss produced no %s lines" % (bench, tag))
        compare(scm, jl, bench)
        report += table(scm, jl, head, checksum_head) + ['']
        payload[bench] = {
            'scheme_process_wall_s': scm_wall,
            'julia_process_wall_s': jl_wall,
            'rows': [{'name': n, 'iterations': scm[n][0],
                      'scheme_s': scm[n][1], 'julia_s': jl[n][1],
                      'speedup': scm[n][1] / jl[n][1],
                      'checksum': list(scm[n][2])} for n in scm],
        }

    report.append('process wall clock, whole benchmark, including load and JIT:')
    for bench in payload:
        report.append('  %-18s chez %6.2f s   julia %6.2f s'
                      % (bench, payload[bench]['scheme_process_wall_s'],
                         payload[bench]['julia_process_wall_s']))
    report.append('')

    # --- time to first answer: one cold process, one small problem ----------
    #
    # Both runners print the same block, so a mismatch here is a porting bug
    # and not just a slow start-up; it is checked rather than assumed.
    problem = ['abc', 'cba', 'pqrs', '42', '5000']
    scm_runs, jl_runs, scm_out, jl_out = [], [], None, None
    for _ in range(opts.cold_repeats):
        out, wall = run([opts.scheme, '--quiet', '--script',
                         os.path.join(BENCH, 'run_metacat_scm.ss')] + problem, ROOT)
        scm_runs.append(wall)
        scm_out = out
        out, wall = run([opts.julia, 'run_metacat_jl.jl'] + problem,
                        os.path.join(ROOT, BENCH))
        jl_runs.append(wall)
        jl_out = out
    if scm_out != jl_out:
        sys.exit('the two runners disagree on %s\n  scheme: %r\n  julia:  %r'
                 % (' '.join(problem), scm_out, jl_out))
    scm_cold, jl_cold = min(scm_runs), min(jl_runs)
    payload['time_to_first_answer'] = {
        'problem': ' '.join(problem), 'repeats': opts.cold_repeats,
        'scheme_s': scm_cold, 'julia_s': jl_cold,
        'scheme_all_s': scm_runs, 'julia_all_s': jl_runs,
    }
    report.append('time to first answer -- cold process, %s, best of %d:'
                  % (' '.join(problem), opts.cold_repeats))
    report.append('  chez %6.2f s   julia %6.2f s   (julia is %.1fx SLOWER here)'
                  % (scm_cold, jl_cold, jl_cold / scm_cold))

    # How much model work has to be done before the port's throughput has paid
    # back its compile time. Solving  jl_cold + w/speedup = scm_cold + w  for w,
    # in seconds of Chez model time, using the whole-model speedup measured
    # above rather than any of the layer figures.
    rows = {r['name']: r for r in payload['metacat_problems']['rows']}
    speedup = (sum(r['scheme_s'] for r in rows.values()) /
               sum(r['julia_s'] for r in rows.values()))
    if speedup > 1:
        w = (jl_cold - scm_cold) / (1 - 1 / speedup)
        report.append('  break-even at ~%.0f s of Chez model time in one process '
                      '(whole-model speedup %.1fx)' % (w, speedup))

    text = '\n'.join(report)
    print(text)
    os.makedirs(opts.out, exist_ok=True)
    with open(os.path.join(opts.out, 'benchmark.json'), 'w') as fh:
        json.dump(payload, fh, indent=1)
    with open(os.path.join(opts.out, 'benchmark.txt'), 'w') as fh:
        fh.write(text + '\n')


if __name__ == '__main__':
    main()
