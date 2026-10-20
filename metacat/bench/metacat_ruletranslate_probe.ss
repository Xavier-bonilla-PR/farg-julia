;; Rule translation: re-reading a top rule in the target string's terms.
;;
;; The workspace is built the same way the rulecodelets probe builds it — run
;; the coderack for a while, then drive the rule codelets by hand until a top
;; rule exists — because a rule can only be translated across vertical bridges
;; the model actually perceived. Then the rule is translated REPEATEDLY from
;; the same state: translation is stochastic (a 0.4 draw per dimension, plus a
;; draw per coattail candidate), so one attempt would test one path through it.
;;
;; Everything the translation touches is dumped: the translated clauses, the
;; slippage log with its coattails, the supporting bridges and the reference
;; objects on both sides.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define sn (lambda (n) (if (exists? n) (tell n 'get-short-name) "*")))
(define yn (lambda (b) (if b "y" "n")))

(define join
  (lambda (strings)
    (if (null? strings)
      "-"
      (let loop ((l (rest strings)) (acc (1st strings)))
        (if (null? l) acc (loop (rest l) (string-append acc "," (1st l))))))))

(define object-tag
  (lambda (o)
    (if (workspace-string? o)
      (format "string:~a" (tell o 'get-string-type))
      (tell o 'ascii-name))))

(define od-tag
  (lambda (od)
    (format "(~a ~a ~a)"
      (if (symbol? (1st od)) (1st od) (sn (1st od)))
      (sn (2nd od)) (sn (3rd od)))))

(define cm-tag (lambda (cm) (tell cm 'print-name)))

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

(define print-clause
  (lambda (tag rc)
    (record-case rc
      (verbatim (lcs) (printf "~a\tVERBATIM\t~a~%" tag (join (map nm lcs))))
      (intrinsic (ods changes)
        (printf "~a\tCHANGE\t~a\t~a~%" tag (od-tag (1st ods))
          (join (map (lambda (c)
                       (format "(~a ~a ~a)" (1st c) (sn (2nd c)) (sn (3rd c))))
                  changes))))
      (extrinsic (ods dims)
        (printf "~a\tSWAP\t~a\t~a~%" tag
          (join (map od-tag ods)) (join (map sn dims)))))))

(define print-rule
  (lambda (tag rule)
    (printf "~a\tTYPE\t~a\ttranslated=~a\tdir=~a~%" tag
      (tell rule 'get-rule-type) (yn (tell rule 'translated?))
      (tell rule 'get-translation-direction))
    (for* each rc in (tell rule 'get-rule-clauses) do (print-clause tag rc))
    (for* each line in (tell rule 'get-english-transcription) do
      (printf "~a\tEN\t|~a|~%" tag line))))

(define print-log
  (lambda (tag log)
    (printf "~a\tDIRECT\t~a~%" tag
      (join (map cm-tag (tell log 'get-directly-applied-slippages))))
    (printf "~a\tCOAT\t~a~%" tag
      (join (map cm-tag (tell log 'get-coattail-slippages))))
    (printf "~a\tCOATIND\t~a~%" tag
      (join (map cm-tag (tell log 'get-coattail-inducing-slippages))))
    (printf "~a\tAPPLIED\t~a~%" tag
      (join (map cm-tag (tell log 'get-applied-slippages))))
    (printf "~a\tLOGBR\t~a~%" tag
      (join (map (lambda (b)
                   (format "~a>~a" (object-tag (tell b 'get-object1))
                     (object-tag (tell b 'get-object2))))
              (tell log 'get-slippage-bridges))))
    ;; the highlight lookup is pure bookkeeping over the same lists
    (for* each s in (tell log 'get-directly-applied-slippages) do
      (printf "~a\tHIGH\t~a\t~a~%" tag (cm-tag s)
        (let ((h (tell log 'get-slippage-to-highlight s)))
          (if (exists? h) (cm-tag h) "-"))))))

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

;; Drive scout -> evaluator -> builder by hand until a top rule is built.
(define build-a-top-rule
  (lambda (rounds)
    (let loop ((k 1))
      (when (and (<= k rounds) (null? (tell *workspace* 'get-rules 'top)))
        (tell (tell rule-scout 'make-codelet %medium-urgency%) 'run)
        (for* each ec in (new-codelets-of-type 'rule-evaluator) do (tell ec 'run))
        (for* each bc in (new-codelets-of-type 'rule-builder) do (tell bc 'run))
        (loop (+ k 1))))
    (let ((rules (tell *workspace* 'get-rules 'top)))
      (if (null? rules) #f (1st rules)))))

(define probe
  (lambda (i m t seed n temp rounds attempts)
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
    ;; the vertical bridges are what translation slides along, so pin them down
    (printf "VBRIDGES\t~a~%" (length (tell *workspace* 'get-bridges 'vertical)))
    (for* each b in (reverse (tell *workspace* 'get-bridges 'vertical)) do
      (printf "VB\t~a>~a\tslip=~a\tnonsym=~a\tsym=~a\tbond=~a~%"
        (object-tag (tell b 'get-object1)) (object-tag (tell b 'get-object2))
        (join (map cm-tag (tell b 'get-slippages)))
        (join (map cm-tag (tell b 'get-non-symmetric-slippages)))
        (join (map cm-tag (tell b 'get-symmetric-slippages)))
        (join (map cm-tag (tell b 'get-bond-slippages)))))
    (let ((rule (build-a-top-rule rounds)))
      (if (not rule)
        (printf "NORULE~%")
        (begin
          (print-rule "RULE" rule)
          ;; reference objects of the ORIGINAL rule, which translation reads
          (printf "REFOBJ\t~a~%"
            (join (map object-tag
                    (tell *initial-string* 'get-all-reference-objects rule))))
          (let loop ((a 1))
            (when (<= a attempts)
              (let ((result (translate rule)))
                (if (not result)
                  (printf "T~a\tFAILED~%" a)
                  (let ((tag (format "T~a" a)))
                    (print-rule tag (1st result))
                    (printf "~a\tSUPBR\t~a~%" tag
                      (join (map (lambda (b)
                                   (format "~a>~a" (object-tag (tell b 'get-object1))
                                     (object-tag (tell b 'get-object2))))
                              (2nd result))))
                    (print-log tag (3rd result))
                    (printf "~a\tSUPGRP\t~a~%" tag
                      (join (map object-tag (4th result))))
                    (printf "~a\tFROMREF\t~a~%" tag
                      (join (map object-tag (5th result))))
                    (printf "~a\tTOREF\t~a~%" tag
                      (join (map object-tag (6th result))))
                    (printf "~a\tVALID\t~a~%" tag
                      (join (map (lambda (rc) (yn (valid-rule-clause? rc)))
                              (tell (1st result) 'get-rule-clauses))))
                    ;; The redundant-ObjCtgy pass, over the translated clauses.
                    ;; NB: verbatim clauses are skipped -- its record-case has
                    ;; only extrinsic and intrinsic arms and returns void for
                    ;; anything else. Nothing in Metacat calls this procedure at
                    ;; all, so nothing there ever hits that.
                    (for* each rc in
                      (filter-out verbatim-clause? (tell (1st result) 'get-rule-clauses))
                      do
                      (let ((reduced (remove-redundant-ObjCtgy-change rc)))
                        (if (not reduced)
                          (printf "~a\tREDUCED\tnone~%" tag)
                          (print-clause (format "~a\tREDUCED" tag) reduced)))))))
              (loop (+ a 1)))))))))

;; 501 and 502 are the two that reach the COATTAIL branch: a slippage whose
;; label matches a lateral sliplink out of a descriptor it does not map
;; directly, dragging that descriptor along with it. They cost a random draw
;; each, so they also pin down the draw order.
(probe 'abc 'abd 'cba 501 2000 30 40 8)
(probe 'abc 'abd 'cba 502 3000 40 40 8)
(probe 'abc 'abd 'kji 401 2000 30 40 8)
(probe 'abc 'abd 'kji 402 4000 30 40 8)
(probe 'abc 'abd 'mrrjjj 404 3000 30 40 8)
(probe 'abc 'cba 'pqrs 405 3000 30 40 8)
(probe 'aabc 'aabd 'ijkk 406 3000 30 40 8)
(probe 'mrrjjj 'mrrkkk 'xyz 409 3000 30 40 8)
(probe 'abc 'abd 'xyz 410 3000 30 40 8)
(probe 'abcd 'abdc 'xyz 408 3000 25 40 8)
(probe 'abc 'abd 'ijk 412 2000 40 40 8)
