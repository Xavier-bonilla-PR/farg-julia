# Mirrors copycat/randomness.py. Every draw goes through the CPython-compatible
# generator, and `weighted_choice` reproduces bisect_left over the cumulative
# weights exactly (including the negative-weight case in chooseOldCodelet,
# where the array is not actually sorted and the binary search is simply
# whatever bisect does).

coinFlip(r::Randomness) = py_random(r.rng) < 0.5
coinFlip(r::Randomness, p::Real) = py_random(r.rng) < p

function choice(r::Randomness, seq::AbstractVector)
    isempty(seq) && throw(ArgumentError("Cannot choose from an empty sequence"))
    return seq[py_randbelow(r.rng, length(seq)) + 1]
end

"""Python's `bisect.bisect_left(a, x)`, returning a 1-based insertion point."""
function bisect_left(a::AbstractVector{Float64}, x::Float64)
    lo = 0
    hi = length(a)
    while lo < hi
        mid = (lo + hi) >> 1
        if @inbounds(a[mid + 1]) < x
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo + 1
end

function weighted_choice(r::Randomness, seq::AbstractVector, weights::AbstractVector)
    # Many callers rely on an empty sequence yielding nothing.
    isempty(seq) && return nothing
    cum = Vector{Float64}(undef, length(weights))
    total = 0.0
    @inbounds for i in eachindex(weights)
        total += weights[i]
        cum[i] = total
    end
    idx = bisect_left(cum, py_random(r.rng) * total)
    return seq[idx]
end

function weighted_greater_than(r::Randomness, first::Real, second::Real)
    total = first + second
    total == 0 && return false
    return coinFlip(r, first / total)
end

function sqrtBlur(r::Randomness, value::Real)
    # This is exceedingly dumb, but it matches the Java code.
    root = sqrt(value)
    return coinFlip(r) ? value + root : value - root
end
