using Printf
using CopycatJL
const C = CopycatJL
f(x) = @sprintf("%.9f", x)
seed = parse(Int, ARGS[1]); n = parse(Int, ARGS[2])
cc = C.Copycat(rng_seed=seed)
C.resetWithStrings!(cc.workspace, ARGS[3], ARGS[4], ARGS[5])
C.useAdj!(cc.temperature, :pbest)
C.reset!(cc.coderack); C.reset!(cc.slipnet); C.reset!(cc.temperature); C.reset!(cc.workspace)
cnt = Ref(0)
while cc.workspace.finalAnswer === nothing && cnt[] < n
    C.mainLoop!(cc)
    cnt[] += 1
end
for nd in cc.slipnet.slipnodes
    println("NODE\t", nd.name, "\t", f(nd.activation), "\t", f(nd.buffer), "\t", nd.clamped)
end
w = cc.workspace
for (sn, ws) in (("I", w.initial), ("M", w.modified), ("T", w.target))
    for o in ws.objects
        kind = o isa C.Group ? "G" : "L"
        descs = sort([string(d.descriptionType.name, "=", d.descriptor.name) for d in o.descriptions])
        println("OBJ\t", sn, "\t", kind, "\t", o.leftIndex, "\t", o.rightIndex, "\t",
                o.group === nothing ? "-" : "g", "\t", o.correspondence === nothing ? "-" : "c",
                "\t", o.replacement === nothing ? "-" : "r", "\t", o.changed, "\t",
                join(descs, ","), "\t",
                f(o.rawImportance), "\t", f(o.relativeImportance), "\t",
                f(o.intraStringSalience), "\t", f(o.interStringSalience), "\t",
                f(o.totalSalience), "\t", f(o.intraStringUnhappiness), "\t",
                f(o.interStringUnhappiness), "\t", f(o.totalUnhappiness), "\t",
                f(o.totalStrength))
    end
    for b in ws.bonds
        bb = b::C.Bond
        println("BOND\t", sn, "\t", bb.leftObject.leftIndex, "-", bb.rightObject.rightIndex,
                "\t", bb.category.name, "\t",
                bb.directionCategory === nothing ? "-" : bb.directionCategory.name,
                "\t", bb.facet.name, "\t", f(bb.internalStrength), "\t",
                f(bb.externalStrength), "\t", f(bb.totalStrength))
    end
end
println("STRUCT\t", length(w.structures), "\t", length(w.objects), "\t",
        w.rule === nothing ? "-" : "rule")
println("TEMP\t", f(w.totalUnhappiness), "\t", f(w.intraStringUnhappiness), "\t",
        f(w.interStringUnhappiness))
