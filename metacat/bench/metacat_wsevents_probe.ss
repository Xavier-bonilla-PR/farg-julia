;; trace.ss slice (C), part 1: the four WORKSPACE and SLIPNET event types --
;; concept-activation, concept-mapping, group and rule events.
;;
;; The workspace is built the way the ruletranslate probe builds it -- run the
;; coderack for a while, then drive the rule codelets by hand until a top rule
;; exists -- because these events describe real perceived structure, and there
;; is no point testing them against structure nobody perceived.
;;
;; IMPORTANT: the Scheme's MONITORS are live, so building groups, bridges and
;; rules raises real events into *trace* on the Scheme side and none on the
;; Julia side, where the monitors are slice (D). This probe therefore never
;; READS *trace*. It constructs its events directly and dumps them, which is
;; what slice (C) is about; the monitors that decide WHICH ones get raised are
;; the next slice. Constructing an event draws no random numbers on either
;; side, so the RNG streams stay in step.
;;
;; An event snapshots the model at the moment it is made -- time, temperature,
;; every structure built by then, the clamped rules, and the themespace's
;; complete and dominant patterns -- so the generic half is dumped for every
;; event, not just the specific half.
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

(define count-of
  (lambda (type structures)
    (count (lambda (s) (eq? (tell s 'object-type) type)) structures)))

(define structure-summary
  (lambda (structures)
    (format "b~a/g~a/x~a/r~a/n~a"
      (count-of 'bond structures) (count-of 'group structures)
      (count-of 'bridge structures) (count-of 'rule structures)
      (length structures))))

(define concept-pattern-tag
  (lambda (pattern)
    (join (map (lambda (e) (format "~a:~a" (sn (1st e)) (2nd e))) (rest pattern)))))

(define theme-pattern-tag
  (lambda (pattern)
    (format "~a[~a]" (1st pattern) (join (map entry-tag (rest pattern))))))

;; --- the generic half, dumped for every event --------------------------------

(define dump-generic
  (lambda (tag e)
    (printf "GEN\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
      (tell e 'get-type) (tell e 'get-time) (tell e 'get-temperature)
      (structure-summary (tell e 'get-structures))
      (length (tell e 'get-active-theme-types))
      (length (tell e 'get-complete-themespace-patterns))
      (length (tell e 'get-dominant-themespace-patterns))
      (tell e 'get-age))
    (printf "GENT\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
      (yn (tell e 'type? 'any)) (yn (tell e 'type? 'workspace))
      (yn (tell e 'type? 'concept-activation)) (yn (tell e 'type? 'concept-mapping))
      (yn (tell e 'type? 'group)) (yn (tell e 'type? 'rule)))
    (for* each tt in '(top-bridge vertical-bridge) do
      (let ((cp (tell e 'get-complete-themespace-pattern tt))
            (dp (tell e 'get-dominant-themespace-pattern tt)))
        (printf "GENP\t~a\t~a\t~a\t~a~%" tag tt
          (if (exists? cp) (length (rest cp)) "-")
          (if (exists? dp) (length (rest dp)) "-"))))))

;; --- the four event types ----------------------------------------------------

(define dump-concept-activation-event
  (lambda (node)
    (let ((e (make-concept-activation-event node))
          (tag (format "CA:~a" (sn node))))
      (printf "CAE\t~a\t~a\t~a\t~a~%" tag
        (tell e 'print-name) (tell e 'get-strength)
        (full-slipnode-name node))
      (printf "CAEP\t~a\t~a~%" tag
        (concept-pattern-tag (tell e 'get-concept-pattern)))
      (printf "CAEQ\t~a\t~a\t~a~%" tag
        (yn (tell e 'equal? e))
        (yn (eq? (tell e 'get-slipnode) node)))
      (dump-generic tag e))))

(define dump-concept-mapping-event
  (lambda (cm bridge)
    (let ((e (make-concept-mapping-event cm bridge))
          (tag (format "CM:~a:~a:~a" (tell bridge 'get-bridge-type)
                 (object-tag (tell bridge 'get-object1)) (cm-tag cm))))
      (printf "CME\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
        (tell e 'print-name) (yn (tell e 'slippage?))
        (tell e 'get-bridge-type) (tell e 'get-strength)
        (sn (tell e 'get-CM-type))
        (yn (tell e 'relevant-for-answer-description?)))
      (printf "CMET\t~a\t~a~%" tag (theme-pattern-tag (tell e 'get-theme-pattern)))
      (printf "CMEP\t~a\t~a~%" tag
        (concept-pattern-tag (tell e 'get-concept-pattern)))
      (printf "CMEQ\t~a\t~a\t~a\t~a~%" tag
        (yn (tell e 'equal? e))
        (yn (tell e 'CM-type? (tell cm 'get-CM-type)))
        (yn (tell e 'currently-present?)))
      (dump-generic tag e))))

(define dump-group-event
  (lambda (group flipped?)
    (let ((e (make-group-event group flipped?))
          (tag (format "GR:~a:~a" (object-tag group) (yn flipped?))))
      (printf "GRE\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
        (tell e 'print-name) (yn (tell e 'flipped?))
        (sn (tell e 'get-group-category)) (nm (tell e 'get-direction))
        (tell e 'get-strength) (yn (tell e 'spanning?))
        (tell e 'get-string-type))
      (printf "GREN\t~a\t~a\t~a\t~a~%" tag
        (group-event-pexp-text-string group)
        (let ((n (unflipped-group-name group))) (if (string? n) n "-"))
        (full-workspace-object-name group))
      (printf "GRES\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
        (yn (tell e 'spans? 'initial)) (yn (tell e 'spans? 'modified))
        (yn (tell e 'spans? 'target))
        (yn (tell e 'currently-present?))
        (yn (tell e 'relevant-for-answer-description?)))
      (printf "GREP\t~a\t~a~%" tag
        (concept-pattern-tag (tell e 'get-concept-pattern)))
      (printf "GREQ\t~a\t~a~%" tag (yn (tell e 'equal? e)))
      (dump-generic tag e))))

(define dump-rule-event
  (lambda (rule)
    (let ((e (make-rule-event rule))
          (tag (format "RU:~a" (tell rule 'get-rule-type))))
      (printf "RUE\t~a\t~a\t~a\t~a\t~a~%" tag
        (tell e 'print-name) (tell e 'get-rule-type)
        (tell e 'get-relative-quality) (tell e 'get-strength))
      (printf "RUEB\t~a\t~a~%" tag
        (join (map (lambda (b)
                     (format "~a>~a" (object-tag (tell b 'get-object1))
                       (object-tag (tell b 'get-object2))))
                (tell e 'get-supporting-bridges))))
      (printf "RUER\t~a\t~a~%" tag
        (join (map object-tag (tell e 'get-reference-objects))))
      (printf "RUEP\t~a\t~a~%" tag
        (concept-pattern-tag (tell e 'get-concept-pattern)))
      (printf "RUEQ\t~a\t~a~%" tag (yn (tell e 'equal? e)))
      (dump-generic tag e))))

;; --- workspace driver (as in the ruletranslate probe) ------------------------

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
    ;; concept-activation events: one per concept, deep and shallow
    (for* each node in (list plato-letter-category plato-successor plato-opposite
                             plato-samegrp plato-length plato-identity
                             plato-string-position-category plato-a plato-right
                             plato-alphabetic-position-category plato-bond-facet
                             plato-whole plato-predgrp) do
      (dump-concept-activation-event node))
    ;; concept-mapping events: every CM of every built bridge
    (for* each bt in '(vertical top) do
      (for* each b in (reverse (tell *workspace* 'get-bridges bt)) do
        (for* each cm in (tell b 'get-all-concept-mappings) do
          (dump-concept-mapping-event cm b))))
    ;; group events, built and flipped
    (for* each string in (list *initial-string* *modified-string* *target-string*) do
      (for* each g in (reverse (tell string 'get-groups)) do
        (dump-group-event g #f)
        (dump-group-event g #t)))
    ;; rule event
    (let ((rule (build-a-top-rule rounds)))
      (if (not rule)
        (printf "NORULE~%")
        (dump-rule-event rule)))
    ;; name helpers over every slipnode and every object
    (for* each node in *slipnet-nodes* do
      (printf "FSN\t~a\t~a~%" (sn node) (full-slipnode-name node)))
    (for* each obj in (tell *workspace* 'get-objects) do
      (printf "SOP\t~a\t~a\t~a~%" (object-tag obj)
        (snag-object-phrase obj)
        (let ((n (full-workspace-object-name obj))) (if (string? n) n "-"))))
    (for* each s in (list *initial-string* *modified-string* *target-string*) do
      (printf "SOPS\t~a\t~a~%" (tell s 'get-string-type) (snag-object-phrase s)))))

(probe 'abc 'abd 'ijk 601 2000 40 40)
(probe 'abc 'abd 'mrrjjj 602 3000 30 40)
(probe 'abc 'cba 'pqrs 603 3000 30 40)
(probe 'mrrjjj 'mrrkkk 'xyz 604 3000 30 40)
