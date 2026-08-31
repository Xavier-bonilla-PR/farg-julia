# Julia counterpart of bench/metacat_util_probe.ss: same trace, same order.
include("../julia/src/pyrandom.jl")
include("../julia/src/metacat/schemenum.jl")
include("../julia/src/metacat/utilities.jl")

fmtnum(v) = v isa AbstractFloat ? string(v) :
            (v isa Rational ? string(numerator(v), "/", denominator(v)) : string(v))
emit(label, v) = println(label, "\t", is_exact(v) ? "E" : "F", "\t", fmtnum(v))
emit_bool(label, v) = println(label, "\tB\t", v ? "t" : "f")

for temp in (0, 1, 19, 36, 50, 64, 75, 100)
    TEMPERATURE[] = temp
    for p in (0.0, 0.001, 0.01, 0.05, 0.2, 0.5, 0.6, 0.9, 0.999, 1.0)
        emit("tap/$temp/$p", temp_adjusted_probability(p))
    end
end

for temp in (0, 25, 50, 75, 100)
    TEMPERATURE[] = temp
    for v in temp_adjusted_values([0, 1, 25, 50, 75, 100])
        emit("tav/$temp/$v", v)
    end
end

for n in (0, 1, 25, 50, 100, 33, 7); emit("pct/$n", pct(n)); end
for n in (0, 1, 4, 25, 99, 100, 81); emit("sqrt/$n", ssqrt(n)); end
for n in (5//2, 7//2, -5//2, 1//3, 99//100)
    emit("round/$(numerator(n))/$(denominator(n))", sround(n))
end

rng = PyRandom(20250831)
for i in 0:24; emit_bool("prob/$i", prob(rng, 0.3)); end
for i in 0:24; emit("fuzz/$i", fuzz(rng, 40)); end
for i in 0:24; emit("pick/$i", random_pick(rng, [10, 20, 30, 40, 50])); end
for i in 0:24; emit("spick/$i", stochastic_pick(rng, [10, 20, 30, 40], [1, 5, 2, 8])); end
for i in 0:24
    emit("ssel/$i", stochastic_select(rng, [(3, 100), (1, 200), (6, 300)])[2])
end
for i in 0:9
    println("sfilter/$i\tL\t(", join(stochastic_filter(rng, x -> pct(x), [10, 30, 50, 70, 90]), " "), ")")
end
