"""
    PhaeacoX

A reconstruction, in Julia, of Harry Foundalis's Phaeaco — the FARG
architecture for Bongard problems described in his 2006 dissertation. The
original source was never released; this is rebuilt from the written
description. See `phaeaco/PLAN.md` and `phaeaco/DECISIONS.md`.
"""
module PhaeacoX

using Random
using LinearAlgebra
using Printf
using TOML
using Serialization

include("core/params.jl")
include("core/activation.jl")
include("core/stats.jl")
include("core/trace.jl")
include("core/rnode.jl")

include("input/image.jl")
include("input/synth.jl")
include("input/synthbp.jl")

include("retina/geometry.jl")
include("retina/detectors.jl")
include("retina/pixels.jl")
include("retina/lines.jl")
include("retina/structure.jl")

include("ltm/concepts.jl")

include("workspace/workspace.jl")
include("workspace/perceive.jl")
include("workspace/codelets.jl")
include("workspace/look.jl")

include("patterns/distributions.jl")
include("patterns/rep.jl")
include("patterns/match.jl")
include("patterns/group.jl")
include("patterns/numerosity.jl")

include("ltm/learned.jl")
include("ext/core.jl")
include("ext/extend.jl")

include("solver/ideas.jl")
include("solver/solver.jl")
include("solver/memory.jl")
include("solver/judge.jl")

end
