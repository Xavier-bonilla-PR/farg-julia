# PhaeacoX — PhaeacoJL with the abilities Phaeaco lacked

PhaeacoX is a fork of [PhaeacoJL](../README.md), the reconstruction of
Foundalis's Phaeaco. It adds what §11.2 of the thesis ("What Phaeaco can't
do") and the survey of Bongard's other problems
(`../results/survey_judged.md`) showed missing. Foundalis calls these
enhancements that fit the existing architecture; they were never in his
Phaeaco, so PhaeacoX is an extension, not a reconstruction. PhaeacoJL is
left untouched, and with `ext_enabled = 0` PhaeacoX behaves like it.

What it adds (`julia/src/ext/extend.jl`, decisions in `DECISIONS.md`):

- shape kinds: circle, ellipse, triangle, quadrangle, polygon, cross, …
- relations between figures by kind: above, larger, inside (BP #36, #37, #47, #48)
- count contrasts: more filled than outlined, inside than outside (#27, #28, #29)
- nesting depth (#71), shape similarity and identity (#57, #59, #60)
- groups of like figures: on a line, horizontal or vertical row, outline (#40, #41, #65, #66, #96)
- orientation (#7), self-crossing strokes (#30), curve ends (#62, #72)
- the core of a figure (`julia/src/ext/core.jl`, X12), after Foundalis's
  2013 report on core extraction: the figure thinned to the pixels
  farthest from its border and parsed as a graph — its free ends (one per
  limb or corner), junctions, side branches, and necks (#19, #86)

## Results

On Bongard's 85 problems outside Appendix A (`results/survey_scored.md`,
20 runs each), PhaeacoX solves 21, 14 of them in at least 15 of 20 runs.
Scored the same way, PhaeacoJL solves 6 (3 reliably). New among the
reliable ones: #7, #10, #19, #27, #36, #37, #48, #60, #66, #71, #86. Core
extraction accounts for #19 and #86; with `ext_core = 0` the count is 19
(12 reliably).

On the fifteen of Appendix A (`results/real_20.txt`) it gives no new wrong
answers. On the slow synthetic problems it loses some success, because the
extra hypotheses compete for the same patience (`results/synth_30.txt`;
same size 25 → 18 of 30). The core finds an unintended rule on the
synthetic closed/open problem (interior 27 → 19 of 30; see
`results/survey_scored.md`).

```bash
julia --project=phaeaco/extended/julia phaeaco/extended/julia/test/runtests.jl
julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_survey.jl 20     # the 85, scored
julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_real.jl 20       # Appendix A
julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_synth.jl 30      # synthetic set
```

The BP images are shared with PhaeacoJL in `../data/` (not committed).
