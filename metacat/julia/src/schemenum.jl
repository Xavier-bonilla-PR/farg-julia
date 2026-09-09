# Scheme's numeric tower, as far as Metacat uses it.
#
# Metacat computes in exact rationals wherever it can: `(% n)` is `(/ n 100)`,
# which for an integer n is an exact rational, not a float. Those exact values
# flow through activations, link lengths, strengths and probabilities, and only
# become floats when something inexact (a random draw, an irrational root)
# enters. A port that silently uses Float64 throughout drifts in the low bits
# and eventually takes a different branch at a stochastic threshold, so the
# port reproduces the tower instead.
#
# Julia's own promotion rules already match Scheme's exactness contagion:
# Int op Int stays exact, Rational op Int stays exact, and anything touching a
# Float64 becomes inexact. What Julia lacks is Scheme's exactness-preserving
# `/`, `sqrt` and `expt`, and its exactness-preserving `round`; those are here.

"""An exact Scheme number: integer or ratio of integers."""
const SExact = Union{Integer,Rational}
"""Any Scheme number Metacat produces."""
const SNum = Union{Integer,Rational,AbstractFloat}

is_exact(x::AbstractFloat) = false
is_exact(::Integer) = true
is_exact(::Rational) = true

"""Normalise an exact rational with denominator 1 back to an integer, the way
Scheme's numeric tower does (`(/ 4 2)` is `2`, not `2/1`)."""
snorm(x::Rational) = denominator(x) == 1 ? numerator(x) : x
snorm(x) = x

"""Scheme's `/`: exact when both operands are exact."""
sdiv(a::SExact, b::SExact) = snorm(a // b)
sdiv(a, b) = a / b

"""Scheme's `sqrt`: exact when the argument is an exact perfect square (of a
rational, too — `(sqrt 1/4)` is `1/2`), inexact otherwise."""
function ssqrt(x::Integer)
    x < 0 && return sqrt(complex(float(x)))
    r = isqrt(x)
    return r * r == x ? r : sqrt(float(x))
end
function ssqrt(x::Rational)
    n, d = numerator(x), denominator(x)
    if n >= 0
        rn, rd = isqrt(n), isqrt(d)
        if rn * rn == n && rd * rd == d
            return snorm(rn // rd)
        end
    end
    return sqrt(float(x))
end
ssqrt(x::AbstractFloat) = sqrt(x)

"""Scheme's `exp`. R6RS lets `exp` return an exact result where one is exactly
representable, and Chez takes that permission in exactly one case:

    (exp 0)   => 1     exact
    (exp 0.0) => 1.0   inexact
    (exp 1)   => 2.718281828459045

Julia's `exp(0)` is `1.0`, so an exact zero would go inexact and stay inexact
through everything downstream. That matters because `exp` is only used inside
the theme-compatibility sigmoid, whose argument is an exact 0 whenever a bridge
has no active themes — which is most of the time early in a run."""
sexp(x) = (is_exact(x) && iszero(x)) ? 1 : exp(float(x))

"""Scheme's `expt`: exact base raised to an exact *integer* power stays exact;
any other combination goes inexact."""
function sexpt(b::SExact, e::Integer)
    e >= 0 && return snorm(b^e)
    return snorm((1 // b)^(-e))
end
sexpt(b, e) = float(b)^float(e)

# Metacat redefines truncate/ceiling/floor/round to return exact integers.
# Julia's round defaults to RoundNearest, which is the same round-half-to-even
# that Scheme's `round` uses.
sround(x::Integer) = x
sround(x::Rational) = Integer(round(x, RoundNearest))
sround(x::AbstractFloat) = Integer(round(x, RoundNearest))
struncate(x::Integer) = x
struncate(x) = Integer(trunc(x))
sfloor(x::Integer) = x
sfloor(x) = Integer(floor(x))
sceiling(x::Integer) = x
sceiling(x) = Integer(ceil(x))

"""`(exact->inexact x)`."""
sinexact(x) = float(x)

"""Scheme's `max` and `min`, and `utilities.ss`'s `maximum` / `minimum` over a
list.

Julia's `max` PROMOTES its arguments to a common type and returns a value of
that type; Scheme returns the winning ARGUMENT, so the winner's representation
survives:

    Chez:   (max 9/10 1)          => 1        an exact INTEGER
    Julia:  max(9//10, 1)         => 1//1     a Rational

The two are numerically equal, so no arithmetic downstream can tell them apart
— but a call site that DISPATCHES on `::Integer` can, and `snorm` at render
time only hides it where a probe happens to run one. Since the tower already
normalises every exact rational with denominator 1 back to an integer,
`snorm` on Julia's answer IS Scheme's answer: the only way the two differ is an
integer beating a rational, and normalising the promoted result restores it.

Exactness contagion needs no special handling: R6RS makes the result inexact if
ANY argument is inexact (`(max 3 2.0)` is `3.0`), which is precisely what
Julia's promotion already does.

Use these wherever an operand can be an exact RATIONAL. Where every operand is
an integer — spans, lengths, ages, activations, most of the model — plain
`max`/`min` is already right and is left alone."""
smax(xs...) = snorm(max(xs...))
smin(xs...) = snorm(min(xs...))
"""`(maximum l)` / `(minimum l)` from utilities.ss: 0 for an empty list."""
smaximum(l) = isempty(l) ? 0 : snorm(maximum(l))
sminimum(l) = isempty(l) ? 0 : snorm(minimum(l))

# --- the arithmetic sugar from utilities.ss ---------------------------------

"""`(% n)` = `(/ n 100)`, exact for exact n."""
pct(n) = sdiv(n, 100)
"""`(100- n)`"""
sub_from_100(n) = 100 - n
"""`(10- x)`"""
sub_from_10(x) = 10 - x
"""`(1- x)` — note this is `(- 1 x)` in Metacat, not a decrement."""
sub_from_1(x) = 1 - x

sq(x) = x * x
cube(x) = x * x * x

"""Metacat's `log10`, including the nudge it adds to steer rounding."""
function slog10(x)
    result = log(float(x)) / log(10.0)
    return result + sign(result) * 1e-15
end

ssum(l) = isempty(l) ? 0 : reduce(+, l)

# NB: `map(*, weights, values)` built a fresh array on every call, and this is
# called for every workspace structure on every update cycle -- it was the single
# largest allocation site in a run. Reducing a generator instead folds the same
# products in the same left-to-right order, so the exactness of the result is
# unchanged (which the probes check to the numerator), with nothing allocated.
# Pass TUPLES rather than array literals at the hot call sites and the whole
# call becomes allocation-free.
function weighted_average(values, weights)
    s = ssum(weights)
    s == 0 && return 0
    isempty(weights) && return sdiv(0, s)
    return sdiv(reduce(+, (w * v for (w, v) in zip(weights, values))), s)
end
