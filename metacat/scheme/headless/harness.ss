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

;; rules.ss's English transcription calls find-next-space-position, which lives
;; in general-graphics.ss -- a graphics file, and so never loaded headless, even
;; though this one procedure is pure string arithmetic. Supply it verbatim.
(define find-next-space-position
  (lambda (s i)
    (cond
      ((>= i (string-length s)) (string-length s))
      ((char=? (string-ref s i) #\space) i)
      (else (find-next-space-position s (+ i 1))))))

;; Metacat ends a run with (suspend) -> (break), which hands control back to
;; the SWL repl. Headless, redirect that to an escape continuation. `suspend`
;; itself only prints "Type (go) or click on the Workspace to continue...",
;; which is an instruction to a user of a GUI that is not here, so drop it and
;; go straight to the escape.
;;
;; Two things end a run, and they end it the same way: `report-new-answer`
;; found an answer, and `give-up` decided there is nothing better to try. The
;; escape alone cannot tell them apart, so `give-up` records which it was.
(define *escape* #f)
(define *stop-reason* 'answer)
(set! break (lambda () (*escape* *stop-reason*)))
(set! suspend (lambda () (break)))
(define original-give-up give-up)
(set! give-up
  (lambda ()
    (set! *stop-reason* 'give-up)
    (original-give-up)))

;; memory.ss's answer descriptions call (get-normal-icon-pexp new-value)
;; UNGUARDED from `update-activation` and `unhighlight` (lines 203 and 264).
;; That slot holds a graphics CLOSURE which only `set-graphics-info` ever fills
;; in, and headless nothing ever does, so it is #f. It is an ARGUMENT to
;; `tell`, evaluated before the guard above can route the send to a no-op, so
;; the guard cannot save it. This only bites on the SECOND problem of a session:
;; `init-mcat` calls (tell *memory* 'clear-activations), which updates the
;; activation of every answer already in memory, and until one is there nothing
;; reaches the call. Fill the slot with a no-op as each description is made.
(define original-make-answer-description make-answer-description)
(set! make-answer-description
  (lambda args
    (let ((answer (apply original-make-answer-description args)))
      (tell answer 'set-graphics-info (lambda (activation) #f) #f)
      answer)))

(define *codelet-limit* 100000)
(define original-step-mcat step-mcat)
(set! step-mcat
  (lambda ()
    (if (>= *codelet-count* *codelet-limit*)
        (*escape* 'limit)
        (original-step-mcat))))

;; `%justify-mode%` is a GUI toggle in Metacat, and `init-mcat` builds the
;; fourth string only when it is on, so a headless run has to set it. Each entry
;; point sets it to what IT needs and leaves it there: the flag says what the
;; workspace currently is, so restoring it afterwards would leave the finished
;; run's workspace being described by the wrong mode -- `get-objects` and
;; `get-bonds` would stop reporting the answer string the run actually used.
(define run-problem
  (lambda (initial modified target seed limit)
    (set! %justify-mode% #f)
    (set! *codelet-limit* limit)
    (set! *stop-reason* 'answer)
    (call/cc
      (lambda (k)
        (set! *escape* k)
        (init-mcat initial modified target #f seed)
        (run-mcat)))))

(define run-justify-problem
  (lambda (initial modified target answer seed limit)
    (set! %justify-mode% #t)
    (set! *codelet-limit* limit)
    (set! *stop-reason* 'answer)
    (call/cc
      (lambda (k)
        (set! *escape* k)
        (init-mcat initial modified target answer seed)
        (run-mcat)))))
