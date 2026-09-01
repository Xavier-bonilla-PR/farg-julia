# The bond codelet pipeline, ported from bonds.ss.
#
# Every structure type in Metacat follows the same three-stage pipeline: a
# SCOUT finds a candidate and proposes it, an EVALUATOR decides stochastically
# (against temperature) whether it is strong enough to pursue, and a BUILDER
# fights it against whatever it is incompatible with and, if it wins, breaks
# those and builds. Each stage posts the next as a fresh codelet, so a single
# structure takes three trips through the coderack.
#
# A codelet "fizzles" - abandons quietly - by calling `fizzle()`. The Scheme
# does this with an escape continuation; here each codelet body returns early,
# which has the same effect since fizzling is always the last thing a codelet
# does.

"""`(instance-of? node category)`."""
instance_of(node::Node, category::Node) = get_category(node) === category

"""`(get-bond-facets object)` — the description types that are bond facets."""
get_bond_facets(o::WSObject, net::Slipnet) =
    Node[d.description_type for d in o.descriptions
         if instance_of(d.description_type, net[:plato_bond_facet])]

"""`(description-type-support description-type string)`."""
function description_type_support(description_type::Node, s::WorkspaceString)
    objs = objects(s)
    num_described = count(o -> description_type_present(o, description_type), objs)
    local_support = sround(100 * sdiv(num_described, length(objs)))
    return sround(sdiv(local_support + description_type.activation, 2))
end

"""`(choose-bond-facet object1 object2)`."""
function choose_bond_facet(rng::PyRandom, o1::WSObject, o2::WSObject, net::Slipnet)
    s = get_string(o1)
    f1 = get_bond_facets(o1, net)
    f2 = get_bond_facets(o2, net)
    facets = Node[f for f in f1 if any(x -> x === f, f2)]
    isempty(facets) && return nothing
    supports = [description_type_support(f, s) for f in facets]
    return stochastic_pick(rng, facets, supports)
end

directed_group(o::WSObject, net::Slipnet) =
    o isa Group && ((o::Group).group_category === net[:plato_succgrp] ||
                    (o::Group).group_category === net[:plato_predgrp])
same_group_category(g1::Group, g2::Group) = g1.group_category === g2.group_category
same_group_direction(g1::Group, g2::Group) = g1.direction === g2.direction

"""`(incompatible-bond-candidates? object1 object2 bond-facet bond-category)`."""
function incompatible_bond_candidates(o1::WSObject, o2::WSObject, bond_facet::Node,
                                      bond_category::Node, net::Slipnet)
    d1 = directed_group(o1, net)
    d2 = directed_group(o2, net)
    if bond_facet === net[:plato_length]
        return d1 && d2 && !same_group_direction(o1::Group, o2::Group)
    elseif bond_category === net[:plato_sameness]
        return d1 || d2
    elseif d1 && d2
        return !same_group_category(o1::Group, o2::Group) ||
               !same_group_direction(o1::Group, o2::Group)
    else
        return d1 || d2
    end
end

"""`(get-common-groups object1 object2)`."""
get_common_groups(o1::WSObject, o2::WSObject) =
    WSObject[g for g in get_string(o1).groups
             if nested_member(g::Group, o1) && nested_member(g::Group, o2)]

# --- proposed bonds ---------------------------------------------------------

function add_proposed_bond!(s::WorkspaceString, b::Bond)
    key = (b.from_object.id_num, b.to_object.id_num)
    push!(get!(s.proposed_bonds, key, Any[]), b)
    return s
end

"""The `delete-proposed-structure` case for bonds; see coderack.jl."""
delete_proposed_structure!(b::Bond) = delete_proposed_bond!(b.string, b)

function delete_proposed_bond!(s::WorkspaceString, b::Bond)
    key = (b.from_object.id_num, b.to_object.id_num)
    haskey(s.proposed_bonds, key) || return s
    v = s.proposed_bonds[key]
    i = findfirst(x -> x === b, v)
    i === nothing || deleteat!(v, i)
    return s
end

"""`(bond-present? bond)` — an equivalent built bond already exists."""
function bond_present(s::WorkspaceString, b::Bond)
    for x in s.bonds
        other = x::Bond
        other.from_object === b.from_object && other.to_object === b.to_object &&
            other.bond_category === b.bond_category &&
            other.direction === b.direction && return true
        # sameness bonds are symmetric, so the reverse entry counts too
        b.bond_category === other.bond_category && b.direction === other.direction &&
            other.from_object === b.to_object && other.to_object === b.from_object &&
            b.direction === nothing && return true
    end
    return false
end

"""`(break-bond bond)`."""
function break_bond!(b::Bond)
    i = findfirst(x -> x === b, b.string.bonds)
    i === nothing || deleteat!(b.string.bonds, i)
    for (obj, list) in ((b.from_object, b.from_object.outgoing_bonds),
                        (b.to_object, b.to_object.incoming_bonds))
        j = findfirst(x -> x === b, list)
        j === nothing || deleteat!(list, j)
    end
    b.left_object.right_bond = nothing
    b.right_object.left_bond = nothing
    return b
end

# --- fights -----------------------------------------------------------------

"""`(wins-fight? challenger challenger-weight defender defender-weight)` — a
stochastic pick between the two temperature-adjusted weighted strengths."""
function wins_fight(rng::PyRandom, ctx, challenger, challenger_weight,
                    defender, defender_weight)
    update_structure_strength!(challenger, ctx)
    update_structure_strength!(defender, ctx)
    return stochastic_pick(rng, [true, false],
                           temp_adjusted_values([challenger_weight * challenger.strength,
                                                 defender_weight * defender.strength]))::Bool
end

function wins_all_fights(rng::PyRandom, ctx, challenger, challenger_weight,
                         defenders, defender_weights)
    for (i, defender) in enumerate(defenders)
        w = defender_weights isa AbstractVector ? defender_weights[i] : defender_weights
        wins_fight(rng, ctx, challenger, challenger_weight, defender, w) || return false
    end
    return true
end

# --- string relevance -------------------------------------------------------

"""`(get-relevance get-category-method-name category)`."""
function get_relevance(s::WorkspaceString, getter, category::Node)
    non_spanning = WSObject[o for o in objects(s) if !spans_whole_string(o)]
    isempty(non_spanning) && return 0
    n = count(non_spanning) do o
        rb = o.right_bond
        rb !== nothing && getter(rb::Bond) === category
    end
    return sround(100 * sdiv(n, length(non_spanning) - 1))
end

get_bond_category_relevance(s::WorkspaceString, category::Node) =
    get_relevance(s, b -> b.bond_category, category)
get_direction_relevance(s::WorkspaceString, direction::Node) =
    get_relevance(s, b -> b.direction, direction)

"""`(choose-object message)` — pick an object weighted by a
temperature-adjusted attribute."""
function choose_object(rng::PyRandom, s::WorkspaceString, attribute::Symbol)
    objs = objects(s)
    weights = temp_adjusted_values([getfield(o, attribute) for o in objs])
    return stochastic_pick(rng, objs, weights)
end

# --- the codelets -----------------------------------------------------------

"""`(propose-bond ...)` — activate the concepts involved, register the bond as
proposed, and post a bond-evaluator for it."""
function propose_bond!(ctx::MetacatCtx, from_object::WSObject, to_object::WSObject,
                       bond_category::Node, bond_facet::Node,
                       from_descriptor::Node, to_descriptor::Node)
    activate_from_workspace!(from_descriptor)
    activate_from_workspace!(to_descriptor)
    activate_from_workspace!(bond_facet)
    b = make_bond(ctx.net, from_object, to_object, bond_category, bond_facet,
                  from_descriptor, to_descriptor, ctx.codelet_count)
    add_proposed_bond!(get_string(from_object), b)
    b.proposal_level = PROPOSED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:bond_evaluator],
                       bond_degree_of_assoc(bond_category), Any[b]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return b
end

"""`bottom-up-bond-scout` — chooses over ALL workspace objects (not per
string), weighted by temperature-adjusted intra-string salience."""
function bottom_up_bond_scout(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    objs = workspace_objects(ctx)
    weights = temp_adjusted_values([o.intra_string_salience for o in objs])
    from_object = stochastic_pick(ctx.rng, objs, weights)
    return bond_scout_from(ctx, from_object)
end

"""The tail shared by the bottom-up scout and the two top-down scouts."""
function bond_scout_from(ctx::MetacatCtx, from_object)
    from_object === nothing && return
    to_object = choose_neighbor(ctx.rng, from_object::WSObject)
    to_object === nothing && return
    bond_facet = choose_bond_facet(ctx.rng, from_object::WSObject, to_object::WSObject,
                                   ctx.net)
    bond_facet === nothing && return
    d1 = get_descriptor_for(from_object::WSObject, bond_facet::Node)
    d2 = get_descriptor_for(to_object::WSObject, bond_facet::Node)
    (d1 === nothing || d2 === nothing) && return
    bond_category = get_bond_category_between(d1::Node, d2::Node, ctx.net)
    bond_category === nothing && return
    incompatible_bond_candidates(from_object::WSObject, to_object::WSObject,
                                 bond_facet::Node, bond_category::Node, ctx.net) && return
    propose_bond!(ctx, from_object::WSObject, to_object::WSObject, bond_category::Node,
                  bond_facet::Node, d1::Node, d2::Node)
    return
end

"""`(choose-neighbor)` — either side, weighted by intra-string salience."""
function choose_neighbor(rng::PyRandom, o::WSObject)
    ns = vcat(all_left_neighbors(o), all_right_neighbors(o))
    isempty(ns) && return nothing
    return stochastic_pick(rng, ns, [n.intra_string_salience for n in ns])
end

"""`bond-evaluator` — decide stochastically whether the bond is strong enough,
against temperature."""
function bond_evaluator(ctx::MetacatCtx, args::Vector{Any})
    b = args[1]::Bond
    update_structure_strength!(b, ctx)
    strength = b.strength
    TEMPERATURE[] = ctx.temperature
    # stochastic-if* on (1- p) fires when the bond is NOT strong enough
    coin = random_real(ctx.rng, 1.0)
    if coin < sub_from_1(temp_adjusted_probability(pct(strength)))
        delete_proposed_bond!(b.string, b)
        return
    end
    activate_from_workspace!(b.from_object_descriptor)
    activate_from_workspace!(b.to_object_descriptor)
    activate_from_workspace!(b.bond_facet)
    b.proposal_level = EVALUATED
    post!(ctx.coderack, make_codelet(CODELET_TYPES[:bond_builder], strength, Any[b]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`bond-builder` — fight the incompatible structures and, if it wins, break
them and build."""
function bond_builder(ctx::MetacatCtx, args::Vector{Any})
    b = args[1]::Bond
    (object_exists(ctx, b.from_object) && object_exists(ctx, b.to_object)) || return
    delete_proposed_bond!(b.string, b)
    if bond_present(b.string, b)
        activate_from_workspace!(b.bond_category)
        directed(b) && activate_from_workspace!(b.direction::Node)
        return
    end
    incompatible_bonds = get_incompatible_bonds(b)
    if !isempty(incompatible_bonds) &&
       !wins_all_fights(ctx.rng, ctx, b, 1, incompatible_bonds, 1)
        return
    end
    incompatible_groups = get_common_groups(b.from_object, b.to_object)
    if !isempty(incompatible_groups)
        max_span = maximum(get_letter_span(g) for g in incompatible_groups)
        wins_all_fights(ctx.rng, ctx, b, 1, incompatible_groups, max_span) || return
    end
    # bridges are not broken by bonds until the bridge codelets are ported
    for g in incompatible_groups
        object_exists(ctx, g) && break_group!(g, ctx.net)
    end
    for other in incompatible_bonds
        break_bond!(other::Bond)
    end
    build_bond!(b)
    return
end

"""`(get-incompatible-bonds)` — the bonds already occupying either end."""
function get_incompatible_bonds(b::Bond)
    result = Any[]
    for candidate in (b.left_object.right_bond, b.right_object.left_bond)
        candidate === nothing && continue
        any(x -> x === candidate, result) || push!(result, candidate)
    end
    return result
end

register_codelet_type!(:bottom_up_bond_scout, bottom_up_bond_scout)
register_codelet_type!(:bond_evaluator, bond_evaluator)
register_codelet_type!(:bond_builder, bond_builder)
