# Retinal detectors (§10.3). Every element found at the retinal level is a
# *detector*: a suggestion to the cognitive level about what might be there,
# carrying the numbers the cognitive level is never allowed to see (§7.1).

"""A line-segment detector (process D)."""
mutable struct LineDet
    id::Int
    src::Symbol             # :endo (skeleton of a thin stroke) or :exo (border of a filled region)
    anchor::Int             # a pixel (linear index) of its component, resolved to a root later
    fit::LineFit
    pts::Vector{Pt}
    act::Activation
    c::Pt                   # fitted line: a point and a unit direction
    d::Pt
    rms::Float64
    tmin::Float64           # extent along d, relative to c
    tmax::Float64
    p1::Pt                  # endpoints (moved onto vertices by process E)
    p2::Pt
    alive::Bool
    comp::Int               # component id, set at settle time
end

function refit!(l::LineDet)
    l.c, l.d, l.rms = linefit(l.fit)
    tmin, tmax = Inf, -Inf
    for p in l.pts
        t = along(p, l.c, l.d)
        tmin = min(tmin, t); tmax = max(tmax, t)
    end
    l.tmin, l.tmax = tmin, tmax
    l.p1 = (l.c[1] + tmin * l.d[1], l.c[2] + tmin * l.d[2])
    l.p2 = (l.c[1] + tmax * l.d[1], l.c[2] + tmax * l.d[2])
    return l
end

linelength(l::LineDet) = dist(l.p1, l.p2)
endpoint(l::LineDet, e::Int) = e == 1 ? l.p1 : l.p2
midpoint(l::LineDet) = ((l.p1[1] + l.p2[1]) / 2, (l.p1[2] + l.p2[2]) / 2)

"""Where lines meet (processes E and K): a vertex, touch, cross, or K-point (§7.4.2)."""
mutable struct Junction
    id::Int
    kind::Symbol            # :V, :T, :X, :K
    p::Pt
    lines::Vector{Int}      # line ids
    ends::Vector{Int}       # for each line: 1 or 2 if it meets here with that end, 0 if through its interior
    comp::Int
end

"""A line string (process M): lines joined end to end (§7.4.4)."""
struct LineString
    id::Int
    lines::Vector{Int}      # in order
    flip::Vector{Bool}      # traverse line i from p2 to p1?
    closed::Bool
    comp::Int
end

"""A curve (process G), represented by a parametric cubic spline (§10.3.8)."""
struct CurveDet
    id::Int
    lines::Vector{Int}
    knots::Vector{Pt}       # the points the spline passes through
    spline::Vector{NTuple{2,NTuple{4,Float64}}}
    closed::Bool
    comp::Int
end

"""An ellipse or circle (process O, Appendix B §2)."""
struct EllipseDet
    id::Int
    centre::Pt
    axes::NTuple{2,Float64}     # semi-major, semi-minor
    theta::Float64              # orientation of the major axis, radians, y up
    ecc::Float64
    circle::Bool
    rms::Float64
    lines::Vector{Int}
    comp::Int
end

"""A dot (process i): too small to be given a shape (§7.4.1)."""
struct DotDet
    id::Int
    centre::Pt
    size::Int                   # pixels
    comp::Int
end

"""A closed background region enclosed by one object (process O, §7.4.7)."""
struct Hole
    area::Int
    pixels::Vector{Int}
end

"""
A connected group of foreground pixels — the retinal level's "object"
(§10.3.1 footnote 75) — with the measurements codelets may later ask for.
"""
mutable struct RetObject
    id::Int
    pixels::Vector{Int}
    bbox::NTuple{4,Int}             # xmin, xmax, ymin, ymax
    ink::Int
    holes::Vector{Hole}
    area::Float64                   # silhouette: ink plus enclosed holes
    hull::Hull
    hull_area::Float64
    barycenter::Pt
    texture::Float64                # fraction of ink that is "thick" (0 outlined … 1 filled)
    filled::Bool
    elongation::Float64             # 0 round … 1 a line
    axis_deg::Float64               # direction of the principal axis, degrees, y up
    missing::Float64                # (hull − silhouette) / hull: "missing quantity" (§7.4.6)
    openness::Float64               # of concavities: 0 closed … 1 wide open (§7.4.7)
    isdot::Bool
    zoomed::Bool
    lines::Vector{Int}
    junctions::Vector{Int}
    strings::Vector{Int}
    curves::Vector{Int}
    ellipses::Vector{Int}
    endoskeleton::Vector{Int}       # skeleton pixels of the thick parts (§7.4.9)
end

"""`(a, b, strength)`: object a is inside object b, to degree `strength` (§7.4.7)."""
const Inside = Tuple{Int,Int,Float64}
