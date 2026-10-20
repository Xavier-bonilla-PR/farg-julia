# The solver (ch. 11) on synthetic BPs. A few seeds per problem, to keep the
# suite fast; bench/run_synth.jl gives the statistics (results/synth_30.txt).

const PS = P.load_params()

@testset "ideas: values, satisfaction, phrasing" begin
    box(areas, tex) = begin
        r = P.RNode(:box)
        for (a, t) in zip(areas, tex)
            o = P.RNode(:object); o.feats[:area] = P.Stats(a); o.feats[:texture] = P.Stats(t)
            push!(r.children, o)
        end
        r.nums[:object] = P.Stats(length(areas)); r
    end
    big = P.Idea(:feature, [:object], :area, :none, :all, 500.0, false)    # left large
    @test P.satisfies(big, box([900], [0]), true) && !P.satisfies(big, box([100], [0]), true)
    @test P.satisfies(big, box([100], [1]), false)
    small = P.Idea(:feature, [:object], :area, :left, :some, 200.0, true)  # some small on the left
    @test P.satisfies(small, box([900, 50], [0, 0]), true) && !P.satisfies(small, box([900, 50], [0, 0]), false)
    cnt = P.Idea(:count, Symbol[], :object, :none, :all, 2.5, true)
    @test P.idea_values(cnt, box([1, 2], [0, 0])) == [2.0] && P.satisfies(cnt, box([1, 2], [0, 0]), true)
    @test P.describe(P.Idea(:feature, [:object], :texture, :none, :all, 0.5, true)) == ("outlined texture", "filled texture")
    @test P.same_idea(big, P.Idea(:feature, [:object], :area, :none, :all, 700.0, false))
    @test !P.same_idea(big, small)
end

solved(name, seeds) = [P.judge(name, P.solve(first(P.synth_bp(name; seed=1)), PS, s)) for s in seeds]

@testset "solver: hardwired, holistic and analytic solutions" begin
    r = P.solve(first(P.synth_bp(:texture; seed=1)), PS, 1)
    @test r.stage == :hardwired && P.judge(:texture, r) == :correct     # BP #3: no verification
    @test all(==(:correct), solved(:size, 1:3))                         # BP #2
    @test all(==(:correct), solved(:existence, 1:3))                    # BP #1
    @test count(==(:correct), solved(:count_objects, 1:3)) >= 2         # BP #23
    @test count(==(:correct), solved(:position, 1:3)) >= 2              # BP #8 (analytic)
    @test count(==(:correct), solved(:parallel_lines, 1:4)) >= 2        # BP #39 (for-all)
end

@testset "solver: deterministic for a seed; gives up rather than loop" begin
    bp = first(P.synth_bp(:size; seed=1))
    a, b = P.solve(bp, PS, 7), P.solve(bp, PS, 7)
    @test a.ticks == b.ticks && string(a.answer) == string(b.answer)
    r = P.solve(first(P.synth_bp(:same_texture; seed=1)), PS, 4)
    @test r.ticks < PS[:solve_max_ticks] + 20_000
end
