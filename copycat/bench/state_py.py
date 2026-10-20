import sys
sys.path.insert(0, 'python')
from copycat.copycat import Copycat
from copycat.group import Group
f = lambda x: '%.9f' % x
seed = int(sys.argv[1]); n = int(sys.argv[2])
cc = Copycat(rng_seed=seed)
cc.workspace.resetWithStrings(sys.argv[3], sys.argv[4], sys.argv[5])
cc.temperature.useAdj('pbest')
cc.coderack.reset(); cc.slipnet.reset(); cc.temperature.reset(); cc.workspace.reset()
count = 0
while cc.workspace.finalAnswer is None and count < n:
    cc.mainLoop()
    count += 1
for nd in cc.slipnet.slipnodes:
    print('NODE\t%s\t%s\t%s\t%s' % (nd.name, f(nd.activation), f(nd.buffer), str(nd.clamped).lower()))
w = cc.workspace
for sn, ws in (('I', w.initial), ('M', w.modified), ('T', w.target)):
    for o in ws.objects:
        kind = 'G' if isinstance(o, Group) else 'L'
        descs = sorted('%s=%s' % (d.descriptionType.name, d.descriptor.name) for d in o.descriptions)
        print('OBJ\t%s\t%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' % (
            sn, kind, o.leftIndex, o.rightIndex,
            '-' if o.group is None else 'g', '-' if o.correspondence is None else 'c',
            '-' if o.replacement is None else 'r', str(o.changed).lower(), ','.join(descs),
            f(o.rawImportance), f(o.relativeImportance), f(o.intraStringSalience),
            f(o.interStringSalience), f(o.totalSalience), f(o.intraStringUnhappiness),
            f(o.interStringUnhappiness), f(o.totalUnhappiness), f(o.totalStrength)))
    for b in ws.bonds:
        print('BOND\t%s\t%d-%d\t%s\t%s\t%s\t%s\t%s\t%s' % (
            sn, b.leftObject.leftIndex, b.rightObject.rightIndex, b.category.name,
            '-' if b.directionCategory is None else b.directionCategory.name, b.facet.name,
            f(b.internalStrength), f(b.externalStrength), f(b.totalStrength)))
print('STRUCT\t%d\t%d\t%s' % (len(w.structures), len(w.objects), '-' if w.rule is None else 'rule'))
print('TEMP\t%s\t%s\t%s' % (f(w.totalUnhappiness), f(w.intraStringUnhappiness), f(w.interStringUnhappiness)))
