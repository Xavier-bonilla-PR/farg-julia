# Representations for matching (ch. 8): exemplars and patterns.
#
# An `RNode` tree is either an *exemplar* — one look at one thing, every
# statistic of sample size 1 — or a *pattern*, a statistical summary of
# several exemplars with the same kind of structure, its statistics of size
# N > 1 (§8.2: "representation" covers both). A child's `support` counts the
# exemplars that contributed it, so support / parent support is the strength
# of its link: serifs present on some A's and not others are in the pattern
# "yes and no", weakly (§8.3.3).

mutable struct RNode
    type::Symbol
    tag::Symbol
    feats::Dict{Symbol,Stats}
    nums::Dict{Symbol,Stats}
    children::Vector{RNode}
    support::Int
    origin::Int                 # the Workspace node an exemplar came from (0 in patterns)
end

RNode(type::Symbol; tag=:none) =
    RNode(type, tag, Dict{Symbol,Stats}(), Dict{Symbol,Stats}(), RNode[], 1, 0)

function Base.copy(r::RNode)
    RNode(r.type, r.tag, Dict(k => copy(v) for (k, v) in r.feats), Dict(k => copy(v) for (k, v) in r.nums),
          [copy(c) for c in r.children], r.support, r.origin)
end

strength(child::RNode, parent::RNode) = child.support / max(parent.support, 1)

"""The exemplar a box's Workspace represents, from node `id` (default: the box) down."""
function exemplar(ws::BoxWS, id::Int=ws.root)
    n = ws.nodes[id]
    r = RNode(n.type; tag=n.tag)
    r.origin = id
    for (f, (_, v)) in n.feats
        r.feats[f] = Stats(v)
    end
    # A count enters matching as the integer the accumulator reports: its
    # noise shows as the occasional miscount, not as 1 ≠ 1 (§7.3.2). A count
    # that has not yet reached every node of its type in this context (their
    # counting codelets did not all run) is left out — not counted yet, like a
    # missing feature — rather than passed on as a smaller number (D38).
    for (t, k) in n.nums
        num = ws.nodes[k]
        num.alive || continue
        present = count(c -> ws.nodes[c].alive && ws.nodes[c].type == t, n.children)
        counted_nodes = count(>(0), num.sharers)
        counted_nodes < present && continue
        r.nums[t] = Stats(Float64(reported(num)))
    end
    for c in parts(ws, id)
        push!(r.children, exemplar(ws, c))
    end
    return r
end

"""Number of nodes in a representation: a crude measure of simplicity (§11.1.3)."""
nnodes(r::RNode) = 1 + length(r.feats) + length(r.nums) + sum((nnodes(c) for c in r.children); init=0)

function show_rep(io::IO, r::RNode; indent=0, parent::Union{Nothing,RNode}=nothing)
    st = parent === nothing ? "" : @sprintf(" (%.2f)", strength(r, parent))
    fs = join([@sprintf("%s=%.3g%s", f, s.mean, s.n > 1 ? @sprintf("±%.2g/%d", stddev(s), s.n) : "")
               for (f, s) in sort(collect(r.feats); by=first)], " ")
    ns = join([@sprintf("%s#=%.3g%s", t, s.mean, s.n > 1 ? @sprintf("±%.2g", stddev(s)) : "")
               for (t, s) in sort(collect(r.nums); by=first)], " ")
    println(io, "  "^indent, r.type, r.tag == :none ? "" : "($(r.tag))", st, "  ", fs, isempty(ns) ? "" : "  [$ns]")
    for c in r.children
        show_rep(io, c; indent=indent + 1, parent=r)
    end
end
show_rep(r::RNode) = show_rep(stdout, r)
