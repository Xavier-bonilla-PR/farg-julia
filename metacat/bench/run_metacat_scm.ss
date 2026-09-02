;; Reference-implementation runner: runs one Metacat problem headless and
;; prints a canonical result block.
;;
;;   scheme --script metacat/bench/run_metacat_scm.ss <initial> <modified> <target> <seed> [limit]

(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")   ;; must precede the model
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(let* ((args (command-line-arguments))
       (initial (string->symbol (list-ref args 0)))
       (modified (string->symbol (list-ref args 1)))
       (target (string->symbol (list-ref args 2)))
       (seed (string->number (list-ref args 3)))
       (limit (if (> (length args) 4) (string->number (list-ref args 4)) 100000))
       (outcome (run-problem initial modified target seed limit)))
  (printf "OUTCOME\t~a\tCODELETS\t~a\tTEMP\t~a~%" outcome *codelet-count* *temperature*)
  (for-each
    (lambda (a)
      (printf "ANSWER\t~a\t~a\t~a\t~a~%"
              (tell a 'problem-print-name)
              (tell a 'get-answer-print-name)
              (tell a 'get-quality)
              (tell a 'get-temperature)))
    (tell *memory* 'get-answers)))
