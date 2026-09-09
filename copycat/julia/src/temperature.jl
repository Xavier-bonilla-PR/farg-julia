# Mirrors copycat/temperature.py, including the whole family of alternative
# getAdjustedProbability formulas that LSaldyt's fork experiments with.

_original(temp, prob) = begin
    (prob == 0 || prob == 0.5 || temp == 0) && return prob
    prob < 0.5 && return 1.0 - _original(temp, 1.0 - prob)
    coldness = 100.0 - temp
    a = sqrt(coldness)
    c = (10 - a) / 100
    f = (c + 1) * prob
    return max(f, 0.5)
end

_entropy(temp, prob) = begin
    (prob == 0 || prob == 0.5 || temp == 0) && return prob
    prob < 0.5 && return 1.0 - _original(temp, 1.0 - prob)
    coldness = 100.0 - temp
    a = sqrt(coldness)
    c = (10 - a) / 100
    f = (c + 1) * prob
    return -f * log2(f)
end

_weighted(temp, s, u) = (temp / 100) * s + ((100 - temp) / 100) * u
_weighted_inverse(temp, prob) = _weighted(temp, 1 - prob, prob)
_fifty_converge(temp, prob) = _weighted(temp, 0.5, prob)
_soft_curve(temp, prob) = min(1, _weighted(temp, (1.5 - prob) / 2, prob))

function _weighted_soft_curve(temp, prob)
    weight = 100
    gamma = 0.5   # convergence value
    alpha = 1     # gamma weight
    beta = 3      # iprob weight
    return min(1, (temp / weight) * ((alpha * gamma + beta * (1 - prob)) / (alpha + beta)) +
                  ((weight - temp) / weight) * prob)
end

_alt_fifty(temp, prob) = _weighted(temp, 0.5, prob < 0.5 ? prob^2 : sqrt(prob))
_averaged_alt(temp, prob) = _weighted(temp, (1.5 - prob) / 2, prob < 0.5 ? prob^2 : sqrt(prob))

function _working_best(temp, prob)
    r = 1.05
    return _weighted(temp, 0.5, prob < 0.5 ? prob^r : prob^(1 / r))
end
const _soft_best = _working_best

function _parameterized_best(temp, prob)
    alpha = 5
    beta = 1
    s = (alpha * prob + beta * 0.5) / (alpha + beta)
    r = 1.05
    u = prob < 0.5 ? prob^r : prob^(1 / r)
    return _weighted(temp, s, u)
end

function _meta(temp, prob)
    r = _weighted(temp, 1, 2)   # make r a function of temperature
    u = prob < 0.5 ? prob^r : prob^(1 / r)
    return _weighted(temp, 0.5, u)
end

function _meta_parameterized(temp, prob)
    r = _weighted(temp, 1, 2)
    alpha = 5
    beta = 1
    s = (alpha * prob + beta * 0.5) / (alpha + beta)
    u = prob < 0.5 ? prob^r : prob^(1 / r)
    return _weighted(temp, s, u)
end

_none(temp, prob) = prob

const ADJUSTMENT_FORMULAS = (
    :original, :entropy, :inverse, :fifty_converge, :soft, :weighted_soft,
    :alt_fifty, :average_alt, :best, :sbest, :pbest, :meta, :pmeta, :none)

function apply_formula(kind::Symbol, temp::Float64, prob::Float64)
    kind === :pbest          && return _parameterized_best(temp, prob)
    kind === :inverse        && return _weighted_inverse(temp, prob)
    kind === :original       && return _original(temp, prob)
    kind === :entropy        && return _entropy(temp, prob)
    kind === :fifty_converge && return _fifty_converge(temp, prob)
    kind === :soft           && return _soft_curve(temp, prob)
    kind === :weighted_soft  && return _weighted_soft_curve(temp, prob)
    kind === :alt_fifty      && return _alt_fifty(temp, prob)
    kind === :average_alt    && return _averaged_alt(temp, prob)
    kind === :best           && return _working_best(temp, prob)
    kind === :sbest          && return _soft_best(temp, prob)
    kind === :meta           && return _meta(temp, prob)
    kind === :pmeta          && return _meta_parameterized(temp, prob)
    kind === :none           && return _none(temp, prob)
    throw(ArgumentError("unknown adjustment formula $kind"))
end

function reset!(t::Temperature)
    t.history = [100.0]
    t.actual_value = 100.0
    t.last_unclamped_value = 100.0
    t.clamped = true
    t.clampTime = 30
    return t
end

function update!(t::Temperature, value::Float64)
    t.last_unclamped_value = value
    if t.clamped
        t.actual_value = 100.0
    else
        push!(t.history, value)
        t.actual_value = value
    end
    return t
end

function clampUntil!(t::Temperature, when::Int)
    t.clamped = true
    t.clampTime = when
    # but do not modify actual_value until someone calls update!
end

function tryUnclamp!(t::Temperature, currentTime::Int)
    if t.clamped && currentTime >= t.clampTime
        t.clamped = false
    end
end

value(t::Temperature) = t.clamped ? 100.0 : t.actual_value

getAdjustedValue(t::Temperature, v::Real) = Float64(v)^(((100.0 - value(t)) / 30.0) + 0.5)

function getAdjustedProbability(t::Temperature, v::Real)
    prob = Float64(v)
    adjusted = apply_formula(t.adjustmentType, value(t), prob)
    t.diffs += abs(adjusted - prob)
    t.ndiffs += 1
    return adjusted
end

getAverageDifference(t::Temperature) = t.diffs / t.ndiffs
useAdj!(t::Temperature, adj::Symbol) = (t.adjustmentType = adj)
