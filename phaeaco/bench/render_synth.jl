# Render synthetic BPs as sheets, for looking at.
#   julia --project=phaeaco/julia phaeaco/bench/render_synth.jl OUTDIR [seed] [σ] [names...]
using PhaeacoJL
const P = PhaeacoJL
outdir = ARGS[1]
seed = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 1
σ = length(ARGS) >= 3 ? parse(Float64, ARGS[3]) : 0.0
names = length(ARGS) >= 4 ? Symbol.(ARGS[4:end]) : sort!(collect(keys(P.SYNTH_BPS)))
mkpath(outdir)
for n in names
    bp, _ = P.synth_bp(n; seed=seed, σ=σ)
    P.write_pbm(joinpath(outdir, "$(n).pbm"), P.sheet_image(bp))
end
