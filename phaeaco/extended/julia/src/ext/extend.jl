# Extended percepts: the abilities §11.2 lists as missing from Phaeaco, and
# others the survey of Bongard's other problems showed it lacks (see
# ../../DECISIONS.md). They are added to the exemplar of each analytic look
# (and each verification look), never to the holistic look: like sameness
# (§7.4.10), relations between figures are "structural curiosities" noticed
# when a box is examined on its own.
#
# Every extended node or feature lives in the exemplar (an RNode), so the
# 2006 machinery — patterns, ideas, verification — uses them unchanged.
# Nodes whose type carries a tag after '@' (`pair@circle_triangle`) take
# their LTM weight from the part before it (`pair`).
#
#   shape@K        per object: its kind K (circle, triangle, cross, …)
#   object         + vert (how vertical its long axis is), crossings, endgap,
#                    endangle (for open single-stroke figures)
#   line           + lvert
#   pair@A_B       two figures of different, unique kinds: above, larger, inside
#   pair@filled_outlined   the two textures' mean positions and sizes
#   contrast@X_Y   the difference of two counts: more X than Y?
#   group@K        three or more figures of one kind: collinear, tricol,
#                    gvert, gelong
#   box            + depth (nesting of insides), simmin/simmax/identmin
#                    (shape similarity of figures), nsame


"""Features only the extension perceives."""
const EXT_FEATURES = Set([:vert, :endgap, :endangle, :above, :larger, :inside, :diff,
                          :depth, :simmin, :simmax, :identmin, :nsame, :collinear, :tricol, :gvert, :gelong,
                          :gcorners, :bcorners])

"""One figure as the extension sees it."""
struct XItem
    obj::Int                # retina object id
    rnode::Union{Nothing,RNode}
    kind::Symbol
    c::Pt                   # barycenter, pixels (y down)
    area::Float64
    filled::Bool
    elong::Float64
    missing::Float64
    holes::Int
    k::Int                  # corners of the simplified hull
end

# --- shape kinds -------------------------------------------------------------------------

"""Corners of a convex polygon after dropping vertices that deviate less than `tol` from their chord."""
function _corners(v::Vector{Pt}, tol::Float64)
    pts = copy(v)
    while length(pts) > 3
        best, bi = Inf, 0
        n = length(pts)
        for i in 1:n
            a, b, c = pts[mod1(i - 1, n)], pts[i], pts[mod1(i + 1, n)]
            L = dist(a, c)
            d = L == 0 ? 0.0 : abs((c[1] - a[1]) * (a[2] - b[2]) - (a[1] - b[1]) * (c[2] - a[2])) / L
            d < best && (best = d; bi = i)
        end
        best >= tol && break
        deleteat!(pts, bi)
    end
    return length(pts)
end

function _kind(r::Retina, o::RetObject)
    if o.isdot                     # a ring too small to be given a shape is a small circle
        w = o.bbox[2] - o.bbox[1] + 1; h = o.bbox[4] - o.bbox[3] + 1
        return (!isempty(o.holes) || o.ink / (w * h) <= 0.68 ? :circle : :dot), 0
    end
    alive = [l for l in o.lines if r.lines[l].alive]
    if !isempty(o.ellipses)
        e = r.ellipses[o.ellipses[1]]
        length(setdiff(alive, e.lines)) <= 1 && return (e.circle || o.elongation < 0.12 ? :circle : :ellipse), 0
    end
    if isempty(o.holes) && !o.filled &&
       any(j -> r.junctions[j].kind == :X, o.junctions) && length(alive) <= 4
        return :cross, 0
    end
    diam = max(o.bbox[2] - o.bbox[1], o.bbox[4] - o.bbox[3], 1)
    k = length(o.hull.v) >= 3 ? _corners(o.hull.v, max(0.18 * diam, 1.5)) : 0
    closed = !isempty(o.holes) || o.filled
    # a round closed figure the retina did not fit as an ellipse; small ones
    # (a few pixels across) show fewer hull corners
    if closed && o.missing < 0.06 && (k >= 7 || !isempty(o.curves) || (diam < 20 && k >= 5))
        return (o.elongation < 0.15 ? :circle : :ellipse), k
    end
    # small rings show few hull corners: a circle fills the ellipse inscribed in
    # its bounding box (ratio ≈ 1), a square overfills it (1.27), a diamond does not (0.64)
    if closed && diam < 20 && k >= 4
        w = o.bbox[2] - o.bbox[1] + 1; h = o.bbox[4] - o.bbox[3] + 1
        ratio = o.hull_area / (π / 4 * w * h)
        0.85 <= ratio <= 1.12 && return (o.elongation < 0.15 ? :circle : :ellipse), k
    end
    if closed                       # wavy or curved sides do not change the corners (BP #10)
        k == 3 && return :triangle, k
        k == 4 && return :quadrangle, k
        return :polygon, k
    end
    isempty(o.curves) || return :curve, k
    length(alive) == 1 && return :segment, k
    return :figure, k
end

function _items(e::RNode, ws::BoxWS)
    r = ws.retina
    byobj = Dict{Int,RNode}()
    for c in e.children
        c.origin > 0 || continue
        det = ws.nodes[c.origin].ret
        det[1] == :object && (byobj[det[2]] = c)
        det[1] == :dot && (byobj[r.dots[det[2]].comp] = c)
        # an isolated line is perceived as a line, not an object; here it is a figure too
        det[1] == :line && c.type == :line && (byobj[r.lines[det[2]].comp] = c)
    end
    items = XItem[]
    for o in r.objects
        haskey(byobj, o.id) || continue            # only what this look perceived
        kind, k = _kind(r, o)
        filled = o.filled
        if o.isdot
            # a solid dot is filled, a ring outlined: holes, or how much of its box the ink covers
            w = o.bbox[2] - o.bbox[1] + 1; h = o.bbox[4] - o.bbox[3] + 1
            filled = isempty(o.holes) && o.ink / (w * h) > 0.68
        end
        push!(items, XItem(o.id, byobj[o.id], kind, o.barycenter, o.area, filled, o.elongation,
                           o.missing, length(o.holes), k))
    end
    return items
end

# --- per-figure features -------------------------------------------------------------------

"""The two free ends of an open single-stroke figure, with the direction of the line at each."""
function _free_ends(r::Retina, o::RetObject)
    ends = Tuple{Pt,Pt}[]
    for l in o.lines
        ln = r.lines[l]
        ln.alive || continue
        for e in 1:2
            atj = any(j -> any(k -> r.junctions[j].lines[k] == l && r.junctions[j].ends[k] == e,
                               eachindex(r.junctions[j].lines)), o.junctions)
            atj || push!(ends, (endpoint(ln, e), ln.d))
        end
    end
    return ends
end

function _figure_features!(it::XItem, r::Retina, P::Params)
    n = it.rnode
    o = r.objects[it.obj]
    n.type == :object || return
    if o.elongation >= P[:ext_vert_min_elong]
        n.feats[:vert] = Stats(abs(sind(o.axis_deg)))
    end
    _selfcrossing(r, o) && push!(n.children, RNode(Symbol("mark@selfcrossing")))
    if isempty(o.holes) && !o.filled
        ends = _free_ends(r, o)
        if length(ends) == 2
            diam = max(o.bbox[2] - o.bbox[1], o.bbox[4] - o.bbox[3], 1)
            n.feats[:endgap] = Stats(dist(ends[1][1], ends[2][1]) / diam)
            d1, d2 = ends[1][2], ends[2][2]
            n.feats[:endangle] = Stats(acosd(clamp(abs(d1[1] * d2[1] + d1[2] * d2[2]), 0.0, 1.0)))
        end
    end
    push!(n.children, RNode(Symbol("shape@", it.kind)))
end

"""
Does a single stroke cross itself (BP #30)? Two of its lines that share no
junction cross properly, or four line ends meet at one point.
"""
function _selfcrossing(r::Retina, o::RetObject)
    any(j -> r.junctions[j].kind == :X || length(r.junctions[j].lines) >= 4, o.junctions) && return true
    ls = [l for l in o.lines if r.lines[l].alive]
    joined(a, b) = any(j -> a in r.junctions[j].lines && b in r.junctions[j].lines, o.junctions)
    cross(p1, p2, q1, q2) = begin
        o1 = (p2[1] - p1[1]) * (q1[2] - p1[2]) - (p2[2] - p1[2]) * (q1[1] - p1[1])
        o2 = (p2[1] - p1[1]) * (q2[2] - p1[2]) - (p2[2] - p1[2]) * (q2[1] - p1[1])
        o3 = (q2[1] - q1[1]) * (p1[2] - q1[2]) - (q2[2] - q1[2]) * (p1[1] - q1[1])
        o4 = (q2[1] - q1[1]) * (p2[2] - q1[2]) - (q2[2] - q1[2]) * (p2[1] - q1[1])
        o1 * o2 < 0 && o3 * o4 < 0
    end
    for i in eachindex(ls), j in i+1:length(ls)
        a, b = r.lines[ls[i]], r.lines[ls[j]]
        joined(ls[i], ls[j]) && continue
        cross(a.p1, a.p2, b.p1, b.p2) && return true
    end
    return false
end

# --- relations between figures -----------------------------------------------------------------

_inside(r::Retina, a::Int, b::Int) = any(t -> t[1] == a && t[2] == b && t[3] >= 0.95, r.insides)

function _pair!(e::RNode, tag, A::Vector{XItem}, B::Vector{XItem}, r::Retina)
    p = RNode(Symbol("pair@", tag))
    ya = sum(it.c[2] for it in A) / length(A); yb = sum(it.c[2] for it in B) / length(B)
    p.feats[:above] = Stats((yb - ya) / BOXSIZE)              # > 0: the first is higher
    aa = sum(it.area for it in A) / length(A); ab = sum(it.area for it in B) / length(B)
    p.feats[:larger] = Stats(log(max(aa, 1.0) / max(ab, 1.0)))
    # +1: some first-kind figure inside a second-kind one and never the reverse
    ab = any(a -> any(b -> _inside(r, a.obj, b.obj), B), A)
    ba = any(b -> any(a -> _inside(r, b.obj, a.obj), A), B)
    p.feats[:inside] = Stats(ab == ba ? 0.0 : ab ? 1.0 : -1.0)
    push!(e.children, p)
end

function _contrast!(e::RNode, tag, na::Int, nb::Int)
    (na + nb) > 0 || return
    c = RNode(Symbol("contrast@", tag))
    c.feats[:diff] = Stats(Float64(sign(na - nb)))          # more, as many, fewer: not a count
    push!(e.children, c)
end

function _relations!(e::RNode, items::Vector{XItem}, r::Retina)
    figs = filter(it -> it.kind != :dot, items)
    bykind = Dict{Symbol,Vector{XItem}}()
    for it in items
        push!(get!(bykind, it.kind, XItem[]), it)
    end
    # kinds pair up: "the triangle is above the circle" (BP #36), "inside" (BP #47);
    # several figures of a kind are taken together (their mean position and size)
    ks = sort([k for k in keys(bykind) if !(k in (:figure, :segment))])
    for i in eachindex(ks), j in i+1:length(ks)
        _pair!(e, Symbol(ks[i], "_", ks[j]), bykind[ks[i]], bykind[ks[j]], r)
    end
    # the two textures as groups (BP #48)
    F = filter(it -> it.filled, figs); O = filter(it -> !it.filled, figs)
    (!isempty(F) && !isempty(O)) && _pair!(e, :filled_outlined, F, O, r)
    # counts compared (§11.2.1, BPs #27, #28)
    _contrast!(e, :filled_outlined, length(F), length(O))
    for k in unique(it.kind for it in figs)
        nf = count(it -> it.kind == k && it.filled, figs); no = count(it -> it.kind == k && !it.filled, figs)
        _contrast!(e, Symbol("filled", k, "_outlined", k), nf, no)
    end
    # inside vs outside the largest figure (BP #29)
    if length(items) >= 3
        big = argmax(it -> it.area, isempty(figs) ? items : figs)
        rest = filter(it -> it.obj != big.obj, items)
        nin = count(it -> _inside(r, it.obj, big.obj), rest)
        nin > 0 && _contrast!(e, :inside_outside, nin, length(rest) - nin)
    end
end

# --- nesting and similarity (§11.2.5, §7.4.10) ----------------------------------------------------

function _depth(items::Vector{XItem}, r::Retina)
    ids = [it.obj for it in items]
    memo = Dict{Int,Int}()
    d(a) = get!(memo, a) do
        m = 0
        for b in ids
            b != a && _inside(r, a, b) && (m = max(m, 1 + d(b)))
        end
        m
    end
    return maximum((d(a) for a in ids); init=0)
end

_samekind(a::Symbol, b::Symbol) = a == b || (a in (:dot, :circle) && b in (:dot, :circle))

function _shape_distance(a::XItem, b::XItem; size::Bool=false)
    d = (_samekind(a.kind, b.kind) ? 0.0 : 1.5) + (a.filled != b.filled ? 1.0 : 0.0) +
        (a.k >= 3 && b.k >= 3 ? 0.5 * abs(a.k - b.k) : 0.0) +
        ((a.holes > 0) != (b.holes > 0) ? 1.0 : 0.0) +
        abs(a.elong - b.elong) / 0.15 + abs(a.missing - b.missing) / 0.08
    size && (d += abs(log(max(a.area, 1.0) / max(b.area, 1.0))) / 0.25)
    return d
end

function _similarity!(e::RNode, items::Vector{XItem})
    figs = filter(it -> it.kind != :dot, items)
    length(figs) >= 2 || return
    sims = Float64[]; idents = Float64[]
    for i in eachindex(figs), j in i+1:length(figs)
        push!(sims, exp(-_shape_distance(figs[i], figs[j])))
        push!(idents, exp(-_shape_distance(figs[i], figs[j]; size=true)))
    end
    # judged, not measured: are they similar (identical) or not?
    t = 0.5
    e.feats[:simmin] = Stats(all(>=(t), sims) ? 1.0 : 0.0)
    e.feats[:simmax] = Stats(any(>=(t), sims) ? 1.0 : 0.0)
    e.feats[:identmin] = Stats(all(>=(t), idents) ? 1.0 : 0.0)
    # the largest set of mutually identical figures (BP #91)
    best = 1
    for a in figs
        best = max(best, count(b -> exp(-_shape_distance(a, b; size=true)) >= 0.5, figs))
    end
    e.feats[:nsame] = Stats(Float64(best))
end

# --- groups of like figures (Gestalt grouping, §11.2.6) ----------------------------------------------

function _groups!(e::RNode, items::Vector{XItem}, r::Retina)
    bykind = Dict{Symbol,Vector{XItem}}()
    for it in items
        push!(get!(bykind, it.kind, XItem[]), it)
    end
    # a kind of both textures also groups by texture (BP #41: the outlined circles)
    for k in collect(keys(bykind))
        F = filter(it -> it.filled, bykind[k]); O = filter(it -> !it.filled, bykind[k])
        if !isempty(F) && !isempty(O)
            length(F) >= 3 && (bykind[Symbol("filled", k)] = F)
            length(O) >= 3 && (bykind[Symbol("outlined", k)] = O)
        end
    end
    for (k, its) in bykind
        length(its) >= 3 || continue
        n = length(its)
        mx = sum(it.c[1] for it in its) / n; my = sum(it.c[2] for it in its) / n
        a = sum((it.c[1] - mx)^2 for it in its) / n
        b = sum((it.c[1] - mx) * (it.c[2] - my) for it in its) / n
        c = sum((it.c[2] - my)^2 for it in its) / n
        disc = sqrt(max((a - c)^2 / 4 + b^2, 0.0))
        l1, l2 = (a + c) / 2 + disc, max((a + c) / 2 - disc, 0.0)
        l1 > 0 || continue
        g = RNode(Symbol("group@", k))
        g.feats[:collinear] = Stats(sqrt(l2 / l1))              # 0: on one line
        g.feats[:gelong] = Stats(1 - sqrt(l2 / l1))
        ux, uy = abs(b) > 1e-12 ? (l1 - c, b) ./ hypot(l1 - c, b) : (a >= c ? (1.0, 0.0) : (0.0, 1.0))
        g.feats[:gvert] = Stats(abs(uy))
        # some three on a straight line (BP #40)
        best = Inf
        for i in 1:n, j in 1:n, m in 1:n
            (i < j && j != m && i != m) || continue
            p, q, s = its[i].c, its[j].c, its[m].c
            L = dist(p, q)
            L > 0 || continue
            # s between p and q, distance from the line pq relative to |pq|
            t = ((s[1] - p[1]) * (q[1] - p[1]) + (s[2] - p[2]) * (q[2] - p[2])) / L^2
            0 < t < 1 || continue
            dd = abs((q[1] - p[1]) * (p[2] - s[2]) - (p[1] - s[1]) * (q[2] - p[2])) / L
            best = min(best, dd / L)
        end
        isfinite(best) && (g.feats[:tricol] = Stats(best))
        # the outline of the group as a whole (BP #96: hatching that makes a triangle)
        h = Hull()
        for it in its, p in r.objects[it.obj].hull.v
            push!(h, p)
        end
        if length(h.v) >= 3
            xs = [p[1] for p in h.v]; ys = [p[2] for p in h.v]
            g.feats[:gcorners] = Stats(Float64(_corners(h.v, 0.15 * max(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys)))))
        end
        push!(e.children, g)
    end
end

"""Add the extended percepts of one look to its exemplar. Returns the number of nodes added."""
function extend!(e::RNode, ws::BoxWS, ctx::Ctx)
    r = ws.retina
    before = nnodes(e)
    items = _items(e, ws)
    for it in items
        it.rnode === nothing || _figure_features!(it, r, ctx.P)
    end
    _relations!(e, items, r)
    d = _depth(items, r)
    length(items) >= 2 && (e.feats[:depth] = Stats(Float64(d)))
    _similarity!(e, items)
    _groups!(e, items, r)
    # a box drawn in many parts (hatching, dots) may make one figure: the
    # corners of the outline of all its ink (BP #96)
    if length(items) >= 4
        h = Hull()
        for it in items, p in r.objects[it.obj].hull.v
            push!(h, p)
        end
        if length(h.v) >= 3
            xs = [p[1] for p in h.v]; ys = [p[2] for p in h.v]
            e.feats[:bcorners] = Stats(Float64(_corners(h.v, 0.18 * max(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys)))))
        end
    end
    return nnodes(e) - before
end
