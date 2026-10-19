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
julia/src/ltm/       the conceptual network's primitives
julia/src/workspace/ representations, codelets, processes P, Q, R
julia/src/patterns/  matching (§8.2), the Patterns algorithm (§8.3)
julia/src/solver/    ideas, the holistic and analytic stages, judging
julia/params.toml    every tunable number
julia/test/          unit and layer tests
bench/               rendering, scoring and batch-run scripts
data/                real BP images (not committed: licence unknown)
```

## Where it stands

All of the plan's phases except the LTM/Mentor work (phase 7) and final
calibration (phase 9) are in place: retina, Workspace, matching and
patterns, the holistic and analytic solver, sameness and for-all.

On the fifteen real BPs Phaeaco solved (`results/real_20.txt`, 20 runs
each), PhaeacoJL solves 14, for example BP #3 by the zero-variance shortcut
(100%; thesis 99%), BP #85 (100%; 94%), BP #5 (75 / 5 / 20 against the
thesis's 60 / 18 / 22), BP #4 (10%; 20%) and BP #56 (10%; 19%). It never
solves BP #22 (thesis 13%). It solves some easy problems much more often
than Phaeaco did (BP #8: 100% vs 23%), and calibration is still to come. On
the synthetic analogues (`results/synth_30.txt`) 13 of 15 are solved
87–100% of the time.

Get the real images: see `bench/fetch/screenshot_to_bp.py` and
`DECISIONS.md` D40; they go in `data/` and are not committed.

```bash
julia --project=phaeaco/julia phaeaco/bench/run_real.jl 20      # real BPs vs Appendix A
julia --project=phaeaco/julia phaeaco/bench/run_synth.jl 30     # synthetic analogues
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
