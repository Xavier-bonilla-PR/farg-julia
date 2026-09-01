# Julia counterpart of bench/metacat_groupcodelets_probe.ss: the group codelet
# pipeline driven through the real coderack.
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
include("../julia/src/metacat/codelets_descriptions.jl")
include("../julia/src/metacat/codelets_groups.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
net = build_slipnet()

function post_scouts!(ctx, strings)
    net = ctx.net
    for _ in 1:4
        for name in (:bottom_up_bond_scout, :group_scout_whole_string,
                     :bottom_up_bridge_scout)
            post!(ctx.coderack, make_codelet(CODELET_TYPES[name], VERY_LOW_URGENCY),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
        end
    end
    # top-down group scouts: both kinds, over both kinds of scope
    for group_category in (net[:plato_succgrp], net[:plato_predgrp], net[:plato_samegrp])
        for scope in (strings[1], ctx)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_group_scout_category], LOW_URGENCY,
                               Any[group_category, scope]),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
        end
    end
    for direction in (net[:plato_left], net[:plato_right])
        for scope in (strings[3], ctx)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_group_scout_direction], LOW_URGENCY,
                               Any[direction, scope]),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
        end
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
               net[:plato_direction_category], net[:plato_length],
               net[:plato_alphabetic_position_category],
               net[:plato_samegrp], net[:plato_succgrp], net[:plato_predgrp],
               net[:plato_left], net[:plato_right])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), strings[1], strings[2], strings[3],
                     temp, 0)
    TEMPERATURE[] = temp
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    # The scouts here never post more scouts, so the rack would drain and the
    # run would stop long before N codelets. Re-seeding whenever it empties
    # keeps groups coming, which is what the builder needs to have anything to
    # fight, consolidate or find already present.
    post_scouts!(ctx, strings)
    c = 0
    while c < n
        coderack_empty(ctx.coderack) && post_scouts!(ctx, strings)
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        println("RUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
                sround(codelet.relative_urgency), "\t", ctx.coderack.current_num)
        run_codelet!(ctx, codelet)
        update_workspace_values!(ctx)
        c += 1
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
                    nm(gg.group_category), "\t", nm(gg.direction), "\t",
                    nm(gg.group_bond_facet), "\t", gg.group_length, "\t",
                    gg.strength, "\t", gg.proposal_level)
            for d in all_descriptions(gg)
                println("GROUPDESC\t", s.string_type, "\t", ascii_name(gg), "\t",
                        nm(d.description_type), "\t", nm(d.descriptor))
            end
        end
        for o in objects(s)
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    o.intra_string_unhappiness, "\t", o.intra_string_salience, "\t",
                    o.average_salience, "\t", o.relative_importance)
        end
    end
    for bridge_type in (:top, :vertical)
        for b in reverse(bridge_list(ctx, bridge_type))
            bb = b::Bridge
            println("BRIDGE\t", bridge_type, "\t", ascii_name(bb.object1), "\t",
                    ascii_name(bb.object2), "\t", yn(bb.spanning_bridge), "\t",
                    bb.strength)
        end
    end
    for node in net.nodes
        node.activation == 0 || println("ACT\t", nm(node), "\t", node.activation)
    end
end

probe("abc", "abd", "ijk", 909, 150, 50)
probe("abc", "abd", "mrrjjj", 313, 200, 40)
probe("aabbcc", "aabbdd", "xxyyzz", 555, 250, 60)
probe("abcde", "abcdf", "pqrst", 777, 250, 70)
# reversed strings: a group's direction ends up contradicting a bridge's
# string-position mapping, which is the group-versus-bridge fight
probe("abc", "abd", "cba", 3, 300, 50)
probe("abcd", "abce", "dcba", 3, 300, 50)
# runs of three identical letters: a sameness group can end up containing
# another one, which is the builder's letter-consolidation case
probe("aaabbb", "aaabbc", "jjjkkk", 1, 300, 55)
