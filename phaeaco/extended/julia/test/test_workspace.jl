# Workspace layer: the representation of single boxes (ch. 7).

const PW = P.load_params()
rep(shapes; seed=1, prime=Symbol[]) = begin
    ctx = P.Ctx(PW, seed)
    for c in prime
        P.prime!(ctx.ltm, c, 0, ctx.rng; marks=40)
    end
    P.represent(P.render(shapes), ctx)
end
types(ws) = [n.type for n in ws.nodes if n.alive]
Λ = [P.polyline([(30, 75), (50, 30), (70, 75)])]

@testset "workspace: the Λ of Fig. 7.1" begin
    for seed in 1:10
        ws = rep(Λ; seed=seed)
        # never fails to represent the two lines, their object and their vertex (§7.1)
        @test count(==(:line), types(ws)) == 2
        @test count(==(:object), types(ws)) == 1
        @test count(==(:vertex), types(ws)) == 1
        obj = first(n for n in ws.nodes if n.type == :object)
        @test obj.parent == ws.root
        @test all(ws.nodes[k].parent == obj.id for k in P.descendants(ws, ws.root, :line))
        @test ws.done
    end
    # leaves vary from look to look (§7.1: "a possible representation")
    shapes = Set([Set(types(rep(Λ; seed=s))) for s in 1:15])
    @test length(shapes) > 1
end

@testset "workspace: convex hull is rarely seen unless primed" begin
    plain = count(s -> :convex_hull in types(rep(Λ; seed=s)), 1:30)
    primed = count(s -> :convex_hull in types(rep(Λ; seed=s, prime=[:convex_hull])), 1:30)
    @test plain < 15
    @test primed > plain
end

@testset "workspace: features and counts" begin
    ws = rep([P.polygon([(20, 20), (80, 20), (80, 80), (20, 80)])])
    lines = P.descendants(ws, ws.root, :line)
    @test length(lines) == 4
    # four sides of the same length share one length node (Fig. 7.7)
    lens = unique(ws.nodes[k].feats[:length][1] for k in lines if haskey(ws.nodes[k].feats, :length))
    @test length(lens) == 1
    obj = first(n for n in ws.nodes if n.type == :object)
    @test haskey(obj.nums, :line) && P.reported(ws.nodes[obj.nums[:line]]) == 4
    @test any(n -> n.type == :interior && n.tag == :closed, ws.nodes)
    ws = rep([P.circle((50, 50), 20; filled=true)])
    obj = first(n for n in ws.nodes if n.type == :object)
    @test obj.feats[:texture][2] == 1.0
    @test count(==(:circle), types(ws)) == 1 && count(==(:line), types(ws)) == 0
end

@testset "workspace: inside, and many" begin
    ws = rep([P.circle((50, 50), 35), P.polygon([(40, 40), (60, 40), (50, 58)])]; seed=3)
    @test count(==(:inside), types(ws)) == 1 && count(==(:contains), types(ws)) == 1
    dots = [P.dot((15.0 + 10 * (k % 8), 20.0 + 15 * (k ÷ 8)), 1.5) for k in 0:31]
    ws = rep(dots; seed=2)
    @test count(==(:dot), types(ws)) < 20               # process Q stopped building dot nodes
    n = ws.nodes[ws.nodes[ws.root].nums[:dot]]
    @test abs(P.reported(n) - 32) <= 6                  # but kept counting, roughly (§7.3)
end

@testset "accumulator: small counts exact, large ones approximate" begin
    ctx = P.Ctx(PW, 5)
    errs(n) = count(1:300) do _
        acc = sum(1 + PW[:numerosity_sigma0] * randn(ctx.rng) for _ in 1:n)
        round(Int, acc) != n
    end
    @test errs(3) <= 3
    @test errs(5) <= 15
    @test errs(30) > errs(5)
end
