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

# --- Chez's `map` application order -----------------------------------------
#
# Metacat does not define its own `map`, so `map`, and everything built on it
# (`tell-all`, `flatmap`, `adjacency-map`), gets Chez's. Chez does NOT apply the
# procedure left to right: it walks the list in PAIRS, recursing to the tail
# first, so for a 4-element list the order is 3, 4, 1, 2, and for 5 elements it
# is 5, 3, 4, 1, 2. (Metacat's own `filter`, `filter-out` and `stochastic-filter`
# ARE hand-written left-to-right recursions, and so is `for-each`; only `map` is
# affected.)
#
# This is invisible for a pure procedure, and it changes the answer for one that
# draws random numbers or mutates shared state. The group builder's
# constituent-bond reconciliation is the first place it bites: it decides the
# order bonds are pushed onto the string's bond list.

"""`(map proc l)` with Chez's application order. Results come back in list
order; only the order in which `f` is APPLIED differs."""
function scheme_map(f, l)
    n = length(l)
    results = Vector{Any}(undef, n)
    function walk(i)
        remaining = n - i + 1
        remaining <= 0 && return
        if remaining > 2
            walk(i + 2)
        end
        results[i] = f(l[i])
        remaining >= 2 && (results[i + 1] = f(l[i + 1]))
        return
    end
    walk(1)
    return results
end

"""`(map proc l1 l2)`, two lists, same application order."""
function scheme_map(f, l1, l2)
    n = min(length(l1), length(l2))
    results = Vector{Any}(undef, n)
    function walk(i)
        remaining = n - i + 1
        remaining <= 0 && return
        if remaining > 2
            walk(i + 2)
        end
        results[i] = f(l1[i], l2[i])
        remaining >= 2 && (results[i + 1] = f(l1[i + 1], l2[i + 1]))
        return
    end
    walk(1)
    return results
end

"""`(adjacency-map f l)` = `(map f (all-but-last 1 l) (rest l))`, and so it
inherits Chez's application order too."""
adjacency_map(f, l) = scheme_map(f, l[1:(end - 1)], l[2:end])
