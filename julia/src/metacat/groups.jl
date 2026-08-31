# Ported from Metacat's groups.ss.
#
# A group is a chunk of a string perceived as a unit - a run of successor
# bonds, a run of sameness bonds - and is itself a workspace object, so groups
# can nest and can be bonded and bridged like letters.

mutable struct Group <: WSObject
    string::WorkspaceString
    group_category::Node
    group_bond_facet::Union{Nothing,Node}
    direction::Union{Nothing,Node}
    left_object::WSObject
    right_object::WSObject
    constituent_objects::Vector{WSObject}
    constituent_bonds::Vector{Any}
    left_string_pos::Int
    right_string_pos::Int
    bond_category::Node
    group_length::Int
    platonic_length::Union{Nothing,Node}
    all_letter_group::Bool
    letters::Vector{WSObject}
    image::Image
    initial_letter_category::Union{Nothing,Node}
    middle_object::Union{Nothing,WSObject}
    bond_descriptions::Vector{Description}
    print_name::Union{Nothing,String}
    ascii_name_::String
    # shared workspace-object fields
    id_num::Int
    descriptions::Vector{Description}
    raw_importance::Union{Int,Rational{Int}}
    relative_importance::Int
    intra_string_unhappiness::Int
    horizontal_inter_string_unhappiness::Int
    vertical_inter_string_unhappiness::Int
    average_unhappiness::Int
    intra_string_salience::Int
    horizontal_inter_string_salience::Int
    vertical_inter_string_salience::Int
    average_salience::Int
    enclosing_group::Union{Nothing,WSObject}
    salience_clamped::Bool
    left_bond::Union{Nothing,Any}
    right_bond::Union{Nothing,Any}
    outgoing_bonds::Vector{Any}
    incoming_bonds::Vector{Any}
    horizontal_bridge::Union{Nothing,Any}
    vertical_bridge::Union{Nothing,Any}
    # workspace-structure fields
    time_stamp::Int
    strength::Int
    proposal_level::Int
end

singleton_group(g::Group) = g.group_length == 1
singleton_group(::Letter) = false
top_level_member(g::Group, object::WSObject) = any(o -> o === object, g.constituent_objects)
all_descriptions(g::Group) = vcat(g.descriptions, g.bond_descriptions)
get_letter_span(o::Letter) = 1
get_letter_span(g::Group) = length(g.letters)

get_string(g::Group) = g.string
left_string_pos(g::Group) = g.left_string_pos
right_string_pos(g::Group) = g.right_string_pos
print_name(g::Group) = g.print_name
ascii_name(g::Group) = g.ascii_name_
get_letters(o::Letter) = WSObject[o]
get_letters(g::Group) = g.letters
get_initial_letter_category(o::Letter) = o.letter_category
get_initial_letter_category(g::Group) = g.initial_letter_category
get_platonic_length(o::Letter, net::Slipnet) = net[:plato_one]
get_platonic_length(g::Group, ::Slipnet) = g.platonic_length
get_image(o::Letter) = make_letter_image(o.letter_category)
get_image(g::Group) = g.image

leftmost_in_string(g::Group) = g.left_string_pos == 0
rightmost_in_string(g::Group) = g.right_string_pos == string_length(g.string) - 1
spans_whole_string(g::Group) = leftmost_in_string(g) && rightmost_in_string(g)
string_spanning_group(g::Group) = spans_whole_string(g)
string_spanning_group(::Letter) = false

"""`(nested-member? object)` — whether the object is somewhere inside this
group's constituent tree."""
function nested_member(g::Group, object::WSObject)
    for o in g.constituent_objects
        o === object && return true
        o isa Group && nested_member(o::Group, object) && return true
    end
    return false
end

"""`(number->platonic-number n)`."""
number_to_platonic_number(net::Slipnet, n::Int) =
    n > length(net.numbers) ? nothing : net.numbers[n]

function new_bond_description!(g::Group, description_type::Node, descriptor::Node,
                               codelet_count::Int = 0)
    d = make_description(g, description_type, descriptor, codelet_count)
    d.proposal_level = BUILT
    pushfirst!(g.bond_descriptions, d)
    return d
end

"""`(make-group ...)` — builds the group and attaches its descriptions in the
order groups.ss does, which is the order they come back out in reverse."""
function make_group(net::Slipnet, string::WorkspaceString, group_category::Node,
                    group_bond_facet::Union{Nothing,Node}, direction::Union{Nothing,Node},
                    left_object::WSObject, right_object::WSObject,
                    objs::Vector{WSObject}, bonds::Vector{Any})
    ordered_objects = direction === net[:plato_left] ? reverse(objs) : objs
    initial_letter_category = get_descriptor_for(ordered_objects[1],
                                                 net[:plato_letter_category])
    bond_category = getRelated = get_related_node(group_category, net[:plato_bond_category],
                                                  net[:plato_identity])::Node
    group_length = length(objs)
    middle_idx = findfirst(o -> get_descriptor_for(o, net[:plato_string_position_category]) ===
                                net[:plato_middle], objs)
    letter_relation = group_length > 1 ?
        relationship_between([get_initial_letter_category(o) for o in ordered_objects],
                             net[:plato_identity]) :
        (bond_category === net[:plato_sameness] ? net[:plato_identity] : bond_category)
    length_relation = group_length > 1 ?
        relationship_between([get_platonic_length(o, net) for o in ordered_objects],
                             net[:plato_identity]) :
        net[:plato_identity]
    image = make_image(initial_letter_category, group_bond_facet, letter_relation,
                       length_relation, direction === nothing ? net[:plato_right] : direction,
                       [get_image(o) for o in ordered_objects])

    g = Group(string, group_category, group_bond_facet, direction,
              left_object, right_object, objs, bonds,
              left_string_pos(left_object), right_string_pos(right_object),
              bond_category, group_length,
              number_to_platonic_number(net, group_length),
              all(o -> o isa Letter, objs),
              vcat((get_letters(o) for o in objs)...),
              image, initial_letter_category,
              middle_idx === nothing ? nothing : objs[middle_idx],
              Description[], nothing, "",
              0, Description[], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              nothing, false, nothing, nothing, Any[], Any[], nothing, nothing, 0, 0, 0)

    new_description!(g, net[:plato_object_category], net[:plato_group])
    new_description!(g, net[:plato_group_category], group_category)
    new_bond_description!(g, net[:plato_bond_category], g.bond_category)
    direction === nothing || new_description!(g, net[:plato_direction_category], direction)
    if spans_whole_string(g)
        new_description!(g, net[:plato_string_position_category], net[:plato_whole])
    elseif leftmost_in_string(g)
        new_description!(g, net[:plato_string_position_category], net[:plato_leftmost])
    elseif middle_in_string(g)
        new_description!(g, net[:plato_string_position_category], net[:plato_middle])
    elseif rightmost_in_string(g)
        new_description!(g, net[:plato_string_position_category], net[:plato_rightmost])
    end
    new_bond_description!(g, net[:plato_bond_facet], group_bond_facet::Node)
    # LettCtgy descriptions go on even for successor/predecessor groups, so that
    # horizontal bridges such as [abc] --> [bcd] can be built.
    if group_bond_facet === net[:plato_letter_category]
        new_description!(g, net[:plato_letter_category], initial_letter_category::Node)
        if group_category === net[:plato_samegrp]
            g.print_name = (initial_letter_category::Node).uppercase_name
        end
    end
    set_ascii_name!(g, net)
    return g
end

function set_ascii_name!(g::Group, net::Slipnet)
    head = g.print_name !== nothing ? g.print_name :
           (g.direction === net[:plato_right] ? ">" :
            g.direction === net[:plato_left] ? "<" : string(g.group_length))
    tail = spans_whole_string(g) ? "*" : string(g.left_string_pos, ",", g.right_string_pos)
    g.ascii_name_ = string("[", head, "]:", tail)
    return g
end

"""`(build-group proposed-group flipped?)` — attaches the group to its string
and its constituents, activates its descriptors, and invalidates any "middle"
descriptions the new grouping has made false. The trace and graphics parts of
the Scheme are not ported."""
function build_group!(g::Group, net::Slipnet)
    g.id_num = g.string.next_id_num
    g.string.next_id_num += 1
    pushfirst!(g.string.left_edge_groups[g.left_string_pos + 1], g)
    pushfirst!(g.string.right_edge_groups[g.right_string_pos + 1], g)
    pushfirst!(g.string.groups, g)
    for o in g.constituent_objects
        o.enclosing_group = g
    end
    for b in g.constituent_bonds
        b.enclosing_group = g
    end
    for d in g.descriptions
        activate_from_workspace!(d.descriptor)
    end
    g.proposal_level = BUILT
    spans_whole_string(g) ||
        delete_invalid_string_position_middle_descriptions!(g.string, net)
    return g
end

"""Building a non-spanning group can make an object no longer "middle"; those
descriptions are removed. The bridge cleanup in the Scheme applies once bridges
are ported."""
function delete_invalid_string_position_middle_descriptions!(s::WorkspaceString,
                                                             net::Slipnet)
    for object in objects(s)
        if any(d -> d.descriptor === net[:plato_middle], object.descriptions) &&
           !middle_in_string(object)
            idx = findfirst(d -> d.description_type === net[:plato_string_position_category],
                            object.descriptions)
            idx === nothing || deleteat!(object.descriptions, idx)
        end
    end
    return s
end

function get_num_of_local_supporting_groups(g::Group)
    n = 0
    for other in g.string.groups
        other === g && continue
        if disjoint_objects(g, other) && other.group_category === g.group_category &&
           other.direction === g.direction
            n += 1
        end
    end
    return n
end

"""`(get-local-density)` — the neighbour walk steps up to an enclosing group
whenever it lands on a letter that has one."""
function get_local_density(rng::PyRandom, g::Group)
    spans_whole_string(g) && return 100
    function neighbors(object, chooser)
        result = WSObject[]
        current = object
        while true
            n = chooser(rng, current)
            n === nothing && break
            grp = n.enclosing_group
            step = (n isa Letter && grp !== nothing) ? grp::WSObject : n
            push!(result, step)
            current = step
        end
        return result
    end
    other_objects = vcat(neighbors(g, choose_left_neighbor),
                         neighbors(g, choose_right_neighbor))
    num_of_objects = length(other_objects)
    num_of_similar_groups = count(other_objects) do o
        o isa Group && disjoint_objects(g, o) &&
            (o::Group).group_category === g.group_category &&
            (o::Group).direction === g.direction
    end
    num_of_objects == 0 && return 100
    return sround(100 * sdiv(num_of_similar_groups, num_of_objects))
end

function get_local_support(rng::PyRandom, g::Group)
    num = get_num_of_local_supporting_groups(g)
    num == 0 && return 0
    density = get_local_density(rng, g)
    adjusted_density = 100 * ssqrt(pct(density))
    num_factor = min(1, sexpt(0.6, sdiv(1, cube(num))))
    return sround(adjusted_density * num_factor)
end

function calculate_internal_strength(g::Group, net::Slipnet)
    bond_factor = degree_of_assoc(g.bond_category) *
        ((g.group_bond_facet !== nothing &&
          g.group_bond_facet === net[:plato_letter_category]) ? 1 : 1 // 2)
    length_factor = g.group_length == 1 ? 5 :
                    g.group_length == 2 ? 40 :
                    g.group_length == 3 ? 60 : 90
    bond_factor_weight = sexpt(bond_factor, 0.98)
    length_factor_weight = sub_from_100(bond_factor_weight)
    return sround(weighted_average([bond_factor, length_factor],
                                   [bond_factor_weight, length_factor_weight]))
end

calculate_external_strength(g::Group, rng::PyRandom) =
    spans_whole_string(g) ? 100 : get_local_support(rng, g)

function update_structure_strength!(g::Group, net::Slipnet, rng::PyRandom)
    internal = calculate_internal_strength(g, net)
    external = calculate_external_strength(g, rng)
    intrinsic = weighted_average([internal, external], [internal, sub_from_100(internal)])
    g.strength = sround(weighted_average([0, intrinsic], [0, 1]))
    return g
end

"""`(distinguishing-descriptor? descriptor)` for groups: compare against the
string's other groups, excluding this group's supergroup and its subgroups."""
function distinguishing_descriptor(net::Slipnet, g::Group, descriptor::Node)
    (descriptor === net[:plato_letter] || descriptor === net[:plato_group] ||
     any(n -> n === descriptor, net.numbers)) && return false
    supergroup = g.enclosing_group
    subgroups = [o for o in g.constituent_objects if o isa Group]
    for other in g.string.groups
        (other === g || other === supergroup ||
         any(sg -> sg === other, subgroups)) && continue
        for d in other.descriptions
            d.descriptor === descriptor && return false
        end
    end
    return true
end

"""`(break-group group)` — recursively breaks any enclosing group first, then
detaches this one and the bonds incident on it. The bridge handling is added
once the bridge codelets are ported."""
function break_group!(g::Group, net::Slipnet)
    s = g.string
    g.enclosing_group === nothing || break_group!(g.enclosing_group::Group, net)
    i = findfirst(x -> x === g, s.groups)
    i === nothing || deleteat!(s.groups, i)
    for (pos, list) in ((g.left_string_pos, s.left_edge_groups),
                        (g.right_string_pos, s.right_edge_groups))
        j = findfirst(x -> x === g, list[pos + 1])
        j === nothing || deleteat!(list[pos + 1], j)
    end
    for b in incident_bonds(g)
        break_bond!(b::Bond)
    end
    for o in g.constituent_objects
        o.enclosing_group = nothing
    end
    for b in g.constituent_bonds
        b.enclosing_group = nothing
    end
    spans_whole_string(g) ||
        delete_invalid_string_position_middle_descriptions!(s, net)
    return g
end
