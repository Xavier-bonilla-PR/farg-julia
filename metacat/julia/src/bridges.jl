# Ported from Metacat's bridges.ss.
#
# A bridge is a correspondence between an object in one string and an object in
# another, justified by a set of concept mappings. Metacat has two orientations:
# HORIZONTAL bridges run initial->modified (the "top" bridge) or
# target->answer (the "bottom" bridge) and say how the change works; VERTICAL
# bridges run initial->target and say how the two situations correspond.
# The two constructors in bridges.ss share nearly all of their behaviour, so
# they are one type here with an `orientation` field, and the places where they
# genuinely differ dispatch on it.
#
# Deferred, and marked where they arise: the flipped-group and translated-rule
# machinery, and graphics. Theme boosting and thematic compatibility live in
# themes.jl, which loads after this file.

mutable struct Bridge
    orientation::Symbol                # :horizontal | :vertical
    bridge_type::Symbol                # :top | :bottom | :vertical
    object1::WSObject
    object2::WSObject
    concept_mappings::Vector{ConceptMapping}
    bond_concept_mappings::Vector{ConceptMapping}
    all_concept_mappings::Vector{ConceptMapping}
    symmetric_slippages::Vector{ConceptMapping}
    spanning_bridge::Bool
    group_spanning_bridge::Bool
    flipped_group1::Bool
    flipped_group2::Bool
    # the unflipped groups a flipped bridge was proposed from; the builder has
    # to beat these before it may replace them
    original_group1::Union{Nothing,WSObject}
    original_group2::Union{Nothing,WSObject}
    translated_rule_bridge::Bool
    # workspace-structure fields
    time_stamp::Int
    strength::Int
    proposal_level::Int
    enclosing_group::Union{Nothing,WSObject}
end

"""`(bridge-type->orientation)` in reverse: which string a horizontal bridge
starts from decides whether it is the top or the bottom bridge."""
function horizontal_bridge_type(object1::WSObject)
    return object1.string.string_type === :initial ? :top : :bottom
end

function make_bridge(orientation::Symbol, object1::WSObject, object2::WSObject,
                     concept_mappings::Vector{ConceptMapping}, net::Slipnet,
                     codelet_count::Int = 0)
    bridge_type = orientation === :horizontal ? horizontal_bridge_type(object1) : :vertical
    # NB: the Scheme constructor does NOT call set-concept-mappings. It starts
    # with bond-CMs empty, all-CMs equal to the CMs passed in, and NO symmetric
    # slippages; those are filled in later, when set-concept-mappings is sent
    # or the bridge is built.
    return Bridge(orientation, bridge_type, object1, object2,
                  copy(concept_mappings), ConceptMapping[], copy(concept_mappings),
                  ConceptMapping[],
                  spans_whole_string(object1) && spans_whole_string(object2),
                  string_spanning_group(object1) && string_spanning_group(object2),
                  false, false, nothing, nothing, false, codelet_count, 0, 0, nothing)
end

"""`(set-concept-mappings CM-list)` — splits the bond CMs out, keeps the rest,
and rebuilds the symmetric slippages."""
function set_concept_mappings!(b::Bridge, cm_list::Vector{ConceptMapping}, net::Slipnet)
    b.bond_concept_mappings = ConceptMapping[cm for cm in cm_list
                                             if bond_concept_mapping(cm, net)]
    b.concept_mappings = ConceptMapping[cm for cm in cm_list
                                        if !bond_concept_mapping(cm, net)]
    b.all_concept_mappings = vcat(b.concept_mappings, b.bond_concept_mappings)
    b.symmetric_slippages = ConceptMapping[cm_symmetric_mapping(cm, net)
                                           for cm in b.all_concept_mappings
                                           if is_slippage(cm)]
    return b
end

"""`(add-concept-mappings cm-list)` — NB these PREPEND, as everything else in
Metacat does. `add-concept-mapping` is this with a one-element list, so a
mapping added later comes out earlier."""
function add_concept_mappings!(b::Bridge, cms::Vector{ConceptMapping})
    prepend!(b.concept_mappings, cms)
    prepend!(b.all_concept_mappings, cms)
    return b
end

add_concept_mapping!(b::Bridge, cm::ConceptMapping) =
    add_concept_mappings!(b, ConceptMapping[cm])

function add_bond_concept_mapping!(b::Bridge, cm::ConceptMapping)
    pushfirst!(b.bond_concept_mappings, cm)
    pushfirst!(b.all_concept_mappings, cm)
    return b
end

add_symmetric_slippage!(b::Bridge, cm::ConceptMapping, net::Slipnet) =
    (pushfirst!(b.symmetric_slippages, cm_symmetric_mapping(cm, net)); b)

get_concept_mapping(b::Bridge, description_type::Node) =
    (i = findfirst(cm -> is_cm_type(cm, description_type), b.all_concept_mappings);
     i === nothing ? nothing : b.all_concept_mappings[i])

get_relevant_cms(b::Bridge) = ConceptMapping[cm for cm in b.concept_mappings if cm_relevant(cm)]
get_distinguishing_cms(b::Bridge, net::Slipnet) =
    ConceptMapping[cm for cm in b.concept_mappings if cm_distinguishing(cm, net)]
"""`(delete-concept-mapping-type type)` — drops the FIRST concept mapping of
that type, and the symmetric slippage that goes with it, from every list it
appears in."""
function delete_concept_mapping_type!(b::Bridge, type::Node)
    i = findfirst(cm -> is_cm_type(cm, type), b.all_concept_mappings)
    if i !== nothing
        cm = b.all_concept_mappings[i]
        deleteat!(b.all_concept_mappings, i)
        j = findfirst(x -> x === cm, b.concept_mappings)
        j === nothing || deleteat!(b.concept_mappings, j)
    end
    k = findfirst(cm -> is_cm_type(cm, type), b.symmetric_slippages)
    k === nothing || deleteat!(b.symmetric_slippages, k)
    return b
end

cm_type_present(b::Bridge, type::Node) =
    any(cm -> is_cm_type(cm, type), b.all_concept_mappings)

get_relevant_distinguishing_cms(b::Bridge, net::Slipnet) =
    ConceptMapping[cm for cm in b.concept_mappings if cm_relevant_distinguishing(cm, net)]

get_non_symmetric_slippages(b::Bridge) =
    ConceptMapping[cm for cm in b.all_concept_mappings if is_slippage(cm)]
"""NB the non-BOND slippages come from `concept-mappings`, not from
`all-concept-mappings` — that is the whole of the difference."""
get_non_symmetric_non_bond_slippages(b::Bridge) =
    ConceptMapping[cm for cm in b.concept_mappings if is_slippage(cm)]

"""`(slippage-type-present? type)` — the FIRST concept mapping of that type, if
there is one, is a slippage."""
function slippage_type_present(b::Bridge, type::Node)
    i = findfirst(cm -> is_cm_type(cm, type), b.all_concept_mappings)
    return i !== nothing && is_slippage(b.all_concept_mappings[i])
end

"""`(bridge-between? orientation object1 object2)`."""
function bridge_between(orientation::Symbol, object1, object2)
    b = get_bridge(object1, orientation)
    return b !== nothing && (b::Bridge).object2 === object2
end

enclosing_group1(b::Bridge) = b.object1.enclosing_group
enclosing_group2(b::Bridge) = b.object2.enclosing_group

"""`(StrPosCtgy:Opposite-slippage?)` — the bridge maps string position by
Opposite, which is what a direction reversal is abstracted from."""
function strposctgy_opposite_slippage(b::Bridge, net::Slipnet)
    i = findfirst(cm -> is_cm_type(cm, net[:plato_string_position_category]),
                  b.concept_mappings)
    return i !== nothing && b.concept_mappings[i].label === net[:plato_opposite]
end
get_slippages(b::Bridge) = vcat(get_non_symmetric_slippages(b), b.symmetric_slippages)

get_other_object(b::Bridge, object::WSObject) =
    object === b.object1 ? b.object2 : b.object1
get_covered_letters(b::Bridge) = vcat(get_letters(b.object1), get_letters(b.object2))
bridge_letter_span(b::Bridge) = get_letter_span(b.object1) + get_letter_span(b.object2)
get_letter_span(b::Bridge) = bridge_letter_span(b)

"""`(get-original-object1)` — the object the bridge was proposed FROM, which for
a flipped bridge is the group before flipping. Existence checks use these,
since the flipped version was never in the workspace."""
original_object1(b::Bridge) =
    b.flipped_group1 ? (b.original_group1)::WSObject : b.object1
original_object2(b::Bridge) =
    b.flipped_group2 ? (b.original_group2)::WSObject : b.object2

"""`(bridge-type->orientation bridge-type)`."""
bridge_type_to_orientation(bridge_type::Symbol) =
    bridge_type === :vertical ? :vertical : :horizontal

"""`(lone-spanning-object? object1 object2)` — exactly one of them spans its
whole string, so there is nothing sensible to map."""
lone_spanning_object(object1::WSObject, object2::WSObject) =
    spans_whole_string(object1) != spans_whole_string(object2)

# --- CM-level compatibility -------------------------------------------------
#
# The horizontal and vertical versions of these four predicates are textually
# identical in bridges.ss; only the bridge-level predicates differ.

function supporting_cms(cm1::ConceptMapping, cm2::ConceptMapping)
    cms_equal(cm1, cm2) && return true
    (related(cm1.descriptor1, cm2.descriptor1) ||
     related(cm1.descriptor2, cm2.descriptor2)) || return false
    (cm1.label !== nothing && cm2.label !== nothing) || return false
    return cm1.label === cm2.label
end

function incompatible_cms(cm1::ConceptMapping, cm2::ConceptMapping, net::Slipnet)
    (related(cm1.descriptor1, cm2.descriptor1) ||
     related(cm1.descriptor2, cm2.descriptor2)) || return false
    (cm1.label !== nothing && cm2.label !== nothing) || return false
    cm1.label === cm2.label && return false
    id = net[:plato_identity]
    return label_between(cm1.descriptor1, cm2.descriptor1, id) !==
           label_between(cm1.descriptor2, cm2.descriptor2, id)
end

incompatible_cm_lists(l1, l2, net::Slipnet) =
    any(cm1 -> any(cm2 -> incompatible_cms(cm1, cm2, net), l2), l1)

incompatible_with_any_cm(cm, l, net::Slipnet) =
    any(other -> incompatible_cms(cm, other, net), l)

"""`(letter-category/length-slippage? cm)`."""
letter_category_or_length_slippage(cm::ConceptMapping, net::Slipnet) =
    (is_cm_type(cm, net[:plato_letter_category]) && is_slippage(cm)) ||
    (is_cm_type(cm, net[:plato_length]) && is_slippage(cm))

"""`(enclosing-bridge? b1 b2)`."""
enclosing_bridge(b1::Bridge, b2::Bridge) =
    nested_member(b1.object1, b2.object1) && nested_member(b1.object2, b2.object2)

bridges_equal(b1::Bridge, b2::Bridge) =
    b1.object1 === b2.object1 && b1.object2 === b2.object2

function bridge_between(orientation::Symbol, object1::WSObject, object2::WSObject)
    b = get_bridge(object1, orientation)
    return b !== nothing && (b::Bridge).object2 === object2
end

function get_bridge_between(orientation::Symbol, object1::WSObject, object2::WSObject)
    b = get_bridge(object1, orientation)
    return (b !== nothing && (b::Bridge).object2 === object2) ? b : nothing
end

# --- bridge-level compatibility ---------------------------------------------

"""`(incompatible-horizontal-bridges? b1 b2)` / the vertical version.

Horizontal bridges first drop letter-category and length slippages, so that
e.g. the spanning bridge of abc -> abcc is not made incompatible with c-->cc by
the Length CMs 3=>3 and 1=>2. Vertical bridges skip that step, since letter
category and length slippages cannot underlie a vertical bridge. Both then
consider a bridge's direction-category CM only when it encloses the other."""
function incompatible_bridges(b1::Bridge, b2::Bridge, net::Slipnet)
    b1.object1 === b2.object1 && return true
    b1.object2 === b2.object2 && return true
    cms1 = b1.concept_mappings
    cms2 = b2.concept_mappings
    if b1.orientation === :horizontal
        cms1 = ConceptMapping[cm for cm in cms1
                              if !letter_category_or_length_slippage(cm, net)]
        cms2 = ConceptMapping[cm for cm in cms2
                              if !letter_category_or_length_slippage(cm, net)]
    end
    dc = net[:plato_direction_category]
    l1 = enclosing_bridge(b1, b2) ? cms1 :
         ConceptMapping[cm for cm in cms1 if !is_cm_type(cm, dc)]
    l2 = enclosing_bridge(b2, b1) ? cms2 :
         ConceptMapping[cm for cm in cms2 if !is_cm_type(cm, dc)]
    return incompatible_cm_lists(l1, l2, net)
end

function supporting_bridges(b1::Bridge, b2::Bridge, net::Slipnet)
    incompatible_bridges(b1, b2, net) && return false
    d1 = get_distinguishing_cms(b1, net)
    d2 = get_distinguishing_cms(b2, net)
    return any(cm1 -> any(cm2 -> supporting_cms(cm1, cm2), d2), d1)
end

# --- mappable descriptions --------------------------------------------------

"""`(letter-category-mappable-objects? object1 object2)`. NB: the last clause
compares object1's group category with ITSELF in the Scheme, so it is always
true for two groups. Preserved."""
function letter_category_mappable_objects(object1::WSObject, object2::WSObject)
    object1 isa Letter && object2 isa Letter && return true
    object1 isa Letter && object2 isa Group && return (object2::Group).all_letter_group
    object1 isa Group && object2 isa Letter && return (object1::Group).all_letter_group
    if object1 isa Group && object2 isa Group
        return related((object1::Group).group_category, (object1::Group).group_category)
    end
    return false
end

function horizontal_mappable_descriptions(object1::WSObject, object2::WSObject,
                                          d1::Description, d2::Description, net::Slipnet)
    d1.description_type === d2.description_type || return false
    if d1.description_type === net[:plato_letter_category]
        return letter_category_mappable_objects(object1, object2)
    end
    return d1.description_type === net[:plato_string_position_category] ||
           d1.description_type === net[:plato_length] ||
           d1.descriptor === d2.descriptor ||
           slip_linked(d1.descriptor, d2.descriptor)
end

function vertical_mappable_descriptions(::WSObject, ::WSObject,
                                        d1::Description, d2::Description, ::Slipnet)
    d1.description_type === d2.description_type || return false
    return d1.descriptor === d2.descriptor || slip_linked(d1.descriptor, d2.descriptor)
end

"""`(all-possible-bridge-CMs ...)`."""
function all_possible_bridge_cms(orientation::Symbol, object1::WSObject,
                                 object1_descriptions, object2::WSObject,
                                 object2_descriptions, net::Slipnet)
    mappable = orientation === :horizontal ? horizontal_mappable_descriptions :
                                             vertical_mappable_descriptions
    result = ConceptMapping[]
    for d1 in object1_descriptions, d2 in object2_descriptions
        mappable(object1, object2, d1, d2, net) || continue
        push!(result, make_concept_mapping(net, object1, d1.description_type, d1.descriptor,
                                           object2, d2.description_type, d2.descriptor))
    end
    return result
end

# --- strength ---------------------------------------------------------------

"""`(singleton-letter? object)`."""
function singleton_letter(object::WSObject)
    g = object.enclosing_group
    return object isa Letter && g !== nothing && singleton_group(g::Group)
end

"""`(singleton-letter-factor object1 object2)` — horizontal bridges only."""
function singleton_letter_factor(object1::WSObject, object2::WSObject)
    singleton_letter(object1) && return object2 isa Letter ? 1 : 0.1
    singleton_letter(object2) && return object1 isa Letter ? 1 : 0.1
    singleton_group(object1) && return object2 isa Group ? 1 : 0.1
    singleton_group(object2) && return object1 isa Group ? 1 : 0.1
    return 1
end

function internally_coherent(b::Bridge, net::Slipnet)
    cms = get_relevant_distinguishing_cms(b, net)
    for cm1 in cms, cm2 in cms
        cm1 === cm2 && continue
        supporting_cms(cm1, cm2) && return true
    end
    return false
end

function calculate_internal_strength(b::Bridge, net::Slipnet)
    cms = get_relevant_distinguishing_cms(b, net)
    isempty(cms) && return 0
    average_strength = sdiv(ssum([cm_strength(cm) for cm in cms]), length(cms))
    n = length(cms)
    num_factor = n == 1 ? 0.8 : (n == 2 ? 1.2 : 1.6)
    coherence_factor = internally_coherent(b, net) ? 2.5 : 1.0
    # singleton-letter-factor applies to horizontal bridges only
    singleton_factor = b.orientation === :horizontal ?
                       singleton_letter_factor(b.object1, b.object2) : 1
    return min(100, sround(average_strength * num_factor * coherence_factor *
                           singleton_factor))
end

"""`(calculate-external-strength)` — the summed strength of every other bridge
of the same type that supports this one."""
function calculate_external_strength(b::Bridge, all_bridges::Vector{Bridge}, net::Slipnet)
    ((b.object1 isa Letter && spans_whole_string(b.object1)) ||
     (b.object2 isa Letter && spans_whole_string(b.object2))) && return 100
    total = 0
    for other in all_bridges
        other === b && continue
        other.bridge_type === b.bridge_type || continue
        supporting_bridges(b, other, net) && (total += other.strength)
    end
    return sround(min(100, total))
end

"""With no themespace there are no active themes, so `get-average-theme-support`
weighs nothing and the compatibility is 0 — the workspace-structure default."""
get_thematic_compatibility(::Bridge, ::Nothing, ::Slipnet) = 0

"""`(update-strength)` for a bridge. Unlike bonds and groups, a bridge has a
thematic compatibility of its own, and it is signed: a bridge that violates an
active theme is dragged toward strength 0, one that realises the themes toward
100."""
function update_structure_strength!(b::Bridge, net::Slipnet, all_bridges::Vector{Bridge},
                                    ts = nothing)
    internal = calculate_internal_strength(b, net)
    external = calculate_external_strength(b, all_bridges, net)
    intrinsic = weighted_average((internal, external), (internal, sub_from_100(internal)))
    compatibility = get_thematic_compatibility(b, ts, net)
    thematic_weight = abs(compatibility)
    b.strength = sround(weighted_average((compatibility > 0 ? 100 : 0, intrinsic),
                                         (thematic_weight, sub_from_1(thematic_weight))))
    return b
end

# --- building ---------------------------------------------------------------

"""`(build-bridge bridge-orientation bridge)` without a workspace context: it
attaches the bridge to its objects but cannot register it in the workspace or
add the length concept mapping. `codelets_bridges.jl` has the full version;
this one exists for the probes that build bridges outside a run."""
function build_bridge!(b::Bridge, net::Slipnet)
    update_bridge!(b.object1, b.orientation, b)
    update_bridge!(b.object2, b.orientation, b)
    if b.orientation === :horizontal
        # every horizontal bridge needs an ObjCtgy CM, relevant or not, so that
        # rule abstraction does not go wrong later
        if !any(cm -> is_cm_type(cm, net[:plato_object_category]), b.concept_mappings)
            cm = make_concept_mapping(net, b.object1, net[:plato_object_category],
                                      get_descriptor_for(b.object1,
                                                         net[:plato_object_category])::Node,
                                      b.object2, net[:plato_object_category],
                                      get_descriptor_for(b.object2,
                                                         net[:plato_object_category])::Node)
            add_concept_mapping!(b, cm)
            is_slippage(cm) && add_symmetric_slippage!(b, cm, net)
        end
    end
    for slippage in ConceptMapping[cm for cm in b.concept_mappings if is_slippage(cm)]
        add_symmetric_slippage!(b, slippage, net)
    end
    if b.object1 isa Group && b.object2 isa Group
        for bond_cm in all_possible_bridge_cms(b.orientation, b.object1,
                                               (b.object1::Group).bond_descriptions,
                                               b.object2,
                                               (b.object2::Group).bond_descriptions, net)
            add_bond_concept_mapping!(b, bond_cm)
            is_slippage(bond_cm) && add_symmetric_slippage!(b, bond_cm, net)
        end
    end
    b.proposal_level = BUILT
    return b
end

"""`(get-bond-slippages)` — the slippages this bridge carries that are ABOUT
bonds (BondCtgy or BondFacet), which is what an enclosing group's bridge
contributes to translating the objects inside it."""
get_bond_slippages(b::Bridge, net::Slipnet) =
    ConceptMapping[cm for cm in get_slippages(b) if bond_concept_mapping(cm, net)]

"""`(mark-as-translated-rule-bridge)` — a bridge from a real object to its
counterpart in a TRANSLATED string, rather than one the model perceived."""
mark_as_translated_rule_bridge!(b::Bridge) = (b.translated_rule_bridge = true; b)

"""`(supports-theme-pattern? pattern)` — whether any concept mapping of this
bridge is exactly one of the pattern's entries. The whole/single mappings are
dropped first, for the reason justify.ss gives: keeping them would drag in the
StrPos:diff theme and only confuse things."""
function supports_theme_pattern(b::Bridge, pattern, net::Slipnet)
    cms = remove_whole_single_concept_mappings(b.all_concept_mappings, net)
    for entry in pattern[2:end], cm in cms
        cm_type(cm) === entry[1] && cm.label === entry[2] && return true
    end
    return false
end
