# Julia counterpart of metacat/bench/metacat_memory_probe.ss.
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
include("../julia/src/memory.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
net = build_slipnet()

# The model's own path from a string to its letter-category nodes.
letters(word) = make_workspace_string(net, :initial, word).letter_categories

pat(type, es...) = Any[type, es...]
theme_tag(e) = string(sn(e[1]), "/", nm(e[2]))

lcat = net[:plato_letter_category]
spos = net[:plato_string_position_category]
dir = net[:plato_direction_category]
otype = net[:plato_object_category]
len = net[:plato_length]
gtype = net[:plato_group_category]
apos = net[:plato_alphabetic_position_category]
iden = net[:plato_identity]
opp = net[:plato_opposite]
succ = net[:plato_successor]
pred = net[:plato_predecessor]

change_clause(otype_node, dtype, descriptor, changes...) =
    intrinsic_clause(ObjectDescription(otype_node, dtype, descriptor),
                     Change[changes...])
verb_clause(word) = verbatim_clause(Node[letters(word)...])

function answer(i, m, t, a, top_clauses, bot_clauses, top_abs, bot_abs, temp,
                quality, vpattern, upattern, uslippages)
    return make_answer_description(letters(i), letters(m), letters(t), letters(a),
                                   top_clauses, bot_clauses, ["top phrase"],
                                   ["bottom phrase"], top_abs, bot_abs, temp,
                                   quality, vpattern, pat(:top_bridge),
                                   pat(:bottom_bridge), upattern, uslippages)
end

function show_answer(tag, a::AnswerDescription)
    println(tag, "\tANS\t", answer_print_name(a), "\tq=", a.quality, "\ttemp=",
            a.temperature, "\tabs=", a.top_rule_abstractness, "/",
            a.bottom_rule_abstractness, "\tact=", get_activation(a),
            "\tunjust=", yn(is_unjustified(a)))
    println(tag, "\tPROB\t", problem_print_name(a))
    println(tag, "\tTHEMES\t", join_or_dash([theme_tag(e) for e in get_themes(a)]))
    println(tag, "\tUTHEMES\t",
            join_or_dash([theme_tag(e) for e in get_unjustified_themes(a)]))
    println(tag, "\tABSTR\t", average_theme_abstractness(a, net), "\tincoherent=",
            yn(answer_incoherent(a, net)))
end

#------------------------------------------------------------- descriptions ---

println("SECTION\tdescriptions")

r_succ = RuleClause[change_clause(net[:plato_letter], spos, net[:plato_rightmost],
                                  Change(:self, lcat, succ))]
r_pred = RuleClause[change_clause(net[:plato_letter], spos, net[:plato_leftmost],
                                  Change(:self, lcat, pred))]
r_succ_group = RuleClause[change_clause(net[:plato_group], spos,
                                        net[:plato_rightmost],
                                        Change(:self, lcat, succ))]
r_len = RuleClause[change_clause(net[:plato_group], spos, net[:plato_rightmost],
                                 Change(:self, len, succ))]
r_verb = RuleClause[verb_clause("abd")]
r_two_changes = RuleClause[change_clause(net[:plato_letter], spos,
                                         net[:plato_rightmost],
                                         Change(:self, lcat, succ),
                                         Change(:self, otype, net[:plato_letter]))]

a1 = answer("abc", "abd", "ijk", "ijl", r_succ, r_succ, 40, 40, 30, 80,
            pat(:vertical_bridge, (lcat, iden), (spos, iden), (otype, iden)),
            pat(:vertical_bridge), ConceptMapping[])
a2 = answer("abc", "abd", "ijk", "ijl", r_succ, r_succ, 40, 40, 30, 80,
            pat(:vertical_bridge, (lcat, iden), (spos, iden), (otype, iden)),
            pat(:vertical_bridge), ConceptMapping[])
a3 = answer("abc", "abd", "ijk", "ijl", r_succ, r_succ, 40, 40, 30, 80,
            pat(:vertical_bridge, (lcat, iden), (spos, opp), (otype, iden)),
            pat(:vertical_bridge), ConceptMapping[])
a4 = answer("abc", "abd", "ijk", "ijl", r_succ, r_succ, 40, 40, 30, 80,
            pat(:vertical_bridge, (lcat, iden), (spos, iden), (otype, iden),
                (dir, opp)),
            pat(:vertical_bridge), ConceptMapping[])
a5 = answer("abc", "abd", "ijk", "ijl", r_pred, r_succ, 40, 40, 30, 80,
            pat(:vertical_bridge, (lcat, iden), (spos, iden), (otype, iden)),
            pat(:vertical_bridge), ConceptMapping[])
a6 = answer("abc", "abd", "ijk", "ijl", r_verb, r_succ, 10, 40, 30, 80,
            pat(:vertical_bridge, (lcat, iden), (spos, iden), (otype, iden)),
            pat(:vertical_bridge), ConceptMapping[])
a7 = answer("abc", "abd", "ijk", "ijl", r_two_changes, r_succ, 40, 40, 30, 80,
            pat(:vertical_bridge, (lcat, iden), (spos, iden), (otype, iden)),
            pat(:vertical_bridge), ConceptMapping[])
a8 = answer("abc", "abd", "ijk", "ijl", r_succ, r_succ, 40, 40, 30, 80,
            pat(:vertical_bridge, (lcat, iden), (spos, iden)),
            pat(:vertical_bridge, (otype, iden), (dir, opp)), ConceptMapping[])
a9 = answer("abc", "abd", "ijk", "ijl", r_succ, r_succ, 5, 40, 30, 80,
            pat(:vertical_bridge, (apos, opp), (gtype, opp), (len, succ)),
            pat(:vertical_bridge), ConceptMapping[])
a10 = answer("abc", "abd", "ijk", "ijd", r_succ, r_succ, 40, 40, 30, 60,
             pat(:vertical_bridge, (lcat, iden), (spos, iden), (otype, iden)),
             pat(:vertical_bridge), ConceptMapping[])
a11 = answer("abc", "abd", "ijk", "ijl", r_succ_group, r_succ, 60, 40, 30, 80,
             pat(:vertical_bridge, (lcat, iden), (otype, opp)),
             pat(:vertical_bridge), ConceptMapping[])
a12 = answer("abc", "abd", "ijk", "ijl", r_len, r_succ, 70, 40, 30, 80,
             pat(:vertical_bridge, (len, succ), (spos, iden)),
             pat(:vertical_bridge), ConceptMapping[])

all_answers = [a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12]
answer_names = ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10",
                "a11", "a12"]

for (a, n) in zip(all_answers, answer_names)
    show_answer(n, a)
end

#----------------------------------------------------------------- distance ---

println("SECTION\tdistance")

mem = make_memory()

for (a, n) in zip(all_answers, answer_names)
    for (b, m) in zip(all_answers, answer_names)
        println("DIST\t", n, "\t", m, "\t", calculate_answer_distance(a, b, mem, net))
    end
end

println("SECTION\trulecompare")
rule_lists = [("succ", r_succ), ("pred", r_pred), ("group", r_succ_group),
              ("len", r_len), ("verb", r_verb), ("two", r_two_changes)]
for (n1, l1) in rule_lists
    for (n2, l2) in rule_lists
        result = compare_rule_clause_lists(l1, l2, net)
        println("RCMP\t", n1, "\t", n2, "\t",
                result === nothing ? "none" :
                join_or_dash([string(sn(p[1]), ">", sn(p[2])) for p in result]))
    end
end

#--------------------------------------------------------------- the memory ---

println("SECTION\tstore")

clear_memory!(mem)
println("EMPTY\t", length(get_answers(mem)), "\t", length(get_snags(mem)), "\t",
        length(get_all_descriptions(mem)))

for (a, n) in zip(all_answers, answer_names)
    add_answer_description!(mem, a, net)
    println("ADD\t", n, "\tn=", length(get_answers(mem)))
    for b in get_answers(mem)
        println("ACT\t", n, "\t", answer_print_name(b), "\t", get_activation(b))
    end
end

println("SECTION\tpresent")
strings = [make_workspace_string(net, :initial, "abc"),
           make_workspace_string(net, :modified, "abd"),
           make_workspace_string(net, :target, "ijk")]
ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                 strings[1], strings[2], strings[3], 100, 0)
fake_top_rule = make_rule(:top, r_succ, ctx.initial_string, net)
fake_bot_rule = make_rule(:bottom, r_succ, ctx.target_string, net)
fake_top_rule2 = make_rule(:top, r_pred, ctx.initial_string, net)
println("PRESENT\tijl-succ-succ\t",
        yn(answer_present(mem, letters("ijl"), fake_top_rule, fake_bot_rule, ctx, net)))
println("PRESENT\tijl-pred-succ\t",
        yn(answer_present(mem, letters("ijl"), fake_top_rule2, fake_bot_rule, ctx, net)))
println("PRESENT\tijz-succ-succ\t",
        yn(answer_present(mem, letters("ijz"), fake_top_rule, fake_bot_rule, ctx, net)))

println("SECTION\tsnags")
snag(rule_clauses, translated_clauses, explanation, spattern) =
    make_snag_description(ctx, rule_clauses, translated_clauses, ["snag phrase"],
                          ["translated phrase"], explanation, spattern)
# NB: get_snag_justified_themes is (answer's themes MINUS the snag's) intersected
# with the answer's unjustified ones -- so a snag whose themes CONTAIN the
# answer's unjustified ones justifies nothing. s1 deliberately shares only a
# justified theme with a8, leaving a8's unjustified ones to come back.
s1 = snag(r_succ, r_succ, "the rule could not be applied",
          pat(:vertical_bridge, (lcat, iden)))
s2 = snag(r_pred, r_succ, "the letters ran out",
          pat(:vertical_bridge, (otype, iden), (dir, opp)))
add_snag_description!(mem, s1)
add_snag_description!(mem, s2)
println("SNAGS\t", length(get_snags(mem)), "\t", length(get_all_descriptions(mem)))
println("SNAGPRESENT\tsucc\t", yn(snag_present(mem, fake_top_rule, ctx, net)))
println("SNAGPRESENT\tpred\t", yn(snag_present(mem, fake_top_rule2, ctx, net)))
for (a, n) in zip(all_answers, answer_names)
    eq_snag = get_equivalent_snag(mem, a, net)
    println("EQSNAG\t", n, "\t",
            eq_snag === nothing ? "-" : problem_print_name(eq_snag), "\tjustified=",
            join_or_dash([theme_tag(e)
                          for e in get_snag_justified_themes(a, mem, net)]))
end

println("SECTION\tdistance-with-snag")
for (a, n) in zip(all_answers, answer_names)
    for (b, m) in zip(all_answers, answer_names)
        println("DIST2\t", n, "\t", m, "\t", calculate_answer_distance(a, b, mem, net))
    end
end

println("SECTION\tclear")
clear_activations!(mem)
println("CLEARACT\t",
        join_or_dash([string(get_activation(a)) for a in get_answers(mem)]))
delete_description!(mem, a1)
println("DELETE\t", length(get_answers(mem)), "\t", length(get_snags(mem)), "\t",
        length(get_all_descriptions(mem)))
delete_description!(mem, s1)
println("DELETE\t", length(get_answers(mem)), "\t", length(get_snags(mem)), "\t",
        length(get_all_descriptions(mem)))
clear_memory!(mem)
println("CLEARED\t", length(get_answers(mem)), "\t", length(get_snags(mem)), "\t",
        length(get_all_descriptions(mem)))
