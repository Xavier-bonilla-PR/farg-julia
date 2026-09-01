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
    # the workspace's bridge bookkeeping. Each list is CONSed, so the newest
    # bridge comes first; the proposed-bridge tables are keyed on the pair of
    # object id-nums, exactly as the Scheme's 2-D tables are indexed.
    top_bridges::Vector{Any}
    bottom_bridges::Vector{Any}
    vertical_bridges::Vector{Any}
    proposed_bridges::Dict{Symbol,Dict{Tuple{Int,Int},Vector{Any}}}
    top_mapping_strength::Int
    bottom_mapping_strength::Int
    vertical_mapping_strength::Int
end

MetacatCtx(net, rng, coderack, initial, modified, target, temperature, codelet_count) =
    MetacatCtx(net, rng, coderack, initial, modified, target, temperature, codelet_count,
               Any[], Any[], Any[],
               Dict(t => Dict{Tuple{Int,Int},Vector{Any}}()
                    for t in (:top, :bottom, :vertical)),
               0, 0, 0)

"""`*non-answer-strings*` — the three strings a non-justify-mode run works on."""
all_strings(ctx::MetacatCtx) =
    WorkspaceString[ctx.initial_string, ctx.modified_string, ctx.target_string]

workspace_objects(ctx::MetacatCtx) = vcat((objects(s) for s in all_strings(ctx))...)
workspace_bonds(ctx::MetacatCtx) = vcat((s.bonds for s in all_strings(ctx))...)
workspace_groups(ctx::MetacatCtx) = vcat((s.groups for s in all_strings(ctx))...)

"""`(object-exists? object)`."""
object_exists(ctx::MetacatCtx, o::WSObject) = any(x -> x === o, workspace_objects(ctx))

# --- bridges ----------------------------------------------------------------

"""`(get-bridges bridge-type)`."""
function bridge_list(ctx::MetacatCtx, bridge_type::Symbol)
    bridge_type === :top && return ctx.top_bridges
    bridge_type === :bottom && return ctx.bottom_bridges
    return ctx.vertical_bridges
end

"""`(get-all-bridges)`, in the Scheme's top / bottom / vertical order."""
all_bridges(ctx::MetacatCtx) =
    vcat(ctx.top_bridges, ctx.bottom_bridges, ctx.vertical_bridges)

"""`(get-mapping-strength bridge-type)`."""
function mapping_strength(ctx::MetacatCtx, bridge_type::Symbol)
    bridge_type === :top && return ctx.top_mapping_strength
    bridge_type === :bottom && return ctx.bottom_mapping_strength
    return ctx.vertical_mapping_strength
end

add_bridge!(ctx::MetacatCtx, b::Bridge) =
    (pushfirst!(bridge_list(ctx, b.bridge_type), b); ctx)

function delete_bridge!(ctx::MetacatCtx, b::Bridge)
    l = bridge_list(ctx, b.bridge_type)
    i = findfirst(x -> x === b, l)
    i === nothing || deleteat!(l, i)
    return ctx
end

"""The proposed-bridge tables are indexed by object id-num, which is why a
flipped group keeps the id-num of the group it was flipped from."""
proposed_bridge_key(b::Bridge) = (b.object1.id_num, b.object2.id_num)

function add_proposed_bridge!(ctx::MetacatCtx, b::Bridge)
    table = ctx.proposed_bridges[b.bridge_type]
    pushfirst!(get!(table, proposed_bridge_key(b), Any[]), b)
    return ctx
end

function delete_proposed_bridge!(ctx::MetacatCtx, b::Bridge)
    table = ctx.proposed_bridges[b.bridge_type]
    key = proposed_bridge_key(b)
    haskey(table, key) || return ctx
    v = table[key]
    i = findfirst(x -> x === b, v)
    i === nothing || deleteat!(v, i)
    return ctx
end

"""`(delete-proposed-vertical-bridges object)` and its horizontal twin: when an
object is destroyed, every proposed bridge indexed against it goes too. Which
index the object occupies depends on which string it is in."""
function delete_proposed_bridges_for!(ctx::MetacatCtx, o::WSObject)
    id = o.id_num
    s = get_string(o)
    for (bridge_type, first_string, second_string) in
            ((:vertical, ctx.initial_string, ctx.target_string),
             (:top, ctx.initial_string, ctx.modified_string))
        table = ctx.proposed_bridges[bridge_type]
        for key in keys(table)
            if (s === first_string && key[1] == id) ||
               (s === second_string && key[2] == id)
                table[key] = Any[]
            end
        end
    end
    return ctx
end

"""`(spanning-bridge-exists? bridge-type)`."""
spanning_bridge_exists(ctx::MetacatCtx, bridge_type::Symbol) =
    any(b -> (b::Bridge).spanning_bridge, bridge_list(ctx, bridge_type))

"""`(maximal-mapping? bridge-type)` — every letter on both sides is covered by
some bridge of this type."""
function maximal_mapping(ctx::MetacatCtx, bridge_type::Symbol)
    # the bottom mapping needs an answer string, which only justify mode has
    strings = bridge_type === :top ? (ctx.initial_string, ctx.modified_string) :
              (ctx.initial_string, ctx.target_string)
    covered = WSObject[]
    for b in bridge_list(ctx, bridge_type)
        append!(covered, get_covered_letters(b::Bridge))
    end
    letters = vcat((s.letters for s in strings)...)
    return all(l -> any(c -> c === l, covered), letters) &&
           all(c -> any(l -> l === c, letters), covered)
end

# --- strengths and averages -------------------------------------------------
#
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
    return update_structure_strength!(b, ctx.net, all_bridges(ctx))
end

"""`(update-average-unhappiness-values)` — the per-string-pair averages, and
the mapping strengths derived from them.

A mapping is worth less than its raw strength suggests when a spanning group
is still possible on both sides (the objects may yet be regrouped), and much
less when every object is already mapped but no spanning bridge exists: the
`tanh` there squashes an apparently-complete mapping that has nowhere to go."""
function update_average_unhappiness_values!(ctx::MetacatCtx)
    top_objects = vcat(objects(ctx.initial_string), objects(ctx.modified_string))
    vertical_objects = vcat(objects(ctx.initial_string), objects(ctx.target_string))
    average(objs, getter) =
        sround(weighted_average([getter(o) for o in objs],
                                [o.relative_importance for o in objs]))
    top_unhappiness = average(top_objects, o -> o.horizontal_inter_string_unhappiness)
    vertical_unhappiness = average(vertical_objects,
                                   o -> o.vertical_inter_string_unhappiness)

    function strength(bridge_type::Symbol, raw, string1, string2)
        spanning_bridge_exists(ctx, bridge_type) && return raw
        (spanning_group_possible(string1, ctx.net) &&
         spanning_group_possible(string2, ctx.net)) && return sround(1 // 2 * raw)
        # (100* (tanh (* 1/40 raw))): the argument is an exact rational in the
        # Scheme, so convert the ratio, do not multiply by a float 1/40.
        maximal_mapping(ctx, bridge_type) && return sround(100 * tanh(float(raw // 40)))
        return raw
    end
    ctx.top_mapping_strength = strength(:top, sub_from_100(top_unhappiness),
                                        ctx.initial_string, ctx.modified_string)
    ctx.vertical_mapping_strength = strength(:vertical, sub_from_100(vertical_unhappiness),
                                             ctx.initial_string, ctx.target_string)
    return ctx
end

"""`(update-workspace-values)` with the bridge half in place.

`get-structures` yields bonds, then groups, then bridges, and the structures
are updated before the objects because an object's unhappiness reads the
strength of the structures around it."""
function update_workspace_values!(ctx::MetacatCtx)
    TEMPERATURE[] = ctx.temperature
    strings = all_strings(ctx)
    for s in strings, b in s.bonds
        update_structure_strength!(b::Bond, ctx.net, ctx.rng)
    end
    for s in strings, g in s.groups
        update_structure_strength!(g::Group, ctx.net, ctx.rng)
    end
    bridges = all_bridges(ctx)
    for b in bridges
        update_structure_strength!(b::Bridge, ctx.net, bridges)
    end
    objs = workspace_objects(ctx)
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
    update_average_unhappiness_values!(ctx)
    return ctx
end
