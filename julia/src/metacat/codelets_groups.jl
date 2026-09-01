# The group codelet pipeline, ported from groups.ss.
#
# Three scouts feed one evaluator and one builder. `top-down-group-scout:
# category` and `:direction` both start from an object and scan outward along
# the bonds that agree with what they are looking for; `group-scout:whole-
# string` starts from the leftmost object and only succeeds if the bonds reach
# all the way across.
#
# The builder is the most involved in the model. Beyond the usual fights it
# has three consolidation cases: a sameness group over letters that swallows
# other sameness groups is rebuilt over the letters directly, the same for a
# length-facet group over length groups, and otherwise the group's bonds are
# reconciled with the ones the string actually holds - a bond the group wants
# the other way round is broken and rebuilt flipped.

"""`(length-group? group)` — grouped on length rather than letter category."""
length_group(g::Group, net::Slipnet) = g.group_bond_facet === net[:plato_length]
length_group(::Letter, ::Slipnet) = false

"""`(right-adjacent-bonds object)` — the run of right-bonds starting here."""
function right_adjacent_bonds(o::WSObject)
    result = Any[]
    current = o
    while true
        bond = current.right_bond
        bond === nothing && return result
        push!(result, bond)
        current = (bond::Bond).right_object
    end
end

"""`(right-adjacent-objects object)` — the objects that run of bonds covers."""
function right_adjacent_objects(o::WSObject)
    result = WSObject[o]
    current = o
    while true
        bond = current.right_bond
        bond === nothing && return result
        current = (bond::Bond).right_object
        push!(result, current)
    end
end

"""`(get-next-bond bond direction-to-scan)`."""
get_next_bond(b::Bond, direction_to_scan::Node, net::Slipnet) =
    direction_to_scan === net[:plato_left] ? b.left_object.left_bond :
                                             b.right_object.right_bond

"""`(scan-bonds max-num-to-scan direction-to-scan initial-bond)` — walk out
from the initial bond while the bonds keep saying the same thing. A bond that
says the opposite thing the other way round counts, flipped: that is how
`abc` read right-to-left still yields a group.

Scanning left builds the list backwards, so it comes back reversed."""
function scan_bonds(max_num_to_scan::Int, direction_to_scan::Node, initial_bond::Bond,
                    net::Slipnet)
    bond_facet = initial_bond.bond_facet
    bond_category = initial_bond.bond_category
    opposite_bond_category = get_related_node(bond_category, net[:plato_opposite],
                                              net[:plato_identity])
    direction = initial_bond.direction
    opposite_direction = direction === nothing ? nothing :
                         get_related_node(direction::Node, net[:plato_opposite],
                                          net[:plato_identity])
    result = Any[]
    n = max_num_to_scan
    bond = initial_bond
    while n > 0 && bond !== nothing
        b = bond::Bond
        if b.bond_facet === bond_facet && b.bond_category === bond_category &&
           b.direction === direction
            push!(result, b)
        elseif b.bond_facet === bond_facet &&
               b.bond_category === opposite_bond_category &&
               b.direction === opposite_direction
            push!(result, make_flipped_version(b, net))
        else
            break
        end
        n -= 1
        bond = get_next_bond(b, direction_to_scan, net)
    end
    return direction_to_scan === net[:plato_right] ? result : reverse(result)
end

"""`(polarize-bonds bonds bond-facet bond-category direction)` — read every
bond the same way, flipping the ones that disagree. Any bond that cannot be
read that way at all abandons the whole list."""
function polarize_bonds(bonds, bond_facet::Node, bond_category::Node,
                        direction::Union{Nothing,Node}, net::Slipnet)
    result = Any[]
    for bond in bonds
        b = bond::Bond
        b.bond_facet === bond_facet || return Any[]
        if b.bond_category === bond_category && b.direction === direction
            push!(result, b)
        elseif get_related_node(b.bond_category, net[:plato_opposite],
                                net[:plato_identity]) === bond_category &&
               b.direction !== nothing &&
               get_related_node((b.direction)::Node, net[:plato_opposite],
                                net[:plato_identity]) === direction
            push!(result, make_flipped_version(b, net))
        else
            return Any[]
        end
    end
    return result
end

"""`(propose-group objects bonds group-category direction)`. The objects must
already be in left-to-right string order."""
function propose_group!(ctx::MetacatCtx, objs::Vector{WSObject}, bonds::Vector{Any},
                        group_category::Node, direction::Union{Nothing,Node})
    net = ctx.net
    left_object = objs[1]
    right_object = objs[end]
    s = get_string(left_object)
    bond_category = get_related_node(group_category, net[:plato_bond_category],
                                     net[:plato_identity])::Node
    group_bond_facet = isempty(bonds) ? net[:plato_letter_category] :
                       (bonds[1]::Bond).bond_facet
    proposed_group = make_group(net, s, group_category, group_bond_facet, direction,
                                left_object, right_object, objs, bonds,
                                ctx.codelet_count)
    TEMPERATURE[] = ctx.temperature
    coin = random_real(ctx.rng, 1.0)
    coin < length_description_probability(proposed_group, net) &&
        attach_length_description!(proposed_group, net)
    activate_from_workspace!(bond_category)
    direction === nothing || activate_from_workspace!(direction::Node)
    add_proposed_group!(s, proposed_group)
    proposed_group.proposal_level = PROPOSED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:group_evaluator],
                       bond_degree_of_assoc(bond_category), Any[proposed_group]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return proposed_group
end

"""The string a top-down group scout works in: whichever one most wants what
the scout is carrying, unless the scope already names one."""
function scout_string(ctx::MetacatCtx, scope, relevance)
    scope isa WorkspaceString && return scope::WorkspaceString
    strings = all_strings(ctx)
    weights = [sdiv(relevance(s) + s.average_intra_string_unhappiness, 2)
               for s in strings]
    return stochastic_pick(ctx.rng, strings, weights)::WorkspaceString
end

"""Which way to scan out from the object: forced at either edge of the string,
otherwise the more active of Right and Left, with no temperature adjustment."""
function direction_to_scan(rng::PyRandom, object::WSObject, net::Slipnet)
    leftmost_in_string(object) && return net[:plato_right]
    rightmost_in_string(object) && return net[:plato_left]
    dirs = Node[net[:plato_right], net[:plato_left]]
    return stochastic_pick(rng, dirs, [d.activation for d in dirs])::Node
end

initial_scan_bond(object::WSObject, dir::Node, net::Slipnet) =
    dir === net[:plato_left] ? object.left_bond : object.right_bond

"""`(cons (get-left-object (1st bonds)) (tell-all bonds 'get-right-object))`."""
function objects_spanned(bonds)
    objs = WSObject[(bonds[1]::Bond).left_object]
    for b in bonds
        push!(objs, (b::Bond).right_object)
    end
    return objs
end

"""`top-down-group-scout:category` — look for a run of bonds of the category
this group category is made of. Failing that, and only for a letter, consider
making a one-object group out of it.

NB the singleton-group branch reads the bond category off the group category,
so a scout carrying samegrp proposes an undirected singleton, while one
carrying succgrp or predgrp picks a direction by how well the string's other
groups already support it."""
function top_down_group_scout_category(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    group_category = args[1]::Node
    scope = args[2]
    bond_category = get_related_node(group_category, net[:plato_bond_category],
                                     net[:plato_identity])::Node
    s = scout_string(ctx, scope,
                     x -> get_bond_category_relevance(x, bond_category))
    object = choose_object(ctx.rng, s, o -> o.intra_string_salience)::WSObject
    spans_whole_string(object) && return
    dir = direction_to_scan(ctx.rng, object, net)
    number_to_scan = num_of_bonds_to_scan(ctx.rng, s)
    initial_bond = initial_scan_bond(object, dir, net)
    if initial_bond !== nothing && (initial_bond::Bond).bond_category === bond_category
        bonds = scan_bonds(number_to_scan, dir, initial_bond::Bond, net)
        objs = objects_spanned(bonds)
        propose_group!(ctx, objs, bonds, group_category, (initial_bond::Bond).direction)
        return
    end
    object isa Group && return
    singleton_direction =
        group_category === net[:plato_samegrp] ? nothing :
        stochastic_pick(ctx.rng, Node[net[:plato_left], net[:plato_right]],
                        [descriptor_support(net[:plato_left], s),
                         descriptor_support(net[:plato_right], s)])
    objs = WSObject[object]
    bonds = Any[]
    singleton_group = make_group(net, s, group_category, net[:plato_letter_category],
                                 singleton_direction, object, object, objs, bonds,
                                 ctx.codelet_count)
    coin = random_real(ctx.rng, 1.0)
    coin < sub_from_1(single_letter_group_probability(ctx.rng, singleton_group, net)) &&
        return
    propose_group!(ctx, objs, bonds, group_category, singleton_direction)
    return
end

"""`top-down-group-scout:direction` — the same walk, but looking for bonds
running the way this direction says rather than of a particular category."""
function top_down_group_scout_direction(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    direction = args[1]::Node
    scope = args[2]
    s = scout_string(ctx, scope, x -> get_direction_relevance(x, direction))
    object = choose_object(ctx.rng, s, o -> o.intra_string_salience)::WSObject
    spans_whole_string(object) && return
    dir = direction_to_scan(ctx.rng, object, net)
    number_to_scan = num_of_bonds_to_scan(ctx.rng, s)
    initial_bond = initial_scan_bond(object, dir, net)
    (initial_bond !== nothing && (initial_bond::Bond).direction === direction) || return
    bond_category = (initial_bond::Bond).bond_category
    group_category = get_related_node(bond_category, net[:plato_group_category],
                                      net[:plato_identity])::Node
    bonds = scan_bonds(number_to_scan, dir, initial_bond::Bond, net)
    objs = objects_spanned(bonds)
    propose_group!(ctx, objs, bonds, group_category, direction)
    return
end

"""`group-scout:whole-string` — only proposes a group that covers the string
end to end, reading every bond the same way as one chosen at random."""
function group_scout_whole_string(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    strings = all_strings(ctx)
    s = stochastic_pick(ctx.rng, strings,
                        [x.average_intra_string_unhappiness for x in strings])::WorkspaceString
    isempty(s.bonds) && return
    leftmost_object = choose_leftmost_object(ctx.rng, s, net)
    leftmost_object === nothing && return
    right_bonds = right_adjacent_bonds(leftmost_object::WSObject)
    bonded_objects = right_adjacent_objects(leftmost_object::WSObject)
    (isempty(right_bonds) || !rightmost_in_string(bonded_objects[end])) && return
    chosen_bond = random_pick(ctx.rng, right_bonds)::Bond
    polarized_bonds = polarize_bonds(right_bonds, chosen_bond.bond_facet,
                                     chosen_bond.bond_category, chosen_bond.direction, net)
    isempty(polarized_bonds) && return
    group_category = get_related_node(chosen_bond.bond_category,
                                      net[:plato_group_category],
                                      net[:plato_identity])::Node
    propose_group!(ctx, bonded_objects, polarized_bonds, group_category,
                   chosen_bond.direction)
    return
end

"""`(group-evaluation-probability x)` — at high temperature this is pushed
toward 1 for all but the weakest groups, and at low temperature it approaches
the identity. Copycat had trouble building the weak groups that strings like
xwyxzy need; this is Metacat's answer."""
group_evaluation_probability(x) =
    pct(TEMPERATURE[]) * (sdiv(2, 1 + exp(sdiv(-x, 5))) - 1) +
    sub_from_1(pct(TEMPERATURE[])) * pct(x)

"""`group-evaluator`."""
function group_evaluator(ctx::MetacatCtx, args::Vector{Any})
    proposed_group = args[1]::Group
    update_structure_strength!(proposed_group, ctx)
    strength = proposed_group.strength
    TEMPERATURE[] = ctx.temperature
    coin = random_real(ctx.rng, 1.0)
    if coin < sub_from_1(group_evaluation_probability(strength))
        delete_proposed_group!(proposed_group.string, proposed_group)
        return
    end
    activate_from_workspace!(proposed_group.bond_category)
    proposed_group.direction === nothing ||
        activate_from_workspace!((proposed_group.direction)::Node)
    proposed_group.proposal_level = EVALUATED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:group_builder], strength, Any[proposed_group]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`group-builder`."""
function group_builder(ctx::MetacatCtx, args::Vector{Any})
    proposed_group = args[1]::Group
    net = ctx.net
    s = proposed_group.string
    group_category = proposed_group.group_category
    direction = proposed_group.direction
    equivalent_group = get_equivalent_group(s, proposed_group)
    constituent_bonds = proposed_group.constituent_bonds
    constituent_objects = proposed_group.constituent_objects
    delete_proposed_group!(s, proposed_group)
    if equivalent_group !== nothing
        # donate any descriptions the existing group is missing, then give up
        for description in (equivalent_group::Group).descriptions
            activate_from_workspace!(description.descriptor)
        end
        for description in proposed_group.descriptions
            description_present(equivalent_group::Group, description) && continue
            build_description!(make_description(equivalent_group::Group,
                                                description.description_type,
                                                description.descriptor,
                                                ctx.codelet_count), net)
        end
        return
    end
    all(b -> bond_present(s, b::Bond) || flipped_bond_present(s, b::Bond, net),
        constituent_bonds) || return

    bonds_to_be_flipped =
        group_category === net[:plato_samegrp] ? Any[] :
        Any[b for b in (get_equivalent_flipped_bond(s, bond::Bond, net)
                        for bond in constituent_bonds) if b !== nothing]
    if !isempty(bonds_to_be_flipped) &&
       !wins_all_fights(ctx.rng, ctx, proposed_group, get_letter_span(proposed_group),
                        bonds_to_be_flipped, 1)
        return
    end
    incompatible_groups = get_incompatible_groups(proposed_group)
    if !isempty(incompatible_groups)
        # a group of the same shape is weighed by length; anything else evenly
        for incompatible_group in incompatible_groups
            g = incompatible_group::Group
            won = (same_group_category(g, proposed_group) &&
                   same_group_direction(g, proposed_group)) ?
                  wins_fight(ctx.rng, ctx, proposed_group, proposed_group.group_length,
                             g, g.group_length) :
                  wins_fight(ctx.rng, ctx, proposed_group, 1, g, 1)
            won || return
        end
    end
    incompatible_bridges = vcat(get_incompatible_bridges(proposed_group, :vertical, net),
                                get_incompatible_bridges(proposed_group, :horizontal, net))
    if !isempty(incompatible_bridges) &&
       !wins_all_fights(ctx.rng, ctx, proposed_group, 1, incompatible_bridges, 1)
        return
    end
    for g in incompatible_groups
        break_group!(g::Group, net, ctx)
    end
    for bridge in incompatible_bridges
        break_bridge!(ctx, bridge::Bridge)
    end

    if group_category === net[:plato_samegrp] &&
       proposed_group.group_bond_facet === net[:plato_letter_category] &&
       any(o -> o isa Group, constituent_objects)
        # a letter-sameness group swallowing other sameness groups is rebuilt
        # over all their letters at once
        letters = get_letters(proposed_group)
        for g in constituent_objects
            g isa Group && break_group!(g::Group, net, ctx)
        end
        letter_bonds = adjacent_sameness_bonds(net, letters, net[:plato_letter_category],
                                               l -> l.letter_category)
        new_group = make_group(net, s, group_category, net[:plato_letter_category],
                               direction, letters[1], letters[end], letters, letter_bonds,
                               ctx.codelet_count)
        description_type_present(proposed_group, net[:plato_length]) &&
            attach_length_description!(new_group, net)
        proposed_group = new_group
    elseif group_category === net[:plato_samegrp] &&
           proposed_group.group_bond_facet === net[:plato_length] &&
           any(o -> length_group(o, net), constituent_objects)
        # same, one level up: a length-sameness group over length groups is
        # rebuilt over their constituents
        new_constituent_groups = WSObject[]
        for g in constituent_objects
            length_group(g, net) ? append!(new_constituent_groups,
                                           (g::Group).constituent_objects) :
                                   push!(new_constituent_groups, g)
        end
        for g in constituent_objects
            length_group(g, net) && break_group!(g::Group, net, ctx)
        end
        lengths = [get_platonic_length(g, net) for g in new_constituent_groups]
        all(l -> l === lengths[1], lengths) || return
        group_bonds = adjacent_sameness_bonds(net, new_constituent_groups,
                                              net[:plato_length],
                                              g -> get_platonic_length(g, net)::Node)
        new_group = make_group(net, s, group_category, net[:plato_length], direction,
                               new_constituent_groups[1], new_constituent_groups[end],
                               new_constituent_groups, group_bonds, ctx.codelet_count)
        attach_length_description!(new_group, net)
        proposed_group = new_group
    else
        # reconcile the group's bonds with the ones the string holds: a bond
        # the string has the other way round is broken and rebuilt flipped
        new_bonds = Any[]
        for bond in constituent_bonds
            b = bond::Bond
            if bond_present(s, b)
                push!(new_bonds, get_equivalent_bond(s, b))
            else
                break_bond!((get_equivalent_flipped_bond(s, b, net))::Bond)
                build_bond!(b)
                push!(new_bonds, b)
            end
        end
        proposed_group.constituent_bonds = new_bonds
    end
    build_group!(proposed_group, net, ctx)
    return
end

"""The `adjacency-map` in group-builder's two consolidation cases: reuse the
bond between each adjacent pair if there is one, otherwise build a sameness
bond on the given facet."""
function adjacent_sameness_bonds(net::Slipnet, objs, bond_facet::Node, descriptor_of)
    result = Any[]
    for i in 1:(length(objs) - 1)
        o1 = objs[i]
        o2 = objs[i + 1]
        if bonded(o1, o2)
            push!(result, o1.right_bond)
        else
            new_bond = make_bond(net, o1, o2, net[:plato_sameness], bond_facet,
                                 descriptor_of(o1), descriptor_of(o2))
            build_bond!(new_bond)
            push!(result, new_bond)
        end
    end
    return result
end

register_codelet_type!(:top_down_group_scout_category, top_down_group_scout_category)
register_codelet_type!(:top_down_group_scout_direction, top_down_group_scout_direction)
register_codelet_type!(:group_scout_whole_string, group_scout_whole_string)
register_codelet_type!(:group_evaluator, group_evaluator)
register_codelet_type!(:group_builder, group_builder)
