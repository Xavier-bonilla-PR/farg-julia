# Continuing this work in a new session

Everything below assumes a **fresh container with a fresh clone** — no
toolchain, nothing cached. Start here.

**Branch:** `claude/copycat-metacat-folders-iybxko` — on the GitHub remote
`Xavier-bonilla-PR/farg-julia`. All work goes here; do not push elsewhere.

**State at time of writing:** **the whole model runs.** `run-problem` — the
same entry point the reference runner uses — initializes Metacat, posts its own
codelets, runs until it finds an answer, gives up or hits a codelet budget, and
records what it concluded in its episodic memory, and the Julia port matches the
Scheme run for run: same answers, same codelet counts, same temperatures, same
trace, same memory, on runs of 1,400 codelets with reminding live.
`trace.ss`, `jootsing.ss`, `answers.ss` step (C) and the run.ss loop are
COMPLETE, and `%self-watching-enabled%` is ON, which is the model's real
configuration. The tree is clean and `origin` is in sync. **Thirty-one probes,
39,543 trace lines byte-identical** — confirmed by a full re-run on this exact
tree.

The `run` probe is the strongest test in the project, and the only one that
drives nothing itself: it calls `run-problem` and compares what Metacat did.
The `runloop` probe is the second strongest — it chooses a codelet, runs it,
updates everything, and repeats, dumping the whole model state every N cycles.
Between them they found the four bugs in section 5 that nothing else could
reach: the re-stamped codelet, the leaked codelet-type clamp, the rebuilt group
that costs a rule its support, and the rule whose strength was never updated.

**Next up:** `answers.ss` step (D) (the commentary, ~830) and the
`answer-justifier` codelet that is the rest of `justify.ss` (~160). After that
the port is feature-complete against the non-graphics model, and
`metacat/bench/metacat_bench.{ss,jl}` can be rewritten to measure the model
rather than its layers.

**Toolchain this state was verified against** (section 1 installs exactly
these): Chez Scheme **9.5.8**, Julia **1.10.9**, Python **3.11.15**. The Julia
version is not incidental — the s3 URL in section 1 pins it, and the probes
compare bit-exact floating point.

**First thing to do in a new session:** section 1 (install the toolchain), then
section 2 (run the suite). Do not write code until all thirty-one probes match on
the clean checkout.

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
  descriptioncodelets groupcodelets bridgecodelets themecodelets images rules \
  ruleapply ruleabstract rulecodelets ruletranslate transstring memory \
  patterns trace justify wsevents swevents monitors abstract runloop run
```

Expected — thirty-one layers, **39,543 trace lines byte-identical**:

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
ok    rules (4620 lines identical)
ok    ruleapply (1993 lines identical)
ok    ruleabstract (1709 lines identical)
ok    rulecodelets (3280 lines identical)
ok    ruletranslate (1449 lines identical)
ok    transstring (974 lines identical)
ok    memory (505 lines identical)
ok    patterns (334 lines identical)
ok    trace (597 lines identical)
ok    justify (289 lines identical)
ok    wsevents (1828 lines identical)
ok    swevents (453 lines identical)
ok    monitors (808 lines identical)
ok    abstract (119 lines identical)
ok    runloop (246 lines identical)
ok    run (89 lines identical)
all probes matched
```

The whole suite takes about four minutes; `groupcodelets`, `bridgecodelets`
and `themecodelets` are the slow ones, because each runs a real coderack on
both sides.

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
JULIA=$JULIA python3 copycat/bench/verify.py --iterations 5 --seeds 1 2 3
# 51/51 must match. NB the JULIA prefix: verify.py defaults to plain `julia`
# on PATH, which does not exist in a fresh container. Takes a few minutes.
```

---

## 3. What exists

### Copycat — **complete**

Python reference (`copycat/python/`, MIT, vendored from `fargonauts/copycat`)
ported to Julia (`copycat/julia/src/*.jl`). Verified by bit-exact RNG parity:
51/51 comparisons byte-identical. Benchmarked at **7.5x** faster than Python
over 1.4M codelets (`copycat/results/benchmark.json`). Nothing outstanding.

### Metacat — **~1,000 lines of non-graphics Scheme left**, all of it `answers.ss` step (D) (the commentary) and the `answer-justifier` codelet: everything else, `run.ss` included, is in

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
| rule structure, English transcription, quality | `rules.jl` | `rules` | 4620 |
| change descriptions, rule application | `rules.jl`, `images.jl` | `ruleapply` | 1993 |
| rule abstraction: schemas, swaps, templates | `rules.jl` | `ruleabstract` | 1709 |
| the rule codelets, and the workspace's rules | `rules.jl`, `context.jl` | `rulecodelets` | 3280 |
| rule translation: slippage log, coattails | `answers.jl` | `ruletranslate` | 1449 |
| the translated string, instantiated from an image | `answers.jl`, `images.jl` | `transstring` | 974 |
| episodic memory: answer/snag descriptions, distance | `memory.jl` | `memory` | 505 |
| trace patterns and the clamping they drive | `trace.jl` | `patterns` | 334 |
| the temporal trace and its generic event | `trace.jl` | `trace` | 597 |
| rule unification and the slippages it yields | `justify.jl` | `justify` | 289 |
| the workspace concrete events (group, cm, ...) | `trace.jl` | `wsevents` | 1828 |
| the self-watching events (answer, clamp, snag) | `trace.jl` | `swevents` | 453 |
| the trace monitors and their importance tests | `trace.jl` | `monitors` | 808 |
| memory's two trace-reading abstractors | `memory.jl` | `abstract` | 119 |
| **the run loop, self-watching ON** | `run.jl`, `codelets_jootsing.jl`, `codelets_breaker.jl` | `runloop` | 246 |
| **the whole model, driven by `run-problem`** | `run.jl` (`init-mcat`, `step-mcat`, `run-mcat`) | `run` | 89 |

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
  random numbers draws the rightmost first. This has bitten repeatedly: a
  group's local-density walk, `pairwise-map`'s recursion, and — through the
  implementation of `map` and `sort` — the order transforms and picks are
  applied in. Assume it applies to every call whose arguments have effects.
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
- **Chez's `map` does NOT apply its procedure left to right.** It recurses on
  the tail-but-two before applying the procedure to the first two elements, so
  it works the list in pairs from the END backwards, left to right within each
  pair: `(1 2 3 4 5)` is applied in the order `5 3 4 1 2`. Invisible for a pure
  procedure; decisive for one with an effect or one that can escape. It is what
  decides how much of a group image has already been changed when
  `new-start-letter` walks off the end of the alphabet part-way through.
  `for-each` (Metacat's `for*`) IS left to right. `chez_map` in `utilities.jl`
  reproduces the order; `chez_map_order` gives it for any length.
- **Chez's `map` order bites again wherever the mapped procedure DRAWS.**
  `instantiate-rule-clause-template` maps over the change templates and over
  the reference objects, and both of those pick stochastically. The two sides
  then consume exactly the same number of draws and still make different
  choices, because the draws are handed out in a different order — which makes
  an RNG-state fingerprint look identical at every checkpoint while the picks
  disagree. When a trace diverges only in what was CHOSEN and the generator
  state agrees on both sides, suspect `map` order, not the stream.
- **`pairwise-map` applies its procedure from the deepest suffix outwards**,
  because Chez evaluates `append`'s arguments right to left and the recursive
  call is the second one. The RESULT is still in plain i<j order — it is only
  the timing that differs, and it decides which conflicting pair
  `check-for-conflicts` reports before it escapes. `pairwise_apply_order` in
  `utilities.jl`.
- **`partition` appends a new class at the END, not the front.** It partitions
  the tail and then inserts the head into the first class all of whose members
  it matches, or, failing that, at the end of the list of classes. With a
  predicate nothing matches across, `(a b c)` comes back as `((c) (b) (a))`.
  Getting this backwards put every rule's transforms in the wrong order.
- **Chez's `sort` splits at `n >> 1` with the LEFT half short and sorts the
  RIGHT half first** (procedure arguments, again), merging in favour of the
  left list on a tie. For a predicate that is a strict weak ordering none of
  that shows. `apply-before?` in `rules.ss` is deliberately NOT transitive, so
  for it the algorithm IS the specification: use `chez_sort` in `utilities.jl`,
  not Julia's `MergeSort`, which splits the other way.
- **`(100- (* 1/2 strength))` is an exact rational.** An object with no bridge
  of its own but whose ENCLOSING GROUP has one takes half that bridge's
  strength, which is a ratio whenever the strength is odd. The port typed the
  inter-string unhappiness fields as `Int` and only found out when a rule
  abstraction run finally built that configuration.
- **A letter's image is made ONCE, at construction.** It is a mutable object
  that rule application transforms in place and that the letter's enclosing
  groups hold a reference to. Rebuilding it on each `get-image` — which the
  port did, harmlessly, while only group construction ever asked — makes every
  transform apply to a fresh copy that nothing ever reads again. The fourth
  stub-shaped bug of the same family.
- **A `record-case` with no matching arm returns Chez's unspecified value,
  which is TRUE.** `literal-clause?` in `rules.ss` has arms for the intrinsic
  and extrinsic clauses only, so a verbatim clause falls off the end and the
  caller sees a truthy result. `rules.jl` returns `true` there deliberately;
  returning `false` (the natural reading) diverges. Check every `record-case`
  and `case` in the Scheme for a missing `else` before assuming the fall-through
  is a no-op.
- **`(average l)` is 0 for an empty list, and `(product '())` is 1.** Both come
  up in the rule quality formulas, where a rule with no intrinsic clauses or no
  swap dimensions leaves a list empty. `savg` and `prod(...; init = 1)` in
  `rules.jl` match.
- **The transcription's line width is computed, not fixed.** Each phrase is
  split into the fewest lines that keep it under 60 characters, and the widest
  of those quotients then sets the width for *every* phrase in the rule. Wrap
  at a constant 60 and the output differs on any rule with more than one clause.
- **A codelet that changes bins is RE-STAMPED.** `set-urgency` moves a codelet
  by calling the destination bin's `add-codelet`, and `add-codelet` ends with
  `(tell codelet 'set-time-stamp)` — so the codelet's time stamp becomes the
  current `*codelet-count*`. Its removal weight is `(- *codelet-count*
  time-stamp)`, which is then zero, so clamping a codelet pattern does not
  merely raise some urgencies: it makes every codelet it MOVED temporarily
  immune to being culled, and that changes which codelets the next
  `delete-codelets` throws away. The port carried the old stamp across the move
  — tidier, and wrong within one cycle of the first clamp. This was the last
  divergence in the `runloop` probe, and it is the shape to remember: **equal
  draw counts, equal draw values, equal workspace, different coderack.** When
  the generator agrees and the *composition* does not, the difference is in a
  non-drawing bookkeeping field, not in a decision.
- **`(tell *coderack* 'initialize)` unclamps every codelet TYPE.** Codelet
  types are global and outlive any one coderack, so a clamp left standing at
  the end of one run carries into the next. A probe that runs several problems
  in sequence and builds a fresh `Coderack()` for each is not enough: it has to
  call `initialize!` too, or problem *n+1* starts with problem *n*'s urgencies.
- **`get-equivalent-object` is not an identity test.** A group that has been
  REBUILT — by consolidation, or by a group-builder replacing a coincident one
  — is a different object occupying the same slot, and the string finds it
  through its group vector and accepts it if category, direction and length all
  agree. That is what keeps a rule SUPPORTED across a rebuild of a group its
  bridge rests on, and so what keeps the temperature down. The port read it as
  "is this object still in the string", which is right until the first rebuild
  and then silently costs every dependent rule its support.
- **RULES are workspace structures, so `update-workspace-values` updates their
  strength too.** A rule's strength is its quality RELATIVE to the other rules
  of its type, so two rules of quality 90 and 99 have strengths 50 and 100 —
  and the answer-finder weights its choice of rule by strength. Leaving
  `strength` at whatever it was when the rule was built reads as plausible
  (90 and 99 are, after all, the right ORDER) right up to the first codelet
  that has to choose between two rules, which in the `run` probe was codelet
  1173 of the sixth problem. Iterate `get_structures`, not a hand-written list
  of the structure kinds you were thinking about.

---

## 6. What's next, in order

**~1,000 lines of Scheme remain**, across two files (`answers.ss` ~830 — the
commentary; `justify.ss` ~160 — the `answer-justifier` codelet only).
`trace.ss`, `jootsing.ss`, `breakers.ss`, `memory.ss` and `run.ss` are DONE.
Every step below is done except those two; the steps are kept for the "not
ported, deliberately" notes buried in them. **The live work is step 5's slice
(D) and the codelet at the end of step 6.**

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
   run. Incompatible BRIDGES, which the builder also has to fight and break,
   were deferred here and filled in with the bridge codelets in step 3.
3. ~~Bridge codelets~~ — **done**, as `codelets_bridges.jl`, together with the
   workspace-level bridge storage and mapping strengths now in `context.jl`.
   **Not** ported: `propose-singleton-group` and
   `try-to-propose-singleton-group`, which `bridges.ss` defines and nothing in
   the model ever calls.
3b. ~~The four deferred `themes.ss` codelet procedures~~ — **done**, as
   `codelets_themes.jl`. That closes the self-watching loop in both directions.
   Everything in `themes.ss` is now ported except themespace state
   save/restore, which only the GUI history browser uses.
4. **`rules.ss` (2,163)** — being ported in three commits, of which the first
   is **done**:
   - (A) ~~the rule structure, its English transcription and its quality
     metrics~~ — **done**, as `rules.jl`, probe `rules`. Clauses are built by
     hand in the probe straight from the grammar at the top of `rules.ss`, so
     every branch of the fourteen-case transcription table and every arm of the
     quality formulas is reached deliberately rather than hoped for.
   - (B) ~~rule application~~ — **done**, as the rest of `rules.jl`, probe
     `ruleapply`: change descriptions of both kinds and the implication
     heuristics they are compared by, then `apply-rule` down through
     `get-intrinsic-transforms`, plus `make-string-image` from `images.ss` and
     the letter/string image plumbing it needs. Applying a rule changes nothing
     in the workspace — what it changes is what the string LOOKS like under the
     rule, which is what has to be computed before anyone can ask whether the
     rule works.
   - (C) ~~abstraction~~ — **done**, probe `ruleabstract`:
     `abstract-change-descriptions` and its helpers, the schemas and swaps it
     reads off a cluster of bridges, and the rule-clause templates it groups
     them into, down to instantiating a rule and applying it. A rule is not
     composed but READ OFF the horizontal bridges, so the probe has to build a
     real workspace through the coderack first and then abstract from whatever
     the model happened to perceive.
   - (D) ~~the rule codelets~~ — **done**, probe `rulecodelets`:
     `rule-scout`, `rule-evaluator`, `rule-builder`, the workspace's rule
     storage, and the rule's own strength, support and revision methods.
     `rule-builder` posts `answer-finder`, which is `answers.ss`, so the probe
     drives the three codelets directly and records what they post rather than
     letting the coderack run it; the Julia `:answer_finder` type is registered
     with a procedure that raises, so it can be posted and counted but never
     silently no-ops.
   `rules.ss` is now complete apart from `set-translated-rule-information`,
   which needs the translated strings `jootsing.ss` builds.
5. **`answers.ss` (1,558)** — (A) and (B) are in, (C) is HALF done and no
   longer blocked, (D) is untouched. It is four separable pieces, in this order,
   because each later one needs the earlier:

   - **(A)** ~~rule translation~~ (`answers.ss` 1196-1558, ~360 lines) —
     **done**, as `answers.jl`, probe `ruletranslate`:
     `make-slippage-log`, `translate`, `translate-rule-clause`,
     `remove-redundant-ObjCtgy-change`, `translate-object-description`,
     `apply-to-change` / `apply-to-dimension` / `apply-to-object-description`,
     `valid-rule-clause?` and friends, plus `apply-slippages` on slipnodes and
     the coattail machinery it drives. The `rulecodelets` driver was reused as
     predicted. Because translation is stochastic, the probe translates the
     same rule EIGHT times from the same state rather than once.
     Configurations were chosen deliberately: `abc->abd :: kji` reaches the
     succ=>pred slippage that makes the classic answer, and `abc->abd :: cba`
     (seeds 501, 502) is the only shape found that reaches the COATTAIL branch,
     where a slippage drags a descriptor it does not map along a lateral
     sliplink. A translation FAILING (the `(fail)` escape) is still
     unexercised — no configuration tried produced one.
     **Not** ported: nothing from this section. `remove-redundant-ObjCtgy-change`
     IS ported but has zero call sites anywhere in Metacat, and its
     `record-case` returns void for a verbatim clause, so the probe feeds it
     only extrinsic and intrinsic ones.
   - **(B)** ~~the translated string~~ (1035-1195) — **done**, probe
     `transstring`: `make-translated-string`,
     `attach-length-to-appropriate-groups`, `make-translated-rule-bridges`,
     `irrelevant-translated-string-group?` and `get-rule-supporting-groups`.
     The two pieces deferred from `images.ss` came with it —
     `instantiate-as-letter` and `instantiate-as-group` — and
     `set-translated-rule-information` from `rules.ss` finally has something to
     work on. `get-equivalent-object` in `context.jl` is no longer a stub:
     `get-equivalent-letter` and `get-equivalent-group` finish it, which is what
     translated strings needed. `equivalent-workspace-objects?` was pulled
     forward from `trace.ss` (it has no trace dependencies), along with
     `get-real-object`.
     **Not** ported: `process-snag`, which needs `*trace*`, `make-snag-event`
     and `post-initial-codelets` — it goes with `trace.ss` slice (C). One trap
     worth keeping: `make-translated-string` ASSUMES the rule applies, and takes
     the `car` of a failed application, so the probe applies the rule first and
     skips on failure exactly as `answer-finder` does.
   - **(C) `answer-finder` and `report-new-answer`** (20-95, 929-1035) —
     **half done; nothing blocks the rest now that `trace.ss` is complete.**

     The MEMORY ABSTRACTORS half is **done**, probe `abstract`:
     `abstract-answer-description` and `abstract-snag-description` from
     memory.ss, plus the helpers they need from answers.ss's commentary half
     (108-265) — `most-recent-group-and-concept-mapping-events`,
     `abstract-answer-description-theme-pattern`,
     `get-theme-supporting-concept-mappings`, `get-unjustified-theme-pattern`,
     `answer-quality-phrase` — and `supports-theme-pattern?` on bridges,
     `select-extreme`, `partition` and `member-equal?` in utilities.
     These turn a moment into a memory: an event describes what happened in
     terms of the workspace that produced it, a description in terms that
     outlive it. They could not be done before slice (D), because
     `most-recent-group-and-concept-mapping-events` reads the group and
     concept-mapping events only the MONITORS raise.
     What the differential test caught here: `set-abstracted-rule-information`
     was assigning the themespace's dominant theme pattern to the rule WITHOUT
     the theme-type head, while `set-translated-rule-information` added one —
     so the same field had two shapes depending on how the rule was built.
     The Scheme's themespace accessor conses the head on; the port's singular
     accessor deliberately does not (see the load-order note), so the head has
     to be added at the call site. Nothing had read an abstracted rule's
     theme-pattern before, which is why it had gone unnoticed.
     Two Scheme quirks worth keeping: a snag-description exposes
     `get-translated-rule-phrases` but NO `get-rule-phrases`, though it stores
     both; and its `get-activation` is hardwired to 0, unlike an
     answer-description's, which is real. Also, `abstract-answer-description`
     comments the quality it stores as "relative quality" and then sends
     `get-quality`, which is ABSOLUTE. The comment is wrong, not the code.

     What REMAINS of (C) is the codelet body:
     `memory.ss` is ported (see below), so `answer-present?` is available.
     What remains is the codelet body, and reading it settles a question the
     plan left open: `answer-finder` ends by calling `report-new-answer`, and
     its snag path calls `process-snag`. BOTH need `*trace*` — answer events,
     `make-answer-event`, `update-everything`, `post-initial-codelets`. So
     `answer-finder` cannot be finished before step 6. Do `trace.ss` first and
     come back. `metacat/julia/src/rules.jl` still registers `:answer_finder`
     with a procedure that raises; replacing that is the signal it is done.

     `memory.ss` (586) is **done**, as `memory.jl`, probe `memory`: the store,
     answer and snag descriptions, `answer-present?` / `snag-present?` /
     `get-equivalent-snag`, the `compare` that activates a remembered answer a
     new one reminds it of, and `calculate-answer-distance` with everything it
     reads — `intersect-themes`, `get-snag-justified-themes`,
     `answer-incoherent?`, `theme-abstractness`, and
     `compare-rule-clause-lists` / `traverse-rule-clauses`, which have since
     moved to `justify.jl` — the file they came from — now that justify.ss has
     its own use for them.
     ~~**Not** ported: `abstract-answer-description` and
     `abstract-snag-description`~~ — **both done**, with `answers.ss` step (C);
     see there. Still not ported: the memory window.
   - **(D) the commentary** (95-928, ~830 lines): `explain`, `theme-phrases`,
     `compare-answers`, `get-answer-comparison-text` — the English prose
     Metacat writes about its own answers, and the part of the program the
     thesis is really about. Leaf-ish, and testable the same way the rule
     transcription was: build the structures by hand and compare the prose.
6. **`trace.ss` (1,672), `jootsing.ss` (344), `justify.ss` (352)** — the
   self-watching layers. `trace.ss` and `jootsing.ss` are **done**; only the
   `answer-justifier` codelet is left, in `justify.ss`.

   **`justify.ss` is half done**, as `justify.jl`, probe `justify`: the
   rule-clause traversal and the two procs that ride it, `unify-rules`,
   `get-unifying-slippages`, `remove-whole/single-concept-mappings`,
   `get-vertical-theme-pattern-to-clamp` and the two heuristics it applies
   (`add-direction-entry`, `replace-bond-category-entry`). Unification is pure
   structure — it never reads the workspace — so the probe writes its rule
   PAIRS by hand from the grammar, the way the `rules` probe writes its clause
   table, and walks every arm deliberately: identical nodes, slip-linked nodes,
   unrelated nodes, shape mismatches at each level (changes, clauses, scope
   symbols, clause kinds), the `'string`/plato-group special case both ways
   round, and verbatim rules, which unify with nothing.
   `compare-rule-clause-lists` and `traverse-rule-clauses` moved here from
   `memory.jl`; `traverse-rule-clauses` regained the `proc` argument the
   Scheme always had, since memory needs `rule-clause-comparison-proc` and
   unification needs `concept-mapping-proc`.
   **Not** ported: the `answer-justifier` codelet (justify.ss 20-180), which
   needs `report-new-answer` (answers.ss step C), `clamp-rules` →
   `make-clamp-event` (slice C), `monitor-new-rules` (slice D) and the answer
   string that only justify mode builds.
   Two traps worth keeping. `remove-whole/single-concept-mappings` is
   `(remq (select ...) cms)` — `select` returns only the FIRST match, so a
   SECOND whole/single mapping survives; the `whole-single-twice` pair pins
   that down. And `retention-probability` returns exactly 1 for a
   string-position entry, which short-circuits `prob?` WITHOUT drawing, so the
   RNG stream depends on which dimensions a pattern names.

   **`jootsing.ss` is done**, as `codelets_jootsing.jl`, covered by the
   `runloop` probe rather than one of its own — its two codelets only ever say
   anything after hundreds of cycles of real history, so a hand-built probe
   would have to fake the trace it is supposed to be reading.
   `get-most-recent-event-set` is generic over event type but has only clamp
   and snag callers; `%satisfactory-rule-quality%` and `%settling-period%` came
   with it (`%max-clamp-period%` and `%grace-period%` were already in
   `trace.jl`). Two things to know. The jootser's snag arm is phrased
   BACKWARDS — it fizzles with probability `1 - p`, so the draw reads as the
   opposite of the test around it. And `joots-from-justify-clamps` is
   deliberately a raise, not a stub: it reads `*answer-string*` and posts
   `answer-justifier`, both of which belong to justify mode, and a justify
   clamp cannot arise with justify mode off. `breakers.ss` went in alongside
   it, as `codelets_breaker.jl`.

   `trace.ss` splits cleanly and is being taken in slices:
   - **(A)** ~~patterns and clamping~~ (1412-1672, ~260 lines) — **done**, as
     `trace.jl`, probe `patterns`: the three pattern kinds and their
     deliberately blind equality (activations and urgencies are ignored),
     `negate-theme-pattern-entry`, `get-associated-concept-pattern`, the theme
     / concept / codelet clamping, `against-background`, and the nine standard
     codelet patterns. Codelet-type clamping came with it, in `coderack.jl`.
     **Not** ported: `print-pattern`, which needs `relation-name` from
     `theme-graphics.ss` — a file the headless harness never loads, so the
     Scheme cannot run it either.
   - **(B)** ~~the temporal trace and `make-generic-event`~~ (23-333) —
     **done**, probe `trace`: the event list and its numbering, the per-type
     lookups, `get-new-events-since-last` and
     `get-new-structures-since-last`, the clamp and snag periods with the
     grace window, and the snapshot a generic event takes (time, temperature,
     structures, clamped rules, active theme types, complete and dominant
     themespace patterns). `get-structures` and the clamped-rule list came
     with it, in `context.jl`, and `get-all-{complete,dominant}-theme-patterns`
     in `themes.jl` — note those return patterns WITH their theme-type head,
     unlike the singular `get_complete_theme_pattern`, which returns the
     entries alone.
     **Deferred with (C):** `progress-since-last-clamp`, `undo-last-clamp`,
     `progress-since-last-snag` and `undo-snag-condition`, the four methods
     that reach into a clamp or snag event for its progress evaluator.
   - **(C)** ~~the seven concrete event types~~ (333-1310), the biggest piece —
     **done**, in two commits:
     - the four WORKSPACE and SLIPNET events (concept-activation,
       concept-mapping, group, rule), probe `wsevents` — the ones raised by the
       model perceiving something. A `ConcreteEvent` abstract type forwards the
       generic accessors through one set of methods; the three workspace types
       override `type?` to answer to `:workspace` too.
     - the three SELF-WATCHING events (answer, clamp, snag) and the four trace
       methods deferred with them, probe `swevents`. Clamp and snag are the
       only events that are ACTIVATED and DEACTIVATED — they impose a state
       rather than describe one — and the only ones carrying a PROGRESS
       EVALUATOR: a clamp scores EVENTS since it went up, a snag scores
       STRUCTURES built since. The probe dumps the themespace, slipnet and
       coderack before activating, while active, and after deactivating, which
       is the only way to see that the imposition and its undoing match.
     **Not** ported: the clamp event's `get-complement-codelet-pattern`, whose
     `let*` never binds the variable it reads (the top-level
     `get-complement-codelet-pattern` is a different name), so calling it
     raises in Chez. Nothing calls it; it is left absent rather than given a
     value it does not have.
     Fixed on the way: `get_concept_pattern(::Rule)` returned a bare
     `Vector{Node}` where the Scheme returns a full
     `(concepts (<node> <activation>) ...)`. Only the `rules` probe consumed
     it, and it stripped the wrapper itself, so the divergence never showed.
     The node list is still available as `rule_concept_nodes`.
     Probing note: the Scheme's monitors are live, so a coderack run raises
     real events into `*trace*` on the Scheme side and none on the Julia side.
     Both probes therefore never READ `*trace*` except where they put events
     into it deliberately. Constructing an event draws no random numbers, so
     the RNG streams stay in step — which is what lets these probes run a real
     coderack, lifting the bonds-only restriction the `trace` probe worked
     under.
   - **(D)** ~~the monitors~~ (1310-1412) — **done**, probe `monitors`, and
     with it `trace.ss` is COMPLETE. Four hooks in the code that builds
     structure and moves slipnode activations, each asking how important what
     just happened was and appending an event only if it clears the threshold
     for its kind. That filter is why the trace stays small enough to reason
     over: Metacat builds thousands of structures per run and remembers dozens.
     The four thresholds differ in spirit — a group must be REMARKABLE (100), a
     concept waking must be deep and move far (85), a rule must be decent (67),
     a slippage need only be a slippage (65).
     **`monitors` is the first probe that compares a WHOLE TRACE**: both sides
     now raise the same events from the same code paths, so it runs a real
     coderack and diffs the event list end to end — numbers, types, names,
     times, temperatures, strengths, in order. That checks not just that each
     event is built right but that the same things were judged worth recording,
     in the same order, at the same moments. The bonds-only restriction the
     `trace` probe worked under is gone.
     Three things the wiring turned up:
     - `set-activation` and `update-activation` are IDENTICAL in the Scheme
       except that the latter monitors. The port had aliased them
       (`const update_activation! = set_activation!`), which was right while no
       monitors existed and wrong the moment they did. They are separate now;
       `clamp` and `flush-activation-buffer` monitor too, `set-activation` does
       not.
     - `activate-label` flushes the label node IMMEDIATELY, with the Scheme
       comment "so that the activation of the label node will show up in the
       trace before the concept-mapping that caused it". That flush is
       monitored, so it is an ORDERING constraint on the trace, not just on
       activation. The `monitors` probe shows it holding: the concept-activation
       events land before the concept-mapping event that caused them.
     - `concept-mapping-importance` only clears 65 for a slippage on a SPANNING
       bridge — the same slippage scores 75-81 spanning and 57 not. Across
       seven stochastic runs the highest non-spanning score reached was 57, so
       the monitor's event path was never exercised. The probe therefore has a
       deterministic second phase that builds whole-string groups on both sides
       by hand and lets `build-bridge` raise the event through the real
       monitor.
     The monitors fire exactly when a TRACE IS ATTACHED to the context
     (`ctx.trace`), where the Scheme's fire always because `*trace*` is a global
     that always exists. That is behaviourally the same: the events monitors
     raise change nothing but the event list, since only clamp and snag events
     set the trace's period flags and no monitor raises those. It is also what
     keeps the twenty-odd probes that never load `trace.jl` working — the call
     sites short-circuit on `ctx.trace === nothing` so the name is never
     resolved.

   **The monitors are already live in the Scheme, and that shapes how (B) and
   (C) can be probed.** Building a group (`groups.ss` 951) or a bridge
   (`bridges.ss` 1221, 1416), building a rule (`rules.ss` 485) and changing a
   slipnode's activation far enough (`slipnet.ss` 140, 153, 167) each raise a
   real trace event. So a probe that runs the coderack fills the Scheme's
   trace with event types the port does not have, and the two sides diverge
   for a reason that is not a porting bug — the first draft of the `trace`
   probe did exactly that, and its first hand-raised event came back numbered
   2 instead of 1. The probe now stays inside the slice: it builds BONDS,
   the only structure with no monitor, and leaves slipnode activations alone.
   Once (C) and (D) are in, that restriction lifts.
7. ~~**The run loop**~~ (`run.ss`, 346) — **done**, as `run.jl`, probe `run`.
   `init-mcat`, `step-mcat`, `run-mcat`, `clamp-initial-slipnodes`,
   `update-everything`, `update-temperature` and `post-initial-codelets`, plus
   a `run_problem` mirroring the headless harness's. Three things in the driver
   are easy to get wrong from reading the probes, which drive the loop by hand:
   `update-everything` runs once every FIFTEEN codelets, not once per codelet;
   `step-mcat` increments the count AFTER running the codelet, so the first
   codelet of a run executes with `*codelet-count*` still 0; and `init-mcat`
   sets every descriptor of every object to full activation with
   `set-activation`, not `update-activation`, so that no concept-activation
   event lands in the trace before the run starts.
   **Not** ported: the interactive half — breakpoints, step mode, `go`,
   `rerun`, `runtil` and the graphics refreshes the loop interleaves. All of it
   exists to hand control back to the SWL repl.
   With this in, `metacat/bench/metacat_bench.{ss,jl}` can finally be rewritten
   to measure the model rather than its layers; it has not been yet.

~~`breakers.ss` (47)~~ — **done**, as `codelets_breaker.jl`.

### Known stubs and deliberate omissions

Every one of these is a place the port answers a question it has not really
been taught to answer. Four of their predecessors turned into silent bugs the
moment the state they excluded became reachable, so treat this list as a set of
alarms, not a backlog.

| where | what is missing | when it becomes wrong |
|---|---|---|
| ~~`:answer_finder`~~ | **done** — the real procedure is attached in `answers.jl` | — |
| ~~`abstract_answer_description` / `abstract_snag_description`~~ | **done** | — |
| ~~`process_snag`~~ | **done**, with `post-initial-codelets` and `update-everything` | — |
| ~~the trace's four clamp/snag progress methods~~ | **done** with slice (C) | — |
| translating an EXTRINSIC (swap) clause | ported but never exercised: no configuration tried produces a swap rule | as soon as one does — and the irrelevant-group deletion goes with it |
| ~~`top-down-bond-scout:category` and `:direction`~~ | **done**, with the run loop, exactly when the alarm said they would be needed | — |
| justify mode | `%justify-mode%` is off everywhere; bottom rules and the answer string are never built | the `answer-justifier` codelet, the unported half of `justify.ss` |
| `joots_from_justify_clamps` | RAISES rather than stubbing: it needs `*answer-string*` and posts `answer-justifier` | only with justify mode on, which cannot produce a justify clamp today — the raise is the alarm |
| the `*comment-window*` prose | every codelet that writes English about what it just did drops it (`how-strings-change`, the two `joots-from-*-clamps` messages, `answer-quality-phrase`'s callers) | `answers.ss` step (D), which is the commentary layer proper |
| the run.ss INTERACTIVE half | breakpoints, step mode, `go`, `rerun`, `runtil` | never headless — all of it hands control back to the SWL repl |
| `metacat_bench.{ss,jl}` | still benchmarks layers, though `run-problem` now works on both sides | whenever someone wants a number for the model rather than its parts |
| themespace state save/restore | not ported | only the GUI history browser uses it |
| `propose-singleton-group` (`bridges.ss`) | not ported | never — nothing in the model calls it |

The rule is the one in section 5: a stub justified by "this state cannot arise
yet" needs a probe the moment that state can arise. Adding a layer means
re-reading this table first.

---

### Known exactness divergences from Chez (open, not fixed)

Two places where the Julia does not reproduce Chez's numeric tower. Both were
found by porting `themes.ss` a second time from `b296069` and diffing the two
ports; both were then measured against the current tree. **Neither changes a
computed number today** — that was checked, not assumed — so nothing is broken
and the probes are honestly green. They are filed because the first
one is a trip-wire for the next probe someone writes, and section 5's rule
about exact arithmetic is what makes them worth knowing before they bite.

**1. `exp` of an exact zero.** R6RS lets `exp` return an exact result where it
is exactly representable, and Chez does:

```
Chez:   (exp 0) => 1     exact? #t        so the sigmoid of an exact 0 is exact 0
Julia:  exp(0)  => 1.0   inexact          so it is 0.0
```

`bridge_theme_compatibility_sigmoid` (`themes.jl:704`) is
`2 / (1 + exp(...)) - 1`, so with **no active themes** — average theme support
an exact 0 — Chez gives an exact `0` and the port gives `0.0`.

- *Does it change a strength?* No. Sweeping every integer and half-integer
  `intrinsic` from 0..100 through `update_strength!` with weight `0` versus
  `0.0` gives identical results: the exact and float paths agree at every
  rounding boundary in range.
- *When does it surface?* The moment any probe emits a bridge's thematic
  compatibility through the themes probe's own `num` helper. That helper
  renders an inexact value as `F<numerator>/<denominator>`, so the two sides
  print `0` and `F0/1`. Any probe covering a bridge with no active themes will
  diff on it.
- *Fix, if wanted:* an exactness-preserving `exp` in the numeric tower,
  `sexp(x) = (is_exact(x) && iszero(x)) ? 1 : exp(float(x))`, and
  `sdiv(2, 1 + sexp(...)) - 1` for the sigmoid.

**2. `max` promotes across exactness in Julia, not in Scheme.**

```
Chez:   (apply max '(9/10 1)) => 1      an exact INTEGER
Julia:  maximum(Real[9//10, 1]) => 1//1  a Rational
```

`get_thematic_compatibility(d::Description, ts)` (`themes.jl:728`) folds with
`maximum` over `get_theme_support_values`, which mixes `pct(...)` rationals
with integer `0`s. A description whose dimension carries one theme at 100 and
another at partial activation therefore gets `1//1` where Metacat has `1`.
Reproduced on real data: `values = Real[9//10, 1]`, compatibility `1//1`.

- *Does it matter?* Less than it looks. Exact-rational arithmetic gives the
  same answer either way, and the probe renderer runs `snorm`, which turns
  `1//1` back into `1` — so it is invisible to the current traces. The only
  way it could bite is a call site that DISPATCHES on `::Integer` (for example
  `sexpt(b::SExact, e::Integer)`, whose fallback takes the float path), if a
  compatibility value ever reaches one.
- *Fix, if wanted:* a `maximum` that returns the winning ELEMENT rather than
  folding with `max`, so the representation survives.

Note that `maximum(positive_activation, ...)` at `themes.jl:146` and `:344` is
NOT affected — those are all integers.

---

### Load order of `metacat/julia/src/`

The files are plain `include`s, so a probe has to load everything a source
file's DEFINITIONS mention — struct fields, method argument types, and anything
run at load time such as `register_codelet_type!`. Function BODIES resolve at
call time, so a body may call forward. The order that works:

```
schemenum utilities slipnet workspace concept_mappings images bonds groups
bridges coderack themes context codelets_bonds codelets_descriptions
codelets_groups codelets_bridges codelets_themes codelets_breaker rules
answers trace justify memory codelets_jootsing run
```

`trace.jl` now needs `answers.jl` BEFORE it, not just at call time: the answer
and snag event structs have `SlippageLog` FIELDS. A probe that includes
`trace.jl` without `answers.jl` fails at load with `UndefVarError: SlippageLog`
— which is exactly how the `justify` probe broke when slice (C) landed.

`justify.jl` loads before `memory.jl`, as justify.ss does before memory.ss:
memory's distance metric calls `compare_rule_clause_lists`, which lives in
`justify.jl`.

`rules.jl` needs `bridges.jl` (it dispatches on `Bridge`), `coderack.jl` and
`context.jl` (it registers codelet types at load time and dispatches on
`MetacatCtx`), so every probe that includes it must include those too.

`codelets_jootsing.jl` loads AFTER `trace.jl` and `answers.jl`: its bodies read
clamp and snag events and call `give_up!`, and it registers `:jootser` and
`:progress_watcher` at load time. `run.jl` is last — `update_everything!` calls
into every layer. `codelets_breaker.jl` has no dependencies beyond the
coderack and can go anywhere after `context.jl`.

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

The harness also supplies `find-next-space-position`. `rules.ss`'s English
transcription calls it to wrap long phrases, but it is defined in
`general-graphics.ss` — a graphics file, never loaded headless — even though
the procedure itself is pure string arithmetic. The harness defines it verbatim
rather than moving it in the vendored source.

The harness also stubs `group-graphics`. `group-builder` calls
`(group-graphics 'erase ...)` UNGUARDED in each of its two consolidation
branches (`groups.ss` 727 and 765), unlike every other graphics call in that
file, which sits behind `%workspace-graphics%`. Headless, `group-graphics.ss`
is never loaded, so those two calls raise the moment a group consolidates.

And it fills in an answer description's icon procedure. `memory.ss`'s
`update-activation` and `unhighlight` call `(get-normal-icon-pexp value)`
unguarded; that slot holds a graphics closure only `set-graphics-info` ever
fills in, and it is an ARGUMENT to `tell`, so the harness's "route a send to a
non-procedure to a no-op" guard cannot save it. It only bites on the SECOND
problem of a session — `init-mcat` calls `clear-activations`, which updates the
activation of every answer already in memory — which is exactly the state the
`run` probe is for. The harness wraps `make-answer-description` and puts a
no-op in the slot.

`suspend` and the stop reason are the harness's too. `suspend` prints "Type
(go) or click on the Workspace to continue..." — an instruction to a user of a
GUI that is not there — so the harness goes straight to the escape; and since
both `report-new-answer` and `give-up` end a run through the same `break`, the
harness has `give-up` record which it was, so `run-problem` can return
`give-up` rather than `answer`.

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
