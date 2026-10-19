# PhaeacoJL — a reconstruction of Phaeaco

**This is not Phaeaco.** Phaeaco is Harry Foundalis's FARG architecture for
Bongard problems, the subject of his 2006 Indiana University dissertation
*Phaeaco: A Cognitive Architecture Inspired by Bongard's Problems*. Its source
code was never released. PhaeacoJL is rebuilt, in Julia, from the
dissertation's written description. Wherever the thesis leaves something
open, the choice made here is recorded in [`DECISIONS.md`](DECISIONS.md) with
the passage that constrains it.

Because there is no original to compare against, "correct" here means
something weaker than in `../copycat` and `../metacat`. See
[`PLAN.md`](PLAN.md) §1 for what is checked and how.

```
julia/src/core/      activation, significance, statistics, parameters, trace
julia/src/input/     boxes and BPs, PBM files, synthetic problem generator
julia/src/retina/    the retinal processes of ch. 10
julia/src/ltm/       the conceptual network: primitives, learned concepts, Mentor
julia/src/workspace/ representations, codelets, processes P, Q, R
julia/src/patterns/  matching (§8.2), the Patterns algorithm (§8.3)
julia/src/solver/    ideas, the holistic and analytic stages, judging
julia/params.toml    every tunable number
julia/test/          unit and layer tests
bench/               rendering, scoring and batch-run scripts
data/                real BP images (not committed: licence unknown)
```

## Where it stands

All of the plan's phases except final calibration (phase 9) are in place:
retina, Workspace, LTM primitives, matching and patterns, the holistic and
analytic solver, sameness and for-all, and the Mentor with learned concepts,
categorisation and associations (phase 7, D41).

On the fifteen real BPs Phaeaco solved (`results/real_20.txt`, 20 runs
each), PhaeacoJL now solves all fifteen at least some of the time. Examples:
BP #3 by the zero-variance shortcut (100%; thesis 99%), BP #4 (25%; 20%),
BP #22 (55%; 13%) and BP #56 (70%; 19%). It solves several problems much
more often than Phaeaco did (BP #8: 100% vs 23%); calibration is still to
come.

The synthetic analogues were developed on one drawn instance each. On two
fresh instances (`results/synth_heldout_30.txt`) the results hold: 13 of 15
are solved 70–100% of the time, same texture about 55%, and convexity
17–20%, like BP #4 in the thesis. What the fresh instances exposed, and what
was changed, is in `DECISIONS.md` D43.

Beyond the fifteen: on Bongard's other 85 problems
(`results/survey_judged.md`) it solves 3 reliably (#12, #34, #89) and 2
occasionally (#24, #33), and on 9 more it finds a rule that separates the
boxes but is not Bongard's.

After a lesson on triangles and quadrilaterals, BP #6 is sometimes solved
in those terms ("some triangle" vs "no triangle", "no quadrilateral" vs
"some quadrilateral"). Untaught, it is solved by counting lines or vertices
(`results/mentor_20.txt`).

Get the real images: see `bench/fetch/screenshot_to_bp.py` and
`DECISIONS.md` D40; they go in `data/` and are not committed.

```bash
julia --project=phaeaco/julia phaeaco/bench/run_real.jl 20      # real BPs vs Appendix A
julia --project=phaeaco/julia phaeaco/bench/run_synth.jl 30     # synthetic analogues (add bpseed=2 for a held-out instance)
julia --project=phaeaco/julia phaeaco/bench/run_mentor.jl 20    # BP #6 before and after a lesson
julia --project=phaeaco/julia phaeaco/bench/run_survey.jl 20    # every other BP in data/, answers listed
julia --project=phaeaco/julia phaeaco/bench/retina_score.jl 100 # retina vs ground truth
julia --project=phaeaco/julia phaeaco/bench/clustering.jl 400   # Table 8.1
```

Run the tests (Julia 1.10, standard library only — see `../CONTINUE.md` for
how to get Julia in this environment):

```bash
julia --project=phaeaco/julia phaeaco/julia/test/runtests.jl
```

Look at the synthetic problems:

```bash
julia --project=phaeaco/julia phaeaco/bench/render_synth.jl /tmp/sheets
```

Licence: MIT (see `LICENSE`). This tree contains no code from `../metacat`
(GPL-2) or `../copycat`.
