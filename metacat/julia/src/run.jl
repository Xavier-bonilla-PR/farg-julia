# Ported from Metacat's run.ss and formulas.ss — the per-cycle update.
#
# `update-everything` is what happens BETWEEN codelets: the workspace revalues
# itself, the trace decides whether a snag or clamp has run its course, the
# themespace is boosted by the bridges and then settles, the slipnet spreads,
# the temperature is recomputed, and the coderack is refilled. Everything in the
# model that is not a codelet running happens here.
#
# The order matters and is not arbitrary. Structures are revalued before the
# trace is consulted, because the trace's progress evaluators read structure
# strengths. Bridges boost themes before the themespace settles, so a bridge
# built this cycle counts. The temperature is recomputed before the rack is
# refilled, because how many codelets to post depends on it.
#
# The run LOOP itself (`run-until-answer`, the suspend/resume machinery and the
# GUI's stepping) is not here — it belongs with the rest of run.ss.

"""`(update-temperature)` — 70% how unhappy the workspace is, 30% whether a
supported rule exists at all. A snag CLAMPS the temperature at 100, and while
clamped this does nothing."""
function update_temperature!(ctx)
    ctx.temperature_clamped && return ctx
    rule_factor = (JUSTIFY_MODE[] ?
                   (rule_possible(ctx, :top) && supported_rule_exists(ctx, :top) &&
                    rule_possible(ctx, :bottom) && supported_rule_exists(ctx, :bottom)) :
                   (rule_possible(ctx, :top) && supported_rule_exists(ctx, :top))) ?
                  0 : 100
    ctx.temperature = sround(weighted_average(
        [get_average_unhappiness(ctx), rule_factor], [70, 30]))
    return ctx
end

"""`(post-initial-codelets)` — the standing start, and what `process-snag` falls
back to after wiping the rack: two bond scouts and two bridge scouts per object,
all deferred and then posted together."""
function post_initial_codelets!(ctx)
    n = 2 * length(workspace_objects(ctx))
    for _ in 1:n
        add_deferred_codelet!(ctx.coderack,
                              make_codelet(CODELET_TYPES[:bottom_up_bond_scout],
                                           VERY_LOW_URGENCY))
        add_deferred_codelet!(ctx.coderack,
                              make_codelet(CODELET_TYPES[:bottom_up_bridge_scout],
                                           VERY_LOW_URGENCY))
    end
    post_deferred_codelets!(ctx.coderack, ctx.codelet_count, ctx.rng,
                            ctx.temperature, ctx)
    return ctx
end

"""`(update-everything)` — one cycle's worth of everything that is not a codelet.

The two trace clauses are how a detour ends. A snag period ends stochastically,
with probability equal to the progress made since the snag, so the better things
have been going the sooner the model stops worrying about it. A clamp period
ends on a timer."""
function update_everything!(ctx)
    check_if_rules_possible!(ctx)
    update_workspace_values!(ctx)
    tr = ctx.trace
    if tr !== nothing
        if (tr::TemporalTrace).within_snag_period
            progress = progress_since_last_snag(tr::TemporalTrace, ctx)
            # stochastic-if* ALWAYS draws, unlike prob?
            if random_real(ctx.rng, 1.0) < pct(progress)
                undo_snag_condition!(tr::TemporalTrace, ctx)
            end
        end
        if clamp_period_expired(tr::TemporalTrace, ctx)
            undo_last_clamp!(tr::TemporalTrace, ctx)
        end
    end
    spread_activation_to_themespace!(ctx)
    spread_activation!(ctx.themespace)
    update_slipnet_activations!(ctx.net, ctx.rng, ctx.themespace, ctx)
    update_temperature!(ctx)
    add_bottom_up_codelets!(ctx)
    add_top_down_codelets!(ctx)
    post_deferred_codelets!(ctx.coderack, ctx.codelet_count, ctx.rng,
                            ctx.temperature, ctx)
    return ctx
end
