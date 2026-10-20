# Bongard's other 85 problems

PhaeacoJL was run 20 times on each of Bongard's original problems that are
not among the fifteen of Appendix A (`survey_20.txt`; images from
foundalis.com, converted as in D40, not committed). An answer is a verified
idea: it holds on all twelve boxes. Whether it is Bongard's rule was judged
by reading the answer against the rule on Foundalis's solutions page, and by
looking at the boxes.

## Solved: the intended rule, or an equivalent

| BP | Rule (left / right) | Solved | PhaeacoJL's answer |
|---|---|---|---|
| #12 | convex hull elongated / compact | 20/20 | "object has elongated elongation" vs "compact". The thesis calls this hard (§7.4.6, Fig. 7.10: box II-C's figure is compact only through its convex hull; 7 of 30 people solved it). PhaeacoJL's elongation comes from the second moments of the figure's pixels, which spread like the hull, so it sidesteps that difficulty instead of meeting it |
| #89 | three parts / five parts | 19/20 | "≤ 4 objects per box" vs "> 4" (and "≤ 3 objects in box" once) |
| #34 | a large hole / a small hole | 20/20 | "outlined texture" vs "filled texture": a figure is outlined when its interior is a meaningful part of it (D37), so here outlined means a large hole. An equivalent by PhaeacoJL's own definition, not by Bongard's words |
| #24 | a circle / no circle | 5/20 | "some curve" vs "no curve" ×3, "> 0 circles in box" ×2 |
| #33 | acute angle / no acute angle | 3/20 | "some object's vertex has acute angle" vs "no …" |

## A different rule that is true of these twelve boxes

Verified, so true of the drawings, but a side effect of how they were drawn
rather than Bongard's rule. A person would likely reject these.

| BP | Rule (left / right) | Answered | PhaeacoJL's answer, and why it holds |
|---|---|---|---|
| #43 | wave amplitude grows to the right / to the left | 20/20 | "object's center has right x": a growing wave has its mass on the right |
| #63 | shading thicker on the right / on the left | 20/20 | "object's center has right x": thicker shading moves the ink's centre right |
| #100 | the letter А / the letter Б | 20/20 | "no object's center has left x": Б's stem pulls its centre left |
| #76 | long sides concave / convex | 19/20 | "elongated" vs "compact": the concave-sided figures happen to be the thinner ones |
| #66 | loose circles in a horizontal / vertical line | 18/20 | "no object's center has high y": a vertical column puts a circle near the edge |
| #26 | a solid black triangle / none | 11/20 | "some object has small area": the black triangles are the smallest figures |
| #25 | the black figure is a triangle / a circle | 10/20 | "some object has small area": same reason |
| #81 | filled and outline figures separable by a line / not | 8/20 | "no object has small area" |
| #73 | ellipse and rectangle axes perpendicular / parallel | 7/20 | "no object has large area" |
| #9, #10, #29, #65 | — | 3–4/20 | line length, an acute vertex, area |

Fourteen more BPs (#28, #36, #44, #60, #61, #62, #68, #77, #82, #84, #88 and
others) produced a single stray answer in 20 runs; none is the rule.

## No answer

The remaining ~60 BPs got no answer in any run, or only the strays above.
They need what Phaeaco (and this reconstruction) does not have:

- orientation of figures and axes (#7, #13, #19, #35, #65, #95),
- relations between figures: above, inside, on top of, closer to, on a line,
  arranged clockwise (#36–#38, #40–#42, #45–#48, #51, #54, #64, #79, #83,
  #84, #99),
- comparing counts or figures within a box (#27, #28, #29, #38, #53, #57–#60),
- curve shape: spirals, necks, self-crossings, branches, tails, symmetry
  (#16–#20, #30, #50, #62, #67–#72, #74, #92–#94),
- counting "parts" of composite figures (#31, #85–#88, #90, #91), except #89,
- shape categories it was not taught (#10, #96–#98: triangles and
  quadrangles built from small elements).

## In sum

Of Bongard's 85 other problems, PhaeacoJL solves 3 reliably (#12, #34, #89)
and 2 occasionally (#24, #33). On 9 more, it consistently finds a rule that
does separate the twelve boxes but is not Bongard's. The thesis lists the
fifteen BPs of Appendix A as the ones Phaeaco solves, so these 5 go beyond
that list, but two of the reliable ones come through shortcuts: #12 through
how elongation is measured, #34 through PhaeacoJL's definition of
"outlined" (D37). Only #89 is solved the way a person would put it.
