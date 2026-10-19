using Test
using Random
using PhaeacoX
const P = PhaeacoX

@testset "PhaeacoX" begin
    include("test_core.jl")
    include("test_input.jl")
    include("test_geometry.jl")
    include("test_retina.jl")
    include("test_workspace.jl")
    include("test_patterns.jl")
    include("test_solver.jl")
    include("test_ltm.jl")
end
