# Julia counterpart of metacat/bench/metacat_abstract_probe.ss: answers.ss step
# (C) part 1, abstracting an answer or snag event into a memory description.
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
include("../julia/src/memory.jl")

net = build_slipnet()

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
hyphen(s::Symbol) = replace(String(s), "_" => "-")

cm_tag(cm::ConceptMapping) = cm_print_name(cm, net)
entry_tag(e) = string(sn(e[1]), "/", nm(e[2]))
pattern_tag(p) = string(hyphen(p[1]), "[",
                        join_or_dash([entry_tag(e) for e in p[2:end]]), "]")
letters_tag(ls) = join([nm(n) for n in ls])

# --- what the abstractors read ----------------------------------------------

function dump_important_events(tag, ctx)
    events = most_recent_group_and_concept_mapping_events(ctx)
    println("IMP\t", tag, "\t", length(events))
    for e in events
        println("IMPE\t", tag, "\t", get_event_number(e), "\t",
                hyphen(get_event_type(e)), "\t", event_print_name(e), "\t",
                get_age(e, ctx))
    end
    println("IMPP\t", tag, "\t",
            pattern_tag(abstract_answer_description_theme_pattern(events, ctx)))
    return
end

# --- the descriptions -------------------------------------------------------

function dump_answer_description(tag, a::AnswerDescription)
    println("AD\t", tag, "\t", letters_tag(a.initial_letters), "\t",
            letters_tag(a.modified_letters), "\t", letters_tag(a.target_letters),
            "\t", letters_tag(a.answer_letters))
    println("ADQ\t", tag, "\t", a.temperature, "\t", a.quality, "\t",
            a.top_rule_abstractness, "\t", a.bottom_rule_abstractness, "\t",
            get_activation(a), "\t", yn(is_unjustified(a)))
    println("ADV\t", tag, "\t", pattern_tag(a.vertical_theme_pattern))
    println("ADT\t", tag, "\t", pattern_tag(a.top_theme_pattern))
    println("ADB\t", tag, "\t", pattern_tag(a.bottom_theme_pattern))
    println("ADU\t", tag, "\t", pattern_tag(a.unjustified_theme_pattern), "\t",
            join_or_dash([cm_tag(s) for s in a.unjustified_slippages]))
    for line in a.top_rule_phrases
        println("ADPT\t", tag, "\t|", line, "|")
    end
    for line in a.bottom_rule_phrases
        println("ADPB\t", tag, "\t|", line, "|")
    end
    return
end

function dump_snag_description(tag, s::SnagDescription)
    println("SD\t", tag, "\t", letters_tag(s.initial_letters), "\t",
            letters_tag(s.modified_letters), "\t", letters_tag(s.target_letters))
    println("SDX\t", tag, "\t", s.snag_explanation)
    println("SDT\t", tag, "\t", pattern_tag(s.theme_pattern))
    println("SDA\t", tag, "\t", get_activation(s), "\t",
            join_or_dash([entry_tag(e) for e in get_themes(s)]))
    for line in s.translated_rule_phrases
        println("SDPT\t", tag, "\t|", line, "|")
    end
    return
end

function dump_memory(tag, mem::Memory)
    println("MEM\t", tag, "\t", length(get_answers(mem)), "\t",
            length(get_snags(mem)), "\t", length(get_all_descriptions(mem)))
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
    ctx.trace = tr
    mem = make_memory()
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    empty!(SEEN)
    seed_rack!(ctx)
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        if c > 0 && c % UPDATE_CYCLE_LENGTH == 0
            seed_rack!(ctx)
            update_slipnet_activations!(net, ctx.rng, ctx.themespace, ctx)
        end
        ctx.codelet_count = c
        run_codelet!(ctx, choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature))
        update_workspace_values!(ctx)
        c += 1
    end
    check_if_rules_possible!(ctx)
    dump_important_events("run", ctx)
    rule = build_a_top_rule(ctx, rounds)
    if rule === nothing
        println("NORULE")
        return
    end
    dump_important_events("rules", ctx)
    # ---- snag description ----
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
        add_event!(tr, e, ctx)
        println("SNAGPRESENT\t", yn(snag_present(mem, rule, ctx, net)))
        abstract_snag_description!(e, mem, ctx)
        dump_memory("after-snag", mem)
        dump_snag_description("snag", get_snags(mem)[1])
        # abstracting the SAME snag again: the memory grows, since
        # abstract_snag_description does not itself check for duplicates
        abstract_snag_description!(e, mem, ctx)
        dump_memory("after-snag2", mem)
    end
    # ---- answer description ----
    result = translate(ctx.rng, rule, ctx.initial_string, ctx.target_string, net)
    if result === nothing
        println("NOTRANSLATE")
        return
    end
    bottom_rule = result.translated_rule
    if apply_rule(bottom_rule, ctx.target_string, net, ignore_snag) === nothing
        println("NOAPPLY")
        return
    end
    answer_string = make_translated_string(bottom_rule, ctx.target_string, ctx, net)
    unjust = get_unifying_slippages(bottom_rule, rule, net)
    for spec in (("just", ConceptMapping[]), ("unjust", unjust))
        e = make_answer_event(ctx.initial_string, ctx.modified_string,
                              ctx.target_string, answer_string, rule, bottom_rule,
                              result.supporting_vertical_bridges,
                              result.vertical_mapping_supporting_groups,
                              result.from_string_ref_objects,
                              result.to_string_ref_objects,
                              result.slippage_log, spec[2], ctx)
        add_event!(tr, e, ctx)
        abstract_answer_description!(e, mem, ctx)
        dump_answer_description(spec[1], get_answer_description(e)::AnswerDescription)
        dump_memory(string("after-", spec[1]), mem)
    end
    return
end

probe("abc", "abd", "xyz", 901, 3000, 30, 40)
probe("abc", "abd", "kji", 902, 2500, 30, 40)
probe("abc", "abd", "cba", 903, 2500, 30, 40)
probe("abc", "abd", "mrrjjj", 904, 1500, 30, 40)
probe("abc", "cba", "pqrs", 905, 1500, 30, 40)
probe("mrrjjj", "mrrkkk", "xyz", 906, 1500, 30, 40)
