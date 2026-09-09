;; The trace's PATTERN vocabulary and the clamping it drives (trace.ss
;; 1412-1672).
;;
;; A pattern is how the trace says what a moment of processing was about:
;; a theme pattern, a concept pattern or a codelet pattern. Patterns are
;; compared ignoring activations and urgencies, which is what lets the trace
;; recognise it has been here before. Clamping is the other direction --
;; forcing the model into a pattern -- and is the mechanism the whole
;; self-watching loop rests on.
;;
;; Patterns are written by hand rather than harvested from a run: the equality
;; rules have specific blind spots (activations, urgencies, order) and the only
;; way to test a blind spot is to construct two patterns that differ ONLY
;; there. The clamping half is then applied to a real themespace, slipnet and
;; coderack and the effect dumped.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define sn (lambda (n) (if (exists? n) (tell n 'get-short-name) "*")))
(define yn (lambda (b) (if b "y" "n")))

(define join
  (lambda (strings)
    (if (null? strings)
      "-"
      (let loop ((l (rest strings)) (acc (1st strings)))
        (if (null? l) acc (loop (rest l) (string-append acc "," (1st l))))))))

(define lcat plato-letter-category)
(define spos plato-string-position-category)
(define dir plato-direction-category)
(define otype plato-object-category)
(define len plato-length)
(define gtype plato-group-category)
(define iden plato-identity)
(define opp plato-opposite)
(define succ plato-successor)
(define pred plato-predecessor)

;; a pattern's own rendering, since print-pattern needs relation-name from
;; theme-graphics.ss, which the headless harness never loads
(define entry-tag
  (lambda (pattern-type entry)
    (case pattern-type
      (concepts (format "~a=~a" (sn (1st entry)) (2nd entry)))
      (codelets (format "~a=~a" (tell (1st entry) 'get-codelet-type-name)
                  (2nd entry)))
      (else (format "~a/~a~a" (sn (1st entry)) (nm (2nd entry))
              (if (= (length entry) 3) (format "@~a" (3rd entry)) ""))))))

(define pattern-tag
  (lambda (pattern)
    (format "(~a ~a)" (1st pattern)
      (join (map (lambda (e) (entry-tag (1st pattern) e)) (entries pattern))))))

;;----------------------------------------------------------- pattern types ---

(printf "SECTION\ttypes~%")

(define tp1 (list 'top-bridge (list lcat succ) (list spos iden)))
(define tp2 (list 'top-bridge (list spos iden) (list lcat succ)))       ; reordered
(define tp3 (list 'top-bridge (list lcat succ 80) (list spos iden 40))) ; activations
(define tp4 (list 'top-bridge (list lcat succ) (list spos opp)))        ; differs
(define tp5 (list 'vertical-bridge (list lcat succ) (list spos iden)))  ; other type
(define tp6 (list 'top-bridge (list lcat succ)))                        ; subset
(define tp7 (list 'top-bridge (list lcat #f) (list otype iden)))        ; diff relation
(define cp1 (list 'concepts (list lcat 100) (list spos 100)))
(define cp2 (list 'concepts (list spos 50) (list lcat 20)))             ; activations
(define cp3 (list 'concepts (list lcat 100) (list dir 100)))            ; differs
(define kp1 (list 'codelets (list bond-evaluator %high-urgency%)
                            (list bond-builder %high-urgency%)))
(define kp2 (list 'codelets (list bond-builder %low-urgency%)
                            (list bond-evaluator %low-urgency%)))       ; urgencies
(define kp3 (list 'codelets (list bond-evaluator %high-urgency%)
                            (list rule-scout %high-urgency%)))          ; differs

(define all-patterns
  (list (list "tp1" tp1) (list "tp2" tp2) (list "tp3" tp3) (list "tp4" tp4)
        (list "tp5" tp5) (list "tp6" tp6) (list "tp7" tp7)
        (list "cp1" cp1) (list "cp2" cp2) (list "cp3" cp3)
        (list "kp1" kp1) (list "kp2" kp2) (list "kp3" kp3)))

(for* each p in all-patterns do
  (printf "PAT\t~a\t~a\ttheme=~a\tconcept=~a\tcodelet=~a\tn=~a~%"
    (1st p) (pattern-tag (2nd p))
    (yn (theme-pattern? (2nd p))) (yn (concept-pattern? (2nd p)))
    (yn (codelet-pattern? (2nd p))) (length (entries (2nd p)))))

;;-------------------------------------------------------------- comparison ---

(printf "SECTION\tequality~%")

(let loop1 ((xs all-patterns))
  (when (not (null? xs))
    (let loop2 ((ys all-patterns))
      (when (not (null? ys))
        (printf "EQ\t~a\t~a\t~a\t~a~%" (1st (1st xs)) (1st (1st ys))
          (yn (same-pattern-type? (2nd (1st xs)) (2nd (1st ys))))
          ;; patterns-equal? falls through to void for same-but-unknown types,
          ;; which cannot happen; print it as a boolean
          (yn (eq? #t (patterns-equal? (2nd (1st xs)) (2nd (1st ys))))))
        (loop2 (rest ys))))
    (loop1 (rest xs))))

(printf "SECTION\tpresent~%")
(define pattern-sets
  (list (list "none" '())
        (list "themes" (list tp1))
        (list "concepts" (list cp1))
        (list "mixed" (list tp1 cp1 kp1))))
(let loop1 ((ps all-patterns))
  (when (not (null? ps))
    (let loop2 ((ss pattern-sets))
      (when (not (null? ss))
        (printf "PRESENT\t~a\t~a\t~a~%" (1st (1st ps)) (1st (1st ss))
          (yn (pattern-type-present? (2nd (1st ps)) (2nd (1st ss)))))
        (loop2 (rest ss))))
    (loop1 (rest ps))))

;;--------------------------------------------------------------- negation ---

(printf "SECTION\tnegate~%")
(for* each p in (list (list "tp1" tp1) (list "tp3" tp3) (list "tp7" tp7)) do
  (for* each e in (entries (2nd p)) do
    (printf "NEG\t~a\t~a\t~a~%" (1st p) (entry-tag 'top-bridge e)
      (entry-tag 'top-bridge (negate-theme-pattern-entry e)))))

;;------------------------------------------------- associated concept pattern ---

(printf "SECTION\tassociated~%")
(for* each p in (list (list "tp1" tp1) (list "tp3" tp3) (list "tp4" tp4)
                      (list "tp7" tp7)
                      (list "tpneg" (list 'top-bridge (list spos opp -60)
                                          (list lcat succ 50)))) do
  (printf "ASSOC\t~a\t~a~%" (1st p)
    (pattern-tag (get-associated-concept-pattern (2nd p)))))

;;----------------------------------------------------------- theme clamping ---

(printf "SECTION\tthemeclamp~%")

(define dump-themes
  (lambda (tag)
    (for* each type in '(top-bridge bottom-bridge vertical-bridge) do
      (let ((themes (tell *themespace* 'get-themes type)))
        (printf "TH\t~a\t~a\t~a\tfrozen=~a\tpressure=~a~%" tag type
          (join (map (lambda (th)
                       (format "~a@~a" (tell th 'ascii-name)
                         (tell th 'get-activation)))
                  themes))
          (yn (tell *themespace* 'theme-type-frozen? type))
          (yn (tell *themespace* 'thematic-pressure? type)))))))

(tell *themespace* 'initialize)
(dump-themes "initial")
(impose-theme-pattern tp3)
(dump-themes "imposed")
(clamp-theme-pattern tp4)
(dump-themes "clamped")
;; clamping wipes the type first, so tp3's StringPos:iden is gone
(clamp-theme-pattern tp5)
(dump-themes "clamped-vertical")
(unclamp-theme-pattern tp4)
(dump-themes "unclamped")
(tell *themespace* 'initialize)
(dump-themes "reinitialized")

;;--------------------------------------------------------- concept clamping ---

(printf "SECTION\tconceptclamp~%")

(define dump-concepts
  (lambda (tag nodes)
    (for* each n in nodes do
      (printf "CN\t~a\t~a\tact=~a\tfrozen=~a~%" tag (sn n)
        (tell n 'get-activation) (yn (tell n 'frozen?))))))

(define watched (list lcat spos dir))
(for* each n in *slipnet-nodes* do (tell n 'reset))
(dump-concepts "initial" watched)
(clamp-concept-pattern cp1)
(dump-concepts "clamped" watched)
;; a clamped node ignores set-activation
(for* each n in watched do (tell n 'set-activation 7))
(dump-concepts "after-set" watched)
(unclamp-concept-pattern cp1)
(dump-concepts "unclamped" watched)
(for* each n in watched do (tell n 'set-activation 7))
(dump-concepts "after-set2" watched)

;;--------------------------------------------------------- codelet clamping ---

(printf "SECTION\tcodeletclamp~%")

(define dump-codelet-types
  (lambda (tag types)
    (for* each ct in types do
      (printf "CT\t~a\t~a\tclamped=~a\turgency=~a~%" tag
        (tell ct 'get-codelet-type-name) (yn (tell ct 'clamped?))
        (if (tell ct 'clamped?) (tell ct 'get-clamped-urgency) "-")))))

(printf "NTYPES\t~a~%" (length *codelet-types*))
(printf "TYPES\t~a~%"
  (join (map (lambda (ct) (format "~a" (tell ct 'get-codelet-type-name)))
          *codelet-types*)))

(define watched-types (list bond-evaluator bond-builder rule-scout breaker))
(dump-codelet-types "initial" watched-types)

;; the rack has to exist for clamping to move codelets between bins
(tell *coderack* 'initialize)
(set! *codelet-count* 0)
(tell *coderack* 'post (tell bond-evaluator 'make-codelet %very-low-urgency%))
(tell *coderack* 'post (tell bond-builder 'make-codelet %very-low-urgency%))
(tell *coderack* 'post (tell rule-scout 'make-codelet %very-low-urgency%))
;; A coderack-bin has no number accessor, so bin membership is observed
;; through the per-bin counts instead -- which is what a clamp actually
;; changes when it moves a codelet.
(define dump-rack
  (lambda (tag)
    (for* each c in (reverse (tell *coderack* 'get-all-codelets)) do
      (printf "CD\t~a\t~a\turg=~a~%" tag
        (tell c 'get-codelet-type-name) (tell c 'get-relative-urgency)))
    (printf "BINS\t~a\t~a~%" tag
      (join (map (lambda (b) (number->string (tell b 'get-num-of-codelets)))
              (tell *coderack* 'get-all-bins))))))
(dump-rack "posted")
(clamp-codelet-pattern kp1)
(dump-codelet-types "clamped" watched-types)
(dump-rack "clamped")
;; a codelet made now takes the clamped urgency
(tell *coderack* 'post (tell bond-evaluator 'make-codelet %very-low-urgency%))
(dump-rack "posted-while-clamped")
(unclamp-codelet-pattern kp1)
(dump-codelet-types "unclamped" watched-types)
(dump-rack "unclamped")

(printf "SECTION\tcomplement~%")
(define comp1 (get-complement-codelet-pattern %low-urgency% (list kp1)))
(define comp2 (get-complement-codelet-pattern %medium-urgency% (list kp1 kp3)))
(printf "COMP\tkp1\t~a\t~a~%" (length (entries comp1)) (pattern-tag comp1))
(printf "COMP\tkp1+kp3\t~a\t~a~%" (length (entries comp2)) (pattern-tag comp2))
(define bg (against-background %low-urgency% kp1))
(printf "BG\t~a\t~a~%" (length (entries bg)) (pattern-tag bg))

(printf "SECTION\tstandard~%")
(for* each p in (list (list "topdown" %top-down-codelet-pattern%)
                      (list "bottomup" %bottom-up-codelet-pattern%)
                      (list "thematic" %thematic-codelet-pattern%)
                      (list "rule" %rule-codelet-pattern%)
                      (list "bond" %bond-codelet-pattern%)
                      (list "group" %group-codelet-pattern%)
                      (list "bridge" %bridge-codelet-pattern%)
                      (list "description" %description-codelet-pattern%)
                      (list "answer" %answer-codelet-pattern%)) do
  (printf "STD\t~a\t~a\t~a~%" (1st p) (length (entries (2nd p)))
    (pattern-tag (2nd p))))
;; and they compare as the same idea regardless of urgency
(printf "STDEQ\tbond-vs-bond\t~a~%"
  (yn (eq? #t (patterns-equal? %bond-codelet-pattern% %bond-codelet-pattern%))))
(printf "STDEQ\tbond-vs-group\t~a~%"
  (yn (eq? #t (patterns-equal? %bond-codelet-pattern% %group-codelet-pattern%))))
