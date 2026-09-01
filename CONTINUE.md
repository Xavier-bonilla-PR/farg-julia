# Continuing this work in a new session

Everything below assumes a **fresh container with a fresh clone** — no
toolchain, nothing cached. Start here.

Branch: `claude/quirky-ptolemy-91zvuu`
Last commit at time of writing: the bridge codelet commit.

---

## 1. Environment setup (do this first)

Three tools are needed and **none of them install the obvious way**. The Julia
step in particular cost real time to discover; don't re-derive it.

```bash
# Chez Scheme — runs the Metacat reference implementation
apt-get update && apt-get install -y chezscheme        # gives `scheme` 9.5.8

# Julia — see the warning below
cd /tmp && curl -fsSL -o julia.tar.gz \
  "https://s3.amazonaws.com/julialang2/bin/linux/x64/1.10/julia-1.10.9-linux-x86_64.tar.gz"
tar xzf julia.tar.gz          # binary at /tmp/julia-1.10.9/bin/julia

# only if you need to read the PDF paper
apt-get install -y poppler-utils
```

### Julia download: the two obvious routes are both blocked

- `julialang-s3.julialang.org` → **403** from the egress proxy (org policy).
- `github.com/JuliaLang/julia/releases/...` → **404**; GitHub is scoped to this
  session's own repos, so release assets are not reachable. `add_repo` grants
  anonymous *git* reads only, not release downloads.
- Ubuntu noble has **no** `julia` package (`apt-cache policy julia` → none).
- **`s3.amazonaws.com/julialang2/...` works.** That is the official bucket
  behind julialang.org, reachable because the hostname is allowed. Use it.

Set `JULIA` to the binary path for every command below:

```bash
export JULIA=/tmp/julia-1.10.9/bin/julia
```

---

## 2. Verify the current state

From the repo root. This is the single most useful command in the project:

```bash
JULIA=$JULIA bash bench/verify_metacat.sh \
  util slipnet workspace cm bonds groups bridges coderack bondcodelets \
  bridgecodelets
```

Expected — ten layers, **3,582 trace lines byte-identical**:

```
ok    util (264 lines identical)
ok    slipnet (538 lines identical)
ok    workspace (378 lines identical)
ok    cm (192 lines identical)
ok    bonds (92 lines identical)
ok    groups (230 lines identical)
ok    bridges (304 lines identical)
ok    coderack (366 lines identical)
ok    bondcodelets (263 lines identical)
ok    bridgecodelets (955 lines identical)
all probes matched
```

If any probe fails on a clean checkout, something in the environment differs —
fix that before writing new code.

The reference implementation also runs standalone:

```bash
scheme --quiet --script bench/run_metacat_scm.ss abc cba pqrs 42
# OUTCOME  answer  CODELETS  618  TEMP  4
# ANSWER   abc -> cba, pqrs -> ?   srqp   98   4
```

The Copycat side (finished, separate from Metacat):

```bash
python3 bench/verify.py --iterations 5 --seeds 1 2 3   # 51/51 must match
```

---

## 3. What exists

### Copycat — **complete**

Python reference (`python/`, MIT, vendored from `fargonauts/copycat`) ported to
Julia (`julia/src/*.jl`). Verified by bit-exact RNG parity: 51/51 comparisons
byte-identical. Benchmarked at **7.5x** faster than Python over 1.4M codelets
(`results/benchmark.json`). Nothing outstanding.

### Metacat — **~5,200 of ~16,000 lines of non-graphics Scheme**

| layer | Julia file | probe | lines |
|---|---|---|---:|
| numeric tower, stochastic utils, temperature | `schemenum.jl`, `utilities.jl` | `util` | 264 |
| slipnet: 59 nodes, 202 links, activation | `slipnet.jl` | `slipnet` | 538 |
| workspace strings, letters, descriptions | `workspace.jl` | `workspace` | 378 |
| concept mappings | `concept_mappings.jl` | `cm` | 192 |
| bonds | `bonds.jl` | `bonds` | 92 |
| groups, image structure | `groups.jl`, `images.jl` | `groups` | 230 |
| bridges (horizontal + vertical) | `bridges.jl` | `bridges` | 304 |
| coderack | `coderack.jl` | `coderack` | 366 |
| bond codelet pipeline via the coderack | `codelets_bonds.jl`, `context.jl` | `bondcodelets` | 263 |
| bridge codelet pipeline, workspace bridge bookkeeping, mapping strengths | `codelets_bridges.jl`, `context.jl` | `bridgecodelets` | 955 |

---

## 4. The method — follow this exactly

Every layer is verified by a **probe pair**: `bench/metacat_<name>_probe.ss` and
`bench/metacat_<name>_probe.jl`, which print the same canonical trace. They must
be **byte-identical**. Do not accept "close enough".

This works because both sides run the **same generator**:
`scheme/headless/shared-rng.ss` installs a CPython-compatible MT19937 over
Chez's `random`, matching `julia/src/pyrandom.jl`. All of Metacat's
nondeterminism funnels through `(random n)`, so seeded runs agree draw for draw.

To add a layer:

1. Read the Scheme file. Note every `random` call and its **order**.
2. Write the Julia port in `julia/src/metacat/`.
3. Write the two probes, dumping every field you can reach. Tag exact vs
   inexact numbers (`E`/`F`) — exactness is a real signal, see below.
4. `JULIA=$JULIA bash bench/verify_metacat.sh <name>` and fix until identical.
5. Re-run **all** probes before committing; later layers change earlier ones.
6. Commit with what the differential test caught.

Add new probe names to the `verify_metacat.sh` invocation; the script takes
names as arguments.

---

## 5. Traps already paid for — do not rediscover these

Each of these was a real bug caught only by byte-comparison. None were visible
by reading the code.

- **Exact arithmetic is load-bearing.** `(% n)` is `(/ n 100)` — an exact
  *rational*, not a float, and those values flow through activations, link
  lengths and probability thresholds. `schemenum.jl` reproduces Scheme's
  numeric tower (`sdiv`, `ssqrt`, `sexpt`, `sround`). Never use `Float64`
  where the Scheme is exact; it drifts and eventually branches differently.
- **Chez evaluates procedure arguments RIGHT TO LEFT.** A call drawing two
  random numbers draws the rightmost first. Nothing has tripped on this yet,
  but it will in denser codelet code.
- **Lists are CONSed**, so link lists, descriptions and codelet lists come out
  in *reverse* declaration order — and the model reads the first match out of
  them. Use `pushfirst!`.
- **`remove-duplicates-pred` keeps the LAST** of each duplicate group, not the
  first.
- **`stochastic-if*` always draws** a random number; `prob?` short-circuits
  without drawing at 0 and 1. Getting this wrong desynchronises the stream
  even when the decision is the same.
- **`middle-in-string?` is not positional arithmetic.** It asks whether the
  *ungrouped* left neighbour is the string's leftmost and the right neighbour
  its rightmost. `isodd(n) && pos == n÷2` agrees for 3-letter strings and
  diverges at 5. Probe with odd lengths ≥ 5.
- **Neighbour lists include edge-groups**, so they change as groups get built.
- **`update-workspace-values` updates STRUCTURES before OBJECTS** (bonds, then
  groups, then bridges/rules), because object unhappiness reads the strength of
  the bonds and group enclosing it.
- **`get-local-density` consumes random draws** — it reads like a plain
  traversal but walks via `choose-left-neighbor`, a stochastic pick.
- **The bridge constructor does NOT call `set-concept-mappings`.** It starts
  with bond-CMs empty, all-CMs equal to the list passed in, and *no* symmetric
  slippages; those are filled in later at propose/build time.
- **`top-down-group-scout:category` has a `return` at the OUTER level** — a
  failed first check always ends the codelet, even though the code appears to
  check the other side first. (This one bit the Copycat port too.)
- **`group-builder`'s `continue` skips the cursor update** for
  `previous`/`next_object`.
- **`bottom-up-bond-scout` chooses over ALL workspace objects**, not per string.
- **A bridge's `add-concept-mappings` PREPENDS** (`(append cm-list concept-mappings)`),
  and so do `add-bond-concept-mapping` and `add-symmetric-slippage`. The first
  port used `push!`; the bridge codelet probe caught it.
- **`delete-concept-mapping-type` selects the mapping out of ALL-CMs but
  removes it only from all-CMs and concept-mappings** — a bond CM deleted this
  way stays in `bond-concept-mappings`. Preserved as-is.
- **An enclosing group's bridge discharges half an object's inter-string
  unhappiness EXACTLY**: `(100- (* 1/2 strength))` is a rational, so the
  unhappiness fields cannot be `Int`.
- **Mapping strengths can be INEXACT.** `(100* (tanh (* 1/40 raw)))` is
  `(round (* 100 <flonum>))`, which in Scheme is a flonum. Convert the exact
  ratio (`float(raw // 40)`) rather than multiplying by a float `1/40`; the two
  differ in the last bit. Probe output has to normalise the exactness
  (`inexact->exact`) or the two sides print `93.0` against `93`.
- **`stochastic-pick-by-method` does NOT temperature-adjust its weights**,
  unlike a string's `choose-object`. `important-object-bridge-scout` uses both,
  three lines apart.
- **`propose-bridge` uses ALL of a string-spanning group's descriptions** and
  only the relevant ones for anything else. This is a deliberate hack, commented
  at length in `bridges.ss`: without it an inactive Direction-Category leaves a
  spanning bridge with no direction mapping, so it is not judged incompatible
  with the sub-bridges it contradicts and both survive.
- **A flipped group keeps the original's id-num** so bridges to it hash to the
  same slot of the proposed-bridge table — but `add-group` assigns a fresh one
  when the flipped group is actually built.
- **`reverse-direction-orientation?` needs EVERY reversible CM to be Opposite.**
  Between two spanning groups that means opposite group category *and* opposite
  direction, which only happens when one group was scanned right-to-left. A
  probe that builds both groups left-to-right never reaches the flip path at
  all — `bench/metacat_bridgecodelets_probe.*` builds the target string's group
  backwards for exactly this reason.

---

## 6. What's next, in order

**~10,700 lines of Scheme remain.** Suggested order, with the reasoning:

1. **`themes.ss` (1,235)** — do this first. It is on the critical path, not
   optional: every workspace structure's strength is weighted by its thematic
   compatibility, which is 0 *only while no themes exist*. The current probes
   hold that condition, which is why the ported layers agree. A real run creates
   themes as soon as bridges start boosting them, so no end-to-end comparison
   means anything until themes are in. Ported layers currently hardcode
   `get_thematic_compatibility(...) = 0` — grep for that and replace.
2. **Description and group codelets** (`descriptions.ss` 205, plus the codelet
   bodies in `groups.ss`) — small, and they follow the exact
   scout → evaluator → builder shape already ported for bonds and bridges in
   `codelets_bonds.jl` / `codelets_bridges.jl`. Use those as the template.
   These are now the *only* thing blocking a bridge between objects of
   different lengths: `propose-bridge` posts a `top-down-description-scout` and
   a `top-down-group-scout:category` in that case, and both are registered in
   `codelets_bridges.jl` as stubs that raise. Also bring back
   `get_incompatible_bridges(::Group, ...)`, which group-builder needs — it was
   left out here rather than shipped unverified. `propose-singleton-group` and
   `try-to-propose-singleton-group` in `bridges.ss` have no callers anywhere in
   the model; they are dead code, not an omission.
3. **`rules.ss` (2,163) and `answers.ss` (1,558)** — needed for a run to reach
   an answer. `rules.ss` also needs the transform/apply half of `images.ss`,
   which is deliberately not ported (`images.jl` is the data structure only).
4. **`trace.ss` (1,672), `memory.ss` (586), `jootsing.ss` (344),
   `justify.ss` (352)** — the self-watching layers the paper is actually about.
5. **The run loop** (`run.ss`, ~350) — then end-to-end comparison becomes
   possible, and `bench/metacat_bench.{ss,jl}` becomes meaningful.

`breakers.ss` (47) can go in any time.

---

## 7. Repo map

```
julia/src/            Copycat port (complete)
julia/src/metacat/    Metacat port (in progress)
python/               Copycat reference, MIT, vendored
scheme/metacat/       Metacat reference, GPL-2, vendored
scheme/headless/      makes Metacat run without its SWL GUI
bench/                runners, probe pairs, verifiers, benchmarks
results/              Copycat benchmark + verification output
README.md             project overview and results
scheme/README.md      how the headless harness works and why
```

### Licences — they differ

Copycat is **MIT** (`python/LICENSE.upstream`); the Julia Copycat port carries
that. Metacat is **GPL-2** (`scheme/metacat/LICENSE.upstream`), so
`julia/src/metacat/` is a derivative work and is **GPL-2**. Keep them distinct.

### Two mechanical patches to the vendored Metacat

Needed to load under Chez 9; the model is otherwise untouched.

- `utilities.ss` redefines `truncate`/`ceiling`/`floor`/`round` in terms of
  themselves; Chez 9 forbids that, so they capture `%chez-*` aliases from the
  prelude.
- Chez 9's reader rejects `#` inside symbols. The five affected symbols all
  ended in `id#` and were renamed to `id-num` throughout.

---

## 8. Benchmarks

Copycat is fully benchmarked (`results/benchmark.json`, table in `README.md`):
**7.5x** over 1.4M codelets, range 3.3x–11.3x per problem.

Metacat has a harness (`bench/metacat_bench.{ss,jl}`) covering the ported
layers with matching checksums, but the numbers are **micro-benchmarks of
layers, not of the model**, and should not be quoted as "Metacat in Julia is
Nx faster". Wait for the run loop.
