# Ported from Metacat's utilities.ss and formulas.ss.
#
# Every one of Metacat's stochastic decisions goes through the handful of
# functions below, so their draw order has to match the Scheme original
# exactly. Two Scheme-isms matter here:
#
#   * `(1- x)` is `(- 1 x)`, not a decrement, and `(10- x)` / `(100- x)` are
#     the same shape. They read like decrements and are not.
#   * Chez evaluates procedure arguments RIGHT TO LEFT. Where a Metacat
#     expression draws more than one random number in a single call, the
#     rightmost draw happens first, and the port has to do the same.

"""Metacat's global `*temperature*`, an exact integer in 0..100."""
const TEMPERATURE = Ref{Int}(100)

# --- random draws (see julia/src/pyrandom.jl for the generator) -------------

"""`(random n)` for an exact integer n."""
random_int(rng::PyRandom, n::Integer) = py_randbelow(rng, Int(n))

"""`(random x)` for an inexact x."""
random_real(rng::PyRandom, x) = x * py_random(rng)

"""`(prob? p)` — flip a coin weighted by p."""
function prob(rng::PyRandom, p)
    p <= 0.0 && return false
    p >= 1.0 && return true
    return p > random_real(rng, 1.0)
end

"""`(~ n)` — Metacat's fuzz: blur n by up to sqrt(n), in either direction."""
function fuzz(rng::PyRandom, n)
    delta = random_int(rng, sround(ssqrt(n)) + 1)
    return prob(rng, 0.5) ? n + delta : n - delta
end

"""`(random-pick l)`."""
random_pick(rng::PyRandom, l) = isempty(l) ? nothing : l[random_int(rng, length(l)) + 1]

"""`(weighted-index w weights)` — 0-based in Scheme, returned 1-based here."""
function weighted_index(w, weights)
    i = 1
    acc = w
    while acc >= weights[i]
        acc -= weights[i]
        i += 1
    end
    return i
end

"""`(stochastic-pick l weights)`."""
function stochastic_pick(rng::PyRandom, l, weights)
    weight_sum = ssum(weights)
    weight_sum == 0 && return random_pick(rng, l)
    return l[weighted_index(random_real(rng, sinexact(weight_sum)), weights)]
end

"""`(weighted-select w selection-list)` where each entry is (weight, payload...)."""
function weighted_select(w, selection_list)
    i = 1
    acc = w
    while acc >= selection_list[i][1]
        acc -= selection_list[i][1]
        i += 1
    end
    return selection_list[i]
end

"""`(stochastic-select selection-list)`."""
function stochastic_select(rng::PyRandom, selection_list)
    weight_sum = ssum([e[1] for e in selection_list])
    weight_sum == 0 && return random_pick(rng, selection_list)
    return weighted_select(random_real(rng, sinexact(weight_sum)), selection_list)
end

"""`(stochastic-filter proc l)` — keep each element with probability proc(x)."""
function stochastic_filter(rng::PyRandom, proc, l)
    result = eltype(l)[]
    for x in l
        if prob(rng, proc(x))
            push!(result, x)
        end
    end
    return result
end

# --- formulas.ss ------------------------------------------------------------

"""`(temp-adjusted-probability prob)` — flattens probabilities toward 0.5 as
the temperature rises."""
function temp_adjusted_probability(p)
    p == 0.0 && return 0.0
    coldness_term = pct(sub_from_10(ssqrt(sub_from_100(TEMPERATURE[]))))
    if p <= 0.5
        low_prob_factor = max(1.0, struncate(abs(slog10(p))))
        return min(0.5, p + coldness_term * (sexpt(10, sub_from_1(low_prob_factor)) - p))
    else
        return max(0.5, sub_from_1(sub_from_1(p) + coldness_term * p))
    end
end

"""`(temp-adjusted-values value-list)`."""
function temp_adjusted_values(value_list)
    exponent = sdiv(sub_from_100(TEMPERATURE[]), 30) + 0.5
    return [sround(sexpt(v, exponent)) for v in value_list]
end

# --- list utilities ---------------------------------------------------------
#
# These are exactly as picky about ordering as the Scheme originals, because
# the model reads the first (or the longest) match out of them.

"""`(product l)` — 1 for the empty list, as `(apply * '())` gives."""
product(l) = isempty(l) ? 1 : reduce(*, l)

"""`(remq-duplicates l)` — keeps the LAST of each duplicate group, not the
first, because the Scheme drops an element whenever it recurs in the tail."""
function remq_duplicates(l)
    result = eltype(l)[]
    for (i, x) in enumerate(l)
        any(y -> y === x, @view l[i+1:end]) && continue
        push!(result, x)
    end
    return result
end

"""`(intersect l1 l2)` — the elements of l1 that are eq? to something in l2,
in l1's order."""
intersect_eq(l1, l2) = eltype(l1)[x for x in l1 if any(y -> y === x, l2)]

"""`(remq-elements elements l)`."""
remq_elements(elements, l) = eltype(l)[x for x in l if !any(y -> y === x, elements)]

"""`(partition pred? l)` — groups l into classes, each of whose members the
new element relates to under `pred`. The Scheme builds the classes from the
END of the list backwards, and inserts into the first class every one of whose
members satisfies the predicate; both matter for which partition comes out."""
function partition_by(pred, l)
    classes = Vector{eltype(l)}[]
    for x in Iterators.reverse(l)
        i = findfirst(c -> all(y -> pred(x, y), c), classes)
        if i === nothing
            push!(classes, eltype(l)[x])
        else
            pushfirst!(classes[i], x)
        end
    end
    return classes
end

"""`(select-longest-list l)` — the FIRST longest sublist, or empty."""
function select_longest_list(l)
    isempty(l) && return []
    lengths = [length(x) for x in l]
    return l[findfirst(==(maximum(lengths)), lengths)]
end
