;; The workspace-level aggregate: bridge registry, inter-string unhappiness
;; averages, and the mapping strengths the bridge scouts weight by. Bonds,
;; groups and bridges are built directly, then the derived values are dumped.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))
(define emit
  (lambda (label v)
    (printf "~a\t~a\t~a~%" label (if (exact? v) "E" "F") (number->string v))))

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

(define dump-workspace
  (lambda (tag)
    (emit (format "AVG-INTRA/~a" tag)
      (tell *workspace* 'get-average-intra-string-unhappiness))
    (emit (format "AVG-TOP/~a" tag)
      (tell *workspace* 'get-average-inter-string-unhappiness 'top))
    (emit (format "AVG-VERT/~a" tag)
      (tell *workspace* 'get-average-inter-string-unhappiness 'vertical))
    (emit (format "AVG-ALL/~a" tag) (tell *workspace* 'get-average-unhappiness))
    (emit (format "MAP-TOP/~a" tag) (tell *workspace* 'get-mapping-strength 'top))
    (emit (format "MAP-VERT/~a" tag) (tell *workspace* 'get-mapping-strength 'vertical))
    (printf "SPAN\t~a\t~a\t~a~%" tag
      (yn (tell *workspace* 'spanning-bridge-exists? 'top))
      (yn (tell *workspace* 'spanning-bridge-exists? 'vertical)))
    (printf "MAXMAP\t~a\t~a\t~a~%" tag
      (yn (tell *workspace* 'maximal-mapping? 'top))
      (yn (tell *workspace* 'maximal-mapping? 'vertical)))
    (printf "SGP\t~a\t~a\t~a\t~a~%" tag
      (yn (spanning-group-possible? *initial-string*))
      (yn (spanning-group-possible? *modified-string*))
      (yn (spanning-group-possible? *target-string*)))
    (printf "NBRIDGES\t~a\t~a\t~a~%" tag
      (length (tell *workspace* 'get-bridges 'top))
      (length (tell *workspace* 'get-bridges 'vertical)))
    (let loop ((k 0) (l (tell *workspace* 'get-all-slippages 'vertical)))
      (when (not (null? l))
        (printf "VSLIP\t~a\t~a\t~a~%" tag k (tell (1st l) 'print-name))
        (loop (add1 k) (rest l))))))

(define probe
  (lambda (i m t seed group?)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a~%" i m t seed group?)
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
    (set! *temperature* 50)
    (update-workspace-values)
    (dump-workspace "bare")
    (random-seed seed)
    (if group?
      (for-each build-chain-and-group
        (list *initial-string* *modified-string* *target-string*)))
    (update-workspace-values)
    (dump-workspace "structured")
    ;; build every bridge we can, letter-to-letter by position and group-to-group
    (for-each
      (lambda (spec)
        (let ((orientation (1st spec)) (s1 (2nd spec)) (s2 (3rd spec)))
          (for* each o1 in (tell s1 'get-objects) do
            (for* each o2 in (tell s2 'get-objects) do
              (if* (and (not (lone-spanning-object? o1 o2))
                        (not (exists? (tell o1 'get-bridge orientation)))
                        (not (exists? (tell o2 'get-bridge orientation))))
                (let ((cms (all-possible-bridge-CMs orientation
                             o1 (tell o1 'get-descriptions)
                             o2 (tell o2 'get-descriptions))))
                  (if* (not (null? cms))
                    (let ((b (case orientation
                               (horizontal (make-horizontal-bridge o1 o2 cms))
                               (vertical (make-vertical-bridge o1 o2 cms)))))
                      (build-bridge orientation b)))))))))
      (list (list 'vertical *initial-string* *target-string*)
            (list 'horizontal *initial-string* *modified-string*)))
    (update-workspace-values)
    (dump-workspace "bridged")
    (for-each
      (lambda (string)
        (for-each
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name)
              (tell o 'get-inter-string-unhappiness 'horizontal)
              (tell o 'get-inter-string-unhappiness 'vertical)
              (tell o 'get-average-unhappiness) (tell o 'get-relative-importance)))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))))

(probe 'abc 'abd 'ijk 11 #f)
(probe 'abc 'abd 'ijk 12 #t)
(probe 'abc 'cba 'pqrs 13 #t)
(probe 'iijjkk 'iijjll 'mmnnoo 14 #t)
(probe 'abcde 'abcdf 'pqrst 15 #f)
