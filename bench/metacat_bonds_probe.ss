;; Builds every possible adjacent bond in each string and dumps its properties,
;; including the stochastic local-density walk.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))

(define probe
  (lambda (i m t seed)
    (printf "PROBLEM\t~a\t~a\t~a\t~a~%" i m t seed)
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
                             plato-predecessor plato-sameness) do
      (tell node 'set-activation %max-activation%))
    (update-workspace-values)
    (random-seed seed)
    ;; build a left-to-right chain of bonds in each string
    (for-each
      (lambda (string)
        (let ((n (tell string 'get-length)))
          (let loop ((p 0))
            (when (< p (sub1 n))
              (let* ((o1 (tell string 'get-letter p))
                     (o2 (tell string 'get-letter (add1 p)))
                     (d1 (tell o1 'get-descriptor-for plato-letter-category))
                     (d2 (tell o2 'get-descriptor-for plato-letter-category))
                     (cat (get-bond-category d1 d2)))
                (if (not (exists? cat))
                  (printf "NOBOND\t~a\t~a\t~a~%" (tell string 'get-string-type)
                    (tell o1 'ascii-name) (tell o2 'ascii-name))
                  (let ((b (make-bond o1 o2 cat plato-letter-category d1 d2)))
                    (build-bond b)
                    (printf "BOND\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
                      (tell string 'get-string-type)
                      (tell o1 'ascii-name) (tell o2 'ascii-name)
                      (nm cat) (nm (tell b 'get-direction))
                      (yn (tell b 'leftmost-in-string?))
                      (yn (tell b 'rightmost-in-string?))
                      (nm (tell b 'get-bond-facet))
                      (tell b 'calculate-internal-strength)))))
              (loop (add1 p))))))
      (list *initial-string* *modified-string* *target-string*))
    ;; now the support/density figures, which depend on the whole chain
    (for-each
      (lambda (string)
        (for-each
          (lambda (b)
            (printf "SUP\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type)
              (tell (tell b 'get-left-object) 'ascii-name)
              (tell (tell b 'get-right-object) 'ascii-name)
              (tell b 'get-num-of-local-supporting-bonds)
              (tell b 'get-local-density)
              (tell b 'get-local-support)))
          (reverse (tell string 'get-bonds))))
      (list *initial-string* *modified-string* *target-string*))
    (update-workspace-values)
    (for-each
      (lambda (string)
        (for-each
          (lambda (b)
            (tell b 'update-strength)
            (printf "STR\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type)
              (tell (tell b 'get-left-object) 'ascii-name)
              (tell (tell b 'get-right-object) 'ascii-name)
              (tell b 'get-strength)
              (tell b 'calculate-external-strength)))
          (reverse (tell string 'get-bonds)))
        (for-each
          (lambda (o)
            (printf "OBJU\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name) (tell o 'get-intra-string-unhappiness)
              (tell o 'get-intra-string-salience)))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))))

(probe 'abc 'abd 'ijk 11)
(probe 'abc 'abd 'mrrjjj 22)
(probe 'abc 'cba 'pqrs 33)
