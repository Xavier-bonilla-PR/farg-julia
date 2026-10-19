# The tree representations matching works on (ch. 8). Defined here, early,
# because long-term memory keeps patterns as the core structures of learned
# concepts (§9.2.1). Building exemplars from a Workspace is in patterns/rep.jl.
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

# Extension node types carry a tag after '@' (`pair@circle_triangle`); their
# LTM concept is the part before it (PhaeacoX, src/ext/extend.jl).
basetype(t::Symbol) = (s = string(t); i = findfirst('@', s); i === nothing ? t : Symbol(s[1:i-1]))
tagof(t::Symbol) = (s = string(t); i = findfirst('@', s); i === nothing ? :none : Symbol(s[i+1:end]))
