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
xkinds(e, ws) = sort([it.kind for it in P._items(e, ws, P.load_params())])

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

function xcore(shapes)
    ctx = P.Ctx(P.load_params(), 1)
    ws = P.BoxWS(1, P.render(shapes), ctx; analytic=true)
    P.look!(ws, ctx)
    return [P.object_core(ws.retina, o, ctx.P) for o in ws.retina.objects]
end

@testset "ext: core extraction (X12)" begin
    # the core ignores the ink: outlined and filled figures have the same core
    for filled in (false, true)
        @test xcore([tri((50.0, 55.0), 25; filled=filled)])[1].ends == 3
        @test xcore([sq((50.0, 50.0), 20; filled=filled)])[1].ends == 4
        @test xcore([P.circle((50.0, 50.0), 22; filled=filled)])[1].ends == 0
    end
    @test xcore([P.ellipse((50.0, 50.0), 30.0, 12.0; filled=true)])[1].ends == 2
    c = xcore([P.polyline([(20.0, 50.0), (80.0, 50.0)]), P.polyline([(50.0, 20.0), (50.0, 80.0)])])[1]
    @test c.ends == 4 && c.junctions == 1
    c = xcore([P.polyline([(20.0, 25.0), (80.0, 25.0)]), P.polyline([(50.0, 25.0), (50.0, 85.0)])])[1]
    @test c.ends == 3 && c.order == 1
    # a trunk, a side branch, and a branch of that branch (BP #70)
    c = xcore([P.polyline([(50.0, 95.0), (50.0, 5.0)]), P.polyline([(50.0, 60.0), (20.0, 45.0)]),
               P.polyline([(35.0, 52.5), (33.0, 40.0)])])[1]
    @test c.order == 2
    c = xcore([P.polyline([(50.0, 95.0), (50.0, 5.0)]), P.polyline([(50.0, 60.0), (20.0, 45.0)])])[1]
    @test c.order == 1
    # a dumbbell has a neck; a disk and a stroke have none (BP #18)
    db = [P.circle((25.0, 50.0), 15; filled=true), P.circle((75.0, 50.0), 15; filled=true),
          P.polygon([(25.0, 47.0), (75.0, 47.0), (75.0, 53.0), (25.0, 53.0)]; filled=true)]
    @test xcore(db)[1].neck < 0.4
    @test xcore([P.circle((50.0, 50.0), 22; filled=true)])[1].neck == 1.0
    @test xcore([P.segment((20.0, 20.0), (80.0, 70.0))])[1].neck == 1.0
    # an outlined and a filled triangle are similar; a triangle and a square less so
    t1, t2, s1 = xcore([tri((50.0, 55.0), 25)])[1], xcore([tri((50.0, 55.0), 25; filled=true)])[1], xcore([sq((50.0, 50.0), 20)])[1]
    @test P.core_distance(t1, t2) < 0.2 < P.core_distance(t1, s1)
end

@testset "ext: off means PhaeacoJL" begin
    bp, _ = P.synth_bp(:size; seed=1)
    pr = P.load_params(; ext_enabled=0)
    s = P.Solver(bp, P.Ctx(pr, 1)); P.look_all!(s)
    @test !any(b -> any(n -> occursin('@', string(n.type)), P._alldesc(b)), s.boxpat)
end

@testset "ext: GCM categorisation (X13)" begin
    ctx = P.Ctx(P.load_params(), 1)
    # a clear best match is taken; a weak lone match is not; between two
    # equally good concepts P is just under ½, so a tie is rarely decided
    @test count(_ -> P.gcm_choice(ctx, [0.85]), 1:50) == 50
    @test count(_ -> P.gcm_choice(ctx, [0.55]), 1:50) == 0
    @test count(_ -> P.gcm_choice(ctx, [0.80, 0.80]), 1:50) < 25
    @test count(_ -> P.gcm_choice(ctx, [0.85, 0.65]), 1:50) == 50
end

@testset "ext: memory of solved problems (X14)" begin
    # the same rule drawn twice: solving the first is remembered, and the
    # second reminds of it and is solved by analogy
    bp1, _ = P.synth_bp(:size; seed=1)
    bp2, _ = P.synth_bp(:size; seed=2)
    ctx = P.Ctx(P.load_params(), 1)
    r1 = P.solve(bp1, ctx)
    @test r1.answer !== nothing && length(ctx.ltm.episodes) == 1
    s = P.Solver(bp2, ctx); P.look_all!(s)
    core = P.problem_core(s)
    @test P.episode_distance(core, ctx.ltm.episodes[1].core) < 0.05
    @test P.transfer(s, r1.answer) !== nothing
    # a slipped idea: the old one's place differs only in tags
    old = P.Idea(:feature, [Symbol("contrast@filledtriangle_outlinedtriangle")], :diff, :none, :all, 0.0, false)
    i = P.transfer(s, old)
    @test i === nothing || P.basetype(i.path[1]) == :contrast
    # off means no episodes
    ctx0 = P.Ctx(P.load_params(; ext_memory=0), 1)
    P.solve(bp1, ctx0)
    @test isempty(ctx0.ltm.episodes)
end
