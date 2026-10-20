;; Per-problem benchmark of the WHOLE model, against the Julia port.
;;
;; metacat_bench.ss times the model in aggregate -- three problems summed into
;; one workload -- which is the right shape for tracking a regression but says
;; nothing about how the cost varies with the problem. Metacat's cost varies a
;; lot: a run that finds its answer in a few hundred codelets and a run that
;; hits a snag, clamps, and grinds to the budget are different workloads, and
;; averaging them hides which one the port is good at.
;;
;; So this benchmark times one problem at a time and reports what each run
;; actually did. Emits, one line per problem:
;;
;;   PROB <name> <iterations> <seconds> <outcome> <codelets> <temperature>
;;
;; The last three fields are the checksum. Both implementations run on the same
;; MT19937 (metacat/scheme/headless/shared-rng.ss), so for a given seed they
;; must agree on all three; metacat/bench/benchmark.py asserts they do before it
;; reports any timing. A port that got faster by doing different work fails
;; there rather than showing up as a speedup.
;;
;; The memory is CLEARED before every iteration. Reminding makes a run depend on
;; the runs before it, so without the clear the second iteration of a problem
;; would do different (and cheaper) work than the first, and the average would
;; be of nothing in particular.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define secs (lambda (ms) (/ (exact->inexact ms) 1000.0)))

;; TWO warm-up runs outside the clock, then `iterations` timed ones. They cost
;; two full runs here and buy nothing on Chez, but the Julia counterpart needs
;; them: one warm-up leaves the FIRST problem in the file still paying for
;; compilation inside the timed loop (it measured 2.4x slower than the same
;; problem does once something else has been run first), and the two harnesses
;; have to have the same shape for the numbers to be comparable.
(define timeit-problem
  (lambda (name iterations thunk)
    (thunk)
    (let ((result (thunk)))
      (let* ((t0 (real-time))
             (final (let loop ((i 0) (last result))
                      (if (>= i iterations) last (loop (+ i 1) (thunk)))))
             (t1 (real-time)))
        (printf "PROB\t~a\t~a\t~a\t~a\t~a\t~a~%"
          name iterations (secs (- t1 t0))
          (1st final) (2nd final) (3rd final))))))

(define ordinary-problem
  (lambda (i m t seed limit)
    (lambda ()
      (tell *memory* 'clear)
      (let ((outcome (run-problem i m t seed limit)))
        (list outcome *codelet-count* *temperature*)))))

(define justify-problem
  (lambda (i m t a seed limit)
    (lambda ()
      (tell *memory* 'clear)
      (let ((outcome (run-justify-problem i m t a seed limit)))
        (list outcome *codelet-count* *temperature*)))))

;; A whole run before any timing starts, matching the Julia counterpart, which
;; needs it: its per-problem warm-ups alone left the FIRST problem in the file
;; absorbing residual compilation and reading ~3x slow. Costs Chez two runs and
;; buys it nothing, but the two harnesses must have the same shape.
((ordinary-problem 'abc 'abd 'ijk 99 2000))
((justify-problem 'abc 'abd 'ijk 'ijl 98 2000))

;;--- ordinary runs ----------------------------------------------------------
(timeit-problem "abc:abd::ijk:?"     5 (ordinary-problem 'abc 'abd 'ijk 11 5000))
(timeit-problem "abc:abd::iijjkk:?"  5 (ordinary-problem 'abc 'abd 'iijjkk 12 5000))
(timeit-problem "abc:cba::pqrs:?"    5 (ordinary-problem 'abc 'cba 'pqrs 13 5000))
(timeit-problem "abc:abd::xyz:?"     5 (ordinary-problem 'abc 'abd 'xyz 14 5000))
(timeit-problem "abc:abd::mrrjjj:?"  5 (ordinary-problem 'abc 'abd 'mrrjjj 15 5000))
(timeit-problem "mrrjjj:mrrkkk::xyz:?" 5 (ordinary-problem 'mrrjjj 'mrrkkk 'xyz 16 5000))

;;--- justify mode -----------------------------------------------------------
(timeit-problem "abc:abd::ijk:ijl"   5 (justify-problem 'abc 'abd 'ijk 'ijl 21 5000))
(timeit-problem "abc:cba::pqrs:srqp" 5 (justify-problem 'abc 'cba 'pqrs 'srqp 22 5000))
(timeit-problem "abc:abd::mrrjjj:mrrjjjj" 5 (justify-problem 'abc 'abd 'mrrjjj 'mrrjjjj 23 5000))
