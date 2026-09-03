# Julia counterpart of metacat/bench/metacat_cm_probe.ss.
include("../../copycat/julia/src/pyrandom.jl")  # shared MT19937 (Copycat side)
include("../julia/src/schemenum.jl")
include("../julia/src/utilities.jl")
include("../julia/src/slipnet.jl")
include("../julia/src/workspace.jl")
include("../julia/src/images.jl")
include("../julia/src/concept_mappings.jl")

numstr(v) = v isa AbstractFloat ? string(v) :
            (v isa Rational ? string(numerator(v), "/", denominator(v)) : string(v))
nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"

net = build_slipnet()

"""`(long-name)` from concept-mappings.ss."""
function cm_long_name(cm::ConceptMapping, net::Slipnet)
    kind = cm.identity ? "CM" : (cm.object1 === :coattail ? "COATTAIL SLIPPAGE" : "SLIPPAGE")
    arrow = (cm.label === nothing || cm.label === net[:plato_identity]) ? "=>" :
            string("=(", (cm.label::Node).short_name, ")=>")
    return string(kind, " ", cm.description_type1.short_name, ":",
                  cm.descriptor1.short_name, arrow, cm.descriptor2.short_name)
end

function probe(i, m, t)
    println("PROBLEM\t", i, "\t", m, "\t", t)
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
              net[:plato_string_position_category])
        set_activation!(n, MAX_ACTIVATION)
    end
    update_workspace_values!(strings)
    for o1 in objects(strings[1]), o2 in objects(strings[3])
        for d1 in o1.descriptions, d2 in o2.descriptions
            cm = make_concept_mapping(net, o1, d1.description_type, d1.descriptor,
                                      o2, d2.description_type, d2.descriptor)
            println("CM\t", ascii_name(o1), "\t", ascii_name(o2), "\t",
                    cm_print_name(cm, net), "\t", cm_english_name(cm), "\t",
                    nm(cm.label), "\t", yn(cm.identity), "\t", yn(is_slippage(cm)), "\t",
                    yn(cm_relevant(cm)), "\t", yn(cm_distinguishing(cm, net)), "\t",
                    yn(identity_or_opposite_mapping(cm, net)), "\t",
                    cm_degree_of_assoc(cm), "\t", numstr(cm_conceptual_depth(cm)), "\t",
                    cm_strength(cm), "\t", cm_slippability(cm), "\t",
                    cm_long_name(cm, net))
        end
    end
end

probe("abc", "abd", "ijk")
probe("abc", "cba", "xyz")
probe("abc", "abd", "a")
