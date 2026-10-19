# PhaeacoX's extended percepts (src/ext/extend.jl), on drawings with known answers.

function xlook(shapes; seed=1)
    ctx = P.Ctx(P.load_params(), seed)
    ws = P.BoxWS(1, P.render(shapes), ctx; analytic=true)
    P.look!(ws, ctx)
    e = P.exemplar(ws)
    P.extend!(e, ws, ctx)
    return e, ws
end
xnode(e, t) = findfirst(c -> c.type == t, e.children) === nothing ? nothing : e.children[findfirst(c -> c.type == t, e.children)]
xkinds(e, ws) = sort([it.kind for it in P._items(e, ws)])

tri(c, r; filled=false) = P.polygon([(c[1], c[2] - r), (c[1] + 0.87r, c[2] + r / 2), (c[1] - 0.87r, c[2] + r / 2)]; filled=filled)
sq(c, r; filled=false) = P.polygon([(c[1] - r, c[2] - r), (c[1] + r, c[2] - r), (c[1] + r, c[2] + r), (c[1] - r, c[2] + r)]; filled=filled)

@testset "ext: shape kinds" begin
    e, ws = xlook([tri((25.0, 30.0), 14), sq((70.0, 30.0), 11), P.circle((50.0, 75.0), 13)])
    @test xkinds(e, ws) == [:circle, :quadrangle, :triangle]
    e, ws = xlook([tri((50.0, 50.0), 20; filled=true)])
    @test xkinds(e, ws) == [:triangle]
end

@testset "ext: relations between figures (§11.2.1)" begin
    e, _ = xlook([tri((50.0, 22.0), 14), P.circle((50.0, 75.0), 12)])
    p = xnode(e, Symbol("pair@circle_triangle"))
    @test p !== nothing && p.feats[:above].mean < 0          # the circle is lower
    @test p.feats[:inside].mean == 0
    e, _ = xlook([sq((50.0, 50.0), 34), P.circle((50.0, 50.0), 12)])
    p = xnode(e, Symbol("pair@circle_quadrangle"))
    @test p !== nothing && p.feats[:inside].mean == 1         # the circle inside the square
    @test e.feats[:depth].mean == 1
end

@testset "ext: nesting (§11.2.5)" begin
    e, _ = xlook([sq((50.0, 50.0), 40), P.circle((50.0, 50.0), 25), tri((50.0, 52.0), 9)])
    @test e.feats[:depth].mean == 2
end

@testset "ext: count contrasts are signs" begin
    e, _ = xlook([P.circle((25.0, 25.0), 9; filled=true), P.circle((75.0, 25.0), 9; filled=true),
                  P.circle((50.0, 75.0), 9)])
    c = xnode(e, Symbol("contrast@filled_outlined"))
    @test c !== nothing && c.feats[:diff].mean == 1
end

@testset "ext: self-crossing strokes" begin
    e, _ = xlook([P.polyline([(15.0, 20.0), (85.0, 80.0), (85.0, 20.0), (15.0, 80.0)])])     # a bow tie, open
    @test any(n -> n.type == Symbol("mark@selfcrossing"), P._alldesc(e))
    e, _ = xlook([P.polyline([(15.0, 20.0), (85.0, 20.0), (15.0, 80.0), (85.0, 80.0)])])     # a Z
    @test !any(n -> n.type == Symbol("mark@selfcrossing"), P._alldesc(e))
end

@testset "ext: groups and similarity" begin
    row = [P.circle((x, 50.0), 6) for x in (18.0, 40.0, 62.0, 84.0)]
    e, _ = xlook(row)
    g = xnode(e, Symbol("group@circle"))
    @test g !== nothing && g.feats[:gvert].mean < 0.3 && g.feats[:collinear].mean < 0.1
    @test e.feats[:identmin].mean == 1
    e, _ = xlook([tri((28.0, 40.0), 8), tri((68.0, 55.0), 20)])
    @test e.feats[:simmax].mean == 1 && e.feats[:identmin].mean == 0     # similar, not identical
end

@testset "ext: off means PhaeacoJL" begin
    bp, _ = P.synth_bp(:size; seed=1)
    pr = P.load_params(; ext_enabled=0)
    s = P.Solver(bp, P.Ctx(pr, 1)); P.look_all!(s)
    @test !any(b -> any(n -> occursin('@', string(n.type)), P._alldesc(b)), s.boxpat)
end
