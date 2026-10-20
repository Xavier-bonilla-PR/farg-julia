# Two kinds of reminding, compared (X18). PhaeacoX's (X14) comes before an
# answer, from how a problem looks; Metacat's comes after, from what the
# answer is (Marshall 1999, §5.2.3). Bongard's problems are solved in order,
# one context carried through, and for every pair of solved problems this
# writes how alike they LOOK (the distance between their cores, X14) and how
# alike their ANSWERS are (Metacat's reminding strength, X18). It also writes,
# for every recall X14 made, how alike the recalled answer and the answer
# finally found are.
#
#   julia --project=phaeaco/extended/julia phaeaco/extended/bench/run_reminding.jl SEED1 SEED2 OUT.tsv
using PhaeacoX, Printf
const P = PhaeacoX

function main(args)
    s1, s2 = parse(Int, args[1]), parse(Int, args[2])
    data = joinpath(@__DIR__, "..", "..", "data")
    bps = [P.load_bp(joinpath(data, @sprintf("bp%03d.pbm", n))) for n in 1:100]
    open(args[3], "w") do io
        println(io, "seed\tkind\told\tnew\tlook_distance\tanswer_reminding")
        for seed in s1:s2
            ctx = P.Ctx(P.load_params(), seed)
            for bp in bps
                before = copy(ctx.ltm.episodes)
                r = P.solve(bp, ctx)
                recalled = [m[1] for l in r.log for m in (match(r"reminded of (\d+)", l),) if m !== nothing]
                length(ctx.ltm.episodes) > length(before) || continue      # not solved
                new = ctx.ltm.episodes[end]
                for e in before
                    @printf(io, "%d\tpair\t%s\t%s\t%.4f\t%d\n", seed, e.name, new.name,
                            P.episode_distance(e.core, new.core), P.answer_reminding(e.answer, new.answer))
                end
                for name in recalled
                    i = findlast(e -> e.name == name, before)
                    i === nothing && continue
                    e = before[i]
                    @printf(io, "%d\trecall\t%s\t%s\t%.4f\t%d\n", seed, e.name, new.name,
                            P.episode_distance(e.core, new.core), P.answer_reminding(e.answer, new.answer))
                end
            end
        end
    end
    return 0
end

exit(main(ARGS))
