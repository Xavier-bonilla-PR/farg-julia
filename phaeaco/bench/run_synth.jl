# Run the solver on synthetic BPs and tabulate the outcomes.
#   julia --project=phaeaco/julia phaeaco/bench/run_synth.jl RUNS [names...]
# Each run uses a fresh LTM and a different seed; the BP itself is fixed
# (seed 1), as a real BP is.
using PhaeacoJL, Printf
const P = PhaeacoJL

function run_one(name, runs; params=P.load_params(), bpseed=1, verbose=false)
    bp, _ = P.synth_bp(name; seed=bpseed)
    out = Dict(:correct => 0, :incorrect => 0, :none => 0)
    ticks = Dict(:correct => Int[], :incorrect => Int[], :none => Int[])
    stages = Dict{Symbol,Int}()
    answers = Dict{String,Int}()
    for seed in 1:runs
        r = P.solve(bp, params, seed)
        j = P.judge(name, r)
        out[j] += 1
        push!(ticks[j], r.ticks)
        stages[r.stage] = get(stages, r.stage, 0) + 1
        r.answer === nothing || (answers[string(r.answer)] = get(answers, string(r.answer), 0) + 1)
        verbose && println("  seed $seed: $j  $(r.stage)  $(r.ticks) ticks  $(r.answer)")
    end
    return out, ticks, stages, answers
end

if abspath(PROGRAM_FILE) == @__FILE__
    runs = parse(Int, ARGS[1])
    names = length(ARGS) >= 2 ? Symbol.(ARGS[2:end]) : sort!(collect(keys(P.SYNTH_BPS)))
    @printf("%-15s %8s %8s %8s %10s   %s\n", "synthetic BP", "correct", "wrong", "none", "mean ticks", "stages / commonest answers")
    for n in names
        out, ticks, stages, answers = run_one(n, runs)
        ok = ticks[:correct]
        mt = isempty(ok) ? NaN : sum(ok) / length(ok)
        top = sort(collect(answers); by=x -> -x[2])[1:min(2, length(answers))]
        @printf("%-15s %8d %8d %8d %10.0f   %s  %s\n", n, out[:correct], out[:incorrect], out[:none], mt,
                join(["$k=$v" for (k, v) in stages], " "), join(["$a ×$c" for (a, c) in top], "; "))
    end
end
