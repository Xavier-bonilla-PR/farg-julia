# Synthetic boxes and Bongard problems with known contents.
#
# With no reference implementation, these are the ground truth for the
# retina (plan §1, tier 2) and the solver's first problems. Every generator is
# seeded and records what it drew, so a test can ask "did the retina find the
# three sides of the triangle at I-C?".

"""
A drawn shape, as ground truth.

- `:segment`  — `pts` = two endpoints
- `:polyline` — `pts` = vertices, open
- `:polygon`  — `pts` = vertices, closed
- `:ellipse`  — `pts[1]` = centre, `a`, `b` semi-axes, `theta` rotation (radians,
                counter-clockwise with y up)
- `:dot`      — `pts[1]` = centre, `a` = radius
"""
struct Shape
    kind::Symbol
    pts::Vector{NTuple{2,Float64}}
    a::Float64
    b::Float64
    theta::Float64
    filled::Bool
    width::Float64
end

Shape(kind, pts; a=0.0, b=0.0, theta=0.0, filled=false, width=1.6) =
    Shape(kind, [Float64.(p) for p in pts], Float64(a), Float64(b), Float64(theta), filled, Float64(width))

segment(p, q; width=1.6) = Shape(:segment, [p, q]; width=width)
polygon(pts; filled=false, width=1.6) = Shape(:polygon, pts; filled=filled, width=width)
polyline(pts; width=1.6) = Shape(:polyline, pts; width=width)
ellipse(c, a, b, theta=0.0; filled=false, width=1.6) =
    Shape(:ellipse, [c]; a=a, b=b, theta=theta, filled=filled, width=width)
circle(c, r; filled=false, width=1.6) = ellipse(c, r, r; filled=filled, width=width)
dot(c, r=1.5) = Shape(:dot, [c]; a=r, filled=true)

"""Number of straight sides, or 0 for shapes made of curves."""
nsides(s::Shape) = s.kind == :polygon ? length(s.pts) :
                   s.kind == :polyline ? length(s.pts) - 1 :
                   s.kind == :segment ? 1 : 0

function centroid(s::Shape)
    s.kind in (:ellipse, :dot) && return s.pts[1]
    n = length(s.pts)
    return (sum(first, s.pts) / n, sum(last, s.pts) / n)
end

"""Area enclosed by the shape's outline (filled or not), in pixels²."""
function enclosed_area(s::Shape)
    s.kind == :ellipse && return π * s.a * s.b
    s.kind == :dot && return π * s.a^2
    s.kind == :polygon || return 0.0
    a = 0.0
    n = length(s.pts)
    for i in 1:n
        (x1, y1), (x2, y2) = s.pts[i], s.pts[i%n+1]
        a += x1 * y2 - x2 * y1
    end
    return abs(a) / 2
end

"""Is a polygon convex? (Ellipses and dots are.)"""
function isconvex(s::Shape)
    s.kind == :polygon || return s.kind in (:ellipse, :dot)
    n = length(s.pts)
    sgn = 0
    for i in 1:n
        (x1, y1), (x2, y2), (x3, y3) = s.pts[i], s.pts[i%n+1], s.pts[(i+1)%n+1]
        z = (x2 - x1) * (y3 - y2) - (y2 - y1) * (x3 - x2)
        abs(z) < 1e-9 && continue
        sgn == 0 && (sgn = sign(z))
        sign(z) != sgn && return false
    end
    return true
end

# --- Rasterising -------------------------------------------------------------

function _segdist(px, py, x1, y1, x2, y2)
    dx, dy = x2 - x1, y2 - y1
    L2 = dx * dx + dy * dy
    t = L2 == 0 ? 0.0 : clamp(((px - x1) * dx + (py - y1) * dy) / L2, 0.0, 1.0)
    return hypot(px - (x1 + t * dx), py - (y1 + t * dy))
end

function _stroke!(img::BitMatrix, p, q, width)
    h, w = size(img)
    r = max(width / 2, 0.75)       # below 0.75 diagonal strokes break apart
    x1, y1 = p
    x2, y2 = q
    for y in max(1, floor(Int, min(y1, y2) - r)):min(h, ceil(Int, max(y1, y2) + r)),
        x in max(1, floor(Int, min(x1, x2) - r)):min(w, ceil(Int, max(x1, x2) + r))
        _segdist(x, y, x1, y1, x2, y2) <= r && (img[y, x] = true)
    end
end

function _inside_polygon(px, py, pts)
    inside = false
    n = length(pts)
    j = n
    for i in 1:n
        (xi, yi), (xj, yj) = pts[i], pts[j]
        if (yi > py) != (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi
            inside = !inside
        end
        j = i
    end
    return inside
end

"""Points along an ellipse outline, `n` of them."""
function ellipse_points(s::Shape, n::Int=64)
    (cx, cy) = s.pts[1]
    c, si = cos(s.theta), sin(s.theta)
    [(cx + s.a * cos(t) * c - s.b * sin(t) * si,
      cy - (s.a * cos(t) * si + s.b * sin(t) * c)) for t in range(0, 2π; length=n + 1)[1:n]]
end

"""
Make a hand-drawn version of a closed or open vertex list: subdivide each
edge into pieces of about `step` px and push interior points sideways by
N(0, σ). Vertices themselves are jittered by N(0, σv).
"""
function wobble(rng::AbstractRNG, pts, closed::Bool; σ=0.0, σv=0.0, step=6.0)
    σ == 0 && σv == 0 && return pts
    vs = [(x + σv * randn(rng), y + σv * randn(rng)) for (x, y) in pts]
    out = NTuple{2,Float64}[]
    n = length(vs)
    for i in 1:(closed ? n : n - 1)
        (x1, y1), (x2, y2) = vs[i], vs[i%n+1]
        L = hypot(x2 - x1, y2 - y1)
        k = max(1, round(Int, L / step))
        nx, ny = L == 0 ? (0.0, 0.0) : (-(y2 - y1) / L, (x2 - x1) / L)
        for j in 0:k-1
            t = j / k
            e = j == 0 ? 0.0 : σ * randn(rng)
            push!(out, (x1 + t * (x2 - x1) + e * nx, y1 + t * (y2 - y1) + e * ny))
        end
    end
    closed || push!(out, vs[end])
    return out
end

"""Draw a shape into `img`. `σ` > 0 gives a hand-drawn wobble."""
function draw!(img::BitMatrix, s::Shape; rng::AbstractRNG=Random.default_rng(), σ=0.0)
    h, w = size(img)
    if s.kind == :dot
        (cx, cy) = s.pts[1]
        for y in max(1, floor(Int, cy - s.a)):min(h, ceil(Int, cy + s.a)),
            x in max(1, floor(Int, cx - s.a)):min(w, ceil(Int, cx + s.a))
            hypot(x - cx, y - cy) <= s.a && (img[y, x] = true)
        end
        return img
    end
    if s.kind == :ellipse
        outline = ellipse_points(s, max(24, round(Int, π * (s.a + s.b) / 3)))
        closed = true
    else
        outline = s.pts
        closed = s.kind == :polygon
    end
    pts = wobble(rng, outline, closed; σ=σ, σv=σ / 2, step=s.kind == :ellipse ? 1e9 : 6.0)
    if s.filled && closed
        xs, ys = first.(pts), last.(pts)
        for y in max(1, floor(Int, minimum(ys))):min(h, ceil(Int, maximum(ys))),
            x in max(1, floor(Int, minimum(xs))):min(w, ceil(Int, maximum(xs)))
            _inside_polygon(x, y, pts) && (img[y, x] = true)
        end
    end
    n = length(pts)
    for i in 1:(closed ? n : n - 1)
        _stroke!(img, pts[i], pts[i%n+1], s.width)
    end
    return img
end

function render(shapes::Vector{Shape}; rng::AbstractRNG=Random.default_rng(), σ=0.0)
    img = falses(BOXSIZE, BOXSIZE)
    for s in shapes
        draw!(img, s; rng=rng, σ=σ)
    end
    return img
end

# --- Random shapes -----------------------------------------------------------

_rot(x, y, t) = (x * cos(t) + y * sin(t), -x * sin(t) + y * cos(t))   # y-down frame

"""A polygon with `n` vertices around `c`, radius `r`, irregular by `irreg`."""
function random_polygon(rng, n, c, r; irreg=0.25, filled=false, width=1.6)
    t0 = 2π * rand(rng)
    pts = NTuple{2,Float64}[]
    # Keep angles well apart so no vertex is nearly flat (it would read as a side).
    base = sort([2π * (k - 1) / n + (rand(rng) - 0.5) * irreg * 2π / n for k in 1:n])
    for (k, θ) in enumerate(base)
        rr = r * (1 - irreg / 2 + irreg * rand(rng))
        dx, dy = _rot(rr, 0.0, t0 + θ)
        push!(pts, (c[1] + dx, c[2] + dy))
    end
    return polygon(pts; filled=filled, width=width)
end

"""A concave polygon: a star-ish, notched or L-like outline around `c`."""
function random_concave(rng, c, r; filled=false, width=1.6)
    kind = rand(rng, 1:3)
    t0 = 2π * rand(rng)
    if kind == 1                               # star / arrowhead
        n = rand(rng, 3:5)
        pts = NTuple{2,Float64}[]
        for k in 0:2n-1
            rr = iseven(k) ? r : r * (0.35 + 0.2 * rand(rng))
            dx, dy = _rot(rr, 0.0, t0 + π * k / n)
            push!(pts, (c[1] + dx, c[2] + dy))
        end
    elseif kind == 2                           # L shape
        a, b = r * (0.9 + 0.2rand(rng)), r * (0.45 + 0.15rand(rng))
        raw = [(-a, -a), (-a + b, -a), (-a + b, a - b), (a, a - b), (a, a), (-a, a)]
        pts = [(c[1] + dx, c[2] + dy) for (dx, dy) in (_rot(x, y, t0) for (x, y) in raw)]
    else                                       # square with a notch deep enough to see
        a, d = r * 0.8, r * (0.65 + 0.25rand(rng))
        raw = [(-a, -a), (-d / 2, -a), (0.0, -a + d), (d / 2, -a), (a, -a), (a, a), (-a, a)]
        pts = [(c[1] + dx, c[2] + dy) for (dx, dy) in (_rot(x, y, t0) for (x, y) in raw)]
    end
    return polygon(pts; filled=filled, width=width)
end

"""Bounding radius used for non-overlapping placement."""
function radius(s::Shape)
    c = centroid(s)
    s.kind == :ellipse && return max(s.a, s.b) + s.width
    s.kind == :dot && return s.a + 1
    return maximum(hypot(p[1] - c[1], p[2] - c[2]) for p in s.pts) + s.width
end

"""
Place shapes made by `makers` (each `(rng, centre) -> Shape`) at random
non-overlapping positions inside the box. Retries a few hundred times; errors
rather than silently drawing overlaps.
"""
function place(rng, makers; margin=6.0, gap=6.0, region=(1.0, BOXSIZE, 1.0, BOXSIZE))
    shapes = Shape[]
    x0, x1, y0, y1 = region
    for mk in makers
        ok = false
        for _ in 1:400
            c = (x0 + margin + rand(rng) * (x1 - x0 - 2margin),
                 y0 + margin + rand(rng) * (y1 - y0 - 2margin))
            s = mk(rng, c)
            r = radius(s)
            sc = centroid(s)
            inbox = all(margin <= p[1] <= BOXSIZE - margin && margin <= p[2] <= BOXSIZE - margin
                        for p in (s.kind in (:ellipse, :dot) ? [(sc[1] - r, sc[2] - r), (sc[1] + r, sc[2] + r)] : s.pts))
            inbox || continue
            clear = all(hypot(sc[1] - centroid(o)[1], sc[2] - centroid(o)[2]) > r + radius(o) + gap for o in shapes)
            clear || continue
            push!(shapes, s)
            ok = true
            break
        end
        ok || error("could not place shape")
    end
    return shapes
end
