;;=============================================================================
;; A CPython-compatible MT19937, used to replace Chez's own `random`.
;;
;; Metacat funnels all of its nondeterminism through `(random n)`: every helper
;; in utilities.ss (flip-coin, random-pick, weighted-select, fuzz, ...) is
;; defined in terms of it. Installing a generator here that the Julia port also
;; implements makes seeded runs of the two comparable draw for draw, which is
;; what lets the port be verified rather than merely eyeballed.
;;
;; This changes only where the random numbers come from, not the distributions
;; they follow, so the model behaves exactly as before - just on a different
;; stream. Load it BEFORE the model (see the note at the bottom).
;;=============================================================================

(define %mt-n% 624)
(define %mt-m% 397)
(define %mt-matrix-a% #x9908b0df)
(define %mt-upper-mask% #x80000000)
(define %mt-lower-mask% #x7fffffff)
(define %mt-mask32% #xffffffff)

(define *mt* (make-vector %mt-n% 0))
(define *mti* (+ %mt-n% 1))

(define mt-init-genrand!
  (lambda (s)
    (vector-set! *mt* 0 (bitwise-and s %mt-mask32%))
    (do ((i 1 (+ i 1))) ((= i %mt-n%))
      (let ((prev (vector-ref *mt* (- i 1))))
        (vector-set! *mt* i
          (bitwise-and
            (+ (* 1812433253 (bitwise-xor prev (bitwise-arithmetic-shift-right prev 30))) i)
            %mt-mask32%))))
    (set! *mti* %mt-n%)))

(define mt-init-by-array!
  (lambda (key)
    (mt-init-genrand! 19650218)
    (let ((klen (length key)))
      (let loop ((i 1) (j 0) (k (max %mt-n% klen)))
        (if (> k 0)
            (let ((prev (vector-ref *mt* (- i 1))))
              (vector-set! *mt* i
                (bitwise-and
                  (+ (bitwise-xor (vector-ref *mt* i)
                       (* (bitwise-xor prev (bitwise-arithmetic-shift-right prev 30)) 1664525))
                     (list-ref key j) j)
                  %mt-mask32%))
              (let* ((i (+ i 1)) (j (+ j 1))
                     (i (if (>= i %mt-n%)
                            (begin (vector-set! *mt* 0 (vector-ref *mt* (- %mt-n% 1))) 1)
                            i))
                     (j (if (>= j klen) 0 j)))
                (loop i j (- k 1))))
            (let loop2 ((i i) (k (- %mt-n% 1)))
              (if (> k 0)
                  (let ((prev (vector-ref *mt* (- i 1))))
                    (vector-set! *mt* i
                      (bitwise-and
                        (- (bitwise-xor (vector-ref *mt* i)
                             (* (bitwise-xor prev (bitwise-arithmetic-shift-right prev 30)) 1566083941))
                           i)
                        %mt-mask32%))
                    (let* ((i (+ i 1))
                           (i (if (>= i %mt-n%)
                                  (begin (vector-set! *mt* 0 (vector-ref *mt* (- %mt-n% 1))) 1)
                                  i)))
                      (loop2 i (- k 1))))
                  (begin
                    (vector-set! *mt* 0 %mt-upper-mask%)
                    (set! *mti* %mt-n%)))))))))

;; CPython splits an integer seed into 32-bit little-endian words.
(define mt-seed-key
  (lambda (n)
    (let ((v (abs n)))
      (if (= v 0)
          (list 0)
          (let loop ((v v) (acc '()))
            (if (= v 0)
                (reverse acc)
                (loop (bitwise-arithmetic-shift-right v 32)
                      (cons (bitwise-and v %mt-mask32%) acc))))))))

(define mt-genrand-int32
  (lambda ()
    (when (>= *mti* %mt-n%)
      (do ((kk 0 (+ kk 1))) ((= kk (- %mt-n% %mt-m%)))
        (let ((y (bitwise-ior (bitwise-and (vector-ref *mt* kk) %mt-upper-mask%)
                              (bitwise-and (vector-ref *mt* (+ kk 1)) %mt-lower-mask%))))
          (vector-set! *mt* kk
            (bitwise-xor (vector-ref *mt* (+ kk %mt-m%))
                         (bitwise-arithmetic-shift-right y 1)
                         (if (odd? y) %mt-matrix-a% 0)))))
      (do ((kk (- %mt-n% %mt-m%) (+ kk 1))) ((= kk (- %mt-n% 1)))
        (let ((y (bitwise-ior (bitwise-and (vector-ref *mt* kk) %mt-upper-mask%)
                              (bitwise-and (vector-ref *mt* (+ kk 1)) %mt-lower-mask%))))
          (vector-set! *mt* kk
            (bitwise-xor (vector-ref *mt* (+ kk (- %mt-m% %mt-n%)))
                         (bitwise-arithmetic-shift-right y 1)
                         (if (odd? y) %mt-matrix-a% 0)))))
      (let ((y (bitwise-ior (bitwise-and (vector-ref *mt* (- %mt-n% 1)) %mt-upper-mask%)
                            (bitwise-and (vector-ref *mt* 0) %mt-lower-mask%))))
        (vector-set! *mt* (- %mt-n% 1)
          (bitwise-xor (vector-ref *mt* (- %mt-m% 1))
                       (bitwise-arithmetic-shift-right y 1)
                       (if (odd? y) %mt-matrix-a% 0))))
      (set! *mti* 0))
    (let* ((y (vector-ref *mt* *mti*)))
      (set! *mti* (+ *mti* 1))
      (let* ((y (bitwise-xor y (bitwise-arithmetic-shift-right y 11)))
             (y (bitwise-xor y (bitwise-and (bitwise-arithmetic-shift-left y 7) #x9d2c5680)))
             (y (bitwise-xor y (bitwise-and (bitwise-arithmetic-shift-left y 15) #xefc60000)))
             (y (bitwise-and y %mt-mask32%))
             (y (bitwise-xor y (bitwise-arithmetic-shift-right y 18))))
        (bitwise-and y %mt-mask32%)))))

;; CPython's random.random(): 53 bits from two draws (genrand_res53).
(define mt-random-real
  (lambda ()
    (let* ((a (bitwise-arithmetic-shift-right (mt-genrand-int32) 5))
           (b (bitwise-arithmetic-shift-right (mt-genrand-int32) 6)))
      (/ (+ (* (exact->inexact a) 67108864.0) (exact->inexact b)) 9007199254740992.0))))

(define mt-getrandbits
  (lambda (k)
    (if (= k 0) 0 (bitwise-arithmetic-shift-right (mt-genrand-int32) (- 32 k)))))

;; CPython's Random._randbelow_with_getrandbits: rejection sampling.
(define mt-randbelow
  (lambda (n)
    (if (<= n 0)
        0
        (let ((k (bitwise-length n)))
          (let loop ((v (mt-getrandbits k)))
            (if (>= v n) (loop (mt-getrandbits k)) v))))))

;; --- installed over Chez's own generator ------------------------------------
;;
;; `random` and `random-seed` are immutable primitives in Chez 9, so these are
;; top-level definitions that shadow them. This file must therefore be loaded
;; BEFORE the model, so that the model's references resolve to these.

(define random-seed (lambda (n) (mt-init-by-array! (mt-seed-key n))))

(define random
  (lambda (n)
    (cond
      ((and (integer? n) (exact? n)) (mt-randbelow n))
      (else (* n (mt-random-real))))))
