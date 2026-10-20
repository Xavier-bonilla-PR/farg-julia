;; Prints a canonical trace of Metacat's numeric/stochastic helpers so the
;; Julia port can be diffed against it. Values are tagged E (exact) or F
;; (inexact) so the comparator can check exactness as well as magnitude.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")

(define emit
  (lambda (label v)
    (printf "~a\t~a\t~a~%" label (if (exact? v) "E" "F") (number->string v))))

(define emit-bool (lambda (label v) (printf "~a\tB\t~a~%" label (if v "t" "f"))))

;; temp-adjusted-probability over a grid of temperatures and probabilities
(for-each
  (lambda (temp)
    (set! *temperature* temp)
    (for-each
      (lambda (p) (emit (format "tap/~a/~a" temp p) (temp-adjusted-probability p)))
      '(0.0 0.001 0.01 0.05 0.2 0.5 0.6 0.9 0.999 1.0)))
  '(0 1 19 36 50 64 75 100))

;; temp-adjusted-values
(for-each
  (lambda (temp)
    (set! *temperature* temp)
    (for-each (lambda (v) (emit (format "tav/~a/~a" temp v) v))
      (temp-adjusted-values '(0 1 25 50 75 100))))
  '(0 25 50 75 100))

;; exactness-preserving arithmetic
(for-each (lambda (n) (emit (format "pct/~a" n) (% n))) '(0 1 25 50 100 33 7))
(for-each (lambda (n) (emit (format "sqrt/~a" n) (sqrt n))) '(0 1 4 25 99 100 81))
(for-each (lambda (n) (emit (format "round/~a/~a" (numerator n) (denominator n)) (round n)))
  '(5/2 7/2 -5/2 1/3 99/100))

;; stochastic helpers, all sharing one seeded stream
(random-seed 20250831)
(let loop ((i 0))
  (when (< i 25)
    (emit-bool (format "prob/~a" i) (prob? 0.3))
    (loop (+ i 1))))
(let loop ((i 0))
  (when (< i 25)
    (emit (format "fuzz/~a" i) (~ 40))
    (loop (+ i 1))))
(let loop ((i 0))
  (when (< i 25)
    (emit (format "pick/~a" i) (random-pick '(10 20 30 40 50)))
    (loop (+ i 1))))
(let loop ((i 0))
  (when (< i 25)
    (emit (format "spick/~a" i) (stochastic-pick '(10 20 30 40) '(1 5 2 8)))
    (loop (+ i 1))))
(let loop ((i 0))
  (when (< i 25)
    (emit (format "ssel/~a" i) (2nd (stochastic-select '((3 100) (1 200) (6 300)))))
    (loop (+ i 1))))
(let loop ((i 0))
  (when (< i 10)
    (printf "sfilter/~a\tL\t~a~%" i
      (stochastic-filter (lambda (x) (% x)) '(10 30 50 70 90)))
    (loop (+ i 1))))
