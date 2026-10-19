using Test
using Random
using PhaeacoJL
const P = PhaeacoJL

@testset "PhaeacoJL" begin
    include("test_core.jl")
    include("test_input.jl")
end
