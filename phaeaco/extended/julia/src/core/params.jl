# Parameters (§7.4.1).
#
# "No parameter in Phaeaco's architecture is a true constant ... All parameters
# that represent decision thresholds are normal distributions N(µ, σ), where µ
# corresponds to the traditional value of a constant, and σ is very small."
#
# A `Thr` is such a distribution. Every decision samples it afresh, so the same
# borderline input can go either way on different looks. Parameters that are
# not decision thresholds (sizes, counts, rates) are plain numbers.
#
# All values live in one TOML file, `params.toml`, so calibration (phase 9)
# never edits code.

"""A decision threshold: a normal distribution sampled at every decision."""
struct Thr
    mu::Float64
    sigma::Float64
end

"""Draw one value of the threshold."""
sample(t::Thr, rng::AbstractRNG) = t.sigma == 0.0 ? t.mu : t.mu + t.sigma * randn(rng)

"""Does `x` exceed a fresh draw of the threshold?"""
exceeds(x::Real, t::Thr, rng::AbstractRNG) = x > sample(t, rng)

struct Params
    thr::Dict{Symbol,Thr}
    num::Dict{Symbol,Float64}
end

function Base.getindex(p::Params, k::Symbol)
    haskey(p.num, k) && return p.num[k]
    throw(KeyError(k))
end
thr(p::Params, k::Symbol) = p.thr[k]

const DEFAULT_PARAMS_PATH = joinpath(@__DIR__, "..", "..", "params.toml")

"""
    load_params(path=params.toml; overrides...)

Read the parameter file. A table `{mu = .., sigma = ..}` becomes a `Thr`; a
bare number stays a number. Keyword overrides replace single entries, which
is how tests and calibration sweeps change one knob.
"""
function load_params(path::AbstractString=DEFAULT_PARAMS_PATH; overrides...)
    raw = TOML.parsefile(path)
    thr = Dict{Symbol,Thr}()
    num = Dict{Symbol,Float64}()
    function walk(d, prefix)
        for (k, v) in d
            # keys under [top] are not prefixed
            key = isempty(prefix) || prefix == "top" ? k : string(prefix, "_", k)
            if v isa AbstractDict && haskey(v, "mu")
                thr[Symbol(key)] = Thr(Float64(v["mu"]), Float64(get(v, "sigma", 0.0)))
            elseif v isa AbstractDict
                walk(v, key)
            elseif v isa Real
                num[Symbol(key)] = Float64(v)
            end
        end
    end
    walk(raw, "")
    for (k, v) in overrides
        if v isa Thr
            thr[k] = v
        elseif haskey(thr, k)
            thr[k] = Thr(Float64(v), thr[k].sigma)
        else
            num[k] = Float64(v)
        end
    end
    return Params(thr, num)
end
