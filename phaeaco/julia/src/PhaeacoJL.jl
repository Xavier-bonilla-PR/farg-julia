"""
    PhaeacoJL

A reconstruction, in Julia, of Harry Foundalis's Phaeaco — the FARG
architecture for Bongard problems described in his 2006 dissertation. The
original source was never released; this is rebuilt from the written
description. See `phaeaco/PLAN.md` and `phaeaco/DECISIONS.md`.
"""
module PhaeacoJL

using Random
using LinearAlgebra
using Printf
using TOML

include("core/params.jl")
include("core/activation.jl")
include("core/stats.jl")
include("core/trace.jl")

include("input/image.jl")
include("input/synth.jl")
include("input/synthbp.jl")

include("retina/geometry.jl")
include("retina/detectors.jl")
include("retina/pixels.jl")
include("retina/lines.jl")
include("retina/structure.jl")

end
