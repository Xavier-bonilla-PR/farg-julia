# Julia counterpart of metacat/bench/metacat_trace_probe.ss.
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
include("../julia/src/rules.jl")
include("../julia/src/answers.jl")
include("../julia/src/trace.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
net = build_slipnet()

hyphen(s::Symbol) = replace(String(s), "_" => "-")

count_of(pred, structures) = count(pred, structures)

structure_summary(structures) =
    string("b", count(s -> s isa Bond, structures),
           "/g", count(s -> s isa Group, structures),
           "/x", count(s -> s isa Bridge, structures),
           "/r", count(s -> s isa Rule, structures),
           "/n", length(structures))

pattern_summary(patterns) =
    join_or_dash([string(hyphen(p[1]), ":",
                         join_or_dash([string(sn(e[1]), "/", nm(e[2]),
                                              length(e) == 3 ? string("@", e[3]) : "")
                                       for e in entries(p)]))
                  for p in patterns])

function show_event(tag, e::GenericEvent, ctx)
    # NB: the generic event captures the clamped rules but exposes no accessor
    # for them in the Scheme, so they are not dumped here.
    println(tag, "\tEV\t", get_event_number(e), "\t", hyphen(get_event_type(e)),
            "\t", get_time(e), "\ttemp=", get_temperature(e), "\tage=",
            get_age(e, ctx), "\tstruct=", structure_summary(get_structures(e)))
    println(tag, "\tEVTH\t", get_event_number(e), "\t",
            join_or_dash([hyphen(s) for s in get_active_theme_types(e)]))
    println(tag, "\tEVCP\t", get_event_number(e), "\t",
            pattern_summary(get_complete_themespace_patterns(e)))
    println(tag, "\tEVDP\t", get_event_number(e), "\t",
            pattern_summary(get_dominant_themespace_patterns(e)))
    println(tag, "\tEVNAME\t", get_event_number(e), "\t|", event_print_name(e), "|")
end

function show_trace(tag, tr::TemporalTrace, ctx)
    println(tag, "\tN\t", length(get_all_events(tr)))
    for type in (:any, :snag, :answer, :clamp, :concept_activation,
                 :concept_mapping, :rule, :group)
        e = get_last_event(tr, type)
        println(tag, "\tCOUNT\t", hyphen(type), "\t", get_num_of_events(tr, type),
                "\tlast=", e === nothing ? "-" : string(get_event_number(e)),
                "\telapsed=", get_elapsed_time(tr, type, ctx))
    end
    println(tag, "\tPERIODS\tclamp=", yn(within_clamp_period(tr)),
            "\tsnag=", yn(within_snag_period(tr)),
            "\tgrace=", yn(within_grace_period(tr, ctx)),
            "\tpermission=", yn(permission_to_clamp(tr, ctx)),
            "\texpired=", yn(clamp_period_expired(tr, ctx)))
    println(tag, "\tTIMES\tlastclamp=",
            get_last_clamp_time(tr) === nothing ? "-" : string(get_last_clamp_time(tr)),
            "\tlastunclamp=",
            get_last_unclamp_time(tr) === nothing ? "-" :
                string(get_last_unclamp_time(tr)),
            "\tcurrentanswer=", yn(current_answer(tr, ctx)),
            "\timmsnag=", yn(immediate_snag_condition(tr, ctx)))
end

# Bonds are the only workspace structure whose builder calls no monitor, so
# they are what this probe builds; see the .ss header.
const BOND_CURSOR = Ref(0)

function build_next_bond!(s::WorkspaceString)
    n = string_length(s)
    BOND_CURSOR[] >= n - 1 && return nothing
    p = BOND_CURSOR[]
    BOND_CURSOR[] += 1
    o1 = s.letters[p + 1]
    o2 = s.letters[p + 2]
    d1 = get_descriptor_for(o1, net[:plato_letter_category])::Node
    d2 = get_descriptor_for(o2, net[:plato_letter_category])::Node
    cat = get_bond_category_between(d1, d2, net)
    cat === nothing && return nothing
    b = make_bond(net, o1, o2, cat::Node, net[:plato_letter_category], d1, d2)
    build_bond!(b, net)
    return b
end

function advance!(ctx::MetacatCtx, n, s::WorkspaceString)
    ctx.codelet_count += n
    return build_next_bond!(s)
end

function probe(i, m, t, seed, temp)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", temp)
    foreach(reset!, net.nodes)
    ts = make_themespace(net)
    tr = make_temporal_trace()
    strings = [make_workspace_string(net, :initial, i),
               make_workspace_string(net, :modified, m),
               make_workspace_string(net, :target, t)]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    # NB: slipnode activations are left alone on purpose — see the .ss header.
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), ts, strings[1], strings[2],
                     strings[3], temp, 0)
    BOND_CURSOR[] = 0
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)

    show_trace("empty", tr, ctx)

    specs = [(:concept_activation, 60), (:group, 80), (:concept_mapping, 120),
             (:rule, 40), (:snag, 90), (:concept_activation, 30), (:clamp, 70),
             (:group, 150), (:answer, 50)]
    for (k, spec) in enumerate(specs)
        advance!(ctx, spec[2], ctx.initial_string)
        if k == 3
            set_theme_activation!(ts, :vertical_bridge, net[:plato_letter_category],
                                  net[:plato_identity], 90)
            thematic_pressure_on!(ts, :vertical_bridge)
        end
        if k == 6
            set_theme_activation!(ts, :top_bridge,
                                  net[:plato_string_position_category],
                                  net[:plato_opposite], 70)
        end
        e = make_generic_event(spec[1], ctx)
        add_event!(tr, e, ctx)
        println("ADDED\t", k, "\t", hyphen(spec[1]), "\ttime=", ctx.codelet_count)
        show_event(string("e", k), e, ctx)
        show_trace(string("after", k), tr, ctx)
    end

    println("ALLEVENTS\t",
            join_or_dash([string(get_event_number(e), ":", hyphen(get_event_type(e)))
                          for e in get_all_events(tr)]))
    for n in 1:9
        e = get_event(tr, n)
        println("BYNUM\t", n, "\t", e === nothing ? "-" : hyphen(get_event_type(e)))
    end
    println("BYNUM\t99\t", get_event(tr, 99) === nothing ? "-" : "found")

    for types in ([:snag, :answer], [:clamp, :group], [:rule],
                  [:concept_activation, :concept_mapping])
        e = get_last_event(tr, types)
        println("LASTOF\t(", join([hyphen(x) for x in types], " "), ")\t",
                e === nothing ? "-" :
                string(get_event_number(e), ":", hyphen(get_event_type(e))))
    end

    for type in (:clamp, :snag, :answer, :group, :rule)
        println("SINCE\t", hyphen(type), "\tevents=",
                length(get_new_events_since_last(tr, type)), "\tstructures=",
                structure_summary(get_new_structures_since_last(tr, type, ctx)))
    end

    println("GRACE\tbefore\t", yn(within_grace_period(tr, ctx)), "\t",
            yn(permission_to_clamp(tr, ctx)))
    ctx.codelet_count += 400
    println("GRACE\tafter400\texpired=", yn(clamp_period_expired(tr, ctx)), "\t",
            yn(permission_to_clamp(tr, ctx)))
    ctx.codelet_count += 400
    println("GRACE\tafter800\texpired=", yn(clamp_period_expired(tr, ctx)))

    initialize!(tr)
    show_trace("reinitialized", tr, ctx)
end

probe("abc", "abd", "ijk", 701, 40)
probe("abc", "abd", "mrrjjj", 702, 30)
probe("abc", "cba", "pqrs", 703, 50)
