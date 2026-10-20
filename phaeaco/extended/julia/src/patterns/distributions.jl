# The two distributions pattern-matching needs (§8.2): the normal (for
# numerosity, Eqs. 8.4–8.6) and Student's t (for features, Eqs. 8.2–8.3).
# The thesis evaluates the t integral by Gauss–Legendre quadrature; we use
# the regularised incomplete beta function, which gives the same numbers to
# far more digits (checked in the tests against tabled values).

"""erf, by Abramowitz & Stegun 7.1.26 (|error| < 1.5e-7)."""
function erf_as(x::Float64)
    s = sign(x)
    x = abs(x)
    t = 1 / (1 + 0.3275911x)
    y = 1 - (((((1.061405429t - 1.453152027)t) + 1.421413741)t - 0.284496736)t + 0.254829592)t * exp(-x * x)
    return s * y
end

"""P(|Z| < z) for a standard normal Z: the probability that two populations differ (§7.3.2)."""
normal_two_sided(z::Float64) = erf_as(abs(z) / sqrt(2))

"""log Γ(x) by the Lanczos approximation (g = 7, n = 9)."""
function lgamma_l(x::Float64)
    if x < 0.5
        return log(π / abs(sin(π * x))) - lgamma_l(1 - x)
    end
    g = 7.0
    c = (0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
         -176.61502916214059, 12.507343278686905, -0.13857109526572012,
         9.9843695780195716e-6, 1.5056327351493116e-7)
    x -= 1
    a = c[1]
    t = x + g + 0.5
    for i in 1:8
        a += c[i+1] / (x + i)
    end
    return 0.5 * log(2π) + (x + 0.5) * log(t) - t + log(a)
end

"""Continued fraction for the incomplete beta function (Numerical Recipes betacf)."""
function _betacf(a::Float64, b::Float64, x::Float64)
    qab, qap, qam = a + b, a + 1, a - 1
    c, d = 1.0, 1 - qab * x / qap
    abs(d) < 1e-300 && (d = 1e-300)
    d = 1 / d
    h = d
    for m in 1:300
        m2 = 2m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1 + aa * d; abs(d) < 1e-300 && (d = 1e-300)
        c = 1 + aa / c; abs(c) < 1e-300 && (c = 1e-300)
        d = 1 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1 + aa * d; abs(d) < 1e-300 && (d = 1e-300)
        c = 1 + aa / c; abs(c) < 1e-300 && (c = 1e-300)
        d = 1 / d
        del = d * c
        h *= del
        abs(del - 1) < 3e-14 && break
    end
    return h
end

"""Regularised incomplete beta I_x(a, b)."""
function betainc_reg(a::Float64, b::Float64, x::Float64)
    x <= 0 && return 0.0
    x >= 1 && return 1.0
    lbt = lgamma_l(a + b) - lgamma_l(a) - lgamma_l(b) + a * log(x) + b * log(1 - x)
    if x < (a + 1) / (a + b + 2)
        return exp(lbt) * _betacf(a, b, x) / a
    else
        return 1 - exp(lbt) * _betacf(b, a, 1 - x) / b
    end
end

"""
P(|T| < t) for Student's t with ν degrees of freedom: the area of Eq. 8.2,
"the probability that f1 comes from a different population".
"""
function t_two_sided(t::Float64, ν::Float64)
    ν <= 0 && return t == 0 ? 0.0 : 1.0
    isinf(t) && return 1.0
    x = ν / (ν + t * t)
    return 1 - betainc_reg(ν / 2, 0.5, x)
end
