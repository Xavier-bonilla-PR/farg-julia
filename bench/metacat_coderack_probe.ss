;; Exercises the coderack: urgency table, bin assignment, posting, overflow
;; deletion, selection probabilities, and the two-stage codelet choice.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

;; the urgency value table across bins and temperatures
(let loop ((b 0))
  (when (< b %num-of-coderack-bins%)
    (let loop2 ((t 0))
      (when (<= t 100)
        (printf "URG\t~a\t~a\t~a~%" b t (table-ref %urgency-value-table% b t))
        (loop2 (+ t 10))))
    (loop (+ b 1))))

;; bin assignment across the urgency range
(let loop ((u 0))
  (when (<= u 100)
    (printf "BIN\t~a\t~a~%" u
      (let ((i (cond ((<= u 0) 0)
                     ((>= u 100) (sub1 %num-of-coderack-bins%))
                     (else (floor (* (% u) %num-of-coderack-bins%))))))
        i))
    (loop (+ u 1))))

;; urgency naming
(for-each (lambda (u) (printf "UNAME\t~a\t~a~%" u (urgency-name u)))
  '(0 7 8 21 22 35 36 49 50 63 64 77 78 91 92 100))

;; bottom-up urgencies
(for-each
  (lambda (temp)
    (set! *temperature* temp)
    (for-each
      (lambda (ct)
        (printf "BUURG\t~a\t~a\t~a~%" temp
          (tell ct 'get-codelet-type-name) (bottom-up-urgency ct)))
      *bottom-up-codelet-types*))
  '(0 25 50 75 100))

;; posting, overflow and selection
(define probe-coderack
  (lambda (seed temp n)
    (printf "RUN\t~a\t~a\t~a~%" seed temp n)
    (set! *temperature* temp)
    (set! *codelet-count* 0)
    (tell *coderack* 'initialize)
    (random-seed seed)
    (let loop ((i 0))
      (when (< i n)
        (set! *codelet-count* i)
        (let* ((ct (nth (modulo i (length *bottom-up-codelet-types*))
                     *bottom-up-codelet-types*))
               (urgency (modulo (* 7 i) 101)))
          (tell *coderack* 'post (tell ct 'make-codelet urgency)))
        (loop (+ i 1))))
    (printf "POSTED\t~a\t~a~%" (tell *coderack* 'get-num-of-codelets)
      (tell *coderack* 'get-total-urgency-sum))
    (for-each
      (lambda (bin)
        (printf "BINSTATE\t~a\t~a\t~a~%"
          (tell bin 'get-num-of-codelets) (tell bin 'get-urgency)
          (tell bin 'get-urgency-sum)))
      (tell *coderack* 'get-all-bins))
    (tell *coderack* 'update-all-selection-probabilities)
    (let loop ((k 0))
      (when (< k 30)
        (let ((c (tell *coderack* 'choose-codelet)))
          (printf "CHOSE\t~a\t~a\t~a\t~a~%" k
            (tell c 'get-codelet-type-name)
            (round (tell c 'get-relative-urgency))
            (tell *coderack* 'get-num-of-codelets)))
        (loop (+ k 1))))))

(probe-coderack 4242 50 40)
(probe-coderack 909 10 120)
(probe-coderack 31337 90 100)
