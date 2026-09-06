;; Rule unification: asking whether two rules are the same idea.
;;
;; The rule pairs below are written out by hand from the grammar at the top of
;; rules.ss, the same way the `rules` probe writes its clause table, because
;; unification is pure structure — it never looks at the workspace — and hand
;; written pairs are the only way to reach every arm of the traversal
;; deliberately: identical nodes, slip-linked nodes, unrelated nodes, shape
;; mismatches at each level, the 'string/plato-group special case, the
;; whole/single removal, and verbatim rules, which unify with nothing.
;;
;; The pattern half is stochastic — get-vertical-theme-pattern-to-clamp draws
;; one random per entry, EXCEPT for a string-position entry, whose retention
;; probability is exactly 1 and so short-circuits prob? without drawing — so
;; each pattern is clamped repeatedly from a seeded generator.
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

(define cm-tag (lambda (cm) (tell cm 'print-name)))

(define entry-tag
  (lambda (e) (format "~a/~a" (sn (1st e)) (nm (2nd e)))))

(define od (lambda (ot dt d) (list ot dt d)))
(define ch list)

;; --- the rule pairs ---------------------------------------------------------

(define pair-table
  (lambda ()
    (list
      ;; identical: unifies, and every pair of nodes is eq?, so no slippages
      (list "identical"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor))))
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor)))))
      ;; succ => pred: the classic slippage, on a lateral sliplink
      (list "succ-pred"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor))))
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-predecessor)))))
      ;; rmost => lmost as well, so two slippages come back
      (list "rmost-lmost-succ-pred"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor))))
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-leftmost))
                (list (ch 'self plato-letter-category plato-predecessor)))))
      ;; leftmost => rightmost only
      (list "lmost-rmost"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-leftmost))
                (list (ch 'self plato-letter-category plato-successor))))
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor)))))
      ;; the 'string / plato-group special case, both ways round
      (list "string-vs-group"
        (list (list 'intrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-letter-category plato-successor))))
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-letter-category plato-successor)))))
      (list "group-vs-string"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-letter-category plato-successor))))
        (list (list 'intrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-letter-category plato-successor)))))
      ;; 'string against something that is NOT plato-group: fails
      (list "string-vs-letter"
        (list (list 'intrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-letter-category plato-successor))))
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-letter-category plato-successor)))))
      ;; whole => single, the mapping that gets dropped
      (list "whole-single"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-direction-category plato-opposite))))
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-single))
                (list (ch 'self plato-direction-category plato-opposite)))))
      ;; two whole/single mappings: only the FIRST is removed. NB a
      ;; group-category change has to be paired with a bond-facet change —
      ;; make-rule's transcription rejects a bare one.
      (list "whole-single-twice"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-direction-category plato-opposite)))
              (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-group-category plato-opposite)
                      (ch 'self plato-bond-facet plato-letter-category))))
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-single))
                (list (ch 'self plato-direction-category plato-opposite)))
              (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-single))
                (list (ch 'self plato-group-category plato-opposite)
                      (ch 'self plato-bond-facet plato-letter-category)))))
      ;; bond-category and group-category entries, for the two heuristics
      (list "bondctgy"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-rightmost))
                (list (ch 'self plato-bond-category plato-successor))))
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-leftmost))
                (list (ch 'self plato-bond-category plato-predecessor)))))
      ;; shape mismatch: two changes against one
      (list "shape-changes"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor)
                      (ch 'self plato-length plato-successor))))
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor)))))
      ;; shape mismatch: two clauses against one
      (list "shape-clauses"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor)))
              (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-leftmost))
                (list (ch 'self plato-letter-category plato-successor))))
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor)))))
      ;; scope symbols differ: 'self against 'subobjects
      (list "scope-mismatch"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor))))
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'subobjects plato-letter-category plato-successor)))))
      ;; unrelated literal descriptors: no sliplink between a and m
      (list "unrelated-letters"
        (list (list 'intrinsic
                (list (od plato-letter plato-letter-category plato-a))
                (list (ch 'self plato-letter-category plato-d))))
        (list (list 'intrinsic
                (list (od plato-letter plato-letter-category plato-m))
                (list (ch 'self plato-letter-category plato-d)))))
      ;; extrinsic (swap) clauses
      (list "extrinsic"
        (list (list 'extrinsic
                (list (od plato-letter plato-string-position-category plato-leftmost)
                      (od plato-letter plato-string-position-category plato-rightmost))
                (list plato-letter-category)))
        (list (list 'extrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost)
                      (od plato-letter plato-string-position-category plato-leftmost))
                (list plato-letter-category))))
      ;; kind mismatch: intrinsic against extrinsic
      (list "kind-mismatch"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor))))
        (list (list 'extrinsic
                (list (od plato-letter plato-string-position-category plato-leftmost)
                      (od plato-letter plato-string-position-category plato-rightmost))
                (list plato-letter-category))))
      ;; verbatim rules unify with nothing at all
      (list "verbatim-both"
        (list (list 'verbatim (list plato-a plato-b plato-d)))
        (list (list 'verbatim (list plato-a plato-b plato-d))))
      (list "verbatim-one"
        (list (list 'verbatim (list plato-a plato-b plato-d)))
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor))))))))

(define dump-pair
  (lambda (tag rule1 rule2)
    (printf "PAIR\t~a\tverb1=~a\tverb2=~a~%" tag
      (yn (tell rule1 'verbatim?)) (yn (tell rule2 'verbatim?)))
    ;; compare-rule-clause-lists: the traversal under the comparison proc
    (let ((cmp (compare-rule-clause-lists
                 (tell rule1 'get-rule-clauses)
                 (tell rule2 'get-rule-clauses))))
      (printf "CMP\t~a\t~a~%" tag
        (if (not cmp)
          "FAIL"
          (join (map (lambda (p) (format "~a>~a" (sn (1st p)) (sn (2nd p)))) cmp)))))
    ;; unify-rules
    (let ((pattern (unify-rules rule1 rule2)))
      (if (not pattern)
        (printf "UNIFY\t~a\tFAIL~%" tag)
        (begin
          (printf "UNIFY\t~a\t~a\t~a~%" tag (1st pattern) (length (rest pattern)))
          (let loop ((k 0) (es (rest pattern)))
            (when (not (null? es))
              (printf "UNIFYE\t~a\t~a\t~a~%" tag k (entry-tag (1st es)))
              (loop (add1 k) (rest es))))
          ;; get-unifying-slippages is only defined when the rules unify
          (let ((slippages (get-unifying-slippages rule1 rule2)))
            (printf "SLIP\t~a\t~a~%" tag (join (map cm-tag slippages)))
            (let loop ((k 0) (ss slippages))
              (when (not (null? ss))
                (printf "SLIPD\t~a\t~a\t~a\t~a\t~a~%" tag k
                  (sn (tell (1st ss) 'get-CM-type))
                  (cm-tag (1st ss))
                  (nm (tell (1st ss) 'get-label)))
                (loop (add1 k) (rest ss))))))))))

;; --- the pattern helpers ----------------------------------------------------

(define pattern-table
  (lambda ()
    (list
      (list "spos-iden"
        (list (list plato-string-position-category plato-identity)))
      (list "spos-opp"
        (list (list plato-string-position-category plato-opposite)))
      (list "spos-diff"
        (list (list plato-string-position-category #f)))
      (list "spos-opp-dir-iden"
        (list (list plato-string-position-category plato-opposite)
              (list plato-direction-category plato-identity)))
      (list "bondctgy-only"
        (list (list plato-bond-category plato-opposite)))
      (list "bondctgy-and-groupctgy"
        (list (list plato-bond-category plato-opposite)
              (list plato-group-category plato-identity)))
      (list "lcat-succ"
        (list (list plato-letter-category plato-successor)))
      (list "mixed"
        (list (list plato-letter-category plato-successor)
              (list plato-string-position-category plato-opposite)
              (list plato-bond-category plato-opposite)
              (list plato-object-category plato-identity)
              (list plato-length plato-successor))))))

(define dump-pattern-helpers
  (lambda (tag entries)
    (for* each e in entries do
      (printf "RETP\t~a\t~a\t~a~%" tag (entry-tag e)
        (number->string ((retention-probability entries) e))))
    (printf "REPBOND\t~a\t~a~%" tag
      (join (map entry-tag (replace-bond-category-entry entries))))
    (printf "ADDDIR\t~a\t~a~%" tag
      (join (map entry-tag (add-direction-entry entries))))
    (printf "BOTH\t~a\t~a~%" tag
      (join (map entry-tag
              (add-direction-entry (replace-bond-category-entry entries)))))))

(define dump-clamp
  (lambda (tag entries seed trials)
    (random-seed seed)
    (let loop ((k 1))
      (when (<= k trials)
        (let ((result (get-vertical-theme-pattern-to-clamp
                        (cons 'vertical-bridge entries))))
          (printf "CLAMP\t~a\t~a\t~a\t~a\t~a~%" tag seed k (1st result)
            (join (map entry-tag (rest result)))))
        (loop (add1 k))))))

;; --- probe ------------------------------------------------------------------

(define probe
  (lambda (i m t)
    (printf "PROBLEM\t~a\t~a\t~a~%" i m t)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (tell *themespace* 'initialize)
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (update-workspace-values)
    (for* each spec in (pair-table) do
      (let ((tag (1st spec))
            (rule1 (make-rule 'top (2nd spec)))
            (rule2 (make-rule 'top (3rd spec))))
        (dump-pair tag rule1 rule2)))
    (for* each spec in (pattern-table) do
      (dump-pattern-helpers (1st spec) (2nd spec)))
    (for* each spec in (pattern-table) do
      (for* each seed in '(11 22 33) do
        (dump-clamp (1st spec) (2nd spec) seed 6)))))

(probe 'abc 'abd 'ijk)
