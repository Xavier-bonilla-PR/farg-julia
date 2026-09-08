;; Reference-implementation runner: runs one Metacat problem headless and
;; prints a canonical result block.
;;
;;   scheme --script metacat/bench/run_metacat_scm.ss <initial> <modified> <target> <seed> [limit]
;;
;; Add a fifth string to run in JUSTIFY MODE -- the configuration where Metacat
;; is given the answer as well as the problem and asked why:
;;
;;   scheme --script metacat/bench/run_metacat_scm.ss abc abd mrrjjj 23 5000 --answer mrrjjjj
;;
;; metacat/bench/run_metacat_jl.jl is the Julia port's counterpart and prints
;; the same block, so the two can be diffed directly.
;;
;; The outcome is `answer` when a codelet reported one, `give-up` when a jootser
;; decided there was nothing better to try, and `limit` when the codelet budget
;; ran out.

(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")   ;; must precede the model
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

;; the value following `flag`, or #f when the flag is absent
(define option-after
  (lambda (flag args)
    (let loop ((l args))
      (cond ((or (null? l) (null? (cdr l))) #f)
            ((string=? (car l) flag) (cadr l))
            (else (loop (cdr l)))))))

(let* ((args (command-line-arguments))
       (initial (string->symbol (list-ref args 0)))
       (modified (string->symbol (list-ref args 1)))
       (target (string->symbol (list-ref args 2)))
       (seed (string->number (list-ref args 3)))
       (limit (if (and (> (length args) 4)
                       (string->number (list-ref args 4)))
                (string->number (list-ref args 4))
                100000))
       (answer (option-after "--answer" args))
       (outcome (if answer
                  (run-justify-problem initial modified target
                                       (string->symbol answer) seed limit)
                  (run-problem initial modified target seed limit))))
  (printf "OUTCOME\t~a\tCODELETS\t~a\tTEMP\t~a~%" outcome *codelet-count* *temperature*)
  (for-each
    (lambda (a)
      (printf "ANSWER\t~a\t~a\t~a\t~a~%"
              (tell a 'problem-print-name)
              (tell a 'get-answer-print-name)
              (tell a 'get-quality)
              (tell a 'get-temperature)))
    (tell *memory* 'get-answers)))
