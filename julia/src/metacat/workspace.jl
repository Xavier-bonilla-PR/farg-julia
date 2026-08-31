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
    # workspace-structure fields
    time_stamp::Int
    strength::Int
    proposal_level::Int
end

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
function middle_in_string(o::Letter)
    n = string_length(o.string)
    return isodd(n) && o.string_pos == struncate(sdiv(n, 2))
end

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
            # no bonds exist yet, so this is the empty-bonds branch
            100
        end
    return o
end

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
    s = WorkspaceString(string_type, cats, WSObject[], WSObject[], String(sym), false, 0, 0)
    for (position, cat) in enumerate(cats)
        letter = Letter(s, cat, position - 1, 0, Description[],
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, nothing, false, 0, 0, 0)
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
exist at this stage of the port."""
function update_workspace_values!(strings::Vector{WorkspaceString})
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
