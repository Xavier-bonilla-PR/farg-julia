# Julia counterpart of metacat/bench/metacat_bridgecodelets_probe.ss: the bridge
# codelet pipeline driven through the real coderack, interleaved with the bond,
# group and description scouts so bridges have structures to span and to fight.
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

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
num(v) = (x = snorm(v); x isa Integer ? string(x) :
                        string(numerator(x), "/", denominator(x)))
net = build_slipnet()

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
        post(:important_object_bridge_scout, MEDIUM_URGENCY)
        post(:bottom_up_description_scout, VERY_LOW_URGENCY)
    end
    return ctx
end

function probe(i, m, t, seed, n, temp)
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
    seed_rack!(ctx)
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        if c > 0 && c % UPDATE_CYCLE_LENGTH == 0
            seed_rack!(ctx)
        end
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        print("RUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
              sround(codelet.relative_urgency), "\t", ctx.coderack.current_num)
        run_codelet!(ctx, codelet)
        println("\t", sum(length(s.bonds) for s in strings), "\t",
                sum(length(s.groups) for s in strings), "\t",
                length(get_all_bridges(ctx)), "\t",
                ctx.top_mapping_strength, "\t", ctx.vertical_mapping_strength, "\t",
                sum(o.average_salience for s in strings for o in objects(s)))
        update_workspace_values!(ctx)
        c += 1
    end
    for bridge_type in (:top, :vertical)
        for b in reverse(get_bridges(ctx, bridge_type))
            println("BRIDGE\t", bridge_type, "\t", ascii_name(b.object1), "\t",
                    ascii_name(b.object2), "\t", yn(b.spanning_bridge), "\t",
                    yn(b.flipped_group1), "\t", yn(b.flipped_group2), "\t",
                    get_letter_span(b), "\t", b.strength)
            println("BRSTR\t", bridge_type, "\t", ascii_name(b.object1), "\t",
                    ascii_name(b.object2), "\t", calculate_internal_strength(b, net), "\t",
                    calculate_external_strength(b, get_all_bridges(ctx), net), "\t",
                    yn(internally_coherent(b, net)), "\t",
                    length(get_relevant_distinguishing_cms(b, net)))
            for cm in b.all_concept_mappings
                println("BRCM\t", bridge_type, "\t", ascii_name(b.object1), "\t",
                        ascii_name(b.object2), "\t", cm_print_name(cm, net), "\t",
                        nm(cm.label), "\t", yn(is_slippage(cm)), "\t",
                        yn(any(x -> x === cm, b.concept_mappings)), "\t",
                        yn(cm_relevant(cm)), "\t", yn(cm_distinguishing(cm, net)))
            end
        end
    end
    for s in strings
        for b in reverse(s.bonds)
            bb = b::Bond
            println("BOND\t", s.string_type, "\t", ascii_name(bb.left_object), "\t",
                    ascii_name(bb.right_object), "\t", nm(bb.bond_category), "\t",
                    nm(bb.direction), "\t", bb.strength)
        end
        for g in reverse(s.groups)
            gg = g::Group
            println("GROUP\t", s.string_type, "\t", ascii_name(gg), "\t",
                    nm(gg.group_category), "\t", nm(gg.direction), "\t",
                    nm(gg.group_bond_facet), "\t", gg.strength)
        end
        for o in objects(s)
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    num(o.raw_importance), "\t", o.relative_importance, "\t",
                    o.horizontal_inter_string_unhappiness, "\t",
                    o.vertical_inter_string_unhappiness, "\t", o.average_salience, "\t",
                    "(", join([string(d.description_type.short_name, ":",
                                      d.descriptor.short_name)
                               for d in all_descriptions(o)], " "), ")")
        end
    end
    println("WS\t", ctx.average_intra_string_unhappiness, "\t", ctx.average_unhappiness,
            "\t", ctx.top_mapping_strength, "\t", ctx.vertical_mapping_strength, "\t",
            get_min_mapping_strength(ctx))
    for node in net.nodes
        node.activation == 0 || println("ACT\t", nm(node), "\t", node.activation)
    end
end

# The flip path needs whole-string groups on BOTH sides at the same moment,
# which random seeding reaches only by luck. This variant builds them directly —
# as metacat_bridges_probe.jl does — turns the target's group around, and
# proposes the flipped bridge outright, so make_flipped_version, the
# flipped-group fight and flip_group! are all exercised deterministically.
function build_chain_and_group!(s::WorkspaceString)
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
                            objs[1], objs[end], objs, bonds), net)
    return
end

get_spanning_group(s::WorkspaceString) =
    (i = findfirst(g -> spans_whole_string(g::Group), s.groups);
     i === nothing ? nothing : s.groups[i])

function flip_probe(i, m, t, seed, n, temp)
    println("FLIPPROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp)
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
    # Direction-Category is clamped but Group-Category deliberately is NOT:
    # reverse_direction_orientation requires every reversible concept mapping to
    # map by opposite, and a GroupCtgy:succgrp=>succgrp identity mapping would
    # veto it. With GroupCtgy inactive those descriptions are irrelevant, so the
    # scouts never build that mapping and the Direction mapping decides.
    for nd in (net[:plato_object_category], net[:plato_letter_category],
               net[:plato_string_position_category], net[:plato_successor],
               net[:plato_predecessor], net[:plato_sameness], net[:plato_bond_facet],
               net[:plato_direction_category], net[:plato_left], net[:plato_right],
               net[:plato_alphabetic_position_category], net[:plato_length])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                     strings[1], strings[2], strings[3], temp, 0)
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    for s in strings
        build_chain_and_group!(s)
    end
    # turn the target's spanning group around, so that it and the initial
    # string's group map by opposite direction — the configuration a flipped
    # bridge exists to express
    let g = get_spanning_group(strings[3])
        if g !== nothing
            fg = make_flipped_version(g::Group, net)
            break_group!(g::Group, net, ctx)
            for bond in (g::Group).constituent_bonds
                break_bond!(bond::Bond, net)
            end
            for bond in fg.constituent_bonds
                build_bond!(bond::Bond, net)
            end
            build_group!(fg, net, ctx)
        end
    end
    update_workspace_values!(ctx)
    let g1 = get_spanning_group(strings[1]), g2 = get_spanning_group(strings[3])
        if g1 !== nothing && g2 !== nothing
            pb = propose_bridge!(ctx, :vertical, g1::Group, false, g2::Group, true)
            println("FPROPOSE\t", ascii_name(pb.object1), "\t", ascii_name(pb.object2),
                    "\t", yn(pb.flipped_group2), "\t", length(pb.concept_mappings), "\t",
                    "(", join([cm_print_name(cm, net) for cm in pb.concept_mappings], " "),
                    ")")
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:bridge_evaluator], EXTREMELY_HIGH_URGENCY,
                               Any[pb]),
                  ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
        end
    end
    c = 0
    while c < n
        if c % 5 == 0
            for _ in 1:2
                post!(ctx.coderack,
                      make_codelet(CODELET_TYPES[:bottom_up_bridge_scout], MEDIUM_URGENCY),
                      ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
                post!(ctx.coderack,
                      make_codelet(CODELET_TYPES[:important_object_bridge_scout],
                                   MEDIUM_URGENCY),
                      ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
            end
        end
        ctx.codelet_count = c
        if !coderack_empty(ctx.coderack)
            codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
            print("FRUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
                  sround(codelet.relative_urgency), "\t", ctx.coderack.current_num)
            run_codelet!(ctx, codelet)
            println("\t", sum(length(s.groups) for s in strings), "\t",
                    length(get_all_bridges(ctx)), "\t",
                    sum(o.average_salience for s in strings for o in objects(s)))
        end
        update_workspace_values!(ctx)
        c += 1
    end
    for bridge_type in (:top, :vertical)
        for b in reverse(get_bridges(ctx, bridge_type))
            println("FBRIDGE\t", bridge_type, "\t", ascii_name(b.object1), "\t",
                    ascii_name(b.object2), "\t", yn(b.spanning_bridge), "\t",
                    yn(b.flipped_group1), "\t", yn(b.flipped_group2), "\t",
                    get_letter_span(b), "\t", b.strength)
        end
    end
    for s in strings
        for g in reverse(s.groups)
            gg = g::Group
            println("FGROUP\t", s.string_type, "\t", ascii_name(gg), "\t",
                    nm(gg.group_category), "\t", nm(gg.direction), "\t", gg.strength)
        end
        for b in reverse(s.bonds)
            bb = b::Bond
            println("FBOND\t", s.string_type, "\t", ascii_name(bb.left_object), "\t",
                    ascii_name(bb.right_object), "\t", nm(bb.bond_category), "\t",
                    nm(bb.direction))
        end
    end
end

probe("abc", "abd", "ijk", 4001, 400, 50)
probe("abc", "abd", "mrrjjj", 4002, 700, 40)
probe("abc", "cba", "pqrs", 4003, 700, 30)
probe("abcde", "abcdf", "pqrst", 4004, 700, 60)
# abc <-> cba is the case flipped bridges exist for: two whole-string groups
# that map by opposite direction, which is better said by reversing one group
# than by slipping right=>left. Opposite is deliberately NOT clamped active
# anywhere in this probe, since reverse_direction_orientation requires it.
probe("abc", "abd", "cba", 4005, 900, 30)
probe("abcd", "abcde", "dcba", 4006, 900, 20)

flip_probe("abc", "abd", "cba", 4101, 200, 30)
flip_probe("abcd", "abce", "dcba", 4102, 200, 20)
flip_probe("abc", "abd", "kji", 4103, 200, 40)
