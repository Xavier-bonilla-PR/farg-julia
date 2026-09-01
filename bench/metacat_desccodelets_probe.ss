;; Runs the description codelet pipeline through the real coderack for N
;; codelets, dumping every codelet run and every description that survives.
;;
;; The rack is seeded with bottom-up description scouts, plus top-down scouts
;; for four description types and two kinds of scope (one string, and the whole
;; workspace), which is what puts every one of the slipnet's descriptor
;; predicates in reach. The last two problems pre-build a spanning group so
;; that the Length and ObjCtgy:group predicates can fire at all.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))

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

(define probe
  (lambda (i m t seed n temp make-groups?)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp
      (if make-groups? "y" "n"))
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
                             plato-direction-category plato-length
                             plato-alphabetic-position-category) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (if* make-groups?
      (build-chain-and-group *initial-string*)
      (build-chain-and-group *target-string*))
    (update-workspace-values)
    (random-seed seed)
    (let loop ((k 0))
      (when (< k 8)
        (tell *coderack* 'post
          (tell bottom-up-description-scout 'make-codelet %very-low-urgency%))
        (loop (+ k 1))))
    ;; top-down scouts: every description type that has descriptor predicates,
    ;; against both kinds of scope
    (for-each
      (lambda (description-type)
        (let loop ((k 0))
          (when (< k 5)
            (tell *coderack* 'post
              (tell top-down-description-scout 'make-codelet %low-urgency%
                description-type *initial-string*))
            (tell *coderack* 'post
              (tell top-down-description-scout 'make-codelet %low-urgency%
                description-type *workspace*))
            (loop (+ k 1)))))
      (list plato-length plato-string-position-category plato-object-category
            plato-alphabetic-position-category))
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
    (for-each
      (lambda (string)
        (for-each
          (lambda (o)
            (for-each
              (lambda (d)
                (printf "DESC\t~a\t~a\t~a\t~a\t~a\t~a~%"
                  (tell string 'get-string-type) (tell o 'ascii-name)
                  (nm (tell d 'get-description-type)) (nm (tell d 'get-descriptor))
                  (tell d 'get-strength) (tell d 'get-proposal-level)))
              (tell o 'get-all-descriptions))
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type) (tell o 'ascii-name)
              (tell o 'get-raw-importance) (tell o 'get-relative-importance)
              (tell o 'get-average-salience) (tell o 'get-intra-string-salience)))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a~%" (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)))

(probe 'abc 'abd 'ijk 4242 80 50 #f)
(probe 'azb 'azc 'xyz 1717 100 40 #f)
;; single-letter strings: the only way plato-single can describe anything
(probe 'a 'b 'c 6161 60 50 #f)
;; grouped strings of two, three, four and five, so that the Length descriptors
;; plato-two .. plato-five each have something they can describe. plato-one
;; needs a singleton group, which only the group codelets can make.
(probe 'ab 'ac 'yz 12 140 50 #t)
(probe 'abc 'abd 'xyz 5150 180 50 #t)
(probe 'abcd 'abce 'wxyz 7 220 60 #t)
(probe 'abcde 'abcdf 'pqrst 3030 240 70 #t)
