# The description codelet pipeline, ported from descriptions.ss.
#
# Descriptions are the smallest structures Metacat builds, and the only ones
# that are not registered with the workspace: a description lives on its object
# and nowhere else, so there is no proposed-description table and nothing to
# fight. The pipeline is the plain scout -> evaluator -> builder shape.
#
# `bottom-up-description-scout` works outward from a description an object
# already has, following a property link (a --> alphabetic-first, z -->
# alphabetic-last). `top-down-description-scout` works inward from a
# description type someone else is interested in, and is the codelet
# `propose-bridge` posts when two bridged objects differ in length.

"""`(descriptions-equal? d1 d2)` — same type and same descriptor; the object
is not part of the comparison."""
descriptions_equal(d1::Description, d2::Description) =
    d1.description_type === d2.description_type && d1.descriptor === d2.descriptor

"""`(description-present? description)` — over ALL descriptions, so a group's
bond descriptions count."""
description_present(o::WSObject, d::Description) =
    any(other -> descriptions_equal(other, d), all_descriptions(o))

"""`(bond-description?)` — bond category and bond facet descriptions hang off a
group's separate bond-description list."""
bond_description(d::Description, net::Slipnet) =
    d.description_type === net[:plato_bond_category] ||
    d.description_type === net[:plato_bond_facet]

"""`(add-description new-description)` — CONSed on, so the newest is first."""
add_description!(o::WSObject, d::Description) = (pushfirst!(o.descriptions, d); o)
add_bond_description!(g::Group, d::Description) = (pushfirst!(g.bond_descriptions, d); g)

"""`(choose-object message)` over the whole workspace rather than one string."""
function choose_object(rng::PyRandom, ctx::MetacatCtx, getter)
    objs = workspace_objects(ctx)
    return stochastic_pick(rng, objs, temp_adjusted_values([getter(o) for o in objs]))
end

"""`(build-description proposed-description)`."""
function build_description!(d::Description, net::Slipnet)
    if bond_description(d, net)
        add_bond_description!(d.object::Group, d)
    else
        add_description!(d.object, d)
    end
    activate_from_workspace!(d.description_type)
    activate_from_workspace!(d.descriptor)
    d.proposal_level = BUILT
    return d
end

"""`(propose-description object description-type descriptor)`."""
function propose_description!(ctx::MetacatCtx, object::WSObject, description_type::Node,
                              descriptor::Node)
    d = make_description(object, description_type, descriptor, ctx.codelet_count)
    activate_from_workspace!(descriptor)
    d.proposal_level = PROPOSED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:description_evaluator], description_type.activation,
                       Any[d]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return d
end

"""`bottom-up-description-scout` — take a description the object already has
and try to slide along one of its descriptor's property links, weighting the
destination by how strongly it is associated and how active it is."""
function bottom_up_description_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    chosen_object = choose_object(ctx.rng, ctx, o -> o.average_salience)::WSObject
    chosen_description = choose_relevant_description_by_activation(ctx.rng, chosen_object)
    chosen_description === nothing && return
    chosen_descriptor = (chosen_description::Description).descriptor
    property_links = get_similar_property_links(ctx.rng, chosen_descriptor)
    isempty(property_links) && return
    properties = Node[l.to_node for l in property_links]
    chosen_property = stochastic_pick(ctx.rng, properties,
                                      [link_degree_of_assoc(l) * l.to_node.activation
                                       for l in property_links])::Node
    propose_description!(ctx, chosen_object, get_category(chosen_property)::Node,
                         chosen_property)
    return
end

"""`top-down-description-scout` — `scope` is either one string or the whole
workspace, depending on who posted the codelet."""
function top_down_description_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    description_type = args[1]::Node
    scope = args[2]
    chosen_object = choose_object(ctx.rng, scope, o -> o.average_salience)::WSObject
    possible_descriptors = get_possible_descriptors(ctx.net, description_type,
                                                    chosen_object)
    isempty(possible_descriptors) && return
    # NB a plain stochastic pick, with no temperature adjustment
    chosen_descriptor = stochastic_pick(ctx.rng, possible_descriptors,
                                        [d.activation for d in possible_descriptors])::Node
    propose_description!(ctx, chosen_object, description_type, chosen_descriptor)
    return
end

"""`description-evaluator` — decide stochastically, against temperature,
whether the description is worth attaching."""
function description_evaluator(ctx::MetacatCtx, args::Vector{Any})
    d = args[1]::Description
    activate_from_workspace!(d.descriptor)
    TEMPERATURE[] = ctx.temperature
    update_strength!(d)
    strength = d.strength
    coin = random_real(ctx.rng, 1.0)
    coin < sub_from_1(temp_adjusted_probability(pct(strength))) && return
    d.proposal_level = EVALUATED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:description_builder], strength, Any[d]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`description-builder` — nothing to fight, so this only checks that the
object is still there and that an equal description is not already on it."""
function description_builder(ctx::MetacatCtx, args::Vector{Any})
    d = args[1]::Description
    object_exists(ctx, d.object) || return
    if description_present(d.object, d)
        activate_from_workspace!(d.description_type)
        activate_from_workspace!(d.descriptor)
        return
    end
    build_description!(d, ctx.net)
    return
end

register_codelet_type!(:bottom_up_description_scout, bottom_up_description_scout)
register_codelet_type!(:top_down_description_scout, top_down_description_scout)
register_codelet_type!(:description_evaluator, description_evaluator)
register_codelet_type!(:description_builder, description_builder)
