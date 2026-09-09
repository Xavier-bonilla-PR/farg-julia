;; Canonical dump of the themespace: structure, activation dynamics, freezing,
;; theme support for real bridges, and the themes' pull on the slipnet.
;;
;; Dimensions and relations are addressed by INDEX rather than by name, so the
;; two sides of the probe cannot disagree about which theme they are talking
;; about without the slipnet probe already having failed.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))

;; Exact rendering of a number: exact values print as themselves, inexact ones
;; print as the exact rational the double actually is, so a one-ulp drift shows.
(define num
  (lambda (v)
    (if (exact? v)
      (if (integer? v)
        (number->string v)
        (format "~a/~a" (numerator v) (denominator v)))
      (let ((r (inexact->exact v)))
        (format "F~a/~a" (numerator r) (denominator r))))))

(define dims (tell *themespace* 'get-dimensions))
(define types '(top-bridge bottom-bridge vertical-bridge))
(define dim-at (lambda (i) (nth i dims)))
(define rel-at
  (lambda (type i j) (nth j (tell *themespace* 'get-relations type (dim-at i)))))

;;-------------------------------------------------------------- structure ----

(printf "DIMS\t~a~%" (length dims))
(let loop ((i 0))
  (when (< i (length dims))
    (let* ((d (dim-at i))
           (relations (tell *themespace* 'get-relations 'top-bridge d)))
      (printf "DIM\t~a\t~a\t~a~%" i (tell d 'get-short-name) (length relations))
      (let rloop ((j 0))
        (when (< j (length relations))
          (printf "REL\t~a\t~a\t~a~%" i j (nm (nth j relations)))
          (rloop (add1 j)))))
    (loop (add1 i))))
(printf "TYPES\t~a~%" (tell *themespace* 'get-possible-theme-types))
(printf "ACTIVE\t~a~%" (tell *themespace* 'get-active-theme-types))
(printf "PRESSURE\t~a~%" (yn (tell *themespace* 'thematic-pressure?)))

;;------------------------------------------------------------ themespace ----

(define dump-themespace
  (lambda (tag)
    (for* each type in types do
      (let cloop ((cs (tell *themespace* 'get-clusters type)))
        (when (not (null? cs))
          (let ((c (1st cs)))
            (if* (not (null? (tell c 'get-themes)))
              (printf "CLUSTER\t~a\t~a\t~a\t~a\t~a\t~a~%"
                tag type (tell (tell c 'get-dimension) 'get-short-name)
                (length (tell c 'get-themes))
                (yn (tell c 'frozen?))
                (let ((d (tell c 'get-dominant-theme)))
                  (if (exists? d) (tell d 'ascii-name) "-")))
              (for* each th in (tell c 'get-themes) do
                (printf "THEME\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
                  tag type (tell th 'ascii-name) (tell th 'get-activation)
                  (yn (tell th 'dominant?)) (yn (tell th 'frozen?))
                  (yn (tell th 'individually-frozen?))))))
          (cloop (rest cs)))))
    (printf "ALLTHEMES\t~a\t~a~%" tag
      (map (lambda (th) (tell th 'ascii-name)) (tell *themespace* 'get-all-themes)))
    (printf "PCTDOM\t~a\t~a~%" tag
      (num (tell *themespace* 'get-percentage-of-dominant-themes)))))

;;-------------------------------------------------------------- dynamics ----

;; LetterCtgy is dimension 0 with 4 relations, StringPos is 1 with 3,
;; ObjectCtgy is 7 with 2 - a wide cluster, a middling one, and the narrowest,
;; so the 1/num-relations term in the sigmoid gets three different values.
(define seed-themes
  (lambda ()
    (tell *themespace* 'delete-everything)
    (tell *themespace* 'unfreeze-everything)
    (tell *themespace* 'set-theme-activation 'top-bridge (dim-at 0) (rel-at 'top-bridge 0 3) 100)
    (tell *themespace* 'set-theme-activation 'top-bridge (dim-at 0) (rel-at 'top-bridge 0 2) 40)
    (tell *themespace* 'set-theme-activation 'top-bridge (dim-at 0) (rel-at 'top-bridge 0 0) -60)
    (tell *themespace* 'set-theme-activation 'top-bridge (dim-at 0) (rel-at 'top-bridge 0 1) 0)
    (tell *themespace* 'set-theme-activation 'vertical-bridge (dim-at 1) (rel-at 'vertical-bridge 1 1) 80)
    (tell *themespace* 'set-theme-activation 'vertical-bridge (dim-at 1) (rel-at 'vertical-bridge 1 2) -30)
    (tell *themespace* 'set-theme-activation 'top-bridge (dim-at 7) (rel-at 'top-bridge 7 0) 95)
    (tell *themespace* 'set-theme-activation 'top-bridge (dim-at 7) (rel-at 'top-bridge 7 1) 95)))

(seed-themes)
(dump-themespace "seeded")

(let loop ((cycle 0))
  (when (< cycle 12)
    (tell *themespace* 'spread-activation)
    (dump-themespace (format "cycle~a" cycle))
    (loop (add1 cycle))))

;;----------------------------------------------------- freezing / deleting ---

(seed-themes)
(tell *themespace* 'freeze-theme 'top-bridge (dim-at 0) (rel-at 'top-bridge 0 3))
(tell *themespace* 'freeze-theme-cluster 'top-bridge (dim-at 7))
(dump-themespace "frozen")
(tell *themespace* 'spread-activation)
(dump-themespace "frozen-spread")
(printf "FROZENQ\t~a\t~a\t~a~%"
  (yn (tell *themespace* 'theme-frozen? 'top-bridge (dim-at 0) (rel-at 'top-bridge 0 3)))
  (yn (tell *themespace* 'cluster-frozen? 'top-bridge (dim-at 7)))
  (yn (tell *themespace* 'theme-type-frozen? 'top-bridge)))
(tell *themespace* 'unfreeze-theme-cluster 'top-bridge (dim-at 7))
(tell *themespace* 'spread-activation)
(dump-themespace "unfrozen-spread")
(tell *themespace* 'delete-theme 'top-bridge (dim-at 0) (rel-at 'top-bridge 0 2))
(dump-themespace "deleted")
(tell *themespace* 'delete-theme-type 'top-bridge)
(dump-themespace "deleted-type")

;;--------------------------------------------- pressure and active themes ----

(tell *themespace* 'delete-everything)
(tell *themespace* 'unfreeze-everything)
(tell *themespace* 'thematic-pressure-off)
(seed-themes)
(printf "PRESSURE\t~a~%" (yn (tell *themespace* 'thematic-pressure?)))
(tell *themespace* 'thematic-pressure-on 'vertical-bridge)
(printf "ACTIVE\t~a~%" (tell *themespace* 'get-active-theme-types))
(printf "ACTIVETHEMES\t~a~%"
  (map (lambda (th) (tell th 'ascii-name)) (tell *themespace* 'get-all-active-themes)))
(printf "MAXPOS\t~a\t~a\t~a~%"
  (tell *themespace* 'get-max-positive-theme-activation 'top-bridge)
  (tell *themespace* 'get-max-positive-theme-activation 'vertical-bridge)
  (tell *themespace* 'get-max-positive-theme-activation
    (tell *themespace* 'get-active-bridge-theme-types)))
(tell *themespace* 'thematic-pressure-on)
(printf "ACTIVE\t~a~%" (tell *themespace* 'get-active-theme-types))
(printf "ACTIVEBRIDGE\t~a~%" (tell *themespace* 'get-active-bridge-theme-types))
(printf "DOMPATTERNS\t~a~%"
  (map
    (lambda (pattern)
      (cons (1st pattern)
        (map (lambda (e) (list (tell (1st e) 'get-short-name) (nm (2nd e))))
          (rest pattern))))
    (tell *themespace* 'get-all-dominant-theme-patterns)))
(printf "NONZERO\t~a~%"
  (let ((pattern (tell *themespace* 'get-nonzero-theme-pattern 'top-bridge)))
    (cons (1st pattern)
      (map (lambda (e) (list (tell (1st e) 'get-short-name) (nm (2nd e)) (3rd e)))
        (rest pattern)))))

;;----------------------------------------- the rest of the themespace API ----

;; Cluster-level queries, the wholesale freeze/unfreeze/delete paths, and the
;; stochastic theme pick, which draws and so has to agree draw for draw.
(printf "CMAXPOS\t~a\t~a\t~a~%"
  (tell (tell *themespace* 'get-cluster 'top-bridge (dim-at 0))
    'get-max-positive-theme-activation)
  (tell (tell *themespace* 'get-cluster 'vertical-bridge (dim-at 1))
    'get-max-positive-theme-activation)
  (tell (tell *themespace* 'get-cluster 'top-bridge (dim-at 4))
    'get-max-positive-theme-activation))
(random-seed 91)
(let loop ((k 0))
  (when (< k 8)
    (let ((th (tell (tell *themespace* 'get-cluster 'top-bridge (dim-at 0))
                'pick-positive-theme)))
      (printf "PICK\t~a\t~a~%" k (if (exists? th) (tell th 'ascii-name) "-")))
    (loop (add1 k))))
(printf "EVERYFROZEN\t~a~%" (yn (tell *themespace* 'everything-frozen?)))
(tell *themespace* 'freeze-theme-type 'top-bridge)
(printf "EVERYFROZEN\t~a\t~a~%"
  (yn (tell *themespace* 'theme-type-frozen? 'top-bridge))
  (yn (tell *themespace* 'everything-frozen?)))
(tell *themespace* 'freeze-everything)
(printf "EVERYFROZEN\t~a~%" (yn (tell *themespace* 'everything-frozen?)))
(tell *themespace* 'unfreeze-theme 'top-bridge (dim-at 0) (rel-at 'top-bridge 0 3))
(dump-themespace "all-frozen")
(tell *themespace* 'unfreeze-everything)
(tell *themespace* 'delete-theme-cluster 'top-bridge (dim-at 0))
(dump-themespace "cluster-deleted")
(tell *themespace* 'set-theme-cluster-activations 'top-bridge (dim-at 2) 55)
(tell *themespace* 'set-theme-type-activations 'vertical-bridge 30)
(dump-themespace "bulk-set")
(tell *themespace* 'set-all-theme-activations 15)
(dump-themespace "all-set")
(let ((held (tell *themespace* 'get-theme 'top-bridge (dim-at 2) (rel-at 'top-bridge 2 1))))
  (printf "PRESENT\t~a\t~a~%"
    (yn (tell *themespace* 'theme-present? held))
    (tell (tell *themespace* 'get-equivalent-theme held) 'ascii-name))
  ;; a theme object outlives its deletion from the themespace
  (tell *themespace* 'delete-theme 'top-bridge (dim-at 2) (rel-at 'top-bridge 2 1))
  (printf "PRESENT\t~a\t~a~%"
    (yn (tell *themespace* 'theme-present? held))
    (if (exists? (tell *themespace* 'get-equivalent-theme held)) "?" "-")))

;;-------------------------------------------- theme support in a workspace ---

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

(define support-probe
  (lambda (i m t seed)
    (printf "PROBLEM\t~a\t~a\t~a\t~a~%" i m t seed)
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
    ;; A theme pattern to judge the bridges against: LettCtgy maps by identity,
    ;; StringPos by opposite, ObjCtgy by identity, and Direction is asserted NOT
    ;; to map by identity.
    (tell *themespace* 'thematic-pressure-on)
    (for* each type in '(top-bridge vertical-bridge) do
      (tell *themespace* 'set-theme-activation type (dim-at 0) (rel-at type 0 3) 100)
      (tell *themespace* 'set-theme-activation type (dim-at 1) (rel-at type 1 1) 90)
      (tell *themespace* 'set-theme-activation type (dim-at 7) (rel-at type 7 0) 70)
      (tell *themespace* 'set-theme-activation type (dim-at 3) (rel-at type 3 1) -80))
    (dump-themespace "support")
    ;; description strengths now feel the themes
    (for* each obj in (tell *workspace* 'get-objects) do
      (for* each d in (tell obj 'get-descriptions) do
        (tell d 'update-strength)
        (printf "DESCR\t~a\t~a\t~a\t~a\t~a~%"
          (tell obj 'ascii-name) (tell d 'print-name)
          (map num (tell d 'get-theme-support-values))
          (num (tell d 'get-thematic-compatibility))
          (tell d 'get-strength))))
    (for-each
      (lambda (spec)
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
                    (tell b 'update-strength)
                    (printf "BRSUP\t~a\t~a\t~a\t~a\t~a~%" tag
                      (map num (tell b 'get-theme-support-values))
                      (num (tell b 'get-average-theme-support))
                      (num (tell b 'get-thematic-compatibility))
                      (tell b 'get-strength))
                    (for* each th in (tell *themespace* 'get-active-themes
                                       (bridge-type->theme-type (tell b 'get-bridge-type))) do
                      (printf "BRTH\t~a\t~a\t~a\t~a~%" tag (tell th 'ascii-name)
                        (yn (tell b 'incompatible-with-theme? th))
                        (yn (tell b 'supported-by-theme? th))))
                    (printf "BRREL\t~a\t~a~%" tag
                      (map (lambda (e) (list (tell (1st e) 'get-short-name) (nm (2nd e))))
                        (tell b 'get-associated-thematic-relations)))
                    (for* each cm in (tell b 'get-all-concept-mappings) do
                      (printf "BRACT\t~a\t~a\t~a~%" tag (tell cm 'print-name)
                        (yn (tell *themespace* 'supported-by-active-theme? cm b)))))))))))
      (list (list 'vertical *initial-string* *target-string*)
            (list 'horizontal *initial-string* *modified-string*)))
    ;; boosting: every bridge votes for the themes its mappings realise
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
                    (tell b 'update-strength)
                    (tell b 'boost-themespace-activations))))))))
      (list (list 'vertical *initial-string* *target-string*)
            (list 'horizontal *initial-string* *modified-string*)))
    (dump-themespace "boosted")
    ;; and the themes push back on the slipnet
    (let loop ((cycle 0))
      (when (< cycle 3)
        (update-slipnet-activations)
        (for* each node in *slipnet-nodes* do
          (printf "NODE\t~a\t~a\t~a~%" cycle (nm node) (tell node 'get-activation)))
        (loop (add1 cycle))))))

(support-probe 'abc 'abd 'ijk 81)
(support-probe 'abc 'cba 'pqrs 82)
(support-probe 'abc 'abd 'mrrjjj 83)

;;--------------------------------------------------------------- exactness ---
;;
;; The two places where the themespace's arithmetic depends on Scheme's
;; EXACTNESS and not just on its numbers. Both were open divergences in the
;; port; this section is what stops them reopening, and it is why `num`
;; distinguishes an exact value from an inexact one that happens to be whole.
;;
;;   `exp` of an exact zero. R6RS lets `exp` return an exact result where one
;;   is exactly representable, and Chez does: `(exp 0)` is the exact `1`, so
;;   the compatibility sigmoid of an exact 0 is the exact `0`, not `0.0`. A
;;   bridge with NO active themes has exactly that argument, which is most
;;   bridges early in a run -- and the whole strength computation downstream
;;   then stays on the exact side of the tower.
;;
;;   `max` and `min` return the winning ARGUMENT, so its representation
;;   survives: `(max 9/10 1)` is the exact INTEGER 1. A port whose `max`
;;   promotes to a common type gets a denominator-1 rational instead, which is
;;   the same number and a different thing.

(printf "SECTION\texactness~%")

;; `num` runs the value through the tower's normaliser, so it renders an exact
;; 1 and an exact 1/1 alike -- which is the whole point of the `max` case, and
;; would hide it. `rep` names the REPRESENTATION instead: an exact integer, an
;; exact ratio, or an inexact number. Scheme has no unnormalised 1/1, so "int"
;; here is a claim the port has to earn.
(define rep
  (lambda (x)
    (cond ((not (exact? x)) "flo") ((integer? x) "int") (else "rat"))))

(for-each
  (lambda (x)
    (let ((y (bridge-theme-compatibility-sigmoid x)))
      (printf "SIG\t~a\t~a\t~a\t~a~%" (num x) (rep x) (num y) (rep y))))
  (list 0 0.0 1 -1 1/2 -1/2 9/10 1/100 -3/4 -1/1000))

(for-each
  (lambda (l)
    (let ((hi (maximum l)) (lo (minimum l)))
      (printf "EXTREME\t~a\t~a\t~a\t~a\t~a~%"
        (if (null? l) "-" (map num l))
        (num hi) (rep hi) (num lo) (rep lo))))
  (list '() '(0) '(9/10 1) '(1 9/10) '(1/2 1/4) '(0 0 9/10) '(1 1 1)
        '(100 3/4 0) '(3 2.0) '(2.0 3) '(1/2 0.25)))

;; And through the model: a description and a bridge with the themespace
;; EMPTY, which is the state the sigmoid's exact zero comes from.
(for* each node in *slipnet-nodes* do (tell node 'reset))
(tell *themespace* 'initialize)
(init-workspace 'abc 'abd 'ijk #f)
(add-string-position-descriptions-to-letters *initial-string*)
(add-string-position-descriptions-to-letters *target-string*)
(update-workspace-values)
(let ((d (1st (tell (tell *initial-string* 'get-letter 0) 'get-descriptions))))
  (tell d 'update-strength)
  (printf "NOTHEMES\tdescr\t~a\t~a\t~a\t~a~%"
    (tell d 'print-name)
    (num (tell d 'get-thematic-compatibility))
    (rep (tell d 'get-thematic-compatibility))
    (tell d 'get-strength)))
;; TWO active themes on the SAME dimension, one at 100 and one at 90, so the
;; description's support values are the exact INTEGER 1 and the exact RATIO
;; 9/10. Scheme's `max` returns the integer; a port whose `max` promotes to a
;; common type returns 1/1 instead -- the same number, a different thing, and
;; the only shape in which that difference is observable.
(tell *themespace* 'thematic-pressure-on)
(let* ((d (1st (tell (tell *initial-string* 'get-letter 0) 'get-descriptions)))
       (dim (tell d 'get-description-type))
       (rels (tell *themespace* 'get-relations 'vertical-bridge dim)))
  (tell *themespace* 'set-theme-activation 'vertical-bridge dim (1st rels) 100)
  (tell *themespace* 'set-theme-activation 'vertical-bridge dim (2nd rels) 90)
  (tell d 'update-strength)
  (printf "MIXED\t~a\t~a\t~a\t~a\t~a~%"
    (tell d 'print-name)
    (map num (tell d 'get-theme-support-values))
    (num (tell d 'get-thematic-compatibility))
    (rep (tell d 'get-thematic-compatibility))
    (tell d 'get-strength)))
(tell *themespace* 'initialize)

(let* ((o1 (tell *initial-string* 'get-letter 0))
       (o2 (tell *target-string* 'get-letter 0))
       (cms (all-possible-bridge-CMs 'vertical
              o1 (tell o1 'get-descriptions) o2 (tell o2 'get-descriptions)))
       (b (make-vertical-bridge o1 o2 cms)))
  (tell b 'update-strength)
  (printf "NOTHEMES\tbridge\t~a\t~a\t~a\t~a\t~a~%"
    (num (tell b 'get-average-theme-support))
    (rep (tell b 'get-average-theme-support))
    (num (tell b 'get-thematic-compatibility))
    (rep (tell b 'get-thematic-compatibility))
    (tell b 'get-strength)))
