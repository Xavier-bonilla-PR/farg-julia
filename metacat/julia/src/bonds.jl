# Ported from Metacat's bonds.ss.
#
# A bond is a perceived relation between two adjacent objects in a string -
# successor, predecessor or sameness - along one facet (letter category or
# length). Sameness bonds are undirected; the others carry a direction.

mutable struct Bond
    from_object::WSObject
    to_object::WSObject
    left_object::WSObject
    right_object::WSObject
    string::WorkspaceString
    bond_category::Node
    direction::Union{Nothing,Node}
    bond_facet::Node
    from_object_descriptor::Node
    to_object_descriptor::Node
    left_string_pos::Int
    right_string_pos::Int
    bond_importance::Int
    # workspace-structure fields
    time_stamp::Int
    strength::Int
    proposal_level::Int
    enclosing_group::Union{Nothing,WSObject}
end

function make_bond(net::Slipnet, from_object::WSObject, to_object::WSObject,
                   bond_category::Node, bond_facet::Node,
                   from_object_descriptor::Node, to_object_descriptor::Node,
                   codelet_count::Int = 0)
    left_object = left_string_pos(from_object) < left_string_pos(to_object) ?
                  from_object : to_object
    right_object = left_object === from_object ? to_object : from_object
    string = get_string(left_object)
    direction = bond_category === net[:plato_sameness] ? nothing :
                (left_object === from_object ? net[:plato_right] : net[:plato_left])
    return Bond(from_object, to_object, left_object, right_object, string,
                bond_category, direction, bond_facet,
                from_object_descriptor, to_object_descriptor,
                left_string_pos(left_object), right_string_pos(right_object),
                direction === nothing ? 100 : 50,
                codelet_count, 0, 0, nothing)
end

directed(b::Bond) = b.direction !== nothing

bond_leftmost_in_string(b::Bond) = b.left_string_pos == 0
bond_rightmost_in_string(b::Bond) = b.right_string_pos == string_length(b.string) - 1

"""`(bond-degree-of-assoc bond-category)`."""
bond_degree_of_assoc(bond_category::Node) =
    min(100, sround(11 * ssqrt(degree_of_assoc(bond_category))))

function get_num_of_local_supporting_bonds(b::Bond)
    n = 0
    for other in b.string.bonds
        other === b && continue
        if disjoint_objects(b.left_object, other.left_object) &&
           disjoint_objects(b.right_object, other.right_object) &&
           other.bond_category === b.bond_category &&
           other.direction === b.direction
            n += 1
        end
    end
    return n
end

"""`(get-local-density)`. NB: the neighbour walk uses choose-left-neighbor /
choose-right-neighbor, which are stochastic picks, so this consumes random
draws even though it reads like a plain traversal."""
function get_local_density(rng::PyRandom, b::Bond)
    function neighbors(object, chooser)
        result = WSObject[]
        current = object
        while true
            n = chooser(rng, current)
            n === nothing && break
            push!(result, n)
            current = n
        end
        return result
    end
    left_neighbors = neighbors(b.left_object, choose_left_neighbor)
    right_neighbors = neighbors(b.right_object, choose_right_neighbor)
    num_of_bond_slots = length(left_neighbors) + length(right_neighbors)
    matches(bond) = bond !== nothing && bond.bond_category === b.bond_category &&
                    bond.direction === b.direction
    num_of_similar_bonds = count(o -> matches(o.right_bond), left_neighbors) +
                           count(o -> matches(o.left_bond), right_neighbors)
    num_of_bond_slots == 0 && return 100
    return sround(100 * sdiv(num_of_similar_bonds, num_of_bond_slots))
end

function get_local_support(rng::PyRandom, b::Bond)
    number = get_num_of_local_supporting_bonds(b)
    number == 0 && return 0
    density = get_local_density(rng, b)
    adjusted_density = 100 * ssqrt(pct(density))
    number_factor = min(1, sexpt(0.6, sdiv(1, cube(number))))
    return sround(adjusted_density * number_factor)
end

function calculate_internal_strength(b::Bond, net::Slipnet)
    compatibility_factor = typeof(b.from_object) === typeof(b.to_object) ? 1.0 : 0.7
    bond_facet_factor = b.bond_facet === net[:plato_letter_category] ? 1.0 : 0.7
    return sround(compatibility_factor * bond_facet_factor *
                  bond_degree_of_assoc(b.bond_category))
end

"""`(build-bond proposed-bond)` — attaches the bond to its string and objects."""
function build_bond!(b::Bond)
    pushfirst!(b.string.bonds, b)
    pushfirst!(b.from_object.outgoing_bonds, b)
    pushfirst!(b.to_object.incoming_bonds, b)
    b.left_object.right_bond = b
    b.right_object.left_bond = b
    activate_from_workspace!(b.bond_category)
    directed(b) && activate_from_workspace!(b.direction::Node)
    b.proposal_level = BUILT
    return b
end

"""`(get-bond-category from-descriptor to-descriptor)` — sameness if the two
descriptors are the same node, otherwise the slipnet label relating them (which
may be nothing, meaning no bond is possible)."""
get_bond_category_between(d1::Node, d2::Node, net::Slipnet) =
    d1 === d2 ? net[:plato_sameness] : label_between(d1, d2, net[:plato_identity])

"""`(bonded? object1 object2)`."""
function bonded(o1::WSObject, o2::WSObject)
    rb = o1.right_bond
    rb !== nothing && rb.right_object === o2 && return true
    lb = o1.left_bond
    return lb !== nothing && lb.left_object === o2
end

calculate_external_strength(b::Bond, rng::PyRandom) = get_local_support(rng, b)

"""Bonds have no thematic compatibility until themes are ported; the Scheme
falls back to the workspace-structure default of 0."""
function update_structure_strength!(b::Bond, net::Slipnet, rng::PyRandom)
    internal = calculate_internal_strength(b, net)
    external = calculate_external_strength(b, rng)
    intrinsic = weighted_average([internal, external], [internal, sub_from_100(internal)])
    b.strength = sround(weighted_average([0, intrinsic], [0, 1]))
    return b
end
