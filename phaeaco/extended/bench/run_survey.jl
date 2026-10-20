# Run PhaeacoX on any BP stacks in phaeaco/data and list what it answers,
# next to the intended rule from the PBM's comments. For BPs outside
# Appendix A there is no machine-readable rule: an answer was verified on all
# twelve boxes, so it is true of them, but whether it is the intended rule
# is judged by SURVEY_RULES where PhaeacoX has a percept that can state it
# (✓ / ✗), and by reading otherwise (results/survey_judged.md).
#   julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_survey.jl RUNS [numbers...]
using PhaeacoX, Printf
const P = PhaeacoX

function survey(n, runs; params=P.load_params())
    bp = P.load_bp(joinpath(@__DIR__, "..", "..", "data", @sprintf("bp%03d.pbm", n)))
    answers = Dict{String,Int}()
    nanswered = 0
    secs = 0.0
    for seed in 1:runs
        t0 = time()
        r = P.solve(bp, params, seed)
        secs += time() - t0
        j = P.judge_survey(n, r)
        k = r.answer === nothing ? "—" : (j == :correct ? "✓ " : j == :incorrect ? "✗ " : "") * string(r.answer)
        r.answer === nothing || (nanswered += 1)
        answers[k] = get(answers, k, 0) + 1
    end
    return bp, nanswered, answers, secs / runs
end

if abspath(PROGRAM_FILE) == @__FILE__
    runs = parse(Int, ARGS[1])
    have = sort([parse(Int, m[1]) for f in readdir(joinpath(@__DIR__, "..", "..", "data"))
                 for m in (match(r"^bp(\d+)\.pbm$", f),) if m !== nothing])
    nums = length(ARGS) >= 2 ? parse.(Int, ARGS[2:end]) : filter(n -> !haskey(P.APPENDIX_A, n), have)
    @printf("Survey: %d runs per BP. answered = runs ending in a verified idea.\n\n", runs)
    for n in nums
        bp, k, answers, spr = survey(n, runs)
        @printf("BP #%d  (%s | %s)  answered %d/%d  %.2f s/run\n", n, bp.left_label, bp.right_label, k, runs, spr)
        for (a, c) in sort(collect(answers); by=x -> -x[2])
            @printf("    ×%-3d %s\n", c, a)
        end
    end
end
