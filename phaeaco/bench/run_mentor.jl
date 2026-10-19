# Does a Mentor lesson change how BP #6 is solved (§5.2, D41)? Each run
# teaches "triangle" and "quadrilateral" from fresh lessons, then solves.
#   julia --project=phaeaco/julia phaeaco/bench/run_mentor.jl RUNS
using PhaeacoJL, Printf
const P = PhaeacoJL

function run_mentor(runs; params=P.load_params(), taught=true)
    bp = P.load_bp(joinpath(@__DIR__, "..", "data", "bp006.pbm"))
    out = Dict(:correct => 0, :incorrect => 0, :none => 0)
    answers = Dict{String,Int}()
    for seed in 1:runs
        ctx = P.Ctx(params, seed)
        if taught
            i1, l1 = P.lesson(3, 8; seed=100 + seed, label=:triangle); P.mentor!(ctx, i1, l1)
            i2, l2 = P.lesson(4, 8; seed=200 + seed, label=:quadrilateral); P.mentor!(ctx, i2, l2)
        end
        r = P.solve(bp, ctx)
        j = P.judge_real(6, r)
        out[j] += 1
        k = r.answer === nothing ? "—" : "$(j == :correct ? "✓" : "✗") $(r.answer)"
        answers[k] = get(answers, k, 0) + 1
    end
    return out, answers
end

if abspath(PROGRAM_FILE) == @__FILE__
    runs = parse(Int, ARGS[1])
    @printf("BP #6, %d runs each: correct / wrong / none, and the commonest answers.\n", runs)
    for taught in (false, true)
        out, answers = run_mentor(runs; taught=taught)
        @printf("%-14s %3d / %3d / %3d\n", taught ? "after lessons" : "untaught", out[:correct], out[:incorrect], out[:none])
        for (k, v) in sort(collect(answers); by=x -> -x[2])[1:min(4, end)]
            println("    ×$v  $k")
        end
    end
end
