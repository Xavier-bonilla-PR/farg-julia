# Julia counterpart of metacat/bench/metacat_slipnet_probe.ss: same dump, same order.
include("../../copycat/julia/src/pyrandom.jl")  # shared MT19937 (Copycat side)
include("../julia/src/schemenum.jl")
include("../julia/src/utilities.jl")
include("../julia/src/slipnet.jl")

numstr(v) = v isa AbstractFloat ? string(v) :
            (v isa Rational ? string(numerator(v), "/", denominator(v)) : string(v))
nm(n) = n === nothing ? "-" : n.lowercase_name
typestr(t) = replace(String(t), "_" => "-")

net = build_slipnet()

println("COUNT\tnodes\t", length(net.nodes))

for node in net.nodes
    println("NODE\t", nm(node), "\t", node.short_name, "\t", node.conceptual_depth,
            "\t", node.intrinsic_link_length, "\t", node.shrunk_link_length,
            "\t", length(node.incoming_links))
end

for node in net.nodes
    instance_links = [l for l in outgoing_links(node) if l.link_type === :instance]
    for (listname, links) in (("category", node.category_links),
                              ("instance", instance_links),
                              ("property", node.property_links),
                              ("lateral", node.lateral_links),
                              ("sliplink", node.lateral_sliplinks),
                              ("labeled", node.links_labeled_by_node))
        for (i, l) in enumerate(links)
            println("LINK\t", nm(node), "\t", listname, "\t", i - 1, "\t",
                    nm(l.from_node), "\t", nm(l.to_node), "\t", typestr(l.link_type), "\t",
                    nm(l.label_node), "\t", l.link_length, "\t",
                    numstr(intrinsic_degree_of_assoc(l)), "\t",
                    numstr(link_degree_of_assoc(l)))
        end
    end
end

# --- activation dynamics ---
foreach(reset!, net.nodes)
rng = PyRandom(314159)
activate_from_workspace!(net[:plato_a])
activate_from_workspace!(net[:plato_successor])
activate_from_workspace!(net[:plato_letter_category])
for cycle in 0:19
    update_slipnet_activations!(net, rng)
    for node in net.nodes
        node.activation == 0 || println("ACT\t", cycle, "\t", nm(node), "\t", node.activation)
    end
end
