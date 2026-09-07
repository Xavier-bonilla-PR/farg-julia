;; run.ss's per-cycle update: `update-everything` and everything it calls.
;;
;; This is what happens BETWEEN codelets. The workspace revalues itself, the
;; trace decides whether a snag or clamp has run its course, the bridges boost
;; the themes and the themespace settles, the slipnet spreads, the temperature
;; is recomputed, and the coderack is refilled from the bottom up while every
;; active slipnode posts its top-down codelets.
;;
;; It is the densest RNG consumer in the model, which is what makes it worth
;; probing on its own: `rough-num-of-objects` FUZZES its thresholds (two draws
;; each, and up to two calls), every `stochastic-if*` draws whether or not it
;; fires, and the slipnet and themespace updates draw again. A port that gets
;; the decisions right but the draw ORDER wrong diverges within a few cycles.
;;
;; The probe runs a genuine loop -- choose a codelet, run it, update everything
;; -- and dumps the whole model state every few cycles: temperature, the
;; coderack by type, the workspace by structure, the slipnet's activations, the
;; themespace, and the trace. Nothing is hand-driven.
;;
;; NB this is the first probe in which ACTIVE SLIPNODES post top-down codelets,
;; so it is the first that exercises top-down-bond-scout:category and
;; :direction. Reaching them takes a long run AND the right problem: the bond
;; categories only wake once bonds are being built, and bonds only get built
;; once the model has settled a little. abc->abd :: mrrjjj gets there (sameness
;; bonds in the j-run come cheap), and at 1500 cycles runs ~108 of them; the
;; short runs never leave temperature 100 and never build a bond at all. Both
;; regimes are probed, because they exercise different halves of the posting
;; logic.
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

(define count-of
  (lambda (type structures)
    (count (lambda (s) (eq? (tell s 'object-type) type)) structures)))

;; --- the whole model state, every few cycles ---------------------------------

(define dump-state
  (lambda (c)
    (let ((structures (tell *workspace* 'get-structures))
          (objects (tell *workspace* 'get-objects)))
      ;; NB there is no accessor for the deferred list, and it is empty by
      ;; construction after post-deferred-codelets, which update-everything
      ;; always ends with.
      (printf "ST\t~a\t~a\tb~a/g~a/x~a/r~a\to~a\tcr~a~%" c *temperature*
        (count-of 'bond structures) (count-of 'group structures)
        (count-of 'bridge structures) (count-of 'rule structures)
        (length objects)
        (tell *coderack* 'get-num-of-codelets))
      (printf "STU\t~a\t~a\t~a\t~a\t~a\t~a~%" c
        (tell *workspace* 'get-average-intra-string-unhappiness)
        (tell *workspace* 'get-average-unhappiness)
        (tell *workspace* 'get-min-mapping-strength)
        (tell *workspace* 'get-max-inter-string-unhappiness)
        (join (map (lambda (s) (format "~a" s))
                (tell *workspace* 'get-possible-rule-types))))
      (printf "STR\t~a\t~a\t~a\t~a~%" c
        (count unrelated? objects) (count ungrouped? objects)
        (count unmapped? objects)))
    ;; the coderack, by type
    (printf "STC\t~a\t~a~%" c
      (join
        (map-compress
          (lambda (ct)
            ;; A codelet exposes only its type NAME, not the type object.
            (let ((n (length
                       (filter
                         (lambda (k) (eq? (tell k 'get-codelet-type-name)
                                      (tell ct 'get-codelet-type-name)))
                         (tell *coderack* 'get-all-codelets)))))
              (if (zero? n) #f (format "~a:~a" (tell ct 'get-codelet-type-name) n))))
          *codelet-types*)))
    ;; the slipnet: the nodes that drive top-down posting
    (printf "STN\t~a\t~a~%" c
      (join (map (lambda (n) (format "~a:~a" (sn n) (tell n 'get-activation)))
              *top-down-slipnodes*)))
    ;; the themespace and the trace
    (printf "STT\t~a\t~a\t~a\t~a\t~a\t~a~%" c
      (length (tell *themespace* 'get-all-themes))
      (join (map (lambda (s) (format "~a" s))
              (tell *themespace* 'get-active-theme-types)))
      (length (tell *trace* 'get-all-events))
      (yn (tell *trace* 'within-snag-period?))
      (yn (tell *trace* 'within-clamp-period?)))))

;; --- probe -------------------------------------------------------------------

(define probe
  (lambda (i m t seed n temp every)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (tell *themespace* 'initialize)
    (tell *trace* 'initialize)
    (tell *memory* 'clear)
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (for* each node in *initially-clamped-slipnodes* do
      (tell node 'clamp %max-activation%))
    ;; Self-watching ON -- the real default from setup.ss. With jootsing.ss
    ;; ported, every codelet type the run loop posts now exists, so the loop
    ;; runs in the model's actual configuration: the jootser and
    ;; progress-watcher post and run, themes get created and boosted, and the
    ;; thematic-bridge-scout joins in.
    (set! *temperature* temp)
    (set! *temperature-clamped?* #f)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    (post-initial-codelets)
    (dump-state 0)
    (let loop ((c 1))
      (when (and (<= c n) (not (tell *coderack* 'empty?)))
        (set! *codelet-count* c)
        (tell (tell *coderack* 'choose-codelet) 'run)
        (update-everything)
        (if* (zero? (modulo c every))
          (dump-state c))
        (loop (+ c 1))))
    (dump-state 'final)))

;; the long runs, which get bonds and groups built and the top-down bond
;; scouts running
(probe 'abc 'abd 'mrrjjj 1003 1500 100 250)
(probe 'mrrjjj 'mrrkkk 'xyz 1005 1200 100 200)
;; the cold-start regime: nothing gets built, temperature never leaves 100
(probe 'abc 'abd 'ijk 1001 200 100 50)
(probe 'abc 'abd 'kji 1002 200 100 50)
(probe 'abc 'cba 'pqrs 1004 200 100 50)
(probe 'aabc 'aabd 'ijkk 1006 300 100 75)
