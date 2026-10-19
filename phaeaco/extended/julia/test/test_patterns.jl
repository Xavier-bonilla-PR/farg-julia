# Matching and pattern formation (ch. 8).

@testset "distributions" begin
    @test P.t_two_sided(2.228, 10.0) ≈ 0.95 atol = 1e-3       # tabled values
    @test P.t_two_sided(12.706, 1.0) ≈ 0.95 atol = 1e-3
    @test P.t_two_sided(2.576, 1e6) ≈ 0.99 atol = 1e-3
    @test P.normal_two_sided(1.96) ≈ 0.95 atol = 1e-4
    @test P.lgamma_l(5.0) ≈ log(24) atol = 1e-10
    @test P.betainc_reg(2.0, 3.0, 0.4) ≈ 0.5248 atol = 1e-4
end

const PM = P.load_params()
mctx() = P.Ctx(PM, 1)
@testset "feature and numerosity differences" begin
    M = P.Matcher(mctx())
    info = mctx().ltm[:area].feature
    @test P.feature_difference(M, P.Stats(1000), P.Stats(1500), info) ≈ 0.05
    s = P.Stats(); foreach(x -> push!(s, x), (1000, 1100, 950, 1050, 1020))
    near, far = P.feature_difference(M, P.Stats(1010), s, info), P.feature_difference(M, P.Stats(3000), s, info)
    @test near < 0.002 && far > 0.15
    @test P.difference_probability(M, P.Stats(3000), s, info) > 0.99
    @test P.numerosity_difference(M, P.Stats(3), P.Stats(3)) == 0
    @test P.numerosity_difference(M, P.Stats(2), P.Stats(3)) > 0.99      # small counts are told apart
    @test P.numerosity_difference(M, P.Stats(30), P.Stats(31)) < P.numerosity_difference(M, P.Stats(3), P.Stats(4))
end

@testset "matching structures" begin
    ex(shape, seed) = (ctx = P.Ctx(PM, seed); P.exemplar(P.represent(P.render([shape]), ctx)))
    rng = Xoshiro(5)
    tris = [ex(P.random_polygon(rng, 3, (50.0, 50.0), 25; irreg=0.2), s) for s in 1:4]
    quads = [ex(P.random_polygon(rng, 4, (50.0, 50.0), 25; irreg=0.2), s) for s in 5:8]
    M = P.Matcher(mctx())
    within = [P.difference(M, tris[i], tris[j]) for i in 1:4 for j in i+1:4]
    across = [P.difference(M, t, q) for t in tris for q in quads]
    @test maximum(within) < minimum(across)
    @test all(0 .<= across .<= 1)
    # a pattern of the triangles: statistics of size 4, its lines fully supported
    p = P.pattern_of(tris[1])
    foreach(t -> P.update!(M, p, t), tris[2:4])
    obj = only(c for c in p.children if c.type == :object)
    @test p.support == 4 && obj.support == 4
    @test obj.nums[:line].n == 4 && abs(obj.nums[:line].mean - 3) < 0.3
    @test P.difference(M, p, tris[1]) < P.difference(M, p, quads[1])
end

include(joinpath(@__DIR__, "..", "..", "bench", "clustering.jl"))
@testset "Table 8.1: the Patterns algorithm" begin
    res = run_benchmark(100)
    m, _, thr, _, _ = res["Patterns"]
    @test m >= 95                      # thesis: 98.5
    @test 0.78 <= thr <= 0.90          # thesis: best at 0.83, tolerant 0.78–0.88
    @test res["Patterns, literal"][1] < 80
    @test res["k-means (k = 3)"][1] < m
end

@testset "comparing counts: the Welford trend (§7.3.2)" begin
    rng = Xoshiro(2)
    rt(L, S) = sum(P.compare_counts(L, S, 0.2, rng)[2] for _ in 1:200) / 200
    seq = [rt(20, 10), rt(100, 95), rt(100, 98), rt(200, 198), rt(300, 299)]
    @test issorted(seq)                # RT grows with L/(L−S)
    @test seq[end] > 3 * seq[1]
    @test first(P.compare_counts(3, 2, 0.1, rng))
end
