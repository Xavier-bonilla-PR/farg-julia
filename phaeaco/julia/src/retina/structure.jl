# The retina's later processes, which work on the lines D and H produced:
# E (intersections), K (K-points), M (line strings), G (curves), O (closure,
# ellipses and circles), i (dots), Z (zooming small objects), plus the
# object-level measurements codelets ask for (§10.3.5–10.3.18).

# --- objects ----------------------------------------------------------------------

"""Group the seen pixels into objects (connected components) and set each line's object."""
function resolve_objects!(r::Retina)
    groups = Dict{Int,Vector{Int}}()
    for li in eachindex(r.uf)
        r.uf[li] == 0 && continue
        push!(get!(groups, uf_find(r, li), Int[]), li)
    end
    empty!(r.objects); empty!(r.comp_of)
    for root in sort!(collect(keys(groups)))
        pix = groups[root]
        xs = [_xy(r, li)[1] for li in pix]
        ys = [_xy(r, li)[2] for li in pix]
        id = length(r.objects) + 1
        o = RetObject(id, pix, (minimum(xs), maximum(xs), minimum(ys), maximum(ys)), length(pix),
                      Hole[], 0.0, Hull(), 0.0, (sum(xs) / length(xs), sum(ys) / length(ys)),
                      0.0, false, 0.0, 0.0, 0.0, 1.0, false, false,
                      Int[], Int[], Int[], Int[], Int[], Int[])
        push!(r.objects, o)
        r.comp_of[root] = id
    end
    for l in r.lines
        l.comp = get(r.comp_of, uf_find(r, l.anchor), 0)
        l.comp == 0 && (l.alive = false)
    end
    for li in r.thick
        id = get(r.comp_of, uf_find(r, li), 0)
        id == 0 || push!(r.objects[id].endoskeleton, li)
    end
end

"""
Within objects that have thick (filled) parts, the skeleton of a thin
corner can still reach process D as `:endo` points, giving medial-axis
fragments that are not sides. Drop endo lines lying mostly in the thick
zone; filled parts are described by their exoskeleton (§7.4.9).
"""
function drop_medial_lines!(r::Retina)
    reach = Int(r.P[:retina_thick_depth]) + 1
    td = r.P[:retina_thick_depth]
    for l in r.lines
        (l.alive && l.src == :endo) || continue
        isempty(r.objects[l.comp].endoskeleton) && continue
        inzone = 0
        for p in l.pts
            x, y = round(Int, p[1]), round(Int, p[2])
            found = false
            for dy in -reach:reach, dx in -reach:reach
                if _ink(r, x + dx, y + dy) && r.depth[y+dy, x+dx] >= td
                    found = true
                    break
                end
            end
            inzone += found
        end
        inzone > length(l.pts) / 2 && (l.alive = false)
    end
end

# --- process i and process Z ----------------------------------------------------------

"""
Process i (§10.3.10): an object too small to be given a shape is a dot.
Process Z (§10.3.17): an object small enough that its pixels are ambiguous
is magnified — with a probabilistic size threshold — and looked at again by a
fresh retina; its lines and structures replace the ones seen at full scale.
"""
function dots_and_zoom!(r::Retina)
    dotsize = r.P[:retina_dot_size]
    for o in r.objects
        xmin, xmax, ymin, ymax = o.bbox
        sz = max(xmax - xmin + 1, ymax - ymin + 1)
        if sz <= dotsize
            o.isdot = true
            push!(r.dots, DotDet(length(r.dots) + 1, o.barycenter, o.ink, o.id))
            for l in r.lines
                l.comp == o.id && (l.alive = false)
            end
        elseif !r.nozoom && sz < sample(thr(r.P, :retina_zoom_size), r.rng)
            zoom_object!(r, o)
        end
    end
end

"""Fuzzy ×2 magnification of an object's pixels (§10.3.17, Fig. 10.27 a–c)."""
function magnify(r::Retina, o::RetObject; margin::Int=2)
    xmin, xmax, ymin, ymax = o.bbox
    xs, ys = xmin - margin, ymin - margin
    w, h = xmax - xmin + 1 + 2margin, ymax - ymin + 1 + 2margin
    mine = falses(r.h, r.w)
    for li in o.pixels
        x, y = _xy(r, li)
        mine[y, x] = true
    end
    Z = falses(2h, 2w)
    for Y in 1:2h, X in 1:2w
        sx, sy = xs - 1 + (X + 0.5) / 2, ys - 1 + (Y + 0.5) / 2
        num = den = 0.0
        for py in floor(Int, sy)-1:ceil(Int, sy)+1, px in floor(Int, sx)-1:ceil(Int, sx)+1
            wgt = max(0.0, 1.5 - abs(sx - px)) * max(0.0, 1.5 - abs(sy - py))
            wgt == 0 && continue
            den += wgt
            (1 <= px <= r.w && 1 <= py <= r.h && mine[py, px]) && (num += wgt)
        end
        Z[Y, X] = num / den >= r.P[:retina_zoom_gray]
    end
    return Z, xs, ys
end

function zoom_object!(r::Retina, o::RetObject)
    Z, xs, ys = magnify(r, o)
    sub = Retina(Z, r.P, Xoshiro(rand(r.rng, UInt64)); tracer=r.tracer, nozoom=true, scale=2.0)
    run_retina!(sub)
    back(p::Pt) = (xs - 1 + (p[1] + 0.5) / 2, ys - 1 + (p[2] + 0.5) / 2)
    for l in r.lines
        l.comp == o.id && (l.alive = false)
    end
    idmap = Dict{Int,Int}()
    for l in sub.lines
        l.alive || continue
        nl = _new_line!(r, [back(p) for p in l.pts], o.pixels[1], l.src)
        nl.comp = o.id
        idmap[l.id] = nl.id
    end
    o.zoomed = true
    # The structures were found at twice the scale, where the pixels were less
    # ambiguous; bring them back rather than recompute them here.
    for jn in sub.junctions
        all(haskey(idmap, l) for l in jn.lines) || continue
        push!(r.junctions, Junction(length(r.junctions) + 1, jn.kind, back(jn.p),
                                    [idmap[l] for l in jn.lines], copy(jn.ends), o.id))
        for (k, l) in enumerate(jn.lines)
            e = jn.ends[k]
            e == 0 && continue
            nl = r.lines[idmap[l]]
            e == 1 ? (nl.p1 = back(jn.p)) : (nl.p2 = back(jn.p))
        end
    end
    for st in sub.strings
        all(haskey(idmap, l) for l in st.lines) || continue
        push!(r.strings, LineString(length(r.strings) + 1, [idmap[l] for l in st.lines], copy(st.flip),
                                    st.closed, o.id))
    end
    for c in sub.curves
        all(haskey(idmap, l) for l in c.lines) || continue
        knots = [back(k) for k in c.knots]
        push!(r.curves, CurveDet(length(r.curves) + 1, [idmap[l] for l in c.lines], knots,
                                 cubic_spline(knots), c.closed, o.id))
    end
    for e in sub.ellipses
        push!(r.ellipses, EllipseDet(length(r.ellipses) + 1, back(e.centre), e.axes ./ 2, e.theta, e.ecc,
                                     e.circle, e.rms / 2, [idmap[l] for l in e.lines if haskey(idmap, l)], o.id))
    end
    # texture is better judged at the larger scale, where small filled shapes have a thick interior
    if !isempty(sub.objects)
        ink = sum(so.ink for so in sub.objects)
        o.texture = sum(so.texture * so.ink for so in sub.objects) / max(ink, 1)
    end
    trace(r.tracer, 3, r.now, "Z zoomed object", o.id, "lines", length(idmap))
    return idmap
end

_zoomed(r::Retina, comp::Int) = r.objects[comp].zoomed

# --- process E and process K -------------------------------------------------------

"""Fraction of sampled points between a and b that have foreground within 1 px."""
function _inked(r::Retina, a::Pt, b::Pt)
    L = dist(a, b)
    L < 1 && return 1.0
    n = max(2, ceil(Int, L))
    hit = 0
    for k in 0:n
        t = k / n
        x, y = round(Int, a[1] + t * (b[1] - a[1])), round(Int, a[2] + t * (b[2] - a[2]))
        hit += any(_ink(r, x + dx, y + dy) for dx in -1:1, dy in -1:1)
    end
    return hit / (n + 1)
end

"""
Process E (§10.3.5): where two lines of an object meet. The lines are
extended to their intersection; a meeting is accepted if the intersection is
close to both segments, there is ink there, and the extensions run over ink.
Each line meets either with an end or through its interior, which gives the
type: vertex (end–end), touch (end–interior), cross (interior–interior).
Nearly collinear lines can only meet end to end (the joints of a curve).
"""
function process_E!(r::Retina)
    reach, endr = r.P[:retina_junction_reach], r.P[:retina_junction_end]
    alive = [l for l in r.lines if l.alive]
    for i in 1:length(alive), j in i+1:length(alive)
        a, b = alive[i], alive[j]
        (a.comp == b.comp && !_zoomed(r, a.comp)) || continue
        if line_angle(a.d, b.d) < r.P[:retina_collinear_angle]
            # end-to-end only
            best = (Inf, 0, 0)
            for ea in 1:2, eb in 1:2
                d = dist(endpoint(a, ea), endpoint(b, eb))
                d < best[1] && (best = (d, ea, eb))
            end
            best[1] <= endr || continue
            pa, pb = endpoint(a, best[2]), endpoint(b, best[3])
            _inked(r, pa, pb) >= 0.7 || continue
            p = ((pa[1] + pb[1]) / 2, (pa[2] + pb[2]) / 2)
            push!(r.junctions, Junction(length(r.junctions) + 1, :V, p, [a.id, b.id], [best[2], best[3]], a.comp))
            continue
        end
        I = line_intersection(a.p1, a.p2, b.p1, b.p2)
        I === nothing && continue
        (segdist(I, a.p1, a.p2) <= reach && segdist(I, b.p1, b.p2) <= reach) || continue
        any(_ink(r, round(Int, I[1]) + dx, round(Int, I[2]) + dy) for dx in -1:1, dy in -1:1) || continue
        ends = Int[]
        ok = true
        for l in (a, b)
            d1, d2 = dist(I, l.p1), dist(I, l.p2)
            if min(d1, d2) <= endr
                e = d1 <= d2 ? 1 : 2
                _inked(r, endpoint(l, e), I) >= 0.7 || (ok = false)
                push!(ends, e)
            else
                push!(ends, 0)
            end
        end
        ok || continue
        kind = ends[1] != 0 && ends[2] != 0 ? :V : (ends[1] == 0 && ends[2] == 0 ? :X : :T)
        push!(r.junctions, Junction(length(r.junctions) + 1, kind, I, [a.id, b.id], ends, a.comp))
    end
    # move the meeting ends of lines onto their junction points
    for jn in r.junctions, (k, lid) in enumerate(jn.lines)
        e = jn.ends[k]
        e == 0 && continue
        l = r.lines[lid]
        e == 1 ? (l.p1 = jn.p) : (l.p2 = jn.p)
    end
end

"""
Process H's second pass, after E: a short line meeting a nearly collinear
line end to end is a fragment of it — typically the tip of a side beyond a
sharp corner, whose pixels the other side claimed, or half of a noisy border
side. Absorb it: extend the longer line to the fragment's far end and hand
it the fragment's junctions (D13).
"""
function absorb_fragments!(r::Retina)
    fraglen = r.P[:retina_fragment_length]
    changed = true
    while changed
        changed = false
        for (ji, jn) in enumerate(r.junctions)
            (jn.kind == :V && length(jn.lines) == 2 && all(!=(0), jn.ends)) || continue
            a, b = r.lines[jn.lines[1]], r.lines[jn.lines[2]]
            ea, eb = jn.ends
            if linelength(a) > linelength(b)
                a, b, ea, eb = b, a, eb, ea
            end
            (a.alive && b.alive) || continue
            (linelength(a) <= fraglen && line_angle(a.d, b.d) <= r.P[:retina_collinear_angle]) || continue
            far = endpoint(a, 3 - ea)
            for p in a.pts
                push!(b.fit, p); push!(b.pts, p)
            end
            b.c, b.d, b.rms = linefit(b.fit)
            eb == 1 ? (b.p1 = far) : (b.p2 = far)
            a.alive = false
            deleteat!(r.junctions, ji)
            for other in r.junctions, k in eachindex(other.lines)
                other.lines[k] == a.id || continue
                other.lines[k] = b.id
                other.ends[k] = other.ends[k] == 3 - ea ? eb : 0
            end
            # a junction may now list b twice; keep one entry
            for other in r.junctions
                if count(==(b.id), other.lines) > 1
                    k = findlast(==(b.id), other.lines)
                    deleteat!(other.lines, k); deleteat!(other.ends, k)
                end
            end
            filter!(j -> length(j.lines) >= 2, r.junctions)
            changed = true
            trace(r.tracer, 3, r.now, "H absorb fragment", a.id, "into", b.id)
            break
        end
    end
    for (i, jn) in enumerate(r.junctions)
        jn.id = i
    end
end

"""
Process K (§10.3.11): junctions too close together to be told apart are
unified into a single K-point, when three or more lines meet there.
"""
function process_K!(r::Retina)
    rad = r.P[:retina_kpoint_radius]
    n = length(r.junctions)
    group = collect(1:n)
    find(i) = (while group[i] != i; i = group[i]; end; i)
    for i in 1:n, j in i+1:n
        _zoomed(r, r.junctions[i].comp) && continue
        (r.junctions[i].comp == r.junctions[j].comp && dist(r.junctions[i].p, r.junctions[j].p) <= rad) || continue
        gi, gj = find(i), find(j)
        gi != gj && (group[max(gi, gj)] = min(gi, gj))
    end
    out = Junction[]
    members = Dict{Int,Vector{Int}}()
    for i in 1:n
        push!(get!(members, find(i), Int[]), i)
    end
    for g in sort!(collect(keys(members)))
        js = [r.junctions[i] for i in members[g]]
        if length(js) == 1
            push!(out, js[1])
            continue
        end
        lines, ends = Int[], Int[]
        for jn in js, (k, l) in enumerate(jn.lines)
            idx = findfirst(==(l), lines)
            if idx === nothing
                push!(lines, l); push!(ends, jn.ends[k])
            elseif ends[idx] == 0
                ends[idx] = jn.ends[k]
            end
        end
        p = (sum(j.p[1] for j in js) / length(js), sum(j.p[2] for j in js) / length(js))
        kind = length(lines) >= 3 ? :K : js[1].kind
        push!(out, Junction(0, kind, p, lines, ends, js[1].comp))
    end
    for (i, jn) in enumerate(out)
        jn.id = i
    end
    r.junctions = out
end

# --- process M --------------------------------------------------------------------------

"""
Process M (§10.3.7): line strings — lines joined end to end at vertices.
A figure can usually be parsed into strings in several ways; we parse
greedily, longest lines first and always continuing along the straightest
way on, so the parse is biased towards long strings of long lines but
varies with the order lines were found in, as the thesis describes.
"""
function process_M!(r::Retina)
    # adjacency: (line, end) → [(other line, other end, junction)]
    adj = Dict{Tuple{Int,Int},Vector{Tuple{Int,Int,Int}}}()
    for jn in r.junctions, a in eachindex(jn.lines), b in eachindex(jn.lines)
        (a == b || _zoomed(r, jn.comp)) && continue
        (jn.ends[a] != 0 && jn.ends[b] != 0) || continue
        push!(get!(adj, (jn.lines[a], jn.ends[a]), Tuple{Int,Int,Int}[]), (jn.lines[b], jn.ends[b], jn.id))
    end
    used = Set{Int}()
    order = sort([l for l in r.lines if l.alive && !_zoomed(r, l.comp)]; by=l -> -linelength(l) + 0.01 * rand(r.rng))
    for start in order
        start.id in used && continue
        push!(used, start.id)
        chain = [(start.id, false)]        # (line, flipped?) — unflipped runs p1 → p2
        # extend forward from the end of the chain, then backward from its start
        for dir in (:fwd, :bwd)
            while true
                lid, fl = dir == :fwd ? chain[end] : chain[1]
                e = dir == :fwd ? (fl ? 1 : 2) : (fl ? 2 : 1)
                l = r.lines[lid]
                here = endpoint(l, e)
                there = endpoint(l, 3 - e)
                best, bestang = nothing, -1.0
                for (m, me, _) in get(adj, (lid, e), ())
                    m in used && continue
                    ml = r.lines[m]
                    ang = vertex_angle(here, there, endpoint(ml, 3 - me))
                    ang > bestang && (best = (m, me); bestang = ang)
                end
                best === nothing && break
                m, me = best
                push!(used, m)
                if dir == :fwd
                    push!(chain, (m, me == 2))         # enter at me, so flipped if entering at p2
                else
                    pushfirst!(chain, (m, me == 1))
                end
            end
        end
        length(chain) >= 2 || continue
        # closed if the two free ends meet at a junction
        (fl, ll) = chain[1], chain[end]
        e_first = fl[2] ? 2 : 1
        e_last = ll[2] ? 1 : 2
        closed = any(t -> t[1] == ll[1] && t[2] == e_last, get(adj, (fl[1], e_first), ()))
        push!(r.strings, LineString(length(r.strings) + 1, first.(chain), last.(chain), closed,
                                    r.lines[start.id].comp))
    end
end

# --- process G ----------------------------------------------------------------------------

_dir(l::LineDet, flip::Bool) = flip ? (-l.d[1], -l.d[2]) : l.d

"""
Process G (§10.3.8): which parts of line strings are really curves. At each
joint we look at how the skeleton points deviate from the two straight
segments meeting there: on a curve, both segments' points bow consistently
with the turn, and the turn is moderate; at a true corner, the points sit on
the segments. Very gentle turns are taken as curves outright. Runs of curved
joints become curve detectors, represented by a parametric cubic spline
through their knots (Appendix B).
"""
function process_G!(r::Retina)
    for s in r.strings
        _zoomed(r, s.comp) && continue
        n = length(s.lines)
        njoints = s.closed ? n : n - 1
        curved = falses(njoints)
        for k in 1:njoints
            a, b = r.lines[s.lines[k]], r.lines[s.lines[k%n+1]]
            da, db = _dir(a, s.flip[k]), _dir(b, s.flip[k%n+1])
            turn = da[1] * db[2] - da[2] * db[1]
            defl = acosd(clamp(da[1] * db[1] + da[2] * db[2], -1.0, 1.0))
            ba, bb = bow(a), bow(b)
            # bow sign relative to traversal: flipping a line flips the sign of its perpendicular
            s.flip[k] && (ba = -ba)
            s.flip[k%n+1] && (bb = -bb)
            bmin = r.P[:retina_bow_min]
            consistent = sign(ba) == sign(turn) && sign(bb) == sign(turn) && abs(ba) >= bmin && abs(bb) >= bmin
            curved[k] = defl <= r.P[:retina_gentle_turn] ||
                        (defl <= r.P[:retina_curve_turn] && consistent)
        end
        any(curved) || continue
        # maximal runs of curved joints
        if s.closed && all(curved)
            _add_curve!(r, s, collect(1:n), true)
            continue
        end
        k = 1
        while k <= njoints
            if curved[k] && (k == 1 || !curved[k-1])
                j = k
                while j < njoints && curved[j+1]
                    j += 1
                end
                # joints k..j connect lines k..j+1
                _add_curve!(r, s, [mod1(i, n) for i in k:j+1], false)
                k = j + 1
            else
                k += 1
            end
        end
    end
end

function _add_curve!(r::Retina, s::LineString, idx::Vector{Int}, closed::Bool)
    lines = [s.lines[i] for i in idx]
    knots = Pt[]
    for (q, i) in enumerate(idx)
        l = r.lines[s.lines[i]]
        a, b = s.flip[i] ? (l.p2, l.p1) : (l.p1, l.p2)
        q == 1 && push!(knots, a)
        push!(knots, b)
    end
    push!(r.curves, CurveDet(length(r.curves) + 1, lines, knots, cubic_spline(knots), closed, s.comp))
end

# --- process O ------------------------------------------------------------------------------

"""
Process O, second task (§10.3.12): ellipses and circles — the only shapes
hard-wired into Phaeaco. Candidate point sets are each closed (or nearly
closed) line string, and each object's lines taken together. A candidate is
an ellipse if the conic fit of Appendix B is tight and its points go most of
the way round; an eccentricity under the (sampled) circle threshold makes it
a circle. The tolerance was set from measurements: drawn circles and ellipses
fit with rms 0.2–0.45 px, polygons with 0.5 px or more unless they are so
small that people see them as round too (D14).
"""
function process_O_ellipses!(r::Retina)
    cands = Vector{Vector{Int}}()
    for s in r.strings
        _zoomed(r, s.comp) && continue
        length(s.lines) >= 4 || continue
        if !s.closed
            # a string whose ends nearly meet (a missed joint) still bounds a region
            a = r.lines[s.lines[1]]; b = r.lines[s.lines[end]]
            ea = s.flip[1] ? a.p2 : a.p1
            eb = s.flip[end] ? b.p1 : b.p2
            dist(ea, eb) <= r.P[:retina_junction_end] + 2 || continue
        end
        push!(cands, sort(s.lines))
    end
    for o in r.objects
        (o.isdot || o.zoomed) && continue
        ls = sort([l.id for l in r.lines if l.alive && l.comp == o.id])
        length(ls) >= 4 && push!(cands, ls)
    end
    unique!(cands)
    sort!(cands; by=c -> -length(c))         # whole objects before their parts
    taken = Set{Int}()
    for ls in cands
        any(in(taken), ls) && continue
        pts = Pt[]
        for lid in ls
            append!(pts, r.lines[lid].pts)
        end
        fit = fit_conic(pts)
        (fit === nothing || !fit.ellipse) && continue
        fit.rms <= r.P[:retina_conic_rms] * r.scale || continue
        fit.axes[2] >= 2.0 * r.scale || continue
        _coverage(pts, fit.centre) >= r.P[:retina_conic_coverage] || continue
        comp = r.lines[ls[1]].comp
        iscircle = fit.ecc < sample(thr(r.P, :retina_circle_ecc), r.rng)
        push!(r.ellipses, EllipseDet(length(r.ellipses) + 1, fit.centre, fit.axes, fit.theta, fit.ecc,
                                     iscircle, fit.rms, ls, comp))
        union!(taken, ls)
        trace(r.tracer, 3, r.now, "O ellipse", comp, iscircle ? "circle" : "ellipse", round(fit.ecc; digits=2))
    end
end

"""Fraction of 24 angular sectors around `c` that contain points."""
function _coverage(pts::Vector{Pt}, c::Pt)
    bins = falses(24)
    for p in pts
        θ = atan(p[2] - c[2], p[1] - c[1])
        bins[clamp(floor(Int, (θ + π) / (2π) * 24) + 1, 1, 24)] = true
    end
    return count(bins) / 24
end

"""
Process O, first task (§10.3.12), and the other object measurements
(§10.3.18): enclosed regions and their areas, the convex hull, how much of
the hull is missing and how open the concavities are, texture, barycenter
and elongation.
"""
function measure_objects!(r::Retina)
    h, w = r.h, r.w
    # What each object encloses: flood from the box edge with only that object
    # as an obstacle; whatever is not reached is enclosed by it. Its connected
    # parts are the object's interiors (holes), which may contain other objects.
    enclosed_of = Dict{Int,BitVector}()
    holes_of = Dict{Int,Vector{Hole}}()
    tiny_of = Dict{Int,Int}()
    mine = falses(h * w)
    for o in r.objects
        o.isdot && continue
        fill!(mine, false)
        for li in o.pixels
            mine[li] = true
        end
        reached = falses(h * w)
        stack = Int[]
        for x in 1:w, y in (1, h)
            li = _li(r, x, y)
            (!mine[li] && !reached[li]) && (reached[li] = true; push!(stack, li))
        end
        for y in 1:h, x in (1, w)
            li = _li(r, x, y)
            (!mine[li] && !reached[li]) && (reached[li] = true; push!(stack, li))
        end
        while !isempty(stack)
            li = pop!(stack)
            x, y = _xy(r, li)
            for (dx, dy) in N4
                nx, ny = x + dx, y + dy
                _inb(r, nx, ny) || continue
                nli = _li(r, nx, ny)
                (mine[nli] || reached[nli]) && continue
                reached[nli] = true
                push!(stack, nli)
            end
        end
        enclosed = .!(reached .| mine)
        any(enclosed) || continue
        enclosed_of[o.id] = enclosed
        # split into interiors
        seen = falses(h * w)
        for li in findall(enclosed)
            seen[li] && continue
            pix = Int[]
            stack = [li]; seen[li] = true
            while !isempty(stack)
                q = pop!(stack)
                push!(pix, q)
                x, y = _xy(r, q)
                for (dx, dy) in N4
                    nx, ny = x + dx, y + dy
                    _inb(r, nx, ny) || continue
                    nq = _li(r, nx, ny)
                    (enclosed[nq] && !seen[nq]) || continue
                    seen[nq] = true
                    push!(stack, nq)
                end
            end
            # pockets of a pixel or two (at a sharp vertex) are below
            # discrimination (§7.4.1): they count towards area, not as interiors
            if length(pix) < r.P[:retina_hole_min_area] * r.scale^2 && !any(q -> r.img[q], pix)
                tiny_of[o.id] = get(tiny_of, o.id, 0) + length(pix)
                continue
            end
            push!(get!(holes_of, o.id, Hole[]), Hole(length(pix), pix))
        end
    end
    thickd = r.P[:retina_thick_depth]
    for o in r.objects
        o.holes = get(holes_of, o.id, Hole[])
        o.area = o.ink + get(tiny_of, o.id, 0) + sum((hl.area for hl in o.holes); init=0)
        # hull of pixel corners, from border pixels only
        for li in o.pixels
            x, y = _xy(r, li)
            _isborder(r, x, y) || continue
            for (cx, cy) in ((x - 0.5, y - 0.5), (x + 0.5, y - 0.5), (x - 0.5, y + 0.5), (x + 0.5, y + 0.5))
                push!(o.hull, (cx, cy))
            end
        end
        o.hull_area = polygon_area(o.hull.v)
        o.missing = o.hull_area > 0 ? clamp((o.hull_area - o.area) / o.hull_area, 0.0, 1.0) : 0.0
        if !o.zoomed
            nthick = count(li -> (xy = _xy(r, li); r.depth[xy[2], xy[1]] >= thickd), o.pixels)
            o.texture = nthick / o.ink
        end
        o.filled = !o.isdot && exceeds(o.texture, thr(r.P, :retina_filled_fraction), r.rng)
        # second moments of the silhouette
        sx = sy = sxx = sxy = syy = 0.0
        n = 0
        for li in Iterators.flatten((o.pixels, (p for hl in o.holes for p in hl.pixels)))
            x, y = _xy(r, li)
            sx += x; sy += y; sxx += x * x; sxy += x * y; syy += y * y; n += 1
        end
        mx, my = sx / n, sy / n
        a, b, c = sxx / n - mx^2, sxy / n - mx * my, syy / n - my^2
        disc = sqrt(max((a - c)^2 / 4 + b^2, 0.0))
        l1, l2 = (a + c) / 2 + disc, max((a + c) / 2 - disc, 0.0)
        o.elongation = l1 > 0 ? 1 - sqrt(l2 / l1) : 0.0
        o.axis_deg = slope_deg(abs(b) > 1e-12 ? (l1 - c, b) ./ hypot(l1 - c, b) : (a >= c ? (1.0, 0.0) : (0.0, 1.0)))
        o.openness = o.missing > r.P[:retina_concavity_min] ? openness(r, o) : 1.0
    end
    # inside relations (§7.4.7): wholly within what another object encloses,
    # or (less completely) within its convex hull, i.e. in one of its bays
    for b in r.objects, a in r.objects
        a.id == b.id && continue
        if haskey(enclosed_of, a.id) && count(p -> enclosed_of[a.id][p], b.pixels) >= 0.95 * b.ink
            push!(r.insides, (b.id, a.id, 1.0))
        elseif length(a.hull.v) >= 3 && count(p -> point_in_hull(a.hull, pixpt(r, p)), b.pixels) >= 0.95 * b.ink
            push!(r.insides, (b.id, a.id, 0.5))
        end
    end
    for l in r.lines
        l.alive && push!(r.objects[l.comp].lines, l.id)
    end
    for j in r.junctions
        push!(r.objects[j.comp].junctions, j.id)
    end
    for s in r.strings
        push!(r.objects[s.comp].strings, s.id)
    end
    for c in r.curves
        push!(r.objects[c.comp].curves, c.id)
    end
    for e in r.ellipses
        push!(r.objects[e.comp].ellipses, e.id)
    end
end

"""
Openness of an object's concavities (§7.4.7, Fig. 7.37): sample points in
the hull but outside the object, send 16 rays from each, and count the
fraction that escape the hull without meeting ink.
"""
function openness(r::Retina, o::RetObject)
    xmin, xmax, ymin, ymax = o.bbox
    inhole = Set{Int}(p for hl in o.holes for p in hl.pixels)
    esc = tot = 0
    samples = 0
    tries = 0
    nsamp = Int(r.P[:retina_openness_samples])
    while samples < nsamp && tries < 50nsamp
        tries += 1
        x, y = rand(r.rng, xmin:xmax), rand(r.rng, ymin:ymax)
        (r.img[y, x] || _li(r, x, y) in inhole || !point_in_hull(o.hull, (Float64(x), Float64(y)))) && continue
        samples += 1
        for k in 0:15
            θ = 2π * k / 16
            dx, dy = cos(θ), sin(θ)
            escaped = false
            for s in 1:200
                px, py = x + s * dx, y + s * dy
                if !point_in_hull(o.hull, (px, py))
                    escaped = true
                    break
                end
                _ink(r, round(Int, px), round(Int, py)) && break
            end
            esc += escaped
            tot += 1
        end
    end
    return tot == 0 ? 1.0 : esc / tot
end

# --- the scheduler -----------------------------------------------------------------------------

const SETTLE_STAGES = (resolve_objects!, drop_medial_lines!, process_H!, dots_and_zoom!,
                       process_E!, absorb_fragments!, process_K!, process_M!, process_G!, process_O_ellipses!,
                       measure_objects!)

"""
One unit of retinal work. Pixel-level processes run interleaved, each chosen
with probability proportional to how much work it has waiting (§10.2:
processes "lurk" and self-regulate their time); once they are all idle the
structural processes run in dependency order. Returns false when finished.
"""
function step!(r::Retina)
    r.settled && return false
    r.now += 1
    wA = r.a_done ? 0.0 : r.P[:retina_a_weight] * (0.2 + r.hitrate * 10)
    wB = Float64(length(r.bq))
    wF = r.P[:retina_f_weight] * length(r.fq)
    wD = r.P[:retina_d_weight] * length(r.dq)
    tot = wA + wB + wF + wD
    if tot > 0
        u = rand(r.rng) * tot
        if u < wA
            process_A!(r)
        elseif u < wA + wB
            process_B!(r)
        elseif u < wA + wB + wF
            process_F!(r)
        else
            process_D!(r)
        end
        return true
    end
    ensure_sources!(r) && return true
    r.stage += 1
    SETTLE_STAGES[r.stage](r)
    r.stage == length(SETTLE_STAGES) && (r.settled = true)
    return !r.settled
end

function run_retina!(r::Retina)
    while step!(r)
    end
    return r
end

"""Run a full retina on one box."""
see(img::AbstractMatrix{Bool}, P::Params, rng::Xoshiro; kw...) = run_retina!(Retina(img, P, rng; kw...))
