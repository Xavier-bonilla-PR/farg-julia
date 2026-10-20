# Line detection: process D (§10.3.4) and its corrector, process H (§10.3.9).
#
# D works from skeleton (and border) points arriving in random order. It does
# not wait for them all: every point either joins the detector it fits best,
# or waits among the "loose" points until two neighbours line up with it, at
# which point a new, weakly activated detector is born. Detectors that keep
# receiving points grow strong; early false hypotheses that stop receiving
# points decay and are dropped at the end. This is the thesis's own
# description, and, as it notes, the template for the cognitive-level
# grouping algorithm of §8.3.2.

const _CELL = 4

_cell(p::Pt) = (floor(Int, p[1] / _CELL), floor(Int, p[2] / _CELL))
_ckey(cx::Int, cy::Int) = cx * 1000 + cy

function _loose_add!(r::Retina, p::Pt, li::Int, src::Symbol)
    push!(r.loose, (p, li, src))
    push!(r.loose_alive, true)
    cx, cy = _cell(p)
    push!(get!(r.grid, _ckey(cx, cy), Int[]), length(r.loose))
end

function _loose_near(r::Retina, p::Pt, radius::Float64, src::Symbol, root::Int)
    out = Int[]
    cx, cy = _cell(p)
    k = ceil(Int, radius / _CELL)
    for ix in cx-k:cx+k, iy in cy-k:cy+k
        for i in get(r.grid, _ckey(ix, iy), ())
            r.loose_alive[i] || continue
            q, qli, qs = r.loose[i]
            qs == src || continue
            uf_find(r, qli) == root || continue
            dist(p, q) <= radius && push!(out, i)
        end
    end
    return out
end

function _new_line!(r::Retina, pts::Vector{Pt}, anchor::Int, src::Symbol)
    f = LineFit()
    foreach(p -> push!(f, p), pts)
    l = LineDet(length(r.lines) + 1, src, anchor, f, copy(pts),
                Activation(Int(r.P[:retina_line_act_steps]), Int(r.P[:retina_line_act_period]);
                           pos=min(length(pts), Int(r.P[:retina_line_act_steps])), now=r.now),
                (0.0, 0.0), (1.0, 0.0), 0.0, 0.0, 0.0, (0.0, 0.0), (0.0, 0.0), true, 0)
    refit!(l)
    push!(r.lines, l)
    trace(r.tracer, 3, r.now, "D new line", l.id, src)
    return l
end

"""Would adding `p` keep the line's fit within tolerance?"""
# Straightness tolerances grow a little with length: a 50-px line with a 1-px
# wiggle looks straight, a 5-px one does not (D15).
_tol(r::Retina, len) = r.P[:retina_line_tol] + r.P[:retina_line_tol_per_px] * len
_rmsmax(r::Retina, base::Symbol, len) = r.P[base] + r.P[:retina_line_rms_per_px] * len

function _accepts(r::Retina, l::LineDet, p::Pt)
    len = l.tmax - l.tmin
    abs(perp(p, l.c, l.d)) <= _tol(r, len) || return false
    t = along(p, l.c, l.d)
    g = r.P[:retina_line_gap]
    l.tmin - g <= t <= l.tmax + g || return false
    f = copy(l.fit)
    push!(f, p)
    _, _, rms = linefit(f)
    return rms <= _rmsmax(r, :retina_line_rms, len)
end

function _add_point!(r::Retina, l::LineDet, p::Pt)
    push!(l.fit, p)
    push!(l.pts, p)
    boost!(l.act, r.now)
    refit!(l)
end

"""Process D on one queued point."""
function process_D!(r::Retina)
    isempty(r.dq) && return 0
    k = rand(r.rng, 1:length(r.dq))
    li, src = r.dq[k]
    r.dq[k] = r.dq[end]
    pop!(r.dq)
    p = pixpt(r, li)
    root = uf_find(r, li)
    best, bestd = 0, Inf
    for l in r.lines
        (l.alive && l.src == src) || continue
        uf_find(r, l.anchor) == root || continue
        d = abs(perp(p, l.c, l.d))
        if d < bestd && _accepts(r, l, p)
            best, bestd = l.id, d
        end
    end
    if best != 0
        _add_point!(r, r.lines[best], p)
        return 1
    end
    # no detector wants it: try to start one with two loose neighbours
    near = _loose_near(r, p, r.P[:retina_seed_radius], src, root)
    if length(near) >= 2
        sort!(near; by=i -> dist(p, r.loose[i][1]))
        for i in 1:length(near)-1, j in i+1:length(near)
            a, b = r.loose[near[i]][1], r.loose[near[j]][1]
            f = LineFit(); push!(f, p); push!(f, a); push!(f, b)
            _, _, rms = linefit(f)
            span = max(dist(p, a), dist(p, b), dist(a, b))
            if rms <= r.P[:retina_seed_rms] && span >= 2.0
                r.loose_alive[near[i]] = false
                r.loose_alive[near[j]] = false
                l = _new_line!(r, [p, a, b], li, src)
                # let it pick up any other loose points already in its path
                for q in _loose_near(r, p, 2 * r.P[:retina_seed_radius], src, root)
                    if _accepts(r, l, r.loose[q][1])
                        r.loose_alive[q] = false
                        _add_point!(r, l, r.loose[q][1])
                    end
                end
                return 1
            end
        end
    end
    _loose_add!(r, p, li, src)
    return 1
end

# --- process H ------------------------------------------------------------------

"""Gap along the line between two detectors' extents (negative if they overlap)."""
function _gap(a::LineDet, b::LineDet)
    t1, t2 = along(b.p1, a.c, a.d), along(b.p2, a.c, a.d)
    lo, hi = min(t1, t2), max(t1, t2)
    return max(lo - a.tmax, a.tmin - hi)
end

function _merge_ok(r::Retina, a::LineDet, b::LineDet)
    (a.alive && b.alive && a.src == b.src && a.comp == b.comp) || return false
    line_angle(a.d, b.d) <= r.P[:retina_merge_angle] || return false
    long, short = linelength(a) >= linelength(b) ? (a, b) : (b, a)
    tol = r.P[:retina_merge_offset] + r.P[:retina_line_tol_per_px] * linelength(long)
    (abs(perp(short.p1, long.c, long.d)) <= tol && abs(perp(short.p2, long.c, long.d)) <= tol) || return false
    g = _gap(long, short)
    if g > r.P[:retina_merge_gap]
        # a longer gap is bridged if ink runs across it — typically where
        # another line crosses and took the points in between (D13)
        g <= r.P[:retina_merge_bridge] || return false
        ends = [(dist(p, q), p, q) for p in (long.p1, long.p2), q in (short.p1, short.p2)]
        _, p, q = minimum(ends)
        _inked(r, p, q) >= 0.9 || return false
    end
    f = copy(a.fit); merge!(f, b.fit)
    _, _, rms = linefit(f)
    return rms <= _rmsmax(r, :retina_merge_rms, linelength(a) + linelength(b))
end

"""
Process H (§10.3.9): unify detectors that describe the same line, drop
those that never gathered support, and give every point to the detector it
fits best. The last step — a single reassignment pass — is our addition:
early detectors are born from whichever points happened to arrive first, and
one pass lets the survivors claim the points they should own (D13).
"""
function process_H!(r::Retina)
    minpts = Int(r.P[:retina_min_line_points])
    minlen = r.P[:retina_min_line_length]
    pool = Pt[]
    for l in r.lines
        l.alive || continue
        if length(l.pts) < minpts || linelength(l) < minlen
            l.alive = false
            append!(pool, l.pts)
        end
    end
    merged = true
    while merged
        merged = false
        alive = [l for l in r.lines if l.alive]
        for i in 1:length(alive), j in i+1:length(alive)
            a, b = alive[i], alive[j]
            if _merge_ok(r, a, b)
                merge!(a.fit, b.fit)
                append!(a.pts, b.pts)
                refit!(a)
                b.alive = false
                merged = true
                trace(r.tracer, 3, r.now, "H merge", a.id, b.id)
                break
            end
        end
    end
    # Dissolve short detectors whose points other lines already explain:
    # fragments left at corners or along a side by early, unlucky hypotheses.
    gap = r.P[:retina_line_gap]
    alive = [l for l in r.lines if l.alive]
    sort!(alive; by=linelength)
    for l in alive
        linelength(l) <= r.P[:retina_fragment_length] || continue
        others = [m for m in alive if m.alive && m.id != l.id && m.comp == l.comp &&
                                      m.src == l.src && linelength(m) > linelength(l)]
        isempty(others) && continue
        covered = count(p -> any(m -> abs(perp(p, m.c, m.d)) <= 1.5 * _tol(r, m.tmax - m.tmin) &&
                                      m.tmin - gap <= along(p, m.c, m.d) <= m.tmax + gap, others), l.pts)
        if covered >= 0.8 * length(l.pts)
            l.alive = false
            trace(r.tracer, 3, r.now, "H dissolve", l.id)
        end
    end
    # reassign every point to its best line
    alive = [l for l in r.lines if l.alive]
    allpts = Tuple{Pt,Symbol,Int}[]
    for l in alive, p in l.pts
        push!(allpts, (p, l.src, l.comp))
    end
    for l in alive
        l.fit = LineFit(); empty!(l.pts)
    end
    for (p, src, comp) in allpts
        best, bestd = nothing, Inf
        for l in alive
            (l.src == src && l.comp == comp) || continue
            d = abs(perp(p, l.c, l.d))
            t = along(p, l.c, l.d)
            (d <= _tol(r, l.tmax - l.tmin) && l.tmin - gap <= t <= l.tmax + gap) || continue
            d < bestd && (best = l; bestd = d)
        end
        best === nothing && continue
        push!(best.fit, p); push!(best.pts, p)
    end
    for l in alive
        if length(l.pts) < minpts
            l.alive = false
        else
            refit!(l)
            linelength(l) < minlen && (l.alive = false)
        end
    end
end

"""
A measure of how much a detector's points bow away from its straight line:
fit perpendicular offset as a quadratic in position along the line and
return the predicted offset of the ends relative to the middle (in pixels,
signed). Straight sides give ≈ 0; chords of a curve give a consistent bow
(process G uses this).
"""
function bow(l::LineDet)
    n = length(l.pts)
    n < 6 && return 0.0
    tm = (l.tmin + l.tmax) / 2
    S = zeros(3, 3); v = zeros(3)
    for p in l.pts
        t = along(p, l.c, l.d) - tm
        e = perp(p, l.c, l.d)
        row = (1.0, t, t * t)
        for i in 1:3
            v[i] += row[i] * e
            for j in 1:3
                S[i, j] += row[i] * row[j]
            end
        end
    end
    c = try
        S \ v
    catch
        return 0.0
    end
    half = (l.tmax - l.tmin) / 2
    return c[3] * half^2
end
