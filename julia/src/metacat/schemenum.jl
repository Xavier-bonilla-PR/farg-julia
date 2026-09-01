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

"""Write a Scheme number the way Chez does: a ratio is `400/3`, not Julia's
`400//3`. Probe output has to go through this wherever an exact rational can
reach the trace."""
swrite(x::Rational) = string(numerator(x), "/", denominator(x))
swrite(x) = string(x)

"""`(^2 x)` and `(^3 x)`."""
square(x) = x * x
cube(x) = x * x * x

ssum(l) = isempty(l) ? 0 : reduce(+, l)

function weighted_average(values, weights)
    s = ssum(weights)
    s == 0 && return 0
    return sdiv(ssum(map(*, weights, values)), s)
end
