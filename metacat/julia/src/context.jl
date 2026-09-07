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
    # Built rules, CONSed, one list per rule type, and whether a rule of each
    # type is possible at all — which is a question about coverage: every letter
    # of both strings has to sit under some describable bridge. Untyped because
    # rules.jl loads after this file.
    top_rules::Vector{Any}
    bottom_rules::Vector{Any}
    top_rule_possible::Bool
    bottom_rule_possible::Bool
    """`clamped-rule-list` — rules the user or a jootser has pinned. Read by
    the trace, which records them with every event."""
    clamped_rules::Vector{Any}
    """`*temperature-clamped?*` — set while a snag holds the temperature up,
    and cleared by the trace's `undo-snag-condition`."""
    temperature_clamped::Bool
    """`*trace*` — the temporal trace, when one is attached. The Scheme keeps it
    as a global that always exists, so its MONITORS are always live; here the
    monitors fire exactly when a trace is present. That is behaviourally the
    same, because the events monitors raise (concept-activation,
    concept-mapping, group, rule) change nothing but the event list — only
    clamp and snag events set the trace's period flags, and no monitor raises
    those. Untyped because trace.jl loads after this file."""
    trace::Any
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
               0, 0, 0, 0, 0, 0, 0, 0,
               Any[], Any[], false, false, Any[], false, nothing)

"""`(get-all-vertical-CMs)` — every concept mapping of every built vertical
bridge, which is what the whole vertical mapping amounts to."""
get_all_vertical_cms(ctx::MetacatCtx) =
    ConceptMapping[cm for b in ctx.vertical_bridges for cm in b.all_concept_mappings]

"""`(clamp-salience)` / `(unclamp-salience)` — hold an object at full salience,
so the model keeps looking at it. Snag events do this to what tripped them."""
clamp_salience!(o) = (o.salience_clamped = true; o)
unclamp_salience!(o) = (o.salience_clamped = false; o)

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

# --- rules ------------------------------------------------------------------

"""`(get-rules rule-type)` — newest first, as CONSed."""
get_rules(ctx::MetacatCtx, rule_type::Symbol) =
    rule_type === :top ? ctx.top_rules : ctx.bottom_rules

get_all_rules(ctx::MetacatCtx) = vcat(ctx.top_rules, ctx.bottom_rules)

"""`(add-rule rule)`."""
function add_rule!(ctx::MetacatCtx, r)
    pushfirst!(r.rule_type === :top ? ctx.top_rules : ctx.bottom_rules, r)
    return ctx
end

"""`(get-equivalent-rule rule)` — the first rule of the same type that says the
same thing."""
function get_equivalent_rule(ctx::MetacatCtx, r)
    rules = get_rules(ctx, r.rule_type)
    i = findfirst(other -> rules_equal(other, r, ctx.net), rules)
    return i === nothing ? nothing : rules[i]
end

rule_present(ctx::MetacatCtx, r) = get_equivalent_rule(ctx, r) !== nothing
rule_exists(ctx::MetacatCtx, rule_type::Symbol) = !isempty(get_rules(ctx, rule_type))

"""`(check-if-rules-possible)` — a rule of a type is possible when every letter
of both its strings is covered by some bridge a rule could be described from.
Outside justify mode only the top rule is ever possible."""
function check_if_rules_possible!(ctx::MetacatCtx)
    covered = Any[o for b in ctx.top_bridges if rule_describable_bridge(b, ctx.net)
                  for o in get_covered_letters(b)]
    letters = vcat(ctx.initial_string.letters, ctx.modified_string.letters)
    ctx.top_rule_possible = all(l -> any(c -> c === l, covered), letters)
    return ctx
end

"""`(get-possible-rule-types)`."""
get_possible_rule_types(ctx::MetacatCtx) =
    ctx.top_rule_possible && ctx.bottom_rule_possible ? Symbol[:top, :bottom] :
    ctx.top_rule_possible ? Symbol[:top] :
    ctx.bottom_rule_possible ? Symbol[:bottom] : Symbol[]

"""`(get-equivalent-object object)` — the object at the same place in this
string. When the object already belongs to the string that is the object
itself; the case where it does not arises only for TRANSLATED strings, which
come with `jootsing.ss` and are not ported yet."""
function get_equivalent_object(s::WorkspaceString, o)
    pool = o isa Letter ? s.letters : s.groups
    any(x -> x === o, pool) && return o
    return nothing
end

"""`(get-equivalent-bridge bridge)` — the bridge in the workspace that does the
same job as this one, which is the bridge itself unless it has been rebuilt."""
function get_equivalent_bridge(ctx::MetacatCtx, b::Bridge)
    list = get_bridges(ctx, b.bridge_type)
    any(x -> x === b, list) && return b
    string1 = b.bridge_type === :bottom ? ctx.target_string : ctx.initial_string
    string2 = b.bridge_type === :top ? ctx.modified_string :
              b.bridge_type === :vertical ? ctx.target_string : nothing
    o1 = get_equivalent_object(string1, b.object1)
    o2 = string2 === nothing ? nothing : get_equivalent_object(string2, b.object2)
    (o1 !== nothing && o2 !== nothing &&
     bridge_between(b.orientation, o1, o2)) || return nothing
    return get_bridge(o1, b.orientation)
end

bridge_present(ctx::MetacatCtx, b::Bridge) = get_equivalent_bridge(ctx, b) !== nothing

"""`(get-real-object fake-object)` — the workspace object a translated
string's object corresponds to, if the model actually perceived one."""
function get_real_object(ctx::MetacatCtx, fake_object)
    i = findfirst(o -> equivalent_workspace_objects(o, fake_object),
                  workspace_objects(ctx))
    return i === nothing ? nothing : workspace_objects(ctx)[i]
end

"""`(get-structures)` — every built structure in the workspace, in the order
the Scheme appends them: bonds, groups, then the three bridge lists and the two
rule lists. The trace snapshots this with every event, which is how it can say
later what had been built by then."""
get_structures(ctx::MetacatCtx) =
    Any[workspace_bonds(ctx)..., workspace_groups(ctx)...,
        ctx.top_bridges..., ctx.bottom_bridges..., ctx.vertical_bridges...,
        ctx.top_rules..., ctx.bottom_rules...]

"""`(get-clamped-rules)`."""
get_clamped_rules(ctx::MetacatCtx) = ctx.clamped_rules

"""`(clamp-rule rule)` / `(unclamp-rule rule)`. NB: CONSed, so the list is in
reverse order of clamping."""
clamp_rule!(ctx::MetacatCtx, rule) = (pushfirst!(ctx.clamped_rules, rule); ctx)
function unclamp_rule!(ctx::MetacatCtx, rule)
    i = findfirst(x -> x === rule, ctx.clamped_rules)
    i === nothing || deleteat!(ctx.clamped_rules, i)
    return ctx
end
