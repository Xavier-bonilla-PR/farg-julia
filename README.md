# Copycat in Julia

> **Picking this up in a new session?** Read [`CONTINUE.md`](CONTINUE.md) first.
> It has the environment setup (Julia will not install the obvious way), the
> one command that verifies everything, the porting method, and the list of
> Scheme traps already paid for.

A Julia rewrite of **Copycat**, the analogy-making architecture of Douglas
Hofstadter and Melanie Mitchell, ported from the Python implementation that
[FARGonautica](https://github.com/fargonauts/FARGonautica) recommends, together
with a benchmark harness that runs both versions on identical work and reports
the performance difference.

Copycat solves proportional analogies over letter strings — *`abc : abd :: iijjkk : ?`*
— by letting a swarm of small stochastic agents ("codelets") build and destroy
perceptual structures in a workspace, under the guidance of an activation
network of concepts (the "slipnet") and a global "temperature" that anneals the
randomness as coherent structure emerges.

## Provenance

`FARGonautica/Software/Copycat` itself holds only Melanie Mitchell's original
Lisp and Scott Boland's Java port; its `copycat.md` names the maintained Python 3
version as the recommended one. That Python code (`fargonauts/copycat`, MIT
licensed, the `co.py.cat` lineage: Lisp → Java → Python) is vendored here under
`copycat/python/` and is the source this port was translated from.

```
Mitchell (Lisp) → Boland (Java) → J Alan Brogan (Python) → LSaldyt/fargonauts (Python 3) → this port (Julia)
```

## Layout

The two models live in separate trees, each self-contained and under its own
licence (MIT for Copycat, GPL-2 for Metacat — see below):

```
copycat/julia/src/       the Julia port (module CopycatJL)
copycat/python/copycat/  the vendored Python reference implementation
copycat/bench/           runners, verifier and benchmark harness
copycat/results/         benchmark and verification output

metacat/julia/src/       the Julia port (in progress)
metacat/scheme/metacat/  the vendored Scheme reference implementation
metacat/scheme/headless/ makes that reference run without its SWL GUI
metacat/bench/           probe pairs, verifier and benchmark harness
```

All commands below are run from the repository root.

## Running it

```bash
# Julia
julia --project=copycat/julia copycat/bench/run_jl.jl abc abd ppqqrr 10 --seed 1

# Python reference
python3 copycat/bench/run_py.py abc abd ppqqrr 10 --seed 1
```

Both print one line per distinct answer — `answer, count, average final
temperature, average codelets used` — where a high count means "more obvious"
and a low temperature means "more elegant".

Or from Julia directly:

```julia
using CopycatJL
cc = CopycatJL.Copycat(rng_seed = 1)
result = CopycatJL.run!(cc, "abc", "abd", "iijjkk", 100)
for k in result.keys
    println(k, "\t", result.stats[k].count, "\t", CopycatJL.avgtemp(result, k))
end
```

## The port is behaviour-identical, not merely similar

Copycat is stochastic, so comparing two implementations by eyeballing answer
distributions is weak evidence. Instead the Julia port includes a bit-exact
reimplementation of CPython's `random.Random` in
`copycat/julia/src/pyrandom.jl`: the MT19937 state, CPython's `init_by_array`
integer seeding, the `genrand_res53` double conversion, and the
`getrandbits`/`_randbelow` rejection sampling used by `random.choice`.

Seeded with the same integer, the two implementations therefore consume the
identical stream of random numbers and must run the identical codelet sequence
and return the identical answers — so any behavioural difference is a porting
bug rather than noise, and the benchmark compares exactly the same work rather
than two different random walks.

```bash
python3 copycat/bench/verify.py --iterations 5 --seeds 1 2 3
```

The verifier compares full answer distributions per problem and seed, and for
problems this Copycat variant takes pathologically long to settle (see below) it
compares the first few thousand codelets of the execution trace instead.

## Benchmark

```bash
python3 copycat/bench/benchmark.py --iterations 10 --seeds 1 2 3
```

The harness asserts that both implementations executed the same number of
codelets and produced the same answers before it reports any timing, so a
mismatch fails loudly rather than producing a meaningless speedup number.

Measured on Intel(R) Xeon(R) Processor @ 2.10GHz (4 cores), CPython 3.11.15, julia version 1.10.9, 10 iterations per problem, seeds 1, 2, 3. Both implementations execute the identical codelet sequence, so the codelet count is shared.

| problem | codelets | Python | Julia | speedup | Python w/ logging |
|---|---:|---:|---:|---:|---:|
| `abc : abd :: ijk : ?` | 17,004 | 0.54 s | 0.143 s | **4.8x** | 0.87 s |
| `abc : abd :: iijjkk : ?` | 47,229 | 1.83 s | 0.214 s | **9.2x** | 3.08 s |
| `abc : abd :: mrrjjj : ?` | 148,415 | 6.49 s | 0.566 s | **11.3x** | 9.47 s |
| `abc : abd :: ppqqrr : ?` | 47,229 | 1.76 s | 0.235 s | **7.5x** | 3.13 s |
| `abc : abd :: xyz : ?` | 132,306 | 3.77 s | 0.363 s | **10.4x** | 6.40 s |
| `abc : abd :: kji : ?` | 38,767 | 1.31 s | 0.312 s | **4.0x** | 2.08 s |
| `abcd : abcde :: ijkl : ?` | 38,557 | 1.33 s | 0.422 s | **3.3x** | 1.99 s |
| **total** | **1,408,529** | **51.07 s** | **6.77 s** | **7.5x** | **81.07 s** |

Throughput: **27,582 codelets/s** in Python vs **208,090 codelets/s** in Julia.

Caveats worth stating plainly:

- The Julia figures exclude interpreter startup and JIT compilation (both runners take a `--warmup` flag that discards a throwaway trial first). A cold `julia ... copycat/bench/run_jl.jl` process averages **5.1 s** wall clock here, most of it compilation, against **3.1 s** for the equivalent Python process. For a single small problem the Python process still finishes first; the Julia advantage is in the work itself, and it pays for its startup within roughly the first second of search.
- The "Python w/ logging" column is what `main.py` actually does - it calls `logging.basicConfig(level=INFO)`, so every `logging.info` in the codelets formats a string and writes it to disk. That alone costs about 59% on top of the Python runtime. The main comparison disables it, which is the fairer measurement of the algorithm.
- Copycat is a stochastic search, so absolute times depend heavily on the problem and seed; the per-problem spread above is the point, not any single number.

## Notes on the translation

The port is deliberately faithful rather than idiomatic where the two conflict;
several quirks of the Python original are preserved on purpose and marked with
`NB:` comments in the source:

- `top-down-group-scout--category` returns unconditionally when the bond on the
  chosen side does not match, even though the code appears to look at the other
  side first — the `return` sits at the outer level.
- `group-builder`'s incompatible-bond scan does not advance its `previous` /
  `next_object` cursor when it skips a bond, because Python's `continue` jumps
  past the update.
- `rule-scout` writes `if not o != changed`, i.e. `o == changed`, so its
  "other objects of the same letter" list only ever inspects the changed object.
- `ConceptMapping.symmetricVersion` and `Group.flippedVersion` reference
  attributes that do not exist in the Python original (`initialDescriptor1`,
  `slipnet.flipped`); those branches raise there and raise here too.

Structural differences that do not change behaviour:

- Codelets "fizzle" in Python by raising `AssertionError`, caught in
  `Coderack.run`. Julia exceptions are comparatively expensive and fizzling is
  the common case, so each such `assert` became an early `return`.
- Python's object graph is cyclic (a `Letter` points at its `Bond`, which points
  back). Julia needs types declared before use, so the fields closing a cycle
  are typed with an abstract supertype that has exactly one concrete subtype,
  and methods recover the concrete type with a `::T` assertion.
- Python compares these objects by identity (none define `__eq__`), so the port
  uses `===` and identity-based `remove_first!` / `contains_identical` helpers
  rather than `==`.
- The GUI, curses reporter and matplotlib plotting of the Python version are out
  of scope and not ported.

### On the Julia side's typing

The port is a direct translation, not a rewrite of the algorithm — no data
structure was changed to make it faster, and the verifier proves the two run
codelet for codelet. The one place where translation choices did matter for
speed is container element types: a first cut declared the object graph's
vectors with abstract element types (`Vector{AbstractDescription}` and friends),
which is the natural way to break Julia's definition cycles but costs a dynamic
lookup on every element access. Profiling put over half the runtime in iterating
those vectors.

Declaring them concretely instead — by ordering the struct definitions so that
`Description`, `Bond`, `Correspondence` and `Group` precede the types that hold
them, and giving the workspace's object list the small union
`Union{Group, Letter}` that Julia splits into a branch — made the port ~1.7x
faster with byte-identical output. Only `WorkspaceString.bonds` still needs an
abstract element type, because `WorkspaceString` and `Bond` are a genuine
definition cycle.

### Changes to the vendored Python

Kept to the minimum needed to run it at all on Python 3.11+; the algorithm is
untouched:

- `inspect.getargspec` (removed in 3.11) → the equivalent `getfullargspec` check.
- Dropped the optional `tkinter` GUI import and the matplotlib import from
  `__init__`, so the package loads headless.

## Pathological problems

`axbxcx : axbxdx :: pxqxrx : ?` does not settle in any reasonable time in
**either** implementation — both were left running well past ten minutes. That
is a property of this Copycat variant, not a port bug: the two run identically
codelet for codelet, which is what `copycat/bench/verify.py` checks for them
instead of comparing final answers. `abc : abd :: aababc : ?` is verified the
same way because it is erratic rather than uniformly slow — it finishes in a
few hundred codelets on some seeds and runs long on others.

Several problems are merely expensive rather than pathological, and are worth
knowing about before pointing the benchmark at them: `abc : abd :: wyz : ?` and
`abc : abd :: glz : ?` average hundreds of thousands of codelets per trial, so
the Python reference takes minutes on them where the Julia port takes seconds.

## Metacat

The repository also contains work on **Metacat**, Jim Marshall's successor to
Copycat, which adds *self-watching*: themes, a temporal trace of its own
processing, an episodic memory of past answers, and the ability to justify and
compare the analogies it makes.

### The reference implementation runs headless

Metacat 1.0 is written for Chez Scheme 6.9b inside SWL and is driven entirely
from its GUI, which makes it useless as something to test a port against.
`metacat/scheme/` vendors Marshall's source and adds a harness that loads the
model under a current Chez with no GUI:

```bash
apt-get install chezscheme
scheme --quiet --script metacat/bench/run_metacat_scm.ss abc cba pqrs 42
```

```
OUTCOME	answer	CODELETS	618	TEMP	4
ANSWER	abc -> cba, pqrs -> ?	srqp	98	4
```

See `metacat/scheme/README.md` for what the harness stubs and why. Metacat is
**GPL-2**, unlike Copycat's MIT, so the port inherits GPL-2.

### The port, and how it is checked

As with Copycat, the point is to make "does the port behave the same?" a
decidable question. Metacat funnels all of its nondeterminism through
`(random n)`, so `metacat/scheme/headless/shared-rng.ss` installs the same
CPython-compatible MT19937 the Julia side uses. Each layer of the port has a
pair of probes that dump a canonical trace, and the two must be byte-identical:

```bash
bash metacat/bench/verify_metacat.sh util slipnet workspace cm bonds groups \
                                     bridges coderack bondcodelets themes \
                                     descriptioncodelets groupcodelets \
                                     bridgecodelets themecodelets images rules \
                                     ruleapply ruleabstract rulecodelets \
                                     ruletranslate transstring memory \
                                     patterns trace justify wsevents swevents \
                                     monitors abstract commentary runloop run \
                                     justifymode
```

Thirty-three layers, 39,881 trace lines, byte-identical.

The last two are the whole model. `run` calls the same `run-problem` the
reference runner above calls and compares what Metacat *did*: six problems,
three of them run to an answer, with the episodic memory carried across so that
a later run is reminded of an earlier one. `justifymode` does the same for
justify mode — the configuration where Metacat is given the answer as well as
the problem and asked *why*. Same answers, same codelet counts, same
temperatures, same trace, same memory.

| layer | Julia | verified |
|---|---|---|
| numeric tower, stochastic utilities, temperature formulas | `schemenum.jl`, `utilities.jl` | 264 lines |
| slipnet: 59 nodes, 202 links, activation dynamics | `slipnet.jl` | 538 lines |
| workspace strings, letters, descriptions | `workspace.jl` | 378 lines |
| concept mappings | `concept_mappings.jl` | 192 lines |
| bonds | `bonds.jl` | 92 lines |
| groups (and the image structure they build) | `groups.jl`, `images.jl` | 230 lines |
| image transforms: the algebra a rule works in | `images.jl` | 1,668 lines |
| bridges (horizontal and vertical) | `bridges.jl` | 304 lines |
| coderack: bins, posting, overflow, selection | `coderack.jl` | 366 lines |
| bond codelets, run through the real coderack | `codelets_bonds.jl`, `context.jl` | 263 lines |
| themespace: clusters, activation dynamics, theme support | `themes.jl` | 2,074 lines |
| description codelets | `codelets_descriptions.jl` | 321 lines |
| group codelets: scouts, evaluator, builder, consolidation | `codelets_groups.jl` | 4,854 lines |
| bridge codelets, incl. group flipping and mapping strength | `codelets_bridges.jl` | 5,396 lines |
| thematic codelets: bridges scouted from the themespace | `codelets_themes.jl` | 3,335 lines |
| rules: structure, English transcription, quality metrics | `rules.jl` | 4,620 lines |
| rule application: transforms run against the string's images | `rules.jl`, `images.jl` | 1,993 lines |
| rule abstraction: rules read off the horizontal bridges | `rules.jl` | 1,709 lines |
| the rule codelets: scout, evaluator, builder | `rules.jl`, `context.jl` | 3,280 lines |
| rule translation: the slippage log and its coattails | `answers.jl` | 1,449 lines |
| the translated string, instantiated from an image | `answers.jl`, `images.jl` | 974 lines |
| episodic memory: answer and snag descriptions, distance | `memory.jl` | 505 lines |
| trace patterns and the clamping they drive | `trace.jl` | 334 lines |
| the temporal trace and its generic event | `trace.jl` | 597 lines |
| rule unification and the slippages it yields | `justify.jl` | 289 lines |
| the workspace's concrete trace events | `trace.jl` | 1,828 lines |
| the self-watching events: answer, clamp, snag | `trace.jl` | 453 lines |
| the trace monitors and what they judge important | `trace.jl` | 808 lines |
| memory's two trace-reading abstractors | `memory.jl` | 119 lines |
| the commentary: what the model says about its answers | `commentary.jl` | 72 lines |
| the run loop, cycle by cycle, self-watching on | `run.jl`, `codelets_jootsing.jl` | 246 lines |
| **the whole model, driven by `run-problem`** | `run.jl` | 161 lines |
| **justify mode: the model with a fourth string** | `justify.jl` and 54 branches through the rest | 169 lines |

### How much is done

**All of it.** Every non-graphics line of Metacat's Scheme is ported, in both
of the model's configurations, and verified run for run against the original.
Given a problem and a seed, the Julia port initializes itself, posts its own
codelets, and runs until it finds an answer, gives up, or exhausts a codelet
budget — in step with the Scheme the whole way.

All three perceptual structures — bonds, groups and bridges — build, fight and
break each other through the real coderack. The self-watching loop is closed in
both directions: the themespace reads what the workspace builds, and
`thematic-bridge-scout` sends the workspace looking for structures that would
bear the themespace out. A rule — Metacat's answer to "what changed?" — is read
off the horizontal bridges, ranks itself against its rivals, writes itself out
in English, and can be applied to a string to see what that string would look
like under it. It is then translated through the slippages a vertical bridge
carries, and the string that translation describes is instantiated: that string
is the answer.

And Metacat watches itself do all of it. Every group built, every rule, every
concept mapping that matters and every slipnode that wakes up far enough raises
an event in a *temporal trace*, which the model then reads back: a snag holds
the temperature at 100 until enough progress has been made to stop worrying
about it; a *jootser* that sees the same clamp three times gives up, and one
that sees the same snag three times clamps the NEGATION of the themes those
snags keep implicating — the model telling itself to stop assuming what it has
been assuming. Answers and snags are abstracted into an episodic memory that
outlives the run, so a later run on a related problem is reminded of an earlier
one, with a strength that falls off with the distance between them.

It also writes about what it did. `commentary.jl` is the English Metacat
produces when asked to explain an answer or to compare two of them: which ideas
they share, which they disagree about, which one of them never considered,
which have no justification beyond dodging a snag it remembers hitting — and
which of the two it prefers, and why. That prose is compared character for
character with the Scheme's.

And it can be asked *why*. **Justify mode** is what Metacat does when given the
answer as well as the problem: a fourth string enters the workspace, so there is
a second mapping to build and a second rule to find, and the `answer-justifier`
tries to show that the two halves of the analogy say the same thing. When it
cannot find the matching rule, it *clamps* the two rules it has together with
the theme pattern that would unify them and waits for the workspace to bear that
out — and if it keeps having to do that, the jootser notices the repetition and
gives up. `%justify-mode%` is one flag, but it branches 64 times through
sixteen files of the model; all of it is ported and exercised.

What is not ported is the GRAPHICS. Metacat 1.0 is driven entirely from an SWL
GUI, and the reference implementation here runs headless; the port has no GUI
either. That boundary is the one the project was drawn around, and it is why
"complete" means complete against the model, not against the application.

The themespace is what makes Metacat more than Copycat, and it was on the
critical path rather than optional: every workspace structure's strength is
weighted by its thematic compatibility, and while no themes existed that weight
was 0 for everything. With `themes.jl` in place, bridges boost the themes their
concept mappings realise, themes feed back into structure strengths and into
slipnet activation, and the `themes` probe checks all three loops — including
the float-valued compatibility, which both sides print as the exact rational
the double really is, so a one-ulp drift shows up as a different numerator.

Three things about Metacat's Scheme turned out to be load-bearing and are easy
to lose in a translation:

- **Exact arithmetic.** Metacat computes in exact rationals wherever it can:
  `(% n)` is `(/ n 100)`, an exact ratio for integer `n`, and those values flow
  through activations, link lengths and probability thresholds. A port using
  `Float64` throughout drifts in the low bits and eventually takes a different
  branch at a stochastic threshold. `schemenum.jl` reproduces the parts of
  Scheme's numeric tower that Metacat relies on.
- **Cons ordering.** Links and descriptions are pushed onto the front of their
  lists, so those lists are in reverse declaration order — and the model reads
  the first match out of them.
- **Right-to-left argument evaluation.** Chez evaluates procedure arguments
  right to left, so a call drawing two random numbers draws the rightmost
  first.

The differential test keeps earning its keep, and what it catches is mostly in
layers that were already passing. Adding the themespace surfaced `contains?`,
stubbed to `false` back when no groups existed — correct then, silently wrong
the moment a group was built, and it inflated every description's local support.
Adding the group codelets surfaced two more: a codelet's "carries a proposed
structure" flag that was always false, because an untyped predicate and an
`::Any` fallback are the same Julia method signature and the second silently
replaced the first; and the right-to-left evaluation trap finally biting, in a
group's local-density walk. Adding the bridge codelets surfaced a third
stub-shaped bug of the same family: the cleanup that removes a "middle"
description once a grouping makes it false is also supposed to strip the
matching concept mapping from any bridge resting on it, and break a bridge left
with none. None of these was visible by reading the code.

Getting the model to run end to end surfaced four more of the same shape, none
of which any layer probe could reach. A codelet that changes urgency bins is
RE-STAMPED by the destination bin, so clamping a codelet pattern makes
everything it moved briefly immune to being culled — the port kept the old
stamp, which is tidier and diverges one cycle after the first clamp.
Initializing the coderack unclamps every codelet *type*, and types are global,
so one run's clamps were leaking into the next. `get-equivalent-object` is not
an identity test: a group rebuilt by consolidation is a different object in the
same slot, and finding it is what keeps a rule *supported* across the rebuild.
And rules are workspace structures, so their strength is updated with
everything else's — it is a rule's quality *relative* to its rivals, so two
rules of quality 90 and 99 have strengths 50 and 100. The port had left
`strength` at build-time quality, which is the right ordering and therefore
looks right, until the first codelet that has to choose between two rules.

Turning on justify mode surfaced two more, both in code that had been green for
months because nothing outside that mode could reach it. `get-equivalent-bridge`
had arms for top and vertical bridges and let the bottom one fall through, so a
bottom bridge could not be found equivalent even to *itself* — which silently
made every bottom rule unsupported, and the answer-justifier clamped forever
instead of reporting. And `get-other-string` answered the initial string for the
target either way round, where in justify mode the target has *two* partners:
the initial string vertically and the answer string horizontally. Both are the
same shape as everything above — a branch that is correct until the state it
excludes becomes reachable.

Two divergences of a different kind were also closed: places where the port got
the right *number* but the wrong *exactness*. Chez's `(exp 0)` is the exact `1`,
so the theme-compatibility sigmoid of a bridge with no active themes is the
exact `0` and not `0.0`; and Chez's `max` returns the winning *argument*, so
`(max 9/10 1)` is the exact integer `1` where Julia's promotes to `1//1`. Both
now have a probe section that prints the representation of each value, not just
its value — because the renderer that makes the traces comparable normalises
exactly the difference at issue, and would have hidden it.

### How fast

`metacat/bench/metacat_bench.{ss,jl}` runs seven identical workloads on both
sides with matching checksums. Five are micro-benchmarks of single layers; the
last two are the model — three problems run to an answer or a 2,000-codelet
budget, twenty times over, ordinarily and in justify mode, checksummed on
codelet count, final temperature and whether an answer was found, so a run that
got faster by doing different work would not pass.

| workload | iterations | Chez 9.5.8 | Julia 1.10.9 | speedup |
|---|---:|---:|---:|---:|
| slipnet, 50 activation cycles | 400 | 0.486 s | 0.018 s | 27.1x |
| workspace initialisation | 2000 | 0.610 s | 0.255 s | 2.4x |
| concept mappings | 2000 | 1.044 s | 0.374 s | 2.8x |
| bonds and groups | 2000 | 2.240 s | 0.621 s | 3.6x |
| themespace, 50 activation cycles | 200 | 1.673 s | 0.093 s | 18.0x |
| **whole runs of the model** | 20 | **7.591 s** | **2.202 s** | **3.4x** |
| **whole runs, justify mode** | 20 | **5.223 s** | **1.521 s** | **3.4x** |

The layer numbers are there to locate cost, not to be quoted: each exercises
one thing in a tight loop and flatters whichever implementation happens to suit
it. **3.4x** is the number for Metacat, and it is the same in both of the
model's configurations.

## Licence

The vendored Python Copycat is MIT licensed
(see `copycat/python/LICENSE.upstream`) and the Julia Copycat port carries that
lineage.

Metacat is **GPL-2** (see `metacat/scheme/metacat/LICENSE.upstream`). The Julia
Metacat port under `metacat/julia/src/` is a derivative work and is therefore
GPL-2, not MIT — the two ports in this repository are under different licences,
which is why they sit in separate top-level trees.
