# Pattern-matching (§8.2): the perceptual difference d ∈ [0, 1] between two
# representations, and similarity s = e^(−d) (Eq. 8.8).

"""What a match needs from its context: LTM weights, σ₀, and recursion limits."""
struct Matcher
    ltm::LTM
    now::Int
    σ0::Float64
    damping::Float64        # weight factor per level down (§8.2.4: diminishing returns)
    maxdepth::Int           # "two or three recursive steps"
    sfloor::Float64         # minimum standard deviation, as a fraction of a feature's range
    literal::Bool           # d = P(different) alone, as Eq. 8.2 reads (see feature_difference)
end

Matcher(ctx::Ctx) = Matcher(ctx.ltm, ctx.now, ctx.P[:numerosity_sigma0], ctx.P[:match_damping],
                            Int(ctx.P[:match_maxdepth]), ctx.P[:match_sfloor], ctx.P[:match_literal] != 0)

"""wᵢ of Eq. 8.7: significance + activation of the concept, with a small floor."""
mweight(M::Matcher, name::Symbol) = haskey(M.ltm, name) ? max(cweight(M.ltm, name, M.now), 0.02) : 0.02

"""
Difference of two feature samples (§8.2.1).

Two single observations: the scaled absolute difference (Eq. 8.1). With a
sample on either side, the thesis takes the probability that the two come
from different populations (Student's t, Eqs. 8.2–8.3). Used alone as a
distance, that probability is uniform on [0, 1] for a genuine member of the
sample, so a clustering threshold of 0.83 (d < 0.19) would admit about one
member in five; the Patterns algorithm could not then score anything like
its 98.5 in Table 8.1. We therefore weight the scaled difference (Eq. 8.1)
by that probability: far *and* improbable is different; a deviation the
sample's own spread accounts for is discounted. With no sample this is
exactly Eq. 8.1. `literal = true` restores the probability alone (D27).

Standard deviations are floored at a small fraction of the feature's range,
so a sample of identical values does not make every other value infinitely
improbable (D26); discrete features have no floor.
"""
function feature_difference(M::Matcher, f1::Stats, f2::Stats, info::FeatureInfo)
    (f1.n == 0 || f2.n == 0) && return 0.0
    scaled = clamp(abs(f1.mean - f2.mean) / info.maxval, 0.0, 1.0)
    (f1.n == 1 && f2.n == 1) && return scaled
    p = difference_probability(M, f1, f2, info)
    return M.literal ? p : scaled * p
end

"""Probability that two feature samples come from different populations (Eqs. 8.2–8.3)."""
function difference_probability(M::Matcher, f1::Stats, f2::Stats, info::FeatureInfo)
    floor = info.discrete ? 0.0 : M.sfloor * info.maxval
    Δ = abs(f1.mean - f2.mean)
    if f1.n == 1 && f2.n == 1
        return Δ == 0 ? 0.0 : 1.0
    elseif f1.n == 1 || f2.n == 1
        x, s = f1.n == 1 ? (f1, f2) : (f2, f1)
        sd = max(stddev(s), floor)
        sd == 0 && return Δ == 0 ? 0.0 : 1.0
        t = Δ / (sd * sqrt(1 + 1 / s.n))          # how far out of the sample the value lies
        return t_two_sided(t, Float64(s.n - 1))
    end
    v1 = max(variance(f1), floor^2) / f1.n
    v2 = max(variance(f2), floor^2) / f2.n
    v1 + v2 == 0 && return Δ == 0 ? 0.0 : 1.0
    t = Δ / sqrt(v1 + v2)
    ν = (v1 + v2)^2 / (v1^2 / (f1.n - 1) + v2^2 / (f2.n - 1))     # Eq. 8.3
    return t_two_sided(t, ν)
end

"""
Difference of two numerosity samples (§8.2.2): the probability that the
accumulator Gaussians they describe are different populations. Eq. 8.4 for
two single observations, 8.5 for one against a sample, 8.6 for two samples.
The accumulator's own spread is kept in the two-sample case too, so two
samples of identical counts are not infinitely confident (D26).
"""
function numerosity_difference(M::Matcher, a::Stats, b::Stats)
    σ0 = M.σ0
    L, S = a.mean, b.mean
    if a.n == 1 && b.n == 1
        den = σ0 * sqrt(max(L, 0.0) + max(S, 0.0))
    elseif a.n == 1 || b.n == 1
        x, s = a.n == 1 ? (a, b) : (b, a)
        den = sqrt(σ0^2 * max(x.mean, 0.0) + variance(s) / s.n)
        L, S = x.mean, s.mean
    else
        den = sqrt(variance(a) / a.n + variance(b) / b.n + σ0^2 * (max(L, 0.0) / a.n + max(S, 0.0) / b.n))
    end
    Δ = abs(L - S)
    den == 0 && return Δ < 0.5 ? 0.0 : 1.0
    return normal_two_sided(Δ / den)
end

"""
    difference(M, a, b) -> d ∈ [0, 1]

The overall difference of two representations (§8.2.3–8.2.4): the weighted
mean (Eq. 8.7) of the differences of their shared features, their counts,
and their parts. A count present on one side only is compared with zero (the
other has none of that thing). Parts are matched type by type, each part to
its best counterpart (O(n·m), §8.2.4), recursing at most `maxdepth` levels
with each level's weight damped. A kind of part present on one side only
counts as wholly different, weighted by how strongly it belongs (§8.3.3).
"""
difference(M::Matcher, a::RNode, b::RNode) = _diff(M, a, b, 0)
# (a count present on one side only is compared with zero when the other side
# has none of that thing; if it has some but did not count them, it is ignored)

function _diff(M::Matcher, a::RNode, b::RNode, depth::Int)
    num = den = 0.0
    for (f, s1) in a.feats
        haskey(b.feats, f) || continue
        info = haskey(M.ltm, f) ? M.ltm[f].feature : nothing
        info === nothing && continue
        w = mweight(M, f)
        num += w * feature_difference(M, s1, b.feats[f], info)
        den += w
    end
    wn = mweight(M, :numerosity)
    for t in union(keys(a.nums), keys(b.nums))
        s1 = count_of(a, t)
        s2 = count_of(b, t)
        (s1 === nothing || s2 === nothing) && continue      # not counted (yet): ignored, like a missing feature
        w = wn * sqrt(mweight(M, t))            # counts of salient things matter more
        num += w * numerosity_difference(M, s1, s2)
        den += w
    end
    if depth < M.maxdepth
        types = union(Set(c.type for c in a.children), Set(c.type for c in b.children))
        for t in types
            ca = [c for c in a.children if c.type == t]
            cb = [c for c in b.children if c.type == t]
            w = mweight(M, t) * M.damping
            if isempty(ca) || isempty(cb)
                present, parent = isempty(ca) ? (cb, b) : (ca, a)
                s = maximum(strength(c, parent) for c in present)
                num += w * s
                den += w * s
                continue
            end
            # each part of the side with fewer to its best counterpart
            small, large = length(ca) <= length(cb) ? (ca, cb) : (cb, ca)
            dsum = 0.0
            for c in small
                dsum += minimum(_diff(M, c, o, depth + 1) for o in large)
            end
            num += w * dsum / length(small)
            den += w
        end
    end
    return den == 0 ? 0.0 : num / den
end

similarity(M::Matcher, a::RNode, b::RNode) = exp(-difference(M, a, b))     # Eq. 8.8

"""
The count of `t` in a node: its numerosity statistics; zero if it has no
parts of that type at all (there are none to count); `nothing` if it has
such parts but did not count them on this look.
"""
function count_of(r::RNode, t::Symbol)
    haskey(r.nums, t) && return r.nums[t]
    any(c -> c.type == t, r.children) && return nothing
    return Stats(0.0)
end

"""
Pair each node in `xs` with a distinct best counterpart in `ys` (greedy by
difference). Returns (i, j) index pairs. Used to record correspondences when
building a pattern (§8.2.4, last paragraph).
"""
function correspond(M::Matcher, xs::Vector{RNode}, ys::Vector{RNode}, depth::Int)
    pairs = Tuple{Float64,Int,Int}[]
    for (i, x) in enumerate(xs), (j, y) in enumerate(ys)
        push!(pairs, (_diff(M, x, y, depth), i, j))
    end
    sort!(pairs)
    usedx, usedy = Set{Int}(), Set{Int}()
    out = Tuple{Int,Int}[]
    for (_, i, j) in pairs
        (i in usedx || j in usedy) && continue
        push!(usedx, i); push!(usedy, j)
        push!(out, (i, j))
    end
    return out
end
