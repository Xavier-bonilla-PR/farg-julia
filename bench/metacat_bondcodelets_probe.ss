;; Runs the bond codelet pipeline through the real coderack for N codelets,
;; dumping every codelet run and the resulting workspace state.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))

(define probe
  (lambda (i m t seed n temp)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (for* each obj in (tell *workspace* 'get-objects) do
      (for* each descriptor in (tell-all (tell obj 'get-descriptions) 'get-descriptor)
        do (tell descriptor 'set-activation %max-activation%)))
    (for* each node in (list plato-object-category plato-letter-category
                             plato-string-position-category plato-successor
                             plato-predecessor plato-sameness plato-bond-facet
                             plato-bond-category plato-length) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    ;; seed the rack with bottom-up bond scouts only
    (let loop ((k 0))
      (when (< k 20)
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%))
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
          (lambda (b)
            (printf "BOND\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type)
              (tell (tell b 'get-left-object) 'ascii-name)
              (tell (tell b 'get-right-object) 'ascii-name)
              (nm (tell b 'get-bond-category)) (nm (tell b 'get-direction))
              (nm (tell b 'get-bond-facet)) (tell b 'get-strength)))
          (reverse (tell string 'get-bonds)))
        (for-each
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name) (tell o 'get-intra-string-unhappiness)
              (tell o 'get-intra-string-salience) (tell o 'get-relative-importance)))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a~%" (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)))

(probe 'abc 'abd 'ijk 1234 60 50)
(probe 'abc 'abd 'mrrjjj 5678 80 40)
(probe 'abcde 'abcdf 'pqrst 9012 100 70)
