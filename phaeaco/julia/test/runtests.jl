using Test
using Random
using PhaeacoJL
const P = PhaeacoJL

@testset "PhaeacoJL" begin
    include("test_core.jl")
    include("test_input.jl")
    include("test_geometry.jl")
    include("test_retina.jl")
    include("test_workspace.jl")
    include("test_patterns.jl")
end
