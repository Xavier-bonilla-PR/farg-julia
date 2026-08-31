# Ported from Metacat's workspace-structures.ss, descriptions.ss,
# workspace-objects.ss and workspace-strings.ss, plus the workspace
# initialisation and value-update passes from run.ss.
#
# This layer covers the workspace as it exists before any perceptual structure
# is built: the three (or four) letter-strings, the letters in them, and the
# descriptions attached to those letters. Bonds, groups and bridges come next;
# where a formula here branches on them, this port takes the same branch the
# Scheme does when none exist.
#
# As in the slipnet, lists are CONSed, so descriptions come out in reverse
# order of attachment, and that order is visible through
# `choose-relevant-description-by-activation`.

const PROPOSED = 1
const EVALUATED = 2
const BUILT = 3

abstract type WSObject end

mutable struct WorkspaceString
    string_type::Symbol            # :initial :modified :target :answer
    letter_categories::Vector{Node}
    letters::Vector{WSObject}
    groups::Vector{WSObject}
    bonds::Vector{Any}
    # groups whose left / right edge sits at each position, newest first
    left_edge_groups::Vector{Vector{WSObject}}
    right_edge_groups::Vector{Vector{WSObject}}
    # proposed (not yet built) bonds, keyed by from/to object id
    proposed_bonds::Dict{Tuple{Int,Int},Vector{Any}}
    print_name::String
    translated::Bool
    average_intra_string_unhappiness::Int
    next_id_num::Int
end

mutable struct Description
    object::WSObject
    string::WorkspaceString
    description_type::Node
    descriptor::Node
    # workspace-structure fields
    time_stamp::Int
    strength::Int
    proposal_level::Int
    enclosing_group::Union{Nothing,WSObject}
end

mutable struct Letter <: WSObject
    string::WorkspaceString
    letter_category::Node
    string_pos::Int
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

"""`(get-bridge bridge-orientation)`."""
get_bridge(o::WSObject, orientation::Symbol) =
    orientation === :horizontal ? o.horizontal_bridge : o.vertical_bridge

function update_bridge!(o::WSObject, orientation::Symbol, bridge)
    if orientation === :horizontal
        o.horizontal_bridge = bridge
    else
        o.vertical_bridge = bridge
    end
    return o
end

"""`(get-all-descriptions)` — groups also contribute their bond descriptions."""
all_descriptions(o::Letter) = o.descriptions

get_string(o::Letter) = o.string
left_string_pos(o::Letter) = o.string_pos
right_string_pos(o::Letter) = o.string_pos
print_name(o::Letter) = o.letter_category.lowercase_name
ascii_name(o::Letter) = string(print_name(o), ":", o.string_pos)

objects(s::WorkspaceString) = vcat(s.letters, s.groups)
string_length(s::WorkspaceString) = length(s.letter_categories)

leftmost_in_string(o::Letter) = o.string_pos == 0
rightmost_in_string(o::Letter) = o.string_pos == string_length(o.string) - 1
spans_whole_string(o::Letter) = string_length(o.string) == 1
"""`(middle-in-string?)` — NB this is NOT positional arithmetic. An object is
"in the middle" when its ungrouped left neighbour is the string's leftmost
object and its ungrouped right neighbour is its rightmost, which for an
ungrouped string means only the centre of a three-object string qualifies.
Shared by letters and groups."""
function middle_in_string(o::WSObject)
    left_neighbor = ungrouped_left_neighbor(o)
    right_neighbor = ungrouped_right_neighbor(o)
    left_neighbor === nothing && return false
    right_neighbor === nothing && return false
    return leftmost_in_string(left_neighbor::WSObject) &&
           rightmost_in_string(right_neighbor::WSObject)
end

"""A neighbour counts as ungrouped when it has no enclosing group, or its
enclosing group already nests this object."""
function ungrouped_neighbor(o::WSObject, neighbors)
    for n in neighbors
        g = n.enclosing_group
        if g === nothing || nested_member(g::WSObject, o)
            return n
        end
    end
    return nothing
end
ungrouped_left_neighbor(o::WSObject) = ungrouped_neighbor(o, all_left_neighbors(o))
ungrouped_right_neighbor(o::WSObject) = ungrouped_neighbor(o, all_right_neighbors(o))

nested_member(::Letter, ::WSObject) = false

# --- descriptions -----------------------------------------------------------

function make_description(object::WSObject, description_type::Node, descriptor::Node,
                          codelet_count::Int)
    return Description(object, get_string(object), description_type, descriptor,
                       codelet_count, 0, 0, nothing)
end

"""`(new-description ...)` — build a description and CONS it on."""
function new_description!(object::WSObject, description_type::Node, descriptor::Node,
                          codelet_count::Int = 0)
    d = make_description(object, description_type, descriptor, codelet_count)
    d.proposal_level = BUILT
    pushfirst!(object.descriptions, d)
    return d
end

relevant(d::Description) = fully_active(d.description_type)
conceptual_depth(d::Description) = d.descriptor.conceptual_depth
descriptor_activation(d::Description) = d.descriptor.activation

get_relevant_descriptions(o::WSObject) = [d for d in o.descriptions if relevant(d)]

function get_descriptor_for(o::WSObject, description_type::Node)
    idx = findfirst(d -> d.description_type === description_type, o.descriptions)
    return idx === nothing ? nothing : o.descriptions[idx].descriptor
end

description_type_present(o::WSObject, t::Node) =
    any(d -> d.description_type === t, o.descriptions)

"""`contains?` — whether one object encloses another. With no groups yet, an
object contains only itself's group chain, so this is false for distinct
letters."""
contains_object(outer::WSObject, inner::WSObject) = false

function calculate_local_support(d::Description)
    n = 0
    for other in objects(d.string)
        other === d.object && continue
        (contains_object(d.object, other) || contains_object(other, d.object)) && continue
        if any(od -> od.description_type === d.description_type, other.descriptions)
            n += 1
        end
    end
    n == 0 && return 0
    n == 1 && return 20
    n == 2 && return 60
    n == 3 && return 90
    return 100
end

calculate_internal_strength(d::Description) = d.descriptor.conceptual_depth
calculate_external_strength(d::Description) =
    sdiv(calculate_local_support(d) + d.description_type.activation, 2)

"""Themes are not ported yet; with no active themes `(maximum '())` is 0,
which is what the Scheme returns here too."""
get_thematic_compatibility(::Description) = 0

"""`(update-strength)` from workspace-structures.ss."""
function update_strength!(s)
    internal = calculate_internal_strength(s)
    external = calculate_external_strength(s)
    intrinsic = weighted_average([internal, external], [internal, sub_from_100(internal)])
    compatibility = get_thematic_compatibility(s)
    thematic_weight = abs(compatibility)
    s.strength = sround(weighted_average([compatibility > 0 ? 100 : 0, intrinsic],
                                         [thematic_weight, sub_from_1(thematic_weight)]))
    return s
end

get_weakness(s) = sub_from_100(sexpt(s.strength, 0.95))

# --- objects ----------------------------------------------------------------

function update_raw_importance!(o::WSObject)
    result = min(300, ssum([descriptor_activation(d) for d in get_relevant_descriptions(o)]))
    o.raw_importance = o.enclosing_group !== nothing ? 2 // 3 * result : result
    return o
end

function update_intra_string_unhappiness!(o::WSObject)
    o.intra_string_unhappiness =
        if spans_whole_string(o)
            0
        elseif o.enclosing_group !== nothing
            sub_from_100((o.enclosing_group::WSObject).strength)
        else
            bonds = incident_bonds(o)
            if isempty(bonds)
                100
            elseif leftmost_in_string(o) || rightmost_in_string(o)
                sub_from_100(sround(1 // 3 * bonds[1].strength))
            else
                sub_from_100(sround(1 // 6 * ssum([b.strength for b in bonds])))
            end
        end
    return o
end

"""`(get-incident-bonds)` — left bond first, then right, dropping absent ones."""
function incident_bonds(o::WSObject)
    bs = Any[]
    o.left_bond === nothing || push!(bs, o.left_bond)
    o.right_bond === nothing || push!(bs, o.right_bond)
    return bs
end

"""`(get-all-left-neighbors)` — the letter immediately to the left, plus any
groups whose RIGHT edge sits at that position."""
function all_left_neighbors(o::WSObject)
    leftmost_in_string(o) && return WSObject[]
    left_pos = left_string_pos(o) - 1
    return WSObject[o.string.letters[left_pos + 1],
                    o.string.right_edge_groups[left_pos + 1]...]
end

"""`(get-all-right-neighbors)` — the letter immediately to the right, plus any
groups whose LEFT edge sits at that position."""
function all_right_neighbors(o::WSObject)
    rightmost_in_string(o) && return WSObject[]
    right_pos = right_string_pos(o) + 1
    return WSObject[o.string.letters[right_pos + 1],
                    o.string.left_edge_groups[right_pos + 1]...]
end

function choose_left_neighbor(rng::PyRandom, o::WSObject)
    ns = all_left_neighbors(o)
    isempty(ns) && return nothing
    return stochastic_pick(rng, ns, [n.intra_string_salience for n in ns])
end

function choose_right_neighbor(rng::PyRandom, o::WSObject)
    ns = all_right_neighbors(o)
    isempty(ns) && return nothing
    return stochastic_pick(rng, ns, [n.intra_string_salience for n in ns])
end

disjoint_objects(a::WSObject, b::WSObject) =
    right_string_pos(a) < left_string_pos(b) || left_string_pos(a) > right_string_pos(b)

"""With no bridges or groups yet, both weaknesses come out at 100. Note that
each string type assigns only the dimensions that apply to it: a modified
string never gets a vertical value, and a target string (outside justify mode)
never gets a horizontal one, so those stay at their initial 0."""
function update_inter_string_unhappiness!(o::WSObject)
    horizontal_weakness = 100
    vertical_weakness = 100
    t = o.string.string_type
    if t === :initial
        o.horizontal_inter_string_unhappiness = horizontal_weakness
        o.vertical_inter_string_unhappiness = vertical_weakness
    elseif t === :modified
        o.horizontal_inter_string_unhappiness = horizontal_weakness
    elseif t === :target
        o.vertical_inter_string_unhappiness = vertical_weakness
    elseif t === :answer
        o.horizontal_inter_string_unhappiness = horizontal_weakness
    end
    return o
end

function update_average_unhappiness!(o::WSObject)
    t = o.string.string_type
    vals = t === :initial  ? [o.intra_string_unhappiness,
                              o.horizontal_inter_string_unhappiness,
                              o.vertical_inter_string_unhappiness] :
           t === :modified ? [o.intra_string_unhappiness,
                              o.horizontal_inter_string_unhappiness] :
           t === :target   ? [o.intra_string_unhappiness,
                              o.vertical_inter_string_unhappiness] :
                             [o.intra_string_unhappiness,
                              o.horizontal_inter_string_unhappiness]
    o.average_unhappiness = sround(sdiv(ssum(vals), length(vals)))
    return o
end

function update_intra_string_salience!(o::WSObject)
    o.intra_string_salience = o.salience_clamped ? 100 :
        sround(4 // 5 * o.intra_string_unhappiness + 1 // 5 * o.relative_importance)
    return o
end

function update_inter_string_salience!(o::WSObject)
    if o.salience_clamped
        o.horizontal_inter_string_salience = 100
        o.vertical_inter_string_salience = 100
        return o
    end
    h() = sround(1 // 5 * o.horizontal_inter_string_unhappiness +
                 4 // 5 * o.relative_importance)
    v() = sround(1 // 5 * o.vertical_inter_string_unhappiness +
                 4 // 5 * o.relative_importance)
    t = o.string.string_type
    if t === :initial
        o.horizontal_inter_string_salience = h()
        o.vertical_inter_string_salience = v()
    elseif t === :modified
        o.horizontal_inter_string_salience = h()
    elseif t === :target
        o.vertical_inter_string_salience = v()
    elseif t === :answer
        o.horizontal_inter_string_salience = h()
    end
    return o
end

function update_average_salience!(o::WSObject)
    t = o.string.string_type
    vals = t === :initial  ? [o.intra_string_salience,
                              o.horizontal_inter_string_salience,
                              o.vertical_inter_string_salience] :
           t === :modified ? [o.intra_string_salience,
                              o.horizontal_inter_string_salience] :
           t === :target   ? [o.intra_string_salience,
                              o.vertical_inter_string_salience] :
                             [o.intra_string_salience,
                              o.horizontal_inter_string_salience]
    o.average_salience = sround(sdiv(ssum(vals), length(vals)))
    return o
end

function update_object_values!(o::WSObject)
    update_intra_string_unhappiness!(o)
    update_inter_string_unhappiness!(o)
    update_average_unhappiness!(o)
    update_intra_string_salience!(o)
    update_inter_string_salience!(o)
    update_average_salience!(o)
    for d in o.descriptions
        update_strength!(d)
    end
    return o
end

function choose_relevant_description_by_activation(rng::PyRandom, o::WSObject)
    ds = get_relevant_descriptions(o)
    isempty(ds) && return nothing
    return stochastic_pick(rng, ds, [descriptor_activation(d) for d in ds])
end

# --- strings ----------------------------------------------------------------

"""`(update-all-relative-importances)`."""
function update_all_relative_importances!(s::WorkspaceString)
    objs = objects(s)
    total = ssum([o.raw_importance for o in objs])
    if total == 0
        importance = sround(100 * sdiv(1, length(objs)))
        for o in objs
            o.relative_importance = importance
        end
    else
        for o in objs
            o.relative_importance = sround(100 * sdiv(o.raw_importance, total))
        end
    end
    return s
end

function update_average_intra_string_unhappiness!(s::WorkspaceString)
    vals = [o.intra_string_unhappiness for o in objects(s)]
    s.average_intra_string_unhappiness = sround(sdiv(ssum(vals), length(vals)))
    return s
end

"""`(make-workspace-string ...)`."""
function make_workspace_string(net::Slipnet, string_type::Symbol, sym::AbstractString)
    cats = [net[Symbol("plato_", c)] for c in sym]
    n = length(cats)
    s = WorkspaceString(string_type, cats, WSObject[], WSObject[], Any[],
                        [WSObject[] for _ in 1:n], [WSObject[] for _ in 1:n],
                        Dict{Tuple{Int,Int},Vector{Any}}(),
                        String(sym), false, 0, 0)
    for (position, cat) in enumerate(cats)
        letter = Letter(s, cat, position - 1, 0, Description[],
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, nothing, false,
                        nothing, nothing, Any[], Any[], nothing, nothing, 0, 0, 0)
        # (make-letter ...) attaches these two, in this order
        new_description!(letter, net[:plato_object_category], net[:plato_letter])
        new_description!(letter, net[:plato_letter_category], cat)
        letter.id_num = s.next_id_num
        s.next_id_num += 1
        push!(s.letters, letter)
    end
    return s
end

"""`(add-string-position-descriptions-to-letters string)` from run.ss."""
function add_string_position_descriptions_to_letters!(net::Slipnet, s::WorkspaceString)
    n = string_length(s)
    if n == 1
        new_description!(s.letters[1], net[:plato_string_position_category],
                         net[:plato_single])
    else
        new_description!(s.letters[1], net[:plato_string_position_category],
                         net[:plato_leftmost])
        new_description!(s.letters[end], net[:plato_string_position_category],
                         net[:plato_rightmost])
        if isodd(n)
            middle = s.letters[struncate(sdiv(n, 2)) + 1]
            new_description!(middle, net[:plato_string_position_category],
                             net[:plato_middle])
        end
    end
    return s
end

"""`(update-workspace-values)` from run.ss, restricted to the strings that
exist at this stage of the port.

NB: this updates the strength of every workspace STRUCTURE first - bonds, and
later groups, bridges and rules - before touching the objects, because object
unhappiness is computed from the strengths of the bonds incident on it. Passing
the rng is what lets a bond's external strength do its stochastic local-density
walk; it is optional so the pre-bond layers can call this without one."""
function update_workspace_values!(strings::Vector{WorkspaceString},
                                  rng::Union{Nothing,PyRandom} = nothing,
                                  net::Union{Nothing,Slipnet} = nothing)
    if rng !== nothing && net !== nothing
        # (tell *workspace* 'get-structures) is bonds, then groups, then
        # bridges and rules, each gathered across all strings in turn.
        for s in strings, structure in s.bonds
            update_structure_strength!(structure, net::Slipnet, rng::PyRandom)
        end
        for s in strings, structure in s.groups
            update_structure_strength!(structure, net::Slipnet, rng::PyRandom)
        end
    end
    objs = vcat((objects(s) for s in strings)...)
    for o in objs
        update_raw_importance!(o)
    end
    for s in strings
        update_all_relative_importances!(s)
    end
    for o in objs
        update_object_values!(o)
    end
    for s in strings
        update_average_intra_string_unhappiness!(s)
    end
    return strings
end

"""The workspace-initialisation sequence from init-mcat, as far as this layer
of the port reaches."""
function init_workspace(net::Slipnet, initial::AbstractString, modified::AbstractString,
                        target::AbstractString)
    foreach(reset!, net.nodes)
    strings = [make_workspace_string(net, :initial, initial),
               make_workspace_string(net, :modified, modified),
               make_workspace_string(net, :target, target)]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    if any(s -> string_length(s) == 1, strings)
        set_activation!(net[:plato_object_category], MAX_ACTIVATION)
    end
    for s in strings, o in objects(s), d in o.descriptions
        set_activation!(d.descriptor, MAX_ACTIVATION)
    end
    update_workspace_values!(strings)
    for n in net.initially_clamped_nodes
        clamp_activation!(n, MAX_ACTIVATION)
    end
    return strings
end

"""`(distinguishing-descriptor? descriptor)` — whether no other object in the
same string carries this descriptor. Letters compare against the string's other
letters; groups have their own rule, added when groups are ported."""
function distinguishing_descriptor(net::Slipnet, o::Letter, descriptor::Node)
    (descriptor === net[:plato_letter] || descriptor === net[:plato_group] ||
     any(n -> n === descriptor, net.numbers)) && return false
    for other in o.string.letters
        other === o && continue
        for d in other.descriptions
            d.descriptor === descriptor && return false
        end
    end
    return true
end
