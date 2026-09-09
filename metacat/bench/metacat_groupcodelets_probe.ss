;; Runs the group codelet pipeline through the real coderack for N codelets,
;; dumping every codelet run and the groups that survive.
;;
;; Bond scouts are seeded alongside the group scouts, because group scouts need
;; bonds to scan and the interleaving is where the interesting fights happen:
;; a group that wants a bond flipped has to beat the bond that is already there.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")
(load "metacat/scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define num
  (lambda (v)
    (if (integer? v)
      (number->string v)
      (format "~a/~a" (numerator v) (denominator v)))))

(define seed-rack
  (lambda ()
    (let loop ((k 0))
      (when (< k 4)
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%))
        (tell *coderack* 'post
          (tell group-scout:whole-string 'make-codelet %low-urgency%))
        (tell *coderack* 'post
          (tell top-down-group-scout:category 'make-codelet %medium-urgency%
            plato-succgrp *workspace*))
        (tell *coderack* 'post
          (tell top-down-group-scout:category 'make-codelet %medium-urgency%
            plato-samegrp *target-string*))
        (tell *coderack* 'post
          (tell top-down-group-scout:direction 'make-codelet %low-urgency%
            plato-right *workspace*))
        (loop (+ k 1))))))

(define probe
  (lambda (i m t seed n temp)
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
                             plato-length) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    ;; A real run replenishes the rack from add-bottom-up-codelets every update
    ;; cycle. Without that the rack drains after the seed batch and the builders
    ;; barely run, so the probe reseeds on the same cadence.
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
          ;; a workspace fingerprint after every codelet, so a divergence
          ;; localises to the codelet that caused it rather than to the first
          ;; codelet whose NAME happens to differ
          (printf "\t~a\t~a\t~a\t~a~%"
            (length (tell *workspace* 'get-bonds))
            (length (tell *workspace* 'get-groups))
            (sum (map (lambda (s) (length (tell s 'get-all-groups)))
                   (list *initial-string* *modified-string* *target-string*)))
            (sum (map (lambda (o) (tell o 'get-intra-string-salience))
                   (tell *workspace* 'get-objects)))))
        (update-workspace-values)
        (loop (+ c 1))))
    (for-each
      (lambda (string)
        (for-each
          (lambda (b)
            (printf "BOND\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type)
              (tell (tell b 'get-left-object) 'ascii-name)
              (tell (tell b 'get-right-object) 'ascii-name)
              (nm (tell b 'get-bond-category)) (nm (tell b 'get-direction))
              (nm (tell b 'get-bond-facet)) (tell b 'get-strength)))
          (reverse (tell string 'get-bonds)))
        (for-each
          (lambda (g)
            (printf "GROUP\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type) (tell g 'ascii-name)
              (nm (tell g 'get-group-category)) (nm (tell g 'get-direction))
              (nm (tell g 'get-bond-facet)) (tell g 'get-group-length)
              (tell g 'get-letter-span) (tell g 'get-strength))
            (for-each
              (lambda (d)
                (printf "GDESCR\t~a\t~a\t~a~%" (tell string 'get-string-type)
                  (tell g 'ascii-name) (tell d 'print-name)))
              (tell g 'get-all-descriptions)))
          (reverse (tell string 'get-groups)))
        (printf "PROPOSED\t~a\t~a~%" (tell string 'get-string-type)
          (length (tell string 'get-all-groups)))
        (for-each
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a\t~a~%" (tell string 'get-string-type)
              (tell o 'ascii-name) (num (tell o 'get-raw-importance))
              (tell o 'get-intra-string-unhappiness)
              (tell o 'get-intra-string-salience)
              (if (exists? (tell o 'get-enclosing-group)) "in" "-")))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a~%" (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)))

(probe 'abc 'abd 'ijk 3001 300 50)
(probe 'abc 'abd 'mrrjjj 3002 600 40)
(probe 'abcde 'abcdf 'pqrst 3003 600 60)
(probe 'abc 'cba 'iijjkk 3004 800 30)
(probe 'abc 'abd 'iijjkkll 3005 900 20)
(probe 'aabbcc 'aabbcd 'mmrrjjjj 3006 900 70)
