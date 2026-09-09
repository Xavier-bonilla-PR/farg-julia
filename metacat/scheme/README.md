# Running Metacat headless

Metacat 1.0 (Jim Marshall, 1999/2003) is written for Chez Scheme 6.9b running
inside **SWL**, the Scheme Widget Library, and is normally driven entirely from
its GUI. That makes it hard to use as a reference implementation: you cannot
script it, and SWL no longer builds against current toolchains.

`metacat/scheme/headless/` makes the model run under a modern Chez Scheme with
no GUI, so it can be driven from a shell script and compared against a port.

```bash
apt-get install chezscheme
scheme --quiet --script metacat/bench/run_metacat_scm.ss abc cba pqrs 42
```

```
OUTCOME	answer	CODELETS	618	TEMP	4
ANSWER	abc -> cba, pqrs -> ?	srqp	98	4
```

## What the harness does

| file | role |
|---|---|
| `headless/prelude.ss` | stands in for SWL: windows, colours, fonts, screen geometry |
| `headless/shared-rng.ss` | a CPython-compatible MT19937 replacing Chez's `random` |
| `headless/load-core.ss` | loads the 26 model files, skipping all graphics files |
| `headless/harness.ss` | stubs the windows and replaces the GUI stop mechanism |

Metacat's own object system is `tell`, which simply applies a closure to a
message, so a GUI window becomes a closure that swallows every message. A run
normally ends by calling `(suspend)` → `(break)`, which hands control back to
the SWL repl; the harness redirects that to an escape continuation so a script
can collect the answer. `(suspend)`'s own message — "Type (go) or click on the
Workspace to continue..." — is an instruction to a user of a GUI that is not
there, so the harness drops it. Two things end a run through that same
`break`: `report-new-answer` found an answer, and `give-up` decided there was
nothing better to try. The escape alone cannot tell them apart, so the harness
has `give-up` record which it was, and `run-problem` returns `answer`,
`give-up` or `limit`.

`run-problem` and `run-justify-problem` are the two entry points, for the
model's two configurations. Justify mode — where Metacat is given the answer as
well as the problem and asked *why* — is a GUI toggle in Metacat 1.0, and
`init-mcat` builds the fourth string only when it is on, so each entry point
SETS `%justify-mode%` to what it needs and leaves it there. Restoring the flag
after a run would leave the finished workspace being described by the wrong
mode: `get-objects` and `get-bonds` consult it, and would stop reporting the
answer string the run actually used.

Two graphics calls reach past the `tell` guard, because they are ARGUMENTS to
a `tell` rather than sends themselves, and the harness fills their slots in.
`group-builder` calls `(group-graphics 'erase ...)` unguarded in each of its
two consolidation branches, so `group-graphics` is stubbed. And an answer
description's `update-activation` and `unhighlight` call
`(get-normal-icon-pexp value)`, a closure only the memory window ever supplies;
the harness wraps `make-answer-description` and puts a no-op there. That one
only bites on the second problem of a session, when `init-mcat`'s
`clear-activations` first has an answer to clear.

Where a *pure* helper happens to live in a graphics file but is called from the
model proper — `find-next-space-position`, `separate-into-words`,
`group-event-pexp-text-string` — it is reproduced verbatim in the prelude
rather than stubbed, because its result is algorithm-visible.

## Changes to the vendored Metacat

Kept to the minimum needed to load under Chez 9; the model is untouched.

- `utilities.ss` redefines `truncate`, `ceiling`, `floor` and `round` in terms
  of themselves. Chez 9 does not let a top-level `define` capture the primitive
  it shadows, so those four capture `%chez-*` aliases taken in the prelude.
- Chez 9's reader rejects `#` inside a symbol, which Chez 6.9b allowed. The
  five affected symbols all end in `id#` (`get-id#`, `next-id#`, `set-id#`,
  `assign-id#`, `id#`) and were renamed to `id-num` throughout.

## Why the RNG is replaced

Metacat funnels all of its nondeterminism through `(random n)`: every helper in
`utilities.ss` — `flip-coin`, `random-pick`, `weighted-select`, `fuzz` — is
defined in terms of it. Installing a generator that a port also implements
makes seeded runs comparable draw for draw, which is what turns "does the port
behave the same?" into a decidable question rather than a statistical one. Only
the source of the numbers changes, not their distributions, so the model
behaves as before on a different stream.

`metacat/bench/run_metacat_scm.ss` loads it; drop that one `load` line to run on
Chez's
own generator instead.

## A note on evaluation order

Chez evaluates procedure arguments **right to left**. Metacat contains
expressions that draw more than one random number in a single call, so a port
that evaluates left to right will diverge even with an identical generator.
Any port aiming at draw-for-draw agreement has to reproduce Chez's order.

## Licence

Metacat is GPL-2 (see `metacat/LICENSE.upstream`) — unlike Copycat, which is
MIT. Anything derived from it, including a port, inherits GPL-2.
