# The group codelet pipeline, ported from the codelet bodies in groups.ss.
#
# Same scout -> evaluator -> builder shape as the bond and description
# pipelines, but the builder is by far the most involved in the model: a group
# can lose fights to flipped bonds, to other groups, and to bridges, and on
# winning it may CONSOLIDATE — a sameness group proposed over objects that are
# themselves sameness groups collapses them all into one flat group, rebuilding
# the bonds it needs.
#
# Three scouts:
#   top-down-group-scout:category   — a group category asks for a run of bonds
#                                     of its matching bond category
#   top-down-group-scout:direction  — a direction asks for a run of bonds
#                                     running that way
#   group-scout:whole-string        — looks for bonds spanning a whole string

# --- string-level helpers ---------------------------------------------------

"""`(get-num-of-bonds-to-scan)` — from the string's bond-scan distribution:
values 0..n-1 weighted by their squares, so long scans are favoured."""
function get_num_of_bonds_to_scan(rng::PyRandom, s::WorkspaceString)
    n = string_length(s)
    values = collect(0:(n - 1))
    return stochastic_pick(rng, values, [v * v for v in values])
end

"""`(choose-leftmost-object)` — among objects described as leftmost, weighted
by relative importance."""
function choose_leftmost_object(rng::PyRandom, s::WorkspaceString, net::Slipnet)
    candidates = WSObject[o for o in objects(s)
                          if get_descriptor_for(o, net[:plato_string_position_category]) ===
                             net[:plato_leftmost]]
    isempty(candidates) && return nothing
    return stochastic_pick(rng, candidates, [o.relative_importance for o in candidates])
end

"""`(get-equivalent-group group)` — the built group with the same leftmost
object, category, direction and length. Reads the `group-vector` slot rather
than searching the group list; see the note on that field in workspace.jl."""
function get_equivalent_group(s::WorkspaceString, g::Group)
    any(x -> x === g, s.groups) && return g
    other = get(s.group_by_leftmost_id, g.left_object.id_num, nothing)
    other === nothing && return nothing
    o = other::Group
    return (o.group_category === g.group_category && o.direction === g.direction &&
            o.group_length == g.group_length) ? o : nothing
end

add_proposed_group!(s::WorkspaceString, g::Group) = (pushfirst!(s.proposed_groups, g); s)

function delete_proposed_group!(s::WorkspaceString, g::Group)
    i = findfirst(x -> x === g, s.proposed_groups)
    i === nothing || deleteat!(s.proposed_groups, i)
    return s
end

"""The `delete-proposed-structure` case for groups; see coderack.jl."""
delete_proposed_structure!(g::Group) = delete_proposed_group!(g.string, g)

"""`(get-equivalent-bond bond)` / `(bond-present? bond)`."""
function get_equivalent_bond(s::WorkspaceString, b::Bond)
    for other in s.bonds
        o = other::Bond
        o.from_object === b.from_object && o.to_object === b.to_object &&
            o.bond_category === b.bond_category && o.direction === b.direction &&
            return o
    end
    return nothing
end
bond_present_in(s::WorkspaceString, b::Bond) = get_equivalent_bond(s, b) !== nothing

"""`(get-equivalent-flipped-bond bond)` — the bond running the other way, with
the opposite category and direction."""
function get_equivalent_flipped_bond(s::WorkspaceString, b::Bond, net::Slipnet)
    opp_cat = get_related_node(b.bond_category, net[:plato_opposite], net[:plato_identity])
    opp_dir = b.direction === nothing ? nothing :
              get_related_node(b.direction::Node, net[:plato_opposite],
                               net[:plato_identity])
    for other in s.bonds
        o = other::Bond
        o.from_object === b.to_object && o.to_object === b.from_object &&
            o.bond_category === opp_cat && o.direction === opp_dir && return o
    end
    return nothing
end
flipped_bond_present_in(s::WorkspaceString, b::Bond, net::Slipnet) =
    get_equivalent_flipped_bond(s, b, net) !== nothing

# --- bond runs --------------------------------------------------------------

"""`(right-adjacent-bonds object)` — the chain of right bonds from here on."""
function right_adjacent_bonds(o::WSObject)
    result = Any[]
    cur = o
    while cur.right_bond !== nothing
        b = cur.right_bond::Bond
        push!(result, b)
        cur = b.right_object
    end
    return result
end

"""`(right-adjacent-objects object)` — that chain's objects, this one first."""
function right_adjacent_objects(o::WSObject)
    result = WSObject[o]
    cur = o
    while cur.right_bond !== nothing
        cur = (cur.right_bond::Bond).right_object
        push!(result, cur)
    end
    return result
end

"""`(polarize-bonds bonds bond-facet bond-category direction)` — all-or-nothing:
every bond must either already match, or be flippable to match. One that does
neither makes the whole run empty."""
function polarize_bonds(bonds, bond_facet, bond_category::Node, direction, net::Slipnet)
    result = Any[]
    for b in bonds
        bb = b::Bond
        bb.bond_facet === bond_facet || return Any[]
        if bb.bond_category === bond_category && bb.direction === direction
            push!(result, bb)
        elseif get_related_node(bb.bond_category, net[:plato_opposite],
                                net[:plato_identity]) === bond_category &&
               (bb.direction === nothing ? nothing :
                get_related_node(bb.direction::Node, net[:plato_opposite],
                                 net[:plato_identity])) === direction
            push!(result, make_flipped_bond(bb, net))
        else
            return Any[]
        end
    end
    return result
end

"""`(get-next-bond bond direction-to-scan)`."""
get_next_bond(b::Bond, direction_to_scan::Node, net::Slipnet) =
    direction_to_scan === net[:plato_left] ? b.left_object.left_bond :
                                             b.right_object.right_bond

"""`(scan-bonds max-num direction-to-scan initial-bond)` — walk outward from a
bond while the facet matches and the category/direction either match or are
both opposite (in which case the bond is flipped into the run)."""
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
            push!(result, make_flipped_bond(b, net))
        else
            break
        end
        n -= 1
        bond = get_next_bond(b, direction_to_scan, net)
    end
    return direction_to_scan === net[:plato_right] ? result : reverse(result)
end

# --- formulas ---------------------------------------------------------------

"""`(length-description-probability group)`."""
function length_description_probability(g::Group, net::Slipnet)
    g.group_length > 5 && return 0
    g.group_length == 1 && return 1
    return temp_adjusted_probability(
        sexpt(0.5, cube(g.group_length) * pct(sub_from_100(net[:plato_length].activation))))
end

"""`(single-letter-group-probability group)`."""
function single_letter_group_probability(rng::PyRandom, g::Group, net::Slipnet)
    n = get_num_of_local_supporting_groups(g)
    exponent = n == 1 ? 4 : n == 2 ? 2 : 1
    return temp_adjusted_probability(
        sexpt(pct(get_local_support(rng, g)) * pct(net[:plato_length].activation),
              exponent))
end

"""`(descriptor-support descriptor string)` — the percentage of the string's
groups carrying that descriptor."""
function descriptor_support(descriptor::Node, s::WorkspaceString)
    gs = s.groups
    isempty(gs) && return 0
    n = count(g -> any(d -> d.descriptor === descriptor, all_descriptions(g)), gs)
    return 100 * sdiv(n, length(gs))
end

"""`(group-evaluation-probability x)` — at high temperature this is boosted
toward 1 for all but the lowest x; at low temperature it approaches the
identity. Copycat had trouble building weak groups in strings like xwyxzy, and
this is Metacat's replacement test."""
group_evaluation_probability(x) =
    pct(TEMPERATURE[]) * (sdiv(2, 1 + sexp_e(sdiv(-x, 5))) - 1) +
    sub_from_1(pct(TEMPERATURE[])) * pct(x)

"""`(attach-length-description group)`."""
function attach_length_description!(g::Group, net::Slipnet)
    get_descriptor_for(g, net[:plato_length]) === nothing || return
    g.platonic_length === nothing && return          # groups longer than five
    new_description!(g, net[:plato_length], g.platonic_length::Node)
    return
end

# --- proposing --------------------------------------------------------------

"""`(propose-group objects bonds group-category direction)`."""
function propose_group!(ctx::MetacatCtx, objs::Vector{WSObject}, bonds,
                        group_category::Node, direction)
    net = ctx.net
    left_object = objs[1]
    right_object = objs[end]
    s = get_string(left_object)
    bond_category = get_related_node(group_category, net[:plato_bond_category],
                                     net[:plato_identity])::Node
    group_bond_facet = isempty(bonds) ? net[:plato_letter_category] :
                       (bonds[1]::Bond).bond_facet
    g = make_group(net, s, group_category, group_bond_facet, direction,
                   left_object, right_object, objs, bonds)
    # stochastic-if* always draws, whether or not the length description lands
    if random_real(ctx.rng, 1.0) < length_description_probability(g, net)
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

"""The string a top-down group scout works in: the given one, or a stochastic
pick over the three weighted by relevance and unhappiness."""
function group_scout_string(ctx::MetacatCtx, scope, relevance)
    scope isa WorkspaceString && return scope::WorkspaceString
    strings = all_strings(ctx)
    weights = [sdiv(relevance(s) + s.average_intra_string_unhappiness, 2) for s in strings]
    return stochastic_pick(ctx.rng, strings, weights)
end

"""The direction a scout scans in: forced at the string's edges, otherwise a
stochastic pick between right and left by activation."""
function direction_to_scan(ctx::MetacatCtx, object::WSObject)
    leftmost_in_string(object) && return ctx.net[:plato_right]
    rightmost_in_string(object) && return ctx.net[:plato_left]
    dirs = [ctx.net[:plato_right], ctx.net[:plato_left]]
    return stochastic_pick(ctx.rng, dirs, [d.activation for d in dirs])::Node
end

# --- the codelets -----------------------------------------------------------

"""`top-down-group-scout:category`. NB the `spans-whole-string?` fizzle is at
the OUTER level, so a chosen object that spans the string ends the codelet
outright — this is the trap that bit the Copycat port too."""
function top_down_group_scout_category(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    group_category = args[1]::Node
    scope = length(args) > 1 ? args[2] : nothing
    bond_category = get_related_node(group_category, net[:plato_bond_category],
                                     net[:plato_identity])::Node
    s = group_scout_string(ctx, scope, x -> get_bond_category_relevance(x, bond_category))
    s === nothing && return
    object = choose_object(ctx.rng, s::WorkspaceString, :intra_string_salience)
    object === nothing && return
    spans_whole_string(object::WSObject) && return
    dir = direction_to_scan(ctx, object::WSObject)
    number_to_scan = get_num_of_bonds_to_scan(ctx.rng, s::WorkspaceString)
    initial_bond = dir === net[:plato_left] ? (object::WSObject).left_bond :
                                              (object::WSObject).right_bond
    if initial_bond !== nothing && (initial_bond::Bond).bond_category === bond_category
        bonds = scan_bonds(number_to_scan, dir, initial_bond::Bond, net)
        isempty(bonds) && return
        objs = WSObject[(bonds[1]::Bond).left_object]
        for b in bonds
            push!(objs, (b::Bond).right_object)
        end
        propose_group!(ctx, objs, bonds, group_category, (bonds[1]::Bond).direction)
        return
    end
    object isa Group && return                       # no singleton group from a group
    singleton_direction = if group_category === net[:plato_samegrp]
        nothing
    else
        # NB right support is the second weight, and both are computed before
        # the pick, so no draw ordering question arises here
        left_support = descriptor_support(net[:plato_left], s::WorkspaceString)
        right_support = descriptor_support(net[:plato_right], s::WorkspaceString)
        stochastic_pick(ctx.rng, [net[:plato_left], net[:plato_right]],
                        [left_support, right_support])
    end
    objs = WSObject[object::WSObject]
    bonds = Any[]
    singleton = make_group(net, s::WorkspaceString, group_category,
                           net[:plato_letter_category], singleton_direction,
                           object::WSObject, object::WSObject, objs, bonds)
    # stochastic-if* on (1- p): always draws, fires when support is too weak
    coin = random_real(ctx.rng, 1.0)
    coin < sub_from_1(single_letter_group_probability(ctx.rng, singleton, net)) && return
    propose_group!(ctx, objs, bonds, group_category, singleton_direction)
    return
end

"""`top-down-group-scout:direction`."""
function top_down_group_scout_direction(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    direction = args[1]::Node
    scope = length(args) > 1 ? args[2] : nothing
    s = group_scout_string(ctx, scope, x -> get_direction_relevance(x, direction))
    s === nothing && return
    object = choose_object(ctx.rng, s::WorkspaceString, :intra_string_salience)
    object === nothing && return
    spans_whole_string(object::WSObject) && return
    dir = direction_to_scan(ctx, object::WSObject)
    number_to_scan = get_num_of_bonds_to_scan(ctx.rng, s::WorkspaceString)
    initial_bond = dir === net[:plato_left] ? (object::WSObject).left_bond :
                                              (object::WSObject).right_bond
    (initial_bond === nothing || (initial_bond::Bond).direction !== direction) && return
    bond_category = (initial_bond::Bond).bond_category
    group_category = get_related_node(bond_category, net[:plato_group_category],
                                      net[:plato_identity])::Node
    bonds = scan_bonds(number_to_scan, dir, initial_bond::Bond, net)
    isempty(bonds) && return
    objs = WSObject[(bonds[1]::Bond).left_object]
    for b in bonds
        push!(objs, (b::Bond).right_object)
    end
    propose_group!(ctx, objs, bonds, group_category, direction)
    return
end

"""`group-scout:whole-string` — a run of bonds covering an entire string."""
function group_scout_whole_string(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    strings = all_strings(ctx)
    s = stochastic_pick(ctx.rng, strings,
                        [x.average_intra_string_unhappiness for x in strings])
    s === nothing && return
    isempty((s::WorkspaceString).bonds) && return
    leftmost_object = choose_leftmost_object(ctx.rng, s::WorkspaceString, net)
    leftmost_object === nothing && return
    right_bonds = right_adjacent_bonds(leftmost_object::WSObject)
    bonded_objects = right_adjacent_objects(leftmost_object::WSObject)
    (isempty(right_bonds) || !rightmost_in_string(bonded_objects[end])) && return
    chosen_bond = random_pick(ctx.rng, right_bonds)::Bond
    polarized = polarize_bonds(right_bonds, chosen_bond.bond_facet,
                               chosen_bond.bond_category, chosen_bond.direction, net)
    isempty(polarized) && return
    group_category = get_related_node(chosen_bond.bond_category,
                                      net[:plato_group_category],
                                      net[:plato_identity])::Node
    propose_group!(ctx, bonded_objects, polarized, group_category, chosen_bond.direction)
    return
end

"""`group-evaluator`."""
function group_evaluator(ctx::MetacatCtx, args::Vector{Any})
    g = args[1]::Group
    update_structure_strength!(g, ctx)
    strength = g.strength
    TEMPERATURE[] = ctx.temperature
    # stochastic-if* on (1- p): always draws, fires when not strong enough
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

"""`(get-incompatible-groups)` — the enclosing groups of this group's own
constituents. NB `remq-duplicates` keeps the LAST of each duplicate group."""
function get_incompatible_groups(g::Group)
    enclosing = WSObject[]
    for o in g.constituent_objects
        o.enclosing_group === nothing || push!(enclosing, o.enclosing_group::WSObject)
    end
    deduped = remq_duplicates(enclosing)
    return WSObject[x for x in deduped if x !== g]
end

"""`group-builder` — the most contested build in the model."""
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
    all(b -> bond_present_in(s, b::Bond) || flipped_bond_present_in(s, b::Bond, net),
        constituent_bonds) || return
    bonds_to_be_flipped = group_category === net[:plato_samegrp] ? Any[] :
        Any[b for b in (get_equivalent_flipped_bond(s, c::Bond, net)
                        for c in constituent_bonds) if b !== nothing]
    if !isempty(bonds_to_be_flipped) &&
       !wins_all_fights(ctx.rng, ctx, g, get_letter_span(g), bonds_to_be_flipped, 1)
        return
    end
    incompatible_groups = get_incompatible_groups(g)
    for ig in incompatible_groups
        won = (ig::Group).group_category === group_category &&
              (ig::Group).direction === direction ?
              wins_fight(ctx.rng, ctx, g, g.group_length, ig, (ig::Group).group_length) :
              wins_fight(ctx.rng, ctx, g, 1, ig, 1)
        won || return
    end
    # incompatible bridges arrive with the bridge codelets
    for ig in incompatible_groups
        break_group!(ig::Group, net)
    end
    g = consolidate_group!(ctx, g, constituent_objects, constituent_bonds, direction)
    g === nothing && return
    build_group!(g, net)
    return
end

"""`(length-group? group)`."""
length_group(g::Group, net::Slipnet) = g.group_bond_facet === net[:plato_length]
length_group(::Letter, ::Slipnet) = false

"""The `cond` at the end of group-builder. A sameness group proposed over
objects that are themselves sameness groups does not nest — it CONSOLIDATES,
breaking the inner groups and rebuilding a single flat group over their parts,
creating whatever bonds that needs. The third branch is the ordinary case: keep
each constituent bond that already exists, and for the rest break the bond
running the other way and build this one. Returns the group to build, or
nothing if the codelet fizzles."""
function consolidate_group!(ctx::MetacatCtx, g::Group, constituent_objects,
                            constituent_bonds, direction)
    net = ctx.net
    s = g.string
    group_category = g.group_category
    if group_category === net[:plato_samegrp] &&
       g.group_bond_facet === net[:plato_letter_category] &&
       any(o -> o isa Group, constituent_objects)
        letters = g.letters
        for o in constituent_objects
            o isa Group && break_group!(o::Group, net)
        end
        letter_bonds = adjacency_map(letters) do l1, l2
            bonded(l1, l2) && return (l1.right_bond)::Bond
            nb = make_bond(net, l1, l2, net[:plato_sameness],
                           net[:plato_letter_category],
                           get_descriptor_for(l1, net[:plato_letter_category])::Node,
                           get_descriptor_for(l2, net[:plato_letter_category])::Node,
                           ctx.codelet_count)
            build_bond!(nb)
            return nb
        end
        new_group = make_group(net, s, group_category, net[:plato_letter_category],
                               direction, letters[1], letters[end], letters,
                               Any[b for b in letter_bonds])
        description_type_present(g, net[:plato_length]) &&
            attach_length_description!(new_group, net)
        return new_group
    elseif group_category === net[:plato_samegrp] &&
           g.group_bond_facet === net[:plato_length] &&
           any(o -> length_group(o, net), constituent_objects)
        new_constituent_groups = WSObject[]
        for o in constituent_objects
            if length_group(o, net)
                append!(new_constituent_groups, (o::Group).constituent_objects)
            else
                push!(new_constituent_groups, o)
            end
        end
        for o in constituent_objects
            length_group(o, net) && break_group!(o::Group, net)
        end
        lengths = [get_platonic_length(o, net) for o in new_constituent_groups]
        # NB this fizzle happens AFTER the inner groups have been broken
        all(x -> x === lengths[1], lengths) || return nothing
        group_bonds = adjacency_map(new_constituent_groups) do g1, g2
            bonded(g1, g2) && return (g1.right_bond)::Bond
            nb = make_bond(net, g1, g2, net[:plato_sameness], net[:plato_length],
                           get_platonic_length(g1, net)::Node,
                           get_platonic_length(g2, net)::Node, ctx.codelet_count)
            build_bond!(nb)
            return nb
        end
        new_group = make_group(net, s, group_category, net[:plato_length], direction,
                               new_constituent_groups[1], new_constituent_groups[end],
                               new_constituent_groups, Any[b for b in group_bonds])
        attach_length_description!(new_group, net)
        return new_group
    else
        # NB Chez's `map` order, not left to right: it decides which bonds get
        # pushed onto the string's bond list first. See scheme_map.
        g.constituent_bonds = scheme_map(constituent_bonds) do b
            equivalent = get_equivalent_bond(s, b::Bond)
            equivalent !== nothing && return equivalent
            flipped = get_equivalent_flipped_bond(s, b::Bond, net)
            flipped === nothing || break_bond!(flipped::Bond)
            build_bond!(b::Bond)
            return b
        end
        return g
    end
end

register_codelet_type!(:top_down_group_scout_category, top_down_group_scout_category)
register_codelet_type!(:top_down_group_scout_direction, top_down_group_scout_direction)
register_codelet_type!(:group_scout_whole_string, group_scout_whole_string)
register_codelet_type!(:group_evaluator, group_evaluator)
register_codelet_type!(:group_builder, group_builder)
