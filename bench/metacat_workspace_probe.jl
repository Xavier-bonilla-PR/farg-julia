# Julia counterpart of bench/metacat_workspace_probe.ss.
include("../julia/src/pyrandom.jl")
include("../julia/src/metacat/schemenum.jl")
include("../julia/src/metacat/utilities.jl")
include("../julia/src/metacat/slipnet.jl")
include("../julia/src/metacat/workspace.jl")

numstr(v) = v isa AbstractFloat ? string(v) :
            (v isa Rational ? string(numerator(v), "/", denominator(v)) : string(v))
nm(n) = n === nothing ? "-" : n.lowercase_name

net = build_slipnet()

function probe_problem(i, m, t)
    println("PROBLEM\t", i, "\t", m, "\t", t)
    strings = init_workspace(net, i, m, t)
    for s in strings
        println("STRING\t", s.string_type, "\t", s.print_name, "\t", string_length(s),
                "\t", s.average_intra_string_unhappiness)
        for obj in objects(s)
            println("OBJ\t", s.string_type, "\t", ascii_name(obj), "\t", obj.id_num,
                    "\t", obj.string_pos, "\t", numstr(obj.raw_importance),
                    "\t", obj.relative_importance,
                    "\t", obj.intra_string_unhappiness,
                    "\t", obj.horizontal_inter_string_unhappiness,
                    "\t", obj.vertical_inter_string_unhappiness,
                    "\t", obj.average_unhappiness,
                    "\t", obj.intra_string_salience,
                    "\t", obj.horizontal_inter_string_salience,
                    "\t", obj.vertical_inter_string_salience,
                    "\t", obj.average_salience,
                    "\t", leftmost_in_string(obj) ? "L" : "-",
                    "\t", rightmost_in_string(obj) ? "R" : "-")
            for (k, d) in enumerate(obj.descriptions)
                println("DESC\t", s.string_type, "\t", ascii_name(obj), "\t", k - 1,
                        "\t", nm(d.description_type), "\t", nm(d.descriptor),
                        "\t", d.proposal_level, "\t", d.strength,
                        "\t", numstr(calculate_internal_strength(d)),
                        "\t", numstr(calculate_external_strength(d)),
                        "\t", calculate_local_support(d))
            end
        end
    end
    for node in net.nodes
        node.activation == 0 && continue
        println("SLIPACT\t", nm(node), "\t", node.activation, "\t",
                node.frozen ? "frozen" : "-")
    end
end

probe_problem("abc", "abd", "ijk")
probe_problem("abc", "cba", "pqrs")
probe_problem("a", "b", "xyz")
probe_problem("abc", "abd", "mrrjjj")
