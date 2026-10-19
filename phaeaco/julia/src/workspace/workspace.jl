# The Workspace (ch. 7): the representation of one box, built node by node.
#
# Nodes form a nearly hierarchical graph rooted at the box node. Every node
# has an activation that starts at the top and decays; adding a node injects
# a mark of activation into each of its ancestors (§7.2), and when the box
# node's activation falls below a threshold the box counts as seen.
#
# Workspace activations run on the box's own clock (`ws.ticks`), so a box
# decays at the same pace whether it is looked at alone or with eleven
# others; LTM concepts run on the global clock (`ctx.now`).
#
# Feature nodes are shared: when two objects of a box have practically the
# same value of a feature, both link to one node (§7.1, Fig. 7.7), which is
# the implicit equality that the sameness codelet later makes explicit
# (§7.4.10). Each parent also keeps its own exact value on the link, so
# matching can use it. The cognitive level never reads a retinal detector
# directly: a node holds an opaque handle (`ret`), and only codelets — the
# agents that "ask" the retinal level — follow it.

"""Shared state for one run: parameters, randomness, LTM, the clock, the trace."""
mutable struct Ctx
    P::Params
    rng::Xoshiro
    ltm::LTM
    now::Int
    tracer::Tracer
end

Ctx(P::Params, seed::Integer; tracer=Tracer(), ltm=build_primitives(P)) =
    Ctx(P, Xoshiro(seed), ltm, 0, tracer)

mutable struct WNode
    id::Int
    type::Symbol                # its LTM concept: :box, :object, :line, :slope, :numerosity, …
    act::Activation
    parent::Int                 # structural parent (0 for the box node)
    children::Vector{Int}
    feats::Dict{Symbol,Tuple{Int,Float64}}      # feature type → (shared feature node, this node's value)
    nums::Dict{Symbol,Int}                      # counted type → numerosity node
    stats::Stats                # feature node: all sharers' values; numerosity: the accumulated count (N = 1)
    sharers::Vector{Int}        # feature node: nodes linked to it. numerosity: nodes counted
    links::Vector{Tuple{Int,Symbol,Float64}}    # lateral: (node, kind, strength)
    ret::Tuple{Symbol,Int}      # retinal handle, (:none, 0) if none
    tag::Symbol                 # junction kind, interior kind, … (:none)
    alive::Bool
end

"""What a numerosity node counts in which context."""
counted(n::WNode) = n.tag

struct Codelet
    kind::Symbol
    node::Int
    urgency::Float64
    born::Int
end

"""The Workspace of one box: its retina, its nodes, its coderack."""
mutable struct BoxWS
    index::Int                  # 1–12
    img::BitMatrix
    retina::Retina
    nodes::Vector{WNode}
    root::Int
    rack::Vector{Codelet}
    pending::Vector{Tuple{Symbol,Int}}          # detectors process P has not yet perceived
    hidden_lines::Set{Int}                      # retinal lines standing in for a curve or ellipse
    node_of::Dict{Tuple{Symbol,Int},Int}        # detector → node
    suppressed::Set{Tuple{Int,Symbol}}          # process Q: (context node, type) seen "many" times
    ticks::Int
    done::Bool
    analytic::Bool              # looked at in the analytic stage: equality can be noticed (§7.4.10)
end

# --- building nodes ---------------------------------------------------------------

function _newnode!(ws::BoxWS, ctx::Ctx, type::Symbol, parent::Int; ret=(:none, 0), tag=:none)
    n = WNode(length(ws.nodes) + 1, type,
              Activation(Int(ctx.P[:ws_act_steps]), Int(ctx.P[:ws_act_period]); now=ws.ticks),
              parent, Int[], Dict{Symbol,Tuple{Int,Float64}}(), Dict{Symbol,Int}(), Stats(), Int[],
              Tuple{Int,Symbol,Float64}[], ret, tag, true)
    push!(ws.nodes, n)
    parent == 0 || push!(ws.nodes[parent].children, n.id)
    ret[1] == :none || (ws.node_of[ret] = n.id)
    inject!(ws, ctx, parent)
    haskey(ctx.ltm, type) && prime!(ctx.ltm, type, ctx.now, ctx.rng)
    trace(ctx.tracer, 2, ctx.now, "box $(ws.index) +", type, "#$(n.id)", parent == 0 ? "" : "under #$parent")
    return n
end

"""Inject a mark of activation into a node and all its ancestors (§7.2)."""
function inject!(ws::BoxWS, ctx::Ctx, id::Int)
    while id != 0
        n = ws.nodes[id]
        boost!(n.act, ws.ticks)
        id = n.parent
    end
end

"""
Move a node under a new parent (an object node inserted above lines,
Fig. 7.3). If it was already counted in its old context, the count moves
with it.
"""
function reparent!(ws::BoxWS, ctx::Ctx, id::Int, newparent::Int)
    n = ws.nodes[id]
    n.parent == newparent && return
    old = n.parent
    recount = false
    if old != 0
        filter!(!=(id), ws.nodes[old].children)
        nk = get(ws.nodes[old].nums, n.type, 0)
        if nk != 0 && id in ws.nodes[nk].sharers
            num = ws.nodes[nk]
            filter!(!=(id), num.sharers)
            num.stats = Stats(num.stats.mean - 1)
            if isempty(num.sharers)
                num.alive = false
                delete!(ws.nodes[old].nums, n.type)
            end
            recount = true
        end
    end
    n.parent = newparent
    push!(ws.nodes[newparent].children, id)
    recount && count_item!(ws, ctx, newparent, id)
end

"""
Attach a feature value to a node: reuse a feature node of that type in this
box whose values are practically the same, or start one (§7.1).
"""
function add_feature!(ws::BoxWS, ctx::Ctx, owner::Int, ftype::Symbol, v::Float64)
    info = ctx.ltm[ftype].feature
    o = ws.nodes[owner]
    haskey(o.feats, ftype) && return o.feats[ftype][1]
    fnode = 0
    for n in ws.nodes
        (n.alive && n.type == ftype && n.stats.n > 0) || continue
        tol = info.relative ? info.eqtol * max(abs(v), abs(n.stats.mean)) : info.eqtol
        if info.discrete ? v == n.stats.mean : fdist(info, v, n.stats.mean) <= tol
            fnode = n.id
            break
        end
    end
    if fnode == 0
        f = _newnode!(ws, ctx, ftype, owner)
        fnode = f.id
    else
        inject!(ws, ctx, owner)
        boost!(ws.nodes[fnode].act, ws.ticks)
        prime!(ctx.ltm, ftype, ctx.now, ctx.rng)
    end
    f = ws.nodes[fnode]
    f.stats.n > 0 && (v = unwrap(info, v, f.stats.mean))
    push!(f.stats, v)
    push!(f.sharers, owner)
    o.feats[ftype] = (fnode, v)
    # values that are the same, or nearly, are a structural curiosity a
    # sameness codelet may notice — the more of them, the likelier (§7.4.10)
    if ws.analytic
        k = _near_owners(ws, ctx, ftype, f.stats.mean)
        k >= 2 && post!(ws, ctx, :equality, fnode, ctx.P[:ws_equality_urgency] * min(1.0, (k - 1) / 2))
    end
    return fnode
end

"""
Feature nodes of a type whose values are within the sameness tolerance of
`v`: the feature's own tolerance widened by `ws_sameness_widening`. Under the
pressure of looking for sameness, nearly equal values count as equal (§7.1:
"lowering the threshold of acceptance of length equality").
"""
function near_nodes(ws::BoxWS, ctx::Ctx, ftype::Symbol, v::Float64)
    info = ctx.ltm[ftype].feature
    k = ctx.P[:ws_sameness_widening]
    out = Int[]
    for n in ws.nodes
        (n.alive && n.type == ftype && n.stats.n > 0) || continue
        tol = k * (info.relative ? info.eqtol * max(abs(v), abs(n.stats.mean)) : info.eqtol)
        (info.discrete ? v == n.stats.mean : fdist(info, v, n.stats.mean) <= tol) && push!(out, n.id)
    end
    return out
end

_near_owners(ws::BoxWS, ctx::Ctx, ftype::Symbol, v::Float64) =
    sum((length(ws.nodes[k].sharers) for k in near_nodes(ws, ctx, ftype, v)); init=0)

"""
Count `item` in the numerosity node of `context` for its type: the
accumulator adds a draw from N(1, σ₀) (§7.3.2). Returns the node.
"""
function count_item!(ws::BoxWS, ctx::Ctx, context::Int, item::Int; type::Symbol=ws.nodes[item].type)
    # `item` is a node id, or a negative key for a thing counted without a node (process Q)
    c = ws.nodes[context]
    if !haskey(c.nums, type)
        n = _newnode!(ws, ctx, :numerosity, context; tag=type)
        c.nums[type] = n.id
    end
    n = ws.nodes[c.nums[type]]
    item in n.sharers && return n
    push!(n.sharers, item)
    acc = n.stats.n == 0 ? 0.0 : n.stats.mean
    acc += 1 + ctx.P[:numerosity_sigma0] * randn(ctx.rng)
    n.stats = Stats(acc)
    boost!(n.act, ws.ticks)
    inject!(ws, ctx, context)
    prime!(ctx.ltm, :numerosity, ctx.now, ctx.rng)
    process_Q!(ws, ctx, context, type, n)
    return n
end

"""The integer the accumulator reports (§7.3.2)."""
reported(n::WNode) = max(0, round(Int, n.stats.mean))

"""
Process Q (§10.3.15): once a context holds "many" of a type (a sampled
threshold around five), stop building individual nodes for more of them
and damp the codelets of the ones already there (§7.4.4).
"""
function process_Q!(ws::BoxWS, ctx::Ctx, context::Int, type::Symbol, n::WNode)
    (context, type) in ws.suppressed && return
    if exceeds(length(n.sharers), thr(ctx.P, :many), ctx.rng)
        push!(ws.suppressed, (context, type))
        prime!(ctx.ltm, :many, ctx.now, ctx.rng)
        trace(ctx.tracer, 2, ctx.now, "box $(ws.index) Q many", type, "in #$context")
    end
end

"""A relation between two nodes, with its twin (§7.4.7, Fig. 7.41)."""
function add_relation!(ws::BoxWS, ctx::Ctx, kind::Symbol, twin::Symbol, a::Int, b::Int, strength::Float64)
    any(l -> l[2] == kind && l[1] == b, ws.nodes[a].links) && return
    r1 = _newnode!(ws, ctx, kind, ws.root)
    r2 = _newnode!(ws, ctx, twin, ws.root)
    push!(r1.links, (a, :subject, strength)); push!(r1.links, (b, :object, strength))
    push!(r2.links, (b, :subject, strength)); push!(r2.links, (a, :object, strength))
    push!(r1.links, (r2.id, :twin, strength)); push!(r2.links, (r1.id, :twin, strength))
    push!(ws.nodes[a].links, (b, kind, strength))
    push!(ws.nodes[b].links, (a, twin, strength))
end

"""Nodes of a type under (any depth below) `id`."""
function descendants(ws::BoxWS, id::Int, type::Symbol)
    out = Int[]
    stack = copy(ws.nodes[id].children)
    while !isempty(stack)
        k = pop!(stack)
        n = ws.nodes[k]
        n.alive || continue
        n.type == type && push!(out, k)
        append!(stack, n.children)
    end
    return out
end

"""Structural children of a node that are themselves things (not features or numbers)."""
function parts(ws::BoxWS, id::Int)
    [k for k in ws.nodes[id].children if ws.nodes[k].alive && !(ws.nodes[k].type in (:numerosity,)) &&
                                          !_isfeature(ws, k)]
end

_isfeature(ws::BoxWS, k::Int) = ws.nodes[k].stats.n > 0 && ws.nodes[k].type != :numerosity

function BoxWS(index::Int, img::AbstractMatrix{Bool}, ctx::Ctx; analytic::Bool=false)
    r = Retina(img, ctx.P, Xoshiro(rand(ctx.rng, UInt64)); tracer=ctx.tracer)
    ws = BoxWS(index, BitMatrix(img), r, WNode[], 0, Codelet[], Tuple{Symbol,Int}[], Set{Int}(),
               Dict{Tuple{Symbol,Int},Int}(), Set{Tuple{Int,Symbol}}(), 0, false, analytic)
    ws.root = _newnode!(ws, ctx, :box, 0).id
    return ws
end
