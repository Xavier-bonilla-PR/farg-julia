# Copycat and Metacat, in Julia

**The purpose of this repository is to make Copycat and Metacat fast enough to
iterate on.**

Both are architectures from Douglas Hofstadter's Fluid Analogies Research Group:
programs that solve proportional analogies over letter strings —
*`abc : abd :: iijjkk : ?`* — by letting a swarm of small stochastic agents
("codelets") build and destroy perceptual structures in a workspace, under an
activation network of concepts (the "slipnet") and a global "temperature" that
anneals the randomness as coherent structure emerges. Metacat is Jim Marshall's
successor to Copycat, and adds *self-watching*: themes, a temporal trace of its
own processing, an episodic memory of past answers, and the ability to justify
and compare the analogies it makes.

Neither is a program you run once. They are stochastic searches, so a question
as basic as *"did that change help?"* means running hundreds of trials across
problems and seeds and comparing distributions. The reference implementations
make that painful:

- **Copycat**'s recommended implementation is Python, and does about **21,000
  codelets/second** here. A seven-problem sweep is a minute; a real parameter
  study is an afternoon.
- **Metacat**'s only implementation is Chez Scheme driven entirely from an SWL
  GUI. There is no headless mode at all, so a sweep is not slow — it is not
  possible without first making the model run without its interface.

So this repository ports both to Julia, and — because a fast model that behaves
differently is worthless — proves the ports run the *identical* computation
rather than merely a similar one. Copycat gets **6.6x**, Metacat **3.4x**, both
with byte-identical output. Metacat also gets a headless reference harness,
which is what makes it measurable in the first place.

```
copycat/julia/src/       the Julia port (module CopycatJL)
copycat/python/copycat/  the vendored Python reference implementation
copycat/bench/           runners, verifier and benchmark harness
copycat/results/         benchmark and verification output

metacat/julia/src/       the Julia port
metacat/scheme/metacat/  the vendored Scheme reference implementation
metacat/scheme/headless/ makes that reference run without its SWL GUI
metacat/bench/           runners, probe pairs, verifier, benchmark, audits
metacat/results/         benchmark and verification output
```

The two models live in separate trees because they are under **different
licences** — MIT for Copycat, GPL-2 for Metacat. See the end of this file.

> Picking the work up in a new session? Read [`CONTINUE.md`](CONTINUE.md) first:
> environment setup (Julia will not install the obvious way), the one command
> that verifies everything, the porting method, and the traps already paid for.

## The two ports at a glance

| | Copycat | Metacat |
|---|---|---|
| reference implementation | Python 3 (`fargonauts/copycat`) | Chez Scheme + SWL (Marshall, 1.0) |
| reference size | 4,082 lines | 18,752 lines (excl. graphics) |
| Julia port size | 3,818 lines | 13,670 lines |
| runs headless out of the box | yes | **no** — `metacat/scheme/headless/` fixes that |
| speedup, whole model | **6.6x** | **3.4x** |
| how the port is checked | 51 answer-distribution and trace comparisons | 33 layer probes, 39,946 trace lines |
| state | complete | the model is complete; the running narration is not |

## Identical, not just similar

Both models are stochastic, so comparing two implementations by eyeballing
answer distributions is weak evidence, and a benchmark of two different random
walks measures nothing. Instead both ports make "does this behave the same?" a
*decidable* question, by sharing a random number generator with the original.

`copycat/julia/src/pyrandom.jl` is a bit-exact reimplementation of CPython's
`random.Random`: the MT19937 state, CPython's `init_by_array` integer seeding,
the `genrand_res53` double conversion, and the `getrandbits`/`_randbelow`
rejection sampling behind `random.choice`. Metacat funnels all of its
nondeterminism through `(random n)`, so `metacat/scheme/headless/shared-rng.ss`
installs that same generator on the Scheme side.

Seeded alike, each implementation therefore consumes the identical stream of
random numbers, must execute the identical codelet sequence, and must return the
identical answers. Any behavioural difference is a porting bug rather than
noise — and every benchmark below compares exactly the same work.

```bash
# Copycat: full answer distributions per problem and seed
python3 copycat/bench/verify.py --iterations 5 --seeds 1 2 3
```

15 problems × 3 seeds compared on their full answer distributions, plus 2
problems compared on the first 5,000 codelets of their execution trace (see
*Pathological problems* below). **51/51 matched.**

```bash
# Metacat: one probe pair per layer, diffed byte for byte
bash metacat/bench/verify_metacat.sh util slipnet workspace cm bonds groups \
     bridges coderack bondcodelets themes descriptioncodelets groupcodelets \
     bridgecodelets themecodelets images rules ruleapply ruleabstract \
     rulecodelets ruletranslate transstring memory patterns trace justify \
     wsevents swevents monitors abstract commentary runloop run justifymode
```

**Thirty-three probes, 39,946 trace lines, byte-identical** — the log is in
[`metacat/results/verify.log`](metacat/results/verify.log). The last two probes
are the whole model: `run` calls the same `run-problem` the reference runner
calls and compares what Metacat *did* across six problems, with the episodic
memory carried between them so reminding is live; `justifymode` does the same
for justify mode. Same answers, same codelet counts, same temperatures, same
trace, same memory.

The two model runners print the same block, so they can be diffed directly:

```bash
$ scheme --quiet --script metacat/bench/run_metacat_scm.ss abc cba pqrs 42 5000
OUTCOME	answer	CODELETS	618	TEMP	4
ANSWER	abc -> cba, pqrs -> ?	srqp	98	4

$ cd metacat/bench && julia run_metacat_jl.jl abc cba pqrs 42 5000
OUTCOME	answer	CODELETS	618	TEMP	4
ANSWER	abc -> cba, pqrs -> ?	srqp	98	4
```

## Benchmarks

All figures below were measured on one machine — **Intel Xeon @ 2.80GHz, 4
cores; CPython 3.11.15, Chez Scheme 9.5.8, Julia 1.10.9** — with nothing else
running. Both harnesses assert that the two implementations did the same work
before reporting any timing, so a port that got faster by doing *different* work
fails the benchmark instead of showing up as a speedup.

Run them with:

```bash
python3 copycat/bench/benchmark.py --iterations 10 --seeds 1 2 3   # writes copycat/results/
python3 metacat/bench/benchmark.py                                 # writes metacat/results/
```

### Copycat against the Python reference

Ten iterations per problem, seeds 1, 2 and 3. Both implementations execute the
identical codelet sequence, so the codelet count is shared rather than compared.

| problem | codelets | Python | Julia | speedup | Python w/ logging |
|---|---:|---:|---:|---:|---:|
| `abc : abd :: ijk : ?` | 17,004 | 0.615 s | 0.179 s | **4.2x** | 1.121 s |
| `abc : abd :: iijjkk : ?` | 47,229 | 2.352 s | 0.356 s | **6.6x** | 3.851 s |
| `abc : abd :: mrrjjj : ?` | 148,415 | 7.911 s | 0.945 s | **8.5x** | 12.728 s |
| `abc : abd :: ppqqrr : ?` | 47,229 | 2.415 s | 0.364 s | **6.8x** | 4.000 s |
| `abc : abd :: xyz : ?` | 132,306 | 5.254 s | 0.532 s | **10.1x** | 8.853 s |
| `abc : abd :: kji : ?` | 38,767 | 1.659 s | 0.435 s | **3.7x** | 2.779 s |
| `abcd : abcde :: ijkl : ?` | 38,557 | 1.671 s | 0.484 s | **3.6x** | 2.887 s |
| **total** | **1,408,529** | **65.63 s** | **9.88 s** | **6.6x** | **108.66 s** |

Throughput: **21,463 codelets/s** in Python against **142,516 codelets/s** in
Julia. Per-seed the spread is wider than the per-problem averages suggest —
individual trials range from 2.1x to 11.9x — because the speedup depends on
which codelets a given random walk happens to run.

### Metacat against the Chez Scheme reference

Five runs of each problem, each from `init-mcat` to an answer under a
5,000-codelet budget, with the episodic memory cleared between runs so that
every iteration does identical work. All nine reach an answer. `outcome`,
`codelets` and `temp` are the checksum: the driver refuses to report a timing
unless the two implementations agree on all three.

| problem | codelets | final temp | Chez | Julia | speedup |
|---|---:|---:|---:|---:|---:|
| `abc : abd :: ijk : ?` | 364 | 19 | 0.195 s | 0.062 s | **3.2x** |
| `abc : abd :: iijjkk : ?` | 886 | 20 | 0.482 s | 0.134 s | **3.6x** |
| `abc : cba :: pqrs : ?` | 726 | 5 | 0.339 s | 0.090 s | **3.8x** |
| `abc : abd :: xyz : ?` | 1,694 | 51 | 0.826 s | 0.253 s | **3.3x** |
| `abc : abd :: mrrjjj : ?` | 336 | 40 | 0.198 s | 0.061 s | **3.2x** |
| `mrrjjj : mrrkkk :: xyz : ?` | 2,925 | 10 | 2.296 s | 0.671 s | **3.4x** |
| `abc : abd :: ijk : ijl` *(justify)* | 436 | 23 | 0.278 s | 0.078 s | **3.6x** |
| `abc : cba :: pqrs : srqp` *(justify)* | 1,287 | 15 | 0.810 s | 0.251 s | **3.2x** |
| `abc : abd :: mrrjjj : mrrjjjj` *(justify)* | 3,282 | 59 | 2.959 s | 0.873 s | **3.4x** |
| **total** | | | **8.38 s** | **2.47 s** | **3.4x** |

The striking thing is how *flat* that column is. Copycat's speedup swings from
3.6x to 10.1x with the problem; Metacat's sits between 3.2x and 3.8x whether the
run is 336 codelets or 3,282, whether it hits a snag (`xyz`, which ends at
temperature 51) or settles cleanly (`pqrs`, temperature 5), and whether or not
justify mode is on. Metacat's per-codelet work is dominated by machinery that
runs on every cycle regardless of what the codelet did — updating the workspace,
spreading activation through the slipnet and the themespace, and maintaining the
temporal trace — so the mixture barely changes and neither does the ratio.

Expect roughly ±10% run to run on these; the three consecutive whole-benchmark
runs made while writing this varied between 3.1x and 3.3x overall.

### Where the time goes

Five single-layer micro-benchmarks, plus the model in aggregate, from
`metacat/bench/metacat_bench.{ss,jl}`. These locate cost; they are not the
number to quote, because each exercises one thing in a tight loop and flatters
whichever implementation happens to suit it.

| workload | iterations | Chez | Julia | speedup |
|---|---:|---:|---:|---:|
| slipnet, 50 activation cycles | 400 | 0.514 s | 0.021 s | 24.5x |
| workspace initialisation | 2,000 | 0.713 s | 0.241 s | 3.0x |
| concept mappings | 2,000 | 1.203 s | 0.142 s | 8.5x |
| bonds and groups | 2,000 | 2.446 s | 0.602 s | 4.1x |
| themespace, 50 activation cycles | 200 | 1.894 s | 0.101 s | 18.8x |
| **whole runs of the model** | 20 | **7.762 s** | **2.040 s** | **3.8x** |
| **whole runs, justify mode** | 20 | **5.420 s** | **1.387 s** | **3.9x** |

The two 16–24x rows are the explanation for the 3.3x. Numeric loops over fixed
arrays — spreading activation through 59 slipnet nodes, or through the
themespace — are exactly what a typed compiled language is good at, and Julia
wins them by more than an order of magnitude. But they are a small fraction of a
real run. The rest of Metacat is pointer-chasing over a graph of workspace
objects, and there Julia's advantage is the 2.5–4x that the whole-model rows
show. **A model is only as fast as its least vectorisable part**, and Metacat's
is most of it.

### Where the originals win: start-up

The tables above deliberately exclude interpreter start-up and JIT compilation
(both harnesses discard a warm-up trial first). That is the fair way to compare
the algorithm, and the wrong way to predict what a single command will cost.
Measured as time from `exec` to a printed answer, cold, best of three:

| one problem, one cold process | reference | Julia | |
|---|---:|---:|---|
| Copycat, `abc:abd::ijk:?`, 1 iteration | 0.08 s | 6.16 s | Julia **77x slower** |
| Metacat, `abc:cba::pqrs:?`, 618 codelets | 0.70 s | 32.35 s | Julia **46x slower** |

Julia compiles the port before it can run a single codelet, and for Metacat's
13,670 lines that compile costs about half a minute — far more than a small
problem does. Chez, meanwhile, loads 18,752 lines of Scheme and starts
interpreting in under a second.

So the port **loses outright on a single run**, and only pays for itself across
a sweep — which is what it is for. The break-even points follow directly from
the two figures above:

- **Copycat**: about **7 seconds** of Python model time in one process, roughly
  150,000 codelets — one `mrrjjj` problem.
- **Metacat**: about **45 seconds** of Chez model time in one process, roughly
  240 runs of the average size in the table above.

Past that, everything is profit, and a study that used to be an afternoon is a
coffee break. Below it, use the original. This is the single most important
caveat in this file, and the reason `metacat/bench/benchmark.py` measures and
prints it rather than leaving it as a footnote.

One more asymmetry, on the Python side only: the "Python w/ logging" column is
what `copycat/main.py` actually does. It calls `logging.basicConfig(level=INFO)`,
so every `logging.info` in the codelets formats a string and writes it to disk,
which costs about **65%** on top of the Python runtime. The main comparison
disables it, as the fairer measurement of the algorithm — but against Copycat
as it ships, the Julia port is closer to 11x.

## What differs between the originals and these ports

### Behaviour: nothing that is ported

This is the whole point of the verification above, and it is worth stating as a
negative result: across 51 Copycat comparisons and 39,946 lines of Metacat
trace, there is **no behavioural difference**. Not "no significant difference" —
no difference. Same answers, same codelet sequences, same temperatures, same
final workspace, same episodic memory, down to the exact rational representation
of a float.

Several quirks of the originals are preserved *on purpose* to keep that true,
and are marked with `NB:` comments in the source. From the Python Copycat:

- `top-down-group-scout--category` returns unconditionally when the bond on the
  chosen side does not match, even though the code appears to look at the other
  side first — the `return` sits at the outer level.
- `group-builder`'s incompatible-bond scan does not advance its `previous` /
  `next_object` cursor when it skips a bond, because Python's `continue` jumps
  past the update.
- `rule-scout` writes `if not o != changed`, i.e. `o == changed`, so its "other
  objects of the same letter" list only ever inspects the changed object.
- `ConceptMapping.symmetricVersion` and `Group.flippedVersion` reference
  attributes that do not exist (`initialDescriptor1`, `slipnet.flipped`); those
  branches raise there and raise here too.

Three properties of Metacat's Scheme turned out to be load-bearing, and are easy
to lose in a translation:

- **Exact arithmetic.** Metacat computes in exact rationals wherever it can:
  `(% n)` is `(/ n 100)`, an exact ratio for integer `n`, and those values flow
  through activations, link lengths and probability thresholds. A port using
  `Float64` throughout drifts in the low bits and eventually takes a different
  branch at a stochastic threshold. `schemenum.jl` reproduces the parts of
  Scheme's numeric tower Metacat relies on.
- **Cons ordering.** Links and descriptions are pushed onto the front of their
  lists, so those lists are in reverse declaration order — and the model reads
  the first match out of them.
- **Right-to-left argument evaluation.** Chez evaluates procedure arguments
  right to left, so a call drawing two random numbers draws the rightmost first.

### Structure: where the ports are not literal

None of these changes what the models compute; the verifiers prove it.

- Copycat codelets "fizzle" in Python by raising `AssertionError`, caught in
  `Coderack.run`. Julia exceptions are comparatively expensive and fizzling is
  the common case, so each such `assert` became an early `return`.
- Python's object graph is cyclic (a `Letter` points at its `Bond`, which points
  back). Julia needs types declared before use, so the fields closing a cycle
  are typed with an abstract supertype that has exactly one concrete subtype,
  and methods recover the concrete type with a `::T` assertion.
- Python compares these objects by identity (none define `__eq__`), so the port
  uses `===` and identity-based helpers rather than `==`.
- Metacat's eight horizontal/vertical twins were collapsed into one function
  taking the orientation as an argument; its constructors, accessors and globals
  became structs, fields and `const`s; its curried closures became ordinary
  arguments. `metacat/bench/audit_coverage.sh` re-derives this list mechanically.

The one place where a translation choice mattered for *speed* was container
element types. A first cut declared the Copycat object graph's vectors
abstractly (`Vector{AbstractDescription}` and friends), which is the natural way
to break Julia's definition cycles but costs a dynamic lookup on every element
access; profiling put over half the runtime in iterating them. Declaring them
concretely instead — ordering the struct definitions so `Description`, `Bond`,
`Correspondence` and `Group` precede the types that hold them, and giving the
workspace's object list the small union `Union{Group, Letter}` that Julia splits
into a branch — made the port **~1.7x faster with byte-identical output**. Only
`WorkspaceString.bonds` still needs an abstract element type, because
`WorkspaceString` and `Bond` are a genuine definition cycle.

Metacat has the same disease and has only been partly treated. Its
`WorkspaceString` declares `letters::Vector{WSObject}` and
`groups::Vector{WSObject}` for that same cycle reason, though instrumenting six
problems shows those vectors only ever hold `Letter` and `Group` respectively —
as do `bonds`, `outgoing_bonds`, `incoming_bonds` and `proposed_groups`, all
declared `Vector{Any}`. A sampling profile attributing each overhead sample to
the model function responsible put **~12% of a whole run** in the two
`distinguishing_descriptor` methods alone, almost all of it Julia resolving
`other.descriptions` at runtime instead of at a fixed field offset. Naming the
concrete type on those two loop variables — two lines, no struct changes — is
worth **1.16x on the whole model** with all 33 probes still byte-identical.

There is more where that came from, but not much that is as cheap. After the fix
the profile is flat: ~21% of the run is still method dispatch and ~23% is GC and
allocation, but the worst single site is 2.4% and the top ten are all between
0.4% and 2.4%. Collecting the rest means making the container fields concrete
rather than annotating call sites one at a time, and that runs into the
definition cycle properly — the honest fix being an arena with integer indices
instead of pointers. A plausible ceiling is 1.5–1.8x over the current port.

One caveat found the hard way: `objects(s) = vcat(s.letters, s.groups)` is
called from 111 sites and looks like the biggest prize, but rewriting it to
return a `Vector{Union{Letter,Group}}` **breaks the build**. The `workspace`,
`cm` and `bonds` probes deliberately load the model *before* `groups.jl` exists,
so naming `Group` in a function defined in `workspace.jl` is an
`UndefVarError` there — and the whole-model probes do not catch it, because they
load everything. Run the full thirty-three before believing any optimisation.

### Not ported

- **Both models' GUIs.** Copycat's tkinter interface, curses reporter and
  matplotlib plotting; Metacat's SWL interface, which is the *entire* front end
  of Metacat 1.0. That boundary is the one this project was drawn around, and it
  is why "complete" means complete against the model, not against the
  application.
- **Metacat's running narration.** Metacat talks to itself as it works — *"Uh-oh,
  I seem to have run into a little problem"*, *"Okay, I'm stumped"*, *"Excuse me
  — I think I'll go get some more punch"* — and those thirteen `add-comment`
  sites (151 lines) are not ported. The machinery behind them is: the port can
  already explain an answer, compare two of them, name a snag and say how one
  string changes into another. What it does not yet do is say those things out
  loud, at the moment it thinks them. `metacat/bench/audit_narration.sh` lists
  the sites. This is the one known gap in the model, and it is deliberately
  *not* rounded away — see `CONTINUE.md`.

### Changes to the vendored originals

Kept to the minimum needed to run them at all; neither algorithm is touched.

- Python Copycat: `inspect.getargspec` (removed in 3.11) → the equivalent
  `getfullargspec` check; dropped the optional `tkinter` and matplotlib imports
  from `__init__` so the package loads headless.
- Scheme Metacat: three mechanical patches to load under Chez 9, listed in
  `CONTINUE.md` §7.

## Running it

```bash
# Copycat
julia --project=copycat/julia copycat/bench/run_jl.jl abc abd ppqqrr 10 --seed 1
python3 copycat/bench/run_py.py abc abd ppqqrr 10 --seed 1
```

Both print one line per distinct answer — *answer, count, average final
temperature, average codelets used* — where a high count means "more obvious"
and a low temperature means "more elegant".

```bash
# Metacat (from the repo root for the Scheme, from metacat/bench for the Julia)
scheme --quiet --script metacat/bench/run_metacat_scm.ss abc abd mrrjjj 23 5000
cd metacat/bench && julia run_metacat_jl.jl abc abd mrrjjj 23 5000

# justify mode: give it the answer too, and ask why
cd metacat/bench && julia run_metacat_jl.jl abc abd mrrjjj 23 5000 --answer mrrjjjj
```

Or from Julia directly:

```julia
using CopycatJL
cc = CopycatJL.Copycat(rng_seed = 1)
result = CopycatJL.run!(cc, "abc", "abd", "iijjkk", 100)
for k in result.keys
    println(k, "\t", result.stats[k].count, "\t", CopycatJL.avgtemp(result, k))
end
```

See [`metacat/scheme/README.md`](metacat/scheme/README.md) for what the headless
harness stubs and why.

## Pathological problems

`axbxcx : axbxdx :: pxqxrx : ?` does not settle in any reasonable time in
**either** Copycat implementation — both were left running well past ten
minutes. That is a property of this Copycat variant, not a port bug: the two run
identically codelet for codelet, which is what the verifier checks for them
instead of comparing final answers. `abc : abd :: aababc : ?` is verified the
same way because it is erratic rather than uniformly slow — a few hundred
codelets on some seeds, and long runs on others.

Several problems are merely expensive, and are worth knowing about before
pointing a benchmark at them: `abc : abd :: wyz : ?` and `abc : abd :: glz : ?`
average hundreds of thousands of codelets per trial, so the Python reference
takes minutes on them where the Julia port takes seconds.

## What is in the Metacat port

Every layer has a probe pair that dumps a canonical trace, and the two sides must
be byte-identical. The line counts are the size of that trace, not of the code.

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
| **justify mode: the model with a fourth string** | `justify.jl` and 64 branches through the rest | 234 lines |

All three perceptual structures — bonds, groups and bridges — build, fight and
break each other through the real coderack. The self-watching loop is closed in
both directions: the themespace reads what the workspace builds, and
`thematic-bridge-scout` sends the workspace looking for structures that would
bear the themespace out. A rule is read off the horizontal bridges, ranks itself
against its rivals, writes itself out in English, and can be applied to a string
to see what that string would look like under it; it is then translated through
the slippages a vertical bridge carries, and the string that translation
describes is instantiated. That string is the answer.

And Metacat watches itself do all of it. Every group built, every rule, every
concept mapping that matters and every slipnode that wakes up far enough raises
an event in a *temporal trace*, which the model reads back: a snag holds the
temperature at 100 until enough progress has been made to stop worrying about
it; a *jootser* that sees the same clamp three times gives up, and one that sees
the same snag three times clamps the NEGATION of the themes those snags keep
implicating — the model telling itself to stop assuming what it has been
assuming. Answers and snags are abstracted into an episodic memory that outlives
the run, so a later run on a related problem is reminded of an earlier one, with
a strength that falls off with the distance between them.

It also writes about what it did. `commentary.jl` is the English Metacat
produces when asked to explain an answer or compare two of them: which ideas
they share, which they disagree about, which one of them never considered, which
have no justification beyond dodging a snag it remembers hitting — and which of
the two it prefers, and why. That prose is compared character for character with
the Scheme's.

And it can be asked *why*. **Justify mode** is what Metacat does when given the
answer as well as the problem: a fourth string enters the workspace, so there is
a second mapping to build and a second rule to find, and the `answer-justifier`
tries to show that the two halves of the analogy say the same thing. When it
cannot find the matching rule it *clamps* the two rules it has, together with the
theme pattern that would unify them, and waits for the workspace to bear that
out — and if it keeps having to do that, the jootser notices the repetition and
either gives up or *settles*: it reports the answer anyway, carrying the
slippages it could not account for. On `abc → abd :: mrrjjj → mrrjjjj` the port
does exactly that, and names the one it could not justify — letter-category ⇔
length, precisely the slippage that makes the analogy work. `%justify-mode%` is
one flag, but it branches 64 times through sixteen non-graphics files; all of
it is ported and exercised.

### What the differential test caught

Worth recording, because most of it was in layers that were already passing.

Adding the themespace surfaced `contains?`, stubbed to `false` back when no
groups existed — correct then, silently wrong the moment a group was built, and
it inflated every description's local support. Adding the group codelets
surfaced two more: a codelet's "carries a proposed structure" flag that was
always false, because an untyped predicate and an `::Any` fallback are the same
Julia method signature and the second silently replaced the first; and the
right-to-left evaluation trap finally biting, in a group's local-density walk.
Adding the bridge codelets surfaced a third of the same family: the cleanup that
removes a "middle" description once a grouping makes it false is also supposed to
strip the matching concept mapping from any bridge resting on it, and break a
bridge left with none. None of these was visible by reading the code.

Getting the model to run end to end surfaced four more that no layer probe could
reach. A codelet that changes urgency bins is **re-stamped** by the destination
bin, so clamping a codelet pattern makes everything it moved briefly immune to
being culled — the port kept the old stamp, which is tidier and diverges one
cycle after the first clamp. Initializing the coderack unclamps every codelet
*type*, and types are global, so one run's clamps were leaking into the next.
`get-equivalent-object` is not an identity test: a group rebuilt by consolidation
is a different object in the same slot, and finding it is what keeps a rule
*supported* across the rebuild. And rules are workspace structures, so their
strength is updated with everything else's — it is a rule's quality *relative* to
its rivals, so two rules of quality 90 and 99 have strengths 50 and 100; the port
had left `strength` at build-time quality, which is the right ordering and
therefore looks right, until the first codelet that has to choose between two
rules.

Turning on justify mode surfaced two more, both in code green for months because
nothing outside that mode could reach it. `get-equivalent-bridge` had arms for
top and vertical bridges and let the bottom one fall through, so a bottom bridge
could not be found equivalent even to *itself* — which silently made every
bottom rule unsupported, and the answer-justifier clamped forever instead of
reporting. And `get-other-string` answered the initial string for the target
either way round, where in justify mode the target has *two* partners: the
initial string vertically and the answer string horizontally.

Two divergences of a different kind were also closed: places where the port got
the right *number* but the wrong *exactness*. Chez's `(exp 0)` is the exact `1`,
so the theme-compatibility sigmoid of a bridge with no active themes is the exact
`0` and not `0.0`; and Chez's `max` returns the winning *argument*, so
`(max 9/10 1)` is the exact integer `1` where Julia's promotes to `1//1`. Both
now have a probe section that prints the *representation* of each value, not just
its value — because the renderer that makes traces comparable normalises exactly
the difference at issue, and would have hidden it.

## Provenance

`FARGonautica/Software/Copycat` holds only Melanie Mitchell's original Lisp and
Scott Boland's Java port; its `copycat.md` names the maintained Python 3 version
as the recommended one. That code (`fargonauts/copycat`, MIT, the `co.py.cat`
lineage) is vendored here under `copycat/python/` and is what this port was
translated from.

```
Mitchell (Lisp) → Boland (Java) → J Alan Brogan (Python) → LSaldyt/fargonauts (Python 3) → this port (Julia)
```

Metacat 1.0 is Jim Marshall's, written for Chez Scheme 6.9b inside SWL. It is
vendored under `metacat/scheme/metacat/` and is the source the Julia Metacat was
translated from.

## Licence

The vendored Python Copycat is MIT licensed (see
`copycat/python/LICENSE.upstream`) and the Julia Copycat port carries that
lineage.

Metacat is **GPL-2** (see `metacat/scheme/metacat/LICENSE.upstream`). The Julia
Metacat port under `metacat/julia/src/` is a derivative work and is therefore
**GPL-2, not MIT** — the two ports in this repository are under different
licences, which is why they sit in separate top-level trees.
