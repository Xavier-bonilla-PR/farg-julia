# Julia counterpart of bench/metacat_groupcodelets_probe.ss.
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
include("../julia/src/metacat/themes.jl")
include("../julia/src/metacat/coderack.jl")
include("../julia/src/metacat/context.jl")
include("../julia/src/metacat/codelets_bonds.jl")
include("../julia/src/metacat/codelets_descriptions.jl")
include("../julia/src/metacat/codelets_groups.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
net = build_slipnet()

count_proposed_groups(strings) = sum(length(s.proposed_groups) for s in strings)

function probe(i, m, t, seed, n, temp, mode)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp, "\t", mode)
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
               net[:plato_bond_category], net[:plato_length], net[:plato_group_category],
               net[:plato_direction_category], net[:plato_samegrp], net[:plato_succgrp],
               net[:plato_predgrp], net[:plato_left], net[:plato_right])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), strings[1], strings[2], strings[3],
                     temp, 0)
    TEMPERATURE[] = temp
    update_workspace_values!(strings)
    ctx.rng = PyRandom(seed)
    # Phase 1: bonds only. Group scouts need runs of bonds to find.
    for _ in 1:25
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_bond_scout], VERY_LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
    end
    c = 0
    while c < 120 && !coderack_empty(ctx.coderack)
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        println("WARM\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
                ctx.coderack.current_num)
        run_codelet!(ctx, codelet)
        update_workspace_values!(strings, ctx.rng, net)
        c += 1
    end
    # Phase 2: group codelets over the bonds that exist.
    for _ in 1:20
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_bond_scout], VERY_LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:group_scout_whole_string], LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_description_scout], VERY_LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        if mode === :category
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_group_scout_category], LOW_URGENCY,
                               Any[net[:plato_succgrp], nothing]),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_group_scout_category], LOW_URGENCY,
                               Any[net[:plato_samegrp], strings[1]]),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
        elseif mode === :direction
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_group_scout_direction], LOW_URGENCY,
                               Any[net[:plato_right], nothing]),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_group_scout_direction], LOW_URGENCY,
                               Any[net[:plato_left], strings[3]]),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
        end
    end
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        println("RUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
                sround(codelet.relative_urgency), "\t", ctx.coderack.current_num, "\t",
                count_proposed_groups(strings))
        run_codelet!(ctx, codelet)
        update_workspace_values!(strings, ctx.rng, net)
        c += 1
    end
    for s in strings
        for gg in reverse(s.groups)
            g = gg::Group
            println("GROUP\t", s.string_type, "\t", ascii_name(g), "\t",
                    nm(g.group_category), "\t", nm(g.direction), "\t",
                    nm(g.group_bond_facet), "\t", g.group_length, "\t",
                    get_letter_span(g), "\t", g.strength, "\t", g.proposal_level)
            for (k, d) in enumerate(all_descriptions(g))
                println("GDESC\t", s.string_type, "\t", ascii_name(g), "\t", k - 1, "\t",
                        d.description_type.short_name, ":", d.descriptor.short_name)
            end
            for (k, b) in enumerate(g.constituent_bonds)
                println("GBOND\t", s.string_type, "\t", ascii_name(g), "\t", k - 1, "\t",
                        ascii_name((b::Bond).left_object), ">",
                        ascii_name((b::Bond).right_object))
            end
        end
        for b in reverse(s.bonds)
            bb = b::Bond
            println("BOND\t", s.string_type, "\t", ascii_name(bb.left_object), "\t",
                    ascii_name(bb.right_object), "\t", nm(bb.bond_category), "\t",
                    nm(bb.direction), "\t", nm(bb.bond_facet), "\t", bb.strength)
        end
        for o in objects(s)
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    o.intra_string_unhappiness, "\t", o.intra_string_salience, "\t",
                    o.relative_importance, "\t",
                    o.enclosing_group === nothing ? "-" :
                    ascii_name(o.enclosing_group::WSObject))
        end
    end
    println("CODERACK\t", ctx.coderack.current_num, "\t", count_proposed_groups(strings))
    for node in net.nodes
        node.activation == 0 || println("ACT\t", nm(node), "\t", node.activation)
    end
end

probe("abc", "abd", "ijk", 4242, 200, 70, :none)
probe("abc", "abd", "mrrjjj", 1357, 250, 80, :category)
probe("abcde", "abcdf", "pqrst", 2468, 300, 60, :direction)
probe("iijjkk", "iijjll", "mmnnoo", 8642, 400, 90, :category)
probe("aabbcc", "aabbdd", "xxyyzz", 9753, 400, 80, :direction)
probe("mrrjjj", "mrrkkk", "xppqqq", 1111, 400, 85, :category)
