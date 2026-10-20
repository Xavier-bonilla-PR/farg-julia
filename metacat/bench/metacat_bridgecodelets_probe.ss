;; Runs the bridge codelet pipeline through the real coderack for N codelets,
;; dumping every codelet run and the bridges that survive.
;;
;; Bond and group scouts are seeded alongside the bridge scouts, because a
;; bridge worth building usually spans structures the other two have to make
;; first — and because the interesting fights are between them: a bridge that
;; wants a group flipped has to beat the group that is already there.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))
(define num
  (lambda (v)
    (if (integer? v)
      (number->string v)
      (format "~a/~a" (numerator v) (denominator v)))))

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
          (tell important-object-bridge-scout 'make-codelet %medium-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-description-scout 'make-codelet %very-low-urgency%))
        (loop (+ k 1))))))

(define probe
  (lambda (i m t seed n temp)
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
    (seed-rack)
    (let loop ((c 0))
      (when (and (< c n) (not (tell *coderack* 'empty?)))
        (if* (and (> c 0) (zero? (modulo c %update-cycle-length%)))
          (seed-rack))
        (set! *codelet-count* c)
        (let ((codelet (tell *coderack* 'choose-codelet)))
          (printf "RUN\t~a\t~a\t~a\t~a" c
            (tell codelet 'get-codelet-type-name)
            (round (tell codelet 'get-relative-urgency))
            (tell *coderack* 'get-num-of-codelets))
          (tell codelet 'run)
          ;; a workspace fingerprint after every codelet, so a divergence
          ;; localises to the codelet that caused it
          (printf "\t~a\t~a\t~a\t~a\t~a\t~a~%"
            (length (tell *workspace* 'get-bonds))
            (length (tell *workspace* 'get-groups))
            (length (tell *workspace* 'get-all-bridges))
            (tell *workspace* 'get-mapping-strength 'top)
            (tell *workspace* 'get-mapping-strength 'vertical)
            (sum (map (lambda (o) (tell o 'get-average-salience))
                   (tell *workspace* 'get-objects)))))
        (update-workspace-values)
        (loop (+ c 1))))
    (for-each
      (lambda (bridge-type)
        (for-each
          (lambda (b)
            (printf "BRIDGE\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" bridge-type
              (tell (tell b 'get-object1) 'ascii-name)
              (tell (tell b 'get-object2) 'ascii-name)
              (yn (tell b 'spanning-bridge?))
              (yn (tell b 'flipped-group1?)) (yn (tell b 'flipped-group2?))
              (tell b 'get-letter-span) (tell b 'get-strength))
            (printf "BRSTR\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" bridge-type
              (tell (tell b 'get-object1) 'ascii-name)
              (tell (tell b 'get-object2) 'ascii-name)
              (tell b 'calculate-internal-strength)
              (tell b 'calculate-external-strength)
              (yn (tell b 'internally-coherent?))
              (length (tell b 'get-relevant-distinguishing-CMs)))
            (for-each
              (lambda (cm)
                (printf "BRCM\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" bridge-type
                  (tell (tell b 'get-object1) 'ascii-name)
                  (tell (tell b 'get-object2) 'ascii-name)
                  (tell cm 'print-name) (nm (tell cm 'get-label))
                  (yn (tell cm 'slippage?))
                  (yn (member? cm (tell b 'get-concept-mappings)))
                  (yn (tell cm 'relevant?)) (yn (tell cm 'distinguishing?))))
              (tell b 'get-all-concept-mappings)))
          (reverse (tell *workspace* 'get-bridges bridge-type))))
      '(top vertical))
    (for-each
      (lambda (string)
        (for-each
          (lambda (b)
            (printf "BOND\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type)
              (tell (tell b 'get-left-object) 'ascii-name)
              (tell (tell b 'get-right-object) 'ascii-name)
              (nm (tell b 'get-bond-category)) (nm (tell b 'get-direction))
              (tell b 'get-strength)))
          (reverse (tell string 'get-bonds)))
        (for-each
          (lambda (g)
            (printf "GROUP\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type) (tell g 'ascii-name)
              (nm (tell g 'get-group-category)) (nm (tell g 'get-direction))
              (nm (tell g 'get-bond-facet)) (tell g 'get-strength)))
          (reverse (tell string 'get-groups)))
        (for-each
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name) (num (tell o 'get-raw-importance))
              (tell o 'get-relative-importance)
              (tell o 'get-inter-string-unhappiness 'horizontal)
              (tell o 'get-inter-string-unhappiness 'vertical)
              (tell o 'get-average-salience)
              (map (lambda (d) (tell d 'print-name)) (tell o 'get-all-descriptions))))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))
    (printf "WS\t~a\t~a\t~a\t~a\t~a~%"
      (tell *workspace* 'get-average-intra-string-unhappiness)
      (tell *workspace* 'get-average-unhappiness)
      (tell *workspace* 'get-mapping-strength 'top)
      (tell *workspace* 'get-mapping-strength 'vertical)
      (tell *workspace* 'get-min-mapping-strength))
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a~%" (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)))

;; The flip path needs whole-string groups on BOTH sides at the same moment,
;; which random seeding reaches only by luck. This variant builds them directly
;; first — as metacat_bridges_probe.ss does — and then runs bridge codelets only,
;; so make-flipped-version, the flipped-group fights and the group-flipping half
;; of bridge-builder are all exercised deterministically.
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

(define flip-probe
  (lambda (i m t seed n temp)
    (printf "FLIPPROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (tell *themespace* 'initialize)
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (for* each obj in (tell *workspace* 'get-objects) do
      (for* each descriptor in (tell-all (tell obj 'get-descriptions) 'get-descriptor)
        do (tell descriptor 'set-activation %max-activation%)))
    ;; Direction-Category is clamped but Group-Category deliberately is NOT:
    ;; reverse-direction-orientation? requires every reversible concept mapping
    ;; to map by opposite, and a GroupCtgy:succgrp=>succgrp identity mapping
    ;; would veto it. With GroupCtgy inactive those descriptions are irrelevant,
    ;; so the scouts never build that mapping and the Direction mapping decides.
    (for* each node in (list plato-object-category plato-letter-category
                             plato-string-position-category plato-successor
                             plato-predecessor plato-sameness plato-bond-facet
                             plato-direction-category plato-left plato-right
                             plato-alphabetic-position-category plato-length) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    (for-each build-chain-and-group
      (list *initial-string* *modified-string* *target-string*))
    ;; turn the target's spanning group around, so that it and the initial
    ;; string's group map by opposite direction — the configuration a flipped
    ;; bridge exists to express
    (let ((g (tell *target-string* 'get-spanning-group)))
      (if* (exists? g)
        (let ((fg (tell g 'make-flipped-version)))
          (break-group g)
          (for* each bond in (tell g 'get-constituent-bonds) do (break-bond bond))
          (for* each bond in (tell fg 'get-constituent-bonds) do (build-bond bond))
          (build-group fg #t))))
    (update-workspace-values)
    ;; Propose the flipped bridge outright rather than waiting for a scout to
    ;; pick both spanning groups: this is the only way to reach the flipping
    ;; half of bridge-builder deterministically. The codelets that follow are
    ;; the real bridge-evaluator and bridge-builder.
    (let ((g1 (tell *initial-string* 'get-spanning-group))
          (g2 (tell *target-string* 'get-spanning-group)))
      (if* (and (exists? g1) (exists? g2))
        (let ((pb (propose-bridge 'vertical g1 #f g2 #t)))
          (printf "FPROPOSE\t~a\t~a\t~a\t~a\t~a~%"
            (tell (tell pb 'get-object1) 'ascii-name)
            (tell (tell pb 'get-object2) 'ascii-name)
            (yn (tell pb 'flipped-group2?))
            (length (tell pb 'get-concept-mappings))
            (map (lambda (cm) (tell cm 'print-name))
              (tell pb 'get-concept-mappings)))
          (post-codelet* urgency: %extremely-high-urgency% bridge-evaluator pb))))
    (let loop ((c 0))
      (when (and (< c n) (or (not (tell *coderack* 'empty?)) #t))
        (if* (zero? (modulo c 5))
          (let loop2 ((k 0))
            (when (< k 2)
              (tell *coderack* 'post
                (tell bottom-up-bridge-scout 'make-codelet %medium-urgency%))
              (tell *coderack* 'post
                (tell important-object-bridge-scout 'make-codelet %medium-urgency%))
              (loop2 (+ k 1)))))
        (set! *codelet-count* c)
        (if* (not (tell *coderack* 'empty?))
          (let ((codelet (tell *coderack* 'choose-codelet)))
            (printf "FRUN\t~a\t~a\t~a\t~a" c
              (tell codelet 'get-codelet-type-name)
              (round (tell codelet 'get-relative-urgency))
              (tell *coderack* 'get-num-of-codelets))
            (tell codelet 'run)
            (printf "\t~a\t~a\t~a~%"
              (length (tell *workspace* 'get-groups))
              (length (tell *workspace* 'get-all-bridges))
              (sum (map (lambda (o) (tell o 'get-average-salience))
                     (tell *workspace* 'get-objects))))))
        (update-workspace-values)
        (loop (+ c 1))))
    (for-each
      (lambda (bridge-type)
        (for-each
          (lambda (b)
            (printf "FBRIDGE\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" bridge-type
              (tell (tell b 'get-object1) 'ascii-name)
              (tell (tell b 'get-object2) 'ascii-name)
              (yn (tell b 'spanning-bridge?))
              (yn (tell b 'flipped-group1?)) (yn (tell b 'flipped-group2?))
              (tell b 'get-letter-span) (tell b 'get-strength)))
          (reverse (tell *workspace* 'get-bridges bridge-type))))
      '(top vertical))
    (for-each
      (lambda (string)
        (for-each
          (lambda (g)
            (printf "FGROUP\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type) (tell g 'ascii-name)
              (nm (tell g 'get-group-category)) (nm (tell g 'get-direction))
              (tell g 'get-strength)))
          (reverse (tell string 'get-groups)))
        (for-each
          (lambda (b)
            (printf "FBOND\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell (tell b 'get-left-object) 'ascii-name)
              (tell (tell b 'get-right-object) 'ascii-name)
              (nm (tell b 'get-bond-category)) (nm (tell b 'get-direction))))
          (reverse (tell string 'get-bonds))))
      (list *initial-string* *modified-string* *target-string*))))

(probe 'abc 'abd 'ijk 4001 400 50)
(probe 'abc 'abd 'mrrjjj 4002 700 40)
(probe 'abc 'cba 'pqrs 4003 700 30)
(probe 'abcde 'abcdf 'pqrst 4004 700 60)
;; abc <-> cba is the case flipped bridges exist for: two whole-string groups
;; that map by opposite direction, which is better said by reversing one group
;; than by slipping right=>left. Opposite is deliberately NOT clamped active
;; anywhere in this probe, since reverse-direction-orientation? requires it.
(probe 'abc 'abd 'cba 4005 900 30)
(probe 'abcd 'abcde 'dcba 4006 900 20)

(flip-probe 'abc 'abd 'cba 4101 200 30)
(flip-probe 'abcd 'abce 'dcba 4102 200 20)
(flip-probe 'abc 'abd 'kji 4103 200 40)
