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

"""`(delete-proposed-bonds object)` — clears the proposed-bond table's row and
column for an object that is going away. Nothing in the model ever reads that
table back (only add/delete touch it), so this is bookkeeping rather than
behaviour, but leaving it out would be a silent divergence for any later layer
that does read it."""
function delete_proposed_bonds!(s::WorkspaceString, o::WSObject)
    for key in collect(keys(s.proposed_bonds))
        (key[1] == o.id_num || key[2] == o.id_num) && delete!(s.proposed_bonds, key)
    end
    return s
end

delete_proposed_structure!(b::Bond, ctx) = delete_proposed_bond!(b.string, b)
"""Without a workspace context there is nowhere a proposed bridge is
registered, so there is nothing to remove."""
delete_proposed_structure!(::Bridge, ::Nothing) = nothing

function delete_proposed_bond!(s::WorkspaceString, b::Bond)
    key = (b.from_object.id_num, b.to_object.id_num)
    haskey(s.proposed_bonds, key) || return s
    v = s.proposed_bonds[key]
    i = findfirst(x -> x === b, v)
    i === nothing || deleteat!(v, i)
    return s
end

"""`(get-equivalent-bond bond)` — the built bond running the same way between
the same two objects, if it also agrees on category and direction."""
function get_equivalent_bond(s::WorkspaceString, b::Bond)
    other = get(s.from_to_bond, (b.from_object.id_num, b.to_object.id_num), nothing)
    other === nothing && return nothing
    return (other::Bond).bond_category === b.bond_category &&
           (other::Bond).direction === b.direction ? other : nothing
end

"""`(opposite-bond-category? b1 b2)` / `(opposite-bond-direction? b1 b2)`.
NB both require BOTH bonds to be DIRECTED. Without that guard two sameness
bonds would compare equal-and-opposite, since an undirected bond has neither a
direction nor an opposite category."""
opposite_bond_category(b1::Bond, b2::Bond, net::Slipnet) =
    directed(b1) && directed(b2) &&
    b1.bond_category === get_related_node(b2.bond_category, net[:plato_opposite],
                                          net[:plato_identity])
opposite_bond_direction(b1::Bond, b2::Bond, net::Slipnet) =
    directed(b1) && directed(b2) &&
    b1.direction === get_related_node(b2.direction::Node, net[:plato_opposite],
                                      net[:plato_identity])

"""`(get-equivalent-flipped-bond bond)` — the built bond running the OTHER way
between the same two objects, saying the opposite thing. A group whose bonds
point the wrong way has to break these before it can build."""
function get_equivalent_flipped_bond(s::WorkspaceString, b::Bond, net::Slipnet)
    other = get(s.from_to_bond, (b.to_object.id_num, b.from_object.id_num), nothing)
    other === nothing && return nothing
    return opposite_bond_category(b, other::Bond, net) &&
           opposite_bond_direction(b, other::Bond, net) ? other : nothing
end

bond_present(s::WorkspaceString, b::Bond) = get_equivalent_bond(s, b) !== nothing
flipped_bond_present(s::WorkspaceString, b::Bond, net::Slipnet) =
    get_equivalent_flipped_bond(s, b, net) !== nothing

"""`(break-bond bond)`."""
function break_bond!(b::Bond, net::Slipnet)
    delete_bond_from_table!(b.string, b, net)
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
    # A directed bond at either edge of its string can contradict a bridge that
    # maps that edge onto the other string; only edge bonds can.
    incompatible_bridges =
        (directed(b) && (bond_leftmost_in_string(b) || bond_rightmost_in_string(b))) ?
        vcat(get_incompatible_bridges(b, :horizontal, ctx.net),
             get_incompatible_bridges(b, :vertical, ctx.net)) : Bridge[]
    if !isempty(incompatible_bridges) &&
       !wins_all_fights(ctx.rng, ctx, b, 2, incompatible_bridges, 3)
        return
    end
    for g in incompatible_groups
        object_exists(ctx, g) && break_group!(g, ctx.net, ctx)
    end
    for other in incompatible_bonds
        break_bond!(other::Bond, ctx.net)
    end
    for bridge in incompatible_bridges
        break_bridge!(bridge, ctx)
    end
    build_bond!(b, ctx.net)
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

# --- the two top-down bond scouts (bonds.ss 217-320) ------------------------
#
# Posted by an ACTIVE SLIPNODE rather than by the bottom-up refill: `successor`
# waking up makes the model go looking for successor bonds. The scope is the
# whole workspace when a slipnode posted it, so the scout first has to pick a
# string — weighted by how relevant the concept is there AND how unhappy that
# string is, averaged. A string that already reads well is left alone even if
# the concept fits it.
#
# These are what CONTINUE.md's stub table warned would become wrong "as soon as
# an active slipnode posts its top-down codelets — i.e. the run loop". They are
# ported with the run loop, on cue.

"""The string a top-down scout works in: the given one when the scope IS a
string, otherwise a stochastic pick over the three (four in justify mode)
weighted by relevance-and-unhappiness."""
function choose_top_down_string(ctx::MetacatCtx, scope, relevance)
    scope isa WorkspaceString && return scope
    strings = all_strings(ctx)
    weights = [sdiv(relevance(s) + s.average_intra_string_unhappiness, 2)
               for s in strings]
    return stochastic_pick(ctx.rng, strings, weights)
end

"""`top-down-bond-scout:category` — look for a bond of THIS category."""
function top_down_bond_scout_category(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    bond_category = args[1]::Node
    scope = length(args) >= 2 ? args[2] : nothing
    s = choose_top_down_string(ctx, scope,
                               st -> get_bond_category_relevance(st, bond_category))
    object1 = choose_object(ctx.rng, s::WorkspaceString, :intra_string_salience)
    object1 === nothing && return
    object2 = choose_neighbor(ctx.rng, object1::WSObject)
    object2 === nothing && return
    bond_facet = choose_bond_facet(ctx.rng, object1::WSObject, object2::WSObject, ctx.net)
    bond_facet === nothing && return
    d1 = get_descriptor_for(object1::WSObject, bond_facet::Node)
    d2 = get_descriptor_for(object2::WSObject, bond_facet::Node)
    (d1 === nothing || d2 === nothing) && return
    incompatible_bond_candidates(object1::WSObject, object2::WSObject, bond_facet::Node,
                                 bond_category, ctx.net) && return
    # The bond may run either way round; the scout takes whichever direction
    # gives the category it was posted for.
    if get_bond_category_between(d1::Node, d2::Node, ctx.net) === bond_category
        propose_bond!(ctx, object1::WSObject, object2::WSObject, bond_category,
                      bond_facet::Node, d1::Node, d2::Node)
    elseif get_bond_category_between(d2::Node, d1::Node, ctx.net) === bond_category
        propose_bond!(ctx, object2::WSObject, object1::WSObject, bond_category,
                      bond_facet::Node, d2::Node, d1::Node)
    end
    return
end

"""`top-down-bond-scout:direction` — look for a bond running THIS way. Sameness
bonds are excluded: they have no direction to be looking for."""
function top_down_bond_scout_direction(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    direction = args[1]::Node
    scope = length(args) >= 2 ? args[2] : nothing
    s = choose_top_down_string(ctx, scope,
                               st -> get_direction_relevance(st, direction))
    from_object = choose_object(ctx.rng, s::WorkspaceString, :intra_string_salience)
    from_object === nothing && return
    to_object = direction === ctx.net[:plato_left] ?
                choose_left_neighbor(ctx.rng, from_object::WSObject) :
                choose_right_neighbor(ctx.rng, from_object::WSObject)
    to_object === nothing && return
    bond_facet = choose_bond_facet(ctx.rng, from_object::WSObject, to_object::WSObject,
                                   ctx.net)
    bond_facet === nothing && return
    from_descriptor = get_descriptor_for(from_object::WSObject, bond_facet::Node)
    to_descriptor = get_descriptor_for(to_object::WSObject, bond_facet::Node)
    (from_descriptor === nothing || to_descriptor === nothing) && return
    bond_category = get_bond_category_between(from_descriptor::Node, to_descriptor::Node,
                                              ctx.net)
    (bond_category === nothing || bond_category === ctx.net[:plato_sameness]) && return
    incompatible_bond_candidates(from_object::WSObject, to_object::WSObject,
                                 bond_facet::Node, bond_category::Node, ctx.net) && return
    propose_bond!(ctx, from_object::WSObject, to_object::WSObject, bond_category::Node,
                  bond_facet::Node, from_descriptor::Node, to_descriptor::Node)
    return
end

register_codelet_type!(:bottom_up_bond_scout, bottom_up_bond_scout)
register_codelet_type!(:bond_evaluator, bond_evaluator)
register_codelet_type!(:bond_builder, bond_builder)
register_codelet_type!(:top_down_bond_scout_category, top_down_bond_scout_category)
register_codelet_type!(:top_down_bond_scout_direction, top_down_bond_scout_direction)
