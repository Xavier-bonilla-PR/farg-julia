# Layer tests for the retina against synthetic ground truth. The floors are
# set a little under what bench/retina_score.jl measures (results/retina_score.txt),
# so a regression shows up here without making the suite flaky.

const PR = P.load_params()
see1(shapes; seed=1, σ=0.0) = P.see(P.render(shapes; rng=Xoshiro(seed), σ=σ), PR, Xoshiro(seed))
mainobj(r) = argmax(o -> o.ink, r.objects)

@testset "retina: basic percepts" begin
    r = see1([P.polygon([(20, 80), (80, 80), (50, 25)])])
    o = mainobj(r)
    @test length(o.lines) == 3 && count(j -> j.kind == :V, r.junctions) == 3
    @test length(r.strings) == 1 && r.strings[1].closed
    @test length(o.holes) == 1 && !o.filled
    r = see1([P.polygon([(25, 25), (75, 25), (75, 75), (25, 75)]; filled=true)])
    o = mainobj(r)
    @test o.filled && length(o.lines) == 4 && all(r.lines[l].src == :exo for l in o.lines)
    @test abs(o.area - 2601) < 60 && o.missing < 0.05
    r = see1([P.circle((50, 50), 25)])
    @test length(r.ellipses) == 1 && r.ellipses[1].circle
    @test all(isapprox.(r.ellipses[1].centre, (50.0, 50.0); atol=1.0))
    @test isapprox(r.ellipses[1].axes[1], 25; atol=1.5)
    r = see1([P.segment((20, 20), (80, 80)), P.segment((20, 80), (80, 20))])
    @test count(l -> l.alive, r.lines) == 2 && length(r.junctions) == 1 && r.junctions[1].kind == :X
    r = see1([P.dot((30, 30), 1.5), P.circle((60, 60), 12)])
    @test length(r.dots) == 1
    r = see1([P.circle((50, 50), 6; filled=true)])         # small: zoomed, still a filled circle
    o = mainobj(r)
    @test o.zoomed && o.filled && length(o.ellipses) == 1
    r = see1([P.circle((50, 50), 30), P.polygon([(45, 45), (55, 45), (50, 55)])])
    tri = argmin(o -> o.ink, r.objects)
    @test any(t -> t[1] == tri.id && t[3] == 1.0, r.insides)  # triangle inside circle
    r = see1([P.random_concave(Xoshiro(3), (50, 50), 30)])
    @test mainobj(r).missing > 0.1                          # concave: hull not filled
end

@testset "retina: side counts on random polygons" begin
    rng = Xoshiro(77)
    ok = Dict(3 => 0, 4 => 0, 5 => 0)
    n = 25
    for t in 1:n, k in (3, 4, 5)
        s = P.random_polygon(rng, k, (50.0, 50.0), 15 + 22rand(rng); irreg=0.3, filled=rand(rng, Bool))
        o = mainobj(see1([s]; seed=t))
        ok[k] += length(o.lines) == k && isempty(o.ellipses)
    end
    @test ok[3] >= 0.88n
    @test ok[4] >= 0.85n
    @test ok[5] >= 0.75n
end

@testset "retina: deterministic for a seed" begin
    img = P.render([P.circle((40, 40), 15), P.polygon([(60, 60), (90, 60), (75, 90)]; filled=true)])
    a, b = P.see(img, PR, Xoshiro(9)), P.see(img, PR, Xoshiro(9))
    @test [(l.p1, l.p2) for l in a.lines if l.alive] == [(l.p1, l.p2) for l in b.lines if l.alive]
    c = P.see(img, PR, Xoshiro(10))
    @test length(c.ellipses) == length(a.ellipses)          # same percepts, different order
end
