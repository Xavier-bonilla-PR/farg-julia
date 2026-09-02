# Emits one line per codelet: run index, codelet name, RNG draws consumed so far.
using Printf
using CopycatJL
rpad_fixed(x) = @sprintf("%.4f", x)
const C = CopycatJL

seed = parse(Int, ARGS[1]); n = parse(Int, ARGS[2])
initial, modified, target = ARGS[3], ARGS[4], ARGS[5]

cc = C.Copycat(rng_seed=seed)
io = stdout
C.resetWithStrings!(cc.workspace, initial, modified, target)
C.useAdj!(cc.temperature, :pbest)
C.reset!(cc.coderack); C.reset!(cc.slipnet); C.reset!(cc.temperature); C.reset!(cc.workspace)
cnt = Ref(0)
while cc.workspace.finalAnswer === nothing && cnt[] < n
    currentTime = cc.coderack.codeletsRun
    C.tryUnclamp!(cc.temperature, currentTime)
    n0 = cc.random.rng.ncalls
    if currentTime >= cc.lastUpdate + 5
        C.update_workspace!(cc, currentTime)
    end
    n1 = cc.random.rng.ncalls
    if isempty(cc.coderack.codelets)
        C.postInitialCodelets!(cc.coderack)
    end
    cl = C.chooseCodeletToRun!(cc.coderack)
    n2 = cc.random.rng.ncalls
    cc.coderack.codeletsRun += 1
    C.dispatch_codelet(cc, cl)
    n3 = cc.random.rng.ncalls
    println(io, currentTime, "\t", cl.name, "\t", n0, "\t", n1, "\t", n2, "\t", n3,
            "\t", length(cc.coderack.codelets), "\t", length(cc.workspace.structures))
    cnt[] += 1
end
