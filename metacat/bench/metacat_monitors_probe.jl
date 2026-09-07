# Julia counterpart of metacat/bench/metacat_monitors_probe.ss: trace.ss slice
# (D), the monitors, and the first whole-trace comparison.
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

# --- the whole trace, in order ----------------------------------------------

function dump_trace(tag, tr::TemporalTrace, ctx)
    events = reverse(get_all_events(tr))
    println("TRACE\t", tag, "\t", length(events), "\t",
            get_num_of_events(tr, :concept_activation), "\t",
            get_num_of_events(tr, :concept_mapping), "\t",
            get_num_of_events(tr, :group), "\t", get_num_of_events(tr, :rule))
    for e in events
        println("EV\t", tag, "\t", get_event_number(e), "\t",
                hyphen(get_event_type(e)), "\t", event_print_name(e), "\t",
                get_time(e), "\t", get_temperature(e), "\t", get_event_strength(e))
    end
    for type in (:concept_activation, :concept_mapping, :group, :rule, :workspace)
        last = get_last_event(tr, type)
        println("LAST\t", tag, "\t", hyphen(type), "\t",
                last === nothing ? "-" : string(get_event_number(last)), "\t",
                last === nothing ? "-" : event_print_name(last))
    end
    return
end

# --- the importance functions, over a fixed spread --------------------------

function dump_importance(ctx, strings)
    for nd in (net[:plato_letter_category], net[:plato_successor], net[:plato_opposite],
               net[:plato_samegrp], net[:plato_length], net[:plato_identity],
               net[:plato_a], net[:plato_right], net[:plato_whole])
        for (prev, new) in ((0, 100), (0, 50), (40, 100), (100, 0), (60, 61),
                            (0, 86), (0, 90))
            imp = concept_activation_importance(nd, prev, new)
            println("CAIMP\t", sn(nd), "\t", prev, "\t", new, "\t", imp, "\t",
                    yn(imp >= CONCEPT_ACTIVATION_IMPORTANCE_THRESHOLD))
        end
    end
    for s in strings, g in reverse(s.groups)
        for f in (false, true)
            imp = group_importance(g::Group, f, net)
            println("GIMP\t", object_tag(g), "\t", yn(f), "\t", imp, "\t",
                    yn(imp >= GROUP_IMPORTANCE_THRESHOLD))
        end
    end
    for bt in (:vertical, :top), b in reverse(get_bridges(ctx, bt))
        for cm in b.all_concept_mappings
            imp = concept_mapping_importance(cm, b, ctx)
            println("CMIMP\t", bt, "\t", object_tag(b.object1), "\t",
                    cm_print_name(cm, net), "\t", yn(is_slippage(cm)), "\t", imp, "\t",
                    yn(imp >= CONCEPT_MAPPING_IMPORTANCE_THRESHOLD))
        end
    end
    for rt in (:top, :bottom), r in get_rules(ctx, rt)
        imp = rule_importance(r, ctx)
        println("RIMP\t", rt, "\t", r.uniformity, "\t", get_relative_quality(r, ctx),
                "\t", imp, "\t", yn(imp >= RULE_IMPORTANCE_THRESHOLD))
    end
    return
end

# --- workspace driver -------------------------------------------------------

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

"""Shared setup: a fresh workspace with every descriptor and every category
fully awake, and a trace ATTACHED, which is what turns the monitors on."""
function setup(i, m, t, temp, extra_nodes)
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
    for nd in extra_nodes
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                     strings[1], strings[2], strings[3], temp, 0)
    tr = make_temporal_trace()
    ctx.trace = tr
    return ctx, tr, strings
end

const RUN_NODES = () -> (net[:plato_object_category], net[:plato_letter_category],
                         net[:plato_string_position_category], net[:plato_successor],
                         net[:plato_predecessor], net[:plato_sameness],
                         net[:plato_bond_facet], net[:plato_bond_category],
                         net[:plato_group_category], net[:plato_direction_category],
                         net[:plato_left], net[:plato_right], net[:plato_samegrp],
                         net[:plato_succgrp], net[:plato_predgrp],
                         net[:plato_alphabetic_position_category], net[:plato_length])

# --- a deterministic phase that forces the concept-mapping monitor ----------

function build_chain_and_group!(s::WorkspaceString, ctx::MetacatCtx)
    n = string_length(s)
    bonds = Any[]
    for p in 1:(n - 1)
        o1 = s.letters[p]; o2 = s.letters[p + 1]
        d1 = get_descriptor_for(o1, net[:plato_letter_category])::Node
        d2 = get_descriptor_for(o2, net[:plato_letter_category])::Node
        cat = get_bond_category_between(d1, d2, net)
        cat === nothing && continue
        b = make_bond(net, o1, o2, cat::Node, net[:plato_letter_category], d1, d2)
        build_bond!(b, net)
        push!(bonds, b)
    end
    (isempty(bonds) || length(bonds) != n - 1) && return
    cat = bonds[1].bond_category
    dir = bonds[1].direction
    gcat = get_related_node(cat, net[:plato_group_category], net[:plato_identity])::Node
    objs = WSObject[bonds[1].left_object]
    for b in bonds
        push!(objs, b.right_object)
    end
    build_group!(make_group(net, s, gcat, net[:plato_letter_category], dir,
                            objs[1], objs[end], objs, bonds), net, ctx, false)
    return
end

function forced_probe(i, m, t, seed, temp)
    println("FORCED\t", i, "\t", m, "\t", t, "\t", seed, "\t", temp)
    ctx, tr, strings = setup(i, m, t, temp,
        (net[:plato_object_category], net[:plato_letter_category],
         net[:plato_string_position_category], net[:plato_successor],
         net[:plato_predecessor], net[:plato_sameness], net[:plato_group_category],
         net[:plato_direction_category], net[:plato_length],
         net[:plato_alphabetic_position_category], net[:plato_bond_category],
         net[:plato_bond_facet], net[:plato_left], net[:plato_right]))
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    for s in strings
        build_chain_and_group!(s, ctx)
    end
    update_workspace_values!(ctx)
    dump_trace("forced-groups", tr, ctx)
    g1 = isempty(ctx.initial_string.groups) ? nothing : ctx.initial_string.groups[1]
    g2 = isempty(ctx.target_string.groups) ? nothing : ctx.target_string.groups[1]
    if g1 === nothing || g2 === nothing
        println("NOSPANNING")
        return
    end
    cms = all_possible_bridge_cms(:vertical, g1, g1.descriptions, g2, g2.descriptions, net)
    println("FCMS\t", object_tag(g1), "\t", object_tag(g2), "\t",
            join_or_dash([cm_print_name(cm, net) for cm in cms]))
    if isempty(cms)
        println("NOCMS")
        return
    end
    b = make_bridge(:vertical, g1, g2, cms, net, ctx.codelet_count)
    println("FSPAN\t", yn(b.spanning_bridge), "\t", yn(b.group_spanning_bridge))
    for cm in b.all_concept_mappings
        imp = concept_mapping_importance(cm, b, ctx)
        println("FIMP\t", cm_print_name(cm, net), "\t", yn(is_slippage(cm)), "\t", imp,
                "\t", yn(imp >= CONCEPT_MAPPING_IMPORTANCE_THRESHOLD))
    end
    build_bridge!(b, ctx)
    dump_trace("forced-bridge", tr, ctx)
    return
end

# --- probe -------------------------------------------------------------------

function probe(i, m, t, seed, n, temp, rounds)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp)
    ctx, tr, strings = setup(i, m, t, temp, RUN_NODES())
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    empty!(SEEN)
    seed_rack!(ctx)
    # The real run loop updates slipnet activations every cycle, and those
    # updates are monitored, so the probe does it too.
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        if c > 0 && c % UPDATE_CYCLE_LENGTH == 0
            seed_rack!(ctx)
            update_slipnet_activations!(net, ctx.rng, ctx.themespace, ctx)
        end
        ctx.codelet_count = c
        run_codelet!(ctx, choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature))
        update_workspace_values!(ctx)
        c += 1
    end
    check_if_rules_possible!(ctx)
    dump_trace("run", tr, ctx)
    build_a_top_rule(ctx, rounds)
    dump_trace("rules", tr, ctx)
    dump_importance(ctx, strings)
    return
end

# abc :: kji and abc :: cba both make a whole-string group on each side running
# in OPPOSITE directions, so the vertical bridge between them spans and carries
# a slippage worth 75-81, over the threshold of 65.
probe("abc", "abd", "kji", 706, 2500, 30, 40)
probe("abc", "abd", "cba", 707, 2500, 30, 40)
probe("abc", "abd", "ijk", 701, 1200, 40, 40)
probe("abc", "abd", "mrrjjj", 702, 1500, 30, 40)
probe("abc", "cba", "pqrs", 703, 1500, 30, 40)
probe("mrrjjj", "mrrkkk", "xyz", 704, 1500, 30, 40)
probe("aabc", "aabd", "ijkk", 705, 1500, 35, 40)

forced_probe("abc", "abd", "kji", 801, 40)
forced_probe("abc", "abd", "cba", 802, 40)
forced_probe("abc", "abd", "ijk", 803, 40)
