;; Loads the Metacat model without any of its graphics files.
;; NB: load without a guard. Chez signals compile warnings as continuable
;; conditions, and catching them aborts the rest of the file mid-way.
(define *platform* 'linux)
(define *tcl/tk-version* 8.5)
(define *tcl/tk-version-8_3?* #t)
(for-each (lambda (f) (load (string-append *metacat-source-dir* f)))
  '("syntactic-sugar.ss" "utilities.ss" "constants.ss" "setup.ss" "coderack.ss"
    "descriptions.ss" "bonds.ss" "groups.ss" "bridges.ss" "breakers.ss"
    "workspace.ss" "workspace-objects.ss" "workspace-structures.ss"
    "workspace-strings.ss" "concept-mappings.ss" "workspace-structure-formulas.ss"
    "run.ss" "formulas.ss" "slipnet.ss" "images.ss" "rules.ss" "answers.ss"
    "themes.ss" "justify.ss" "trace.ss" "jootsing.ss" "memory.ss"))
