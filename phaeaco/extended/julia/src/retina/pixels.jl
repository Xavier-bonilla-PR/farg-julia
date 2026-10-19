# The retina's state and its pixel-level processes: A (random sampling),
# B (altitude), C (skeleton), F (borders of filled regions) — §10.3.1–10.3.6.

mutable struct Retina
    img::BitMatrix
    h::Int
    w::Int
    P::Params
    rng::Xoshiro
    tracer::Tracer
    now::Int
    nozoom::Bool                # a zoomed sub-retina must not zoom again
    scale::Float64              # pixels of this retina per box pixel (2 inside a zoom)
    # process A
    perm::Vector{Int}
    ppos::Int
    hitrate::Float64
    a_done::Bool
    seen::BitMatrix
    # process B / C
    bq::Vector{Int}
    alt::Matrix{Int}            # altitude; -1 = not computed
    depth::Matrix{Int}          # ring at which B stopped (≈ half stroke width + 1)
    uf::Vector{Int}             # union-find parent over linear indices; 0 = not a seen pixel
    thick::Vector{Int}          # skeleton pixels in thick regions (endoskeleton)
    # process F
    fq::Vector{Int}
    sourced::Vector{Int}        # pixels already used as F sources
    sources_checked::Bool
    border_seen::BitMatrix
    # process D
    dq::Vector{Tuple{Int,Symbol}}
    lines::Vector{LineDet}
    loose::Vector{Tuple{Pt,Int,Symbol}}     # unassigned points: point, pixel, source
    loose_alive::BitVector
    grid::Dict{Int,Vector{Int}}             # cell → indices into `loose`
    # results of the settle stage
    junctions::Vector{Junction}
    strings::Vector{LineString}
    curves::Vector{CurveDet}
    ellipses::Vector{EllipseDet}
    dots::Vector{DotDet}
    objects::Vector{RetObject}
    insides::Vector{Inside}
    comp_of::Dict{Int,Int}                  # union-find root → object id
    settled::Bool
    stage::Int                              # progress through the settle stage
end

function Retina(img::AbstractMatrix{Bool}, P::Params, rng::Xoshiro;
                tracer::Tracer=Tracer(), nozoom::Bool=false, scale::Float64=1.0)
    h, w = size(img)
    Retina(BitMatrix(img), h, w, P, rng, tracer, 0, nozoom, scale,
           randperm(rng, h * w), 0, 1.0, false, falses(h, w),
           Int[], fill(-1, h, w), zeros(Int, h, w), zeros(Int, h * w), Int[],
           Int[], Int[], false, falses(h, w),
           Tuple{Int,Symbol}[], LineDet[], Tuple{Pt,Int,Symbol}[], BitVector(), Dict{Int,Vector{Int}}(),
           Junction[], LineString[], CurveDet[], EllipseDet[], DotDet[], RetObject[], Inside[],
           Dict{Int,Int}(), false, 0)
end

@inline _xy(r::Retina, li::Int) = ((li - 1) ÷ r.h + 1, (li - 1) % r.h + 1)   # (x, y); column-major
@inline _li(r::Retina, x::Int, y::Int) = (x - 1) * r.h + y
@inline _inb(r::Retina, x::Int, y::Int) = 1 <= x <= r.w && 1 <= y <= r.h
@inline _ink(r::Retina, x::Int, y::Int) = _inb(r, x, y) && r.img[y, x]
pixpt(r::Retina, li::Int) = (x = _xy(r, li); (Float64(x[1]), Float64(x[2])))

const N8 = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))
const N4 = ((0, -1), (-1, 0), (1, 0), (0, 1))

# --- union-find over pixels ---------------------------------------------------

function uf_find(r::Retina, i::Int)
    p = r.uf[i]
    p == 0 && return 0
    while r.uf[i] != i
        r.uf[i] = r.uf[r.uf[i]]
        i = r.uf[i]
    end
    return i
end

function uf_union(r::Retina, a::Int, b::Int)
    ra, rb = uf_find(r, a), uf_find(r, b)
    (ra == 0 || rb == 0 || ra == rb) && return
    r.uf[max(ra, rb)] = min(ra, rb)
end

# --- process A ------------------------------------------------------------------

"""
Sample pixels at random locations (§10.3.1). We visit a random permutation
rather than sampling with replacement, so a figure of four or more pixels is
practically never missed, while the visiting order stays random (D11). A
self-regulates: it tracks its rate of new hits and retires once the rate has
fallen low and most of the box has been looked at, so an isolated pixel can
occasionally go unseen, as in the thesis.
"""
function process_A!(r::Retina)
    n = Int(r.P[:retina_a_batch])
    hits = 0
    for _ in 1:n
        r.ppos += 1
        if r.ppos > length(r.perm)
            r.a_done = true
            break
        end
        li = r.perm[r.ppos]
        x, y = _xy(r, li)
        if r.img[y, x] && !r.seen[y, x]
            r.seen[y, x] = true
            r.uf[li] = li
            push!(r.bq, li)
            hits += 1
        end
    end
    r.hitrate = 0.9 * r.hitrate + 0.1 * hits / n
    if r.ppos >= r.P[:retina_a_stop_fraction] * length(r.perm) && r.hitrate < r.P[:retina_a_stop_rate]
        r.a_done = true
    end
    return n
end

# --- process B ------------------------------------------------------------------

"""
Altitude of a pixel (§10.3.2): count foreground pixels on concentric squares
around it, stopping after the first square that contains a background pixel.
Also records the square at which it stopped, a measure of local stroke
half-width that the later processes use (D12).
"""
function altitude!(r::Retina, x::Int, y::Int)
    a = r.alt[y, x]
    a >= 0 && return a
    total = 0
    k = 0
    while true
        k += 1
        cnt = 0
        white = false
        for dx in -k:k, dy in (-k, k)
            _ink(r, x + dx, y + dy) ? (cnt += 1) : (white = true)
        end
        for dy in -k+1:k-1, dx in (-k, k)
            _ink(r, x + dx, y + dy) ? (cnt += 1) : (white = true)
        end
        total += cnt
        white && break
    end
    r.alt[y, x] = total
    r.depth[y, x] = k
    return total
end

"""
Process B on one pixel from A's queue: its altitude; joining it to the seen
neighbours of its object; and asking A to look at its neighbours next
(§10.3.2: "B helps A to concentrate on non-0 pixels"). Then process C.
"""
function process_B!(r::Retina)
    isempty(r.bq) && return 0
    k = rand(r.rng, 1:length(r.bq))
    li = r.bq[k]
    r.bq[k] = r.bq[end]
    pop!(r.bq)
    x, y = _xy(r, li)
    altitude!(r, x, y)
    for (dx, dy) in N8
        nx, ny = x + dx, y + dy
        _ink(r, nx, ny) || continue
        nli = _li(r, nx, ny)
        if !r.seen[ny, nx]
            r.seen[ny, nx] = true
            r.uf[nli] = nli
            push!(r.bq, nli)
        end
        uf_union(r, li, nli)
    end
    process_C!(r, li, x, y)
    return 1
end

# --- process C ------------------------------------------------------------------

"""
Is the pixel on the endoskeleton (§10.3.3)? Yes if no more than two of its
eight neighbours are strictly taller. Skeleton pixels of thin strokes go to
process D; those of thick regions are the endoskeleton proper, and a few of
them become sources for process F.
"""
function process_C!(r::Retina, li::Int, x::Int, y::Int)
    a = r.alt[y, x]
    taller = 0
    for (dx, dy) in N8
        _ink(r, x + dx, y + dy) || continue
        altitude!(r, x + dx, y + dy) > a && (taller += 1)
    end
    taller > 2 && return
    if r.depth[y, x] >= r.P[:retina_thick_depth]
        push!(r.thick, li)
        rand(r.rng) < r.P[:retina_f_source_prob] && push!(r.fq, li)
    else
        push!(r.dq, (li, :endo))
    end
end

# --- process F ------------------------------------------------------------------

_isborder(r::Retina, x::Int, y::Int) =
    _ink(r, x, y) && any(!_ink(r, x + dx, y + dy) for (dx, dy) in N4)

"""
Borders of filled regions (§10.3.6). From a source pixel deep inside a thick
region, send 16 rays; where each leaves the region is a border pixel. From
each border pixel found we also follow the border to its neighbours, so the
exoskeleton comes out whole rather than as 16 isolated points (D10). Border
pixels go to process D as `:exo` points.
"""
function process_F!(r::Retina)
    isempty(r.fq) && return 0
    li = pop!(r.fq)
    push!(r.sourced, li)
    x0, y0 = _xy(r, li)
    walk = Int[]
    for k in 0:15
        θ = 2π * k / 16
        dx, dy = cos(θ), sin(θ)
        lastx, lasty = x0, y0
        for s in 1:200
            x, y = round(Int, x0 + s * dx), round(Int, y0 + s * dy)
            _ink(r, x, y) || break
            lastx, lasty = x, y
        end
        _isborder(r, lastx, lasty) && push!(walk, _li(r, lastx, lasty))
    end
    # follow borders, staying near the thick region (thin attachments have their own skeleton)
    reach = Int(r.P[:retina_thick_depth])
    while !isempty(walk)
        b = pop!(walk)
        x, y = _xy(r, b)
        r.border_seen[y, x] && continue
        r.border_seen[y, x] = true
        push!(r.dq, (b, :exo))
        for (dx, dy) in N8
            nx, ny = x + dx, y + dy
            (_inb(r, nx, ny) && !r.border_seen[ny, nx] && _isborder(r, nx, ny)) || continue
            _near_thick(r, nx, ny, reach) && push!(walk, _li(r, nx, ny))
        end
    end
    return 1
end

function _near_thick(r::Retina, x::Int, y::Int, reach::Int)
    for dy in -reach:reach, dx in -reach:reach
        _inb(r, x + dx, y + dy) || continue
        r.img[y+dy, x+dx] && altitude!(r, x + dx, y + dy) >= 0 &&
            r.depth[y+dy, x+dx] >= r.P[:retina_thick_depth] && return true
    end
    return false
end

"""
Every thick region needs at least one source for F, however small its
skeleton (a filled disk's is a handful of pixels). Called once when the
pixel processes fall idle; returns true if it queued more work.
"""
function ensure_sources!(r::Retina)
    r.sources_checked && return false
    r.sources_checked = true
    have = Set(uf_find(r, li) for li in r.sourced)
    for li in r.thick
        root = uf_find(r, li)
        root in have && continue
        push!(have, root)
        push!(r.fq, li)
    end
    return !isempty(r.fq)
end
