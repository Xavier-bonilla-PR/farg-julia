@testset "sigmoid" begin
    s = P.Sigmoid()
    @test s(0.0) ≈ s.l
    @test s(1.0) ≈ 1 - s.l
    @test s(0.5) ≈ 0.5
    @test s(s.x1) ≈ s.y1                       # pieces join
    xs = range(0, 1; length=1001)
    ys = s.(xs)
    @test all(diff(ys) .> 0)                   # strictly increasing
    @test all(abs(s(x) + s(1 - x) - 1) < 1e-12 for x in xs)   # symmetric about (½, ½)
    # matching slopes at the joint
    h = 1e-6
    @test (s(s.x1) - s(s.x1 - h)) / h ≈ s.m rtol = 1e-3
    @test all(s.l <= y <= 1 - s.l for y in ys)
end

@testset "activation" begin
    a = P.Activation(10, 5)                    # starts at the top
    @test P.value(a, 0) ≈ 1 - P.DEFAULT_SIGMOID.l
    @test P.value(a, 4) ≈ P.value(a, 0)        # not a full period yet
    @test a.pos == 10
    P.sync!(a, 5);  @test a.pos == 9
    P.sync!(a, 23); @test a.pos == 6           # three more periods by t=20
    @test P.value(a, 1000) ≈ P.DEFAULT_SIGMOID.l   # floors, never 0
    @test a.pos == 0
    @test !P.boost!(a, 1000)
    @test a.pos == 1
    @test P.boost!(a, 1000, 50)                # reaching the top reports true
    @test a.pos == 10
end

@testset "significance" begin
    w = P.Weight(act_steps=3, act_period=1000, sig_steps=2, sig_period=10^6, growth=5)
    @test w.sig.pos == 0
    P.prime!(w, 0, 3)                          # activation maxes once
    @test w.sig.pos == 1
    P.prime!(w, 0, 1)                          # at max again
    @test w.sig.pos == 2 && w.sig.steps == 7   # significance maxed: stability grew
    @test P.weight(w, 0) > 1.0
end

@testset "stats" begin
    rng = Xoshiro(3)
    xs = randn(rng, 50) .* 7 .+ 3
    s = P.Stats()
    foreach(x -> push!(s, x), xs)
    m = sum(xs) / length(xs)
    v = sum((xs .- m) .^ 2) / (length(xs) - 1)
    @test s.n == 50
    @test s.mean ≈ m
    @test P.variance(s) ≈ v
    @test s.min == minimum(xs) && s.max == maximum(xs)
    a, b = P.Stats(), P.Stats()
    foreach(x -> push!(a, x), xs[1:20]); foreach(x -> push!(b, x), xs[21:end])
    merge!(a, b)
    @test a.mean ≈ m && P.variance(a) ≈ v
    @test P.variance(P.Stats(4.0)) == 0
    # the thesis's worked example (§8.3.3): slopes 65 and 75
    e = P.Stats(); push!(e, 65); push!(e, 75)
    @test e.mean == 70 && P.variance(e) ≈ 50
end

@testset "params" begin
    p = P.load_params()
    @test p isa P.Params
    t = P.Thr(1.0, 0.0)
    @test P.sample(t, Xoshiro(1)) == 1.0
    @test P.exceeds(2.0, t, Xoshiro(1))
end
