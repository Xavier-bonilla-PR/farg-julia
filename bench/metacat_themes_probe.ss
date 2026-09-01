;; Exercises the themespace: cluster construction, theme creation order,
;; activation spreading, dominant-theme selection, freezing, theme patterns,
;; and the thematic compatibility that feeds bridge and description strengths.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define tt->tag
  (lambda (tt) (case tt (top-bridge "top") (bottom-bridge "bot") (vertical-bridge "ver"))))
(define rel->tag
  (lambda (r) (if (exists? r) (tell r 'get-lowercase-name) "diff")))
(define emit
  (lambda (label v)
    (printf "~a\t~a\t~a~%" label (if (exact? v) "E" "F") (number->string v))))
(define yn (lambda (b) (if b "y" "n")))

;;-------------------------------------------------------------------- A. shape
(for* each tt in '(top-bridge bottom-bridge vertical-bridge) do
  (for* each c in (tell *themespace* 'get-clusters tt) do
    (printf "CLUSTER\t~a\t~a\t~a\t~a~%"
      (tt->tag tt) (tell (tell c 'get-dimension) 'get-short-name)
      (length (tell c 'get-relations))
      (map rel->tag (tell c 'get-relations)))))

(printf "POSSIBLE-TYPES\t~a~%" (map tt->tag (tell *themespace* 'get-possible-theme-types)))

;;----------------------------------------------------------- dumping utilities
(define dump-themes
  (lambda (tag)
    (let loop ((k 0) (l (tell *themespace* 'get-all-themes)))
      (when (not (null? l))
        (let ((th (1st l)))
          (printf "TH\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
            tag k (tt->tag (tell th 'get-theme-type)) (tell th 'ascii-name)
            (tell th 'get-activation) (yn (tell th 'dominant?))
            (yn (tell th 'frozen?)) (yn (tell th 'individually-frozen?))
            (length (tell (tell th 'get-cluster) 'get-themes))))
        (loop (add1 k) (rest l))))))

(define dump-dominant
  (lambda (tag)
    (for* each tt in '(top-bridge bottom-bridge vertical-bridge) do
      (for* each c in (tell *themespace* 'get-clusters tt) do
        (let ((d (tell c 'get-dominant-theme)))
          (if* (exists? d)
            (printf "DOM\t~a\t~a\t~a\t~a~%"
              tag (tt->tag tt) (tell d 'ascii-name) (tell d 'get-activation))))))))

;;----------------------------------------------------- B. creation and spread
(tell *themespace* 'delete-everything)
(tell *themespace* 'unfreeze-everything)
(tell *themespace* 'thematic-pressure-on)
(printf "ACTIVE\t~a~%" (map tt->tag (tell *themespace* 'get-active-theme-types)))
(printf "PRESSURE\t~a\t~a\t~a~%"
  (yn (tell *themespace* 'thematic-pressure? 'top-bridge))
  (yn (tell *themespace* 'thematic-pressure? 'bottom-bridge))
  (yn (tell *themespace* 'thematic-pressure? 'vertical-bridge)))

;; A spread of activations, positive and negative, across three dimensions.
(for-each
  (lambda (spec)
    (tell *themespace* 'set-theme-activation (1st spec) (2nd spec) (3rd spec) (4th spec)))
  (list
    (list 'top-bridge plato-letter-category plato-successor 100)
    (list 'top-bridge plato-letter-category plato-identity 40)
    (list 'top-bridge plato-letter-category #f -60)
    (list 'top-bridge plato-string-position-category plato-identity 75)
    (list 'top-bridge plato-string-position-category plato-opposite -30)
    (list 'vertical-bridge plato-letter-category plato-successor 90)
    (list 'vertical-bridge plato-object-category #f 55)
    (list 'vertical-bridge plato-length plato-predecessor -100)
    (list 'bottom-bridge plato-direction-category plato-opposite 65)))
(dump-themes "init")
(dump-dominant "init")

;; Settle. Activations must stay exact integers through the tanh.
(let loop ((step 0))
  (when (< step 12)
    (tell *themespace* 'spread-activation)
    (let inner ((k 0) (l (tell *themespace* 'get-all-themes)))
      (when (not (null? l))
        (emit (format "SPREAD/~a/~a/~a" step (tt->tag (tell (1st l) 'get-theme-type))
                (tell (1st l) 'ascii-name))
          (tell (1st l) 'get-activation))
        (inner (add1 k) (rest l))))
    (loop (add1 step))))
(dump-dominant "settled")
(emit "PCT-DOMINANT" (tell *themespace* 'get-percentage-of-dominant-themes))

;;----------------------------------------------------------------- C. boosting
(for-each
  (lambda (factor)
    (for* each th in (tell *themespace* 'get-all-themes) do
      (tell th 'boost-activation factor))
    (let loop ((l (tell *themespace* 'get-all-themes)))
      (when (not (null? l))
        (emit (format "BOOST/~a/~a/~a" factor
                (tt->tag (tell (1st l) 'get-theme-type)) (tell (1st l) 'ascii-name))
          (tell (1st l) 'get-activation))
        (loop (rest l)))))
  '(0 13 50 87 100 250))

;;----------------------------------------------------------------- D. freezing
(tell *themespace* 'freeze-theme 'top-bridge plato-letter-category plato-successor)
(tell *themespace* 'freeze-theme-cluster 'vertical-bridge plato-letter-category)
(printf "FROZEN\t~a\t~a\t~a\t~a~%"
  (yn (tell *themespace* 'theme-frozen? 'top-bridge plato-letter-category plato-successor))
  (yn (tell *themespace* 'cluster-frozen? 'vertical-bridge plato-letter-category))
  (yn (tell *themespace* 'theme-type-frozen? 'top-bridge))
  (yn (tell *themespace* 'everything-frozen?)))
(tell *themespace* 'spread-activation)
(dump-themes "frozen")
;; A frozen cluster refuses new themes only when asked to check:
(printf "ADD-IF\t~a~%"
  (yn (exists? (tell *themespace* 'add-theme-if-possible
                 'vertical-bridge plato-letter-category plato-opposite))))
(printf "ADD-UNC\t~a~%"
  (yn (exists? (tell *themespace* 'add-theme-unconditionally
                 'vertical-bridge plato-letter-category plato-opposite))))
(tell *themespace* 'unfreeze-everything)

;;----------------------------------------------------------------- E. patterns
(for* each tt in '(top-bridge vertical-bridge) do
  (printf "COMPLETE\t~a\t~a~%" (tt->tag tt)
    (map (lambda (e)
           (if (= (length e) 3)
             (list (tell (1st e) 'get-short-name) (rel->tag (2nd e)) (3rd e))
             e))
      (entries (tell *themespace* 'get-complete-theme-pattern tt))))
  (printf "NONZERO\t~a\t~a~%" (tt->tag tt)
    (map (lambda (e)
           (if (= (length e) 3)
             (list (tell (1st e) 'get-short-name) (rel->tag (2nd e)) (3rd e))
             e))
      (entries (tell *themespace* 'get-nonzero-theme-pattern tt))))
  (printf "DOMPAT\t~a\t~a~%" (tt->tag tt)
    (map (lambda (e) (list (tell (1st e) 'get-short-name) (rel->tag (2nd e))))
      (entries (tell *themespace* 'get-dominant-theme-pattern tt)))))

;;----------------------------------------- F. themes against a real workspace
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

(define probe-workspace
  (lambda (i m t seed themes)
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
    ;; description-possible? for every object against every dimension
    (for* each obj in (tell *workspace* 'get-objects) do
      (printf "DPOSS\t~a\t~a~%" (tell obj 'ascii-name)
        (map (lambda (dim)
               (list (tell dim 'get-short-name)
                 (yn (tell dim 'description-possible? obj))))
          (tell *themespace* 'get-dimensions))))
    ;; install the themes for this problem
    (tell *themespace* 'delete-everything)
    (tell *themespace* 'unfreeze-everything)
    (tell *themespace* 'thematic-pressure-on)
    (for-each
      (lambda (spec)
        (tell *themespace* 'set-theme-activation (1st spec) (2nd spec) (3rd spec) (4th spec)))
      themes)
    (for* each spec in
      (list (list 'vertical *initial-string* *target-string*)
            (list 'horizontal *initial-string* *modified-string*)) do
      (let ((orientation (1st spec)) (s1 (2nd spec)) (s2 (3rd spec)))
        (for* each o1 in (tell s1 'get-objects) do
          (for* each o2 in (tell s2 'get-objects) do
            (let ((cms (all-possible-bridge-CMs orientation
                         o1 (tell o1 'get-descriptions)
                         o2 (tell o2 'get-descriptions))))
              (if* (not (null? cms))
                (let* ((b (case orientation
                            (horizontal (make-horizontal-bridge o1 o2 cms))
                            (vertical (make-vertical-bridge o1 o2 cms))))
                       (tag (format "~a:~a>~a" orientation
                             (tell o1 'ascii-name) (tell o2 'ascii-name))))
                  ;; support values, in active-theme order
                  (let loop ((k 0) (vals (tell b 'get-theme-support-values)))
                    (when (not (null? vals))
                      (emit (format "TSV/~a/~a" tag k) (1st vals))
                      (loop (add1 k) (rest vals))))
                  (emit (format "AVG/~a" tag) (tell b 'get-average-theme-support))
                  (emit (format "COMPAT/~a" tag) (tell b 'get-thematic-compatibility))
                  (tell b 'update-strength)
                  (emit (format "STRENGTH/~a" tag) (tell b 'get-strength))
                  (printf "ATR\t~a\t~a~%" tag
                    (map (lambda (e)
                           (list (tell (1st e) 'get-short-name) (rel->tag (2nd e))))
                      (tell b 'get-associated-thematic-relations)))
                  ;; boosting feeds back into the themespace
                  (tell b 'boost-themespace-activations))))))))
    (dump-themes "boosted")
    (dump-dominant "boosted")
    ;; description strengths now see nonzero thematic compatibility
    (for* each obj in (tell *workspace* 'get-objects) do
      (for* each d in (tell obj 'get-descriptions) do
        (tell d 'update-strength)
        (printf "DESC\t~a\t~a\t~a\t~a\t~a~%"
          (tell obj 'ascii-name) (tell d 'print-name)
          (number->string (tell d 'get-thematic-compatibility))
          (tell d 'get-strength)
          (map number->string (tell d 'get-theme-support-values)))))))

(probe-workspace 'abc 'abd 'ijk 81
  (list (list 'top-bridge plato-letter-category plato-successor 100)
        (list 'top-bridge plato-string-position-category plato-identity 80)
        (list 'vertical-bridge plato-letter-category plato-identity 100)
        (list 'vertical-bridge plato-string-position-category plato-identity 90)
        (list 'vertical-bridge plato-object-category #f -70)))

(probe-workspace 'abc 'cba 'pqrs 82
  (list (list 'top-bridge plato-string-position-category plato-opposite 100)
        (list 'top-bridge plato-letter-category plato-identity 60)
        (list 'vertical-bridge plato-length plato-successor 85)
        (list 'vertical-bridge plato-group-category plato-identity 100)
        (list 'vertical-bridge plato-direction-category plato-opposite -45)))

(probe-workspace 'iijjkk 'iijjll 'mmnnoo 83
  (list (list 'top-bridge plato-letter-category plato-successor 95)
        (list 'top-bridge plato-bond-facet #f 70)
        (list 'vertical-bridge plato-object-category plato-identity 100)
        (list 'vertical-bridge plato-alphabetic-position-category plato-opposite -80)))
