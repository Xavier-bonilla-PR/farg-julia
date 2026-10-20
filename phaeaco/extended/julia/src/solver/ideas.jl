# Ideas for solutions (§11.1.2): "To 'form an idea' for a solution in the BP
# domain means to construct a pair of representations that describe the
# idea" — here, what is compared (a feature or a count at some place in the
# structure, or the existence of some kind of thing), and how the two sides
# differ in it.

"""
An idea.

- `kind`  `:feature` (a feature value), `:count` (a numerosity), `:exists`
          (some kind of node is present on one side and absent on the other),
          `:same` (all instances in a box share a value, §7.4.10).
- `path`  where in a box's representation: node types from the box down,
          e.g. `[:object]` (every object), `[:object, :barycenter]`. For
          counts, the path is where the count lives; `[:deep]` counts the
          type anywhere in the box.
- `what`  the feature, the counted type, or the node type that exists.
- `tag`   for `:exists`, the node's tag (`:closed`, `:concavity`) or `:any`;
          for `:some` features, the side that has the instances (`:left`/`:right`);
          for `:same`, `:relative` or `:absolute` tolerance.
- `quant` `:all` (every instance on a side is on its side of the split) or
          `:some` (each box of one side has an instance there, the other
          side's boxes have none).
- `thr`   the split point between the sides' values.
- `leftlow` `:all` features and counts: whether the left side has the lower
          values. `:some` features: whether the instances in question are
          below the split (true) or above it. `:exists`/`:same`: whether the
          left side is the one that has the property.
"""
struct Idea
    kind::Symbol
    path::Vector{Symbol}
    what::Symbol
    tag::Symbol
    quant::Symbol
    thr::Float64
    leftlow::Bool
end

"""Same idea, whatever the exact split point (§11.1.3: "identical to one of the verified-and-failed ones")."""
same_idea(a::Idea, b::Idea) =
    a.kind == b.kind && a.path == b.path && a.what == b.what && a.tag == b.tag &&
    a.quant == b.quant && a.leftlow == b.leftlow

"""
Kinds of node an existence idea about `what` accepts: a circle is an ellipse
is a curve (§7.4.5, the LTM is-a hierarchy).
"""
const KIND_OF = Dict(:curve => (:curve, :ellipse, :circle), :ellipse => (:ellipse, :circle))
iskind(t::Symbol, what::Symbol) = t == what || t in get(KIND_OF, what, ())

"""Nodes reached from `r` by following `path` (child types)."""
function instances(r::RNode, path::Vector{Symbol})
    cur = [r]
    for t in path
        t == :deep && return _alldesc(r)
        cur = [c for n in cur for c in n.children if c.type == t]
    end
    return cur
end

function _alldesc(r::RNode)
    out = RNode[r]
    i = 1
    while i <= length(out)
        append!(out, out[i].children)
        i += 1
    end
    return out
end

"""The values an idea looks at in one box's representation (one per instance; empty if none)."""
function idea_values(idea::Idea, r::RNode)
    if idea.kind == :feature
        return [n.feats[idea.what].mean for n in instances(r, idea.path) if haskey(n.feats, idea.what)]
    elseif idea.kind == :count
        if idea.path == [:deep]
            # the count of a type anywhere in the box: sum the counts kept in each context
            tot = 0.0
            seen = false
            for n in _alldesc(r)
                c = count_of(n, idea.what)
                c === nothing && return Float64[]          # some context did not count: unknown
                (haskey(n.nums, idea.what) || any(ch -> ch.type == idea.what, n.children)) && (seen = true)
                tot += c.mean
            end
            return [tot]
        end
        vals = Float64[]
        for n in instances(r, idea.path)
            c = count_of(n, idea.what)
            c === nothing || push!(vals, c.mean)
        end
        return vals
    end
    return Float64[]
end

"""Does a box of the left (`left = true`) or right side satisfy the idea?"""
function satisfies(idea::Idea, r::RNode, left::Bool)
    if idea.kind == :exists
        has = idea.what == :thing ? !isempty(r.children) :
              any(n -> iskind(n.type, idea.what) && (idea.tag in (:any, :none) || n.tag == idea.tag), _alldesc(r))
        return has == (left == idea.leftlow)
    elseif idea.kind == :same
        return same_value(idea, r) == (left == idea.leftlow)
    end
    vals = idea_values(idea, r)
    low = left == idea.leftlow               # this side should be below the split
    onside(v) = low ? v < idea.thr : v > idea.thr
    if idea.quant == :all
        return !isempty(vals) && all(onside, vals)
    else
        # :some — every box of the marked side has such an instance, the other side's none
        want = (idea.tag == :left) == left
        hit = any(v -> idea.leftlow ? v < idea.thr : v > idea.thr, vals)
        return hit == want
    end
end

"""
For `:same` ideas: do all instances in the box share practically one value
of the feature (§7.4.10)? Uses the feature's "same" tolerance.
"""
function same_value(idea::Idea, r::RNode; info::Union{Nothing,FeatureInfo}=nothing)
    vals = [n.feats[idea.what].mean for n in instances(r, idea.path) if haskey(n.feats, idea.what)]
    length(vals) >= 2 || return false
    lo, hi = extrema(vals)
    tol = idea.thr                               # for :same ideas thr holds the tolerance
    return hi - lo <= tol * (idea.tag == :relative ? max(abs(hi), 1e-9) : 1.0)
end

# --- describing ideas, as Phaeaco printed them ------------------------------------------

const _NOUN = Dict(:thing => "thing", :object => "object", :cluster => "figure made of parts", :line => "line", :dot => "dot", :circle => "circle",
                   :ellipse => "ellipse", :curve => "curve", :interior => "interior", :vertex => "vertex",
                   :barycenter => "center", :deep => "box", :box => "box")

function _where(path)
    isempty(path) && return "box"
    return join((get(_NOUN, t, string(t)) for t in path), "'s ")
end

_xname(s::AbstractString) =
    s == "filled" ? "filled figures" : s == "outlined" ? "outlined figures" :
    s == "inside" ? "figures inside the largest" : s == "outside" ? "figures outside it" :
    startswith(s, "filled") ? "filled $(s[7:end])s" : startswith(s, "outlined") ? "outlined $(s[9:end])s" : s

const _XROOT = Dict(:depth => ("figures nested less deeply", "figures nested more deeply"),
                    :simmin => ("some figures unlike the others", "all figures similar"),
                    :simmax => ("no two figures similar", "some two figures similar"),
                    :identmin => ("not all figures identical", "all figures identical"),
                    :nsame => ("fewer identical figures", "more identical figures"),
                    :bcorners => ("the whole drawing has fewer corners", "the whole drawing has more corners"),
                    :ssimmin => ("some figures unlike the others in structure", "all figures alike in structure"),
                    :ssimmax => ("no two figures alike in structure", "some two figures alike in structure"))
const _XADJ = Dict(:vert => ("horizontal", "vertical"),
                   :endgap => ("ends close together", "ends far apart"),
                   :endangle => ("ends parallel", "ends perpendicular"),
                   :cends => ("core with fewer ends", "core with more ends"),
                   :cjunct => ("core with fewer branchings", "core with more branchings"),
                   :corder => ("core without side branches of higher order", "core with side branches of higher order"),
                   :neck => ("with a neck", "without a neck"),
                   :neckvert => ("neck horizontal", "neck vertical"),
                   :ccorners => ("outline with fewer corners", "outline with more corners"))

"""Phrases for PhaeacoX's extended percepts, or nothing."""
function _xphrases(idea::Idea)
    idea.kind == :feature || return nothing
    f = idea.what
    if isempty(idea.path)
        return get(_XROOT, f, nothing)
    end
    t = idea.path[end]
    b, tag = basetype(t), string(tagof(t))
    if b == :pair
        a, c = _xname.(split(tag, '_'; limit=2))
        f == :above && return ("the $a lower than the $c", "the $a higher than the $c")
        f == :larger && return ("the $a smaller than the $c", "the $a larger than the $c")
        f == :inside && return ("the $c inside the $a", "the $a inside the $c")
    elseif b == :contrast
        a, c = _xname.(split(tag, '_'; limit=2))
        return ("fewer $a than $c", "more $a than $c")
    elseif b == :group
        k = "$(tag)s"
        f == :collinear && return ("the $k on one line", "the $k not on one line")
        f == :tricol && return ("some three $k on a line", "no three $k on a line")
        f == :gvert && return ("the $k in a horizontal row", "the $k in a vertical row")
        f == :gelong && return ("the $k in a compact cluster", "the $k in an elongated cluster")
        f == :gcorners && return ("the $k outline fewer corners", "the $k outline more corners")
    elseif haskey(_XADJ, f)
        a, c = _XADJ[f]
        return ("$(_where(idea.path)) $a", "$(_where(idea.path)) $c")
    end
    return nothing
end

"""The two phrases for the left and right sides."""
function describe(idea::Idea)
    w = string(idea.what)
    if basetype(idea.what) in (:shape, :mark) && idea.kind == :exists
        thing = basetype(idea.what) == :mark && tagof(idea.what) == :selfcrossing ? "self-crossing line" : string(tagof(idea.what))
        has, hasnt = "some $thing", "no $thing"
        return idea.leftlow ? (has, hasnt) : (hasnt, has)
    end
    xp = _xphrases(idea)
    if xp !== nothing
        lo, hi = xp
        if idea.quant == :some
            p = idea.leftlow ? lo : hi
            return idea.tag == :left ? ("some box: $p", "no box: $p") : ("no box: $p", "some box: $p")
        end
        return idea.leftlow ? (lo, hi) : (hi, lo)
    end
    if idea.kind == :exists && idea.what == :forall
        t, f = split_forall(idea.tag)
        s, n = "every $(get(_NOUN, t, string(t))) has similar $f", "not every $(get(_NOUN, t, string(t))) has similar $f"
        return idea.leftlow ? (s, n) : (n, s)
    elseif idea.kind == :exists && idea.what == :category
        has, hasnt = "some $(idea.tag)", "no $(idea.tag)"
        return idea.leftlow ? (has, hasnt) : (hasnt, has)
    elseif idea.kind == :exists
        thing = idea.tag in (:any, :none) ? get(_NOUN, idea.what, w) : "$(idea.tag) $(get(_NOUN, idea.what, w))"
        has, hasnt = "some $thing", "no $thing"
        return idea.leftlow ? (has, hasnt) : (hasnt, has)
    elseif idea.kind == :same
        s = "every $(_where(idea.path)) has similar $w"
        n = "$(_where(idea.path))s differ in $w"
        return idea.leftlow ? (s, n) : (n, s)
    elseif idea.kind == :count
        place = idea.path == [:deep] ? "in box" : "per $(_where(idea.path))"
        k = round(Int, floor(idea.thr))
        lo = "≤ $k $(w)s $place"; hi = "> $k $(w)s $place"
        return idea.leftlow ? (lo, hi) : (hi, lo)
    else
        if idea.what == :texture
            lo, hi = "outlined texture", "filled texture"
        else
            adj = Dict(:area => ("small", "large"), :x => ("left", "right"), :y => ("low", "high"),
                       :elongation => ("compact", "elongated"), :missing => ("convex", "concave"),
                       :slope => ("shallow", "steep"), :length => ("short", "long"),
                       :angle => ("acute", "wide"), :size => ("small", "large"))
            a, b = get(adj, idea.what, ("low", "high"))
            lo, hi = "$(_where(idea.path)) has $a $w", "$(_where(idea.path)) has $b $w"
        end
        if idea.quant == :some
            p = idea.leftlow ? lo : hi
            return idea.tag == :left ? ("some $p", "no $p") : ("no $p", "some $p")
        end
        return idea.leftlow ? (lo, hi) : (hi, lo)
    end
end

Base.show(io::IO, idea::Idea) = (l = describe(idea); print(io, "\"", l[1], "\" vs \"", l[2], "\""))
