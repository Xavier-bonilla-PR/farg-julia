"""Emits one line per codelet: run index, codelet name, RNG draws consumed so far."""
import random, sys
sys.path.insert(0, 'python')
sys.setrecursionlimit(10000)

class CountingRandom(random.Random):
    n = 0
    def random(self):
        self.n += 1
        return super().random()
    def getrandbits(self, k):
        self.n += 1
        return super().getrandbits(k)

from copycat.copycat import Copycat
import copycat.randomness as rnd

seed = int(sys.argv[1]); limit = int(sys.argv[2])
initial, modified, target = sys.argv[3], sys.argv[4], sys.argv[5]

cc = Copycat(rng_seed=seed)
cc.random.rng = CountingRandom(seed)
cc.workspace.resetWithStrings(initial, modified, target)
cc.temperature.useAdj('pbest')
cc.coderack.reset(); cc.slipnet.reset(); cc.temperature.reset(); cc.workspace.reset()
count = 0
out = sys.stdout
while cc.workspace.finalAnswer is None and count < limit:
    currentTime = cc.coderack.codeletsRun
    cc.temperature.tryUnclamp(currentTime)
    n0 = cc.random.rng.n
    if currentTime >= cc.lastUpdate + 5:
        cc.update_workspace(currentTime)
    n1 = cc.random.rng.n
    if not len(cc.coderack.codelets):
        cc.coderack.postInitialCodelets()
    cl = cc.coderack.chooseCodeletToRun()
    n2 = cc.random.rng.n
    cc.coderack.codeletsRun += 1
    try:
        cc.coderack.methods[cl.name](cc.coderack.ctx, cl)
    except AssertionError:
        pass
    n3 = cc.random.rng.n
    out.write('%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\n' % (currentTime, cl.name, n0, n1, n2, n3,
              len(cc.coderack.codelets), len(cc.workspace.structures)))
    count += 1
