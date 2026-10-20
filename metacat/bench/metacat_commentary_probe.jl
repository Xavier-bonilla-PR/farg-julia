# Julia counterpart of metacat/bench/metacat_commentary_probe.ss: answers.ss's
# commentary, the English Metacat writes about its own answers.
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
include("../julia/src/commentary.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
net = build_slipnet()

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
facet = net[:plato_bond_facet]
iden = net[:plato_identity]
opp = net[:plato_opposite]
succ = net[:plato_successor]
pred = net[:plato_predecessor]

change_clause(otype_node, dtype, descriptor, changes...) =
    intrinsic_clause(ObjectDescription(otype_node, dtype, descriptor),
                     Change[changes...])
verb_clause(word) = verbatim_clause(Node[letters(word)...])

mem = make_memory()

answer(i, m, t, a, top_clauses, top_abs, quality, vpattern, upattern) =
    make_answer_description(letters(i), letters(m), letters(t), letters(a),
                            top_clauses, top_clauses, ["top phrase"],
                            ["bottom phrase"], top_abs, top_abs, 30, quality,
                            vpattern, pat(:top_bridge), pat(:bottom_bridge),
                            upattern, ConceptMapping[])

#--------------------------------------------------- punctuate-with-commas ---

println("SECTION\tpunctuate")

for l in [String[], ["one"], ["one", "two"], ["one", "two", "three"],
          ["one", "two", "three", "four"]]
    println("PUNC\t", length(l), "\t[", punctuate_with_commas("and", l), "]\t[",
            punctuate_with_commas("or", l), "]")
end

#------------------------------------------------------------ theme-phrases ---

println("SECTION\tthemephrases")

tp(tag, themes, unjust, snag_just, prep, conj, verb, caveats, the_strings, two) =
    println("TP\t", tag, "\t[",
            theme_phrases(prep, conj, verb, themes, snag_just, unjust,
                          "abc", "pqrs", "the letters do not line up",
                          caveats, the_strings, two, net), "]")

sp_i = (spos, iden)
sp_o = (spos, opp)
sp_d = (spos, nothing)
gc_i = (gtype, iden)
gc_o = (gtype, opp)
gc_d = (gtype, nothing)
ap_i = (apos, iden)
ap_o = (apos, opp)
bf = (facet, iden)

E = Any[]
tp("spos-iden",     Any[sp_i], E, E, "on ", "and", "ing", false, false, nothing)
tp("spos-opp",      Any[sp_o], E, E, "on ", "and", "ing", false, false, nothing)
tp("spos-diff",     Any[sp_d], E, E, "on ", "and", "ing", false, false, nothing)
tp("gctgy-iden",    Any[gc_i], E, E, "on ", "and", "ing", false, false, nothing)
tp("gctgy-opp",     Any[gc_o], E, E, "on ", "and", "ing", false, false, nothing)
tp("gctgy-diff",    Any[gc_d], E, E, "on ", "and", "ing", false, false, nothing)
tp("gctgy+facet",   Any[gc_o, bf], E, E, "on ", "and", "ing", false, false, nothing)
tp("spos+gctgy",    Any[sp_o, gc_o], E, E, "on ", "and", "ing", false, false, nothing)
tp("spos+gctgy+bf", Any[sp_o, gc_o, bf], E, E, "on ", "and", "ing", false, false, nothing)
tp("facet-alone",   Any[bf], E, E, "on ", "and", "ing", false, false, nothing)
tp("apos-iden",     Any[ap_i], E, E, "on ", "and", "ing", false, false, nothing)
tp("apos-opp",      Any[ap_o], E, E, "on ", "and", "ing", false, false, nothing)
tp("all-four",      Any[sp_i, gc_i, bf, ap_o], E, E, "on ", "and", "ing", false, false, nothing)
tp("gctgy-unjust",  Any[sp_o], Any[gc_o], E, "on ", "and", "ing", false, false, nothing)
tp("gctgy-unjust-alone", E, Any[gc_o, bf], E, "on ", "and", "ing", false, false, nothing)
tp("caveat-unjust", Any[sp_o], Any[ap_o], E, "on ", "and", "ing", true, false, nothing)
tp("caveat-snag",   Any[sp_o], E, Any[sp_o], "on ", "and", "ing", true, false, nothing)
tp("caveat-both",   Any[sp_o], Any[ap_o], Any[sp_o], "on ", "and", "ing", true, false, nothing)
tp("to-or",         Any[sp_o, ap_o], E, E, "to ", "or", "", false, true, nothing)
tp("of-and",        Any[ap_i], E, E, "of ", "and", "ing", false, false, nothing)
tp("bare",          Any[sp_i, bf], E, E, "", "and", "ing", false, false, nothing)
tp("two-strings",   Any[gc_i, bf], E, E, "on ", "and", "ing", false, false,
   "(abc and pqrs in both cases)")
tp("the-strings",   Any[bf, ap_i], E, E, "on ", "and", "ing", false, true, nothing)
tp("empty",         E, E, E, "on ", "and", "ing", false, false, nothing)

#------------------------------------------------------- coherence-phrase ---

println("SECTION\tcoherence")

for c in [-100, -51, -50, -11, -10, -1, 0, 9, 10, 50]
    println("COH\t", c, "\t", coherence_phrase(c))
end

#----------------------------------------------------------------- explain ---

println("SECTION\texplain")

r_succ = RuleClause[change_clause(net[:plato_letter], spos, net[:plato_rightmost],
                                  Change(:self, lcat, succ))]
r_pred = RuleClause[change_clause(net[:plato_letter], spos, net[:plato_leftmost],
                                  Change(:self, lcat, pred))]
r_len = RuleClause[change_clause(net[:plato_group], spos, net[:plato_rightmost],
                                 Change(:self, len, succ))]
r_verb = RuleClause[verb_clause("abd")]

e1 = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 80,
            pat(:vertical_bridge, sp_i, (lcat, iden)), pat(:vertical_bridge))
e2 = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 40,
            pat(:vertical_bridge, sp_o, gc_o), pat(:vertical_bridge, ap_o))
e3 = answer("abc", "cba", "pqrs", "srqp", r_pred, 70, 95,
            pat(:vertical_bridge, sp_o, gc_o, bf), pat(:vertical_bridge))

function show_explanation(tag, a)
    (short, long) = explain(a, mem, net)
    println("EXPL\t", tag, "\t", join_or_dash([string("[", l, "]") for l in short]))
    println("EXPLV\t", tag, "\t", join_or_dash([string("[", l, "]") for l in long]))
end

for (tag, a) in [("e1", e1), ("e2", e2), ("e3", e3)]
    show_explanation(tag, a)
end

#-------------------------------------------------- snag-justified commentary ---

println("SECTION\tsnagjustified")

# make-snag-description reads the three strings from the GLOBALS in the Scheme,
# so the Scheme probe has to initialise the workspace first; the port takes them
# from a context, so the probe builds one.
ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                 make_workspace_string(net, :initial, "abc"),
                 make_workspace_string(net, :modified, "abd"),
                 make_workspace_string(net, :target, "ijk"), 100, 0)
s1 = make_snag_description(ctx, r_succ, r_succ, ["snag phrase"],
                           ["translated phrase"], "the k has no successor",
                           pat(:vertical_bridge, sp_o))
add_snag_description!(mem, s1)

println("SNAGEXPL\te2\t[", get_snag_explanation(e2, mem, net), "]")
println("SNAGJUST\te2\t",
        join_or_dash([theme_tag(e) for e in get_snag_justified_themes(e2, mem, net)]))
show_explanation("e2-with-snag", e2)
println("SNAGEXPL\te1\t[", get_snag_explanation(e1, mem, net), "]")

#----------------------------------------------- get-answer-comparison-text ---

println("SECTION\tcompare")

cmp_(tag, a, b) =
    println("CMP\t", tag, "\t[", get_answer_comparison_text(a, b, mem, net), "]")

c_base = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 80,
                pat(:vertical_bridge, sp_i, (lcat, iden)), pat(:vertical_bridge))
c_identical = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 80,
                     pat(:vertical_bridge, sp_i, (lcat, iden)), pat(:vertical_bridge))
c_rule_differs = answer("abc", "abd", "ijk", "ijl", r_len, 70, 80,
                        pat(:vertical_bridge, sp_i, (lcat, iden)), pat(:vertical_bridge))
c_rule_shapeless = answer("abc", "abd", "ijk", "ijl", r_verb, 10, 80,
                          pat(:vertical_bridge, sp_i, (lcat, iden)), pat(:vertical_bridge))
c_theme_differs = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 70,
                         pat(:vertical_bridge, sp_o, (lcat, iden)), pat(:vertical_bridge))
c_extra_theme = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 75,
                       pat(:vertical_bridge, sp_i, (lcat, iden), ap_o),
                       pat(:vertical_bridge))
c_fewer_themes = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 75,
                        pat(:vertical_bridge, sp_i), pat(:vertical_bridge))
c_unjustified = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 60,
                       pat(:vertical_bridge, (lcat, iden)),
                       pat(:vertical_bridge, sp_i))
c_unjustified2 = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 60,
                        pat(:vertical_bridge, sp_i),
                        pat(:vertical_bridge, (lcat, iden)))
c_incoherent = answer("abc", "abd", "ijk", "ijl", r_verb, 5, 55,
                      pat(:vertical_bridge, gc_o, ap_o, bf), pat(:vertical_bridge))
c_incoherent2 = answer("abc", "abd", "ijk", "ijl", r_verb, 5, 50,
                       pat(:vertical_bridge, gc_o, ap_o), pat(:vertical_bridge))
c_other_problem = answer("abc", "cba", "pqrs", "srqp", r_pred, 70, 95,
                         pat(:vertical_bridge, sp_o, gc_o), pat(:vertical_bridge))
c_same_string = answer("abc", "abd", "ijk", "ijl", r_pred, 55, 65,
                       pat(:vertical_bridge, ap_o, bf), pat(:vertical_bridge))
c_just_snag = answer("abc", "abd", "ijk", "ijl", r_succ, 40, 70,
                     pat(:vertical_bridge, sp_i), pat(:vertical_bridge, ap_o))
c_just_none = answer("abc", "abd", "ijk", "ijl", r_pred, 40, 70,
                     pat(:vertical_bridge, sp_i), pat(:vertical_bridge, ap_o))

cmp_("identical",        c_base, c_identical)
cmp_("rule-differs",     c_base, c_rule_differs)
cmp_("rule-shapeless",   c_base, c_rule_shapeless)
cmp_("theme-differs",    c_base, c_theme_differs)
cmp_("extra-theme",      c_base, c_extra_theme)
cmp_("fewer-themes",     c_base, c_fewer_themes)
cmp_("unjustified",      c_base, c_unjustified)
cmp_("unjustified-both", c_unjustified, c_unjustified2)
cmp_("incoherent-one",   c_base, c_incoherent)
cmp_("incoherent-both",  c_incoherent, c_incoherent2)
cmp_("other-problem",    c_base, c_other_problem)
cmp_("same-string",      c_base, c_same_string)
cmp_("reversed",         c_theme_differs, c_base)
cmp_("self",             c_base, c_base)
cmp_("justification",    c_just_snag, c_just_none)
cmp_("justification-rev", c_just_none, c_just_snag)
