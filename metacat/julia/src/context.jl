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
    themespace::Themespace
    initial_string::WorkspaceString
    modified_string::WorkspaceString
    target_string::WorkspaceString
    temperature::Int
    codelet_count::Int
    # Built bridges, CONSed, one list per bridge type. The Scheme also keeps a
    # vector indexed by object1 id; nothing reads it that the object own
    # horizontal_bridge / vertical_bridge field does not already answer.
    top_bridges::Vector{Bridge}
    bottom_bridges::Vector{Bridge}
    vertical_bridges::Vector{Bridge}
    # Proposed bridges, keyed by (object1 id, object2 id) per type. NB a
    # FLIPPED group keeps the id of the group it was flipped from, precisely so
    # that its proposed bridges land in the same slot.
    proposed_top_bridges::Dict{Tuple{Int,Int},Vector{Bridge}}
    proposed_bottom_bridges::Dict{Tuple{Int,Int},Vector{Bridge}}
    proposed_vertical_bridges::Dict{Tuple{Int,Int},Vector{Bridge}}
    # workspace-level averages, and the mapping strengths derived from them
    average_intra_string_unhappiness::Int
    average_top_inter_string_unhappiness::Int
    average_bottom_inter_string_unhappiness::Int
    average_vertical_inter_string_unhappiness::Int
    average_unhappiness::Int
    top_mapping_strength::Int
    bottom_mapping_strength::Int
    vertical_mapping_strength::Int
end

"""A context with empty bridge storage and zeroed workspace averages, which is
what `(tell *workspace* 'initialize)` leaves behind."""
MetacatCtx(net::Slipnet, rng::PyRandom, coderack::Coderack, ts::Themespace,
           initial::WorkspaceString, modified::WorkspaceString, target::WorkspaceString,
           temperature::Int, codelet_count::Int) =
    MetacatCtx(net, rng, coderack, ts, initial, modified, target, temperature,
               codelet_count,
               Bridge[], Bridge[], Bridge[],
               Dict{Tuple{Int,Int},Vector{Bridge}}(),
               Dict{Tuple{Int,Int},Vector{Bridge}}(),
               Dict{Tuple{Int,Int},Vector{Bridge}}(),
               0, 0, 0, 0, 0, 0, 0, 0)

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
    return update_structure_strength!(b, ctx.net, ctx.rng, ctx.themespace)
end
function update_structure_strength!(g::Group, ctx::MetacatCtx)
    TEMPERATURE[] = ctx.temperature
    return update_structure_strength!(g, ctx.net, ctx.rng, ctx.themespace)
end
function update_structure_strength!(b::Bridge, ctx::MetacatCtx)
    TEMPERATURE[] = ctx.temperature
    # a bridge's external strength is the summed strength of the OTHER bridges
    # of its type that support it, so it needs the workspace's real bridge list
    return update_structure_strength!(b, ctx.net, get_all_bridges(ctx), ctx.themespace)
end

# --- bridges in the workspace -----------------------------------------------

"""`(get-bridges bridge-type)`."""
get_bridges(ctx::MetacatCtx, bridge_type::Symbol) =
    bridge_type === :top    ? ctx.top_bridges :
    bridge_type === :bottom ? ctx.bottom_bridges : ctx.vertical_bridges

get_all_bridges(ctx::MetacatCtx) =
    vcat(ctx.top_bridges, ctx.bottom_bridges, ctx.vertical_bridges)

proposed_bridge_table(ctx::MetacatCtx, bridge_type::Symbol) =
    bridge_type === :top    ? ctx.proposed_top_bridges :
    bridge_type === :bottom ? ctx.proposed_bottom_bridges : ctx.proposed_vertical_bridges

add_bridge!(ctx::MetacatCtx, b::Bridge) = (pushfirst!(get_bridges(ctx, b.bridge_type), b); ctx)

function delete_bridge!(ctx::MetacatCtx, b::Bridge)
    l = get_bridges(ctx, b.bridge_type)
    i = findfirst(x -> x === b, l)
    i === nothing || deleteat!(l, i)
    return ctx
end

function add_proposed_bridge!(ctx::MetacatCtx, b::Bridge)
    key = (b.object1.id_num, b.object2.id_num)
    push!(get!(proposed_bridge_table(ctx, b.bridge_type), key, Bridge[]), b)
    return ctx
end

function delete_proposed_bridge!(ctx::MetacatCtx, b::Bridge)
    table = proposed_bridge_table(ctx, b.bridge_type)
    key = (b.object1.id_num, b.object2.id_num)
    haskey(table, key) || return ctx
    v = table[key]
    i = findfirst(x -> x === b, v)
    i === nothing || deleteat!(v, i)
    return ctx
end

"""`(get-all-slippages bridge-type)`."""
get_all_slippages(ctx::MetacatCtx, bridge_type::Symbol) =
    ConceptMapping[cm for b in get_bridges(ctx, bridge_type) for cm in get_slippages(b)]

delete_proposed_structure!(b::Bridge, ctx::MetacatCtx) = delete_proposed_bridge!(ctx, b)

"""`(delete-proposed-vertical-bridges object)` and its horizontal twin — clears
the proposed-bridge table's row or column for an object that is going away.
Which of the two depends on which string the object is in, since a bridge is
keyed by (object1 id, object2 id) and object ids are only unique per string."""
function delete_proposed_bridges!(ctx::MetacatCtx, o::WSObject)
    s = get_string(o)
    for (table, from_string, to_string) in
        ((ctx.proposed_vertical_bridges, ctx.initial_string, ctx.target_string),
         (ctx.proposed_top_bridges, ctx.initial_string, ctx.modified_string))
        for key in collect(keys(table))
            if (s === from_string && key[1] == o.id_num) ||
               (s === to_string && key[2] == o.id_num)
                delete!(table, key)
            end
        end
    end
    return ctx
end

spanning_bridge_exists(ctx::MetacatCtx, bridge_type::Symbol) =
    any(b -> b.spanning_bridge, get_bridges(ctx, bridge_type))

# --- workspace-level values -------------------------------------------------

"""The two strings a bridge type maps between."""
bridge_type_strings(ctx::MetacatCtx, bridge_type::Symbol) =
    bridge_type === :top ? (ctx.initial_string, ctx.modified_string) :
                           (ctx.initial_string, ctx.target_string)

"""`(spanning-group-possible? string)` — a whole-string group already exists, or
the string's top-level objects run in one unbroken relation under some bond
facet."""
function spanning_group_possible(s::WorkspaceString, net::Slipnet)
    any(g -> spans_whole_string(g::Group), s.groups) && return true
    objs = sort(WSObject[o for o in objects(s) if o.enclosing_group === nothing],
                by = left_string_pos)
    for facet in instance_nodes(net[:plato_bond_facet])
        relations = Union{Nothing,Node}[]
        for i in 1:(length(objs) - 1)
            d1 = get_descriptor_for(objs[i], facet)
            d2 = get_descriptor_for(objs[i + 1], facet)
            push!(relations, (d1 === nothing || d2 === nothing) ? nothing :
                             label_between(d1::Node, d2::Node, net[:plato_identity]))
        end
        all(r -> r !== nothing, relations) && all_same(relations) && return true
    end
    return false
end

"""`(get-covered-letters)`."""
get_covered_letters(b::Bridge) = vcat(get_letters(b.object1), get_letters(b.object2))

"""`(maximal-mapping? bridge-type)` — the letters covered by bridges of that
type are exactly the letters of the two strings."""
function maximal_mapping(ctx::MetacatCtx, bridge_type::Symbol)
    s1, s2 = bridge_type_strings(ctx, bridge_type)
    covered = WSObject[]
    for b in get_bridges(ctx, bridge_type), l in get_covered_letters(b)
        any(x -> x === l, covered) || push!(covered, l)
    end
    all_letters = vcat(s1.letters, s2.letters)
    return all(l -> any(x -> x === l, covered), all_letters) &&
           all(l -> any(x -> x === l, all_letters), covered)
end

"""`(update-average-unhappiness-values)` plus the mapping strengths derived from
it. A mapping strength is the complement of the average inter-string
unhappiness, except that it is HALVED while a spanning group is still possible
on both sides — the model should not settle for a letter-by-letter mapping when
a whole-string one might yet appear — and squashed through a tanh once the
mapping is maximal but still not spanning."""
function update_workspace_averages!(ctx::MetacatCtx)
    all_objs = workspace_objects(ctx)
    top_objs = vcat(objects(ctx.initial_string), objects(ctx.modified_string))
    vertical_objs = vcat(objects(ctx.initial_string), objects(ctx.target_string))
    importances(l) = [o.relative_importance for o in l]
    ctx.average_intra_string_unhappiness =
        sround(weighted_average([o.intra_string_unhappiness for o in all_objs],
                                importances(all_objs)))
    ctx.average_top_inter_string_unhappiness =
        sround(weighted_average([o.horizontal_inter_string_unhappiness for o in top_objs],
                                importances(top_objs)))
    ctx.average_vertical_inter_string_unhappiness =
        sround(weighted_average([o.vertical_inter_string_unhappiness for o in vertical_objs],
                                importances(vertical_objs)))
    ctx.average_unhappiness =
        sround(weighted_average([o.average_unhappiness for o in all_objs],
                                importances(all_objs)))
    net = ctx.net
    raw_top = sub_from_100(ctx.average_top_inter_string_unhappiness)
    raw_vertical = sub_from_100(ctx.average_vertical_inter_string_unhappiness)
    ctx.top_mapping_strength =
        spanning_bridge_exists(ctx, :top) ? raw_top :
        (spanning_group_possible(ctx.initial_string, net) &&
         spanning_group_possible(ctx.modified_string, net)) ? sround(1 // 2 * raw_top) :
        maximal_mapping(ctx, :top) ? sround(100 * tanh(1 // 40 * raw_top)) : raw_top
    ctx.vertical_mapping_strength =
        spanning_bridge_exists(ctx, :vertical) ? raw_vertical :
        (spanning_group_possible(ctx.initial_string, net) &&
         spanning_group_possible(ctx.target_string, net)) ? sround(1 // 2 * raw_vertical) :
        maximal_mapping(ctx, :vertical) ? sround(100 * tanh(1 // 40 * raw_vertical)) :
        raw_vertical
    return ctx
end

get_mapping_strength(ctx::MetacatCtx, bridge_type::Symbol) =
    bridge_type === :top    ? ctx.top_mapping_strength :
    bridge_type === :bottom ? ctx.bottom_mapping_strength : ctx.vertical_mapping_strength

get_min_mapping_strength(ctx::MetacatCtx) =
    min(ctx.top_mapping_strength, ctx.vertical_mapping_strength)

"""`(update-workspace-values)` in full: structures — bonds, then groups, then
bridges — followed by the objects and the per-string and workspace-level
averages."""
function update_workspace_values!(ctx::MetacatCtx)
    TEMPERATURE[] = ctx.temperature
    strings = all_strings(ctx)
    for s in strings, b in s.bonds
        update_structure_strength!(b, ctx.net, ctx.rng, ctx.themespace)
    end
    for s in strings, g in s.groups
        update_structure_strength!(g, ctx.net, ctx.rng, ctx.themespace)
    end
    all_bridges = get_all_bridges(ctx)
    for b in all_bridges
        update_structure_strength!(b, ctx.net, all_bridges, ctx.themespace)
    end
    update_workspace_values!(strings, nothing, nothing, ctx.themespace)
    update_workspace_averages!(ctx)
    return ctx
end
