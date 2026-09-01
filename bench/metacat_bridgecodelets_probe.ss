;; Runs the bridge codelet pipeline through the real coderack for N codelets,
;; dumping every codelet run and the resulting workspace state.
;;
;; The last two problems pre-build a spanning group in the initial and target
;; strings, which is what puts group-incompatible bridges, direction-
;; incompatible bridges and group flipping in reach. All three strings are the
;; same length there, so no bridge ever spans objects of different lengths and
;; the description/group scouts propose-bridge would post in that case (not
;; ported yet) are never reached.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))

;; With reversed? true the bonds are scanned right to left, which is what
;; makes a group whose direction is `left`: the only way to get a pair of
;; spanning groups related by Opposite on BOTH group category and direction,
;; and so the only way a bridge between them asks to flip one.
(define build-chain-and-group
  (lambda (string reversed?)
    (let* ((n (tell string 'get-length))
           (bonds
             (let loop ((p 0) (acc '()))
               (if (>= p (sub1 n))
                 (reverse acc)
                 (let* ((oa (tell string 'get-letter p))
                        (ob (tell string 'get-letter (add1 p)))
                        (o1 (if reversed? ob oa))
                        (o2 (if reversed? oa ob))
                        (d1 (tell o1 'get-descriptor-for plato-letter-category))
                        (d2 (tell o2 'get-descriptor-for plato-letter-category))
                        (cat (get-bond-category d1 d2)))
                   (if (not (exists? cat))
                     (loop (add1 p) acc)
                     (let ((b (make-bond o1 o2 cat plato-letter-category d1 d2)))
                       (build-bond b)
                       (loop (add1 p) (cons b acc)))))))))
      (if (and (not (null? bonds))
               (= (length bonds) (sub1 n)))
        (let* ((cat (tell (1st bonds) 'get-bond-category))
               (dir (tell (1st bonds) 'get-direction))
               (gcat (tell cat 'get-related-node plato-group-category))
               (objs (cons (tell (1st bonds) 'get-left-object)
                       (map (lambda (b) (tell b 'get-right-object)) bonds))))
          (build-group
            (make-group string gcat plato-letter-category dir
              (1st objs) (nth (sub1 (length objs)) objs) objs bonds)
            #f))))))

(define dump-bridges
  (lambda (bridge-type)
    (for-each
      (lambda (b)
        (printf "BRIDGE\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
          bridge-type (tell b 'get-orientation)
          (tell (tell b 'get-object1) 'ascii-name)
          (tell (tell b 'get-object2) 'ascii-name)
          (yn (tell b 'spanning-bridge?))
          (yn (tell b 'flipped-group1?)) (yn (tell b 'flipped-group2?))
          (tell b 'get-strength) (tell b 'get-proposal-level))
        (for-each
          (lambda (cm)
            (printf "BRIDGECM\t~a\t~a\t~a\t~a\t~a~%" bridge-type
              (tell cm 'print-name) (nm (tell cm 'get-label))
              (yn (tell cm 'slippage?)) (tell cm 'get-strength)))
          (tell b 'get-all-concept-mappings))
        (for-each
          (lambda (ss)
            (printf "BRIDGESS\t~a\t~a~%" bridge-type (tell ss 'print-name)))
          (tell b 'get-symmetric-slippages)))
      (reverse (tell *workspace* 'get-bridges bridge-type)))))

(define probe
  (lambda (i m t seed n temp make-groups?)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp make-groups?)
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
                             plato-bond-category plato-group-category
                             plato-direction-category plato-length) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (if* (not (eq? make-groups? 'none))
      (build-chain-and-group *initial-string* #f)
      (build-chain-and-group *target-string* (eq? make-groups? 'flip)))
    (update-workspace-values)
    (random-seed seed)
    ;; Seed the rack with the two bridge scouts, plus bond scouts so that bonds
    ;; and bridges get to fight each other. The flip problems leave the bond
    ;; scouts out: their target group is built from right-to-left bonds, and a
    ;; bond scout proposing the left-to-right reading would break it up before
    ;; any bridge got to ask for a flip.
    (let ((num-of-scouts (if (eq? make-groups? 'flip) 20 10)))
      (let loop ((k 0))
        (when (< k num-of-scouts)
          (if* (not (eq? make-groups? 'flip))
            (tell *coderack* 'post
              (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%)))
          (tell *coderack* 'post
            (tell bottom-up-bridge-scout 'make-codelet %very-low-urgency%))
          (tell *coderack* 'post
            (tell important-object-bridge-scout 'make-codelet %very-low-urgency%))
          (loop (+ k 1)))))
    (let loop ((c 0))
      (when (and (< c n) (not (tell *coderack* 'empty?)))
        (set! *codelet-count* c)
        (let ((codelet (tell *coderack* 'choose-codelet)))
          (printf "RUN\t~a\t~a\t~a\t~a~%" c
            (tell codelet 'get-codelet-type-name)
            (round (tell codelet 'get-relative-urgency))
            (tell *coderack* 'get-num-of-codelets))
          (tell codelet 'run))
        (update-workspace-values)
        (loop (+ c 1))))
    (printf "MAP\t~a\t~a~%"
      (inexact->exact (round (tell *workspace* 'get-mapping-strength 'top)))
      (inexact->exact (round (tell *workspace* 'get-mapping-strength 'vertical))))
    (for-each dump-bridges '(top vertical))
    (for-each
      (lambda (string)
        (for-each
          (lambda (b)
            (printf "BOND\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type)
              (tell (tell b 'get-left-object) 'ascii-name)
              (tell (tell b 'get-right-object) 'ascii-name)
              (nm (tell b 'get-bond-category)) (nm (tell b 'get-direction))
              (nm (tell b 'get-bond-facet)) (tell b 'get-strength)))
          (reverse (tell string 'get-bonds)))
        (for-each
          (lambda (g)
            (printf "GROUP\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type) (tell g 'ascii-name)
              (nm (tell g 'get-group-category)) (nm (tell g 'get-direction))
              (tell g 'get-strength)))
          (reverse (tell string 'get-groups)))
        (for-each
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type) (tell o 'ascii-name)
              (tell o 'get-intra-string-unhappiness)
              (tell o 'get-intra-string-salience)
              (tell o 'get-inter-string-salience 'horizontal)
              (tell o 'get-inter-string-salience 'vertical)
              (tell o 'get-average-unhappiness)
              (tell o 'get-relative-importance)))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a~%" (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)))

(probe 'abc 'abd 'ijk 1234 60 50 'none)
(probe 'abc 'abd 'mrrjjj 5678 90 40 'none)
(probe 'abcde 'abcdf 'pqrst 9012 120 70 'none)
(probe 'abc 'abd 'cba 3141 120 50 'plain)
(probe 'abc 'abd 'xyz 2718 120 60 'plain)
(probe 'abc 'abd 'abc 2 200 50 'flip)
(probe 'abcd 'abce 'abcd 10 200 40 'flip)
