# Copycat in Julia

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
`python/` and is the source this port was translated from.

```
Mitchell (Lisp) → Boland (Java) → J Alan Brogan (Python) → LSaldyt/fargonauts (Python 3) → this port (Julia)
```

## Layout

```
julia/src/         the Julia port (module CopycatJL)
python/copycat/    the vendored Python reference implementation
bench/             runners, verifier and benchmark harness
results/           benchmark and verification output
```

## Running it

```bash
# Julia
julia --project=julia bench/run_jl.jl abc abd ppqqrr 10 --seed 1

# Python reference
python3 bench/run_py.py abc abd ppqqrr 10 --seed 1
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
reimplementation of CPython's `random.Random` in `julia/src/pyrandom.jl`: the
MT19937 state, CPython's `init_by_array` integer seeding, the `genrand_res53`
double conversion, and the `getrandbits`/`_randbelow` rejection sampling used by
`random.choice`.

Seeded with the same integer, the two implementations therefore consume the
identical stream of random numbers and must run the identical codelet sequence
and return the identical answers — so any behavioural difference is a porting
bug rather than noise, and the benchmark compares exactly the same work rather
than two different random walks.

```bash
python3 bench/verify.py --iterations 5 --seeds 1 2 3
```

The verifier compares full answer distributions per problem and seed, and for
problems this Copycat variant takes pathologically long to settle (see below) it
compares the first few thousand codelets of the execution trace instead.

## Benchmark

```bash
python3 bench/benchmark.py --iterations 10 --seeds 1 2 3
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

- The Julia figures exclude interpreter startup and JIT compilation (both runners take a `--warmup` flag that discards a throwaway trial first). A cold `julia ... bench/run_jl.jl` process averages **5.1 s** wall clock here, most of it compilation, against **3.1 s** for the equivalent Python process. For a single small problem the Python process still finishes first; the Julia advantage is in the work itself, and it pays for its startup within roughly the first second of search.
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

`axbxcx : axbxdx :: pxqxrx : ?` and `abc : abd :: aababc : ?` do not settle in
any reasonable time in **either** implementation — they are not port bugs. Both
run identically codelet for codelet (that is what `bench/verify.py` checks for
them); they simply need an enormous number of codelets before the rule
translator fires at a low enough temperature.

## Licence

The vendored Python implementation is MIT licensed (see
`python/LICENSE.upstream`); the Julia port carries that lineage.
