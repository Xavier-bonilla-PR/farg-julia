;; Runs the description codelet pipeline through the real coderack, mixed with
;; bond scouts so the coderack fills and overflows -- which is what exercises
;; the proposed-structure bookkeeping on codelet eviction.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))

(define probe
  (lambda (i m t seed n temp top-down? nseed)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
      i m t seed n temp top-down? nseed)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
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
                             plato-bond-category plato-length
                             plato-alphabetic-position-category) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    (let loop ((k 0))
      (when (< k nseed)
        (tell *coderack* 'post
          (tell bottom-up-description-scout 'make-codelet %very-low-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%))
        ;; NB plain `if`, not `if*`: Metacat's if* is a `when` and would run
        ;; BOTH branches when the test is true and neither when it is false.
        (if top-down?
          (tell *coderack* 'post
            (tell top-down-description-scout 'make-codelet %low-urgency%
              plato-alphabetic-position-category *workspace*))
          (tell *coderack* 'post
            (tell top-down-description-scout 'make-codelet %low-urgency%
              plato-string-position-category *initial-string*)))
        (loop (+ k 1))))
    (let loop ((c 0))
      (when (and (< c n) (not (tell *coderack* 'empty?)))
        (set! *codelet-count* c)
        (let ((codelet (tell *coderack* 'choose-codelet)))
          (printf "RUN\t~a\t~a\t~a\t~a\t~a~%" c
            (tell codelet 'get-codelet-type-name)
            (round (tell codelet 'get-relative-urgency))
            (tell *coderack* 'get-num-of-codelets)
            ;; total proposed-but-unbuilt bonds: this is what codelet eviction
            ;; has to keep straight, so track it every step
            (apply +
              (map (lambda (str)
                     (- (length (tell str 'get-all-bonds))
                        (length (tell str 'get-bonds))))
                (list *initial-string* *modified-string* *target-string*))))
          (tell codelet 'run))
        (update-workspace-values)
        (loop (+ c 1))))
    ;; every description on every object, in list order, with strengths
    (for-each
      (lambda (string)
        (for* each o in (tell string 'get-objects) do
          (let loop ((k 0) (ds (tell o 'get-all-descriptions)))
            (when (not (null? ds))
              (printf "DESC\t~a\t~a\t~a\t~a\t~a\t~a~%"
                (tell string 'get-string-type) (tell o 'ascii-name) k
                (tell (1st ds) 'print-name)
                (tell (1st ds) 'get-proposal-level)
                (tell (1st ds) 'get-strength))
              (loop (add1 k) (rest ds)))))
        (for-each
          (lambda (b)
            (printf "BOND\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type)
              (tell (tell b 'get-left-object) 'ascii-name)
              (tell (tell b 'get-right-object) 'ascii-name)
              (nm (tell b 'get-bond-category)) (nm (tell b 'get-direction))
              (nm (tell b 'get-bond-facet)) (tell b 'get-strength)))
          (reverse (tell string 'get-bonds)))
        ;; proposed bonds still registered: the eviction bookkeeping shows here
        (printf "PROPOSED\t~a\t~a~%" (tell string 'get-string-type)
          (- (length (tell string 'get-all-bonds))
             (length (tell string 'get-bonds))))
        (for-each
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name) (tell o 'get-intra-string-unhappiness)
              (tell o 'get-intra-string-salience) (tell o 'get-relative-importance)))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))
    (printf "CODERACK\t~a~%" (tell *coderack* 'get-num-of-codelets))
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a~%" (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)))

;; The first three drain the rack; the last two seed past %max-coderack-size%
;; (100) so every further post evicts a codelet -- including, once evaluators
;; are in flight, ones carrying a proposed bond.
;; A codelet carrying a proposed structure is normally chosen to RUN long
;; before it is old enough to be evicted -- high urgency puts it in the top
;; bin, and removal weight favours old, low-urgency codelets. So drive the
;; eviction path directly: park bond-evaluators at the lowest urgency, flood
;; the rack to %max-coderack-size% with high-urgency codelets, and keep
;; posting. Each further post evicts one codelet, and the parked evaluators
;; are now the preferred victims -- at which point the coderack has to
;; unregister the proposed bond each was carrying.
(define seed-proposed-bond
  (lambda (string p)
    (let* ((o1 (tell string 'get-letter p))
           (o2 (tell string 'get-letter (add1 p)))
           (d1 (tell o1 'get-descriptor-for plato-letter-category))
           (d2 (tell o2 'get-descriptor-for plato-letter-category))
           (cat (get-bond-category d1 d2)))
      (if* (exists? cat)
        (let ((b (make-bond o1 o2 cat plato-letter-category d1 d2)))
          (tell string 'add-proposed-bond b)
          (tell b 'update-proposal-level %proposed%)
          (tell *coderack* 'post
            (tell bond-evaluator 'make-codelet %extremely-low-urgency% b)))))))

(define count-proposed
  (lambda ()
    (apply +
      (map (lambda (str)
             (- (length (tell str 'get-all-bonds)) (length (tell str 'get-bonds))))
        (list *initial-string* *modified-string* *target-string*)))))

(define eviction-probe
  (lambda (i m t seed)
    (printf "EVICT-PROBLEM\t~a\t~a\t~a\t~a~%" i m t seed)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (for* each node in (list plato-letter-category plato-successor plato-predecessor
                             plato-sameness plato-bond-facet plato-bond-category) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* 50)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    (for* each str in (list *initial-string* *modified-string* *target-string*) do
      (let loop ((p 0))
        (when (< p (sub1 (tell str 'get-length)))
          (seed-proposed-bond str p)
          (loop (add1 p)))))
    (printf "EVICT-SEEDED\t~a\t~a~%" (tell *coderack* 'get-num-of-codelets)
      (count-proposed))
    ;; age the parked codelets, then fill to capacity with high-urgency codelets
    (set! *codelet-count* 500)
    (let loop ((k 0))
      (when (< k 120)
        (set! *codelet-count* (+ 500 k))
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %extremely-high-urgency%))
        (printf "EVICT\t~a\t~a\t~a~%" k
          (tell *coderack* 'get-num-of-codelets) (count-proposed))
        (loop (add1 k))))))

(probe 'abc 'abd 'ijk 3141 80 50 #f 15)
(probe 'abc 'abd 'mrrjjj 2718 120 40 #t 15)
(probe 'abcde 'abcdf 'pqrst 1618 150 70 #f 15)
(probe 'abcde 'abcdf 'pqrst 2024 120 50 #f 60)
(probe 'iijjkk 'iijjll 'mmnnoo 4096 200 30 #t 55)

(eviction-probe 'abcde 'abcdf 'pqrst 777)
(eviction-probe 'iijjkk 'iijjll 'mmnnoo 888)
