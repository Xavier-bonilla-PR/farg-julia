#!/usr/bin/env julia
# Benchmark/verification runner for the Julia Copycat port.
#
# Usage: julia --project=copycat/julia copycat/bench/run_jl.jl <initial> <modified> <target>
#                                              <iterations> [--seed N] [--json]
#
# Prints the same canonical result block as copycat/bench/run_py.py.

using Printf
using CopycatJL
const C = CopycatJL

function main()
    args = copy(ARGS)
    seed = nothing
    asjson = false
    warmup = 0
    i = 1
    positional = String[]
    while i <= length(args)
        a = args[i]
        if a == "--seed"
            seed = parse(Int, args[i + 1]); i += 2
        elseif a == "--warmup"
            warmup = parse(Int, args[i + 1]); i += 2
        elseif a == "--json"
            asjson = true; i += 1
        else
            push!(positional, a); i += 1
        end
    end
    initial, modified, target = positional[1], positional[2], positional[3]
    iterations = parse(Int, positional[4])

    # Warm up so that Julia's JIT compilation is not charged to the measured
    # run. Uses a throwaway instance so the measured RNG stream is untouched.
    if warmup > 0
        wcc = C.Copycat(rng_seed = 12345)
        C.resetWithStrings!(wcc.workspace, initial, modified, target)
        C.useAdj!(wcc.temperature, :pbest)
        for _ in 1:warmup
            C.runTrial!(wcc)
        end
    end

    setup0 = time_ns()
    cc = C.Copycat(rng_seed = seed)
    C.resetWithStrings!(cc.workspace, initial, modified, target)
    C.useAdj!(cc.temperature, :pbest)
    setup = (time_ns() - setup0) / 1e9

    keys = String[]
    stats = Dict{String,C.AnswerStats}()
    total_codelets = 0
    t0 = time_ns()
    for _ in 1:iterations
        answer = C.runTrial!(cc)
        total_codelets += answer.time
        st = get(stats, answer.answer, nothing)
        if st === nothing
            st = C.AnswerStats(0, 0.0, 0.0)
            stats[answer.answer] = st
            push!(keys, answer.answer)
        end
        st.count += 1
        st.sumtemp += answer.temp
        st.sumtime += answer.time
    end
    elapsed = (time_ns() - t0) / 1e9

    if asjson
        rows = join(["""{"answer":"$(k)","count":$(stats[k].count),""" *
                     """"avgtemp":$(stats[k].sumtemp / stats[k].count),""" *
                     """"avgtime":$(stats[k].sumtime / stats[k].count)}""" for k in keys], ",")
        println("""{"impl":"julia","version":"$(VERSION)",""" *
                """"problem":["$initial","$modified","$target"],""" *
                """"iterations":$iterations,"seed":$(seed === nothing ? "null" : seed),""" *
                """"setup_s":$setup,"elapsed_s":$elapsed,"warmup":$warmup,""" *
                """"codelets":$total_codelets,"answers":[$rows]}""")
    else
        for k in keys
            @printf("%s\t%d\t%.9f\t%.6f\n", k, stats[k].count,
                    stats[k].sumtemp / stats[k].count, stats[k].sumtime / stats[k].count)
        end
        @printf("# codelets\t%d\n", total_codelets)
        @printf("# elapsed_s\t%.6f\n", elapsed)
    end
end

main()
