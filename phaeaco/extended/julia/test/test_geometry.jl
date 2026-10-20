@testset "line fit" begin
    f = P.LineFit()
    for t in 0:10
        push!(f, (10.0 + 3t, 20.0 - 4t))
    end
    c, d, rms = P.linefit(f)
    @test rms < 1e-9
    @test abs(abs(d[1] * 4 + d[2] * 3)) < 1e-9     # direction ∥ (3, −4)
    @test P.slope_deg((0.6, -0.8)) ≈ atand(0.8, 0.6)   # rising to the right, y up
    v = P.LineFit(); push!(v, (5.0, 1.0)); push!(v, (5.0, 9.0)); push!(v, (5.0, 4.0))
    @test P.slope_deg(P.linefit(v)[2]) ≈ 90
end

@testset "incremental hull = brute force" begin
    rng = Xoshiro(4)
    for trial in 1:20
        pts = [(100rand(rng), 100rand(rng)) for _ in 1:40]
        h = P.Hull()
        foreach(p -> push!(h, p), pts)
        # every point is inside or on the hull, every hull vertex is an input point
        @test all(p -> P.point_in_hull(h, p) || minimum(P.segdist(p, h.v[i], h.v[i%length(h.v)+1]) for i in eachindex(h.v)) < 1e-6, pts)
        @test all(v -> v in pts, h.v)
        # convex: all turns the same way
        n = length(h.v)
        @test all(P._cross(h.v[i], h.v[i%n+1], h.v[(i+1)%n+1]) >= -1e-9 for i in 1:n)
    end
    sq = P.Hull(); foreach(p -> push!(sq, p), [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0), (5.0, 5.0)])
    @test P.polygon_area(sq.v) ≈ 100
end

@testset "conic fit (Appendix B)" begin
    c = P.Shape(:ellipse, [(50.0, 40.0)]; a=30, b=12, theta=0.5)
    pts = P.ellipse_points(c, 60)
    f = P.fit_conic(pts)
    @test f.ellipse
    @test f.rms < 1e-6
    @test all(isapprox.(f.centre, (50.0, 40.0); atol=1e-6))
    @test all(isapprox.(f.axes, (30.0, 12.0); atol=1e-6))
    @test f.ecc ≈ sqrt(1 - (12 / 30)^2)
    @test mod(f.theta - 0.5, π) < 1e-6 || mod(f.theta - 0.5, π) > π - 1e-6
    circ = P.fit_conic(P.ellipse_points(P.Shape(:ellipse, [(30.0, 30.0)]; a=10, b=10), 30))
    @test circ.ecc < 1e-6
    @test P.circumcentre((0.0, 0.0), (2.0, 0.0), (0.0, 2.0)) == (1.0, 1.0)
end

@testset "cubic spline (Appendix B)" begin
    knots = [(0.0, 0.0), (10.0, 5.0), (20.0, 0.0), (30.0, -5.0), (40.0, 0.0)]
    sp = P.cubic_spline(knots)
    @test length(sp) == 4
    for i in 1:4                      # interpolates the knots
        @test all(isapprox.(P.spline_point(sp[i], 0.0), knots[i]; atol=1e-9))
        @test all(isapprox.(P.spline_point(sp[i], 1.0), knots[i+1]; atol=1e-9))
    end
    d(piece, t) = (piece[1][2] + 2piece[1][3] * t + 3piece[1][4] * t^2)
    dd(piece, t) = (2piece[1][3] + 6piece[1][4] * t)
    for i in 1:3                      # C² at the joints
        @test d(sp[i], 1.0) ≈ d(sp[i+1], 0.0) atol = 1e-9
        @test dd(sp[i], 1.0) ≈ dd(sp[i+1], 0.0) atol = 1e-9
    end
    @test dd(sp[1], 0.0) ≈ 0 atol = 1e-9      # natural ends
    @test dd(sp[4], 1.0) ≈ 0 atol = 1e-9
end
