;; trace.ss slice (D): the MONITORS (1310-1412), and the first probe that
;; compares a WHOLE TRACE rather than individual events.
;;
;; Slices (A)-(C) had to work around the fact that the Scheme's monitors are
;; always live and the port's did not exist: the `trace` probe could only build
;; bonds, the only structure nothing monitors, and the two event probes had to
;; construct their events by hand and never read *trace*. With (D) in, both
;; sides raise the same events from the same code paths, so the probe can run a
;; real coderack and then diff the event list end to end -- numbers, types,
;; names, times, temperatures and strengths, in order.
;;
;; That is a much stronger test than the event probes were: it checks not only
;; that each event is built right, but that the same things were judged worth
;; recording, in the same order, at the same moments.
;;
;; The probe also drives the four importance functions directly over a fixed
;; spread of inputs, because the thresholds mean most of their range never
;; reaches an event -- a group scoring 99 and a group scoring 3 are both simply
;; absent from the trace, and only a direct call tells them apart.
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

;; --- the whole trace, in order ----------------------------------------------

(define dump-trace
  (lambda (tag)
    (let ((events (reverse (tell *trace* 'get-all-events))))
      (printf "TRACE\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
        (length events)
        (tell *trace* 'get-num-of-events 'concept-activation)
        (tell *trace* 'get-num-of-events 'concept-mapping)
        (tell *trace* 'get-num-of-events 'group)
        (tell *trace* 'get-num-of-events 'rule))
      (for* each e in events do
        (printf "EV\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
          (tell e 'get-event-number) (tell e 'get-type)
          (tell e 'print-name) (tell e 'get-time)
          (tell e 'get-temperature) (tell e 'get-strength)))
      ;; the per-type views the trace offers over the same list
      (for* each type in '(concept-activation concept-mapping group rule workspace) do
        (let ((last (tell *trace* 'get-last-event type)))
          (printf "LAST\t~a\t~a\t~a\t~a~%" tag type
            (if (exists? last) (tell last 'get-event-number) "-")
            (if (exists? last) (tell last 'print-name) "-")))))))

;; --- the importance functions, over a fixed spread --------------------------

(define dump-importance
  (lambda ()
    (for* each node in (list plato-letter-category plato-successor plato-opposite
                             plato-samegrp plato-length plato-identity
                             plato-a plato-right plato-whole) do
      (for* each pair in '((0 100) (0 50) (40 100) (100 0) (60 61) (0 86) (0 90)) do
        (let ((imp (concept-activation-importance node (1st pair) (2nd pair))))
          (printf "CAIMP\t~a\t~a\t~a\t~a\t~a~%" (sn node) (1st pair) (2nd pair) imp
            (yn (>= imp %concept-activation-importance-threshold%))))))
    (for* each string in (list *initial-string* *modified-string* *target-string*) do
      (for* each g in (reverse (tell string 'get-groups)) do
        (for* each f in '(#f #t) do
          (let ((imp (group-importance g f)))
            (printf "GIMP\t~a\t~a\t~a\t~a~%" (object-tag g) (yn f) imp
              (yn (>= imp %group-importance-threshold%)))))))
    (for* each bt in '(vertical top) do
      (for* each b in (reverse (tell *workspace* 'get-bridges bt)) do
        (for* each cm in (tell b 'get-all-concept-mappings) do
          (let ((imp (concept-mapping-importance cm b)))
            (printf "CMIMP\t~a\t~a\t~a\t~a\t~a\t~a~%" bt (object-tag (tell b 'get-object1))
              (tell cm 'print-name) (yn (tell cm 'slippage?)) imp
              (yn (>= imp %concept-mapping-importance-threshold%)))))))
    (for* each rt in '(top bottom) do
      (for* each r in (tell *workspace* 'get-rules rt) do
        (let ((imp (rule-importance r)))
          (printf "RIMP\t~a\t~a\t~a\t~a\t~a~%" rt
            (tell r 'get-uniformity) (tell r 'get-relative-quality) imp
            (yn (>= imp %rule-importance-threshold%))))))))

;; --- workspace driver --------------------------------------------------------

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

;; --- a deterministic phase that forces the concept-mapping monitor ------------
;;
;; concept-mapping-importance only clears its threshold of 65 for a slippage on
;; a SPANNING bridge: the same slippage scores 75 spanning and 57 not. Spanning
;; bridges need a whole-string group on both sides, and the stochastic runs
;; above did not reliably produce one -- across all seven, the highest score
;; reached was 57. So this phase builds the configuration by hand, the way the
;; bridges probe does, and lets build-bridge raise the event through the real
;; monitor rather than calling the monitor directly.

(define build-chain-and-group
  (lambda (string)
    (let* ((n (tell string 'get-length))
           (bonds
             (let loop ((p 0) (acc '()))
               (if (>= p (sub1 n))
                 (reverse acc)
                 (let* ((o1 (tell string 'get-letter p))
                        (o2 (tell string 'get-letter (add1 p)))
                        (d1 (tell o1 'get-descriptor-for plato-letter-category))
                        (d2 (tell o2 'get-descriptor-for plato-letter-category))
                        (cat (get-bond-category d1 d2)))
                   (if (not (exists? cat))
                     (loop (add1 p) acc)
                     (let ((b (make-bond o1 o2 cat plato-letter-category d1 d2)))
                       (build-bond b)
                       (loop (add1 p) (cons b acc)))))))))
      (if (and (not (null? bonds)) (= (length bonds) (sub1 n)))
        (let* ((cat (tell (1st bonds) 'get-bond-category))
               (dir (tell (1st bonds) 'get-direction))
               (gcat (tell cat 'get-related-node plato-group-category))
               (objs (cons (tell (1st bonds) 'get-left-object)
                       (map (lambda (b) (tell b 'get-right-object)) bonds))))
          (build-group
            (make-group string gcat plato-letter-category dir
              (1st objs) (nth (sub1 (length objs)) objs) objs bonds)
            #f))))))

(define forced-probe
  (lambda (i m t seed temp)
    (printf "FORCED\t~a\t~a\t~a\t~a\t~a~%" i m t seed temp)
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
                             plato-predecessor plato-sameness plato-group-category
                             plato-direction-category plato-length
                             plato-alphabetic-position-category plato-bond-category
                             plato-bond-facet plato-left plato-right) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (update-workspace-values)
    (random-seed seed)
    (for-each build-chain-and-group
      (list *initial-string* *modified-string* *target-string*))
    (update-workspace-values)
    (dump-trace "forced-groups")
    ;; the spanning vertical bridge, built through the real build-bridge
    (let ((g1 (if (null? (tell *initial-string* 'get-groups)) #f
                (1st (tell *initial-string* 'get-groups))))
          (g2 (if (null? (tell *target-string* 'get-groups)) #f
                (1st (tell *target-string* 'get-groups)))))
      (if (or (not g1) (not g2))
        (printf "NOSPANNING~%")
        (let ((cms (all-possible-bridge-CMs 'vertical
                     g1 (tell g1 'get-descriptions) g2 (tell g2 'get-descriptions))))
          (printf "FCMS\t~a\t~a\t~a~%"
            (object-tag g1) (object-tag g2)
            (join (map (lambda (cm) (tell cm 'print-name)) cms)))
          (if (null? cms)
            (printf "NOCMS~%")
            (let ((b (make-vertical-bridge g1 g2 cms)))
              (printf "FSPAN\t~a\t~a~%"
                (yn (tell b 'spanning-bridge?)) (yn (tell b 'group-spanning-bridge?)))
              (for* each cm in (tell b 'get-all-concept-mappings) do
                (printf "FIMP\t~a\t~a\t~a\t~a~%"
                  (tell cm 'print-name) (yn (tell cm 'slippage?))
                  (concept-mapping-importance cm b)
                  (yn (>= (concept-mapping-importance cm b)
                          %concept-mapping-importance-threshold%))))
              (build-bridge 'vertical b)
              (dump-trace "forced-bridge"))))))))

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
    ;; The real run loop updates slipnet activations every cycle, and those
    ;; updates are monitored, so the probe does it too: without it the only
    ;; slipnode changes the trace would ever see are the label flushes that
    ;; bridge-building does.
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
    (dump-trace "run")
    (build-a-top-rule rounds)
    (dump-trace "rules")
    (dump-importance)))

;; abc :: kji and abc :: cba both make a whole-string group on each side
;; running in OPPOSITE directions, so the vertical bridge between them spans
;; and carries a Direction or StringPos opposite slippage. That is what pushes
;; concept-mapping-importance to 75, over its threshold of 65 -- a NON-spanning
;; bridge with the same slippage scores 57 and never raises an event. Without
;; one of these, the concept-mapping monitor is never exercised end to end.
(probe 'abc 'abd 'kji 706 2500 30 40)
(probe 'abc 'abd 'cba 707 2500 30 40)
(probe 'abc 'abd 'ijk 701 1200 40 40)
(probe 'abc 'abd 'mrrjjj 702 1500 30 40)
(probe 'abc 'cba 'pqrs 703 1500 30 40)
(probe 'mrrjjj 'mrrkkk 'xyz 704 1500 30 40)
(probe 'aabc 'aabd 'ijkk 705 1500 35 40)

(forced-probe 'abc 'abd 'kji 801 40)
(forced-probe 'abc 'abd 'cba 802 40)
(forced-probe 'abc 'abd 'ijk 803 40)
