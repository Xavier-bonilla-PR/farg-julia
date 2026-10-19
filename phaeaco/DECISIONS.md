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
