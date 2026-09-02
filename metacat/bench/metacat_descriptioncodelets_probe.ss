;; Runs the description codelet pipeline through the real coderack for N
;; codelets, dumping every codelet run and the descriptions that survive.
;;
;; The rack is seeded with both scouts: bottom-up ones, which slide along a
;; property link from a description an object already has, and top-down ones
;; for a named description type, over the whole workspace and over one string.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))

;; raw importance is an exact rational whenever the object sits inside a group
(define num
  (lambda (v)
    (if (integer? v)
      (number->string v)
      (format "~a/~a" (numerator v) (denominator v)))))

(define probe
  (lambda (i m t seed n temp)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (tell *themespace* 'initialize)
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (for* each obj in (tell *workspace* 'get-objects) do
      (for* each descriptor in (tell-all (tell obj 'get-descriptions) 'get-descriptor)
        do (tell descriptor 'set-activation %max-activation%)))
    (for* each node in (list plato-object-category plato-letter-category
                             plato-string-position-category
                             plato-alphabetic-position-category
                             plato-length plato-alphabetic-first plato-alphabetic-last) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    (let loop ((k 0))
      (when (< k 10)
        (tell *coderack* 'post
          (tell bottom-up-description-scout 'make-codelet %very-low-urgency%))
        (tell *coderack* 'post
          (tell top-down-description-scout 'make-codelet %low-urgency%
            plato-alphabetic-position-category *workspace*))
        (tell *coderack* 'post
          (tell top-down-description-scout 'make-codelet %medium-urgency%
            plato-string-position-category *target-string*))
        (loop (+ k 1))))
    (let loop ((c 0))
      (when (and (< c n) (not (tell *coderack* 'empty?)))
        (set! *codelet-count* c)
        (let ((codelet (tell *coderack* 'choose-codelet)))
          (printf "RUN\t~a\t~a\t~a\t~a~%" c
            (tell codelet 'get-codelet-type-name)
            (round (tell codelet 'get-relative-urgency))
            (tell *coderack* 'get-num-of-codelets))
          (tell codelet 'run))
        (update-workspace-values)
        (loop (+ c 1))))
    (for-each
      (lambda (string)
        (for-each
          (lambda (o)
            (for-each
              (lambda (d)
                (printf "DESCR\t~a\t~a\t~a\t~a\t~a~%"
                  (tell string 'get-string-type) (tell o 'ascii-name)
                  (tell d 'print-name) (tell d 'get-proposal-level)
                  (tell d 'get-strength)))
              (tell o 'get-all-descriptions))
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name) (num (tell o 'get-raw-importance))
              (tell o 'get-relative-importance) (tell o 'get-average-salience)))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a~%" (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)))

(probe 'abc 'abd 'ijk 2001 60 50)
(probe 'abc 'abd 'mrrjjj 2002 90 30)
(probe 'abcde 'abcdf 'pqrst 2003 120 80)
