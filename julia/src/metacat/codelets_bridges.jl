# The bridge codelet pipeline, ported from bridges.ss.
#
# Bridges follow the same scout -> evaluator -> builder shape as bonds, but the
# builder has far more to fight: other bridges (directly incompatible, or
# incompatible through the groups at either end), a bond whose direction
# contradicts the mapping, that bond's enclosing group, and - when the bridge
# wants to read a spanning group backwards - the unflipped group itself.
#
# Two scouts feed it. `bottom-up-bridge-scout` picks both objects by
# inter-string salience; `important-object-bridge-scout` picks an important
# object on one side and then looks for something on the other side carrying
# the descriptor an existing slippage maps it to.

"""`(bridge-type->orientation bridge-type)`."""
bridge_type_orientation(bridge_type::Symbol) =
    bridge_type === :vertical ? :vertical : :horizontal

"""`(get-inter-string-salience bridge-orientation)` as a getter."""
inter_string_salience_getter(orientation::Symbol) =
    orientation === :horizontal ? (o -> o.horizontal_inter_string_salience) :
                                  (o -> o.vertical_inter_string_salience)

"""The string pair a bridge type runs between. Justify mode, which adds the
`bottom` type over the target and answer strings, is not ported."""
function bridge_strings(ctx::MetacatCtx, bridge_type::Symbol)
    bridge_type === :top && return (ctx.initial_string, ctx.modified_string)
    bridge_type === :vertical && return (ctx.initial_string, ctx.target_string)
    error("bridge type $bridge_type needs justify mode, which is not ported")
end

"""`(get-all-slippages bridge-type)`."""
all_slippages(ctx::MetacatCtx, bridge_type::Symbol) =
    vcat(ConceptMapping[],
         (get_slippages(b::Bridge) for b in bridge_list(ctx, bridge_type))...)

# --- incompatibility --------------------------------------------------------

"""`(group-incompatible-bridges bridge-orientation object1 object2)` — the
bridges that this one would have to displace because of the grouping around
its two ends.

A bridge to a group is incompatible with any bridge from one of that group's
constituents, unless the constituent's bridge lands inside the group at the
other end - in which case the two are nested, not in conflict. Symmetrically,
a bridge from an object inside a group conflicts with the group's own bridge
unless both ends sit inside the two bridged groups."""
function group_incompatible_bridges(orientation::Symbol, object1::WSObject,
                                    object2::WSObject)
    result = Any[]
    enclosing_group1 = object1.enclosing_group
    enclosing_group2 = object2.enclosing_group
    if object1 isa Group
        subobject_bridges = get_subobject_bridges(object1::Group, orientation)
        append!(result, object2 isa Letter ? subobject_bridges :
                Any[b for b in subobject_bridges
                    if !top_level_member(object2::Group, (b::Bridge).object2)])
    end
    if object2 isa Group
        subobject_bridges = get_subobject_bridges(object2::Group, orientation)
        append!(result, object1 isa Letter ? subobject_bridges :
                Any[b for b in subobject_bridges
                    if !top_level_member(object1::Group, (b::Bridge).object1)])
    end
    if enclosing_group1 !== nothing
        group_bridge = get_bridge(enclosing_group1::WSObject, orientation)
        if group_bridge !== nothing
            other_object = (group_bridge::Bridge).object2
            (enclosing_group2 === nothing || enclosing_group2 !== other_object) &&
                push!(result, group_bridge)
        end
    end
    if enclosing_group2 !== nothing
        group_bridge = get_bridge(enclosing_group2::WSObject, orientation)
        if group_bridge !== nothing
            other_object = (group_bridge::Bridge).object1
            (enclosing_group1 === nothing || enclosing_group1 !== other_object) &&
                push!(result, group_bridge)
        end
    end
    return result
end

"""`(direction-incompatible-bridges ...)` — for a bridge between two spanning
groups, the sub-bridges that disagree with its direction mapping.

An Identity direction mapping wants the sub-bridges to run in parallel (left to
right on one side matches left to right on the other); an Opposite mapping
wants them crossed. The largest mutually consistent set survives, and the rest
are what this returns."""
function direction_incompatible_bridges(orientation::Symbol, group1::WSObject,
                                        group2::WSObject, direction_cm::ConceptMapping,
                                        net::Slipnet)
    label = direction_cm.label
    partition_function(pred1, pred2) = function (b1, b2)
        b1_pos1 = left_string_pos((b1::Bridge).object1)
        b1_pos2 = left_string_pos((b1::Bridge).object2)
        b2_pos1 = left_string_pos((b2::Bridge).object1)
        b2_pos2 = left_string_pos((b2::Bridge).object2)
        return (b1_pos1 < b2_pos1 && pred1(b1_pos2, b2_pos2)) ||
               (b1_pos1 > b2_pos1 && pred2(b1_pos2, b2_pos2))
    end
    subobject_bridges = intersect_eq(get_subobject_bridges(group1::Group, orientation),
                                     get_subobject_bridges(group2::Group, orientation))
    isempty(subobject_bridges) && return Any[]
    pred = label === net[:plato_identity] ? partition_function(<, >) :
           label === net[:plato_opposite] ? partition_function(>, <) :
           error("direction mapping is neither identity nor opposite")
    mutually_compatible_bridges = select_longest_list(partition_by(pred, subobject_bridges))
    return remq_elements(mutually_compatible_bridges, subobject_bridges)
end

"""`(get-incompatible-bridges)` for a proposed bridge."""
function get_incompatible_bridges(ctx::MetacatCtx, b::Bridge)
    net = ctx.net
    result = Any[other for other in bridge_list(ctx, b.bridge_type)
                 if incompatible_bridges(other::Bridge, b, net)]
    append!(result, group_incompatible_bridges(b.orientation, b.object1, b.object2))
    if both_spanning_groups(b.object1, b.object2)
        i = findfirst(cm -> is_cm_type(cm, net[:plato_direction_category]),
                      b.concept_mappings)
        i === nothing ||
            append!(result, direction_incompatible_bridges(b.orientation, b.object1,
                                                           b.object2,
                                                           b.concept_mappings[i], net))
    end
    return remq_duplicates(result)
end

"""`(get-incompatible-bond)` — the bond at the far end of the mapping whose
direction contradicts it. Only consulted when both objects sit at an edge of
their string, since otherwise "the bond beyond this object" is ambiguous."""
function get_incompatible_bond(b::Bridge, net::Slipnet)
    edge_bond(o::WSObject) = leftmost_in_string(o) ? o.right_bond : o.left_bond
    bond1 = edge_bond(b.object1)
    bond2 = edge_bond(b.object2)
    (bond1 === nothing || bond2 === nothing) && return nothing
    (directed(bond1::Bond) && directed(bond2::Bond)) || return nothing
    direction_category_cm =
        make_concept_mapping(net, bond1, net[:plato_direction_category],
                             (bond1::Bond).direction::Node,
                             bond2, net[:plato_direction_category],
                             (bond2::Bond).direction::Node)
    return incompatible_with_any_cm(direction_category_cm, b.concept_mappings, net) ?
           bond2 : nothing
end

"""`(get-incompatible-bridge object bridge-orientation)`, shared by bonds and
groups: `structure` is the bond or group whose direction is at stake.

The bridge is incompatible when its string-position mapping and this
structure's direction, read against the bond hanging off the bridge's other
end, cannot both hold."""
function get_incompatible_bridge(net::Slipnet, structure, direction::Union{Nothing,Node},
                                 object::WSObject, orientation::Symbol)
    bridge = get_bridge(object, orientation)
    bridge === nothing && return nothing
    i = findfirst(cm -> is_cm_type(cm, net[:plato_string_position_category]),
                  (bridge::Bridge).concept_mappings)
    i === nothing && return nothing
    string_position_cm = (bridge::Bridge).concept_mappings[i]
    other_object = get_other_object(bridge::Bridge, object)
    (leftmost_in_string(other_object) || rightmost_in_string(other_object)) || return nothing
    other_bond = leftmost_in_string(other_object) ? other_object.right_bond :
                                                    other_object.left_bond
    (other_bond !== nothing && directed(other_bond::Bond)) || return nothing
    cm = make_concept_mapping(net, structure, net[:plato_direction_category],
                              direction::Node, other_bond,
                              net[:plato_direction_category],
                              (other_bond::Bond).direction::Node)
    return incompatible_cms(cm, string_position_cm, net) ? bridge : nothing
end

"""`(get-incompatible-bridges bridge-orientation)` for a bond."""
function get_incompatible_bridges(b::Bond, orientation::Symbol, net::Slipnet)
    result = Any[]
    for object in (b.left_object, b.right_object)
        bridge = get_incompatible_bridge(net, b, b.direction, object, orientation)
        bridge === nothing || push!(result, bridge)
    end
    return result
end

# groups.ss has the same method over a group's constituents, used by
# group-builder. It arrives with the group codelets.

# --- building and breaking --------------------------------------------------

"""`(break-bridge bridge)`."""
function break_bridge!(ctx::MetacatCtx, b::Bridge)
    update_bridge!(b.object1, b.orientation, nothing)
    update_bridge!(b.object2, b.orientation, nothing)
    delete_bridge!(ctx, b)
    return b
end

"""`(reverse-direction-orientation? concept-mappings)` — the mapping wants the
two directed groups read against each other, and Opposite is not yet so active
that the model would rather say so outright."""
function reverse_direction_orientation(cms::Vector{ConceptMapping}, net::Slipnet)
    any(cm -> is_cm_type(cm, net[:plato_direction_category]), cms) || return false
    all(cm -> opposite_mapping(cm, net),
        ConceptMapping[cm for cm in cms if reversible_cm_type(cm, net)]) || return false
    return !fully_active(net[:plato_opposite])
end

"""`(propose-bridge bridge-orientation object1 flip1? object2 flip2?)`.

A string-spanning group contributes ALL of its descriptions rather than only
the relevant ones. That is a deliberate hack in the Scheme: without it a
momentarily inactive Direction-Category leaves a spanning bridge with no
direction mapping, so it is not judged incompatible with the sub-bridges it
contradicts, and both survive."""
function propose_bridge!(ctx::MetacatCtx, orientation::Symbol, object1::WSObject,
                         flip1::Bool, object2::WSObject, flip2::Bool)
    net = ctx.net
    obj1 = flip1 ? make_flipped_version(object1::Group, net) : object1
    obj2 = flip2 ? make_flipped_version(object2::Group, net) : object2
    descriptions_of(o) = string_spanning_group(o) ? o.descriptions :
                                                    get_relevant_descriptions(o)
    concept_mappings = all_possible_bridge_cms(orientation, obj1, descriptions_of(obj1),
                                               obj2, descriptions_of(obj2), net)
    proposed_bridge = make_bridge(orientation, obj1, obj2, concept_mappings, net,
                                  ctx.codelet_count)
    flip1 && mark_flipped_group1!(proposed_bridge, object1)
    flip2 && mark_flipped_group2!(proposed_bridge, object2)
    add_proposed_bridge!(ctx, proposed_bridge)
    proposed_bridge.proposal_level = PROPOSED
    for cm in concept_mappings
        activate_descriptions!(cm)
    end
    if orientation === :horizontal &&
       get_platonic_length(object1, net) !== get_platonic_length(object2, net)
        # The two sides are different sizes, so go looking for length
        # descriptions on both, and for a group on whichever side has none.
        activate_from_workspace!(net[:plato_length])
        for object in (object1, object2)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_description_scout],
                               VERY_HIGH_URGENCY,
                               Any[net[:plato_length], get_string(object)]),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
        end
        for (letter_side, group_side) in ((object1, object2), (object2, object1))
            (letter_side isa Letter && group_side isa Group) || continue
            group_category = (group_side::Group).group_category
            activate_from_workspace!(group_category)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_group_scout_category],
                               VERY_HIGH_URGENCY,
                               Any[group_category, get_string(letter_side)]),
                  ctx.codelet_count, ctx.rng, ctx.temperature)
        end
    end
    return proposed_bridge
end

# --- the codelets -----------------------------------------------------------

"""`(average l)` — 0 for the empty list, and an exact division otherwise."""
scheme_average(l) = isempty(l) ? 0 : sdiv(ssum(l), length(l))

"""The tail both bridge scouts share, from the spanning check onwards."""
function bridge_scout_tail(ctx::MetacatCtx, orientation::Symbol, object1::WSObject,
                           object2::WSObject)
    net = ctx.net
    lone_spanning_object(object1, object2) && return
    possible_cms = all_possible_bridge_cms(orientation,
                                           object1, get_relevant_descriptions(object1),
                                           object2, get_relevant_descriptions(object2), net)
    slippabilities = [temp_adjusted_probability(pct(cm_slippability(cm)))
                      for cm in possible_cms]
    # fizzles with the probability that at least one slippage cannot be made
    coin = random_real(ctx.rng, 1.0)
    coin < product([sub_from_1(s) for s in slippabilities]) && return
    # A bridge needs at least one distinguishing Identity/Opposite mapping to
    # justify it at all. In abc -> abcd, b--d has ObjCtgy:letter=>letter (not
    # distinguishing), StrPosCtgy:middle=>lmost and LettCtgy:b=>d, and should
    # not be built on the latter two alone. Thematic bridge scouts, which are
    # not ported, are the exception the Scheme allows here.
    any(cm -> distinguishing_identity_or_opposite(cm, net), possible_cms) || return
    flip2 = both_spanning_groups(object1, object2) &&
            reverse_direction_orientation(possible_cms, net)
    proposed_bridge = propose_bridge!(ctx, orientation, object1, false, object2, flip2)
    urgency = scheme_average([cm_strength(cm)
                              for cm in get_distinguishing_cms(proposed_bridge, net)])
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:bridge_evaluator], urgency, Any[proposed_bridge]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`bottom-up-bridge-scout` — picks the mapping to work on in inverse
proportion to how strong it already is, then an object from each of its two
strings by inter-string salience."""
function bottom_up_bridge_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    bridge_types = [:top, :vertical]
    weights = [sub_from_100(mapping_strength(ctx, t)) for t in bridge_types]
    bridge_type = stochastic_pick(ctx.rng, bridge_types, weights)::Symbol
    orientation = bridge_type_orientation(bridge_type)
    strings = bridge_strings(ctx, bridge_type)
    salience = inter_string_salience_getter(orientation)
    object1 = choose_object(ctx.rng, strings[1], salience)::WSObject
    object2 = choose_object(ctx.rng, strings[2], salience)::WSObject
    return bridge_scout_tail(ctx, orientation, object1, object2)
end

"""`important-object-bridge-scout` — picks an important object, one of its
relevant distinguishing descriptions, and then an object on the other side
carrying whatever descriptor the existing slippages map that one to. This is
how a slippage already found in one place propagates to another."""
function important_object_bridge_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    bridge_types = [:top, :vertical]
    weights = [sub_from_100(mapping_strength(ctx, t)) for t in bridge_types]
    bridge_type = stochastic_pick(ctx.rng, bridge_types, weights)::Symbol
    orientation = bridge_type_orientation(bridge_type)
    strings = bridge_strings(ctx, bridge_type)
    object1 = choose_object(ctx.rng, strings[1], o -> o.relative_importance)::WSObject
    object1_description =
        choose_relevant_distinguishing_description_by_depth(ctx.rng, object1, net)
    object1_description === nothing && return
    object1_descriptor = (object1_description::Description).descriptor
    slippages = all_slippages(ctx, bridge_type)
    i = findfirst(s -> s.descriptor1 === object1_descriptor, slippages)
    object2_descriptor = i === nothing ? object1_descriptor : slippages[i].descriptor2
    object2_candidates =
        WSObject[o for o in objects(strings[2])
                 if any(d -> d.descriptor === object2_descriptor,
                        get_relevant_descriptions(o))]
    isempty(object2_candidates) && return
    # NB a plain stochastic pick, with no temperature adjustment
    salience = inter_string_salience_getter(orientation)
    object2 = stochastic_pick(ctx.rng, object2_candidates,
                              [salience(o) for o in object2_candidates])::WSObject
    return bridge_scout_tail(ctx, orientation, object1, object2)
end

"""`bridge-evaluator` — decide stochastically, against temperature, whether the
bridge is strong enough to fight for."""
function bridge_evaluator(ctx::MetacatCtx, args::Vector{Any})
    proposed_bridge = args[1]::Bridge
    # No need to erase the bridge here: it went when its object was broken.
    (object_exists(ctx, original_object1(proposed_bridge)) &&
     object_exists(ctx, original_object2(proposed_bridge))) || return
    update_structure_strength!(proposed_bridge, ctx)
    strength = proposed_bridge.strength
    TEMPERATURE[] = ctx.temperature
    coin = random_real(ctx.rng, 1.0)
    if coin < sub_from_1(temp_adjusted_probability(pct(strength)))
        delete_proposed_bridge!(ctx, proposed_bridge)
        return
    end
    for cm in proposed_bridge.concept_mappings
        activate_descriptions!(cm)
    end
    proposed_bridge.proposal_level = EVALUATED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:bridge_builder], strength, Any[proposed_bridge]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`bridge-builder` — fight every incompatible structure in turn and, if the
bridge wins them all, break them and build it."""
function bridge_builder(ctx::MetacatCtx, args::Vector{Any})
    proposed_bridge = args[1]::Bridge
    net = ctx.net
    (object_exists(ctx, original_object1(proposed_bridge)) &&
     object_exists(ctx, original_object2(proposed_bridge))) || return
    delete_proposed_bridge!(ctx, proposed_bridge)
    orientation = proposed_bridge.orientation
    object1 = proposed_bridge.object1
    object2 = proposed_bridge.object2
    concept_mappings = proposed_bridge.concept_mappings
    # StrPosCtgy:middle descriptions can be deleted out from under a proposal
    all(t -> description_type_present(object1, t) && description_type_present(object2, t),
        get_concept_mapping_types(proposed_bridge)) || return
    if bridge_between(orientation, object1, object2)
        # An equivalent bridge is already there; donate any new mappings to it.
        for cm in concept_mappings
            activate_label!(cm)
        end
        existing_bridge = get_bridge(object1, orientation)::Bridge
        to_add = ConceptMapping[cm for cm in concept_mappings
                                if !concept_mapping_present(existing_bridge, cm)]
        isempty(to_add) || add_concept_mappings!(existing_bridge, to_add)
        return
    end
    all(cm_relevant, concept_mappings) || return

    incompatible_bridges_ = get_incompatible_bridges(ctx, proposed_bridge)
    if !isempty(incompatible_bridges_) &&
       !wins_all_fights(ctx.rng, ctx, proposed_bridge,
                        bridge_letter_span(proposed_bridge), incompatible_bridges_,
                        [bridge_letter_span(b::Bridge) for b in incompatible_bridges_])
        return
    end
    incompatible_bond =
        ((leftmost_in_string(object1) || rightmost_in_string(object1)) &&
         (leftmost_in_string(object2) || rightmost_in_string(object2))) ?
        get_incompatible_bond(proposed_bridge, net) : nothing
    if incompatible_bond !== nothing &&
       !wins_fight(ctx.rng, ctx, proposed_bridge, 3, incompatible_bond::Bond, 2)
        return
    end
    incompatible_group = incompatible_bond === nothing ? nothing :
                         (incompatible_bond::Bond).enclosing_group
    if incompatible_group !== nothing &&
       !wins_fight(ctx.rng, ctx, proposed_bridge, 1, incompatible_group::Group, 1)
        return
    end
    if proposed_bridge.flipped_group1 &&
       !wins_fight(ctx.rng, ctx, proposed_bridge, 1,
                   (proposed_bridge.original_group1)::Group, 1)
        return
    end
    if proposed_bridge.flipped_group2 &&
       !wins_fight(ctx.rng, ctx, proposed_bridge, 1,
                   (proposed_bridge.original_group2)::Group, 1)
        return
    end

    for bridge in incompatible_bridges_
        break_bridge!(ctx, bridge::Bridge)
    end
    incompatible_bond === nothing || break_bond!(incompatible_bond::Bond)
    incompatible_group === nothing || break_group!(incompatible_group::Group, net, ctx)
    proposed_bridge.flipped_group1 &&
        replace_with_flipped_group!(ctx, (proposed_bridge.original_group1)::Group,
                                    object1::Group)
    proposed_bridge.flipped_group2 &&
        replace_with_flipped_group!(ctx, (proposed_bridge.original_group2)::Group,
                                    object2::Group)
    build_bridge!(ctx, proposed_bridge, net)
    # boost-themespace-activations goes here; themes are not ported.
    return
end

"""Swap a built group for the flipped version the winning bridge reads it as:
the original and its bonds go, and the flipped group's bonds are built in
their place."""
function replace_with_flipped_group!(ctx::MetacatCtx, original_group::Group,
                                     flipped_group::Group)
    break_group!(original_group, ctx.net, ctx)
    for bond in original_group.constituent_bonds
        break_bond!(bond::Bond)
    end
    for bond in flipped_group.constituent_bonds
        build_bond!(bond::Bond)
    end
    build_group!(flipped_group, ctx.net, ctx)
    return flipped_group
end

# `propose-bridge` also posts a top-down-description-scout, which lives in
# codelets_descriptions.jl. top-down-group-scout:category belongs to groups.ss
# and is not ported yet; a stub that raises keeps the gap visible instead of
# letting it diverge silently.
not_yet_ported(name) = (ctx, args) -> error("$name is not ported yet")

register_codelet_type!(:bottom_up_bridge_scout, bottom_up_bridge_scout)
register_codelet_type!(:important_object_bridge_scout, important_object_bridge_scout)
register_codelet_type!(:bridge_evaluator, bridge_evaluator)
register_codelet_type!(:bridge_builder, bridge_builder)
register_codelet_type!(:top_down_group_scout_category,
                       not_yet_ported("top-down-group-scout:category"))
