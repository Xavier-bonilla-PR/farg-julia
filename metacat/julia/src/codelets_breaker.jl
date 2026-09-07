# Ported from Metacat's breakers.ss.
#
# The breaker is the model's capacity to change its mind. It picks a structure
# at random and tries to destroy it, weighted by how WEAK the structure is and
# how hot the model is. At low temperature it almost never fires at all; at high
# temperature it tears down freely. That is what keeps the model from committing
# early to a reading it cannot get out of.
#
# Rules are exempt: they are not part of the perceptual structure the breaker
# works on.

"""`breaker` — try to destroy one structure.

Two nested stochastic decisions. The first is the temperature gate, phrased
backwards: it FIZZLES with probability `(100 - temperature)/100`, so a cold
model rarely gets past it. The second is the structure's own weakness.

The bond-inside-a-group case is special: breaking such a bond would leave the
group standing on nothing, so the two weaknesses are multiplied and BOTH go —
`stochastic-if*` runs every form of its body, and the group is broken before
the bond it rests on."""
function breaker(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    # stochastic-if* ALWAYS draws
    random_real(ctx.rng, 1.0) < pct(sub_from_100(ctx.temperature)) && return
    breakable = Any[s for s in get_structures(ctx) if !(s isa Rule)]
    isempty(breakable) && return
    structure = random_pick(ctx.rng, breakable)
    structure === nothing && return
    enclosing_group = structure.enclosing_group
    if structure isa Bond && enclosing_group !== nothing
        p1 = temp_adjusted_probability(pct(get_weakness(structure)))
        p2 = temp_adjusted_probability(pct(get_weakness(enclosing_group::Group)))
        if random_real(ctx.rng, 1.0) < p1 * p2
            break_group!(enclosing_group::Group, net, ctx)
            break_bond!(structure::Bond, net)
        end
        return
    end
    random_real(ctx.rng, 1.0) <
        temp_adjusted_probability(pct(get_weakness(structure))) || return
    if structure isa Bond
        break_bond!(structure::Bond, net)
    elseif structure isa Group
        break_group!(structure::Group, net, ctx)
    elseif structure isa Bridge
        break_bridge!(structure::Bridge, ctx)
    end
    return
end

register_codelet_type!(:breaker, breaker)
