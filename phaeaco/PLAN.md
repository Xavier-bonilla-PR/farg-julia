# Recreating Phaeaco in Julia — plan

Phaeaco is Harry Foundalis's FARG architecture for Bongard problems (BPs):
twelve 100×100 black-and-white boxes, six on each side, where the job is to
say what the left six share that the right six lack. It was his 2006 Indiana
University dissertation, *Phaeaco: A Cognitive Architecture Inspired by
Bongard's Problems* (461 pages), written in C++ for Windows.

**Its source code was never released.** Foundalis's research page says so
outright ("Phaeaco's source code: not provided"), and his executable was never
distributed either. So this is not a port like `copycat/` and `metacat/`. It is
a *reconstruction from the written description*, and that changes what
"correct" can mean. Read section 1 before anything else.

This plan is based on a full read of the dissertation's technical chapters
(5, 7, 8, 9, 10, 11 and Appendix B), plus Appendix A's performance tables and
Foundalis's 2006 progress page. Section numbers like §7.2 below refer to the
dissertation.

---

## 1. What "done" means without a reference implementation

The Copycat and Metacat ports here are trustworthy because they are
*byte-identical* to a running original: shared RNG, layer probes, trace diffs.
None of that is available. In its place, three tiers of evidence, from
strongest to weakest:

1. **Numbers the thesis states about its own components.** Several are
   reproducible in isolation and make real unit tests:
   - The *Patterns* clustering algorithm scores **98.5 ± 7** on Foundalis's
     clustering benchmark at threshold **0.83** (tolerance 0.78–0.88), against
     leader 92.9, Lu & Fu 78.8 and k-means 54.7 (Table 8.1, §8.3.4).
   - The accumulator model of numerosity must give reaction times that follow
     **Welford's formula**, RT = a + k·log(L / (L − S)) (§7.3.2).
   - Circles come out with ellipse eccentricity **below ~0.45**, and **~0.20**
     for one that nearly fills the box (Appendix B).
   - Small numerosities (≤ 5) are reported almost always exactly; larger ones
     drift (§7.3.2).
2. **Ground truth we generate ourselves.** For the image-processing level we
   can draw boxes whose contents we know exactly (a triangle with known
   vertices, a circle of known radius, *n* dots, a filled vs. outlined shape)
   and score what the retina finds. This is the substitute for a reference at
   the bottom of the stack, and it is unlimited.
3. **Behaviour on real BPs, compared with Appendix A.** Foundalis reports 100
   runs per problem for the 15 BPs Phaeaco solves. Matching those
   distributions (correct / wrong / no answer, and *relative* time) is the
   end-to-end target. It is also the weakest evidence: many different
   programs could produce the same 15 success rates.

The honest description of the finished thing is **"a Phaeaco reconstruction"**,
not "Phaeaco". The README for this tree should say that in its first
paragraph.

### The target table

From Appendix A (100 runs each; the per-problem times are there too). The solution column paraphrases how the thesis body describes each
problem; confirm the exact wording against the images in phase 1. We compare **relative** times (divided by BP #3's time), which is
how Foundalis compared himself with humans, measured in cycles rather than
seconds.

| BP | Solution (left vs. right) | Mechanism | Phaeaco correct / wrong / none | Humans correct / n |
|---|---|---|---|---|
| 3 | outlined vs. filled | hardwired: zero-variance texture | 99 / 1 / 0 | 28 / 28 |
| 1 | nothing vs. something | hardwired: existence | 100 / 0 / 0 | 31 / 31 |
| 2 | large vs. small | holistic: feature statistics | 82 / 18 / 0 | 28 / 28 |
| 23 | differing number of objects | holistic: numerosity | 83 / 4 / 13 | 30 / 31 |
| 15 | closed interior vs. none | holistic: interior | 99 / 0 / 1 | 27 / 31 |
| 85 | differing number of lines | analytic: line numerosity, re-parsing | 94 / 0 / 6 | 27 / 30 |
| 11 | a continuous-feature difference | holistic: feature statistics | 83 / 4 / 13 | 15 / 31 |
| 6 | triangles vs. quadrilaterals | structural difference | 70 / 11 / 19 | 26 / 31 |
| 39 | lines almost parallel vs. not | equality, for-all | 65 / 29 / 6 | 30 / 31 |
| 5 | no curves vs. curves | existence of curves | 60 / 18 / 22 | 28 / 31 |
| 21 | small object present vs. not | analytic: in-box contrast | 34 / 20 / 46 | 20 / 31 |
| 8 | where the figure sits in its box | barycenter coordinates | 23 / 4 / 73 | 24 / 31 |
| 4 | convex vs. concave | imaginary percept: convex hull | 20 / 3 / 77 | 5 / 31 |
| 56 | all same texture vs. not | equality, for-all, abstract | 19 / 17 / 64 | 22 / 31 |
| 22 | all same size vs. not | equality, for-all, abstract | 13 / 6 / 81 | 11 / 30 |

Note that **the failures are part of the target.** BP #4 and #56 are failures
the thesis explains (convex hull is a low-urgency percept; verification at
the retinal level is not sharp enough). A reconstruction that solves #4 every
time is not more faithful, it is less.

---

## 2. What the thesis specifies, and what it leaves to us

This decides where the work is mechanical and where it is design.

**Specified closely enough to implement directly:**

- The activation structure (§7.2): value in (0, 1), raised only by discrete
  "advance one step" signals, decaying one step per time unit, along a
  sigmoid built from two hyperbola pieces and a linear middle. Its parameters
  are *stability* (the number of steps) and *limiting activation* *l* (values
  stay within [*l*, 1 − *l*]).
- Significance (§9.3.1): the same structure with stability several orders of
  magnitude higher. Each time activation hits its maximum, significance
  advances a step; each time significance hits *its* maximum, its stability
  grows. LTM weight = significance + activation.
- Feature statistics (Table 7.1: N, mean, var, sum of squares, min, max) and
  their incremental update (Eqs. 8.9–8.11).
- Accumulator numerosity (§7.3.2): each counted item adds a draw from
  N(1, σ₀); comparison is the sequential z-test loop with an upper bound on
  cycles.
- Feature distance (Eqs. 8.1–8.3: scaled difference, then Student's t for
  exemplar-vs-pattern and Welch for pattern-vs-pattern), numerosity distance
  (Eqs. 8.4–8.6), weighted combination by LTM weight (Eq. 8.7), and
  similarity = e^(−d) (Eq. 8.8).
- The *Patterns* group-formation algorithm and its sub-algorithms
  (Figs. 8.6, 8.8), including incremental pattern updating and link strengths
  that grow with each exemplar carrying a structural element (§8.3.3).
- Every threshold is a normal distribution N(µ, σ) with small σ, sampled per
  decision (§7.4.1).
- The retinal pipeline (ch. 10): processes A, B, C, D, E, F, M, G, H, i, K, O,
  P, R, Q, S, Z, each described in a paragraph or two. These include the
  concentric-square altitude used for thinning (B), the "no more than two
  taller neighbours" skeleton rule (C), the 16-ray border search (F), the ray
  escape test for openness (O), and fuzzy shrinking and zooming with factors
  0.5 / 5×5 and 2 / 3×3→6×6 (S, Z).
- Cubic B-splines for curves, a conic least-squares fit for ellipses, and
  circumcentres for circle centres (Appendix B). Convex hull is built
  incrementally; area is triangulated when convex and Monte Carlo when not
  (§10.3.18).
- The LTM: Platonic primitives in an is-a hierarchy with property
  inheritance, core structures, anonymous associations that are promoted to
  relations past a weight threshold, an index of relational and numerosity
  nodes for retrieval with inhibition from inactive indexical nodes, and
  forgetting by not saving unreachable nodes (ch. 9).
- The solver's control (ch. 11): a holistic stage over all 12 boxes; a box
  counts as "seen" when its root activation drops below a threshold; side
  patterns; ideas as pairs of representations; verification requiring the two
  sides' value *ranges* not to overlap; an analytic stage with box selection
  biased towards simpler boxes; a master node of failed ideas whose
  activation is the program's motivation, so it gives up when that drops
  below a threshold; and persistence when 4–5 of 6 boxes confirm an idea.

**Left to us. These are the real design work:**

- **The codelet inventory.** The thesis says outright that it will not list
  the codelets per node type or their urgencies, because "the exact number,
  quality, and urgencies of generated codelets per node type is not what
  makes the system work" (§7.1). We get the *shape*: each λ-node spawns slope
  and length (very high urgency), a line counter (medium), and width,
  endpoints and midpoint (very low). We also learn that the codelet set comes
  from the node type's links in LTM, not from hard-coded lists. Everything
  else we design.
- **Almost every numeric parameter.** σ₀, stabilities, decay periods, the
  clustering threshold in the solver (0.83 is only the benchmark's optimum),
  the box-done threshold, the boredom threshold, the line-vs-filled thickness
  threshold, the dot size (a radius of about 5 px is suggested), and all
  urgencies.
- **The Bongard-specific codelets** (§11.1.2–11.1.3). We know they compare
  side patterns feature by feature, with urgency proportional to the
  probability that the distributions differ and to the feature's LTM
  salience. We know they generate ideas from nodes and go from specific to
  general ("3 line segments" → "counting lines" → "counting things" →
  "3-ness"). The full set is not given.
- **Structural matching details** (§8.2.4). The thesis gives an O(n·m)
  best-match at each level and recursion damped by an "importance-weighted
  depth" that usually stops after 2–3 levels. The damping formula is not
  given.
- **How the solver phrases answers.** It prints short phrases ("outlined
  texture", "object has small area", "every object has similar texture").
  We need a phrase template per idea type.
- **The process scheduler.** Each retinal process "self-regulates" its time
  slice from its hit rate or queue length. We pick the scheme.

Every one of these choices goes in `DECISIONS.md`, with the thesis passage
it is constrained by and why we chose what we did. That file is this
project's equivalent of the trace diff: what lets someone else judge the
result.

---

## 3. Scope

**In:** the BP solver, the retinal level, the workspace, matching and
patterns, the LTM (saved and loaded), and the Mentor's *visual* lessons
(draw a figure and let it update LTM). A headless runner. Rendering of a
box's detections and representation to PNG/SVG for debugging.

**Out (for now):**
- The linguistic side of the Mentor (§5.2). The thesis itself says it was
  unfinished and unpublished.
- The photographic preprocessor (§10.1). BPs are already two-colour, so only
  the background-colour detection (§10.1.1) is needed. The contour filter is
  a later nicety.
- Everything in §11.2, "What Phaeaco can't do": conjunctions, noise
  screening, applying an on-the-fly procedure to every box, Ockham-style
  minimum descriptions, meta-descriptions, and figure–ground. These are
  *improvements* on Phaeaco, and belong behind a flag after the
  reconstruction is calibrated.
- Temperature. Phaeaco does not have one (§6.2.3), and adding it would make
  this something else.

---

## 4. Architecture

```
phaeaco/
  PLAN.md            this file
  DECISIONS.md       every gap in the thesis and how it was filled
  README.md          what this is (a reconstruction) and how to run it
  julia/
    Project.toml     PhaeacoJL
    src/
      PhaeacoJL.jl
      core/          rng, params (N(µ,σ) thresholds), activation, stats, trace
      input/         BP loading, box splitting, background detection
      retina/        processes A–Z, detectors, scheduler, geometry
                     (least squares, splines, conics, hull, area)
      workspace/     node and link types, codelets, coderack (process R),
                     process P (retina → nodes), process Q (quantity)
      ltm/           conceptual network, primitives, index, persistence
      patterns/      matching (§8.2), Patterns algorithm and updating (§8.3)
      solver/        holistic and analytic stages, ideas, verification,
                     answer phrasing
      mentor/        visual lessons only
    test/
  bench/             synthetic box generator, retina scoring, batch runner,
                     Appendix A comparison, timing
  data/              (not committed, see section 7) the BP images
  results/
```

Carry-overs from this repo: the *method* (layer-by-layer with a test at each
layer, seeded runs, `CONTINUE.md` handoff notes, a benchmark harness) and
the Julia performance lessons in `CONTINUE.md` (concrete field types, no
abstract containers in hot loops). **No code is copied from `metacat/`**,
which is GPL-2. Little from `copycat/` either, since its coderack mirrors
Python's binning bit for bit and Phaeaco's needs differ.

Two cross-cutting rules, from the thesis:

- **Retina and cognition never share numbers.** The cognitive level sees
  "there is a line segment" and a feature node's statistics, never the
  y = ax + b behind it (§7.1, §5.1.5). Enforce it in the types: a cognitive
  node holds an opaque handle to its retinal detector, not the detector's
  fields.
- **Everything is incremental.** No stage waits for the previous one to
  finish (§10.2, §8.3). Processes run interleaved under one scheduler, and
  the coderack is just another process (R) that gets more time as the retinal
  processes run dry.

Seeded randomness throughout (Julia's `Xoshiro`, one stream per run). With
no reference to diff against, reproducing a run exactly is what makes
debugging possible.

---

## 5. Phases

Each phase ends in a check that can fail. Sizes are relative (S/M/L/XL),
because the thesis gaps make calendar estimates fiction.

### Phase 0 — Groundwork (S)

- Skeleton package, CI-able test runner, `CONTINUE.md` and `DECISIONS.md`.
- `core/`: the activation structure (piecewise-hyperbola sigmoid, stability,
  limiting activation, step up, step-down timer), significance on top of it,
  Table 7.1 statistics, N(µ, σ) parameters loaded from one TOML file, and a
  structured trace.
- **Check:** unit tests that activation is monotone, symmetric about
  (½, ½), and never leaves [*l*, 1 − *l*]. That repeated maximisation raises
  significance and then its stability. That incremental statistics match a
  batch computation to rounding.

### Phase 1 — Input and synthetic data (S)

- Load a BP image, split it into 12 boxes, detect the background (§10.1.1),
  and produce a 0/1 array per box.
- `bench/synth.jl`: draw boxes with known contents (lines at known slopes,
  polygons with known vertices, circles and ellipses, filled vs. outlined,
  *n* dots, thick vs. thin strokes, small objects that need zooming) with
  optional jitter and "hand-drawn" noise. Write a ground-truth record beside
  each image.
- Synthetic BPs for every target mechanism (texture, size, count,
  existence, interior, convexity, equality). This lets the solver be
  developed before real images are sorted out.

### Phase 2 — The retina (XL, the largest single risk)

In dependency order, each scored against synthetic ground truth before
moving on:

1. A (random sampling, self-regulated), B (altitude), C (skeleton pixels,
   filled-region sampling), F (16-ray border search).
   **Check:** the skeleton of synthetic strokes lies within 1 px of the true
   centreline.
2. D (line detectors with activation, least squares, decay of unsupported
   hypotheses), H (merge duplicate detectors).
   **Check:** slope and length within tolerance on synthetic lines, and no
   surviving false detectors on clean input.
3. E (intersections and V/T/X types, neighbourhood and extension sampling),
   K (merge into K-points).
   **Check:** vertex count of synthetic polygons, and the T and X cases.
4. M (line strings, closure), G (curves via B-splines, Appendix B),
   O (closure and openness by escaping rays, ellipse and circle fit).
   **Check:** eccentricity thresholds from Appendix B, and openness of 0 for
   closed shapes rising to 1 for a straight line.
5. i (dots), Z (zoom small objects), S (shrink objects made of many short
   lines), convex hull (incremental), area.
   **Check:** small circles vs. small triangles become distinguishable after
   Z, and Monte Carlo area is within a few percent of true area.
6. The scheduler: interleave everything with self-regulated time slices.
   **Check:** the same detections as running each process alone, and
   different-but-equivalent detection orders across seeds.

### Phase 3 — Workspace and LTM primitives (L)

- Node types from ch. 7: box, object, λ (line segment), curve, line string,
  dot, V/T/X/K points, feature nodes (slope, length, width, texture, angle,
  area, x, y, curvature, openness, elongatedness, missing area), numerosity,
  convex hull, barycenter, endoskeleton, relations with twin links and
  strengths, equality/grouping nodes, the for-all quantifier, and Necker
  views.
- Process P builds nodes from detectors, inserting object nodes and
  replacing them when a shape is identified. Process Q notices "many" and
  damps per-item codelets.
- LTM primitives: the Platonic nodes, is-a inheritance (dot is-a point, so it
  gets coordinates), and "has feature" links that *generate* each node
  type's codelets (§7.1).
- Codelets and the coderack as process R. Upward activation injection, and
  termination when the box node's activation falls below threshold.
- **Check:** the Λ shape from Fig. 7.1 yields Fig. 7.15's structure in most
  seeds: always the two λ-nodes, the object and the vertex, and the leaves
  only some of the time. Convex hull is rare unless primed. Inside/outside
  works for nested shapes. For-all on a BP #56 box.

### Phase 4 — Matching and patterns (M)

- Feature and numerosity distances, Gauss–Legendre integration of the t
  distribution (check it against `Distributions.jl` in tests only), weighted
  combination, damped structural recursion with O(n·m) best match, and the
  correspondence record.
- The *Patterns* algorithm and pattern updating with link strengths.
- **Check:** reproduce Table 8.1. Build Foundalis's benchmark (1-D exemplars
  in [0, 1], varying cluster count, density and separation, scored 0–100)
  and get Patterns ≈ 98.5 at threshold ≈ 0.83, with leader, Lu & Fu and
  k-means in their reported order. Also: the numerosity comparison
  reproduces the Welford trend.

### Phase 5 — The solver, holistic stage (L)

- Twelve boxes interleaved, side patterns once each box is "seen",
  multiple patterns per side under a Necker node.
- Bongard codelets that compare side patterns: zero-variance shortcut,
  feature-difference probability, existence (pattern element vs. "missing"),
  and structural difference.
- Ideas, verification with range non-overlap, re-looking at each box during
  verification and merging the two looks, and answer phrasing.
- **Targets:** BP #3, #1, #2, #23, #15, synthetic first and then real.

### Phase 6 — The solver, analytic stage (L)

- Box re-examination biased towards simple boxes, priming carried across
  boxes, idea generation from nodes going specific → general, the failed-idea
  master node, boredom, and persistence on near-misses.
- **Targets:** BP #85, #11, #6 (once LTM has triangle and quadrilateral, see
  phase 7), #5, #21, #8, #4.

### Phase 7 — LTM proper and the Mentor (M)

- Patterns migrating to LTM (match an existing concept or found a new one),
  the index with inhibition, association → relation promotion, save and load
  with forgetting.
- Visual Mentor lessons: a list of drawings to learn, replayable.
- **Check:** after a triangle/quadrilateral lesson, BP #6 is solved as
  "triangle vs. quadrilateral", and without it as "three sides vs. four"
  (§5.2). Forgetting drops never-reinforced concepts across save/load.

### Phase 8 — Abstraction: equality and for-all (M)

- The sameness-detector codelet, for-all, and the "similar value, whatever
  it is" form that points at the Platonic feature.
- **Targets:** BP #56, #39, #22. The thesis notes that #39 and #22 came "for
  free" once #56 worked. If ours doesn't do the same, that is a signal we
  special-cased #56.

### Phase 9 — Calibration and reporting (M)

- Batch runner: 100 seeded runs per BP, giving correct / wrong / none and
  cycle counts.
- Tune the parameters in `params.toml` against the target table, recording
  every change in `DECISIONS.md`.
- **Guard against overfitting.** There are only 15 targets and dozens of
  knobs. Freeze the parameters, then run the frozen model on BPs Phaeaco did
  *not* solve and on new synthetic BPs, and report those results too, good
  or bad.
- A `results/` table in the same shape as section 1, plus a speed benchmark.

---

## 6. Risks

- **The retina never gets robust enough.** Hand-drawn noise, serifs, and
  near-touching lines are where image processing goes wrong, and the solver
  is only as good as what it sees. Mitigations: synthetic ground truth from
  day one, and building the solver on synthetic BPs in parallel so it is not
  blocked.
- **Gap-filling drifts from Phaeaco.** With no reference, every choice in
  section 2's second list is a chance to build something else. Mitigation:
  `DECISIONS.md`, and treating the thesis's *qualitative* claims as tests
  (convex hull is rarely perceived, textures are noticed first, #39 and #22
  come free after #56).
- **Overfitting the 15.** Covered in phase 9.
- **Scope creep into §11.2.** The "can't do" list is tempting. It stays
  behind a flag until phase 9 is done.
- **Speed.** Phaeaco took seconds per problem on a 2006 machine. Julia
  should be much faster, but process interleaving and per-decision Gaussian
  sampling are hot paths. Profile from phase 2 on, not at the end.

---

## 7. Decisions needed before or during phase 1

1. **Where the BP images come from, and whether they can be committed.**
   Foundalis hosts the BPs as GIFs (`foundalis.com/res/bps/...`) and the
   OEBP (oebp.org) has more. Neither states a licence, and the originals are
   from Bongard's 1967 book. Note that this sandbox's network blocks
   foundalis.com directly (it was only reachable through the web scraper).
   *Recommendation:* a fetch script that downloads them into an uncommitted
   `phaeaco/data/`, plus our own synthetic BPs, which can be committed.
2. **The licence for this tree.** It is new code written from a published
   description, so it is not bound by Copycat's MIT or Metacat's GPL-2.
   *Recommendation:* MIT, matching `copycat/`, unless you prefer otherwise.
3. **Fidelity first, or improvement first.** *Recommendation:* reconstruct
   the 2006 behaviour, including its failure rates, and put improvements
   behind flags afterwards. Otherwise there is nothing to compare against.
4. **The name.** *Recommendation:* the module `PhaeacoJL`, with the README
   calling it a reconstruction and pointing to the thesis.

One piece of context worth knowing: Foundalis stopped working on Bongard
problems in 2008 over ethical concerns about where this line of research
leads, and that is part of why the code was never released. His page
explaining this is linked from his research page.

---

## 8. Sources

- H. E. Foundalis, *Phaeaco: A Cognitive Architecture Inspired by Bongard's
  Problems*, PhD dissertation, Indiana University, 2006:
  https://www.foundalis.com/res/Foundalis_dissertation.pdf
- Research page (source not provided; link to the ethics note):
  https://www.foundalis.com/res/diss_research.html
- Program interface (C++, Windows, text-only Solaris build):
  https://www.foundalis.com/res/interf.html
- 2006 progress table (50-run figures, earlier than Appendix A's 100-run ones):
  https://www.foundalis.com/res/solvprog.htm
