# Julia counterpart of bench/metacat_desccodelets_probe.ss: the description
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
include("../julia/src/metacat/codelets_descriptions.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
net = build_slipnet()

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

function probe(i, m, t, seed, n, temp, make_groups)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp, "\t",
            yn(make_groups))
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
               net[:plato_alphabetic_position_category])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), strings[1], strings[2], strings[3],
                     temp, 0)
    TEMPERATURE[] = temp
    update_workspace_values!(ctx)
    if make_groups
        build_chain_and_group!(strings[1])
        build_chain_and_group!(strings[3])
    end
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    for _ in 1:8
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_description_scout], VERY_LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
    end
    # top-down scouts: every description type that has descriptor predicates,
    # against both kinds of scope
    for description_type in (net[:plato_length], net[:plato_string_position_category],
                             net[:plato_object_category],
                             net[:plato_alphabetic_position_category])
        for _ in 1:5, scope in (strings[1], ctx)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_description_scout], LOW_URGENCY,
                               Any[description_type, scope]),
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
    for s in strings
        for o in objects(s)
            for d in all_descriptions(o)
                println("DESC\t", s.string_type, "\t", ascii_name(o), "\t",
                        nm(d.description_type), "\t", nm(d.descriptor), "\t",
                        d.strength, "\t", d.proposal_level)
            end
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    swrite(o.raw_importance), "\t", o.relative_importance, "\t",
                    o.average_salience, "\t", o.intra_string_salience)
        end
    end
    for node in net.nodes
        node.activation == 0 || println("ACT\t", nm(node), "\t", node.activation)
    end
end

probe("abc", "abd", "ijk", 4242, 80, 50, false)
probe("azb", "azc", "xyz", 1717, 100, 40, false)
# single-letter strings: the only way plato-single can describe anything
probe("a", "b", "c", 6161, 60, 50, false)
# grouped strings of two, three, four and five, so that the Length descriptors
# plato-two .. plato-five each have something they can describe. plato-one
# needs a singleton group, which only the group codelets can make.
probe("ab", "ac", "yz", 12, 140, 50, true)
probe("abc", "abd", "xyz", 5150, 180, 50, true)
probe("abcd", "abce", "wxyz", 7, 220, 60, true)
probe("abcde", "abcdf", "pqrst", 3030, 240, 70, true)
