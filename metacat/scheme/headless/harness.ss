;; Turns the loaded model into something that can be driven from a script:
;; stubs the windows, silences the graphics flags, and replaces Metacat's
;; GUI-oriented stop mechanism with an escape continuation.

(define make-stub-window (lambda (name) (lambda msg (void))))

(for-each
  (lambda (sym) (set-top-level-value! sym (make-stub-window sym)))
  '(*workspace-window* *slipnet-window* *coderack-window* *themespace-window*
    *top-themes-window* *bottom-themes-window* *vertical-themes-window*
    *memory-window* *comment-window* *trace-window* *temperature-window*
    *control-panel* *EEG-window*))

;; group-builder calls (group-graphics 'erase ...) UNGUARDED in each of its two
;; consolidation branches (groups.ss lines 727 and 765), unlike every other
;; graphics call in that file, which sits behind %workspace-graphics%. Headless,
;; group-graphics.ss is never loaded, so those two calls raise as soon as a
;; group consolidates. Stub the dispatcher rather than patch the model.
(set-top-level-value! 'group-graphics (lambda args (void)))

(set! %workspace-graphics% #f)
(set! %slipnet-graphics% #f)
(set! %coderack-graphics% #f)
(set! %codelet-count-graphics% #f)
(set! %highlight-last-codelet% #f)
(set! %nice-graphics% #f)

;; A few objects captured a window global at construction time, when it was
;; still #f. Those sends are graphics-only, so route a tell to a non-procedure
;; to a no-op rather than letting it crash the run.
(define original-tell tell)
(set! tell
  (lambda args
    (if (procedure? (car args)) (apply original-tell args) (void))))

;; Metacat ends a run with (suspend) -> (break), which hands control back to
;; the SWL repl. Headless, redirect that to an escape continuation.
(define *escape* #f)
(set! break (lambda () (*escape* 'answer)))

(define *codelet-limit* 100000)
(define original-step-mcat step-mcat)
(set! step-mcat
  (lambda ()
    (if (>= *codelet-count* *codelet-limit*)
        (*escape* 'limit)
        (original-step-mcat))))

(define run-problem
  (lambda (initial modified target seed limit)
    (set! *codelet-limit* limit)
    (call/cc
      (lambda (k)
        (set! *escape* k)
        (init-mcat initial modified target #f seed)
        (run-mcat)))))
