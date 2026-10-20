;; Runs the thematic codelet pipeline through the real coderack.
;;
;; thematic-bridge-scout only does anything when thematic pressure is on and
;; positive themes exist, so the probe clamps a theme pattern first and then
;; lets the scouts work against it. The ordinary bond, group and bridge scouts
;; run alongside, because a thematic bridge has to fight for its place like any
;; other, and because propose-description-based-on-theme feeds the description
;; codelets.
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

(define seed-rack
  (lambda ()
    (let loop ((k 0))
      (when (< k 3)
        (tell *coderack* 'post
          (tell thematic-bridge-scout 'make-codelet %very-high-urgency%))
        (tell *coderack* 'post
          (tell thematic-bridge-scout 'make-codelet %very-high-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%))
        (tell *coderack* 'post
          (tell group-scout:whole-string 'make-codelet %low-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-bridge-scout 'make-codelet %medium-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-description-scout 'make-codelet %very-low-urgency%))
        (loop (+ k 1))))))

;; dimension and relation indices match metacat_themes_probe.ss
(define dims (tell *themespace* 'get-dimensions))
(define dim-at (lambda (i) (nth i dims)))
(define rel-at
  (lambda (type i j) (nth j (tell *themespace* 'get-relations type (dim-at i)))))

(define probe
  (lambda (i m t seed n temp theme-spec)
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
    ;; clamp the theme pattern the scouts will work toward
    (tell *themespace* 'thematic-pressure-on)
    (for* each entry in theme-spec do
      (tell *themespace* 'set-theme-activation
        (1st entry) (dim-at (2nd entry)) (rel-at (1st entry) (2nd entry) (3rd entry))
        (4th entry)))
    (tell *themespace* 'update-dominant-themes)
    (printf "THEMES\t~a~%"
      (map (lambda (th) (list (tell th 'ascii-name) (tell th 'get-activation)))
        (tell *themespace* 'get-all-active-themes)))
    (random-seed seed)
    (seed-rack)
    (let loop ((c 0))
      (when (and (< c n) (not (tell *coderack* 'empty?)))
        (if* (and (> c 0) (zero? (modulo c %update-cycle-length%)))
          (seed-rack))
        (set! *codelet-count* c)
        (let ((codelet (tell *coderack* 'choose-codelet)))
          (printf "RUN\t~a\t~a\t~a\t~a" c
            (tell codelet 'get-codelet-type-name)
            (round (tell codelet 'get-relative-urgency))
            (tell *coderack* 'get-num-of-codelets))
          (tell codelet 'run)
          (printf "\t~a\t~a\t~a\t~a\t~a~%"
            (length (tell *workspace* 'get-bonds))
            (length (tell *workspace* 'get-groups))
            (length (tell *workspace* 'get-all-bridges))
            (length (tell *themespace* 'get-all-themes))
            (sum (map (lambda (o) (tell o 'get-average-salience))
                   (tell *workspace* 'get-objects)))))
        (update-workspace-values)
        (loop (+ c 1))))
    (for-each
      (lambda (bridge-type)
        (for-each
          (lambda (b)
            (printf "BRIDGE\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" bridge-type
              (tell (tell b 'get-object1) 'ascii-name)
              (tell (tell b 'get-object2) 'ascii-name)
              (yn (tell b 'flipped-group1?)) (yn (tell b 'flipped-group2?))
              (tell b 'get-strength)
              (map (lambda (cm) (tell cm 'print-name))
                (tell b 'get-all-concept-mappings))))
          (reverse (tell *workspace* 'get-bridges bridge-type))))
      '(top vertical))
    (for-each
      (lambda (string)
        (for-each
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name) (num (tell o 'get-raw-importance))
              (tell o 'get-average-salience)
              (map (lambda (d) (tell d 'print-name)) (tell o 'get-all-descriptions))))
          (tell string 'get-objects))
        (for-each
          (lambda (g)
            (printf "GROUP\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell g 'ascii-name) (nm (tell g 'get-group-category))
              (nm (tell g 'get-direction)) (tell g 'get-strength)))
          (reverse (tell string 'get-groups))))
      (list *initial-string* *modified-string* *target-string*))
    (for-each
      (lambda (th)
        (printf "THEME\t~a\t~a\t~a\t~a~%" (tell th 'get-theme-type)
          (tell th 'ascii-name) (tell th 'get-activation) (yn (tell th 'dominant?))))
      (tell *themespace* 'get-all-themes))
    (printf "WS\t~a\t~a\t~a~%"
      (tell *workspace* 'get-mapping-strength 'top)
      (tell *workspace* 'get-mapping-strength 'vertical)
      (num (tell *themespace* 'get-percentage-of-dominant-themes)))))

;; A variant that builds bonds and whole-string groups FIRST. Two of the
;; thematic scout's branches need group objects to exist: a Length theme has no
;; possible descriptor for a letter, so propose-description-based-on-theme only
;; posts anything when the chosen object is a group; and look-for-auxiliary-
;; slippages needs the proposed bridge to carry slippages, which identity
;; mappings between letters never do.
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

(define grouped-probe
  (lambda (i m t seed n temp theme-spec)
    (printf "GPROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp)
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
    (for-each build-chain-and-group
      (list *initial-string* *modified-string* *target-string*))
    (update-workspace-values)
    (tell *themespace* 'thematic-pressure-on)
    (for* each entry in theme-spec do
      (tell *themespace* 'set-theme-activation
        (1st entry) (dim-at (2nd entry)) (rel-at (1st entry) (2nd entry) (3rd entry))
        (4th entry)))
    (tell *themespace* 'update-dominant-themes)
    (let loop ((c 0))
      (when (< c n)
        (if* (zero? (modulo c 6))
          (let loop2 ((k 0))
            (when (< k 2)
              (tell *coderack* 'post
                (tell thematic-bridge-scout 'make-codelet %very-high-urgency%))
              (loop2 (+ k 1)))))
        (set! *codelet-count* c)
        (if* (not (tell *coderack* 'empty?))
          (let ((codelet (tell *coderack* 'choose-codelet)))
            (printf "GRUN\t~a\t~a\t~a\t~a" c
              (tell codelet 'get-codelet-type-name)
              (round (tell codelet 'get-relative-urgency))
              (tell *coderack* 'get-num-of-codelets))
            (tell codelet 'run)
            (printf "\t~a\t~a\t~a\t~a~%"
              (length (tell *workspace* 'get-groups))
              (length (tell *workspace* 'get-all-bridges))
              (length (tell *themespace* 'get-all-themes))
              (sum (map (lambda (o) (tell o 'get-average-salience))
                     (tell *workspace* 'get-objects))))))
        (update-workspace-values)
        (loop (+ c 1))))
    (for-each
      (lambda (bridge-type)
        (for-each
          (lambda (b)
            (printf "GBRIDGE\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%" bridge-type
              (tell (tell b 'get-object1) 'ascii-name)
              (tell (tell b 'get-object2) 'ascii-name)
              (yn (tell b 'flipped-group1?)) (yn (tell b 'flipped-group2?))
              (tell b 'get-strength)
              (map (lambda (cm) (tell cm 'print-name))
                (tell b 'get-all-concept-mappings))))
          (reverse (tell *workspace* 'get-bridges bridge-type))))
      '(top vertical))
    (for-each
      (lambda (string)
        (for-each
          (lambda (o)
            (printf "GOBJ\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name) (tell o 'get-average-salience)
              (map (lambda (d) (tell d 'print-name)) (tell o 'get-all-descriptions))))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))))

;; LetterCtgy:identity + StringPos:identity on both bridge types
(probe 'abc 'abd 'ijk 5001 400 50
  '((top-bridge 0 3 100) (vertical-bridge 0 3 100)
    (top-bridge 1 2 100) (vertical-bridge 1 2 100)))
;; StringPos:opposite pressure, the case that wants flipped/crossing bridges
(probe 'abc 'abd 'cba 5002 600 30
  '((vertical-bridge 1 1 100) (vertical-bridge 3 0 100)
    (top-bridge 0 3 100) (top-bridge 1 2 100)))
;; ObjectCtgy:different, which forces letter<->group correspondences and so
;; exercises propose-description-based-on-theme
(probe 'abc 'abd 'mrrjjj 5003 600 40
  '((vertical-bridge 7 0 100) (vertical-bridge 0 3 90)
    (top-bridge 0 3 100) (top-bridge 6 3 80)))
;; Length pressure on a string where lengths genuinely differ
(probe 'abc 'abd 'iijjkk 5004 600 20
  '((vertical-bridge 6 3 100) (vertical-bridge 1 2 90)
    (top-bridge 0 3 100)))

;; StringPos:opposite between abc and cba gives lmost=>rmost slippages, which is
;; what look-for-auxiliary-slippages needs something to work from
(grouped-probe 'abc 'abd 'cba 5101 300 30
  '((vertical-bridge 1 1 100) (vertical-bridge 6 3 100)
    (top-bridge 0 3 100) (top-bridge 1 2 100)))
;; Length pressure with groups already present, so a Length description is
;; possible for the chosen object and propose-description-based-on-theme posts
(grouped-probe 'abc 'abd 'iijjkk 5102 300 20
  '((vertical-bridge 6 2 100) (vertical-bridge 7 0 100)
    (top-bridge 0 3 100)))
;; abc <-> xyz is the case look-for-auxiliary-slippages exists for: a StringPos
;; lmost=>rmost slippage drags an AlphaPos first=>last slippage along with it,
;; because leftmost is linked to alphabetic-first and a is alphabetic-first
;; while z is alphabetic-last. No other pair of letters reaches that branch.
(grouped-probe 'abc 'abd 'xyz 5104 300 30
  '((vertical-bridge 1 1 100) (vertical-bridge 3 0 100)
    (top-bridge 0 3 100)))
(grouped-probe 'abc 'abd 'zyx 5105 300 20
  '((vertical-bridge 1 1 100) (vertical-bridge 2 0 100)
    (top-bridge 0 3 100)))

(grouped-probe 'abcd 'abce 'dcba 5103 300 40
  '((vertical-bridge 1 1 100) (vertical-bridge 3 0 100)
    (vertical-bridge 6 3 90) (top-bridge 0 3 100)))
