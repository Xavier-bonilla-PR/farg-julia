# Julia counterpart of metacat/bench/metacat_swevents_probe.ss: trace.ss slice
# (C) part 2, the answer, clamp and snag events and the four trace methods
# deferred with them.
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
include("../julia/src/rules.jl")
include("../julia/src/answers.jl")
include("../julia/src/trace.jl")
include("../julia/src/justify.jl")

net = build_slipnet()

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
hyphen(s::Symbol) = replace(String(s), "_" => "-")

object_tag(o) = o isa WorkspaceString ? string("string:", o.string_type) : ascii_name(o)
cm_tag(cm::ConceptMapping) = cm_print_name(cm, net)
entry_tag(e) = string(sn(e[1]), "/", nm(e[2]))
bridge_tag(b::Bridge) = string(object_tag(b.object1), ">", object_tag(b.object2))

"""Codelet types print by NAME, not by identity: the Scheme's entries hold
closures, whose printed form is an address."""
codelet_type_name(t) = replace(replace(String(t.name),
                                       "_scout_category" => "-scout:category"),
                               "_scout_whole_string" => "-scout:whole-string")

function pattern_tag(p)
    if is_concept_pattern(p)
        return string("concepts[",
                      join_or_dash([string(sn(e[1]), ":", e[2]) for e in p[2:end]]), "]")
    elseif is_codelet_pattern(p)
        return string("codelets[",
                      join_or_dash([string(replace(codelet_type_name(e[1]),
                                                   "_" => "-"), ":", e[2])
                                    for e in p[2:end]]), "]")
    end
    return string(hyphen(p[1]), "[",
                  join_or_dash([entry_tag(e) for e in p[2:end]]), "]")
end

count_of(T, structures) = count(s -> s isa T, structures)

structure_summary(structures) =
    string("b", count_of(Bond, structures), "/g", count_of(Group, structures),
           "/x", count_of(Bridge, structures), "/r", count_of(Rule, structures),
           "/n", length(structures))

function dump_generic(tag, e)
    println("GEN\t", tag, "\t", hyphen(get_event_type(e)), "\t", get_time(e), "\t",
            get_temperature(e), "\t", structure_summary(get_structures(e)), "\t",
            length(get_active_theme_types(e)), "\t",
            length(get_complete_themespace_patterns(e)))
    return
end

# --- the state clamping actually moves --------------------------------------

function model_state(tag, label, ctx)
    println("STATE\t", tag, "\t", label, "\tthemes=",
            length(ctx.themespace.all_themes), "\tpressure=",
            join_or_dash([hyphen(s) for s in ctx.themespace.active_theme_types]),
            "\tclamped-rules=", length(ctx.clamped_rules),
            "\tcodelets=", length(ctx.coderack.codelet_list))
    println("STATEN\t", tag, "\t", label, "\t",
            join_or_dash([string(sn(n), ":", n.activation, ":", yn(n.frozen))
                          for n in (net[:plato_letter_category], net[:plato_successor],
                                    net[:plato_opposite],
                                    net[:plato_string_position_category],
                                    net[:plato_length])]))
    return
end

# --- answer events ----------------------------------------------------------

function dump_answer_event(tag, e::AnswerEvent, ctx)
    println("ANE\t", tag, "\t", event_print_name(e), "\t", problem_print_name(e),
            "\t", problem_answer_print_name(e))
    println("ANEL\t", tag, "\t", join_or_dash([nm(n) for n in get_initial_letters(e)]),
            "\t", join_or_dash([nm(n) for n in get_modified_letters(e)]),
            "\t", join_or_dash([nm(n) for n in get_target_letters(e)]),
            "\t", join_or_dash([nm(n) for n in get_answer_letters(e)]))
    println("ANEQ\t", tag, "\t", get_absolute_quality(e), "\t",
            get_event_relative_quality(e, ctx), "\t", get_event_quality(e), "\t",
            get_event_strength(e))
    println("ANEU\t", tag, "\t", yn(is_unjustified(e)), "\t",
            join_or_dash([cm_tag(s) for s in get_unjustified_slippages(e)]))
    for bt in (:top, :vertical, :bottom)
        println("ANEB\t", tag, "\t", bt, "\t",
                join_or_dash([bridge_tag(b) for b in get_supporting_bridges(e, bt)]))
    end
    for rt in (:top, :bottom)
        println("ANER\t", tag, "\t", rt, "\t", get_event_rule(e, rt).rule_type, "\t",
                join_or_dash([object_tag(o) for o in get_rule_ref_objects(e, rt)]))
    end
    println("ANEG\t", tag, "\t",
            join_or_dash([object_tag(o) for o in get_supporting_groups(e)]))
    println("ANED\t", tag, "\t",
            join_or_dash([cm_tag(s)
                          for s in get_applied_slippages(get_slippage_log(e))]))
    println("ANEE\t", tag, "\t", yn(events_equal(e, e)))
    dump_generic(tag, e)
    return
end

# --- clamp events -----------------------------------------------------------

function dump_clamp_event(tag, e::ClampEvent)
    println("CLE\t", tag, "\t", event_print_name(e), "\t", hyphen(get_clamp_type(e)),
            "\t", hyphen(get_progress_focus(e)), "\t", get_progress_achieved(e),
            "\t", get_event_strength(e))
    println("CLET\t", tag, "\t",
            join_or_dash([pattern_tag(p) for p in get_clamped_theme_patterns(e)]))
    println("CLEC\t", tag, "\t",
            join_or_dash([pattern_tag(p) for p in get_clamped_concept_patterns(e)]))
    println("CLEK\t", tag, "\t",
            join_or_dash([pattern_tag(p) for p in get_clamped_codelet_patterns(e)]))
    slips = get_unifying_slippages(e)
    println("CLER\t", tag, "\t", length(get_event_rules(e)), "\t",
            slips === nothing ? "#f" : join_or_dash([cm_tag(s) for s in slips]))
    println("CLEA\t", tag, "\t", length(get_all_clamped_patterns(e)), "\t",
            join_or_dash([yn(is_clamp_type(e, t))
                          for t in (:rule_codelet_clamp, :snag_response_clamp,
                                    :justify_clamp, :manual_clamp)]))
    dump_generic(tag, e)
    return
end

# --- snag events ------------------------------------------------------------

function dump_snag_event(tag, e::SnagEvent)
    println("SNE\t", tag, "\t", event_print_name(e), "\t", get_snag_type(e), "\t",
            get_progress_achieved(e), "\t", get_event_strength(e))
    println("SNEX\t", tag, "\t", snag_explanation(e, net))
    println("SNEO\t", tag, "\t",
            join_or_dash([object_tag(o) for o in get_snag_objects(e)]))
    println("SNEB\t", tag, "\t",
            join_or_dash([bridge_tag(b) for b in get_snag_bridges(e)]))
    println("SNEC\t", tag, "\t",
            join_or_dash([cm_tag(cm) for cm in get_snag_concept_mappings(e)]))
    println("SNET\t", tag, "\t", pattern_tag(get_snag_theme_pattern(e)))
    println("SNEP\t", tag, "\t", pattern_tag(get_snag_concept_pattern(e)))
    for bt in (:top, :vertical)
        println("SNEV\t", tag, "\t", bt, "\t",
                join_or_dash([bridge_tag(b) for b in get_supporting_bridges(e, bt)]))
    end
    println("SNER\t", tag, "\t",
            join_or_dash([object_tag(o) for o in get_rule_ref_objects(e)]), "\t",
            get_event_rule(e, :bottom).rule_type)
    println("SNEE\t", tag, "\t", yn(events_equal(e, e, net)))
    dump_generic(tag, e)
    return
end

# --- workspace driver -------------------------------------------------------

function seed_rack!(ctx::MetacatCtx)
    post(name, urgency, args = Any[]) =
        post!(ctx.coderack, make_codelet(CODELET_TYPES[name], urgency, args),
              ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
    for _ in 1:3
        post(:bottom_up_bond_scout, VERY_LOW_URGENCY)
        post(:group_scout_whole_string, LOW_URGENCY)
        post(:top_down_group_scout_category, LOW_URGENCY,
             Any[ctx.net[:plato_succgrp], nothing])
        post(:top_down_group_scout_category, LOW_URGENCY,
             Any[ctx.net[:plato_samegrp], nothing])
        post(:bottom_up_bridge_scout, MEDIUM_URGENCY)
        post(:bottom_up_bridge_scout, MEDIUM_URGENCY)
        post(:important_object_bridge_scout, MEDIUM_URGENCY)
        post(:bottom_up_description_scout, VERY_LOW_URGENCY)
    end
    return ctx
end

const SEEN = Codelet[]

function new_codelets_of_type(ctx::MetacatCtx, type_name::Symbol)
    found = Codelet[c for c in ctx.coderack.codelet_list
                    if c.codelet_type.name === type_name && !any(x -> x === c, SEEN)]
    prepend!(SEEN, found)
    return found
end

function build_a_top_rule(ctx::MetacatCtx, rounds)
    k = 1
    while k <= rounds && isempty(get_rules(ctx, :top))
        run_codelet!(ctx, make_codelet(CODELET_TYPES[:rule_scout], MEDIUM_URGENCY))
        for ec in new_codelets_of_type(ctx, :rule_evaluator)
            run_codelet!(ctx, ec)
        end
        for bc in new_codelets_of_type(ctx, :rule_builder)
            run_codelet!(ctx, bc)
        end
        k += 1
    end
    rules = get_rules(ctx, :top)
    return isempty(rules) ? nothing : rules[1]
end

const SNAG_RESULT = Any[]
record_snag(failure_result) = (empty!(SNAG_RESULT); push!(SNAG_RESULT, failure_result))

# --- probe -------------------------------------------------------------------

function probe(i, m, t, seed, n, temp, rounds)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp)
    foreach(reset!, net.nodes)
    strings = [make_workspace_string(net, :initial, i),
               make_workspace_string(net, :modified, m),
               make_workspace_string(net, :target, t)]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    for s in strings, o in objects(s), d in o.descriptions
        set_activation!(d.descriptor, MAX_ACTIVATION)
    end
    for nd in (net[:plato_object_category], net[:plato_letter_category],
               net[:plato_string_position_category], net[:plato_successor],
               net[:plato_predecessor], net[:plato_sameness], net[:plato_bond_facet],
               net[:plato_bond_category], net[:plato_group_category],
               net[:plato_direction_category], net[:plato_left], net[:plato_right],
               net[:plato_samegrp], net[:plato_succgrp], net[:plato_predgrp],
               net[:plato_alphabetic_position_category], net[:plato_length])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                     strings[1], strings[2], strings[3], temp, 0)
    tr = make_temporal_trace()
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    empty!(SEEN)
    seed_rack!(ctx)
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        if c > 0 && c % UPDATE_CYCLE_LENGTH == 0
            seed_rack!(ctx)
        end
        ctx.codelet_count = c
        run_codelet!(ctx, choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature))
        update_workspace_values!(ctx)
        c += 1
    end
    check_if_rules_possible!(ctx)
    rule = build_a_top_rule(ctx, rounds)
    if rule === nothing
        println("NORULE")
        return
    end
    # ---- clamp events, one of each type ----
    tp = Any[:vertical_bridge,
             Any[net[:plato_string_position_category], net[:plato_opposite]],
             Any[net[:plato_letter_category], net[:plato_successor]]]
    cp = Any[:concepts, Any[net[:plato_opposite], MAX_ACTIVATION]]
    kp = rule_codelet_pattern()
    for spec in (("rcc", :rule_codelet_clamp, Any[kp], Any[], :rule),
                 ("src", :snag_response_clamp, Any[tp, kp], Any[], :workspace),
                 ("man", :manual_clamp, Any[tp, cp, kp], Any[], :workspace))
        tag = string("CL:", spec[1])
        e = make_clamp_event(spec[2], spec[3], spec[4], spec[5], ctx)
        dump_clamp_event(tag, e)
        model_state(tag, "before", ctx)
        activate!(e, tr, ctx)
        model_state(tag, "active", ctx)
        deactivate!(e, ctx)
        model_state(tag, "after", ctx)
    end
    # ---- snag events ----
    empty!(SNAG_RESULT)
    apply_rule(rule, ctx.target_string, net, record_snag)
    if isempty(SNAG_RESULT)
        println("NOSNAG")
    else
        result = translate(ctx.rng, rule, ctx.initial_string, ctx.target_string, net)
        translated = result === nothing ? rule : result.translated_rule
        supbr = result === nothing ? Bridge[] : result.supporting_vertical_bridges
        log = result === nothing ? make_slippage_log(:top) : result.slippage_log
        refobjs = result === nothing ? Any[] : result.from_string_ref_objects
        e = make_snag_event(SNAG_RESULT[1], rule, translated, supbr, log, refobjs, ctx)
        tag = "SN:top"
        dump_snag_event(tag, e)
        model_state(tag, "before", ctx)
        add_event!(tr, e, ctx)
        activate!(e, tr, ctx)
        model_state(tag, "active", ctx)
        println("SNPROG\t", tag, "\t", yn(tr.within_snag_period), "\t",
                progress_since_last_snag(tr, ctx))
        undo_snag_condition!(tr, ctx)
        model_state(tag, "after", ctx)
        println("SNPROG2\t", tag, "\t", yn(tr.within_snag_period), "\t",
                get_progress_achieved(e))
    end
    # ---- answer event, built the way answer-finder builds one ----
    result = translate(ctx.rng, rule, ctx.initial_string, ctx.target_string, net)
    if result === nothing
        println("NOTRANSLATE")
    else
        bottom_rule = result.translated_rule
        if apply_rule(bottom_rule, ctx.target_string, net, ignore_snag) === nothing
            println("NOAPPLY")
        else
            answer_string = make_translated_string(bottom_rule, ctx.target_string,
                                                   ctx, net)
            unjust = get_unifying_slippages(bottom_rule, rule, net)
            for spec in (("just", ConceptMapping[]), ("unjust", unjust))
                e = make_answer_event(ctx.initial_string, ctx.modified_string,
                                      ctx.target_string, answer_string, rule,
                                      bottom_rule, result.supporting_vertical_bridges,
                                      result.vertical_mapping_supporting_groups,
                                      result.from_string_ref_objects,
                                      result.to_string_ref_objects,
                                      result.slippage_log, spec[2], ctx)
                dump_answer_event(string("AN:", spec[1]), e, ctx)
            end
        end
    end
    # ---- the clamp half of the four deferred trace methods ----
    # NB a justify-clamp reads a TOP and a BOTTOM rule out of its rule list to
    # compute the unifying slippages, so it needs both.
    initialize!(tr)
    tp2 = Any[:vertical_bridge,
              Any[net[:plato_string_position_category], net[:plato_opposite]]]
    tr2 = translate(ctx.rng, rule, ctx.initial_string, ctx.target_string, net)
    bottom = tr2 === nothing ? nothing : tr2.translated_rule
    if bottom === nothing
        println("NOJUSTIFYCLAMP")
    else
        e = make_clamp_event(:justify_clamp, Any[tp2, rule_codelet_pattern()],
                             Any[rule, bottom], :rule, ctx)
        add_event!(tr, e, ctx)
        activate!(e, tr, ctx)
        println("CLPROG\t", yn(tr.within_clamp_period), "\t",
                yn(permission_to_clamp(tr, ctx)), "\t",
                progress_since_last_clamp(tr, ctx))
        # a rule event since the clamp is what the rule-focused evaluator scores
        add_event!(tr, make_rule_event(rule, ctx), ctx)
        println("CLPROG2\t", progress_since_last_clamp(tr, ctx), "\t",
                get_progress_achieved(e))
        undo_last_clamp!(tr, ctx)
        println("CLPROG3\t", yn(tr.within_clamp_period), "\t",
                get_progress_achieved(e), "\t", yn(within_grace_period(tr, ctx)), "\t",
                yn(permission_to_clamp(tr, ctx)))
    end
    return
end

# abc->abd with target xyz is THE snag: the top rule says "replace the rightmost
# letter by its successor", and z has no successor.
probe("abc", "abd", "xyz", 410, 3000, 30, 40)
probe("abc", "abd", "xyz", 411, 2000, 40, 40)
probe("abc", "abd", "cba", 501, 2000, 30, 40)
probe("abc", "abd", "kji", 401, 2000, 30, 40)
probe("abc", "abd", "mrrjjj", 404, 3000, 30, 40)
probe("abc", "cba", "pqrs", 405, 3000, 30, 40)
probe("mrrjjj", "mrrkkk", "xyz", 409, 3000, 30, 40)
