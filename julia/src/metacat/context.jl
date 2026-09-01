# The pieces of Metacat's global state that codelets read and write.
#
# The Scheme keeps these as top-level variables (*workspace*, *coderack*,
# *temperature*, *codelet-count*, and the string globals). Bundling them into
# one context passed explicitly keeps the port's data flow visible and avoids
# mutable globals, without changing any behaviour.

mutable struct MetacatCtx
    net::Slipnet
    rng::PyRandom
    coderack::Coderack
    initial_string::WorkspaceString
    modified_string::WorkspaceString
    target_string::WorkspaceString
    temperature::Int
    codelet_count::Int
    themespace::Union{Nothing,Themespace}
    # bridges live here rather than on a string, because they span two
    top_bridges::Vector{Bridge}
    bottom_bridges::Vector{Bridge}
    vertical_bridges::Vector{Bridge}
    proposed_top_bridges::Vector{Bridge}
    proposed_bottom_bridges::Vector{Bridge}
    proposed_vertical_bridges::Vector{Bridge}
    # workspace-level averages, recomputed at the end of every update pass
    average_intra_string_unhappiness::Int
    average_top_inter_string_unhappiness::Int
    average_vertical_inter_string_unhappiness::Int
    average_unhappiness::Int
    top_mapping_strength::Int
    bottom_mapping_strength::Int
    vertical_mapping_strength::Int
end

MetacatCtx(net, rng, coderack, i, m, t, temperature, codelet_count,
           themespace::Union{Nothing,Themespace}) =
    MetacatCtx(net, rng, coderack, i, m, t, temperature, codelet_count, themespace,
               Bridge[], Bridge[], Bridge[], Bridge[], Bridge[], Bridge[],
               0, 0, 0, 0, 0, 0, 0)

"""A context with no themespace: structure strengths then use the
workspace-structure default of 0 thematic compatibility, which is what the
pre-themes layers assume."""
MetacatCtx(net, rng, coderack, i, m, t, temperature, codelet_count) =
    MetacatCtx(net, rng, coderack, i, m, t, temperature, codelet_count, nothing)

"""`*non-answer-strings*` — the three strings a non-justify-mode run works on."""
all_strings(ctx::MetacatCtx) =
    WorkspaceString[ctx.initial_string, ctx.modified_string, ctx.target_string]

workspace_objects(ctx::MetacatCtx) = vcat((objects(s) for s in all_strings(ctx))...)
workspace_bonds(ctx::MetacatCtx) = vcat((s.bonds for s in all_strings(ctx))...)
workspace_groups(ctx::MetacatCtx) = vcat((s.groups for s in all_strings(ctx))...)

"""`(object-exists? object)`."""
object_exists(ctx::MetacatCtx, o::WSObject) = any(x -> x === o, workspace_objects(ctx))

# Structure strengths, dispatched through the context so codelets need only
# one call shape. TEMPERATURE is the global the formulas read.
function update_structure_strength!(b::Bond, ctx::MetacatCtx)
    TEMPERATURE[] = ctx.temperature
    return update_structure_strength!(b, ctx.net, ctx.rng)
end
function update_structure_strength!(g::Group, ctx::MetacatCtx)
    TEMPERATURE[] = ctx.temperature
    return update_structure_strength!(g, ctx.net, ctx.rng)
end
function update_structure_strength!(b::Bridge, ctx::MetacatCtx)
    TEMPERATURE[] = ctx.temperature
    # a bridge's external strength is the support it gets from the OTHER built
    # bridges of its type, so it needs the workspace registry
    return update_structure_strength!(b, ctx.net, get_bridges(ctx, b.bridge_type),
                                      ctx.themespace)
end
function update_structure_strength!(d::Description, ctx::MetacatCtx)
    TEMPERATURE[] = ctx.temperature
    return update_strength!(d, ctx.themespace, ctx.net)
end

# --- the workspace aggregate ------------------------------------------------
#
# Bridges span strings, so unlike bonds and groups they have no string to live
# on: the Scheme keeps them on *workspace*, in three lists by bridge type. This
# context plays that role. Along with the lists come the workspace-level
# averages the Scheme recomputes at the end of every update-workspace-values
# pass, and the MAPPING STRENGTHS derived from them — which is what the bridge
# scouts weight their bridge-type choice by.

get_bridges(ctx::MetacatCtx, bridge_type::Symbol) =
    bridge_type === :top ? ctx.top_bridges :
    bridge_type === :bottom ? ctx.bottom_bridges : ctx.vertical_bridges

get_all_bridges(ctx::MetacatCtx) =
    vcat(ctx.top_bridges, ctx.bottom_bridges, ctx.vertical_bridges)

"""`(add-bridge bridge)` — CONSed, so newest first."""
function add_bridge!(ctx::MetacatCtx, b::Bridge)
    pushfirst!(get_bridges(ctx, b.bridge_type), b)
    return ctx
end

function delete_bridge!(ctx::MetacatCtx, b::Bridge)
    list = get_bridges(ctx, b.bridge_type)
    i = findfirst(x -> x === b, list)
    i === nothing || deleteat!(list, i)
    return ctx
end

get_proposed_bridges(ctx::MetacatCtx, bridge_type::Symbol) =
    bridge_type === :top ? ctx.proposed_top_bridges :
    bridge_type === :bottom ? ctx.proposed_bottom_bridges : ctx.proposed_vertical_bridges

add_proposed_bridge!(ctx::MetacatCtx, b::Bridge) =
    (pushfirst!(get_proposed_bridges(ctx, b.bridge_type), b); ctx)

function delete_proposed_bridge!(ctx::MetacatCtx, b::Bridge)
    list = get_proposed_bridges(ctx, b.bridge_type)
    i = findfirst(x -> x === b, list)
    i === nothing || deleteat!(list, i)
    return ctx
end

"""`(break-bridge bridge)`."""
function break_bridge!(ctx::MetacatCtx, b::Bridge)
    update_bridge!(b.object1, b.orientation, nothing)
    update_bridge!(b.object2, b.orientation, nothing)
    delete_bridge!(ctx, b)
    return b
end

"""`(get-all-slippages bridge-type)`."""
get_all_slippages(ctx::MetacatCtx, bridge_type::Symbol) =
    vcat((get_slippages(b) for b in get_bridges(ctx, bridge_type))...,
         ConceptMapping[])

spanning_bridge_exists(ctx::MetacatCtx, bridge_type::Symbol) =
    any(b -> b.spanning_bridge, get_bridges(ctx, bridge_type))

"""The two strings a bridge type maps between."""
function bridge_type_strings(ctx::MetacatCtx, bridge_type::Symbol)
    bridge_type === :top && return (ctx.initial_string, ctx.modified_string)
    bridge_type === :vertical && return (ctx.initial_string, ctx.target_string)
    return (ctx.target_string, ctx.target_string)   # bottom needs the answer string
end

"""`(maximal-mapping? bridge-type)` — whether the bridges of this type between
them cover every letter of both strings."""
function maximal_mapping(ctx::MetacatCtx, bridge_type::Symbol)
    s1, s2 = bridge_type_strings(ctx, bridge_type)
    covered = WSObject[]
    for b in get_bridges(ctx, bridge_type)
        append!(covered, get_covered_letters(b))
    end
    covered = remq_duplicates(covered)
    all_letters = vcat(s1.letters, s2.letters)
    length(covered) == length(all_letters) || return false
    return all(l -> any(c -> c === l, covered), all_letters)
end

"""`(get-top-level-objects)` / `(get-constituent-objects)` for a string: the
objects not enclosed in any group, left to right."""
function constituent_objects(s::WorkspaceString)
    tops = WSObject[o for o in objects(s) if o.enclosing_group === nothing]
    return sort(tops, by = left_string_pos, alg = MergeSort)
end

spanning_group_exists(s::WorkspaceString) = any(g -> spans_whole_string(g), s.groups)

"""`(spanning-group-possible? string)` — could the string be covered by one
group? True if one already exists, or if some bond facet relates every adjacent
pair of top-level objects by the same label."""
function spanning_group_possible(s::WorkspaceString, net::Slipnet)
    spanning_group_exists(s) && return true
    objs = constituent_objects(s)
    length(objs) < 2 && return false
    for facet in instance_nodes(net[:plato_bond_facet])
        relations = adjacency_map(objs) do o1, o2
            d1 = get_descriptor_for(o1, facet)
            d2 = get_descriptor_for(o2, facet)
            (d1 === nothing || d2 === nothing) && return nothing
            return label_between(d1::Node, d2::Node, net[:plato_identity])
        end
        all(r -> r !== nothing, relations) || continue
        all(r -> r === relations[1], relations) && return true
    end
    return false
end

"""`(update-average-unhappiness-values)` — the workspace-level averages, and
the mapping strengths derived from them. NB `%justify-mode%` is off, so the
bottom mapping is not computed."""
function update_average_unhappiness_values!(ctx::MetacatCtx)
    net = ctx.net
    all_objects = workspace_objects(ctx)
    top_objects = vcat(objects(ctx.initial_string), objects(ctx.modified_string))
    vertical_objects = vcat(objects(ctx.initial_string), objects(ctx.target_string))
    importances(l) = [o.relative_importance for o in l]
    ctx.average_intra_string_unhappiness =
        sround(weighted_average([o.intra_string_unhappiness for o in all_objects],
                                importances(all_objects)))
    ctx.average_top_inter_string_unhappiness =
        sround(weighted_average([o.horizontal_inter_string_unhappiness
                                 for o in top_objects], importances(top_objects)))
    ctx.average_vertical_inter_string_unhappiness =
        sround(weighted_average([o.vertical_inter_string_unhappiness
                                 for o in vertical_objects],
                                importances(vertical_objects)))
    ctx.average_unhappiness =
        sround(weighted_average([o.average_unhappiness for o in all_objects],
                                importances(all_objects)))
    raw_top = sub_from_100(ctx.average_top_inter_string_unhappiness)
    raw_vertical = sub_from_100(ctx.average_vertical_inter_string_unhappiness)
    ctx.top_mapping_strength =
        mapping_strength(ctx, :top, raw_top, ctx.initial_string, ctx.modified_string, net)
    ctx.vertical_mapping_strength =
        mapping_strength(ctx, :vertical, raw_vertical, ctx.initial_string,
                         ctx.target_string, net)
    return ctx
end

"""The `cond` behind each mapping strength. NB `100*` is `(round (* 100 x))`,
and the tanh makes this the one inexact step in the chain."""
function mapping_strength(ctx::MetacatCtx, bridge_type::Symbol, raw,
                          s1::WorkspaceString, s2::WorkspaceString, net::Slipnet)
    spanning_bridge_exists(ctx, bridge_type) && return raw
    (spanning_group_possible(s1, net) && spanning_group_possible(s2, net)) &&
        return sround((1 // 2) * raw)
    maximal_mapping(ctx, bridge_type) && return sround(100 * stanh((1 // 40) * raw))
    return raw
end

get_mapping_strength(ctx::MetacatCtx, bridge_type::Symbol) =
    bridge_type === :top ? ctx.top_mapping_strength :
    bridge_type === :bottom ? ctx.bottom_mapping_strength : ctx.vertical_mapping_strength

"""`(update-workspace-values)` in full, including bridges and the workspace
averages. The strings-only version in workspace.jl is what the pre-bridge
layers call; this one is the whole thing."""
function update_workspace_values!(ctx::MetacatCtx)
    TEMPERATURE[] = ctx.temperature
    strings = all_strings(ctx)
    # STRUCTURES before OBJECTS: bonds, then groups, then bridges
    for s in strings, b in s.bonds
        update_structure_strength!(b::Bond, ctx)
    end
    for s in strings, g in s.groups
        update_structure_strength!(g::Group, ctx)
    end
    for b in get_all_bridges(ctx)
        update_structure_strength!(b, ctx)
    end
    objs = workspace_objects(ctx)
    for o in objs
        update_raw_importance!(o)
    end
    for s in strings
        update_all_relative_importances!(s)
    end
    for o in objs
        update_object_values!(o, ctx.themespace, ctx.net)
    end
    for s in strings
        update_average_intra_string_unhappiness!(s)
    end
    update_average_unhappiness_values!(ctx)
    return ctx
end

"""`(build-bridge bridge-orientation bridge)` — the structural part lives in
bridges.jl; this adds the workspace registration the Scheme does in the middle
of it. Nothing between the two draws, so the split is not observable."""
function build_bridge!(ctx::MetacatCtx, b::Bridge)
    build_bridge!(b, ctx.net)
    add_bridge!(ctx, b)
    return b
end
