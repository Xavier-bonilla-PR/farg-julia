@testset "pbm round trip" begin
    rng = Xoshiro(7)
    img = bitrand(rng, 37, 53)
    path = tempname() * ".pbm"
    P.write_pbm(path, img; comment="hello")
    back, comments = P.read_pbm(path)
    @test back == img
    @test "hello" in comments
end

@testset "rasteriser" begin
    img = P.render([P.segment((10, 50), (90, 50); width=1.6)])
    @test count(img) > 75
    @test all(img[50, 12:88])
    sq = P.polygon([(20, 20), (80, 20), (80, 80), (20, 80)]; filled=true)
    img = P.render([sq])
    @test abs(count(img) - P.enclosed_area(sq)) < 0.1 * P.enclosed_area(sq)
    c = P.circle((50, 50), 20)
    img = P.render([c])
    @test !img[50, 50] && img[50, 70]          # outlined: hollow
    @test P.isconvex(sq) && !P.isconvex(P.random_concave(Xoshiro(1), (50, 50), 20))
end

@testset "foreground" begin
    img = falses(100, 100); img[40:60, 40:60] .= true
    @test P.foreground_mask(img) == img
    @test P.foreground_mask(.!img) == img      # inverted input, same figure
end

@testset "synthetic BPs" begin
    for name in keys(P.SYNTH_BPS)
        bp, truth = P.synth_bp(name; seed=11)
        @test length(bp.boxes) == 12
        @test all(size(b) == (100, 100) for b in bp.boxes)
        @test length(truth) == 12
        # every non-empty box drew something
        @test all(isempty(t) || count(b) > 0 for (t, b) in zip(truth, bp.boxes))
    end
    bp, truth = P.synth_bp(:texture; seed=2)
    @test all(!s.filled for t in truth[1:6] for s in t)
    @test all(s.filled for t in truth[7:12] for s in t)
    bp, truth = P.synth_bp(:existence; seed=2)
    @test all(count(b) == 0 for b in bp.boxes[1:6])
    path = tempname() * ".pbm"
    P.save_bp(path, bp)
    back = P.load_bp(path)
    @test back.boxes == bp.boxes && back.left_label == bp.left_label
end
