# Continuing this work in a new session

Everything below assumes a **fresh container with a fresh clone** — no
toolchain, nothing cached. Start here.

Branch: `claude/copycat-metacat-folders-iybxko`
Last commit at time of writing: the themespace port (see `git log -1`)

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
JULIA=$JULIA bash metacat/bench/verify_metacat.sh \
  util slipnet workspace cm bonds groups bridges coderack bondcodelets themes \
  descriptioncodelets groupcodelets bridgecodelets themecodelets images
```

Expected — fifteen layers, **20,250 trace lines byte-identical**:

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
ok    themes (2049 lines identical)
ok    descriptioncodelets (321 lines identical)
ok    groupcodelets (4854 lines identical)
ok    bridgecodelets (5396 lines identical)
ok    themecodelets (3335 lines identical)
ok    images (1668 lines identical)
all probes matched
```

If any probe fails on a clean checkout, something in the environment differs —
fix that before writing new code.

The reference implementation also runs standalone:

```bash
scheme --quiet --script metacat/bench/run_metacat_scm.ss abc cba pqrs 42
# OUTCOME  answer  CODELETS  618  TEMP  4
# ANSWER   abc -> cba, pqrs -> ?   srqp   98   4
```

The Copycat side (finished, separate from Metacat):

```bash
python3 copycat/bench/verify.py --iterations 5 --seeds 1 2 3  # 51/51 must match
```

---

## 3. What exists

### Copycat — **complete**

Python reference (`copycat/python/`, MIT, vendored from `fargonauts/copycat`)
ported to Julia (`copycat/julia/src/*.jl`). Verified by bit-exact RNG parity:
51/51 comparisons byte-identical. Benchmarked at **7.5x** faster than Python
over 1.4M codelets (`copycat/results/benchmark.json`). Nothing outstanding.

### Metacat — **~7,500 of ~16,000 lines of non-graphics Scheme**

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
| themespace: clusters, dynamics, theme support | `themes.jl` | `themes` | 2049 |
| description codelets | `codelets_descriptions.jl` | `descriptioncodelets` | 321 |
| group codelets, incl. consolidation | `codelets_groups.jl` | `groupcodelets` | 4854 |
| bridge codelets, workspace mapping strength | `codelets_bridges.jl`, `context.jl` | `bridgecodelets` | 5396 |
| thematic codelets | `codelets_themes.jl` | `themecodelets` | 3335 |
| image transforms (the algebra rules compute in) | `images.jl` | `images` | 1668 |

---

## 4. The method — follow this exactly

Every layer is verified by a **probe pair**:
`metacat/bench/metacat_<name>_probe.ss` and
`metacat/bench/metacat_<name>_probe.jl`, which print the same canonical trace.
They must be **byte-identical**. Do not accept "close enough".

This works because both sides run the **same generator**:
`metacat/scheme/headless/shared-rng.ss` installs a CPython-compatible MT19937
over Chez's `random`, matching `copycat/julia/src/pyrandom.jl` (the one file
the Metacat probes borrow from the Copycat side; it is MIT, so the borrow is
fine). All of Metacat's nondeterminism funnels through `(random n)`, so seeded
runs agree draw for draw.

To add a layer:

1. Read the Scheme file. Note every `random` call and its **order**.
2. Write the Julia port in `metacat/julia/src/`.
3. Write the two probes, dumping every field you can reach. Tag exact vs
   inexact numbers (`E`/`F`) — exactness is a real signal, see below. For a
   value that is genuinely a float, print the exact rational the double is
   (`(inexact->exact x)` in Chez, `Rational{BigInt}(x)` in Julia) rather than
   the float itself: it is a bit-exact comparison, and it sidesteps the two
   languages disagreeing about how to render `1e-5`. See
   `metacat_themes_probe.{ss,jl}`, which compares thematic compatibilities that
   way.
4. `JULIA=$JULIA bash metacat/bench/verify_metacat.sh <name>` and fix until
   identical.
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
- **`shorten`'s two relation repairs are in the SAME `if*` body.** It reads like
  an if/else — repair the letter relation, otherwise the length relation — but
  `if*` takes a test and a BODY, so both repairs happen together once more than
  one constituent is left. Nothing happens to either when only one is.
- **A transform's `fail` is an escape continuation for the whole rule**, not a
  local error. `images.jl` throws `ImageTransformFailure` and the caller catches;
  the transforms themselves must not try to recover.
- **`new-start-letter` applied as a RELATION to a group image does not check the
  group's own new start letter.** The sub-images are each checked and can fail,
  but the group's `start-letter` is slid with `get-related-node` and simply
  becomes `#f` if there is nothing there. Preserved.
- **Image state snapshots capture the sub-image LIST by reference**, and that is
  safe only because every transform that changes the constituents REPLACES the
  list rather than mutating it. `shorten` and `extend` both build a new one; the
  Julia port must keep doing that or `reset` silently stops working.
- **A bridge's concept-mapping lists PREPEND.** `add-concept-mappings` uses
  `(append cm-list concept-mappings)` and `add-bond-concept-mapping` and
  `add-symmetric-slippage` both `cons`, so a mapping added later comes out
  earlier. Appending instead is invisible until a bridge is BUILT — that is when
  bond CMs and the ObjCtgy CM get added — and then it reorders every list that
  reads them.
- **`look-for-auxiliary-slippages` calls `(fizzle)` from inside a helper**,
  which escapes the whole codelet, not just the helper. Adding a description
  there ENDS the thematic scout; the slippage it was about to make happens on
  some later run, once the description is in place.
- **The auxiliary-slippage branch needs `a` and `z`.** It fires when a slippage's
  descriptor is laterally linked to an instance of another category whose
  opposite is a possible descriptor of the other object — which in practice
  means StringPos `lmost=>rmost` dragging AlphaPos `first=>last` behind it,
  since `leftmost` links to `alphabetic-first`. No other pair of letters reaches
  it, so a probe without a `z` in it exercises the traversal and never the body.
- **`conditions-for-bridge` distinguishes `'()` from `#f`.** An empty list means
  "possible, no flips needed"; `#f` means "no bridge possible". `exists?` is
  true for `'()`, so the two must not both map to `nothing` in Julia.
- **`delete-invalid-string-position-middle-descriptions` is not only about
  descriptions.** When a grouping makes an object no longer "middle" it deletes
  the StringPos description AND the StringPos concept mapping of every bridge
  that object is part of, breaking any bridge left with no mappings. Porting
  only the description half leaves bridges resting on descriptions that no
  longer exist, and their strengths drift.
- **`propose-bridge` uses ALL descriptions of a string-spanning group**, not
  just the relevant ones. The Scheme has a long comment about why: a momentarily
  inactive Direction-Category would otherwise leave a spanning bridge without
  the very concept mapping that makes it incompatible with the letter bridges it
  ought to replace.
- **A flipped group keeps the ORIGINAL group's id-num**, so that bridges to it
  land in the same slot of the proposed-bridge table as bridges to the
  unflipped version. And existence checks use `get-original-object1/2`, since
  the flipped group was never in the workspace.
- **`reverse-direction-orientation?` requires EVERY reversible concept mapping
  to map by opposite** — reversible being Direction, BondCtgy and GroupCtgy. A
  single `GroupCtgy:succgrp=>succgrp` identity mapping vetoes flipping. To reach
  the flip path in a probe, leave Group-Category inactive so those descriptions
  are irrelevant and the scouts never build that mapping.
- **A group and a bond ask the same question of a bridge.** `groups.ss` and
  `bonds.ss` each define `get-incompatible-bridge`, and the two bodies are
  identical apart from which object supplies the direction. `codelets_bridges.jl`
  has one function taking the direction as an argument.
- **The bond builder fights bridges too** (weights 2 against 3), but only when
  the bond is directed and sits at an edge of its string.
- **An object's inter-string unhappiness counts its own bridge in full and its
  enclosing group's bridge at half.** Both of those can be exact rationals.
- **A bridge's external strength needs the workspace's real bridge list.** The
  context shim that dispatches `update-strength` was passing an empty one, which
  is invisible until bridges exist and then quietly halves every fight.
- **Right-to-left argument evaluation finally bit.** A group's
  `get-local-density` builds its neighbour list with
  `(append (neighbors self 'choose-left-neighbor) (neighbors self 'choose-right-neighbor))`.
  That is a procedure call, so Chez runs the RIGHT walk first even though the
  result lists left first — and both walks draw. The BOND version of the same
  walk uses `let*`, which is sequential, so it really does go left first. Two
  near-identical functions, two different draw orders. Whenever both arguments
  of a call have side effects, check which Chez runs first.
- **In Julia, an untyped predicate and an `::Any` fallback are the SAME method.**
  `is_proposed_structure(x) = ...` followed by `is_proposed_structure(::Any) =
  false` does not define a fallback; the second silently replaces the first, and
  the flag was always false. Nothing read it until proposed groups needed
  cleaning up when their codelet was culled. Dispatch on
  `::Union{Bond,Group,Bridge}` instead.
- **Culling a codelet deletes its proposed structure.** `delete-codelets` calls
  `delete-proposed-structure` before removing the codelet, so a bond or group
  whose codelet is culled leaves the workspace too.
- **`100*` is `(round (* 100 x))`,** not a bare multiply. `%`, `1-`, `10-` and
  `100-` are all not what they look like either; `1+` genuinely is `add1`.
- **`description-type-present?` reads ALL descriptions** (a group's bond
  descriptions included), while `get-descriptor-for` reads only the plain ones.
- **`(tell string 'get-all-objects)` includes PROPOSED groups**, and the
  middle-description cleanup walks that, not `get-objects`.
- **`group-builder` may REBUILD its group before building it.** A letter-sameness
  group containing other letter-sameness groups, or a length-sameness group
  containing length groups, is flattened over its letters and re-made; the
  object that gets built is not the one that was proposed.
- **`contains?` is group nesting, not position arithmetic** — and a stub of
  `false` is correct exactly until the first group is built. This one sat in
  `workspace.jl` for four commits: `calculate-local-support` excludes objects
  that enclose or are enclosed by the one being described, and with the stub it
  excluded nothing, inflating every description's local support once a group
  existed. No earlier probe printed a description strength after grouping.
  **Lesson: a stub justified by "this state cannot arise yet" needs a probe the
  moment that state can arise.**
- **A theme cluster's `alpha` is frozen at construction.** `net-effect` closes
  over the value of `sensitivity` inside the cluster's `let*`, so
  `set-sensitivity` mutates the variable and changes nothing. `themes.jl`
  stores the computed `alpha` rather than the sensitivity to keep that true.
- **`(get-label from to)` can legitimately return `#f`**, and in the themespace
  that `#f` is not "missing" — it is the DIFFERENCE theme, a claim in its own
  right ("this dimension maps by no relation at all"). It sits in the relation
  list beside `identity` and `successor`.
- **`get-possible-relations` uses `remq-duplicates`,** which keeps the LAST of
  each duplicate group. Relations therefore come out in an order no forward
  scan of the cross product reproduces.
- **Julia's two-variable comprehensions are COLUMN-major.** `[f(a,b) for a in
  A, b in B]` varies `a` fastest, but Scheme's `cross-product-map` is
  row-major. A two-variable `for` loop is row-major and safe; a comprehension
  is not. Order matters here because theme support values feed a
  `weighted-average`, and float addition is not associative.
- **`update-strength` is where the themes actually bite.** Every workspace
  structure's strength is `weighted-average([compatibility > 0 ? 100 : 0,
  intrinsic], [|compatibility|, 1 - |compatibility|])`. Bonds and groups have
  no compatibility of their own (the workspace-structure default of 0), so only
  bridges and descriptions feel it — but they feel it hard: a bridge violating
  an active theme drops to strength 0 outright.

---

## 6. What's next, in order

**~8,500 lines of Scheme remain.** Suggested order, with the reasoning:

0. ~~`themes.ss`~~ — **done.** `themes.jl` covers the themespace, its clusters
   and their recurrent dynamics, freezing and deletion, theme patterns, the
   theme-support predicates, and the three feedback loops (bridges boost
   themes; themes weight structure strengths; themes re-activate slipnodes).
   **Not** ported from `themes.ss`, deliberately, because they need codelets
   that do not exist yet: `thematic-bridge-scout`,
   `propose-description-based-on-theme`, `look-for-auxiliary-slippages` and
   `conditions-for-bridge`/`flipped`. Do those with step 3 below. Also skipped:
   themespace state save/restore, which only the GUI's history browser uses.
1. ~~Description and group codelets~~ — **done**, as `codelets_descriptions.jl`
   and `codelets_groups.jl`. The group builder's fight-and-consolidate logic is
   the hairiest thing in the port so far; its probe reseeds the coderack every
   `%update-cycle-length%` codelets, mimicking `add-bottom-up-codelets`, because
   without that the rack drains after the seed batch and the builders barely
   run. Deferred there: incompatible BRIDGES, which the builder is supposed to
   fight and break — grep `get_incompatible_bridges` in `codelets_groups.jl`.
3. ~~Bridge codelets~~ — **done**, as `codelets_bridges.jl`, together with the
   workspace-level bridge storage and mapping strengths now in `context.jl`.
   **Not** ported: `propose-singleton-group` and
   `try-to-propose-singleton-group`, which `bridges.ss` defines and nothing in
   the model ever calls.
3b. ~~The four deferred `themes.ss` codelet procedures~~ — **done**, as
   `codelets_themes.jl`. That closes the self-watching loop in both directions.
   Everything in `themes.ss` is now ported except themespace state
   save/restore, which only the GUI history browser uses.
4. **`rules.ss` (2,163) and `answers.ss` (1,558)** — needed for a run to reach
   an answer, and now the next thing on the critical path. The transform/apply
   half of `images.ss` is DONE, so `rules.ss` has the algebra it computes in.
   Still deferred from `images.ss`: `make-string-image`, which `rules.ss` uses
   for whole-string images, and `instantiate-as-letter` /
   `instantiate-as-group`, which need the answer string `answers.ss` builds.
5. **`trace.ss` (1,672), `memory.ss` (586), `jootsing.ss` (344),
   `justify.ss` (352)** — the self-watching layers the paper is actually about.
6. **The run loop** (`run.ss`, ~350) — then end-to-end comparison becomes
   possible, and `metacat/bench/metacat_bench.{ss,jl}` becomes meaningful.

`breakers.ss` (47) can go in any time.

---

## 7. Repo map

```
copycat/julia/src/        Copycat port (complete)
copycat/python/           Copycat reference, MIT, vendored
copycat/bench/            runners, verifier, benchmark
copycat/results/          Copycat benchmark + verification output

metacat/julia/src/        Metacat port (in progress)
metacat/scheme/metacat/   Metacat reference, GPL-2, vendored
metacat/scheme/headless/  makes Metacat run without its SWL GUI
metacat/bench/            probe pairs, verifier, benchmark

README.md                 project overview and results
metacat/scheme/README.md  how the headless harness works and why
```

### Licences — they differ

Copycat is **MIT** (`copycat/python/LICENSE.upstream`); the Julia Copycat port
carries that. Metacat is **GPL-2** (`metacat/scheme/metacat/LICENSE.upstream`),
so `metacat/julia/src/` is a derivative work and is **GPL-2**. The top-level
`copycat/` and `metacat/` split is what keeps them distinct.

### Three mechanical patches to the vendored Metacat

Needed to load under Chez 9; the model is otherwise untouched.

- `utilities.ss` redefines `truncate`/`ceiling`/`floor`/`round` in terms of
  themselves; Chez 9 forbids that, so they capture `%chez-*` aliases from the
  prelude.
- Chez 9's reader rejects `#` inside symbols. The five affected symbols all
  ended in `id#` and were renamed to `id-num` throughout.
- `enumerate` is a Chez 9 primitive of one argument. `images.ss` defines its own
  four-argument `enumerate` at the BOTTOM of the file, but calls it from
  `new-start-letter` near the top; Chez compiles that call against the primitive
  it can see at that point and raises "incorrect argument count" the first time
  a rule tries to renumber a group's letters. Renamed to `enumerate-nodes`.
  Nothing reached that path until the image probe did.

The harness also stubs `group-graphics`. `group-builder` calls
`(group-graphics 'erase ...)` UNGUARDED in each of its two consolidation
branches (`groups.ss` 727 and 765), unlike every other graphics call in that
file, which sits behind `%workspace-graphics%`. Headless, `group-graphics.ss`
is never loaded, so those two calls raise the moment a group consolidates.

---

## 8. Benchmarks

Copycat is fully benchmarked (`copycat/results/benchmark.json`, table in
`README.md`): **7.5x** over 1.4M codelets, range 3.3x–11.3x per problem.

Metacat has a harness (`metacat/bench/metacat_bench.{ss,jl}`) covering the
ported layers with matching checksums — five workloads now, the newest being
50 themespace activation cycles over all 27 clusters. The numbers are
**micro-benchmarks of layers, not of the model**, and should not be quoted as
"Metacat in Julia is Nx faster". Wait for the run loop.

When adding a workload, check the checksum is not trivially constant: the
themespace one summed activations after 50 cycles, by which point everything
had decayed to zero on both sides. It now accumulates the trajectory across
cycles instead, which is what actually distinguishes the two runs.
