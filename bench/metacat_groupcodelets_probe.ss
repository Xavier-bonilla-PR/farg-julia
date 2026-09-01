;; Runs the group codelet pipeline through the real coderack, alongside bond
;; and description codelets, so groups form over real bonds and the builder's
;; fights and consolidation branches get exercised.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))

(define count-proposed-groups
  (lambda ()
    (apply +
      (map (lambda (str)
             (- (length (tell str 'get-all-groups)) (length (tell str 'get-groups))))
        (list *initial-string* *modified-string* *target-string*)))))

(define probe
  (lambda (i m t seed n temp mode)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp mode)
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
                             plato-bond-category plato-length plato-group-category
                             plato-direction-category plato-samegrp plato-succgrp
                             plato-predgrp plato-left plato-right) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    ;; Phase 1: bonds only. Group scouts need runs of bonds to find, so
    ;; posting them from the start just makes them fizzle.
    (let loop ((k 0))
      (when (< k 25)
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%))
        (loop (+ k 1))))
    (let loop ((c 0))
      (when (and (< c 120) (not (tell *coderack* 'empty?)))
        (set! *codelet-count* c)
        (let ((codelet (tell *coderack* 'choose-codelet)))
          (printf "WARM\t~a\t~a\t~a~%" c
            (tell codelet 'get-codelet-type-name)
            (tell *coderack* 'get-num-of-codelets))
          (tell codelet 'run))
        (update-workspace-values)
        (loop (+ c 1))))
    ;; Phase 2: now post the group codelets over the bonds that exist.
    (let loop ((k 0))
      (when (< k 20)
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%))
        (tell *coderack* 'post
          (tell group-scout:whole-string 'make-codelet %low-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-description-scout 'make-codelet %very-low-urgency%))
        (case mode
          (category
            (tell *coderack* 'post
              (tell top-down-group-scout:category 'make-codelet %low-urgency%
                plato-succgrp *workspace*))
            (tell *coderack* 'post
              (tell top-down-group-scout:category 'make-codelet %low-urgency%
                plato-samegrp *initial-string*)))
          (direction
            (tell *coderack* 'post
              (tell top-down-group-scout:direction 'make-codelet %low-urgency%
                plato-right *workspace*))
            (tell *coderack* 'post
              (tell top-down-group-scout:direction 'make-codelet %low-urgency%
                plato-left *target-string*)))
          (else 'none))
        (loop (+ k 1))))
    (let loop ((c 0))
      (when (and (< c n) (not (tell *coderack* 'empty?)))
        (set! *codelet-count* c)
        (let ((codelet (tell *coderack* 'choose-codelet)))
          (printf "RUN\t~a\t~a\t~a\t~a\t~a~%" c
            (tell codelet 'get-codelet-type-name)
            (round (tell codelet 'get-relative-urgency))
            (tell *coderack* 'get-num-of-codelets)
            (count-proposed-groups))
          (tell codelet 'run))
        (update-workspace-values)
        (loop (+ c 1))))
    (for-each
      (lambda (string)
        (for-each
          (lambda (g)
            (printf "GROUP\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type) (tell g 'ascii-name)
              (nm (tell g 'get-group-category)) (nm (tell g 'get-direction))
              (nm (tell g 'get-bond-facet)) (tell g 'get-group-length)
              (tell g 'get-letter-span) (tell g 'get-strength)
              (tell g 'get-proposal-level))
            (let loop ((k 0) (ds (tell g 'get-all-descriptions)))
              (when (not (null? ds))
                (printf "GDESC\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
                  (tell g 'ascii-name) k (tell (1st ds) 'print-name))
                (loop (add1 k) (rest ds))))
            (let loop ((k 0) (bs (tell g 'get-constituent-bonds)))
              (when (not (null? bs))
                (printf "GBOND\t~a\t~a\t~a\t~a>~a~%" (tell string 'get-string-type)
                  (tell g 'ascii-name) k
                  (tell (tell (1st bs) 'get-left-object) 'ascii-name)
                  (tell (tell (1st bs) 'get-right-object) 'ascii-name))
                (loop (add1 k) (rest bs)))))
          (reverse (tell string 'get-groups)))
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
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name) (tell o 'get-intra-string-unhappiness)
              (tell o 'get-intra-string-salience) (tell o 'get-relative-importance)
              (if (exists? (tell o 'get-enclosing-group))
                (tell (tell o 'get-enclosing-group) 'ascii-name) "-")))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))
    (printf "CODERACK\t~a\t~a~%" (tell *coderack* 'get-num-of-codelets)
      (count-proposed-groups))
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a~%" (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)))

(probe 'abc 'abd 'ijk 4242 200 70 'none)
(probe 'abc 'abd 'mrrjjj 1357 250 80 'category)
(probe 'abcde 'abcdf 'pqrst 2468 300 60 'direction)
;; the doubled strings exercise sameness groups, and so the consolidation
;; branch of group-builder
(probe 'iijjkk 'iijjll 'mmnnoo 8642 400 90 'category)
(probe 'aabbcc 'aabbdd 'xxyyzz 9753 400 80 'direction)
(probe 'mrrjjj 'mrrkkk 'xppqqq 1111 400 85 'category)
