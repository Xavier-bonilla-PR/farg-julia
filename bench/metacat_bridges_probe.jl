# Julia counterpart of bench/metacat_bridges_probe.ss.
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

function dump_bridge(tag, b::Bridge)
    println("BR\t", tag, "\t", b.orientation, "\t", b.bridge_type, "\t",
            ascii_name(b.object1), "\t", ascii_name(b.object2), "\t",
            yn(b.spanning_bridge), "\t", yn(b.group_spanning_bridge), "\t",
            length(b.concept_mappings), "\t", length(b.all_concept_mappings), "\t",
            yn(internally_coherent(b, net)), "\t", calculate_internal_strength(b, net))
    for (k, cm) in enumerate(b.all_concept_mappings)
        println("BRCM\t", tag, "\t", k - 1, "\t", cm_print_name(cm, net), "\t",
                nm(cm.label), "\t", yn(is_slippage(cm)), "\t", yn(cm_relevant(cm)), "\t",
                yn(cm_distinguishing(cm, net)), "\t", cm_strength(cm))
    end
    for (k, ss) in enumerate(b.symmetric_slippages)
        println("BRSS\t", tag, "\t", k - 1, "\t", cm_print_name(ss, net))
    end
end

function probe(i, m, t, seed)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed)
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
    for n in (net[:plato_object_category], net[:plato_letter_category],
              net[:plato_string_position_category], net[:plato_successor],
              net[:plato_predecessor], net[:plato_sameness], net[:plato_group_category],
              net[:plato_direction_category], net[:plato_length],
              net[:plato_alphabetic_position_category], net[:plato_bond_category],
              net[:plato_bond_facet])
        set_activation!(n, MAX_ACTIVATION)
    end
    update_workspace_values!(strings)
    rng = PyRandom(seed)
    for s in strings
        build_chain_and_group!(s)
    end
    update_workspace_values!(strings, rng, net)
    for (orientation, s1, s2) in ((:vertical, strings[1], strings[3]),
                                  (:horizontal, strings[1], strings[2]))
        for o1 in objects(s1), o2 in objects(s2)
            cms = all_possible_bridge_cms(orientation, o1, o1.descriptions,
                                          o2, o2.descriptions, net)
            isempty(cms) && continue
            b = make_bridge(orientation, o1, o2, cms, net)
            dump_bridge(string(orientation, ":", ascii_name(o1), ">", ascii_name(o2)), b)
        end
    end
end

probe("abc", "abd", "ijk", 71)
probe("abc", "abd", "mrrjjj", 72)
probe("abc", "cba", "pqrs", 73)
