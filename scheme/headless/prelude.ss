;;=============================================================================
;; Headless prelude for Metacat.
;;
;; Metacat 1.0 is written for Chez Scheme 6.9b running inside SWL (the Scheme
;; Widget Library), and is normally driven entirely from its GUI. This file
;; supplies the handful of bindings the non-graphics source needs so that the
;; model can be loaded and run under a modern Chez Scheme with no GUI at all,
;; which is what makes it usable as a reference implementation for testing.
;;
;; Two kinds of binding appear below:
;;   * Genuinely graphical things (windows, colours, fonts, screen geometry)
;;     become inert stubs. Metacat's object system is `tell`, which just
;;     applies a closure to the message, so a window is a closure that
;;     swallows every message.
;;   * Pure helpers that happen to live in a graphics file but are called from
;;     the model proper are reproduced verbatim rather than stubbed, because
;;     their results are algorithm-visible.
;;=============================================================================

;; Chez 9 will not let a top-level `define` capture the primitive it shadows,
;; which utilities.ss does for these four. Captured here instead; utilities.ss
;; is patched to refer to these names.
(define %chez-truncate truncate)
(define %chez-ceiling ceiling)
(define %chez-floor floor)
(define %chez-round round)

;; --- SWL -------------------------------------------------------------------

(define swl:version "0.9x")
(define swl:screen-width (lambda () 1280))
(define swl:screen-height (lambda () 1024))
(define swl:sync-display (lambda args (void)))
(define thread-sleep (lambda (ms) (void)))
(define thread-kill (lambda args (void)))

;; <rgb> is an SWL colour class; constants.ss builds colours with (make <rgb> r g b).
(define <rgb> 'rgb)
(define-syntax make
  (syntax-rules ()
    ((_ cls arg ...) (list 'rgb arg ...))))

;; fonts.ss is a graphics file; constants.ss needs one font constant from it.
(define swl-font (lambda args 'stub-font))
(define sans-serif 'sans-serif)
(define serif 'serif)
(define fixed-width 'fixed-width)

;; Colour constants from general-graphics.ss: only ever stored and handed back
;; to the stubbed windows.
(define %default-fg-color% 'black)
(define %default-bg-color% 'white)

;; The EEG display.
(define *EEG* (lambda msg (void)))

;; --- pure helpers reproduced from the graphics files ------------------------

;; from general-graphics.ss; rules.ss uses these to lay out rule descriptions
(define find-next-space-position
  (lambda (s i)
    (cond
      ((>= i (string-length s)) (string-length s))
      ((char=? (string-ref s i) #\space) i)
      (else (find-next-space-position s (+ i 1))))))

(define separate-into-words
  (lambda (text-string)
    (let* ((next-pos (find-next-space-position text-string 0))
	   (next-word (string-append " " (substring text-string 0 next-pos)))
	   (length (string-length text-string)))
      (if (= next-pos length)
	(list next-word)
	(cons next-word
	  (separate-into-words (substring text-string (+ next-pos 1) length)))))))

;; from trace-graphics.ss; trace.ss uses this to label group events
(define group-event-pexp-text-string
  (lambda (group)
    (let* ((bond-facet (tell group 'get-bond-facet))
	   (constituent-objects (tell group 'get-constituent-objects))
	   (descriptors (tell-all constituent-objects 'get-descriptor-for bond-facet))
	   (descriptor-strings
	     (map (lambda (object descriptor)
		    (cond
		      ((platonic-number? descriptor)
		       (format "~a" (platonic-number->number descriptor)))
		      ((letter? object) (tell descriptor 'get-lowercase-name))
		      ((group? object) (tell descriptor 'get-uppercase-name))))
	       constituent-objects
	       descriptors)))
      (apply string-append
	(cons (1st descriptor-strings)
	  (adjacency-map
	    (lambda (x y) (format "-~a" y))
	    descriptor-strings))))))
