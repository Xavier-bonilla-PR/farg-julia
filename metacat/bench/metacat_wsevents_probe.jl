# Julia counterpart of metacat/bench/metacat_wsevents_probe.ss: trace.ss slice
# (C) part 1, the four workspace and slipnet event types.
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
include("../julia/src/answers.jl")
include("../julia/src/trace.jl")

net = build_slipnet()

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
hyphen(s::Symbol) = replace(String(s), "_" => "-")

object_tag(o) = o isa WorkspaceString ? string("string:", o.string_type) : ascii_name(o)
cm_tag(cm::ConceptMapping) = cm_print_name(cm, net)
bridge_tag(b::Bridge) = string(object_tag(b.object1), ">", object_tag(b.object2))
entry_tag(e) = string(sn(e[1]), "/", nm(e[2]))

count_of(T, structures) = count(s -> s isa T, structures)

structure_summary(structures) =
    string("b", count_of(Bond, structures), "/g", count_of(Group, structures),
           "/x", count_of(Bridge, structures), "/r", count_of(Rule, structures),
           "/n", length(structures))

concept_pattern_tag(pattern) =
    join_or_dash([string(sn(e[1]), ":", e[2]) for e in pattern[2:end]])

theme_pattern_tag(pattern) =
    string(hyphen(pattern[1]), "[",
           join_or_dash([entry_tag(e) for e in pattern[2:end]]), "]")

# --- the generic half, dumped for every event --------------------------------

function dump_generic(tag, e, ctx)
    println("GEN\t", tag, "\t", hyphen(get_event_type(e)), "\t", get_time(e), "\t",
            get_temperature(e), "\t", structure_summary(get_structures(e)), "\t",
            length(get_active_theme_types(e)), "\t",
            length(get_complete_themespace_patterns(e)), "\t",
            length(get_dominant_themespace_patterns(e)), "\t", get_age(e, ctx))
    println("GENT\t", tag, "\t", yn(event_type_is(e, :any)), "\t",
            yn(event_type_is(e, :workspace)), "\t",
            yn(event_type_is(e, :concept_activation)), "\t",
            yn(event_type_is(e, :concept_mapping)), "\t",
            yn(event_type_is(e, :group)), "\t", yn(event_type_is(e, :rule)))
    for tt in (:top_bridge, :vertical_bridge)
        cp = get_complete_themespace_pattern(e, tt)
        dp = get_dominant_themespace_pattern(e, tt)
        println("GENP\t", tag, "\t", hyphen(tt), "\t",
                cp === nothing ? "-" : length(cp[2:end]), "\t",
                dp === nothing ? "-" : length(dp[2:end]))
    end
    return
end

# --- the four event types ----------------------------------------------------

function dump_concept_activation_event(node::Node, ctx)
    e = make_concept_activation_event(node, ctx)
    tag = string("CA:", sn(node))
    println("CAE\t", tag, "\t", event_print_name(e), "\t", get_event_strength(e),
            "\t", full_slipnode_name(node, net))
    println("CAEP\t", tag, "\t", concept_pattern_tag(get_concept_pattern(e)))
    println("CAEQ\t", tag, "\t", yn(events_equal(e, e)), "\t",
            yn(get_slipnode(e) === node))
    dump_generic(tag, e, ctx)
    return
end

function dump_concept_mapping_event(cm::ConceptMapping, bridge::Bridge, ctx)
    e = make_concept_mapping_event(cm, bridge, ctx)
    tag = string("CM:", bridge.bridge_type, ":", object_tag(bridge.object1), ":",
                 cm_tag(cm))
    println("CME\t", tag, "\t", event_print_name(e), "\t",
            yn(is_event_slippage(e)), "\t", get_bridge_type(e), "\t",
            get_event_strength(e), "\t", sn(get_cm_type(e)), "\t",
            yn(relevant_for_answer_description(e, ctx)))
    println("CMET\t", tag, "\t", theme_pattern_tag(get_theme_pattern(e)))
    println("CMEP\t", tag, "\t", concept_pattern_tag(get_concept_pattern(e)))
    println("CMEQ\t", tag, "\t", yn(events_equal(e, e, net)), "\t",
            yn(is_cm_type(e, cm_type(cm))), "\t", yn(event_currently_present(e, ctx)))
    dump_generic(tag, e, ctx)
    return
end

function dump_group_event(group::Group, flipped::Bool, ctx)
    e = make_group_event(group, flipped, ctx)
    tag = string("GR:", object_tag(group), ":", yn(flipped))
    println("GRE\t", tag, "\t", event_print_name(e), "\t", yn(is_event_flipped(e)),
            "\t", sn(get_group_category(e)), "\t", nm(get_event_direction(e)), "\t",
            get_event_strength(e), "\t", yn(is_event_spanning(e)), "\t",
            get_event_string_type(e))
    unflipped = unflipped_group_name(group, net)
    println("GREN\t", tag, "\t", group_event_pexp_text_string(group, net), "\t",
            unflipped === nothing ? "-" : unflipped, "\t",
            full_workspace_object_name(group, net))
    println("GRES\t", tag, "\t", yn(event_spans(e, :initial)), "\t",
            yn(event_spans(e, :modified)), "\t", yn(event_spans(e, :target)), "\t",
            yn(event_currently_present(e)), "\t",
            yn(relevant_for_answer_description(e)))
    println("GREP\t", tag, "\t", concept_pattern_tag(get_concept_pattern(e)))
    println("GREQ\t", tag, "\t", yn(events_equal(e, e)))
    dump_generic(tag, e, ctx)
    return
end

function dump_rule_event(rule::Rule, ctx)
    e = make_rule_event(rule, ctx)
    tag = string("RU:", rule.rule_type)
    println("RUE\t", tag, "\t", event_print_name(e), "\t", get_rule_type(e), "\t",
            get_event_relative_quality(e), "\t", get_event_strength(e))
    println("RUEB\t", tag, "\t",
            join_or_dash([bridge_tag(b) for b in get_supporting_bridges(e)]))
    println("RUER\t", tag, "\t",
            join_or_dash([object_tag(o) for o in get_reference_objects(e)]))
    println("RUEP\t", tag, "\t", concept_pattern_tag(get_concept_pattern(e)))
    println("RUEQ\t", tag, "\t", yn(events_equal(e, e, net)))
    dump_generic(tag, e, ctx)
    return
end

# --- workspace driver (as in the ruletranslate probe) ------------------------

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

const SEEN = Codelet[]

function new_codelets_of_type(ctx::MetacatCtx, type_name::Symbol)
    found = Codelet[c for c in ctx.coderack.codelet_list
                    if c.codelet_type.name === type_name && !any(x -> x === c, SEEN)]
    prepend!(SEEN, found)
    return found
end

function build_a_top_rule(ctx::MetacatCtx, rounds)
    k = 1
    while k <= rounds && isempty(get_rules(ctx, :top))
        run_codelet!(ctx, make_codelet(CODELET_TYPES[:rule_scout], MEDIUM_URGENCY))
        for ec in new_codelets_of_type(ctx, :rule_evaluator)
            run_codelet!(ctx, ec)
        end
        for bc in new_codelets_of_type(ctx, :rule_builder)
            run_codelet!(ctx, bc)
        end
        k += 1
    end
    rules = get_rules(ctx, :top)
    return isempty(rules) ? nothing : rules[1]
end

# --- probe -------------------------------------------------------------------

function probe(i, m, t, seed, n, temp, rounds)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp)
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
    # concept-activation events: one per concept, deep and shallow
    for nd in (net[:plato_letter_category], net[:plato_successor],
               net[:plato_opposite], net[:plato_samegrp], net[:plato_length],
               net[:plato_identity], net[:plato_string_position_category],
               net[:plato_a], net[:plato_right],
               net[:plato_alphabetic_position_category], net[:plato_bond_facet],
               net[:plato_whole], net[:plato_predgrp])
        dump_concept_activation_event(nd, ctx)
    end
    # concept-mapping events: every CM of every built bridge
    for bt in (:vertical, :top)
        for b in reverse(get_bridges(ctx, bt))
            for cm in b.all_concept_mappings
                dump_concept_mapping_event(cm, b, ctx)
            end
        end
    end
    # group events, built and flipped
    for s in strings
        for g in reverse(s.groups)
            dump_group_event(g::Group, false, ctx)
            dump_group_event(g::Group, true, ctx)
        end
    end
    # rule event
    rule = build_a_top_rule(ctx, rounds)
    if rule === nothing
        println("NORULE")
    else
        dump_rule_event(rule, ctx)
    end
    # name helpers over every slipnode and every object
    for nd in net.nodes
        println("FSN\t", sn(nd), "\t", full_slipnode_name(nd, net))
    end
    for s in strings, o in objects(s)
        full = full_workspace_object_name(o, net)
        println("SOP\t", object_tag(o), "\t", snag_object_phrase(o), "\t",
                full === nothing ? "-" : full)
    end
    for s in strings
        println("SOPS\t", s.string_type, "\t", snag_object_phrase(s))
    end
    return
end

probe("abc", "abd", "ijk", 601, 2000, 40, 40)
probe("abc", "abd", "mrrjjj", 602, 3000, 30, 40)
probe("abc", "cba", "pqrs", 603, 3000, 30, 40)
probe("mrrjjj", "mrrkkk", "xyz", 604, 3000, 30, 40)
