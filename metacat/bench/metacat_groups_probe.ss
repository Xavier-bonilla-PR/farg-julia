;; Builds bonds, then maximal same-category same-direction runs as groups,
;; and dumps every group property.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))

(define build-bond-chain
  (lambda (string)
    (let ((n (tell string 'get-length)))
      (let loop ((p 0) (acc '()))
        (if (>= p (sub1 n))
          (reverse acc)
          (let* ((o1 (tell string 'get-letter p))
                 (o2 (tell string 'get-letter (add1 p)))
                 (d1 (tell o1 'get-descriptor-for plato-letter-category))
                 (d2 (tell o2 'get-descriptor-for plato-letter-category))
                 (cat (get-bond-category d1 d2)))
            (if (not (exists? cat))
              (loop (add1 p) (cons #f acc))
              (let ((b (make-bond o1 o2 cat plato-letter-category d1 d2)))
                (build-bond b)
                (loop (add1 p) (cons b acc))))))))))

;; group maximal runs of bonds sharing category and direction
(define build-runs
  (lambda (string bonds)
    (let loop ((bs bonds) (run '()))
      (cond
        ((null? bs)
         (if (not (null? run)) (make-run string (reverse run))))
        ((not (1st bs))
         (if (not (null? run)) (make-run string (reverse run)))
         (loop (rest bs) '()))
        ((or (null? run)
             (and (eq? (tell (1st bs) 'get-bond-category)
                       (tell (1st run) 'get-bond-category))
                  (eq? (tell (1st bs) 'get-direction)
                       (tell (1st run) 'get-direction))))
         (loop (rest bs) (cons (1st bs) run)))
        (else
          (make-run string (reverse run))
          (loop (rest bs) (list (1st bs))))))))

(define make-run
  (lambda (string run-bonds)
    (let* ((cat (tell (1st run-bonds) 'get-bond-category))
           (dir (tell (1st run-bonds) 'get-direction))
           (gcat (tell cat 'get-related-node plato-group-category))
           (objs (cons (tell (1st run-bonds) 'get-left-object)
                   (map (lambda (b) (tell b 'get-right-object)) run-bonds)))
           (g (make-group string gcat plato-letter-category dir
                (1st objs) (nth (sub1 (length objs)) objs) objs run-bonds)))
      (build-group g #f)
      g)))

(define probe
  (lambda (i m t seed)
    (printf "PROBLEM\t~a\t~a\t~a\t~a~%" i m t seed)
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
                             plato-predecessor plato-sameness plato-group-category
                             plato-direction-category plato-length) do
      (tell node 'set-activation %max-activation%))
    (update-workspace-values)
    (random-seed seed)
    (for-each
      (lambda (string) (build-runs string (build-bond-chain string)))
      (list *initial-string* *modified-string* *target-string*))
    (update-workspace-values)
    (for-each
      (lambda (string)
        (for-each
          (lambda (g)
            (printf "GRP\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type) (tell g 'ascii-name)
              (if (exists? (tell g 'print-name)) (tell g 'print-name) "-")
              (nm (tell g 'get-group-category)) (nm (tell g 'get-bond-category))
              (nm (tell g 'get-direction)) (nm (tell g 'get-bond-facet))
              (tell g 'get-left-string-pos) (tell g 'get-right-string-pos)
              (tell g 'get-group-length)
              (nm (tell g 'get-platonic-length))
              (yn (tell g 'spans-whole-string?)) (yn (tell g 'leftmost-in-string?))
              (yn (tell g 'middle-in-string?)) (yn (tell g 'rightmost-in-string?))
              (tell g 'calculate-internal-strength)
              (tell g 'get-num-of-local-supporting-groups))
            (let loop ((k 0) (ds (tell g 'get-descriptions)))
              (when (not (null? ds))
                (printf "GDESC\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
                  (tell g 'ascii-name) k
                  (nm (tell (1st ds) 'get-description-type))
                  (nm (tell (1st ds) 'get-descriptor)))
                (loop (add1 k) (rest ds))))
            (let loop ((k 0) (ds (tell g 'get-bond-descriptions)))
              (when (not (null? ds))
                (printf "GBDESC\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
                  (tell g 'ascii-name) k
                  (nm (tell (1st ds) 'get-description-type))
                  (nm (tell (1st ds) 'get-descriptor)))
                (loop (add1 k) (rest ds)))))
          (reverse (tell string 'get-groups)))
        (for-each
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name)
              (if (exists? (tell o 'get-enclosing-group))
                (tell (tell o 'get-enclosing-group) 'ascii-name) "-")
              (tell o 'get-intra-string-unhappiness)
              (tell o 'get-intra-string-salience)
              (yn (tell o 'middle-in-string?))
              (length (tell o 'get-descriptions))))
          (tell string 'get-all-objects)))
      (list *initial-string* *modified-string* *target-string*))))

(probe 'abc 'abd 'ijk 101)
(probe 'abc 'abd 'mrrjjj 202)
(probe 'abcde 'abcdf 'pqrst 303)
(probe 'aabbcc 'aabbdd 'ijkk 404)
