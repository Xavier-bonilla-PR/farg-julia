# Reproduce the method of Table 8.1 (§8.3.4): the Patterns algorithm against
# leader, Lu & Fu and k-means on one-dimensional exemplars in [0, 1] that form
# groups unambiguously, each threshold-based algorithm at its best threshold.
#
#   julia --project=phaeaco/extended/julia phaeaco/extended/bench/clustering.jl [cases]
#
# The thesis does not publish its test cases or its performance index, so
# both are ours: k = 1–4 clusters of 3–12 exemplars, spreads 0.01–0.06,
# centres at least 0.28 apart; the index is the Rand index × 100 (agreement on
# every pair of exemplars: same group or not). The comparison, not the exact
# figures, is what is reproduced. DECISIONS D27.

using PhaeacoX, Random, Printf
const P = PhaeacoX

function make_case(rng; sep=0.28, σmax=0.06)
    k = rand(rng, 1:4)
    σs = [0.01 + (σmax - 0.01) * rand(rng) for _ in 1:k]
    # centres at least `sep` apart: lay out the minimum gaps, share the slack at random
    slack = 0.9 - (k - 1) * sep
    shares = rand(rng, k + 1); shares ./= sum(shares)
    centres = Float64[]
    pos = 0.05 + slack * shares[1]
    for i in 1:k
        push!(centres, pos)
        pos += sep + slack * shares[i+1]
    end
    xs, labels = Float64[], Int[]
    for (i, c) in enumerate(centres)
        σ = σs[i]
        for _ in 1:rand(rng, 3:12)
            push!(xs, clamp(c + σ * randn(rng), 0.0, 1.0)); push!(labels, i)
        end
    end
    perm = randperm(rng, length(xs))
    return xs[perm], labels[perm], k
end

function rand_index(assign, labels)
    n = length(labels)
    agree = total = 0
    for i in 1:n, j in i+1:n
        total += 1
        agree += (assign[i] == assign[j]) == (labels[i] == labels[j])
    end
    return total == 0 ? 100.0 : 100 * agree / total
end

sim(a, b) = exp(-abs(a - b))           # Eq. 8.8 with d = |Δ| (Eq. 8.1, max 1)

function patterns_alg(xs, thr, M)
    ex = [begin r = P.RNode(:item); r.feats[:value] = P.Stats(x); r end for x in xs]
    groups = P.find_patterns(M, ex; threshold=thr)
    assign = zeros(Int, length(xs))
    for (g, grp) in enumerate(groups), m in grp.members
        assign[m] = g
    end
    return assign
end

function leader_alg(xs, thr)
    centres, counts = Float64[], Int[]
    assign = Int[]
    for x in xs
        best = isempty(centres) ? 0 : argmax(c -> sim(c, x), centres) |> c -> findfirst(==(c), centres)
        if best == 0 || sim(centres[best], x) <= thr
            push!(centres, x); push!(counts, 1); push!(assign, length(centres))
        else
            counts[best] += 1
            centres[best] += (x - centres[best]) / counts[best]
            push!(assign, best)
        end
    end
    return assign
end

function lufu_alg(xs, thr)
    assign = Int[]
    nextc = 0
    for (i, x) in enumerate(xs)
        if i == 1
            nextc += 1; push!(assign, nextc); continue
        end
        j = argmax(j -> sim(xs[j], x), 1:i-1)
        if sim(xs[j], x) > thr
            push!(assign, assign[j])
        else
            nextc += 1; push!(assign, nextc)
        end
    end
    return assign
end

function kmeans_alg(xs, k, rng; iters=50)
    centres = xs[randperm(rng, length(xs))[1:min(k, length(xs))]]
    assign = zeros(Int, length(xs))
    for _ in 1:iters
        for (i, x) in enumerate(xs)
            assign[i] = argmin(c -> abs(centres[c] - x), eachindex(centres))
        end
        for c in eachindex(centres)
            m = [x for (x, a) in zip(xs, assign) if a == c]
            isempty(m) || (centres[c] = sum(m) / length(m))
        end
    end
    return assign
end

function run_benchmark(ncases; seed=8, sep=0.28, σmax=0.06)
    params = P.load_params()
    ltm = P.LTM()
    P.add_concept!(ltm, :value, :feature; feature=P.FeatureInfo(1.0, 0.0, false, false), P=params)
    P.add_concept!(ltm, :numerosity, :numerosity; P=params)
    M = P.Matcher(ltm, 0, params[:numerosity_sigma0], params[:match_damping],
                  Int(params[:match_maxdepth]), params[:match_sfloor], false)
    Mlit = P.Matcher(ltm, 0, params[:numerosity_sigma0], params[:match_damping],
                     Int(params[:match_maxdepth]), params[:match_sfloor], true)
    rng = Xoshiro(seed)
    cases = [make_case(rng; sep=sep, σmax=σmax) for _ in 1:ncases]
    thresholds = 0.74:0.01:0.94
    results = Dict{String,Any}()
    for (name, alg) in (("Patterns", (xs, t) -> patterns_alg(xs, t, M)),
                        ("Patterns, literal", (xs, t) -> patterns_alg(xs, t, Mlit)),
                        ("leader", leader_alg), ("Lu&Fu", lufu_alg))
        scores = [[rand_index(alg(xs, t), lab) for (xs, lab, _) in cases] for t in thresholds]
        means = [sum(s) / length(s) for s in scores]
        b = argmax(means)
        sd = sqrt(sum((x - means[b])^2 for x in scores[b]) / (length(scores[b]) - 1))
        tol = [thresholds[i] for i in eachindex(means) if means[i] >= means[b] - 1.5]
        results[name] = (means[b], sd, thresholds[b], minimum(tol), maximum(tol))
    end
    krng = Xoshiro(seed + 1)
    for (name, kf) in (("k-means (k = 3)", _ -> 3), ("k-means (true k)", k -> k))
        s = [rand_index(kmeans_alg(xs, kf(k), krng), lab) for (xs, lab, k) in cases]
        m = sum(s) / length(s)
        results[name] = (m, sqrt(sum((x - m)^2 for x in s) / (length(s) - 1)), NaN, NaN, NaN)
    end
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    n = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 400
    thesis = Dict("Patterns" => "98.5 ± 7, thr 0.83 (0.78–0.88)", "Patterns, literal" => "—",
                  "leader" => "92.9 ± 16, thr 0.82 (0.78–0.85)",
                  "Lu&Fu" => "78.8 ± 28, thr 0.85 (0.81–0.88)", "k-means (k = 3)" => "54.7 ± 36",
                  "k-means (true k)" => "—")
    for (label, sep, σmax) in (("well separated: gaps ≥ 0.28, spreads 0.01–0.06", 0.28, 0.06),
                               ("harder: gaps ≥ 0.22, spreads 0.01–0.08", 0.22, 0.08))
        res = run_benchmark(n; sep=sep, σmax=σmax)
        @printf("Table 8.1 reproduction, %d cases, %s (thesis figures in brackets)\n", n, label)
        for name in ("Patterns", "Patterns, literal", "leader", "Lu&Fu", "k-means (k = 3)", "k-means (true k)")
            m, sd, t, lo, hi = res[name]
            thr = isnan(t) ? "" : @sprintf(", thr %.2f (%.2f–%.2f)", t, lo, hi)
            @printf("  %-18s %5.1f ± %4.1f%-24s [%s]\n", name, m, sd, thr, thesis[name])
        end
    end
end
