# Julia counterpart of metacat/bench/metacat_justifymode_probe.ss: JUSTIFY MODE
# -- the model run end to end with a fourth string.
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
    # the justify-mode half of the workspace, which no other probe has
    println("STJ\t", tag, "\tr", length(get_rules(ctx, :top)), "/",
            length(get_rules(ctx, :bottom)),
            "\tx", length(get_bridges(ctx, :top)), "/",
            length(get_bridges(ctx, :bottom)), "/",
            length(get_bridges(ctx, :vertical)),
            "\tm", get_mapping_strength(ctx, :top), "/",
            get_mapping_strength(ctx, :bottom), "/",
            get_mapping_strength(ctx, :vertical),
            "\tu", ctx.average_top_inter_string_unhappiness, "/",
            ctx.average_bottom_inter_string_unhappiness, "/",
            ctx.average_vertical_inter_string_unhappiness, "\t",
            join_or_dash([string(t) for t in get_possible_rule_types(ctx)]))
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
        # Whether the model could JUSTIFY the answer, and if not, which
        # slippages it could not account for. An answer carrying unjustified
        # slippages can only have come from `joots_from_justify_clamps`: every
        # other call to `report_new_answer!` passes an empty list here. So this
        # line is the visible trace of the model settling for an answer it
        # cannot defend.
        println("MAJ\t", tag, "\t", letters_print_name(a.answer_letters), "\t",
                yn(is_unjustified(a)), "\t",
                join_or_dash([cm_english_name(cm) for cm in a.unjustified_slippages]))
    end
    for s in get_snags(mem)
        println("MS\t", tag, "\t", problem_print_name(s), "\t", s.snag_explanation,
                "\t", s.activation)
    end
    return
end

# --- probe -------------------------------------------------------------------

function probe(tag, i, m, t, a, seed, limit)
    println("PROBLEM\t", tag, "\t", i, "\t", m, "\t", t, "\t", a, "\t", seed,
            "\t", limit)
    tr = make_temporal_trace()
    (outcome, ctx) = run_problem(net, i, m, t, seed, limit; answer_sym = a,
                                 memory = mem, trace = tr)
    println("OUTCOME\t", tag, "\t", hyphen(outcome), "\t", ctx.codelet_count, "\t",
            ctx.temperature)
    dump_final_state(tag, ctx, tr)
    dump_memory(tag)
    return
end

# Short budgets first, so the loop's bookkeeping in justify mode is compared
# before any answer can end a run.
probe("budget60", "abc", "abd", "ijk", "ijl", 2001, 60)
probe("budget250", "abc", "cba", "pqrs", "srqp", 2002, 250)
probe("budget700", "mrrjjj", "mrrkkk", "xyz", "xyd", 2003, 700)
# Then long enough to justify, or to fail to.
probe("full1", "abc", "abd", "ijk", "ijl", 42, 20000)
probe("full2", "abc", "cba", "pqrs", "srqp", 7, 20000)
# A literal answer, where the bottom rule is verbatim and the halves do not
# unify -- the clamping arm.
probe("literal", "abc", "abd", "ijk", "ijd", 11, 20000)
# And one already in memory, so reminding is live in justify mode too.
probe("again", "abc", "abd", "ijk", "ijl", 99, 20000)

# And a WRONG answer, which the model cannot justify however hard it tries:
# it clamps the rules together over and over, and the jootser eventually
# notices the repetition and gives up. That run exercises the jootser inside
# justify mode, which nothing else does.
probe("wrong", "abc", "abd", "ijk", "xyz", 6, 12000)

# SETTLING FOR AN UNJUSTIFIED ANSWER -- `joots_from_justify_clamps`, the one
# jootser arm that does not give up.
#
# Three EQUIVALENT justify clamps have to be the most recent cluster in the
# trace, and the gate is narrow: for a justify clamp the clamp-type factor is
# 1 only when the trace's LAST event is itself a clamp, and the jootser also
# refuses to look while a clamp period is running. Then, having re-translated
# the clamped top rule, it settles with probability 1/n for n unjustified
# slippages.
#
# `mrrjjj -> mrrjjjj` is the case the Scheme's own comment discusses -- the
# bottom rule increases the length of the j group, and the top rule cannot be
# walked onto it cleanly. Here the model clamps the two rules together
# repeatedly, notices the repetition, and settles: the answer it reports
# carries the slippages it could not account for, which the MAJ line shows.
# No other configuration in this suite reaches that arm.
probe("unjustified", "abc", "abd", "mrrjjj", "mrrjjjj", 6, 10000)
