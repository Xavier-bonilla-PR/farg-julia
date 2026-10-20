# Spontaneous analogy in isolation (X14): solve problem A, then problem B in
# the same context, with the memory on and off. Pairs whose rules are
# analogous should be solved more often or sooner; pairs that only look
# alike should cost little.
#   julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_pairs.jl RUNS
using PhaeacoX, Printf
const P = PhaeacoX

const PAIRS = [(36, 37), (27, 28), (37, 48), (36, 38), (19, 20), (2, 3)]
judge(n, r) = haskey(P.REAL_RULES, n) ? P.judge_real(n, r) : P.judge_survey(n, r)
bp(n) = P.load_bp(joinpath(@__DIR__, "..", "..", "data", @sprintf("bp%03d.pbm", n)))

function run_pair(a, b, runs, memory)
    A, B = bp(a), bp(b)
    out = Dict(:correct => 0, :incorrect => 0, :none => 0, :unscored => 0)
    ticks = 0; analog = 0
    for seed in 1:runs
        ctx = P.Ctx(P.load_params(; ext_memory=memory), seed)
        P.solve(A, ctx)
        r = P.solve(B, ctx)
        out[judge(b, r)] += 1
        ticks += r.ticks
        analog += r.stage == :analogy
    end
    return out, ticks / runs, analog
end

if abspath(PROGRAM_FILE) == @__FILE__
    runs = parse(Int, ARGS[1])
    @printf("A then B, %d runs. B's correct / wrong / none (unscored answered), mean ticks, solved by analogy.\n", runs)
    for (a, b) in PAIRS
        for m in (0, 1)
            o, t, an = run_pair(a, b, runs, m)
            @printf("#%-3d → #%-3d memory %s  %2d / %2d / %2d (%2d)  %6.0f ticks  analogy %2d\n", a, b, m == 1 ? "on " : "off",
                    o[:correct], o[:incorrect], o[:none], o[:unscored], t, an)
        end
    end
end
