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
end

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
    return update_structure_strength!(b, ctx.net, Bridge[], ctx.themespace)
end
