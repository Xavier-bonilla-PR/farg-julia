;; Times the Metacat layers that the Julia port covers, on identical workloads.
;; Emits: BENCH <name> <iterations> <seconds> <checksum>
;; The checksum is there to prove both implementations did the same work.
(define *metacat-source-dir* "scheme/metacat/")
(load "scheme/headless/prelude.ss")
(load "scheme/headless/shared-rng.ss")
(load "scheme/headless/load-core.ss")
(load "scheme/headless/harness.ss")

(define secs (lambda (ms) (/ (exact->inexact ms) 1000.0)))

(define timeit
  (lambda (name iterations thunk)
    (thunk)                                  ;; warm up
    (let* ((t0 (real-time))
           (checksum (let loop ((i 0) (acc 0))
                       (if (>= i iterations)
                         acc
                         (loop (+ i 1) (+ acc (thunk))))))
           (t1 (real-time)))
      (printf "BENCH\t~a\t~a\t~a\t~a~%" name iterations (secs (- t1 t0)) checksum))))

;;--- workload 1: slipnet activation cycles ---------------------------------
(define slipnet-cycle-workload
  (lambda ()
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (random-seed 777)
    (tell plato-a 'activate-from-workspace)
    (tell plato-successor 'activate-from-workspace)
    (tell plato-letter-category 'activate-from-workspace)
    (let loop ((c 0))
      (when (< c 50)
        (update-slipnet-activations)
        (loop (+ c 1))))
    (sum (tell-all *slipnet-nodes* 'get-activation))))

;;--- workload 2: workspace initialisation ----------------------------------
(define workspace-init-workload
  (lambda ()
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (init-workspace 'abcde 'abcdf 'pqrst #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (for* each obj in (tell *workspace* 'get-objects) do
      (for* each descriptor in (tell-all (tell obj 'get-descriptions) 'get-descriptor)
        do (tell descriptor 'set-activation %max-activation%)))
    (update-workspace-values)
    (sum (tell-all (tell *workspace* 'get-objects) 'get-average-salience))))

;;--- workload 3: concept mappings ------------------------------------------
(define cm-workload
  (lambda ()
    (let ((acc 0))
      (for* each o1 in (tell *initial-string* 'get-objects) do
        (for* each o2 in (tell *target-string* 'get-objects) do
          (for* each d1 in (tell o1 'get-descriptions) do
            (for* each d2 in (tell o2 'get-descriptions) do
              (let ((cm (make-concept-mapping
                          o1 (tell d1 'get-description-type) (tell d1 'get-descriptor)
                          o2 (tell d2 'get-description-type) (tell d2 'get-descriptor))))
                (set! acc (+ acc (tell cm 'get-strength)
                              (tell cm 'get-slippability)
                              (if (tell cm 'distinguishing?) 1 0))))))))
      acc)))

;;--- workload 4: bonds and groups ------------------------------------------
(define build-chain-and-groups
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
      (if (not (null? bonds))
        (let* ((cat (tell (1st bonds) 'get-bond-category))
               (dir (tell (1st bonds) 'get-direction))
               (gcat (tell cat 'get-related-node plato-group-category))
               (objs (cons (tell (1st bonds) 'get-left-object)
                       (map (lambda (b) (tell b 'get-right-object)) bonds))))
          (build-group
            (make-group string gcat plato-letter-category dir
              (1st objs) (nth (sub1 (length objs)) objs) objs bonds)
            #f))))))

(define bonds-groups-workload
  (lambda ()
    (for* each node in *slipnet-nodes* do (tell node 'reset))
    (init-workspace 'abcde 'abcdf 'pqrst #f)
    (add-string-position-descriptions-to-letters *initial-string*)
    (add-string-position-descriptions-to-letters *modified-string*)
    (add-string-position-descriptions-to-letters *target-string*)
    (for* each obj in (tell *workspace* 'get-objects) do
      (for* each descriptor in (tell-all (tell obj 'get-descriptions) 'get-descriptor)
        do (tell descriptor 'set-activation %max-activation%)))
    (update-workspace-values)
    (random-seed 555)
    (for-each build-chain-and-groups
      (list *initial-string* *modified-string* *target-string*))
    (update-workspace-values)
    (+ (sum (tell-all (tell *workspace* 'get-bonds) 'get-strength))
       (sum (tell-all (tell *workspace* 'get-groups) 'get-strength)))))

(timeit "slipnet-50-cycles" 400 slipnet-cycle-workload)
(timeit "workspace-init" 2000 workspace-init-workload)
(workspace-init-workload)
(timeit "concept-mappings" 2000 cm-workload)
(timeit "bonds-and-groups" 2000 bonds-groups-workload)
