# Decisions

Every place the dissertation leaves a choice open, what was chosen, and why.
§ numbers refer to Foundalis (2006). Numbers in `params.toml` that are not
from the thesis point back here.

## Core

**D1. How a threshold distribution decides (§7.4.1).** The thesis says a
decision draws r from N(µ, σ) and outputs "yes" if r > µ. Read literally that
is a coin flip whatever the input, so the intent must be that r *is* the
threshold for that decision: the measured value is compared with a fresh draw
of r. That is what `exceeds(x, thr, rng)` does.

**D2. The sigmoid's shape (§7.2, Fig. 7.19).** The thesis fixes the form (a
hyperbola piece, a linear middle, the mirrored hyperbola; division the most
expensive operation; symmetric about (½, ½); limits l and 1 − l) but not the
parameters, and says the joints need not be smooth. We make them smooth
anyway, because a kink would make one mark of activation worth suddenly more
than its neighbour for no reason. With the lower piece c + 1/(b − a·x), the
three conditions (passes through (0, l), through (x1, y1), and matches the
middle's slope at x1) have a closed-form solution. Defaults: x1 = 0.25,
y1 = 0.1, l = 0.001.

**D3. Decay is lazy.** An activation records the tick it was last brought up
to date and drops ⌊Δt / period⌋ marks when next read. This is the same
behaviour as decrementing every node on every tick, at a fraction of the
cost. At mark 0 the value is l, never 0 (the open interval of §7.2).

**D4. Coupling activation to significance (§9.3.1).** Each time a prime
leaves the activation at its maximum, significance advances one mark; each
time *that* leaves significance at its maximum, significance's stability
grows by `growth` marks. "Several orders of magnitude slower" is taken as
decay periods two to three orders of magnitude apart (act 10 ticks,
significance 5000).

**D5. Variance is the sample variance.** Eq. 8.10 divides by N (the old
count, i.e. n − 1 for the new sample), and the worked example (slopes 65 and
75 → 50) confirms n − 1.

## Input

**D6. Coordinates.** Boxes are indexed [y, x] with y down. Angles reported
to the cognitive level use y up (a line rising to the right is +45°).

**D7. No image library.** Everything is standard-library Julia; boxes are
read and written as PBM. Real BP GIFs are converted outside the package.

**D8. Synthetic BPs are analogues.** Each isolates the mechanism of one
target BP, with other features varied. Where the thesis does not say what
the real BP shows (e.g. the counts in BP #23), the analogue picks something
that exercises the same mechanism (two figures vs. three).

## Retina (ch. 10)

**D9. Orthogonal least squares.** Lines are fitted by minimising
perpendicular distance (principal axis of the scatter matrix) rather than
vertical distance, so vertical lines need no special case.

**D10. Process F follows the border.** The thesis has F send 16 rays from a
few source pixels deep in a filled region and treat where they leave as
border pixels. Sixteen isolated points cannot describe a polygon's sides, so
from each ray hit F also walks along the border, staying near the thick
region (thin attachments are described by their own skeleton). A border
pixel is a foreground pixel with a background 4-neighbour. Every thick object
gets at least one source, however small its skeleton.

**D11. Process A visits a random permutation.** "Testing pixels at random
locations" with replacement would miss a four-pixel dot more often than the
thesis allows ("practically zero"). A random permutation keeps the order
random and the coverage complete; A still retires early (after 90% of the
box, once its hit rate is low), so an isolated pixel can go unseen. B pulls
in the neighbours of every pixel it handles, so a figure is fully seen once
any of its pixels is hit.

**D12. B also records stroke depth.** Alongside altitude, B records the ring
at which it stopped, ≈ half the local stroke width + 1. Regions with depth ≥ 3
(strokes about 5 px or more) are "thick". An object's texture is the fraction
of its ink that is thick; it is filled when that exceeds a sampled threshold
(≈ 0.3). Thick lines therefore become filled objects, as in Fig. 7.6. Small
objects are judged at the zoomed scale.

**D13. Process H does more than merge duplicates.** On top of §10.3.9's
unification: (a) a gap between collinear detectors longer than usual is
bridged if ink runs across it (another line crossed there and took the
points); (b) short detectors whose points other lines already explain are
dissolved; (c) one reassignment pass gives every point to the line it fits
best; (d) after E, a short line meeting a nearly collinear one end to end is
absorbed into it. Each was added for a failure seen in
`bench/retina_score.jl`: split sides, corner fragments, sides stopping short
of a sharp vertex.

**D14. The ellipse test, from measurements.** Drawn circles and ellipses fit
the Appendix B conic with rms 0.2–0.45 px at every size tested; polygons fit
at 0.5 px or worse unless they are about 16 px across or less, where an
octagon or pentagon is round to the eye as well (cf. Fig. 5.13). So: an
ellipse is a closed or nearly closed string, or a whole object, whose conic
fit has rms ≤ 0.5 px (in box pixels) and whose points go ≥ 85% of the way
round. Curvature from process G is not required. The circle threshold on
eccentricity (0.45) is the thesis's.

**D15. Straightness tolerances grow with length.** A point joins a line
within 1.2 px + 0.012 px per px of length, and the rms limits grow by 0.008
px per px. This keeps a hand-drawn 50-px side from splitting at a wiggle.

**D16. Exact enclosure; scalar elongation.** Enclosed regions are found by
flooding from the box edge with one object as the obstacle, which gives
exact interiors, areas and "inside" relations. The thesis's ray-escape test
(§7.4.7) is used for the openness of *concavities*, and its Monte Carlo area
(§10.3.18) is not needed at 100 × 100. Elongatedness is the scalar
1 − √(λ₂/λ₁) of the silhouette's second moments, not the vector along the
skeleton of §7.4.8. That is the thesis's own "special case" for objects with
a linear skeleton, which covers the BPs in the target set.

**D17. Not yet implemented in the retina.** Process S (shrinking objects
made of many short lines, §10.3.16) is not yet implemented; it matters for
BP #7, which is outside the target set. Pipelining (Fig. 10.1) is at the
level of the box: the cognitive level starts on a box once its retina has
settled, rather than on individual detectors mid-stream.

## Workspace and LTM primitives (ch. 7, ch. 9)

**D18. Urgencies and built-in salience.** The thesis gives only the ordering
of codelet urgencies (§7.1): a line segment's slope and length very high
(90, 85), its count medium (50), its width very low (10, ends and middle are
not implemented). Texture is high (80) and also has the highest built-in
significance in LTM (§11.1.1). The convex hull is low (10) (Fig. 7.8 is
"one of the last perceptual elements"), but once the hull exists its
"missing quantity" codelet is high (70), as §7.1 says of hull area. A
barycenter's coordinates are high (85: "almost always selected"). An
intersection's coordinates are very low (8). The values live in
`build_primitives`.

**D19. How the coderack chooses (§7.2).** The thesis says activity ends while
low-urgency codelets are still waiting. If the most urgent codelet always
ran, the leftovers would eventually run too. So a codelet is drawn with
probability ∝ urgency and then runs with probability (u/100)^γ, γ = 2;
otherwise the tick passes. A codelet's urgency is its base urgency ×
(1 + LTM weight of its feature concept), set when it is posted, so priming
a concept makes its codelets likelier (§7.1).

**D20. "Area" of an object.** For a closed or filled object, the area it
covers (ink and enclosed interior). For an open figure (a Λ, a zig-zag), the
area of its convex hull, which "gives a rough idea about how large an
object these lines make" (§7.1).

**D21. Identified shapes and their parts.** Lines that are only the retina's
approximation of a circle, ellipse or curve are not perceived as line
segments; the circle node stands for them. The object node is kept, with the
circle as its child, rather than replaced by it. This keeps object-to-object
matching uniform. A closed line string damps its lines' codelets (§7.4.4)
but carries the count of its lines itself (Fig. 7.30).

**D22. Clocks.** Workspace activations run on the box's own tick count, so
a box decays at the same pace whether it is looked at alone or with eleven
others; LTM runs on the global clock. A box's retinal work is charged to it
at 40 retinal steps per tick. A box is seen when its node's activation drops
below a sampled 0.15, once P has nothing left to perceive.

**D23. Counting.** σ₀ = 0.1, so counts up to five are reported exactly about
99% of the time, and larger counts drift (§7.3.2). Process Q watches the
nodes process P builds; once a context holds "many" of a type (a sampled ≈ 5),
further ones are only counted, and the per-item codelets of those already
there are damped, except their counting.

**D24. Shared feature nodes keep exact values.** When two objects share a
feature node (practically equal values, §7.1), each parent also records its
own exact value on the link, so matching (§8.2) compares exact values while
the shared node still shows the equality.

## Matching and patterns (ch. 8)

**D25. The accumulator and Welford's formula pull apart (§7.3.2).** The
thesis claims both that counts up to five are reported "almost always"
exactly and that its sequential comparison yields Welford-like reaction
times. With accumulator noise σ₀√n, a σ₀ small enough for the first claim
(0.1) makes comparisons of everyday quantities instantly confident: 26 vs 25
is resolved within the initial m = 12 samples. Reaction time does grow with
L/(L − S), as Welford says, but only for large, close quantities (200 vs 198,
300 vs 299). We keep σ₀ = 0.1 and record the tension (`compare_counts`,
tested in `test_patterns.jl`) rather than tune it away. It does not touch
the target BPs, which compare small counts.

**D26. Variance floors.** When comparing with a sample whose values are all
equal, its standard deviation is floored at 1% of the feature's range, so no
other value is infinitely improbable. Discrete features (texture) have no
floor, which is what lets two zero-variance samples of different textures
differ with certainty (BP #3, §11.1.1). Two-sample count comparisons keep
the accumulator's own spread for the same reason.

**D27. A feature difference is distance weighted by improbability.** Read
literally, Eq. 8.2 makes the difference between an exemplar and a sample the
probability that it comes from a different population. For a genuine member
that probability is uniformly distributed on [0, 1], so at the thesis's
clustering threshold (similarity 0.83, d < 0.19) about one member in five
would be admitted, and the Patterns algorithm could not score anything like
Table 8.1's 98.5. Measured: the literal reading scores 64. We use the scaled
difference of Eq. 8.1 weighted by that probability. It equals Eq. 8.1 when
neither side is a sample, and discounts deviations the sample's spread
accounts for. With it, Patterns scores 99.6 ± 2 with its best threshold at
0.85 (tolerance 0.80–0.89), against the thesis's 98.5 ± 7 at 0.83
(0.78–0.88) (`results/clustering.txt`). The thesis's benchmark cases and
performance index are unpublished, so ours are an approximation (Rand index
on 1-D groups). On them leader and Lu & Fu do about as well as Patterns,
unlike the thesis's 92.9 and 78.8. That part is not reproduced, and is
reported as such. `match.literal = 1` restores the literal reading. The
probabilities themselves are still what the solver uses to notice that two
sides differ (§11.1.2).

In Fig. 8.6, when the pattern a new exemplar would form with its closest
kept exemplar resembles an existing pattern, the thesis discards the new
pattern without saying what becomes of the exemplar. We keep it, on its own.

**D28. Counts and parts in structural matching.** A count enters matching as
the integer the accumulator reports. A count missing from one side is
compared as zero if that side has no parts of the type, and ignored if it
has some that were not counted on that look, as a missing feature is
(§8.2.3). Parts are matched type by type, each part of the side with fewer
to its best counterpart. A type of part present on one side only counts as
wholly different, weighted by its link strength. Each level down is damped
by 0.5, and recursion stops after three levels (§8.2.4: "two or three
recursive steps"). A count's weight is the LTM weight of numerosity times
the square root of that of the counted type.

## The solver (ch. 11) and sameness (§7.4.10)

**D29. What an idea is.** An idea compares one thing across the sides. That
thing is a feature at a place in the representation (every object's area,
the x of every object's barycenter), a count (lines per object, or lines
anywhere in the box), the existence of a kind of node (a closed interior, a
circle), or the existence of a for-all node (§7.4.10). The idea also carries
a split point and a direction. An "all" idea requires every instance on
each side to fall on its side of the split. A "some" idea requires every
box of one side to have an instance beyond the split, and no box of the
other side to have one (BP #21). The thesis's own idea types
(feature-value difference, existence, structural difference) map onto
these. Structural difference appears as counts ("three lines" vs "four")
until LTM concepts exist (phase 7).

**D30. Holistic ideas.** After the parallel look, every feature, count and
kind found in the box patterns is compared across sides. A feature's
salience is the probability that the two sides' distributions differ times
the feature's LTM weight (§11.1.2, footnote 85); counts are treated likewise
with Eqs. 8.4–8.6, and an existence difference has salience equal to the
kind's LTM weight. An idea needs five of six boxes per side to show the
thing, and a salience above 0.15. One is picked with probability ∝
salience², and if it fails verification the analytic stage begins, as in
§11.1.2. A discrete feature with zero variance on both sides and different
values ends the run without verification (§11.1.1).

**D31. Verification.** Each box is looked at again with the idea in focus:
its concepts are primed, and anything the idea needs that the look missed is
perceived top-down (the convex hull and its missing area, a count, the
sameness of a shared feature). This follows "verifies this idea by quickly
looking at each box" (§5.1.1). The new look is merged into that box's
pattern of looks (§11.1.2). Verification stops at the third failing box. If
one or two boxes failed, each gets two more looks (§11.1.3, BP #192).

**D32. Analytic ideas.** Each analytic iteration re-looks one box, chosen
with probability ∝ 1/(size of its representation) (§11.1.3: simpler boxes
more often). An idea comes from one node of that box, chosen by its type's
LTM weight (so a for-all node, a "structural curiosity", is noticed sooner
than a line), and from one of its features, counts or its existence. It is
formed if the boxes seen so far do not contradict it: one box per side with
data is enough, and verification looks at them all. A count idea is tried
at its own place first, then box-wide ("counting lines?" before "counting
things"). With probability 0.3 per iteration the side patterns are also
compared again, now allowing "some" ideas. Failed ideas are recognised
regardless of split point.

**D33. Motivation.** The master node of failed ideas has an activation of 20
marks, decaying one mark per 500 ticks; each new idea adds 5. Phaeaco gives
up below a sampled 0.15. The decay was set so that giving up takes about
five times as long as solving BP #3, which is the ratio of no-answer times
to BP #3's time in Appendix A (BP #4: 23.8 s, BP #22: 23.3 s, vs 4.3 s).

**D34. Sameness and for-all.** Only in analytic looks (§7.4.10: "cannot happen
during the holistic stage"), a feature node that gains a second sharer
posts the sameness codelet, with urgency 40 × min(1, (sharers − 1)/2). It
builds an equality node. If every node of that type in the context shares
the value, it builds a for-all node whose tag names the type and feature
(`:object_texture`), meaning "all objects have similar texture" (Fig. 7.52).
The slope "same" tolerance is 6°, so that "almost parallel" (BP #39) counts
as the same slope.

**D35. Synthetic BPs must not leak.** Several first-draft generators gave the
solver accidental rules that held on all twelve boxes: every elongated
figure was an ellipse, compact figures were larger, only concave shapes had
short sides, "same size" boxes mixed shapes of equal radius but unequal
area. The solver found those rules and verified them, which is correct
behaviour, so the generators were fixed so that only the intended rule
separates the sides. The judge accepts equivalent descriptions that hold by
construction ("three lines" for "triangles").

## First contact with the real BPs

These came from running the fifteen real target BPs (`bench/run_real.jl`,
`results/real_20.txt`). Each fixes a failure that only real drawings showed.

**D36. Slope is circular.** Lines at 178° and 2° are parallel. Slope sharing,
matching and pattern statistics use the short way round with period 180°
(and its maximum for Eq. 8.1 is 90°). Values are unwrapped to stay within
half a period of a node's mean, so means stay coherent. Without this, BP #39
never found its parallel lines.

**D37. A figure enclosing a meaningful interior is outlined.** Small outlined
figures in BP #3, zoomed ×2, have outlines thick enough to pass the
thick-fraction test for "filled", although they plainly enclose white. A
figure is filled only if its thick fraction passes and its interiors are
under 12% of its area. Zoomed objects take their sub-retina's verdict. With
this, BP #3 is solved by the zero-variance shortcut, as in the thesis.

**D38. An incomplete count is not a count.** If a count node has not yet
reached every node of its type in its context (some counting codelets did
not run), the exemplar leaves it out rather than passing on the smaller
number. It is "not counted yet", which matching and ideas already treat like a
missing feature.

**D39. Hulls from pixel centres.** The convex hull is built from the centres
of border pixels, not their corners. Corners add a half-pixel rim that made
small convex figures read as 10% "missing" (concave). With centres, convex
figures measure ≈ 0 at every size, and the concavity threshold drops to 4%.

Also from the real BPs: process G's curve-joint rules were tightened
(a gentle turn is ≤ 15°, a bow must be ≥ 0.5 px), because an obtuse polygon
corner (BP #6, box II-C) was being taken for a curve. The sameness detector
groups values within twice the "same" tolerance, the context-driven
relaxation of §7.1, and is posted whenever a box holds two values of a
feature (D34). Fragment absorption works at any junction, including the
K-point at a thin triangle's tip. Existence ideas respect the is-a hierarchy
(a circle is an ellipse is a curve). An entirely empty side is the hardwired
"nothing vs something" of §11.1.1.

## Real BP images

**D40. Where the images come from.** Foundalis's site renders each BP's GIF
at native size; this sandbox cannot reach it directly, so each page was
captured as a lossless screenshot through a scraping service and converted by
`bench/fetch/screenshot_to_bp.py`. That script finds the twelve 100 × 100
frames, takes their 98 × 98 interiors, pads them with one white pixel to
100 × 100, and orders them I-A..I-F, II-A..II-F. The PBM stacks live in
`data/` and are not committed: the problems are from Bongard's book and the
web copies state no licence.

## Learning (ch. 9, §5.2)

**D41. The Mentor, categorisation and association.** The thesis's Mentor
pairs drawings with phrases; that linguistic part was unfinished and
unpublished, so here a lesson is a set of drawings with one label, and the
largest object of each is learned under it (`mentor!`, `lesson`). A learned
concept is a pattern (its *core*) plus index keys, linked is-a `object`.

- *Weight.* Being taught is significant in itself: each example primes the
  concept and also boosts its significance directly (`ltm_learn_sig_marks`),
  instead of waiting for the activation to max out by chance.
- *Categorisation* is a codelet posted for every object. It waits (reposting
  itself up to three times) until the object's lines and vertices are
  counted, since a sparse early representation can resemble the wrong
  concept. It attaches a category node only for a clear best match: the
  similarity must pass `category_match` (0.60) and beat the runner-up by
  `ltm_category_margin` (0.08). Precision is good; recall depends on the
  lesson (about 30% of objects in BP #6 after a three-sides lesson).
- *Ideas.* Because categorisation is a codelet, one look sees a concept in
  only some boxes. A concept seen on one side only, in at least half its
  boxes, is a candidate existence idea weighted by the concept's weight;
  verification decides.
- *Associations* (§9.3.2). Two concepts categorised in the same box prime
  their anonymous association by 8 marks. Its activation fades ten times
  more slowly than a concept's priming, since it is long-term learning; once
  its significance has grown through `ltm_relation_marks` (3) peaks, it is
  reified as a relation concept `with_A_B`, linked to both.
- *Persistence.* `save_ltm`/`load_ltm!` serialise the LTM; concepts whose
  weight has decayed to the floor are forgotten on saving.

## Counts against patterns

**D42. A count differs from a pattern's by a weighted prediction test.** Eq.
8.4 compares two single counts by their accumulator noise. Against a pattern
(a sample of counts) the standard error of the pattern's mean is the wrong
spread: a concept learned from outlined and filled examples has 0 or 1
interiors, and an example with either belongs to it. So the single count is
tested against the population, with a prediction interval
`√(σ0²·x + s²·(1 + 1/n))`, as for features. And, as D27 found for features,
a bare probability averages 0.5 for a genuine member, so it is weighted by
the difference in counts capped at one: a whole item more or fewer stays
decisive (a pentagon is not an odd quadrilateral), while a fractional mean
(3.4 lines) does not set every triangle apart. A version weighted by the
relative difference was tried and dropped: it let pentagons pass as
quadrilaterals.

## Held-out instances (phase 9)

**D43. What fresh drawings exposed, and what was changed.** The synthetic
BPs were developed on one drawn instance each (bpseed 1). Instances 2 and 3,
never looked at during development, showed two kinds of failure.

*Generator leaks.* Some answers judged wrong were true of the drawn instance:
every left figure a polygon and every right one an ellipse (`size`, so "lines
per object" separates the sides); a true circle in every right box
(`curves`); the right side always holding a figure smaller than any left one
(`same_size`). The generators now alternate round and straight figures by
box, give `curves` two ellipse-only boxes with clearly elongated ellipses,
and set `same_size`'s ranges so that neither "some small" nor "some large"
is a rule. The notched square of `random_concave` lost only 2–6% of its hull,
below what the retina reports as concave; its notch is now deeper. The judge
also accepts descriptions equivalent by construction: "≤ 0 curves" for "no
curve"; "> 0 interiors" for outlined (D37); and, for closed vs open, an open
figure's concavity interior (§7.4.7, Fig. 7.38: a bay is an open interior).

*Solver faults.*
- Filled triangles of radius 9–12 px have a thick-ink fraction of 0.26–0.32,
  straddling the filled threshold N(0.3, 0.03), so one look in three called
  them outlined and "all the same texture" failed verification. Outlined
  figures measure ≈ 0, and D37's interior rule separates outlines anyway, so
  the threshold is now N(0.15, 0.02). Verifying the texture for-all went
  from 4–19 of 20 to 20 of 20 on all three instances.
- "Same size" compares areas (§5.1: in BP #22 "it is the area of objects
  (approximately equal, of course)"). A circle, square and triangle of one
  extent differ by up to ~30% in area, beyond the old tolerance (0.12,
  widened ×2 by D34). Area's "same" tolerance is now 0.18; the right side of
  BP #22 differs by factors of 4–10. BP #22 went from 0% to 55%.
- An analytic look is costly, but only one of its ~30 nodes was attended to
  before the next look. If that node suggests nothing untried, attention
  now moves to another node of the same look, up to three
  (`solve_picks_per_look`). Give-up time is unchanged (D33).

*Tried and reverted.* Making the convex-hull codelet's urgency grow with the
retina's measured concavity took convexity from 0–4 to 25–27 of 30, but it
contradicts the thesis (the hull is "one of the last perceptual elements",
Fig. 7.8) and the test that encodes it. Without it, the fixes above bring
convexity to 5–6 of 30 on every instance, and BP #4 to 25%, close to the
thesis's 20%.

The rates of BP #22 (55%) and #56 (70%) are now well above Phaeaco's (13%,
19%). Lowering them toward Appendix A is phase 9's calibration question.

