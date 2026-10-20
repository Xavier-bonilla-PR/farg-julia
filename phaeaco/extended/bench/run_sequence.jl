# Bongard's problems in the book's order, one context carried through them
# all, so that each solved problem is remembered (X14). Run with the memory
# on and off (`ext_memory=0`) to see what reminding does. Per problem:
# correct / wrong / none over the seeds, how many runs were solved by
# analogy, and from which problems.
#   julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_sequence.jl SEED1 SEED2 [key=value ...]
using PhaeacoX, Printf
const P = PhaeacoX

judge(n, r) = haskey(P.REAL_RULES, n) ? P.judge_real(n, r) : P.judge_survey(n, r)

function run_sequence(seeds; params=P.load_params(), nums=1:100)
    data = joinpath(@__DIR__, "..", "..", "data")
    bps = Dict(n => P.load_bp(joinpath(data, @sprintf("bp%03d.pbm", n))) for n in nums)
    res = Dict(n => Dict{Symbol,Int}() for n in nums)
    ticks = Dict(n => 0 for n in nums)
    from = Dict(n => Dict{String,Int}() for n in nums)
    for seed in seeds
        ctx = P.Ctx(params, seed)
        for n in nums
            r = P.solve(bps[n], ctx)
            j = judge(n, r)
            res[n][j] = get(res[n], j, 0) + 1
            ticks[n] += r.ticks
            if r.stage == :analogy
                res[n][:analogy] = get(res[n], :analogy, 0) + 1
                m = match(r"reminded of (\S+)", join(r.log, "\n"))
                k = m === nothing ? "?" : m[1]
                from[n][k] = get(from[n], k, 0) + 1
            end
        end
    end
    return res, ticks, from
end

if abspath(PROGRAM_FILE) == @__FILE__
    s1, s2 = parse(Int, ARGS[1]), parse(Int, ARGS[2])
    kv = Dict(Symbol(split(a, '=')[1]) => parse(Float64, split(a, '=')[2]) for a in ARGS[3:end])
    res, ticks, from = run_sequence(s1:s2; params=P.load_params(; kv...))
    @printf("Sequence 1..100, seeds %d-%d%s. ✓ ✗ — unscored-answered, analogy, mean ticks\n", s1, s2,
            isempty(kv) ? "" : " ($(join(("$k=$v" for (k, v) in kv), ", ")))")
    for n in sort(collect(keys(res)))
        r = res[n]
        @printf("#%-3d %3d %3d %3d %3d  analogy %2d  %7.0f  %s\n", n, get(r, :correct, 0), get(r, :incorrect, 0),
                get(r, :none, 0), get(r, :unscored, 0), get(r, :analogy, 0), ticks[n] / (s2 - s1 + 1),
                join(("$k×$v" for (k, v) in from[n]), " "))
    end
end
