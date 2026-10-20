# Metacat's answer comparison and reminding (Marshall 1999, section 5.2.3):
# the demo families of demos.ss run through ONE episodic memory, then every
# pair of answers measured with Metacat's own answer distance and turned into
# the reminding strength `compare` gives (100 at distance 0, 0 at
# `%distance-threshold%` or beyond).
#
# Each answer is obtained in justify mode (Metacat is given the problem AND
# the answer and asked why), so the families hold the answers the demos name.
# The demos' seeds are Chez seeds for the original random generator; under the
# shared MT19937 they are just seeds, and a run that does not reach the answer
# is retried with the next seed.
#
#   julia metacat/bench/reminding_families.jl [limit] [tries] [offset]
#
# `offset` shifts every seed, for replications with different runs.
include("../../copycat/julia/src/pyrandom.jl")
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
using Printf

# demos.ss, "Answer comparison and reminding (section 5.2.3)". eqe-qeeeq is
# left out: it names no answer.
const FAMILIES = [
    "xyz" => [("abc", "abd", "xyz", "xyd", 1760747975), ("abc", "abd", "xyz", "wyz", 3100511611),
              ("abc", "abd", "xyz", "dyz", 2107869027), ("rst", "rsu", "xyz", "xyu", 939480183),
              ("rst", "rsu", "xyz", "wyz", 720286361), ("rst", "rsu", "xyz", "uyz", 2330176791)],
    "mrrjjj" => [("abc", "abd", "mrrjjj", "mrrkkk", 4211806334), ("abc", "abd", "mrrjjj", "mrrjjjj", 1092119323),
                 ("xqc", "xqd", "mrrjjj", "mrrkkk", 1248075611), ("xqc", "xqd", "mrrjjj", "mrrjjjj", 3729474543)],
    "eqe" => [("eqe", "qeq", "abbba", "baaab", 3635369418), ("eqe", "qeq", "abbba", "aaabaaa", 4209674874),
              ("eqe", "qeq", "abbbc", "aaabccc", 789090523)],
]

function main(args)
    limit = length(args) >= 1 ? parse(Int, args[1]) : 20000
    tries = length(args) >= 2 ? parse(Int, args[2]) : 5
    offset = length(args) >= 3 ? parse(Int, args[3]) : 0
    net = build_slipnet()
    mem = make_memory()
    found = Tuple{String,String,AnswerDescription}[]      # (family, label, description)
    for (fam, probs) in FAMILIES, (i, m, t, ans, seed) in probs
        label = "$i→$m, $t→$ans"
        got = false
        for k in 0:tries-1
            before = length(get_answers(mem))
            # Some justify runs hit a bug of the original Metacat itself: a rule's
            # `subobjects` change applied to a reference object that is a letter
            # sends `get-constituent-objects` to the letter. Chez reports "bad
            # message"; the port raises a MethodError at the same point (e.g.
            # eqe qeq abbba, answer aaabaaa, seed 2062194226, in both). Such a run
            # counts as a failed try.
            local outcome, ctx
            try
                (outcome, ctx) = run_problem(net, i, m, t, Int(seed % 2^31) + offset + k, limit;
                                             answer_sym = ans, memory = mem,
                                             trace = make_temporal_trace())
            catch e
                e isa MethodError || rethrow()
                @printf("%-8s %-24s seed+%d  Metacat's get-constituent-objects bug; next seed\n", fam, label, k)
                continue
            end
            if outcome == :answer && length(get_answers(mem)) > before
                a = get_answers(mem)[1]                     # newest first
                letters_print_name(a.answer_letters) == ans || continue
                push!(found, (fam, label, a))
                @printf("%-8s %-24s seed+%d  %5d codelets  quality %3d\n", fam, label, k, ctx.codelet_count, a.quality)
                got = true
                break
            end
        end
        got || @printf("%-8s %-24s not reached in %d tries\n", fam, label, tries)
    end
    n = length(found)
    act(a, b) = sub_from_100(sround(100 * smin(1, sdiv(calculate_answer_distance(a, b, mem, net), DISTANCE_THRESHOLD))))
    A = [i == j ? 100 : act(found[i][3], found[j][3]) for i in 1:n, j in 1:n]
    println("\nReminding strength between answers (Metacat's `compare`; 100 = the same answer):")
    @printf("%-26s", "")
    for j in 1:n; @printf("%4d", j); end
    println()
    for i in 1:n
        @printf("%2d %-23s", i, found[i][2])
        for j in 1:n; @printf("%4d", A[i, j]); end
        println()
    end
    within = [A[i, j] for i in 1:n, j in 1:n if i < j && found[i][1] == found[j][1]]
    between = [A[i, j] for i in 1:n, j in 1:n if i < j && found[i][1] != found[j][1]]
    m(v) = isempty(v) ? NaN : sum(v) / length(v)
    @printf("\nwithin a family: mean %.1f, reminding (> 0) in %d of %d pairs\n", m(within), count(>(0), within), length(within))
    @printf("between families: mean %.1f, reminding (> 0) in %d of %d pairs\n", m(between), count(>(0), between), length(between))
    # the strongest reminding of each answer by an EARLIER one, as Metacat experiences it in order
    println("\nAs met in order, each answer's strongest reminding of an earlier one:")
    for j in 2:n
        i = argmax(i -> A[i, j], 1:j-1)
        @printf("  %-24s ← %-24s %3d%s\n", found[j][2], found[i][2], A[i, j], found[i][1] == found[j][1] ? "" : "  (other family)")
    end
    return 0
end

exit(main(ARGS))
