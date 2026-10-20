# Julia counterpart of metacat/bench/metacat_transstring_probe.ss.
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

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
net = build_slipnet()

join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
object_tag(o) = o isa WorkspaceString ? string("string:", o.string_type) : ascii_name(o)

od_tag(od::ObjectDescription) =
    string("(", od.object_type isa Symbol ? od.object_type : sn(od.object_type), " ",
           sn(od.description_type), " ", sn(od.descriptor), ")")

cm_tag(cm::ConceptMapping) = cm_print_name(cm, net)

bridge_tag(b::Bridge) = string(object_tag(b.object1), ">", object_tag(b.object2))

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

function print_clause(tag, rc::RuleClause)
    if is_verbatim_clause(rc)
        println(tag, "\tVERBATIM\t",
                join_or_dash([nm(n) for n in rc.letter_categories]))
    elseif is_intrinsic_clause(rc)
        println(tag, "\tCHANGE\t", od_tag(rc.object_descriptions[1]), "\t",
                join_or_dash([string("(", c.scope, " ", sn(c.dimension), " ",
                                     sn(c.descriptor), ")") for c in rc.changes]))
    else
        println(tag, "\tSWAP\t",
                join_or_dash([od_tag(od) for od in rc.object_descriptions]), "\t",
                join_or_dash([sn(d) for d in rc.dimensions]))
    end
end

function print_rule(tag, rule::Rule)
    println(tag, "\tTYPE\t", rule.rule_type, "\ttranslated=", yn(rule.translated),
            "\tdir=", rule.translation_direction === nothing ? "#f" :
                       replace(String(rule.translation_direction), "_" => "-"))
    for rc in rule.rule_clauses
        print_clause(tag, rc)
    end
    for line in rule.english_transcription
        println(tag, "\tEN\t|", line, "|")
    end
end

function print_log(tag, log::SlippageLog)
    println(tag, "\tDIRECT\t",
            join_or_dash([cm_tag(s) for s in get_directly_applied_slippages(log)]))
    println(tag, "\tCOAT\t",
            join_or_dash([cm_tag(s) for s in get_coattail_slippages(log)]))
    println(tag, "\tCOATIND\t",
            join_or_dash([cm_tag(s) for s in get_coattail_inducing_slippages(log)]))
    println(tag, "\tAPPLIED\t",
            join_or_dash([cm_tag(s) for s in get_applied_slippages(log)]))
    println(tag, "\tLOGBR\t",
            join_or_dash([bridge_tag(b) for b in get_slippage_bridges(log)]))
    for s in get_directly_applied_slippages(log)
        h = get_slippage_to_highlight(log, s)
        println(tag, "\tHIGH\t", cm_tag(s), "\t", h === nothing ? "-" : cm_tag(h))
    end
end

const SEEN = Codelet[]

function new_codelets_of_type(ctx::MetacatCtx, type_name::Symbol)
    found = Codelet[c for c in ctx.coderack.codelet_list
                    if c.codelet_type.name === type_name && !any(x -> x === c, SEEN)]
    prepend!(SEEN, found)
    return found
end

"""Drive scout -> evaluator -> builder by hand until a top rule is built."""
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

"""Dump a constructed string exhaustively: every letter, every group, the
nesting, and the descriptions each object ended up with."""
function dump_string(tag, s::WorkspaceString)
    println(tag, "\tSTR\t", s.string_type, "\t", s.print_name, "\tlen=",
            string_length(s), "\ttranslated=", yn(s.translated))
    for l in s.letters
        println(tag, "\tLET\t", ascii_name(l), "\tpos=", l.string_pos, "\tid=",
                l.id_num, "\tencl=",
                l.enclosing_group === nothing ? "-" : ascii_name(l.enclosing_group))
        for d in l.descriptions
            println(tag, "\tLD\t", ascii_name(l), "\t", sn(d.description_type), "\t",
                    sn(d.descriptor), "\tlevel=", d.proposal_level)
        end
    end
    println(tag, "\tNGROUPS\t", length(s.groups))
    for g in reverse(s.groups)
        println(tag, "\tGRP\t", ascii_name(g), "\tcat=", sn(g.group_category),
                "\tfacet=", sn(g.group_bond_facet), "\tdir=", nm(g.direction),
                "\tlen=", g.group_length, "\tspan=", g.left_string_pos, "-",
                g.right_string_pos, "\tid=", g.id_num, "\tencl=",
                g.enclosing_group === nothing ? "-" : ascii_name(g.enclosing_group))
        println(tag, "\tGOBJ\t", ascii_name(g), "\t",
                join_or_dash([ascii_name(o) for o in get_constituent_objects(g)]))
        for d in g.descriptions
            println(tag, "\tGD\t", ascii_name(g), "\t", sn(d.description_type), "\t",
                    sn(d.descriptor), "\tlevel=", d.proposal_level)
        end
    end
end

supbr_tag(b::Bridge) = string(object_tag(b.object1), ">", object_tag(b.object2),
                              "\ttrb=", yn(b.translated_rule_bridge))

function probe(i, m, t, seed, n, temp, rounds, attempts)
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
    print_rule("RULE", rule)
    # NB: make_translated_string assumes the rule APPLIES -- it takes the first
    # element of each result immediately, so a failed application would be an
    # index into `nothing`. answer-finder guards it the same way.
    if apply_rule(rule, ctx.initial_string, net, ignore_snag) === nothing
        println("TOP\tNOAPPLY")
    else
        top_string = make_translated_string(rule, ctx.initial_string, ctx, net)
        dump_string("TOP", top_string)
        println("TOP\tSUPBR\t",
                join_or_dash([supbr_tag(b) for b in rule.supporting_horizontal_bridges]))
        p = rule.theme_pattern
        println("TOP\tTHEME\t", replace(String(p[1]), "_" => "-"), ":",
                join_or_dash([string(sn(e[1]), "/", nm(e[2])) for e in p[2:end]]))
    end

    for a in 1:attempts
        result = translate(ctx.rng, rule, ctx.initial_string, ctx.target_string, net)
        if result === nothing
            println("T", a, "\tFAILED")
            continue
        end
        tag = string("T", a)
        bottom_rule = result.translated_rule
        print_rule(tag, bottom_rule)
        if apply_rule(bottom_rule, ctx.target_string, net, ignore_snag) === nothing
            println(tag, "\tNOAPPLY")
            continue
        end
        answer_string = make_translated_string(bottom_rule, ctx.target_string, ctx, net)
        dump_string(tag, answer_string)
        println(tag, "\tSUPBR\t",
                join_or_dash([supbr_tag(b)
                              for b in bottom_rule.supporting_horizontal_bridges]))
        println(tag, "\tSUPGRP\t",
                join_or_dash([ascii_name(o) for o in
                              get_rule_supporting_groups(rule, bottom_rule, ctx, net)]))
    end
end

probe("abc", "abd", "cba", 501, 2000, 30, 40, 4)
probe("abc", "abd", "kji", 401, 2000, 30, 40, 4)
probe("abc", "abd", "kji", 402, 4000, 30, 40, 4)
probe("abc", "abd", "mrrjjj", 404, 3000, 30, 40, 4)
probe("abc", "cba", "pqrs", 405, 3000, 30, 40, 4)
probe("aabc", "aabd", "ijkk", 406, 3000, 30, 40, 4)
probe("mrrjjj", "mrrkkk", "xyz", 409, 3000, 30, 40, 4)
probe("abc", "abd", "xyz", 410, 3000, 30, 40, 4)
probe("abcd", "abdc", "xyz", 408, 3000, 25, 40, 4)
probe("abc", "abd", "ijk", 412, 2000, 40, 40, 4)
