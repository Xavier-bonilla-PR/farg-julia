# Score the retina against synthetic ground truth (plan §1, tier 2; phase 2).
#   julia --project=phaeaco/julia phaeaco/bench/retina_score.jl [trials] [σ]
using PhaeacoJL, Random, Printf
const P = PhaeacoJL

function score(trials, σ; params=P.load_params())
    rng = Xoshiro(2024)
    results = Dict{String,Vector{Bool}}()
    rec(k, ok) = push!(get!(results, k, Bool[]), ok)
    for t in 1:trials
        # one shape per box, at a random size
        for (kind, n) in (("triangle", 3), ("quad", 4), ("pentagon", 5))
            for filled in (false, true)
                rad = 10 + 30rand(rng)
                s = P.random_polygon(rng, n, (50 + 10randn(rng), 50 + 10randn(rng)), rad; irreg=0.3, filled=filled)
                maximum(max(abs(p[1] - 50), abs(p[2] - 50)) for p in s.pts) > 45 && continue
                r = P.see(P.render([s]; rng=rng, σ=σ), params, Xoshiro(t))
                o = argmax(o -> o.ink, r.objects)
                nl = length(o.lines)
                sz = rad < 18 ? "small" : "large"
                rec("$kind $(filled ? "filled" : "outlined") $sz: sides = $n", nl == n && isempty(o.ellipses))
                rec("$kind $(filled ? "filled" : "outlined") $sz: texture", o.filled == filled)
                (filled || n > 3) || rec("$kind outlined $sz: closed interior", length(o.holes) == 1)
            end
        end
        for filled in (false, true)
            rad = 5 + 30rand(rng)
            a, b = rand(rng) < 0.5 ? (rad, rad) : (rad, rad * (0.35 + 0.4rand(rng)))
            s = P.ellipse((50.0, 50.0), a, b, π * rand(rng); filled=filled)
            r = P.see(P.render([s]; rng=rng, σ=σ), params, Xoshiro(t))
            o = argmax(o -> o.ink, r.objects)
            sz = rad < 9 ? "small" : "large"
            nm = a == b ? "circle" : "ellipse"
            rec("$nm $(filled ? "filled" : "outlined") $sz: ellipse found", length(o.ellipses) == 1)
            if length(o.ellipses) == 1
                rec("$nm $(filled ? "filled" : "outlined") $sz: circle flag", r.ellipses[o.ellipses[1]].circle == (a == b || b / a > 0.9))
            end
            rec("$nm $(filled ? "filled" : "outlined") $sz: texture", o.filled == filled)
        end
        # segments: slope and length
        L, θ = 15 + 30rand(rng), π * rand(rng)
        c = (50.0, 50.0)
        s = P.segment((c[1] - L * cos(θ), c[2] + L * sin(θ)), (c[1] + L * cos(θ), c[2] - L * sin(θ)))
        r = P.see(P.render([s]; rng=rng, σ=σ), params, Xoshiro(t))
        ls = [l for l in r.lines if l.alive]
        ok = length(ls) == 1
        rec("segment: one line", ok)
        if ok
            sl = P.slope_deg(ls[1].d)
            err = min(abs(sl - rad2deg(θ)), 180 - abs(sl - rad2deg(θ)))
            rec("segment: slope within 3°", err <= 3)
            rec("segment: length within 10%", abs(P.linelength(ls[1]) - 2L) <= 0.1 * 2L)
        end
        # a dot among figures
        s = [P.dot((30.0 + 40rand(rng), 20.0 + 10rand(rng)), 1.0 + 1.2rand(rng)), P.circle((50.0, 65.0), 15)]
        r = P.see(P.render(s; rng=rng, σ=σ), params, Xoshiro(t))
        rec("dot: found", length(r.dots) == 1)
        # X, T, V
        for (nm, segs, kind) in (("cross", [((25.0, 25.0), (75.0, 75.0)), ((25.0, 75.0), (75.0, 25.0))], :X),
                                 ("touch", [((20.0, 30.0), (80.0, 30.0)), ((50.0, 30.0), (50.0, 85.0))], :T),
                                 ("vertex", [((20.0, 80.0), (50.0, 20.0)), ((50.0, 20.0), (85.0, 75.0))], :V))
            # jitter each distinct point once, so shared points stay shared
            pts = unique(vcat([a for (a, _) in segs], [b for (_, b) in segs]))
            moved = Dict(p => (p[1] + 3randn(rng), p[2] + 3randn(rng)) for p in pts)
            sh = [P.segment(moved[a], moved[b]) for (a, b) in segs]
            if kind == :T      # keep the stem's foot on the bar
                (a, b) = (sh[1].pts[1], sh[1].pts[2])
                u = 0.3 + 0.4rand(rng)
                foot = (a[1] + u * (b[1] - a[1]), a[2] + u * (b[2] - a[2]))
                sh[2] = P.segment(foot, sh[2].pts[2])
            end
            r = P.see(P.render(sh; rng=rng, σ=σ), params, Xoshiro(t))
            rec("$nm: one $kind junction", length(r.junctions) == 1 && r.junctions[1].kind == kind &&
                                            count(l -> l.alive, r.lines) == 2)
        end
    end
    return results
end

trials = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 30
σ = length(ARGS) >= 2 ? parse(Float64, ARGS[2]) : 0.0
res = score(trials, σ)
@printf("retina score, %d trials, wobble σ = %.2f\n", trials, σ)
for k in sort!(collect(keys(res)))
    v = res[k]
    @printf("  %-48s %5.1f%%  (%d)\n", k, 100 * count(v) / length(v), length(v))
end
