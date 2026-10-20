# Activation (§7.2) and significance (§9.3.1).
#
# An activation is a position on a discrete axis of `steps` marks. Its value is
# f(pos/steps) for a sigmoid f. The only way up is "advance to the next mark";
# the only way down is time: every `period` clock ticks it slips back one mark.
# The number of marks is the activation's *stability* — more marks, slower
# decay from the top.
#
# f is the thesis's cheap sigmoid (Fig. 7.19): a hyperbola piece rising from
# (0, l), a straight middle, and the mirror image of the first piece falling
# into (1, 1 − l), where l is the *limiting activation*. Values never reach 0
# or 1. The thesis leaves the pieces' parameters open; we choose them so the
# three parts join with matching slope (see DECISIONS.md, D2).

"""The three-piece sigmoid, precomputed. Built once per (x1, y1, l)."""
struct Sigmoid
    x1::Float64     # end of the lower hyperbola piece; the upper starts at 1 − x1
    y1::Float64     # f(x1)
    l::Float64      # limiting activation: f(0) = l, f(1) = 1 − l
    m::Float64      # slope of the linear middle
    a::Float64      # lower piece: f(x) = c + 1 / (b − a·x)
    b::Float64
    c::Float64
end

function Sigmoid(x1::Float64=0.25, y1::Float64=0.1, l::Float64=0.001)
    0 < x1 < 0.5 && l < y1 < 0.5 || throw(ArgumentError("bad sigmoid shape"))
    m = (1 - 2y1) / (1 - 2x1)
    # Solve c + 1/b = l, c + 1/(b − a·x1) = y1, a/(b − a·x1)² = m.
    # With u = b − a·x1 and k = b/u this reduces to k = m·x1/(y1 − l),
    # u = (k − 1)/((y1 − l)·k). k > 1 is what makes the piece convex.
    k = m * x1 / (y1 - l)
    k > 1 || throw(ArgumentError("sigmoid middle too shallow for a convex start"))
    u = (k - 1) / ((y1 - l) * k)
    b = k * u
    a = (b - u) / x1
    c = l - 1 / b
    return Sigmoid(x1, y1, l, m, a, b, c)
end

function (s::Sigmoid)(x::Float64)
    if x <= s.x1
        return s.c + 1 / (s.b - s.a * x)
    elseif x < 1 - s.x1
        return s.y1 + s.m * (x - s.x1)
    else
        return 1 - (s.c + 1 / (s.b - s.a * (1 - x)))
    end
end

const DEFAULT_SIGMOID = Sigmoid()

"""
    Activation(steps, period; pos=steps)

An activation with `steps` marks that loses one mark every `period` ticks.
New activations start at the top, as new Workspace nodes do (§7.2).
"""
mutable struct Activation
    pos::Int
    steps::Int
    period::Int
    last::Int       # clock tick at which `pos` was last brought up to date
end

Activation(steps::Integer, period::Integer; pos::Integer=steps, now::Integer=0) =
    Activation(Int(pos), Int(steps), Int(period), Int(now))

"""Bring the position up to date with the clock (lazy decay)."""
function sync!(a::Activation, now::Int)
    dt = now - a.last
    if dt >= a.period
        k = dt ÷ a.period
        a.pos = max(0, a.pos - k)
        a.last = a.pos == 0 ? now : a.last + k * a.period
    end
    return a
end

value(a::Activation, now::Int, s::Sigmoid=DEFAULT_SIGMOID) =
    s(sync!(a, now).pos / a.steps)

"""Advance `n` marks. Returns true if the activation is now at its maximum."""
function boost!(a::Activation, now::Int, n::Integer=1)
    sync!(a, now)
    if a.pos == 0
        a.last = now        # the decay clock restarts when it leaves the floor
    end
    a.pos = min(a.steps, a.pos + n)
    return a.pos == a.steps
end

atmax(a::Activation, now::Int) = sync!(a, now).pos == a.steps

"""
LTM weight = significance + activation (§9.3.1).

Significance is an activation with stability orders of magnitude higher.
Each time the activation reaches its maximum, significance advances a mark;
each time significance reaches *its* maximum, its stability grows, so a
concept that keeps being used becomes both weightier and harder to forget.
"""
mutable struct Weight
    act::Activation
    sig::Activation
    growth::Int     # marks added to significance's stability when it maxes out
end

function Weight(; act_steps=20, act_period=10, sig_steps=200, sig_period=5000,
                sig_pos=0, growth=20, now=0)
    Weight(Activation(act_steps, act_period; pos=0, now=now),
           Activation(sig_steps, sig_period; pos=sig_pos, now=now), growth)
end

weight(w::Weight, now::Int) = value(w.sig, now) + value(w.act, now)

"""Prime the concept by `n` activation marks, propagating to significance."""
function prime!(w::Weight, now::Int, n::Integer=1)
    for _ in 1:n
        if boost!(w.act, now)
            if boost!(w.sig, now)
                w.sig.steps += w.growth
            end
        end
    end
    return w
end
