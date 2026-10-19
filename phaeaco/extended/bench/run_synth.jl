# Run the solver on synthetic BPs and tabulate the outcomes.
#   julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_synth.jl RUNS [bpseed=N] [names...]
# Each run uses a fresh LTM and a different seed; the BP itself is fixed
# (seed 1 unless bpseed= says otherwise), as a real BP is. Development used
# bpseed 1 only, so other seeds are held-out instances of the same rules.
using PhaeacoX, Printf
const P = PhaeacoX

function run_one(name, runs; params=P.load_params(), bpseed=1, verbose=false)
    bp, _ = P.synth_bp(name; seed=bpseed)
    out = Dict(:correct => 0, :incorrect => 0, :none => 0)
    ticks = Dict(:correct => Int[], :incorrect => Int[], :none => Int[])
    stages = Dict{Symbol,Int}()
    answers = Dict{String,Int}()
    secs = 0.0
    for seed in 1:runs
        t0 = time()
        r = P.solve(bp, params, seed)
        secs += time() - t0
        j = P.judge(name, r)
        out[j] += 1
        push!(ticks[j], r.ticks)
        stages[r.stage] = get(stages, r.stage, 0) + 1
        r.answer === nothing || (answers[string(r.answer)] = get(answers, string(r.answer), 0) + 1)
        verbose && println("  seed $seed: $j  $(r.stage)  $(r.ticks) ticks  $(r.answer)")
    end
    return out, ticks, stages, answers, secs / runs
end

if abspath(PROGRAM_FILE) == @__FILE__
    runs = parse(Int, ARGS[1])
    rest = ARGS[2:end]
    bpseed = 1
    if !isempty(rest) && startswith(rest[1], "bpseed=")
        bpseed = parse(Int, rest[1][8:end])
        rest = rest[2:end]
    end
    names = isempty(rest) ? sort!(collect(keys(P.SYNTH_BPS))) : Symbol.(rest)
    P.solve(P.synth_bp(:position; seed=1)[1], P.load_params(), 1)       # compile first
    bpseed == 1 || println("held-out instances: bpseed = $bpseed")
    @printf("%-15s %8s %8s %8s %10s %7s   %s\n", "synthetic BP", "correct", "wrong", "none", "mean ticks", "s/run", "stages / commonest answers")
    for n in names
        out, ticks, stages, answers, spr = run_one(n, runs; bpseed=bpseed)
        ok = ticks[:correct]
        mt = isempty(ok) ? NaN : sum(ok) / length(ok)
        top = sort(collect(answers); by=x -> -x[2])[1:min(2, length(answers))]
        @printf("%-15s %8d %8d %8d %10.0f %7.2f   %s  %s\n", n, out[:correct], out[:incorrect], out[:none], mt, spr,
                join(["$k=$v" for (k, v) in stages], " "), join(["$a ×$c" for (a, c) in top], "; "))
    end
end
