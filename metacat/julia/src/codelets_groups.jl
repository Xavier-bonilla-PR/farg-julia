# The group codelet pipeline, ported from groups.ss.
#
# Same scout/evaluator/builder shape as bonds and descriptions, but the builder
# is by far the most involved in the model: a group has to beat the bonds that
# point the wrong way, the groups that overlap it, and (once bridges exist) the
# bridges its constituents are part of, and then it may have to REBUILD itself
# in consolidated form before it can be attached.
#
# Three scouts, each finding a different kind of group. Two are top-down, posted
# by an active group category or direction; the third looks for a group that
# spans a whole string.
#
# Deferred, and marked where they arise: incompatible bridges, which need the
# bridge codelet layer, and the trace's new-group monitoring.

"""`(get-num-of-bonds-to-scan)` — 0..n-1 for an n-letter string, weighted by
the square of the value, so long scans are much likelier than short ones."""
function get_num_of_bonds_to_scan(rng::PyRandom, s::WorkspaceString)
    n = string_length(s)
    values = collect(0:(n - 1))
    return stochastic_pick(rng, values, [sq(v) for v in values])
end

"""`(get-equivalent-group group)` — the built group with the same leftmost
object, if it also agrees on category, direction and length."""
function get_equivalent_group(s::WorkspaceString, g::Group)
    any(x -> x === g, s.groups) && return g
    other = get(s.group_by_leftmost_id, g.left_object.id_num, nothing)
    other === nothing && return nothing
    return (other::Group).group_category === g.group_category &&
           (other::Group).direction === g.direction &&
           (other::Group).group_length == g.group_length ? other : nothing
end

delete_proposed_structure!(g::Group, ctx) = delete_proposed_group!(g.string, g)

add_proposed_group!(s::WorkspaceString, g::Group) = (pushfirst!(s.proposed_groups, g); s)
delete_proposed_group!(s::WorkspaceString, g::Group) =
    (filter!(x -> x !== g, s.proposed_groups); s)

"""`(get-incompatible-groups)` — the groups already enclosing this one's
constituents. `remq-duplicates` keeps the LAST of each duplicate group."""
function get_incompatible_groups(g::Group)
    enclosing = Any[o.enclosing_group for o in g.constituent_objects
                    if o.enclosing_group !== nothing]
    deduped = Any[x for (i, x) in enumerate(enclosing)
                  if !any(y -> y === x, enclosing[(i + 1):end])]
    return Any[x for x in deduped if x !== g]
end

# `(get-incompatible-bridges bridge-orientation)` for a group lives in
# codelets_bridges.jl, which loads after this file.

"""`(descriptor-support descriptor string)` — what fraction of the string's
groups already carry this descriptor."""
function descriptor_support(descriptor::Node, s::WorkspaceString)
    groups = s.groups
    isempty(groups) && return 0
    n = count(g -> any(d -> d.descriptor === descriptor, all_descriptions(g)), groups)
    # (100* x) is (round (* 100 x)), not a bare multiply
    return sround(100 * sdiv(n, length(groups)))
end

"""`(length-description-probability group)` — whether to bother describing the
group's length. Never for groups longer than five, always for singletons."""
function length_description_probability(g::Group, net::Slipnet)
    g.group_length > 5 && return 0
    g.group_length == 1 && return 1
    return temp_adjusted_probability(
        sexpt(0.5, cube(g.group_length) * pct(sub_from_100(net[:plato_length].activation))))
end

"""`(single-letter-group-probability group)` — how willing the model is to call
one letter a group. Local support is raised to a power that falls as other
similar groups appear, so the first singleton is much harder than the third."""
function single_letter_group_probability(rng::PyRandom, g::Group, net::Slipnet)
    n = get_num_of_local_supporting_groups(g)
    exponent = n == 1 ? 4 : n == 2 ? 2 : 1
    return temp_adjusted_probability(
        sexpt(pct(get_local_support(rng, g)) * pct(net[:plato_length].activation), exponent))
end

"""`(attach-length-description group)` — groups longer than five have no
platonic length node, so they get no length description."""
function attach_length_description!(g::Group, net::Slipnet)
    get_descriptor_for(g, net[:plato_length]) === nothing || return g
    platonic_length = get_platonic_length(g, net)
    platonic_length === nothing && return g
    new_description!(g, net[:plato_length], platonic_length::Node)
    return g
end

# --- scanning ---------------------------------------------------------------

right_adjacent_bonds(o::WSObject) =
    (rb = o.right_bond; rb === nothing ? Any[] :
     vcat(Any[rb], right_adjacent_bonds((rb::Bond).right_object)))

right_adjacent_objects(o::WSObject) =
    (rb = o.right_bond; rb === nothing ? WSObject[o] :
     vcat(WSObject[o], right_adjacent_objects((rb::Bond).right_object)))

"""`(get-next-bond bond direction-to-scan)`."""
get_next_bond(b::Bond, direction_to_scan::Node, net::Slipnet) =
    direction_to_scan === net[:plato_left] ? b.left_object.left_bond :
                                             b.right_object.right_bond

"""`(scan-bonds max-num direction-to-scan initial-bond)` — walk outward from a
bond, collecting bonds that say the same thing. A bond that says the opposite
thing in the opposite direction says the SAME thing read the other way round,
so it is collected as its flipped version."""
function scan_bonds(max_num_to_scan::Int, direction_to_scan::Node, initial_bond::Bond,
                    net::Slipnet, codelet_count::Int = 0)
    bond_facet = initial_bond.bond_facet
    bond_category = initial_bond.bond_category
    opposite_bond_cat = get_related_node(bond_category, net[:plato_opposite],
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
        elseif b.bond_facet === bond_facet && b.bond_category === opposite_bond_cat &&
               b.direction === opposite_direction
            push!(result, make_flipped_version(b, net, codelet_count))
        else
            break
        end
        n -= 1
        bond = get_next_bond(b, direction_to_scan, net)
    end
    return direction_to_scan === net[:plato_right] ? result : reverse(result)
end

"""`(polarize-bonds bonds bond-facet bond-category direction)` — turn a run of
bonds into a run that all say the same thing, flipping the ones that say the
opposite. Any bond that cannot be made to agree kills the whole run."""
function polarize_bonds(bonds, bond_facet::Node, bond_category::Node,
                        direction::Union{Nothing,Node}, net::Slipnet,
                        codelet_count::Int = 0)
    result = Any[]
    for x in bonds
        b = x::Bond
        b.bond_facet === bond_facet || return Any[]
        if b.bond_category === bond_category && b.direction === direction
            push!(result, b)
        elseif get_related_node(b.bond_category, net[:plato_opposite],
                                net[:plato_identity]) === bond_category &&
               b.direction !== nothing &&
               get_related_node(b.direction::Node, net[:plato_opposite],
                                net[:plato_identity]) === direction
            push!(result, make_flipped_version(b, net, codelet_count))
        else
            return Any[]
        end
    end
    return result
end

"""`(adjacency-map f l)` — f over each adjacent pair."""
adjacency_map(f, l) = [f(l[i], l[i + 1]) for i in 1:(length(l) - 1)]

all_same(l) = isempty(l) || all(x -> x === l[1], l)

length_group(o::WSObject, net::Slipnet) =
    o isa Group && (o::Group).group_bond_facet === net[:plato_length]

# --- the codelets -----------------------------------------------------------

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
    g = make_group(net, s, group_category, group_bond_facet, direction,
                   left_object, right_object, objs, bonds, ctx.codelet_count)
    # stochastic-if* ALWAYS draws, even when the probability is 0 or 1
    coin = random_real(ctx.rng, 1.0)
    if coin < length_description_probability(g, net)
        attach_length_description!(g, net)
    end
    activate_from_workspace!(bond_category)
    direction === nothing || activate_from_workspace!(direction::Node)
    add_proposed_group!(s, g)
    g.proposal_level = PROPOSED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:group_evaluator],
                       bond_degree_of_assoc(bond_category), Any[g]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return g
end

"""Pick the string to work in, weighted by how relevant the concept already is
there and how unhappy the string is. `relevance` is per-string."""
function choose_string_by(ctx::MetacatCtx, relevance)
    strings = all_strings(ctx)
    weights = [sdiv(relevance(s) + s.average_intra_string_unhappiness, 2) for s in strings]
    # the answer string contributes a 0 weight outside justify mode
    return stochastic_pick(ctx.rng, strings, vcat(weights, [0]))
end

"""The head shared by both top-down group scouts: choose a string, choose an
object in it, and decide which way to scan from that object."""
function group_scout_setup(ctx::MetacatCtx, s::WorkspaceString)
    net = ctx.net
    object = choose_object(ctx.rng, s, :intra_string_salience)
    object === nothing && return nothing
    spans_whole_string(object::WSObject) && return nothing
    direction_to_scan =
        leftmost_in_string(object::WSObject)  ? net[:plato_right] :
        rightmost_in_string(object::WSObject) ? net[:plato_left] :
        stochastic_pick(ctx.rng, [net[:plato_right], net[:plato_left]],
                        [net[:plato_right].activation, net[:plato_left].activation])
    number_to_scan = get_num_of_bonds_to_scan(ctx.rng, s)
    initial_bond = direction_to_scan === net[:plato_left] ?
                   (object::WSObject).left_bond : (object::WSObject).right_bond
    return (object::WSObject, direction_to_scan, number_to_scan, initial_bond)
end

"""`top-down-group-scout:category`. NB the spans-whole-string check RETURNS at
the outer level, so a chosen object that spans the string ends the codelet
outright — the singleton branch below never gets a look at it."""
function top_down_group_scout_category(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    group_category = args[1]::Node
    scope = args[2]
    bond_category = get_related_node(group_category, net[:plato_bond_category],
                                     net[:plato_identity])::Node
    s = scope === nothing ?
        choose_string_by(ctx, x -> get_bond_category_relevance(x, bond_category)) :
        scope::WorkspaceString
    setup = group_scout_setup(ctx, s)
    setup === nothing && return
    (object, direction_to_scan, number_to_scan, initial_bond) = setup
    if initial_bond !== nothing && (initial_bond::Bond).bond_category === bond_category
        bonds = scan_bonds(number_to_scan, direction_to_scan, initial_bond::Bond,
                           net, ctx.codelet_count)
        isempty(bonds) && return
        objs = WSObject[(bonds[1]::Bond).left_object]
        for b in bonds
            push!(objs, (b::Bond).right_object)
        end
        propose_group!(ctx, objs, bonds, group_category, (bonds[1]::Bond).direction)
        return
    end
    # a singleton group made of one letter
    object isa Group && return
    singleton_direction =
        group_category === net[:plato_samegrp] ? nothing :
        begin
            left_support = descriptor_support(net[:plato_left], s)
            right_support = descriptor_support(net[:plato_right], s)
            stochastic_pick(ctx.rng, [net[:plato_left], net[:plato_right]],
                            [left_support, right_support])
        end
    objs = WSObject[object]
    bonds = Any[]
    singleton_group = make_group(net, s, group_category, net[:plato_letter_category],
                                 singleton_direction, object, object, objs, bonds,
                                 ctx.codelet_count)
    coin = random_real(ctx.rng, 1.0)
    coin < sub_from_1(single_letter_group_probability(ctx.rng, singleton_group, net)) && return
    propose_group!(ctx, objs, bonds, group_category, singleton_direction)
    return
end

"""`top-down-group-scout:direction`."""
function top_down_group_scout_direction(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    direction = args[1]::Node
    scope = args[2]
    s = scope === nothing ?
        choose_string_by(ctx, x -> get_direction_relevance(x, direction)) :
        scope::WorkspaceString
    setup = group_scout_setup(ctx, s)
    setup === nothing && return
    (object, direction_to_scan, number_to_scan, initial_bond) = setup
    initial_bond === nothing && return
    (initial_bond::Bond).direction === direction || return
    bond_category = (initial_bond::Bond).bond_category
    group_category = get_related_node(bond_category, net[:plato_group_category],
                                      net[:plato_identity])::Node
    bonds = scan_bonds(number_to_scan, direction_to_scan, initial_bond::Bond,
                       net, ctx.codelet_count)
    isempty(bonds) && return
    objs = WSObject[(bonds[1]::Bond).left_object]
    for b in bonds
        push!(objs, (b::Bond).right_object)
    end
    propose_group!(ctx, objs, bonds, group_category, direction)
    return
end

"""`group-scout:whole-string` — look for a run of bonds reaching from the
leftmost object to the rightmost."""
function group_scout_whole_string(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    strings = all_strings(ctx)
    s = stochastic_pick(ctx.rng, strings,
                        vcat([x.average_intra_string_unhappiness for x in strings], [0]))
    isempty((s::WorkspaceString).bonds) && return
    leftmost_object = choose_leftmost_object(ctx.rng, s::WorkspaceString, net)
    leftmost_object === nothing && return
    right_bonds = right_adjacent_bonds(leftmost_object::WSObject)
    bonded_objects = right_adjacent_objects(leftmost_object::WSObject)
    (isempty(right_bonds) || !rightmost_in_string(bonded_objects[end])) && return
    chosen_bond = random_pick(ctx.rng, right_bonds)::Bond
    polarized_bonds = polarize_bonds(right_bonds, chosen_bond.bond_facet,
                                     chosen_bond.bond_category, chosen_bond.direction,
                                     net, ctx.codelet_count)
    isempty(polarized_bonds) && return
    group_category = get_related_node(chosen_bond.bond_category,
                                      net[:plato_group_category],
                                      net[:plato_identity])::Node
    propose_group!(ctx, bonded_objects, polarized_bonds, group_category,
                   chosen_bond.direction)
    return
end

"""`(choose-leftmost-object)` — among the objects described as leftmost,
weighted by relative importance."""
function choose_leftmost_object(rng::PyRandom, s::WorkspaceString, net::Slipnet)
    candidates = WSObject[o for o in objects(s)
                          if get_descriptor_for(o, net[:plato_string_position_category]) ===
                             net[:plato_leftmost]]
    isempty(candidates) && return nothing
    return stochastic_pick(rng, candidates, [o.relative_importance for o in candidates])
end

"""`(group-evaluation-probability x)`, equal to
`T/100 * tanh(x/10) + (1 - T/100) * x/100`. At high temperature it is strongly
boosted toward 1 for all but the weakest groups; at low temperature it
approaches the identity. Copycat struggles to build weak groups in strings like
`xwyxzy` without this."""
group_evaluation_probability(x) =
    pct(TEMPERATURE[]) * (sdiv(2, 1 + exp(sdiv(-x, 5))) - 1) +
    sub_from_1(pct(TEMPERATURE[])) * pct(x)

"""`group-evaluator`."""
function group_evaluator(ctx::MetacatCtx, args::Vector{Any})
    g = args[1]::Group
    TEMPERATURE[] = ctx.temperature
    update_structure_strength!(g, ctx)
    strength = g.strength
    coin = random_real(ctx.rng, 1.0)
    if coin < sub_from_1(group_evaluation_probability(strength))
        delete_proposed_group!(g.string, g)
        return
    end
    activate_from_workspace!(g.bond_category)
    g.direction === nothing || activate_from_workspace!(g.direction::Node)
    g.proposal_level = EVALUATED
    post!(ctx.coderack, make_codelet(CODELET_TYPES[:group_builder], strength, Any[g]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`group-builder` — fight everything incompatible, consolidate if needed, and
build."""
function group_builder(ctx::MetacatCtx, args::Vector{Any})
    g = args[1]::Group
    net = ctx.net
    s = g.string
    group_category = g.group_category
    direction = g.direction
    equivalent_group = get_equivalent_group(s, g)
    constituent_bonds = g.constituent_bonds
    constituent_objects = g.constituent_objects
    delete_proposed_group!(s, g)
    if equivalent_group !== nothing
        # the group is already there; donate any descriptions it lacks
        eg = equivalent_group::Group
        for d in eg.descriptions
            activate_from_workspace!(d.descriptor)
        end
        for d in g.descriptions
            description_present(eg, d) && continue
            build_description!(make_description(eg, d.description_type, d.descriptor,
                                                ctx.codelet_count), net)
        end
        return
    end
    all(b -> bond_present(s, b::Bond) || flipped_bond_present(s, b::Bond, net),
        constituent_bonds) || return
    bonds_to_be_flipped =
        group_category === net[:plato_samegrp] ? Any[] :
        Any[b for b in (get_equivalent_flipped_bond(s, x::Bond, net)
                        for x in constituent_bonds) if b !== nothing]
    if !isempty(bonds_to_be_flipped) &&
       !wins_all_fights(ctx.rng, ctx, g, get_letter_span(g), bonds_to_be_flipped, 1)
        return
    end
    incompatible_groups = get_incompatible_groups(g)
    for other in incompatible_groups
        og = other::Group
        won = (og.group_category === group_category && og.direction === direction) ?
              wins_fight(ctx.rng, ctx, g, g.group_length, og, og.group_length) :
              wins_fight(ctx.rng, ctx, g, 1, og, 1)
        won || return
    end
    incompatible_bridges = vcat(get_incompatible_bridges(g, :vertical, net),
                                get_incompatible_bridges(g, :horizontal, net))
    if !isempty(incompatible_bridges) &&
       !wins_all_fights(ctx.rng, ctx, g, 1, incompatible_bridges, 1)
        return
    end
    for other in incompatible_groups
        break_group!(other::Group, net, ctx)
    end
    for bridge in incompatible_bridges
        break_bridge!(bridge::Bridge, ctx)
    end
    g = consolidate_group(ctx, g, constituent_objects, constituent_bonds)
    g === nothing && return
    build_group!(g::Group, net, ctx)
    return
end

"""The three-way `cond` at the end of `group-builder`. A letter-sameness group
containing other letter-sameness groups, or a length-sameness group containing
other length groups, is REBUILT flat over its letters rather than nested;
anything else just adopts the built versions of its bonds. Returns the group to
build, or nothing if the codelet has to fizzle."""
function consolidate_group(ctx::MetacatCtx, g::Group, constituent_objects, constituent_bonds)
    net = ctx.net
    s = g.string
    group_category = g.group_category
    direction = g.direction
    if group_category === net[:plato_samegrp] &&
       g.group_bond_facet === net[:plato_letter_category] &&
       any(o -> o isa Group, constituent_objects)
        letters = g.letters
        for o in constituent_objects
            o isa Group && break_group!(o::Group, net, ctx)
        end
        letter_bonds = adjacency_map(letters) do l1, l2
            bonded(l1, l2) && return l1.right_bond
            new_bond = make_bond(net, l1, l2, net[:plato_sameness],
                                 net[:plato_letter_category],
                                 get_descriptor_for(l1, net[:plato_letter_category])::Node,
                                 get_descriptor_for(l2, net[:plato_letter_category])::Node)
            build_bond!(new_bond, net)
            return new_bond
        end
        new_group = make_group(net, s, group_category, net[:plato_letter_category],
                               direction, letters[1], letters[end], letters,
                               Any[b for b in letter_bonds], ctx.codelet_count)
        description_type_present(g, net[:plato_length]) &&
            attach_length_description!(new_group, net)
        return new_group
    elseif group_category === net[:plato_samegrp] &&
           g.group_bond_facet === net[:plato_length] &&
           any(o -> length_group(o, net), constituent_objects)
        new_constituents = WSObject[]
        for o in constituent_objects
            if length_group(o, net)
                append!(new_constituents, (o::Group).constituent_objects)
            else
                push!(new_constituents, o)
            end
        end
        for o in constituent_objects
            length_group(o, net) && break_group!(o::Group, net, ctx)
        end
        all_same([get_platonic_length(o, net) for o in new_constituents]) || return nothing
        group_bonds = adjacency_map(new_constituents) do g1, g2
            bonded(g1, g2) && return g1.right_bond
            new_bond = make_bond(net, g1, g2, net[:plato_sameness], net[:plato_length],
                                 get_platonic_length(g1, net)::Node,
                                 get_platonic_length(g2, net)::Node)
            build_bond!(new_bond, net)
            return new_bond
        end
        new_group = make_group(net, s, group_category, net[:plato_length], direction,
                               new_constituents[1], new_constituents[end],
                               new_constituents, Any[b for b in group_bonds],
                               ctx.codelet_count)
        attach_length_description!(new_group, net)
        return new_group
    else
        new_bonds = Any[]
        for x in constituent_bonds
            b = x::Bond
            if bond_present(s, b)
                push!(new_bonds, get_equivalent_bond(s, b))
            else
                flipped_bond = get_equivalent_flipped_bond(s, b, net)::Bond
                break_bond!(flipped_bond, net)
                build_bond!(b, net)
                push!(new_bonds, b)
            end
        end
        g.constituent_bonds = new_bonds
        return g
    end
end

register_codelet_type!(:top_down_group_scout_category, top_down_group_scout_category)
register_codelet_type!(:top_down_group_scout_direction, top_down_group_scout_direction)
register_codelet_type!(:group_scout_whole_string, group_scout_whole_string)
register_codelet_type!(:group_evaluator, group_evaluator)
register_codelet_type!(:group_builder, group_builder)
