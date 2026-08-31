#!/usr/bin/env python3
"""Benchmark/verification runner for the reference Python Copycat.

Usage: run_py.py <initial> <modified> <target> <iterations> [--seed N]
                 [--logging] [--json]

Prints a canonical result block (answers in first-seen order) plus timings, so
that the Julia runner's output can be diffed against it directly.
"""
import argparse
import json
import logging
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))
from copycat.copycat import Copycat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('initial')
    ap.add_argument('modified')
    ap.add_argument('target')
    ap.add_argument('iterations', type=int)
    ap.add_argument('--seed', type=int, default=None)
    ap.add_argument('--logging', action='store_true',
                    help='enable the INFO file logging that main.py turns on')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--warmup', type=int, default=0,
                    help='discarded warmup trials, mirroring the Julia runner')
    opts = ap.parse_args()

    if opts.logging:
        os.makedirs('output', exist_ok=True)
        logging.basicConfig(level=logging.INFO, format='%(message)s',
                            filename='./output/copycat.log', filemode='w')
    else:
        logging.disable(logging.CRITICAL)

    if opts.warmup > 0:
        warm = Copycat(rng_seed=12345)
        warm.workspace.resetWithStrings(opts.initial, opts.modified, opts.target)
        warm.temperature.useAdj('pbest')
        for _ in range(opts.warmup):
            warm.runTrial()

    setup0 = time.perf_counter()
    copycat = Copycat(rng_seed=opts.seed)
    copycat.workspace.resetWithStrings(opts.initial, opts.modified, opts.target)
    copycat.temperature.useAdj('pbest')
    setup = time.perf_counter() - setup0

    answers = {}
    total_codelets = 0
    t0 = time.perf_counter()
    for _ in range(opts.iterations):
        answer = copycat.runTrial()
        total_codelets += answer['time']
        d = answers.setdefault(answer['answer'],
                               {'count': 0, 'sumtemp': 0.0, 'sumtime': 0.0})
        d['count'] += 1
        d['sumtemp'] += answer['temp']
        d['sumtime'] += answer['time']
    elapsed = time.perf_counter() - t0

    rows = [{'answer': k, 'count': v['count'],
             'avgtemp': v['sumtemp'] / v['count'],
             'avgtime': v['sumtime'] / v['count']}
            for k, v in answers.items()]

    if opts.json:
        print(json.dumps({'impl': 'python', 'version': sys.version.split()[0],
                          'problem': [opts.initial, opts.modified, opts.target],
                          'iterations': opts.iterations, 'seed': opts.seed,
                          'setup_s': setup, 'elapsed_s': elapsed, 'warmup': opts.warmup,
                          'codelets': total_codelets, 'answers': rows}))
    else:
        for r in rows:
            print('%s\t%d\t%.9f\t%.6f' % (r['answer'], r['count'], r['avgtemp'],
                                          r['avgtime']))
        print('# codelets\t%d' % total_codelets)
        print('# elapsed_s\t%.6f' % elapsed)


if __name__ == '__main__':
    main()
