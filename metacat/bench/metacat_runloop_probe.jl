# Julia counterpart of metacat/bench/metacat_runloop_probe.ss: run.ss's
# per-cycle update, driven as a genuine loop.
include("../../copycat/julia/src/pyrandom.jl")  # shared MT19937 (Copycat side)
include("../julia/src/schemenum.jl")
include("../julia/src/utilities.jl")
include("../julia/src/slipnet.jl")
include("../julia/src/workspace.jl")
include("../julia/src/concept_mappings.jl")
include("../julia/src/images.jl")
include("../julia/src/bonds.jl")
include("../julia/src/groups.jl")
include("../julia/src/bridges.jl")
include("../julia/src/coderack.jl")
include("../julia/src/themes.jl")
include("../julia/src/context.jl")
include("../julia/src/codelets_bonds.jl")
include("../julia/src/codelets_descriptions.jl")
include("../julia/src/codelets_groups.jl")
include("../julia/src/codelets_bridges.jl")
include("../julia/src/codelets_themes.jl")
include("../julia/src/codelets_breaker.jl")
include("../julia/src/rules.jl")
include("../julia/src/answers.jl")
include("../julia/src/trace.jl")
include("../julia/src/justify.jl")
include("../julia/src/memory.jl")
include("../julia/src/codelets_jootsing.jl")
include("../julia/src/run.jl")

net = build_slipnet()

sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
hyphen(s::Symbol) = replace(String(s), "_" => "-")

count_of(T, structures) = count(s -> s isa T, structures)

# --- the whole model state, every few cycles ---------------------------------

function dump_state(c, ctx, tr)
    structures = get_structures(ctx)
    objs = workspace_objects(ctx)
    println("ST\t", c, "\t", ctx.temperature, "\tb", count_of(Bond, structures),
            "/g", count_of(Group, structures), "/x", count_of(Bridge, structures),
            "/r", count_of(Rule, structures), "\to", length(objs), "\tcr",
            length(ctx.coderack.codelet_list))
    println("STU\t", c, "\t", get_average_intra_string_unhappiness(ctx), "\t",
            get_average_unhappiness(ctx), "\t", get_min_mapping_strength(ctx), "\t",
            get_max_inter_string_unhappiness(ctx), "\t",
            join_or_dash([string(t) for t in get_possible_rule_types(ctx)]))
    println("STR\t", c, "\t", count(unrelated, objs), "\t", count(ungrouped, objs),
            "\t", count(unmapped, objs))
    # the coderack, by type
    counts = String[]
    for name in ALL_CODELET_TYPE_NAMES
        n = count(k -> k.codelet_type.name === name, ctx.coderack.codelet_list)
        n == 0 && continue
        ct = get(CODELET_TYPES, name, nothing)
        push!(counts, string(ct === nothing ? hyphen(name) : codelet_type_display(ct),
                             ":", n))
    end
    println("STC\t", c, "\t", join_or_dash(counts))
    println("STN\t", c, "\t",
            join_or_dash([string(sn(n), ":", n.activation) for n in net.top_down_nodes]))
    println("STT\t", c, "\t", length(ctx.themespace.all_themes), "\t",
            join_or_dash([hyphen(s) for s in ctx.themespace.active_theme_types]), "\t",
            length(get_all_events(tr)), "\t", yn(tr.within_snag_period), "\t",
            yn(tr.within_clamp_period))
    return
end

# --- probe -------------------------------------------------------------------

function probe(i, m, t, seed, n, temp, every)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp)
    foreach(reset!, net.nodes)
    strings = [make_workspace_string(net, :initial, i),
               make_workspace_string(net, :modified, m),
               make_workspace_string(net, :target, t)]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                     strings[1], strings[2], strings[3], temp, 0)
    tr = make_temporal_trace()
    ctx.trace = tr
    ctx.memory = make_memory()
    for nd in net.initially_clamped_nodes
        clamp_activation!(nd, MAX_ACTIVATION, ctx)
    end
    # Self-watching ON -- the real default from setup.ss.
    ctx.temperature_clamped = false
    # (tell *coderack* 'initialize). The rack is brand new, but the CODELET
    # TYPES are global and outlive it, so a clamp left standing by the previous
    # problem would carry over.
    initialize!(ctx.coderack)
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    post_initial_codelets!(ctx)
    dump_state(0, ctx, tr)
    c = 1
    # report-new-answer ends the run via (suspend), which the headless harness
    # redirects to an escape continuation; the port throws instead.
    finished = nothing
    try
        while c <= n && !coderack_empty(ctx.coderack)
            ctx.codelet_count = c
            run_codelet!(ctx, choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature))
            update_everything!(ctx)
            c % every == 0 && dump_state(c, ctx, tr)
            c += 1
        end
    catch e
        e isa RunFinished || rethrow()
        finished = e.reason
    end
    finished === nothing || println("FINISHED\t", c, "\t", hyphen(finished))
    dump_state("final", ctx, tr)
    return
end

# the long runs, which get bonds and groups built and the top-down bond scouts
# running
probe("abc", "abd", "mrrjjj", 1003, 1500, 100, 250)
probe("mrrjjj", "mrrkkk", "xyz", 1005, 1200, 100, 200)
# the cold-start regime: nothing gets built, temperature never leaves 100
probe("abc", "abd", "ijk", 1001, 200, 100, 50)
probe("abc", "abd", "kji", 1002, 200, 100, 50)
probe("abc", "cba", "pqrs", 1004, 200, 100, 50)
probe("aabc", "aabd", "ijkk", 1006, 300, 100, 75)
