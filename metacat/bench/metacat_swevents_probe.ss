;; trace.ss slice (C), part 2: the three SELF-WATCHING event types -- answer,
;; clamp and snag -- and the four trace methods deferred with them.
;;
;; Where the workspace events record the model perceiving something, these
;; record it reacting to its own history. Clamp and snag events are the only
;; ones that are ACTIVATED and DEACTIVATED: they do not merely describe a state,
;; they impose one, so the probe dumps the themespace, slipnet and coderack
;; before activating, after activating, and again after deactivating, which is
;; the only way to see that the imposition and its undoing really match.
;;
;; They are also the only events carrying a PROGRESS EVALUATOR, which is how
;; the trace later asks whether the detour was worth taking -- a clamp scores
;; EVENTS since it went up, a snag scores STRUCTURES built since. Those four
;; methods (progress-since-last-clamp, undo-last-clamp, progress-since-last-snag,
;; undo-snag-condition) are exercised against a real trace at the end.
;;
;; The answer event is built the way answer-finder builds one: translate the top
;; rule, make the translated string from the translated rule, and hand the
;; pieces over. Justify mode stays off, so the "bottom rule" is the translated
;; one, which is exactly what a non-justify-mode answer rests on.
;;
;; As in the wsevents probe, *trace* is only read where the probe puts events
;; into it deliberately; the Scheme's live monitors are slice (D).
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

(define cm-tag (lambda (cm) (tell cm 'print-name)))
(define entry-tag (lambda (e) (format "~a/~a" (sn (1st e)) (nm (2nd e)))))
(define bridge-tag
  (lambda (b) (format "~a>~a" (object-tag (tell b 'get-object1))
                 (object-tag (tell b 'get-object2)))))

(define pattern-tag
  (lambda (p)
    (cond
      ((concept-pattern? p)
       (format "concepts[~a]"
         (join (map (lambda (e) (format "~a:~a" (sn (1st e)) (2nd e))) (rest p)))))
      ((codelet-pattern? p)
       (format "codelets[~a]"
         (join (map (lambda (e)
                      (format "~a:~a" (tell (1st e) 'get-codelet-type-name) (2nd e)))
                 (rest p)))))
      (else
        (format "~a[~a]" (1st p) (join (map entry-tag (rest p))))))))

(define count-of
  (lambda (type structures)
    (count (lambda (s) (eq? (tell s 'object-type) type)) structures)))

(define structure-summary
  (lambda (structures)
    (format "b~a/g~a/x~a/r~a/n~a"
      (count-of 'bond structures) (count-of 'group structures)
      (count-of 'bridge structures) (count-of 'rule structures)
      (length structures))))

(define dump-generic
  (lambda (tag e)
    (printf "GEN\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
      (tell e 'get-type) (tell e 'get-time) (tell e 'get-temperature)
      (structure-summary (tell e 'get-structures))
      (length (tell e 'get-active-theme-types))
      (length (tell e 'get-complete-themespace-patterns)))))

;; --- the state clamping actually moves --------------------------------------

(define model-state
  (lambda (tag label)
    (printf "STATE\t~a\t~a\tthemes=~a\tpressure=~a\tclamped-rules=~a\tcodelets=~a~%"
      tag label
      (length (tell *themespace* 'get-all-themes))
      (join (map (lambda (s) (format "~a" s))
              (tell *themespace* 'get-active-theme-types)))
      (length (tell *workspace* 'get-clamped-rules))
      (tell *coderack* 'get-num-of-codelets))
    ;; the slipnet nodes a concept pattern can pin
    (printf "STATEN\t~a\t~a\t~a~%" tag label
      (join (map (lambda (n) (format "~a:~a:~a" (sn n) (tell n 'get-activation)
                               (yn (tell n 'frozen?))))
              (list plato-letter-category plato-successor plato-opposite
                    plato-string-position-category plato-length))))))

;; --- answer events ----------------------------------------------------------

(define dump-answer-event
  (lambda (tag e)
    (printf "ANE\t~a\t~a\t~a\t~a~%" tag
      (tell e 'print-name) (tell e 'problem-print-name)
      (tell e 'problem-answer-print-name))
    (printf "ANEL\t~a\t~a\t~a\t~a\t~a~%" tag
      (join (map nm (tell e 'get-initial-letters)))
      (join (map nm (tell e 'get-modified-letters)))
      (join (map nm (tell e 'get-target-letters)))
      (join (map nm (tell e 'get-answer-letters))))
    (printf "ANEQ\t~a\t~a\t~a\t~a\t~a~%" tag
      (tell e 'get-absolute-quality) (tell e 'get-relative-quality)
      (tell e 'get-quality) (tell e 'get-strength))
    (printf "ANEU\t~a\t~a\t~a~%" tag
      (yn (tell e 'unjustified?))
      (join (map cm-tag (tell e 'get-unjustified-slippages))))
    (for* each bt in '(top vertical bottom) do
      (printf "ANEB\t~a\t~a\t~a~%" tag bt
        (join (map bridge-tag (tell e 'get-supporting-bridges bt)))))
    (for* each rt in '(top bottom) do
      (printf "ANER\t~a\t~a\t~a\t~a~%" tag rt
        (tell (tell e 'get-rule rt) 'get-rule-type)
        (join (map object-tag (tell e 'get-rule-ref-objects rt)))))
    (printf "ANEG\t~a\t~a~%" tag
      (join (map object-tag (tell e 'get-supporting-groups))))
    (printf "ANED\t~a\t~a~%" tag
      (join (map cm-tag (tell (tell e 'get-slippage-log) 'get-applied-slippages))))
    (printf "ANEE\t~a\t~a~%" tag (yn (tell e 'equal? e)))
    (dump-generic tag e)))

;; --- clamp events -----------------------------------------------------------

(define dump-clamp-event
  (lambda (tag e)
    (printf "CLE\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
      (tell e 'print-name) (tell e 'get-clamp-type)
      (tell e 'get-progress-focus) (tell e 'get-progress-achieved)
      (tell e 'get-strength))
    (printf "CLET\t~a\t~a~%" tag
      (join (map pattern-tag (tell e 'get-clamped-theme-patterns))))
    (printf "CLEC\t~a\t~a~%" tag
      (join (map pattern-tag (tell e 'get-clamped-concept-patterns))))
    (printf "CLEK\t~a\t~a~%" tag
      (join (map pattern-tag (tell e 'get-clamped-codelet-patterns))))
    (printf "CLER\t~a\t~a\t~a~%" tag
      (length (tell e 'get-rules))
      (let ((s (tell e 'get-unifying-slippages)))
        (if s (join (map cm-tag s)) "#f")))
    (printf "CLEA\t~a\t~a\t~a~%" tag
      (length (tell e 'get-all-clamped-patterns))
      (join (map (lambda (t) (yn (tell e 'clamp-type? t)))
              '(rule-codelet-clamp snag-response-clamp justify-clamp manual-clamp))))
    (dump-generic tag e)))

;; --- snag events ------------------------------------------------------------

(define dump-snag-event
  (lambda (tag e)
    (printf "SNE\t~a\t~a\t~a\t~a\t~a~%" tag
      (tell e 'print-name) (tell e 'get-snag-type)
      (tell e 'get-progress-achieved) (tell e 'get-strength))
    (printf "SNEX\t~a\t~a~%" tag (tell e 'get-explanation))
    (printf "SNEO\t~a\t~a~%" tag
      (join (map object-tag (tell e 'get-snag-objects))))
    (printf "SNEB\t~a\t~a~%" tag
      (join (map bridge-tag (tell e 'get-snag-bridges))))
    (printf "SNEC\t~a\t~a~%" tag
      (join (map cm-tag (tell e 'get-snag-concept-mappings))))
    (printf "SNET\t~a\t~a~%" tag (pattern-tag (tell e 'get-snag-theme-pattern)))
    (printf "SNEP\t~a\t~a~%" tag (pattern-tag (tell e 'get-snag-concept-pattern)))
    (for* each bt in '(top vertical) do
      (printf "SNEV\t~a\t~a\t~a~%" tag bt
        (join (map bridge-tag (tell e 'get-supporting-bridges bt)))))
    (printf "SNER\t~a\t~a\t~a~%" tag
      (join (map object-tag (tell e 'get-rule-ref-objects)))
      (tell (tell e 'get-rule 'bottom) 'get-rule-type))
    (printf "SNEE\t~a\t~a~%" tag (yn (tell e 'equal? e)))
    (dump-generic tag e)))

;; --- workspace driver (as in the transstring probe) --------------------------

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

;; Collect a failure result by applying a rule where it cannot work.
(define snag-result #f)
(define record-snag (lambda (failure-result) (set! snag-result failure-result)))

;; --- probe -------------------------------------------------------------------

(define probe
  (lambda (i m t seed n temp rounds)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (tell *themespace* 'initialize)
    (tell *trace* 'initialize)
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
    (let ((rule (build-a-top-rule rounds)))
      (if (not rule)
        (printf "NORULE~%")
        (begin
          ;; ---- clamp events, one of each type ----
          (let* ((tp (cons 'vertical-bridge
                       (list (list plato-string-position-category plato-opposite)
                             (list plato-letter-category plato-successor))))
                 (cp (list 'concepts (list plato-opposite %max-activation%)))
                 (kp %rule-codelet-pattern%))
            (for* each spec in (list
                                 (list "rcc" 'rule-codelet-clamp (list kp) '() 'rule)
                                 (list "src" 'snag-response-clamp (list tp kp) '() 'workspace)
                                 (list "man" 'manual-clamp (list tp cp kp) '() 'workspace))
              do
              (let* ((tag (format "CL:~a" (1st spec)))
                     (e (make-clamp-event (2nd spec) (3rd spec) (4th spec) (5th spec))))
                (dump-clamp-event tag e)
                (model-state tag "before")
                (tell e 'activate)
                (model-state tag "active")
                (tell e 'deactivate)
                (model-state tag "after"))))
          ;; ---- snag events ----
          ;; Applying the top rule to the TARGET string untranslated is the
          ;; reliable way to reach a failure: the rule talks about objects the
          ;; target string need not have.
          (set! snag-result #f)
          (apply-rule rule *target-string* record-snag)
          (if (not snag-result)
            (printf "NOSNAG~%")
            (let* ((result (translate rule))
                   (translated (if result (1st result) rule))
                   (supbr (if result (2nd result) '()))
                   (log (if result (3rd result) (make-slippage-log 'top)))
                   (refobjs (if result (5th result) '()))
                   (e (make-snag-event snag-result rule translated supbr log refobjs))
                   (tag "SN:top"))
              (dump-snag-event tag e)
              (model-state tag "before")
              (tell *trace* 'add-event e)
              (tell e 'activate)
              (model-state tag "active")
              (printf "SNPROG\t~a\t~a\t~a~%" tag
                (yn (tell *trace* 'within-snag-period?))
                (tell *trace* 'progress-since-last-snag))
              (tell *trace* 'undo-snag-condition)
              (model-state tag "after")
              (printf "SNPROG2\t~a\t~a\t~a~%" tag
                (yn (tell *trace* 'within-snag-period?))
                (tell e 'get-progress-achieved))))
          ;; ---- answer event, built the way answer-finder builds one ----
          (let ((result (translate rule)))
            (if (not result)
              (printf "NOTRANSLATE~%")
              (let ((bottom-rule (1st result)))
                (if (not (apply-rule bottom-rule *target-string* ignore-snag))
                  (printf "NOAPPLY~%")
                  (let* ((answer-string
                           (make-translated-string bottom-rule *target-string*))
                         (supbr (2nd result))
                         (log (3rd result))
                         (supgroups (4th result))
                         (topref (5th result))
                         (botref (6th result))
                         (unjust (get-unifying-slippages bottom-rule rule)))
                    (for* each spec in (list (list "just" '())
                                             (list "unjust" unjust))
                      do
                      (let ((e (make-answer-event
                                 *initial-string* *modified-string* *target-string*
                                 answer-string rule bottom-rule supbr supgroups
                                 topref botref log (2nd spec))))
                        (dump-answer-event (format "AN:~a" (1st spec)) e))))))))
          ;; ---- the clamp half of the four deferred trace methods ----
          ;; NB a justify-clamp reads a TOP and a BOTTOM rule out of its rule
          ;; list to compute the unifying slippages, so it needs both; with only
          ;; a top rule, select-meth gives #f and get-unifying-slippages applies
          ;; it as a procedure.
          (tell *trace* 'initialize)
          (let* ((tp (cons 'vertical-bridge
                       (list (list plato-string-position-category plato-opposite))))
                 (tr (translate rule))
                 (bottom (if tr (1st tr) #f))
                 (e (if (not bottom)
                      #f
                      (make-clamp-event 'justify-clamp
                        (list tp %rule-codelet-pattern%)
                        (list rule bottom) 'rule))))
            (if (not e) (printf "NOJUSTIFYCLAMP~%"))
            (if* e
            (tell *trace* 'add-event e)
            (tell e 'activate)
            (printf "CLPROG\t~a\t~a\t~a~%"
              (yn (tell *trace* 'within-clamp-period?))
              (yn (tell *trace* 'permission-to-clamp?))
              (tell *trace* 'progress-since-last-clamp))
            ;; a rule event since the clamp is what the rule-focused evaluator scores
            (tell *trace* 'add-event (make-rule-event rule))
            (printf "CLPROG2\t~a\t~a~%"
              (tell *trace* 'progress-since-last-clamp)
              (tell e 'get-progress-achieved))
            (tell *trace* 'undo-last-clamp)
            (printf "CLPROG3\t~a\t~a\t~a\t~a~%"
              (yn (tell *trace* 'within-clamp-period?))
              (tell e 'get-progress-achieved)
              (yn (tell *trace* 'within-grace-period?))
              (yn (tell *trace* 'permission-to-clamp?))))))))))

;; abc->abd with target xyz is THE snag: the top rule says "replace the
;; rightmost letter by its successor", and z has no successor, so applying it
;; to xyz fails with a CHANGE failure-result. That is the configuration the
;; whole snag machinery exists for.
(probe 'abc 'abd 'xyz 410 3000 30 40)
(probe 'abc 'abd 'xyz 411 2000 40 40)
(probe 'abc 'abd 'cba 501 2000 30 40)
(probe 'abc 'abd 'kji 401 2000 30 40)
(probe 'abc 'abd 'mrrjjj 404 3000 30 40)
(probe 'abc 'cba 'pqrs 405 3000 30 40)
(probe 'mrrjjj 'mrrkkk 'xyz 409 3000 30 40)
