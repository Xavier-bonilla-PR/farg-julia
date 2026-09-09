# The description codelet pipeline, ported from descriptions.ss.
#
# Same three-stage shape as the bond codelets: a SCOUT finds a candidate
# description and proposes it, an EVALUATOR decides stochastically against
# temperature whether it is strong enough, and a BUILDER attaches it. Unlike
# bonds and groups, descriptions fight nothing - an object can carry any number
# of them - so the builder only checks that the object still exists and that
# the description is not already there.
#
# There are two scouts. The bottom-up one starts from a description an object
# already has and slides along a PROPERTY link to a related one ("this is an a,
# and a is alphabetic-first"). The top-down one starts from an active
# description type and asks what descriptor of that type would fit.

"""`(get-similar-property-links)` — the descriptor's property links, filtered
by a temperature-adjusted coin per link. NB this DRAWS, once per link, and
`prob?` short-circuits at 0 and 1 without drawing."""
get_similar_property_links(rng::PyRandom, n::Node) =
    Sliplink[l for l in n.property_links
             if prob(rng, temp_adjusted_probability(pct(link_degree_of_assoc(l))))]

"""`(descriptions-equal? d1 d2)` — same type and same descriptor. Note this is
not object identity: two different Description objects can be equal."""
descriptions_equal(d1::Description, d2::Description) =
    d1.description_type === d2.description_type && d1.descriptor === d2.descriptor

"""`(description-present? description)` — an equal description is already on
the object. Checks ALL descriptions, a group's bond descriptions included."""
description_present(o::WSObject, d::Description) =
    any(other -> descriptions_equal(d, other), all_descriptions(o))

"""`(bond-description?)` — bond category and bond facet descriptions live in a
group's separate bond-description list."""
bond_description(d::Description, net::Slipnet) =
    d.description_type === net[:plato_bond_category] ||
    d.description_type === net[:plato_bond_facet]

"""`(add-description)` / `(add-bond-description)` — both CONS, so descriptions
come out in reverse order of attachment."""
add_description!(o::WSObject, d::Description) = (pushfirst!(o.descriptions, d); o)
add_bond_description!(g::Group, d::Description) = (pushfirst!(g.bond_descriptions, d); g)

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

"""`(choose-object message)` over the whole workspace rather than one string."""
function choose_workspace_object(ctx::MetacatCtx, attribute::Symbol)
    objs = workspace_objects(ctx)
    weights = temp_adjusted_values([getfield(o, attribute) for o in objs])
    return stochastic_pick(ctx.rng, objs, weights)
end

# --- the codelets -----------------------------------------------------------

"""`(propose-description object description-type descriptor)`."""
function propose_description!(ctx::MetacatCtx, object::WSObject,
                              description_type::Node, descriptor::Node)
    d = make_description(object, description_type, descriptor, ctx.codelet_count)
    activate_from_workspace!(descriptor)
    d.proposal_level = PROPOSED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:description_evaluator],
                       description_type.activation, Any[d]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return d
end

"""`bottom-up-description-scout` — slide from a description the object already
has to a related property of its descriptor."""
function bottom_up_description_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    chosen_object = choose_workspace_object(ctx, :average_salience)
    chosen_object === nothing && return
    chosen_description = choose_relevant_description_by_activation(ctx.rng,
                                                                   chosen_object::WSObject)
    chosen_description === nothing && return
    chosen_descriptor = (chosen_description::Description).descriptor
    property_links = get_similar_property_links(ctx.rng, chosen_descriptor)
    isempty(property_links) && return
    properties = Node[l.to_node for l in property_links]
    property_activations = [p.activation for p in properties]
    degrees_of_assoc = [link_degree_of_assoc(l) for l in property_links]
    chosen_property = stochastic_pick(ctx.rng, properties,
                                      map(*, degrees_of_assoc, property_activations))
    propose_description!(ctx, chosen_object::WSObject,
                         get_category(chosen_property)::Node, chosen_property)
    return
end

"""`top-down-description-scout` — posted by an active description type. `scope`
is a string, or `nothing` for the whole workspace."""
function top_down_description_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    description_type = args[1]::Node
    scope = args[2]
    chosen_object = scope === nothing ?
                    choose_workspace_object(ctx, :average_salience) :
                    choose_object(ctx.rng, scope::WorkspaceString, :average_salience)
    chosen_object === nothing && return
    possible_descriptors = get_possible_descriptors(description_type,
                                                    chosen_object::WSObject, ctx.net)
    isempty(possible_descriptors) && return
    chosen_descriptor = stochastic_pick(ctx.rng, possible_descriptors,
                                        [d.activation for d in possible_descriptors])
    propose_description!(ctx, chosen_object::WSObject, description_type, chosen_descriptor)
    return
end

"""`description-evaluator` — decide stochastically whether the description is
strong enough, against temperature."""
function description_evaluator(ctx::MetacatCtx, args::Vector{Any})
    d = args[1]::Description
    activate_from_workspace!(d.descriptor)
    TEMPERATURE[] = ctx.temperature
    update_strength!(d, ctx.themespace)
    strength = d.strength
    # stochastic-if* on (1- p) fires when the description is NOT strong enough,
    # and always draws
    coin = random_real(ctx.rng, 1.0)
    coin < sub_from_1(temp_adjusted_probability(pct(strength))) && return
    d.proposal_level = EVALUATED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:description_builder], strength, Any[d]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`description-builder` — attach it, unless the object is gone or an equal
description is already there."""
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
