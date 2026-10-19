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
julia/params.toml    every tunable number
julia/test/          unit and layer tests
bench/               rendering, scoring and batch-run scripts
data/                real BP images (not committed: licence unknown)
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
