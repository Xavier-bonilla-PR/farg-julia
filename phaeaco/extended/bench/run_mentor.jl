# Does a Mentor lesson change how BP #6 is solved (§5.2, D41), and how well
# are BP #6's figures categorised after it (X13)? Each run teaches
# "triangle" and "quadrilateral" from fresh lessons, then (1) looks once at
# every box and counts which figures were categorised as what, and
# (2) solves the problem.
#   julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_mentor.jl RUNS [four] [key=value ...]
# With `four`, pentagons and circles are taught too, so a figure has more
# concepts to choose among.
using PhaeacoX, Printf
const P = PhaeacoX

"""Per look at each box: figures categorised correctly, wrongly, or not at all."""
function categorised!(tally, bp, ctx)
    for i in 1:12
        ws = P.BoxWS(i, bp.boxes[i], ctx; analytic=true)
        P.look!(ws, ctx)
        want = i <= 6 ? :triangle : :quadrilateral
        for k in eachindex(ws.nodes)
            n = ws.nodes[k]
            (n.alive && n.type == :object) || continue
            cats = [ws.nodes[c].tag for c in n.children if ws.nodes[c].type == :category]
            tally[isempty(cats) ? :none : want in cats ? :right : :wrong] += 1
        end
    end
end

function run_mentor(runs; params=P.load_params(), taught=true, four=false)
    bp = P.load_bp(joinpath(@__DIR__, "..", "..", "data", "bp006.pbm"))
    out = Dict(:correct => 0, :incorrect => 0, :none => 0)
    tally = Dict(:right => 0, :wrong => 0, :none => 0)
    answers = Dict{String,Int}()
    for seed in 1:runs
        ctx = P.Ctx(params, seed)
        if taught
            i1, l1 = P.lesson(3, 8; seed=100 + seed, label=:triangle); P.mentor!(ctx, i1, l1)
            i2, l2 = P.lesson(4, 8; seed=200 + seed, label=:quadrilateral); P.mentor!(ctx, i2, l2)
            if four
                i3, l3 = P.lesson(5, 8; seed=300 + seed, label=:pentagon); P.mentor!(ctx, i3, l3)
                i4, l4 = P.lesson(0, 8; seed=400 + seed, label=:circle); P.mentor!(ctx, i4, l4)
            end
            categorised!(tally, bp, P.Ctx(params, seed; ltm=deepcopy(ctx.ltm)))
        end
        r = P.solve(bp, ctx)
        j = P.judge_real(6, r)
        out[j] += 1
        k = r.answer === nothing ? "—" : "$(j == :correct ? "✓" : "✗") $(r.answer)"
        answers[k] = get(answers, k, 0) + 1
    end
    return out, tally, answers
end

if abspath(PROGRAM_FILE) == @__FILE__
    runs = parse(Int, ARGS[1])
    four = "four" in ARGS
    kv = Dict(Symbol(split(a, '=')[1]) => parse(Float64, split(a, '=')[2]) for a in ARGS[2:end] if occursin('=', a))
    params = P.load_params(; kv...)
    @printf("BP #6, %d runs each, %s concepts taught%s: correct / wrong / none, and the commonest answers.\n", runs, four ? "four" : "two",
            isempty(kv) ? "" : " ($(join(("$k=$v" for (k, v) in kv), ", ")))")
    for taught in (false, true)
        out, tally, answers = run_mentor(runs; params=params, taught=taught, four=four)
        @printf("%-14s %3d / %3d / %3d\n", taught ? "after lessons" : "untaught", out[:correct], out[:incorrect], out[:none])
        if taught
            n = tally[:right] + tally[:wrong] + tally[:none]
            @printf("    figures categorised (one look per box): right %d, wrong %d, none %d of %d  (precision %.2f, recall %.2f)\n",
                    tally[:right], tally[:wrong], tally[:none], n,
                    tally[:right] / max(1, tally[:right] + tally[:wrong]), tally[:right] / max(1, n))
        end
        for (k, v) in sort(collect(answers); by=x -> -x[2])[1:min(4, end)]
            println("    ×$v  $k")
        end
    end
end
