;; The TEMPORAL TRACE and its generic event (trace.ss 23-333).
;;
;; The trace is Metacat's record of its own processing. Each event snapshots
;; the moment it happened -- time, temperature, every structure built by then,
;; the clamped rules, and the themespace's complete and dominant patterns --
;; and the trace answers questions against those snapshots: how long since the
;; last snag, what has been built since the last clamp, is there a current
;; answer.
;;
;; The seven concrete event types do not exist yet, so this probe raises
;; GENERIC events of each type instead. That is enough to test everything the
;; trace itself does: numbering, ordering, per-type lookup, the since-last
;; queries, and the clamp and snag periods with their grace window. The four
;; methods that reach INTO a clamp or snag event for its progress evaluator are
;; deferred with those event types.
;;
;; IMPORTANT: the Scheme's MONITORS are always live. Building a group or a
;; bridge, and changing a slipnode's activation by enough, each raise a real
;; trace event (trace.ss 1315-1343) -- so running the coderack here would fill
;; the Scheme's trace with event types the port does not have yet, and the two
;; sides would diverge for a reason that is not a porting bug. The monitors are
;; slice (D).
;;
;; So this probe deliberately stays inside slice (B)'s boundary: it builds
;; BONDS, which nothing monitors, and leaves slipnode activations alone. That
;; still gives `get-new-structures-since-last` something real to difference.
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

;; Structures are counted and typed rather than named: their print-names would
;; drag in the whole workspace, and what the trace does with them is set
;; arithmetic, not inspection.
(define count-of
  (lambda (type structures)
    (count (lambda (s) (eq? (tell s 'object-type) type)) structures)))

(define structure-summary
  (lambda (structures)
    (format "b~a/g~a/x~a/r~a/n~a"
      (count-of 'bond structures) (count-of 'group structures)
      (count-of 'bridge structures) (count-of 'rule structures)
      (length structures))))

(define pattern-summary
  (lambda (patterns)
    (join
      (map (lambda (p)
             (format "~a:~a" (1st p)
               (join (map (lambda (e)
                            (format "~a/~a~a" (sn (1st e)) (nm (2nd e))
                              (if (= (length e) 3) (format "@~a" (3rd e)) "")))
                       (entries p)))))
        patterns))))

(define show-event
  (lambda (tag e)
;; NB: the generic event CAPTURES the clamped rules but exposes no accessor
    ;; for them -- only display-workspace-state reads them -- so they are not
    ;; dumped here.
    (printf "~a\tEV\t~a\t~a\t~a\ttemp=~a\tage=~a\tstruct=~a~%"
      tag (tell e 'get-event-number) (tell e 'get-type) (tell e 'get-time)
      (tell e 'get-temperature) (tell e 'get-age)
      (structure-summary (tell e 'get-structures)))
    (printf "~a\tEVTH\t~a\t~a~%" tag (tell e 'get-event-number)
      (join (map (lambda (s) (format "~a" s)) (tell e 'get-active-theme-types))))
    (printf "~a\tEVCP\t~a\t~a~%" tag (tell e 'get-event-number)
      (pattern-summary (tell e 'get-complete-themespace-patterns)))
    (printf "~a\tEVDP\t~a\t~a~%" tag (tell e 'get-event-number)
      (pattern-summary (tell e 'get-dominant-themespace-patterns)))
    (printf "~a\tEVNAME\t~a\t|~a|~%" tag (tell e 'get-event-number)
      (tell e 'print-name))))

(define show-trace
  (lambda (tag)
    (printf "~a\tN\t~a~%" tag (length (tell *trace* 'get-all-events)))
    (for* each type in '(any snag answer clamp concept-activation
                         concept-mapping rule group) do
      (printf "~a\tCOUNT\t~a\t~a\tlast=~a\telapsed=~a~%" tag type
        (tell *trace* 'get-num-of-events type)
        (let ((e (tell *trace* 'get-last-event type)))
          (if (exists? e) (tell e 'get-event-number) "-"))
        (tell *trace* 'get-elapsed-time type)))
    (printf "~a\tPERIODS\tclamp=~a\tsnag=~a\tgrace=~a\tpermission=~a\texpired=~a~%"
      tag (yn (tell *trace* 'within-clamp-period?))
      (yn (tell *trace* 'within-snag-period?))
      (yn (tell *trace* 'within-grace-period?))
      (yn (tell *trace* 'permission-to-clamp?))
      (yn (tell *trace* 'clamp-period-expired?)))
    (printf "~a\tTIMES\tlastclamp=~a\tlastunclamp=~a\tcurrentanswer=~a\timmsnag=~a~%"
      tag
      (let ((t (tell *trace* 'get-last-clamp-time))) (if (exists? t) t "-"))
      (let ((t (tell *trace* 'get-last-unclamp-time))) (if (exists? t) t "-"))
      (yn (tell *trace* 'current-answer?))
      (yn (tell *trace* 'immediate-snag-condition?)))))

;; Build the next adjacent bond in a string, if there is one to build. Bonds
;; are the only workspace structure whose builder does not call a monitor.
(define bond-cursor 0)
(define build-next-bond
  (lambda (string)
    (let ((n (tell string 'get-length)))
      (if (>= bond-cursor (sub1 n))
        #f
        (let* ((o1 (tell string 'get-letter bond-cursor))
               (o2 (tell string 'get-letter (add1 bond-cursor)))
               (d1 (tell o1 'get-descriptor-for plato-letter-category))
               (d2 (tell o2 'get-descriptor-for plato-letter-category))
               (cat (get-bond-category d1 d2)))
          (set! bond-cursor (+ bond-cursor 1))
          (if (not (exists? cat))
            #f
            (let ((b (make-bond o1 o2 cat plato-letter-category d1 d2)))
              (build-bond b)
              b)))))))

;; Advance the clock and build a bond or two, so successive snapshots differ.
(define advance
  (lambda (n string)
    (set! *codelet-count* (+ *codelet-count* n))
    (build-next-bond string)))

(define probe
  (lambda (i m t seed temp)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a~%" i m t seed temp)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (tell *themespace* 'initialize)
    (tell *trace* 'initialize)
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    ;; NB: slipnode activations are left alone on purpose. Raising one far
    ;; enough on a deep node clears the concept-activation importance
    ;; threshold and raises a real trace event.
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (set! bond-cursor 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)

    (show-trace "empty")

    ;; Events are raised as GENERIC events, one per type, with the workspace
    ;; advanced between them so the snapshots differ.
    (let loop ((specs (list (list 'concept-activation 60)
                            (list 'group 80)
                            (list 'concept-mapping 120)
                            (list 'rule 40)
                            (list 'snag 90)
                            (list 'concept-activation 30)
                            (list 'clamp 70)
                            (list 'group 150)
                            (list 'answer 50)))
               (k 1))
      (when (not (null? specs))
        (advance (2nd (1st specs)) *initial-string*)
        ;; a couple of themes so the snapshots carry a pattern that changes
        (if* (= k 3)
          (tell *themespace* 'set-theme-activation 'vertical-bridge
            plato-letter-category plato-identity 90)
          (tell *themespace* 'thematic-pressure-on 'vertical-bridge))
        (if* (= k 6)
          (tell *themespace* 'set-theme-activation 'top-bridge
            plato-string-position-category plato-opposite 70))
        (let ((e (make-generic-event (1st (1st specs)))))
          (tell *trace* 'add-event e)
          (printf "ADDED\t~a\t~a\ttime=~a~%" k (1st (1st specs)) *codelet-count*)
          (show-event (format "e~a" k) e))
        (show-trace (format "after~a" k))
        (loop (rest specs) (+ k 1))))

    ;; every event, in the order the trace holds them (newest first)
    (printf "ALLEVENTS\t~a~%"
      (join (map (lambda (e) (format "~a:~a" (tell e 'get-event-number)
                               (tell e 'get-type)))
              (tell *trace* 'get-all-events))))
    ;; and by number
    (let loop ((n 1))
      (when (<= n 9)
        (let ((e (tell *trace* 'get-event n)))
          (printf "BYNUM\t~a\t~a~%" n
            (if (exists? e) (tell e 'get-type) "-")))
        (loop (+ n 1))))
    (printf "BYNUM\t99\t~a~%"
      (let ((e (tell *trace* 'get-event 99))) (if (exists? e) "found" "-")))

    ;; get-last-event over a LIST of types takes the most recent of any
    (for* each types in (list '(snag answer) '(clamp group) '(rule)
                              '(concept-activation concept-mapping)) do
      (let ((e (tell *trace* 'get-last-event types)))
        (printf "LASTOF\t~a\t~a~%" types
          (if (exists? e) (format "~a:~a" (tell e 'get-event-number)
                            (tell e 'get-type)) "-"))))

    ;; since-last queries
    (for* each type in '(clamp snag answer group rule) do
      (printf "SINCE\t~a\tevents=~a\tstructures=~a~%" type
        (length (tell *trace* 'get-new-events-since-last type))
        (structure-summary (tell *trace* 'get-new-structures-since-last type))))

    ;; the grace period: unclamping by hand, since undo-last-clamp needs a real
    ;; clamp event's progress evaluator
    (printf "GRACE\tbefore\t~a\t~a~%"
      (yn (tell *trace* 'within-grace-period?))
      (yn (tell *trace* 'permission-to-clamp?)))
    (set! *codelet-count* (+ *codelet-count* 400))
    (printf "GRACE\tafter400\texpired=~a\t~a~%"
      (yn (tell *trace* 'clamp-period-expired?))
      (yn (tell *trace* 'permission-to-clamp?)))
    (set! *codelet-count* (+ *codelet-count* 400))
    (printf "GRACE\tafter800\texpired=~a~%"
      (yn (tell *trace* 'clamp-period-expired?)))

    ;; re-initialising wipes everything
    (tell *trace* 'initialize)
    (show-trace "reinitialized")))

(probe 'abc 'abd 'ijk 701 40)
(probe 'abc 'abd 'mrrjjj 702 30)
(probe 'abc 'cba 'pqrs 703 50)
