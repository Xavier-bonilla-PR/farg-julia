;; Metacat's episodic memory: what it has answered before, what it got stuck on
;; before, and how far apart two answers are.
;;
;; Unlike the codelet probes this one builds its answer descriptions BY HAND
;; rather than running the model, for the same reason the `rules` probe builds
;; rule clauses by hand: the distance metric has a dozen branches and reaching
;; them by driving the coderack would be a matter of luck. Every arm of
;; calculate-answer-distance is reached deliberately here -- identical answers,
;; answers differing only in themes, only in rules, rules with no common shape
;; at all, unjustified themes, and the incoherence flag.
;;
;; The rule clauses and theme patterns are written straight from the grammar,
;; so the two sides cannot disagree about what they are comparing.
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

;; The model's own path from a symbol to its letter-category nodes.
(define letters
  (lambda (word)
    (tell (make-workspace-string 'initial word) 'get-letter-categories)))

;; theme entries are (dimension relation); a pattern is (type entry ...)
(define pat
  (lambda (type . es) (cons type es)))

(define theme-tag
  (lambda (e) (format "~a/~a" (sn (1st e)) (nm (2nd e)))))

(define lcat plato-letter-category)
(define spos plato-string-position-category)
(define dir plato-direction-category)
(define otype plato-object-category)
(define len plato-length)
(define gtype plato-group-category)
(define apos plato-alphabetic-position-category)
(define iden plato-identity)
(define opp plato-opposite)
(define succ plato-successor)
(define pred plato-predecessor)

;; rule clauses, written from the grammar at the top of rules.ss
(define change-clause
  (lambda (otype-node dtype descriptor . changes)
    (list 'intrinsic (list (list otype-node dtype descriptor)) changes)))
(define swap-clause
  (lambda (ods dims) (list 'extrinsic ods dims)))
(define verb-clause
  (lambda (word) (list 'verbatim (letters word))))

;; NB: update-activation calls the answer's normal-icon-pexp GENERATOR, which
;; is #f until set-graphics-info supplies one -- so an answer description
;; cannot change activation headless without one. The harness stubs the memory
;; WINDOW but not this, so the probe supplies a no-op generator. The Julia port
;; drops the graphics entirely, which is why it needs no equivalent.
(define answer
  (lambda (i m t a top-clauses bot-clauses top-abs bot-abs temp quality
            vpattern upattern uslippages)
    (let ((a (make-answer-description
               (letters i) (letters m) (letters t) (letters a)
               top-clauses bot-clauses '("top phrase") '("bottom phrase")
               top-abs bot-abs temp quality vpattern
               (pat 'top-bridge) (pat 'bottom-bridge)
               upattern uslippages)))
      (tell a 'set-graphics-info (lambda (activation) '()) '())
      a)))

;; NB: make-snag-description reads the three strings from the GLOBALS rather
;; than taking them, so the workspace has to be initialised before one is made.
(define snag
  (lambda (rule-clauses translated-clauses explanation spattern)
    (make-snag-description
      rule-clauses translated-clauses '("snag phrase") '("translated phrase")
      explanation spattern)))

(define show-answer
  (lambda (tag a)
    (printf "~a\tANS\t~a\tq=~a\ttemp=~a\tabs=~a/~a\tact=~a\tunjust=~a~%"
      tag (tell a 'print-name) (tell a 'get-quality) (tell a 'get-temperature)
      (tell a 'get-top-rule-abstractness) (tell a 'get-bottom-rule-abstractness)
      (tell a 'get-activation) (yn (tell a 'unjustified?)))
    (printf "~a\tPROB\t~a~%" tag (tell a 'problem-print-name))
    (printf "~a\tTHEMES\t~a~%" tag (join (map theme-tag (tell a 'get-themes))))
    (printf "~a\tUTHEMES\t~a~%" tag
      (join (map theme-tag (tell a 'get-unjustified-themes))))
    (printf "~a\tABSTR\t~a\tincoherent=~a~%" tag
      (average-theme-abstractness a) (yn (answer-incoherent? a)))))

;;------------------------------------------------------------- descriptions ---

(printf "SECTION\tdescriptions~%")

(define r-succ
  (list (change-clause plato-letter spos plato-rightmost (list 'self lcat succ))))
(define r-pred
  (list (change-clause plato-letter spos plato-leftmost (list 'self lcat pred))))
(define r-succ-group
  (list (change-clause plato-group spos plato-rightmost (list 'self lcat succ))))
(define r-len
  (list (change-clause plato-group spos plato-rightmost (list 'self len succ))))
(define r-verb (list (verb-clause 'abd)))
(define r-two-changes
  (list (change-clause plato-letter spos plato-rightmost
          (list 'self lcat succ) (list 'self otype plato-letter))))

;; a spread of answers over the same problem
(define a1
  (answer 'abc 'abd 'ijk 'ijl r-succ r-succ 40 40 30 80
    (pat 'vertical-bridge (list lcat iden) (list spos iden) (list otype iden))
    (pat 'vertical-bridge) '()))
(define a2   ; identical to a1 -- distance must be 0
  (answer 'abc 'abd 'ijk 'ijl r-succ r-succ 40 40 30 80
    (pat 'vertical-bridge (list lcat iden) (list spos iden) (list otype iden))
    (pat 'vertical-bridge) '()))
(define a3   ; same rules, one theme differs in RELATION
  (answer 'abc 'abd 'ijk 'ijl r-succ r-succ 40 40 30 80
    (pat 'vertical-bridge (list lcat iden) (list spos opp) (list otype iden))
    (pat 'vertical-bridge) '()))
(define a4   ; same rules, an extra theme a1 does not have
  (answer 'abc 'abd 'ijk 'ijl r-succ r-succ 40 40 30 80
    (pat 'vertical-bridge (list lcat iden) (list spos iden) (list otype iden)
      (list dir opp))
    (pat 'vertical-bridge) '()))
(define a5   ; different top rule, same shape
  (answer 'abc 'abd 'ijk 'ijl r-pred r-succ 40 40 30 80
    (pat 'vertical-bridge (list lcat iden) (list spos iden) (list otype iden))
    (pat 'vertical-bridge) '()))
(define a6   ; verbatim top rule -- no common shape with r-succ at all
  (answer 'abc 'abd 'ijk 'ijl r-verb r-succ 10 40 30 80
    (pat 'vertical-bridge (list lcat iden) (list spos iden) (list otype iden))
    (pat 'vertical-bridge) '()))
(define a7   ; different SHAPE of rule (two changes, not one)
  (answer 'abc 'abd 'ijk 'ijl r-two-changes r-succ 40 40 30 80
    (pat 'vertical-bridge (list lcat iden) (list spos iden) (list otype iden))
    (pat 'vertical-bridge) '()))
(define a8   ; unjustified themes
  (answer 'abc 'abd 'ijk 'ijl r-succ r-succ 40 40 30 80
    (pat 'vertical-bridge (list lcat iden) (list spos iden))
    (pat 'vertical-bridge (list otype iden) (list dir opp)) '()))
(define a9   ; abstract themes over a concrete rule -- incoherent
  (answer 'abc 'abd 'ijk 'ijl r-succ r-succ 5 40 30 80
    (pat 'vertical-bridge (list apos opp) (list gtype opp) (list len succ))
    (pat 'vertical-bridge) '()))
(define a10  ; a different answer string entirely
  (answer 'abc 'abd 'ijk 'ijd r-succ r-succ 40 40 30 60
    (pat 'vertical-bridge (list lcat iden) (list spos iden) (list otype iden))
    (pat 'vertical-bridge) '()))
(define a11  ; group rule rather than letter rule
  (answer 'abc 'abd 'ijk 'ijl r-succ-group r-succ 60 40 30 80
    (pat 'vertical-bridge (list lcat iden) (list otype opp))
    (pat 'vertical-bridge) '()))
(define a12  ; a length rule
  (answer 'abc 'abd 'ijk 'ijl r-len r-succ 70 40 30 80
    (pat 'vertical-bridge (list len succ) (list spos iden))
    (pat 'vertical-bridge) '()))

(define all-answers (list a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12))
(define answer-names
  '("a1" "a2" "a3" "a4" "a5" "a6" "a7" "a8" "a9" "a10" "a11" "a12"))

(let loop ((as all-answers) (ns answer-names))
  (when (not (null? as))
    (show-answer (1st ns) (1st as))
    (loop (rest as) (rest ns))))

;;----------------------------------------------------------------- distance ---

(printf "SECTION\tdistance~%")

;; every pair, both ways round -- the metric is not obviously symmetric
(let loop1 ((as all-answers) (ns answer-names))
  (when (not (null? as))
    (let loop2 ((bs all-answers) (ms answer-names))
      (when (not (null? bs))
        (printf "DIST\t~a\t~a\t~a~%" (1st ns) (1st ms)
          (calculate-answer-distance (1st as) (1st bs)))
        (loop2 (rest bs) (rest ms))))
    (loop1 (rest as) (rest ns))))

;; the rule comparison on its own, since it is the part with a failure mode
(printf "SECTION\trulecompare~%")
(define rule-lists
  (list (list "succ" r-succ) (list "pred" r-pred) (list "group" r-succ-group)
        (list "len" r-len) (list "verb" r-verb) (list "two" r-two-changes)))
(let loop1 ((xs rule-lists))
  (when (not (null? xs))
    (let loop2 ((ys rule-lists))
      (when (not (null? ys))
        (let ((result (compare-rule-clause-lists (2nd (1st xs)) (2nd (1st ys)))))
          (printf "RCMP\t~a\t~a\t~a~%" (1st (1st xs)) (1st (1st ys))
            (if (not (exists? result))
              "none"
              (join (map (lambda (p) (format "~a>~a" (sn (1st p)) (sn (2nd p))))
                      result)))))
        (loop2 (rest ys))))
    (loop1 (rest xs))))

;;--------------------------------------------------------------- the memory ---

(printf "SECTION\tstore~%")

(tell *memory* 'clear)
(printf "EMPTY\t~a\t~a\t~a~%"
  (length (tell *memory* 'get-answers))
  (length (tell *memory* 'get-snags))
  (length (tell *memory* 'get-all-descriptions)))

;; adding compares each stored answer against the newcomer, which is what
;; activates the ones it reminds Metacat of
(let loop ((as all-answers) (ns answer-names))
  (when (not (null? as))
    (tell *memory* 'add-answer-description (1st as))
    (printf "ADD\t~a\tn=~a~%" (1st ns) (length (tell *memory* 'get-answers)))
    (let loop2 ((bs (tell *memory* 'get-answers)))
      (when (not (null? bs))
        (printf "ACT\t~a\t~a\t~a~%" (1st ns)
          (tell (1st bs) 'print-name) (tell (1st bs) 'get-activation))
        (loop2 (rest bs))))
    (loop (rest as) (rest ns))))

;; answer-present? is what stops the model reporting the same answer twice
(printf "SECTION\tpresent~%")
(init-workspace 'abc 'abd 'ijk #f)
(define fake-top-rule (make-rule 'top r-succ))
(define fake-bot-rule (make-rule 'bottom r-succ))
(define fake-top-rule2 (make-rule 'top r-pred))
(printf "PRESENT\tijl-succ-succ\t~a~%"
  (yn (tell *memory* 'answer-present? (letters 'ijl) fake-top-rule fake-bot-rule)))
(printf "PRESENT\tijl-pred-succ\t~a~%"
  (yn (tell *memory* 'answer-present? (letters 'ijl) fake-top-rule2 fake-bot-rule)))
(printf "PRESENT\tijz-succ-succ\t~a~%"
  (yn (tell *memory* 'answer-present? (letters 'ijz) fake-top-rule fake-bot-rule)))

;; snags
(printf "SECTION\tsnags~%")
;; NB: get-snag-justified-themes is (intersect (answer's themes MINUS the
;; snag's) (answer's unjustified themes)) -- so a snag whose themes CONTAIN the
;; answer's unjustified ones justifies nothing. s1 deliberately shares only a
;; justified theme with a8, leaving a8's unjustified ones to come back.
(define s1 (snag r-succ r-succ "the rule could not be applied"
             (pat 'vertical-bridge (list lcat iden))))
(define s2 (snag r-pred r-succ "the letters ran out"
             (pat 'vertical-bridge (list otype iden) (list dir opp))))
(tell *memory* 'add-snag-description s1)
(tell *memory* 'add-snag-description s2)
(printf "SNAGS\t~a\t~a~%"
  (length (tell *memory* 'get-snags))
  (length (tell *memory* 'get-all-descriptions)))
(printf "SNAGPRESENT\tsucc\t~a~%" (yn (tell *memory* 'snag-present? fake-top-rule)))
(printf "SNAGPRESENT\tpred\t~a~%" (yn (tell *memory* 'snag-present? fake-top-rule2)))
;; a8's unjustified themes are exactly what s1 explains
(let loop ((as all-answers) (ns answer-names))
  (when (not (null? as))
    (let ((eq-snag (tell *memory* 'get-equivalent-snag (1st as))))
      (printf "EQSNAG\t~a\t~a\tjustified=~a~%" (1st ns)
        (if (exists? eq-snag) (tell eq-snag 'problem-print-name) "-")
        (join (map theme-tag (get-snag-justified-themes (1st as))))))
    (loop (rest as) (rest ns))))

;; the distances again, now that a snag is in memory and can justify a theme
(printf "SECTION\tdistance-with-snag~%")
(let loop1 ((as all-answers) (ns answer-names))
  (when (not (null? as))
    (let loop2 ((bs all-answers) (ms answer-names))
      (when (not (null? bs))
        (printf "DIST2\t~a\t~a\t~a~%" (1st ns) (1st ms)
          (calculate-answer-distance (1st as) (1st bs)))
        (loop2 (rest bs) (rest ms))))
    (loop1 (rest as) (rest ns))))

;; clearing
(printf "SECTION\tclear~%")
(tell *memory* 'clear-activations)
(printf "CLEARACT\t~a~%"
  (join (map (lambda (a) (number->string (tell a 'get-activation)))
          (tell *memory* 'get-answers))))
(tell *memory* 'delete a1)
(printf "DELETE\t~a\t~a\t~a~%"
  (length (tell *memory* 'get-answers))
  (length (tell *memory* 'get-snags))
  (length (tell *memory* 'get-all-descriptions)))
(tell *memory* 'delete s1)
(printf "DELETE\t~a\t~a\t~a~%"
  (length (tell *memory* 'get-answers))
  (length (tell *memory* 'get-snags))
  (length (tell *memory* 'get-all-descriptions)))
(tell *memory* 'clear)
(printf "CLEARED\t~a\t~a\t~a~%"
  (length (tell *memory* 'get-answers))
  (length (tell *memory* 'get-snags))
  (length (tell *memory* 'get-all-descriptions)))
