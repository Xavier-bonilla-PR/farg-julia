;; Exhaustive dump of the image transform algebra from images.ss.
;;
;; Images are the representation a rule works in: applying a rule means applying
;; its transforms to an object's image and reading the result back out. The
;; algebra is pure and deterministic, so this probe drives every transform over
;; a fixed set of images and records what each one produces — including which
;; ones FAIL, since a transform's refusal is what makes a rule inapplicable.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))

;; render the nested letter structure (generate) as a flat readable string
(define render
  (lambda (g)
    (cond
      ((not (exists? g)) "-")
      ((list? g) (string-append "(" (apply string-append
                                      (map (lambda (x) (string-append (render x) " "))
                                        g)) ")"))
      (else (tell g 'get-lowercase-name)))))

(define show
  (lambda (im)
    (format "[~a ~a ~a ~a ~a n=~a ~a]"
      (nm (tell im 'get-letter))
      (nm (tell im 'get-bond-facet))
      (nm (tell im 'get-letter-relation))
      (nm (tell im 'get-length-relation))
      (nm (tell im 'get-direction))
      (length (tell im 'get-sub-images))
      (render (tell im 'generate)))))

;; build an image for a run of letters under a relation, in a direction
(define run-image
  (lambda (start relation n direction facet)
    (let ((letters (let loop ((k 0) (cur start) (acc '()))
                     (if (= k n)
                       (reverse acc)
                       (loop (add1 k)
                         (if (< (add1 k) n) (tell cur 'get-related-node relation) cur)
                         (cons cur acc))))))
      (make-image (1st letters) facet relation plato-identity direction
        (map make-letter-image letters)))))

;; a group of groups: ((a) (b b) (c c c)) style
(define nested-image
  (lambda (specs relation direction facet)
    (let ((subs (map (lambda (spec)
                       (run-image (1st spec) plato-identity (2nd spec)
                         plato-right plato-letter-category))
                  specs)))
      (make-image (tell (1st subs) 'get-letter) facet relation
        (relationship-between (tell-all subs 'get-length))
        direction subs))))

(define images
  (lambda ()
    (list
      (list "a" (make-letter-image plato-a))
      (list "z" (make-letter-image plato-z))
      (list "abc" (run-image plato-a plato-successor 3 plato-right plato-letter-category))
      (list "cba" (run-image plato-c plato-predecessor 3 plato-right plato-letter-category))
      (list "abc-left" (run-image plato-a plato-successor 3 plato-left plato-letter-category))
      (list "xyz" (run-image plato-x plato-successor 3 plato-right plato-letter-category))
      (list "aaa" (run-image plato-a plato-identity 3 plato-right plato-letter-category))
      (list "ab" (run-image plato-a plato-successor 2 plato-right plato-letter-category))
      (list "abcde" (run-image plato-a plato-successor 5 plato-right plato-letter-category))
      (list "a-bb-ccc"
        (nested-image (list (list plato-a 1) (list plato-b 2) (list plato-c 3))
          plato-successor plato-right plato-length))
      (list "aa-bb"
        (nested-image (list (list plato-a 2) (list plato-b 2))
          plato-successor plato-right plato-letter-category)))))

;; every transform, as (name . thunk-taking-image-and-fail)
(define transforms
  (list
    (list "letter" (lambda (im fail) (tell im 'letter fail)))
    (list "group" (lambda (im fail) (tell im 'group fail)))
    (list "rev-dir" (lambda (im fail) (tell im 'reverse-direction fail)))
    (list "rev-med-lett"
      (lambda (im fail) (tell im 'reverse-medium plato-letter-category fail)))
    (list "rev-med-len"
      (lambda (im fail) (tell im 'reverse-medium plato-length fail)))
    (list "start-succ"
      (lambda (im fail) (tell im 'new-start-letter plato-successor fail)))
    (list "start-pred"
      (lambda (im fail) (tell im 'new-start-letter plato-predecessor fail)))
    (list "start-iden"
      (lambda (im fail) (tell im 'new-start-letter plato-identity fail)))
    (list "start-m" (lambda (im fail) (tell im 'new-start-letter plato-m fail)))
    (list "start-a" (lambda (im fail) (tell im 'new-start-letter plato-a fail)))
    (list "start-none" (lambda (im fail) (tell im 'new-start-letter #f fail)))
    (list "len-succ" (lambda (im fail) (tell im 'new-length plato-successor fail)))
    (list "len-pred" (lambda (im fail) (tell im 'new-length plato-predecessor fail)))
    (list "len-one" (lambda (im fail) (tell im 'new-length plato-one fail)))
    (list "len-two" (lambda (im fail) (tell im 'new-length plato-two fail)))
    (list "len-four" (lambda (im fail) (tell im 'new-length plato-four fail)))
    (list "len-five" (lambda (im fail) (tell im 'new-length plato-five fail)))
    (list "alpha-first"
      (lambda (im fail) (tell im 'new-alpha-position-category plato-alphabetic-first fail)))
    (list "alpha-last"
      (lambda (im fail) (tell im 'new-alpha-position-category plato-alphabetic-last fail)))
    (list "alpha-opp"
      (lambda (im fail) (tell im 'new-alpha-position-category plato-opposite fail)))
    (list "singleton" (lambda (im fail) (tell im 'letter->singleton-group fail)))
    (list "shorten" (lambda (im fail) (tell im 'shorten fail)))
    (list "extend-succ-iden"
      (lambda (im fail) (tell im 'extend plato-successor plato-identity fail)))
    (list "extend-iden-succ"
      (lambda (im fail) (tell im 'extend plato-identity plato-successor fail)))))

;; single transforms
(for-each
  (lambda (entry)
    (let ((tname (1st entry)) (proc (2nd entry)))
      (for-each
        (lambda (ientry)
          (let* ((iname (1st ientry))
                 (im (tell (2nd ientry) 'copy))
                 (result
                   (call/cc
                     (lambda (k)
                       (proc im (lambda () (k "FAIL")))
                       (show im)))))
            (printf "T1\t~a\t~a\t~a~%" tname iname result)))
        (images))))
  transforms)

;; pairs of transforms, to catch order-dependent behaviour
(for-each
  (lambda (e1)
    (for-each
      (lambda (e2)
        (for-each
          (lambda (ientry)
            (let* ((iname (1st ientry))
                   (im (tell (2nd ientry) 'copy))
                   (result
                     (call/cc
                       (lambda (k)
                         ((2nd e1) im (lambda () (k "FAIL1")))
                         ((2nd e2) im (lambda () (k "FAIL2")))
                         (show im)))))
              (printf "T2\t~a\t~a\t~a\t~a~%" (1st e1) (1st e2) iname result)))
          (images)))
      transforms))
  (list (nth 0 transforms) (nth 1 transforms) (nth 11 transforms)
        (nth 12 transforms) (nth 20 transforms)))

;; state save / restore / reset
(for-each
  (lambda (ientry)
    (let* ((iname (1st ientry))
           (im (tell (2nd ientry) 'copy))
           (saved (tell im 'get-state)))
      (call/cc (lambda (k) (tell im 'new-length plato-four (lambda () (k 'x)))))
      (printf "ST\t~a\tafter\t~a~%" iname (show im))
      (tell im 'new-state saved)
      (printf "ST\t~a\trestored\t~a~%" iname (show im))
      (call/cc (lambda (k) (tell im 'new-start-letter plato-successor (lambda () (k 'x)))))
      (tell im 'reset)
      (printf "ST\t~a\treset\t~a~%" iname (show im))))
  (images))

;; walks and lengths
(for-each
  (lambda (ientry)
    (let* ((iname (1st ientry)) (im (2nd ientry)) (leaves '()) (interiors '()))
      (tell im 'leaf-walk
        (lambda (i) (set! leaves (cons (nm (tell i 'get-letter)) leaves))))
      (tell im 'postorder-interior-walk
        (lambda (i) (set! interiors (cons (length (tell i 'get-sub-images)) interiors))))
      (printf "W\t~a\t~a\t~a\t~a\t~a~%" iname
        (reverse leaves) (reverse interiors)
        (nm (tell im 'get-length))
        (if (tell im 'letter-image?) "leaf" "node"))))
  (images))

;; change-length-first? and enumerate, directly
(for-each
  (lambda (len-arg)
    (for-each
      (lambda (cur)
        (printf "CLF\t~a\t~a\t~a~%" (nm len-arg) (nm cur)
          (if (change-length-first? len-arg cur) "y" "n")))
      (list plato-one plato-two plato-three plato-five #f)))
  (list plato-predecessor plato-successor plato-identity
        plato-one plato-two plato-four))

(for-each
  (lambda (spec)
    (printf "EN\t~a\t~a\t~a\t~a~%" (nm (1st spec)) (nm (2nd spec)) (3rd spec)
      (call/cc
        (lambda (k)
          (map nm (enumerate-nodes (1st spec) (2nd spec) (3rd spec) (lambda () (k "FAIL"))))))))
  (list (list plato-a plato-successor 3)
        (list plato-x plato-successor 3)
        (list plato-x plato-successor 4)
        (list plato-a plato-predecessor 2)
        (list plato-c plato-predecessor 3)
        (list plato-a plato-identity 4)
        (list plato-a #f 1)
        (list plato-a #f 2)
        (list plato-one plato-successor 3)
        (list plato-four plato-successor 3)))
