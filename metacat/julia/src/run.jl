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
# The run LOOP is here too, at the bottom: `init-mcat`, `step-mcat` and
# `run-mcat`. What is NOT ported is the interactive half — breakpoints, step
# mode, `go`/`rerun`, and the graphics refreshes the loop interleaves — all of
# which exist to hand control back to the SWL repl.

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


# --- the run loop (run.ss 20-231) -------------------------------------------
#
# Two things here are easy to get wrong by reading the probes rather than the
# model, because the probes drive the loop by hand.
#
# `update-everything` runs once every %update-cycle-length% CODELETS, not once
# per codelet. The model's "cycle" is fifteen codelets long.
#
# And `step-mcat` runs the codelet FIRST and increments the count afterwards,
# so the very first codelet of a run executes with `*codelet-count*` still 0.
# Every time stamp and every age in the model is measured against that count.

"""`%update-cycle-length%` — how many codelets run between updates."""
const UPDATE_CYCLE_LENGTH = 15

"""`%initial-slipnode-clamp-cycles%` — how many UPDATE CYCLES (so times fifteen
codelets) the initially-clamped slipnodes stay clamped."""
const INITIAL_SLIPNODE_CLAMP_CYCLES = 50

# %garbage-collect-cycles% is graphics-only and is not ported.

"""`(clamp-initial-slipnodes)` — pin the nodes every run starts believing in,
and record when to let them go."""
function clamp_initial_slipnodes!(ctx)
    for n in ctx.net.initially_clamped_nodes
        clamp_activation!(n, MAX_ACTIVATION, ctx)
    end
    ctx.initial_slipnode_unclamp_time =
        ctx.codelet_count + INITIAL_SLIPNODE_CLAMP_CYCLES * UPDATE_CYCLE_LENGTH
    return ctx
end

"""`(init-mcat initial modified target answer seed)` — set up a run and return
the context it runs in.

The two `set-activation` calls are `set-`, not `update-`, and the Scheme says
why: `update-activation` is monitored, and a run has not begun yet, so an
update here would put concept-activation events in the trace before the first
codelet.

`answer_sym` is justify mode: pass one and the workspace gains a fourth string,
which is what `%justify-mode%` amounts to. The flag is set from it rather than
the other way round, so the two cannot disagree."""
function init_mcat(net::Slipnet, initial_sym, modified_sym, target_sym, seed::Int;
                   answer_sym = nothing, memory = nothing, trace = nothing)
    JUSTIFY_MODE[] = answer_sym !== nothing
    rng = PyRandom(seed)
    foreach(reset!, net.nodes)
    strings = [make_workspace_string(net, :initial, initial_sym),
               make_workspace_string(net, :modified, modified_sym),
               make_workspace_string(net, :target, target_sym)]
    answer_string = answer_sym === nothing ? nothing :
                    make_workspace_string(net, :answer, answer_sym)
    answer_string === nothing || push!(strings, answer_string::WorkspaceString)
    ctx = MetacatCtx(net, rng, Coderack(), make_themespace(net),
                     strings[1], strings[2], strings[3], 100, 0;
                     answer = answer_string)
    initialize!(ctx.coderack)
    ctx.temperature_clamped = false
    ctx.trace = trace
    ctx.memory = memory
    # `(tell *memory* 'clear-activations)`. The memory itself SURVIVES a run —
    # that is what makes reminding possible — but the previous run's reminding
    # strengths do not.
    memory === nothing || clear_activations!(memory::Memory)
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    if any(s -> length(s.letters) == 1, strings)
        set_activation!(net[:plato_object_category], MAX_ACTIVATION)
    end
    for o in workspace_objects(ctx), d in o.descriptions
        set_activation!(d.descriptor, MAX_ACTIVATION)
    end
    update_workspace_values!(ctx)
    clamp_initial_slipnodes!(ctx)
    post_initial_codelets!(ctx)
    return ctx
end

"""`(step-mcat)` — one codelet. NB the increment comes AFTER the run."""
function step_mcat!(ctx)
    run_codelet!(ctx, choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature))
    ctx.codelet_count += 1
    return ctx
end

"""`(run-mcat)` — the loop. Returns why it stopped: `:answer` when a codelet
reported one, `:give_up` when a jootser gave up, `:limit` when the codelet
budget ran out.

The Scheme returns through an escape continuation the headless harness
installs; here `report-new-answer` and `give-up` throw `RunFinished` and this
catches it, which is the same shape. The codelet limit is the harness's too —
the model itself runs forever."""
function run_mcat!(ctx; codelet_limit::Int = 100000)
    try
        while true
            ctx.codelet_count >= codelet_limit && return :limit
            step_mcat!(ctx)
            if ctx.codelet_count == ctx.initial_slipnode_unclamp_time
                for n in ctx.net.initially_clamped_nodes
                    unfreeze!(n)
                end
            end
            # NB `if*` is `when`: BOTH of these run when the rack empties.
            if coderack_empty(ctx.coderack)
                post_initial_codelets!(ctx)
                clamp_initial_slipnodes!(ctx)
            end
            ctx.codelet_count % UPDATE_CYCLE_LENGTH == 0 && update_everything!(ctx)
        end
    catch e
        e isa RunFinished || rethrow()
        return e.reason
    end
end

"""`(run-problem ...)` and `(run-justify-problem ...)` from the headless harness
— one problem, start to finish. `answer_sym` chooses between them: pass one and
the run is a justify run."""
function run_problem(net::Slipnet, initial_sym, modified_sym, target_sym, seed::Int,
                     codelet_limit::Int = 100000; answer_sym = nothing,
                     memory = make_memory(), trace = make_temporal_trace())
    ctx = init_mcat(net, initial_sym, modified_sym, target_sym, seed;
                    answer_sym = answer_sym, memory = memory, trace = trace)
    return (run_mcat!(ctx; codelet_limit = codelet_limit), ctx)
end
