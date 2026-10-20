;; JUSTIFY MODE -- the model run end to end with a FOURTH STRING.
;;
;; `%justify-mode%` is what Metacat does when you give it the answer as well as
;; the problem and ask WHY. The flag is small; what it turns on is not. The
;; workspace gains an answer string, so there are BOTTOM bridges (target to
;; answer) to build and a BOTTOM rule to find; `*all-strings*` gains a member,
;; so every scout that picks a string to work in can pick that one; the target
;; string is now mapped in two directions at once, so its objects have a
;; horizontal unhappiness and salience they never had; the bottom themespace
;; clusters come alive; and the `answer-justifier` replaces the `answer-finder`
;; as the codelet a new rule posts.
;;
;; The Scheme has 64 non-graphics `%justify-mode%` branches across sixteen
;; files, and NOT ONE of them runs in any other probe in this suite. This probe
;; is the only thing that exercises them, which is why it drives whole runs
;; rather than hand-built state: the interactions are the point.
;;
;; The interesting arm is the one where the two halves DON'T line up. The
;; answer-justifier translates a rule from one half and looks for the matching
;; rule in the other; failing to find one, it CLAMPS the two rules it has
;; together with the theme pattern that would unify them, and waits for the
;; workspace to bear that out. That clamp is a trace event, so a run that keeps
;; making it is a run the jootser will eventually notice -- which is what
;; `joots-from-justify-clamps` is for, and it is reachable for the first time
;; here.
;;
;; The memory is deliberately NOT cleared between problems, as it is not in a
;; real session: `init-mcat` clears its ACTIVATIONS only.
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
    ;; the justify-mode half of the workspace, which no other probe has
    (printf "STJ\t~a\tr~a/~a\tx~a/~a/~a\tm~a/~a/~a\tu~a/~a/~a\t~a~%" tag
      (length (tell *workspace* 'get-rules 'top))
      (length (tell *workspace* 'get-rules 'bottom))
      (length (tell *workspace* 'get-bridges 'top))
      (length (tell *workspace* 'get-bridges 'bottom))
      (length (tell *workspace* 'get-bridges 'vertical))
      (tell *workspace* 'get-mapping-strength 'top)
      (tell *workspace* 'get-mapping-strength 'bottom)
      (tell *workspace* 'get-mapping-strength 'vertical)
      (tell *workspace* 'get-average-inter-string-unhappiness 'top)
      (tell *workspace* 'get-average-inter-string-unhappiness 'bottom)
      (tell *workspace* 'get-average-inter-string-unhappiness 'vertical)
      (join (map (lambda (s) (format "~a" s))
              (tell *workspace* 'get-possible-rule-types))))
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
        (tell a 'get-activation))
      ;; Whether the model could JUSTIFY the answer, and if not, which
      ;; slippages it could not account for. An answer carrying unjustified
      ;; slippages can only have come from `joots-from-justify-clamps`: every
      ;; other call to `report-new-answer` passes '() here. So this line is the
      ;; visible trace of the model settling for an answer it cannot defend.
      (printf "MAJ\t~a\t~a\t~a\t~a~%" tag (tell a 'get-answer-print-name)
        (yn (tell a 'unjustified?))
        (join (tell-all (tell a 'get-unjustified-slippages) 'english-name))))
    (for* each s in (tell *memory* 'get-snags) do
      (printf "MS\t~a\t~a\t~a\t~a~%" tag
        (tell s 'problem-print-name) (tell s 'get-explanation)
        (tell s 'get-activation)))))

;; --- probe -------------------------------------------------------------------

(define probe
  (lambda (tag i m t a seed limit)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" tag i m t a seed limit)
    (let ((outcome (run-justify-problem i m t a seed limit)))
      (printf "OUTCOME\t~a\t~a\t~a\t~a~%" tag outcome *codelet-count* *temperature*))
    (dump-final-state tag)
    (dump-memory tag)))

;; Short budgets first, so the loop's bookkeeping in justify mode is compared
;; before any answer can end a run: four strings to pick from, bottom bridges
;; being scouted, and the bottom rule's possibility being checked every cycle.
(probe 'budget60 'abc 'abd 'ijk 'ijl 2001 60)
(probe 'budget250 'abc 'cba 'pqrs 'srqp 2002 250)
(probe 'budget700 'mrrjjj 'mrrkkk 'xyz 'xyd 2003 700)
;; Then long enough to justify, or to fail to.
(probe 'full1 'abc 'abd 'ijk 'ijl 42 20000)
(probe 'full2 'abc 'cba 'pqrs 'srqp 7 20000)
;; A literal answer, where the bottom rule is verbatim and the halves do not
;; unify -- the clamping arm.
(probe 'literal 'abc 'abd 'ijk 'ijd 11 20000)
;; And one already in memory, so reminding is live in justify mode too.
(probe 'again 'abc 'abd 'ijk 'ijl 99 20000)

;; And a WRONG answer, which the model cannot justify however hard it tries:
;; it clamps the rules together over and over, and the jootser eventually
;; notices the repetition and gives up. That run exercises the jootser inside
;; justify mode, which nothing else does.
(probe 'wrong 'abc 'abd 'ijk 'xyz 6 12000)

;; SETTLING FOR AN UNJUSTIFIED ANSWER -- `joots-from-justify-clamps`, the one
;; jootser arm that does not give up.
;;
;; Three EQUIVALENT justify clamps have to be the most recent cluster in the
;; trace, and the gate is narrow: for a justify clamp the clamp-type factor is
;; 1 only when the trace's LAST event is itself a clamp, and the jootser also
;; refuses to look while a clamp period is running. Then, having re-translated
;; the clamped top rule, it settles with probability 1/n for n unjustified
;; slippages.
;;
;; `mrrjjj -> mrrjjjj` is the case the Scheme's own comment discusses -- the
;; bottom rule increases the length of the j group, and the top rule cannot be
;; walked onto it cleanly. Here the model clamps the two rules together
;; repeatedly, notices the repetition, and settles: the answer it reports
;; carries the slippages it could not account for, which the MAJ line shows.
;; No other configuration in this suite reaches that arm.
(probe 'unjustified 'abc 'abd 'mrrjjj 'mrrjjjj 6 10000)
