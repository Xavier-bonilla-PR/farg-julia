;; Runs the group codelet pipeline through the real coderack for N codelets,
;; dumping every codelet run and the resulting workspace state.
;;
;; The rack is seeded with bond scouts (so there are bonds to group), all three
;; group scouts, and the bridge scouts, so that groups and bridges get to fight
;; each other and the bridge-to-group length branch - which posts a
;; top-down-group-scout:category - is reachable.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))
(define yn (lambda (b) (if b "y" "n")))

(define post-scouts
  (lambda ()
    (let loop ((k 0))
      (when (< k 4)
        (tell *coderack* 'post
          (tell bottom-up-bond-scout 'make-codelet %very-low-urgency%))
        (tell *coderack* 'post
          (tell group-scout:whole-string 'make-codelet %very-low-urgency%))
        (tell *coderack* 'post
          (tell bottom-up-bridge-scout 'make-codelet %very-low-urgency%))
        (loop (+ k 1))))
    ;; top-down group scouts: both kinds, over both kinds of scope
    (for-each
      (lambda (group-category)
        (tell *coderack* 'post
          (tell top-down-group-scout:category 'make-codelet %low-urgency%
            group-category *initial-string*))
        (tell *coderack* 'post
          (tell top-down-group-scout:category 'make-codelet %low-urgency%
            group-category *workspace*)))
      (list plato-succgrp plato-predgrp plato-samegrp))
    (for-each
      (lambda (direction)
        (tell *coderack* 'post
          (tell top-down-group-scout:direction 'make-codelet %low-urgency%
            direction *target-string*))
        (tell *coderack* 'post
          (tell top-down-group-scout:direction 'make-codelet %low-urgency%
            direction *workspace*)))
      (list plato-left plato-right))))

(define probe
  (lambda (i m t seed n temp)
    (printf "PROBLEM\t~a\t~a\t~a\t~a\t~a\t~a~%" i m t seed n temp)
    (for* each node in *slipnet-nodes* do (tell node 'reset))
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
                             plato-direction-category plato-length
                             plato-alphabetic-position-category
                             plato-samegrp plato-succgrp plato-predgrp
                             plato-left plato-right) do
      (tell node 'set-activation %max-activation%))
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (update-workspace-values)
    (random-seed seed)
    ;; The scouts here never post more scouts, so the rack would drain and the
    ;; run would stop long before N codelets. Re-seeding whenever it empties
    ;; keeps groups coming, which is what the builder needs to have anything
    ;; to fight, consolidate or find already present.
    (post-scouts)
    (let loop ((c 0))
      (when (< c n)
        (if* (tell *coderack* 'empty?) (post-scouts))
        (set! *codelet-count* c)
        (let ((codelet (tell *coderack* 'choose-codelet)))
          (printf "RUN\t~a\t~a\t~a\t~a~%" c
            (tell codelet 'get-codelet-type-name)
            (round (tell codelet 'get-relative-urgency))
            (tell *coderack* 'get-num-of-codelets))
          (tell codelet 'run))
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
              (tell g 'get-strength) (tell g 'get-proposal-level))
            (for-each
              (lambda (d)
                (printf "GROUPDESC\t~a\t~a\t~a\t~a~%"
                  (tell string 'get-string-type) (tell g 'ascii-name)
                  (nm (tell d 'get-description-type)) (nm (tell d 'get-descriptor))))
              (tell g 'get-all-descriptions)))
          (reverse (tell string 'get-groups)))
        (for-each
          (lambda (o)
            (printf "OBJ\t~a\t~a\t~a\t~a\t~a\t~a~%"
              (tell string 'get-string-type) (tell o 'ascii-name)
              (tell o 'get-intra-string-unhappiness)
              (tell o 'get-intra-string-salience)
              (tell o 'get-average-salience)
              (tell o 'get-relative-importance)))
          (tell string 'get-objects)))
      (list *initial-string* *modified-string* *target-string*))
    (for-each
      (lambda (bridge-type)
        (for-each
          (lambda (b)
            (printf "BRIDGE\t~a\t~a\t~a\t~a\t~a~%" bridge-type
              (tell (tell b 'get-object1) 'ascii-name)
              (tell (tell b 'get-object2) 'ascii-name)
              (yn (tell b 'spanning-bridge?)) (tell b 'get-strength)))
          (reverse (tell *workspace* 'get-bridges bridge-type))))
      '(top vertical))
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a~%" (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)))

(probe 'abc 'abd 'ijk 909 150 50)
(probe 'abc 'abd 'mrrjjj 313 200 40)
(probe 'aabbcc 'aabbdd 'xxyyzz 555 250 60)
(probe 'abcde 'abcdf 'pqrst 777 250 70)
;; reversed strings: a group's direction ends up contradicting a bridge's
;; string-position mapping, which is the group-versus-bridge fight
(probe 'abc 'abd 'cba 3 300 50)
(probe 'abcd 'abce 'dcba 3 300 50)
;; runs of three identical letters: a sameness group can end up containing
;; another one, which is the builder's letter-consolidation case
(probe 'aaabbb 'aaabbc 'jjjkkk 1 300 55)
