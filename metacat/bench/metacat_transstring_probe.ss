;; The TRANSLATED STRING: what the answer looks like once the translated rule
;; is applied to the target string.
;;
;; The workspace is built as in the ruletranslate probe — run the coderack,
;; then drive the rule codelets until a top rule exists — and the rule is then
;; translated. What is new here is what happens next: applying the translated
;; rule to the target string, instantiating the resulting image back into real
;; letters and groups, attaching the length descriptions, building the
;; translated-rule bridges and deleting the groups nothing maps to.
;;
;; The whole constructed string is dumped object by object, since it is built
;; rather than perceived and a single misplaced letter would otherwise hide.
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

(define object-tag
  (lambda (o)
    (if (workspace-string? o)
      (format "string:~a" (tell o 'get-string-type))
      (tell o 'ascii-name))))

(define od-tag
  (lambda (od)
    (format "(~a ~a ~a)"
      (if (symbol? (1st od)) (1st od) (sn (1st od)))
      (sn (2nd od)) (sn (3rd od)))))

(define cm-tag (lambda (cm) (tell cm 'print-name)))

(define seed-rack
  (lambda ()
    (let loop ((k 0))
      (when (< k 3)
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%))
        (tell *coderack* 'post
          (tell group-scout:whole-string 'make-codelet %low-urgency%))
        (tell *coderack* 'post
          (tell top-down-group-scout:category 'make-codelet %low-urgency%
            plato-succgrp *workspace*))
        (tell *coderack* 'post
          (tell top-down-group-scout:category 'make-codelet %low-urgency%
            plato-samegrp *workspace*))
        (tell *coderack* 'post
          (tell bottom-up-bridge-scout 'make-codelet %medium-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-bridge-scout 'make-codelet %medium-urgency%))
        (tell *coderack* 'post
          (tell important-object-bridge-scout 'make-codelet %medium-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-description-scout 'make-codelet %very-low-urgency%))
        (loop (+ k 1))))))

(define print-clause
  (lambda (tag rc)
    (record-case rc
      (verbatim (lcs) (printf "~a\tVERBATIM\t~a~%" tag (join (map nm lcs))))
      (intrinsic (ods changes)
        (printf "~a\tCHANGE\t~a\t~a~%" tag (od-tag (1st ods))
          (join (map (lambda (c)
                       (format "(~a ~a ~a)" (1st c) (sn (2nd c)) (sn (3rd c))))
                  changes))))
      (extrinsic (ods dims)
        (printf "~a\tSWAP\t~a\t~a~%" tag
          (join (map od-tag ods)) (join (map sn dims)))))))

(define print-rule
  (lambda (tag rule)
    (printf "~a\tTYPE\t~a\ttranslated=~a\tdir=~a~%" tag
      (tell rule 'get-rule-type) (yn (tell rule 'translated?))
      (tell rule 'get-translation-direction))
    (for* each rc in (tell rule 'get-rule-clauses) do (print-clause tag rc))
    (for* each line in (tell rule 'get-english-transcription) do
      (printf "~a\tEN\t|~a|~%" tag line))))

(define print-log
  (lambda (tag log)
    (printf "~a\tDIRECT\t~a~%" tag
      (join (map cm-tag (tell log 'get-directly-applied-slippages))))
    (printf "~a\tCOAT\t~a~%" tag
      (join (map cm-tag (tell log 'get-coattail-slippages))))
    (printf "~a\tCOATIND\t~a~%" tag
      (join (map cm-tag (tell log 'get-coattail-inducing-slippages))))
    (printf "~a\tAPPLIED\t~a~%" tag
      (join (map cm-tag (tell log 'get-applied-slippages))))
    (printf "~a\tLOGBR\t~a~%" tag
      (join (map (lambda (b)
                   (format "~a>~a" (object-tag (tell b 'get-object1))
                     (object-tag (tell b 'get-object2))))
              (tell log 'get-slippage-bridges))))
    ;; the highlight lookup is pure bookkeeping over the same lists
    (for* each s in (tell log 'get-directly-applied-slippages) do
      (printf "~a\tHIGH\t~a\t~a~%" tag (cm-tag s)
        (let ((h (tell log 'get-slippage-to-highlight s)))
          (if (exists? h) (cm-tag h) "-"))))))

(define seen '())
(define new-codelets-of-type
  (lambda (type-name)
    (let ((found
            (filter
              (lambda (c)
                (and (eq? (tell c 'get-codelet-type-name) type-name)
                     (not (memq c seen))))
              (tell *coderack* 'get-all-codelets))))
      (set! seen (append found seen))
      found)))

;; Drive scout -> evaluator -> builder by hand until a top rule is built.
(define build-a-top-rule
  (lambda (rounds)
    (let loop ((k 1))
      (when (and (<= k rounds) (null? (tell *workspace* 'get-rules 'top)))
        (tell (tell rule-scout 'make-codelet %medium-urgency%) 'run)
        (for* each ec in (new-codelets-of-type 'rule-evaluator) do (tell ec 'run))
        (for* each bc in (new-codelets-of-type 'rule-builder) do (tell bc 'run))
        (loop (+ k 1))))
    (let ((rules (tell *workspace* 'get-rules 'top)))
      (if (null? rules) #f (1st rules)))))


;; Dump a constructed string exhaustively: every letter, every group, the
;; nesting, and the descriptions each object ended up with.
(define dump-string
  (lambda (tag s)
    (printf "~a\tSTR\t~a\t~a\tlen=~a\ttranslated=~a~%" tag
      (tell s 'get-string-type) (tell s 'print-name)
      (tell s 'get-length) (yn (tell s 'translated?)))
    (for* each l in (tell s 'get-letters) do
      (printf "~a\tLET\t~a\tpos=~a\tid=~a\tencl=~a~%" tag
        (tell l 'ascii-name) (tell l 'get-string-pos) (tell l 'get-id-num)
        (let ((g (tell l 'get-enclosing-group)))
          (if (exists? g) (tell g 'ascii-name) "-")))
      (for* each d in (tell l 'get-descriptions) do
        (printf "~a\tLD\t~a\t~a\t~a\tlevel=~a~%" tag (tell l 'ascii-name)
          (sn (tell d 'get-description-type)) (sn (tell d 'get-descriptor))
          (tell d 'get-proposal-level))))
    (printf "~a\tNGROUPS\t~a~%" tag (length (tell s 'get-groups)))
    (for* each g in (reverse (tell s 'get-groups)) do
      (printf "~a\tGRP\t~a\tcat=~a\tfacet=~a\tdir=~a\tlen=~a\tspan=~a-~a\tid=~a\tencl=~a~%"
        tag (tell g 'ascii-name) (sn (tell g 'get-group-category))
        (sn (tell g 'get-bond-facet)) (nm (tell g 'get-direction))
        (tell g 'get-group-length)
        (tell g 'get-left-string-pos) (tell g 'get-right-string-pos)
        (tell g 'get-id-num)
        (let ((e (tell g 'get-enclosing-group)))
          (if (exists? e) (tell e 'ascii-name) "-")))
      (printf "~a\tGOBJ\t~a\t~a~%" tag (tell g 'ascii-name)
        (join (map (lambda (o) (tell o 'ascii-name))
                (tell g 'get-constituent-objects))))
      (for* each d in (tell g 'get-descriptions) do
        (printf "~a\tGD\t~a\t~a\t~a\tlevel=~a~%" tag (tell g 'ascii-name)
          (sn (tell d 'get-description-type)) (sn (tell d 'get-descriptor))
          (tell d 'get-proposal-level))))))

(define probe
  (lambda (i m t seed n temp rounds attempts)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp)
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
                             plato-predecessor plato-sameness plato-bond-facet
                             plato-bond-category plato-group-category
                             plato-direction-category plato-left plato-right
                             plato-samegrp plato-succgrp plato-predgrp
                             plato-alphabetic-position-category plato-length) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    (set! seen '())
    (seed-rack)
    (let loop ((c 0))
      (when (and (< c n) (not (tell *coderack* 'empty?)))
        (if* (and (> c 0) (zero? (modulo c %update-cycle-length%)))
          (seed-rack))
        (set! *codelet-count* c)
        (tell (tell *coderack* 'choose-codelet) 'run)
        (update-workspace-values)
        (loop (+ c 1))))
    (tell *workspace* 'check-if-rules-possible)
    (let ((rule (build-a-top-rule rounds)))
      (if (not rule)
        (printf "NORULE~%")
        (begin
          (print-rule "RULE" rule)
          ;; NB: make-translated-string assumes the rule APPLIES -- it calls
          ;; apply-rule and immediately takes (1st ...) of each result, so a
          ;; failed application is a car of #f. answer-finder guards it the
          ;; same way, applying the rule first and fizzling if it fails.
          (if (not (exists? (apply-rule rule *initial-string* ignore-snag)))
            (printf "TOP\tNOAPPLY~%")
          ;; the top rule applied to the INITIAL string rebuilds the modified
          ;; string, which is the construction with a known right answer
          (let ((top-string (make-translated-string rule *initial-string*)))
            (dump-string "TOP" top-string)
            (printf "TOP\tSUPBR\t~a~%"
              (join (map (lambda (b)
                           (format "~a>~a\ttrb=~a"
                             (object-tag (tell b 'get-object1))
                             (object-tag (tell b 'get-object2))
                             (yn (tell b 'translated-rule-bridge?))))
                      (tell rule 'get-supporting-horizontal-bridges))))
            (printf "TOP\tTHEME\t~a~%"
              (let ((p (tell rule 'get-theme-pattern)))
                (format "~a:~a" (1st p)
                  (join (map (lambda (e) (format "~a/~a" (sn (1st e)) (nm (2nd e))))
                          (rest p))))))))
          ;; then the translated rule applied to the TARGET string, which is
          ;; the answer itself
          (let loop ((a 1))
            (when (<= a attempts)
              (let ((result (translate rule)))
                (if (not result)
                  (printf "T~a\tFAILED~%" a)
                  (let* ((tag (format "T~a" a))
                         (bottom-rule (1st result)))
                    (print-rule tag bottom-rule)
                    (if (not (exists?
                               (apply-rule bottom-rule *target-string* ignore-snag)))
                      (printf "~a\tNOAPPLY~%" tag)
                    (let ((answer-string
                            (make-translated-string bottom-rule *target-string*)))
                      (dump-string tag answer-string)
                      (printf "~a\tSUPBR\t~a~%" tag
                        (join (map (lambda (b)
                                     (format "~a>~a\ttrb=~a"
                                       (object-tag (tell b 'get-object1))
                                       (object-tag (tell b 'get-object2))
                                       (yn (tell b 'translated-rule-bridge?))))
                                (tell bottom-rule 'get-supporting-horizontal-bridges))))
                      (printf "~a\tSUPGRP\t~a~%" tag
                        (join (map (lambda (o) (tell o 'ascii-name))
                                (get-rule-supporting-groups rule bottom-rule)))))))))
              (loop (+ a 1)))))))))

(probe 'abc 'abd 'cba 501 2000 30 40 4)
(probe 'abc 'abd 'kji 401 2000 30 40 4)
(probe 'abc 'abd 'kji 402 4000 30 40 4)
(probe 'abc 'abd 'mrrjjj 404 3000 30 40 4)
(probe 'abc 'cba 'pqrs 405 3000 30 40 4)
(probe 'aabc 'aabd 'ijkk 406 3000 30 40 4)
(probe 'mrrjjj 'mrrkkk 'xyz 409 3000 30 40 4)
(probe 'abc 'abd 'xyz 410 3000 30 40 4)
(probe 'abcd 'abdc 'xyz 408 3000 25 40 4)
(probe 'abc 'abd 'ijk 412 2000 40 40 4)
