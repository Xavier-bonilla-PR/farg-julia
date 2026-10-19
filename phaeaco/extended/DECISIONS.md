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

