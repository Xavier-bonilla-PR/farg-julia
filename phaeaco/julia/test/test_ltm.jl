# Long-term memory and the Mentor (ch. 9, §5.2).

const PL = P.load_params()
taught(seed) = begin
    ctx = P.Ctx(PL, seed)
    i1, l1 = P.lesson(3, 8; seed=100 + seed, label=:triangle); P.mentor!(ctx, i1, l1)
    i2, l2 = P.lesson(4, 8; seed=200 + seed, label=:quadrilateral); P.mentor!(ctx, i2, l2)
    ctx
end

@testset "ltm: lessons make concepts that categorise" begin
    ctx = taught(1)
    names = [ctx.ltm[lc.id].name for lc in ctx.ltm.learned]
    @test names == [:triangle, :quadrilateral]
    @test all(lc -> lc.core.support == 8, ctx.ltm.learned)
    @test (:line, 3) in ctx.ltm.learned[1].keys && any(k -> k[1] == :line && k[2] >= 4, ctx.ltm.learned[2].keys)
    @test P.cweight(ctx.ltm, :triangle, ctx.now) > 0.3          # a lesson is significant
    # varied shapes, three lessons: rarely the wrong concept, often enough the
    # right one (verification can also categorise top-down)
    conf = Dict{Tuple{Int,Symbol},Int}()
    for seed in 1:3
        c = taught(seed)
        rng = Xoshiro(10 + seed)
        for _ in 1:6, k in (3, 4, 5, 0)
            r = 12 + 22rand(rng)
            ctr = (r + 6 + (88 - 2r) * rand(rng), r + 6 + (88 - 2r) * rand(rng))
            s = k == 0 ? P.circle(ctr, r) : P.random_polygon(rng, k, ctr, r; irreg=0.3, filled=rand(rng, Bool))
            ws = P.represent(P.render([s]), c)
            o = first(n for n in ws.nodes if n.type == :object)
            P.cod_category!(ws, c, o.id)
            cs = [n.tag for n in ws.nodes if n.type == :category]
            key = (k, isempty(cs) ? :none : cs[1])
            conf[key] = get(conf, key, 0) + 1
        end
    end
    got(k, c) = get(conf, (k, c), 0)
    wrong = got(3, :quadrilateral) + got(4, :triangle) + got(5, :triangle) + got(5, :quadrilateral) +
            got(0, :triangle) + got(0, :quadrilateral)
    @test wrong <= 6                                            # of 72
    @test got(3, :triangle) >= 3 && got(4, :quadrilateral) >= 3 # of 18 each
end

@testset "ltm: remembering and forgetting" begin
    ctx = taught(2)
    path = tempname()
    @test P.save_ltm(path, ctx) == 2
    fresh = P.Ctx(PL, 3)
    @test P.load_ltm!(path, fresh) == 2
    @test [fresh.ltm[lc.id].name for lc in fresh.ltm.learned] == [:triangle, :quadrilateral]
    ctx.now += 10^8                                             # a very long time without reinforcement
    @test P.save_ltm(path, ctx) == 0                            # unreachable concepts are not saved
end

@testset "ltm: associations harden into relations (§9.3.2)" begin
    ctx = taught(3)
    rng = Xoshiro(31)
    tri(r, c) = P.random_polygon(r, 3, c, 12 + 5rand(r); irreg=0.2)
    quad(r, c) = P.random_polygon(r, 4, c, 12 + 5rand(r); irreg=0.2)
    for k in 1:12
        img = P.render(P.place(rng, [tri, quad]; gap=8.0))     # a triangle and a quadrilateral in one box
        ws = P.represent(img, ctx)
        for n in collect(ws.nodes)
            n.type == :object && P.cod_category!(ws, ctx, n.id)
        end
    end
    @test haskey(ctx.ltm.assoc, (ctx.ltm.byname[:triangle], ctx.ltm.byname[:quadrilateral]))
    @test haskey(ctx.ltm, :with_triangle_quadrilateral)
end

@testset "mentor: concepts change how a BP is described (§5.2)" begin
    bp = first(P.synth_bp(:tri_vs_quad; seed=1))
    iscat(r) = r.answer !== nothing && r.answer.kind == :exists && r.answer.what == :category
    without = count(s -> iscat(P.solve(bp, PL, s)), 1:6)
    with = count(s -> iscat(P.solve(bp, taught(s))), 1:8)
    @test without == 0
    @test with >= 1
end
