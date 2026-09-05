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

"""`(stochastic-if* prob ...)` — the coin is ALWAYS drawn, and it is drawn
BEFORE the probability is evaluated. Callers pass an already-evaluated
probability; where the probability expression itself consumes randomness, draw
the coin first by hand instead of using this."""
stochastic_if(rng::PyRandom, p) = random_real(rng, 1.0) < p

"""`(list-index l v)` — 0-based position of v in l, by `eq?`."""
list_index(l, v) = (i = findfirst(x -> x === v, l); i === nothing ? nothing : i - 1)

"""`(sort-wrt-order l order)` — order the elements by where they appear in a
reference list."""
sort_wrt_order(l, order) =
    chez_sort((v1, v2) -> list_index(order, v1) < list_index(order, v2), l)

"""`(bounded-random-partition pred? l bound)` — like `partition`, but the
elements are taken in a RANDOM order and no class may exceed `bound`.

The draw is `(random-pick l)` on the remaining elements, so the number of draws
is the length of the list, not the number of classes."""
function bounded_random_partition(rng::PyRandom, pred, l, bound::Integer)
    remaining = collect(l)
    isempty(remaining) && return Vector{eltype(remaining)}[]
    x = remaining[random_int(rng, length(remaining)) + 1]
    rest = bounded_random_partition(rng, pred, remove_first(x, remaining), bound)
    for (i, cls) in enumerate(rest)
        if length(cls) < bound && all(y -> pred(x, y), cls)
            rest[i] = vcat([x], cls)
            return rest
        end
    end
    return push!(rest, eltype(rest)([x]))
end

"""`(remove-first x l)` — drop the first element `eq?` to x."""
function remove_first(x, l)
    i = findfirst(y -> y === x, l)
    i === nothing && return collect(l)
    return vcat(l[1:(i - 1)], l[(i + 1):end])
end

"""`(sort pred? l)` — Chez's list sort, reproduced exactly.

Chez splits at `n >> 1` with the LEFT half short, recurses on the right half
FIRST (procedure arguments are evaluated right to left), and merges preferring
the left list on a tie. For a predicate that is a strict weak ordering none of
that is observable — but `apply-before?` in `rules.ss` is deliberately not
transitive, so for it the algorithm IS the specification. Julia's `MergeSort`
splits the other way and would order such a list differently."""
function chez_sort(pred, l::AbstractVector)
    n = length(l)
    n <= 1 && return collect(l)
    i = n >> 1
    right = chez_sort(pred, l[(i + 1):end])
    left = chez_sort(pred, l[1:i])
    out = similar(left, 0)
    a = 1
    b = 1
    while a <= length(left) && b <= length(right)
        if pred(right[b], left[a])
            push!(out, right[b]); b += 1
        else
            push!(out, left[a]); a += 1
        end
    end
    append!(out, left[a:end])
    append!(out, right[b:end])
    return out
end

"""`(pairwise-map proc l)` — proc over every ordered pair `(l[i], l[j])`, i<j,
in that order."""
pairwise_map(proc, l) =
    [proc(l[i], l[j]) for i in eachindex(l) for j in (i + 1):lastindex(l)]

"""The order in which `(pairwise-map proc l)` APPLIES proc.

`pairwise-map` is `(append (map (proc l[1] .) (rest l)) (pairwise-map (rest l)))`
and Chez evaluates `append`'s arguments right to left, so the recursive call
runs first: the pairs come out starting from the deepest suffix and working
back to the head, each head's own pairs in `chez_map_order`. The RESULT list is
still in plain i<j order — this is only about when each call happens, which
matters when proc escapes, as it does in `check-for-conflicts`."""
function pairwise_apply_order(n::Integer)
    pairs = Tuple{Int,Int}[]
    for i in (n - 1):-1:1
        for k in chez_map_order(n - i)
            push!(pairs, (i, i + k))
        end
    end
    return pairs
end

"""`(pairwise-andmap pred? l)`."""
pairwise_andmap(pred, l) =
    all(pred(l[i], l[j]) for i in eachindex(l) for j in (i + 1):lastindex(l))

"""`(cross-product l1 l2)` — pairs in row-major order, `l1` varying slowest."""
cross_product(l1, l2) = [(x, y) for x in l1 for y in l2]

"""`(sets-equal? s1 s2)` — by `eq?`, i.e. object identity."""
sets_equal(s1, s2) = all(x -> any(y -> y === x, s2), s1) &&
                     all(y -> any(x -> x === y, s1), s2)

"""`(sets-equal-pred? pred? s1 s2)` — mutual subset under an arbitrary
equivalence, which is how theme-pattern entries are compared (they match on
dimension and relation, ignoring any activation)."""
sets_equal_pred(pred, s1, s2) = all(x -> any(y -> pred(x, y), s2), s1) &&
                                all(y -> any(x -> pred(y, x), s1), s2)

"""The order in which Chez's `map` applies its procedure — NOT left to right.

Chez's `map` recurses on the tail-but-two before applying the procedure to the
first two elements, so it works the list in pairs from the END backwards, left
to right within each pair: `(1 2 3 4 5)` is applied in the order `5 3 4 1 2`.
That is invisible for a pure procedure and decides the answer for one with side
effects or one that can fail part-way — which is what `new-start-letter` on a
group image does when the run walks off the end of the alphabet. `for-each`
(Metacat's `for*`) IS left to right; only `map` and `tell-all` do this."""
function chez_map_order(n::Integer)
    order = Int[]
    for start in ((isodd(n) ? n : n - 1):-2:1)
        push!(order, start)
        start + 1 <= n && push!(order, start + 1)
    end
    return order
end

"""`(map f l)` — the result is in list order, but `f` is APPLIED in Chez's
order, which is what matters when `f` has an effect or can escape."""
function chez_map(f, l)
    n = length(l)
    n == 0 && return Any[]
    results = Vector{Any}(undef, n)
    for i in chez_map_order(n)
        results[i] = f(l[i])
    end
    return results
end

"""`(map f l1 l2)`, applied in the same order."""
function chez_map(f, l1, l2)
    n = min(length(l1), length(l2))
    n == 0 && return Any[]
    results = Vector{Any}(undef, n)
    for i in chez_map_order(n)
        results[i] = f(l1[i], l2[i])
    end
    return results
end

"""`(partition pred? l)` — greedily group elements into classes whose members
all satisfy pred? pairwise.

The Scheme builds this back-to-front: it partitions the TAIL, then inserts the
head into the first class all of whose members it matches, or, failing that,
appends a class of its own at the END. Both halves of that matter to the order
of the result: with a predicate nothing matches across, `(a b c)` comes back as
`((c) (b) (a))`, not `((a) (b) (c))`."""
function spartition(pred, l)
    isempty(l) && return Vector{eltype(l)}[]
    classes = spartition(pred, l[2:end])
    x = l[1]
    for (i, cls) in enumerate(classes)
        if all(y -> pred(x, y), cls)
            classes[i] = vcat([x], cls)
            return classes
        end
    end
    return push!(classes, eltype(classes)([x]))
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

"""`(remq-duplicates l)`. NB: `remove-duplicates-pred` drops an element when an
identical one appears LATER in the list, so it keeps the LAST of each duplicate
group, not the first. Identity (`eq?`), not equality — Metacat compares
workspace and slipnet objects by identity throughout."""
remq_duplicates(l::AbstractVector) =
    [x for (i, x) in enumerate(l) if !any(y -> y === x, @view l[(i + 1):end])]
