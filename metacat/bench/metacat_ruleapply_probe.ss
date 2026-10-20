;; Applies rules to strings and reads the result back out of the images.
;;
;; Applying a rule changes nothing in the workspace: what it changes is what
;; the string LOOKS like under the rule, which is what has to be computed
;; before anyone can ask whether the rule works. The probe therefore dumps, for
;; each rule, the letters the string image generates, the transforms grouped by
;; object, and — when the rule cannot be applied — the snag that stopped it.
;;
;; The strings are grouped so that both bare letters and nested groups are
;; available as reference objects, since "all objects in the whole group" and
;; "all objects in the string" denote different things once a group exists.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
;; a letter image generates a bare node, not a list of them
(define listify (lambda (x) (if (list? x) (flatten x) (list x))))
(define yn (lambda (b) (if b "y" "n")))

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

;; a whole-string group over the top-level objects, so that rules naming
;; (<group> <StrPos> <whole>) have something to name
(define make-whole-group
  (lambda (string)
    (let* ((objs (tell string 'get-constituent-objects))
           (bonds (compress
                    (map (lambda (o) (tell o 'get-right-bond))
                      (all-but-last 1 objs)))))
      (if (and (> (length objs) 1) (= (length bonds) (sub1 (length objs))))
        (let* ((cat (tell (1st bonds) 'get-bond-category))
               (dir (tell (1st bonds) 'get-direction))
               (gcat (tell cat 'get-related-node plato-group-category))
               (g (make-group string gcat plato-letter-category dir
                    (1st objs) (nth (sub1 (length objs)) objs) objs bonds)))
          (build-group g #f)
          g)
        #f))))

;;------------------------------------ printing ------------------------------------

(define object-tag
  (lambda (o)
    (if (workspace-string? o)
      (format "string:~a" (tell o 'get-string-type))
      (tell o 'ascii-name))))

(define format-transform
  (lambda (t)
    (if (= (length t) 3)
      (format "(~a ~a ~a)" (format-slipnode (1st t)) (format-slipnode (2nd t))
        (format-slipnode (3rd t)))
      (format "(~a ~a)" (format-slipnode (1st t))
        (if (exists? (2nd t)) (format-slipnode (2nd t)) "#f")))))

(define snag '())

(define record-snag
  (lambda (failure-result)
    (set! snag
      (cons
        (case (1st failure-result)
          (SWAP (format "SWAP ~a ~a"
                  (map object-tag (2nd failure-result))
                  (format-slipnode (3rd failure-result))))
          (CONFLICT (format "CONFLICT ~a ~a ~a ~a"
                      (object-tag (2nd failure-result))
                      (format-slipnode (3rd failure-result))
                      (object-tag (4th failure-result))
                      (format-slipnode (5th failure-result))))
          (CHANGE (format "CHANGE ~a ~a"
                    (object-tag (2nd failure-result))
                    (format-transform (3rd failure-result)))))
        snag))
    'done))

(define apply-and-report
  (lambda (label rule string)
    (printf "APPLY\t~a\t~a~%" label (tell string 'get-string-type))
    (set! snag '())
    (let ((result (apply-rule rule string record-snag)))
      (cond
        ((not (exists? result)) (printf "  RESULT\tfailed~%"))
        ((null? result)
         (printf "  RESULT\t~a~%" (if (tell rule 'verbatim?) "verbatim" "empty")))
        (else
          (printf "  RESULT\tok\t~a~%" (length result))
          (for* each l in result do
            (printf "    OT\t~a\t~a~%"
              (object-tag (1st l))
              (map format-transform (2nd l))))))
      (for* each s in (reverse snag) do (printf "  SNAG\t~a~%" s))
      (printf "  IMAGE\t~a~%"
        (apply string-append
          (tell-all (tell string 'generate-image-letters) 'get-lowercase-name)))
      ;; the objects' own images, so that a swap is visible object by object
      (for* each o in (tell string 'get-constituent-objects) do
        (printf "  OBJIMG\t~a\t~a\tswapped=~a~%"
          (object-tag o)
          (apply string-append
            (tell-all (listify (tell (tell o 'get-image) 'generate))
              'get-lowercase-name))
          (yn (exists? (tell (tell o 'get-image) 'get-swapped-image)))))
      (tell string 'reset-string-image)
      (printf "  AFTERRESET\t~a~%"
        (apply string-append
          (tell-all (tell string 'generate-image-letters) 'get-lowercase-name))))))

;;------------------------------------- clauses -------------------------------------

(define od (lambda (ot dt d) (list ot dt d)))
(define ch list)

(define rule-specs
  (lambda ()
    (list
      (list "identity" '())
      (list "verbatim-xyz" (list (list 'verbatim (list plato-x plato-y plato-z))))
      (list "rmost-letter-succ"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor)))))
      (list "lmost-letter-pred"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-leftmost))
                (list (ch 'self plato-letter-category plato-predecessor)))))
      (list "rmost-letter-literal-d"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-d)))))
      (list "string-subobjs-succ"
        (list (list 'intrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-letter-category plato-successor)))))
      (list "string-subobjs-literal-a"
        (list (list 'intrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-letter-category plato-a)))))
      (list "string-subobjs-length-succ"
        (list (list 'intrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-length plato-successor)))))
      (list "string-subobjs-to-group-two"
        (list (list 'intrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-object-category plato-group)
                      (ch 'subobjects plato-length plato-two)))))
      (list "whole-group-length-succ"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-length plato-successor)))))
      (list "whole-group-length-pred"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-length plato-predecessor)))))
      (list "whole-group-direction-opp"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-direction-category plato-opposite)))))
      (list "whole-group-ctgy-opp"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-group-category plato-opposite)
                      (ch 'self plato-bond-facet plato-letter-category)))))
      (list "whole-group-to-letter"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-object-category plato-letter)))))
      (list "whole-group-alphapos-last"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-alphabetic-position-category
                          plato-alphabetic-last)))))
      (list "whole-group-alphapos-first"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-alphabetic-position-category
                          plato-alphabetic-first)))))
      ;; Length before LettCtgy, and the other way round: apply-before? decides
      (list "whole-group-length-and-letter"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-letter-category plato-successor)
                      (ch 'self plato-length plato-successor)))))
      (list "whole-group-shorten-and-letter"
        (list (list 'intrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list (ch 'self plato-letter-category plato-successor)
                      (ch 'self plato-length plato-predecessor)))))
      ;; deliberately impossible: z has no successor
      (list "all-letters-to-z-then-succ"
        (list (list 'intrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-letter-category plato-z)))
              (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor)))))
      ;; deliberately conflicting: two changes to the same dimension of one object
      (list "conflicting-rmost"
        (list (list 'intrinsic
                (list (od plato-letter plato-string-position-category plato-rightmost))
                (list (ch 'self plato-letter-category plato-successor)))
              (list 'intrinsic
                (list (od plato-letter plato-letter-category plato-c))
                (list (ch 'self plato-letter-category plato-predecessor)))))
      (list "swap-string-letters"
        (list (list 'extrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list plato-letter-category))))
      (list "swap-string-positions"
        (list (list 'extrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list plato-string-position-category))))
      (list "swap-lmost-rmost-letters"
        (list (list 'extrinsic
                (list (od plato-letter plato-string-position-category plato-leftmost)
                      (od plato-letter plato-string-position-category plato-rightmost))
                (list plato-letter-category))))
      (list "swap-lmost-rmost-positions"
        (list (list 'extrinsic
                (list (od plato-letter plato-string-position-category plato-leftmost)
                      (od plato-letter plato-string-position-category plato-rightmost))
                (list plato-string-position-category))))
      (list "swap-whole-group-lengths"
        (list (list 'extrinsic
                (list (od plato-group plato-string-position-category plato-whole))
                (list plato-length))))
      (list "swap-and-change"
        (list (list 'extrinsic
                (list (od plato-letter plato-string-position-category plato-leftmost)
                      (od plato-letter plato-string-position-category plato-rightmost))
                (list plato-letter-category))
              (list 'intrinsic
                (list (od 'string plato-string-position-category plato-whole))
                (list (ch 'subobjects plato-length plato-successor))))))))

;;-------------------------------------- probe --------------------------------------

(define probe
  (lambda (i m t group?)
    (printf "PROBLEM\t~a\t~a\t~a\tgroups=~a~%" i m t (yn group?))
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (init-workspace i m t #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (if* group?
      (for* each string in (list *initial-string* *target-string*) do
        (build-runs string (build-bond-chain string))
        (make-whole-group string)))
    (update-workspace-values)
    (for* each string in (list *initial-string* *target-string*) do
      (printf "STRING\t~a\twhole-group=~a\tobjects=~a\t~a~%"
        (tell string 'get-string-type)
        (yn (tell string 'whole-group?))
        (length (tell string 'get-constituent-objects))
        (map object-tag (tell string 'get-constituent-objects))))
    (for* each spec in (rule-specs) do
      (for* each pair in (list (list 'top *initial-string*)
                               (list 'bottom *target-string*)) do
        (apply-and-report (1st spec) (make-rule (1st pair) (2nd spec)) (2nd pair))))))

(probe 'abc 'abd 'ijk #f)
(probe 'abc 'abd 'ijk #t)
(probe 'aabc 'aabd 'ijkk #t)
(probe 'xyz 'xyd 'rssttt #t)
(probe 'aabbcc 'aabbdd 'mrrjjj #t)
