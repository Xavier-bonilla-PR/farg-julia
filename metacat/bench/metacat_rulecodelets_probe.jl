# Julia counterpart of metacat/bench/metacat_rulecodelets_probe.ss: the three
# rule codelets, driven directly so that the answer-finder rule-builder posts is
# only ever posted and never run.
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
include("../julia/src/rules.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
slist(xs) = string("(", join(xs, " "), ")")
net = build_slipnet()

object_tag(o) = o isa WorkspaceString ? string("string:", o.string_type) : ascii_name(o)

function seed_rack!(ctx::MetacatCtx)
    post(name, urgency, args = Any[]) =
        post!(ctx.coderack, make_codelet(CODELET_TYPES[name], urgency, args),
              ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
    for _ in 1:3
        post(:bottom_up_bond_scout, VERY_LOW_URGENCY)
        post(:group_scout_whole_string, LOW_URGENCY)
        post(:top_down_group_scout_category, LOW_URGENCY,
             Any[ctx.net[:plato_succgrp], nothing])
        post(:top_down_group_scout_category, LOW_URGENCY,
             Any[ctx.net[:plato_samegrp], nothing])
        post(:bottom_up_bridge_scout, MEDIUM_URGENCY)
        post(:bottom_up_bridge_scout, MEDIUM_URGENCY)
        post(:important_object_bridge_scout, MEDIUM_URGENCY)
        post(:bottom_up_description_scout, VERY_LOW_URGENCY)
    end
    return ctx
end

# ------------------------------------ printing ------------------------------------

rack_summary(ctx) = string(ctx.coderack.current_num)

function print_clause(rc::RuleClause)
    if is_verbatim_clause(rc)
        println("    RC\tVERBATIM\t", slist([nm(n) for n in rc.letter_categories]))
    elseif is_intrinsic_clause(rc)
        println("    RC\tCHANGE\t", format_object_description(rc.object_descriptions[1]))
        for c in rc.changes
            println("      CH\t(", c.scope, " ", sn(c.dimension), " ", sn(c.descriptor),
                    ")")
        end
    else
        println("    RC\tSWAP\t",
                slist([format_object_description(od) for od in rc.object_descriptions]),
                "\t", slist([sn(d) for d in rc.dimensions]))
    end
end

function print_rule(label, r::Rule, ctx::MetacatCtx)
    println("   RULE\t", label, "\t", r.rule_type, "\tlevel=", r.proposal_level,
            "\tstamp=", r.time_stamp)
    foreach(print_clause, r.rule_clauses)
    println("   RQ\tqual=", r.quality, "\tstr=", r.strength, "\tchar=",
            rule_characterization(r, net), "\tworks=", yn(currently_works(r, ctx)),
            "\tsupported=", yn(rule_supported(r, ctx)), "\tsupport=",
            get_degree_of_support(r, ctx))
    println("   RSUP\t",
            slist([string(object_tag(b.object1), "->", object_tag(b.object2))
                   for b in r.supporting_horizontal_bridges]))
    println("   RTAG\t",
            slist([string(yn(unsupported_self_change(tagged)), ":",
                          slist([object_tag(b.object1)
                                 for b in tagged_bridges(tagged)]))
                   for tagged in r.tagged_supporting_horizontal_bridges]))
    for line in r.english_transcription
        println("   EN\t|", line, "|")
    end
end

# Rule codelets post their successors, so the probe pulls each newly posted
# codelet back off the rack and runs it by hand: the pipeline one stage at a
# time, with what each stage did dumped in between. Codelets are never removed
# from the rack — the rack has no single-codelet delete — so the ones already
# seen are remembered instead.
const SEEN = Codelet[]

function new_codelets_of_type(ctx::MetacatCtx, type_name::Symbol)
    found = Codelet[c for c in ctx.coderack.codelet_list
                    if c.codelet_type.name === type_name && !any(x -> x === c, SEEN)]
    prepend!(SEEN, found)
    return found
end

function drive_pipeline(round, ctx::MetacatCtx)
    println("  ROUND\t", round, "\track=", rack_summary(ctx))
    before = ctx.coderack.current_num
    run_codelet!(ctx, make_codelet(CODELET_TYPES[:rule_scout], MEDIUM_URGENCY))
    println("  SCOUT\tposted=", ctx.coderack.current_num - before, "\track=",
            rack_summary(ctx))
    evaluators = new_codelets_of_type(ctx, :rule_evaluator)
    if isempty(evaluators)
        println("  NOEVAL")
    else
        for ec in evaluators
            print_rule("proposed", ec.arguments[1]::Rule, ctx)
            before = ctx.coderack.current_num
            run_codelet!(ctx, ec)
            println("  EVAL\tposted=", ctx.coderack.current_num - before, "\track=",
                    rack_summary(ctx))
        end
    end
    builders = new_codelets_of_type(ctx, :rule_builder)
    if isempty(builders)
        println("  NOBUILD")
    else
        for bc in builders
            proposed = bc.arguments[1]::Rule
            print_rule("evaluated", proposed, ctx)
            before = ctx.coderack.current_num
            run_codelet!(ctx, bc)
            println("  BUILD\tposted=", ctx.coderack.current_num - before, "\track=",
                    rack_summary(ctx), "\tlevel=", proposed.proposal_level)
        end
    end
    println("  FINDERS\t", length(new_codelets_of_type(ctx, :answer_finder)))
    println("  RULES\ttop=", length(get_rules(ctx, :top)))
    for r in reverse(get_rules(ctx, :top))
        print_rule("built", r::Rule, ctx)
    end
end

# -------------------------------------- probe --------------------------------------

function probe(i, m, t, seed, n, temp, rounds)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp, "\t",
            rounds)
    foreach(reset!, net.nodes)
    strings = [make_workspace_string(net, :initial, i),
               make_workspace_string(net, :modified, m),
               make_workspace_string(net, :target, t)]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    for s in strings, o in objects(s), d in o.descriptions
        set_activation!(d.descriptor, MAX_ACTIVATION)
    end
    for nd in (net[:plato_object_category], net[:plato_letter_category],
               net[:plato_string_position_category], net[:plato_successor],
               net[:plato_predecessor], net[:plato_sameness], net[:plato_bond_facet],
               net[:plato_bond_category], net[:plato_group_category],
               net[:plato_direction_category], net[:plato_left], net[:plato_right],
               net[:plato_samegrp], net[:plato_succgrp], net[:plato_predgrp],
               net[:plato_alphabetic_position_category], net[:plato_length])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                     strings[1], strings[2], strings[3], temp, 0)
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    empty!(SEEN)
    seed_rack!(ctx)
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        if c > 0 && c % UPDATE_CYCLE_LENGTH == 0
            seed_rack!(ctx)
        end
        ctx.codelet_count = c
        run_codelet!(ctx, choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature))
        update_workspace_values!(ctx)
        c += 1
    end
    check_if_rules_possible!(ctx)
    println("POSSIBLE\t", slist(get_possible_rule_types(ctx)))
    println("BRIDGES\ttop=", length(get_bridges(ctx, :top)), "\tdescribable=",
            count(b -> rule_describable_bridge(b, net), get_bridges(ctx, :top)))
    for k in 1:rounds
        drive_pipeline(k, ctx)
    end
end

probe("abc", "abd", "ijk", 201, 400, 40, 20)
probe("abc", "abd", "ijk", 202, 700, 20, 20)
probe("abc", "cba", "pqrs", 203, 900, 30, 20)
probe("aabc", "aabd", "ijkk", 204, 700, 30, 20)
probe("mrrjjj", "mrrkkk", "xyz", 205, 900, 30, 20)
probe("aabb", "bbaa", "ijkk", 206, 1200, 30, 20)
probe("abcd", "abdc", "xyz", 207, 1200, 25, 20)
probe("eqe", "qqq", "abc", 208, 700, 50, 20)
