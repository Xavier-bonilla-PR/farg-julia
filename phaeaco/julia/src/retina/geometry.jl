# Geometry for the retinal level: line fitting, intersections, convex hulls,
# conic and circle fits (Appendix B), and cubic splines (Appendix B §1).
#
# Points are (x, y) in box coordinates, y down (D6).

const Pt = NTuple{2,Float64}

# --- Lines -------------------------------------------------------------------

"""
Running sums for an orthogonal least-squares line fit. The thesis fits lines
"by the method of least squares" (§10.3.4); we minimise perpendicular rather
than vertical distance so vertical lines need no special case (DECISIONS D9).
"""
mutable struct LineFit
    n::Int
    sx::Float64
    sy::Float64
    sxx::Float64
    sxy::Float64
    syy::Float64
end
LineFit() = LineFit(0, 0.0, 0.0, 0.0, 0.0, 0.0)

function Base.push!(f::LineFit, p::Pt)
    x, y = p
    f.n += 1
    f.sx += x; f.sy += y
    f.sxx += x * x; f.sxy += x * y; f.syy += y * y
    return f
end

function Base.merge!(f::LineFit, g::LineFit)
    f.n += g.n
    f.sx += g.sx; f.sy += g.sy
    f.sxx += g.sxx; f.sxy += g.sxy; f.syy += g.syy
    return f
end

Base.copy(f::LineFit) = LineFit(f.n, f.sx, f.sy, f.sxx, f.sxy, f.syy)

"""
(centre, unit direction, rms perpendicular residual) of the fitted line.
The direction is the principal eigenvector of the scatter matrix; the
residual is the square root of the smaller eigenvalue.
"""
function linefit(f::LineFit)
    n = f.n
    cx, cy = f.sx / n, f.sy / n
    a = f.sxx / n - cx^2
    b = f.sxy / n - cx * cy
    c = f.syy / n - cy^2
    tr, det = a + c, a * c - b * b
    disc = sqrt(max(tr^2 / 4 - det, 0.0))
    l1, l2 = tr / 2 + disc, max(tr / 2 - disc, 0.0)
    if abs(b) > 1e-12
        dx, dy = l1 - c, b
    else
        dx, dy = a >= c ? (1.0, 0.0) : (0.0, 1.0)
    end
    L = hypot(dx, dy)
    return (cx, cy), (dx / L, dy / L), sqrt(l2)
end

"""Signed perpendicular distance of `p` from the line through `c` with direction `d`."""
perp(p::Pt, c::Pt, d::Pt) = (p[1] - c[1]) * (-d[2]) + (p[2] - c[2]) * d[1]
"""Position of `p` along the line through `c` with direction `d`."""
along(p::Pt, c::Pt, d::Pt) = (p[1] - c[1]) * d[1] + (p[2] - c[2]) * d[2]

dist(p::Pt, q::Pt) = hypot(p[1] - q[1], p[2] - q[2])

function segdist(p::Pt, a::Pt, b::Pt)
    dx, dy = b[1] - a[1], b[2] - a[2]
    L2 = dx * dx + dy * dy
    t = L2 == 0 ? 0.0 : clamp(((p[1] - a[1]) * dx + (p[2] - a[2]) * dy) / L2, 0.0, 1.0)
    return hypot(p[1] - a[1] - t * dx, p[2] - a[2] - t * dy)
end

"""Intersection of the infinite lines a1–a2 and b1–b2, or nothing if parallel."""
function line_intersection(a1::Pt, a2::Pt, b1::Pt, b2::Pt)
    d1x, d1y = a2[1] - a1[1], a2[2] - a1[2]
    d2x, d2y = b2[1] - b1[1], b2[2] - b1[2]
    den = d1x * d2y - d1y * d2x
    abs(den) < 1e-9 && return nothing
    t = ((b1[1] - a1[1]) * d2y - (b1[2] - a1[2]) * d2x) / den
    return (a1[1] + t * d1x, a1[2] + t * d1y)
end

"""
Slope of a direction in degrees in [0, 180), measured counter-clockwise from
the x axis with y pointing up (D6).
"""
function slope_deg(d::Pt)
    θ = atand(-d[2], d[1])
    θ < 0 && (θ += 180)
    θ >= 180 && (θ -= 180)
    return θ
end

"""Smallest angle between two undirected lines, in degrees, in [0, 90]."""
function line_angle(d1::Pt, d2::Pt)
    c = abs(d1[1] * d2[1] + d1[2] * d2[2])
    return acosd(clamp(c, 0.0, 1.0))
end

"""Angle at vertex `v` between rays to `p` and `q`, in degrees, in [0, 180]."""
function vertex_angle(v::Pt, p::Pt, q::Pt)
    ax, ay = p[1] - v[1], p[2] - v[2]
    bx, by = q[1] - v[1], q[2] - v[2]
    la, lb = hypot(ax, ay), hypot(bx, by)
    (la == 0 || lb == 0) && return 180.0
    return acosd(clamp((ax * bx + ay * by) / (la * lb), -1.0, 1.0))
end

# --- Convex hull (§10.3.18) --------------------------------------------------

_cross(o::Pt, a::Pt, b::Pt) = (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])

"""
An incrementally built convex hull (§10.3.18, Fig. 10.28): each new point
either falls inside (ignored) or replaces the chain of edges it can see.
Vertices are kept in counter-clockwise order (in the y-down frame, that is
clockwise on screen; only consistency matters).
"""
mutable struct Hull
    v::Vector{Pt}
    pending::Vector{Pt}     # the first points, until three non-collinear ones exist
end
Hull() = Hull(Pt[], Pt[])

function Base.push!(h::Hull, p::Pt)
    if isempty(h.v)
        push!(h.pending, p)
        length(h.pending) >= 3 || return h
        # find a non-degenerate triangle among the pending points
        pts = h.pending
        for i in 3:length(pts)
            a, b, c = pts[1], pts[2], pts[i]
            z = _cross(a, b, c)
            abs(z) < 1e-9 && continue
            h.v = z > 0 ? [a, b, c] : [a, c, b]
            rest = [pts[j] for j in 3:length(pts) if j != i]
            empty!(h.pending)
            foreach(q -> push!(h, q), rest)
            return h
        end
        return h
    end
    v = h.v
    n = length(v)
    visible = [_cross(v[i], v[i%n+1], p) < -1e-9 for i in 1:n]
    any(visible) || return h
    # the visible edges form one contiguous run; replace it with two edges to p
    first_vis = findfirst(i -> visible[i] && !visible[mod1(i - 1, n)], 1:n)
    first_vis === nothing && return h          # numerically all visible; ignore
    k = first_vis
    while visible[mod1(k, n)]
        k += 1
    end
    last_vis = mod1(k - 1, n)
    # keep vertices from end of last visible edge round to start of first
    keep = Pt[]
    i = mod1(last_vis + 1, n)
    while true
        push!(keep, v[i])
        i == first_vis && break
        i = mod1(i + 1, n)
    end
    push!(keep, p)
    h.v = keep
    return h
end

"""All points seen so far, for hulls still degenerate (collinear input)."""
hullpoints(h::Hull) = isempty(h.v) ? h.pending : h.v

function polygon_area(v::AbstractVector{Pt})
    n = length(v)
    n < 3 && return 0.0
    a = 0.0
    for i in 1:n
        a += v[i][1] * v[i%n+1][2] - v[i%n+1][1] * v[i][2]
    end
    return abs(a) / 2
end

function point_in_hull(h::Hull, p::Pt)
    v = h.v
    n = length(v)
    n < 3 && return false
    for i in 1:n
        _cross(v[i], v[i%n+1], p) < -1e-9 && return false
    end
    return true
end

# --- Conics and circles (Appendix B §2–3) -------------------------------------

"""
Least-squares conic ax² + 2bxy + cy² + 2dx + 2fy + 1 = 0 through the points
(Appendix B, eq. 13), after moving the origin to the points' centroid so the
"+1" normalisation is safe. Returns `nothing` for fewer than six points.

The result: centre, semi-axes (major ≥ minor), rotation, eccentricity
(eq. 19), whether it is an ellipse at all (ac − b² > 0), and the rms of the
approximate geometric distance |F| / |∇F| of the points from the curve.
"""
function fit_conic(pts::AbstractVector{Pt})
    n = length(pts)
    n < 6 && return nothing
    mx = sum(first, pts) / n
    my = sum(last, pts) / n
    s = max(1.0, sqrt(sum(((p[1] - mx)^2 + (p[2] - my)^2) for p in pts) / n))
    A = zeros(n, 5)
    for (i, p) in enumerate(pts)
        x, y = (p[1] - mx) / s, (p[2] - my) / s
        A[i, :] = [x * x, 2x * y, y * y, 2x, 2y]
    end
    coef = try
        A \ (-ones(n))
    catch
        return nothing
    end
    a, b, c, d, f = coef
    isellipse = a * c - b * b > 0
    # residual: |F| / |∇F| in scaled coordinates, then back to pixels
    r2 = 0.0
    for p in pts
        x, y = (p[1] - mx) / s, (p[2] - my) / s
        F = a * x * x + 2b * x * y + c * y * y + 2d * x + 2f * y + 1
        gx, gy = 2a * x + 2b * y + 2d, 2b * x + 2c * y + 2f
        g = hypot(gx, gy)
        r2 += g > 1e-12 ? (F / g)^2 : 1.0
    end
    rms = sqrt(r2 / n) * s
    isellipse || return (ellipse=false, rms=rms, centre=(mx, my), axes=(0.0, 0.0), theta=0.0, ecc=1.0)
    # centre: solve the gradient = 0 system
    M = [a b; b c]
    ctr = M \ [-d, -f]
    x0, y0 = ctr
    k = -(a * x0^2 + 2b * x0 * y0 + c * y0^2 + 2d * x0 + 2f * y0 + 1)
    # rotation (eq. 15) and the rotated coefficients (eqs. 16–18)
    θ = 0.5 * atan(2b, a - c)
    ct, st = cos(θ), sin(θ)
    a′ = a * ct^2 + 2b * ct * st + c * st^2
    c′ = a * st^2 - 2b * ct * st + c * ct^2
    (k / a′ <= 0 || k / c′ <= 0) && return (ellipse=false, rms=rms, centre=(mx, my), axes=(0.0, 0.0), theta=0.0, ecc=1.0)
    ax1, ax2 = sqrt(k / a′) * s, sqrt(k / c′) * s
    major, minor = max(ax1, ax2), min(ax1, ax2)
    ecc = sqrt(max(0.0, 1 - (minor / major)^2))      # eq. 19
    rot = ax1 >= ax2 ? θ : θ + π / 2
    return (ellipse=true, rms=rms, centre=(mx + x0 * s, my + y0 * s), axes=(major, minor),
            theta=-rot, ecc=ecc)                   # theta reported with y up
end

"""Circumcentre of three points (Appendix B §3), or nothing if collinear."""
function circumcentre(a::Pt, b::Pt, c::Pt)
    d = 2 * (a[1] * (b[2] - c[2]) + b[1] * (c[2] - a[2]) + c[1] * (a[2] - b[2]))
    abs(d) < 1e-9 && return nothing
    a2, b2, c2 = a[1]^2 + a[2]^2, b[1]^2 + b[2]^2, c[1]^2 + c[2]^2
    ux = (a2 * (b[2] - c[2]) + b2 * (c[2] - a[2]) + c2 * (a[2] - b[2])) / d
    uy = (a2 * (c[1] - b[1]) + b2 * (a[1] - c[1]) + c2 * (b[1] - a[1])) / d
    return (ux, uy)
end

# --- Parametric cubic splines (Appendix B §1) ---------------------------------

"""
The natural parametric cubic spline through P0 … Pn: piece i is
S_i(t) = [a3 t³ + a2 t² + a1 t + a0, b3 t³ + …], 0 ≤ t ≤ 1, with matching
first and second derivatives at the joints and zero second derivative at
both ends. Solved by the tridiagonal system of eq. 10. Returns a vector of
pieces, each `(ax::NTuple{4}, bx::NTuple{4})` holding (a0, a1, a2, a3).
"""
function cubic_spline(P::AbstractVector{Pt})
    n = length(P) - 1
    n >= 1 || return NTuple{2,NTuple{4,Float64}}[]
    function coeffs(x)
        a2 = zeros(n + 1)
        if n >= 2
            # (n−1)×(n−1) tridiagonal: a2[i−1] + 4 a2[i] + a2[i+1] = 3(x[i−1] − 2x[i] + x[i+1])
            m = n - 1
            dl = ones(m - 1); du = ones(m - 1); dd = fill(4.0, m)
            rhs = [3 * (x[i] - 2x[i+1] + x[i+2]) for i in 1:m]
            a2[2:n] = Tridiagonal(dl, dd, du) \ rhs
        end
        out = NTuple{4,Float64}[]
        for i in 1:n
            a0 = x[i]
            a1 = x[i+1] - x[i] - (2a2[i] + a2[i+1]) / 3      # eq. 9a
            a3 = (a2[i+1] - a2[i]) / 3                         # eq. 7
            push!(out, (a0, a1, a2[i], a3))
        end
        return out
    end
    ax = coeffs(first.(P))
    bx = coeffs(last.(P))
    return [(ax[i], bx[i]) for i in 1:n]
end

_poly(c::NTuple{4,Float64}, t) = c[1] + t * (c[2] + t * (c[3] + t * c[4]))
spline_point(piece, t) = (_poly(piece[1], t), _poly(piece[2], t))
