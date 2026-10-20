# Comparing two quantities by the accumulator (§7.3.2): draw samples from the
# two Gaussians N(n, σ₀√n) the accumulator would produce, test whether they
# come from different populations, and keep drawing — one more sample each,
# one more unit of reaction time — until the test is confident or an upper
# bound says "about equal". The reaction times this yields follow the trend
# of Welford's formula, RT = a + k·log(L / (L − S)) (Eq. 7.1).

"""
    compare_counts(L, S, σ0, rng; m=12, maxrt=300, confidence=0.99) -> (differ, rt)

`differ` is false if the bound was reached ("the numerosity appears about
equal").
"""
function compare_counts(L::Real, S::Real, σ0::Real, rng::AbstractRNG;
                        m::Int=12, maxrt::Int=300, confidence::Float64=0.99)
    sL, sS = σ0 * sqrt(L), σ0 * sqrt(S)
    sumL = sum(L + sL * randn(rng) for _ in 1:m)
    sumS = sum(S + sS * randn(rng) for _ in 1:m)
    n = m
    while true
        z = (sumL / n - sumS / n) / sqrt((sL^2 + sS^2) / n)
        normal_two_sided(z) > confidence && return (true, n)
        n >= maxrt && return (false, n)
        sumL += L + sL * randn(rng)
        sumS += S + sS * randn(rng)
        n += 1
    end
end
