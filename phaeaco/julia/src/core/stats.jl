# The statistics of a feature (Table 7.1) and their incremental update
# (Eqs. 8.9–8.11). Feature and numerosity nodes carry these rather than a
# single number, because Phaeaco looks at the same thing repeatedly and
# because patterns are statistical summaries of exemplars (§8.3.3).

mutable struct Stats
    n::Int
    mean::Float64
    sumsq::Float64
    min::Float64
    max::Float64
end

Stats() = Stats(0, 0.0, 0.0, Inf, -Inf)
Stats(x::Real) = push!(Stats(), x)

function Base.push!(s::Stats, x::Real)
    x = Float64(x)
    s.mean = (s.n * s.mean + x) / (s.n + 1)       # Eq. 8.9
    s.n += 1
    s.sumsq += x * x                              # Eq. 8.11
    s.min = min(s.min, x)
    s.max = max(s.max, x)
    return s
end

"""Merge a whole sample into `s` (the generalisation the thesis notes after Eq. 8.11)."""
function Base.merge!(s::Stats, t::Stats)
    t.n == 0 && return s
    n = s.n + t.n
    s.mean = (s.n * s.mean + t.n * t.mean) / n
    s.n = n
    s.sumsq += t.sumsq
    s.min = min(s.min, t.min)
    s.max = max(s.max, t.max)
    return s
end

Base.copy(s::Stats) = Stats(s.n, s.mean, s.sumsq, s.min, s.max)

"""Sample variance (Eq. 8.10, squared). Zero for fewer than two observations."""
function variance(s::Stats)
    s.n < 2 && return 0.0
    v = (s.sumsq - s.n * s.mean^2) / (s.n - 1)
    return max(v, 0.0)          # rounding can push an all-equal sample below 0
end

stddev(s::Stats) = sqrt(variance(s))
