# The thematic codelets, ported from themes.ss.
#
# These are bridge codelets in all but name, which is why they live here rather
# than with the themespace: where the ordinary bridge scouts look for two
# objects that happen to correspond, THEMATIC-BRIDGE-SCOUT starts from what the
# themespace currently believes the mapping is, and goes looking for a bridge
# that would bear that belief out. It is the one place where the model's
# self-watching reaches back down and changes what it perceives.
#
# Only POSITIVE themes exert this pressure. A negative theme ("letter-category
# does NOT map by identity") can weigh on a structure's strength, but is far too
# unspecific to scout for: it would have the model building bridges to satisfy
# "anything but identity".

"""`(get-possible-bridge-objects bridge-type)` — the objects of both strings the
bridge type maps between."""
function get_possible_bridge_objects(ctx::MetacatCtx, bridge_type::Symbol)
    s1, s2 = bridge_type_strings(ctx, bridge_type)
    return vcat(objects(s1), objects(s2))
end

"""`(get-other-string string bridge-orientation)`."""
function get_other_string(ctx::MetacatCtx, s::WorkspaceString, orientation::Symbol)
    t = s.string_type
    t === :initial && return orientation === :horizontal ? ctx.modified_string :
                                                           ctx.target_string
    t === :modified && return ctx.initial_string
    # The target string has TWO partners in justify mode: the initial string
    # vertically, and the answer string horizontally.
    t === :target && return orientation === :horizontal ?
                            ctx.answer_string::WorkspaceString : ctx.initial_string
    return ctx.target_string                                    # :answer
end

"""`(all-description-types-present? description-types)`."""
all_description_types_present(o::WSObject, types) =
    all(t -> description_type_present(o, t), types)

"""`(get-num-of-spanning-bridges)` — only a whole-string object has any."""
get_num_of_spanning_bridges(o::WSObject) =
    spans_whole_string(o) ? count(!isnothing, (o.horizontal_bridge, o.vertical_bridge)) : 0

"""`(flipped object)`."""
flipped(o::WSObject, net::Slipnet) = make_flipped_version(o::Group, net)

"""`(conditions-for-bridge chosen-object from-object? themes)` — for a candidate
partner, which of the two objects (if any) would have to be turned around for
the themes to be satisfied.

Returns `nothing` when no bridge is possible at all, and a possibly EMPTY list
of objects to flip otherwise. The empty list is a success, not a failure: the
Scheme distinguishes `'()` from `#f` here and so must the port."""
function conditions_for_bridge(ctx::MetacatCtx, chosen_object::WSObject, from_object::Bool,
                               themes, other_object::WSObject)
    net = ctx.net
    object1 = from_object ? chosen_object : other_object
    object2 = from_object ? other_object : chosen_object
    supports(a, b) = themes_support(a, b, themes, net)
    lone_spanning_object(object1, object2) && return nothing
    if !(string_spanning_group(object1) && string_spanning_group(object2))
        return supports(object1, object2) ? WSObject[] : nothing
    end
    supports(object1, object2) && return WSObject[]
    # Don't always try to flip object1 first: bias toward turning around
    # whichever object has fewer spanning bridges riding on it.
    num1 = get_num_of_spanning_bridges(object1)
    num2 = get_num_of_spanning_bridges(object2)
    object1_bias = num1 > num2 ? pct(20) : num1 < num2 ? pct(80) : pct(50)
    if prob(ctx.rng, object1_bias)
        supports(flipped(object1, net), object2) && return WSObject[object1]
        supports(object1, flipped(object2, net)) && return WSObject[object2]
        supports(flipped(object1, net), flipped(object2, net)) &&
            return WSObject[object1, object2]
        return nothing
    else
        supports(object1, flipped(object2, net)) && return WSObject[object2]
        supports(flipped(object1, net), object2) && return WSObject[object1]
        supports(flipped(object1, net), flipped(object2, net)) &&
            return WSObject[object1, object2]
        return nothing
    end
end

"""`(propose-description-based-on-theme object theme)` — when the chosen object
lacks a description in a theme's dimension, try to give it one, so that the
theme has something to weigh on. NB the proposal level is set BEFORE the
descriptor is activated here, the other way round from `propose-description`."""
function propose_description_based_on_theme!(ctx::MetacatCtx, object::WSObject,
                                             theme::BridgeTheme)
    dimension = theme.dimension
    possible_descriptors = get_possible_descriptors(dimension, object, ctx.net)
    isempty(possible_descriptors) && return ctx
    chosen_descriptor = stochastic_pick(ctx.rng, possible_descriptors,
                                        [d.activation for d in possible_descriptors])
    d = make_description(object, dimension, chosen_descriptor, ctx.codelet_count)
    d.proposal_level = PROPOSED
    activate_from_workspace!(chosen_descriptor)
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:description_evaluator],
                       absolute_activation(theme), Any[d]),
          ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
    return ctx
end

"""`(look-for-auxiliary-slippages proposed-bridge)` — a slippage the bridge
already makes may drag others along with it: if `leftmost` slips to `rightmost`,
then whatever else is linked to `leftmost` may slip the same way. Each candidate
is taken with probability equal to the label's degree of association.

Returns false when the codelet must FIZZLE. The Scheme calls `(fizzle)` from
inside this helper, which escapes the whole codelet, not just the helper — so a
new description added here ends the scout rather than continuing to the
bridge."""
function look_for_auxiliary_slippages!(ctx::MetacatCtx, b::Bridge)
    net = ctx.net
    for slippage in get_slippages(b)
        object1 = slippage.object1
        object2 = slippage.object2
        cm_t = cm_type(slippage)
        descriptor1 = slippage.descriptor1
        label = slippage.label
        linked_instance_nodes = Node[l.to_node for l in outgoing_links(descriptor1)
                                     if is_instance(l.to_node) &&
                                        get_category(l.to_node) !== cm_t]
        for node in linked_instance_nodes
            new_cm_type = get_category(node)::Node
            related_node = get_related_node(node, label, net[:plato_identity])
            (!cm_type_present(b, new_cm_type) && related_node !== nothing &&
             possible_descriptor(node, object1, net) &&
             possible_descriptor(related_node::Node, object2, net)) || continue
            make_slippage = prob(ctx.rng, pct(degree_of_assoc(label::Node)))
            make_slippage || continue
            new_slippage = make_concept_mapping(net, object1, new_cm_type, node,
                                                object2, new_cm_type, related_node::Node)
            if !description_type_present(object1, new_cm_type)
                build_description!(make_description(object1, new_cm_type, node,
                                                    ctx.codelet_count), net)
                return false
            end
            if !description_type_present(object2, new_cm_type)
                build_description!(make_description(object2, new_cm_type,
                                                    related_node::Node, ctx.codelet_count),
                                   net)
                return false
            end
            add_concept_mapping!(b, new_slippage)
        end
    end
    return true
end

"""`thematic-bridge-scout` — pick a bridge type weighted by how strongly its
themes feel and how weak that mapping still is, pick one positive theme per
cluster that clears a probability test on its own activation, then look for two
objects a bridge between which would satisfy them."""
function thematic_bridge_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    ts = ctx.themespace
    SELF_WATCHING_ENABLED[] || return
    active_types = get_active_bridge_theme_types(ts)
    isempty(active_types) && return
    weights = [get_max_positive_theme_activation(ts, t) *
               sub_from_100(get_mapping_strength(ctx, theme_type_to_bridge_type(t)))
               for t in active_types]
    theme_type = stochastic_pick(ctx.rng, active_types, weights)::Symbol
    bridge_type = theme_type_to_bridge_type(theme_type)
    orientation = bridge_type_to_orientation(bridge_type)
    clusters = ThemeCluster[c for c in get_clusters(ts, theme_type)
                            if prob(ctx.rng,
                                    sq(pct(get_max_positive_theme_activation(c))))]
    themes = BridgeTheme[t for t in (pick_positive_theme(ctx.rng, c) for c in clusters)
                         if t !== nothing]
    isempty(themes) && return
    objs = get_possible_bridge_objects(ctx, bridge_type)
    salience = orientation === :horizontal ? :horizontal_inter_string_salience :
                                             :vertical_inter_string_salience
    chosen_object = stochastic_pick(ctx.rng, objs, [getfield(o, salience) for o in objs])
    chosen_object === nothing && return
    applicable = BridgeTheme[t for t in themes
                             if description_type_present(chosen_object::WSObject, t.dimension)]
    non_applicable = BridgeTheme[t for t in themes if !any(x -> x === t, applicable)]
    chosen_string = get_string(chosen_object::WSObject)
    if !isempty(non_applicable)
        for theme in non_applicable
            # Special case: if StringPos is impossible for the chosen object,
            # don't propose a bridge with it at all. In iijjkk->aabbdd with
            # StringPos:iden and ObjCtgy:iden clamped, spurious i--b bridges get
            # proposed without this.
            if theme.dimension === net[:plato_string_position_category] &&
               !description_possible(net[:plato_string_position_category],
                                     chosen_object::WSObject, net)
                return
            end
            propose_description_based_on_theme!(ctx, chosen_object::WSObject, theme)
        end
    end
    other_string = get_other_string(ctx, chosen_string, orientation)
    dimensions = Node[t.dimension for t in applicable]
    candidates = WSObject[o for o in objects(other_string)
                          if all_description_types_present(o, dimensions)]
    isempty(candidates) && return
    from_object = chosen_string.string_type === :initial ||
                  (chosen_string.string_type === :target && orientation === :horizontal)
    selection_list = Tuple{Any,WSObject,Vector{WSObject}}[]
    for obj in candidates
        conditions = conditions_for_bridge(ctx, chosen_object::WSObject, from_object,
                                           applicable, obj)
        conditions === nothing && continue
        push!(selection_list, (getfield(obj, salience), obj, conditions::Vector{WSObject}))
    end
    isempty(selection_list) && return
    chosen_element = stochastic_select(ctx.rng, selection_list)
    other_object = chosen_element[2]
    conditions = chosen_element[3]
    object1 = from_object ? chosen_object::WSObject : other_object
    object2 = from_object ? other_object : chosen_object::WSObject
    flip1 = any(x -> x === object1, conditions)
    flip2 = any(x -> x === object2, conditions)
    proposed = propose_bridge!(ctx, orientation, object1, flip1, object2, flip2)
    max_theme_activation = maximum(t.activation for t in applicable)
    urgency = sround(pct(max_theme_activation) *
                     (string_spanning_group(chosen_object::WSObject) ?
                      EXTREMELY_HIGH_URGENCY : VERY_HIGH_URGENCY))
    look_for_auxiliary_slippages!(ctx, proposed) || return
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:bridge_evaluator], urgency, Any[proposed]),
          ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
    return
end

register_codelet_type!(:thematic_bridge_scout, thematic_bridge_scout)
