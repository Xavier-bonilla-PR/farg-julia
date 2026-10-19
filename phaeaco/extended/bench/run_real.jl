# Run the solver on the real BPs of the target set and compare with Appendix A.
#   julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_real.jl RUNS [numbers...]
# Needs the PBM stacks in phaeaco/data (see bench/fetch/).
using PhaeacoX, Printf
const P = PhaeacoX

function run_bp(n, runs; params=P.load_params(), verbose=false)
    bp = P.load_bp(joinpath(@__DIR__, "..", "..", "data", @sprintf("bp%03d.pbm", n)))
    out = Dict(:correct => 0, :incorrect => 0, :none => 0)
    ticks = Int[]
    answers = Dict{String,Int}()
    for seed in 1:runs
        r = P.solve(bp, params, seed)
        j = P.judge_real(n, r)
        out[j] += 1
        j == :correct && push!(ticks, r.ticks)
        k = r.answer === nothing ? "—" : "$(j == :correct ? "✓" : "✗") $(r.answer)"
        answers[k] = get(answers, k, 0) + 1
        verbose && println("  seed $seed: $j $(r.stage) $(r.ticks) $(r.answer)")
    end
    return out, ticks, answers
end

if abspath(PROGRAM_FILE) == @__FILE__
    runs = parse(Int, ARGS[1])
    nums = length(ARGS) >= 2 ? parse.(Int, ARGS[2:end]) : sort!(collect(keys(P.APPENDIX_A)))
    res = Dict(n => run_bp(n, runs) for n in nums)
    t3 = haskey(res, 3) && !isempty(res[3][2]) ? sum(res[3][2]) / length(res[3][2]) : NaN
    @printf("Real BPs, %d runs each. Percentages: correct / wrong / none. Relative time: mean ticks to a correct answer ÷ BP #3's.\n", runs)
    @printf("%-6s %-22s %-22s %-14s %s\n", "BP", "PhaeacoX", "Phaeaco (App. A)", "rel. time", "commonest answers")
    for n in nums
        out, ticks, answers = res[n]
        pct(k) = round(Int, 100 * out[k] / runs)
        a = P.APPENDIX_A[n]
        rt = isempty(ticks) ? NaN : (sum(ticks) / length(ticks)) / t3
        top = sort(collect(answers); by=x -> -x[2])[1:min(2, length(answers))]
        @printf("#%-5d %3d / %3d / %3d        %3d / %3d / %3d        %5.2f vs %5.2f  %s\n", n, pct(:correct), pct(:incorrect), pct(:none),
                a[1], a[2], a[3], rt, a[4], join(["$k ×$v" for (k, v) in top], "; "))
    end
end
