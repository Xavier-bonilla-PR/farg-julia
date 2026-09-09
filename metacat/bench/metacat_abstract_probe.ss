;; answers.ss step (C), part 1: turning an answer or snag EVENT into a
;; DESCRIPTION the memory can keep.
;;
;; An event records what happened in terms of the workspace that produced it --
;; particular groups, particular bridges, all of which are gone by the next run.
;; A description records the same moment in terms that outlive it, so a later
;; run on a different problem can be reminded of it. `abstract-answer-description`
;; and `abstract-snag-description` are the two functions that make that
;; translation, and they were the last things in memory.ss waiting on trace.ss.
;;
;; The helpers they need live in answers.ss's commentary half (108-265) but are
;; nothing to do with the prose, so they come here rather than with step (D):
;; most-recent-group-and-concept-mapping-events, which picks one event per
;; distinct structure at its latest moment; and
;; abstract-answer-description-theme-pattern, which decides what an answer is
;; really ABOUT thematically -- five dimensions, with three fallbacks for
;; string-position, which is always included whatever happens.
;;
;; The workspace is driven exactly as the swevents probe drives it, and the
;; answer and snag events are built the same way, because those are the inputs.
;; The MONITORS are live now, so the trace also fills with the group and
;; concept-mapping events that
;; most-recent-group-and-concept-mapping-events reads -- which is the whole
;; reason this could not be done before slice (D).
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
(define pattern-tag
  (lambda (p) (format "~a[~a]" (1st p) (join (map entry-tag (rest p))))))

(define letters-tag (lambda (ls) (apply string-append (map nm ls))))

;; --- what the abstractors read ----------------------------------------------

(define dump-important-events
  (lambda (tag)
    (let ((events (most-recent-group-and-concept-mapping-events)))
      (printf "IMP\t~a\t~a~%" tag (length events))
      (for* each e in events do
        (printf "IMPE\t~a\t~a\t~a\t~a\t~a~%" tag
          (tell e 'get-event-number) (tell e 'get-type)
          (tell e 'print-name) (tell e 'get-age)))
      (printf "IMPP\t~a\t~a~%" tag
        (pattern-tag (abstract-answer-description-theme-pattern events))))))

;; --- the descriptions -------------------------------------------------------

(define dump-answer-description
  (lambda (tag a)
    (printf "AD\t~a\t~a\t~a\t~a\t~a~%" tag
      (letters-tag (tell a 'get-initial-letters))
      (letters-tag (tell a 'get-modified-letters))
      (letters-tag (tell a 'get-target-letters))
      (letters-tag (tell a 'get-answer-letters)))
    (printf "ADQ\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
      (tell a 'get-temperature) (tell a 'get-quality)
      (tell a 'get-top-rule-abstractness) (tell a 'get-bottom-rule-abstractness)
      (tell a 'get-activation) (yn (tell a 'unjustified?)))
    (printf "ADV\t~a\t~a~%" tag (pattern-tag (tell a 'get-vertical-theme-pattern)))
    (printf "ADT\t~a\t~a~%" tag (pattern-tag (tell a 'get-top-theme-pattern)))
    (printf "ADB\t~a\t~a~%" tag (pattern-tag (tell a 'get-bottom-theme-pattern)))
    (printf "ADU\t~a\t~a\t~a~%" tag
      (pattern-tag (tell a 'get-unjustified-theme-pattern))
      (join (map cm-tag (tell a 'get-unjustified-slippages))))
    (for* each line in (tell a 'get-top-rule-phrases) do
      (printf "ADPT\t~a\t|~a|~%" tag line))
    (for* each line in (tell a 'get-bottom-rule-phrases) do
      (printf "ADPB\t~a\t|~a|~%" tag line))))

(define dump-snag-description
  (lambda (tag s)
    (printf "SD\t~a\t~a\t~a\t~a~%" tag
      (letters-tag (tell s 'get-initial-letters))
      (letters-tag (tell s 'get-modified-letters))
      (letters-tag (tell s 'get-target-letters)))
    (printf "SDX\t~a\t~a~%" tag (tell s 'get-explanation))
    (printf "SDT\t~a\t~a~%" tag (pattern-tag (tell s 'get-theme-pattern)))
    ;; NB a snag-description's get-activation is hardwired to 0 -- unlike an
    ;; answer-description's, which is real. Only the memory window reads it.
    (printf "SDA\t~a\t~a\t~a~%" tag (tell s 'get-activation)
      (join (map entry-tag (tell s 'get-themes))))
    ;; NB there is no `get-rule-phrases`: a snag-description exposes only the
    ;; TRANSLATED rule's phrases, though it stores both.
    (for* each line in (tell s 'get-translated-rule-phrases) do
      (printf "SDPT\t~a\t|~a|~%" tag line))))

(define dump-memory
  (lambda (tag)
    (printf "MEM\t~a\t~a\t~a\t~a~%" tag
      (length (tell *memory* 'get-answers))
      (length (tell *memory* 'get-snags))
      (length (tell *memory* 'get-all-descriptions)))))

;; --- workspace driver (as in the swevents probe) -----------------------------

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

(define snag-result #f)
(define record-snag (lambda (failure-result) (set! snag-result failure-result)))

;; --- probe -------------------------------------------------------------------

(define probe
  (lambda (i m t seed n temp rounds)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (tell *themespace* 'initialize)
    (tell *trace* 'initialize)
    (tell *memory* 'clear)
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
          (seed-rack)
          (update-slipnet-activations))
        (set! *codelet-count* c)
        (tell (tell *coderack* 'choose-codelet) 'run)
        (update-workspace-values)
        (loop (+ c 1))))
    (tell *workspace* 'check-if-rules-possible)
    (dump-important-events "run")
    (let ((rule (build-a-top-rule rounds)))
      (if (not rule)
        (printf "NORULE~%")
        (begin
          (dump-important-events "rules")
          ;; ---- snag description ----
          (set! snag-result #f)
          (apply-rule rule *target-string* record-snag)
          (if (not snag-result)
            (printf "NOSNAG~%")
            (let* ((result (translate rule))
                   (translated (if result (1st result) rule))
                   (supbr (if result (2nd result) '()))
                   (log (if result (3rd result) (make-slippage-log 'top)))
                   (refobjs (if result (5th result) '()))
                   (e (make-snag-event snag-result rule translated supbr log refobjs)))
              (tell *trace* 'add-event e)
              (printf "SNAGPRESENT\t~a~%" (yn (tell *memory* 'snag-present? rule)))
              (abstract-snag-description e)
              (dump-memory "after-snag")
              (dump-snag-description "snag"
                (1st (tell *memory* 'get-snags)))
              ;; abstracting the SAME snag again: the memory grows, since
              ;; abstract-snag-description does not itself check for duplicates
              (abstract-snag-description e)
              (dump-memory "after-snag2")))
          ;; ---- answer description ----
          (let ((result (translate rule)))
            (if (not result)
              (printf "NOTRANSLATE~%")
              (let ((bottom-rule (1st result)))
                (if (not (apply-rule bottom-rule *target-string* ignore-snag))
                  (printf "NOAPPLY~%")
                  (let* ((answer-string
                           (make-translated-string bottom-rule *target-string*))
                         (unjust (get-unifying-slippages bottom-rule rule)))
                    (for* each spec in (list (list "just" '())
                                             (list "unjust" unjust))
                      do
                      (let ((e (make-answer-event
                                 *initial-string* *modified-string* *target-string*
                                 answer-string rule bottom-rule (2nd result)
                                 (4th result) (5th result) (6th result)
                                 (3rd result) (2nd spec))))
                        (tell *trace* 'add-event e)
                        (abstract-answer-description e)
                        (dump-answer-description (1st spec)
                          (tell e 'get-answer-description))
                        (dump-memory (format "after-~a" (1st spec)))))))))))))))

(probe 'abc 'abd 'xyz 901 3000 30 40)
(probe 'abc 'abd 'kji 902 2500 30 40)
(probe 'abc 'abd 'cba 903 2500 30 40)
(probe 'abc 'abd 'mrrjjj 904 1500 30 40)
(probe 'abc 'cba 'pqrs 905 1500 30 40)
(probe 'mrrjjj 'mrrkkk 'xyz 906 1500 30 40)
