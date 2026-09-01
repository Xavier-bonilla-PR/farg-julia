# Julia counterpart of bench/metacat_desccodelets_probe.ss: the description
# codelet pipeline through the real coderack, mixed with bond scouts.
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

nm(n) = n === nothing ? "-" : n.lowercase_name
net = build_slipnet()

"""Proposed-but-unbuilt bonds across the three strings — what codelet eviction
has to keep straight."""
proposed_bond_count(strings) =
    sum(ssum([length(v) for v in values(s.proposed_bonds)]) for s in strings)

function probe(i, m, t, seed, n, temp, top_down, nseed)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp, "\t",
            top_down ? "#t" : "#f", "\t", nseed)
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
               net[:plato_bond_category], net[:plato_length],
               net[:plato_alphabetic_position_category])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), strings[1], strings[2], strings[3],
                     temp, 0)
    TEMPERATURE[] = temp
    update_workspace_values!(strings)
    ctx.rng = PyRandom(seed)
    for _ in 1:nseed
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_description_scout], VERY_LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_bond_scout], VERY_LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        args = top_down ? Any[net[:plato_alphabetic_position_category], nothing] :
                          Any[net[:plato_string_position_category], strings[1]]
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:top_down_description_scout], LOW_URGENCY, args),
              ctx.codelet_count, ctx.rng, ctx.temperature)
    end
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        println("RUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
                sround(codelet.relative_urgency), "\t", ctx.coderack.current_num, "\t",
                proposed_bond_count(strings))
        run_codelet!(ctx, codelet)
        update_workspace_values!(strings, ctx.rng, net)
        c += 1
    end
    for s in strings
        for o in objects(s)
            for (k, d) in enumerate(all_descriptions(o))
                println("DESC\t", s.string_type, "\t", ascii_name(o), "\t", k - 1, "\t",
                        d.description_type.short_name, ":", d.descriptor.short_name, "\t",
                        d.proposal_level, "\t", d.strength)
            end
        end
        for b in reverse(s.bonds)
            bb = b::Bond
            println("BOND\t", s.string_type, "\t", ascii_name(bb.left_object), "\t",
                    ascii_name(bb.right_object), "\t", nm(bb.bond_category), "\t",
                    nm(bb.direction), "\t", nm(bb.bond_facet), "\t", bb.strength)
        end
        println("PROPOSED\t", s.string_type, "\t",
                ssum([length(v) for v in values(s.proposed_bonds)]))
        for o in objects(s)
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    o.intra_string_unhappiness, "\t", o.intra_string_salience, "\t",
                    o.relative_importance)
        end
    end
    println("CODERACK\t", ctx.coderack.current_num)
    for node in net.nodes
        node.activation == 0 || println("ACT\t", nm(node), "\t", node.activation)
    end
end

# A codelet carrying a proposed structure is normally chosen to RUN long before
# it is old enough to be evicted -- high urgency puts it in the top bin, and
# removal weight favours old, low-urgency codelets. So drive the eviction path
# directly: park bond-evaluators at the lowest urgency, flood the rack to
# MAX_CODERACK_SIZE with high-urgency codelets, and keep posting. Each further
# post evicts one codelet, and the parked evaluators are the preferred victims
# -- at which point the coderack has to unregister the bond each was carrying.
function seed_proposed_bond!(ctx::MetacatCtx, s::WorkspaceString, p::Int)
    o1 = s.letters[p]; o2 = s.letters[p + 1]
    d1 = get_descriptor_for(o1, net[:plato_letter_category])::Node
    d2 = get_descriptor_for(o2, net[:plato_letter_category])::Node
    cat = get_bond_category_between(d1, d2, net)
    cat === nothing && return
    b = make_bond(net, o1, o2, cat::Node, net[:plato_letter_category], d1, d2)
    add_proposed_bond!(s, b)
    b.proposal_level = PROPOSED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:bond_evaluator], EXTREMELY_LOW_URGENCY, Any[b]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

function eviction_probe(i, m, t, seed)
    println("EVICT-PROBLEM\t", i, "\t", m, "\t", t, "\t", seed)
    foreach(reset!, net.nodes)
    strings = [make_workspace_string(net, :initial, i),
               make_workspace_string(net, :modified, m),
               make_workspace_string(net, :target, t)]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    for nd in (net[:plato_letter_category], net[:plato_successor],
               net[:plato_predecessor], net[:plato_sameness], net[:plato_bond_facet],
               net[:plato_bond_category])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), strings[1], strings[2], strings[3],
                     50, 0)
    TEMPERATURE[] = 50
    update_workspace_values!(strings)
    ctx.rng = PyRandom(seed)
    for s in strings, p in 1:(string_length(s) - 1)
        seed_proposed_bond!(ctx, s, p)
    end
    println("EVICT-SEEDED\t", ctx.coderack.current_num, "\t",
            proposed_bond_count(strings))
    for k in 0:119
        ctx.codelet_count = 500 + k
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_bond_scout], EXTREMELY_HIGH_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        println("EVICT\t", k, "\t", ctx.coderack.current_num, "\t",
                proposed_bond_count(strings))
    end
end

probe("abc", "abd", "ijk", 3141, 80, 50, false, 15)
probe("abc", "abd", "mrrjjj", 2718, 120, 40, true, 15)
probe("abcde", "abcdf", "pqrst", 1618, 150, 70, false, 15)
probe("abcde", "abcdf", "pqrst", 2024, 120, 50, false, 60)
probe("iijjkk", "iijjll", "mmnnoo", 4096, 200, 30, true, 55)

eviction_probe("abcde", "abcdf", "pqrst", 777)
eviction_probe("iijjkk", "iijjll", "mmnnoo", 888)
