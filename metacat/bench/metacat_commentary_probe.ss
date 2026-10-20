;; answers.ss (95-928): the COMMENTARY -- the English Metacat writes about its
;; own answers.
;;
;; This is the part of the program the thesis is really about, and it is the
;; only layer whose output is prose rather than numbers. It reads nothing but
;; the episodic memory: an answer description, and at most one other to compare
;; it with. By the time these run the run is over, so everything they can say
;; has to have survived abstraction into memory.
;;
;; Like the `memory` and `rules` probes, this one builds its descriptions BY
;; HAND. `theme-phrases` alone has four clauses whose presence depends on each
;; other -- string-position and group-category share a clause when both are
;; there, bond-facet rides inside that clause in one case and gets its own in
;; another -- and `get-answer-comparison-text` has a dozen top-level arms and a
;; nine-way verdict at the end. Reaching those by running the model would be a
;; matter of luck; here every arm is chosen.
;;
;; The memory holds a SNAG description as well, because two of the branches
;; exist only to say "this idea has no justification except that it dodges the
;; snag we hit last time", and that sentence is assembled from the snag's own
;; explanation.
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

(define letters
  (lambda (word)
    (tell (make-workspace-string 'initial word) 'get-letter-categories)))

(define pat (lambda (type . es) (cons type es)))
(define theme-tag (lambda (e) (format "~a/~a" (sn (1st e)) (nm (2nd e)))))

(define lcat plato-letter-category)
(define spos plato-string-position-category)
(define dir plato-direction-category)
(define otype plato-object-category)
(define len plato-length)
(define gtype plato-group-category)
(define apos plato-alphabetic-position-category)
(define facet plato-bond-facet)
(define iden plato-identity)
(define opp plato-opposite)
(define succ plato-successor)
(define pred plato-predecessor)

(define change-clause
  (lambda (otype-node dtype descriptor . changes)
    (list 'intrinsic (list (list otype-node dtype descriptor)) changes)))
(define verb-clause (lambda (word) (list 'verbatim (letters word))))

(define answer
  (lambda (i m t a top-clauses top-abs quality vpattern upattern)
    (let ((a (make-answer-description
               (letters i) (letters m) (letters t) (letters a)
               top-clauses top-clauses '("top phrase") '("bottom phrase")
               top-abs top-abs 30 quality vpattern
               (pat 'top-bridge) (pat 'bottom-bridge)
               upattern '())))
      (tell a 'set-graphics-info (lambda (activation) '()) '())
      a)))

;;--------------------------------------------------- punctuate-with-commas ---

(printf "SECTION\tpunctuate~%")

(for* each l in (list '() '("one") '("one" "two") '("one" "two" "three")
                      '("one" "two" "three" "four")) do
  (printf "PUNC\t~a\t[~a]\t[~a]~%" (length l)
    (punctuate-with-commas "and" l)
    (punctuate-with-commas "or" l)))

;;-------------------------------------------------------------- theme-phrases ---

(printf "SECTION\tthemephrases~%")

;; every combination of the four dimensions theme-phrases knows about, at every
;; relation, justified and not
(define tp
  (lambda (tag themes unjust snag-just prep conj verb caveats? the-strings? two)
    (printf "TP\t~a\t[~a]~%" tag
      (theme-phrases prep conj verb themes snag-just unjust
        "abc" "pqrs" "the letters do not line up" caveats? the-strings? two))))

(define sp-i (list spos iden))
(define sp-o (list spos opp))
(define sp-d (list spos #f))
(define gc-i (list gtype iden))
(define gc-o (list gtype opp))
(define gc-d (list gtype #f))
(define ap-i (list apos iden))
(define ap-o (list apos opp))
(define bf   (list facet iden))

(tp "spos-iden"     (list sp-i) '() '() "on " "and" "ing" #f #f #f)
(tp "spos-opp"      (list sp-o) '() '() "on " "and" "ing" #f #f #f)
(tp "spos-diff"     (list sp-d) '() '() "on " "and" "ing" #f #f #f)
(tp "gctgy-iden"    (list gc-i) '() '() "on " "and" "ing" #f #f #f)
(tp "gctgy-opp"     (list gc-o) '() '() "on " "and" "ing" #f #f #f)
(tp "gctgy-diff"    (list gc-d) '() '() "on " "and" "ing" #f #f #f)
(tp "gctgy+facet"   (list gc-o bf) '() '() "on " "and" "ing" #f #f #f)
(tp "spos+gctgy"    (list sp-o gc-o) '() '() "on " "and" "ing" #f #f #f)
(tp "spos+gctgy+bf" (list sp-o gc-o bf) '() '() "on " "and" "ing" #f #f #f)
(tp "facet-alone"   (list bf) '() '() "on " "and" "ing" #f #f #f)
(tp "apos-iden"     (list ap-i) '() '() "on " "and" "ing" #f #f #f)
(tp "apos-opp"      (list ap-o) '() '() "on " "and" "ing" #f #f #f)
(tp "all-four"      (list sp-i gc-i bf ap-o) '() '() "on " "and" "ing" #f #f #f)
;; the group-category theme unjustified: it drops out of the string-position
;; clause and, without one, out of its own
(tp "gctgy-unjust"  (list sp-o) (list gc-o) '() "on " "and" "ing" #f #f #f)
(tp "gctgy-unjust-alone" '() (list gc-o bf) '() "on " "and" "ing" #f #f #f)
;; caveats
(tp "caveat-unjust" (list sp-o) (list ap-o) '() "on " "and" "ing" #t #f #f)
(tp "caveat-snag"   (list sp-o) '() (list sp-o) "on " "and" "ing" #t #f #f)
(tp "caveat-both"   (list sp-o) (list ap-o) (list sp-o) "on " "and" "ing" #t #f #f)
;; the other prepositions and endings the callers use
(tp "to-or"         (list sp-o ap-o) '() '() "to " "or" "" #f #t #f)
(tp "of-and"        (list ap-i) '() '() "of " "and" "ing" #f #f #f)
(tp "bare"          (list sp-i bf) '() '() "" "and" "ing" #f #f #f)
;; two-strings replaces the string pair entirely
(tp "two-strings"   (list gc-i bf) '() '() "on " "and" "ing" #f #f
  "(abc and pqrs in both cases)")
(tp "the-strings"   (list bf ap-i) '() '() "on " "and" "ing" #f #t #f)
(tp "empty"         '() '() '() "on " "and" "ing" #f #f #f)

;;------------------------------------------------------- coherence-phrase ---

(printf "SECTION\tcoherence~%")

(for* each c in '(-100 -51 -50 -11 -10 -1 0 9 10 50) do
  (printf "COH\t~a\t~a~%" c (coherence-phrase c)))

;;----------------------------------------------------------------- explain ---

(printf "SECTION\texplain~%")

;; the workspace has to exist before a snag description can be made: it reads
;; the three strings from the globals
(init-workspace 'abc 'abd 'ijk #f)

(define r-succ
  (list (change-clause plato-letter spos plato-rightmost (list 'self lcat succ))))
(define r-pred
  (list (change-clause plato-letter spos plato-leftmost (list 'self lcat pred))))
(define r-len
  (list (change-clause plato-group spos plato-rightmost (list 'self len succ))))
(define r-verb (list (verb-clause 'abd)))

(define e1
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 80
    (pat 'vertical-bridge sp-i (list lcat iden)) (pat 'vertical-bridge)))
(define e2
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 40
    (pat 'vertical-bridge sp-o gc-o) (pat 'vertical-bridge ap-o)))
(define e3
  (answer 'abc 'cba 'pqrs 'srqp r-pred 70 95
    (pat 'vertical-bridge sp-o gc-o bf) (pat 'vertical-bridge)))

;; `explain` writes to the comment window, so capture what it says rather than
;; rebuilding the string here: the point is to exercise `explain` itself.
(define *captured* '())
(set! *comment-window*
  (lambda args
    (if (and (pair? (rest args)) (eq? (2nd args) 'add-comment))
      (set! *captured* (list (3rd args) (4th args))))
    (void)))

(define show-explanation
  (lambda (tag a)
    (set! *captured* '())
    (explain a)
    (printf "EXPL\t~a\t~a~%" tag
      (join (map (lambda (line) (format "[~a]" line)) (1st *captured*))))
    (printf "EXPLV\t~a\t~a~%" tag
      (join (map (lambda (line) (format "[~a]" line)) (2nd *captured*))))))

(for* each pair in (list (list "e1" e1) (list "e2" e2) (list "e3" e3)) do
  (show-explanation (1st pair) (2nd pair)))

;;-------------------------------------------------- snag-justified commentary ---

(printf "SECTION\tsnagjustified~%")

;; A snag on e2's problem and top rule, so that get-equivalent-snag finds it.
;; Its themes must NOT include the theme we want reported as snag-justified:
;; snag-avoiding themes are the answer's OWN themes minus the snag's, and only
;; those that are also unjustified count. So the snag is about string-position
;; and e2's unjustified alphabetic-position theme comes back as the thing that
;; dodges it.
(define s1
  (make-snag-description r-succ r-succ '("snag phrase") '("translated phrase")
    "the k has no successor" (pat 'vertical-bridge sp-o)))
(tell *memory* 'add-snag-description s1)

(printf "SNAGEXPL\te2\t[~a]~%" (get-snag-explanation e2))
(printf "SNAGJUST\te2\t~a~%"
  (join (map theme-tag (get-snag-justified-themes e2))))
(show-explanation "e2-with-snag" e2)
(printf "SNAGEXPL\te1\t[~a]~%" (get-snag-explanation e1))

;;----------------------------------------------- get-answer-comparison-text ---

(printf "SECTION\tcompare~%")

(define cmp
  (lambda (tag a b)
    (printf "CMP\t~a\t[~a]~%" tag (get-answer-comparison-text a b))))

(define c-base
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 80
    (pat 'vertical-bridge sp-i (list lcat iden)) (pat 'vertical-bridge)))
(define c-identical
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 80
    (pat 'vertical-bridge sp-i (list lcat iden)) (pat 'vertical-bridge)))
(define c-rule-differs
  (answer 'abc 'abd 'ijk 'ijl r-len 70 80
    (pat 'vertical-bridge sp-i (list lcat iden)) (pat 'vertical-bridge)))
(define c-rule-shapeless
  (answer 'abc 'abd 'ijk 'ijl r-verb 10 80
    (pat 'vertical-bridge sp-i (list lcat iden)) (pat 'vertical-bridge)))
(define c-theme-differs
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 70
    (pat 'vertical-bridge sp-o (list lcat iden)) (pat 'vertical-bridge)))
(define c-extra-theme
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 75
    (pat 'vertical-bridge sp-i (list lcat iden) ap-o) (pat 'vertical-bridge)))
(define c-fewer-themes
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 75
    (pat 'vertical-bridge sp-i) (pat 'vertical-bridge)))
(define c-unjustified
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 60
    (pat 'vertical-bridge (list lcat iden)) (pat 'vertical-bridge sp-i)))
(define c-unjustified2
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 60
    (pat 'vertical-bridge sp-i) (pat 'vertical-bridge (list lcat iden))))
(define c-incoherent
  (answer 'abc 'abd 'ijk 'ijl r-verb 5 55
    (pat 'vertical-bridge gc-o ap-o bf) (pat 'vertical-bridge)))
(define c-incoherent2
  (answer 'abc 'abd 'ijk 'ijl r-verb 5 50
    (pat 'vertical-bridge gc-o ap-o) (pat 'vertical-bridge)))
(define c-other-problem
  (answer 'abc 'cba 'pqrs 'srqp r-pred 70 95
    (pat 'vertical-bridge sp-o gc-o) (pat 'vertical-bridge)))
(define c-same-string
  (answer 'abc 'abd 'ijk 'ijl r-pred 55 65
    (pat 'vertical-bridge ap-o bf) (pat 'vertical-bridge)))

;; No theme differences at all, but one answer cannot justify an idea the other
;; can -- and the one that can, can only because it dodges the remembered snag.
(define c-just-snag
  (answer 'abc 'abd 'ijk 'ijl r-succ 40 70
    (pat 'vertical-bridge sp-i) (pat 'vertical-bridge ap-o)))
(define c-just-none
  (answer 'abc 'abd 'ijk 'ijl r-pred 40 70
    (pat 'vertical-bridge sp-i) (pat 'vertical-bridge ap-o)))

(cmp "identical"        c-base c-identical)
(cmp "rule-differs"     c-base c-rule-differs)
(cmp "rule-shapeless"   c-base c-rule-shapeless)
(cmp "theme-differs"    c-base c-theme-differs)
(cmp "extra-theme"      c-base c-extra-theme)
(cmp "fewer-themes"     c-base c-fewer-themes)
(cmp "unjustified"      c-base c-unjustified)
(cmp "unjustified-both" c-unjustified c-unjustified2)
(cmp "incoherent-one"   c-base c-incoherent)
(cmp "incoherent-both"  c-incoherent c-incoherent2)
(cmp "other-problem"    c-base c-other-problem)
(cmp "same-string"      c-base c-same-string)
(cmp "reversed"         c-theme-differs c-base)
(cmp "self"             c-base c-base)
(cmp "justification"    c-just-snag c-just-none)
(cmp "justification-rev" c-just-none c-just-snag)
