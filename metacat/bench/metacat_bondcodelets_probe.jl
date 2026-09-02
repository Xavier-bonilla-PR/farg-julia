# Julia counterpart of metacat/bench/metacat_bondcodelets_probe.ss: the bond
# codelet pipeline driven through the real coderack.
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
include("../julia/src/context.jl")
include("../julia/src/codelets_bonds.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
net = build_slipnet()

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
               net[:plato_bond_category], net[:plato_length])
        set_activation!(nd, MAX_ACTIVATION)
    end
    rng = PyRandom(0)   # reseeded below, after the workspace values pass
    ctx = MetacatCtx(net, rng, Coderack(), strings[1], strings[2], strings[3], temp, 0)
    TEMPERATURE[] = temp
    update_workspace_values!(strings)
    ctx.rng = PyRandom(seed)
    for _ in 1:20
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_bond_scout], VERY_LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
    end
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        println("RUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
                sround(codelet.relative_urgency), "\t", ctx.coderack.current_num)
        run_codelet!(ctx, codelet)
        update_workspace_values!(strings, ctx.rng, net)
        c += 1
    end
    for s in strings
        for b in reverse(s.bonds)
            bb = b::Bond
            println("BOND\t", s.string_type, "\t", ascii_name(bb.left_object), "\t",
                    ascii_name(bb.right_object), "\t", nm(bb.bond_category), "\t",
                    nm(bb.direction), "\t", nm(bb.bond_facet), "\t", bb.strength)
        end
        for o in objects(s)
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    o.intra_string_unhappiness, "\t", o.intra_string_salience, "\t",
                    o.relative_importance)
        end
    end
    for node in net.nodes
        node.activation == 0 || println("ACT\t", nm(node), "\t", node.activation)
    end
end

probe("abc", "abd", "ijk", 1234, 60, 50)
probe("abc", "abd", "mrrjjj", 5678, 80, 40)
probe("abcde", "abcdf", "pqrst", 9012, 100, 70)
