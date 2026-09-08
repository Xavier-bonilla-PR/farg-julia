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
    # `from-to-bond-table`: the built bond running from one object id to
    # another. A sameness bond is registered under both orderings, since it is
    # symmetric. This is a lookup, not a list — at most one bond per ordered
    # pair — which is what makes `bond-present?` exact rather than a scan.
    from_to_bond::Dict{Tuple{Int,Int},Any}
    # `group-vector`: the built group whose LEFTMOST object has this id. The
    # Scheme indexes a vector of `max-object-capacity` and grows it, so its
    # bounds check can never fire for an object that has an id at all; a Dict
    # models the same thing without the capacity bookkeeping.
    group_by_leftmost_id::Dict{Int,Any}
    # `proposed-group-list`. The Scheme also keeps a proposed-group TABLE, but
    # nothing ever reads it — only this list is read, through `get-all-objects`.
    proposed_groups::Vector{Any}
    print_name::String
    translated::Bool
    average_intra_string_unhappiness::Int
    next_id_num::Int
    # `string-image`: the string's appearance under whatever rule is currently
    # being applied to it, a StringImage (images.jl). Untyped because images.jl
    # loads after this file.
    string_image::Any
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
    # A letter's image is made once, at construction, and is then a mutable
    # object that rule application transforms in place — NOT something to
    # rebuild on each read. Untyped because images.jl loads after this file.
    image::Any
    descriptions::Vector{Description}
    raw_importance::Union{Int,Rational{Int}}
    relative_importance::Int
    intra_string_unhappiness::Int
    # `(100- (* 1/2 strength))` for an object whose ENCLOSING GROUP carries the
    # bridge is an exact rational whenever that strength is odd, so these are
    # not integers.
    horizontal_inter_string_unhappiness::Union{Int,Rational{Int}}
    vertical_inter_string_unhappiness::Union{Int,Rational{Int}}
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

"""`(get-concept-pattern)` on a workspace object — every descriptor it carries,
each clamped only if its description type is currently RELEVANT, so an object
described along a dimension nobody cares about contributes a 0. Groups fold in
their bond descriptions, which is what `get-all-descriptions` is for."""
get_concept_pattern(o::WSObject) =
    Any[:concepts,
        Any[Any[d.descriptor, relevant(d) ? MAX_ACTIVATION : 0]
            for d in all_descriptions(o)]...]

"""`(get-all-descriptors)`."""
get_all_descriptors(o::WSObject) = Node[d.descriptor for d in o.descriptions]

get_string(o::Letter) = o.string
left_string_pos(o::Letter) = o.string_pos
right_string_pos(o::Letter) = o.string_pos
print_name(o::Letter) = o.letter_category.lowercase_name
ascii_name(o::Letter) = string(print_name(o), ":", o.string_pos)

objects(s::WorkspaceString) = vcat(s.letters, s.groups)
"""`(get-all-objects)` — includes groups that are only PROPOSED. The
middle-description cleanup walks this, not `get-objects`, so a proposed group
can lose a description it never had a chance to build on."""
all_objects(s::WorkspaceString) = vcat(s.letters, s.groups, s.proposed_groups)
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

nested_member(::Letter, _) = false

"""A workspace string's own extent: `sort-templates` and `disjoint-objects?`
compare it against real objects."""
left_string_pos(::WorkspaceString) = 0
right_string_pos(s::WorkspaceString) = string_length(s) - 1

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

"""`(description-type-present? description-type)` — NB this looks at ALL
descriptions, so a group's bond descriptions count too."""
description_type_present(o::WSObject, t::Node) =
    any(d -> d.description_type === t, all_descriptions(o))

"""`(get-distinguishing-descriptions)`."""
get_distinguishing_descriptions(o::WSObject, net::Slipnet) =
    Description[d for d in o.descriptions
                if distinguishing_descriptor(net, o, d.descriptor)]

"""`(get-relevant-distinguishing-descriptions)`."""
get_relevant_distinguishing_descriptions(o::WSObject, net::Slipnet) =
    Description[d for d in get_distinguishing_descriptions(o, net) if relevant(d)]

"""`(get-descriptions-for-rule)` — the descriptions a rule may name an object
by: where it sits in the string, where it sits in the alphabet, or which letter
it is (a group only when it is a sameness group, since only then does one letter
category describe the whole of it)."""
get_descriptions_for_rule(o::WSObject, net::Slipnet) =
    Description[d for d in get_relevant_distinguishing_descriptions(o, net)
                if d.description_type === net[:plato_string_position_category] ||
                   d.description_type === net[:plato_alphabetic_position_category] ||
                   (d.description_type === net[:plato_letter_category] &&
                    (o isa Letter || (o::Group).group_category === net[:plato_samegrp]))]

"""`(choose-description-for-rule)` — by conceptual depth, temperature-adjusted."""
function choose_description_for_rule(rng::PyRandom, o::WSObject, net::Slipnet)
    ds = get_descriptions_for_rule(o, net)
    isempty(ds) && return nothing
    return stochastic_pick(rng, ds,
                           temp_adjusted_values([conceptual_depth(d) for d in ds]))
end

"""`(singleton-group?)` for a string — one top-level object."""
singleton_group(s::WorkspaceString) = length(get_top_level_objects(s)) == 1

"""`(nested-member? object)` for a string — the string contains everything in
it, at any depth."""
function nested_member(s::WorkspaceString, object)
    tops = get_top_level_objects(s)
    any(o -> o === object, tops) && return true
    return any(o -> nested_member(o, object), tops)
end

"""`(get-bond-facet)` for a string. A group answers with its own bond facet
(groups.jl); a letter has no answer at all, as in the Scheme."""
get_bond_facet(s::WorkspaceString, net::Slipnet) = net[:plato_letter_category]

"""`(get-top-level-objects)` — the string's letters and groups that no group
encloses. NB letters come before groups, as in the Scheme's `append`."""
get_top_level_objects(s::WorkspaceString) =
    WSObject[o for o in vcat(s.letters, s.groups) if o.enclosing_group === nothing]

"""`(get-constituent-objects)` for a string: its top-level objects, left to
right. For a group it is the objects the group was built from (groups.jl)."""
get_constituent_objects(s::WorkspaceString) =
    chez_sort((a, b) -> left_string_pos(a) < left_string_pos(b),
              get_top_level_objects(s))

"""`(get-enclosing-object object)` — the immediately enclosing group, or, for a
top-level object, the string it sits in."""
get_enclosing_object(o::WSObject) =
    o.enclosing_group === nothing ? o.string : o.enclosing_group::WSObject

"""`(get-image)` for a letter. A group's image lives on the group (groups.jl),
and a string's on the string."""
get_image(s::WorkspaceString) = s.string_image

"""`(descriptor-present? descriptor)` — like `description-type-present?`, this
scans ALL descriptions."""
descriptor_present(o::WSObject, descriptor::Node) =
    any(d -> d.descriptor === descriptor, all_descriptions(o))

"""`(get-nesting-level)` — how deeply the object sits inside groups. A
workspace string is at level 0."""
nesting_level(o::WSObject) =
    o.enclosing_group === nothing ? 0 : nesting_level(o.enclosing_group::WSObject) + 1
nesting_level(::WorkspaceString) = 0

"""`(contains? object1 object2)` — whether the first object is a group that has
the second somewhere inside it. Only groups can contain anything, and
`nested-member?` is false for a letter, so this is just the nesting test."""
contains_object(outer::WSObject, inner::WSObject) = nested_member(outer, inner)

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

"""With no themespace there are no active themes, and `(maximum '())` is 0 —
the same answer the Scheme gives before any theme exists."""
get_thematic_compatibility(::Description, ::Nothing) = 0

"""`(update-strength)` from workspace-structures.ss. A structure that fits the
active themes is pulled toward 100, one that fights them toward 0, in
proportion to how strongly the themes feel about it."""
function update_strength!(s, ts = nothing)
    internal = calculate_internal_strength(s)
    external = calculate_external_strength(s)
    intrinsic = weighted_average([internal, external], [internal, sub_from_100(internal)])
    compatibility = get_thematic_compatibility(s, ts)
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

"""`(disjoint-objects? o1 o2)` — untyped in its arguments, as in the Scheme,
because `sort-templates` compares a template's reference object against another
that may be the workspace string itself."""
disjoint_objects(a, b) =
    right_string_pos(a) < left_string_pos(b) || left_string_pos(a) > right_string_pos(b)

"""An object is inter-string unhappy to the extent it is NOT bridged: its own
bridge's strength counts in full, an enclosing group's bridge counts half, and
an object with neither is maximally unhappy.

Each string type assigns only the dimensions that apply to it: a modified
string never gets a vertical value, and a target string (outside justify mode)
never gets a horizontal one, so those stay at their initial 0."""
function update_inter_string_unhappiness!(o::WSObject)
    function weakness(orientation::Symbol)
        own = get_bridge(o, orientation)
        own === nothing || return sub_from_100((own::Bridge).strength)
        g = o.enclosing_group
        g === nothing && return 100
        gb = get_bridge(g::WSObject, orientation)
        # `snorm` because Scheme's tower collapses an exact ratio with
        # denominator 1 back to an integer, and the value is printed.
        return gb === nothing ? 100 :
               snorm(sub_from_100(1 // 2 * (gb::Bridge).strength))
    end
    horizontal_weakness = weakness(:horizontal)
    vertical_weakness = weakness(:vertical)
    t = o.string.string_type
    if t === :initial
        o.horizontal_inter_string_unhappiness = horizontal_weakness
        o.vertical_inter_string_unhappiness = vertical_weakness
    elseif t === :modified
        o.horizontal_inter_string_unhappiness = horizontal_weakness
    elseif t === :target
        o.vertical_inter_string_unhappiness = vertical_weakness
        # In justify mode the target string is bridged HORIZONTALLY too, to the
        # answer string, so it has a horizontal unhappiness like the initial
        # string does.
        JUSTIFY_MODE[] && (o.horizontal_inter_string_unhappiness = horizontal_weakness)
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
           t === :target   ? (JUSTIFY_MODE[] ?
                              [o.intra_string_unhappiness,
                               o.vertical_inter_string_unhappiness,
                               o.horizontal_inter_string_unhappiness] :
                              [o.intra_string_unhappiness,
                               o.vertical_inter_string_unhappiness]) :
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
        JUSTIFY_MODE[] && (o.horizontal_inter_string_salience = h())
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
           t === :target   ? (JUSTIFY_MODE[] ?
                              [o.intra_string_salience,
                               o.vertical_inter_string_salience,
                               o.horizontal_inter_string_salience] :
                              [o.intra_string_salience,
                               o.vertical_inter_string_salience]) :
                             [o.intra_string_salience,
                              o.horizontal_inter_string_salience]
    o.average_salience = sround(sdiv(ssum(vals), length(vals)))
    return o
end

function update_object_values!(o::WSObject, ts = nothing)
    update_intra_string_unhappiness!(o)
    update_inter_string_unhappiness!(o)
    update_average_unhappiness!(o)
    update_intra_string_salience!(o)
    update_inter_string_salience!(o)
    update_average_salience!(o)
    for d in o.descriptions
        update_strength!(d, ts)
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
                        Dict{Tuple{Int,Int},Any}(), Dict{Int,Any}(), Any[],
                        String(sym), false, 0, 0, nothing)
    s.string_image = make_string_image(s, net[:plato_right])
    for (position, cat) in enumerate(cats)
        letter = Letter(s, cat, position - 1, 0, make_letter_image(cat), Description[],
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
                                  net::Union{Nothing,Slipnet} = nothing,
                                  ts = nothing)
    if rng !== nothing && net !== nothing
        # (tell *workspace* 'get-structures) is bonds, then groups, then
        # bridges and rules, each gathered across all strings in turn.
        for s in strings, structure in s.bonds
            update_structure_strength!(structure, net::Slipnet, rng::PyRandom, ts)
        end
        for s in strings, structure in s.groups
            update_structure_strength!(structure, net::Slipnet, rng::PyRandom, ts)
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
        update_object_values!(o, ts)
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
    # NB: `letters` is a Vector{WSObject} because WorkspaceString is defined
    # before Letter and they point at each other, so the element type has to be
    # the abstract one. Naming the concrete type here costs nothing at runtime
    # (the vector only ever holds Letters) and lets `other.descriptions` compile
    # to a fixed field offset instead of a runtime lookup. This loop and its
    # counterpart in groups.jl were ~12% of a run before the annotation.
    for other::Letter in o.string.letters
        other === o && continue
        for d in other.descriptions
            d.descriptor === descriptor && return false
        end
    end
    return true
end

# --- string-level predicates the rule translation needs ---------------------

"""`(top-string?)` — the two strings a TOP rule is about."""
top_string(s::WorkspaceString) =
    s.string_type === :initial || s.string_type === :modified
"""`(vertical-string?)` — the two a VERTICAL bridge runs between."""
vertical_string(s::WorkspaceString) =
    s.string_type === :initial || s.string_type === :target
"""`(bottom-string?)`."""
bottom_string(s::WorkspaceString) =
    s.string_type === :target || s.string_type === :answer

# --- building a string from letter categories --------------------------------
#
# `make_workspace_string` builds a string AND its letters, which is what the
# three real strings need. A TRANSLATED string is built the other way round:
# the string first, then the letters instantiated into it from an image.

"""`(new-workspace-string string-type letter-categories)` — an EMPTY string of
the right shape. Its letters arrive through `add_letter!`."""
function new_workspace_string(net::Slipnet, string_type::Symbol,
                              letter_categories::Vector{Node})
    n = length(letter_categories)
    # The Scheme keeps a letter VECTOR written by position, so letters can in
    # principle arrive out of order. Allocating undefined slots reproduces that
    # and fails loudly on a slot never filled, rather than silently holding a
    # placeholder.
    s = WorkspaceString(string_type, letter_categories, Vector{WSObject}(undef, n),
                        WSObject[], Any[],
                        [WSObject[] for _ in 1:n], [WSObject[] for _ in 1:n],
                        Dict{Tuple{Int,Int},Vector{Any}}(),
                        Dict{Tuple{Int,Int},Any}(), Dict{Int,Any}(), Any[],
                        "", false, 0, 0, nothing)
    s.string_image = make_string_image(s, net[:plato_right])
    return s
end

"""`(make-letter string letter-category position)`."""
function make_letter(net::Slipnet, s::WorkspaceString, cat::Node, position::Int)
    letter = Letter(s, cat, position, 0, make_letter_image(cat), Description[],
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, nothing, false,
                    nothing, nothing, Any[], Any[], nothing, nothing, 0, 0, 0)
    # (make-letter ...) attaches these two, in this order
    new_description!(letter, net[:plato_object_category], net[:plato_letter])
    new_description!(letter, net[:plato_letter_category], cat)
    return letter
end

"""`(assign-id-num object)`."""
function assign_id_num!(s::WorkspaceString, o)
    o.id_num = s.next_id_num
    s.next_id_num += 1
    return o
end

"""`(add-letter letter position)`. The Scheme writes into a vector at
`position`, so letters may arrive out of order; the list is read off later by
`set_letter_list!`."""
function add_letter!(s::WorkspaceString, letter::WSObject, position::Int)
    assign_id_num!(s, letter)
    s.letters[position + 1] = letter
    return s
end

"""`(set-letter-list)` — freeze the letter vector into the list, and take the
string's print name from it."""
function set_letter_list!(s::WorkspaceString)
    s.print_name = join([print_name(l) for l in s.letters])
    return s
end

"""`(mark-as-translated)` on a string."""
mark_string_as_translated!(s::WorkspaceString) = (s.translated = true; s)

"""`(get-instantiated-image-object)` — the object this one turned into under
the rule currently being applied, following a swap if one was made."""
function get_instantiated_image_object(o::WSObject)
    image = get_image(o)
    swapped = image.swapped_image
    return swapped === nothing ? get_instantiated_object(image) :
                                 get_instantiated_object(swapped::Image)
end
