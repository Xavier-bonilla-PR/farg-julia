;; run.ss's DRIVER: `init-mcat`, `step-mcat` and `run-mcat` -- the model run
;; end to end, with nothing hand-driven at all.
;;
;; Every other probe in this suite builds its own starting state and then drives
;; whatever it is testing. This one calls the same `run-problem` the reference
;; runner calls, and lets Metacat do the rest: initialize itself, post its own
;; codelets, run until it finds an answer, gives up, or hits the codelet budget,
;; and record what it concluded in its episodic memory.
;;
;; Three things here exist nowhere else in the suite, which is why the driver
;; needs its own probe rather than being taken on trust from `runloop`:
;;
;;   `init-mcat` sets EVERY descriptor of every object to full activation before
;;   the first codelet, with `set-activation` rather than `update-activation`, so
;;   that no concept-activation event lands in the trace before the run begins.
;;
;;   `update-everything` runs once every %update-cycle-length% CODELETS, not
;;   once per codelet -- the model's cycle is fifteen codelets long, and the
;;   `runloop` probe's per-codelet driving is not what the model does.
;;
;;   `step-mcat` runs the codelet and increments the count AFTERWARDS, so the
;;   first codelet of a run executes with *codelet-count* still 0. Every time
;;   stamp and every age in the model is measured against that count.
;;
;; The memory is deliberately NOT cleared between problems, as it is not in a
;; real session: `init-mcat` clears its ACTIVATIONS only. So the later problems
;; run against a memory that already holds the earlier answers, and reminding
;; is live.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define sn (lambda (n) (if (exists? n) (tell n 'get-short-name) "*")))
(define yn (lambda (b) (if b "y" "n")))

(define join
  (lambda (strings)
    (if (null? strings)
      "-"
      (let loop ((l (rest strings)) (acc (1st strings)))
        (if (null? l) acc (loop (rest l) (string-append acc "," (1st l))))))))

(define count-of
  (lambda (type structures)
    (count (lambda (s) (eq? (tell s 'object-type) type)) structures)))

;; --- the state the run ended in ---------------------------------------------

(define dump-final-state
  (lambda (tag)
    (let ((structures (tell *workspace* 'get-structures))
          (objects (tell *workspace* 'get-objects)))
      (printf "ST\t~a\t~a\tb~a/g~a/x~a/r~a\to~a\tcr~a~%" tag *temperature*
        (count-of 'bond structures) (count-of 'group structures)
        (count-of 'bridge structures) (count-of 'rule structures)
        (length objects)
        (tell *coderack* 'get-num-of-codelets))
      (printf "STU\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
        (tell *workspace* 'get-average-intra-string-unhappiness)
        (tell *workspace* 'get-average-unhappiness)
        (tell *workspace* 'get-min-mapping-strength)
        (tell *workspace* 'get-max-inter-string-unhappiness)
        (join (map (lambda (s) (format "~a" s))
                (tell *workspace* 'get-possible-rule-types)))))
    (printf "STC\t~a\t~a~%" tag
      (join
        (map-compress
          (lambda (ct)
            (let ((n (length
                       (filter
                         (lambda (k) (eq? (tell k 'get-codelet-type-name)
                                      (tell ct 'get-codelet-type-name)))
                         (tell *coderack* 'get-all-codelets)))))
              (if (zero? n) #f (format "~a:~a" (tell ct 'get-codelet-type-name) n))))
          *codelet-types*)))
    (printf "STN\t~a\t~a~%" tag
      (join (map (lambda (n) (format "~a:~a" (sn n) (tell n 'get-activation)))
              *top-down-slipnodes*)))
    (printf "STT\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
      (length (tell *themespace* 'get-all-themes))
      (join (map (lambda (s) (format "~a" s))
              (tell *themespace* 'get-active-theme-types)))
      (length (tell *trace* 'get-all-events))
      (yn (tell *trace* 'within-snag-period?))
      (yn (tell *trace* 'within-clamp-period?)))
    ;; every event the run left in the trace, in order
    (for* each e in (reverse (tell *trace* 'get-all-events)) do
      (printf "EV\t~a\t~a\t~a\t~a~%" tag
        (tell e 'get-event-number) (tell e 'get-type) (tell e 'print-name)))))

;; --- what the run concluded, as the memory holds it -------------------------

(define dump-memory
  (lambda (tag)
    (printf "MEM\t~a\t~a\t~a~%" tag
      (length (tell *memory* 'get-answers))
      (length (tell *memory* 'get-snags)))
    (for* each a in (tell *memory* 'get-answers) do
      (printf "MA\t~a\t~a\t~a\t~a\t~a\t~a~%" tag
        (tell a 'problem-print-name) (tell a 'get-answer-print-name)
        (tell a 'get-quality) (tell a 'get-temperature)
        (tell a 'get-activation)))
    (for* each s in (tell *memory* 'get-snags) do
      (printf "MS\t~a\t~a\t~a\t~a~%" tag
        (tell s 'problem-print-name) (tell s 'get-explanation)
        (tell s 'get-activation)))))

;; --- probe -------------------------------------------------------------------

(define probe
  (lambda (tag i m t seed limit)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" tag i m t seed limit)
    (let ((outcome (run-problem i m t seed limit)))
      (printf "OUTCOME\t~a\t~a\t~a\t~a~%" tag outcome *codelet-count* *temperature*))
    (dump-final-state tag)
    (dump-memory tag)))

;; Short budgets first, so the loop's own bookkeeping is compared before any
;; answer can end a run: the unclamp time, the every-fifteenth update, and the
;; refill when the rack empties.
(probe 'budget50 'abc 'abd 'ijk 1001 50)
(probe 'budget200 'abc 'abd 'mrrjjj 1003 200)
(probe 'budget800 'mrrjjj 'mrrkkk 'xyz 1005 800)
;; Then long enough to finish, on the problem the reference runner uses.
(probe 'full1 'abc 'cba 'pqrs 42 20000)
(probe 'full2 'abc 'abd 'ijk 7 20000)
;; And once more on a problem already in memory, so reminding is live.
(probe 'again 'abc 'cba 'pqrs 99 20000)
