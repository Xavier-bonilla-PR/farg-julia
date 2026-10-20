;; Builds bonds and groups, then every possible bridge between the strings,
;; and dumps concept mappings, compatibility relations and strengths.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))

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

(define dump-bridge
  (lambda (tag b)
    (printf "BR\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
      tag (tell b 'get-orientation) (tell b 'get-bridge-type)
      (tell (tell b 'get-object1) 'ascii-name)
      (tell (tell b 'get-object2) 'ascii-name)
      (yn (tell b 'spanning-bridge?)) (yn (tell b 'group-spanning-bridge?))
      (length (tell b 'get-concept-mappings))
      (length (tell b 'get-all-concept-mappings))
      (yn (tell b 'internally-coherent?))
      (tell b 'calculate-internal-strength))
    (let loop ((k 0) (cms (tell b 'get-all-concept-mappings)))
      (when (not (null? cms))
        (printf "BRCM\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" tag k
          (tell (1st cms) 'print-name) (nm (tell (1st cms) 'get-label))
          (yn (tell (1st cms) 'slippage?)) (yn (tell (1st cms) 'relevant?))
          (yn (tell (1st cms) 'distinguishing?))
          (tell (1st cms) 'get-strength))
        (loop (add1 k) (rest cms))))
    (let loop ((k 0) (ss (tell b 'get-symmetric-slippages)))
      (when (not (null? ss))
        (printf "BRSS\t~a\t~a\t~a~%" tag k (tell (1st ss) 'print-name))
        (loop (add1 k) (rest ss))))))

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
                             plato-direction-category plato-length
                             plato-alphabetic-position-category plato-bond-category
                             plato-bond-facet) do
      (tell node 'set-activation %max-activation%))
    (update-workspace-values)
    (random-seed seed)
    (for-each build-chain-and-group
      (list *initial-string* *modified-string* *target-string*))
    (update-workspace-values)
    ;; vertical bridges: initial <-> target ; horizontal: initial <-> modified
    (for-each
      (lambda (spec)
        (let ((orientation (1st spec)) (s1 (2nd spec)) (s2 (3rd spec)))
          (for* each o1 in (tell s1 'get-objects) do
            (for* each o2 in (tell s2 'get-objects) do
              (let ((cms (all-possible-bridge-CMs orientation
                           o1 (tell o1 'get-descriptions)
                           o2 (tell o2 'get-descriptions))))
                (if* (not (null? cms))
                  (let ((b (case orientation
                             (horizontal (make-horizontal-bridge o1 o2 cms))
                             (vertical (make-vertical-bridge o1 o2 cms)))))
                    (dump-bridge (format "~a:~a>~a" orientation
                                   (tell o1 'ascii-name) (tell o2 'ascii-name))
                      b))))))))
      (list (list 'vertical *initial-string* *target-string*)
            (list 'horizontal *initial-string* *modified-string*)))))

(probe 'abc 'abd 'ijk 71)
(probe 'abc 'abd 'mrrjjj 72)
(probe 'abc 'cba 'pqrs 73)
