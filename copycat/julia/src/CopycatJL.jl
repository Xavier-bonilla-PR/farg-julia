"""
    CopycatJL

A Julia port of the Copycat analogy-making architecture of Hofstadter and
Mitchell, translated from the Python implementation maintained under the
FARGonautica project (`fargonauts/copycat`, itself a port of Scott Boland's
Java version of Melanie Mitchell's original Lisp).

The port is behaviour-preserving: seeded with the same integer, this and the
Python original draw the identical stream of random numbers and produce the
identical answer on every trial.
"""
module CopycatJL

export Copycat, run!, runTrial!, Answer, RunResult, avgtemp, avgtime,
       NullReporter, SimpleReporter, build_slipnet

include("pyrandom.jl")
include("types.jl")
include("randomness.jl")
include("temperature.jl")
include("formulas.jl")
include("slipnet.jl")
include("workspace.jl")
include("bond.jl")
include("group.jl")
include("correspondence.jl")
include("rule.jl")
include("workspace_core.jl")
include("coderack.jl")
include("codelets.jl")
include("run.jl")

end # module
