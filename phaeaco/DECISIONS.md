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
