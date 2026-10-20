;; The three rule codelets: rule-scout, rule-evaluator, rule-builder.
;;
;; They are driven DIRECTLY rather than through the coderack, because
;; rule-builder posts an answer-finder — that is answers.ss, which is not
;; ported — and a codelet posted at extremely-high urgency would be chosen
;; almost at once. Driving them by hand tests each codelet's own behaviour, the
;; randomness it consumes and what it posts, while leaving the answer codelet
;; sitting on the rack unrun. The rack's contents are dumped after every step,
;; so a wrong post shows up.
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

(define rack-summary
  (lambda ()
    (format "~a" (tell *coderack* 'get-num-of-codelets))))

;; the codelets the rack is holding, by type, so a post shows up
(define rack-types
  (lambda ()
    (map (lambda (c) (tell c 'get-codelet-type-name))
      (tell *coderack* 'get-all-codelets))))

(define print-clause
  (lambda (rc)
    (record-case rc
      (verbatim (lcs) (printf "    RC\tVERBATIM\t~a~%" (map nm lcs)))
      (intrinsic (ods changes)
        (printf "    RC\tCHANGE\t~a~%" (format-object-description (1st ods)))
        (for* each c in changes do
          (printf "      CH\t(~a ~a ~a)~%" (1st c) (sn (2nd c)) (sn (3rd c)))))
      (extrinsic (ods dims)
        (printf "    RC\tSWAP\t~a\t~a~%"
          (map format-object-description ods) (map sn dims))))))

(define print-rule
  (lambda (label rule)
    (printf "   RULE\t~a\t~a\tlevel=~a\tstamp=~a~%" label
      (tell rule 'get-rule-type) (tell rule 'get-proposal-level)
      (tell rule 'get-time-stamp))
    (for* each rc in (tell rule 'get-rule-clauses) do (print-clause rc))
    (printf "   RQ\tqual=~a\tstr=~a\tchar=~a\tworks=~a\tsupported=~a\tsupport=~a~%"
      (tell rule 'get-quality) (tell rule 'get-strength)
      (tell rule 'get-characterization) (yn (tell rule 'currently-works?))
      (yn (tell rule 'supported?)) (tell rule 'get-degree-of-support))
    (printf "   RSUP\t~a~%"
      (map (lambda (b)
             (format "~a->~a" (object-tag (tell b 'get-object1))
               (object-tag (tell b 'get-object2))))
        (tell rule 'get-supporting-horizontal-bridges)))
    (printf "   RTAG\t~a~%"
      (map (lambda (tagged)
             (format "~a:~a" (yn (1st tagged))
               (map (lambda (b) (object-tag (tell b 'get-object1))) (2nd tagged))))
        (tell rule 'get-tagged-supporting-horizontal-bridges)))
    (for* each line in (tell rule 'get-english-transcription) do
      (printf "   EN\t|~a|~%" line))))

;; Rule codelets post their successors, so the probe pulls each newly posted
;; codelet back off the rack and runs it by hand: the pipeline one stage at a
;; time, with what each stage did dumped in between. Codelets are never removed
;; from the rack — the rack has no single-codelet delete — so the ones already
;; seen are remembered instead.
(define seen '())

(define new-codelets-of-type
  (lambda (type-name)
    (let ((found
            (filter
              (lambda (c)
                (and (eq? (tell c 'get-codelet-type-name) type-name)
                     (not (memq c seen))))
              (tell *coderack* 'get-all-codelets))))
      (set! seen (append found seen))
      found)))

(define drive-pipeline
  (lambda (round)
    (printf "  ROUND\t~a\track=~a~%" round (rack-summary))
    (let ((before (tell *coderack* 'get-num-of-codelets)))
      (tell (tell rule-scout 'make-codelet %medium-urgency%) 'run)
      (printf "  SCOUT\tposted=~a\track=~a~%"
        (- (tell *coderack* 'get-num-of-codelets) before) (rack-summary)))
    (let ((evaluators (new-codelets-of-type 'rule-evaluator)))
      (if (null? evaluators)
        (printf "  NOEVAL~%")
        (for* each ec in evaluators do
          (let ((proposed (tell ec 'get-argument 0)))
            (print-rule "proposed" proposed)
            (let ((before (tell *coderack* 'get-num-of-codelets)))
              (tell ec 'run)
              (printf "  EVAL\tposted=~a\track=~a~%"
                (- (tell *coderack* 'get-num-of-codelets) before) (rack-summary)))))))
    (let ((builders (new-codelets-of-type 'rule-builder)))
      (if (null? builders)
        (printf "  NOBUILD~%")
        (for* each bc in builders do
          (let ((proposed (tell bc 'get-argument 0)))
            (print-rule "evaluated" proposed)
            (let ((before (tell *coderack* 'get-num-of-codelets)))
              (tell bc 'run)
              (printf "  BUILD\tposted=~a\track=~a\tlevel=~a~%"
                (- (tell *coderack* 'get-num-of-codelets) before) (rack-summary)
                (tell proposed 'get-proposal-level)))))))
    (printf "  FINDERS\t~a~%" (length (new-codelets-of-type 'answer-finder)))
    (printf "  RULES\ttop=~a~%" (length (tell *workspace* 'get-rules 'top)))
    (for* each r in (reverse (tell *workspace* 'get-rules 'top)) do
      (print-rule "built" r))))

;;-------------------------------------- probe --------------------------------------

(define probe
  (lambda (i m t seed n temp rounds)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp rounds)
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
    (set! seen '())
    (seed-rack)
    (let loop ((c 0))
      (when (and (< c n) (not (tell *coderack* 'empty?)))
        (if* (and (> c 0) (zero? (modulo c %update-cycle-length%)))
          (seed-rack))
        (set! *codelet-count* c)
        (tell (tell *coderack* 'choose-codelet) 'run)
        (update-workspace-values)
        (loop (+ c 1))))
    (tell *workspace* 'check-if-rules-possible)
    (printf "POSSIBLE\t~a~%" (tell *workspace* 'get-possible-rule-types))
    (printf "BRIDGES\ttop=~a\tdescribable=~a~%"
      (length (tell *workspace* 'get-bridges 'top))
      (length (filter rule-describable-bridge? (tell *workspace* 'get-bridges 'top))))
    (let loop ((k 1))
      (when (<= k rounds)
        (drive-pipeline k)
        (loop (+ k 1))))))

(probe 'abc 'abd 'ijk 201 400 40 20)
(probe 'abc 'abd 'ijk 202 700 20 20)
(probe 'abc 'cba 'pqrs 203 900 30 20)
(probe 'aabc 'aabd 'ijkk 204 700 30 20)
(probe 'mrrjjj 'mrrkkk 'xyz 205 900 30 20)
(probe 'aabb 'bbaa 'ijkk 206 1200 30 20)
(probe 'abcd 'abdc 'xyz 207 1200 25 20)
(probe 'eqe 'qqq 'abc 208 700 50 20)
