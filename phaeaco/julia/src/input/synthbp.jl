# Synthetic Bongard problems, one per mechanism in the plan's target table.
#
# These are *analogues*, not copies: each one isolates the idea behind a real
# BP (texture, size, count, ...) while varying everything else, so the solver
# can be developed before real images are available and so its failures can
# be attributed. Named by mechanism, not by BP number, to avoid implying they
# are the originals.

const _MAX_TRIES = 50

_tex(rng) = rand(rng, Bool)

function _any_shape(rng, c, r; filled=_tex(rng), width=1.6)
    k = rand(rng, 1:4)
    k == 1 && return circle(c, r; filled=filled, width=width)
    k == 2 && return ellipse(c, r, r * (0.45 + 0.35rand(rng)), π * rand(rng); filled=filled, width=width)
    return random_polygon(rng, rand(rng, 3:5), c, r; filled=filled, width=width)
end

_maker(f) = (rng, c) -> f(rng, c)

"""Build a BP from a per-box generator `gen(rng, side) -> Vector{Shape}`."""
function _bp(name, left, right, gen; seed, σ=0.0)
    rng = Xoshiro(seed)
    truth = Vector{Vector{Shape}}()
    boxes = BitMatrix[]
    for i in 1:12
        side = side_of(i)
        shapes = Shape[]
        for _ in 1:_MAX_TRIES
            try
                shapes = gen(rng, side)
                break
            catch e
                e isa ErrorException || rethrow()
            end
        end
        push!(truth, shapes)
        push!(boxes, render(shapes; rng=rng, σ=σ))
    end
    return BP(name, boxes, left, right), truth
end

"""name => (left label, right label, per-box generator)"""
const SYNTH_BPS = Dict{Symbol,Tuple{String,String,Function}}()

synthbp!(name::Symbol, left, right, gen) = (SYNTH_BPS[name] = (left, right, gen))

# BP #1 — nothing vs. something.
synthbp!(:existence, "no object", "some object", (rng, side) ->
    side == :left ? Shape[] :
    place(rng, [_maker((r, c) -> _any_shape(r, c, 8 + 14rand(r))) for _ in 1:rand(rng, 1:3)]))

# BP #2 — large vs. small.
synthbp!(:size, "large figure", "small figure", (rng, side) ->
    place(rng, [_maker((r, c) -> _any_shape(r, c, side == :left ? 28 + 12rand(r) : 7 + 4rand(r)))]))

# BP #3 — outlined vs. filled.
synthbp!(:texture, "outlined figures", "filled figures", (rng, side) ->
    place(rng, [_maker((r, c) -> _any_shape(r, c, 6 + 16rand(r); filled=side == :right))
                for _ in 1:rand(rng, 1:3)]))

# BP #4 — convex vs. concave.
synthbp!(:convexity, "convex figure", "concave figure", (rng, side) ->
    place(rng, [_maker((r, c) -> side == :left ?
        (rand(r) < 0.25 ? ellipse(c, 25 + 10rand(r), 15 + 10rand(r), π * rand(r); filled=_tex(r)) :
                         random_polygon(r, rand(r, 3:6), c, 25 + 10rand(r); irreg=0.2, filled=_tex(r))) :
        random_concave(r, c, 25 + 10rand(r); filled=_tex(r)))]))

# BP #5 — no curves vs. curves.
synthbp!(:curves, "straight lines only", "some curve", (rng, side) ->
    place(rng, [_maker((r, c) -> side == :left ?
        random_polygon(r, rand(r, 3:5), c, 12 + 14rand(r); filled=_tex(r)) :
        (rand(r) < 0.5 ? circle(c, 10 + 14rand(r); filled=_tex(r)) :
                         ellipse(c, 14 + 12rand(r), 8 + 6rand(r), π * rand(r); filled=_tex(r))))
        for _ in 1:rand(rng, 1:2)]))

# BP #6 — triangles vs. quadrilaterals.
synthbp!(:tri_vs_quad, "triangles", "quadrilaterals", (rng, side) ->
    place(rng, [_maker((r, c) -> random_polygon(r, side == :left ? 3 : 4, c, 15 + 20rand(r); irreg=0.3))]))

# BP #8 — figure toward the right of the box vs. toward the left.
synthbp!(:position, "figure on the right", "figure on the left", (rng, side) ->
    place(rng, [_maker((r, c) -> _any_shape(r, c, 8 + 8rand(r)))];
          region=side == :left ? (55.0, 100.0, 1.0, 100.0) : (1.0, 45.0, 1.0, 100.0), margin=4.0))

# BP #11-like — elongated vs. compact figures.
synthbp!(:elongation, "elongated figure", "compact figure", (rng, side) ->
    place(rng, [_maker((r, c) -> begin
        L = 22 + 12rand(r)
        side == :left ? ellipse(c, L, L * (0.18 + 0.12rand(r)), π * rand(r); filled=_tex(r)) :
                        (rand(r) < 0.5 ? circle(c, 14 + 10rand(r); filled=_tex(r)) :
                                         random_polygon(r, rand(r, 4:6), c, 16 + 10rand(r); irreg=0.1, filled=_tex(r)))
    end)]))

# BP #15 — closed figures vs. open figures.
synthbp!(:interior, "closed figure", "open figure", (rng, side) ->
    place(rng, [_maker((r, c) -> begin
        p = random_polygon(r, rand(r, 3:5), c, 15 + 15rand(r))
        side == :left ? p : polyline(p.pts)           # same outline, one side missing
    end) for _ in 1:rand(rng, 1:2)]))

# BP #21 — a small figure present vs. none.
synthbp!(:small_present, "a small figure present", "no small figure", (rng, side) ->
    begin
        n = rand(rng, 1:2)
        big = [_maker((r, c) -> _any_shape(r, c, 14 + 10rand(r))) for _ in 1:n]
        side == :left ? place(rng, vcat(big, [_maker((r, c) -> _any_shape(r, c, 3.5 + 1.5rand(r); filled=true))])) :
                        place(rng, big)
    end)

# BP #22 — figures of equal size vs. unequal.
synthbp!(:same_size, "figures of the same size", "figures of different sizes", (rng, side) ->
    begin
        n = rand(rng, 2:3)
        r0 = 9 + 6rand(rng)
        sizes = side == :left ? fill(r0, n) : shuffle(rng, [r0 * f for f in (1.0, 1.8, 2.4)][1:n])
        place(rng, [_maker((r, c) -> _any_shape(r, c, s)) for s in sizes])
    end)

# BP #23 — two figures vs. three. (The real BP's counts are not given in the
# thesis text; any small distinct pair exercises numerosity.)
synthbp!(:count_objects, "two figures", "three figures", (rng, side) ->
    place(rng, [_maker((r, c) -> _any_shape(r, c, 6 + 8rand(r))) for _ in 1:(side == :left ? 2 : 3)]))

# BP #39 — lines nearly parallel vs. not.
synthbp!(:parallel_lines, "all lines almost parallel", "lines not all parallel", (rng, side) ->
    begin
        n = rand(rng, 3:5)
        θ0 = π * rand(rng)
        angles = side == :left ? [θ0 + 0.05randn(rng) for _ in 1:n] :
                                 [θ0 + (k == 1 ? π / 2 * (0.6 + 0.4rand(rng)) : 0.05randn(rng)) for k in 1:n]
        place(rng, [_maker((r, c) -> begin
            L = 12 + 8rand(r)
            dx, dy = L * cos(θ), -L * sin(θ)
            segment((c[1] - dx, c[2] - dy), (c[1] + dx, c[2] + dy))
        end) for θ in shuffle(rng, angles)]; gap=3.0)
    end)

# BP #56 — all figures of one texture vs. mixed.
synthbp!(:same_texture, "every figure has the same texture", "textures differ", (rng, side) ->
    begin
        n = rand(rng, 3:4)
        t = _tex(rng)
        texs = side == :left ? fill(t, n) : shuffle(rng, vcat([true, false], [_tex(rng) for _ in 3:n]))
        place(rng, [_maker((r, c) -> _any_shape(r, c, 7 + 5rand(r); filled=f)) for f in texs])
    end)

# BP #85 — three lines vs. four (isolated or joined, as in the original).
synthbp!(:line_count, "three lines", "four lines", (rng, side) ->
    begin
        n = side == :left ? 3 : 4
        mode = rand(rng, 1:3)
        if mode == 1                               # n separate segments
            place(rng, [_maker((r, c) -> begin
                L, θ = 8 + 8rand(r), π * rand(r)
                segment((c[1] - L * cos(θ), c[2] + L * sin(θ)), (c[1] + L * cos(θ), c[2] - L * sin(θ)))
            end) for _ in 1:n]; gap=4.0)
        elseif mode == 2                           # a closed n-gon
            place(rng, [_maker((r, c) -> random_polygon(r, n, c, 16 + 14rand(r); irreg=0.3))])
        else                                       # an open zig-zag of n lines
            place(rng, [_maker((r, c) -> begin
                p = random_polygon(r, n + 1, c, 18 + 12rand(r); irreg=0.3)
                polyline(p.pts)
            end)])
        end
    end)

"""
    synth_bp(name; seed=1, σ=0.0) -> (bp, truth)

One of the synthetic BPs. `σ` > 0 draws the figures hand-drawn.
"""
function synth_bp(name::Symbol; seed=1, σ=0.0)
    left, right, gen = SYNTH_BPS[name]
    return _bp(string(name), left, right, gen; seed=seed, σ=σ)
end
