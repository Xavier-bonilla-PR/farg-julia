# Core extraction (Foundalis 2013, "Unification of Clustering, Concept
# Formation, Categorization, and Analogy Making", Figs. 6–7): thin a figure
# down to the pixels farthest from its border, its "core pixels", and parse
# them "as lines that intersect and meet each other". The core keeps a
# figure's structure (arms, legs, a torso) and ignores its ink: the figure is
# taken as a silhouette, its holes filled, so an outlined triangle and a
# filled one have the same core. See ../../DECISIONS.md X12.
#
#   ends       free ends of the core (a triangle 3, a square 4, a disk 0)
#   junctions  points where three or more branches meet
#   order      deepest side branch: 0 a simple path, 1 branches off the main
#              path, 2 branches off those (BP #70)
#   neck       thinnest point of a path between two free ends ÷ the thinner
#              of the thickest points on either side of it (1: no neck; BP #18)
#   neckvert   how vertical the path runs through that neck (BP #19)
#   branches   branch lengths ÷ the core's total length, longest first

"""The core of one figure."""
struct FigCore
    ends::Int
    junctions::Int
    order::Int
    neck::Float64
    neckvert::Float64
    branches::Vector{Float64}
end

const POINT_CORE = FigCore(0, 0, 0, 1.0, 0.0, Float64[])

const _RING = ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1))   # N, NE, E, … clockwise

@inline _on(m::BitMatrix, y::Int, x::Int) = 1 <= y <= size(m, 1) && 1 <= x <= size(m, 2) && m[y, x]

"""
Euclidean distance of every foreground pixel to the nearest background
pixel. Figures are at most 100 × 100, so it is computed directly against the
background pixels that touch the figure.
"""
function _distance(m::BitMatrix)
    h, w = size(m)
    edge = [(y, x) for y in 1:h, x in 1:w if !m[y, x] &&
            any(((dx, dy),) -> _on(m, y + dy, x + dx), _RING)]
    D = zeros(h, w)
    for y in 1:h, x in 1:w
        m[y, x] || continue
        d2 = Inf
        for (ey, ex) in edge
            d2 = min(d2, (ey - y)^2 + (ex - x)^2)
        end
        D[y, x] = sqrt(d2)
    end
    return D
end

"""
Is the pixel simple, i.e. can it be removed without splitting the figure or
opening a hole? Yokoi's connectivity number for 8-connected figures.
"""
function _simple(s::BitMatrix, y::Int, x::Int)
    # E, NE, N, NW, W, SW, S, SE: counter-clockwise from east
    q = [!_on(s, y + dy, x + dx) for (dx, dy) in ((1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1))]
    nc = 0
    for k in (1, 3, 5, 7)
        nc += q[k] - q[k] * q[mod1(k + 1, 8)] * q[mod1(k + 2, 8)]
    end
    return nc == 1
end

"""
Thinning (Zhang–Suen's parallel peeling) that never removes a centre of a
maximal disc in a thick part. Those centres are the core pixels proper — "as
far as possible from the border" — and they keep the limbs reaching into the
corners, which plain peeling rounds off. Thin strokes have no such centres
and are simply peeled to their centre line, keeping their ends.
"""
function _thin(m::BitMatrix, D::Matrix{Float64})
    s = copy(m)
    h, w = size(s)
    anchor = falses(h, w)
    for y in 1:h, x in 1:w
        (s[y, x] && D[y, x] >= 2.0) || continue
        anchor[y, x] = all(((dx, dy),) -> !_on(m, y + dy, x + dx) ||
                               D[y+dy, x+dx] - D[y, x] < (dx != 0 && dy != 0 ? sqrt(2.0) : 1.0) - 0.3, _RING)
    end
    nb(y, x) = [_on(s, y + dy, x + dx) for (dx, dy) in _RING]
    changed = true
    while changed
        changed = false
        for pass in 1:2
            del = Tuple{Int,Int}[]
            for y in 1:h, x in 1:w
                (s[y, x] && !anchor[y, x]) || continue
                p = nb(y, x)                          # p[1]=N p[3]=E p[5]=S p[7]=W
                2 <= count(p) <= 6 || continue
                count(i -> !p[i] && p[mod1(i + 1, 8)], 1:8) == 1 || continue
                if pass == 1
                    (p[1] && p[3] && p[5]) && continue
                    (p[3] && p[5] && p[7]) && continue
                else
                    (p[1] && p[3] && p[7]) && continue
                    (p[1] && p[5] && p[7]) && continue
                end
                push!(del, (y, x))
            end
            for (y, x) in del
                s[y, x] = false
            end
            changed |= !isempty(del)
        end
    end
    # anchors may leave the core two pixels wide: remove pixels whose removal
    # neither splits it nor makes a neighbour a new end, thinnest parts first
    for (_, y, x) in sort([(D[y, x], y, x) for y in 1:h, x in 1:w if s[y, x]])
        count(((dx, dy),) -> _on(s, y + dy, x + dx), _RING) >= 2 || continue
        _simple(s, y, x) || continue
        s[y, x] = false
        if any(((dx, dy),) -> _on(s, y + dy, x + dx) &&
                              count(((ex, ey),) -> _on(s, y + dy + ey, x + dx + ex), _RING) <= 1, _RING)
            s[y, x] = true
        end
    end
    return s
end

"""Crossing number: 1 an end, 2 a point on a branch, 3 or more a junction."""
function _crossings(s::BitMatrix, y::Int, x::Int)
    p = [_on(s, y + dy, x + dx) for (dx, dy) in _RING]
    any(p) || return 0
    return count(i -> p[i] != p[mod1(i + 1, 8)], 1:8) ÷ 2
end

"""One branch of the core: the pixels from one node to another, both ends included."""
struct _Branch
    a::Int                      # node ids
    b::Int
    px::Vector{Tuple{Int,Int}}  # (y, x)
    len::Float64
end

_steplen(p, q) = p[1] != q[1] && p[2] != q[2] ? sqrt(2.0) : 1.0

"""
The core's graph: nodes (ends and junctions, adjacent junction pixels merged)
and the branches between them. Returns `(nodeof, kinds, branches)`.
"""
function _graph(s::BitMatrix)
    h, w = size(s)
    nodeof = zeros(Int, h, w)
    kinds = Symbol[]
    for y in 1:h, x in 1:w
        s[y, x] || continue
        c = _crossings(s, y, x)
        c == 2 && continue
        # a node pixel: join it to a neighbouring node pixel's node if there is one
        id = 0
        for (dx, dy) in _RING
            _on(s, y + dy, x + dx) && nodeof[y+dy, x+dx] > 0 && (id = nodeof[y+dy, x+dx]; break)
        end
        if id == 0
            push!(kinds, c <= 1 ? :end : :junction)
            id = length(kinds)
        elseif c >= 3
            kinds[id] = :junction
        end
        nodeof[y, x] = id
    end
    seen = falses(h, w)
    branches = _Branch[]
    for y in 1:h, x in 1:w
        nodeof[y, x] > 0 || continue
        for (dx, dy) in _RING
            yy, xx = y + dy, x + dx
            (_on(s, yy, xx) && nodeof[yy, xx] == 0 && !seen[yy, xx]) || continue
            px = [(y, x), (yy, xx)]
            seen[yy, xx] = true
            stop = 0
            while stop == 0
                cy, cx = px[end]
                nxt = nothing
                # a neighbouring node ends the branch; else continue to an unseen pixel, 4-neighbours first
                for (ex, ey) in _RING
                    ny, nx = cy + ey, cx + ex
                    _on(s, ny, nx) && nodeof[ny, nx] > 0 && (ny, nx) != px[1] && (nxt = (ny, nx); break)
                end
                if nxt !== nothing
                    push!(px, nxt); stop = nodeof[nxt...]
                    break
                end
                for (ex, ey) in ((0, -1), (1, 0), (0, 1), (-1, 0), (1, -1), (1, 1), (-1, 1), (-1, -1))
                    ny, nx = cy + ey, cx + ex
                    (_on(s, ny, nx) && !seen[ny, nx] && nodeof[ny, nx] == 0) || continue
                    nxt = (ny, nx); break
                end
                nxt === nothing && break                # a loop without nodes, or noise
                seen[nxt...] = true
                push!(px, nxt)
            end
            stop == 0 && continue
            len = sum(_steplen(px[i], px[i+1]) for i in 1:length(px)-1)
            push!(branches, _Branch(nodeof[y, x], stop, px, len))
        end
    end
    return nodeof, kinds, branches
end

"""
Prune spurs. A branch from a free end to a junction that reaches no farther
than the border it runs into is a bump of the border, not a limb: its
extension, length − (thickness at the junction − thickness at the end), is
about zero. A polygon's corner extends `(1/sin(θ/2) − 1)` times the
inscribed radius (a triangle 1, a square 0.41, a pentagon 0.24, a hexagon
0.15), so `factor` sets where polygons start to count as round.
"""
function _prune!(s::BitMatrix, D::Matrix{Float64}, factor::Float64)
    while true
        nodeof, kinds, br = _graph(s)
        spurs = _Branch[]
        for b in br
            xor(kinds[b.a] == :end, kinds[b.b] == :end) || continue
            j, e = kinds[b.a] == :junction ? (b.px[1], b.px[end]) : (b.px[end], b.px[1])
            b.len - (D[j...] - D[e...]) < max(2.0, factor * D[j...]) && push!(spurs, b)
        end
        isempty(spurs) && return
        # the shortest spur at each junction goes first: two equal limbs must not both go
        b = argmin(x -> x.len, spurs)
        for p in b.px
            nodeof[p...] > 0 && kinds[nodeof[p...]] == :junction && continue
            s[p...] = false
        end
    end
end

"""
Merge junctions joined by a branch shorter than the figure is thick there:
where three strokes meet, the thinned pixels often make two junctions a
pixel or two apart. Returns the merged node kinds and the remaining branches.
"""
function _contract(kinds::Vector{Symbol}, br::Vector{_Branch}, D::Matrix{Float64})
    parent = collect(1:length(kinds))
    root(i) = parent[i] == i ? i : (parent[i] = root(parent[i]))
    keep = _Branch[]
    for b in br
        if kinds[b.a] == :junction && kinds[b.b] == :junction &&
           b.len <= max(3.5, D[b.px[1]...] + D[b.px[end]...])
            parent[root(b.a)] = root(b.b)
        else
            push!(keep, b)
        end
    end
    ids = unique(root(i) for i in eachindex(kinds))
    newid = Dict(r => k for (k, r) in enumerate(ids))
    nk = [kinds[r] for r in ids]
    nb = [_Branch(newid[root(b.a)], newid[root(b.b)], b.px, b.len) for b in keep if root(b.a) != root(b.b)]
    return nk, nb
end

"""
Splice branches through nodes where exactly two meet: such a node is not an
end or a junction, only a place where pruning or merging left the path cut
in two, and it would make one limb read as two in the branch profile.
"""
function _splice(nn::Int, br::Vector{_Branch})
    br = copy(br)
    while true
        deg = zeros(Int, nn)
        for b in br
            deg[b.a] += 1; deg[b.b] += 1
        end
        u = findfirst(k -> deg[k] == 2 && count(b -> b.a == k && b.b == k, br) == 0, 1:nn)
        u === nothing && return br
        i, j = findall(b -> b.a == u || b.b == u, br)
        bi, bj = br[i], br[j]
        # orient both away from u, join them end to end through u
        pi = bi.b == u ? bi.px : reverse(bi.px); ai = bi.b == u ? bi.a : bi.b
        pj = bj.a == u ? bj.px : reverse(bj.px); aj = bj.a == u ? bj.b : bj.a
        ai == aj && ai == u && return br
        nb = _Branch(ai, aj, vcat(pi, pj[2:end]), bi.len + bj.len)
        deleteat!(br, sort([i, j]))
        push!(br, nb)
    end
end

"""Longest path through a tree of branches (by length): its branch indices, in order."""
function _main_path(nn::Int, br::Vector{_Branch})
    adj = [Int[] for _ in 1:nn]
    for (i, b) in enumerate(br)
        push!(adj[b.a], i); push!(adj[b.b], i)
    end
    function far(src)
        d = fill(-1.0, nn); back = zeros(Int, nn)
        d[src] = 0.0
        st = [src]
        while !isempty(st)
            x = pop!(st)
            for i in adj[x]
                y = br[i].a == x ? br[i].b : br[i].a
                d[y] >= 0 && continue
                d[y] = d[x] + br[i].len; back[y] = i
                push!(st, y)
            end
        end
        return argmax(d), back
    end
    u, _ = far(br[1].a)
    v, via = far(u)
    path = Int[]
    n = v
    while n != u && via[n] > 0
        i = via[n]
        pushfirst!(path, i)
        n = br[i].a == n ? br[i].b : br[i].a
    end
    return u, path, adj
end

"""Order of the deepest side branch, walking down from the main path."""
function _order(br::Vector{_Branch}, adj, main::Set{Int}, mainnodes::Set{Int})
    best = 0
    other(i, u) = br[i].a == u ? br[i].b : br[i].a
    # the thinned core is a tree only up to pixel noise: never revisit a node
    function reach(u, from, seen)
        push!(seen, u)
        m = 0.0
        for i in adj[u]
            (i == from || other(i, u) in seen) && continue
            m = max(m, br[i].len + reach(other(i, u), i, seen))
        end
        return m
    end
    visited = copy(mainnodes)
    function walk(u, from, ord)
        best = max(best, ord)
        push!(visited, u)
        kids = [i for i in adj[u] if i != from && !(other(i, u) in visited)]
        isempty(kids) && return
        # the longest continuation keeps the order; the others branch off it
        cont = argmax(i -> br[i].len + reach(other(i, u), i, Set([u])), kids)
        for i in kids
            other(i, u) in visited && continue
            walk(other(i, u), i, i == cont ? ord : ord + 1)
        end
    end
    for u in mainnodes, i in adj[u]
        (i in main || other(i, u) in visited) && continue
        walk(other(i, u), i, 1)
    end
    return best
end

"""Branches on the path from node u to node v, in order, or nothing."""
function _tree_path(adj, br::Vector{_Branch}, u::Int, v::Int)
    back = zeros(Int, length(adj))
    seen = falses(length(adj)); seen[u] = true
    st = [u]
    while !isempty(st)
        x = pop!(st)
        x == v && break
        for i in adj[x]
            y = br[i].a == x ? br[i].b : br[i].a
            seen[y] && continue
            seen[y] = true; back[y] = i
            push!(st, y)
        end
    end
    seen[v] || return nothing
    path = Int[]
    n = v
    while n != u
        i = back[n]
        pushfirst!(path, i)
        n = br[i].a == n ? br[i].b : br[i].a
    end
    return path
end

"""The pixels of a path of branches, end to end."""
function _path_pixels(br::Vector{_Branch}, path::Vector{Int}, start::Int)
    px = Tuple{Int,Int}[]
    n = start
    for i in path
        seg = br[i].a == n ? br[i].px : reverse(br[i].px)
        append!(px, isempty(px) ? seg : seg[2:end])
        n = br[i].a == n ? br[i].b : br[i].a
    end
    return px
end

"""Thinnest point of a path between thicker parts, and the direction of the path there."""
function _neck(px::Vector{Tuple{Int,Int}}, D::Matrix{Float64})
    n = length(px)
    n >= 5 || return 1.0, 0.0
    r = [D[p...] for p in px]
    pre = accumulate(max, r); suf = reverse(accumulate(max, reverse(r)))
    best, bi = 1.0, 0
    for i in 2:n-1
        min(pre[i], suf[i]) >= 3.0 || continue       # a neck joins two thick parts; strokes have none
        q = r[i] / min(pre[i], suf[i])
        q < best && (best = q; bi = i)
    end
    bi == 0 && return 1.0, 0.0
    a, b = px[max(bi - 3, 1)], px[min(bi + 3, n)]
    dy, dx = b[1] - a[1], b[2] - a[2]
    return best, hypot(dx, dy) == 0 ? 0.0 : abs(dy) / hypot(dx, dy)
end

"""
The core of a silhouette (foreground = the figure with its holes filled).
`prune` is the spur factor of `_prune!`.
"""
function extract_core(m::BitMatrix; prune::Float64=0.2)
    count(m) >= 4 || return POINT_CORE
    h, w = size(m)
    pm = falses(h + 2, w + 2)                       # a margin of background all round
    pm[2:h+1, 2:w+1] .= m
    D = _distance(pm)
    s = _thin(pm, D)
    _prune!(s, D, prune)
    _, kinds, br = _graph(s)
    kinds, br = _contract(kinds, br, D)
    br = _splice(length(kinds), br)
    isempty(br) && return POINT_CORE
    start, path, adj = _main_path(length(kinds), br)
    total = sum(b.len for b in br)
    # a lone path is two arms from its thickest point; an arm that extends no
    # farther than the border it runs into is a bump, as for spurs, and a
    # path with no real arm is the centre of a round figure, not a limb
    if length(br) == 1
        px = br[1].px
        r = [D[p...] for p in px]
        c = argmax(r)
        arm(rng) = length(rng) < 2 ? 0.0 :
            sum(_steplen(px[rng[k]], px[rng[k+1]]) for k in 1:length(rng)-1) - (r[c] - r[rng[end]])
        ext = (arm(c:length(px)), arm(c:-1:1))
        lim = max(2.0, prune * r[c])
        all(<(lim), ext) && return POINT_CORE
    end
    main = Set(path)
    mainnodes = Set{Int}(vcat([br[i].a for i in path], [br[i].b for i in path], [start]))
    # the narrowest neck on any path between two free ends
    neck, nvert = _neck(_path_pixels(br, path, start), D)
    ends = [u for u in eachindex(kinds) if length(adj[u]) == 1]
    for (k, u) in enumerate(ends), v in ends[k+1:end]
        p = _tree_path(adj, br, u, v)
        p === nothing && continue
        q, qv = _neck(_path_pixels(br, p, u), D)
        q < neck && ((neck, nvert) = (q, qv))
    end
    deg = zeros(Int, length(kinds))
    for b in br
        deg[b.a] += 1; deg[b.b] += 1
    end
    return FigCore(count(==(1), deg), count(>=(3), deg),
                   _order(br, adj, main, mainnodes), neck, nvert,
                   sort([b.len / total for b in br]; rev=true))
end

"""The silhouette of a retina object: its ink and its holes, cropped to its bounding box."""
function silhouette(r::Retina, o::RetObject)
    x0, x1, y0, y1 = o.bbox
    m = falses(y1 - y0 + 1, x1 - x0 + 1)
    for li in Iterators.flatten((o.pixels, (p for hl in o.holes for p in hl.pixels)))
        x, y = _xy(r, li)
        (x0 <= x <= x1 && y0 <= y <= y1) && (m[y-y0+1, x-x0+1] = true)
    end
    return m
end

"""
A silhouette magnified `f` times: each pixel becomes an f × f block, and a
3 × 3 majority vote rounds the blocks' corners. (Bilinear interpolation,
which smooths slanted borders fully, was tried: it turned the 1–2 pixel
bumps of drawn outlines into limbs, giving circles 5–15 core ends; X17.)
"""
function magnify(m::BitMatrix, f::Int)
    f <= 1 && return m
    h, w = size(m)
    b = falses(h * f, w * f)
    for y in 1:h, x in 1:w
        m[y, x] && (b[(y-1)*f+1:y*f, (x-1)*f+1:x*f] .= true)
    end
    out = similar(b)
    H, W = size(b)
    for y in 1:H, x in 1:W
        n = 0
        for dy in -1:1, dx in -1:1
            _on(b, y + dy, x + dx) && (n += 1)
        end
        out[y, x] = n >= 5
    end
    return out
end

"""
The magnification that brings a silhouette to about `target` pixels across:
an integer from 1 to 4. Small figures are seen larger, as process Z zooms
small objects (§10.3.17), so that their cores do not depend on single pixels.
"""
scale_for(m::BitMatrix, target::Real) = clamp(ceil(Int, target / max(size(m)...)), 1, 4)

"""
The core of a retina object. With `magnified`, the silhouette is first
magnified to about `ext_core_scale` pixels across (a focused look, X17).
"""
function object_core(r::Retina, o::RetObject, P::Params; magnified::Bool=false)
    o.isdot && return POINT_CORE
    m = silhouette(r, o)
    magnified && (m = magnify(m, scale_for(m, P[:ext_core_scale])))
    return extract_core(m; prune=P[:ext_core_prune])
end

"""How different two cores are: their ends, junctions, and the profile of their branch lengths."""
function core_distance(a::FigCore, b::FigCore)
    n = max(length(a.branches), length(b.branches))
    pa = vcat(a.branches, zeros(n - length(a.branches)))
    pb = vcat(b.branches, zeros(n - length(b.branches)))
    return 0.6 * abs(a.ends - b.ends) + 0.6 * abs(a.junctions - b.junctions) +
           (n == 0 ? 0.0 : sum(abs.(pa .- pb)))
end
