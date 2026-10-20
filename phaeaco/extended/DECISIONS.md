# PhaeacoX decisions

PhaeacoX began as a copy of PhaeacoJL (`../julia`) and adds what §11.2 of
the thesis lists as missing from Phaeaco, plus other abilities the survey
of Bongard's other problems showed it lacked (`../results/survey_judged.md`).
Foundalis calls these "suggested implementational enhancements" that need
no change to the architecture. They are not in the thesis's Phaeaco, so
none of this is reconstruction: the choices below are this project's.
PhaeacoJL's own decisions (D1–D43, `../DECISIONS.md`) still apply.

With `ext_enabled = 0` in `params.toml`, PhaeacoX behaves as PhaeacoJL.

**X1. Where the extension lives.** Every extended percept is added to a
look's exemplar (the `RNode` tree), not built by Workspace codelets. Ideas,
patterns and verification all work on exemplars, so they use the new
percepts unchanged. This skips the codelet level: in effect the extension's
"codelets" always run at the end of a look. Each extended node costs
`ext_tick_cost` ticks. Node types carry their tag after an `@`
(`pair@circle_triangle`), so the existing machinery, which matches by type,
keeps different relations apart; their LTM weight is the base concept's
(`pair`).

**X2. Shape kinds.** A figure's kind comes from the retina: an ellipse
detector covering it (circle or ellipse); an X junction in an open figure
with at most four lines (cross); otherwise the corners of its convex hull,
after removing vertices that deviate less than 18% of the figure's diameter
from their chord: 3 triangle, 4 quadrangle, more polygon. Wavy or curved
sides do not change the corners (BP #10's jagged triangles). A closed,
nearly convex figure with seven or more corners, with curves, or small
(under 20 px) with five or more is round, circle or ellipse by elongation;
an ellipse fit on a figure of elongation under 0.12 is a circle. A small
closed figure whose hull fills the ellipse inscribed in its bounding box
(ratio 0.85–1.12; a square gives 1.27, a diamond 0.64) is round too. A dot
is a small circle if it is a ring (a hole, or ink covering at most 68% of
its box), and is filled otherwise. An isolated line, which PhaeacoJL
perceives as a line and not an object, is a segment.

Kinds are noisy, so they never suggest ideas from one analytic look. In the
holistic comparison, a kind seen on one side only, in at least half its
boxes, is a candidate weighted by its concept and verified, as learned
categories are (D41).

**X3. Relations between figures (§11.2.1–2).** Every two kinds present in a
box form a `pair@A_B` with `above` (mean height of A minus B's), `larger`
(log ratio of mean areas) and `inside` (+1 if some A is inside some B and
never the reverse, −1 for the reverse, 0 otherwise). Kinds that repeat are
taken together. Keying relations by kind is what screens out distractors
(the squares of BP #37). The two textures form `pair@filled_outlined`.

**X4. Comparing parts of a box (§11.2.1).** `contrast@X_Y` holds the sign
of #X − #Y: filled vs outlined figures, filled vs outlined figures of each
kind, and figures inside vs outside the largest figure. Only the sign:
the difference itself is a count, and BP #23 showed that a count of filled
figures, passed off as a contrast, would answer "one vs two figures".

**X5. Nesting (§11.2.5).** `depth` is the longest chain of figures each
wholly inside the next (BP #71: inside figures of the second order).

**X6. Shape similarity (§7.4.10).** Two figures are similar when a distance
over kind, texture, having a hole, corner count, elongation and missing
area is small (similarity ≥ 0.5); identical when their areas also agree.
A box records only judgements: all similar, some two similar, all
identical, and the size of the largest identical set. A measured similarity
let any threshold pass for "identical" (BP #22).

**X7. Groups (§11.2.6).** Three or more figures of one kind form a
`group@K`, with how collinear their centres are, whether some three are on
a line, their spread's elongation and verticality, and the corners of the
group's outline. A kind present in both textures also groups by texture
(`group@outlinedcircle`, BP #41). A box drawn in four or more parts records
the corners of the outline of all its ink (`bcorners`): hatching or dots
may make one figure (BP #96).

**X8. Contours.** A figure's long axis gives `vert` (|sin|) once its
elongation passes 0.25. A stroke crosses itself when two of its lines that
share no junction cross, or four line ends meet (`mark@selfcrossing`). An
open single stroke has `endgap` (distance between its free ends ÷ its
size) and `endangle` (angle between its end directions).

**X9. When the extension looks.** Extended percepts are computed in the
holistic look as well as in analytic and verification looks. Computed only
analytically, they reached an idea only once boxes from both sides had
been re-examined, and the solver usually gave up first (BP #71, perfectly
separable, was found 2 times in 10).

**X10. Attention.** The ordinary analytic attention is PhaeacoJL's: it
never picks an extended node or feature. In addition, with probability
`ext_pick_prob` a look's extended percepts are attended to separately.
Sharing one pool of picks halved the ordinary search and cut BP #22 and
#56 in half. The hardwired zero-variance shortcut of BP #3 applies only to
built-in features.

**X11. Limits met.** Figures that touch are one object to the retina, so a
circle touching the triangle it sits in has no "inside" relation to
perceive (BP #47, boxes I-E, II-B, II-E). Separating them is the parsing
problem of §11.2.4 (Ockham's razor) and is not attempted. Nor is
figure–ground separation of a patterned background (BP #98), or
"three-ness" across unrelated shapes (BP #91).


**X12. Core extraction (Foundalis 2013).** After the thesis, Foundalis
described how Phaeaco gets from a figure to its structure: "successively
eliminating pixels at the border of the figure until only the pixels that
have a maximal distance from the original border remain", the *core
pixels*, which are then "parsed as lines that intersect and meet each
other" (*Unification of Clustering, Concept Formation, Categorization, and
Analogy Making*, CRCC technical report, 2013, Figs. 6–7). The retina
already finds those pixels for thick regions (process C, §10.3.3) but uses
them only as sources for process F. `src/ext/core.jl` makes them a percept.

- *Silhouette.* A figure's core is taken from its ink with its holes
  filled, because "the black pixels are not important": an outlined and a
  filled triangle have the same core, and so do figures with holes in them.
- *Thinning.* Zhang–Suen's peeling alone rounds polygon corners away (a
  square shrinks to a point), so pixels that are centres of maximal discs in
  thick parts (Euclidean distance ≥ 2) are anchored and never peeled. Thin
  strokes have no such centres and are peeled to their centre line.
- *Pruning.* A branch from a free end to a junction is a bump of the border
  when its *extension* — length minus the drop in thickness along it — is
  under `max(2, ext_core_prune × thickness at the junction)`. A corner
  extends `(1/sin(θ/2) − 1)` inscribed radii (a triangle 1, a square 0.41,
  a pentagon 0.24, a hexagon 0.15). `ext_core_prune = 0.2` keeps the
  corners of triangles and quadrangles, whose drawn corners are a little
  rounded, and makes circles round; hexagons and pentagons fall either
  way. A lone path is pruned the same way as two arms from its thickest
  point: with no real arm it is the centre of a round figure, a point
  core. Junctions closer together than the figure is thick are merged.
- *Percepts.* Each object gets `cends` (free ends: triangle 3, square 4,
  circle 0, ellipse 2, plus sign 4) and `neck` (over the paths between free
  ends, the thinnest point ÷ the thinner of the thickest points on either
  side, both at least 3 px; 1 = no neck; BP #18), and, for a neck under
  `ext_core_neck`, `neckvert` (how vertical the path runs through it; BP
  #19). Open figures also get `cjunct` (junctions) and `corder` (the
  deepest side branch, counting from the longest path: 0 a simple path, 1
  branches off it, 2 branches of those; BP #70). In a closed figure the
  junctions only join the limbs that run into corners, so they restated
  `cends`, and on BP #5 they competed with it for 11 runs of 20.
- *Similarity.* `ext_core_sim` weights the cores' difference (their ends,
  junctions, and branch-length profile) in X6's shape distance. It is 0:
  on #57, #59, #60 and #91 a weight of 0.1 changed nothing and 0.2 or more
  broke #57 and #60, because small drawn figures' cores are noisy (a
  triangle of 200 px may lose a corner). The paper's use of the core —
  matching two figures by their structure — is not reached this way.
- *Judging.* The parts problems (#86–#90) accept a count of core ends,
  #18/#19/#70/#92 are scored by the new percepts, and BPs #5 and #6 accept
  core ends as one per corner, as BP #6 accepts "three sides".

`ext_core = 0` leaves all of this out.

Measured on the real BPs (one look, seed 1): BP #18's neck ratio is
0.41–0.54 in five left boxes and 0.93–0.99 in all six right boxes; the
sixth left figure is small (28 px) and its neck joins parts under 3 px
thick. BP #19's neck runs at 0–0.16 (horizontal) in five left boxes and
0.99–1.0 in all right ones; in the sixth left box the outline does not
close and the neck found runs at 0.45, still below every right box. BP
#70's order is 1 in five left boxes and 2–3 in five right ones. On BP #86
the core has 3 free ends in every left box and 5–6 in every right one.

Survey of the 85 (`results/survey_20.txt`, 20 runs; `survey_20_nocore.txt`
the same with `ext_core = 0`): 21 solved, 14 reliably, against 19 and 12.
#19 goes 0 → 20 ("object neck horizontal"), #86 0 → 19 ("object core with
fewer ends"); no other problem moves by more than 3 runs. #18 and #70 stay
at 0 in 20 runs: one box per side that the core gets wrong is enough to
fail an "all" idea. Costs on
Appendix A and the synthetic set are in `results/survey_scored.md`.

**X13. Categorisation by the Generalized Context Model.** Foundalis's 2013
report takes categorisation to be Nosofsky's GCM: a weighted distance
between exemplars, a similarity `s = e^{−(c·d)^q}`, and the probability of
category J, `P(J|i) = Σ_{j∈J} s_ij / Σ_K Σ_{k∈K} s_ik`. It also proposes a
hybrid: exemplars kept one by one until a category's sample is large, then
its mean and spread. A learned concept here is already such a hybrid (its
core is a pattern, §8.3), and its similarity to an object is
`exp(−difference)` (Eq. 8.8), the GCM form with q = 1. So
`gcm_choice` (src/ltm/learned.jl) only adds the choice rule. Each retrieved
concept's similarity is raised to `ltm_gcm_c` (the sensitivity c; 8), and
the best concept is taken when `s_J / (β + Σ_K s_K)` passes a draw of
`category_p` (N(0.5, 0.03)). That one decision replaces D41's threshold
and margin. β = `ltm_gcm_base`^c (0.6) is the similarity of a concept the
object is not an instance of: without it a lone concept would win every
object, and the report's rule for forming a new category (the best P too
low) would never fire. Two equally good concepts give P just under ½, so a
tie is rarely decided; a weak lone match gives P ≈ 0.33 at s = 0.55.

Measured on BP #6 after the Mentor's lessons (`bench/run_mentor.jl`,
`results/mentor_20.txt`; 20 runs, one look at each box, 240 figures). Each
row gives the figures categorised correctly, precision, and recall.

| lessons | D41 | GCM |
|---|---|---|
| triangle, quadrilateral | 193, 0.92, 0.80 | 204, 0.91, 0.85 |
| + pentagon, circle | 161, 0.88, 0.67 | 175, 0.89, 0.73 |

BP #6 itself is solved 19–20 of 20 either way. With four concepts, c = 4
gives precision 0.93 but recall 0.47, and c = 16 gives 0.82 and 0.78; the
defaults were set before these runs and not tuned to them. `ltm_gcm = 0`
restores D41.

**X14. A memory of solved problems, and spontaneous analogy.** The report's
account of analogy (Fig. 9) is that a situation is stored as its core, "the
most abstract and generalized parts" of it. A later situation's core is
categorised among the stored ones, and one that lands near an old core
activates it: the analogy is spotted without being looked for.
`src/solver/memory.jl` does this across Bongard problems.

- *Episode.* When a problem is solved, its core and its answer are kept in
  the LTM (`ltm.episodes`).
- *The core of a problem.* After the holistic look, each feature at a
  place and each kind of node in the box patterns gives one dimension: the
  fraction of the twelve boxes that show it, weighted by its concept's LTM
  weight (the report's w_k). Values are dropped (the attrition of detail),
  and so are counts: whether a count is there records whether the counting
  codelets finished on that look (D38), and it made the same problem's
  cores differ by up to 0.2 from look to look. Without counts, the same
  pair (#36 → #37) measures 0.036–0.084 over six seeds.
- *Distance.* Weighted mean of the absolute differences of the fractions; a
  dimension one core lacks counts as 0. Over all pairs of the 100 problems
  the nearest neighbours are thematic: #36/#37/#38/#47 (circles and
  triangles placed), #25–#28/#48/#81 (filled and outlined), #52/#67–#69
  (branches), #84/#92/#93 (chains), #19/#20 (necks).
- *Reminding* is GCM (X13) over episodes, with the episodes that share an
  answer (whatever its split and sides) as one category. The similarity is
  `exp(−ext_memory_c × d)` (60), and β is the similarity at
  `ext_memory_base` (0.06). The report says the new core activates the old
  ones "the nearer, the higher", and the nearest solved problem is often
  not the analogous one, so up to `ext_memory_recall` (3) categories whose P
  passes a draw of `ext_memory_p` (N(0.2, 0.02)) come to mind, best first.
- *Transfer, with slippage.* A remembered idea is refitted to the new boxes.
  Its place may slip to any place whose node types differ only in their
  tags (`contrast@filled_outlined` → `contrast@filledcircle_outlinedcircle`,
  `pair@circle_triangle` → `pair@filled_outlined`). Its split is recomputed,
  or its sides chosen for existence and sameness ideas. The candidate the
  boxes bear out in most boxes is kept if that is at least `ext_memory_fit`
  (10) of twelve. Only then are its concepts primed (`ext_memory_marks` × P)
  and the idea verified, before the holistic stage. A result found this way
  has stage `:analogy`. Priming every recalled answer, borne out or not, was
  tried first: it steered later problems' attention (BP #27 17 → 8 correct,
  in runs where #27 itself recalled nothing useful).

Measured (`results/pairs_20.txt`, `bench/run_pairs.jl`): solving A then B
in one context, 20 runs.

- #36 → #37: B is solved by analogy in 16 of 20 runs (18 → 19 correct,
  mean ticks −5%).
- #27 → #28: 5 runs by analogy; correct 7 → 9, wrong 9 → 6.
- #37 → #48: one run by analogy (already 19/20 without memory).
- Pairs that only look alike (#36 → #38, #19 → #20, #2 → #3): no analogy
  verified, no wrong answers, ticks within 3%.

Over Bongard's 100 problems in order, one context carried through, 20
seeds (`results/sequence_20.txt`, `bench/run_sequence.jl`): correct
539 → 544, wrong 46 → 38, mean ticks +1.5%. 19 runs are solved by analogy:
#28 from #27 and #25, #37 from #36 and #27, #48 from #27, #9 and #12 from
earlier one-figure problems (#3, #5, #9), #26 and #81 from #25. Problems in the book rarely share a rule
with an earlier one PhaeacoX solves, so the total moves by about the noise
of 2000 runs; the effect is clear only where an analogue exists.
Per-problem swings of up to 4 runs with no analogy at that problem
are the context's state diverging.

Not done: episodes are not saved by `save_ltm`, and they are never
forgotten. Nor is the report's further step, a conscious search for more
analogous parts once a reminding has happened.

**X15. Object individuation as clustering.** The report begins its chain
with object individuation. Dots dense enough make a region: "we can make
the dots so dense that their in-between spaces are hard to discern. In that
case the observer has no choice but see two contiguous dark regions." The
retina's objects are connected pieces of ink, so a triangle drawn as
hatching is twenty separate lines (BP #96). `src/ext/individuate.jl`
closes the gaps between nearby pieces in any box with at least
`ext_ind_parts` (4) objects. The closing joins ink within `ext_ind_gap`
(3) pixels by dilating, then eroding, by a disc of that radius. A joined
region uniting at least 4 pieces, its holes filled, becomes a `cluster`
node. Its kind (`shape@K`) comes from its outline by X2's rule: hull
corners, with round when the hull fills the inscribed ellipse. It also gets
`ccorners` and `cends`, the free ends of its core (X12). Figures more than
6 px apart are never joined, so ordinary boxes are left alone (a test
checks four separate circles).

Measured on #96 (one look per box): the hatched figures are triangles with
3 outline corners in all six left boxes, and quadrangles in four of six
right ones. II-B and II-E read as triangles; II-E is a kite whose fourth
corner deviates less than X2's 18% tolerance. No rule then covers all twelve boxes, and #96 stays
unsolved. #98's triangle is a region of different texture in a patterned
grid: figure–ground segregation, which closing gaps does not address. Over
the 85 problems the only change is #66, 17 → 19 correct.

**X16. Structural similarity.** The report's Fig. 7 matches two figures
by their structure: the core "parsed as lines", with homologous parts. The
"black pixels" do not matter, and neither do fill, holes, size or place.
X6's shape distance charges for fill, holes, elongation and missing area,
and adding the cores to it (`ext_core_sim`, X12) did not help. So
structural similarity is a percept of its own (`_structural_similarity!`).
Two figures are alike when their kinds agree (as in X6) and their cores do
(`core_distance`). Two cores without junctions are compared as equal: a
blob's point and a stroke's line have no limbs to match, and the kind
already tells a circle from an ellipse. A box records `ssimmin` (all
figures alike), and, when it has three or more figures, `ssimmax` (some
two alike); with two figures "some two" would only repeat "all". The
first version recorded both and answered #59 with "some two figures alike"
in 10 runs of 20, which the judge scored wrong.

The core graph also changed: branches are now spliced through nodes where
only two meet (`_splice`). Pruning and merging left such nodes, and they
made one limb read as two in the branch profile (two circles, both with
2 ends, measured unlike). On #59 structural similarity holds in all six
left boxes and in no right box (one look). The survey's #59 goes 0 → 19
("all figures alike in structure"). No other problem's answers change,
and #57 and #60 keep their X6 answers.

**X17. A closer look at cores.** When an idea about a figure's core is
verified, each box is looked at again (D31). With `ext_core_focus = 1`,
that look sees cores magnified to about `ext_core_scale` (48) pixels
across, and its core values replace the box's earlier ones instead of
being merged with them. An analytic idea about cores may also be formed
despite one contradicting box, since the closer look may see that box
otherwise. Magnification is by f × f blocks rounded by a 3 × 3 majority.
Bilinear interpolation was tried: it turned the 1–2 pixel bumps of drawn
outlines into limbs, giving circles 5–15 core ends.

Result: no gain, so the default is `ext_core_focus = 0`. On BP #18 the
neck idea is now formed and verified in every run, and fails on box I-F
every time: its neck ratio is 0.96, 0.83, 0.93 and 0.84 at magnifications
1–4, against a split near 0.74. BP #70's errors come from which path is
taken as the main one, not from resolution. The 85-problem survey is
identical with the closer look on and off.

`results/mentor_20.txt`, `pairs_20.txt` and `sequence_20.txt` were measured
before X15–X17; the survey, Appendix A and synthetic files after them.
