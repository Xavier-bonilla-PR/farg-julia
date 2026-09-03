# The bridge codelet pipeline, ported from bridges.ss.
#
# A bridge is a correspondence between an object in one string and an object in
# another. Two scouts look for one: the bottom-up scout picks both ends by
# inter-string salience, while the important-object scout picks a salient
# description on one side and hunts for an object on the other side carrying
# the descriptor that description slips to. Both refuse to propose a bridge
# with no distinguishing identity-or-opposite concept mapping, which is what
# stops the model bridging objects that have no a priori reason to correspond.
#
# The builder fights incompatible bridges, then at most one incompatible bond,
# then that bond's enclosing group, then the unflipped originals of any group
# it wants to flip. Flipping is what lets >abc> map onto <cba< read backwards:
# the group is rebuilt with its bonds reversed, and the original broken.
#
# Deferred, and marked where they arise: the trace's concept-mapping monitoring
# and graphics. NOT ported: propose-singleton-group and
# try-to-propose-singleton-group, which bridges.ss defines and nothing in the
# model ever calls.

# --- flipped groups ---------------------------------------------------------

"""`(make-flipped-version)` for a group — the same objects read the other way
round, with every bond flipped and the group and direction categories replaced
by their opposites. A sameness group reads the same either way, so it is its
own flipped version.

NB the flipped group keeps the ORIGINAL group's id, so that bridges to it land
in the same slot of the proposed-bridge table as bridges to the unflipped
version."""
function make_flipped_version(g::Group, net::Slipnet)
    g.group_category === net[:plato_samegrp] && return g
    flipped_bonds = Any[make_flipped_version(b::Bond, net) for b in g.constituent_bonds]
    flipped = make_group(net, g.string,
                         get_related_node(g.group_category, net[:plato_opposite],
                                          net[:plato_identity])::Node,
                         g.group_bond_facet,
                         get_related_node(g.direction::Node, net[:plato_opposite],
                                          net[:plato_identity]),
                         g.left_object, g.right_object, g.constituent_objects,
                         flipped_bonds)
    flipped.id_num = g.id_num
    description_type_present(g, net[:plato_length]) &&
        attach_length_description!(flipped, net)
    return flipped
end

# --- incompatible structures ------------------------------------------------

"""`(get-subobject-bridges bridge-orientation)` — the bridges of that
orientation belonging to the group's immediate constituents."""
get_subobject_bridges(g::Group, orientation::Symbol) =
    Bridge[b for b in (get_bridge(o, orientation) for o in g.constituent_objects)
           if b !== nothing]
get_subobject_bridges(::Letter, ::Symbol) = Bridge[]
"""For a string: the bridges belonging to its TOP-LEVEL objects, which is what
a rule clause about the whole string rests on."""
get_subobject_bridges(s::WorkspaceString, orientation::Symbol) =
    Bridge[b for b in (get_bridge(o, orientation) for o in get_top_level_objects(s))
           if b !== nothing]

"""`(group-incompatible-bridges bridge-orientation object1 object2)` — bridges
that cross this one because they involve a part of it, or the whole of which it
is a part."""
function group_incompatible_bridges(orientation::Symbol, object1::WSObject,
                                    object2::WSObject)
    result = Bridge[]
    if object1 isa Group
        subs = get_subobject_bridges(object1::Group, orientation)
        append!(result, object2 isa Letter ? subs :
                        Bridge[b for b in subs
                               if !top_level_member(object2::Group, b.object2)])
    end
    if object2 isa Group
        subs = get_subobject_bridges(object2::Group, orientation)
        append!(result, object1 isa Letter ? subs :
                        Bridge[b for b in subs
                               if !top_level_member(object1::Group, b.object1)])
    end
    g1 = object1.enclosing_group
    g2 = object2.enclosing_group
    if g1 !== nothing
        gb = get_bridge(g1::WSObject, orientation)
        if gb !== nothing && !(g2 !== nothing && g2 === (gb::Bridge).object2)
            push!(result, gb::Bridge)
        end
    end
    if g2 !== nothing
        gb = get_bridge(g2::WSObject, orientation)
        if gb !== nothing && !(g1 !== nothing && g1 === (gb::Bridge).object1)
            push!(result, gb::Bridge)
        end
    end
    return result
end


"""`(select-longest-list l)` — `select-extreme` takes the FIRST entry attaining
the maximum, via assv on the (length, list) pairs."""
function select_longest_list(l)
    isempty(l) && return eltype(l)()
    lengths = [length(x) for x in l]
    return l[findfirst(==(maximum(lengths)), lengths)]
end

"""`(direction-incompatible-bridges ...)` — among the bridges between the two
spanning groups' constituents, keep the largest mutually consistent set (all
running the same way, or all crossing, depending on the direction mapping) and
call the rest incompatible."""
function direction_incompatible_bridges(orientation::Symbol, group1::Group, group2::Group,
                                        direction_cm::ConceptMapping, net::Slipnet)
    label = direction_cm.label
    consistent = if label === net[:plato_identity]
        (b1, b2) -> (left_string_pos(b1.object1) < left_string_pos(b2.object1) &&
                     left_string_pos(b1.object2) < left_string_pos(b2.object2)) ||
                    (left_string_pos(b1.object1) > left_string_pos(b2.object1) &&
                     left_string_pos(b1.object2) > left_string_pos(b2.object2))
    elseif label === net[:plato_opposite]
        (b1, b2) -> (left_string_pos(b1.object1) < left_string_pos(b2.object1) &&
                     left_string_pos(b1.object2) > left_string_pos(b2.object2)) ||
                    (left_string_pos(b1.object1) > left_string_pos(b2.object1) &&
                     left_string_pos(b1.object2) < left_string_pos(b2.object2))
    else
        (b1, b2) -> false
    end
    subs1 = get_subobject_bridges(group1, orientation)
    subs2 = get_subobject_bridges(group2, orientation)
    subobject_bridges = Bridge[b for b in subs1 if any(x -> x === b, subs2)]
    keep = select_longest_list(spartition(consistent, subobject_bridges))
    return Bridge[b for b in subobject_bridges if !any(x -> x === b, keep)]
end

"""`(get-incompatible-bridges)` for a bridge."""
function get_incompatible_bridges(b::Bridge, ctx::MetacatCtx)
    net = ctx.net
    result = Bridge[other for other in get_bridges(ctx, b.bridge_type)
                    if incompatible_bridges(other, b, net)]
    append!(result, group_incompatible_bridges(b.orientation, b.object1, b.object2))
    if string_spanning_group(b.object1) && string_spanning_group(b.object2)
        i = findfirst(cm -> is_cm_type(cm, net[:plato_direction_category]),
                      b.concept_mappings)
        i === nothing ||
            append!(result, direction_incompatible_bridges(b.orientation,
                                                           b.object1::Group,
                                                           b.object2::Group,
                                                           b.concept_mappings[i], net))
    end
    # remq-duplicates keeps the LAST of each duplicate group
    return Bridge[x for (k, x) in enumerate(result)
                  if !any(y -> y === x, result[(k + 1):end])]
end

"""`(get-incompatible-bridge object bridge-orientation)`.

Groups and bonds ask the same question of a bridge, in the same words: take the
bridge's string-position mapping, and the direction mapping between MY
direction and the direction of the bond running inward from the far end of the
bridge. If those two disagree, the bridge contradicts me. The only difference
between the group and bond versions in groups.ss and bonds.ss is which object
supplies the direction."""
function get_incompatible_bridge(self, direction::Union{Nothing,Node}, object::WSObject,
                                 orientation::Symbol, net::Slipnet)
    bridge = get_bridge(object, orientation)
    bridge === nothing && return nothing
    b = bridge::Bridge
    i = findfirst(cm -> is_cm_type(cm, net[:plato_string_position_category]),
                  b.concept_mappings)
    i === nothing && return nothing
    string_position_cm = b.concept_mappings[i]
    other_object = b.object1 === object ? b.object2 : b.object1
    (leftmost_in_string(other_object) || rightmost_in_string(other_object)) ||
        return nothing
    other_bond = leftmost_in_string(other_object) ? other_object.right_bond :
                                                    other_object.left_bond
    (other_bond !== nothing && directed(other_bond::Bond)) || return nothing
    direction_cm = make_concept_mapping(net, self, net[:plato_direction_category],
                                        direction::Node,
                                        other_bond, net[:plato_direction_category],
                                        (other_bond::Bond).direction::Node)
    return incompatible_cms(direction_cm, string_position_cm, net) ? b : nothing
end

"""`(get-incompatible-bridges bridge-orientation)` for a GROUP — the bridges its
constituents are part of that contradict the group's own direction. Only a
directed group has any."""
function get_incompatible_bridges(g::Group, orientation::Symbol, net::Slipnet)
    g.direction === nothing && return Bridge[]
    result = Bridge[]
    for o in g.constituent_objects
        b = get_incompatible_bridge(g, g.direction, o, orientation, net)
        b === nothing || push!(result, b::Bridge)
    end
    return result
end

"""`(get-incompatible-bridges bridge-orientation)` for a BOND — a bridge at
either end of the bond whose string-position mapping disagrees with the way the
bond points."""
function get_incompatible_bridges(bond::Bond, orientation::Symbol, net::Slipnet)
    result = Bridge[]
    for o in (bond.left_object, bond.right_object)
        b = get_incompatible_bridge(bond, bond.direction, o, orientation, net)
        b === nothing || push!(result, b::Bridge)
    end
    return result
end

"""`(get-incompatible-bond)` — a bridge between two string-edge objects is
incompatible with the bonds running inward from those edges when those bonds
point in mutually inconsistent directions."""
function get_incompatible_bond(b::Bridge, net::Slipnet)
    bond1 = leftmost_in_string(b.object1) ? b.object1.right_bond : b.object1.left_bond
    bond2 = leftmost_in_string(b.object2) ? b.object2.right_bond : b.object2.left_bond
    (bond1 === nothing || bond2 === nothing) && return nothing
    (directed(bond1::Bond) && directed(bond2::Bond)) || return nothing
    dc = make_concept_mapping(net, bond1, net[:plato_direction_category],
                              (bond1::Bond).direction::Node,
                              bond2, net[:plato_direction_category],
                              (bond2::Bond).direction::Node)
    return incompatible_with_any_cm(dc, b.concept_mappings, net) ? bond2 : nothing
end

# --- building and breaking --------------------------------------------------

"""`(build-bridge bridge-orientation bridge)`. The length concept mapping is
added AFTER the ObjCtgy one, and deliberately does not activate Length."""
function build_bridge!(b::Bridge, ctx::MetacatCtx)
    net = ctx.net
    update_bridge!(b.object1, b.orientation, b)
    update_bridge!(b.object2, b.orientation, b)
    add_bridge!(ctx, b)
    if b.orientation === :horizontal &&
       !any(cm -> is_cm_type(cm, net[:plato_object_category]), b.concept_mappings)
        # every horizontal bridge needs an ObjCtgy CM, relevant or not, so that
        # rule abstraction does not go wrong later
        cm = make_concept_mapping(net, b.object1, net[:plato_object_category],
                                  get_descriptor_for(b.object1,
                                                     net[:plato_object_category])::Node,
                                  b.object2, net[:plato_object_category],
                                  get_descriptor_for(b.object2,
                                                     net[:plato_object_category])::Node)
        add_concept_mapping!(b, cm)
        is_slippage(cm) && add_symmetric_slippage!(b, cm, net)
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
    if b.orientation === :horizontal
        length1 = get_platonic_length(b.object1, net)
        length2 = get_platonic_length(b.object2, net)
        if length1 !== length2 &&
           !any(cm -> is_cm_type(cm, net[:plato_length]), b.all_concept_mappings)
            add_concept_mapping!(b, make_concept_mapping(net, b.object1,
                                                         net[:plato_length], length1::Node,
                                                         b.object2, net[:plato_length],
                                                         length2::Node))
        end
    end
    for cm in b.concept_mappings
        activate_label!(cm)
    end
    b.proposal_level = BUILT
    return b
end

"""`(break-bridge bridge)`."""
function break_bridge!(b::Bridge, ctx::MetacatCtx)
    update_bridge!(b.object1, b.orientation, nothing)
    update_bridge!(b.object2, b.orientation, nothing)
    delete_bridge!(ctx, b)
    return b
end

# --- proposing --------------------------------------------------------------

"""`(reverse-direction-orientation? concept-mappings)` — the two spanning groups
map by opposite direction throughout, and Opposite is not fully active, so the
mapping is better expressed by flipping one group than by slipping."""
reverse_direction_orientation(cms, net::Slipnet) =
    any(cm -> is_cm_type(cm, net[:plato_direction_category]), cms) &&
    all(cm -> opposite_mapping(cm, net),
        ConceptMapping[cm for cm in cms if reversible_cm_type(cm, net)]) &&
    !fully_active(net[:plato_opposite])

"""`(propose-bridge bridge-orientation object1 flip1? object2 flip2?)`.

The descriptions used are the RELEVANT ones, except on a string-spanning group,
where all of them are used — a hack in the Scheme to stop a momentarily
inactive Direction-Category leaving a spanning bridge without the very concept
mapping that would make it incompatible with the letter-to-letter bridges it
ought to replace."""
function propose_bridge!(ctx::MetacatCtx, orientation::Symbol, object1::WSObject,
                         flip1::Bool, object2::WSObject, flip2::Bool)
    net = ctx.net
    obj1 = flip1 ? make_flipped_version(object1::Group, net) : object1
    obj2 = flip2 ? make_flipped_version(object2::Group, net) : object2
    cms = all_possible_bridge_cms(orientation,
                                  obj1, string_spanning_group(obj1) ? obj1.descriptions :
                                        get_relevant_descriptions(obj1),
                                  obj2, string_spanning_group(obj2) ? obj2.descriptions :
                                        get_relevant_descriptions(obj2), net)
    b = make_bridge(orientation, obj1, obj2, cms, net, ctx.codelet_count)
    if flip1
        b.flipped_group1 = true
        b.original_group1 = object1
    end
    if flip2
        b.flipped_group2 = true
        b.original_group2 = object2
    end
    add_proposed_bridge!(ctx, b)
    b.proposal_level = PROPOSED
    for cm in cms
        activate_descriptions!(cm)
    end
    # A horizontal bridge between objects of different length wants length
    # descriptions on both sides, and a group on the side that has only a letter.
    if orientation === :horizontal &&
       get_platonic_length(object1, net) !== get_platonic_length(object2, net)
        activate_from_workspace!(net[:plato_length])
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:top_down_description_scout], VERY_HIGH_URGENCY,
                           Any[net[:plato_length], get_string(object1)]),
              ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:top_down_description_scout], VERY_HIGH_URGENCY,
                           Any[net[:plato_length], get_string(object2)]),
              ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
        if object1 isa Letter && object2 isa Group
            activate_from_workspace!((object2::Group).group_category)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_group_scout_category],
                               VERY_HIGH_URGENCY,
                               Any[(object2::Group).group_category, get_string(object1)]),
                  ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
        end
        if object1 isa Group && object2 isa Letter
            activate_from_workspace!((object1::Group).group_category)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[:top_down_group_scout_category],
                               VERY_HIGH_URGENCY,
                               Any[(object1::Group).group_category, get_string(object2)]),
                  ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
        end
    end
    return b
end

# --- the codelets -----------------------------------------------------------

"""The bridge type both scouts pick, weighted by how weak that mapping still
is."""
function choose_bridge_type(ctx::MetacatCtx)
    types = Symbol[:top, :vertical]
    weights = [sub_from_100(get_mapping_strength(ctx, t)) for t in types]
    return stochastic_pick(ctx.rng, types, weights)::Symbol
end

"""The tail both scouts share once they have two objects: check the slippages
are makeable, insist on a distinguishing identity-or-opposite mapping, propose,
and post an evaluator."""
function bridge_scout_tail(ctx::MetacatCtx, orientation::Symbol,
                           object1::WSObject, object2::WSObject)
    net = ctx.net
    lone_spanning_object(object1, object2) && return
    possible_cms = all_possible_bridge_cms(orientation,
                                           object1, get_relevant_descriptions(object1),
                                           object2, get_relevant_descriptions(object2), net)
    slippabilities = [temp_adjusted_probability(pct(cm_slippability(cm)))
                      for cm in possible_cms]
    coin = random_real(ctx.rng, 1.0)
    coin < prod(Float64[sub_from_1(s) for s in slippabilities]; init = 1.0) && return
    any(cm -> distinguishing_identity_or_opposite(cm, net), possible_cms) || return
    flip2 = string_spanning_group(object1) && string_spanning_group(object2) &&
            reverse_direction_orientation(possible_cms, net)
    b = propose_bridge!(ctx, orientation, object1, false, object2, flip2)
    dcms = get_distinguishing_cms(b, net)
    urgency = isempty(dcms) ? 0 : sdiv(ssum([cm_strength(cm) for cm in dcms]), length(dcms))
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:bridge_evaluator], urgency, Any[b]),
          ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
    return
end

"""`bottom-up-bridge-scout` — both ends chosen by inter-string salience."""
function bottom_up_bridge_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    bridge_type = choose_bridge_type(ctx)
    orientation = bridge_type_to_orientation(bridge_type)
    s1, s2 = bridge_type_strings(ctx, bridge_type)
    salience = orientation === :horizontal ? :horizontal_inter_string_salience :
                                             :vertical_inter_string_salience
    object1 = choose_object(ctx.rng, s1, salience)
    object2 = choose_object(ctx.rng, s2, salience)
    (object1 === nothing || object2 === nothing) && return
    return bridge_scout_tail(ctx, orientation, object1::WSObject, object2::WSObject)
end

"""`important-object-bridge-scout` — start from an important object's deepest
distinguishing description, follow any slippage already in play for that
descriptor, and look for an object on the other side that has it."""
function important_object_bridge_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    bridge_type = choose_bridge_type(ctx)
    orientation = bridge_type_to_orientation(bridge_type)
    s1, s2 = bridge_type_strings(ctx, bridge_type)
    object1 = choose_object(ctx.rng, s1, :relative_importance)
    object1 === nothing && return
    d = choose_relevant_distinguishing_description_by_depth(ctx.rng, object1::WSObject, net)
    d === nothing && return
    object1_descriptor = (d::Description).descriptor
    slippages = get_all_slippages(ctx, bridge_type)
    i = findfirst(s -> s.descriptor1 === object1_descriptor, slippages)
    object2_descriptor = i === nothing ? object1_descriptor : slippages[i].descriptor2
    candidates = WSObject[o for o in objects(s2)
                          if any(dd -> dd.descriptor === object2_descriptor,
                                 get_relevant_descriptions(o))]
    isempty(candidates) && return
    salience = orientation === :horizontal ? :horizontal_inter_string_salience :
                                             :vertical_inter_string_salience
    object2 = stochastic_pick(ctx.rng, candidates,
                              [getfield(o, salience) for o in candidates])
    return bridge_scout_tail(ctx, orientation, object1::WSObject, object2::WSObject)
end

"""`(choose-relevant-distinguishing-description-by-depth)`."""
function choose_relevant_distinguishing_description_by_depth(rng::PyRandom, o::WSObject,
                                                             net::Slipnet)
    ds = Description[d for d in o.descriptions
                     if distinguishing_descriptor(net, o, d.descriptor) && relevant(d)]
    isempty(ds) && return nothing
    return stochastic_pick(rng, ds, [conceptual_depth(d) for d in ds])
end

"""`bridge-evaluator`."""
function bridge_evaluator(ctx::MetacatCtx, args::Vector{Any})
    b = args[1]::Bridge
    (object_exists(ctx, original_object1(b)) && object_exists(ctx, original_object2(b))) ||
        return
    TEMPERATURE[] = ctx.temperature
    update_structure_strength!(b, ctx.net, get_all_bridges(ctx), ctx.themespace)
    strength = b.strength
    coin = random_real(ctx.rng, 1.0)
    if coin < sub_from_1(temp_adjusted_probability(pct(strength)))
        delete_proposed_bridge!(ctx, b)
        return
    end
    for cm in b.concept_mappings
        activate_descriptions!(cm)
    end
    b.proposal_level = EVALUATED
    post!(ctx.coderack, make_codelet(CODELET_TYPES[:bridge_builder], strength, Any[b]),
          ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
    return
end

"""`bridge-builder` — fight everything incompatible, flip any groups that need
flipping, and build."""
function bridge_builder(ctx::MetacatCtx, args::Vector{Any})
    b = args[1]::Bridge
    net = ctx.net
    (object_exists(ctx, original_object1(b)) && object_exists(ctx, original_object2(b))) ||
        return
    delete_proposed_bridge!(ctx, b)
    object1 = b.object1
    object2 = b.object2
    # StrPos:middle descriptions can be deleted out from under a proposed bridge
    all(t -> description_type_present(object1, t) && description_type_present(object2, t),
        Node[cm_type(cm) for cm in b.concept_mappings]) || return
    if bridge_between(b.orientation, object1, object2)
        # the bridge is already there; donate any concept mappings it lacks
        for cm in b.concept_mappings
            activate_label!(cm)
        end
        existing = get_bridge(object1, b.orientation)::Bridge
        to_add = ConceptMapping[cm for cm in b.concept_mappings
                                if !any(x -> cms_equal(x, cm), existing.all_concept_mappings)]
        isempty(to_add) || add_concept_mappings!(existing, to_add)
        return
    end
    all(cm_relevant, b.concept_mappings) || return
    incompatible = get_incompatible_bridges(b, ctx)
    if !isempty(incompatible) &&
       !wins_all_fights(ctx.rng, ctx, b, get_letter_span(b),
                        incompatible, [get_letter_span(x) for x in incompatible])
        return
    end
    incompatible_bond =
        ((leftmost_in_string(object1) || rightmost_in_string(object1)) &&
         (leftmost_in_string(object2) || rightmost_in_string(object2))) ?
        get_incompatible_bond(b, net) : nothing
    if incompatible_bond !== nothing &&
       !wins_fight(ctx.rng, ctx, b, 3, incompatible_bond::Bond, 2)
        return
    end
    incompatible_group = incompatible_bond === nothing ? nothing :
                         (incompatible_bond::Bond).enclosing_group
    if incompatible_group !== nothing &&
       !wins_fight(ctx.rng, ctx, b, 1, incompatible_group::Group, 1)
        return
    end
    if b.flipped_group1 &&
       !wins_fight(ctx.rng, ctx, b, 1, (b.original_group1)::Group, 1)
        return
    end
    if b.flipped_group2 &&
       !wins_fight(ctx.rng, ctx, b, 1, (b.original_group2)::Group, 1)
        return
    end
    for other in incompatible
        break_bridge!(other, ctx)
    end
    incompatible_bond === nothing || break_bond!(incompatible_bond::Bond, net)
    incompatible_group === nothing || break_group!(incompatible_group::Group, net, ctx)
    b.flipped_group1 && flip_group!(ctx, (b.original_group1)::Group, object1::Group)
    b.flipped_group2 && flip_group!(ctx, (b.original_group2)::Group, object2::Group)
    build_bridge!(b, ctx)
    # after the build, because building may add bond concept mappings (and, for
    # a horizontal bridge, an ObjCtgy one) that the themes should see
    boost_themespace_activations!(b, ctx.themespace, net)
    return
end

"""Replace a built group by its flipped version: break the original and its
bonds, then build the flipped bonds and the flipped group."""
function flip_group!(ctx::MetacatCtx, original::Group, flipped::Group)
    net = ctx.net
    break_group!(original, net, ctx)
    for bond in original.constituent_bonds
        break_bond!(bond::Bond, net)
    end
    for bond in flipped.constituent_bonds
        build_bond!(bond::Bond, net)
    end
    build_group!(flipped, net, ctx)
    return ctx
end

register_codelet_type!(:bottom_up_bridge_scout, bottom_up_bridge_scout)
register_codelet_type!(:important_object_bridge_scout, important_object_bridge_scout)
register_codelet_type!(:bridge_evaluator, bridge_evaluator)
register_codelet_type!(:bridge_builder, bridge_builder)
