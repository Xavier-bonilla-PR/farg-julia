;; Reads rules off the horizontal bridges.
;;
;; A rule is not composed; it is ABSTRACTED. The probe therefore has to build a
;; real workspace first — bonds, groups and top bridges, through the real
;; coderack — and only then run the abstraction machinery over what the model
;; happened to perceive. Every stage is dumped: the change descriptions read off
;; the bridges, what survives the redundancy filter, the rule-clause templates
;; those are grouped into, and the rule finally instantiated from them, applied
;; to the initial string to see whether it works.
;;
;; Abstraction is stochastic at almost every step, so each workspace is
;; abstracted from repeatedly against one seeded stream.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define sn (lambda (n) (if (exists? n) (tell n 'get-short-name) "*")))
(define yn (lambda (b) (if b "y" "n")))

(define object-tag
  (lambda (o)
    (if (workspace-string? o)
      (format "string:~a" (tell o 'get-string-type))
      (tell o 'ascii-name))))

(define seed-rack
  (lambda ()
    (let loop ((k 0))
      (when (< k 3)
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%))
        (tell *coderack* 'post
          (tell group-scout:whole-string 'make-codelet %low-urgency%))
        (tell *coderack* 'post
          (tell top-down-group-scout:category 'make-codelet %low-urgency%
            plato-succgrp *workspace*))
        (tell *coderack* 'post
          (tell top-down-group-scout:category 'make-codelet %low-urgency%
            plato-samegrp *workspace*))
        (tell *coderack* 'post
          (tell bottom-up-bridge-scout 'make-codelet %medium-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-bridge-scout 'make-codelet %medium-urgency%))
        (tell *coderack* 'post
          (tell important-object-bridge-scout 'make-codelet %medium-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-description-scout 'make-codelet %very-low-urgency%))
        (loop (+ k 1))))))

;;------------------------------------ printing ------------------------------------

(define print-change-description
  (lambda (cd)
    (if (tell cd 'intrinsic?)
      (printf "  CD\tintrinsic\t~a\t~a\t~a\t~a\t~a\t~a~%"
        (object-tag (tell cd 'get-reference-object))
        (tell cd 'get-scope)
        (sn (tell cd 'get-dimension))
        (sn (tell cd 'get-descriptor1))
        (sn (tell cd 'get-descriptor2))
        (map sn (tell cd 'get-descriptors)))
      (printf "  CD\textrinsic\t~a\t~a\tsubswap=~a~%"
        (map object-tag (tell cd 'get-reference-objects))
        (sn (tell cd 'get-dimension))
        (yn (tell cd 'subobjects-swap?))))))

(define print-template
  (lambda (t)
    (if (intrinsic-clause? t)
      (begin
        (printf "  TMPL\tintrinsic\t~a~%" (object-tag (2nd t)))
        (for* each ct in (3rd t) do
          (printf "    CT\t~a\t~a\t~a~%" (1st ct) (sn (2nd ct)) (map sn (3rd ct)))))
      (printf "  TMPL\textrinsic\t~a\t~a~%"
        (map object-tag (2nd t)) (map sn (3rd t))))))

(define print-clause
  (lambda (rc)
    (record-case rc
      (verbatim (lcs) (printf "  RC\tVERBATIM\t~a~%" (map nm lcs)))
      (intrinsic (ods changes)
        (printf "  RC\tCHANGE\t~a~%" (format-object-description (1st ods)))
        (for* each c in changes do
          (printf "    CH\t(~a ~a ~a)~%" (1st c) (sn (2nd c)) (sn (3rd c)))))
      (extrinsic (ods dims)
        (printf "  RC\tSWAP\t~a\t~a~%"
          (map format-object-description ods) (map sn dims))))))

(define snag '())
(define record-snag (lambda (r) (set! snag (cons (1st r) snag)) 'done))

;;-------------------------------------- probe --------------------------------------

(define abstract-once
  (lambda (trial describable)
    (printf " TRIAL\t~a~%" trial)
    (let* ((all-cds (abstract-change-descriptions describable))
           (final-cds (remove-redundant-change-descriptions all-cds)))
      (printf "  NCD\tall=~a\tfinal=~a~%" (length all-cds) (length final-cds))
      (for* each cd in all-cds do (print-change-description cd))
      (printf "  ---kept---~%")
      (for* each cd in final-cds do (print-change-description cd))
      (let ((templates
              (sort-templates
                (map change-descriptions->rule-clause-template
                  (partition
                    (lambda (c1 c2)
                      (and (tell c1 'same-change-type? c2)
                           (tell c1 'same-reference-objects? c2)))
                    final-cds)))))
        (printf "  NTMPL\t~a~%" (length templates))
        (for* each t in templates do (print-template t))
        (if (not (possible-to-instantiate? templates))
          (printf "  INSTANTIABLE\tn~%")
          (begin
            (printf "  INSTANTIABLE\ty~%")
            (let* ((clauses (map instantiate-rule-clause-template templates))
                   (rule (make-rule 'top clauses)))
              (for* each rc in clauses do (print-clause rc))
              (tell rule 'set-quality-values)
              (printf "  RULEQ\tunif=~a\tabst=~a\tsucc=~a\tintr=~a\tqual=~a\tchar=~a~%"
                (tell rule 'get-uniformity) (tell rule 'get-abstractness)
                (tell rule 'get-succinctness) (tell rule 'get-intrinsic-quality)
                (tell rule 'get-quality) (tell rule 'get-characterization))
              (for* each line in (tell rule 'get-english-transcription) do
                (printf "  EN\t|~a|~%" line))
              (set! snag '())
              (let ((result (apply-rule rule *initial-string* record-snag)))
                (printf "  APPLIED\t~a\t~a~%"
                  (if (exists? result) (format "ok:~a" (length result)) "failed")
                  (reverse snag))
                (printf "  IMAGE\t~a~%"
                  (apply string-append
                    (tell-all (tell *initial-string* 'generate-image-letters)
                      'get-lowercase-name)))
                (printf "  WORKS\t~a~%"
                  (yn (and (exists? result)
                           (equal? (tell *initial-string* 'generate-image-letters)
                                   (tell *modified-string* 'get-letter-categories)))))
                (tell *initial-string* 'reset-string-image)))))))))

(define probe
  (lambda (i m t seed n temp trials)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp trials)
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
                             plato-string-position-category plato-successor
                             plato-predecessor plato-sameness plato-bond-facet
                             plato-bond-category plato-group-category
                             plato-direction-category plato-left plato-right
                             plato-samegrp plato-succgrp plato-predgrp
                             plato-alphabetic-position-category plato-length) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    (seed-rack)
    (let loop ((c 0))
      (when (and (< c n) (not (tell *coderack* 'empty?)))
        (if* (and (> c 0) (zero? (modulo c %update-cycle-length%)))
          (seed-rack))
        (set! *codelet-count* c)
        (tell (tell *coderack* 'choose-codelet) 'run)
        (update-workspace-values)
        (loop (+ c 1))))
    (let* ((top-bridges (reverse (tell *workspace* 'get-bridges 'top)))
           (describable (filter rule-describable-bridge? top-bridges)))
      (printf "BRIDGES\ttop=~a\tdescribable=~a~%"
        (length top-bridges) (length describable))
      (for* each b in top-bridges do
        (printf " B\t~a\t~a\tdescribable=~a\tslippages=~a\tstrposopp=~a~%"
          (object-tag (tell b 'get-object1))
          (object-tag (tell b 'get-object2))
          (yn (rule-describable-bridge? b))
          (length (tell b 'get-non-symmetric-non-bond-slippages))
          (yn (tell b 'StrPosCtgy:Opposite-slippage? ))))
      ;; the cluster predicates, which decide what can be lifted
      (let ((clusters (partition same-left-enclosing-objects? describable)))
        (printf "CLUSTERS\t~a~%" (length clusters))
        (for* each cl in clusters do
          (printf " CL\t~a\tleft=~a\tspansL=~a\tcommonR=~a\tspansR=~a\tschemas=~a~%"
            (map (lambda (b) (object-tag (tell b 'get-object1))) cl)
            (object-tag (get-left-enclosing-object cl))
            (yn (spans-left-side? cl))
            (yn (common-right-enclosing-object? cl))
            (yn (and (common-right-enclosing-object? cl) (spans-right-side? cl)))
            (map (lambda (s)
                   (format "~a:~a:~a:~a" (sn (schema-dim s)) (sn (schema-desc1 s))
                     (sn (schema-relation s)) (sn (schema-desc2 s))))
              (get-common-change-schemas cl)))
          (for* each sw in (get-all-swaps cl) do
            (printf " SWAP\t~a\t~a\t~a~%"
              (map object-tag (swap-objs sw)) (sn (swap-dim sw))
              (map sn (swap-descs sw))))))
      (let loop ((k 1))
        (when (<= k trials)
          (abstract-once k describable)
          (loop (+ k 1)))))))

(probe 'abc 'abd 'ijk 91 400 40 6)
(probe 'abc 'abd 'ijk 92 700 20 6)
(probe 'aabc 'aabd 'ijkk 93 700 30 6)
(probe 'abc 'cba 'pqrs 94 900 30 10)
(probe 'mrrjjj 'mrrkkk 'xyz 95 900 30 6)
(probe 'eqe 'qqq 'abc 96 700 50 6)
;; strings chosen for the extrinsic path: a modified string that trades
;; descriptors with the initial one is what an abstracted SWAP is read off
(probe 'aabb 'bbaa 'ijkk 97 1200 30 10)
(probe 'abcd 'abdc 'xyz 98 1200 25 10)
(probe 'abcde 'abcdf 'ijklm 99 1200 35 8)
(probe 'aabbcc 'ccbbaa 'mrrjjj 100 1400 30 10)
