#!/usr/bin/env python3
"""Renders results/benchmark.json into the results table embedded in README.md."""
import json
import os
import platform
import statistics
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    with open(os.path.join(ROOT, 'results', 'benchmark.json')) as fh:
        data = json.load(fh)
    rows = data['results']

    problems = []
    for r in rows:
        if r['problem'] not in problems:
            problems.append(r['problem'])

    out = []
    out.append('Measured on %s, %d iterations per problem, seeds %s. '
               'Both implementations execute the identical codelet sequence, so '
               'the codelet count is shared.' %
               (describe_machine(), data['iterations'],
                ', '.join(str(s) for s in data['seeds'])))
    out.append('')
    out.append('| problem | codelets | Python | Julia | speedup | Python w/ logging |')
    out.append('|---|---:|---:|---:|---:|---:|')
    for p in problems:
        rs = [r for r in rows if r['problem'] == p]
        out.append('| `%s : %s :: %s : ?` | %s | %.2f s | %.3f s | **%.1fx** | %.2f s |' % (
            p[0], p[1], p[2],
            f'{sum(r["codelets"] for r in rs) // len(rs):,}',
            statistics.mean(r['python_s'] for r in rs),
            statistics.mean(r['julia_s'] for r in rs),
            statistics.mean(r['speedup'] for r in rs),
            statistics.mean(r['python_logging_s'] for r in rs)))
    tot_py = sum(r['python_s'] for r in rows)
    tot_jl = sum(r['julia_s'] for r in rows)
    tot_log = sum(r['python_logging_s'] for r in rows)
    tot_cod = sum(r['codelets'] for r in rows)
    out.append('| **total** | **%s** | **%.2f s** | **%.2f s** | **%.1fx** | **%.2f s** |' % (
        f'{tot_cod:,}', tot_py, tot_jl, tot_py / tot_jl, tot_log))
    out.append('')
    out.append('Throughput: **%s codelets/s** in Python vs **%s codelets/s** in Julia.'
               % (f'{round(tot_cod / tot_py):,}', f'{round(tot_cod / tot_jl):,}'))
    out.append('')
    out.append('Caveats worth stating plainly:')
    out.append('')
    out.append('- The Julia figures exclude interpreter startup and JIT '
               'compilation (both runners take a `--warmup` flag that discards '
               'a throwaway trial first). A cold `julia ... bench/run_jl.jl` '
               'process averages **%.1f s** wall clock here, most of it '
               'compilation, against **%.1f s** for the equivalent Python '
               'process. For a single small problem the Python process still '
               'finishes first; the Julia advantage is in the work itself, and '
               'it pays for its startup within roughly the first second of '
               'search.' % (statistics.mean(r['julia_cold_process_wall_s'] for r in rows),
                            statistics.mean(r['python_process_wall_s'] for r in rows)))
    out.append('- The "Python w/ logging" column is what `main.py` actually does '
               '- it calls `logging.basicConfig(level=INFO)`, so every '
               '`logging.info` in the codelets formats a string and writes it to '
               'disk. That alone costs about %.0f%% on top of the Python '
               'runtime. The main comparison disables it, which is the fairer '
               'measurement of the algorithm.' % (100 * (tot_log / tot_py - 1)))
    out.append('- Copycat is a stochastic search, so absolute times depend '
               'heavily on the problem and seed; the per-problem spread above is '
               'the point, not any single number.')

    table = '\n'.join(out)
    readme = os.path.join(ROOT, 'README.md')
    with open(readme) as fh:
        s = fh.read()
    marker = 'RESULTS_PLACEHOLDER'
    if marker in s:
        s = s.replace(marker, table)
    else:
        start = s.index('## Benchmark')
        end = s.index('## Notes on the translation')
        head = s[start:end]
        cut = head.index('mismatch fails loudly rather than producing a meaningless speedup number.')
        cut = start + cut + len('mismatch fails loudly rather than producing a meaningless speedup number.')
        s = s[:cut] + '\n\n' + table + '\n\n' + s[end:]
    with open(readme, 'w') as fh:
        fh.write(s)
    print(table)


def describe_machine():
    try:
        model = subprocess.run(['bash', '-c',
                                "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2"],
                               capture_output=True, text=True).stdout.strip()
    except Exception:
        model = ''
    cpu = model or platform.processor() or 'unknown CPU'
    jl = subprocess.run([os.environ.get('JULIA', 'julia'), '--version'],
                        capture_output=True, text=True).stdout.strip()
    return '%s (%s cores), CPython %s, %s' % (
        cpu, os.cpu_count(), platform.python_version(), jl or 'julia')


if __name__ == '__main__':
    main()
