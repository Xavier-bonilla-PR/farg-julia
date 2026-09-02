;; Canonical dump of the slipnet: structure first, then activation dynamics.
(define *metacat-source-dir* "metacat/scheme/metacat/")
(load "metacat/scheme/headless/prelude.ss")
(load "metacat/scheme/headless/shared-rng.ss")
(load "metacat/scheme/headless/load-core.ss")

(define num->str
  (lambda (v)
    (if (exact? v)
      (if (integer? v)
        (number->string v)
        (format "~a/~a" (numerator v) (denominator v)))
      (number->string v))))

(define nm (lambda (n) (if (exists? n) (tell n 'get-lowercase-name) "-")))

(printf "COUNT\tnodes\t~a~%" (length *slipnet-nodes*))

(for-each
  (lambda (node)
    (printf "NODE\t~a\t~a\t~a\t~a\t~a\t~a~%"
      (nm node) (tell node 'get-short-name) (tell node 'get-conceptual-depth)
      (tell node 'get-intrinsic-link-length)
      (tell node 'get-shrunk-link-length)
      (length (tell node 'get-incoming-links))))
  *slipnet-nodes*)

(for-each
  (lambda (node)
    (for-each
      (lambda (pair)
        (let ((listname (1st pair)) (links (2nd pair)))
          (let loop ((i 0) (ls links))
            (when (not (null? ls))
              (let ((l (1st ls)))
                (printf "LINK\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a~%"
                  (nm node) listname i (nm (tell l 'get-from-node)) (nm (tell l 'get-to-node))
                  (tell l 'get-link-type) (nm (tell l 'get-label-node))
                  (tell l 'get-link-length)
                  (num->str (tell l 'get-intrinsic-degree-of-assoc))
                  (num->str (tell l 'get-degree-of-assoc))))
              (loop (+ i 1) (rest ls))))))
      (list (list "category" (tell node 'get-category-links))
            (list "instance"
                  (filter (lambda (l) (eq? (tell l 'get-link-type) 'instance))
                    (tell node 'get-outgoing-links)))
            (list "property" (tell node 'get-property-links))
            (list "lateral" (tell node 'get-lateral-links))
            (list "sliplink" (tell node 'get-lateral-sliplinks))
            (list "labeled" (tell node 'get-links-labeled-by-node)))))
  *slipnet-nodes*)

;; --- activation dynamics ---
(for* each node in *slipnet-nodes* do (tell node 'reset))
(random-seed 314159)
(tell plato-a 'activate-from-workspace)
(tell plato-successor 'activate-from-workspace)
(tell plato-letter-category 'activate-from-workspace)
(let loop ((cycle 0))
  (when (< cycle 20)
    (update-slipnet-activations)
    (for-each
      (lambda (node)
        (if* (not (= 0 (tell node 'get-activation)))
          (printf "ACT\t~a\t~a\t~a~%" cycle (nm node) (tell node 'get-activation))))
      *slipnet-nodes*)
    (loop (+ cycle 1))))
