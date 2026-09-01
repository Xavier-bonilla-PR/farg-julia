# Julia counterpart of bench/metacat_bridgecodelets_probe.ss: the bridge
# codelet pipeline driven through the real coderack.
include("../julia/src/pyrandom.jl")
include("../julia/src/metacat/schemenum.jl")
include("../julia/src/metacat/utilities.jl")
include("../julia/src/metacat/slipnet.jl")
include("../julia/src/metacat/workspace.jl")
include("../julia/src/metacat/concept_mappings.jl")
include("../julia/src/metacat/images.jl")
include("../julia/src/metacat/bonds.jl")
include("../julia/src/metacat/groups.jl")
include("../julia/src/metacat/bridges.jl")
include("../julia/src/metacat/coderack.jl")
include("../julia/src/metacat/context.jl")
include("../julia/src/metacat/codelets_bonds.jl")
include("../julia/src/metacat/codelets_bridges.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
net = build_slipnet()

# With `reversed` the bonds are scanned right to left, which is what makes a
# group whose direction is `left`: the only way to get a pair of spanning
# groups related by Opposite on BOTH group category and direction, and so the
# only way a bridge between them asks to flip one.
function build_chain_and_group!(s::WorkspaceString, reversed::Bool)
    n = string_length(s)
    bonds = Any[]
    for p in 1:(n - 1)
        oa = s.letters[p]; ob = s.letters[p + 1]
        o1 = reversed ? ob : oa
        o2 = reversed ? oa : ob
        d1 = get_descriptor_for(o1, net[:plato_letter_category])::Node
        d2 = get_descriptor_for(o2, net[:plato_letter_category])::Node
        cat = get_bond_category_between(d1, d2, net)
        cat === nothing && continue
        b = make_bond(net, o1, o2, cat::Node, net[:plato_letter_category], d1, d2)
        build_bond!(b)
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

function dump_bridges(ctx, bridge_type::Symbol)
    for b in reverse(bridge_list(ctx, bridge_type))
        bb = b::Bridge
        println("BRIDGE\t", bridge_type, "\t", bb.orientation, "\t",
                ascii_name(bb.object1), "\t", ascii_name(bb.object2), "\t",
                yn(bb.spanning_bridge), "\t",
                yn(bb.flipped_group1), "\t", yn(bb.flipped_group2), "\t",
                bb.strength, "\t", bb.proposal_level)
        for cm in bb.all_concept_mappings
            println("BRIDGECM\t", bridge_type, "\t", cm_print_name(cm, net), "\t",
                    nm(cm.label), "\t", yn(is_slippage(cm)), "\t", cm_strength(cm))
        end
        for ss in bb.symmetric_slippages
            println("BRIDGESS\t", bridge_type, "\t", cm_print_name(ss, net))
        end
    end
end

function probe(i, m, t, seed, n, temp, make_groups)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp, "\t",
            make_groups)
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
               net[:plato_direction_category], net[:plato_length])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), strings[1], strings[2], strings[3],
                     temp, 0)
    TEMPERATURE[] = temp
    update_workspace_values!(ctx)
    if make_groups !== :none
        build_chain_and_group!(strings[1], false)
        build_chain_and_group!(strings[3], make_groups === :flip)
    end
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    # The flip problems leave the bond scouts out: their target group is built
    # from right-to-left bonds, and a bond scout proposing the left-to-right
    # reading would break it up before any bridge got to ask for a flip.
    scouts = make_groups === :flip ?
             (:bottom_up_bridge_scout, :important_object_bridge_scout) :
             (:bottom_up_bond_scout, :bottom_up_bridge_scout,
              :important_object_bridge_scout)
    for _ in 1:(make_groups === :flip ? 20 : 10)
        for name in scouts
            post!(ctx.coderack, make_codelet(CODELET_TYPES[name], VERY_LOW_URGENCY),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
        end
    end
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        println("RUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
                sround(codelet.relative_urgency), "\t", ctx.coderack.current_num)
        run_codelet!(ctx, codelet)
        update_workspace_values!(ctx)
        c += 1
    end
    println("MAP\t", ctx.top_mapping_strength, "\t", ctx.vertical_mapping_strength)
    for bridge_type in (:top, :vertical)
        dump_bridges(ctx, bridge_type)
    end
    for s in strings
        for b in reverse(s.bonds)
            bb = b::Bond
            println("BOND\t", s.string_type, "\t", ascii_name(bb.left_object), "\t",
                    ascii_name(bb.right_object), "\t", nm(bb.bond_category), "\t",
                    nm(bb.direction), "\t", nm(bb.bond_facet), "\t", bb.strength)
        end
        for g in reverse(s.groups)
            gg = g::Group
            println("GROUP\t", s.string_type, "\t", ascii_name(gg), "\t",
                    nm(gg.group_category), "\t", nm(gg.direction), "\t", gg.strength)
        end
        for o in objects(s)
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    o.intra_string_unhappiness, "\t", o.intra_string_salience, "\t",
                    o.horizontal_inter_string_salience, "\t",
                    o.vertical_inter_string_salience, "\t",
                    o.average_unhappiness, "\t", o.relative_importance)
        end
    end
    for node in net.nodes
        node.activation == 0 || println("ACT\t", nm(node), "\t", node.activation)
    end
end

probe("abc", "abd", "ijk", 1234, 60, 50, :none)
probe("abc", "abd", "mrrjjj", 5678, 90, 40, :none)
probe("abcde", "abcdf", "pqrst", 9012, 120, 70, :none)
probe("abc", "abd", "cba", 3141, 120, 50, :plain)
probe("abc", "abd", "xyz", 2718, 120, 60, :plain)
probe("abc", "abd", "abc", 2, 200, 50, :flip)
probe("abcd", "abce", "abcd", 10, 200, 40, :flip)
