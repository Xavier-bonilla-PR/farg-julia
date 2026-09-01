# The description codelet pipeline, ported from descriptions.ss.
#
# Same three-stage shape as the bond codelets in codelets_bonds.jl: a SCOUT
# finds a candidate description and proposes it, an EVALUATOR decides
# stochastically against temperature whether it is strong enough, and a BUILDER
# checks the object still exists and that the description is not already there.
# Descriptions have no incompatible structures to fight, so the builder is the
# simplest of the three — it never breaks anything.
#
# There are two scouts. The bottom-up one starts from a description the object
# already has and slides sideways along a PROPERTY link (leftmost -> first, say)
# to a related descriptor. The top-down one is posted by an active slipnode and
# asks that node directly for a descriptor it could apply.

"""`(tell *workspace* 'choose-object message)` — over every object in the
workspace, weighted by a temperature-adjusted attribute. NB this is the
workspace-wide version; the per-string one is `choose_object` in
codelets_bonds.jl."""
function choose_workspace_object(ctx::MetacatCtx, attribute::Symbol)
    objs = workspace_objects(ctx)
    weights = temp_adjusted_values([getfield(o, attribute) for o in objs])
    return stochastic_pick(ctx.rng, objs, weights)
end

"""`(get-similar-property-links)` — a stochastic filter, so it draws once per
property link, in link-list order, whether or not any survive."""
get_similar_property_links(rng::PyRandom, n::Node) =
    stochastic_filter(rng, l -> temp_adjusted_probability(pct(link_degree_of_assoc(l))),
                      n.property_links)

"""`(descriptions-equal? d1 d2)` — same type and same descriptor."""
descriptions_equal(d1::Description, d2::Description) =
    d1.description_type === d2.description_type && d1.descriptor === d2.descriptor

"""`(description-present? d)` — checked against ALL descriptions, a group's
bond descriptions included."""
description_present(o::WSObject, d::Description) =
    any(other -> descriptions_equal(d, other), all_descriptions(o))

"""`(build-description proposed-description)` — a bond description goes on the
group's separate bond-description list, everything else on the object's own."""
function build_description!(d::Description, net::Slipnet)
    if bond_description(d, net)
        pushfirst!((d.object::Group).bond_descriptions, d)
    else
        pushfirst!(d.object.descriptions, d)
    end
    activate_from_workspace!(d.description_type)
    activate_from_workspace!(d.descriptor)
    d.proposal_level = BUILT
    return d
end

"""`(bond-description?)`."""
bond_description(d::Description, net::Slipnet) =
    d.description_type === net[:plato_bond_category] ||
    d.description_type === net[:plato_bond_facet]

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

# --- the codelets -----------------------------------------------------------

"""`bottom-up-description-scout` — slide sideways from a description the object
already has to a related descriptor along a property link."""
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
    weights = [link_degree_of_assoc(l) * p.activation
               for (l, p) in zip(property_links, properties)]
    chosen_property = stochastic_pick(ctx.rng, properties, weights)
    propose_description!(ctx, chosen_object::WSObject,
                         get_category(chosen_property::Node)::Node,
                         chosen_property::Node)
    return
end

"""`top-down-description-scout` — a description type posted this and now asks
for one of its own instances that could describe the chosen object. `scope` is
a string, or nothing for the whole workspace."""
function top_down_description_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    description_type = args[1]::Node
    scope = length(args) > 1 ? args[2] : nothing
    chosen_object = scope === nothing ? choose_workspace_object(ctx, :average_salience) :
                    choose_object(ctx.rng, scope::WorkspaceString, :average_salience)
    chosen_object === nothing && return
    possible = get_possible_descriptors(description_type, chosen_object::WSObject, ctx.net)
    isempty(possible) && return
    chosen_descriptor = stochastic_pick(ctx.rng, possible, [d.activation for d in possible])
    propose_description!(ctx, chosen_object::WSObject, description_type,
                         chosen_descriptor::Node)
    return
end

"""`description-evaluator`."""
function description_evaluator(ctx::MetacatCtx, args::Vector{Any})
    d = args[1]::Description
    activate_from_workspace!(d.descriptor)
    update_structure_strength!(d, ctx)
    strength = d.strength
    TEMPERATURE[] = ctx.temperature
    # stochastic-if* on (1- p) always draws, and fires when NOT strong enough
    coin = random_real(ctx.rng, 1.0)
    coin < sub_from_1(temp_adjusted_probability(pct(strength))) && return
    d.proposal_level = EVALUATED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:description_builder], strength, Any[d]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`description-builder` — nothing to fight; just check the object survived and
that an equal description is not already on it."""
function description_builder(ctx::MetacatCtx, args::Vector{Any})
    d = args[1]::Description
    object_exists(ctx, d.object) || return
    if description_present(d.object, d)
        # NB the Scheme activates both concepts on this path before fizzling
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
