# Julia counterpart of metacat/bench/metacat_bonds_probe.ss.
include("../../copycat/julia/src/pyrandom.jl")  # shared MT19937 (Copycat side)
include("../julia/src/schemenum.jl")
include("../julia/src/utilities.jl")
include("../julia/src/slipnet.jl")
include("../julia/src/workspace.jl")
include("../julia/src/concept_mappings.jl")
include("../julia/src/bonds.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"

net = build_slipnet()

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
              net[:plato_predecessor], net[:plato_sameness])
        set_activation!(n, MAX_ACTIVATION)
    end
    update_workspace_values!(strings)
    rng = PyRandom(seed)
    for s in strings
        for p in 1:(string_length(s) - 1)
            o1 = s.letters[p]
            o2 = s.letters[p + 1]
            d1 = get_descriptor_for(o1, net[:plato_letter_category])::Node
            d2 = get_descriptor_for(o2, net[:plato_letter_category])::Node
            cat = get_bond_category_between(d1, d2, net)
            if cat === nothing
                println("NOBOND\t", s.string_type, "\t", ascii_name(o1), "\t", ascii_name(o2))
            else
                b = make_bond(net, o1, o2, cat::Node, net[:plato_letter_category], d1, d2)
                build_bond!(b)
                println("BOND\t", s.string_type, "\t", ascii_name(o1), "\t", ascii_name(o2),
                        "\t", nm(cat), "\t", nm(b.direction), "\t",
                        yn(bond_leftmost_in_string(b)), "\t", yn(bond_rightmost_in_string(b)),
                        "\t", nm(b.bond_facet), "\t", calculate_internal_strength(b, net))
            end
        end
    end
    for s in strings
        for b in reverse(s.bonds)
            println("SUP\t", s.string_type, "\t", ascii_name(b.left_object), "\t",
                    ascii_name(b.right_object), "\t", get_num_of_local_supporting_bonds(b),
                    "\t", get_local_density(rng, b), "\t", get_local_support(rng, b))
        end
    end
    update_workspace_values!(strings, rng, net)
    for s in strings
        for b in reverse(s.bonds)
            println("STR\t", s.string_type, "\t", ascii_name(b.left_object), "\t",
                    ascii_name(b.right_object), "\t", b.strength, "\t",
                    get_local_support(rng, b))
        end
        for o in objects(s)
            println("OBJU\t", s.string_type, "\t", ascii_name(o), "\t",
                    o.intra_string_unhappiness, "\t", o.intra_string_salience)
        end
    end
end

probe("abc", "abd", "ijk", 11)
probe("abc", "abd", "mrrjjj", 22)
probe("abc", "cba", "pqrs", 33)
