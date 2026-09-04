# Continuing this work in a new session

Everything below assumes a **fresh container with a fresh clone** — no
toolchain, nothing cached. Start here.

Branch: `claude/copycat-metacat-folders-iybxko`
Last commit at time of writing: the rule codelets, which complete `rules.ss`
(see `git log -1`). Next up is `answers.ss` — the plan for it is in section 6.

**First thing to do in a new session:** section 1 (install the toolchain), then
section 2 (run the suite). Do not write code until all nineteen probes match on
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
  ruleapply ruleabstract rulecodelets
```

Expected — nineteen layers, **31,852 trace lines byte-identical**:

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
all probes matched
```

If any probe fails on a clean checkout, something in the environment differs —
fix that before writing new code.

The reference implementation also runs standalone:

```bash
scheme --quiet --script metacat/bench/run_metacat_scm.ss abc cba pqrs 42
# a stray "Type (go) or click on the Workspace to continue..." comes first;
# the two lines that matter are:
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

### Metacat — **~9,400 of ~16,000 lines of non-graphics Scheme**, `rules.ss` complete

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

---

## 6. What's next, in order

**~4,900 lines of Scheme remain**, across seven files (`answers.ss` 1,558,
`trace.ss` 1,672, `memory.ss` 586, `jootsing.ss` 344, `justify.ss` 352,
`run.ss` 346, `breakers.ss` 47). Steps 0-4 below are done and
are kept only for the "not ported, deliberately" notes buried in them; the live
work starts at step 5.

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
5. **`answers.ss` (1,558)** — the next thing to do, and the reconnaissance is
   already done. It is four separable pieces; take them in this order, because
   each later one needs the earlier:

   - **(A) rule translation** (`answers.ss` 1196-1558, ~360 lines):
     `make-slippage-log`, `translate`, `translate-rule-clause`,
     `remove-redundant-ObjCtgy-change`, `translate-object-description`,
     `apply-to-change` / `apply-to-dimension` / `apply-to-object-description`,
     `valid-rule-clause?` and friends. **Start here.** It is self-contained:
     given a workspace with vertical bridges and a built top rule, translating
     that rule into a bottom one needs nothing from memory, trace or the answer
     string. The `rulecodelets` probe already builds exactly that state, so its
     driver can be reused wholesale — run the coderack, drive the rule codelets
     to build a top rule, then translate it and dump the result.
   - **(B) the translated string** (1035-1195): `make-translated-string`,
     `attach-length-to-appropriate-groups`, `make-translated-rule-bridges`,
     `irrelevant-translated-string-group?`, `process-snag`,
     `get-rule-supporting-groups`. This is where the two pieces still deferred
     from `images.ss` are needed — `instantiate-as-letter` and
     `instantiate-as-group` — and where `set-translated-rule-information` from
     `rules.ss` finally has something to work on. `get-equivalent-object` in
     `context.jl` is currently a stub that only handles the "object already
     belongs to this string" case; translated strings are the other case, and
     it must be finished here. **That stub is the fifth of its family — see the
     stub lesson in section 5, and the running list below.**
   - **(C) `answer-finder` and `report-new-answer`** (20-95, 929-1035): the
     codelet itself is short, but it asks `*memory*` whether the answer has
     been found before, so **`memory.ss` (586) has to come with it** — or at
     least `answer-present?`. `metacat/julia/src/rules.jl` registers
     `:answer_finder` with a procedure that raises; replacing that is the
     signal this step is finished.
   - **(D) the commentary** (95-928, ~830 lines): `explain`, `theme-phrases`,
     `compare-answers`, `get-answer-comparison-text` — the English prose
     Metacat writes about its own answers, and the part of the program the
     thesis is really about. Leaf-ish, and testable the same way the rule
     transcription was: build the structures by hand and compare the prose.
6. **`trace.ss` (1,672), `jootsing.ss` (344), `justify.ss` (352)** — the rest of
   the self-watching layers. `memory.ss` will already be in by then.
7. **The run loop** (`run.ss`, 346) — then end-to-end comparison becomes
   possible, and `metacat/bench/metacat_bench.{ss,jl}` becomes meaningful.
   Until then the benchmark measures layers, not the model.

`breakers.ss` (47) can go in any time.

### Known stubs and deliberate omissions

Every one of these is a place the port answers a question it has not really
been taught to answer. Four of their predecessors turned into silent bugs the
moment the state they excluded became reachable, so treat this list as a set of
alarms, not a backlog.

| where | what is missing | when it becomes wrong |
|---|---|---|
| `get_equivalent_object` (`context.jl`) | only handles an object that already belongs to the string | as soon as TRANSLATED strings exist — `answers.ss` step B |
| `:answer_finder` (`rules.jl`) | registered with a procedure that raises | `answers.ss` step C |
| `instantiate_as_letter` / `instantiate_as_group` | not ported from `images.ss` | `answers.ss` step B |
| `set_translated_rule_information` | not ported from `rules.ss` | `answers.ss` step B |
| justify mode | `%justify-mode%` is off everywhere; bottom rules and the answer string are never built | `justify.ss` |
| themespace state save/restore | not ported | only the GUI history browser uses it |
| `propose-singleton-group` (`bridges.ss`) | not ported | never — nothing in the model calls it |

The rule is the one in section 5: a stub justified by "this state cannot arise
yet" needs a probe the moment that state can arise. Adding a layer means
re-reading this table first.

---

### Load order of `metacat/julia/src/`

The files are plain `include`s, so a probe has to load everything a source
file's DEFINITIONS mention — struct fields, method argument types, and anything
run at load time such as `register_codelet_type!`. Function BODIES resolve at
call time, so a body may call forward. The order that works:

```
schemenum utilities slipnet workspace concept_mappings images bonds groups
bridges coderack themes context codelets_bonds codelets_descriptions
codelets_groups codelets_bridges codelets_themes rules
```

`rules.jl` needs `bridges.jl` (it dispatches on `Bridge`), `coderack.jl` and
`context.jl` (it registers codelet types at load time and dispatches on
`MetacatCtx`), so every probe that includes it must include those too.

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
