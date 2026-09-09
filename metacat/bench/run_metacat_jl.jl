# Julia counterpart of metacat/bench/run_metacat_scm.ss: runs one Metacat
# problem and prints the same canonical result block, so the two can be diffed.
#
#   julia metacat/bench/run_metacat_jl.jl <initial> <modified> <target> <seed> [limit]
#
# Add a fifth string to run in JUSTIFY MODE -- the configuration where Metacat is
# given the answer as well as the problem and asked why:
#
#   julia metacat/bench/run_metacat_jl.jl abc abd mrrjjj 23 5000 --answer mrrjjjj
#
# The outcome is `answer` when a codelet reported one, `give-up` when a jootser
# decided there was nothing better to try, and `limit` when the budget ran out.
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

hyphen(s::Symbol) = replace(String(s), "_" => "-")

function main(args)
    if length(args) < 4
        println(stderr,
                "usage: run_metacat_jl.jl <initial> <modified> <target> <seed> " *
                "[limit] [--answer <string>]")
        return 2
    end
    initial, modified, target = args[1], args[2], args[3]
    seed = parse(Int, args[4])
    limit = (length(args) > 4 && !startswith(args[5], "--")) ? parse(Int, args[5]) : 100000
    i = findfirst(==("--answer"), args)
    answer = i === nothing ? nothing : args[i + 1]

    mem = make_memory()
    (outcome, ctx) = run_problem(build_slipnet(), initial, modified, target, seed, limit;
                                 answer_sym = answer, memory = mem,
                                 trace = make_temporal_trace())
    println("OUTCOME\t", hyphen(outcome), "\tCODELETS\t", ctx.codelet_count,
            "\tTEMP\t", ctx.temperature)
    for a in get_answers(mem)
        println("ANSWER\t", problem_print_name(a), "\t",
                letters_print_name(a.answer_letters), "\t", a.quality, "\t",
                a.temperature)
    end
    return 0
end

exit(main(ARGS))
