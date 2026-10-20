;; Exercises the rule structure itself: its English transcription, its quality
;; metrics, and the predicates and equality test that let one rule stand in for
;; another.
;;
;; Rules are normally abstracted from horizontal bridges, which is a later
;; layer; here the clauses are written out by hand, straight from the grammar
;; in the comment at the top of rules.ss, so that every branch of the
;; transcription's fourteen-case table and every arm of the quality formulas
;; can be reached deliberately. The workspace is set up with bonds and groups
;; first, because an object description resolves against real objects (and a
;; whole-string group changes "string" into "whole group").
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))
(define num
  (lambda (v)
    (if (integer? v)
      (number->string v)
      (format "~a/~a" (numerator v) (denominator v)))))

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

;;------------------------------------ printing ------------------------------------

(define print-object-description
  (lambda (od)
    (printf "  OD\t~a~%" (format-object-description od))))

(define print-rule-clause
  (lambda (rc)
    (record-case rc
      (verbatim (letter-categories)
        (printf "  CLAUSE\tVERBATIM\t~a~%"
          (apply string-append (tell-all letter-categories 'get-lowercase-name))))
      (intrinsic (object-descriptions changes)
        (printf "  CLAUSE\tCHANGE\t~a~%"
          (format-object-description (1st object-descriptions)))
        (for* each change in changes do
          (printf "    CH\t(~a ~a ~a)~%"
            (1st change)
            (format-slipnode (2nd change))
            (format-slipnode (3rd change)))))
      (extrinsic (object-descriptions dimensions)
        (printf "  CLAUSE\tSWAP\t~a~%"
          (apply string-append
            (cons (format-slipnode (1st dimensions))
              (map (lambda (dim) (format ", ~a" (format-slipnode dim)))
                (rest dimensions)))))
        (if (= (length object-descriptions) 1)
          (printf "    subobjects\t~a~%"
            (format-object-description (1st object-descriptions)))
          (for* each od in object-descriptions do
            (printf "    OD\t~a~%" (format-object-description od))))))))

(define print-rule
  (lambda (label rule)
    (printf "RULE\t~a\t~a~%" label (tell rule 'get-rule-type))
    (for* each rc in (tell rule 'get-rule-clauses) do (print-rule-clause rc))
    (printf "  N\tintrinsic=~a\textrinsic=~a~%"
      (length (tell rule 'get-intrinsic-rule-clauses))
      (length (tell rule 'get-extrinsic-rule-clauses)))
    (printf "  FLAGS\tidentity=~a\tverbatim=~a\tliteral=~a\tabstract=~a\tchar=~a~%"
      (yn (tell rule 'identity?))
      (yn (tell rule 'verbatim?))
      (yn (tell rule 'literal?))
      (yn (tell rule 'abstract?))
      (tell rule 'get-characterization))
    (printf "  CHARZN\t~a~%" (rule-characterization rule))
    (for* each rc in (tell rule 'get-rule-clauses) do
      (printf "  LITCLAUSE\t~a~%" (yn (literal-clause? rc))))
    (tell rule 'set-quality-values)
    (printf "  Q\tunif=~a\tabst=~a\tsucc=~a\tintr=~a\tqual=~a~%"
      (tell rule 'get-uniformity)
      (tell rule 'get-abstractness)
      (tell rule 'get-succinctness)
      (tell rule 'get-intrinsic-quality)
      (tell rule 'get-quality))
    (printf "  CONCEPTS\t~a~%"
      (map (lambda (entry) (tell (1st entry) 'get-short-name))
        (rest (tell rule 'get-concept-pattern))))
    (if (tell rule 'verbatim?)
      (printf "  VERBLETTERS\t~a~%"
        (tell-all (tell rule 'get-verbatim-letter-categories) 'get-lowercase-name)))
    (for* each line in (tell rule 'get-english-transcription) do
      (printf "  EN\t|~a|~%" line))))

;;------------------------------------- clauses -------------------------------------

;; Every clause below is written out from the grammar, and the set is chosen to
;; walk the transcription table: ObjCtgy alone, ObjCtgy with Length, the
;; subobject variants of both, bare Length changes at either scope, and the
;; direction and group-category changes that get their own "Reverse ..."
;; phrasing.
(define od
  (lambda (object-type description-type descriptor)
    (list object-type description-type descriptor)))

(define ch list)

(define clause-table
  (lambda ()
    (list
      (list "letter-rmost-succ"
        (list 'intrinsic
          (list (od plato-letter plato-string-position-category plato-rightmost))
          (list (ch 'self plato-letter-category plato-successor))))
      (list "letter-lmost-literal"
        (list 'intrinsic
          (list (od plato-letter plato-letter-category plato-a))
          (list (ch 'self plato-letter-category plato-d))))
      (list "string-subobjs-a"
        (list 'intrinsic
          (list (od 'string plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-letter-category plato-a))))
      (list "group-whole-dir-opp"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'self plato-direction-category plato-opposite))))
      (list "group-whole-grpctgy"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'self plato-group-category plato-opposite)
                (ch 'self plato-bond-facet plato-letter-category))))
      (list "group-whole-grpctgy-len"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-group-category plato-opposite)
                (ch 'self plato-bond-facet plato-length))))
      (list "objctgy-self-letter"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-rightmost))
          (list (ch 'self plato-object-category plato-letter)
                (ch 'self plato-length plato-one)
                (ch 'self plato-letter-category plato-e))))
      (list "objctgy-self-group-rel-len"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-rightmost))
          (list (ch 'self plato-object-category plato-group)
                (ch 'self plato-length plato-successor))))
      (list "objctgy-self-group-lit-len"
        (list 'intrinsic
          (list (od plato-letter plato-string-position-category plato-rightmost))
          (list (ch 'self plato-object-category plato-group)
                (ch 'self plato-length plato-three)
                (ch 'self plato-letter-category plato-a))))
      (list "objctgy-self-only"
        (list 'intrinsic
          (list (od plato-letter plato-string-position-category plato-leftmost))
          (list (ch 'self plato-object-category plato-group)
                (ch 'self plato-letter-category plato-x))))
      (list "objsubs-lenself-lensubs-letter"
        (list 'intrinsic
          (list (od 'string plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-letter)
                (ch 'self plato-length plato-successor)
                (ch 'subobjects plato-length plato-one)
                (ch 'subobjects plato-letter-category plato-successor))))
      (list "objsubs-lenself-lensubs-rel"
        (list 'intrinsic
          (list (od 'string plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-group)
                (ch 'self plato-length plato-three)
                (ch 'subobjects plato-length plato-successor))))
      (list "objsubs-lenself-lensubs-lit"
        (list 'intrinsic
          (list (od 'string plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-group)
                (ch 'self plato-length plato-predecessor)
                (ch 'subobjects plato-length plato-two)
                (ch 'subobjects plato-letter-category plato-o))))
      (list "objsubs-lenself"
        (list 'intrinsic
          (list (od 'string plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-group)
                (ch 'self plato-length plato-four)
                (ch 'subobjects plato-letter-category plato-m))))
      (list "objsubs-lensubs-letter"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-letter)
                (ch 'subobjects plato-length plato-one))))
      (list "objsubs-lensubs-rel"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-group)
                (ch 'subobjects plato-length plato-predecessor))))
      (list "objsubs-lensubs-lit"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-group)
                (ch 'subobjects plato-length plato-five)
                (ch 'subobjects plato-letter-category plato-i))))
      (list "objsubs-only"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-letter)
                (ch 'subobjects plato-letter-category plato-successor))))
      (list "lenself-lensubs"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'self plato-length plato-successor)
                (ch 'subobjects plato-length plato-predecessor))))
      (list "lenself-only"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'self plato-length plato-two))))
      (list "lensubs-only"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-length plato-successor))))
      (list "alphapos-clause"
        (list 'intrinsic
          (list (od plato-letter plato-alphabetic-position-category
                    plato-alphabetic-first))
          (list (ch 'self plato-alphabetic-position-category plato-alphabetic-last))))
      (list "swap-one-od"
        (list 'extrinsic
          (list (od 'string plato-string-position-category plato-whole))
          (list plato-letter-category)))
      (list "swap-two-ods"
        (list 'extrinsic
          (list (od plato-letter plato-string-position-category plato-leftmost)
                (od plato-letter plato-string-position-category plato-rightmost))
          (list plato-letter-category plato-length)))
      (list "swap-three-dims"
        (list 'extrinsic
          (list (od plato-letter plato-string-position-category plato-leftmost)
                (od plato-group plato-letter-category plato-c))
          (list plato-letter-category plato-length plato-direction-category)))
      (list "verbatim"
        (list 'verbatim (list plato-a plato-b plato-d)))
      (list "objctgy-self-group-nolett"
        (list 'intrinsic
          (list (od plato-letter plato-string-position-category plato-leftmost))
          (list (ch 'self plato-object-category plato-group))))
      (list "objctgy-self-letter-nolett"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'self plato-object-category plato-letter))))
      (list "objsubs-group-nolett"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-group))))
      (list "objsubs-letter-nolett"
        (list 'intrinsic
          (list (od 'string plato-string-position-category plato-whole))
          (list (ch 'subobjects plato-object-category plato-letter))))
      ;; `c' is not one of the an-letters, so this is the "a `c' group" article
      (list "lit-group-article-a"
        (list 'intrinsic
          (list (od plato-letter plato-string-position-category plato-rightmost))
          (list (ch 'self plato-object-category plato-group)
                (ch 'self plato-length plato-three)
                (ch 'self plato-letter-category plato-c))))
      ;; a relation Length change keeps the literal LettCtgy change, which then
      ;; gets a phrase of its own
      (list "objctgy-group-rellen-litlett"
        (list 'intrinsic
          (list (od plato-letter plato-string-position-category plato-rightmost))
          (list (ch 'self plato-object-category plato-group)
                (ch 'self plato-length plato-successor)
                (ch 'self plato-letter-category plato-b))))
      (list "strpos-change"
        (list 'intrinsic
          (list (od plato-letter plato-string-position-category plato-leftmost))
          (list (ch 'self plato-string-position-category plato-rightmost))))
      (list "groupctgy-descriptor"
        (list 'intrinsic
          (list (od plato-group plato-group-category plato-samegrp))
          (list (ch 'self plato-direction-category plato-opposite))))
      (list "long-phrase"
        (list 'intrinsic
          (list (od plato-group plato-string-position-category plato-rightmost))
          (list (ch 'subobjects plato-alphabetic-position-category
                    plato-alphabetic-last)))))))

;; The rules built from those clauses: singletons for every clause, then a few
;; multi-clause rules, so that the uniformity formulas see mixtures of clause
;; types, of description dimensions and of literal against abstract changes.
(define rule-specs
  (lambda (table)
    (let ((cl (lambda (name) (2nd (assoc name table)))))
      (append
        (list (list "identity" '()))
        (map (lambda (entry) (list (1st entry) (list (2nd entry)))) table)
        (list
          (list "two-intrinsic-same-dim"
            (list (cl "letter-rmost-succ")
                  (list 'intrinsic
                    (list (od plato-letter plato-string-position-category
                              plato-leftmost))
                    (list (ch 'self plato-letter-category plato-predecessor)))))
          (list "two-intrinsic-mixed-abstractness"
            (list (cl "letter-rmost-succ") (cl "letter-lmost-literal")))
          (list "two-intrinsic-mixed-dims"
            (list (cl "letter-rmost-succ") (cl "alphapos-clause")))
          (list "intrinsic-plus-extrinsic"
            (list (cl "letter-rmost-succ") (cl "swap-two-ods")))
          (list "two-extrinsic"
            (list (cl "swap-one-od") (cl "swap-two-ods")))
          (list "three-mixed"
            (list (cl "letter-rmost-succ") (cl "alphapos-clause")
                  (cl "swap-two-ods"))))))))

;;-------------------------------------- probe --------------------------------------

(define probe
  (lambda (i m t)
    (printf "PROBLEM\t~a\t~a\t~a~%" i m t)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (for* each string in (list *initial-string* *target-string*) do
      (build-runs string (build-bond-chain string)))
    (update-workspace-values)
    (for* each string in (list *initial-string* *target-string*) do
      (printf "STRING\t~a\twhole-group=~a\tletters=~a\tgroups=~a~%"
        (tell string 'get-string-type)
        (yn (tell string 'whole-group?))
        (length (tell string 'get-letters))
        (length (tell string 'get-groups))))
    (let ((table (clause-table)))
      ;; what each object description actually picks out, and how it is phrased
      (for* each entry in table do
        (let ((rc (2nd entry)))
          (if (not (verbatim-clause? rc))
            (for* each object-description in (2nd rc) do
              (for* each string in (list *initial-string* *target-string*) do
                (let* ((refs (tell string 'get-object-description-ref-objects
                               object-description))
                       (plural? (plural-object-phrase? object-description string)))
                  (printf "REF\t~a\t~a\t~a\t~a\t~a\t~a~%"
                    (1st entry)
                    (tell string 'get-string-type)
                    (format-object-description object-description)
                    (length refs)
                    (yn plural?)
                    (get-object-phrase object-description plural? string))))))))
      (for* each spec in (rule-specs table) do
        (for* each rule-type in '(top bottom) do
          (print-rule (format "~a/~a" (1st spec) rule-type)
            (make-rule rule-type (2nd spec)))))
      ;; equality: every rule against every other, plus a structurally identical
      ;; rebuild of each, which must compare equal
      (let* ((specs (rule-specs table))
             (names (map 1st specs))
             (rules (map (lambda (spec) (make-rule 'top (2nd spec))) specs))
             (rebuilt (map (lambda (spec) (make-rule 'top (2nd spec)))
                        (rule-specs (clause-table)))))
        (let loop ((ns names) (rs rules) (r2s rebuilt))
          (if (not (null? ns))
            (begin
              (printf "SELFEQ\t~a\t~a~%"
                (1st ns) (yn (rules-equal? (1st rs) (1st r2s))))
              (loop (rest ns) (rest rs) (rest r2s)))))
        (let loop ((a rules) (anames names))
          (if (not (null? a))
            (begin
              (let loop2 ((b rules) (bnames names))
                (if (not (null? b))
                  (begin
                    (if (rules-equal? (1st a) (1st b))
                      (printf "EQ\t~a\t~a~%" (1st anames) (1st bnames)))
                    (loop2 (rest b) (rest bnames)))))
              (loop (rest a) (rest anames)))))))))

(probe 'abc 'abd 'ijk)
(probe 'aabc 'aabd 'ijkk)
(probe 'eqe 'qqq 'mrrjjj)
(probe 'aabbcc 'aabbdd 'mrrjjj)
