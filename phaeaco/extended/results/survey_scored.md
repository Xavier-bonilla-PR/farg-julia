# PhaeacoX on Bongard's other 85 problems

Each problem was run 20 times (`survey_20.txt`). An answer is scored ✓ or
✗ where `SURVEY_RULES` (src/solver/judge.jl) states Bongard's rule in terms
PhaeacoX can perceive (38 problems); other answers are listed but not
scored, as in PhaeacoJL's survey (`../../results/survey_judged.md`).

## Solved

| BP | Rule (left / right) | PhaeacoJL | PhaeacoX | PhaeacoX's answer | Percept (DECISIONS) |
|---|---|---|---|---|---|
| #7 | elongated vertically / horizontally | 0 | **20** | "object vertical" | orientation (X8) |
| #10 | triangles / quadrangles (jagged sides) | 0 | **20** | "some triangle" vs "no triangle" | shape kinds (X2) |
| #12 | convex hull elongated / compact | 20 | 20 | "elongated" vs "compact" | — |
| #34 | a large hole / a small hole | 20 | 20 | "outlined" vs "filled" (D37) | — |
| #36 | triangle above circle / circle above triangle | 0 | **20** | "the circle lower than the triangle" | relations (X3) |
| #37 | the same, with distracting squares | 0 | **19** | the same | relations keyed by kind (X3) |
| #48 | filled figures above outlined / below | 0 | **20** | "the filled figures higher than the outlined figures" | relations (X3) |
| #60 | some similar figures / none | 0 | **20** | "some two figures similar" | similarity (X6) |
| #66 | loose circles in a horizontal / vertical line | 0 | **17** | "the circles in a horizontal row" | groups (X7) |
| #19 | neck horizontal / vertical | 0 | **20** | "object neck horizontal" | core: neck direction (X12) |
| #86 | three parts / five parts | 0 | **19** | "object core with fewer ends" | core: free ends (X12) |
| #89 | three parts / five parts | 19 | 19 | "≤ 4 objects per box" | — |
| #71 | inside figures of the second order / none | 0 | **17** | "figures nested more deeply" | nesting (X5) |
| #27 | more filled figures / more outlined | 0 | **16** | "more filled figures than outlined figures" | contrasts (X4) |
| #28 | more filled circles / more outlined circles | 0 | **8** | "more filled circles than outlined circles" (11 others: a side effect, below) | contrasts (X4) |
| #57 | identical figures / not identical | 0 | **9** | "all figures identical" | similarity (X6) |
| #24 | a circle / no circle | 5 | 5 | "some curve", "> 0 circles" | — |
| #30 | a line crossing itself / not | 0 | **4** | "some self-crossing line" | contours (X8) |
| #33 | an acute angle / none | 3 | 1 | "some vertex has an acute angle" | — |
| #72 | curve ends parallel / perpendicular | 0 | **4** | "object ends parallel" | contours (X8) |
| #88 | three parts / five parts | 1 | 1 | "≤ 10 lines in box" | — |

Scored the same way, PhaeacoJL solved 6 of these problems (3 reliably);
PhaeacoX solves 21, 14 of them in at least 15 of 20 runs. With core
extraction off (`ext_core = 0`, `survey_20_nocore.txt`, the same images)
it solves 19, 12 reliably: X12 adds #19 and #86 and moves no other
problem by more than 3 runs in 20.

## Wrong answers among the scored problems

- #28: half the runs answer "the filled figures larger than the outlined
  figures", true of these boxes but not the rule.
- #57: four runs answer "more identical figures", as one did before X12.
- #27, #66: two stray runs each; #65, #86: one each.

## A different rule true of the boxes (unscored)

As in PhaeacoJL: #43, #63, #100 (centre of mass), #76 (elongation), #25,
#26, #73, #81, #64 (area). Nearly all come from PhaeacoJL's percepts; the
extension added #25's "the filled figures smaller than the outlined
figures" and #28's "the filled figures larger than the outlined figures".

## Still out of reach

The percept exists but is too noisy to separate the sides:

- #47 (inside): a figure touching the one it sits in merges with it (X11).
- #59 (similar): the shape distance is too crude. Adding the cores'
  difference to it (`ext_core_sim`) did not help #59 and, from a weight of
  0.2, broke #57 and #60: the cores of small drawn figures are too noisy
  (X12).
- #18 (neck), #70 (side branches of the second order): the core measures
  the rule in five boxes of six on each side, which is not enough for an
  "all" idea to verify (X12).
- #29 (more inside than outside) and #41, #40, #65 (lines of figures):
  missing figures in some boxes.
- #62, #72 (curve ends): too few strokes with exactly two free ends.
- #96, #98: the hatching or the patterned background breaks the outline.

No percept at all: spirals, symmetry, "three-ness"
(#91), arrows, Kanizsa completion (#46), occlusion ("on top", #45), and
distance comparisons (#79, #80).

## Cost on PhaeacoJL's own problems

On the fifteen of Appendix A (`real_20.txt`) PhaeacoX gives no wrong answer
PhaeacoJL did not; rates move within the noise of 20 runs (BP #5 85 → 70,
#4 25 → 20, #22 55 → 60, #56 70 → 65). On the synthetic set
(`synth_30.txt`) the slow problems lose some: same size 25 → 17, small
figure present 29 → 25, elongation 30 → 26. The new hypotheses compete for
the same patience (D33): on same size, PhaeacoX spends part of its time
verifying ideas like "more filled quadrangles than outlined ones" before
reaching the area rule. With the extension off (`ext_enabled = 0`) the
rates return to PhaeacoJL's.

With core extraction (X12) the files above are rerun. Appendix A: BP #5
70 → 100 (16 of 20 runs answer "core with more ends", a core end per
corner, which the judge accepts as it accepts "three sides" for a
triangle), #4 20 → 10, #22 60 → 50, #56 65 → 60, #21 85 → 80, the rest
unchanged; no new wrong answers. Synthetic set: interior 27 → 19 correct,
3 → 11 wrong. Ten runs answer "some box: object core with more ends": the
generator's closed figures are polygons and its open ones two-ended
strokes, a leak in D35's sense; the real closed/open problem, BP #15,
stays at 100. Convexity 7 → 2, the others within 5 of 30.
