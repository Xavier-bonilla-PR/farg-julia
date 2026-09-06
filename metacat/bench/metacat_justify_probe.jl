# Julia counterpart of metacat/bench/metacat_justify_probe.ss: rule unification,
# the two procs that ride the rule-clause traversal, and the theme pattern a
# unification asks to be clamped.
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
include("../julia/src/rules.jl")
include("../julia/src/answers.jl")
include("../julia/src/trace.jl")
include("../julia/src/justify.jl")

net = build_slipnet()
const N = net

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
"""The port spells symbols with underscores; the Scheme uses hyphens."""
hyphen(s::Symbol) = replace(String(s), "_" => "-")

"""Exact rendering of a number, matching the Scheme probe."""
function num(v)
    if is_exact(v)
        x = snorm(v)
        return x isa Integer ? string(x) : string(numerator(x), "/", denominator(x))
    end
    r = Rational{BigInt}(v)
    return string("F", numerator(r), "/", denominator(r))
end

cm_tag(cm) = cm_print_name(cm, net)
entry_tag(e) = string(sn(e[1]), "/", nm(e[2]))

od(ot, dt, d) = ObjectDescription(ot, dt, d)
ch(scope, dim, d) = Change(scope, dim, d)
ich(o, cs) = intrinsic_clause(o, Change[cs...])
ech(os, ds) = extrinsic_clause(ObjectDescription[os...], Node[ds...])
vch(ls) = verbatim_clause(Node[ls...])

# --- the rule pairs ---------------------------------------------------------

function pair_table()
    return Any[
        # identical: unifies, and every pair of nodes is ===, so no slippages
        Any["identical",
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])]],
        # succ => pred: the classic slippage, on a lateral sliplink
        Any["succ-pred",
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_predecessor])])]],
        # rmost => lmost as well, so two slippages come back
        Any["rmost-lmost-succ-pred",
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_leftmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_predecessor])])]],
        # leftmost => rightmost only
        Any["lmost-rmost",
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_leftmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])]],
        # the :string / plato-group special case, both ways round
        Any["string-vs-group",
            RuleClause[ich(od(:string, N[:plato_string_position_category],
                              N[:plato_whole]),
                           [ch(:subobjects, N[:plato_letter_category],
                               N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_whole]),
                           [ch(:subobjects, N[:plato_letter_category],
                               N[:plato_successor])])]],
        Any["group-vs-string",
            RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_whole]),
                           [ch(:subobjects, N[:plato_letter_category],
                               N[:plato_successor])])],
            RuleClause[ich(od(:string, N[:plato_string_position_category],
                              N[:plato_whole]),
                           [ch(:subobjects, N[:plato_letter_category],
                               N[:plato_successor])])]],
        # :string against something that is NOT plato-group: fails
        Any["string-vs-letter",
            RuleClause[ich(od(:string, N[:plato_string_position_category],
                              N[:plato_whole]),
                           [ch(:subobjects, N[:plato_letter_category],
                               N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_whole]),
                           [ch(:subobjects, N[:plato_letter_category],
                               N[:plato_successor])])]],
        # whole => single, the mapping that gets dropped
        Any["whole-single",
            RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_whole]),
                           [ch(:self, N[:plato_direction_category],
                               N[:plato_opposite])])],
            RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_single]),
                           [ch(:self, N[:plato_direction_category],
                               N[:plato_opposite])])]],
        # two whole/single mappings: only the FIRST is removed. NB a
        # group-category change has to be paired with a bond-facet change —
        # make_rule's transcription rejects a bare one.
        Any["whole-single-twice",
            RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_whole]),
                           [ch(:self, N[:plato_direction_category],
                               N[:plato_opposite])]),
                       ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_whole]),
                           [ch(:self, N[:plato_group_category], N[:plato_opposite]),
                            ch(:self, N[:plato_bond_facet],
                               N[:plato_letter_category])])],
            RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_single]),
                           [ch(:self, N[:plato_direction_category],
                               N[:plato_opposite])]),
                       ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_single]),
                           [ch(:self, N[:plato_group_category], N[:plato_opposite]),
                            ch(:self, N[:plato_bond_facet],
                               N[:plato_letter_category])])]],
        # bond-category and group-category entries, for the two heuristics
        Any["bondctgy",
            RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_bond_category], N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                              N[:plato_leftmost]),
                           [ch(:self, N[:plato_bond_category],
                               N[:plato_predecessor])])]],
        # shape mismatch: two changes against one
        Any["shape-changes",
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor]),
                            ch(:self, N[:plato_length], N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])]],
        # shape mismatch: two clauses against one
        Any["shape-clauses",
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])]),
                       ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_leftmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])]],
        # scope symbols differ: :self against :subobjects
        Any["scope-mismatch",
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:subobjects, N[:plato_letter_category],
                               N[:plato_successor])])]],
        # unrelated literal descriptors: no sliplink between a and m
        Any["unrelated-letters",
            RuleClause[ich(od(N[:plato_letter], N[:plato_letter_category],
                              N[:plato_a]),
                           [ch(:self, N[:plato_letter_category], N[:plato_d])])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_letter_category],
                              N[:plato_m]),
                           [ch(:self, N[:plato_letter_category], N[:plato_d])])]],
        # extrinsic (swap) clauses
        Any["extrinsic",
            RuleClause[ech([od(N[:plato_letter], N[:plato_string_position_category],
                               N[:plato_leftmost]),
                            od(N[:plato_letter], N[:plato_string_position_category],
                               N[:plato_rightmost])],
                           [N[:plato_letter_category]])],
            RuleClause[ech([od(N[:plato_letter], N[:plato_string_position_category],
                               N[:plato_rightmost]),
                            od(N[:plato_letter], N[:plato_string_position_category],
                               N[:plato_leftmost])],
                           [N[:plato_letter_category]])]],
        # kind mismatch: intrinsic against extrinsic
        Any["kind-mismatch",
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])],
            RuleClause[ech([od(N[:plato_letter], N[:plato_string_position_category],
                               N[:plato_leftmost]),
                            od(N[:plato_letter], N[:plato_string_position_category],
                               N[:plato_rightmost])],
                           [N[:plato_letter_category]])]],
        # verbatim rules unify with nothing at all
        Any["verbatim-both",
            RuleClause[vch([N[:plato_a], N[:plato_b], N[:plato_d]])],
            RuleClause[vch([N[:plato_a], N[:plato_b], N[:plato_d]])]],
        Any["verbatim-one",
            RuleClause[vch([N[:plato_a], N[:plato_b], N[:plato_d]])],
            RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                              N[:plato_rightmost]),
                           [ch(:self, N[:plato_letter_category], N[:plato_successor])])]],
    ]
end

function dump_pair(tag, rule1::Rule, rule2::Rule)
    println("PAIR\t", tag, "\tverb1=", yn(is_verbatim_rule(rule1)),
            "\tverb2=", yn(is_verbatim_rule(rule2)))
    cmp = compare_rule_clause_lists(rule1.rule_clauses, rule2.rule_clauses, net)
    println("CMP\t", tag, "\t",
            cmp === nothing ? "FAIL" :
            join_or_dash([string(sn(p[1]), ">", sn(p[2])) for p in cmp]))
    pattern = unify_rules(rule1, rule2, net)
    if pattern === nothing
        println("UNIFY\t", tag, "\tFAIL")
        return
    end
    es = entries(pattern)
    println("UNIFY\t", tag, "\t", hyphen(pattern[1]), "\t", length(es))
    for (k, e) in enumerate(es)
        println("UNIFYE\t", tag, "\t", k - 1, "\t", entry_tag(e))
    end
    # get_unifying_slippages is only defined when the rules unify
    slippages = get_unifying_slippages(rule1, rule2, net)
    println("SLIP\t", tag, "\t", join_or_dash([cm_tag(s) for s in slippages]))
    for (k, s) in enumerate(slippages)
        println("SLIPD\t", tag, "\t", k - 1, "\t", sn(cm_type(s)), "\t",
                cm_tag(s), "\t", nm(s.label))
    end
    return
end

# --- the pattern helpers ----------------------------------------------------

function pattern_table()
    return Any[
        Any["spos-iden",
            Any[Any[N[:plato_string_position_category], N[:plato_identity]]]],
        Any["spos-opp",
            Any[Any[N[:plato_string_position_category], N[:plato_opposite]]]],
        Any["spos-diff",
            Any[Any[N[:plato_string_position_category], nothing]]],
        Any["spos-opp-dir-iden",
            Any[Any[N[:plato_string_position_category], N[:plato_opposite]],
                Any[N[:plato_direction_category], N[:plato_identity]]]],
        Any["bondctgy-only",
            Any[Any[N[:plato_bond_category], N[:plato_opposite]]]],
        Any["bondctgy-and-groupctgy",
            Any[Any[N[:plato_bond_category], N[:plato_opposite]],
                Any[N[:plato_group_category], N[:plato_identity]]]],
        Any["lcat-succ",
            Any[Any[N[:plato_letter_category], N[:plato_successor]]]],
        Any["mixed",
            Any[Any[N[:plato_letter_category], N[:plato_successor]],
                Any[N[:plato_string_position_category], N[:plato_opposite]],
                Any[N[:plato_bond_category], N[:plato_opposite]],
                Any[N[:plato_object_category], N[:plato_identity]],
                Any[N[:plato_length], N[:plato_successor]]]],
    ]
end

function dump_pattern_helpers(tag, es)
    for e in es
        println("RETP\t", tag, "\t", entry_tag(e), "\t",
                num(retention_probability(e, net)))
    end
    println("REPBOND\t", tag, "\t",
            join_or_dash([entry_tag(e) for e in replace_bond_category_entry(es, net)]))
    println("ADDDIR\t", tag, "\t",
            join_or_dash([entry_tag(e) for e in add_direction_entry(es, net)]))
    println("BOTH\t", tag, "\t",
            join_or_dash([entry_tag(e) for e in
                          add_direction_entry(replace_bond_category_entry(es, net), net)]))
    return
end

function dump_clamp(tag, es, seed, trials)
    rng = PyRandom(seed)
    for k in 1:trials
        result = get_vertical_theme_pattern_to_clamp(Any[:vertical_bridge, es...],
                                                     rng, net)
        println("CLAMP\t", tag, "\t", seed, "\t", k, "\t", hyphen(result[1]), "\t",
                join_or_dash([entry_tag(e) for e in entries(result)]))
    end
    return
end

# --- probe ------------------------------------------------------------------

function probe(i, m, t)
    println("PROBLEM\t", i, "\t", m, "\t", t)
    reset_slipnet!(net)
    initial, modified, target = init_workspace(net, string(i), string(m), string(t))
    add_string_position_descriptions_to_letters!(net, initial)
    add_string_position_descriptions_to_letters!(net, modified)
    add_string_position_descriptions_to_letters!(net, target)
    update_workspace_values!(WorkspaceString[initial, modified, target])
    for spec in pair_table()
        rule1 = make_rule(:top, spec[2], initial, net)
        rule2 = make_rule(:top, spec[3], initial, net)
        dump_pair(spec[1], rule1, rule2)
    end
    for spec in pattern_table()
        dump_pattern_helpers(spec[1], spec[2])
    end
    for spec in pattern_table()
        for seed in (11, 22, 33)
            dump_clamp(spec[1], spec[2], seed, 6)
        end
    end
    return
end

probe(:abc, :abd, :ijk)
