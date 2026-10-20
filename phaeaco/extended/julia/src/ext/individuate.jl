# Object individuation as clustering (Foundalis 2013, "Object Individuation
# as Simple Clustering", Fig. 1; ../../DECISIONS.md X15). Dots dense enough
# make a region: "bringing this idea to its logical limit, we can make the
# dots so dense that their in-between spaces are hard to discern. In that
# case the observer has no choice but see two contiguous dark regions."
#
# The retina's objects are connected pieces of ink, so a triangle drawn as
# hatching is twenty separate lines (BP #96). Here the gaps between nearby
# pieces are closed: ink within `ext_ind_gap` pixels of other ink is joined
# (a closing: dilate, then erode by the same disc). A joined region that
# unites at least `ext_ind_parts` pieces is an individuated figure, a
# `cluster` node with
#
#   shape@K    its kind from the outline: triangle, quadrangle, polygon, circle
#   ccorners   corners of its outline (as X2 counts a hull's corners)
#   cends      free ends of its core (X12)

"""Dilate (`grow = true`) or erode a mask by a disc of radius `k`."""
function _morph(m::BitMatrix, k::Int, grow::Bool)
    h, w = size(m)
    out = falses(h, w)
    offs = [(dx, dy) for dx in -k:k for dy in -k:k if dx^2 + dy^2 <= k^2 + k]
    for y in 1:h, x in 1:w
        if grow
            out[y, x] = any(((dx, dy),) -> _on(m, y + dy, x + dx), offs)
        else
            # outside the box counts as background
            out[y, x] = all(((dx, dy),) -> _on(m, y + dy, x + dx), offs)
        end
    end
    return out
end

"""Connected regions of a mask (8-connected), as vectors of (y, x)."""
function _regions(m::BitMatrix)
    h, w = size(m)
    seen = falses(h, w)
    out = Vector{Vector{Tuple{Int,Int}}}()
    for y in 1:h, x in 1:w
        (m[y, x] && !seen[y, x]) || continue
        reg = [(y, x)]; seen[y, x] = true
        i = 1
        while i <= length(reg)
            cy, cx = reg[i]; i += 1
            for dy in -1:1, dx in -1:1
                ny, nx = cy + dy, cx + dx
                (_on(m, ny, nx) && !seen[ny, nx]) || continue
                seen[ny, nx] = true
                push!(reg, (ny, nx))
            end
        end
        push!(out, reg)
    end
    return out
end

"""Fill the holes of a mask: background not reachable from its border becomes foreground."""
function _fill_holes(m::BitMatrix)
    h, w = size(m)
    outside = falses(h, w)
    st = [(y, x) for y in 1:h, x in 1:w if (y in (1, h) || x in (1, w)) && !m[y, x]]
    foreach(p -> outside[p...] = true, st)
    while !isempty(st)
        y, x = pop!(st)
        for (dx, dy) in N4
            ny, nx = y + dy, x + dx
            (1 <= ny <= h && 1 <= nx <= w && !m[ny, nx] && !outside[ny, nx]) || continue
            outside[ny, nx] = true
            push!(st, (ny, nx))
        end
    end
    return .!outside
end

"""
The kind of an individuated figure, from its outline: the corners of its
convex hull (X2's rule), or round when the hull fills the ellipse inscribed
in its bounding box. Returns `(kind, corners)`.
"""
function _cluster_kind(sil::BitMatrix)
    h, w = size(sil)
    hull = Hull()
    for y in 1:h, x in 1:w
        sil[y, x] && any(((dx, dy),) -> !_on(sil, y + dy, x + dx), N4) && push!(hull, (Float64(x), Float64(y)))
    end
    length(hull.v) >= 3 || return :figure, 0
    k = _corners(hull.v, max(0.18 * max(h, w), 1.5))
    v = hull.v
    area = abs(sum(v[i][1] * v[mod1(i + 1, end)][2] - v[mod1(i + 1, end)][1] * v[i][2] for i in eachindex(v))) / 2
    ratio = area / (π / 4 * w * h)
    k >= 5 && 0.85 <= ratio <= 1.12 && return :circle, k
    k == 3 && return :triangle, k
    k == 4 && return :quadrangle, k
    return :polygon, k
end

"""
Individuate figures made of many pieces and add them to the exemplar.
Returns the number of figures found.
"""
function _individuate!(e::RNode, r::Retina, P::Params)
    length(r.objects) >= P[:ext_ind_parts] || return 0
    k = Int(P[:ext_ind_gap])
    joined = _morph(_morph(r.img, k, true), k, false)
    # which retina object each ink pixel belongs to
    owner = zeros(Int, r.h, r.w)
    for o in r.objects, li in o.pixels
        x, y = _xy(r, li)
        owner[y, x] = o.id
    end
    n = 0
    for reg in _regions(_morph(r.img, k, true))
        parts = unique(owner[y, x] for (y, x) in reg if owner[y, x] > 0)
        length(parts) >= P[:ext_ind_parts] || continue
        ys = first.(reg); xs = last.(reg)
        y0, y1, x0, x1 = minimum(ys), maximum(ys), minimum(xs), maximum(xs)
        sil = falses(y1 - y0 + 1, x1 - x0 + 1)
        for (y, x) in reg
            joined[y, x] && (sil[y-y0+1, x-x0+1] = true)
        end
        sil = _fill_holes(sil)
        count(sil) >= 30 || continue
        kind, corners = _cluster_kind(sil)
        c = RNode(:cluster)
        c.feats[:ccorners] = Stats(Float64(corners))
        core = extract_core(magnify(sil, scale_for(sil, P[:ext_core_scale])); prune=P[:ext_core_prune])
        c.feats[:cends] = Stats(Float64(core.ends))
        push!(c.children, RNode(Symbol("shape@", kind)))
        push!(e.children, c)
        n += 1
    end
    return n
end
