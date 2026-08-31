;; Canonical dump of concept mappings built between letters of two strings.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define num->str
  (lambda (v)
    (if (exact? v)
      (if (integer? v) (number->string v)
        (format "~a/~a" (numerator v) (denominator v)))
      (number->string v))))
(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))

(define probe
  (lambda (i m t)
    (printf "PROBLEM\t~a\t~a\t~a~%" i m t)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (for* each obj in (tell *workspace* 'get-objects) do
      (for* each descriptor in (tell-all (tell obj 'get-descriptions) 'get-descriptor)
        do (tell descriptor 'set-activation %max-activation%)))
    ;; also fully activate the description types so relevance is exercised
    (for* each node in (list plato-object-category plato-letter-category
                             plato-string-position-category) do
      (tell node 'set-activation %max-activation%))
    (update-workspace-values)
    ;; every description of every initial letter against every target letter
    (for* each o1 in (tell *initial-string* 'get-objects) do
      (for* each o2 in (tell *target-string* 'get-objects) do
        (for* each d1 in (tell o1 'get-descriptions) do
          (for* each d2 in (tell o2 'get-descriptions) do
            (let ((cm (make-concept-mapping
                        o1 (tell d1 'get-description-type) (tell d1 'get-descriptor)
                        o2 (tell d2 'get-description-type) (tell d2 'get-descriptor))))
              (printf "CM\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
                (tell o1 'ascii-name) (tell o2 'ascii-name)
                (tell cm 'print-name) (tell cm 'english-name)
                (nm (tell cm 'get-label))
                (yn (tell cm 'identity?)) (yn (tell cm 'slippage?))
                (yn (tell cm 'relevant?)) (yn (tell cm 'distinguishing?))
                (yn (tell cm 'identity/opposite-mapping?))
                (tell cm 'get-degree-of-assoc)
                (num->str (tell cm 'get-conceptual-depth))
                (tell cm 'get-strength)
                (tell cm 'get-slippability)
                (tell cm 'long-name)))))))))

(probe 'abc 'abd 'ijk)
(probe 'abc 'cba 'xyz)
(probe 'abc 'abd 'a)
