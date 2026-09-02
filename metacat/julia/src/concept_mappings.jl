# Ported from Metacat's concept-mappings.ss.
#
# A concept mapping records that a descriptor of one object corresponds to a
# descriptor of another - `lmost=>rmost`, say - together with the slipnet label
# relating them. Bridges are built out of these, and their strength and
# slippability drive most of the mapping decisions the program makes.

mutable struct ConceptMapping
    object1::Union{Nothing,WSObject,Symbol}   # Symbol for the 'coattail marker
    description_type1::Node
    descriptor1::Node
    object2::Union{Nothing,WSObject,Symbol}
    description_type2::Node
    descriptor2::Node
    label::Union{Nothing,Node}
    identity::Bool
    slipnet_link::Union{Nothing,Sliplink}
end

function make_concept_mapping(net::Slipnet, object1, description_type1::Node,
                              descriptor1::Node, object2, description_type2::Node,
                              descriptor2::Node)
    label = label_between(descriptor1, descriptor2, net[:plato_identity])
    identity = descriptor1 === descriptor2
    # Usually a lateral sliplink, but for LettCtgy/Length pred/succ "slippages"
    # such as LettCtgy:a=(succ)=>b it is a plain lateral link.
    slipnet_link = nothing
    if !identity
        candidates = (description_type1 === net[:plato_letter_category] ||
                      description_type1 === net[:plato_length]) ?
                     descriptor1.lateral_links : descriptor1.lateral_sliplinks
        idx = findfirst(l -> l.to_node === descriptor2, candidates)
        slipnet_link = idx === nothing ? nothing : candidates[idx]
    end
    return ConceptMapping(object1, description_type1, descriptor1,
                          object2, description_type2, descriptor2,
                          label, identity, slipnet_link)
end

cm_print_name(cm::ConceptMapping, net::Slipnet) =
    string(cm_short_name(cm.descriptor1, net), "=>", cm_short_name(cm.descriptor2, net))

"""`(get-CM-short-name)` — letter-category prints specially to avoid overlap."""
cm_short_name(n::Node, net::Slipnet) =
    n === net[:plato_letter_category] ? "LettCtgy" : n.short_name

cm_english_name(cm::ConceptMapping) =
    string(cm.descriptor1.lowercase_name, " <=> ", cm.descriptor2.lowercase_name)

cm_type(cm::ConceptMapping) = cm.description_type1
is_cm_type(cm::ConceptMapping, t::Node) = cm.description_type1 === t

bond_concept_mapping(cm::ConceptMapping, net::Slipnet) =
    cm.description_type1 === net[:plato_bond_category] ||
    cm.description_type1 === net[:plato_bond_facet]

reversible_cm_type(cm::ConceptMapping, net::Slipnet) =
    cm.description_type1 === net[:plato_direction_category] ||
    cm.description_type1 === net[:plato_bond_category] ||
    cm.description_type1 === net[:plato_group_category]

"""`(slippage?)` — anything where the two descriptors differ, including
unlabelled ObjCtgy:let=>grp mappings."""
is_slippage(cm::ConceptMapping) = !cm.identity

opposite_mapping(cm::ConceptMapping, net::Slipnet) = cm.label === net[:plato_opposite]

identity_or_opposite_mapping(cm::ConceptMapping, net::Slipnet) =
    cm.label === net[:plato_identity] || cm.label === net[:plato_opposite] ||
    (cm.descriptor1 === net[:plato_whole] && cm.descriptor2 === net[:plato_single]) ||
    (cm.descriptor1 === net[:plato_single] && cm.descriptor2 === net[:plato_whole])

cm_relevant(cm::ConceptMapping) =
    fully_active(cm.description_type1) && fully_active(cm.description_type2)

function cm_distinguishing(cm::ConceptMapping, net::Slipnet)
    (cm.identity && cm.descriptor1 === net[:plato_whole]) && return false
    distinguishing_descriptor(net, cm.object1::WSObject, cm.descriptor1) || return false
    return distinguishing_descriptor(net, cm.object2::WSObject, cm.descriptor2)
end

cm_relevant_distinguishing(cm::ConceptMapping, net::Slipnet) =
    cm_relevant(cm) && cm_distinguishing(cm, net)

distinguishing_identity_or_opposite(cm::ConceptMapping, net::Slipnet) =
    cm_distinguishing(cm, net) && identity_or_opposite_mapping(cm, net)

"""`(get-degree-of-assoc)` — 5 for an unlabelled LettCtgy/Length slippage such
as LettCtgy:m=>j."""
function cm_degree_of_assoc(cm::ConceptMapping)
    cm.identity && return 100
    cm.slipnet_link !== nothing && return link_degree_of_assoc(cm.slipnet_link::Sliplink)
    return 5
end

cm_conceptual_depth(cm::ConceptMapping) =
    sdiv(cm.descriptor1.conceptual_depth + cm.descriptor2.conceptual_depth, 2)

function cm_strength(cm::ConceptMapping)
    doa = cm_degree_of_assoc(cm)
    doa == 100 && return 100
    return sround(doa * (1 + sq(pct(cm_conceptual_depth(cm)))))
end

function cm_slippability(cm::ConceptMapping)
    doa = cm_degree_of_assoc(cm)
    doa == 100 && return 100
    return sround(doa * sub_from_1(sq(pct(cm_conceptual_depth(cm)))))
end

cm_symmetric(cm::ConceptMapping, other::ConceptMapping) =
    other.descriptor1 === cm.descriptor2 && other.descriptor2 === cm.descriptor1

function cm_symmetric_mapping(cm::ConceptMapping, net::Slipnet)
    cm.identity && return cm
    return make_concept_mapping(net, cm.object1, cm.description_type2, cm.descriptor2,
                                cm.object2, cm.description_type1, cm.descriptor1)
end

function activate_descriptions!(cm::ConceptMapping)
    activate_from_workspace!(cm.description_type1)
    activate_from_workspace!(cm.descriptor1)
    activate_from_workspace!(cm.description_type2)
    activate_from_workspace!(cm.descriptor2)
    return cm
end

function activate_label!(cm::ConceptMapping)
    if cm.label !== nothing
        label = cm.label::Node
        activate_from_workspace!(label)
        # flushed immediately so the label's activation shows up in the trace
        # before the concept mapping that caused it
        flush_activation_buffer!(label)
    end
    return cm
end

cms_equal(a::ConceptMapping, b::ConceptMapping) =
    a.descriptor1 === b.descriptor1 && a.descriptor2 === b.descriptor2

"""`(remove-duplicate-CMs)`. NB: remove-duplicates-pred drops an element when a
duplicate appears LATER in the list, so it keeps the last of each group, not
the first."""
function remove_duplicate_cms(cms::Vector{ConceptMapping})
    result = ConceptMapping[]
    for (i, cm) in enumerate(cms)
        any(x -> cms_equal(cm, x), @view cms[i+1:end]) && continue
        push!(result, cm)
    end
    return result
end
