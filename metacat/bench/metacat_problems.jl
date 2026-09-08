# Julia counterpart of metacat/bench/metacat_problems.ss: the same problems, the
# same iteration counts, the same checksum fields. See that file for why the
# benchmark is shaped this way and why the memory is cleared every iteration.
include("../../copycat/julia/src/pyrandom.jl")  # shared MT19937 (Copycat side)
include("../julia/src/schemenum.jl")
include("../julia/src/utilities.jl")
include("../julia/src/slipnet.jl")
include("../julia/src/workspace.jl")
include("../julia/src/concept_mappings.jl")
include("../julia/src/images.jl")
include("../julia/src/bonds.jl")
include("../julia/src/groups.jl")
include("../julia/src/bridges.jl")
include("../julia/src/coderack.jl")
include("../julia/src/themes.jl")
include("../julia/src/context.jl")
include("../julia/src/codelets_bonds.jl")
include("../julia/src/codelets_descriptions.jl")
include("../julia/src/codelets_groups.jl")
include("../julia/src/codelets_bridges.jl")
include("../julia/src/codelets_themes.jl")
include("../julia/src/codelets_breaker.jl")
include("../julia/src/rules.jl")
include("../julia/src/answers.jl")
include("../julia/src/trace.jl")
include("../julia/src/justify.jl")
include("../julia/src/memory.jl")
include("../julia/src/codelets_jootsing.jl")
include("../julia/src/run.jl")

const net = build_slipnet()

hyphen(s::Symbol) = replace(String(s), "_" => "-")

# The Scheme's memory is a global that `run-problem` writes into and the
# benchmark clears; here a fresh `make_memory()` per iteration is the same
# thing, so each timed run starts from an empty memory either way.
function timeit_problem(name, iterations, thunk)
    thunk()                                   # warm up: compile
    result = thunk()                          # warm up: and let it settle
    t0 = time_ns()
    final = result
    for _ in 1:iterations
        final = thunk()
    end
    elapsed = (time_ns() - t0) / 1e9
    println("PROB\t", name, "\t", iterations, "\t", elapsed, "\t",
            hyphen(final[1]), "\t", final[2], "\t", final[3])
end

ordinary_problem(i, m, t, seed, limit) = function ()
    (outcome, ctx) = run_problem(net, i, m, t, seed, limit;
                                 memory = make_memory(), trace = make_temporal_trace())
    return (outcome, ctx.codelet_count, ctx.temperature)
end

justify_problem(i, m, t, a, seed, limit) = function ()
    (outcome, ctx) = run_problem(net, i, m, t, seed, limit; answer_sym = a,
                                 memory = make_memory(), trace = make_temporal_trace())
    return (outcome, ctx.codelet_count, ctx.temperature)
end

# A whole run before any timing starts. The per-problem warm-ups are not enough
# on their own: the FIRST problem in the file still absorbed residual
# compilation and intermittently read ~3x slow, because until something has run
# end to end there are code paths no warm-up of that problem has reached.
ordinary_problem("abc", "abd", "ijk", 99, 2000)()
justify_problem("abc", "abd", "ijk", "ijl", 98, 2000)()

#--- ordinary runs -----------------------------------------------------------
timeit_problem("abc:abd::ijk:?",     5, ordinary_problem("abc", "abd", "ijk", 11, 5000))
timeit_problem("abc:abd::iijjkk:?",  5, ordinary_problem("abc", "abd", "iijjkk", 12, 5000))
timeit_problem("abc:cba::pqrs:?",    5, ordinary_problem("abc", "cba", "pqrs", 13, 5000))
timeit_problem("abc:abd::xyz:?",     5, ordinary_problem("abc", "abd", "xyz", 14, 5000))
timeit_problem("abc:abd::mrrjjj:?",  5, ordinary_problem("abc", "abd", "mrrjjj", 15, 5000))
timeit_problem("mrrjjj:mrrkkk::xyz:?", 5, ordinary_problem("mrrjjj", "mrrkkk", "xyz", 16, 5000))

#--- justify mode ------------------------------------------------------------
timeit_problem("abc:abd::ijk:ijl",   5, justify_problem("abc", "abd", "ijk", "ijl", 21, 5000))
timeit_problem("abc:cba::pqrs:srqp", 5, justify_problem("abc", "cba", "pqrs", "srqp", 22, 5000))
timeit_problem("abc:abd::mrrjjj:mrrjjjj", 5, justify_problem("abc", "abd", "mrrjjj", "mrrjjjj", 23, 5000))
