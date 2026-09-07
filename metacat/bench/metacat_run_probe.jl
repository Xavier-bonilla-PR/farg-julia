# Julia counterpart of metacat/bench/metacat_run_probe.ss: run.ss's DRIVER --
# `init-mcat`, `step-mcat` and `run-mcat` -- the model run end to end.
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

net = build_slipnet()

sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
hyphen(s::Symbol) = replace(String(s), "_" => "-")

count_of(T, structures) = count(s -> s isa T, structures)

# The episodic memory is NOT cleared between problems, exactly as it is not in
# a real session: `init-mcat` clears its ACTIVATIONS only.
mem = make_memory()

# --- the state the run ended in ---------------------------------------------

function dump_final_state(tag, ctx, tr)
    structures = get_structures(ctx)
    objs = workspace_objects(ctx)
    println("ST\t", tag, "\t", ctx.temperature, "\tb", count_of(Bond, structures),
            "/g", count_of(Group, structures), "/x", count_of(Bridge, structures),
            "/r", count_of(Rule, structures), "\to", length(objs), "\tcr",
            length(ctx.coderack.codelet_list))
    println("STU\t", tag, "\t", get_average_intra_string_unhappiness(ctx), "\t",
            get_average_unhappiness(ctx), "\t", get_min_mapping_strength(ctx), "\t",
            get_max_inter_string_unhappiness(ctx), "\t",
            join_or_dash([string(t) for t in get_possible_rule_types(ctx)]))
    counts = String[]
    for name in ALL_CODELET_TYPE_NAMES
        n = count(k -> k.codelet_type.name === name, ctx.coderack.codelet_list)
        n == 0 && continue
        ct = get(CODELET_TYPES, name, nothing)
        push!(counts, string(ct === nothing ? hyphen(name) : codelet_type_display(ct),
                             ":", n))
    end
    println("STC\t", tag, "\t", join_or_dash(counts))
    println("STN\t", tag, "\t",
            join_or_dash([string(sn(n), ":", n.activation) for n in net.top_down_nodes]))
    println("STT\t", tag, "\t", length(ctx.themespace.all_themes), "\t",
            join_or_dash([hyphen(s) for s in ctx.themespace.active_theme_types]), "\t",
            length(get_all_events(tr)), "\t", yn(tr.within_snag_period), "\t",
            yn(tr.within_clamp_period))
    # every event the run left in the trace, in order
    for e in reverse(get_all_events(tr))
        println("EV\t", tag, "\t", get_event_number(e), "\t",
                hyphen(get_event_type(e)), "\t", event_print_name(e))
    end
    return
end

# --- what the run concluded, as the memory holds it -------------------------

function dump_memory(tag)
    println("MEM\t", tag, "\t", length(get_answers(mem)), "\t", length(get_snags(mem)))
    for a in get_answers(mem)
        println("MA\t", tag, "\t", problem_print_name(a), "\t",
                letters_print_name(a.answer_letters), "\t", a.quality, "\t",
                a.temperature, "\t", a.activation)
        # The RULE the answer rests on, in English, and whether it is a SWAP.
        # Without this the probe compares what the model answered but not what
        # it thought, and an extrinsic (swap) clause -- the one clause kind a
        # whole run rarely produces -- would go through translation, string
        # instantiation and abstraction without ever being looked at.
        for phrase in a.top_rule_phrases
            println("MAR\t", tag, "\t", letters_print_name(a.answer_letters), "\t",
                    phrase)
        end
        println("MAX\t", tag, "\t", letters_print_name(a.answer_letters), "\t",
                yn(any(is_extrinsic_clause, a.top_rule_clauses)), "\t",
                a.top_rule_abstractness)
    end
    for s in get_snags(mem)
        println("MS\t", tag, "\t", problem_print_name(s), "\t", s.snag_explanation,
                "\t", s.activation)
    end
    return
end

# --- probe -------------------------------------------------------------------

function probe(tag, i, m, t, seed, limit)
    println("PROBLEM\t", tag, "\t", i, "\t", m, "\t", t, "\t", seed, "\t", limit)
    tr = make_temporal_trace()
    (outcome, ctx) = run_problem(net, i, m, t, seed, limit; memory = mem, trace = tr)
    println("OUTCOME\t", tag, "\t", hyphen(outcome), "\t", ctx.codelet_count, "\t",
            ctx.temperature)
    dump_final_state(tag, ctx, tr)
    dump_memory(tag)
    return
end

# Short budgets first, so the loop's own bookkeeping is compared before any
# answer can end a run: the unclamp time, the every-fifteenth update, and the
# refill when the rack empties.
probe("budget50", "abc", "abd", "ijk", 1001, 50)
probe("budget200", "abc", "abd", "mrrjjj", 1003, 200)
probe("budget800", "mrrjjj", "mrrkkk", "xyz", 1005, 800)
# Then long enough to finish, on the problem the reference runner uses.
probe("full1", "abc", "cba", "pqrs", 42, 20000)
probe("full2", "abc", "abd", "ijk", 7, 20000)
# And once more on a problem already in memory, so reminding is live.
probe("again", "abc", "cba", "pqrs", 99, 20000)

# SWAP (EXTRINSIC) RULE CLAUSES. A rule clause is extrinsic when two objects
# trade a descriptor along one dimension -- "swap the string-positions of the
# leftmost and rightmost letter" -- and it takes its own arm through
# `translate_rule_clause`, which the hand-built probes could not reach.
#
# That arm was ALREADY reached, once, by `again` above: its answer sqrp rests
# on a swap rule, which the MAR line now makes visible. These two widen it.
#
#   swaptranslate -- `abc -> cba` seed 4. Twenty passes through the extrinsic
#                    arm, against one everywhere else, because the model keeps
#                    proposing and translating swap rules; its own answer then
#                    comes from a verbatim rule, so this is coverage of the
#                    TRANSLATION, not of an answer.
#   swapanswer    -- `mrrjjj -> jjjrrm` seed 4, the case rules.ss and
#                    answers.jl both name: the [m] and the [jjj] trade places,
#                    so the swap is between a LETTER and a GROUP and carries
#                    Length with it -- a shape `abc -> cba` cannot make. Its
#                    answer IS reported through that rule.
probe("swaptranslate", "abc", "cba", "pqrs", 4, 4000)
probe("swapanswer", "mrrjjj", "jjjrrm", "xyz", 4, 4000)
